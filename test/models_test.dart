import 'package:flutter_test/flutter_test.dart';
import 'package:app_rotas_entregas/domain/models.dart';

void main() {
  const address = AddressData(
    raw: 'Rua Exemplo, 10',
    street: 'Rua Exemplo',
    number: '10',
    confidence: 1,
    validation: ValidationStatus.confirmed,
  );

  DeliveryPackage package() => DeliveryPackage(
        id: 'pkg-1',
        scanNumber: 1,
        trackingCode: 'TRACK123',
        recipient: 'Cliente',
        physicalZone: 'A-01',
        address: address,
        scannedAt: DateTime(2026, 9, 11, 10),
        completedAt: DateTime(2026, 9, 11, 11),
        status: DeliveryStatus.delivered,
      );

  test('copyWith can explicitly clear nullable operational fields', () {
    final cleared = package().copyWith(
      clearPhysicalZone: true,
      clearTrackingCode: true,
      clearRecipient: true,
      clearCompletedAt: true,
    );

    expect(cleared.physicalZone, isNull);
    expect(cleared.trackingCode, isNull);
    expect(cleared.recipient, isNull);
    expect(cleared.completedAt, isNull);
  });

  test('json round trip preserves completion and physical load data', () {
    final original = package();
    final restored = DeliveryPackage.fromJson(original.toJson());

    expect(restored.id, original.id);
    expect(restored.physicalZone, 'A-01');
    expect(restored.completedAt, original.completedAt);
    expect(restored.status, DeliveryStatus.delivered);
  });

  test('json round trip preserves complete package details', () {
    final scannedAt = DateTime.utc(2026, 9, 13, 2, 45);
    final original = DeliveryPackage(
      id: 'pkg-complete',
      scanNumber: 42,
      trackingCode: 'BR123456789SP',
      recipient: 'Destinatário Teste',
      physicalZone: 'C-07',
      address: const AddressData(
        raw: 'Rua das Flores, 321, Bloco B, Centro, São Paulo - SP, 01001-000',
        street: 'Rua das Flores',
        number: '321',
        complement: 'Bloco B',
        neighborhood: 'Centro',
        city: 'São Paulo',
        state: 'SP',
        cep: '01001-000',
        latitude: -23.5505,
        longitude: -46.6333,
        confidence: .93,
        validation: ValidationStatus.confirmed,
      ),
      scannedAt: scannedAt,
      pinned: true,
      status: DeliveryStatus.current,
    );

    final restored = DeliveryPackage.fromJson(original.toJson());
    expect(restored.id, original.id);
    expect(restored.scanNumber, 42);
    expect(restored.trackingCode, 'BR123456789SP');
    expect(restored.recipient, 'Destinatário Teste');
    expect(restored.physicalZone, 'C-07');
    expect(restored.scannedAt, scannedAt);
    expect(restored.pinned, isTrue);
    expect(restored.status, DeliveryStatus.current);
    expect(restored.address.raw, original.address.raw);
    expect(restored.address.street, 'Rua das Flores');
    expect(restored.address.number, '321');
    expect(restored.address.complement, 'Bloco B');
    expect(restored.address.neighborhood, 'Centro');
    expect(restored.address.city, 'São Paulo');
    expect(restored.address.state, 'SP');
    expect(restored.address.cep, '01001-000');
    expect(restored.address.latitude, -23.5505);
    expect(restored.address.longitude, -46.6333);
    expect(restored.address.confidence, .93);
    expect(restored.address.validation, ValidationStatus.confirmed);
  });

  test('older saved package without completedAt remains compatible', () {
    final json = package().toJson()..remove('completedAt');
    final restored = DeliveryPackage.fromJson(json);

    expect(restored.completedAt, isNull);
    expect(restored.physicalZone, 'A-01');
  });
}
