import 'package:flutter_test/flutter_test.dart';
import 'package:app_rotas_entregas/services/tracking_code_selector.dart';

void main(){
  test('rastreio vence chave fiscal de 44 dígitos',(){
    final selected=TrackingCodeSelector.chooseBest(['35260912345678000190550010000012341234567890','BR123456789SP']);
    expect(selected,'BR123456789SP');
  });

  test('rastreio vence URL de QR code',(){
    final selected=TrackingCodeSelector.chooseBest(['https://exemplo.com.br/pacote?id=123456789','AB123456789BR']);
    expect(selected,'AB123456789BR');
  });

  test('rastreio vence payload JSON',(){
    final selected=TrackingCodeSelector.chooseBest(['{"pedido":"123","rota":"A"}','PKG-9A82B771']);
    expect(selected,'PKG-9A82B771');
  });

  test('remove duplicados e espaços externos',(){
    final selected=TrackingCodeSelector.chooseBest(['  BR123456789SP  ','BR123456789SP']);
    expect(selected,'BR123456789SP');
  });

  test('sem códigos retorna nulo',(){expect(TrackingCodeSelector.chooseBest(['','   ']),isNull);});
}
