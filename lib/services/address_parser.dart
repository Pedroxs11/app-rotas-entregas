import '../domain/models.dart';

class AddressParser {
  static final _cep = RegExp(r'\b(\d{5})[-\s]?(\d{3})\b');
  static final _street = RegExp(r'\b(RUA|R\.?|AVENIDA|AV\.?|ALAMEDA|AL\.?|ESTRADA|RODOVIA|TRAVESSA|TRAV\.?|PRAÇA|PRACA|ROD\.?)\s+([^\n,;]{3,60})', caseSensitive:false);
  static final _number = RegExp(r'(?:,|\s)\s*(\d{1,6})(?:\b|\s)');
  static final _uf = RegExp(r'\b(AC|AL|AP|AM|BA|CE|DF|ES|GO|MA|MT|MS|MG|PA|PB|PR|PE|PI|RJ|RN|RS|RO|RR|SC|SP|SE|TO)\b',caseSensitive:false);
  static final _complement = RegExp(r'\b(AP(?:TO)?\.?|APARTAMENTO|BLOCO|BL\.?|CASA|SALA|LOTE|FUNDOS|CJ|CONJUNTO)\s*[A-Z0-9-]+',caseSensitive:false);
  static final _recipient = RegExp(r'\b(DESTINAT[ÁA]RIO|DESTINO|ENTREGA|RECEBEDOR)\b',caseSensitive:false);
  static final _sender = RegExp(r'\b(REMETENTE|EMISSOR)\b',caseSensitive:false);
  static final _noise = RegExp(r'\b(DANFE|SIMPLIFICADA|AG[ÊE]NCIA|GAIOLA|PARADA|PACOTES?|ORDEM|CORREDOR|DESCRI[CÇ][AÃ]O|QUANTIDADE|TOTAL|CHAVE|NOTA FISCAL)\b',caseSensitive:false);

  AddressData parse(String raw) {
    final normalized=raw.replaceAll('\r','').replaceAll(RegExp(r'[ \t]+'),' ').trim();
    final text=_addressBlock(normalized);
    final cepMatch=_cep.firstMatch(text);
    final streetMatch=_street.firstMatch(text);
    final streetText=streetMatch?.group(0)??'';
    final numberMatch=_number.firstMatch(streetText);
    final compMatch=_complement.firstMatch(text);
    final textForUf=compMatch==null?text:text.replaceRange(compMatch.start,compMatch.end,' ');
    final ufMatches=_uf.allMatches(textForUf).toList();
    final ufMatch=ufMatches.isEmpty?null:ufMatches.last;
    final cep=cepMatch==null?null:'${cepMatch.group(1)}-${cepMatch.group(2)}';

    // OCR de número precisa ser realmente numérico. Ex.: S03 não vira 303 e
    // o "2" de CASA 2 nunca pode ser promovido a número do imóvel.
    final suspiciousHouseToken=RegExp(r'\b[A-Z]+\d+\b|\b\d+[A-Z]+\b',caseSensitive:false).hasMatch(streetText);
    double score=0;
    if(streetMatch!=null)score+=.35;
    if(numberMatch!=null)score+=.20;
    if(cep!=null)score+=.30;
    if(ufMatch!=null)score+=.10;
    if(_recipient.hasMatch(normalized))score+=.05;
    if(suspiciousHouseToken&&numberMatch==null)score-=.20;
    if(_noise.hasMatch(text)&&streetMatch==null)score-=.25;
    score=score.clamp(0,1);
    final coherent=streetMatch!=null&&numberMatch!=null&&!suspiciousHouseToken&&(cep!=null||ufMatch!=null);
    final validation=coherent&&score>=.75?ValidationStatus.confirmed:score>=.35?ValidationStatus.needsReview:ValidationStatus.invalid;
    return AddressData(raw:raw,street:streetMatch?.group(0)?.trim(),number:numberMatch?.group(1),complement:compMatch?.group(0),state:ufMatch?.group(1)?.toUpperCase(),cep:cep,confidence:score,validation:validation);
  }

  String _addressBlock(String raw){
    final lines=raw.split('\n').map((e)=>e.trim()).where((e)=>e.isNotEmpty).toList();
    if(lines.isEmpty)return raw;
    var start=lines.indexWhere((l)=>_recipient.hasMatch(l));
    final sender=lines.indexWhere((l)=>_sender.hasMatch(l));
    if(start>=0){start++;final end=sender>start?sender:(start+8).clamp(0,lines.length);return lines.sublist(start,end).where((l)=>!_noise.hasMatch(l)).join('\n');}
    final useful=lines.where((l)=>!_noise.hasMatch(l)&&(_street.hasMatch(l)||_cep.hasMatch(l)||_complement.hasMatch(l)||_uf.hasMatch(l)||RegExp(r'\b\d{1,6}\b').hasMatch(l))).toList();
    return useful.isEmpty?raw:useful.join('\n');
  }
}
