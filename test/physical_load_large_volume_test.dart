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
  expect(state.packages,hasLength(600));expect(state.packages.first.physicalZone,'Chão do passageiro');expect(state.packages.last.physicalZone,'Porta-malas direito');expect(state.packages.every((p)=>p.physicalZone?.isNotEmpty==true),isTrue);expect(state.packages.map((p)=>p.id).toSet().length,600);expect(store.saves,1);
 });

 test('default physical organization uses only the 11 car zones at large volume',()async{
  final store=VolumeStore(List.generate(560,(i)=>_p(i+1)));final state=AppState(store:store);await state.init();
  await state.organizePhysicalLoad(overwrite:true);
  final labels=state.packages.map((p)=>p.physicalZone).whereType<String>().toSet();
  expect(labels.length,11);expect(labels,containsAll(<String>['Chão do passageiro','Banco do passageiro','Chão traseiro esquerdo','Chão traseiro centro','Chão traseiro direito','Banco traseiro esquerdo','Banco traseiro centro','Banco traseiro direito','Porta-malas esquerdo','Porta-malas centro','Porta-malas direito']));
 });

 test('custom group size scales beyond Z without dropping packages',()async{
  final store=VolumeStore(List.generate(300,(i)=>_p(i+1)));final state=AppState(store:store);await state.init();
  await state.organizePhysicalLoad(groupSize:10,overwrite:true);
  expect(state.packages,hasLength(300));expect(state.packages[249].physicalZone,'Y-10');expect(state.packages[250].physicalZone,'Z-01');expect(state.packages[259].physicalZone,'Z-10');expect(state.packages[260].physicalZone,'AA-01');expect(state.packages[299].physicalZone,'AD-10');expect(state.packages.map((p)=>p.id).toSet().length,300);
 });
}
