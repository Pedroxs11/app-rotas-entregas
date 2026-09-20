import 'package:flutter/material.dart';
import '../app_state.dart';
import '../domain/models.dart';
import 'delivery_screen.dart';

class LoadScreen extends StatefulWidget {
  final AppState state;
  const LoadScreen({super.key,required this.state});
  @override State<LoadScreen> createState()=>_LoadScreenState();
}
class _LoadScreenState extends State<LoadScreen>{
  bool organizing=false;
  bool _active(DeliveryPackage p)=>p.status==DeliveryStatus.pending||p.status==DeliveryStatus.current||p.status==DeliveryStatus.absent||p.status==DeliveryStatus.addressProblem;
  Future<void> _organize()async{setState(()=>organizing=true);try{await widget.state.organizePhysicalLoad();if(mounted)setState((){});}finally{if(mounted)setState(()=>organizing=false);}}
  @override Widget build(BuildContext context){
    final route=widget.state.packages.where(_active).toList();
    final organized=route.isNotEmpty&&route.every((p)=>p.physicalZone?.trim().isNotEmpty==true);
    final groups=<String,List<int>>{};
    for(var i=0;i<route.length;i++){final z=route[i].physicalZone;if(z!=null&&z.trim().isNotEmpty)groups.putIfAbsent(z,()=>[]).add(i+1);}
    return Scaffold(appBar:AppBar(title:const Text('Ordem dos pacotes')),body:route.isEmpty?const Center(child:Text('Nenhum pacote ativo na rota.')):Column(children:[
      Padding(padding:const EdgeInsets.all(16),child:Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('${route.length} pacotes',style:Theme.of(context).textTheme.titleLarge),const SizedBox(height:6),Text(organized?'Carga organizada em ${groups.length} áreas do carro. Confira abaixo antes de sair.':'Organize automaticamente os pacotes nas 11 áreas do carro conforme a ordem da rota.'),const SizedBox(height:12),SizedBox(width:double.infinity,child:OutlinedButton.icon(onPressed:organizing?null:_organize,icon:const Icon(Icons.directions_car_filled_outlined),label:Text(organized?'REORGANIZAR NO CARRO':'ORGANIZAR NO CARRO')))])))),
      if(organized)SizedBox(height:132,child:ListView(padding:const EdgeInsets.symmetric(horizontal:12),scrollDirection:Axis.horizontal,children:[for(final e in groups.entries)SizedBox(width:190,child:Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Icon(Icons.inventory_2_outlined),const SizedBox(height:6),Text(e.key,style:const TextStyle(fontWeight:FontWeight.bold),maxLines:2),const Spacer(),Text(_range(e.value))]))))])),
      Expanded(child:ListView.separated(padding:const EdgeInsets.fromLTRB(12,8,12,12),itemCount:route.length,separatorBuilder:(_,__)=>const Divider(height:1),itemBuilder:(context,i){final p=route[i];final address=p.address.formatted.isEmpty?p.address.raw:p.address.formatted;return ListTile(leading:CircleAvatar(child:Text('${i+1}')),title:Text(p.label,style:const TextStyle(fontWeight:FontWeight.w600)),subtitle:Text('${p.physicalZone?.trim().isNotEmpty==true?p.physicalZone!:'Sem posição'}\n$address',maxLines:3,overflow:TextOverflow.ellipsis));})),
      SafeArea(top:false,child:Padding(padding:const EdgeInsets.fromLTRB(16,8,16,16),child:SizedBox(width:double.infinity,child:FilledButton.icon(onPressed:organized?()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>DeliveryScreen(state:widget.state))):null,icon:const Icon(Icons.play_arrow),label:const Padding(padding:EdgeInsets.all(16),child:Text('INICIAR ENTREGAS'))))))
    ]));
  }
  String _range(List<int> values)=>values.length==1?'Pacote ${values.first}':'Pacotes ${values.first}–${values.last}';
}
