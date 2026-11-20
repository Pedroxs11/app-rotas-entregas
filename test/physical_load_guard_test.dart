import 'dart:async';
import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/services/package_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GuardStore implements PackageStore {
  GuardStore(this.packages,{this.optimized=false,this.failSaves=false});
  bool failSaves;
  List<DeliveryPackage> packages;
  bool optimized;
  int saves=0;
  @override Future<List<DeliveryPackage>> load()async=>[...packages];
  @override Future<bool> loadRouteOptimized()async=>optimized;
  @override Future<void> save(List<DeliveryPackage> value,{bool? routeOptimized})async{if(failSaves)throw StateError('simulated storage failure');packages=[...value];if(routeOptimized!=null)optimized=routeOptimized;saves++;}
  @override Future<void> clear()async{packages=[];optimized=false;}
}

class BlockingGuardStore implements PackageStore {
  BlockingGuardStore(this.packages, {this.optimized = true});

  List<DeliveryPackage> packages;
  bool optimized;
  final List<Completer<void>> pendingWrites = [];
  final List<List<DeliveryPackage>> snapshots = [];

  @override
  Future<List<DeliveryPackage>> load() async => [...packages];

  @override
  Future<bool> loadRouteOptimized() async => optimized;

  @override
  Future<void> save(List<DeliveryPackage> value, {bool? routeOptimized}) async {
    final gate = Completer<void>();
    pendingWrites.add(gate);
    snapshots.add([...value]);
    await gate.future;
    packages = [...value];
    if (routeOptimized != null) optimized = routeOptimized;
  }

  @override
  Future<void> clear() async {
    packages = [];
    optimized = false;
  }
}

DeliveryPackage _package(String id,int scan,{String? zone,DeliveryStatus status=DeliveryStatus.pending})=>DeliveryPackage(
 id:id,scanNumber:scan,physicalZone:zone,status:status,
 address:AddressData(raw:'Rua Teste, $scan',street:'Rua Teste',number:'$scan',city:'São Paulo',state:'SP',latitude:-23.55,longitude:-46.63,confidence:1,validation:ValidationStatus.confirmed),
 scannedAt:DateTime.utc(2026,9,13,13,scan),
);

void main(){
 test('manual position cannot be assigned before route optimization',()async{
  final store=GuardStore([_package('a',1),_package('b',2)]);
  final state=AppState(store:store);await state.init();
  expect(()=>state.setPhysicalZone('a','Frente esquerda'),throwsA(isA<StateError>()));
  expect(state.packages.every((p)=>p.physicalZone==null),isTrue);
  expect(store.saves,0);
 });

 test('invalid vehicle zone fails without changing package',()async{
  final store=GuardStore([_package('a',1)],optimized:true);final state=AppState(store:store);await state.init();
  expect(()=>state.setPhysicalZone('a','Banco traseiro'),throwsA(isA<ArgumentError>()));
  expect(state.packages.single.physicalZone,isNull);
  expect(store.saves,0);
 });

 test('manual position can be moved and cleared',()async{
  final store=GuardStore([_package('a',1,zone:'Frente esquerda'),_package('b',2)],optimized:true);final state=AppState(store:store);await state.init();
  await state.setPhysicalZone('a','Porta-malas');
  expect(state.packages[0].physicalZone,'Porta-malas');
  await state.setPhysicalZone('a',null);
  expect(state.packages[0].physicalZone,isNull);
  expect(store.saves,2);
 });

 test('delivered package cannot be manually reorganized',()async{
  final store=GuardStore([_package('done',1,zone:'Porta-malas',status:DeliveryStatus.delivered)],optimized:true);final state=AppState(store:store);await state.init();
  expect(()=>state.setPhysicalZone('done','Frente esquerda'),throwsA(isA<StateError>()));
  expect(state.packages.single.physicalZone,'Porta-malas');
  expect(store.saves,0);
 });

 test('inactive skipped packages cannot be reassigned, including in a bulk operation',()async{
  final store=GuardStore([
   _package('active',1),
   _package('skipped',2,zone:'Porta-malas',status:DeliveryStatus.skipped),
  ],optimized:true);
  final state=AppState(store:store);await state.init();

  await expectLater(
   state.setPhysicalZones({'active','skipped'},'Frente esquerda'),
   throwsA(isA<StateError>()),
  );
  expect(state.packages.first.physicalZone,isNull);
  expect(state.packages.last.physicalZone,'Porta-malas');
  expect(store.saves,0);

  await expectLater(
   state.setPhysicalZone('skipped','Frente esquerda'),
   throwsA(isA<StateError>()),
  );
  expect(state.packages.last.physicalZone,'Porta-malas');
  expect(store.saves,0);
 });


 test('bulk clear rejects delivered packages atomically',()async{
  final store=GuardStore([
   _package('active',1,zone:'Frente esquerda'),
   _package('done',2,zone:'Porta-malas',status:DeliveryStatus.delivered),
  ],optimized:true);
  final state=AppState(store:store);await state.init();

  await expectLater(
   state.clearPhysicalZones({'active','done'}),
   throwsA(isA<StateError>()),
  );
  expect(state.packages[0].physicalZone,'Frente esquerda');
  expect(state.packages[1].physicalZone,'Porta-malas');
  expect(store.saves,0);
 });

 test('bulk clear rejects unknown package ids without partial changes',()async{
  final store=GuardStore([
   _package('active',1,zone:'Frente esquerda'),
  ],optimized:true);
  final state=AppState(store:store);await state.init();

  await expectLater(
   state.clearPhysicalZones({'active','missing'}),
   throwsA(isA<StateError>()),
  );
  expect(state.packages.single.physicalZone,'Frente esquerda');
  expect(store.saves,0);
 });

 test('bulk clear requires route optimization and preserves current positions',()async{
  final store=GuardStore([
   _package('active',1,zone:'Frente esquerda'),
  ],optimized:false);
  final state=AppState(store:store);await state.init();

  await expectLater(
   state.clearPhysicalZones({'active'}),
   throwsA(isA<StateError>()),
  );
  expect(state.packages.single.physicalZone,'Frente esquerda');
  expect(store.saves,0);
 });


 test('bulk assignment rolls back in-memory positions when persistence fails',()async{
  final store=GuardStore([_package('a',1),_package('b',2)],optimized:true,failSaves:true);
  final state=AppState(store:store);await state.init();

  await expectLater(
   state.setPhysicalZones({'a','b'},'Frente esquerda'),
   throwsA(isA<StateError>()),
  );
  expect(state.packages.every((p)=>p.physicalZone==null),isTrue);
  expect(store.saves,0);
 });

 test('bulk clear rolls back in-memory positions when persistence fails',()async{
  final store=GuardStore([
   _package('a',1,zone:'Frente esquerda'),
   _package('b',2,zone:'Porta-malas'),
  ],optimized:true,failSaves:true);
  final state=AppState(store:store);await state.init();

  await expectLater(
   state.clearPhysicalZones({'a','b'}),
   throwsA(isA<StateError>()),
  );
  expect(state.packages[0].physicalZone,'Frente esquerda');
  expect(state.packages[1].physicalZone,'Porta-malas');
  expect(store.saves,0);
 });

 test('individual assignment and clearing roll back in-memory positions when persistence fails',()async{
  final store=GuardStore([
   _package('a',1,zone:'Porta-malas'),
  ],optimized:true,failSaves:true);
  final state=AppState(store:store);
  await state.init();

  await expectLater(
   state.setPhysicalZone('a','Frente esquerda'),
   throwsA(isA<StateError>()),
  );
  expect(state.packages.single.physicalZone,'Porta-malas');

  await expectLater(
   state.setPhysicalZone('a',null),
   throwsA(isA<StateError>()),
  );
  expect(state.packages.single.physicalZone,'Porta-malas');
  expect(store.saves,0);
 });

 test('serializes load assignments and vehicle switches while storage writes are pending',()async{
  SharedPreferences.setMockInitialValues({});
  final store=BlockingGuardStore([
   _package('a',1),
   _package('b',2),
  ]);
  final state=AppState(store:store);
  await state.init();

  final firstAssignment=state.setPhysicalZone('a','Frente esquerda');
  await Future<void>.delayed(Duration.zero);
  expect(store.pendingWrites,hasLength(1));

  final secondAssignment=state.setPhysicalZone('b','Porta-malas');
  final vehicleSwitch=state.setVehicleType(VehicleType.motorcycle);
  await Future<void>.delayed(Duration.zero);

  expect(store.pendingWrites,hasLength(1),
   reason:'Later load changes must wait for the active storage write.');
  expect(state.vehicleType,VehicleType.car);
  expect(state.packages[0].physicalZone,'Frente esquerda');
  expect(state.packages[1].physicalZone,isNull);

  store.pendingWrites[0].complete();
  await firstAssignment;
  await Future<void>.delayed(Duration.zero);

  expect(store.pendingWrites,hasLength(2));
  expect(store.snapshots[1][0].physicalZone,'Frente esquerda');
  expect(store.snapshots[1][1].physicalZone,'Porta-malas');
  expect(state.vehicleType,VehicleType.car);

  store.pendingWrites[1].complete();
  await secondAssignment;
  await Future<void>.delayed(Duration.zero);

  expect(store.pendingWrites,hasLength(3));
  expect(store.snapshots[2].every((p)=>p.physicalZone==null),isTrue);
  expect(state.vehicleType,VehicleType.car);

  store.pendingWrites[2].complete();
  await vehicleSwitch;

  expect(state.vehicleType,VehicleType.motorcycle);
  expect(state.packages.every((p)=>p.physicalZone==null),isTrue);
  expect(store.packages.map((p)=>p.physicalZone),[null,null]);
 });

 test('car and motorcycle compartments cannot be mixed',()async{
  SharedPreferences.setMockInitialValues({'load_vehicle_type':'car'});
  final carStore=GuardStore([_package('car-package',1)],optimized:true);
  final carState=AppState(store:carStore);
  await carState.init();

  await expectLater(
   carState.setPhysicalZone('car-package','Baú traseiro'),
   throwsA(isA<ArgumentError>()),
  );
  expect(carState.packages.single.physicalZone,isNull);
  expect(carStore.saves,0);

  SharedPreferences.setMockInitialValues({'load_vehicle_type':'motorcycle'});
  final motorcycleStore=GuardStore([_package('motorcycle-package',1)],optimized:true);
  final motorcycleState=AppState(store:motorcycleStore);
  await motorcycleState.init();

  await expectLater(
   motorcycleState.setPhysicalZone('motorcycle-package','Porta-malas'),
   throwsA(isA<ArgumentError>()),
  );
  expect(motorcycleState.packages.single.physicalZone,isNull);
  expect(motorcycleStore.saves,0);
 });

}

  SharedPreferences.setMockInitialValues({'load_vehicle_type':'car'});
  final carStore=GuardStore([_package('car-package',1)],optimized:true);
  final carState=AppState(store:carStore);
  await carState.init();

  await expectLater(
   carState.setPhysicalZone('car-package','Baú traseiro'),
   throwsA(isA<ArgumentError>()),
  );
  expect(carState.packages.single.physicalZone,isNull);
  expect(carStore.saves,0);

  SharedPreferences.setMockInitialValues({'load_vehicle_type':'motorcycle'});
  final motorcycleStore=GuardStore([_package('motorcycle-package',1)],optimized:true);
  final motorcycleState=AppState(store:motorcycleStore);
  await motorcycleState.init();

  await expectLater(
   motorcycleState.setPhysicalZone('motorcycle-package','Porta-malas'),
   throwsA(isA<ArgumentError>()),
  );
  expect(motorcycleState.packages.single.physicalZone,isNull);
  expect(motorcycleStore.saves,0);
 });

}
