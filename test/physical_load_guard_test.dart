import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/services/package_store.dart';
import 'package:flutter_test/flutter_test.dart';

class GuardStore implements PackageStore {
  GuardStore(this.packages,{this.optimized=false});

  List<DeliveryPackage> packages;
  bool optimized;
  int saves=0;

  @override
  Future<List<DeliveryPackage>> load() async => [...packages];

  @override
  Future<bool> loadRouteOptimized() async => optimized;

  @override
  Future<void> save(List<DeliveryPackage> value,{bool? routeOptimized}) async {
    packages=[...value];
    if(routeOptimized!=null) optimized=routeOptimized;
    saves++;
  }

  @override
  Future<void> clear() async {
    packages=[];
    optimized=false;
  }
}

DeliveryPackage _package(String id,int scan,{String? zone,DeliveryStatus status=DeliveryStatus.pending})=>DeliveryPackage(
  id:id,
  scanNumber:scan,
  physicalZone:zone,
  status:status,
  address:AddressData(
    raw:'Rua Teste, $scan',
    street:'Rua Teste',
    number:'$scan',
    city:'São Paulo',
    state:'SP',
    latitude:-23.55,
    longitude:-46.63,
    confidence:1,
    validation:ValidationStatus.confirmed,
  ),
  scannedAt:DateTime.utc(2026,9,13,13,scan),
);

void main(){
  test('physical load cannot be organized before route optimization',() async {
    final store=GuardStore([_package('a',1),_package('b',2)]);
    final state=AppState(store:store);
    await state.init();

    expect(
      () => state.organizePhysicalLoad(),
      throwsA(isA<StateError>()),
    );
    expect(state.packages.map((p)=>p.id).toList(),['a','b']);
    expect(state.packages.every((p)=>p.physicalZone==null),isTrue);
    expect(store.saves,0);
  });

  test('invalid physical load group size fails without changing packages',() async {
    final store=GuardStore([_package('a',1,zone:'A-01')],optimized:true);
    final state=AppState(store:store);
    await state.init();

    expect(
      () => state.organizePhysicalLoad(groupSize:0),
      throwsA(isA<ArgumentError>()),
    );
    expect(state.routeOptimized,isTrue);
    expect(state.packages.single.physicalZone,'A-01');
    expect(store.saves,0);
  });

  test('physical load preserves existing active positions unless overwrite is requested',() async {
    final store=GuardStore([
      _package('a',1,zone:'CUSTOM-09'),
      _package('b',2),
    ],optimized:true);
    final state=AppState(store:store);
    await state.init();

    await state.organizePhysicalLoad(groupSize:20);
    expect(state.packages[0].physicalZone,'CUSTOM-09');
    expect(state.packages[1].physicalZone,'A-02');

    await state.organizePhysicalLoad(groupSize:20,overwrite:true);
    expect(state.packages[0].physicalZone,'A-01');
    expect(state.packages[1].physicalZone,'A-02');
    expect(store.saves,2);
  });

  test('physical load skips delivered packages without consuming active positions',() async {
    final store=GuardStore([
      _package('done',1,zone:'HIST',status:DeliveryStatus.delivered),
      _package('active-a',2),
      _package('active-b',3),
    ],optimized:true);
    final state=AppState(store:store);
    await state.init();

    await state.organizePhysicalLoad(groupSize:20,overwrite:true);
    expect(state.packages[0].physicalZone,'HIST');
    expect(state.packages[1].physicalZone,'A-01');
    expect(state.packages[2].physicalZone,'A-02');
    expect(store.saves,1);
  });
}
