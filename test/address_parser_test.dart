import 'package:flutter_test/flutter_test.dart';
import 'package:app_rotas_entregas/services/address_parser.dart';
import 'package:app_rotas_entregas/domain/models.dart';

void main(){
  test('detecta endereço brasileiro com CEP',(){
    final a=AddressParser().parse('JOAO SILVA\nRUA DR ARNALDO 455 AP 12\nCERQUEIRA CESAR SP\n01355-000');
    expect(a.cep,'01355-000');
    expect(a.state,'SP');
    expect(a.number,'455');
    expect(a.validation,ValidationStatus.confirmed);
  });
  test('texto fraco exige revisão',(){
    final a=AddressParser().parse('JOAO - SAO PAULO');
    expect(a.validation,isNot(ValidationStatus.confirmed));
  });
}
