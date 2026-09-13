import 'package:flutter_test/flutter_test.dart';
import 'package:app_rotas_entregas/services/address_parser.dart';
import 'package:app_rotas_entregas/services/package_service.dart';

void main(){
  final service=PackageService(AddressParser());
  const address='Rua Vergueiro, 1000, Liberdade, São Paulo - SP, 01504-001';

  test('same tracking code is a duplicate',(){
    final first=service.fromOcr(address,[],trackingCode:'AB-123 456');
    expect(()=>service.fromOcr(address,[first],trackingCode:'ab123456'),throwsA(isA<DuplicatePackageException>()));
  });

  test('different parcels may share exactly the same address',(){
    final first=service.fromOcr(address,[],trackingCode:'PKG001');
    final second=service.fromOcr(address,[first],trackingCode:'PKG002');
    expect(second.trackingCode,'PKG002');
  });

  test('address alone never causes hard duplicate rejection',(){
    final first=service.fromOcr(address,[]);
    expect(()=>service.fromOcr(address,[first]),returnsNormally);
  });

  test('sender-only label never becomes a delivery package',(){
    const senderOnly='REMETENTE\nRUA ORIGEM 99\nCURITIBA PR\n80000-000';
    expect(
      ()=>service.fromOcr(senderOnly,[],trackingCode:'PKG-SENDER'),
      throwsA(isA<SenderOnlyLabelException>()),
    );
  });

  test('label containing sender and recipient is not rejected as sender-only',(){
    const fullLabel='REMETENTE\nRUA ORIGEM 99\nDESTINATARIO\nRUA VERGUEIRO 1000\nSAO PAULO SP\n01504-001';
    expect(()=>service.fromOcr(fullLabel,[],trackingCode:'PKG-DEST'),returnsNormally);
  });
}
