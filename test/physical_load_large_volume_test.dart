import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/services/package_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class VolumeStore implements PackageStore {
 VolumeStore(this.packages);List<DeliveryPackage> packages;bool optimized=true;int saves=0;
 @override Future<List<DeliveryPackage>> load()async=>[...packages];
 @override Future<bool> loadRouteOptimized()async=>optimized;
 @override Future<void> save(List<DeliveryPackage> value,{bool? routeOptimized})async{packages=[...value];if(routeOptimized!=null)optimized=routeOptimized;saves++;}
 @override Future<void> clear()async{packages=[];optimized=false;}
}
DeliveryPackage _p(int n)=>DeliveryPackage(id:'p$n',scanNumber:n,address:AddressData(raw:'Rua $n',street:'Rua',number:'$n',city:'São Paulo',state:'SP',confidence:1,validation:ValidationStatus.confirmed),scannedAt:DateTime.utc(2026,9,13).add(Duration(minutes:n)));

void main(){
 test('manual organization supports large routes without automatic assignment',()async{
  final store=VolumeStore(List.generate(600,(i)=>_p(i+1)));final state=AppState(store:store);await state.init();
  expect(state.packages,hasLength(600));
  expect(state.packages.every((p)=>p.physicalZone==null),isTrue);
  await state.setPhysicalZone('p1','Frente esquerda');
  await state.setPhysicalZone('p600','Porta-malas');
  expect(state.packages.first.physicalZone,'Frente esquerda');
  expect(state.packages.last.physicalZone,'Porta-malas');
  expect(state.packages,hasLength(600));
 });

 test('200 packages can be bulk-organized in car and motorcycle compartments',()async{
  SharedPreferences.setMockInitialValues({});
  final store=VolumeStore(List.generate(200,(i)=>_p(i+1)));
  final state=AppState(store:store);
  await state.init();

  final allIds=state.packages.map((p)=>p.id).toSet();
  expect(allIds,hasLength(200));
  await state.setPhysicalZones(allIds,'Porta-malas');
  expect(state.packages.every((p)=>p.physicalZone=='Porta-malas'),isTrue);

  await state.setVehicleType(VehicleType.motorcycle);
  expect(state.packages.every((p)=>p.physicalZone==null),isTrue);
  expect(state.activePhysicalZones,contains('Baú traseiro'));

  await state.setPhysicalZones(allIds,'Baú traseiro');
  expect(state.packages,hasLength(200));
  expect(state.packages.every((p)=>p.physicalZone=='Baú traseiro'),isTrue);
  expect(store.saves,greaterThan(0));
 });

 test('600 packages can be bulk-assigned across every car and motorcycle compartment',()async{
  for(final vehicle in [VehicleType.car,VehicleType.motorcycle]){
   SharedPreferences.setMockInitialValues({'load_vehicle_type':vehicle.name});
   final zones=vehicle==VehicleType.car
       ?AppState.carPhysicalZones
       :AppState.motorcyclePhysicalZones;
   final expectedPerZone=600~/zones.length;
   final store=VolumeStore(List.generate(600,(i)=>_p(i+1)));
   final state=AppState(store:store);
   await state.init();

   expect(state.vehicleType,vehicle);
   expect(state.routeOptimized,isTrue);
   expect(state.packages,hasLength(600));

   for(var zoneIndex=0;zoneIndex<zones.length;zoneIndex++){
    final ids=state.packages
        .skip(zoneIndex*expectedPerZone)
        .take(expectedPerZone)
        .map((p)=>p.id)
        .toSet();
    expect(ids,hasLength(expectedPerZone));
    await state.setPhysicalZones(ids,zones[zoneIndex]);
   }

   expect(state.packages,hasLength(600));
   expect(state.packages.every((p)=>p.physicalZone!=null),isTrue);
   for(final zone in zones){
    expect(
     state.packages.where((p)=>p.physicalZone==zone),
     hasLength(expectedPerZone),
     reason:'$vehicle must retain the expected package count in $zone',
    );
   }
   expect(state.routeOptimized,isTrue);
   expect(store.packages.map((p)=>p.id).toSet(),hasLength(600));
   expect(store.saves,zones.length);
  }
 });

 test('bulk assigned compartments survive a fresh app state for car and motorcycle',()async{
  for(final vehicle in [VehicleType.car,VehicleType.motorcycle]){
   SharedPreferences.setMockInitialValues({});
   final isMotorcycle=vehicle==VehicleType.motorcycle;
   final customZones=isMotorcycle
       ?['Baú traseiro','Bolsa lateral esquerda']
       :['Frente direita','Porta-malas'];
   final assignedZone=isMotorcycle
       ?'Bolsa lateral esquerda'
       :'Porta-malas';
   final historicalZone=isMotorcycle?'Porta-malas':'Baú traseiro';
   final store=VolumeStore([
    _p(1),
    _p(2),
    _p(3),
    _p(4).copyWith(
     status:DeliveryStatus.delivered,
     physicalZone:historicalZone,
    ),
   ]);
   final firstSession=AppState(store:store);
   await firstSession.init();
   if(isMotorcycle)await firstSession.setVehicleType(VehicleType.motorcycle);
   await firstSession.setActivePhysicalZones(customZones);
   await firstSession.setPhysicalZones({'p1','p2','p3'},assignedZone);
   final savesBeforeRestart=store.saves;

   final resumedSession=AppState(store:store);
   await resumedSession.init();

   expect(resumedSession.vehicleType,vehicle);
   expect(resumedSession.activePhysicalZones,customZones);
   expect(
    resumedSession.packages.take(3).every((p)=>p.physicalZone==assignedZone),
    isTrue,
   );
   expect(resumedSession.packages.last.status,DeliveryStatus.delivered);
   expect(resumedSession.packages.last.physicalZone,historicalZone);
   expect(store.saves,savesBeforeRestart);
  }
 });

 test('car and motorcycle compartment preferences remain independent across repeated vehicle switches',()async{
  SharedPreferences.setMockInitialValues({});
  final historicalPackage=_p(3).copyWith(
   status:DeliveryStatus.delivered,
   physicalZone:'Baú traseiro',
  );
  final store=VolumeStore([_p(1),_p(2),historicalPackage]);
  final state=AppState(store:store);
  await state.init();

  const carZones=['Frente direita','Porta-malas'];
  const motorcycleZones=['Baú traseiro','Bolsa lateral esquerda'];

  await state.setActivePhysicalZones(carZones);
  await state.setPhysicalZone('p1','Porta-malas');

  await state.setVehicleType(VehicleType.motorcycle);
  expect(state.activePhysicalZones,AppState.motorcyclePhysicalZones);
  expect(state.packages[0].physicalZone,isNull);
  await state.setActivePhysicalZones(motorcycleZones);
  await state.setPhysicalZone('p2','Bolsa lateral esquerda');
  expect(state.packages[1].physicalZone,'Bolsa lateral esquerda');

  await state.setVehicleType(VehicleType.car);
  expect(state.activePhysicalZones,carZones);
  expect(state.packages[0].physicalZone,isNull);
  expect(state.packages[1].physicalZone,isNull);
  expect(state.packages.last.physicalZone,'Baú traseiro');

  await state.setVehicleType(VehicleType.motorcycle);
  expect(state.activePhysicalZones,motorcycleZones);
  expect(state.packages.every((p)=>p.status==DeliveryStatus.delivered||p.physicalZone==null),isTrue);
  expect(state.packages.last.physicalZone,'Baú traseiro');

  final resumed=AppState(store:store);
  await resumed.init();
  expect(resumed.vehicleType,VehicleType.motorcycle);
  expect(resumed.activePhysicalZones,motorcycleZones);
  expect(resumed.packages.last.physicalZone,'Baú traseiro');
 });

 test('moving a subset between compartments preserves the remaining 600-package load after restart for both vehicles',()async{
  for(final vehicle in [VehicleType.car,VehicleType.motorcycle]){
   SharedPreferences.setMockInitialValues({'load_vehicle_type':vehicle.name});
   final zones=vehicle==VehicleType.car
       ?AppState.carPhysicalZones
       :AppState.motorcyclePhysicalZones;
   final store=VolumeStore(List.generate(600,(i)=>_p(i+1)));
   final state=AppState(store:store);
   await state.init();

   final firstBatch=state.packages.take(137).map((p)=>p.id).toSet();
   final movedBatch=state.packages.take(37).map((p)=>p.id).toSet();
   await state.setPhysicalZones(firstBatch,zones[0]);
   await state.setPhysicalZones(movedBatch,zones[1]);

   expect(state.packages,hasLength(600));
   expect(state.packages.map((p)=>p.id).toSet(),hasLength(600));
   expect(state.packages.where((p)=>p.physicalZone==zones[0]),hasLength(100));
   expect(state.packages.where((p)=>p.physicalZone==zones[1]),hasLength(37));
   expect(state.packages.where((p)=>p.physicalZone==null),hasLength(463));
   expect(store.saves,2);

   final savesBeforeRestart=store.saves;
   final resumed=AppState(store:store);
   await resumed.init();

   expect(resumed.vehicleType,vehicle);
   expect(resumed.activePhysicalZones,zones);
   expect(resumed.packages,hasLength(600));
   expect(resumed.packages.map((p)=>p.id).toSet(),hasLength(600));
   expect(resumed.packages.where((p)=>p.physicalZone==zones[0]),hasLength(100));
   expect(resumed.packages.where((p)=>p.physicalZone==zones[1]),hasLength(37));
   expect(resumed.packages.where((p)=>p.physicalZone==null),hasLength(463));
   expect(store.saves,savesBeforeRestart);
  }
 });

}
