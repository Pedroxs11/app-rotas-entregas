import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class CepResult {
  final String cep, street, neighborhood, city, state;
  const CepResult({required this.cep,required this.street,required this.neighborhood,required this.city,required this.state});
}

abstract class CepService {
  Future<CepResult?> lookup(String cep);
}

class ViaCepService implements CepService {
  final http.Client _client;
  final Map<String,CepResult?> _cache={};
  final Map<String,Future<CepResult?>> _inFlight={};
  ViaCepService({http.Client? client}):_client=client??http.Client();

  @override
  Future<CepResult?> lookup(String cep) async {
    final digits=cep.replaceAll(RegExp(r'\D'),'');
    if(digits.length!=8)return null;
    if(_cache.containsKey(digits))return _cache[digits];
    final running=_inFlight[digits];if(running!=null)return running;
    final future=_fetch(digits);_inFlight[digits]=future;
    try{final result=await future;_cache[digits]=result;return result;}finally{_inFlight.remove(digits);}
  }

  Future<CepResult?> _fetch(String digits) async {
    final response=await _client.get(Uri.parse('https://viacep.com.br/ws/$digits/json/')).timeout(const Duration(seconds:6));
    if(response.statusCode!=200)return null;
    final json=jsonDecode(response.body) as Map<String,dynamic>;
    if(json['erro']==true)return null;
    return CepResult(cep:(json['cep']??digits).toString(),street:(json['logradouro']??'').toString(),neighborhood:(json['bairro']??'').toString(),city:(json['localidade']??'').toString(),state:(json['uf']??'').toString().toUpperCase());
  }

  void clearCache()=>_cache.clear();
  void dispose()=>_client.close();
}
