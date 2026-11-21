import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/screens/load_screen.dart';
import 'package:app_rotas_entregas/services/package_store.dart';

class _LargeSelectionStore implements PackageStore {
  _LargeSelectionStore(this.items);

  List<DeliveryPackage> items;
  int saves = 0;

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
    saves++;
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
    'selecting and assigning all 600 active packages works for car and motorcycle',
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
        final store = _LargeSelectionStore(
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

        await tester.tap(find.text('Selecionar lista'));
        await tester.pumpAndSettle();

        expect(find.text('600 pacote(s) selecionado(s)'), findsOneWidget);

        await tester.tap(find.text(targetLabel));
        await tester.pumpAndSettle();

        expect(state.packages, hasLength(600));
        expect(
          state.packages.every((package) => package.physicalZone == targetZone),
          isTrue,
          reason: 'Every active package must be assigned in $vehicle mode.',
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
        expect(store.saves, 1);
        expect(state.routeOptimized, isTrue);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    },
  );
}
