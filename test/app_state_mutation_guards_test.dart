import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/services/package_store.dart';
import 'package:flutter_test/flutter_test.dart';

class MutationStore implements PackageStore {
  MutationStore(this.packages,{this.optimized=false});
  List<DeliveryPackage> packages;
  bool optimized;
  int saves=0;
  bool failNextSave=false;
  @override Future<List<DeliveryPackage>> load() async=>[...packages];
  @override Future<bool> loadRouteOptimized() async=>optimized;
  @override Future<void> save(List<DeliveryPackage> value,{bool? routeOptimized}) async {if(failNextSave){failNextSave=false;throw StateError('simulated storage failure');}packages=[...value];if(routeOptimized!=null)optimized=routeOptimized;saves++;}
  @override Future<void> clear() async {packages=[];optimized=false;}
}

DeliveryPackage _p(String id,int scan,{String? zone,DeliveryStatus status=DeliveryStatus.pending})=>DeliveryPackage(
  id:id,scanNumber:scan,status:status,physicalZone:zone,
  address:AddressData(raw:'Rua Teste, $scan',street:'Rua Teste',number:'$scan',city:'São Paulo',state:'SP',confidence:.5,validation:ValidationStatus.needsReview),
  scannedAt:DateTime.utc(2026,9,13,17,scan),
);

void main(){
  test('adding structured package invalidates route while preserving existing load positions',() async {
    final store=MutationStore([_p('old',1,zone:'A-01')],optimized:true);
    final state=AppState(store:store);await state.init();
    const address=AddressData(raw:'Rua Nova, 200',street:'Rua Nova',number:'200',city:'São Paulo',state:'SP',confidence:.5,validation:ValidationStatus.needsReview);
    await state.addStructured(address);
    expect(state.packages,hasLength(2));expect(state.routeOptimized,isFalse);expect(state.packages[0].physicalZone,'A-01');expect(state.packages[1].physicalZone,isNull);expect(store.optimized,isFalse);expect(store.saves,1);
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

  test('remove rolls back packages and route metadata when persistence fails',() async {
    final original=[_p('a',1,zone:'A-01'),_p('b',2,zone:'A-02')];
    final store=MutationStore(original,optimized:true);
    final state=AppState(store:store);await state.init();
    store.failNextSave=true;

    await expectLater(state.removePackage('a'),throwsA(isA<StateError>()));

    expect(state.packages.map((p)=>p.id).toList(),['a','b']);
    expect(state.packages.map((p)=>p.physicalZone).toList(),['A-01','A-02']);
    expect(state.routeOptimized,isTrue);
    expect(store.packages.map((p)=>p.id).toList(),['a','b']);
    expect(store.optimized,isTrue);
  });

  test('reorder rolls back order and physical positions when persistence fails',() async {
    final original=[_p('a',1,zone:'A-01'),_p('b',2,zone:'A-02')];
    final store=MutationStore(original,optimized:true);
    final state=AppState(store:store);await state.init();
    store.failNextSave=true;

    await expectLater(state.reorder(0,2),throwsA(isA<StateError>()));

    expect(state.packages.map((p)=>p.id).toList(),['a','b']);
    expect(state.packages.map((p)=>p.physicalZone).toList(),['A-01','A-02']);
    expect(state.routeOptimized,isTrue);
    expect(store.packages.map((p)=>p.id).toList(),['a','b']);
  });

  test('optimization restores previous route state when persistence fails',() async {
    final original=[_p('a',1,zone:'A-01'),_p('b',2,zone:'A-02')];
    final store=MutationStore(original,optimized:false);
    final state=AppState(store:store);await state.init();
    store.failNextSave=true;

    await expectLater(state.optimizeFrom(-23.5,-46.6),throwsA(isA<StateError>()));

    expect(state.packages.map((p)=>p.id).toList(),['a','b']);
    expect(state.packages.map((p)=>p.physicalZone).toList(),['A-01','A-02']);
    expect(state.routeOptimized,isFalse);
    expect(store.optimized,isFalse);
  });

  test('retry preparation restores delivery status and load positions when persistence fails',() async {
    final original=[
      _p('absent',1,zone:'A-01',status:DeliveryStatus.absent),
      _p('pending',2,zone:'A-02',status:DeliveryStatus.pending),
    ];
    final store=MutationStore(original,optimized:true);
    final state=AppState(store:store);await state.init();
    store.failNextSave=true;

    await expectLater(
      state.prepareRetryRoute(-23.5,-46.6),
      throwsA(isA<StateError>()),
    );

    expect(state.packages.map((p)=>p.status).toList(),[
      DeliveryStatus.absent,
      DeliveryStatus.pending,
    ]);
    expect(state.packages.map((p)=>p.physicalZone).toList(),['A-01','A-02']);
    expect(state.routeOptimized,isTrue);
    expect(store.packages.first.status,DeliveryStatus.absent);
  });

  test('address edit restores every package position when persistence fails',() async {
    final original=[_p('a',1,zone:'A-01'),_p('b',2,zone:'A-02')];
    final store=MutationStore(original,optimized:true);
    final state=AppState(store:store);await state.init();
    const edited=AddressData(
      raw:'Rua Nova, 100',
      street:'Rua Nova',
      number:'100',
      city:'São Paulo',
      state:'SP',
      confidence:.8,
      validation:ValidationStatus.confirmed,
    );
    store.failNextSave=true;

    await expectLater(state.updateAddress(0,edited),throwsA(isA<StateError>()));

    expect(state.packages.first.address.raw,'Rua Teste, 1');
    expect(state.packages.map((p)=>p.physicalZone).toList(),['A-01','A-02']);
    expect(state.routeOptimized,isTrue);
    expect(store.packages.map((p)=>p.physicalZone).toList(),['A-01','A-02']);
  });
  });
}
