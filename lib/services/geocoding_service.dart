import '../domain/models.dart';

/// Contrato para geocodificação. A UI/domínio não depende de Google, HERE,
/// Mapbox ou outro fornecedor. A implementação real será plugável.
abstract class GeocodingService {
  Future<AddressData> locate(AddressData address);
}

class GeocodingException implements Exception {
  final String message;
  GeocodingException(this.message);
  @override String toString()=>message;
}
