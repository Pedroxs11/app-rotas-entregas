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


Future<void> _ensureLoadItemVisible(
  WidgetTester tester,
  Finder finder,
) async {
  final scrollable = find.descendant(
    of: find.byType(CustomScrollView),
    matching: find.byType(Scrollable),
  ).first;
  final position = tester.state<ScrollableState>(scrollable).position;
  final viewportFinder = find.byType(CustomScrollView);

  if (finder.evaluate().isEmpty &&
      position.pixels > position.minScrollExtent) {
    position.jumpTo(position.minScrollExtent);
    await tester.pumpAndSettle();
  }

  for (var attempt = 0; attempt < 120; attempt++) {
    if (finder.evaluate().isNotEmpty) {
      final target = tester.getRect(finder.first);
      final viewport = tester.getRect(viewportFinder);
      if (target.top >= viewport.top && target.bottom <= viewport.bottom) {
        return;
      }
      final delta = target.top < viewport.top
          ? target.top - viewport.top
          : target.bottom - viewport.bottom;
      final next = (position.pixels + delta)
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      if ((next - position.pixels).abs() < 0.5) break;
      position.jumpTo(next);
    } else {
      // Sliver children outside the cache extent do not have an Element yet,
      // so scroll in small increments until the requested package is built.
      final next = (position.pixels + 100)
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      if (next <= position.pixels) break;
      position.jumpTo(next);
    }
    await tester.pumpAndSettle();
  }

  expect(finder, findsWidgets);
  final target = tester.getRect(finder.first);
  final viewport = tester.getRect(viewportFinder);
  expect(target.top, greaterThanOrEqualTo(viewport.top));
  expect(target.bottom, lessThanOrEqualTo(viewport.bottom));
}

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

        // Selecting an assigned chip must not bubble into the compartment
        // assignment target and clear the selection immediately.
        for (final label in ['P01', 'P02']) {
          final chip = find.widgetWithText(InputChip, label);
          await tester.ensureVisible(chip);
          await tester.pumpAndSettle();
          await tester.tap(chip);
          await tester.pumpAndSettle();
        }

        expect(find.text('2 pacote(s) selecionado(s)'), findsOneWidget);
        expect(
          store.saveAttempts,
          0,
          reason: 'Selecting chips must not trigger a compartment save.',
        );
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

  testWidgets(
    'bulk removal only targets assigned packages and preserves unassigned selections',
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
          _package(vehicle, 2, targetZone).copyWith(clearPhysicalZone: true),
        ])..failNextSave = false;
        final state = AppState(store: store);
        await state.init();

        await tester.pumpWidget(MaterialApp(home: LoadScreen(state: state)));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Selecionar vários'));
        await tester.pumpAndSettle();

        final unassignedTile = find.text('Pacote 02');
        await _ensureLoadItemVisible(tester, unassignedTile);
        await tester.pumpAndSettle();
        await tester.tap(unassignedTile);
        await tester.pumpAndSettle();

        // The unassigned row is in a lazy sliver. Return to the top so the
        // organizer diagram and its assigned-package chips are mounted.
        await tester.drag(find.byType(CustomScrollView), const Offset(0, 1200));
        await tester.pumpAndSettle();

        expect(find.text('1 pacote(s) selecionado(s)'), findsOneWidget);
        expect(find.textContaining('RETIRAR'), findsNothing);

        final assignedChip = find.widgetWithText(InputChip, 'P01');
        expect(assignedChip, findsOneWidget);
        await tester.tap(assignedChip);
        await tester.pumpAndSettle();

        expect(find.text('2 pacote(s) selecionado(s)'), findsOneWidget);
        // The removal action must still count only the one assigned package.
        expect(find.text('RETIRAR PACOTE SELECIONADO'), findsOneWidget);

        await tester.tap(find.text('RETIRAR PACOTE SELECIONADO'));
        await tester.pumpAndSettle();

        expect(store.saveAttempts, 1);
        expect(store.successfulSaves, 1);
        expect(state.packages.first.physicalZone, isNull);
        expect(state.packages.last.physicalZone, isNull);
        expect(find.text('1 pacote(s) selecionado(s)'), findsOneWidget);
        expect(find.textContaining('RETIRAR'), findsNothing);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    },
  );

}
