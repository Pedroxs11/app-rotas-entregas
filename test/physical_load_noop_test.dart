import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/services/package_store.dart';
import 'package:flutter_test/flutter_test.dart';

class NoopLoadStore implements PackageStore{
 NoopLoadStore(this.packages);List<DeliveryPackage> packages;bool optimized=true;int saves=0;
 @override Future<List<DeliveryPackage>> load()async=>[...packages];
 @override Future<bool> loadRouteOptimized()async=>optimized;
 @override Future<void> save(List<DeliveryPackage> value,{bool? routeOptimized})async{packages=[...value];if(routeOptimized!=null)optimized=routeOptimized;saves++;}
 @override Future<void> clear()async{packages=[];optimized=false;}
}
DeliveryPackage _p(String id,int n,DeliveryStatus status,String zone)=>DeliveryPackage(id:id,scanNumber:n,status:status,physicalZone:zone,address:AddressData(raw:'Rua $n',street:'Rua',number:'$n',city:'São Paulo',state:'SP',confidence:1,validation:ValidationStatus.confirmed),scannedAt:DateTime.utc(2026,9,13,21,n),completedAt:status==DeliveryStatus.delivered?DateTime.utc(2026,9,13,21,40):null);
void main(){
 test('manual organization does not change delivered or skipped history',()async{
  final done=_p('done',1,DeliveryStatus.delivered,'Porta-malas');final skipped=_p('skip',2,DeliveryStatus.skipped,'Traseira direita');final store=NoopLoadStore([done,skipped]);final state=AppState(store:store);await state.init();
  expect(()=>state.setPhysicalZone('done','Frente esquerda'),throwsA(isA<StateError>()));
  expect(state.packages.map((p)=>p.physicalZone).toList(),['Porta-malas','Traseira direita']);
  expect(state.packages.first.completedAt,done.completedAt);
  expect(store.saves,0);
 });
}
