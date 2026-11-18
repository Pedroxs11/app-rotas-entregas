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

    await tester.ensureVisible(find.text('Pacote 01'));
    await tester.tap(find.text('Pacote 01'));
    await tester.pump();
    expect(find.textContaining('Pacote 01 selecionado'),findsOneWidget);

    await tester.ensureVisible(find.text('FRENTE E'));
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
    await tester.ensureVisible(find.text('Pacote 01'));
    await tester.tap(find.text('Pacote 01'));
    await tester.ensureVisible(find.text('Pacote 02'));
    await tester.tap(find.text('Pacote 02'));
    await tester.pump();

    await tester.ensureVisible(find.text('FRENTE E'));
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

    await tester.ensureVisible(find.text('Pacote 07'));
    await tester.tap(find.text('Pacote 07'));
    await tester.pump();
    await tester.ensureVisible(find.text('BAÚ TRASEIRO'));
    await tester.tap(find.text('BAÚ TRASEIRO'));
    await tester.pumpAndSettle();

    expect(state.packages.single.physicalZone,'Baú traseiro');
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,isNotNull);
    expect(find.text('P07 • Baú traseiro'),findsOneWidget);
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
    await tester.ensureVisible(find.text('Pacote 07'));
    await tester.tap(find.text('Pacote 07'));
    await tester.ensureVisible(find.text('Pacote 12'));
    await tester.tap(find.text('Pacote 12'));
    await tester.pump();

    expect(find.text('2 pacote(s) selecionado(s)'), findsOneWidget);
    await tester.ensureVisible(find.text('BAÚ TRASEIRO'));
    await tester.tap(find.text('BAÚ TRASEIRO'));
    await tester.pumpAndSettle();

    expect(state.packages[0].physicalZone, 'Baú traseiro');
    expect(state.packages[1].physicalZone, 'Baú traseiro');
    expect(state.packages[2].physicalZone, isNull);
    expect(find.text('P07 • Baú traseiro'), findsOneWidget);
    expect(find.text('P12 • Baú traseiro'), findsOneWidget);
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

    await tester.ensureVisible(find.text('P01'));
    await tester.tap(find.text('P01'));
    await tester.pump();
    final selectedChip=tester.widget<InputChip>(
      find.ancestor(of:find.text('P01'),matching:find.byType(InputChip)),
    );
    expect(selectedChip.selected,isTrue);

    await tester.ensureVisible(find.text('Pacote 02'));
    await tester.tap(find.text('Pacote 02'));
    await tester.pump();

    await tester.ensureVisible(find.text('FRENTE E'));
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
    await tester.ensureVisible(find.text('Selecionar todos'));
    await tester.tap(find.text('Selecionar todos'));
    await tester.pump();

    expect(find.text('3 pacote(s) selecionado(s)'),findsOneWidget);

    await tester.ensureVisible(find.text('FRENTE D'));
    await tester.tap(find.text('FRENTE D'));
    await tester.pumpAndSettle();

    expect(state.packages.every((p)=>p.physicalZone=='Frente direita'),isTrue);
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

}
