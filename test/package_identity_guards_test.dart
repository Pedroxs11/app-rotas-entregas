import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/services/address_parser.dart';
import 'package:app_rotas_entregas/services/package_service.dart';
import 'package:flutter_test/flutter_test.dart';

DeliveryPackage _existing(String code)=>DeliveryPackage(
 id:'old',scanNumber:1,trackingCode:code,
 address:const AddressData(raw:'Rua Antiga, 1',street:'Rua Antiga',number:'1',city:'São Paulo',state:'SP',confidence:1,validation:ValidationStatus.confirmed),
 scannedAt:DateTime.utc(2026,9,13),
);

void main(){
 final service=PackageService(AddressParser());
 const recipient='DESTINATARIO\nRua Nova, 100\nSão Paulo SP\n01001-000';

 test('same physical code is duplicate despite case spaces and punctuation',(){
  final existing=[_existing('BR-12 34.ab')];
  expect(()=>service.fromOcr(recipient,existing,trackingCode:' br1234AB '),throwsA(isA<DuplicatePackageException>()));
 });

 test('same delivery address with different physical codes creates distinct packages',(){
  final first=service.fromOcr(recipient,[],trackingCode:'CODE-A');
  final second=service.fromOcr(recipient,[first],trackingCode:'CODE-B');
  expect(second.id,isNot(first.id));expect(second.scanNumber,2);expect(second.address.raw,first.address.raw);expect(second.trackingCode,'CODE-B');
 });

 test('same address without physical identifier is allowed more than once',(){
  final first=service.fromOcr(recipient,[]);
  final second=service.fromOcr(recipient,[first]);
  expect(first.scanNumber,1);expect(second.scanNumber,2);expect(first.id,isNot(second.id));expect(first.trackingCode,isNull);expect(second.trackingCode,isNull);
 });

 test('sender-only label is rejected before a package can be created',(){
  const sender='REMETENTE\nRua Origem, 10\nSão Paulo SP\n01001-000';
  expect(()=>service.fromOcr(sender,[],trackingCode:'NEW-CODE'),throwsA(isA<SenderOnlyLabelException>()));
 });

 test('label containing recipient and sender is not rejected as sender-only',(){
  const mixed='DESTINATARIO\nRua Destino, 200\nSão Paulo SP\n01001-000\nREMETENTE\nRua Origem, 10';
  final p=service.fromOcr(mixed,[],trackingCode:'MIXED-1');
  expect(p.scanNumber,1);expect(p.trackingCode,'MIXED-1');expect(p.address.raw,mixed);
 });

 test('tracking code is trimmed for storage while duplicate comparison stays normalized',(){
  final p=service.fromOcr(recipient,[],trackingCode:'  BR-XYZ-99  ');
  expect(p.trackingCode,'BR-XYZ-99');
  expect(()=>service.fromOcr(recipient,[p],trackingCode:'br xyz 99'),throwsA(isA<DuplicatePackageException>()));
 });
}
