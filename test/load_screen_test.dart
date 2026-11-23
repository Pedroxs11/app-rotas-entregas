import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/screens/load_screen.dart';
import 'package:app_rotas_entregas/services/package_store.dart';

class _LoadStore implements PackageStore {
  _LoadStore(this.items);
  List<DeliveryPackage> items;
  int saves = 0;
  @override Future<void> clear() async {}
  @override Future<List<DeliveryPackage>> load() async => [...items];
  @override Future<bool> loadRouteOptimized() async => true;
  @override Future<void> save(List<DeliveryPackage> value,{bool? routeOptimized}) async {
    items=[...value];
    saves++;
  }
}

DeliveryPackage _package(int n,{String? physicalZone})=>DeliveryPackage(
  id:'p$n',
  scanNumber:n,
  physicalZone:physicalZone,
  address:AddressData(
    raw:'Rua Teste, $n',
    street:'Rua Teste',
    number:'$n',
    city:'São Paulo',
    state:'SP',
    confidence:1,
    validation:ValidationStatus.confirmed,
  ),
  scannedAt:DateTime.utc(2026,10,5,10,n),
);

Future<void> _ensureLoadItemVisible(WidgetTester tester, Finder finder) async {
  final scrollable = find.descendant(
    of: find.byType(CustomScrollView),
    matching: find.byType(Scrollable),
  ).first;
  final position = tester.state<ScrollableState>(scrollable).position;
  final viewportFinder = find.byType(CustomScrollView);

  if (finder.evaluate().isEmpty && position.pixels > position.minScrollExtent) {
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
      // Small increments avoid skipping a first row that starts just
      // below the viewport after the organizer reserves its action area.
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

Future<int> _dragSelectToBottom(
  WidgetTester tester, {
  required Duration autoScrollDuration,
}) async {
  await _ensureLoadItemVisible(tester, find.text('Pacote 01'));
  final first = tester.getCenter(find.text('Pacote 01'));
  final viewport = tester.getRect(find.byType(CustomScrollView));
  final gesture = await tester.startGesture(first);
  await tester.pump(const Duration(milliseconds: 600));
  expect(find.text('1 pacote(s) selecionado(s)'), findsOneWidget);

  // Keep the finger near the bottom edge so the real auto-scroll behavior
  // moves the lazy list underneath it, just as it does on a phone.
  final edge = Offset(first.dx, viewport.bottom - 30);
  await gesture.moveTo(edge, timeStamp: const Duration(milliseconds: 700));
  await tester.pump();

  final frames = (autoScrollDuration.inMilliseconds / 16).ceil();
  for (var frame = 0; frame < frames; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
  }

  await gesture.up();
  await tester.pumpAndSettle();

  final selectedCountFinder = find.byWidgetPredicate(
    (widget) =>
        widget is Text &&
        (widget.data?.endsWith('pacote(s) selecionado(s)') ?? false),
  );
  expect(selectedCountFinder, findsOneWidget);
  final selectedText = tester.widget<Text>(selectedCountFinder).data!;
  return int.parse(selectedText.split(' ').first);
}

void main(){
  setUp((){SharedPreferences.setMockInitialValues({});});
  testWidgets('car diagram lets driver manually place a package', (tester) async {
    final store=_LoadStore([_package(1),_package(2)]);
    final state=AppState(store:store);
    await state.init();

    await tester.pumpWidget(MaterialApp(home:LoadScreen(state:state)));
    await tester.pumpAndSettle();

    expect(find.text('FRENTE'),findsOneWidget);
    expect(find.text('FRENTE E'),findsOneWidget);
    expect(find.text('FRENTE D'),findsOneWidget);
    expect(find.text('TRASEIRA E'),findsOneWidget);
    expect(find.text('TRASEIRA D'),findsOneWidget);
    expect(find.text('PORTA-MALAS'),findsOneWidget);

    final frontLeft = tester.getTopLeft(find.text('FRENTE E'));
    final frontRight = tester.getTopLeft(find.text('FRENTE D'));
    final rearLeft = tester.getTopLeft(find.text('TRASEIRA E'));
    final rearRight = tester.getTopLeft(find.text('TRASEIRA D'));
    final trunk = tester.getTopLeft(find.text('PORTA-MALAS'));
    expect((frontLeft.dy - frontRight.dy).abs(), lessThan(1));
    expect(frontLeft.dx, lessThan(frontRight.dx));
    expect((rearLeft.dy - rearRight.dy).abs(), lessThan(1));
    expect(rearLeft.dx, lessThan(rearRight.dx));
    expect(trunk.dy, greaterThan(rearLeft.dy));

    await _ensureLoadItemVisible(tester, find.text('Pacote 01'));
    await tester.tap(find.text('Pacote 01'));
    await tester.pump();
    expect(find.textContaining('Pacote 01 selecionado'),findsOneWidget);

    await _ensureLoadItemVisible(tester, find.text('FRENTE E'));
    await tester.tap(find.text('FRENTE E'));
    await tester.pumpAndSettle();

    expect(state.packages.first.physicalZone,'Frente esquerda');
    expect(find.text('P01'),findsOneWidget);
  });


  testWidgets('multi-select keeps individually tapped packages selected and assigns them together', (tester) async {
    final store=_LoadStore([_package(1),_package(2),_package(3)]);
    final state=AppState(store:store);
    await state.init();

    await tester.pumpWidget(MaterialApp(home:LoadScreen(state:state)));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Selecionar vários'));
    await tester.pump();
    await _ensureLoadItemVisible(tester, find.text('Pacote 01'));
    await tester.tap(find.text('Pacote 01'));
    await _ensureLoadItemVisible(tester, find.text('Pacote 02'));
    await tester.tap(find.text('Pacote 02'));
    await tester.pump();

    await _ensureLoadItemVisible(tester, find.text('FRENTE E'));
    await tester.tap(find.text('FRENTE E'));
    await tester.pumpAndSettle();

    expect(state.packages[0].physicalZone,'Frente esquerda');
    expect(state.packages[1].physicalZone,'Frente esquerda');
    expect(state.packages[2].physicalZone,isNull);
  });

  testWidgets('moto does not require physical zones and uses package number identification', (tester) async {
    final store=_LoadStore([_package(7),_package(12)]);
    final state=AppState(store:store);
    await state.init();
    await state.setVehicleType(VehicleType.motorcycle);

    await tester.pumpWidget(MaterialApp(home:LoadScreen(state:state)));
    await tester.pumpAndSettle();

    expect(find.text('MODO MOTO'),findsOneWidget);
    expect(find.text('Toque no espaço da moto onde cada pacote será transportado.'),findsOneWidget);
    expect(find.text('BAÚ TRASEIRO'),findsOneWidget);
    expect(find.text('BOLSA ESQUERDA'),findsOneWidget);
    expect(find.text('FRENTE E'),findsNothing);
    expect(find.text('TRASEIRA E'),findsNothing);
    expect(find.text('PORTA-MALAS'),findsNothing);
    await _ensureLoadItemVisible(tester, find.text('Pacote 07'));
    expect(find.text('07'),findsWidgets);
    await _ensureLoadItemVisible(tester, find.text('Pacote 12'));
    expect(find.text('12'),findsWidgets);
    expect(find.text('INICIAR ENTREGAS'),findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,isNull);
    expect(state.packages.every((p)=>p.physicalZone==null),isTrue);

    final progress=tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    expect(progress.value,0.0);
    expect(find.text('Todos os pacotes estão posicionados. Confira a carga antes de sair.'),findsNothing);
  });
  testWidgets('moto treats old car compartments as unassigned and allows reassignment', (tester) async {
    final store=_LoadStore([_package(7,physicalZone:'Frente esquerda')]);
    final state=AppState(store:store);
    await state.init();
    await state.setVehicleType(VehicleType.motorcycle);

    await tester.pumpWidget(MaterialApp(home:LoadScreen(state:state)));
    await tester.pumpAndSettle();

    await _ensureLoadItemVisible(tester, find.text('Pacote 07'));
    expect(find.text('Pacote 07'),findsOneWidget);
    expect(find.text('Frente esquerda'),findsNothing);
    expect(find.text('BAÚ TRASEIRO'),findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,isNull);

    await _ensureLoadItemVisible(tester, find.text('Pacote 07'));
    await tester.tap(find.text('Pacote 07'));
    await tester.pump();
    await _ensureLoadItemVisible(tester, find.text('BAÚ TRASEIRO'));
    await tester.tap(find.text('BAÚ TRASEIRO'));
    await tester.pumpAndSettle();

    expect(state.packages.single.physicalZone,'Baú traseiro');
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,isNotNull);
    expect(find.text('P07'),findsOneWidget);
  });


  testWidgets('moto assigns multiple selected packages to one compartment', (tester) async {
    final state = AppState(store: _LoadStore([
      _package(7),
      _package(12),
      _package(18),
    ]));
    await state.init();
    await state.setVehicleType(VehicleType.motorcycle);

    await tester.pumpWidget(MaterialApp(home: LoadScreen(state: state)));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Selecionar vários'));
    await tester.pump();
    await _ensureLoadItemVisible(tester, find.text('Pacote 07'));
    await tester.tap(find.text('Pacote 07'));
    await _ensureLoadItemVisible(tester, find.text('Pacote 12'));
    await tester.tap(find.text('Pacote 12'));
    await tester.pump();

    expect(find.text('2 pacote(s) selecionado(s)'), findsOneWidget);
    await _ensureLoadItemVisible(tester, find.text('BAÚ TRASEIRO'));
    await tester.tap(find.text('BAÚ TRASEIRO'));
    await tester.pumpAndSettle();

    expect(state.packages[0].physicalZone, 'Baú traseiro');
    expect(state.packages[1].physicalZone, 'Baú traseiro');
    expect(state.packages[2].physicalZone, isNull);
    expect(find.text('P07'), findsOneWidget);
    expect(find.text('P12'), findsOneWidget);
    // The third package is intentionally left unassigned, so starting the
    // delivery route must remain disabled until the full load is organized.
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });

  testWidgets('multi-select can move assigned packages together with unassigned packages', (tester) async {
    final store=_LoadStore([
      _package(1,physicalZone:'Porta-malas'),
      _package(2),
    ]);
    final state=AppState(store:store);
    await state.init();

    await tester.pumpWidget(MaterialApp(home:LoadScreen(state:state)));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Selecionar vários'));
    await tester.pump();

    await _ensureLoadItemVisible(tester, find.text('P01'));
    await tester.tap(find.text('P01'));
    await tester.pump();
    final selectedChip=tester.widget<InputChip>(
      find.ancestor(of:find.text('P01'),matching:find.byType(InputChip)),
    );
    expect(selectedChip.selected,isTrue);

    await _ensureLoadItemVisible(tester, find.text('Pacote 02'));
    await tester.tap(find.text('Pacote 02'));
    await tester.pump();

    await _ensureLoadItemVisible(tester, find.text('FRENTE E'));
    await tester.tap(find.text('FRENTE E'));
    await tester.pumpAndSettle();

    expect(state.packages[0].physicalZone,'Frente esquerda');
    expect(state.packages[1].physicalZone,'Frente esquerda');
  });

  testWidgets('select all only includes unassigned packages', (tester) async {
    final store=_LoadStore([
      _package(1,physicalZone:'Porta-malas'),
      _package(2),
      _package(3,physicalZone:'Traseira direita'),
    ]);
    final state=AppState(store:store);
    await state.init();

    await tester.pumpWidget(MaterialApp(home:LoadScreen(state:state)));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Selecionar vários'));
    await tester.pump();
    await _ensureLoadItemVisible(tester, find.text('Selecionar lista'));
    await tester.tap(find.text('Selecionar lista'));
    await tester.pump();

    expect(find.text('1 pacote(s) selecionado(s)'),findsOneWidget);

    await _ensureLoadItemVisible(tester, find.text('FRENTE D'));
    await tester.tap(find.text('FRENTE D'));
    await tester.pumpAndSettle();

    expect(state.packages[0].physicalZone, 'Porta-malas');
    expect(state.packages[1].physicalZone, 'Frente direita');
    expect(state.packages[2].physicalZone, 'Traseira direita');
  });


  testWidgets('car and motorcycle drag selection auto-scroll on a phone-sized screen', (tester) async {
    tester.view.physicalSize = const Size(400, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final vehicle in [VehicleType.car, VehicleType.motorcycle]) {
      SharedPreferences.setMockInitialValues(
        vehicle == VehicleType.motorcycle
            ? {'load_vehicle_type': 'motorcycle'}
            : {},
      );
      final state = AppState(
        store: _LoadStore(List.generate(60, (index) => _package(index + 1))),
      );
      await state.init();

      await tester.pumpWidget(MaterialApp(home: LoadScreen(state: state)));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Selecionar vários'));
      await tester.pump();

      final selectedCount = await _dragSelectToBottom(
        tester,
        autoScrollDuration: const Duration(seconds: 2),
      );

      expect(
        selectedCount,
        greaterThan(10),
        reason: 'Drag selection should keep auto-scrolling in $vehicle mode.',
      );
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });


  testWidgets('car and motorcycle drag selection auto-scrolls upward through an 80-package load', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final vehicle in [VehicleType.car, VehicleType.motorcycle]) {
      SharedPreferences.setMockInitialValues(
        vehicle == VehicleType.motorcycle
            ? {'load_vehicle_type': 'motorcycle'}
            : {},
      );
      final state = AppState(
        store: _LoadStore(List.generate(80, (index) => _package(index + 1))),
      );
      await state.init();

      await tester.pumpWidget(MaterialApp(home: LoadScreen(state: state)));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Selecionar vários'));
      await tester.pump();

      // Begin at the bottom of the lazy list and keep the finger near the
      // top edge. This exercises the reverse direction of the real auto-scroll.
      await _ensureLoadItemVisible(tester, find.text('Pacote 80'));
      final last = tester.getCenter(find.text('Pacote 80'));
      final viewport = tester.getRect(find.byType(CustomScrollView));
      final gesture = await tester.startGesture(last);
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('1 pacote(s) selecionado(s)'), findsOneWidget);

      final edge = Offset(last.dx, viewport.top + 30);
      await gesture.moveTo(edge, timeStamp: const Duration(milliseconds: 700));
      await tester.pump();

      for (var frame = 0; frame < 125; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      await gesture.up();
      await tester.pumpAndSettle();

      final selectedCountFinder = find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            (widget.data?.endsWith('pacote(s) selecionado(s)') ?? false),
      );
      expect(selectedCountFinder, findsOneWidget);
      final selectedCount = int.parse(
        tester.widget<Text>(selectedCountFinder).data!.split(' ').first,
      );
      expect(
        selectedCount,
        greaterThan(10),
        reason: 'Reverse drag auto-scroll must keep selecting packages in $vehicle mode.',
      );
      expect(state.packages, hasLength(80));
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });


  testWidgets('drag selection stays contiguous when the finger changes direction', (tester) async {
    // Keep all six target rows mounted so this test isolates direction changes,
    // rather than depending on lazy-list scrolling before the drag begins.
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = AppState(
      store: _LoadStore(List.generate(8, (index) => _package(index + 1))),
    );
    await state.init();

    await tester.pumpWidget(MaterialApp(home: LoadScreen(state: state)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Selecionar vários'));
    await tester.pump();

    final first = tester.getCenter(find.text('Pacote 01'));
    final second = tester.getCenter(find.text('Pacote 02'));
    final fourth = tester.getCenter(find.text('Pacote 04'));
    final sixth = tester.getCenter(find.text('Pacote 06'));
    final gesture = await tester.createGesture();
    await gesture.down(first, timeStamp: Duration.zero);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('1 pacote(s) selecionado(s)'), findsOneWidget);
    // Showing the bulk-action button must not move the rows under the finger.
    expect(tester.getCenter(find.text('Pacote 04')), fourth);

    // Pin the pointer-down event to zero, then advance pointer and scheduler
    // timestamps together so no move is discarded as an out-of-order event.
    var pointerTimestamp = const Duration(milliseconds: 600);
    Future<void> moveToNextFrame(Offset position) async {
      await gesture.moveTo(position, timeStamp: pointerTimestamp);
      await tester.pump(const Duration(milliseconds: 16));
      pointerTimestamp += const Duration(milliseconds: 16);
    }

    await moveToNextFrame(fourth);
    expect(find.text('4 pacote(s) selecionado(s)'), findsOneWidget);

    await moveToNextFrame(second);
    expect(find.text('4 pacote(s) selecionado(s)'), findsOneWidget);

    await moveToNextFrame(sixth);
    expect(find.text('6 pacote(s) selecionado(s)'), findsOneWidget);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });


  testWidgets('car and motorcycle large loads build package rows lazily', (tester) async {
    tester.view.physicalSize = const Size(400, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final vehicle in VehicleType.values) {
      final state = AppState(
        store: _LoadStore(
          List.generate(600, (index) => _package(index + 1)),
        ),
      );
      await state.init();
      if (vehicle != VehicleType.car) {
        await state.setVehicleType(vehicle);
      }

      await tester.pumpWidget(MaterialApp(home: LoadScreen(state: state)));
      await tester.pumpAndSettle();

      expect(
        find.text('Pacote 600'),
        findsNothing,
        reason: 'The last package should not be built before scrolling ($vehicle).',
      );
      expect(
        find.byType(ListTile).evaluate().length,
        lessThan(30),
        reason: 'Only nearby package rows should be built ($vehicle).',
      );

      final scrollable = find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(Scrollable),
      ).first;
      final position = tester.state<ScrollableState>(scrollable).position;
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();

      expect(find.text('Pacote 600'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });


  testWidgets('car and motorcycle can bulk-organize 200 packages from the load screen', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final vehicle in [VehicleType.car, VehicleType.motorcycle]) {
      SharedPreferences.setMockInitialValues(
        vehicle == VehicleType.motorcycle
            ? {'load_vehicle_type': 'motorcycle'}
            : {'load_vehicle_type': 'car'},
      );
      final store = _LoadStore(
        List.generate(200, (index) => _package(index + 1)),
      );
      final state = AppState(store: store);
      await state.init();

      await tester.pumpWidget(MaterialApp(home: LoadScreen(state: state)));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Selecionar vários'));
      await tester.pump();
      await _ensureLoadItemVisible(tester, find.text('Selecionar lista'));
      await tester.tap(find.text('Selecionar lista'));
      await tester.pump();

      expect(find.text('200 pacote(s) selecionado(s)'), findsOneWidget);

      final targetLabel = vehicle == VehicleType.car
          ? 'PORTA-MALAS'
          : 'MOCHILA DE ENTREGA';
      final targetZone = vehicle == VehicleType.car
          ? 'Porta-malas'
          : 'Mochila de entrega';
      await _ensureLoadItemVisible(tester, find.text(targetLabel));
      await tester.tap(find.text(targetLabel));
      await tester.pumpAndSettle();

      expect(state.packages, hasLength(200));
      expect(store.saves, 1, reason: 'Bulk assignment must persist once in $vehicle mode.');
      expect(
        state.packages.every((p) => p.physicalZone == targetZone),
        isTrue,
        reason: 'All packages must be assigned in $vehicle mode.',
      );
      expect(find.text('200 de 200 pacotes posicionados'), findsOneWidget);
      expect(find.text('Ver todos (200)'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);

      await _ensureLoadItemVisible(tester, find.text('Ver todos (200)'));
      await tester.tap(find.text('Ver todos (200)'));
      await tester.pumpAndSettle();
      expect(find.text('P200'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });


  testWidgets('car and motorcycle can bulk-organize 600 packages from the load screen', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final vehicle in [VehicleType.car, VehicleType.motorcycle]) {
      SharedPreferences.setMockInitialValues(
        vehicle == VehicleType.motorcycle
            ? {'load_vehicle_type': 'motorcycle'}
            : {'load_vehicle_type': 'car'},
      );
      final store = _LoadStore(
        List.generate(600, (index) => _package(index + 1)),
      );
      final state = AppState(store: store);
      await state.init();

      await tester.pumpWidget(MaterialApp(home: LoadScreen(state: state)));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Selecionar vários'));
      await tester.pump();
      await _ensureLoadItemVisible(tester, find.text('Selecionar lista'));
      await tester.tap(find.text('Selecionar lista'));
      await tester.pump();

      expect(find.text('600 pacote(s) selecionado(s)'), findsOneWidget);

      final targetLabel = vehicle == VehicleType.car
          ? 'PORTA-MALAS'
          : 'MOCHILA DE ENTREGA';
      final targetZone = vehicle == VehicleType.car
          ? 'Porta-malas'
          : 'Mochila de entrega';
      await _ensureLoadItemVisible(tester, find.text(targetLabel));
      await tester.tap(find.text(targetLabel));
      await tester.pumpAndSettle();

      expect(state.packages, hasLength(600));
      expect(store.saves, 1, reason: 'Bulk assignment must persist once in $vehicle mode.');
      expect(
        state.packages.every((p) => p.physicalZone == targetZone),
        isTrue,
        reason: 'All 600 packages must be assigned in $vehicle mode.',
      );
      expect(find.text('600 de 600 pacotes posicionados'), findsOneWidget);
      expect(find.text('Ver todos (600)'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);

      await _ensureLoadItemVisible(tester, find.text('Ver todos (600)'));
      await tester.tap(find.text('Ver todos (600)'));
      await tester.pumpAndSettle();
      expect(find.text('P600'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });


  testWidgets('drag selection auto-scrolls through an 80-package load', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = AppState(
      store: _LoadStore(List.generate(80, (index) => _package(index + 1))),
    );
    await state.init();

    await tester.pumpWidget(MaterialApp(home: LoadScreen(state: state)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Selecionar vários'));
    await tester.pump();

    final selectedCount = await _dragSelectToBottom(
      tester,
      autoScrollDuration: const Duration(seconds: 8),
    );

    expect(selectedCount, 80);
    expect(tester.takeException(), isNull);
  });


  testWidgets('drag selection can bulk assign packages in a lazy 600-package load', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = _LoadStore([
      for (var index = 0; index < 600; index++) _package(index + 1),
      _package(601, physicalZone: 'Porta-malas').copyWith(
        status: DeliveryStatus.delivered,
      ),
    ]);
    final state = AppState(store: store);
    await state.init();

    await tester.pumpWidget(MaterialApp(home: LoadScreen(state: state)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Selecionar vários'));
    await tester.pump();

    final selectedCount = await _dragSelectToBottom(
      tester,
      autoScrollDuration: const Duration(seconds: 3),
    );

    expect(selectedCount, greaterThan(20));
    expect(selectedCount, lessThan(600));

    await _ensureLoadItemVisible(tester, find.text('PORTA-MALAS'));
    await tester.tap(find.text('PORTA-MALAS'));
    await tester.pumpAndSettle();

    expect(
      state.packages.where((package) => package.physicalZone == 'Porta-malas' &&
          package.status != DeliveryStatus.delivered),
      hasLength(selectedCount),
    );
    expect(
      state.packages.where((package) => package.physicalZone == null),
      hasLength(600 - selectedCount),
    );
    expect(state.packages, hasLength(601));
    expect(state.packages.last.status, DeliveryStatus.delivered);
    expect(state.packages.last.physicalZone, 'Porta-malas');
    expect(store.saves, 1);
    expect(find.text('0 pacote(s) selecionado(s)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });


  testWidgets('select all respects the active package search filter', (tester) async {
    final store = _LoadStore([
      _package(1),
      _package(2),
      _package(3),
    ]);
    final state = AppState(store: store);
    await state.init();

    await tester.pumpWidget(MaterialApp(home: LoadScreen(state: state)));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Selecionar vários'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Rua Teste, 2');
    await tester.pump();

    await _ensureLoadItemVisible(tester, find.text('Selecionar resultados'));
    await tester.tap(find.text('Selecionar resultados'));
    await tester.pump();

    expect(find.text('1 pacote(s) selecionado(s)'), findsOneWidget);

    await _ensureLoadItemVisible(tester, find.text('FRENTE E'));
    await tester.tap(find.text('FRENTE E'));
    await tester.pumpAndSettle();

    expect(state.packages[0].physicalZone, isNull);
    expect(state.packages[1].physicalZone, 'Frente esquerda');
    expect(state.packages[2].physicalZone, isNull);
  });


  testWidgets('search filters packages already placed in compartments', (tester) async {
    final state = AppState(store: _LoadStore([
      _package(1, physicalZone: 'Porta-malas'),
      _package(2, physicalZone: 'Porta-malas'),
      _package(3, physicalZone: 'Porta-malas'),
    ]));
    await state.init();

    await tester.pumpWidget(MaterialApp(home: LoadScreen(state: state)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Rua Teste, 2');
    await tester.pump();

    expect(find.text('P02'), findsOneWidget);
    expect(find.text('P01'), findsNothing);
    expect(find.text('P03'), findsNothing);
    expect(find.text('1/3'), findsOneWidget);

    await tester.tap(find.byTooltip('Limpar busca'));
    await tester.pump();

    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
    expect(find.text('P01'), findsOneWidget);
    expect(find.text('P02'), findsOneWidget);
    expect(find.text('P03'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });
  
  testWidgets('search matches city names without accents', (tester) async {
    final state = AppState(store: _LoadStore([_package(1), _package(2)]));
    await state.init();

    await tester.pumpWidget(MaterialApp(home: LoadScreen(state: state)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Sao Paulo');
    await tester.pumpAndSettle();

    final scrollable = find.descendant(
      of: find.byType(CustomScrollView),
      matching: find.byType(Scrollable),
    ).first;
    await tester.scrollUntilVisible(find.text('Pacote 01'), 250, scrollable: scrollable);
    expect(find.text('Pacote 01'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Pacote 02'), 250, scrollable: scrollable);
    expect(find.text('Pacote 02'), findsOneWidget);
    expect(
      find.text('Nenhum pacote encontrado para essa busca.'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('large compartments collapse after eight package chips', (tester) async {
    final state = AppState(store: _LoadStore(
      List.generate(12, (index) => _package(index + 1, physicalZone: 'Porta-malas')),
    ));
    await state.init();

    await tester.pumpWidget(MaterialApp(home: LoadScreen(state: state)));
    await tester.pumpAndSettle();

    expect(find.text('P08'), findsOneWidget);
    expect(find.text('P09'), findsNothing);
    expect(find.text('Ver todos (12)'), findsOneWidget);

    await _ensureLoadItemVisible(tester, find.text('Ver todos (12)'));
    await tester.tap(find.text('Ver todos (12)'));
    await tester.pumpAndSettle();

    expect(find.text('P12'), findsOneWidget);
    expect(find.text('Mostrar menos'), findsOneWidget);

    await _ensureLoadItemVisible(tester, find.text('Mostrar menos'));
    await tester.tap(find.text('Mostrar menos'));
    await tester.pumpAndSettle();

    expect(find.text('P12'), findsNothing);
    expect(tester.takeException(), isNull);
  });


  testWidgets('a positioned package can be moved directly between compartments', (tester) async {
    final state = AppState(store: _LoadStore([
      _package(1, physicalZone: 'Porta-malas'),
      _package(2, physicalZone: 'Frente direita'),
    ]));
    await state.init();

    await tester.pumpWidget(MaterialApp(home: LoadScreen(state: state)));
    await tester.pumpAndSettle();

    await _ensureLoadItemVisible(tester, find.text('P01'));
    await tester.tap(find.text('P01'));
    await tester.pump();

    expect(find.textContaining('Pacote 01 selecionado'), findsOneWidget);

    await _ensureLoadItemVisible(tester, find.text('FRENTE E'));
    await tester.tap(find.text('FRENTE E'));
    await tester.pumpAndSettle();

    expect(state.packages[0].physicalZone, 'Frente esquerda');
    expect(state.packages[1].physicalZone, 'Frente direita');
    expect(find.text('P01'), findsOneWidget);
  });


  testWidgets('moto can move a positioned package between compartments', (tester) async {
    SharedPreferences.setMockInitialValues({'load_vehicle_type':'motorcycle'});
    final state = AppState(store: _LoadStore([
      _package(7, physicalZone: 'Baú traseiro'),
    ]));
    await state.init();

    await tester.pumpWidget(MaterialApp(home: LoadScreen(state: state)));
    await tester.pumpAndSettle();

    await _ensureLoadItemVisible(tester, find.text('P07'));
    await tester.tap(find.text('P07'));
    await tester.pump();
    expect(find.textContaining('Pacote 07 selecionado'), findsOneWidget);

    await _ensureLoadItemVisible(tester, find.text('MOCHILA DE ENTREGA'));
    await tester.tap(find.text('MOCHILA DE ENTREGA'));
    await tester.pumpAndSettle();

    expect(state.packages.single.physicalZone, 'Mochila de entrega');
    expect(find.text('P07'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('large motorcycle compartments collapse after eight package chips', (tester) async {
    SharedPreferences.setMockInitialValues({'load_vehicle_type':'motorcycle'});
    final state = AppState(store: _LoadStore(
      List.generate(12, (index) => _package(index + 1, physicalZone: 'Baú traseiro')),
    ));
    await state.init();

    await tester.pumpWidget(MaterialApp(home: LoadScreen(state: state)));
    await tester.pumpAndSettle();

    expect(find.text('P08'), findsOneWidget);
    expect(find.text('P09'), findsNothing);
    expect(find.text('Ver todos (12)'), findsOneWidget);

    await _ensureLoadItemVisible(tester, find.text('Ver todos (12)'));
    await tester.tap(find.text('Ver todos (12)'));
    await tester.pumpAndSettle();

    expect(find.text('P12'), findsOneWidget);
    expect(find.text('Mostrar menos'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching vehicle clears stale cargo search and preserves delivered history', (tester) async {
    final state = AppState(store: _LoadStore([
      _package(1, physicalZone: 'Porta-malas'),
      _package(2, physicalZone: 'Porta-malas').copyWith(
        status: DeliveryStatus.delivered,
      ),
    ]));
    await state.init();

    await tester.pumpWidget(MaterialApp(home: LoadScreen(state: state)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Rua Teste, 1');
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'Rua Teste, 1');

    await tester.tap(find.byTooltip('Veículo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('🏍️ Moto'));
    await tester.pumpAndSettle();

    expect(state.vehicleType, VehicleType.motorcycle);
    expect(state.packages[0].physicalZone, isNull);
    expect(state.packages[1].physicalZone, 'Porta-malas');
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
    expect(find.text('Organizar a moto'), findsOneWidget);
    await _ensureLoadItemVisible(tester, find.text('Pacote 01'));
    expect(find.text('Pacote 01'), findsOneWidget);
    expect(find.text('P01'), findsNothing);
    expect(tester.takeException(), isNull);
  });


  testWidgets('select all only selects unassigned packages for each vehicle', (tester) async {
    for (final vehicle in [VehicleType.car, VehicleType.motorcycle]) {
      SharedPreferences.setMockInitialValues(
        vehicle == VehicleType.motorcycle
            ? {'load_vehicle_type': 'motorcycle'}
            : {},
      );
      final assignedZone = vehicle == VehicleType.motorcycle
          ? 'Baú traseiro'
          : 'Porta-malas';
      final targetZone = vehicle == VehicleType.motorcycle
          ? 'MOCHILA DE ENTREGA'
          : 'FRENTE E';
      final targetPhysicalZone = vehicle == VehicleType.motorcycle
          ? 'Mochila de entrega'
          : 'Frente esquerda';
      final state = AppState(store: _LoadStore([
        _package(1, physicalZone: assignedZone),
        _package(2),
        _package(3),
      ]));
      await state.init();

      await tester.pumpWidget(MaterialApp(home: LoadScreen(state: state)));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Selecionar vários'));
      await tester.pump();

      await _ensureLoadItemVisible(tester, find.text('Selecionar lista'));
      await tester.tap(find.text('Selecionar lista'));
      await tester.pump();

      expect(
        find.text('2 pacote(s) selecionado(s)'),
        findsOneWidget,
        reason: 'Select all should include only visible unassigned packages ($vehicle).',
      );

      await _ensureLoadItemVisible(tester, find.text(targetZone));
      await tester.tap(find.text(targetZone));
      await tester.pumpAndSettle();

      expect(
        state.packages[0].physicalZone,
        assignedZone,
        reason: 'A package already assigned to a compartment must not be moved ($vehicle).',
      );
      expect(state.packages[1].physicalZone, targetPhysicalZone);
      expect(state.packages[2].physicalZone, targetPhysicalZone);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });


  testWidgets('configuring car and motorcycle compartments clears only active packages in removed zones', (tester) async {
    for (final vehicle in [VehicleType.car, VehicleType.motorcycle]) {
      final zone = vehicle == VehicleType.car ? 'Porta-malas' : 'Baú traseiro';
      SharedPreferences.setMockInitialValues(
        vehicle == VehicleType.motorcycle
            ? {'load_vehicle_type': 'motorcycle'}
            : {'load_vehicle_type': 'car'},
      );
      final active = _package(1, physicalZone: zone);
      final delivered = _package(2, physicalZone: zone).copyWith(
        status: DeliveryStatus.delivered,
      );
      final state = AppState(store: _LoadStore([active, delivered]));
      await state.init();

      await tester.pumpWidget(MaterialApp(home: LoadScreen(state: state)));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Configurar compartimentos'));
      await tester.pumpAndSettle();
      expect(
        find.text(vehicle == VehicleType.car
            ? 'Compartimentos do carro'
            : 'Compartimentos da moto'),
        findsOneWidget,
      );

      final zoneTitle = find.text(zone);
      final zoneTile = find.ancestor(
        of: zoneTitle,
        matching: find.byType(CheckboxListTile),
      );
      expect(zoneTile, findsOneWidget);
      expect(tester.widget<CheckboxListTile>(zoneTile).value, isTrue);
      await tester.tap(zoneTitle);
      await tester.pump();

      final save = find.widgetWithText(FilledButton, 'Salvar');
      expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
      await tester.tap(save);
      await tester.pumpAndSettle();

      expect(state.activePhysicalZones, isNot(contains(zone)));
      expect(state.packages.first.physicalZone, isNull);
      expect(
        state.packages.last.physicalZone,
        zone,
        reason: 'Delivered package history must remain unchanged ($vehicle).',
      );
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });

  testWidgets('compartment settings cannot be saved with every area disabled', (tester) async {
    SharedPreferences.setMockInitialValues({'load_vehicle_type': 'car'});
    final state = AppState(store: _LoadStore([_package(1)]));
    await state.init();

    await tester.pumpWidget(MaterialApp(home: LoadScreen(state: state)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Configurar compartimentos'));
    await tester.pumpAndSettle();

    for (final zone in AppState.carPhysicalZones) {
      await tester.tap(find.text(zone));
      await tester.pump();
    }

    final save = find.widgetWithText(FilledButton, 'Salvar');
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });


  testWidgets('car package row separates load status and address with a line break', (tester) async {
    // Keep this UI assertion independent from vehicle preferences written by
    // previous tests in the same SharedPreferences test environment.
    SharedPreferences.setMockInitialValues({'load_vehicle_type': 'car'});
    final state = AppState(store: _LoadStore([_package(1)]));
    await state.init();

    await tester.pumpWidget(MaterialApp(home: LoadScreen(state: state)));
    await tester.pumpAndSettle();

    // The organizer uses a lazy SliverList; scroll the package row into the
    // viewport before asserting its subtitle is built.
    await _ensureLoadItemVisible(tester, find.text('Pacote 01'));
    expect(find.text('Sem posição no carro\nRua Teste, 1, São Paulo, SP'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });



  testWidgets('search accepts the visible P-number code for assigned and unassigned packages',
      (tester) async {
    final unassignedState = AppState(
      store: _LoadStore([_package(7)]),
    );
    await unassignedState.init();

    await tester.pumpWidget(
      MaterialApp(home: LoadScreen(state: unassignedState)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Selecionar vários'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'P07');
    await tester.pumpAndSettle();
    await _ensureLoadItemVisible(tester, find.text('Selecionar resultados'));
    await tester.tap(find.text('Selecionar resultados'));
    await tester.pump();

    expect(find.text('1 pacote(s) selecionado(s)'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    SharedPreferences.setMockInitialValues({});
    final assignedState = AppState(
      store: _LoadStore([
        _package(17, physicalZone: 'Porta-malas'),
      ]),
    );
    await assignedState.init();

    await tester.pumpWidget(
      MaterialApp(home: LoadScreen(state: assignedState)),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'P17');
    await tester.pumpAndSettle();

    expect(find.widgetWithText(InputChip, 'P17'), findsOneWidget);
    expect(find.text('1/1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('starting deliveries clears the temporary load selection',
      (tester) async {
    tester.view.physicalSize = const Size(400, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = AppState(
      store: _LoadStore([
        _package(1, physicalZone: 'Porta-malas'),
      ]),
    );
    await state.init();

    await tester.pumpWidget(MaterialApp(home: LoadScreen(state: state)));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Selecionar vários'));
    await tester.pump();
    await _ensureLoadItemVisible(tester, find.text('P01'));
    await tester.tap(find.text('P01'));
    await tester.pump();

    expect(find.text('1 pacote(s) selecionado(s)'), findsOneWidget);

    await tester.tap(find.text('INICIAR ENTREGAS'));
    await tester.pumpAndSettle();
    expect(find.text('PEGUE ESTE PACOTE'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('1 pacote(s) selecionado(s)'), findsNothing);
    expect(find.byIcon(Icons.library_add_check), findsOneWidget);
    expect(tester.takeException(), isNull);
  });


  testWidgets('bulk selection can be cleared with one tap', (tester) async {
    final state = AppState(
      store: _LoadStore(
        List.generate(3, (index) => _package(index + 1)),
      ),
    );
    await state.init();

    await tester.pumpWidget(MaterialApp(home: LoadScreen(state: state)));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Selecionar vários'));
    await tester.pump();
    await _ensureLoadItemVisible(tester, find.text('Selecionar lista'));
    await tester.tap(find.text('Selecionar lista'));
    await tester.pump();

    expect(find.text('3 pacote(s) selecionado(s)'), findsOneWidget);
    expect(find.text('Desmarcar lista'), findsOneWidget);

    await tester.tap(find.text('Desmarcar lista'));
    await tester.pump();

    expect(find.text('0 pacote(s) selecionado(s)'), findsOneWidget);
    expect(find.text('Selecionar lista'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });


  testWidgets('deselecting the unassigned list keeps assigned compartment selections',
      (tester) async {
    final state = AppState(
      store: _LoadStore([
        _package(1, physicalZone: 'Porta-malas'),
        _package(2),
        _package(3),
      ]),
    );
    await state.init();

    await tester.pumpWidget(MaterialApp(home: LoadScreen(state: state)));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Selecionar vários'));
    await tester.pump();

    await _ensureLoadItemVisible(tester, find.text('P01'));
    await tester.tap(find.widgetWithText(InputChip, 'P01'));
    await tester.pump();
    expect(find.text('1 pacote(s) selecionado(s)'), findsOneWidget);

    await _ensureLoadItemVisible(tester, find.text('Selecionar lista'));
    await tester.tap(find.text('Selecionar lista'));
    await tester.pump();
    expect(find.text('3 pacote(s) selecionado(s)'), findsOneWidget);
    expect(find.text('Desmarcar lista'), findsOneWidget);

    await tester.tap(find.text('Desmarcar lista'));
    await tester.pump();

    expect(find.text('1 pacote(s) selecionado(s)'), findsOneWidget);
    expect(find.text('Selecionar lista'), findsOneWidget);
    final assignedChip = tester.widget<InputChip>(
      find.widgetWithText(InputChip, 'P01'),
    );
    expect(assignedChip.selected, isTrue);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('search does not report empty when a matching package is already assigned',
      (tester) async {
    final state = AppState(
      store: _LoadStore([
        _package(1, physicalZone: 'Porta-malas'),
        _package(2),
      ]),
    );
    await state.init();

    await tester.pumpWidget(MaterialApp(home: LoadScreen(state: state)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Rua Teste, 1');
    await tester.pumpAndSettle();

    expect(find.text('P01'), findsOneWidget);
    expect(
      find.text('Nenhum pacote encontrado para essa busca.'),
      findsNothing,
    );
    expect(find.text('Sem resultados'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });


  testWidgets('car compartment order stays physically correct when preferences are reversed',
      (tester) async {
    final state = AppState(
      store: _LoadStore([_package(1)]),
    );
    await state.init();
    await state.setActivePhysicalZones([
      'Frente direita',
      'Frente esquerda',
      'Traseira direita',
      'Traseira esquerda',
    ]);

    expect(
      state.activePhysicalZones,
      [
        'Frente esquerda',
        'Frente direita',
        'Traseira esquerda',
        'Traseira direita',
      ],
    );

    await tester.pumpWidget(MaterialApp(home: LoadScreen(state: state)));
    await tester.pumpAndSettle();

    final frontLeft = tester.getTopLeft(find.text('FRENTE E'));
    final frontRight = tester.getTopLeft(find.text('FRENTE D'));
    final rearLeft = tester.getTopLeft(find.text('TRASEIRA E'));
    final rearRight = tester.getTopLeft(find.text('TRASEIRA D'));

    expect(frontLeft.dx, lessThan(frontRight.dx));
    expect(rearLeft.dx, lessThan(rearRight.dx));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'car diagram keeps enabled compartments on their physical sides when opposite sides are disabled',
    (tester) async {
      tester.view.physicalSize = const Size(400, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final state = AppState(store: _LoadStore([_package(1)]));
      await state.init();
      await state.setActivePhysicalZones([
        'Frente direita',
        'Traseira esquerda',
      ]);

      await tester.pumpWidget(MaterialApp(home: LoadScreen(state: state)));
      await tester.pumpAndSettle();

      final frontRightCenter = tester.getCenter(find.text('FRENTE D'));
      final rearLeftCenter = tester.getCenter(find.text('TRASEIRA E'));

      expect(
        frontRightCenter.dx,
        greaterThan(200),
        reason: 'The only enabled front seat must remain on the right side.',
      );
      expect(
        rearLeftCenter.dx,
        lessThan(200),
        reason: 'The only enabled rear seat must remain on the left side.',
      );
      expect(find.text('FRENTE E'), findsNothing);
      expect(find.text('TRASEIRA D'), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('filtered bulk selection preserves packages selected outside the search',
      (tester) async {
    tester.view.physicalSize = const Size(400, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = AppState(
      store: _LoadStore([
        _package(1),
        _package(2),
        _package(3),
      ]),
    );
    await state.init();

    await tester.pumpWidget(MaterialApp(home: LoadScreen(state: state)));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Selecionar vários'));
    await tester.pump();

    await _ensureLoadItemVisible(tester, find.text('Pacote 01'));
    await tester.tap(find.text('Pacote 01'));
    await tester.pump();
    expect(find.text('1 pacote(s) selecionado(s)'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Rua Teste, 2');
    await tester.pumpAndSettle();
    expect(find.text('Pacote 01'), findsNothing);
    expect(find.text('1 pacote(s) selecionado(s)'), findsOneWidget);

    await _ensureLoadItemVisible(tester, find.text('Selecionar resultados'));
    await tester.tap(find.text('Selecionar resultados'));
    await tester.pump();
    expect(find.text('2 pacote(s) selecionado(s)'), findsOneWidget);

    await tester.tap(find.text('Desmarcar resultados'));
    await tester.pump();
    expect(find.text('1 pacote(s) selecionado(s)'), findsOneWidget);

    await _ensureLoadItemVisible(tester, find.byTooltip('Limpar busca'));
    await tester.tap(find.byTooltip('Limpar busca'));
    await tester.pumpAndSettle();
    await _ensureLoadItemVisible(tester, find.text('Pacote 01'));

    final retainedRow = tester.widget<ListTile>(
      find.ancestor(
        of: find.text('Pacote 01'),
        matching: find.byType(ListTile),
      ).first,
    );
    expect(retainedRow.selected, isTrue);

    await _ensureLoadItemVisible(tester, find.text('PORTA-MALAS'));
    await tester.tap(find.text('PORTA-MALAS'));
    await tester.pumpAndSettle();

    expect(state.packages[0].physicalZone, 'Porta-malas');
    expect(state.packages[1].physicalZone, isNull);
    expect(state.packages[2].physicalZone, isNull);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });


  testWidgets('package search accepts code with or without leading zero and separators',
      (tester) async {
    final state = AppState(store: _LoadStore([_package(7), _package(17)]));
    await state.init();

    await tester.pumpWidget(MaterialApp(home: LoadScreen(state: state)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'P7');
    await tester.pumpAndSettle();
    await _ensureLoadItemVisible(tester, find.text('Pacote 07'));
    expect(find.text('Pacote 07'), findsOneWidget);
    expect(find.text('Pacote 17'), findsNothing);

    await tester.enterText(find.byType(TextField), 'P07');
    await tester.pumpAndSettle();
    await _ensureLoadItemVisible(tester, find.text('Pacote 07'));
    expect(find.text('Pacote 07'), findsOneWidget);
    expect(find.text('Pacote 17'), findsNothing);

    await tester.enterText(find.byType(TextField), 'p-07');
    await tester.pumpAndSettle();
    await _ensureLoadItemVisible(tester, find.text('Pacote 07'));
    expect(find.text('Pacote 07'), findsOneWidget);
    expect(find.text('Pacote 17'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });


  testWidgets('motorcycle side bags stay on their physical sides when the opposite bag is disabled',
      (tester) async {
    tester.view.physicalSize = const Size(400, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final side in [
      ('Bolsa lateral esquerda', 'BOLSA ESQUERDA', 'BOLSA DIREITA', true),
      ('Bolsa lateral direita', 'BOLSA DIREITA', 'BOLSA ESQUERDA', false),
    ]) {
      final state = AppState(store: _LoadStore([_package(1)]));
      await state.init();
      await state.setVehicleType(VehicleType.motorcycle);
      await state.setActivePhysicalZones([side.$1, 'Baú traseiro']);

      await tester.pumpWidget(MaterialApp(home: LoadScreen(state: state)));
      await tester.pumpAndSettle();

      final motorcycleCenter = tester.getCenter(find.text('MOTO'));
      final enabledBagCenter = tester.getCenter(find.text(side.$2));
      expect(find.text(side.$3), findsNothing);
      if (side.$4) {
        expect(enabledBagCenter.dx, lessThan(motorcycleCenter.dx));
      } else {
        expect(enabledBagCenter.dx, greaterThan(motorcycleCenter.dx));
      }
      expect(find.text('BAÚ TRASEIRO'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });


  testWidgets('car and motorcycle drag selection can bulk assign packages in a lazy 600-package load', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final vehicle in VehicleType.values) {
      final isMotorcycle = vehicle == VehicleType.motorcycle;
      final historicalZone = isMotorcycle ? 'Baú traseiro' : 'Porta-malas';
      final targetZone = isMotorcycle ? 'Mochila de entrega' : 'Frente esquerda';
      final targetLabel = isMotorcycle ? 'MOCHILA DE ENTREGA' : 'FRENTE E';

      SharedPreferences.setMockInitialValues(
        isMotorcycle ? {'load_vehicle_type': 'motorcycle'} : {},
      );
      final store = _LoadStore([
        for (var index = 0; index < 600; index++) _package(index + 1),
        _package(601, physicalZone: historicalZone).copyWith(
          status: DeliveryStatus.delivered,
        ),
      ]);
      final state = AppState(store: store);
      await state.init();

      await tester.pumpWidget(MaterialApp(home: LoadScreen(state: state)));
      await tester.pumpAndSettle();
      expect(
        find.text(isMotorcycle ? 'Organizar a moto' : 'Organizar o carro'),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('Selecionar vários'));
      await tester.pump();

      final selectedCount = await _dragSelectToBottom(
        tester,
        autoScrollDuration: const Duration(seconds: 3),
      );

      expect(selectedCount, greaterThan(20), reason: 'Selection should auto-scroll in $vehicle mode.');
      expect(selectedCount, lessThan(600));

      await _ensureLoadItemVisible(tester, find.text(targetLabel));
      await tester.tap(find.text(targetLabel));
      await tester.pumpAndSettle();

      expect(
        state.packages.where((package) =>
            package.status != DeliveryStatus.delivered &&
            package.physicalZone == targetZone),
        hasLength(selectedCount),
      );
      expect(
        state.packages.where((package) =>
            package.status != DeliveryStatus.delivered &&
            package.physicalZone == null),
        hasLength(600 - selectedCount),
      );
      expect(state.packages, hasLength(601));
      expect(state.packages.last.status, DeliveryStatus.delivered);
      expect(state.packages.last.physicalZone, historicalZone);
      expect(store.saves, 1);
      expect(find.text('0 pacote(s) selecionado(s)'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });


  testWidgets(
    'turning off multi-select cancels an active drag auto-scroll',
    (tester) async {
      tester.view.physicalSize = const Size(400, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final store = _LoadStore(
        List.generate(80, (index) => _package(index + 1)),
      );
      final state = AppState(store: store);
      await state.init();

      await tester.pumpWidget(MaterialApp(home: LoadScreen(state: state)));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Selecionar vários'));
      await tester.pump();

      await _ensureLoadItemVisible(tester, find.text('Pacote 01'));
      final first = tester.getCenter(find.text('Pacote 01'));
      final viewport = tester.getRect(find.byType(CustomScrollView));
      final gesture = await tester.startGesture(first, pointer: 1);
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('1 pacote(s) selecionado(s)'), findsOneWidget);

      await gesture.moveTo(
        Offset(first.dx, viewport.bottom - 30),
        timeStamp: const Duration(milliseconds: 700),
      );
      await tester.pump(const Duration(milliseconds: 160));

      final scrollable = find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(Scrollable),
      ).first;
      final position = tester.state<ScrollableState>(scrollable).position;
      final offsetBeforeToggle = position.pixels;
      expect(
        offsetBeforeToggle,
        greaterThan(0),
        reason: 'The test must start with the drag auto-scroll active.',
      );

      // A second finger can reach the toolbar while the first finger keeps
      // dragging. Disabling multi-select must stop the timer immediately.
      await tester.tapAt(
        tester.getCenter(find.byTooltip('Selecionar vários')),
        pointer: 2,
      );
      await tester.pump();
      expect(find.text('1 pacote(s) selecionado(s)'), findsNothing);

      final offsetAfterToggle = position.pixels;
      await tester.pump(const Duration(milliseconds: 240));
      expect(
        position.pixels,
        offsetAfterToggle,
        reason: 'Auto-scroll must stop as soon as multi-select is disabled.',
      );

      await gesture.up();
      await tester.pumpAndSettle();
      expect(position.pixels, offsetAfterToggle);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );


  testWidgets(
    'lifting an unrelated second pointer does not cancel an active drag selection',
    (tester) async {
      tester.view.physicalSize = const Size(400, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final state = AppState(
        store: _LoadStore(List.generate(80, (index) => _package(index + 1))),
      );
      await state.init();

      await tester.pumpWidget(MaterialApp(home: LoadScreen(state: state)));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Selecionar vários'));
      await tester.pump();

      await _ensureLoadItemVisible(tester, find.text('Pacote 01'));
      final first = tester.getCenter(find.text('Pacote 01'));
      final viewport = tester.getRect(find.byType(CustomScrollView));
      final drag = await tester.startGesture(first, pointer: 1);
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('1 pacote(s) selecionado(s)'), findsOneWidget);

      await drag.moveTo(
        Offset(first.dx, viewport.bottom - 30),
        timeStamp: const Duration(milliseconds: 700),
      );
      await tester.pump(const Duration(milliseconds: 160));

      final scrollable = find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(Scrollable),
      ).first;
      final position = tester.state<ScrollableState>(scrollable).position;
      final offsetBeforeSecondPointer = position.pixels;
      expect(
        offsetBeforeSecondPointer,
        greaterThan(0),
        reason: 'The primary drag must have activated auto-scroll.',
      );

      // A second finger briefly touches blank space inside the same list.
      // Its pointer-up must not terminate the first finger's active drag.
      final secondary = Offset(viewport.left + 4, viewport.top + 4);
      final secondPointer = await tester.startGesture(secondary, pointer: 2);
      await tester.pump(const Duration(milliseconds: 40));
      await secondPointer.moveTo(
        Offset(secondary.dx + 1, secondary.dy + 1),
        timeStamp: const Duration(milliseconds: 816),
      );
      await tester.pump(const Duration(milliseconds: 16));
      await secondPointer.up();
      await tester.pump();

      final offsetAfterSecondPointer = position.pixels;
      await tester.pump(const Duration(milliseconds: 240));
      expect(
        position.pixels,
        greaterThan(offsetAfterSecondPointer),
        reason: 'The primary drag auto-scroll must continue after an unrelated pointer lifts.',
      );
      expect(find.textContaining('pacote(s) selecionado(s)'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await drag.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );


  testWidgets(
    'a second long press cannot replace the active drag selection owner',
    (tester) async {
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final state = AppState(
        store: _LoadStore(List.generate(10, (index) => _package(index + 1))),
      );
      await state.init();

      await tester.pumpWidget(MaterialApp(home: LoadScreen(state: state)));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Selecionar vários'));
      await tester.pump();

      final first = tester.getCenter(find.text('Pacote 01'));
      final primary = await tester.startGesture(
        first,
        pointer: 1,
        timeStamp: const Duration(milliseconds: 0),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('1 pacote(s) selecionado(s)'), findsOneWidget);

      final second = tester.getCenter(find.text('Pacote 02'));
      await primary.moveTo(
        second,
        timeStamp: const Duration(milliseconds: 700),
      );
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.text('2 pacote(s) selecionado(s)'), findsOneWidget);

      // This second pointer long-presses a different package while the
      // primary pointer still owns the active selection session.
      final unrelated = tester.getCenter(find.text('Pacote 04'));
      final secondary = await tester.startGesture(
        unrelated,
        pointer: 2,
        timeStamp: const Duration(milliseconds: 800),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        find.text('2 pacote(s) selecionado(s)'),
        findsOneWidget,
        reason: 'A secondary long press must not add a package or reset the anchor.',
      );

      final third = tester.getCenter(find.text('Pacote 03'));
      await primary.moveTo(
        third,
        timeStamp: const Duration(milliseconds: 1500),
      );
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.text('3 pacote(s) selecionado(s)'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await secondary.up(timeStamp: const Duration(milliseconds: 1516));
      await primary.up(timeStamp: const Duration(milliseconds: 1532));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

}
