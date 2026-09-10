import '../domain/models.dart';

class AddressParser {
  static final _cep = RegExp(r'\b(\d{5})[-\s]?(\d{3})\b');
  static final _street = RegExp(r'\b(RUA|R\.?|AVENIDA|AV\.?|ALAMEDA|AL\.?|ESTRADA|RODOVIA|TRAVESSA|PRAÇA)\s+([^\n,]+)', caseSensitive:false);
  static final _number = RegExp(r'(?:,|\s)\s*(\d{1,6})(?:\b|\s)');
  static final _uf = RegExp(r'\b(AC|AL|AP|AM|BA|CE|DF|ES|GO|MA|MT|MS|MG|PA|PB|PR|PE|PI|RJ|RN|RS|RO|RR|SC|SP|SE|TO)\b',caseSensitive:false);
  static final _complement = RegExp(r'\b(AP(?:TO)?\.?|APARTAMENTO|BLOCO|BL\.?|CASA|SALA|LOTE|FUNDOS)\s*[A-Z0-9-]+',caseSensitive:false);

  AddressData parse(String raw) {
    final text=raw.replaceAll('\r','').replaceAll(RegExp(r'[ \t]+'),' ').trim();
    final cepMatch=_cep.firstMatch(text);
    final streetMatch=_street.firstMatch(text);
    final numberMatch=_number.firstMatch(streetMatch?.group(0) ?? text);
    final compMatch=_complement.firstMatch(text);

    // Complementos como "AP 12" não podem ser confundidos com a UF Amapá (AP).
    final textForUf = compMatch == null
        ? text
        : text.replaceRange(compMatch.start, compMatch.end, ' ');
    final ufMatches=_uf.allMatches(textForUf).toList();
    final ufMatch=ufMatches.isEmpty?null:ufMatches.last;

    final cep=cepMatch==null?null:'${cepMatch.group(1)}-${cepMatch.group(2)}';
    double score=0;
    if(streetMatch!=null) score+=.35;
    if(numberMatch!=null) score+=.20;
    if(cep!=null) score+=.30;
    if(ufMatch!=null) score+=.10;
    if(text.length>20) score+=.05;
    score=score.clamp(0,1);
    final validation=score>=.75?ValidationStatus.confirmed:score>=.40?ValidationStatus.needsReview:ValidationStatus.invalid;
    return AddressData(raw:raw,street:streetMatch?.group(0)?.trim(),number:numberMatch?.group(1),complement:compMatch?.group(0),state:ufMatch?.group(1)?.toUpperCase(),cep:cep,confidence:score,validation:validation);
  }
}
