import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/services/package_store.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryPackageStore implements PackageStore {
  List<DeliveryPackage> packages;
  bool optimized;
  int saves=0;
  int clears=0;

  MemoryPackageStore({List<DeliveryPackage>? packages,this.optimized=false})
      : packages=[...?packages];

  @override Future<List<DeliveryPackage>> load() async=>[...packages];
  @override Future<bool> loadRouteOptimized() async=>optimized;
  @override Future<void> save(List<DeliveryPackage> value,{bool? routeOptimized}) async {packages=[...value];if(routeOptimized!=null)optimized=routeOptimized;saves++;}
  @override Future<void> clear() async {packages=[];optimized=false;clears++;}
}

DeliveryPackage package(String id,int scan,{DeliveryStatus status=DeliveryStatus.pending,String? zone,double? lat,double? lng,DateTime? completedAt})=>DeliveryPackage(
  id:id,scanNumber:scan,physicalZone:zone,
  address:AddressData(raw:'Rua Teste, $scan',street:'Rua Teste',number:'$scan',city:'São Paulo',state:'SP',latitude:lat,longitude:lng,confidence:1,validation:ValidationStatus.confirmed),
  scannedAt:DateTime.utc(2026,9,11,12,scan),completedAt:completedAt,status:status,
);

void main(){
  test('AppState restores packages and route state through PackageStore',() async {
    final original=package('saved-1',7,status:DeliveryStatus.absent,zone:'B-03',lat:-23.55,lng:-46.63);
    final store=MemoryPackageStore(packages:[original],optimized:true);
    final state=AppState(store:store);await state.init();
    expect(state.loading,isFalse);expect(state.routeOptimized,isTrue);expect(state.packages,hasLength(1));expect(state.packages.single,same(original));expect(state.packages.single.id,'saved-1');expect(state.packages.single.status,DeliveryStatus.absent);expect(state.packages.single.physicalZone,'B-03');
  });

  test('optimized route order and delivery states survive app restart',() async {
    final store=MemoryPackageStore(packages:[package('far',1,lat:-23.60,lng:-46.70),package('near',2,lat:-23.551,lng:-46.631),package('done',3,status:DeliveryStatus.delivered,zone:'HIST',lat:-23.54,lng:-46.62)]);
    final first=AppState(store:store);await first.init();await first.optimizeFrom(-23.55,-46.63);await first.organizePhysicalLoad(groupSize:20);
    final beforeIds=first.packages.map((p)=>p.id).toList();final beforeStatuses=first.packages.map((p)=>p.status).toList();final beforeZones=first.packages.map((p)=>p.physicalZone).toList();
    final reopened=AppState(store:store);await reopened.init();
    expect(reopened.routeOptimized,isTrue);expect(reopened.packages.map((p)=>p.id).toList(),beforeIds);expect(reopened.packages.map((p)=>p.status).toList(),beforeStatuses);expect(reopened.packages.map((p)=>p.physicalZone).toList(),beforeZones);expect(reopened.packages.firstWhere((p)=>p.id=='near').physicalZone,isNotNull);expect(reopened.packages.firstWhere((p)=>p.id=='done').status,DeliveryStatus.delivered);
  });

  test('organizePhysicalLoad persists positions without imposing route cap',() async {
    final items=List.generate(75,(i)=>package('p$i',i+1,lat:-23.5-(i*.0001),lng:-46.6-(i*.0001)));final store=MemoryPackageStore(packages:items,optimized:true);final state=AppState(store:store);await state.init();await state.organizePhysicalLoad(groupSize:20);
    expect(state.packages.length,75);expect(state.packages[0].physicalZone,'A-01');expect(state.packages[19].physicalZone,'A-20');expect(state.packages[20].physicalZone,'B-01');expect(state.packages[74].physicalZone,'D-15');expect(store.saves,1);expect(store.packages[74].physicalZone,'D-15');
  });

  test('active reoptimization preserves physical load positions',() async {
    final store=MemoryPackageStore(packages:[package('far',1,zone:'A-01',lat:-23.60,lng:-46.70),package('near',2,zone:'A-02',lat:-23.551,lng:-46.631)],optimized:true);final state=AppState(store:store);await state.init();await state.optimizeFrom(-23.55,-46.63);
    expect(state.packages.map((p)=>p.id),['near','far']);expect(state.packages.first.physicalZone,'A-02');expect(state.packages.last.physicalZone,'A-01');expect(store.optimized,isTrue);
  });

  test('reoptimization changes first stop when driver position changes',() async {
    final store=MemoryPackageStore(packages:[package('west',1,lat:-23.55,lng:-46.70),package('east',2,lat:-23.55,lng:-46.60),package('middle',3,lat:-23.55,lng:-46.65)]);final state=AppState(store:store);await state.init();await state.optimizeFrom(-23.55,-46.705);expect(state.packages.first.id,'west');await state.optimizeFrom(-23.55,-46.595);expect(state.packages.first.id,'east');expect(state.packages.map((p)=>p.id).toSet(),{'west','east','middle'});expect(store.optimized,isTrue);
  });

  test('second attempt clears stale load positions and resets retry statuses',() async {
    final completed=DateTime.utc(2026,9,12,18,30);
    final store=MemoryPackageStore(packages:[package('done',1,status:DeliveryStatus.delivered,zone:'HIST',lat:-23.54,lng:-46.62,completedAt:completed),package('absent',2,status:DeliveryStatus.absent,zone:'A-02',lat:-23.56,lng:-46.64),package('problem',3,status:DeliveryStatus.addressProblem,zone:'A-03',lat:-23.57,lng:-46.65),package('skipped',4,status:DeliveryStatus.skipped,zone:'A-04',lat:-23.58,lng:-46.66)],optimized:true);
    final state=AppState(store:store);await state.init();final count=await state.prepareRetryRoute(-23.55,-46.63,includeAddressProblems:true,includeSkipped:true);
    expect(count,3);final done=state.packages.firstWhere((p)=>p.id=='done');expect(done.status,DeliveryStatus.delivered);expect(done.completedAt,completed);expect(done.physicalZone,'HIST');
    for(final id in ['absent','problem','skipped']){final retry=state.packages.firstWhere((p)=>p.id==id);expect(retry.status,DeliveryStatus.pending);expect(retry.completedAt,isNull);expect(retry.physicalZone,isNull);}
    expect(store.optimized,isTrue);
  });

  test('clear uses injected store instead of concrete local storage',() async {
    final store=MemoryPackageStore(packages:[package('x',1)],optimized:true);final state=AppState(store:store);await state.init();await state.clear();expect(store.clears,1);expect(store.optimized,isFalse);expect(state.routeOptimized,isFalse);expect(state.packages,isEmpty);
  });
}
