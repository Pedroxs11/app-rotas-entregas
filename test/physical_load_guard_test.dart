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

DeliveryPackage _package(String id,int scan,{String? zone})=>DeliveryPackage(
  id:id,
  scanNumber:scan,
  physicalZone:zone,
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
}
