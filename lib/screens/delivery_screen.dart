import 'package:flutter/material.dart';
import '../app_state.dart';
import '../domain/models.dart';
import '../services/navigation_service.dart';
import '../services/location_service.dart';
import 'map_screen.dart';

class DeliveryScreen extends StatelessWidget {
  final AppState state;
  const DeliveryScreen({super.key, required this.state});
  DeliveryPackage? _next(){for(final p in state.packages){if(p.status==DeliveryStatus.pending||p.status==DeliveryStatus.current)return p;}return null;}
  int _done()=>state.packages.where((p)=>p.status==DeliveryStatus.delivered||p.status==DeliveryStatus.absent||p.status==DeliveryStatus.skipped||p.status==DeliveryStatus.addressProblem).length;

  @override Widget build(BuildContext context)=>AnimatedBuilder(animation:state,builder:(context,_){
    final p=_next();final total=state.packages.length;final done=_done();
    if(p==null)return Scaffold(appBar:AppBar(title:const Text('Rota concluída')),body:Center(child:Padding(padding:const EdgeInsets.all(24),child:Column(mainAxisSize:MainAxisSize.min,children:[const Icon(Icons.task_alt,size:72),const SizedBox(height:16),Text('Rota finalizada',style:Theme.of(context).textTheme.headlineMedium),const SizedBox(height:8),Text('$total pacotes processados'),const SizedBox(height:20),FilledButton.icon(onPressed:()=>Navigator.pop(context),icon:const Icon(Icons.home_outlined),label:const Text('Voltar para minha rota'))]))));
    final i=state.packages.indexWhere((e)=>e.id==p.id);final remaining=total-done;final progress=total==0?0.0:done/total;
    return Scaffold(appBar:AppBar(title:Text('Entrega ${done+1} de $total'),actions:[IconButton(tooltip:'Ver rota no mapa',onPressed:state.locatedCount==0?null:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>RouteMapScreen(packages:state.packages))),icon:const Icon(Icons.map_outlined))]),body:SafeArea(child:Padding(padding:const EdgeInsets.all(20),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      LinearProgressIndicator(value:progress),const SizedBox(height:8),Text('$remaining restantes • $done concluídas',textAlign:TextAlign.center),const SizedBox(height:18),
      Row(children:[Expanded(child:Text(p.label,style:Theme.of(context).textTheme.headlineLarge?.copyWith(fontWeight:FontWeight.bold))),if(p.pinned)const Chip(avatar:Icon(Icons.push_pin,size:16),label:Text('Fixada'))]),
      if(p.physicalZone!=null)Text('📦 Local físico: ${p.physicalZone}',style:Theme.of(context).textTheme.titleLarge),const SizedBox(height:18),
      Card(child:Padding(padding:const EdgeInsets.all(18),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('ENDEREÇO DE ENTREGA',style:TextStyle(fontWeight:FontWeight.bold)),const SizedBox(height:8),Text(p.address.formatted.isEmpty?p.address.raw:p.address.formatted,style:Theme.of(context).textTheme.titleLarge)]))),
      const Spacer(),FilledButton.icon(onPressed:()=>NavigationService().openWaze(p),icon:const Icon(Icons.navigation),label:const Padding(padding:EdgeInsets.all(14),child:Text('ABRIR NO WAZE'))),const SizedBox(height:10),
      FilledButton.tonalIcon(onPressed:()=>state.update(i,p.copyWith(status:DeliveryStatus.delivered)),icon:const Icon(Icons.check_circle),label:const Padding(padding:EdgeInsets.all(13),child:Text('ENTREGUE'))),const SizedBox(height:10),
      Row(children:[Expanded(child:OutlinedButton.icon(onPressed:()=>state.update(i,p.copyWith(status:DeliveryStatus.absent)),icon:const Icon(Icons.person_off_outlined),label:const Text('Ausente'))),const SizedBox(width:8),Expanded(child:OutlinedButton.icon(onPressed:()=>state.update(i,p.copyWith(status:DeliveryStatus.skipped)),icon:const Icon(Icons.skip_next),label:const Text('Pular')))]),
      const SizedBox(height:6),TextButton.icon(onPressed:()=>_addressProblem(context,i,p),icon:const Icon(Icons.wrong_location_outlined),label:const Text('Problema com o endereço')),
      TextButton.icon(onPressed:()=>_reoptimize(context),icon:const Icon(Icons.auto_fix_high),label:const Text('Reotimizar entregas restantes')),
    ]))));
  });

  Future<void> _addressProblem(BuildContext context,int i,DeliveryPackage p)async{final ok=await showDialog<bool>(context:context,builder:(d)=>AlertDialog(title:const Text('Problema com o endereço?'),content:const Text('O pacote ficará separado para conferência e a rota seguirá para a próxima entrega.'),actions:[TextButton(onPressed:()=>Navigator.pop(d,false),child:const Text('Cancelar')),FilledButton(onPressed:()=>Navigator.pop(d,true),child:const Text('Marcar problema'))]));if(ok==true)await state.update(i,p.copyWith(status:DeliveryStatus.addressProblem));}
  Future<void> _reoptimize(BuildContext context)async{try{final pos=await LocationService().current();await state.optimizeFrom(pos.latitude,pos.longitude);if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Entregas restantes reotimizadas.')));}catch(e){if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$e')));}}
}
