import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/screens/load_screen.dart';
import 'package:app_rotas_entregas/services/package_store.dart';

class _RetryingLoadStore implements PackageStore {
  _RetryingLoadStore(this.items);

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
      throw StateError('Falha simulada de gravação');
    }
    items = [...value];
    successfulSaves++;
  }
}

DeliveryPackage _package(VehicleType vehicle, int number) => DeliveryPackage(
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
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'failed 600-package assignment keeps selection and can be retried for car and motorcycle',
    (tester) async {
      for (final vehicle in [VehicleType.car, VehicleType.motorcycle]) {
        SharedPreferences.setMockInitialValues({
          'load_vehicle_type': vehicle.name,
        });

        final targetZone = vehicle == VehicleType.car
            ? 'Porta-malas'
            : 'Baú traseiro';
        final targetLabel = vehicle == VehicleType.car
            ? 'PORTA-MALAS'
            : 'BAÚ TRASEIRO';
        final store = _RetryingLoadStore(
          List.generate(600, (index) => _package(vehicle, index + 1)),
        );
        final state = AppState(store: store);
        await state.init();

        expect(state.packages, hasLength(600));
        expect(state.routeOptimized, isTrue);
        expect(state.vehicleType, vehicle);

        await tester.pumpWidget(MaterialApp(home: LoadScreen(state: state)));
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('Selecionar vários'));
        await tester.pumpAndSettle();

        final selectListButton = find.text('Selecionar lista');
        await tester.ensureVisible(selectListButton);
        await tester.pumpAndSettle();
        await tester.tap(selectListButton);
        await tester.pumpAndSettle();

        expect(find.text('600 pacote(s) selecionado(s)'), findsOneWidget);

        final targetCompartment = find.text(targetLabel);
        await tester.ensureVisible(targetCompartment);
        await tester.pumpAndSettle();
        await tester.tap(targetCompartment);
        await tester.pumpAndSettle();

        expect(store.saveAttempts, 1);
        expect(store.successfulSaves, 0);
        expect(state.packages, hasLength(600));
        expect(
          state.packages.every((package) => package.physicalZone == null),
          isTrue,
          reason: 'A failed save must roll back every package in $vehicle mode.',
        );
        expect(
          store.items.every((package) => package.physicalZone == null),
          isTrue,
        );
        expect(find.text('600 pacote(s) selecionado(s)'), findsOneWidget);
        expect(find.textContaining('Falha simulada de gravação'), findsOneWidget);

        // Let the error snackbar leave the target area before retrying.
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();

        await tester.ensureVisible(targetCompartment);
        await tester.pumpAndSettle();
        await tester.tap(targetCompartment);
        await tester.pumpAndSettle();

        expect(state.packages, hasLength(600));
        expect(
          state.packages.every((package) => package.physicalZone == targetZone),
          isTrue,
        );
        expect(
          state.packages.map((package) => package.id).toSet(),
          hasLength(600),
        );
        expect(store.items, hasLength(600));
        expect(
          store.items.every((package) => package.physicalZone == targetZone),
          isTrue,
        );
        expect(store.saveAttempts, 2);
        expect(store.successfulSaves, 1);
        expect(state.routeOptimized, isTrue);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    },
  );
}
