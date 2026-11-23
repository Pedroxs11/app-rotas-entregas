import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/screens/load_screen.dart';
import 'package:app_rotas_entregas/services/package_store.dart';

class _PersistentLoadStore implements PackageStore {
  _PersistentLoadStore(this.items);

  List<DeliveryPackage> items;
  int saves = 0;
  Completer<void>? nextSaveGate;
  Object? nextSaveError;

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
    final gate = nextSaveGate;
    nextSaveGate = null;
    if (gate != null) await gate.future;
    final error = nextSaveError;
    nextSaveError = null;
    if (error != null) throw error;
    items = [...value];
    saves++;
  }
}

DeliveryPackage _package(
  String id,
  int scanNumber, {
  String? zone,
  DeliveryStatus status = DeliveryStatus.pending,
}) =>
    DeliveryPackage(
      id: id,
      scanNumber: scanNumber,
      physicalZone: zone,
      status: status,
      address: AddressData(
        raw: 'Rua Teste, $scanNumber',
        street: 'Rua Teste',
        number: '$scanNumber',
        city: 'São Paulo',
        state: 'SP',
        confidence: 1,
        validation: ValidationStatus.confirmed,
      ),
      scannedAt: DateTime.utc(2026, 11, 20, 11, scanNumber),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'car and motorcycle layouts survive repeated UI switches and app restart',
    (tester) async {
      final store = _PersistentLoadStore([
        _package('active-1', 1, zone: 'Porta-malas'),
        _package('active-2', 2),
        _package(
          'delivered',
          3,
          zone: 'Porta-malas',
          status: DeliveryStatus.delivered,
        ),
      ]);
      final state = AppState(store: store);
      await state.init();

      await tester.pumpWidget(MaterialApp(home: LoadScreen(state: state)));
      await tester.pumpAndSettle();

      Future<void> configureOnly(
        List<String> zones,
        String retainedZone,
      ) async {
        await tester.tap(find.byTooltip('Configurar compartimentos'));
        await tester.pumpAndSettle();
        for (final zone in zones.where((zone) => zone != retainedZone)) {
          await tester.tap(find.widgetWithText(CheckboxListTile, zone));
          await tester.pump();
        }
        await tester.tap(find.text('Salvar'));
        await tester.pumpAndSettle();
        expect(state.activePhysicalZones, [retainedZone]);
      }

      Future<void> selectVehicle(VehicleType vehicle) async {
        await tester.tap(find.byTooltip('Veículo'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(
          vehicle == VehicleType.car ? '🚗 Carro' : '🏍️ Moto',
        ));
        await tester.pumpAndSettle();
        expect(state.vehicleType, vehicle);
      }

      await configureOnly(AppState.carPhysicalZones, 'Porta-malas');
      await state.setPhysicalZone('active-2', 'Porta-malas');
      expect(
        state.packages.take(2).every((package) => package.physicalZone == 'Porta-malas'),
        isTrue,
      );

      await selectVehicle(VehicleType.motorcycle);
      expect(state.activePhysicalZones, AppState.motorcyclePhysicalZones);
      expect(
        state.packages.take(2).every((package) => package.physicalZone == null),
        isTrue,
      );
      expect(state.packages.last.physicalZone, 'Porta-malas');

      await configureOnly(
        AppState.motorcyclePhysicalZones,
        'Baú traseiro',
      );
      await state.setPhysicalZones(
        {'active-1', 'active-2'},
        'Baú traseiro',
      );
      expect(
        state.packages.take(2).every((package) => package.physicalZone == 'Baú traseiro'),
        isTrue,
      );

      await selectVehicle(VehicleType.car);
      expect(state.activePhysicalZones, ['Porta-malas']);
      expect(
        state.packages.take(2).every((package) => package.physicalZone == null),
        isTrue,
      );
      expect(state.packages.last.physicalZone, 'Porta-malas');

      await selectVehicle(VehicleType.motorcycle);
      expect(state.activePhysicalZones, ['Baú traseiro']);
      expect(state.packages.last.status, DeliveryStatus.delivered);
      expect(state.packages.last.physicalZone, 'Porta-malas');

      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.getStringList('load_zones_car'),
        ['Porta-malas'],
      );
      expect(
        preferences.getStringList('load_zones_motorcycle'),
        ['Baú traseiro'],
      );
      expect(preferences.getString('load_vehicle_type'), 'motorcycle');
      expect(tester.takeException(), isNull);

      final savesBeforeRestart = store.saves;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      final resumed = AppState(store: store);
      await resumed.init();

      expect(resumed.startupError, isNull);
      expect(resumed.vehicleType, VehicleType.motorcycle);
      expect(resumed.activePhysicalZones, ['Baú traseiro']);
      expect(resumed.packages, hasLength(3));
      expect(resumed.packages[0].physicalZone, isNull);
      expect(resumed.packages[1].physicalZone, isNull);
      expect(resumed.packages[2].status, DeliveryStatus.delivered);
      expect(resumed.packages[2].physicalZone, 'Porta-malas');
      expect(
        store.saves,
        savesBeforeRestart,
        reason: 'Restart must not rewrite an already reconciled load.',
      );

      await resumed.setVehicleType(VehicleType.car);
      expect(resumed.activePhysicalZones, ['Porta-malas']);
      await resumed.setVehicleType(VehicleType.motorcycle);
      expect(resumed.activePhysicalZones, ['Baú traseiro']);

      expect(
        preferences.getStringList('load_zones_car'),
        ['Porta-malas'],
      );
      expect(
        preferences.getStringList('load_zones_motorcycle'),
        ['Baú traseiro'],
      );
    },
  );

  testWidgets(
    'switching vehicles cancels an in-progress drag selection',
    (tester) async {
      tester.view.physicalSize = const Size(400, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final store = _PersistentLoadStore(
        List.generate(
          60,
          (index) => _package('drag-${index + 1}', index + 1),
        ),
      );
      final state = AppState(store: store);
      await state.init();

      await tester.pumpWidget(MaterialApp(home: LoadScreen(state: state)));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Selecionar vários'));
      await tester.pump();

      final loadScrollable = find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(Scrollable),
      ).first;
      await tester.scrollUntilVisible(
        find.text('Pacote 01'),
        120,
        scrollable: loadScrollable,
      );
      final first = tester.getCenter(find.text('Pacote 01'));
      final viewport = tester.getRect(find.byType(CustomScrollView));
      final gesture = await tester.startGesture(first, pointer: 1);
      await tester.pump(const Duration(milliseconds: 600));
      final edge = Offset(first.dx, viewport.bottom - 30);
      await gesture.moveTo(
        edge,
        timeStamp: const Duration(milliseconds: 700),
      );
      await tester.pump(const Duration(milliseconds: 160));

      final selectedCountFinder = find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            (widget.data?.endsWith('pacote(s) selecionado(s)') ?? false),
      );
      expect(selectedCountFinder, findsOneWidget);
      final selectedBeforeSwitch = int.parse(
        tester.widget<Text>(selectedCountFinder).data!.split(' ').first,
      );
      expect(selectedBeforeSwitch, greaterThan(1));

      // Create a pending package-position save only after the drag has started.
      // This keeps the whole list available for the selection gesture while
      // still forcing the vehicle switch to await persistence.
      await state.setPhysicalZone('drag-60', 'Porta-malas');
      await tester.pump();
      expect(
        int.parse(tester.widget<Text>(selectedCountFinder).data!.split(' ').first),
        greaterThan(1),
      );

      final oldScrollable = find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(Scrollable),
      ).first;
      final oldScrollOffset =
          tester.state<ScrollableState>(oldScrollable).position.pixels;
      expect(oldScrollOffset, greaterThan(0));

      // Hold package persistence open while invoking the same selection
      // callback used by the vehicle popup. The old auto-scroll timer must
      // stop immediately, not after the asynchronous save finishes.
      final saveGate = Completer<void>();
      store.nextSaveGate = saveGate;
      final vehicleSelector = tester.widget<PopupMenuButton<VehicleType>>(
        find.byType(PopupMenuButton<VehicleType>),
      );
      vehicleSelector.onSelected!(VehicleType.motorcycle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 160));
      expect(state.vehicleType, VehicleType.car);
      expect(find.text('0 pacote(s) selecionado(s)'), findsOneWidget);
      expect(
        tester.state<ScrollableState>(oldScrollable).position.pixels,
        oldScrollOffset,
        reason: 'Auto-scroll must stop while vehicle persistence is pending.',
      );

      // The old vehicle screen remains visible until persistence completes.
      // A fresh gesture during that interval must be absorbed rather than
      // starting a second drag session against stale compartments.
      final oldViewport = tester.getRect(find.byType(CustomScrollView));
      final blockedGesture = await tester.startGesture(
        tester.getCenter(find.byType(CustomScrollView)),
        pointer: 2,
      );
      await blockedGesture.moveTo(
        Offset(oldViewport.center.dx, oldViewport.bottom - 20),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        tester.state<ScrollableState>(oldScrollable).position.pixels,
        oldScrollOffset,
        reason: 'The organizer must ignore new gestures while switching vehicles.',
      );
      expect(find.text('0 pacote(s) selecionado(s)'), findsOneWidget);
      await blockedGesture.up();

      saveGate.complete();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 160));

      final scrollable = find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(Scrollable),
      ).first;
      expect(
        tester.state<ScrollableState>(scrollable).position.pixels,
        0,
        reason: 'The old drag timer must not scroll the new vehicle layout.',
      );
      expect(state.vehicleType, VehicleType.motorcycle);
      expect(find.text('MODO MOTO'), findsOneWidget);
      expect(find.text('0 pacote(s) selecionado(s)'), findsOneWidget);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'failed vehicle persistence rolls back and unlocks the organizer',
    (tester) async {
      final store = _PersistentLoadStore([
        _package('assigned', 1, zone: 'Porta-malas'),
        _package('pending', 2),
      ]);
      final state = AppState(store: store);
      await state.init();

      await tester.pumpWidget(MaterialApp(home: LoadScreen(state: state)));
      await tester.pumpAndSettle();

      store.nextSaveError = StateError('simulated disk failure');
      await tester.tap(find.byTooltip('Veículo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('🏍️ Moto'));
      await tester.pumpAndSettle();

      expect(state.vehicleType, VehicleType.car);
      expect(state.activePhysicalZones, AppState.carPhysicalZones);
      expect(state.packages.first.physicalZone, 'Porta-malas');
      expect(
        find.textContaining('Não foi possível trocar o veículo'),
        findsOneWidget,
      );
      final vehicleMenuButton = find.byWidgetPredicate(
        (widget) => widget is PopupMenuButton<VehicleType>,
      );
      expect(
        tester.widget<PopupMenuButton<VehicleType>>(vehicleMenuButton).enabled,
        isTrue,
        reason: 'A failed save must release the vehicle-switch lock.',
      );
      expect(tester.takeException(), isNull);

      // The failed write is consumed and the same action can be retried.
      await tester.tap(find.byTooltip('Veículo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('🏍️ Moto'));
      await tester.pumpAndSettle();

      expect(state.vehicleType, VehicleType.motorcycle);
      expect(state.packages.first.physicalZone, isNull);
      expect(find.text('MODO MOTO'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'switching vehicles returns the load organizer to the top',
    (tester) async {
      tester.view.physicalSize = const Size(400, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final store = _PersistentLoadStore(
        List.generate(
          40,
          (index) => _package('package-${index + 1}', index + 1),
        ),
      );
      final state = AppState(store: store);
      await state.init();

      await tester.pumpWidget(MaterialApp(home: LoadScreen(state: state)));
      await tester.pumpAndSettle();

      final scrollable = find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(Scrollable),
      ).first;
      double currentScrollOffset() =>
          tester.state<ScrollableState>(scrollable).position.pixels;
      double currentMinScrollOffset() =>
          tester.state<ScrollableState>(scrollable).position.minScrollExtent;

      Future<void> scrollToLastPackage() async {
        await tester.scrollUntilVisible(
          find.text('Pacote 40'),
          180,
          scrollable: scrollable,
        );
        await tester.pumpAndSettle();
      }

      Future<void> switchVehicle(VehicleType vehicle) async {
        await tester.tap(find.byTooltip('Veículo'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(
          vehicle == VehicleType.car ? '🚗 Carro' : '🏍️ Moto',
        ));
        await tester.pumpAndSettle();
        expect(state.vehicleType, vehicle);
        expect(currentScrollOffset(), currentMinScrollOffset());
      }

      await scrollToLastPackage();
      expect(currentScrollOffset(), greaterThan(0));

      await switchVehicle(VehicleType.motorcycle);
      expect(find.text('MODO MOTO'), findsOneWidget);

      await scrollToLastPackage();
      expect(currentScrollOffset(), greaterThan(0));

      await switchVehicle(VehicleType.car);
      expect(find.text('FRENTE', skipOffstage: false), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
