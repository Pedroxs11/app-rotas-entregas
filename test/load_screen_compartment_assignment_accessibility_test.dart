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
          final assignmentNode = find.byKey(
            ValueKey('load-zone-assignment-${scenario.zone}'),
          );
          await Scrollable.ensureVisible(
            tester.element(assignmentNode),
            alignment: 0.5,
            duration: Duration.zero,
          );
          await tester.pumpAndSettle();
          expect(assignmentNode, findsOneWidget);
          final emptyCompartmentData =
              tester.getSemantics(assignmentNode).getSemanticsData();
          expect(emptyCompartmentData.label, emptyLabel);
          expect(
            emptyCompartmentData.hasAction(SemanticsAction.tap),
            isTrue,
            reason: 'The compartment must expose an actionable TalkBack target.',
          );

          await tester.tap(find.byTooltip('Selecionar vários'));
          await tester.pumpAndSettle();

          // The unassigned packages live in a lazy SliverList. A ListTile
          // finder cannot use .at(index) before that row has entered the
          // viewport, so scroll to its stable scan-number label first.
          Future<void> tapUnassignedPackage(int scanNumber) async {
            final numberLabel = find.text(
              scanNumber.toString().padLeft(2, '0'),
            );
            await tester.scrollUntilVisible(
              numberLabel,
              240,
              scrollable: find.byType(Scrollable).first,
            );
            final tile = find.ancestor(
              of: numberLabel,
              matching: find.byType(ListTile),
            );
            expect(tile, findsOneWidget);
            await tester.tap(tile);
            await tester.pumpAndSettle();
          }

          await tapUnassignedPackage(1);
          await tapUnassignedPackage(2);

          expect(find.text('2 pacote(s) selecionado(s)'), findsOneWidget);
          final selectedLabel =
              'Compartimento ${scenario.label}. 0 pacotes posicionados. '
              'Toque para guardar 2 pacotes neste compartimento.';
          // Package selection scrolls the lazy list. Reposition the
          // compartment into the viewport before reading or tapping its
          // semantics node; the fixed selection card can otherwise clip it.
          await Scrollable.ensureVisible(
            tester.element(assignmentNode),
            alignment: 0.5,
            duration: Duration.zero,
          );
          await tester.pumpAndSettle();
          final selectedCompartmentData =
              tester.getSemantics(assignmentNode).getSemanticsData();
          expect(selectedCompartmentData.label, selectedLabel);
          expect(
            selectedCompartmentData.hasAction(SemanticsAction.tap),
            isTrue,
          );
          expect(
            tester.getSize(assignmentNode).height,
            greaterThanOrEqualTo(48),
            reason: 'The compartment action must have a 48 dp touch target.',
          );

          await tester.tap(assignmentNode);
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
              'Selecione pacotes e toque aqui para posicioná-los.';
          // Assignment changes the diagram's contents and can slightly alter
          // its scroll extent. Verify the complete action node after it is
          // brought back into the viewport, not only the previously tapped
          // position.
          await Scrollable.ensureVisible(
            tester.element(assignmentNode),
            alignment: 0.5,
            duration: Duration.zero,
          );
          await tester.pumpAndSettle();
          expect(
            tester.getSemantics(assignmentNode).getSemanticsData().label,
            assignedLabel,
          );
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
