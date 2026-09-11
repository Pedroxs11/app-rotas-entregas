import 'package:flutter_test/flutter_test.dart';
import 'package:app_rotas_entregas/services/address_parser.dart';
import 'package:app_rotas_entregas/domain/models.dart';

void main(){
  final parser=AddressParser();

  test('detecta endereço brasileiro com CEP',(){
    final a=parser.parse('JOAO SILVA\nRUA DR ARNALDO 455 AP 12\nCERQUEIRA CESAR SP\n01355-000');
    expect(a.cep,'01355-000');
    expect(a.state,'SP');
    expect(a.number,'455');
    expect(a.validation,ValidationStatus.confirmed);
  });

  test('texto fraco exige revisão',(){
    final a=parser.parse('JOAO - SAO PAULO');
    expect(a.validation,isNot(ValidationStatus.confirmed));
  });

  test('prioriza destinatario e ignora remetente',(){
    final a=parser.parse('REMETENTE\nAV ORIGEM 900\nSAO PAULO SP\n01000-000\nDESTINATARIO\nRUA DAS FLORES 303 CASA 2\nSAO PAULO SP\n05887-300');
    expect(a.number,'303');
    expect(a.cep,'05887-300');
    expect(a.state,'SP');
    expect(a.validation,ValidationStatus.confirmed);
  });

  test('ignora ruído de operação logística',(){
    final a=parser.parse('SAO-32\nLSH\nJ\nCORREDOR A\nGAIOLA 15\nPACOTES NESTA PARADA 1\nPARADA 25\nORDEM 003');
    expect(a.validation,isNot(ValidationStatus.confirmed));
  });

  test('não confirma propaganda ou texto aleatório como endereço',(){
    final a=parser.parse('R PARA SUJEIRAS MAIS DIFICEIS DEIXAR O PRODUTO\nRR\n18225-000');
    expect(a.validation,isNot(ValidationStatus.confirmed));
  });

  test('complemento casa não vira número principal',(){
    final a=parser.parse('DESTINATARIO\nRUA EXEMPLO 303 CASA 2\nJARDIM TESTE SP\n05887-300');
    expect(a.number,'303');
    expect(a.complement?.toUpperCase(),contains('CASA 2'));
    expect(a.validation,ValidationStatus.confirmed);
  });

  test('número OCR suspeito não é inventado nem corrigido silenciosamente',(){
    final a=parser.parse('DESTINATARIO\nRUA EXEMPLO S03 CASA 2\nSAO PAULO SP\n05887-300');
    expect(a.number,isNot('303'));
    expect(a.validation,isNot(ValidationStatus.confirmed));
  });

  test('DANFE e códigos não vencem um endereço de destinatário',(){
    final a=parser.parse('DANFE SIMPLIFICADA\nTOTAL 303\nAGENCIA SAO-32\nDESTINATARIO\nAVENIDA CENTRAL 120\nSAO PAULO SP\n01310-000\nREMETENTE\nRUA ORIGEM 99\nCURITIBA PR\n80000-000');
    expect(a.number,'120');
    expect(a.cep,'01310-000');
    expect(a.state,'SP');
    expect(a.validation,ValidationStatus.confirmed);
  });
}
