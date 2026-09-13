import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/services/package_store.dart';
import 'package:flutter_test/flutter_test.dart';

class VolumeStore implements PackageStore {
 VolumeStore(this.packages);List<DeliveryPackage> packages;bool optimized=true;int saves=0;
 @override Future<List<DeliveryPackage>> load()async=>[...packages];
 @override Future<bool> loadRouteOptimized()async=>optimized;
 @override Future<void> save(List<DeliveryPackage> value,{bool? routeOptimized})async{packages=[...value];if(routeOptimized!=null)optimized=routeOptimized;saves++;}
 @override Future<void> clear()async{packages=[];optimized=false;}
}

DeliveryPackage _p(int n)=>DeliveryPackage(
 id:'p$n',scanNumber:n,
 address:AddressData(raw:'Rua $n',street:'Rua',number:'$n',city:'São Paulo',state:'SP',confidence:1,validation:ValidationStatus.confirmed),
 scannedAt:DateTime.utc(2026,9,13).add(Duration(minutes:n)),
);

void main(){
 test('physical organization handles hundreds of packages with no product cap',()async{
  final store=VolumeStore(List.generate(600,(i)=>_p(i+1)));final state=AppState(store:store);await state.init();
  await state.organizePhysicalLoad(overwrite:true);
  expect(state.packages,hasLength(600));expect(state.packages.first.physicalZone,'A-01');expect(state.packages[19].physicalZone,'A-20');expect(state.packages[20].physicalZone,'B-01');expect(state.packages[519].physicalZone,'Z-20');expect(state.packages[520].physicalZone,'AA-01');expect(state.packages[599].physicalZone,'AD-20');expect(state.packages.map((p)=>p.id).toSet().length,600);expect(store.saves,1);
 });

 test('large load labels remain unique across alphabet rollover',()async{
  final store=VolumeStore(List.generate(560,(i)=>_p(i+1)));final state=AppState(store:store);await state.init();
  await state.organizePhysicalLoad(overwrite:true);
  final labels=state.packages.map((p)=>p.physicalZone).toList();
  expect(labels.whereType<String>().toSet().length,560);expect(labels[499],'Y-20');expect(labels[500],'Z-01');expect(labels[519],'Z-20');expect(labels[520],'AA-01');expect(labels[539],'AA-20');expect(labels[540],'AB-01');
 });

 test('custom group size scales beyond Z without dropping packages',()async{
  final store=VolumeStore(List.generate(300,(i)=>_p(i+1)));final state=AppState(store:store);await state.init();
  await state.organizePhysicalLoad(groupSize:10,overwrite:true);
  expect(state.packages,hasLength(300));expect(state.packages[249].physicalZone,'Y-10');expect(state.packages[250].physicalZone,'Z-01');expect(state.packages[259].physicalZone,'Z-10');expect(state.packages[260].physicalZone,'AA-01');expect(state.packages[299].physicalZone,'AD-10');expect(state.packages.map((p)=>p.id).toSet().length,300);
 });
}
