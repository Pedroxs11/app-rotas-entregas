import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/screens/load_screen.dart';
import 'package:app_rotas_entregas/services/package_store.dart';

class _LargeLoadStore implements PackageStore {
  _LargeLoadStore(this.items);

  List<DeliveryPackage> items;
  bool optimized = true;

  @override
  Future<void> clear() async {
    items = [];
    optimized = false;
  }

  @override
  Future<List<DeliveryPackage>> load() async => [...items];

  @override
  Future<bool> loadRouteOptimized() async => optimized;

  @override
  Future<void> save(
    List<DeliveryPackage> value, {
    bool? routeOptimized,
  }) async {
    items = [...value];
    if (routeOptimized != null) optimized = routeOptimized;
  }
}

DeliveryPackage _package(int number) => DeliveryPackage(
      id: 'p$number',
      scanNumber: number,
      address: AddressData(
        raw: 'Rua Teste, $number',
        street: 'Rua Teste',
        number: '$number',
        city: 'São Paulo',
        state: 'SP',
        confidence: 1,
        validation: ValidationStatus.confirmed,
      ),
      scannedAt: DateTime.utc(2026, 11, 20, 10, number % 60),
    );

Future<void> _ensureVisible(
  WidgetTester tester,
  Finder finder,
) async {
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

int _selectedCount(WidgetTester tester) {
  final finder = find.byWidgetPredicate(
    (widget) =>
        widget is Text &&
        (widget.data?.endsWith('pacote(s) selecionado(s)') ?? false),
  );
  expect(finder, findsOneWidget);
  return int.parse(tester.widget<Text>(finder).data!.split(' ').first);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'car and motorcycle drag-select and assign a large 600-package load',
    (tester) async {
      tester.view.physicalSize = const Size(400, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (final vehicle in [VehicleType.car, VehicleType.motorcycle]) {
        SharedPreferences.setMockInitialValues({
          if (vehicle == VehicleType.motorcycle)
            'load_vehicle_type': 'motorcycle',
        });

        final store = _LargeLoadStore(
          List.generate(600, (index) => _package(index + 1)),
        );
        final state = AppState(store: store);
        await state.init();

        await tester.pumpWidget(
          MaterialApp(home: LoadScreen(state: state)),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('Selecionar vários'));
        await tester.pump();
        await _ensureVisible(tester, find.text('Pacote 01'));

        final first = tester.getCenter(find.text('Pacote 01'));
        final viewport = tester.getRect(find.byType(CustomScrollView));
        final gesture = await tester.startGesture(first);
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.text('1 pacote(s) selecionado(s)'), findsOneWidget);

        final edge = Offset(first.dx, viewport.bottom - 30);
        await gesture.moveTo(
          edge,
          timeStamp: const Duration(milliseconds: 700),
        );
        await tester.pump();

        // Exercise lazy row mounting and auto-scroll over a genuinely large
        // load, not just the small sample used by the basic gesture test.
        for (var frame = 0; frame < 375; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
        }

        await gesture.up();
        await tester.pumpAndSettle();

        final selected = _selectedCount(tester);
        expect(
          selected,
          greaterThan(40),
          reason: 'Drag selection should cross many lazy rows in $vehicle mode.',
        );
        expect(tester.takeException(), isNull);

        final scrollable = find.descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(Scrollable),
        ).first;
        tester.state<ScrollableState>(scrollable).position.jumpTo(0);
        await tester.pumpAndSettle();

        final targetZone = vehicle == VehicleType.car
            ? 'FRENTE E'
            : 'BAÚ TRASEIRO';
        await tester.tap(find.text(targetZone));
        await tester.pumpAndSettle();

        expect(
          state.packages.where((p) => p.physicalZone != null),
          hasLength(selected),
          reason: 'Only the dragged packages should be assigned in $vehicle mode.',
        );
        expect(
          state.packages.where((p) => p.physicalZone == null),
          hasLength(600 - selected),
        );
        expect(
          state.packages.where((p) => p.physicalZone == targetZone ||
              (vehicle == VehicleType.car &&
                  p.physicalZone == 'Frente esquerda')),
          hasLength(selected),
        );
        expect(store.items.map((p) => p.id).toSet(), hasLength(600));
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    },
  );
}
