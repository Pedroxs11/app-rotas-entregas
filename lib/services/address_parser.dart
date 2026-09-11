import '../domain/models.dart';

class AddressParser {
  static final _cep=RegExp(r'\b(\d{5})[-\s]?(\d{3})\b');
  static final _street=RegExp(r'\b(RUA|R\.?|AVENIDA|AV\.?|ALAMEDA|AL\.?|ESTRADA|RODOVIA|TRAVESSA|TRAV\.?|PRAÇA|PRACA|ROD\.?)\s+([^\n,;]{3,60})',caseSensitive:false);
  static final _number=RegExp(r'(?:,|\s)\s*(\d{1,6})(?:\b|\s)');
  static final _uf=RegExp(r'\b(AC|AL|AP|AM|BA|CE|DF|ES|GO|MA|MT|MS|MG|PA|PB|PR|PE|PI|RJ|RN|RS|RO|RR|SC|SP|SE|TO)\b',caseSensitive:false);
  static final _complement=RegExp(r'\b(AP(?:TO)?\.?|APARTAMENTO|BLOCO|BL\.?|CASA|SALA|LOTE|FUNDOS|CJ|CONJUNTO)\s*[A-Z0-9-]+',caseSensitive:false);
  static final _recipient=RegExp(r'\b(DESTINAT[ÁA]RIO|DESTINO|ENTREGA|RECEBEDOR)\b',caseSensitive:false);
  static final _sender=RegExp(r'\b(REMETENTE|EMISSOR)\b',caseSensitive:false);
  static final _noise=RegExp(r'\b(DANFE|SIMPLIFICADA|AG[ÊE]NCIA|GAIOLA|PARADA|PACOTES?|ORDEM|CORREDOR|DESCRI[CÇ][AÃ]O|QUANTIDADE|TOTAL|CHAVE|NOTA FISCAL)\b',caseSensitive:false);
  static final _suspiciousToken=RegExp(r'\b[A-Z]+\d+\b|\b\d+[A-Z]+\b',caseSensitive:false);

  AddressData parse(String raw){
    final normalized=raw.replaceAll('\r','').replaceAll(RegExp(r'[ \t]+'),' ').trim();
    final clean=_parseCleanLine(normalized);if(clean!=null)return clean;
    final text=_addressBlock(normalized);final cepMatch=_cep.firstMatch(text);final streetMatch=_street.firstMatch(text);final streetText=streetMatch?.group(0)??'';final numberMatch=_number.firstMatch(streetText);final compMatch=_complement.firstMatch(text);final textForUf=compMatch==null?text:text.replaceRange(compMatch.start,compMatch.end,' ');final ufMatches=_uf.allMatches(textForUf).toList();final ufMatch=ufMatches.isEmpty?null:ufMatches.last;final cep=cepMatch==null?null:'${cepMatch.group(1)}-${cepMatch.group(2)}';final suspiciousHouseToken=_suspiciousToken.hasMatch(streetText);double score=0;if(streetMatch!=null)score+=.35;if(numberMatch!=null)score+=.20;if(cep!=null)score+=.30;if(ufMatch!=null)score+=.10;if(_recipient.hasMatch(normalized))score+=.05;if(suspiciousHouseToken)score-=.20;if(_noise.hasMatch(text)&&streetMatch==null)score-=.25;score=score.clamp(0,1);final coherent=streetMatch!=null&&numberMatch!=null&&!suspiciousHouseToken&&(cep!=null||ufMatch!=null);final validation=coherent&&score>=.75?ValidationStatus.confirmed:score>=.35?ValidationStatus.needsReview:ValidationStatus.invalid;return AddressData(raw:raw,street:streetMatch?.group(0)?.trim(),number:numberMatch?.group(1),complement:compMatch?.group(0),state:ufMatch?.group(1)?.toUpperCase(),cep:cep,confidence:score,validation:validation);
  }

  AddressData? _parseCleanLine(String raw){
    if(raw.contains('\n')||_recipient.hasMatch(raw)||_sender.hasMatch(raw)||_noise.hasMatch(raw))return null;final parts=raw.split(',').map((e)=>e.trim()).where((e)=>e.isNotEmpty).toList();if(parts.length<2||!_street.hasMatch(parts.first))return null;final number=RegExp(r'^\d{1,6}[A-Za-z]?$').firstMatch(parts[1])?.group(0);if(number==null)return null;final cepMatch=_cep.firstMatch(raw);final ufMatches=_uf.allMatches(raw).toList();final state=ufMatches.isEmpty?null:ufMatches.last.group(1)?.toUpperCase();final cep=cepMatch==null?null:'${cepMatch.group(1)}-${cepMatch.group(2)}';var tail=parts.sublist(2).where((p)=>!_cep.hasMatch(p)).toList();String? city,neighborhood,complement;if(tail.isNotEmpty){var last=tail.last;if(state!=null&&state.isNotEmpty){last=last.replaceFirst(RegExp('\\s*[-/]?\\s*${RegExp.escape(state)}\\s*\$',caseSensitive:false),'').trim();}if(last.isNotEmpty){city=last;tail=tail.sublist(0,tail.length-1);}}if(tail.isNotEmpty){neighborhood=tail.last;tail=tail.sublist(0,tail.length-1);}if(tail.isNotEmpty)complement=tail.join(', ');final valid=cep!=null||(city?.isNotEmpty==true&&state!=null);return AddressData(raw:raw,street:parts.first,number:number,complement:complement,neighborhood:neighborhood,city:city,state:state,cep:cep,confidence:valid?1:.65,validation:valid?ValidationStatus.confirmed:ValidationStatus.needsReview);
  }

  String _addressBlock(String raw){final lines=raw.split('\n').map((e)=>e.trim()).where((e)=>e.isNotEmpty).toList();if(lines.isEmpty)return raw;var start=lines.indexWhere((l)=>_recipient.hasMatch(l));final sender=lines.indexWhere((l)=>_sender.hasMatch(l));if(start>=0){start++;final end=sender>start?sender:(start+8).clamp(0,lines.length);return lines.sublist(start,end).where((l)=>!_noise.hasMatch(l)).join('\n');}final useful=lines.where((l)=>!_noise.hasMatch(l)&&(_street.hasMatch(l)||_cep.hasMatch(l)||_complement.hasMatch(l)||_uf.hasMatch(l)||RegExp(r'\b\d{1,6}\b').hasMatch(l))).toList();return useful.isEmpty?raw:useful.join('\n');}
}
