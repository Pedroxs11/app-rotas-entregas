import '../domain/models.dart';

class AddressParser {
  static final _cep=RegExp(r'\b(\d{5})[-\s]?(\d{3})\b');
  static final _cepAndNumber=RegExp(r'^\s*\d{5}[-\s]?\d{3}\s*[,;:]\s*(?:N[º°o]?|NÚMERO|NUMERO)?\s*(\d{1,6}[A-Za-z]?)\s*$',caseSensitive:false);
  static final _street=RegExp(r'\b(RUA|R\.?|AVENIDA|AV\.?|ALAMEDA|AL\.?|ESTRADA|RODOVIA|TRAVESSA|TRAV\.?|PRAÇA|PRACA|ROD\.?)\s+([^\n,;]{3,60})',caseSensitive:false);
  static final _number=RegExp(r'(?:,|\s)\s*(?:(?:N[º°o]?|NÚMERO|NUMERO)\.?\s*)?(\d{1,6}[A-Za-z]?)\b',caseSensitive:false);
  static final _numberAfterStreet=RegExp(r'^\s*[,;:\-]?\s*(?:(?:N[º°o]?|NÚMERO|NUMERO)\.?\s*)?(\d{1,6}[A-Za-z]?)\b',caseSensitive:false);
  static final _standaloneNumberLine=RegExp(r'^\s*(?:(?:N[º°o]?|NÚMERO|NUMERO)\.?\s*)?(\d{1,6}[A-Za-z]?)\s*$',caseSensitive:false);
  static final _uf=RegExp(r'\b(AC|AL|AP|AM|BA|CE|DF|ES|GO|MA|MT|MS|MG|PA|PB|PR|PE|PI|RJ|RN|RS|RO|RR|SC|SP|SE|TO)\b',caseSensitive:false);
  static final _complement=RegExp(r'\b(AP(?:TO)?\.?|APARTAMENTO|BLOCO|BL\.?|CASA|SALA|LOTE|FUNDOS|CJ|CONJUNTO)\s*[A-Z0-9-]+',caseSensitive:false);
  static final _recipient=RegExp(r'\b(DESTINAT[ÁA]RIO|DESTINO|ENTREGA|RECEBEDOR)\b',caseSensitive:false);
  static final _sender=RegExp(r'\b(REMETENTE|EMISSOR)\b',caseSensitive:false);
  static final _noise=RegExp(r'\b(DANFE|SIMPLIFICADA|AG[ÊE]NCIA|GAIOLA|PARADA|PACOTES?|ORDEM|CORREDOR|DESCRI[CÇ][AÃ]O|QUANTIDADE|TOTAL|CHAVE|NOTA FISCAL)\b',caseSensitive:false);
  static final _suspiciousToken=RegExp(r'\b[A-Z]+\d+\b|\b\d+[A-Z]+\b',caseSensitive:false);

  bool isSenderOnlyLabel(String raw){final normalized=raw.replaceAll('\r','').trim();return _sender.hasMatch(normalized)&&!_recipient.hasMatch(normalized);}

  AddressData parse(String raw){
    final normalized=raw.replaceAll('\r','').replaceAll(RegExp(r'[ \t]+'),' ').trim();
    final cepAndNumber=_cepAndNumber.firstMatch(normalized);
    if(cepAndNumber!=null){
      final cepMatch=_cep.firstMatch(normalized)!;
      return AddressData(raw:raw,number:cepAndNumber.group(1),cep:'${cepMatch.group(1)}-${cepMatch.group(2)}',confidence:.50,validation:ValidationStatus.needsReview);
    }
