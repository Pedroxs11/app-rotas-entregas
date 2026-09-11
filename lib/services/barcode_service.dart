import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

class BarcodeService {
  final BarcodeScanner _scanner=BarcodeScanner();

  Future<String?> recognizeFile(String path) async {
    final input=InputImage.fromFilePath(path);
    final codes=await _scanner.processImage(input);
    final values=codes.map((b)=>b.rawValue?.trim()).whereType<String>().where((v)=>v.isNotEmpty).toSet().toList();
    return chooseBest(values);
  }

  /// Etiquetas brasileiras podem trazer rastreio, QR de URL e chave de NF-e
  /// na mesma foto. Não escolhemos mais simplesmente o maior valor.
  String? chooseBest(Iterable<String> values){
    final list=values.map((v)=>v.trim()).where((v)=>v.isNotEmpty).toList();
    if(list.isEmpty)return null;
    list.sort((a,b)=>_score(b).compareTo(_score(a)));
    return list.first;
  }

  int _score(String value){
    final compact=value.replaceAll(RegExp(r'\s+'),'');
    final upper=compact.toUpperCase();
    var score=0;
    final url=RegExp(r'^(HTTPS?://|WWW\.)',caseSensitive:false).hasMatch(compact);
    final fiscalKey=RegExp(r'^\d{44}$').hasMatch(compact);
    final jsonLike=compact.startsWith('{')||compact.startsWith('[');
    if(url)score-=100;
    if(fiscalKey)score-=90;
    if(jsonLike)score-=80;
    if(compact.length>=8&&compact.length<=32)score+=30;
    if(RegExp(r'^[A-Z0-9._-]+$').hasMatch(upper))score+=20;
    if(RegExp(r'[A-Z]').hasMatch(upper)&&RegExp(r'\d').hasMatch(upper))score+=20;
    if(compact.length>64)score-=30;
    return score;
  }

  Future<void> dispose()=>_scanner.close();
}
