import 'package:uuid/uuid.dart';
import '../domain/models.dart';
import 'address_parser.dart';

class DuplicatePackageException implements Exception { final String message; DuplicatePackageException(this.message); }

class PackageService {
  final AddressParser parser;
  final _uuid=const Uuid();
  PackageService(this.parser);

  DeliveryPackage fromOcr(String text,List<DeliveryPackage> existing,{String? trackingCode}) {
    final address=parser.parse(text);
    final normalized=_normalize(address.formatted.isEmpty?text:address.formatted);
    final duplicate=existing.any((p)=>(trackingCode!=null && trackingCode.isNotEmpty && p.trackingCode==trackingCode) || _normalize(p.address.formatted)==normalized);
    if(duplicate) throw DuplicatePackageException('Este pacote parece já ter sido escaneado.');
    return DeliveryPackage(id:_uuid.v4(),scanNumber:existing.length+1,trackingCode:trackingCode,address:address,scannedAt:DateTime.now());
  }

  String _normalize(String value)=>value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'),'');
}
