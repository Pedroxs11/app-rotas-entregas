import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/screens/load_screen.dart';
import 'package:app_rotas_entregas/services/package_store.dart';

class _CarCompartmentStore implements PackageStore {
  _CarCompartmentStore(this.items);

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
      id: 'car-compartment-$number',
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
      scannedAt: DateTime.utc(2026, 11, 26).add(Duration(minutes: number)),
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
    '600-package car load keeps all four seat positions and pagination usable on a compact phone with enlarged text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({
        'load_vehicle_type': VehicleType.car.name,
      });
      final packages = List.generate(600, (index) => _package(index + 1));
      final store = _CarCompartmentStore(packages);
      final state = AppState(store: store);
      await state.init();

      const zones = [
        'Frente esquerda',
        'Frente direita',
        'Traseira esquerda',
        'Traseira direita',
      ];
      await state.setActivePhysicalZones(zones);
      for (var index = 0; index < zones.length; index++) {
        final first = index * 150;
        final ids = packages
            .skip(first)
            .take(150)
            .map((package) => package.id)
            .toSet();
        await state.setPhysicalZones(ids, zones[index]);
      }

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(320, 568),
              textScaler: TextScaler.linear(1.3),
            ),
            child: LoadScreen(state: state),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final viewport = tester.getRect(find.byType(CustomScrollView));
      const labels = {
        'Frente esquerda': 'FRENTE E',
        'Frente direita': 'FRENTE D',
        'Traseira esquerda': 'TRASEIRA E',
        'Traseira direita': 'TRASEIRA D',
      };

      for (final entry in labels.entries) {
        final compartment = find.ancestor(
          of: find.text(entry.value),
          matching: find.byType(AnimatedContainer),
        ).first;
        final rect = tester.getRect(compartment);
        expect(
          rect.width,
          greaterThan(100),
          reason: '${entry.value} must keep a usable touch width.',
        );
        if (entry.key.endsWith('esquerda')) {
          expect(
            rect.center.dx,
            lessThan(viewport.center.dx),
            reason: '${entry.value} must remain on the physical left.',
          );
        } else {
          expect(
            rect.center.dx,
            greaterThan(viewport.center.dx),
            reason: '${entry.value} must remain on the physical right.',
          );
        }
      }

      expect(find.text('PORTA-MALAS'), findsNothing);
      expect(find.byType(InputChip), findsNWidgets(32));

      for (var index = 0; index < zones.length; index++) {
        final compartment = find.ancestor(
          of: find.text(labels[zones[index]]!),
          matching: find.byType(AnimatedContainer),
        ).first;
        final more = find.descendant(
          of: compartment,
          matching: find.text('Ver mais 24'),
        );
        await _ensureVisible(tester, more);
        await tester.tap(more);
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: compartment,
            matching: find.byType(InputChip),
          ),
          findsNWidgets(32),
        );

        final collapse = find.descendant(
          of: compartment,
          matching: find.text('Mostrar menos'),
        );
        await _ensureVisible(tester, collapse);
        await tester.tap(collapse);
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: compartment,
            matching: find.byType(InputChip),
          ),
          findsNWidgets(8),
        );
      }

      await _ensureVisible(tester, find.byType(TextField));
      await tester.enterText(find.byType(TextField), '600');
      await tester.pumpAndSettle();

      final rearRight = find.ancestor(
        of: find.text('TRASEIRA D'),
        matching: find.byType(AnimatedContainer),
      ).first;
      expect(
        find.descendant(of: rearRight, matching: find.byType(InputChip)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: rearRight, matching: find.text('P600')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: rearRight, matching: find.text('1/150')),
        findsOneWidget,
      );

      final clearSearch = find.byTooltip('Limpar busca');
      await _ensureVisible(tester, clearSearch);
      await tester.tap(clearSearch);
      await tester.pumpAndSettle();

      for (final label in labels.values) {
        final compartment = find.ancestor(
          of: find.text(label),
          matching: find.byType(AnimatedContainer),
        ).first;
        expect(
          find.descendant(
            of: compartment,
            matching: find.byType(InputChip),
          ),
          findsNWidgets(8),
        );
      }
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      state.dispose();
    },
  );
}
