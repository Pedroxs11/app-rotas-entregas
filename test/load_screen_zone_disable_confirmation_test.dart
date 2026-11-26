import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/screens/load_screen.dart';
import 'package:app_rotas_entregas/services/package_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ZoneConfirmationStore implements PackageStore {
  _ZoneConfirmationStore(this.items);

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

DeliveryPackage _assignedPackage(
  String zone, {
  String id = 'confirmation-package',
  bool delivered = false,
}) =>
    DeliveryPackage(
      id: id,
      scanNumber: delivered ? 2 : 1,
      physicalZone: zone,
      status: delivered ? DeliveryStatus.delivered : DeliveryStatus.pending,
      address: AddressData(
        raw: 'Rua da Confirmação, ${delivered ? 2 : 1}',
        street: 'Rua da Confirmação',
        number: delivered ? '2' : '1',
        city: 'São Paulo',
        state: 'SP',
        confidence: 1,
        validation: ValidationStatus.confirmed,
      ),
      scannedAt: DateTime.utc(2026, 11, 25, 12),
      completedAt: delivered ? DateTime.utc(2026, 11, 25, 13) : null,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'disabling an occupied car or motorcycle compartment requires confirmation and preserves delivered history',
    (tester) async {
      tester.view.physicalSize = const Size(400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (final scenario in [
        (
          vehicle: VehicleType.car,
          zone: 'Porta-malas',
          dialogTitle: 'Compartimentos do carro',
        ),
        (
          vehicle: VehicleType.motorcycle,
          zone: 'Mochila de entrega',
          dialogTitle: 'Compartimentos da moto',
        ),
      ]) {
        SharedPreferences.setMockInitialValues({
          'load_vehicle_type': scenario.vehicle.name,
        });
        final store = _ZoneConfirmationStore([
          _assignedPackage(
            scenario.zone,
            id: 'active-confirmation-package',
          ),
          _assignedPackage(
            scenario.zone,
            id: 'delivered-confirmation-package',
            delivered: true,
          ),
        ]);
        final state = AppState(store: store);
        await state.init();

        await tester.pumpWidget(
          MaterialApp(home: LoadScreen(state: state)),
        );
        await tester.pumpAndSettle();

        DeliveryPackage activePackage() => state.packages.singleWhere(
              (package) => package.id == 'active-confirmation-package',
            );
        DeliveryPackage deliveredPackage() => state.packages.singleWhere(
              (package) => package.id == 'delivered-confirmation-package',
            );

        expect(activePackage().physicalZone, scenario.zone);
        expect(deliveredPackage().physicalZone, scenario.zone);
        expect(deliveredPackage().completedAt, DateTime.utc(2026, 11, 25, 13));

        await tester.tap(find.byTooltip('Configurar compartimentos'));
        await tester.pumpAndSettle();
        expect(find.text(scenario.dialogTitle), findsOneWidget);

        final compartment = find.widgetWithText(
          CheckboxListTile,
          scenario.zone,
        );
        await tester.ensureVisible(compartment);
        await tester.tap(compartment);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Salvar'));
        await tester.pumpAndSettle();

        // Only the active package should be counted as losing its position.
        // Delivered packages keep their historical compartment and completion.
        expect(
          find.text('1 pacote não entregue perderá sua posição atual.'),
          findsOneWidget,
        );
        await tester.tap(find.text('Voltar'));
        await tester.pumpAndSettle();

        // Canceling the destructive confirmation must keep both records intact.
        expect(find.text(scenario.dialogTitle), findsOneWidget);
        expect(state.activePhysicalZones, contains(scenario.zone));
        expect(activePackage().physicalZone, scenario.zone);
        expect(deliveredPackage().physicalZone, scenario.zone);
        expect(
          deliveredPackage().completedAt,
          DateTime.utc(2026, 11, 25, 13),
        );
        expect(store.items.firstWhere((p) => p.id == 'active-confirmation-package').physicalZone, scenario.zone);
        expect(store.items.firstWhere((p) => p.id == 'delivered-confirmation-package').physicalZone, scenario.zone);
        expect(store.saves, 0);

        await tester.tap(find.text('Cancelar'));
        await tester.pumpAndSettle();

        // Confirming the same change clears only the active package's position.
        await tester.tap(find.byTooltip('Configurar compartimentos'));
        await tester.pumpAndSettle();
        final secondCompartment = find.widgetWithText(
          CheckboxListTile,
          scenario.zone,
        );
        await tester.ensureVisible(secondCompartment);
        await tester.tap(secondCompartment);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Salvar'));
        await tester.pumpAndSettle();
        expect(
          find.text('Confirmar alteração dos compartimentos'),
          findsOneWidget,
        );
        await tester.tap(find.text('Desativar e continuar'));
        await tester.pumpAndSettle();

        expect(state.activePhysicalZones, isNot(contains(scenario.zone)));
        expect(activePackage().physicalZone, isNull);
        expect(deliveredPackage().physicalZone, scenario.zone);
        expect(
          deliveredPackage().status,
          DeliveryStatus.delivered,
        );
        expect(
          deliveredPackage().completedAt,
          DateTime.utc(2026, 11, 25, 13),
        );
        expect(
          store.items.firstWhere((p) => p.id == 'active-confirmation-package').physicalZone,
          isNull,
        );
        final storedDelivered = store.items.firstWhere(
          (p) => p.id == 'delivered-confirmation-package',
        );
        expect(storedDelivered.physicalZone, scenario.zone);
        expect(storedDelivered.status, DeliveryStatus.delivered);
        expect(storedDelivered.completedAt, DateTime.utc(2026, 11, 25, 13));
        expect(store.saves, 1);

        final preferences = await SharedPreferences.getInstance();
        final preferenceKey = scenario.vehicle == VehicleType.car
            ? 'load_zones_car'
            : 'load_zones_motorcycle';
        expect(
          preferences.getStringList(preferenceKey),
          isNot(contains(scenario.zone)),
        );
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        state.dispose();
      }
    },
  );
}
