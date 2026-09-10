import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../domain/models.dart';
import '../services/osrm_service.dart';

class RouteMapScreen extends StatefulWidget {
  final List<DeliveryPackage> packages;
  const RouteMapScreen({super.key,required this.packages});
  @override State<RouteMapScreen> createState()=>_RouteMapScreenState();
}
class _RouteMapScreenState extends State<RouteMapScreen>{
  RoadRoute? road; String? error;
  List<DeliveryPackage> get located=>widget.packages.where((p)=>p.address.latitude!=null&&p.address.longitude!=null).toList();
  @override void initState(){super.initState();_load();}
  Future<void> _load()async{if(located.length<2)return;try{final r=await OsrmService().route(located);if(mounted)setState(()=>road=r);}catch(e){if(mounted)setState(()=>error='$e');}}
  @override Widget build(BuildContext context){if(located.isEmpty)return Scaffold(appBar:AppBar(title:const Text('Mapa da rota')),body:const Center(child:Text('Localize os endereços para exibir a rota.')));final center=LatLng(located.first.address.latitude!,located.first.address.longitude!);return Scaffold(appBar:AppBar(title:const Text('Mapa da rota')),body:Stack(children:[FlutterMap(options:MapOptions(initialCenter:center,initialZoom:12),children:[TileLayer(urlTemplate:'https://tile.openstreetmap.org/{z}/{x}/{y}.png',userAgentPackageName:'app.rotas.entregas'),if(road!=null)PolylineLayer(polylines:[Polyline(points:road!.geometry.map((p)=>LatLng(p[0],p[1])).toList(),strokeWidth:5)]),MarkerLayer(markers:[for(var i=0;i<located.length;i++)Marker(point:LatLng(located[i].address.latitude!,located[i].address.longitude!),width:42,height:42,child:CircleAvatar(child:Text('${i+1}')))])]),Positioned(left:12,right:12,bottom:12,child:Card(child:Padding(padding:const EdgeInsets.all(12),child:Text(error??(road==null?'Calculando rota...':'${road!.distanceKm.toStringAsFixed(1)} km • ${road!.duration.inMinutes} min • ${located.length} paradas')))))]));}
}
