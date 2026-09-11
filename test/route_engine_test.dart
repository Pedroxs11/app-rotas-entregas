import 'package:flutter_test/flutter_test.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/services/route_engine.dart';

DeliveryPackage pkg(String id,double? lat,double? lng)=>DeliveryPackage(
 id:id,scanNumber:int.parse(id.substring(1)),scannedAt:DateTime(2026),
 address:AddressData(raw:id,latitude:lat,longitude:lng,confidence:1,validation:ValidationStatus.confirmed),
);

void main(){
 final engine=RouteEngine();
 test('nearest stop from driver becomes first',(){
  final near=pkg('p1',-23.501,-46.601);final far=pkg('p2',-23.7,-46.8);final middle=pkg('p3',-23.55,-46.65);
  final out=engine.optimize([far,middle,near],startLat:-23.5,startLng:-46.6);
  expect(out.first.id,'p1');
  expect(out.map((e)=>e.id).toSet(),{'p1','p2','p3'});
 });
 test('unlocated packages are preserved at end',(){
  final out=engine.optimize([pkg('p1',-23.51,-46.61),pkg('p2',null,null),pkg('p3',-23.52,-46.62)],startLat:-23.5,startLng:-46.6);
  expect(out.length,3);expect(out.last.id,'p2');
 });
 test('optimization never drops or duplicates a large batch',(){
  final input=List.generate(300,(i)=>pkg('p${i+1}',-23.5-i/10000,-46.6-i/10000));
  final out=engine.optimize(input,startLat:-23.5,startLng:-46.6);
  expect(out.length,300);expect(out.map((e)=>e.id).toSet().length,300);expect(out.map((e)=>e.id).toSet(),input.map((e)=>e.id).toSet());
 });
 test('manual move preserves all packages',(){
  final input=[pkg('p1',-23.1,-46.1),pkg('p2',-23.2,-46.2),pkg('p3',-23.3,-46.3)];
  final out=engine.move(input,0,3);
  expect(out.map((e)=>e.id).toList(),['p2','p3','p1']);
 });
}
