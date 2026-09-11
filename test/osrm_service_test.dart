import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/services/osrm_service.dart';

DeliveryPackage stop(int i) => DeliveryPackage(
  id: 'p$i', scanNumber: i, scannedAt: DateTime(2026),
  address: AddressData(raw: 'P$i', latitude: -23.0-i/1000, longitude: -46.0-i/1000, confidence: 1, validation: ValidationStatus.confirmed),
);

String okRoute(double meters, int seconds) => jsonEncode({'code':'Ok','routes':[{'distance':meters,'duration':seconds,'geometry':{'coordinates':[[-46.0,-23.0],[-46.1,-23.1]]}}]});

void main(){
 test('requires at least two located stops',() async {
  final service=OsrmService(client:MockClient((_) async=>http.Response('{}',200)));
  await expectLater(service.route([stop(1)]),throwsException);
 });
 test('rejects invalid request chunk size',() async {
  final service=OsrmService(client:MockClient((_) async=>http.Response('{}',200)),maxStopsPerRequest:1);
  await expectLater(service.route([stop(1),stop(2)]),throwsStateError);
 });
 test('chunks large routes with one-stop overlap and aggregates totals',() async {
  final paths=<String>[];
  final service=OsrmService(client:MockClient((request) async {
    paths.add(request.url.path);
    return http.Response(okRoute(1000,60),200);
  }),maxStopsPerRequest:3);
  final route=await service.route(List.generate(7,(i)=>stop(i+1)));
  expect(paths.length,3);
  expect(paths[0],contains('route/v1/driving'));
  expect(route.distanceKm,3);
  expect(route.duration,const Duration(minutes:3));
  expect(route.geometry.length,4);
 });
 test('surfaces HTTP and OSRM route errors',() async {
  final httpFailure=OsrmService(client:MockClient((_) async=>http.Response('down',503)));
  await expectLater(httpFailure.route([stop(1),stop(2)]),throwsException);
  final noRoute=OsrmService(client:MockClient((_) async=>http.Response('{"code":"NoRoute","routes":[]}',200)));
  await expectLater(noRoute.route([stop(1),stop(2)]),throwsException);
 });
}
