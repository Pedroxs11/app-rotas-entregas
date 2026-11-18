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
  @override Future<void> clear() async {}
  @override Future<List<DeliveryPackage>> load() async => [...items];
  @override Future<bool> loadRouteOptimized() async => true;
  @override Future<void> save(List<DeliveryPackage> value,{bool? routeOptimized}) async {
    items=[...value];
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
  final viewportFinder = find.byType(CustomScrollView);

  await tester.scrollUntilVisible(
    finder,
    250,
    scrollable: scrollable,
  );

  for (var attempt = 0; attempt < 20; attempt++) {
    if (finder.evaluate().isEmpty) {
      await tester.drag(scrollable, const Offset(0, -250));
    } else {
      final target = tester.getRect(finder.first);
      final viewport = tester.getRect(viewportFinder);
      if (target.top >= viewport.top && target.bottom <= viewport.bottom) {
        return;
      }
      final delta = target.top < viewport.top ? 250.0 : -250.0;
      await tester.drag(scrollable, Offset(0, delta));
    }
    await tester.pumpAndSettle();
  }

  expect(finder, findsWidgets);
  final target = tester.getRect(finder.first);
  final viewport = tester.getRect(viewportFinder);
  expect(target.top, greaterThanOrEqualTo(viewport.top));
  expect(target.bottom, lessThanOrEqualTo(viewport.bottom));
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
    expect(find.text('07'),findsWidgets);
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

  testWidgets('select all includes packages already positioned in a compartment', (tester) async {
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
    await _ensureLoadItemVisible(tester, find.text('Selecionar todos'));
    await tester.tap(find.text('Selecionar todos'));
    await tester.pump();

    expect(find.text('3 pacote(s) selecionado(s)'),findsOneWidget);

    await _ensureLoadItemVisible(tester, find.text('FRENTE D'));
    await tester.tap(find.text('FRENTE D'));
    await tester.pumpAndSettle();

    expect(state.packages.every((p)=>p.physicalZone=='Frente direita'),isTrue);
  });


  testWidgets('drag selection auto-scrolls through packages on a phone-sized screen', (tester) async {
    tester.view.physicalSize = const Size(400, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = AppState(
      store: _LoadStore(List.generate(60, (index) => _package(index + 1))),
    );
    await state.init();

    await tester.pumpWidget(MaterialApp(home: LoadScreen(state: state)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Selecionar vários'));
    await tester.pump();

    await _ensureLoadItemVisible(tester, find.text('Pacote 01'));
    final first = tester.getCenter(find.text('Pacote 01'));
    final viewport = tester.getRect(find.byType(CustomScrollView));
    final bottomEdge = Offset(viewport.center.dx, viewport.bottom - 8);
    final gesture = await tester.startGesture(first);
    await gesture.moveTo(bottomEdge, timeStamp: const Duration(milliseconds: 100));
    for (var frame = 0; frame < 60; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    final selectionLabel = tester.widget<Text>(
      find.textContaining('pacote(s) selecionado(s)'),
    );
    final selectedCount = int.parse(selectionLabel.data!.split(' ').first);
    expect(selectedCount, greaterThan(10));
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

      await tester.scrollUntilVisible(
        find.text('Pacote 600'),
        1000,
        scrollable: find.descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(Scrollable),
        ).first,
        maxScrolls: 100,
      );
      await tester.pumpAndSettle();

      expect(find.text('Pacote 600'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });


  testWidgets('drag selection crosses an 80-package load without skipping cards', (tester) async {
    tester.view.physicalSize = const Size(400, 10000);
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

    final first = tester.getCenter(find.text('Pacote 01'));
    final last = tester.getCenter(find.text('Pacote 80'));
    final gesture = await tester.startGesture(first);
    await gesture.moveTo(last);
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('80 pacote(s) selecionado(s)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });


  testWidgets('drag selection crosses a 600-package load without skipping cards', (tester) async {
    tester.view.physicalSize = const Size(400, 60000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = AppState(
      store: _LoadStore(List.generate(600, (index) => _package(index + 1))),
    );
    await state.init();

    await tester.pumpWidget(MaterialApp(home: LoadScreen(state: state)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Selecionar vários'));
    await tester.pump();

    final first = tester.getCenter(find.text('Pacote 01'));
    final last = tester.getCenter(find.text('Pacote 600'));
    final gesture = await tester.startGesture(first);
    await gesture.moveTo(last);
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('600 pacote(s) selecionado(s)'), findsOneWidget);
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

    await _ensureLoadItemVisible(tester, find.text('Selecionar todos'));
    await tester.tap(find.text('Selecionar todos'));
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
    expect(find.text('Pacote 01'), findsOneWidget);
    expect(find.text('P01'), findsNothing);
    expect(tester.takeException(), isNull);
  });

}
