import 'dart:convert';
import 'package:http/http.dart' as http;
import '../domain/models.dart';
import 'geocoding_service.dart';

class NominatimGeocodingService implements GeocodingService {
  final http.Client client;
  NominatimGeocodingService({http.Client? client}):client=client??http.Client();

  @override Future<AddressData> locate(AddressData address) async {
    final queries=_queries(address);
    for(final query in queries){
      final hit=await _search(query);
      if(hit!=null){
        final lat=double.tryParse('${hit['lat']}');
        final lon=double.tryParse('${hit['lon']}');
        if(lat!=null&&lon!=null){
          return AddressData(raw:address.raw,street:address.street,number:address.number,complement:address.complement,neighborhood:address.neighborhood,city:address.city,state:address.state,cep:address.cep,latitude:lat,longitude:lon,confidence:address.confidence,validation:address.validation);
        }
      }
    }
    throw GeocodingException('Endereço não localizado. Revise antes de seguir.');
  }

  Future<Map<String,dynamic>?> _search(String query) async {
    final uri=Uri.https('nominatim.openstreetmap.org','/search',{'q':query,'format':'jsonv2','limit':'1','countrycodes':'br','addressdetails':'1'});
    final r=await client.get(uri,headers:{'User-Agent':'RotasEntregas/0.2 (mobile app)','Accept-Language':'pt-BR,pt;q=0.9'});
    if(r.statusCode!=200) throw GeocodingException('Falha ao localizar endereço (${r.statusCode}).');
    final data=jsonDecode(r.body) as List;
    if(data.isEmpty)return null;
    return Map<String,dynamic>.from(data.first);
  }

  List<String> _queries(AddressData a){
    final out=<String>[];
    void add(Iterable<String?> parts){
      final q=parts.whereType<String>().map((e)=>e.trim()).where((e)=>e.isNotEmpty).join(', ');
      if(q.isNotEmpty&&!out.contains(q))out.add(q);
    }
    // Do not send apartment/house complements as part of the location query.
    // Start precise, then relax only fields that commonly make Nominatim miss
    // otherwise valid Brazilian addresses.
    add([a.street,a.number,a.neighborhood,a.city,a.state,a.cep]);
    add([a.street,a.number,a.city,a.state,a.cep]);
    add([a.street,a.number,a.neighborhood,a.city,a.state]);
    add([a.street,a.number,a.city,a.state]);
    add([a.street,a.neighborhood,a.city,a.state,a.cep]);
    add([a.street,a.city,a.state,a.cep]);
    add([a.street,a.neighborhood,a.city,a.state]);
    add([a.street,a.city,a.state]);
    if(out.isEmpty){
      final raw=a.raw.trim();
      if(raw.isNotEmpty)out.add(raw);
    }
    return out;
  }
}
