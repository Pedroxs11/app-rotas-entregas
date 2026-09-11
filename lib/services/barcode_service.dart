import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

class BarcodeService {
  final BarcodeScanner _scanner=BarcodeScanner();

  Future<String?> recognizeFile(String path) async {
    final input=InputImage.fromFilePath(path);
    final codes=await _scanner.processImage(input);
    final values=codes
        .map((b)=>b.rawValue?.trim())
        .whereType<String>()
        .where((v)=>v.isNotEmpty)
        .toList();
    if(values.isEmpty)return null;
    // Prefere identificadores mais específicos/longos quando a etiqueta tem
    // vários códigos. O valor é usado para vínculo e deduplicação, não como endereço.
    values.sort((a,b)=>b.length.compareTo(a.length));
    return values.first;
  }

  Future<void> dispose()=>_scanner.close();
}
