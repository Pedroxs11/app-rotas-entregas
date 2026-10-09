import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

DeliveryPackage _package(int n)=>DeliveryPackage(
  id:'p$n',
  scanNumber:n,
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
    expect(find.textContaining('Pacote P01 selecionado'),findsOneWidget);

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
    state.setVehicleType(VehicleType.motorcycle);

    await tester.pumpWidget(MaterialApp(home:LoadScreen(state:state)));
    await tester.pumpAndSettle();

    expect(find.text('MODO MOTO'),findsOneWidget);
    expect(find.text('Sem quadrantes. Cada pacote será identificado pelo número.'),findsOneWidget);
    expect(find.text('FRENTE E'),findsNothing);
    expect(find.text('TRASEIRA E'),findsNothing);
    expect(find.text('PORTA-MALAS'),findsNothing);
    expect(find.text('07'),findsWidgets);
    expect(find.text('12'),findsWidgets);
    expect(find.text('INICIAR ENTREGAS'),findsOneWidget);
    expect(state.packages.every((p)=>p.physicalZone==null),isTrue);

    final progress=tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    expect(progress.value,1.0);
    expect(find.text('Todos os pacotes estão posicionados. Confira o carro antes de sair.'),findsNothing);
  });
}
