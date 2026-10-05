import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/services/package_store.dart';
import 'package:flutter_test/flutter_test.dart';

class GuardStore implements PackageStore {
  GuardStore(this.packages,{this.optimized=false});
  List<DeliveryPackage> packages;
  bool optimized;
  int saves=0;
  @override Future<List<DeliveryPackage>> load()async=>[...packages];
  @override Future<bool> loadRouteOptimized()async=>optimized;
  @override Future<void> save(List<DeliveryPackage> value,{bool? routeOptimized})async{packages=[...value];if(routeOptimized!=null)optimized=routeOptimized;saves++;}
  @override Future<void> clear()async{packages=[];optimized=false;}
}

DeliveryPackage _package(String id,int scan,{String? zone,DeliveryStatus status=DeliveryStatus.pending})=>DeliveryPackage(
 id:id,scanNumber:scan,physicalZone:zone,status:status,
 address:AddressData(raw:'Rua Teste, $scan',street:'Rua Teste',number:'$scan',city:'São Paulo',state:'SP',latitude:-23.55,longitude:-46.63,confidence:1,validation:ValidationStatus.confirmed),
 scannedAt:DateTime.utc(2026,9,13,13,scan),
);

void main(){
 test('manual position cannot be assigned before route optimization',()async{
  final store=GuardStore([_package('a',1),_package('b',2)]);
  final state=AppState(store:store);await state.init();
  expect(()=>state.setPhysicalZone('a','Frente esquerda'),throwsA(isA<StateError>()));
  expect(state.packages.every((p)=>p.physicalZone==null),isTrue);
  expect(store.saves,0);
 });

 test('invalid vehicle zone fails without changing package',()async{
  final store=GuardStore([_package('a',1)],optimized:true);final state=AppState(store:store);await state.init();
  expect(()=>state.setPhysicalZone('a','Banco traseiro'),throwsA(isA<ArgumentError>()));
  expect(state.packages.single.physicalZone,isNull);
  expect(store.saves,0);
 });

 test('manual position can be moved and cleared',()async{
  final store=GuardStore([_package('a',1,zone:'Frente esquerda'),_package('b',2)],optimized:true);final state=AppState(store:store);await state.init();
  await state.setPhysicalZone('a','Porta-malas');
  expect(state.packages[0].physicalZone,'Porta-malas');
  await state.setPhysicalZone('a',null);
  expect(state.packages[0].physicalZone,isNull);
  expect(store.saves,2);
 });

 test('delivered package cannot be manually reorganized',()async{
  final store=GuardStore([_package('done',1,zone:'Porta-malas',status:DeliveryStatus.delivered)],optimized:true);final state=AppState(store:store);await state.init();
  expect(()=>state.setPhysicalZone('done','Frente esquerda'),throwsA(isA<StateError>()));
  expect(state.packages.single.physicalZone,'Porta-malas');
  expect(store.saves,0);
 });
}
