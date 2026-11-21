import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/screens/load_screen.dart';
import 'package:app_rotas_entregas/services/package_store.dart';

class _SingleZoneUiStore implements PackageStore {
  _SingleZoneUiStore(this.items);

  List<DeliveryPackage> items;
  bool optimized = true;
  int saves = 0;

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
    saves++;
  }
}

DeliveryPackage _package(
  String id,
  int scanNumber, {
  String? zone,
  DeliveryStatus status = DeliveryStatus.pending,
}) =>
    DeliveryPackage(
      id: id,
      scanNumber: scanNumber,
      physicalZone: zone,
      status: status,
      address: AddressData(
        raw: 'Rua Teste, $scanNumber',
        street: 'Rua Teste',
        number: '$scanNumber',
        city: 'São Paulo',
        state: 'SP',
        confidence: 1,
        validation: ValidationStatus.confirmed,
      ),
      scannedAt: DateTime.utc(2026, 11, 20, 10, scanNumber),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'saving one active compartment through the UI persists for car and motorcycle',
    (tester) async {
      for (final vehicle in [VehicleType.car, VehicleType.motorcycle]) {
        final isMotorcycle = vehicle == VehicleType.motorcycle;
        final defaults = isMotorcycle
            ? AppState.motorcyclePhysicalZones
            : AppState.carPhysicalZones;
        final activeZone = isMotorcycle ? 'Baú traseiro' : 'Porta-malas';
        final disabledZone =
            isMotorcycle ? 'Bolsa lateral esquerda' : 'Frente esquerda';
        final deliveredZone =
            isMotorcycle ? 'Bolsa lateral direita' : 'Traseira direita';

        SharedPreferences.setMockInitialValues({
          'load_vehicle_type': vehicle.name,
        });

        final store = _SingleZoneUiStore([
          _package('active', 1, zone: activeZone),
          _package('disabled', 2, zone: disabledZone),
          _package(
            'delivered',
            3,
            zone: deliveredZone,
            status: DeliveryStatus.delivered,
          ),
        ]);
        final state = AppState(store: store);
        await state.init();

        expect(state.vehicleType, vehicle);
        await tester.pumpWidget(MaterialApp(home: LoadScreen(state: state)));
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('Configurar compartimentos'));
        await tester.pumpAndSettle();

        for (final zone in defaults.where((zone) => zone != activeZone)) {
          await tester.tap(find.widgetWithText(CheckboxListTile, zone));
          await tester.pump();
        }

        await tester.tap(find.text('Salvar'));
        await tester.pumpAndSettle();

        expect(state.activePhysicalZones, [activeZone]);
        expect(state.packages[0].physicalZone, activeZone);
        expect(state.packages[1].physicalZone, isNull);
        expect(state.packages[2].status, DeliveryStatus.delivered);
        expect(state.packages[2].physicalZone, deliveredZone);
        expect(store.saves, 1);

        final preferences = await SharedPreferences.getInstance();
        final preferenceKey =
            isMotorcycle ? 'load_zones_motorcycle' : 'load_zones_car';
        expect(preferences.getStringList(preferenceKey), [activeZone]);

        final savesBeforeRestart = store.saves;
        final resumed = AppState(store: store);
        await resumed.init();

        expect(resumed.vehicleType, vehicle);
        expect(resumed.activePhysicalZones, [activeZone]);
        expect(resumed.packages, hasLength(3));
        expect(resumed.packages[0].physicalZone, activeZone);
        expect(resumed.packages[1].physicalZone, isNull);
        expect(resumed.packages[2].status, DeliveryStatus.delivered);
        expect(resumed.packages[2].physicalZone, deliveredZone);
        expect(
          store.saves,
          savesBeforeRestart,
          reason: 'Restart must not rewrite a reconciled $vehicle load.',
        );
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    },
  );
}
