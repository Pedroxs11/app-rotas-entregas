import 'package:flutter_test/flutter_test.dart';
import 'package:app_rotas_entregas/services/address_parser.dart';
import 'package:app_rotas_entregas/domain/models.dart';

void main(){
  final parser=AddressParser();

  test('detecta endereço brasileiro com CEP',(){
    final a=parser.parse('JOAO SILVA\nRUA DR ARNALDO 455 AP 12\nCERQUEIRA CESAR SP\n01355-000');
    expect(a.cep,'01355-000');expect(a.state,'SP');expect(a.number,'455');expect(a.validation,ValidationStatus.confirmed);
  });

  test('texto fraco exige revisão',(){final a=parser.parse('JOAO - SAO PAULO');expect(a.validation,isNot(ValidationStatus.confirmed));});

  test('prioriza destinatario e ignora remetente',(){
    final a=parser.parse('REMETENTE\nAV ORIGEM 900\nSAO PAULO SP\n01000-000\nDESTINATARIO\nRUA DAS FLORES 303 CASA 2\nSAO PAULO SP\n05887-300');
    expect(a.number,'303');expect(a.cep,'05887-300');expect(a.state,'SP');expect(a.validation,ValidationStatus.confirmed);
  });

  test('identifica captura que mostra somente remetente',(){
    expect(parser.isSenderOnlyLabel('REMETENTE\nRUA ORIGEM 99\nCURITIBA PR\n80000-000'),isTrue);
    expect(parser.isSenderOnlyLabel('REMETENTE\nRUA ORIGEM 99\nDESTINATARIO\nRUA DESTINO 120'),isFalse);
  });

  test('ignora ruído de operação logística',(){final a=parser.parse('SAO-32\nLSH\nJ\nCORREDOR A\nGAIOLA 15\nPACOTES NESTA PARADA 1\nPARADA 25\nORDEM 003');expect(a.validation,isNot(ValidationStatus.confirmed));});

  test('não confirma propaganda ou texto aleatório como endereço',(){final a=parser.parse('R PARA SUJEIRAS MAIS DIFICEIS DEIXAR O PRODUTO\nRR\n18225-000');expect(a.validation,isNot(ValidationStatus.confirmed));});

  test('complemento casa não vira número principal',(){
    final a=parser.parse('DESTINATARIO\nRUA EXEMPLO 303 CASA 2\nJARDIM TESTE SP\n05887-300');expect(a.number,'303');expect(a.complement?.toUpperCase(),contains('CASA 2'));expect(a.validation,ValidationStatus.confirmed);
  });

  test('número OCR suspeito não é inventado nem corrigido silenciosamente',(){final a=parser.parse('DESTINATARIO\nRUA EXEMPLO S03 CASA 2\nSAO PAULO SP\n05887-300');expect(a.number,isNot('303'));expect(a.validation,isNot(ValidationStatus.confirmed));});

  test('DANFE e códigos não vencem um endereço de destinatário',(){
    final a=parser.parse('DANFE SIMPLIFICADA\nTOTAL 303\nAGENCIA SAO-32\nDESTINATARIO\nAVENIDA CENTRAL 120\nSAO PAULO SP\n01310-000\nREMETENTE\nRUA ORIGEM 99\nCURITIBA PR\n80000-000');expect(a.number,'120');expect(a.cep,'01310-000');expect(a.state,'SP');expect(a.validation,ValidationStatus.confirmed);
  });

  test('lista numerada preserva número do imóvel após vírgula',(){
    final a=parser.parse('7. Rua Barão de Comorogi, 500, Jardim Ângela (Zona Sul), São Paulo, SP, 04900-000');
    expect(a.number,'500');
    expect(a.cep,'04900-000');
    expect(a.state,'SP');
    expect(a.validation,ValidationStatus.confirmed);
  });

  test('OCR preserva número separado da rua por vírgula',(){
    final a=parser.parse('DESTINATARIO\nRUA PADRE MATEUS DE AGUIAR, 16\nJARDIM ANGELA SAO PAULO SP\n04900-000');
    expect(a.number,'16');
    expect(a.validation,ValidationStatus.confirmed);
  });

  test('importação limpa preserva todos os campos dos 8 endereços de regressão',(){
    const cases=<List<String>>[
      ['Avenida Paulista, 1578, Bela Vista, São Paulo - SP, 01310-200','Avenida Paulista','1578','Bela Vista','01310-200'],
      ['Rua Augusta, 1508, Consolação, São Paulo - SP, 01304-001','Rua Augusta','1508','Consolação','01304-001'],
      ['Avenida Ipiranga, 200, República, São Paulo - SP, 01046-010','Avenida Ipiranga','200','República','01046-010'],
      ['Rua da Consolação, 930, Consolação, São Paulo - SP, 01302-907','Rua da Consolação','930','Consolação','01302-907'],
      ['Avenida Brigadeiro Faria Lima, 3477, Itaim Bibi, São Paulo - SP, 04538-133','Avenida Brigadeiro Faria Lima','3477','Itaim Bibi','04538-133'],
      ['Rua Oscar Freire, 379, Cerqueira César, São Paulo - SP, 01426-001','Rua Oscar Freire','379','Cerqueira César','01426-001'],
      ['Avenida Rebouças, 3970, Pinheiros, São Paulo - SP, 05402-600','Avenida Rebouças','3970','Pinheiros','05402-600'],
      ['Rua Vergueiro, 1000, Liberdade, São Paulo - SP, 01504-001','Rua Vergueiro','1000','Liberdade','01504-001'],
    ];
    for(final c in cases){final a=parser.parse(c[0]);expect(a.street,c[1],reason:c[0]);expect(a.number,c[2],reason:c[0]);expect(a.neighborhood,c[3],reason:c[0]);expect(a.city,'São Paulo',reason:c[0]);expect(a.state,'SP',reason:c[0]);expect(a.cep,c[4],reason:c[0]);expect(a.validation,ValidationStatus.confirmed,reason:c[0]);}
  });

  test('importação com cidade e UF em campos separados preserva cidade, bairro e número',(){
    final a=parser.parse('1. Rua Anum-Branco, 303, Jardim Dom José, São Paulo, SP, 05887-300');
    expect(a.street,'Rua Anum-Branco');
    expect(a.number,'303');
    expect(a.neighborhood,'Jardim Dom José');
    expect(a.city,'São Paulo');
    expect(a.state,'SP');
    expect(a.cep,'05887-300');
    expect(a.formatted,contains('Rua Anum-Branco, 303'));
  });
  test('CEP seguido de número preserva o número para enriquecimento posterior',(){
    final a=parser.parse('05887-300, 303');
    expect(a.cep,'05887-300');
    expect(a.number,'303');
    expect(a.validation,ValidationStatus.needsReview);
  });
}

