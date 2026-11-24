import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/screens/load_screen.dart';
import 'package:app_rotas_entregas/services/package_store.dart';

class _CompactLoadStore implements PackageStore {
  _CompactLoadStore(this.items);

  List<DeliveryPackage> items;

  @override
  Future<void> clear() async {
    items = [];
  }

  @override
  Future<List<DeliveryPackage>> load() async => [...items];

  @override
  Future<bool> loadRouteOptimized() async => true;

  @override
  Future<void> save(
    List<DeliveryPackage> value, {
    bool? routeOptimized,
  }) async {
    items = [...value];
  }
}

DeliveryPackage _package(int number) => DeliveryPackage(
      id: 'compact-$number',
      scanNumber: number,
      address: AddressData(
        raw: 'Rua Compacta, $number',
        street: 'Rua Compacta',
        number: '$number',
        city: 'São Paulo',
        state: 'SP',
        confidence: 1,
        validation: ValidationStatus.confirmed,
      ),
      scannedAt: DateTime.utc(2026, 11, 22, 10, number),
    );

Future<void> _ensureLoadItemVisible(
  WidgetTester tester,
  Finder finder,
) async {
  final scrollable = find.descendant(
    of: find.byType(CustomScrollView),
    matching: find.byType(Scrollable),
  ).first;
  final position = tester.state<ScrollableState>(scrollable).position;
  final viewportFinder = find.byType(CustomScrollView);

  // The compartment diagram is near the start of the scroll view. A previous
  // ensure-visible call may have moved to the package list, so return to the
  // start before searching for a chip that is no longer in the sliver cache.
  if (finder.evaluate().isEmpty &&
      position.pixels > position.minScrollExtent) {
    position.jumpTo(position.minScrollExtent);
    await tester.pumpAndSettle();
  }

  for (var attempt = 0; attempt < 120; attempt++) {
    if (finder.evaluate().isNotEmpty) {
      final target = tester.getRect(finder.first);
      final viewport = tester.getRect(viewportFinder);
      if (target.top >= viewport.top && target.bottom <= viewport.bottom) {
        return;
      }
      final delta = target.top < viewport.top
          ? target.top - viewport.top
          : target.bottom - viewport.bottom;
      final next = (position.pixels + delta)
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      if ((next - position.pixels).abs() < 0.5) break;
      position.jumpTo(next);
    } else {
      // SliverList builds rows lazily. Scroll in small increments until the
      // package enters the cache extent before trying to inspect or tap it.
      final next = (position.pixels + 100)
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      if (next <= position.pixels) break;
      position.jumpTo(next);
    }
    await tester.pumpAndSettle();
  }

  expect(finder, findsWidgets);
  final target = tester.getRect(finder.first);
  final viewport = tester.getRect(viewportFinder);
  expect(target.top, greaterThanOrEqualTo(viewport.top));
  expect(target.bottom, lessThanOrEqualTo(viewport.bottom));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'car and motorcycle organizers remain usable on compact phone viewports',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Cover a short 5-inch class viewport as well as common compact Android
      // sizes. The fixed bottom action must not prevent the organizer from
      // scrolling to packages, compartments, and bulk-removal controls.
      const compactSizes = <Size>[
        Size(320, 568),
        Size(360, 640),
        Size(320, 700),
      ];

      for (final screenSize in compactSizes) {
        tester.view.physicalSize = screenSize;
        for (final vehicle in VehicleType.values) {
          SharedPreferences.setMockInitialValues({
            'load_vehicle_type': vehicle.name,
          });

          final store = _CompactLoadStore([
            _package(1),
            _package(2),
            _package(3),
          ]);
          final state = AppState(store: store);
          await state.init();

          await tester.pumpWidget(
            MaterialApp(home: LoadScreen(state: state)),
          );
          await tester.pumpAndSettle();

          if (vehicle == VehicleType.car) {
            expect(find.text('FRENTE E'), findsOneWidget);
            expect(find.text('FRENTE D'), findsOneWidget);
            expect(find.text('TRASEIRA E'), findsOneWidget);
            expect(find.text('TRASEIRA D'), findsOneWidget);
            expect(find.text('PORTA-MALAS'), findsOneWidget);
          } else {
            expect(find.text('MODO MOTO'), findsOneWidget);
            expect(find.text('BOLSA ESQUERDA'), findsOneWidget);
            expect(find.text('BOLSA DIREITA'), findsOneWidget);
            expect(find.text('BAÚ TRASEIRO'), findsOneWidget);
            expect(find.text('MOCHILA DE ENTREGA'), findsOneWidget);
            final leftBag = find.ancestor(
              of: find.text('BOLSA ESQUERDA'),
              matching: find.byType(InkWell),
            ).first;
            final rightBag = find.ancestor(
              of: find.text('BOLSA DIREITA'),
              matching: find.byType(InkWell),
            ).first;
            final leftBagRect = tester.getRect(leftBag);
            final rightBagRect = tester.getRect(rightBag);
            expect(leftBagRect.width, greaterThan(100));
            expect(rightBagRect.width, greaterThan(100));
            expect(
              (leftBagRect.top - rightBagRect.top).abs(),
              lessThan(1),
            );
          }
          expect(tester.takeException(), isNull);

          final packageRow = find.text('Pacote 01');
          await _ensureLoadItemVisible(tester, packageRow);
          await tester.pumpAndSettle();
          await tester.tap(packageRow);
          await tester.pump();

          final targetZone = find.text(
            vehicle == VehicleType.car ? 'FRENTE E' : 'BAÚ TRASEIRO',
          );
          await _ensureLoadItemVisible(tester, targetZone);
          await tester.pumpAndSettle();
          await tester.tap(targetZone);
          await tester.pumpAndSettle();

          expect(
            state.packages.first.physicalZone,
            vehicle == VehicleType.car ? 'Frente esquerda' : 'Baú traseiro',
          );
          expect(find.text('P01'), findsOneWidget);

          // On compact phones, assigned chips and the removal action must
          // remain reachable without relying on a large viewport.
          await tester.tap(find.byTooltip('Selecionar vários'));
          await tester.pumpAndSettle();
          final assignedChip = find.widgetWithText(InputChip, 'P01');
          await _ensureLoadItemVisible(tester, assignedChip);
          await tester.tap(assignedChip);
          await tester.pumpAndSettle();
          expect(find.text('1 pacote(s) selecionado(s)'), findsOneWidget);

          final removeButton = find.text('RETIRAR PACOTE SELECIONADO');
          await _ensureLoadItemVisible(tester, removeButton);
          await tester.tap(removeButton);
          await tester.pumpAndSettle();

          expect(state.packages.first.physicalZone, isNull);
          expect(store.items.first.physicalZone, isNull);
          expect(find.text('0 pacote(s) selecionado(s)'), findsOneWidget);
          expect(tester.takeException(), isNull);

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        }
      }
    },
  );
  testWidgets(
    'car and motorcycle organizers support enlarged text on compact phones',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (final vehicle in VehicleType.values) {
        SharedPreferences.setMockInitialValues({
          'load_vehicle_type': vehicle.name,
        });
        final state = AppState(
          store: _CompactLoadStore([_package(1), _package(2)]),
        );
        await state.init();

        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(1.3),
              ),
              child: child!,
            ),
            home: LoadScreen(state: state),
          ),
        );
        await tester.pumpAndSettle();

        final expectedZone = vehicle == VehicleType.car
            ? 'FRENTE E'
            : 'BAÚ TRASEIRO';
        expect(find.text(expectedZone), findsOneWidget);
        expect(find.text('Pacotes sem posição'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // The compartment settings dialog must remain usable with enlarged
        // system text instead of clipping its title, choices, or actions.
        await tester.tap(find.byTooltip('Configurar compartimentos'));
        await tester.pumpAndSettle();
        expect(
          find.text(
            vehicle == VehicleType.car
                ? 'Compartimentos do carro'
                : 'Compartimentos da moto',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);

        // Reach the last option inside the scrollable dialog, disable it, and
        // save with enlarged text on the smallest supported phone viewport.
        final lastZone = vehicle == VehicleType.car
            ? 'Porta-malas'
            : 'Mochila de entrega';
        final lastZoneTile =
            find.widgetWithText(CheckboxListTile, lastZone);
        await tester.ensureVisible(lastZoneTile);
        await tester.pumpAndSettle();
        await tester.tap(lastZoneTile);
        await tester.pumpAndSettle();

        final saveZonesButton = find.text('Salvar');
        await tester.ensureVisible(saveZonesButton);
        await tester.tap(saveZonesButton);
        await tester.pumpAndSettle();

        expect(state.activePhysicalZones, isNot(contains(lastZone)));
        expect(tester.takeException(), isNull);

        await _ensureLoadItemVisible(tester, find.text('Pacote 01'));
        await tester.tap(find.text('Pacote 01'));
        await tester.pump();

        await _ensureLoadItemVisible(tester, find.text(expectedZone));
        await tester.tap(find.text(expectedZone));
        await tester.pumpAndSettle();

        expect(
          state.packages.first.physicalZone,
          vehicle == VehicleType.car ? 'Frente esquerda' : 'Baú traseiro',
        );
        expect(find.text('P01'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    },
  );

}
