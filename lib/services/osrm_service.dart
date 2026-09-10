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
  OsrmService({http.Client? client}):client=client??http.Client();

  Future<RoadRoute> route(List<DeliveryPackage> stops) async {
    final located=stops.where((p)=>p.address.latitude!=null&&p.address.longitude!=null).toList();
    if(located.length<2) throw Exception('São necessários pelo menos dois endereços localizados.');
    final coords=located.map((p)=>'${p.address.longitude},${p.address.latitude}').join(';');
    final uri=Uri.parse('https://router.project-osrm.org/route/v1/driving/$coords?overview=full&geometries=geojson');
    final r=await client.get(uri);
    if(r.statusCode!=200) throw Exception('Falha ao calcular rota viária.');
    final json=jsonDecode(r.body) as Map<String,dynamic>;
    if(json['code']!='Ok'||(json['routes'] as List).isEmpty) throw Exception('Rota viária não encontrada.');
    final route=Map<String,dynamic>.from((json['routes'] as List).first);
    final geometry=Map<String,dynamic>.from(route['geometry']);
    final points=(geometry['coordinates'] as List).map((p){final x=p as List;return <double>[(x[1] as num).toDouble(),(x[0] as num).toDouble()];}).toList();
    return RoadRoute(distanceKm:(route['distance'] as num).toDouble()/1000,duration:Duration(seconds:(route['duration'] as num).round()),geometry:points);
  }
}
