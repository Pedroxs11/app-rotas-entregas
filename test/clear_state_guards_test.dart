import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/services/package_store.dart';
import 'package:flutter_test/flutter_test.dart';

class ClearStore implements PackageStore {
 ClearStore(this.packages,{this.optimized=true});List<DeliveryPackage> packages;bool optimized;int clears=0;int saves=0;
 @override Future<List<DeliveryPackage>> load()async=>[...packages];
 @override Future<bool> loadRouteOptimized()async=>optimized;
 @override Future<void> save(List<DeliveryPackage> value,{bool? routeOptimized})async{packages=[...value];if(routeOptimized!=null)optimized=routeOptimized;saves++;}
 @override Future<void> clear()async{packages=[];optimized=false;clears++;}
}

DeliveryPackage _p(String id,int n,DeliveryStatus status)=>DeliveryPackage(
 id:id,scanNumber:n,status:status,physicalZone:'A-${n.toString().padLeft(2,'0')}',
 address:AddressData(raw:'Rua $n',street:'Rua',number:'$n',city:'São Paulo',state:'SP',latitude:-23.55,longitude:-46.63,confidence:1,validation:ValidationStatus.confirmed),
 scannedAt:DateTime.utc(2026,9,13,23,n),completedAt:status==DeliveryStatus.delivered?DateTime.utc(2026,9,13,23,30):null,
);

void main(){
 test('clear removes packages route metadata and every dashboard count in one operation',()async{
  final store=ClearStore([_p('pending',1,DeliveryStatus.pending),_p('absent',2,DeliveryStatus.absent),_p('done',3,DeliveryStatus.delivered)]);
  final state=AppState(store:store);await state.init();
  expect(state.routeOptimized,isTrue);expect(state.packages,hasLength(3));
  await state.clear();
  expect(state.packages,isEmpty);expect(state.routeOptimized,isFalse);expect(state.reviewCount,0);expect(state.deliveredCount,0);expect(state.locatedCount,0);expect(state.retryCount,0);expect(store.packages,isEmpty);expect(store.optimized,isFalse);expect(store.clears,1);expect(store.saves,0);
 });

 test('clear resets previous geocoding summary counters',()async{
  final store=ClearStore([]);final state=AppState(store:store);await state.init();
  state.lastLocateAttempted=7;state.lastLocateSucceeded=5;state.lastLocateFailed=2;
  await state.clear();
  expect(state.lastLocateAttempted,0);expect(state.lastLocateSucceeded,0);expect(state.lastLocateFailed,0);expect(store.clears,1);
 });

 test('cleared store stays empty after a fresh state initialization',()async{
  final store=ClearStore([_p('old',1,DeliveryStatus.pending)]);final first=AppState(store:store);await first.init();await first.clear();
  final restarted=AppState(store:store);await restarted.init();
  expect(restarted.packages,isEmpty);expect(restarted.routeOptimized,isFalse);expect(restarted.deliveredCount,0);expect(restarted.retryCount,0);
 });
}
