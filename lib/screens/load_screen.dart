import 'package:flutter/material.dart';
import '../app_state.dart';
import '../domain/models.dart';
import 'delivery_screen.dart';

class LoadScreen extends StatelessWidget {
  final AppState state;
  const LoadScreen({super.key, required this.state});
  bool _active(DeliveryPackage p)=>p.status==DeliveryStatus.pending||p.status==DeliveryStatus.current||p.status==DeliveryStatus.absent||p.status==DeliveryStatus.addressProblem;
  @override Widget build(BuildContext context){
    final route=state.packages.where(_active).toList();
    return Scaffold(appBar:AppBar(title:const Text('Ordem dos pacotes')),body:route.isEmpty?const Center(child:Text('Nenhum pacote ativo na rota.')):Column(children:[
      Padding(padding:const EdgeInsets.all(16),child:Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('${route.length} pacotes',style:Theme.of(context).textTheme.titleLarge),const SizedBox(height:6),const Text('Esta é a sequência otimizada das entregas. Separe os pacotes usando esta ordem como referência.')])))),
      Expanded(child:ListView.separated(padding:const EdgeInsets.fromLTRB(12,0,12,12),itemCount:route.length,separatorBuilder:(_,__)=>const Divider(height:1),itemBuilder:(context,i){final p=route[i];final address=p.address.formatted.isEmpty?p.address.raw:p.address.formatted;return ListTile(leading:CircleAvatar(child:Text('${i+1}')),title:Text(p.label,style:const TextStyle(fontWeight:FontWeight.w600)),subtitle:Text('Entrega #${i+1}\n$address',maxLines:3,overflow:TextOverflow.ellipsis));})),
      SafeArea(top:false,child:Padding(padding:const EdgeInsets.fromLTRB(16,8,16,16),child:SizedBox(width:double.infinity,child:FilledButton.icon(onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>DeliveryScreen(state:state))),icon:const Icon(Icons.play_arrow),label:const Padding(padding:EdgeInsets.all(16),child:Text('INICIAR ENTREGAS'))))))
    ]));
  }
}
