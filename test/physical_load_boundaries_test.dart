import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/services/package_store.dart';
import 'package:flutter_test/flutter_test.dart';

class LoadStore implements PackageStore {
  LoadStore(this.packages);List<DeliveryPackage> packages;bool optimized=true;int saves=0;
  @override Future<List<DeliveryPackage>> load()async=>[...packages];
  @override Future<bool> loadRouteOptimized()async=>optimized;
  @override Future<void> save(List<DeliveryPackage> value,{bool? routeOptimized})async{packages=[...value];if(routeOptimized!=null)optimized=routeOptimized;saves++;}
  @override Future<void> clear()async{packages=[];optimized=false;}
}

DeliveryPackage _p(int n,{DeliveryStatus status=DeliveryStatus.pending,String? zone})=>DeliveryPackage(
 id:'p$n',scanNumber:n,status:status,physicalZone:zone,
 address:AddressData(raw:'Rua $n',street:'Rua',number:'$n',city:'São Paulo',state:'SP',confidence:1,validation:ValidationStatus.confirmed),
 scannedAt:DateTime.utc(2026,9,13,22,n%60),
);

void main(){
 test('default organization distributes active packages across the 11 car zones',()async{
  final store=LoadStore(List.generate(22,(i)=>_p(i+1)));final state=AppState(store:store);await state.init();
  await state.organizePhysicalLoad(overwrite:true);
  expect(state.packages[0].physicalZone,'Chão do passageiro');expect(state.packages[1].physicalZone,'Chão do passageiro');expect(state.packages[2].physicalZone,'Banco do passageiro');expect(state.packages[20].physicalZone,'Porta-malas direito');expect(state.packages[21].physicalZone,'Porta-malas direito');expect(store.saves,1);
 });

 test('custom group size respects every group boundary',()async{
  final store=LoadStore(List.generate(8,(i)=>_p(i+1)));final state=AppState(store:store);await state.init();
  await state.organizePhysicalLoad(groupSize:3,overwrite:true);
  expect(state.packages.map((p)=>p.physicalZone).toList(),['A-01','A-02','A-03','B-01','B-02','B-03','C-01','C-02']);
 });

 test('finished packages between active stops do not consume physical positions',()async{
  final store=LoadStore([_p(1),_p(2,status:DeliveryStatus.delivered,zone:'DONE'),_p(3),_p(4,status:DeliveryStatus.skipped,zone:'SKIP'),_p(5)]);final state=AppState(store:store);await state.init();
  await state.organizePhysicalLoad(groupSize:2,overwrite:true);
  expect(state.packages[0].physicalZone,'A-01');expect(state.packages[1].physicalZone,'DONE');expect(state.packages[2].physicalZone,'A-02');expect(state.packages[3].physicalZone,'SKIP');expect(state.packages[4].physicalZone,'B-01');
 });

 test('overwrite false preserves active labels but numbering still follows route slots',()async{
  final store=LoadStore([_p(1,zone:'CUSTOM'),_p(2),_p(3)]);final state=AppState(store:store);await state.init();
  await state.organizePhysicalLoad(groupSize:2);
  expect(state.packages.map((p)=>p.physicalZone).toList(),['CUSTOM','A-02','B-01']);expect(state.routeOptimized,isTrue);
 });
}
