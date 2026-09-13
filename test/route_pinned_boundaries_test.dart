import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/services/package_store.dart';
import 'package:flutter_test/flutter_test.dart';

class PinStore implements PackageStore {
 PinStore(this.packages);List<DeliveryPackage> packages;bool optimized=false;int saves=0;
 @override Future<List<DeliveryPackage>> load()async=>[...packages];
 @override Future<bool> loadRouteOptimized()async=>optimized;
 @override Future<void> save(List<DeliveryPackage> value,{bool? routeOptimized})async{packages=[...value];if(routeOptimized!=null)optimized=routeOptimized;saves++;}
 @override Future<void> clear()async{packages=[];optimized=false;}
}

DeliveryPackage _p(String id,int scan,double lat,double lng,{bool pinned=false})=>DeliveryPackage(
 id:id,scanNumber:scan,pinned:pinned,
 address:AddressData(raw:'Rua $scan',street:'Rua',number:'$scan',city:'São Paulo',state:'SP',latitude:lat,longitude:lng,confidence:1,validation:ValidationStatus.confirmed),
 scannedAt:DateTime.utc(2026,9,13,23,scan),
);

void main(){
 test('multiple pinned stops keep their original route slots while free stops optimize',()async{
  final store=PinStore([
   _p('free-far',1,-23.70,-46.80),
   _p('pin-one',2,-23.90,-46.90,pinned:true),
   _p('free-near',3,-23.5501,-46.6301),
   _p('pin-two',4,-23.80,-46.85,pinned:true),
   _p('free-mid',5,-23.57,-46.65),
  ]);
  final state=AppState(store:store);await state.init();await state.optimizeFrom(-23.55,-46.63);
  expect(state.packages[1].id,'pin-one');expect(state.packages[3].id,'pin-two');expect(state.packages.where((p)=>!p.pinned).map((p)=>p.id).toList(),['free-near','free-mid','free-far']);expect(state.packages.map((p)=>p.id).toSet(),{'free-far','pin-one','free-near','pin-two','free-mid'});expect(state.routeOptimized,isTrue);expect(store.saves,1);
 });

 test('pinned first and last stops remain at route boundaries',()async{
  final store=PinStore([
   _p('pin-first',1,-23.90,-46.90,pinned:true),
   _p('free-far',2,-23.70,-46.80),
   _p('free-near',3,-23.5501,-46.6301),
   _p('pin-last',4,-23.80,-46.85,pinned:true),
  ]);
  final state=AppState(store:store);await state.init();await state.optimizeFrom(-23.55,-46.63);
  expect(state.packages.first.id,'pin-first');expect(state.packages.last.id,'pin-last');expect(state.packages[1].id,'free-near');expect(state.packages[2].id,'free-far');
 });

 test('all pinned active stops preserve the complete original order',()async{
  final original=[_p('a',1,-23.7,-46.8,pinned:true),_p('b',2,-23.55,-46.63,pinned:true),_p('c',3,-23.6,-46.7,pinned:true)];
  final store=PinStore(original);final state=AppState(store:store);await state.init();await state.optimizeFrom(-23.55,-46.63);
  expect(state.packages.map((p)=>p.id).toList(),['a','b','c']);expect(state.packages.every((p)=>p.pinned),isTrue);expect(state.routeOptimized,isTrue);
 });

 test('pinned optimization never changes physical load labels',()async{
  final original=_p('pin',1,-23.8,-46.8,pinned:true).copyWith(physicalZone:'A-01');
  final free=_p('free',2,-23.5501,-46.6301).copyWith(physicalZone:'A-02');
  final store=PinStore([original,free]);final state=AppState(store:store);await state.init();await state.optimizeFrom(-23.55,-46.63);
  expect(state.packages.firstWhere((p)=>p.id=='pin').physicalZone,'A-01');expect(state.packages.firstWhere((p)=>p.id=='free').physicalZone,'A-02');
 });
}
