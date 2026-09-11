import 'package:flutter/material.dart';
import '../domain/models.dart';

class AddressEditorResult {
  final String street, number, complement, neighborhood, city, state, cep;
  const AddressEditorResult({required this.street,required this.number,required this.complement,required this.neighborhood,required this.city,required this.state,required this.cep});
  String get raw => [street,number,complement,neighborhood,city,state,cep].where((e)=>e.trim().isNotEmpty).join(', ');
  AddressData toAddress()=>AddressData(raw:raw,street:_n(street),number:_n(number),complement:_n(complement),neighborhood:_n(neighborhood),city:_n(city),state:_n(state.toUpperCase()),cep:_n(cep),confidence:_valid?1:0.55,validation:_valid?ValidationStatus.confirmed:ValidationStatus.needsReview);
  bool get _valid=>street.trim().length>=3&&number.trim().isNotEmpty&&(cep.replaceAll(RegExp(r'\D'),'').length==8||(city.trim().isNotEmpty&&state.trim().length==2));
  static String? _n(String v)=>v.trim().isEmpty?null:v.trim();
}

Future<AddressEditorResult?> showAddressEditor(BuildContext context,{AddressData? initial,String title='Endereço'}) async {
  final street=TextEditingController(text:initial?.street??'');
  final number=TextEditingController(text:initial?.number??'');
  final complement=TextEditingController(text:initial?.complement??'');
  final neighborhood=TextEditingController(text:initial?.neighborhood??'');
  final city=TextEditingController(text:initial?.city??'');
  final state=TextEditingController(text:initial?.state??'');
  final cep=TextEditingController(text:initial?.cep??'');
  final result=await showDialog<AddressEditorResult>(context:context,builder:(c)=>AlertDialog(
    title:Text(title),
    content:SizedBox(width:480,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
      _field(street,'Rua / Avenida',Icons.signpost),
      Row(children:[Expanded(child:_field(number,'Número',Icons.pin)),const SizedBox(width:8),Expanded(child:_field(complement,'Complemento',Icons.home_outlined))]),
      _field(neighborhood,'Bairro',Icons.location_city),
      _field(city,'Cidade',Icons.location_on_outlined),
      Row(children:[Expanded(child:_field(state,'UF',Icons.map_outlined,maxLength:2)),const SizedBox(width:8),Expanded(flex:2,child:_field(cep,'CEP',Icons.local_post_office_outlined))]),
    ]))),
    actions:[TextButton(onPressed:()=>Navigator.pop(c),child:const Text('Cancelar')),FilledButton.icon(onPressed:()=>Navigator.pop(c,AddressEditorResult(street:street.text,number:number.text,complement:complement.text,neighborhood:neighborhood.text,city:city.text,state:state.text,cep:cep.text)),icon:const Icon(Icons.check),label:const Text('Confirmar endereço'))],
  ));
  for(final x in [street,number,complement,neighborhood,city,state,cep]){x.dispose();}
  return result;
}

Widget _field(TextEditingController c,String label,IconData icon,{int? maxLength})=>Padding(padding:const EdgeInsets.only(bottom:10),child:TextField(controller:c,maxLength:maxLength,textCapitalization:TextCapitalization.words,decoration:InputDecoration(labelText:label,prefixIcon:Icon(icon),border:const OutlineInputBorder(),counterText:'')));
