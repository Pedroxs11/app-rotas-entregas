import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../app_state.dart';
import '../domain/models.dart';
import '../services/osrm_service.dart';
import 'load_screen.dart';

class RouteMapScreen extends StatefulWidget {
  final AppState state;
  const RouteMapScreen({super.key,required this.state});
  @override State<RouteMapScreen> createState()=>_RouteMapScreenState();
}
class _RouteMapScreenState extends State<RouteMapScreen>{
  RoadRoute? road; String? error;
  List<DeliveryPackage> get located=>widget.state.packages.where((p)=>p.address.latitude!=null&&p.address.longitude!=null).toList();
  @override void initState(){super.initState();_load();}
  Future<void> _load()async{final active=located.where((p)=>p.status==DeliveryStatus.pending||p.status==DeliveryStatus.current).toList();if(active.length<2)return;try{final r=await OsrmService().route(active);if(mounted)setState(()=>road=r);}catch(e){if(mounted)setState(()=>error='$e');}}
  IconData _icon(DeliveryPackage p){switch(p.status){case DeliveryStatus.delivered:return Icons.check;case DeliveryStatus.absent:return Icons.person_off;case DeliveryStatus.skipped:return Icons.skip_next;case DeliveryStatus.addressProblem:return Icons.priority_high;case DeliveryStatus.current:return Icons.navigation;case DeliveryStatus.pending:return p.pinned?Icons.push_pin:Icons.circle;}}
  String _status(DeliveryPackage p){switch(p.status){case DeliveryStatus.delivered:return'Entregue';case DeliveryStatus.absent:return'Ausente';case DeliveryStatus.skipped:return'Pulada';case DeliveryStatus.addressProblem:return'Problema no endereço';case DeliveryStatus.current:return'Atual';case DeliveryStatus.pending:return'Pendente';}}
  @override Widget build(BuildContext context){if(located.isEmpty)return Scaffold(appBar:AppBar(title:const Text('Conferir rota')),body:const Center(child:Text('Localize os endereços para exibir a rota.')));final center=LatLng(located.first.address.latitude!,located.first.address.longitude!);final active=located.where((p)=>p.status==DeliveryStatus.pending||p.status==DeliveryStatus.current).length;return Scaffold(appBar:AppBar(title:Text('Conferir rota • $active paradas')),body:Column(children:[Expanded(child:Stack(children:[FlutterMap(options:MapOptions(initialCenter:center,initialZoom:12),children:[TileLayer(urlTemplate:'https://tile.openstreetmap.org/{z}/{x}/{y}.png',userAgentPackageName:'app.rotas.entregas'),if(road!=null)PolylineLayer(polylines:[Polyline(points:road!.geometry.map((p)=>LatLng(p[0],p[1])).toList(),strokeWidth:5)]),MarkerLayer(markers:[for(var i=0;i<located.length;i++)Marker(point:LatLng(located[i].address.latitude!,located[i].address.longitude!),width:46,height:46,child:GestureDetector(onTap:()=>_showStop(context,located[i],i),child:CircleAvatar(child:located[i].status==DeliveryStatus.pending?Text('${i+1}'):Icon(_icon(located[i]),size:20))))]),RichAttributionWidget(attributions:[TextSourceAttribution('OpenStreetMap contributors')])]),Positioned(left:12,right:12,bottom:12,child:Card(child:Padding(padding:const EdgeInsets.all(12),child:Text(error??(road==null?(active<2?'$active parada restante':'Calculando rota...'):'${road!.distanceKm.toStringAsFixed(1)} km • ${road!.duration.inMinutes} min • $active paradas'),textAlign:TextAlign.center))))])),SafeArea(top:false,child:Padding(padding:const EdgeInsets.fromLTRB(16,10,16,16),child:SizedBox(width:double.infinity,child:FilledButton.icon(onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>LoadScreen(state:widget.state))),icon:const Icon(Icons.format_list_numbered),label:const Padding(padding:EdgeInsets.all(15),child:Text('VER ORDEM DOS PACOTES'))))))]));}
  Future<void> _showStop(BuildContext context,DeliveryPackage p,int index)=>showModalBottomSheet(context:context,builder:(c)=>SafeArea(child:Padding(padding:const EdgeInsets.all(18),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[Text('Parada ${index+1} • ${p.label}',style:Theme.of(context).textTheme.titleLarge),const SizedBox(height:6),Text(_status(p),style:const TextStyle(fontWeight:FontWeight.bold)),const SizedBox(height:12),Text(p.address.formatted.isEmpty?p.address.raw:p.address.formatted),if(p.pinned)const Padding(padding:EdgeInsets.only(top:8),child:Text('📌 Parada fixada'))]))));
}
