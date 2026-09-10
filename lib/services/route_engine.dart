import 'dart:math';
import '../domain/models.dart';

class RouteEngine {
  /// Heurística nearest-neighbor para V1. Será substituível por matriz viária/OR-Tools.
  List<DeliveryPackage> optimize(List<DeliveryPackage> input,{double? startLat,double? startLng}) {
    final located=input.where((p)=>p.address.latitude!=null && p.address.longitude!=null).toList();
    final unlocated=input.where((p)=>p.address.latitude==null || p.address.longitude==null).toList();
    if(located.length<2 || startLat==null || startLng==null) return [...input];
    final result=<DeliveryPackage>[];
    var lat=startLat; var lng=startLng;
    while(located.isNotEmpty){
      located.sort((a,b)=>_distance(lat,lng,a.address.latitude!,a.address.longitude!).compareTo(_distance(lat,lng,b.address.latitude!,b.address.longitude!)));
      final next=located.removeAt(0); result.add(next); lat=next.address.latitude!; lng=next.address.longitude!;
    }
    return [...result,...unlocated];
  }
  double _distance(double a,double b,double c,double d){ final x=(d-b)*cos((a+c)/2*pi/180); final y=c-a; return sqrt(x*x+y*y); }

  List<DeliveryPackage> move(List<DeliveryPackage> route,int oldIndex,int newIndex){ final out=[...route]; if(newIndex>oldIndex)newIndex--; final item=out.removeAt(oldIndex); out.insert(newIndex,item); return out; }
}
