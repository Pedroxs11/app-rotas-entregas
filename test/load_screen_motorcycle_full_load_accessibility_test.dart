import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/screens/load_screen.dart';
import 'package:app_rotas_entregas/services/package_store.dart';

class _MotorcycleFullLoadStore implements PackageStore {
  _MotorcycleFullLoadStore(this.items);

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

const _motorcycleZones = [
  'Baú traseiro',
  'Bolsa lateral esquerda',
  'Bolsa lateral direita',
  'Mochila de entrega',
];

const _motorcycleLabels = {
  'Baú traseiro': 'BAÚ TRASEIRO',
  'Bolsa lateral esquerda': 'BOLSA ESQUERDA',
  'Bolsa lateral direita': 'BOLSA DIREITA',
  'Mochila de entrega': 'MOCHILA DE ENTREGA',
};

DeliveryPackage _package(int number, String zone) => DeliveryPackage(
      id: 'motorcycle-full-load-$number',
      scanNumber: number,
      physicalZone: zone,
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
    '600-package motorcycle load preserves all four compartments and side-bag alignment on a compact phone with enlarged text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({
        'load_vehicle_type': VehicleType.motorcycle.name,
      });

      final packages = List.generate(600, (index) {
        final zoneIndex = index ~/ 150;
        return _package(index + 1, _motorcycleZones[zoneIndex]);
      });
      final store = _MotorcycleFullLoadStore(packages);
      final state = AppState(store: store);
      await state.init();

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
      for (final entry in _motorcycleLabels.entries) {
        final compartment = find.ancestor(
          of: find.text(entry.value),
          matching: find.byType(AnimatedContainer),
        ).first;
        final rect = tester.getRect(compartment);
        expect(
          rect.width,
          greaterThan(100),
          reason: entry.value + ' must keep a usable touch width.',',
        );

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

      for (final side in [
        (
          label: 'BOLSA ESQUERDA',
          isRight: false,
        ),
        (
          label: 'BOLSA DIREITA',
          isRight: true,
        ),
      ]) {
        final sideTapTarget = find.ancestor(
          of: find.text(side.label),
          matching: find.byType(InkWell),
        ).first;
        final rect = tester.getRect(sideTapTarget);
        if (side.isRight) {
          expect(
            rect.center.dx,
            greaterThan(viewport.center.dx),
            reason: 'The right side bag must stay on the physical right.',
          );
        } else {
          expect(
            rect.center.dx,
            lessThan(viewport.center.dx),
            reason: 'The left side bag must stay on the physical left.',
          );
        }
      }

      await _ensureVisible(tester, find.byType(TextField));
      await tester.enterText(find.byType(TextField), '600');
      await tester.pumpAndSettle();

      final backpack = find.ancestor(
        of: find.text('MOCHILA DE ENTREGA'),
        matching: find.byType(AnimatedContainer),
      ).first;
      expect(
        find.descendant(of: backpack, matching: find.byType(InputChip)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: backpack, matching: find.text('P600')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: backpack, matching: find.text('1/150')),
        findsOneWidget,
      );

      final clearSearch = find.byTooltip('Limpar busca');
      await _ensureVisible(tester, clearSearch);
      await tester.tap(clearSearch);
      await tester.pumpAndSettle();

      for (final label in _motorcycleLabels.values) {
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
      expect(find.byType(InputChip), findsNWidgets(32));
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      state.dispose();
    },
  );
}
