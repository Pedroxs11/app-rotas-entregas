import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/screens/load_screen.dart';
import 'package:app_rotas_entregas/services/package_store.dart';

class _CompactLoadStore implements PackageStore {
  _CompactLoadStore(this.items);

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
      id: 'compact-$number',
      scanNumber: number,
      address: AddressData(
        raw: 'Rua Compacta, $number',
        street: 'Rua Compacta',
        number: '$number',
        city: 'São Paulo',
        state: 'SP',
        confidence: 1,
        validation: ValidationStatus.confirmed,
      ),
      scannedAt: DateTime.utc(2026, 11, 22, 10, number),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'car and motorcycle organizers remain usable on a 320px phone',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (final vehicle in VehicleType.values) {
        SharedPreferences.setMockInitialValues({
          'load_vehicle_type': vehicle.name,
        });

        final state = AppState(
          store: _CompactLoadStore([
            _package(1),
            _package(2),
            _package(3),
          ]),
        );
        await state.init();

        await tester.pumpWidget(
          MaterialApp(home: LoadScreen(state: state)),
        );
        await tester.pumpAndSettle();

        if (vehicle == VehicleType.car) {
          expect(find.text('FRENTE E'), findsOneWidget);
          expect(find.text('FRENTE D'), findsOneWidget);
          expect(find.text('TRASEIRA E'), findsOneWidget);
          expect(find.text('TRASEIRA D'), findsOneWidget);
          expect(find.text('PORTA-MALAS'), findsOneWidget);
        } else {
          expect(find.text('MODO MOTO'), findsOneWidget);
          expect(find.text('BOLSA ESQUERDA'), findsOneWidget);
          expect(find.text('BOLSA DIREITA'), findsOneWidget);
          expect(find.text('BAÚ TRASEIRO'), findsOneWidget);
          expect(find.text('MOCHILA DE ENTREGA'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);

        final packageRow = find.text('Pacote 01');
        await tester.ensureVisible(packageRow);
        await tester.pumpAndSettle();
        await tester.tap(packageRow);
        await tester.pump();

        final targetZone = find.text(
          vehicle == VehicleType.car ? 'FRENTE E' : 'BAÚ TRASEIRO',
        );
        await tester.ensureVisible(targetZone);
        await tester.pumpAndSettle();
        await tester.tap(targetZone);
        await tester.pumpAndSettle();

        expect(
          state.packages.first.physicalZone,
          vehicle == VehicleType.car ? 'Frente esquerda' : 'Baú traseiro',
        );
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    },
  );
}
