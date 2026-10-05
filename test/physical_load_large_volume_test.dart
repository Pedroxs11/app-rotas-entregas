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
}
