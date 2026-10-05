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
  String? selectedId;

  bool _active(DeliveryPackage p)=>p.status==DeliveryStatus.pending||p.status==DeliveryStatus.current||p.status==DeliveryStatus.absent||p.status==DeliveryStatus.addressProblem;
  List<DeliveryPackage> get _route=>widget.state.packages.where(_active).toList();
  bool get _organized=>_route.isNotEmpty&&_route.every((p)=>p.physicalZone?.trim().isNotEmpty==true);

  DeliveryPackage? _selected(){
    final id=selectedId;
    if(id==null)return null;
    for(final p in _route){if(p.id==id)return p;}
    return null;
  }

  Future<void> _assign(String zone)async{
    final p=_selected();
    if(p==null)return;
    try{await widget.state.setPhysicalZone(p.id,zone);if(mounted)setState(()=>selectedId=null);}
    catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$e')));}
  }

  Future<void> _clearSelected()async{
    final p=_selected();
    if(p==null)return;
    try{await widget.state.setPhysicalZone(p.id,null);if(mounted)setState((){});}
    catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$e')));}
  }

  @override Widget build(BuildContext context){
    final route=_route;
    final selected=_selected();
    final assigned=route.where((p)=>p.physicalZone?.trim().isNotEmpty==true).length;
    final missing=route.length-assigned;
    return Scaffold(
      appBar:AppBar(title:const Text('Organizar o carro')),
      body:route.isEmpty?const Center(child:Text('Nenhum pacote ativo na rota.')):Column(children:[
        Padding(padding:const EdgeInsets.fromLTRB(16,12,16,8),child:Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text('$assigned de ${route.length} pacotes posicionados',style:Theme.of(context).textTheme.titleLarge),
          const SizedBox(height:6),
          Text(selected==null?'Toque em um pacote e depois toque na área do carro onde ele ficará.':'Pacote ${selected.scanNumber.toString().padLeft(2,'0')} selecionado. Agora toque na área do carro.'),
          const SizedBox(height:10),
          LinearProgressIndicator(value:route.isEmpty?0:assigned/route.length),
        ])))),
        Expanded(child:SingleChildScrollView(padding:const EdgeInsets.fromLTRB(16,0,16,12),child:Column(children:[
          _carDiagram(context,route),
          const SizedBox(height:14),
          if(selected!=null)SizedBox(width:double.infinity,child:OutlinedButton.icon(onPressed:_clearSelected,icon:const Icon(Icons.remove_circle_outline),label:const Text('TIRAR PACOTE SELECIONADO DO CARRO'))),
          const SizedBox(height:8),
          Align(alignment:Alignment.centerLeft,child:Text('Pacotes para posicionar',style:Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight:FontWeight.bold))),
          const SizedBox(height:8),
          for(final p in route)_packageTile(context,p,selected?.id==p.id),
          if(missing==0)Padding(padding:const EdgeInsets.only(top:8),child:Text('Todos os pacotes estão posicionados. Confira o carro antes de sair.',style:TextStyle(color:Theme.of(context).colorScheme.primary,fontWeight:FontWeight.w600))),
        ]))),
        SafeArea(top:false,child:Padding(padding:const EdgeInsets.fromLTRB(16,8,16,16),child:SizedBox(width:double.infinity,child:FilledButton.icon(onPressed:_organized?()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>DeliveryScreen(state:widget.state))):null,icon:const Icon(Icons.play_arrow),label:const Padding(padding:EdgeInsets.all(15),child:Text('INICIAR ENTREGAS')))))),
      ]),
    );
  }

  Widget _carDiagram(BuildContext context,List<DeliveryPackage> route){
    final selected=_selected();
    return Container(
      constraints:const BoxConstraints(maxWidth:390),
      padding:const EdgeInsets.fromLTRB(14,12,14,14),
      decoration:BoxDecoration(
        color:Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius:BorderRadius.circular(42),
        border:Border.all(color:Theme.of(context).colorScheme.outline,width:2),
        boxShadow:[BoxShadow(color:Theme.of(context).colorScheme.shadow.withValues(alpha:.10),blurRadius:10,offset:const Offset(0,4))],
      ),
      child:Column(children:[
        const Text('FRENTE',style:TextStyle(fontWeight:FontWeight.w800,letterSpacing:1.2)),
        const SizedBox(height:6),
        Container(
          height:20,
          margin:const EdgeInsets.symmetric(horizontal:24),
          decoration:BoxDecoration(
            borderRadius:BorderRadius.circular(12),
            border:Border.all(color:Theme.of(context).colorScheme.outlineVariant),
          ),
          child:Center(child:Text('PARA-BRISA',style:Theme.of(context).textTheme.labelSmall)),
        ),
        const SizedBox(height:10),
        Row(children:[
          Expanded(child:_zone(context,'Frente esquerda','FRENTE E',route,selected)),
          const SizedBox(width:8),
          Expanded(child:_zone(context,'Frente direita','FRENTE D',route,selected)),
        ]),
        const SizedBox(height:8),
        Container(
          height:10,
          margin:const EdgeInsets.symmetric(horizontal:8),
          decoration:BoxDecoration(
            color:Theme.of(context).colorScheme.outlineVariant.withValues(alpha:.35),
            borderRadius:BorderRadius.circular(8),
          ),
        ),
        const SizedBox(height:8),
        Row(children:[
          Expanded(child:_zone(context,'Traseira esquerda','TRASEIRA E',route,selected)),
          const SizedBox(width:8),
          Expanded(child:_zone(context,'Traseira direita','TRASEIRA D',route,selected)),
        ]),
        const SizedBox(height:8),
        _zone(context,'Porta-malas','PORTA-MALAS',route,selected,wide:true),
        const SizedBox(height:6),
        Text(
          selected==null
              ? 'Selecione um pacote e toque no local onde ele ficará.'
              : 'Pacote P${selected.scanNumber.toString().padLeft(2,'0')} selecionado — toque em uma área.',
          textAlign:TextAlign.center,
          style:Theme.of(context).textTheme.bodySmall,
        ),
      ]),
    );
  }

  Widget _zone(BuildContext context,String zone,String shortName,List<DeliveryPackage> route,DeliveryPackage? selected,{bool wide=false}){
    final packages=route.where((p)=>p.physicalZone==zone).toList();
    final activeZone=selected?.physicalZone==zone;
    final highlighted=selected!=null;
    return InkWell(
      onTap:()=>_assign(zone),
      borderRadius:BorderRadius.circular(18),
      child:AnimatedContainer(
        duration:const Duration(milliseconds:160),
        constraints:BoxConstraints(minHeight:wide?78:126),
        padding:const EdgeInsets.all(9),
        decoration:BoxDecoration(
          color:activeZone
              ?Theme.of(context).colorScheme.primaryContainer
              :Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius:BorderRadius.circular(18),
          border:Border.all(
            color:activeZone
                ?Theme.of(context).colorScheme.primary
                :highlighted
                    ?Theme.of(context).colorScheme.outline
                    :Theme.of(context).colorScheme.outlineVariant,
            width:activeZone?2:1,
          ),
        ),
        child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Row(children:[
            Expanded(child:Text(shortName,style:const TextStyle(fontWeight:FontWeight.w800,fontSize:12))),
            if(packages.isNotEmpty)Text('${packages.length}',style:const TextStyle(fontWeight:FontWeight.bold)),
          ]),
          const SizedBox(height:6),
          if(packages.isEmpty)
            const SizedBox(height:72,child:Center(child:Text('Vazio',style:TextStyle(fontSize:12))))
          else
            Wrap(spacing:3,runSpacing:3,children:[
              for(final p in packages)
                GestureDetector(
                  onTap:(){if(mounted)setState(()=>selectedId=p.id);},
                  child:Chip(
                    visualDensity:VisualDensity.compact,
                    padding:EdgeInsets.zero,
                    label:Text('P${p.scanNumber.toString().padLeft(2,'0')}'),
                  ),
                ),
            ]),
        ]),
      ),
    );
  }

  Widget _packageTile(BuildContext context,DeliveryPackage p,bool selected){
    final zone=p.physicalZone?.trim();
    final address=p.address.formatted.isEmpty?p.address.raw:p.address.formatted;
    return Card(margin:const EdgeInsets.only(bottom:6),child:ListTile(selected:selected,leading:CircleAvatar(child:Text(p.scanNumber.toString().padLeft(2,'0'))),title:Text(p.label,style:const TextStyle(fontWeight:FontWeight.w600)),subtitle:Text(zone?.isNotEmpty==true?'$zone\n$address':'Sem posição no carro\n$address',maxLines:2,overflow:TextOverflow.ellipsis),trailing:zone?.isNotEmpty==true?const Chip(label:Text('OK')):const Chip(label:Text('Falta')),onTap:()=>setState(()=>selectedId=selected?null:p.id)));
  }
}

