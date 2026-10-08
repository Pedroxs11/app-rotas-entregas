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
  final Set<String> selectedIds=<String>{};
  final Map<String,GlobalKey> _tileKeys=<String,GlobalKey>{};
  bool multiSelect=false;
  String search='';
  bool get _isMoto=>widget.state.vehicleType==VehicleType.motorcycle;

  bool _active(DeliveryPackage p)=>p.status==DeliveryStatus.pending||p.status==DeliveryStatus.current||p.status==DeliveryStatus.absent||p.status==DeliveryStatus.addressProblem;
  List<DeliveryPackage> get _route=>widget.state.packages.where(_active).toList();
  bool get _organized=>_route.isNotEmpty&&(_isMoto||_route.every((p)=>p.physicalZone?.trim().isNotEmpty==true));

  List<DeliveryPackage> get _visibleRoute{final q=search.trim().toLowerCase();final items=_route.where((p){final unassigned=_isMoto||p.physicalZone?.trim().isNotEmpty!=true;if(!unassigned)return false;return q.isEmpty||p.label.toLowerCase().contains(q)||p.address.formatted.toLowerCase().contains(q)||p.address.raw.toLowerCase().contains(q)||p.scanNumber.toString().contains(q);}).toList();return items;}
  DeliveryPackage? _selected(){
    final id=selectedId;
    if(id==null)return null;
    for(final p in _route){if(p.id==id)return p;}
    return null;
  }

  Future<void> _assign(String zone)async{
    final ids=selectedIds.isNotEmpty?selectedIds.toList():(_selected()==null?<String>[]:[_selected()!.id]);
    if(ids.isEmpty)return;
    try{for(final id in ids){await widget.state.setPhysicalZone(id,zone);}if(mounted)setState((){selectedId=null;selectedIds.clear();});}
    catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$e')));}
  }
  void _togglePackage(String id){setState((){if(!multiSelect){selectedId=selectedId==id?null:id;return;}if(selectedIds.contains(id)){selectedIds.remove(id);}else{selectedIds.add(id);}});}
  void _toggleMulti(){setState((){multiSelect=!multiSelect;selectedId=null;selectedIds.clear();});}
  void _selectAll(){setState(()=>selectedIds.addAll(_visibleRoute.map((p)=>p.id)));}
  void _dragSelect(Offset pos){if(!multiSelect)return;for(final p in _visibleRoute){final ctx=_tileKeys[p.id]?.currentContext;if(ctx==null)continue;final box=ctx.findRenderObject() as RenderBox;final rect=box.localToGlobal(Offset.zero)&box.size;if(rect.contains(pos)&&!selectedIds.contains(p.id)){setState(()=>selectedIds.add(p.id));break;}}}

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
      appBar:AppBar(title:Text(_isMoto?'Organizar a moto':'Organizar o carro'),actions:[if(!_isMoto)IconButton(tooltip:'Selecionar vários',onPressed:_toggleMulti,icon:Icon(multiSelect?Icons.close:Icons.library_add_check)),PopupMenuButton<VehicleType>(tooltip:'Veículo',onSelected:(v)=>setState(()=>widget.state.setVehicleType(v)),itemBuilder:(_)=>const [PopupMenuItem(value:VehicleType.car,child:Text('🚗 Carro')),PopupMenuItem(value:VehicleType.motorcycle,child:Text('🏍️ Moto'))])]),
      body:route.isEmpty?const Center(child:Text('Nenhum pacote ativo na rota.')):Column(children:[
        Padding(padding:const EdgeInsets.fromLTRB(16,12,16,8),child:Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(_isMoto?'${route.length} pacotes • número como identificação':'$assigned de ${route.length} pacotes posicionados',style:Theme.of(context).textTheme.titleLarge),
          const SizedBox(height:6),
          Text(_isMoto?'Na moto não usamos quadrantes. Use o número grande do pacote.':(selected==null?'Toque em um pacote e depois toque na área do carro onde ele ficará.':'Pacote ${selected.scanNumber.toString().padLeft(2,'0')} selecionado. Agora toque na área do carro.')),
          const SizedBox(height:10),
          LinearProgressIndicator(value:route.isEmpty?0:(_isMoto?1:assigned/route.length)),
        ])))),
        Expanded(child:SingleChildScrollView(padding:const EdgeInsets.fromLTRB(16,0,16,12),child:Column(children:[
          if(_isMoto)_motoCard(context,route) else _carDiagram(context,route),
          const SizedBox(height:14),
          if(!_isMoto&&(selected!=null||selectedIds.isNotEmpty))SizedBox(width:double.infinity,child:OutlinedButton.icon(onPressed:_clearSelected,icon:const Icon(Icons.remove_circle_outline),label:const Text('TIRAR PACOTE SELECIONADO DO CARRO'))),
          const SizedBox(height:8),
          Row(children:[Expanded(child:Text(_isMoto?'Pacotes':'Pacotes para posicionar',style:Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight:FontWeight.bold))),if(multiSelect)TextButton(onPressed:_selectAll,child:const Text('Selecionar todos'))]),
          const SizedBox(height:8),
          TextField(decoration:const InputDecoration(prefixIcon:Icon(Icons.search),hintText:'Buscar pacote ou endereço',border:OutlineInputBorder(),isDense:true),onChanged:(v)=>setState(()=>search=v)),
          const SizedBox(height:8),
          Listener(behavior:HitTestBehavior.translucent,onPointerDown:(e)=>_dragSelect(e.position),onPointerMove:(e)=>_dragSelect(e.position),child:Column(children:[for(final p in _visibleRoute)_packageTile(context,p,multiSelect?selectedIds.contains(p.id):selected?.id==p.id)])),
          if(!_isMoto&&missing==0)Padding(padding:const EdgeInsets.only(top:8),child:Text('Todos os pacotes estão posicionados. Confira o carro antes de sair.',style:TextStyle(color:Theme.of(context).colorScheme.primary,fontWeight:FontWeight.w600))),
        ]))),
        SafeArea(top:false,child:Padding(padding:const EdgeInsets.fromLTRB(16,8,16,16),child:SizedBox(width:double.infinity,child:FilledButton.icon(onPressed:_organized?()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>DeliveryScreen(state:widget.state))):null,icon:const Icon(Icons.play_arrow),label:const Padding(padding:EdgeInsets.all(15),child:Text('INICIAR ENTREGAS')))))),
      ]),
    );
  }

  Widget _motoCard(BuildContext context,List<DeliveryPackage> route){return Card(child:Padding(padding:const EdgeInsets.all(20),child:Column(children:[const Icon(Icons.two_wheeler,size:56),const SizedBox(height:8),const Text('MODO MOTO',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),const SizedBox(height:6),const Text('Sem quadrantes. Cada pacote será identificado pelo número.',textAlign:TextAlign.center),const SizedBox(height:14),Wrap(spacing:10,runSpacing:10,children:[for(final p in route.take(12))Container(width:72,padding:const EdgeInsets.symmetric(vertical:10),decoration:BoxDecoration(borderRadius:BorderRadius.circular(14),color:Theme.of(context).colorScheme.primaryContainer),child:Text(p.scanNumber.toString().padLeft(2,'0'),textAlign:TextAlign.center,style:const TextStyle(fontSize:26,fontWeight:FontWeight.w900)))])])));}

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
    final cs=Theme.of(context).colorScheme;return Card(key:_tileKeys.putIfAbsent(p.id,()=>GlobalKey()),margin:const EdgeInsets.only(bottom:6),color:selected?cs.inverseSurface:null,child:ListTile(selected:selected,selectedColor:selected?cs.onInverseSurface:null,leading:CircleAvatar(radius:24,backgroundColor:selected?cs.onInverseSurface:cs.primaryContainer,foregroundColor:selected?cs.inverseSurface:null,child:Text(p.scanNumber.toString().padLeft(2,'0'),style:const TextStyle(fontWeight:FontWeight.w900))),title:Text(p.label,style:const TextStyle(fontWeight:FontWeight.w700)),subtitle:Text(_isMoto?address:(zone?.isNotEmpty==true?'$zone\n$address':'Sem posição no carro\n$address'),maxLines:2,overflow:TextOverflow.ellipsis),trailing:_isMoto?null:(zone?.isNotEmpty==true?const Chip(label:Text('OK')):const Chip(label:Text('Falta'))),onTap:()=>_togglePackage(p.id)));
  }
}

