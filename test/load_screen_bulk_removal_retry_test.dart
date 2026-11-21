import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/screens/load_screen.dart';
import 'package:app_rotas_entregas/services/package_store.dart';

class _FailOncePackageStore implements PackageStore {
  _FailOncePackageStore(this.items);

  List<DeliveryPackage> items;
  bool failNextSave = true;
  int saveAttempts = 0;
  int successfulSaves = 0;

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
    saveAttempts++;
    if (failNextSave) {
      failNextSave = false;
      throw StateError('Falha simulada ao retirar pacotes');
    }
    items = [...value];
    successfulSaves++;
  }
}

DeliveryPackage _package(
  VehicleType vehicle,
  int number,
  String zone, {
  DeliveryStatus status = DeliveryStatus.pending,
}) =>
    DeliveryPackage(
      id: '${vehicle.name}-$number',
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
      scannedAt: DateTime.utc(2026, 11, 21, 12),
      physicalZone: zone,
      status: status,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'failed bulk removal keeps selection and can be retried for car and motorcycle',
    (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (final vehicle in [VehicleType.car, VehicleType.motorcycle]) {
        SharedPreferences.setMockInitialValues({
          'load_vehicle_type': vehicle.name,
        });

        final targetZone = vehicle == VehicleType.car
            ? 'Porta-malas'
            : 'Baú traseiro';
        final store = _FailOncePackageStore([
          _package(vehicle, 1, targetZone),
          _package(vehicle, 2, targetZone),
          _package(
            vehicle,
            3,
            targetZone,
            status: DeliveryStatus.delivered,
          ),
        ]);
        final state = AppState(store: store);
        await state.init();

        expect(state.routeOptimized, isTrue);
        expect(state.vehicleType, vehicle);
        expect(state.packages, hasLength(3));

        await tester.pumpWidget(MaterialApp(home: LoadScreen(state: state)));
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('Selecionar vários'));
        await tester.pumpAndSettle();

        // Select the two active packages through the screen's bulk action.
        // The delivered package is intentionally excluded from the active route.
        final selectListButton = find.text('Selecionar lista');
        await tester.ensureVisible(selectListButton);
        await tester.pumpAndSettle();
        await tester.tap(selectListButton);
        await tester.pumpAndSettle();

        expect(find.text('2 pacote(s) selecionado(s)'), findsOneWidget);
        final removeButton = find.text('RETIRAR 2 PACOTES');
        await tester.ensureVisible(removeButton);
        await tester.tap(removeButton);
        await tester.pumpAndSettle();

        // A failed clear must roll back the model and keep the selection
        // available so the driver does not have to mark the packages again.
        expect(store.saveAttempts, 1);
        expect(store.successfulSaves, 0);
        expect(
          state.packages
              .where((package) => package.status != DeliveryStatus.delivered)
              .every((package) => package.physicalZone == targetZone),
          isTrue,
        );
        expect(
          store.items
              .where((package) => package.status != DeliveryStatus.delivered)
              .every((package) => package.physicalZone == targetZone),
          isTrue,
        );
        expect(find.text('2 pacote(s) selecionado(s)'), findsOneWidget);
        expect(
          find.textContaining('Falha simulada ao retirar pacotes'),
          findsOneWidget,
        );
        expect(
          state.packages.singleWhere(
            (package) => package.status == DeliveryStatus.delivered,
          ).physicalZone,
          targetZone,
        );

        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();

        await tester.ensureVisible(removeButton);
        await tester.tap(removeButton);
        await tester.pumpAndSettle();

        expect(store.saveAttempts, 2);
        expect(store.successfulSaves, 1);
        expect(
          state.packages
              .where((package) => package.status != DeliveryStatus.delivered)
              .every((package) => package.physicalZone == null),
          isTrue,
        );
        expect(
          store.items
              .where((package) => package.status != DeliveryStatus.delivered)
              .every((package) => package.physicalZone == null),
          isTrue,
        );
        expect(
          state.packages.singleWhere(
            (package) => package.status == DeliveryStatus.delivered,
          ).physicalZone,
          targetZone,
        );
        expect(find.text('0 pacote(s) selecionado(s)'), findsOneWidget);
        expect(find.textContaining('RETIRAR'), findsNothing);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    },
  );
}
