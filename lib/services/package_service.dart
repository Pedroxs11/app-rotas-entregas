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

    if(tracking.isNotEmpty){
      final sameCode=existing.any((p)=>_normalizeCode(p.trackingCode)==tracking);
      if(sameCode)throw DuplicatePackageException('Pacote já escaneado: mesmo código de barras/QR.');
    }

    // Endereço é uma proteção secundária. Só bloqueia automaticamente quando há
    // dados estruturados suficientes; duas entregas reais podem existir no mesmo CEP.
    final key=_addressKey(address);
    if(key.isNotEmpty){
      final sameAddress=existing.any((p)=>_addressKey(p.address)==key);
      if(sameAddress)throw DuplicatePackageException('Possível pacote duplicado: mesmo endereço de entrega.');
    }

    return DeliveryPackage(
      id:_uuid.v4(),
      scanNumber:existing.length+1,
      trackingCode:trackingCode?.trim(),
      address:address,
      scannedAt:DateTime.now(),
    );
  }

  String _addressKey(AddressData a){
    final street=_normalizeText(a.street);
    final number=_normalizeText(a.number);
    final cep=_digits(a.cep);
    if(street.isEmpty||number.isEmpty)return '';
    // CEP aumenta muito a precisão quando disponível; sem ele usamos cidade/UF.
    if(cep.length==8)return '$street|$number|$cep';
    final city=_normalizeText(a.city);
    final state=_normalizeText(a.state);
    if(city.isEmpty&&state.isEmpty)return '';
    return '$street|$number|$city|$state';
  }

  String _normalizeCode(String? value)=>
      (value??'').toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'),'');

  String _normalizeText(String? value)=>
      (value??'')
          .toUpperCase()
          .replaceAll('Á','A').replaceAll('À','A').replaceAll('Â','A').replaceAll('Ã','A')
          .replaceAll('É','E').replaceAll('Ê','E')
          .replaceAll('Í','I')
          .replaceAll('Ó','O').replaceAll('Ô','O').replaceAll('Õ','O')
          .replaceAll('Ú','U').replaceAll('Ç','C')
          .replaceAll(RegExp(r'[^A-Z0-9]'),'');

  String _digits(String? value)=>(value??'').replaceAll(RegExp(r'\D'),'');
}
