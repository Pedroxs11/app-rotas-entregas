import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/services/route_engine.dart';
import 'package:flutter_test/flutter_test.dart';

DeliveryPackage _p(String id,int scan,{double? lat,double? lng})=>DeliveryPackage(
  id:id,scanNumber:scan,
  address:AddressData(raw:'Rua $scan',street:'Rua',number:'$scan',city:'São Paulo',state:'SP',latitude:lat,longitude:lng,confidence:1,validation:ValidationStatus.confirmed),
  scannedAt:DateTime.utc(2026,9,13,20,scan),
);

void main(){
  final engine=RouteEngine();

  test('empty route stays empty',(){
    expect(engine.optimize([],startLat:-23.55,startLng:-46.63),isEmpty);
  });

  test('single located package is preserved exactly',(){
    final only=_p('only',1,lat:-23.55,lng:-46.63);
    final out=engine.optimize([only],startLat:-23.50,startLng:-46.60);
    expect(out.map((p)=>p.id).toList(),['only']);
  });

  test('missing driver coordinate preserves original order',(){
    final input=[_p('far',1,lat:-23.70,lng:-46.80),_p('near',2,lat:-23.5501,lng:-46.6301)];
    expect(engine.optimize(input,startLat:null,startLng:-46.63).map((p)=>p.id).toList(),['far','near']);
    expect(engine.optimize(input,startLat:-23.55,startLng:null).map((p)=>p.id).toList(),['far','near']);
  });

  test('unlocated packages remain after every located stop and keep relative order',(){
    final input=[
      _p('unlocated-a',1),
      _p('far',2,lat:-23.60,lng:-46.70),
      _p('unlocated-b',3),
      _p('near',4,lat:-23.5501,lng:-46.6301),
      _p('middle',5,lat:-23.57,lng:-46.65),
    ];
    final out=engine.optimize(input,startLat:-23.55,startLng:-46.63);
    expect(out.map((p)=>p.id).toList(),['near','middle','far','unlocated-a','unlocated-b']);
  });

  test('equal-distance candidates keep original priority deterministically',(){
    final input=[_p('first',1,lat:-23.55,lng:-46.62),_p('second',2,lat:-23.55,lng:-46.64),_p('third',3,lat:-23.60,lng:-46.70)];
    final out=engine.optimize(input,startLat:-23.55,startLng:-46.63);
    expect(out.first.id,'first');
    expect(out.map((p)=>p.id).toSet(),{'first','second','third'});
  });

  test('optimization never mutates input list or loses package identities',(){
    final input=[_p('a',1,lat:-23.60,lng:-46.70),_p('b',2,lat:-23.5501,lng:-46.6301),_p('c',3)];
    final before=input.map((p)=>p.id).toList();
    final out=engine.optimize(input,startLat:-23.55,startLng:-46.63);
    expect(input.map((p)=>p.id).toList(),before);expect(out.map((p)=>p.id).toSet(),before.toSet());expect(out,hasLength(input.length));
  });

  test('manual move down and up keeps every package exactly once',(){
    final route=[_p('a',1),_p('b',2),_p('c',3),_p('d',4)];
    final down=engine.move(route,0,4);
    expect(down.map((p)=>p.id).toList(),['b','c','d','a']);
    final up=engine.move(down,3,0);
    expect(up.map((p)=>p.id).toList(),['a','b','c','d']);
    expect(route.map((p)=>p.id).toList(),['a','b','c','d']);
  });
}
