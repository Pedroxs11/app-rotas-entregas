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

  test('older saved package without completedAt remains compatible', () {
    final json = package().toJson()..remove('completedAt');
    final restored = DeliveryPackage.fromJson(json);

    expect(restored.completedAt, isNull);
    expect(restored.physicalZone, 'A-01');
  });
}
