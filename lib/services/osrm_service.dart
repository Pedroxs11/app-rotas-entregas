import 'dart:convert';
import 'package:http/http.dart' as http;
import '../domain/models.dart';

class RoadRoute {
  final double distanceKm;
  final Duration duration;
  final List<List<double>> geometry;
  const RoadRoute({required this.distanceKm,required this.duration,required this.geometry});
}

class OsrmService {
  final http.Client client;
  final int maxStopsPerRequest;
  OsrmService({http.Client? client,this.maxStopsPerRequest=40}):client=client??http.Client();

  Future<RoadRoute> route(List<DeliveryPackage> stops) async {
    final located=stops.where((p)=>p.address.latitude!=null&&p.address.longitude!=null).toList();
    if(located.length<2) throw Exception('São necessários pelo menos dois endereços localizados.');
    if(maxStopsPerRequest<2) throw StateError('maxStopsPerRequest deve ser pelo menos 2.');
    if(located.length<=maxStopsPerRequest)return _routeChunk(located);

    var distance=0.0;var seconds=0;final geometry=<List<double>>[];
    var start=0;
    while(start<located.length-1){
      final end=(start+maxStopsPerRequest).clamp(0,located.length);
      final chunk=located.sublist(start,end);
      final part=await _routeChunk(chunk);
      distance+=part.distanceKm;seconds+=part.duration.inSeconds;
      if(geometry.isEmpty){geometry.addAll(part.geometry);}else if(part.geometry.isNotEmpty){geometry.addAll(part.geometry.skip(1));}
      if(end>=located.length)break;
      start=end-1;
    }
    return RoadRoute(distanceKm:distance,duration:Duration(seconds:seconds),geometry:geometry);
  }

  Future<RoadRoute> _routeChunk(List<DeliveryPackage> located)async{
    final coords=located.map((p)=>'${p.address.longitude},${p.address.latitude}').join(';');
    final uri=Uri.parse('https://router.project-osrm.org/route/v1/driving/$coords?overview=full&geometries=geojson');
    final r=await client.get(uri).timeout(const Duration(seconds:15));
    if(r.statusCode!=200) throw Exception('Falha ao calcular rota viária (${r.statusCode}).');
    final json=jsonDecode(r.body) as Map<String,dynamic>;
    if(json['code']!='Ok'||(json['routes'] as List? ?? const []).isEmpty) throw Exception('Rota viária não encontrada.');
    final route=Map<String,dynamic>.from((json['routes'] as List).first);
    final geometry=Map<String,dynamic>.from(route['geometry']);
    final points=(geometry['coordinates'] as List).map((p){final x=p as List;return <double>[(x[1] as num).toDouble(),(x[0] as num).toDouble()];}).toList();
    return RoadRoute(distanceKm:(route['distance'] as num).toDouble()/1000,duration:Duration(seconds:(route['duration'] as num).round()),geometry:points);
  }
}
