import 'dart:async';

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
  Completer<void>? saveGate;

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
    final gate = saveGate;
    saveGate = null;
    if (gate != null) await gate.future;
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
    await tester.pump(const Duration(milliseconds: 16));
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
      final next = (position.pixels + 100)
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      if (next <= position.pixels) break;
      position.jumpTo(next);
    }
    await tester.pump(const Duration(milliseconds: 16));
  }

  expect(finder, findsWidgets);
  final target = tester.getRect(finder.first);
  final viewport = tester.getRect(viewportFinder);
  expect(target.top, greaterThanOrEqualTo(viewport.top));
  expect(target.bottom, lessThanOrEqualTo(viewport.bottom));
}


Future<TestGesture> _startDragAutoScroll(
  WidgetTester tester,
  String packageLabel,
) async {
  final scrollable = find.descendant(
    of: find.byType(CustomScrollView),
    matching: find.byType(Scrollable),
  ).first;
  await _ensureLoadItemVisible(tester, find.text(packageLabel));
  final packageNumber = int.parse(RegExp(r'\d+').firstMatch(packageLabel)!.group(0)!);
  final nextPackageLabel = 'Pacote ${(packageNumber + 1).toString().padLeft(2, '0')}';
  await _ensureLoadItemVisible(tester, find.text(nextPackageLabel));

  final start = tester.getCenter(find.text(packageLabel));
  final nextPackage = tester.getCenter(find.text(nextPackageLabel));
  final viewport = tester.getRect(find.byType(CustomScrollView));
  final gesture = await tester.startGesture(start, pointer: 1);
  await tester.pump(const Duration(milliseconds: 600));
  await gesture.moveTo(
    nextPackage,
    timeStamp: const Duration(milliseconds: 700),
  );
  await tester.pump(const Duration(milliseconds: 16));
  await gesture.moveTo(
    Offset(nextPackage.dx, viewport.bottom - 30),
    timeStamp: const Duration(milliseconds: 716),
  );
  await tester.pump(const Duration(milliseconds: 160));

  final selectedCount = find.byWidgetPredicate(
    (widget) =>
        widget is Text &&
        (widget.data?.endsWith('pacote(s) selecionado(s)') ?? false),
  );
  expect(selectedCount, findsOneWidget);
  final selected = int.parse(
    tester.widget<Text>(selectedCount).data!.split(' ').first,
  );
  expect(selected, greaterThan(1));

  final position = tester.state<ScrollableState>(scrollable).position;
  expect(
    position.pixels,
    greaterThan(0),
    reason: 'The drag must have started the periodic edge auto-scroll.',
  );
  return gesture;
}

int _selectedPackageCount(WidgetTester tester) {
  final finder = find.byWidgetPredicate(
    (widget) =>
        widget is Text &&
        (widget.data?.endsWith('pacote(s) selecionado(s)') ?? false),
  );
  expect(finder, findsOneWidget);
  return int.parse(tester.widget<Text>(finder).data!.split(' ').first);
}

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
        // A successful retry must consume the selection so a later tap
        // cannot accidentally assign the same 600 packages a second time.
        expect(find.text('0 pacote(s) selecionado(s)'), findsOneWidget);
        expect(find.textContaining('RETIRAR'), findsNothing);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets(
    'rapid compartment taps do not queue a second assignment while the first save is pending',
    (tester) async {
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({'load_vehicle_type': 'car'});
      final store = _RetryingLoadStore([
        _package(VehicleType.car, 1),
        _package(VehicleType.car, 2),
      ])..failNextSave = false;
      final saveGate = Completer<void>();
      store.saveGate = saveGate;
      final state = AppState(store: store);
      await state.init();

      await tester.pumpWidget(MaterialApp(home: LoadScreen(state: state)));
      await tester.pumpAndSettle();

      final packageRow = find.text('Pacote 01');
      await _ensureLoadItemVisible(tester, packageRow);
      await tester.tap(packageRow);
      await tester.pump();

      final firstCompartment = find.text('FRENTE E');
      await _ensureLoadItemVisible(tester, firstCompartment);
      await tester.tap(firstCompartment);
      await tester.pump();

      expect(store.saveAttempts, 1);
      expect(find.byType(CircularProgressIndicator), findsWidgets);

      // The second compartment remains visible, but the organizer must absorb
      // taps until the first persistence operation finishes.
      final secondCompartment = find.text('FRENTE D');
      expect(secondCompartment, findsOneWidget);
      // The first compartment was brought fully into view; the adjacent
      // compartment shares the same row. Absorb this intentional blocked tap.
      await tester.tap(secondCompartment, warnIfMissed: false);
      await tester.pump();
      expect(store.saveAttempts, 1);

      saveGate.complete();
      await tester.pumpAndSettle();

      expect(state.packages.first.physicalZone, 'Frente esquerda');
      expect(state.packages.last.physicalZone, isNull);
      expect(store.items.first.physicalZone, 'Frente esquerda');
      expect(store.saveAttempts, 1);
      expect(store.successfulSaves, 1);
      expect(find.textContaining('selecionado. Agora toque'), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'rapid bulk-removal taps perform only one save while persistence is pending',
    (tester) async {
      tester.view.physicalSize = const Size(400, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({'load_vehicle_type': 'car'});
      final store = _RetryingLoadStore([
        _package(VehicleType.car, 1).copyWith(physicalZone: 'Porta-malas'),
        _package(VehicleType.car, 2).copyWith(physicalZone: 'Porta-malas'),
      ])..failNextSave = false;
      final saveGate = Completer<void>();
      store.saveGate = saveGate;
      final state = AppState(store: store);
      await state.init();

      await tester.pumpWidget(MaterialApp(home: LoadScreen(state: state)));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Selecionar vários'));
      await tester.pumpAndSettle();

      for (final label in ['P01', 'P02']) {
        final assignedChip = find.widgetWithText(InputChip, label);
        final chip = tester.widget<InputChip>(assignedChip);
        chip.onSelected!(true);
        await tester.pump();
      }
      expect(find.text('2 pacote(s) selecionado(s)'), findsOneWidget);

      final removeButton = find.text('RETIRAR 2 PACOTES');
      await tester.ensureVisible(removeButton);
      await tester.pumpAndSettle();
      // Capture the original hit target before the optimistic state update
      // removes the now-unassigned packages from the removal action.
      final removeButtonCenter = tester.getCenter(removeButton);
      await tester.tap(removeButton);
      await tester.pump();

      expect(store.saveAttempts, 1);
      expect(removeButton, findsNothing);
      expect(find.byType(CircularProgressIndicator), findsWidgets);

      // The action can disappear while the save is pending, but tapping its
      // former location must still be absorbed by the organizer's busy lock.
      await tester.tapAt(removeButtonCenter);
      await tester.pump();
      expect(store.saveAttempts, 1);

      saveGate.complete();
      await tester.pumpAndSettle();

      expect(state.packages, hasLength(2));
      expect(state.packages.every((package) => package.physicalZone == null), isTrue);
      expect(store.items, hasLength(2));
      expect(store.items.every((package) => package.physicalZone == null), isTrue);
      expect(store.saveAttempts, 1);
      expect(store.successfulSaves, 1);
      expect(find.text('0 pacote(s) selecionado(s)'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );


  testWidgets(
    'assignment stops active drag auto-scroll before persistence for car and motorcycle',
    (tester) async {
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (final vehicle in [VehicleType.car, VehicleType.motorcycle]) {
        SharedPreferences.setMockInitialValues({
          'load_vehicle_type': vehicle.name,
        });
        final zone = vehicle == VehicleType.car
            ? 'Porta-malas'
            : 'Baú traseiro';
        final zoneLabel = vehicle == VehicleType.car
            ? 'PORTA-MALAS'
            : 'BAÚ TRASEIRO';
        final store = _RetryingLoadStore(
          List.generate(60, (index) => _package(vehicle, index + 1)),
        )..failNextSave = false;
        final saveGate = Completer<void>();
        store.saveGate = saveGate;
        final state = AppState(store: store);
        await state.init();

        await tester.pumpWidget(MaterialApp(home: LoadScreen(state: state)));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Selecionar vários'));
        await tester.pump();

        // Capture the real compartment callback while its card is visible;
        // the drag will scroll this card out of the viewport.
        final zoneFinder = find.ancestor(
          of: find.text(zoneLabel),
          matching: find.byType(InkWell),
        ).first;
        final assignToZone = tester.widget<InkWell>(zoneFinder).onTap!;

        final gesture = await _startDragAutoScroll(tester, 'Pacote 01');
        final selectedForAssignment = _selectedPackageCount(tester);
        final scrollable = find.descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(Scrollable),
        ).first;
        final position = tester.state<ScrollableState>(scrollable).position;

        // Invoke the actual compartment tap callback while the drag pointer
        // is still down, matching a second-finger compartment selection.
        assignToZone();
        await tester.pump();
        final offsetAtMutation = position.pixels;

        expect(store.saveAttempts, 1);
        expect(find.byType(CircularProgressIndicator), findsWidgets);
        expect(_selectedPackageCount(tester), greaterThan(1));
        await tester.pump(const Duration(milliseconds: 160));
        expect(
          position.pixels,
          offsetAtMutation,
          reason: 'Assignment must stop the old drag timer immediately in $vehicle mode.',
        );

        await gesture.up();
        await tester.pump();
        saveGate.complete();
        await tester.pumpAndSettle();

        expect(state.packages, hasLength(60));
        expect(
          state.packages.where((package) => package.physicalZone == zone),
          hasLength(selectedForAssignment),
        );
        expect(
          state.packages.where((package) => package.physicalZone == null),
          hasLength(60 - selectedForAssignment),
        );
        expect(store.successfulSaves, 1);
        expect(_selectedPackageCount(tester), 0);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets(
    'bulk removal stops active drag auto-scroll before persistence for car and motorcycle',
    (tester) async {
      tester.view.physicalSize = const Size(400, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (final vehicle in [VehicleType.car, VehicleType.motorcycle]) {
        SharedPreferences.setMockInitialValues({
          'load_vehicle_type': vehicle.name,
        });
        final zone = vehicle == VehicleType.car
            ? 'Porta-malas'
            : 'Baú traseiro';
        final store = _RetryingLoadStore([
          _package(vehicle, 1).copyWith(physicalZone: zone),
          ...List.generate(
            59,
            (index) => _package(vehicle, index + 2),
          ),
        ])..failNextSave = false;
        final saveGate = Completer<void>();
        store.saveGate = saveGate;
        final state = AppState(store: store);
        await state.init();

        await tester.pumpWidget(MaterialApp(home: LoadScreen(state: state)));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Selecionar vários'));
        await tester.pump();

        final assignedChip = find.widgetWithText(InputChip, 'P01');
        final chip = tester.widget<InputChip>(assignedChip);
        chip.onSelected!(true);
        await tester.pump();
        expect(_selectedPackageCount(tester), 1);

        // Capture the removal action before the drag scrolls the header away.
        final removeFinder = find.ancestor(
          of: find.text('RETIRAR PACOTE SELECIONADO'),
          matching: find.byType(OutlinedButton),
        ).first;
        final removeSelected =
            tester.widget<OutlinedButton>(removeFinder).onPressed!;

        final gesture = await _startDragAutoScroll(tester, 'Pacote 02');
        final scrollable = find.descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(Scrollable),
        ).first;
        final position = tester.state<ScrollableState>(scrollable).position;

        // The assigned chip remains selected while a second pointer drags
        // through unassigned packages. Removing it must cancel that timer.
        removeSelected();
        await tester.pump();
        final offsetAtMutation = position.pixels;

        expect(store.saveAttempts, 1);
        expect(find.byType(CircularProgressIndicator), findsWidgets);
        await tester.pump(const Duration(milliseconds: 160));
        expect(
          position.pixels,
          offsetAtMutation,
          reason: 'Bulk removal must stop the old drag timer immediately in $vehicle mode.',
        );

        await gesture.up();
        await tester.pump();
        saveGate.complete();
        await tester.pumpAndSettle();

        expect(state.packages, hasLength(60));
        expect(state.packages.first.physicalZone, isNull);
        expect(store.items.first.physicalZone, isNull);
        expect(store.successfulSaves, 1);
        expect(_selectedPackageCount(tester), greaterThan(0));
        expect(find.textContaining('RETIRAR'), findsNothing);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    },
  );

}
