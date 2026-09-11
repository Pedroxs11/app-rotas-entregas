import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:app_rotas_entregas/services/cep_service.dart';

void main() {
  test('normalizes CEP and maps ViaCEP response fields', () async {
    var calls = 0;
    final service = ViaCepService(
      client: MockClient((request) async {
        calls++;
        final normalized = '01310-200'.replaceAll('-', '');
        expect(request.url.path, '/ws/$normalized/json/');
        return http.Response(
          '{"cep":"01310-200","logradouro":"Avenida Paulista","bairro":"Bela Vista","localidade":"São Paulo","uf":"sp"}',
          200,
        );
      }),
    );
    final result = await service.lookup('01310-200');
    expect(result?.street, 'Avenida Paulista');
    expect(result?.neighborhood, 'Bela Vista');
    expect(result?.city, 'São Paulo');
    expect(result?.state, 'SP');
    expect(calls, 1);
  });

  test('invalid CEP does not make an HTTP request', () async {
    var calls = 0;
    final service = ViaCepService(client: MockClient((request) async {calls++;return http.Response('{}', 200);}));
    expect(await service.lookup('123'), isNull);
    expect(calls, 0);
  });

  test('cached CEP is requested only once', () async {
    var calls = 0;
    final service = ViaCepService(client: MockClient((request) async {calls++;return http.Response('{"cep":"01310-200","logradouro":"Avenida Paulista","bairro":"Bela Vista","localidade":"São Paulo","uf":"SP"}',200);}));
    await service.lookup('01310-200');
    await service.lookup('01310200');
    expect(calls, 1);
  });

  test('simultaneous lookup for same CEP shares one request', () async {
    var calls = 0;
    final gate = Completer<void>();
    final service = ViaCepService(client: MockClient((request) async {calls++;await gate.future;return http.Response('{"cep":"01310-200","logradouro":"Avenida Paulista","bairro":"Bela Vista","localidade":"São Paulo","uf":"SP"}',200);}));
    final first = service.lookup('01310-200');
    final second = service.lookup('01310200');
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
    gate.complete();
    final results = await Future.wait([first, second]);
    expect(results[0]?.street, 'Avenida Paulista');
    expect(results[1]?.street, 'Avenida Paulista');
  });

  test('ViaCEP error and non-200 responses return null', () async {
    var calls = 0;
    final service = ViaCepService(client: MockClient((request) async {calls++;if (calls == 1) return http.Response('{"erro":true}', 200);return http.Response('indisponível', 503);}));
    expect(await service.lookup('99999999'), isNull);
    expect(await service.lookup('88888888'), isNull);
  });
}
