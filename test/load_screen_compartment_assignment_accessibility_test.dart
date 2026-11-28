import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/screens/load_screen.dart';
import 'package:app_rotas_entregas/services/package_store.dart';

class _AssignmentSemanticsStore implements PackageStore {
  _AssignmentSemanticsStore(this.items);

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
      id: 'assignment-semantics-$number',
      scanNumber: number,
      recipient: 'Destinatário $number',
      address: AddressData(
        raw: 'Rua da Acessibilidade, $number',
        street: 'Rua da Acessibilidade',
        number: '$number',
        city: 'São Paulo',
        state: 'SP',
        confidence: 1,
        validation: ValidationStatus.confirmed,
      ),
      scannedAt: DateTime.utc(2026, 11, 27).add(Duration(minutes: number)),
    );

const _scenarios = [
  (
    vehicle: VehicleType.car,
    zone: 'Frente esquerda',
    label: 'FRENTE E',
  ),
  (
    vehicle: VehicleType.motorcycle,
    zone: 'Baú traseiro',
    label: 'BAÚ TRASEIRO',
  ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'compartment assignment announces the selected package count for car and motorcycle',
    (tester) async {
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();

      try {
        for (final scenario in _scenarios) {
          SharedPreferences.setMockInitialValues({
            'load_vehicle_type': scenario.vehicle.name,
          });
          final store = _AssignmentSemanticsStore(
            List.generate(3, (index) => _package(index + 1)),
          );
          final state = AppState(store: store);
          await state.init();

          await tester.pumpWidget(
            MaterialApp(home: LoadScreen(state: state)),
          );
          await tester.pumpAndSettle();

          final emptyLabel =
              'Compartimento ${scenario.label}. 0 pacotes posicionados. '
              'Selecione pacotes e toque aqui para posicioná-los.';
          final emptyCompartment = find.bySemanticsLabel(emptyLabel);
          expect(emptyCompartment, findsOneWidget);
          expect(
            tester
                .getSemantics(emptyCompartment)
                .getSemanticsData()
                .hasAction(SemanticsAction.tap),
            isTrue,
            reason: 'The compartment must expose an actionable TalkBack target.',
          );

          await tester.tap(find.byTooltip('Selecionar vários'));
          await tester.pumpAndSettle();

          final firstPackage = find.byType(ListTile).at(0);
          await tester.ensureVisible(firstPackage);
          await tester.pumpAndSettle();
          await tester.tap(firstPackage);
          await tester.pumpAndSettle();

          final secondPackage = find.byType(ListTile).at(1);
          await tester.ensureVisible(secondPackage);
          await tester.pumpAndSettle();
          await tester.tap(secondPackage);
          await tester.pumpAndSettle();

          expect(find.text('2 pacote(s) selecionado(s)'), findsOneWidget);
          final selectedLabel =
              'Compartimento ${scenario.label}. 0 pacotes posicionados. '
              'Toque para guardar 2 pacotes neste compartimento.';
          final selectedCompartment = find.bySemanticsLabel(selectedLabel);
          expect(selectedCompartment, findsOneWidget);
          expect(
            tester
                .getSemantics(selectedCompartment)
                .getSemanticsData()
                .hasAction(SemanticsAction.tap),
            isTrue,
          );

          await tester.tap(selectedCompartment);
          await tester.pumpAndSettle();

          expect(
            state.packages
                .where((package) => package.physicalZone == scenario.zone)
                .map((package) => package.id)
                .toSet(),
            {'assignment-semantics-1', 'assignment-semantics-2'},
          );
          expect(
            state.packages
                .singleWhere((package) => package.id == 'assignment-semantics-3')
                .physicalZone,
            isNull,
            reason: 'Bulk assignment must not move unselected packages.',
          );

          final assignedLabel =
              'Compartimento ${scenario.label}. 2 pacotes posicionados. '
              'Toque para selecionar este compartimento.';
          expect(find.bySemanticsLabel(assignedLabel), findsOneWidget);
          expect(tester.takeException(), isNull);

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          state.dispose();
        }
      } finally {
        semantics.dispose();
      }
    },
  );
}
