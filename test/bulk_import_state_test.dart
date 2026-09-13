import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/services/package_store.dart';
import 'package:flutter_test/flutter_test.dart';

class BulkStore implements PackageStore {
  BulkStore(this.packages,{this.optimized=false});
  List<DeliveryPackage> packages;
  bool optimized;
  int saves=0;
  @override Future<List<DeliveryPackage>> load() async=>[...packages];
  @override Future<bool> loadRouteOptimized() async=>optimized;
  @override Future<void> save(List<DeliveryPackage> value,{bool? routeOptimized}) async {packages=[...value];if(routeOptimized!=null)optimized=routeOptimized;saves++;}
  @override Future<void> clear() async {packages=[];optimized=false;}
}

DeliveryPackage _existing(String id,int scan,{DeliveryStatus status=DeliveryStatus.pending,String? zone})=>DeliveryPackage(
  id:id,scanNumber:scan,status:status,physicalZone:zone,
  address:AddressData(raw:'Rua Antiga, $scan',street:'Rua Antiga',number:'$scan',city:'São Paulo',state:'SP',confidence:.5,validation:ValidationStatus.needsReview),
  scannedAt:DateTime.utc(2026,9,13,19,scan),
);

void main(){
  test('bulk import ignores blank lines and imports each valid address once',() async {
    final store=BulkStore([]);final state=AppState(store:store);await state.init();
    final count=await state.addManyFromText('Rua Alfa, 10\n\n  Rua Beta, 20  \n\nRua Gama, 30');
    expect(count,3);expect(state.packages,hasLength(3));expect(state.packages.map((p)=>p.address.raw).toSet(),{'Rua Alfa, 10','Rua Beta, 20','Rua Gama, 30'});expect(state.routeOptimized,isFalse);expect(store.saves,1);
  });

  test('bulk import invalidates optimized route and clears stale active load labels',() async {
    final store=BulkStore([_existing('old',1,zone:'A-01')],optimized:true);final state=AppState(store:store);await state.init();
    final count=await state.addManyFromText('Rua Nova, 200\nRua Nova Dois, 300');
    expect(count,2);expect(state.packages,hasLength(3));expect(state.routeOptimized,isFalse);expect(state.packages.every((p)=>p.physicalZone==null),isTrue);expect(store.optimized,isFalse);
  });

  test('bulk import preserves delivered history label while clearing active labels',() async {
    final store=BulkStore([_existing('done',1,status:DeliveryStatus.delivered,zone:'HIST'),_existing('active',2,zone:'A-02')],optimized:true);final state=AppState(store:store);await state.init();
    final count=await state.addManyFromText('Rua Nova, 400');
    expect(count,1);expect(state.packages.firstWhere((p)=>p.id=='done').physicalZone,'HIST');expect(state.packages.firstWhere((p)=>p.id=='done').status,DeliveryStatus.delivered);expect(state.packages.firstWhere((p)=>p.id=='active').physicalZone,isNull);expect(state.packages.last.physicalZone,isNull);expect(state.routeOptimized,isFalse);
  });

  test('empty bulk import does not invent packages but still leaves route unoptimized',() async {
    final store=BulkStore([_existing('old',1,zone:'A-01')],optimized:true);final state=AppState(store:store);await state.init();
    final count=await state.addManyFromText('  \n\n   ');
    expect(count,0);expect(state.packages,hasLength(1));expect(state.packages.single.id,'old');expect(state.routeOptimized,isFalse);expect(store.optimized,isFalse);expect(store.saves,1);
  });
}
