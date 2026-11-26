import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/screens/load_screen.dart';
import 'package:app_rotas_entregas/services/package_store.dart';

class _MotorcycleSideBagStore implements PackageStore {
  _MotorcycleSideBagStore(this.items);

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
      id: 'motorcycle-side-bag-$number',
      scanNumber: number,
      address: AddressData(
        raw: 'Rua da Entrega, $number',
        street: 'Rua da Entrega',
        number: '$number',
        city: 'São Paulo',
        state: 'SP',
        confidence: 1,
        validation: ValidationStatus.confirmed,
      ),
      scannedAt: DateTime.utc(2026, 11, 24).add(Duration(minutes: number)),
    );

Future<void> _ensureVisible(WidgetTester tester, Finder finder) async {
  final scrollable = find.descendant(
    of: find.byType(CustomScrollView),
    matching: find.byType(Scrollable),
  ).first;
  final position = tester.state<ScrollableState>(scrollable).position;
  final viewportFinder = find.byType(CustomScrollView);

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
      final next = (position.pixels + 80)
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

  testWidgets(
    '600-package motorcycle side bags keep their physical side and pagination usable on a compact phone',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (final zone in [
        'Bolsa lateral esquerda',
        'Bolsa lateral direita',
      ]) {
        SharedPreferences.setMockInitialValues({
          'load_vehicle_type': VehicleType.motorcycle.name,
        });

        final store = _MotorcycleSideBagStore(
          List.generate(600, (index) => _package(index + 1)),
        );
        final state = AppState(store: store);
        await state.init();
        await state.setActivePhysicalZones([zone]);
        await state.setPhysicalZones(
          state.packages.map((package) => package.id).toSet(),
          zone,
        );

        await tester.pumpWidget(
          MaterialApp(home: LoadScreen(state: state)),
        );
        await tester.pumpAndSettle();

        final label = zone == 'Bolsa lateral esquerda'
            ? 'BOLSA ESQUERDA'
            : 'BOLSA DIREITA';
        final disabledLabel = zone == 'Bolsa lateral esquerda'
            ? 'BOLSA DIREITA'
            : 'BOLSA ESQUERDA';
        final bag = find.ancestor(
          of: find.text(label),
          matching: find.byType(InkWell),
        ).first;
        final compartment = find.ancestor(
          of: find.text(label),
          matching: find.byType(AnimatedContainer),
        ).first;
        final viewport = tester.getRect(find.byType(CustomScrollView));
        final bagRect = tester.getRect(bag);

        expect(find.text(disabledLabel), findsNothing);
        expect(
          bagRect.width,
          greaterThan(100),
          reason: 'The enabled side bag must keep a usable touch width.',
        );
        if (zone == 'Bolsa lateral esquerda') {
          expect(
            bagRect.center.dx,
            lessThan(viewport.center.dx),
            reason: 'The left bag must remain on the physical left side.',
          );
        } else {
          expect(
            bagRect.center.dx,
            greaterThan(viewport.center.dx),
            reason: 'The right bag must remain on the physical right side.',
          );
        }

        expect(find.byType(InputChip), findsNWidgets(8));
        expect(find.text('P08'), findsOneWidget);
        expect(find.text('P09'), findsNothing);

        final more = find.descendant(
          of: compartment,
          matching: find.text('Ver mais 24'),
        );
        await _ensureVisible(tester, more);
        await tester.tap(more);
        await tester.pumpAndSettle();

        expect(
          find.descendant(of: compartment, matching: find.byType(InputChip)),
          findsNWidgets(32),
        );
        expect(find.text('P32'), findsOneWidget);
        expect(find.text('P33'), findsNothing);

        await _ensureVisible(tester, find.byType(TextField));
        await tester.enterText(find.byType(TextField), '600');
        await tester.pumpAndSettle();

        expect(
          find.descendant(of: compartment, matching: find.byType(InputChip)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: compartment, matching: find.text('P600')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: compartment, matching: find.text('1/600')),
          findsOneWidget,
        );

        final clearSearch = find.byTooltip('Limpar busca');
        await _ensureVisible(tester, clearSearch);
        await tester.tap(clearSearch);
        await tester.pumpAndSettle();

        expect(
          find.descendant(of: compartment, matching: find.byType(InputChip)),
          findsNWidgets(32),
        );
        expect(find.text('P32'), findsOneWidget);

        final collapse = find.descendant(
          of: compartment,
          matching: find.text('Mostrar menos'),
        );
        await _ensureVisible(tester, collapse);
        await tester.tap(collapse);
        await tester.pumpAndSettle();

        expect(
          find.descendant(of: compartment, matching: find.byType(InputChip)),
          findsNWidgets(8),
        );
        expect(find.text('P08'), findsOneWidget);
        expect(find.text('P09'), findsNothing);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        state.dispose();
      }
    },
  );
}
