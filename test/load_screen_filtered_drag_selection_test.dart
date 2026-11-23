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
        raw: number >= 10
            ? 'Rua Teste, setor 1, $number'
            : 'Rua Teste, setor 2, $number',
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

        await tester.enterText(find.byType(TextField), 'setor 1');
        await tester.pumpAndSettle();

        // The package list is a lazy SliverList below the vehicle diagram.
        // Bring the last filtered row into view with small increments so the
        // first and last drag targets remain visible at the same time.
        final scrollable = find.descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(Scrollable),
        ).first;
        await tester.scrollUntilVisible(
          find.text('Pacote 12'),
          100,
          scrollable: scrollable,
        );

        expect(find.text('Pacote 10'), findsOneWidget);
        expect(find.text('Pacote 11'), findsOneWidget);
        expect(find.text('Pacote 12'), findsOneWidget);
        expect(find.text('Pacote 01'), findsNothing);

        final viewport = tester.getRect(find.byType(CustomScrollView));
        for (final target in ['Pacote 10', 'Pacote 12']) {
          final targetRect = tester.getRect(find.text(target));
          expect(targetRect.top, greaterThanOrEqualTo(viewport.top));
          expect(targetRect.bottom, lessThanOrEqualTo(viewport.bottom));
        }

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
        // The drag leaves the list scrolled near the filtered packages.
        // Bring the compartment back into the viewport before tapping it.
        final targetCompartment = find.text(targetLabel);
        await tester.ensureVisible(targetCompartment);
        await tester.pumpAndSettle();
        await tester.tap(targetCompartment);
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

  testWidgets(
    'select all only assigns filtered search results for car and motorcycle',
    (tester) async {
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

        await tester.enterText(find.byType(TextField), 'setor 1');
        await tester.pumpAndSettle();

        final selectResults = find.text('Selecionar resultados');
        await tester.ensureVisible(selectResults);
        await tester.pumpAndSettle();
        await tester.tap(selectResults);
        await tester.pumpAndSettle();

        expect(find.text('3 pacote(s) selecionado(s)'), findsOneWidget);

        final targetLabel = vehicle == VehicleType.car
            ? 'FRENTE E'
            : 'BAÚ TRASEIRO';
        final targetZone = vehicle == VehicleType.car
            ? 'Frente esquerda'
            : 'Baú traseiro';
        final targetCompartment = find.text(targetLabel);
        await tester.ensureVisible(targetCompartment);
        await tester.pumpAndSettle();
        await tester.tap(targetCompartment);
        await tester.pumpAndSettle();

        expect(
          state.packages
              .where((package) => package.physicalZone == targetZone)
              .map((package) => package.id)
              .toSet(),
          {'p10', 'p11', 'p12'},
        );
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



  testWidgets(
    'changing search cancels pending and active drag selection for car and motorcycle',
    (tester) async {
      // Keep the search field and the first lazy-list rows mounted together so
      // the test can change the query while a pointer remains down.
      tester.view.physicalSize = const Size(400, 1800);
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

        final firstPackage = find.text('Pacote 01');
        expect(firstPackage, findsOneWidget);

        // A query change must also cancel a pointer that is reserved for a
        // long press but has not crossed the long-press threshold yet.
        final pendingGesture =
            await tester.startGesture(tester.getCenter(firstPackage));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.enterText(find.byType(TextField), 'setor 1');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.text('0 pacote(s) selecionado(s)'), findsOneWidget);
        await pendingGesture.up();
        await tester.pumpAndSettle();

        // Reset the filter and start a real drag-selection session.
        await tester.enterText(find.byType(TextField), '');
        await tester.pumpAndSettle();
        final gesture = await tester.startGesture(tester.getCenter(firstPackage));
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.text('1 pacote(s) selecionado(s)'), findsOneWidget);

        // The new filter contains only packages 10-12. The existing pointer
        // must no longer be allowed to extend its old index range into it.
        await tester.enterText(find.byType(TextField), 'setor 1');
        await tester.pumpAndSettle();
        final filteredPackage = find.text('Pacote 10');
        await tester.ensureVisible(filteredPackage);
        await tester.pumpAndSettle();
        await gesture.moveTo(
          tester.getCenter(filteredPackage),
          timeStamp: const Duration(milliseconds: 700),
        );
        await tester.pump();
        expect(find.text('1 pacote(s) selecionado(s)'), findsOneWidget);

        await gesture.up();
        await tester.pumpAndSettle();

        // Clearing the filter reveals the original selection again. Assigning
        // it must affect only the package selected before the query changed.
        await tester.enterText(find.byType(TextField), '');
        await tester.pumpAndSettle();
        final targetLabel = vehicle == VehicleType.car
            ? 'FRENTE E'
            : 'BAÚ TRASEIRO';
        final targetZone = vehicle == VehicleType.car
            ? 'Frente esquerda'
            : 'Baú traseiro';
        final targetCompartment = find.text(targetLabel);
        await tester.ensureVisible(targetCompartment);
        await tester.pumpAndSettle();
        await tester.tap(targetCompartment);
        await tester.pumpAndSettle();

        expect(
          state.packages
              .where((package) => package.physicalZone == targetZone)
              .map((package) => package.id)
              .toSet(),
          {'p1'},
          reason: 'A stale drag must not add newly filtered packages in $vehicle mode.',
        );
        expect(
          state.packages
              .where((package) => package.physicalZone == null)
              .map((package) => package.id)
              .toSet(),
          {'p2', 'p3', 'p4', 'p5', 'p6', 'p7', 'p8', 'p9', 'p10', 'p11', 'p12'},
        );
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    },
  );

}
