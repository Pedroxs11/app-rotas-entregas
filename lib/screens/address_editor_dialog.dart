import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../domain/models.dart';
import '../services/cep_service.dart';

class AddressEditorResult {
  final String street, number, complement, neighborhood, city, state, cep;
  const AddressEditorResult({required this.street,required this.number,required this.complement,required this.neighborhood,required this.city,required this.state,required this.cep});
  String get raw => [street,number,complement,neighborhood,city,state,cep].where((e)=>e.trim().isNotEmpty).join(', ');
  AddressData toAddress()=>AddressData(raw:raw,street:_n(street),number:_n(number),complement:_n(complement),neighborhood:_n(neighborhood),city:_n(city),state:_n(state.toUpperCase()),cep:_n(cep),confidence:_valid?1:0.55,validation:_valid?ValidationStatus.confirmed:ValidationStatus.needsReview);
  bool get _valid=>street.trim().length>=3&&number.trim().isNotEmpty&&(cep.replaceAll(RegExp(r'\D'),'').length==8||(city.trim().isNotEmpty&&state.trim().length==2));
  static String? _n(String v)=>v.trim().isEmpty?null:v.trim();
}

Future<AddressEditorResult?> showAddressEditor(BuildContext context,{AddressData? initial,String title='Endereço'}) {
  return showDialog<AddressEditorResult>(context:context,builder:(_)=>_AddressEditorDialog(initial:initial,title:title));
}

class _AddressEditorDialog extends StatefulWidget {
  final AddressData? initial;
  final String title;
  const _AddressEditorDialog({this.initial,required this.title});
  @override State<_AddressEditorDialog> createState()=>_AddressEditorDialogState();
}

class _AddressEditorDialogState extends State<_AddressEditorDialog>{
  late final TextEditingController street,number,complement,neighborhood,city,state,cep;
  final CepService cepService=ViaCepService();
  bool lookingUp=false;
  String? cepMessage,lastCep;

  @override void initState(){super.initState();final a=widget.initial;street=TextEditingController(text:a?.street??'');number=TextEditingController(text:a?.number??'');complement=TextEditingController(text:a?.complement??'');neighborhood=TextEditingController(text:a?.neighborhood??'');city=TextEditingController(text:a?.city??'');state=TextEditingController(text:a?.state??'');cep=TextEditingController(text:a?.cep??'');cep.addListener(_cepChanged);}
  void _cepChanged(){final digits=cep.text.replaceAll(RegExp(r'\D'),'');if(digits.length==8&&digits!=lastCep){lastCep=digits;_lookupCep(digits);}else if(digits.length<8){lastCep=null;if(cepMessage!=null&&mounted)setState(()=>cepMessage=null);}}
  Future<void> _lookupCep(String digits)async{setState((){lookingUp=true;cepMessage='Buscando CEP...';});try{final r=await cepService.lookup(digits);if(!mounted)return;if(r==null){setState(()=>cepMessage='CEP não encontrado. Você pode preencher manualmente.');return;}street.text=r.street;neighborhood.text=r.neighborhood;city.text=r.city;state.text=r.state;cep.text=r.cep;setState(()=>cepMessage='CEP encontrado ✓ — informe o número.');}catch(_){if(mounted)setState(()=>cepMessage='Sem consulta de CEP agora. Continue preenchendo manualmente.');}finally{if(mounted)setState(()=>lookingUp=false);}}
  AddressEditorResult _result()=>AddressEditorResult(street:street.text,number:number.text,complement:complement.text,neighborhood:neighborhood.text,city:city.text,state:state.text,cep:cep.text);
  @override void dispose(){cep.removeListener(_cepChanged);for(final x in [street,number,complement,neighborhood,city,state,cep]){x.dispose();}super.dispose();}
  @override Widget build(BuildContext context)=>AlertDialog(title:Text(widget.title),content:SizedBox(width:480,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
    _field(cep,'CEP',Icons.local_post_office_outlined,keyboardType:TextInputType.number,inputFormatters:[FilteringTextInputFormatter.digitsOnly,LengthLimitingTextInputFormatter(8)],suffix:lookingUp?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)):null),
    if(cepMessage!=null)Padding(padding:const EdgeInsets.only(bottom:10),child:Align(alignment:Alignment.centerLeft,child:Text(cepMessage!,style:Theme.of(context).textTheme.bodySmall))),
    _field(street,'Rua / Avenida',Icons.signpost),
    Row(children:[Expanded(child:_field(number,'Número',Icons.pin,keyboardType:TextInputType.streetAddress)),const SizedBox(width:8),Expanded(child:_field(complement,'Complemento',Icons.home_outlined))]),
    _field(neighborhood,'Bairro',Icons.location_city),
    _field(city,'Cidade',Icons.location_on_outlined),
    _field(state,'UF',Icons.map_outlined,maxLength:2,prefixIconSize:20),
  ]))),actions:[TextButton(onPressed:()=>Navigator.of(context).pop(),child:const Text('Cancelar')),FilledButton.icon(onPressed:()=>Navigator.of(context).pop(_result()),icon:const Icon(Icons.check),label:const Text('Confirmar endereço'))]);
}

Widget _field(TextEditingController c,String label,IconData icon,{int? maxLength,TextInputType? keyboardType,List<TextInputFormatter>? inputFormatters,Widget? suffix,double prefixIconSize=22})=>Padding(padding:const EdgeInsets.only(bottom:10),child:TextField(controller:c,maxLength:maxLength,keyboardType:keyboardType,inputFormatters:inputFormatters,textCapitalization:TextCapitalization.words,decoration:InputDecoration(labelText:label,prefixIcon:Icon(icon,size:prefixIconSize),suffixIcon:suffix,border:const OutlineInputBorder(),counterText:'')));
