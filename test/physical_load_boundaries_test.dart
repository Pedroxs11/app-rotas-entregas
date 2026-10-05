import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/services/package_store.dart';
import 'package:flutter_test/flutter_test.dart';

class LoadStore implements PackageStore {
  LoadStore(this.packages);
  List<DeliveryPackage> packages;
  bool optimized=true;
  int saves=0;
  @override Future<List<DeliveryPackage>> load()async=>[...packages];
  @override Future<bool> loadRouteOptimized()async=>optimized;
  @override Future<void> save(List<DeliveryPackage> value,{bool? routeOptimized})async{packages=[...value];if(routeOptimized!=null)optimized=routeOptimized;saves++;}
  @override Future<void> clear()async{packages=[];optimized=false;}
}

DeliveryPackage _p(int n,{DeliveryStatus status=DeliveryStatus.pending,String? zone})=>DeliveryPackage(
 id:'p$n',scanNumber:n,status:status,physicalZone:zone,
 address:AddressData(raw:'Rua $n',street:'Rua',number:'$n',city:'São Paulo',state:'SP',confidence:1,validation:ValidationStatus.confirmed),
 scannedAt:DateTime.utc(2026,9,13,22,n%60),
);

void main(){
 test('manual organization uses the five vehicle areas without auto distribution',()async{
  final store=LoadStore(List.generate(5,(i)=>_p(i+1)));final state=AppState(store:store);await state.init();
  expect(state.packages.every((p)=>p.physicalZone==null),isTrue);
  await state.setPhysicalZone('p1','Frente esquerda');
  await state.setPhysicalZone('p2','Frente direita');
  await state.setPhysicalZone('p3','Traseira esquerda');
  await state.setPhysicalZone('p4','Traseira direita');
  await state.setPhysicalZone('p5','Porta-malas');
  expect(state.packages.map((p)=>p.physicalZone).toList(),['Frente esquerda','Frente direita','Traseira esquerda','Traseira direita','Porta-malas']);
  expect(store.saves,5);
 });

 test('manual organization allows multiple packages in the same vehicle area',()async{
  final store=LoadStore(List.generate(8,(i)=>_p(i+1)));final state=AppState(store:store);await state.init();
  for(final p in state.packages.take(4))await state.setPhysicalZone(p.id,'Porta-malas');
  expect(state.packages.take(4).every((p)=>p.physicalZone=='Porta-malas'),isTrue);
 });
}
