import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/services/nominatim_geocoding_service.dart';

void main() {
  test('fallback de geocodificação preserva número original do imóvel', () async {
    final requested = <Uri>[];
    final client = MockClient((request) async {
      requested.add(request.url);
      if (requested.length == 1) {
        return http.Response('[]', 200);
      }
      return http.Response(
        jsonEncode([
          {'lat': '-23.6501', 'lon': '-46.7652'}
        ]),
        200,
      );
    });

    final service = NominatimGeocodingService(client: client);
    const address = AddressData(
      raw: 'Rua Anum-Branco, 303, Jardim Dom José, São Paulo, SP, 05887-300',
      street: 'Rua Anum-Branco',
      number: '303',
      complement: 'Casa 2',
      neighborhood: 'Jardim Dom José',
      city: 'São Paulo',
      state: 'SP',
      cep: '05887-300',
      confidence: .95,
      validation: ValidationStatus.confirmed,
    );

    final located = await service.locate(address);

    expect(requested.length, 2);
    expect(requested.first.queryParameters['q'], contains('303'));
    expect(requested.first.queryParameters['q'], isNot(contains('Casa 2')));
    expect(located.number, '303');
    expect(located.complement, 'Casa 2');
    expect(located.latitude, -23.6501);
    expect(located.longitude, -46.7652);
  });
}
