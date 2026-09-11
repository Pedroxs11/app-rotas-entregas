import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'tracking_code_selector.dart';

class BarcodeService {
  final BarcodeScanner _scanner=BarcodeScanner();

  Future<String?> recognizeFile(String path) async {
    final input=InputImage.fromFilePath(path);
    final codes=await _scanner.processImage(input);
    final values=codes.map((b)=>b.rawValue?.trim()).whereType<String>().where((v)=>v.isNotEmpty);
    return TrackingCodeSelector.chooseBest(values);
  }

  String? chooseBest(Iterable<String> values)=>TrackingCodeSelector.chooseBest(values);
  Future<void> dispose()=>_scanner.close();
}
