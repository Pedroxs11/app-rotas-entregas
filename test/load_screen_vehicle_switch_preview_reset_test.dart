import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/screens/load_screen.dart';
import 'package:app_rotas_entregas/services/package_store.dart';

class _VehiclePreviewStore implements PackageStore {
  _VehiclePreviewStore(this.items);

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

DeliveryPackage _package(int number, {String? zone}) => DeliveryPackage(
      id: 'vehicle-preview-$number',
      scanNumber: number,
      physicalZone: zone,
      address: AddressData(
        raw: 'Rua da Troca, $number',
        street: 'Rua da Troca',
        number: '$number',
        city: 'São Paulo',
        state: 'SP',
        confidence: 1,
        validation: ValidationStatus.confirmed,
      ),
      scannedAt: DateTime.utc(2026, 11, 27).add(Duration(minutes: number)),
    );

Future<void> _ensureVisible(WidgetTester tester, Finder finder) async {
  final scrollable = find.descendant(
    of: find.byType(CustomScrollView),
    matching: find.byType(Scrollable),
  ).first;
  final position = tester.state<ScrollableState>(scrollable).position;
  final viewport = find.byType(CustomScrollView);

  for (var attempt = 0; attempt < 120; attempt++) {
    if (finder.evaluate().isNotEmpty) {
      final target = tester.getRect(finder.first);
      final visible = tester.getRect(viewport);
      if (target.top >= visible.top && target.bottom <= visible.bottom) {
        return;
      }
      final delta = target.top < visible.top
          ? target.top - visible.top
          : target.bottom - visible.bottom;
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
  final visible = tester.getRect(viewport);
  expect(target.top, greaterThanOrEqualTo(visible.top));
  expect(target.bottom, lessThanOrEqualTo(visible.bottom));
}

Future<void> _expandZone(WidgetTester tester) async {
  final more = find.text('Ver mais 24');
  await _ensureVisible(tester, more);
  await tester.tap(more);
  await tester.pumpAndSettle();
  expect(find.byType(InputChip), findsNWidgets(32));
  expect(find.text('P32'), findsOneWidget);
}

Future<void> _searchLastPackage(WidgetTester tester) async {
  await _ensureVisible(tester, find.byType(TextField));
  await tester.enterText(find.byType(TextField), '40');
  await tester.pumpAndSettle();
  expect(find.byType(InputChip), findsOneWidget);
  expect(find.text('P40'), findsOneWidget);
}

Future<void> _switchVehicle(
  WidgetTester tester,
  VehicleType vehicle,
) async {
  await tester.tap(find.byTooltip('Veículo'));
  await tester.pumpAndSettle();
  await tester.tap(
    find.text(vehicle == VehicleType.car ? '🚗 Carro' : '🏍️ Moto'),
  );
  await tester.pumpAndSettle();
}

Future<void> _assignAll(
  WidgetTester tester,
  String zoneLabel,
) async {
  final selectAll = find.text('Selecionar lista');
  await _ensureVisible(tester, selectAll);
  await tester.tap(selectAll);
  await tester.pumpAndSettle();
  expect(find.text('40 pacote(s) selecionado(s)'), findsOneWidget);

  final target = find.text(zoneLabel);
  await _ensureVisible(tester, target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'vehicle switches clear search and reset compartment previews in both directions',
    (tester) async {
      tester.view.physicalSize = const Size(360, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({
        'load_vehicle_type': VehicleType.car.name,
      });
      final store = _VehiclePreviewStore(
        List.generate(
          40,
          (index) => _package(
            index + 1,
            zone: 'Porta-malas',
          ),
        ),
      );
      final state = AppState(store: store);
      await state.init();

      await tester.pumpWidget(MaterialApp(home: LoadScreen(state: state)));
      await tester.pumpAndSettle();

      // Expand and filter the car compartment. The search and preview state
      // must not leak into the motorcycle layout.
      await _expandZone(tester);
      await _searchLastPackage(tester);
      expect(find.text('1/40'), findsOneWidget);

      await _switchVehicle(tester, VehicleType.motorcycle);
      expect(state.vehicleType, VehicleType.motorcycle);
      expect(state.packages.every((package) => package.physicalZone == null), isTrue);
      expect(tester.widget<TextField>(find.byType(TextField)).controller?.text, '');
      expect(find.text('1/40'), findsNothing);

      await _assignAll(tester, 'BAÚ TRASEIRO');
      expect(
        state.packages.every((package) => package.physicalZone == 'Baú traseiro'),
        isTrue,
      );
      expect(find.byType(InputChip), findsNWidgets(8));
      expect(find.text('P08'), findsOneWidget);
      expect(find.text('P09'), findsNothing);
      expect(find.text('Ver mais 24'), findsOneWidget);

      // Repeat the same scenario in reverse to ensure motorcycle pagination
      // does not leak into the car's trunk preview.
      await _expandZone(tester);
      await _searchLastPackage(tester);
      expect(find.text('1/40'), findsOneWidget);

      await _switchVehicle(tester, VehicleType.car);
      expect(state.vehicleType, VehicleType.car);
      expect(state.packages.every((package) => package.physicalZone == null), isTrue);
      expect(tester.widget<TextField>(find.byType(TextField)).controller?.text, '');
      expect(find.text('1/40'), findsNothing);

      await _assignAll(tester, 'PORTA-MALAS');
      expect(
        state.packages.every((package) => package.physicalZone == 'Porta-malas'),
        isTrue,
      );
      expect(find.byType(InputChip), findsNWidgets(8));
      expect(find.text('P08'), findsOneWidget);
      expect(find.text('P09'), findsNothing);
      expect(find.text('Ver mais 24'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      state.dispose();
    },
  );
}
