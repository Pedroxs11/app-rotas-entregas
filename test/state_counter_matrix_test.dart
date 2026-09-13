import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/services/package_store.dart';
import 'package:flutter_test/flutter_test.dart';

class CounterStore implements PackageStore {
 CounterStore(this.packages);List<DeliveryPackage> packages;
 @override Future<List<DeliveryPackage>> load()async=>[...packages];
 @override Future<bool> loadRouteOptimized()async=>false;
 @override Future<void> save(List<DeliveryPackage> value,{bool? routeOptimized})async{packages=[...value];}
 @override Future<void> clear()async{packages=[];}
}

DeliveryPackage _p(String id,int n,DeliveryStatus status,ValidationStatus validation,{bool located=false})=>DeliveryPackage(
 id:id,scanNumber:n,status:status,
 address:AddressData(raw:'Rua $n',street:'Rua',number:'$n',city:'São Paulo',state:'SP',latitude:located?-23.55:null,longitude:located?-46.63:null,confidence:validation==ValidationStatus.confirmed?1:.4,validation:validation),
 scannedAt:DateTime.utc(2026,9,13,23,n),
);

void main(){
 test('dashboard counters follow the full delivery status and validation matrix',()async{
  final store=CounterStore([
   _p('pending-review',1,DeliveryStatus.pending,ValidationStatus.needsReview),
   _p('pending-located',2,DeliveryStatus.pending,ValidationStatus.confirmed,located:true),
   _p('current-located',3,DeliveryStatus.current,ValidationStatus.confirmed,located:true),
   _p('absent-review',4,DeliveryStatus.absent,ValidationStatus.needsReview,located:true),
   _p('problem',5,DeliveryStatus.addressProblem,ValidationStatus.confirmed),
   _p('skipped',6,DeliveryStatus.skipped,ValidationStatus.confirmed,located:true),
   _p('delivered-review',7,DeliveryStatus.delivered,ValidationStatus.needsReview,located:true),
   _p('delivered-ok',8,DeliveryStatus.delivered,ValidationStatus.confirmed,located:true),
  ]);
  final state=AppState(store:store);await state.init();
  expect(state.deliveredCount,2);expect(state.reviewCount,2);expect(state.locatedCount,4);expect(state.retryCount,3);
 });

 test('delivered packages never inflate review or located counters but leave retry count clean',()async{
  final store=CounterStore([
   _p('done-review',1,DeliveryStatus.delivered,ValidationStatus.invalid,located:true),
   _p('done-ok',2,DeliveryStatus.delivered,ValidationStatus.confirmed,located:true),
  ]);
  final state=AppState(store:store);await state.init();
  expect(state.deliveredCount,2);expect(state.reviewCount,0);expect(state.locatedCount,0);expect(state.retryCount,0);
 });

 test('retry counter includes absent problem and skipped regardless of address validation',()async{
  final store=CounterStore([
   _p('absent',1,DeliveryStatus.absent,ValidationStatus.confirmed),
   _p('problem',2,DeliveryStatus.addressProblem,ValidationStatus.invalid),
   _p('skip',3,DeliveryStatus.skipped,ValidationStatus.needsReview),
   _p('pending',4,DeliveryStatus.pending,ValidationStatus.invalid),
   _p('current',5,DeliveryStatus.current,ValidationStatus.confirmed),
  ]);
  final state=AppState(store:store);await state.init();
  expect(state.retryCount,3);expect(state.deliveredCount,0);expect(state.reviewCount,3);
 });

 test('empty state exposes zero for every dashboard counter',()async{
  final state=AppState(store:CounterStore([]));await state.init();
  expect(state.reviewCount,0);expect(state.deliveredCount,0);expect(state.locatedCount,0);expect(state.retryCount,0);
 });
}
