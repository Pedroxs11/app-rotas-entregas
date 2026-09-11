class TrackingCodeSelector {
  const TrackingCodeSelector._();

  static String? chooseBest(Iterable<String> values){
    final list=values.map((v)=>v.trim()).where((v)=>v.isNotEmpty).toSet().toList();
    if(list.isEmpty)return null;
    list.sort((a,b){final scoreCompare=_score(b).compareTo(_score(a));if(scoreCompare!=0)return scoreCompare;return a.length.compareTo(b.length);});
    return list.first;
  }

  static int _score(String value){
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
}
