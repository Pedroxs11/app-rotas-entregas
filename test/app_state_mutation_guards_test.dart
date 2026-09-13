import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/services/package_store.dart';
import 'package:flutter_test/flutter_test.dart';

class MutationStore implements PackageStore {
  MutationStore(this.packages,{this.optimized=false});
  List<DeliveryPackage> packages;
  bool optimized;
  int saves=0;
  @override Future<List<DeliveryPackage>> load() async=>[...packages];
  @override Future<bool> loadRouteOptimized() async=>optimized;
  @override Future<void> save(List<DeliveryPackage> value,{bool? routeOptimized}) async {packages=[...value];if(routeOptimized!=null)optimized=routeOptimized;saves++;}
  @override Future<void> clear() async {packages=[];optimized=false;}
}

DeliveryPackage _p(String id,int scan,{String? zone,DeliveryStatus status=DeliveryStatus.pending})=>DeliveryPackage(
  id:id,scanNumber:scan,status:status,physicalZone:zone,
  address:AddressData(raw:'Rua Teste, $scan',street:'Rua Teste',number:'$scan',city:'São Paulo',state:'SP',confidence:.5,validation:ValidationStatus.needsReview),
  scannedAt:DateTime.utc(2026,9,13,17,scan),
);

void main(){
  test('adding structured package invalidates route and clears stale active load labels',() async {
    final store=MutationStore([_p('old',1,zone:'A-01')],optimized:true);
    final state=AppState(store:store);await state.init();
    const address=AddressData(raw:'Rua Nova, 200',street:'Rua Nova',number:'200',city:'São Paulo',state:'SP',confidence:.5,validation:ValidationStatus.needsReview);
    await state.addStructured(address);
    expect(state.packages,hasLength(2));expect(state.routeOptimized,isFalse);expect(state.packages[0].physicalZone,isNull);expect(state.packages[1].physicalZone,isNull);expect(store.optimized,isFalse);expect(store.saves,1);
  });

  test('adding structured package preserves delivered history label',() async {
    final store=MutationStore([_p('done',1,zone:'HIST',status:DeliveryStatus.delivered)],optimized:true);
    final state=AppState(store:store);await state.init();
    const address=AddressData(raw:'Rua Nova, 300',street:'Rua Nova',number:'300',city:'São Paulo',state:'SP',confidence:.5,validation:ValidationStatus.needsReview);
    await state.addStructured(address);
    expect(state.routeOptimized,isFalse);expect(state.packages.first.physicalZone,'HIST');expect(state.packages.first.status,DeliveryStatus.delivered);expect(state.packages.last.physicalZone,isNull);
  });

  test('manual reorder moving downward uses insertion semantics without losing packages',() async {
    final store=MutationStore([_p('a',1,zone:'A-01'),_p('b',2,zone:'A-02'),_p('c',3,zone:'A-03')],optimized:true);
    final state=AppState(store:store);await state.init();
    await state.reorder(0,3);
    expect(state.packages.map((p)=>p.id).toList(),['b','c','a']);expect(state.packages.map((p)=>p.id).toSet(),{'a','b','c'});expect(state.routeOptimized,isFalse);expect(state.packages.every((p)=>p.physicalZone==null),isTrue);expect(store.saves,1);
  });

  test('manual reorder moving upward keeps exact package set and clears active labels',() async {
    final store=MutationStore([_p('a',1,zone:'A-01'),_p('b',2,zone:'A-02'),_p('c',3,zone:'A-03')],optimized:true);
    final state=AppState(store:store);await state.init();
    await state.reorder(2,0);
    expect(state.packages.map((p)=>p.id).toList(),['c','a','b']);expect(state.packages.map((p)=>p.id).toSet(),{'a','b','c'});expect(state.routeOptimized,isFalse);expect(state.packages.every((p)=>p.physicalZone==null),isTrue);
  });

  test('direct status update preserves route metadata and physical position',() async {
    final store=MutationStore([_p('delivery',1,zone:'A-01')],optimized:true);
    final state=AppState(store:store);await state.init();
    final completed=DateTime.utc(2026,9,13,18);
    await state.update(0,state.packages.single.copyWith(status:DeliveryStatus.delivered,completedAt:completed));
    expect(state.routeOptimized,isTrue);expect(state.packages.single.status,DeliveryStatus.delivered);expect(state.packages.single.completedAt,completed);expect(state.packages.single.physicalZone,'A-01');expect(store.optimized,isTrue);expect(store.saves,1);
  });
}
