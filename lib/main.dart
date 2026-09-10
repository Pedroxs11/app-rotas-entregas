import 'package:flutter/material.dart';
import 'app_state.dart';
import 'domain/models.dart';
import 'services/navigation_service.dart';

void main()=>runApp(const DeliveryApp());

class DeliveryApp extends StatefulWidget { const DeliveryApp({super.key}); @override State<DeliveryApp> createState()=>_DeliveryAppState(); }
class _DeliveryAppState extends State<DeliveryApp>{
  final state=AppState();
  @override void initState(){super.initState();state.init();}
  @override Widget build(BuildContext context)=>MaterialApp(debugShowCheckedModeBanner:false,title:'Rotas Entregas',theme:ThemeData(useMaterial3:true,colorSchemeSeed:Colors.indigo),home:HomePage(state:state));
}

class HomePage extends StatefulWidget { final AppState state; const HomePage({super.key,required this.state}); @override State<HomePage> createState()=>_HomePageState(); }
class _HomePageState extends State<HomePage>{
  final input=TextEditingController();
  @override Widget build(BuildContext context)=>AnimatedBuilder(animation:widget.state,builder:(context,_){
    final s=widget.state;
    if(s.loading)return const Scaffold(body:Center(child:CircularProgressIndicator()));
    return Scaffold(appBar:AppBar(title:const Text('Minha rota')),floatingActionButton:FloatingActionButton.extended(onPressed:()=>_add(context),icon:const Icon(Icons.document_scanner),label:const Text('Escanear')),
      body:Column(children:[
        Padding(padding:const EdgeInsets.all(16),child:Row(children:[Expanded(child:_stat('${s.packages.length}','Pacotes')),Expanded(child:_stat('${s.reviewCount}','Revisar')),Expanded(child:_stat('${s.deliveredCount}','Entregues'))])),
        if(s.packages.isEmpty) const Expanded(child:Center(child:Text('Nenhum pacote ainda.\nToque em Escanear para começar.',textAlign:TextAlign.center))) else Expanded(child:ReorderableListView.builder(itemCount:s.packages.length,onReorder:s.reorder,itemBuilder:(context,i){final p=s.packages[i];return ListTile(key:ValueKey(p.id),leading:CircleAvatar(child:Text('${i+1}')),title:Text('${p.label}${p.physicalZone==null?'':' • ${p.physicalZone}'}'),subtitle:Text(p.address.formatted.isEmpty?p.address.raw:p.address.formatted,maxLines:2,overflow:TextOverflow.ellipsis),trailing:Icon(p.address.validation==ValidationStatus.confirmed?Icons.check_circle:Icons.warning_amber),onTap:()=>_package(context,i,p));})),
      ]));
  });}
  Widget _stat(String n,String t)=>Column(children:[Text(n,style:const TextStyle(fontSize:24,fontWeight:FontWeight.bold)),Text(t)]);
  Future<void> _add(BuildContext context) async { input.clear(); final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('Leitura da etiqueta'),content:TextField(controller:input,maxLines:8,decoration:const InputDecoration(hintText:'Cole/digite o texto da etiqueta. O scanner OCR entra nesta mesma etapa.')),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Cancelar')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Registrar'))])); if(ok==true&&input.text.trim().isNotEmpty){try{await widget.state.addFromText(input.text);}catch(e){if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$e')));}} }
  Future<void> _package(BuildContext context,int i,DeliveryPackage p) async { await showModalBottomSheet(context:context,builder:(c)=>SafeArea(child:Wrap(children:[ListTile(title:Text(p.label),subtitle:Text(p.address.formatted.isEmpty?p.address.raw:p.address.formatted)),ListTile(leading:const Icon(Icons.navigation),title:const Text('Abrir no Waze'),onTap:(){Navigator.pop(c);NavigationService().openWaze(p);}),ListTile(leading:const Icon(Icons.check),title:const Text('Marcar entregue'),onTap:(){Navigator.pop(c);widget.state.update(i,p.copyWith(status:DeliveryStatus.delivered));}),ListTile(leading:const Icon(Icons.person_off),title:const Text('Destinatário ausente'),onTap:(){Navigator.pop(c);widget.state.update(i,p.copyWith(status:DeliveryStatus.absent));}),ListTile(leading:const Icon(Icons.push_pin),title:Text(p.pinned?'Desafixar parada':'Fixar parada'),onTap:(){Navigator.pop(c);widget.state.update(i,p.copyWith(pinned:!p.pinned));})]))); }
}
