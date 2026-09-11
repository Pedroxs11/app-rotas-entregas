import 'package:uuid/uuid.dart';
import '../domain/models.dart';
import 'address_parser.dart';

class DuplicatePackageException implements Exception {
  final String message;
  DuplicatePackageException(this.message);
  @override String toString()=>message;
}

class PackageService {
  final AddressParser parser;
  final _uuid=const Uuid();
  PackageService(this.parser);

  DeliveryPackage fromOcr(String text,List<DeliveryPackage> existing,{String? trackingCode}) {
    final address=parser.parse(text);
    final tracking=_normalizeCode(trackingCode);

    // Endereço igual NÃO significa pacote duplicado: uma casa pode receber vários
    // volumes. Só bloqueamos automaticamente quando o identificador físico é igual.
    if(tracking.isNotEmpty){
      final sameCode=existing.any((p)=>_normalizeCode(p.trackingCode)==tracking);
      if(sameCode)throw DuplicatePackageException('Pacote já escaneado: mesmo código de barras/QR.');
    }

    return DeliveryPackage(
      id:_uuid.v4(),
      scanNumber:existing.length+1,
      trackingCode:trackingCode?.trim(),
      address:address,
      scannedAt:DateTime.now(),
    );
  }

  String _normalizeCode(String? value)=>
      (value??'').toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'),'');
}
