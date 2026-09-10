import 'dart:convert';
import 'package:http/http.dart' as http;
import '../domain/models.dart';
import 'geocoding_service.dart';

class NominatimGeocodingService implements GeocodingService {
  final http.Client client;
  NominatimGeocodingService({http.Client? client}):client=client??http.Client();

  @override Future<AddressData> locate(AddressData address) async {
    final query=address.formatted.isNotEmpty?address.formatted:address.raw;
    final uri=Uri.https('nominatim.openstreetmap.org','/search',{'q':query,'format':'jsonv2','limit':'1','countrycodes':'br'});
    final r=await client.get(uri,headers:{'User-Agent':'RotasEntregas/0.2 (mobile app)'});
    if(r.statusCode!=200) throw GeocodingException('Falha ao localizar endereço (${r.statusCode}).');
    final data=jsonDecode(r.body) as List;
    if(data.isEmpty) throw GeocodingException('Endereço não localizado. Revise antes de seguir.');
    final hit=Map<String,dynamic>.from(data.first);
    return AddressData(raw:address.raw,street:address.street,number:address.number,complement:address.complement,neighborhood:address.neighborhood,city:address.city,state:address.state,cep:address.cep,latitude:double.tryParse('${hit['lat']}'),longitude:double.tryParse('${hit['lon']}'),confidence:address.confidence,validation:address.validation);
  }
}
