import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/services/package_store.dart';
import 'package:flutter_test/flutter_test.dart';

class LocateStore implements PackageStore {
 LocateStore(this.packages,{this.optimized=false});List<DeliveryPackage> packages;bool optimized;int saves=0;
 @override Future<List<DeliveryPackage>> load()async=>[...packages];
 @override Future<bool> loadRouteOptimized()async=>optimized;
 @override Future<void> save(List<DeliveryPackage> value,{bool? routeOptimized})async{packages=[...value];if(routeOptimized!=null)optimized=routeOptimized;saves++;}
 @override Future<void> clear()async{packages=[];optimized=false;}
}

DeliveryPackage _p(String id,int n,{required ValidationStatus validation,double? lat,double? lng,DeliveryStatus status=DeliveryStatus.pending,String? zone})=>DeliveryPackage(
 id:id,scanNumber:n,status:status,physicalZone:zone,
 address:AddressData(raw:'Rua $n',street:'Rua',number:'$n',city:'São Paulo',state:'SP',latitude:lat,longitude:lng,confidence:validation==ValidationStatus.confirmed?1:.4,validation:validation),
 scannedAt:DateTime.utc(2026,9,13,23,n),
);

void main(){
 test('locate confirmed is a true no-op when every eligible package is already located',()async{
  final store=LocateStore([_p('ready',1,validation:ValidationStatus.confirmed,lat:-23.55,lng:-46.63,zone:'A-01')],optimized:true);
  final state=AppState(store:store);await state.init();await state.locateConfirmed();
  expect(state.lastLocateAttempted,0);expect(state.lastLocateSucceeded,0);expect(state.lastLocateFailed,0);expect(state.locating,isFalse);expect(state.routeOptimized,isTrue);expect(state.packages.single.physicalZone,'A-01');expect(store.saves,0);
 });

 test('review and invalid addresses do not trigger geocoding persistence',()async{
  final store=LocateStore([_p('review',1,validation:ValidationStatus.needsReview),_p('invalid',2,validation:ValidationStatus.invalid)],optimized:false);
  final state=AppState(store:store);await state.init();await state.locateConfirmed();
  expect(state.lastLocateAttempted,0);expect(state.lastLocateSucceeded,0);expect(state.lastLocateFailed,0);expect(store.saves,0);expect(state.packages,hasLength(2));
 });

 test('delivered confirmed package without coordinates is not geocoded or rewritten',()async{
  final store=LocateStore([_p('done',1,validation:ValidationStatus.confirmed,status:DeliveryStatus.delivered,zone:'HIST')],optimized:true);
  final state=AppState(store:store);await state.init();await state.locateConfirmed();
  expect(state.lastLocateAttempted,0);expect(state.packages.single.status,DeliveryStatus.delivered);expect(state.packages.single.physicalZone,'HIST');expect(state.routeOptimized,isTrue);expect(store.saves,0);
 });
}
