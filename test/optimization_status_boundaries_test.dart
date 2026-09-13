import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/services/package_store.dart';
import 'package:flutter_test/flutter_test.dart';

class StatusStore implements PackageStore {
 StatusStore(this.packages);List<DeliveryPackage> packages;bool optimized=false;int saves=0;
 @override Future<List<DeliveryPackage>> load()async=>[...packages];
 @override Future<bool> loadRouteOptimized()async=>optimized;
 @override Future<void> save(List<DeliveryPackage> value,{bool? routeOptimized})async{packages=[...value];if(routeOptimized!=null)optimized=routeOptimized;saves++;}
 @override Future<void> clear()async{packages=[];optimized=false;}
}

DeliveryPackage _p(String id,int n,DeliveryStatus status,double lat,double lng,{String? zone})=>DeliveryPackage(
 id:id,scanNumber:n,status:status,physicalZone:zone,
 address:AddressData(raw:'Rua $n',street:'Rua',number:'$n',city:'São Paulo',state:'SP',latitude:lat,longitude:lng,confidence:1,validation:ValidationStatus.confirmed),
 scannedAt:DateTime.utc(2026,9,13,23,n),completedAt:status==DeliveryStatus.delivered?DateTime.utc(2026,9,13,23,40):null,
);

void main(){
 test('optimization includes pending current absent and address problem but excludes delivered and skipped',()async{
  final store=StatusStore([
   _p('pending-far',1,DeliveryStatus.pending,-23.70,-46.80),
   _p('delivered',2,DeliveryStatus.delivered,-23.55001,-46.63001,zone:'HIST'),
   _p('current',3,DeliveryStatus.current,-23.5501,-46.6301),
   _p('skipped',4,DeliveryStatus.skipped,-23.55002,-46.63002,zone:'SKIP'),
   _p('absent',5,DeliveryStatus.absent,-23.56,-46.64),
   _p('problem',6,DeliveryStatus.addressProblem,-23.57,-46.65),
  ]);
  final state=AppState(store:store);await state.init();await state.optimizeFrom(-23.55,-46.63);
  expect(state.packages.take(2).map((p)=>p.id).toList(),['delivered','skipped']);
  expect(state.packages.skip(2).map((p)=>p.id).toSet(),{'pending-far','current','absent','problem'});
  expect(state.packages[2].id,'current');expect(state.packages.firstWhere((p)=>p.id=='delivered').physicalZone,'HIST');expect(state.packages.firstWhere((p)=>p.id=='skipped').physicalZone,'SKIP');expect(state.routeOptimized,isTrue);expect(store.saves,1);
 });

 test('reoptimization preserves every package identity exactly once across status groups',()async{
  final original=[
   _p('p',1,DeliveryStatus.pending,-23.60,-46.70),_p('c',2,DeliveryStatus.current,-23.55,-46.63),_p('a',3,DeliveryStatus.absent,-23.58,-46.68),_p('e',4,DeliveryStatus.addressProblem,-23.59,-46.69),_p('d',5,DeliveryStatus.delivered,-23.57,-46.67),_p('s',6,DeliveryStatus.skipped,-23.56,-46.66),
  ];
  final state=AppState(store:StatusStore(original));await state.init();await state.optimizeFrom(-23.55,-46.63);
  expect(state.packages,hasLength(original.length));expect(state.packages.map((p)=>p.id).toSet(),original.map((p)=>p.id).toSet());expect(state.packages.map((p)=>p.id).toSet().length,original.length);
 });

 test('optimization does not rewrite delivery status or completion history',()async{
  final done=_p('done',1,DeliveryStatus.delivered,-23.55,-46.63,zone:'HIST');
  final absent=_p('absent',2,DeliveryStatus.absent,-23.56,-46.64);
  final store=StatusStore([absent,done]);final state=AppState(store:store);await state.init();await state.optimizeFrom(-23.55,-46.63);
  final afterDone=state.packages.firstWhere((p)=>p.id=='done');final afterAbsent=state.packages.firstWhere((p)=>p.id=='absent');
  expect(afterDone.status,DeliveryStatus.delivered);expect(afterDone.completedAt,done.completedAt);expect(afterDone.physicalZone,'HIST');expect(afterAbsent.status,DeliveryStatus.absent);expect(afterAbsent.completedAt,isNull);
 });
}
