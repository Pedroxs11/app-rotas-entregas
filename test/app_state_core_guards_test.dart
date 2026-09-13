import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/services/package_store.dart';
import 'package:flutter_test/flutter_test.dart';

class CoreStore implements PackageStore {
  CoreStore(this.packages,{this.optimized=false});
  List<DeliveryPackage> packages;
  bool optimized;
  int saves=0;
  int clears=0;

  @override Future<List<DeliveryPackage>> load() async=>[...packages];
  @override Future<bool> loadRouteOptimized() async=>optimized;
  @override Future<void> save(List<DeliveryPackage> value,{bool? routeOptimized}) async {
    packages=[...value];
    if(routeOptimized!=null) optimized=routeOptimized;
    saves++;
  }
  @override Future<void> clear() async {packages=[];optimized=false;clears++;}
}

DeliveryPackage _p(String id,int scan,{DeliveryStatus status=DeliveryStatus.pending,ValidationStatus validation=ValidationStatus.confirmed,double? lat,double? lng,String? zone})=>DeliveryPackage(
  id:id,scanNumber:scan,status:status,physicalZone:zone,
  address:AddressData(raw:'Rua $scan',street:'Rua',number:'$scan',city:'São Paulo',state:'SP',latitude:lat,longitude:lng,confidence:validation==ValidationStatus.confirmed?1:.5,validation:validation),
  scannedAt:DateTime.utc(2026,9,13,15,scan),
);

void main(){
  test('summary counters exclude delivered packages from review and located totals',() async {
    final store=CoreStore([
      _p('pending-review',1,validation:ValidationStatus.needsReview),
      _p('pending-located',2,lat:-23.55,lng:-46.63),
      _p('absent',3,status:DeliveryStatus.absent,lat:-23.56,lng:-46.64),
      _p('problem',4,status:DeliveryStatus.addressProblem,validation:ValidationStatus.needsReview),
      _p('skipped',5,status:DeliveryStatus.skipped),
      _p('delivered-review',6,status:DeliveryStatus.delivered,validation:ValidationStatus.needsReview,lat:-23.57,lng:-46.65),
    ]);
    final state=AppState(store:store);await state.init();
    expect(state.reviewCount,2);
    expect(state.locatedCount,2);
    expect(state.retryCount,3);
    expect(state.deliveredCount,1);
  });

  test('clear resets route and location counters and survives restart',() async {
    final store=CoreStore([_p('x',1,lat:-23.55,lng:-46.63,zone:'A-01')],optimized:true);
    final state=AppState(store:store);await state.init();
    state.lastLocateAttempted=4;state.lastLocateSucceeded=3;state.lastLocateFailed=1;
    await state.clear();
    expect(state.packages,isEmpty);expect(state.routeOptimized,isFalse);
    expect(state.lastLocateAttempted,0);expect(state.lastLocateSucceeded,0);expect(state.lastLocateFailed,0);
    expect(store.clears,1);expect(store.optimized,isFalse);
    final reopened=AppState(store:store);await reopened.init();
    expect(reopened.packages,isEmpty);expect(reopened.routeOptimized,isFalse);expect(reopened.startupError,isNull);
  });

  test('optimizing an empty route persists optimized state without inventing packages',() async {
    final store=CoreStore([]);
    final state=AppState(store:store);await state.init();
    await state.optimizeFrom(-23.55,-46.63);
    expect(state.packages,isEmpty);expect(state.routeOptimized,isTrue);expect(store.optimized,isTrue);expect(store.saves,1);
  });

  test('route optimization keeps finished packages out of active optimization',() async {
    final store=CoreStore([
      _p('delivered',1,status:DeliveryStatus.delivered,zone:'DONE',lat:-23.551,lng:-46.631),
      _p('skipped',2,status:DeliveryStatus.skipped,zone:'SKIP',lat:-23.552,lng:-46.632),
      _p('far',3,lat:-23.60,lng:-46.70),
      _p('near',4,lat:-23.5505,lng:-46.6305),
    ]);
    final state=AppState(store:store);await state.init();
    await state.optimizeFrom(-23.55,-46.63);
    expect(state.packages.map((p)=>p.id).toList(),['delivered','skipped','near','far']);
    expect(state.packages[0].physicalZone,'DONE');expect(state.packages[1].physicalZone,'SKIP');expect(state.routeOptimized,isTrue);
  });

  test('default retry includes absent only and leaves problem and skipped untouched',() async {
    final store=CoreStore([
      _p('absent',1,status:DeliveryStatus.absent,zone:'A-01',lat:-23.55,lng:-46.63),
      _p('problem',2,status:DeliveryStatus.addressProblem,zone:'A-02',lat:-23.56,lng:-46.64),
      _p('skipped',3,status:DeliveryStatus.skipped,zone:'A-03',lat:-23.57,lng:-46.65),
    ],optimized:true);
    final state=AppState(store:store);await state.init();
    final count=await state.prepareRetryRoute(-23.55,-46.63);
    expect(count,1);
    expect(state.packages.firstWhere((p)=>p.id=='absent').status,DeliveryStatus.pending);
    expect(state.packages.firstWhere((p)=>p.id=='problem').status,DeliveryStatus.addressProblem);
    expect(state.packages.firstWhere((p)=>p.id=='skipped').status,DeliveryStatus.skipped);
    expect(state.packages.firstWhere((p)=>p.id=='absent').physicalZone,isNull);
    expect(state.packages.firstWhere((p)=>p.id=='problem').physicalZone,isNull);
    expect(state.packages.firstWhere((p)=>p.id=='skipped').physicalZone,isNull);
    expect(state.routeOptimized,isTrue);
  });
}
