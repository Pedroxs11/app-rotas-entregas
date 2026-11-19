import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/services/package_store.dart';
import 'package:flutter_test/flutter_test.dart';

class RetryStore implements PackageStore {
  RetryStore(this.packages,{this.optimized=true});
  List<DeliveryPackage> packages;bool optimized;int saves=0;
  @override Future<List<DeliveryPackage>> load()async=>[...packages];
  @override Future<bool> loadRouteOptimized()async=>optimized;
  @override Future<void> save(List<DeliveryPackage> value,{bool? routeOptimized})async{packages=[...value];if(routeOptimized!=null)optimized=routeOptimized;saves++;}
  @override Future<void> clear()async{packages=[];optimized=false;}
}

DeliveryPackage _p(String id,int scan,DeliveryStatus status,{String? zone,double? lat,double? lng})=>DeliveryPackage(
 id:id,scanNumber:scan,status:status,physicalZone:zone,
 address:AddressData(raw:'Rua $scan',street:'Rua',number:'$scan',city:'São Paulo',state:'SP',latitude:lat,longitude:lng,confidence:1,validation:ValidationStatus.confirmed),
 scannedAt:DateTime.utc(2026,9,13,21,scan),
);

List<DeliveryPackage> _route()=>[
 _p('delivered',1,DeliveryStatus.delivered,zone:'HIST',lat:-23.54,lng:-46.62),
 _p('pending',2,DeliveryStatus.pending,zone:'A-01',lat:-23.58,lng:-46.67),
 _p('absent',3,DeliveryStatus.absent,zone:'A-02',lat:-23.5501,lng:-46.6301),
 _p('problem',4,DeliveryStatus.addressProblem,zone:'A-03',lat:-23.56,lng:-46.64),
 _p('skipped',5,DeliveryStatus.skipped,zone:'SKIP',lat:-23.57,lng:-46.65),
];

void main(){
 test('address-problem flag retries absent plus address problems but not skipped',()async{
  final store=RetryStore(_route());final state=AppState(store:store);await state.init();
  final count=await state.prepareRetryRoute(-23.55,-46.63,includeAddressProblems:true);
  expect(count,2);expect(state.packages.firstWhere((p)=>p.id=='absent').status,DeliveryStatus.pending);expect(state.packages.firstWhere((p)=>p.id=='problem').status,DeliveryStatus.pending);expect(state.packages.firstWhere((p)=>p.id=='skipped').status,DeliveryStatus.skipped);expect(state.packages.firstWhere((p)=>p.id=='delivered').physicalZone,'HIST');expect(state.routeOptimized,isTrue);
 });

 test('skipped flag retries absent plus skipped but not address problems',()async{
  final store=RetryStore(_route());final state=AppState(store:store);await state.init();
  final count=await state.prepareRetryRoute(-23.55,-46.63,includeSkipped:true);
  expect(count,2);expect(state.packages.firstWhere((p)=>p.id=='absent').status,DeliveryStatus.pending);expect(state.packages.firstWhere((p)=>p.id=='skipped').status,DeliveryStatus.pending);expect(state.packages.firstWhere((p)=>p.id=='problem').status,DeliveryStatus.addressProblem);expect(state.packages.firstWhere((p)=>p.id=='delivered').status,DeliveryStatus.delivered);
 });

 test('both flags retry all three retryable failure statuses exactly once',()async{
  final store=RetryStore(_route());final state=AppState(store:store);await state.init();
  final count=await state.prepareRetryRoute(-23.55,-46.63,includeAddressProblems:true,includeSkipped:true);
  expect(count,3);for(final id in ['absent','problem','skipped']){expect(state.packages.firstWhere((p)=>p.id==id).status,DeliveryStatus.pending);}expect(state.packages.map((p)=>p.id).toSet(),{'delivered','pending','absent','problem','skipped'});expect(state.packages,hasLength(5));expect(state.packages.firstWhere((p)=>p.id=='delivered').physicalZone,'HIST');expect(state.packages.where((p)=>p.id!='delivered').every((p)=>p.physicalZone==null),isTrue);expect(store.saves,1);
 });

 test('retry never changes already pending or delivered status',()async{
  final store=RetryStore(_route());final state=AppState(store:store);await state.init();
  await state.prepareRetryRoute(-23.55,-46.63,includeAddressProblems:true,includeSkipped:true);
  expect(state.packages.firstWhere((p)=>p.id=='pending').status,DeliveryStatus.pending);expect(state.packages.firstWhere((p)=>p.id=='delivered').status,DeliveryStatus.delivered);expect(state.packages.firstWhere((p)=>p.id=='delivered').physicalZone,'HIST');
 });
}
