import 'package:app_rotas_entregas/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

AddressData _address()=>const AddressData(
 raw:'Rua Teste, 100',street:'Rua Teste',number:'100',complement:'Apto 2',neighborhood:'Centro',city:'São Paulo',state:'SP',cep:'01001-000',latitude:-23.55,longitude:-46.63,confidence:1,validation:ValidationStatus.confirmed,
);

DeliveryPackage _package()=>DeliveryPackage(
 id:'pkg',scanNumber:7,trackingCode:'BR123456789012345',recipient:'Cliente',physicalZone:'A-07',address:_address(),scannedAt:DateTime.utc(2026,9,13,23),completedAt:DateTime.utc(2026,9,13,23,30),pinned:true,status:DeliveryStatus.delivered,
);

void main(){
 test('copyWith changes requested fields and preserves package identity/history by default',(){
  final original=_package();final changed=original.copyWith(status:DeliveryStatus.absent,pinned:false);
  expect(changed.id,original.id);expect(changed.scanNumber,original.scanNumber);expect(changed.scannedAt,original.scannedAt);expect(changed.trackingCode,original.trackingCode);expect(changed.recipient,original.recipient);expect(changed.physicalZone,original.physicalZone);expect(changed.completedAt,original.completedAt);expect(changed.status,DeliveryStatus.absent);expect(changed.pinned,isFalse);
 });

 test('explicit clear flags remove only the requested optional values',(){
  final original=_package();final changed=original.copyWith(clearPhysicalZone:true,clearTrackingCode:true,clearRecipient:true,clearCompletedAt:true);
  expect(changed.physicalZone,isNull);expect(changed.trackingCode,isNull);expect(changed.recipient,isNull);expect(changed.completedAt,isNull);expect(changed.id,original.id);expect(changed.address.raw,original.address.raw);expect(changed.pinned,isTrue);expect(changed.status,DeliveryStatus.delivered);
 });

 test('package labels stay stable and physical label falls back when zone is blank',(){
  final original=_package();expect(original.label,'Pacote 07');expect(original.physicalLabel,'A-07');
  expect(original.copyWith(physicalZone:'  ').physicalLabel,'Pacote 07');expect(original.copyWith(clearPhysicalZone:true).physicalLabel,'Pacote 07');
 });

 test('short tracking never exposes more than twelve trailing characters for long codes',(){
  final original=_package();expect(original.shortTracking,'…456789012345');
  expect(original.copyWith(trackingCode:'ABC123').shortTracking,'ABC123');expect(original.copyWith(clearTrackingCode:true).shortTracking,isNull);
 });

 test('address formatted output contains populated delivery components in order',(){
  expect(_address().formatted,'Rua Teste, 100, Apto 2, Centro, São Paulo, SP, 01001-000');
 });

 test('copy and JSON roundtrip together preserve cleared optional fields',(){
  final cleared=_package().copyWith(clearPhysicalZone:true,clearCompletedAt:true,clearRecipient:true);
  final restored=DeliveryPackage.fromJson(cleared.toJson());
  expect(restored.id,'pkg');expect(restored.physicalZone,isNull);expect(restored.completedAt,isNull);expect(restored.recipient,isNull);expect(restored.trackingCode,'BR123456789012345');expect(restored.pinned,isTrue);expect(restored.status,DeliveryStatus.delivered);
 });
}
