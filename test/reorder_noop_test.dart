import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/services/package_store.dart';
import 'package:flutter_test/flutter_test.dart';

class ReorderStore implements PackageStore {
 ReorderStore(this.packages);List<DeliveryPackage> packages;bool optimized=true;int saves=0;
 @override Future<List<DeliveryPackage>> load()async=>[...packages];
 @override Future<bool> loadRouteOptimized()async=>optimized;
 @override Future<void> save(List<DeliveryPackage> value,{bool? routeOptimized})async{packages=[...value];if(routeOptimized!=null)optimized=routeOptimized;saves++;}
 @override Future<void> clear()async{packages=[];optimized=false;}
}
DeliveryPackage _p(String id,int n,String zone)=>DeliveryPackage(id:id,scanNumber:n,physicalZone:zone,address:AddressData(raw:'Rua $n',street:'Rua',number:'$n',city:'São Paulo',state:'SP',confidence:1,validation:ValidationStatus.confirmed),scannedAt:DateTime.utc(2026,9,13,20,n));
void main(){
 test('same index reorder is a true no-op',()async{
  final store=ReorderStore([_p('a',1,'A-01'),_p('b',2,'A-02'),_p('c',3,'A-03')]);final state=AppState(store:store);await state.init();await state.reorder(1,1);
  expect(state.packages.map((p)=>p.id).toList(),['a','b','c']);expect(state.packages.map((p)=>p.physicalZone).toList(),['A-01','A-02','A-03']);expect(state.routeOptimized,isTrue);expect(store.optimized,isTrue);expect(store.saves,0);
 });
 test('flutter downward adjacent drop that normalizes to same slot is a no-op',()async{
  final store=ReorderStore([_p('a',1,'A-01'),_p('b',2,'A-02'),_p('c',3,'A-03')]);final state=AppState(store:store);await state.init();await state.reorder(1,2);
  expect(state.packages.map((p)=>p.id).toList(),['a','b','c']);expect(state.packages.map((p)=>p.physicalZone).toList(),['A-01','A-02','A-03']);expect(state.routeOptimized,isTrue);expect(store.saves,0);
 });
 test('real reorder still invalidates optimization and stale physical labels',()async{
  final store=ReorderStore([_p('a',1,'A-01'),_p('b',2,'A-02'),_p('c',3,'A-03')]);final state=AppState(store:store);await state.init();await state.reorder(0,3);
  expect(state.packages.map((p)=>p.id).toList(),['b','c','a']);expect(state.packages.every((p)=>p.physicalZone==null),isTrue);expect(state.routeOptimized,isFalse);expect(store.optimized,isFalse);expect(store.saves,1);
 });
}
