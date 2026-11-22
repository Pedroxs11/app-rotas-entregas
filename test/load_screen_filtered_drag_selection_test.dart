import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/screens/load_screen.dart';
import 'package:app_rotas_entregas/services/package_store.dart';

class _FilteredDragStore implements PackageStore {
  _FilteredDragStore(this.items);

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
      scannedAt: DateTime.utc(2026, 11, 22, 12, number),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'drag selection only includes filtered search results for car and motorcycle',
    (tester) async {
      tester.view.physicalSize = const Size(400, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (final vehicle in [VehicleType.car, VehicleType.motorcycle]) {
        SharedPreferences.setMockInitialValues({
          'load_vehicle_type': vehicle.name,
        });
        final store = _FilteredDragStore(
          List.generate(12, (index) => _package(index + 1)),
        );
        final state = AppState(store: store);
        await state.init();

        await tester.pumpWidget(MaterialApp(home: LoadScreen(state: state)));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Selecionar vários'));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), 'Pacote 1');
        await tester.pumpAndSettle();

        expect(find.text('Pacote 10'), findsOneWidget);
        expect(find.text('Pacote 11'), findsOneWidget);
        expect(find.text('Pacote 12'), findsOneWidget);
        expect(find.text('Pacote 01'), findsNothing);

        final first = tester.getCenter(find.text('Pacote 10'));
        final last = tester.getCenter(find.text('Pacote 12'));
        final gesture = await tester.startGesture(first);
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.text('1 pacote(s) selecionado(s)'), findsOneWidget);

        await gesture.moveTo(last, timeStamp: const Duration(milliseconds: 700));
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();

        expect(find.text('3 pacote(s) selecionado(s)'), findsOneWidget);

        final targetZone = vehicle == VehicleType.car
            ? 'Frente esquerda'
            : 'Baú traseiro';
        final targetLabel = vehicle == VehicleType.car
            ? 'FRENTE E'
            : 'BAÚ TRASEIRO';
        await tester.tap(find.text(targetLabel));
        await tester.pumpAndSettle();

        final assignedIds = state.packages
            .where((package) => package.physicalZone == targetZone)
            .map((package) => package.id)
            .toSet();
        expect(assignedIds, {'p10', 'p11', 'p12'});
        expect(
          state.packages
              .where((package) => package.physicalZone == null)
              .map((package) => package.id)
              .toSet(),
          {'p1', 'p2', 'p3', 'p4', 'p5', 'p6', 'p7', 'p8', 'p9'},
        );
        expect(store.items, hasLength(12));
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    },
  );
}
