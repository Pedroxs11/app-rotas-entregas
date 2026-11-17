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
  Offset? _selectionPointerStart;
  Offset? _selectionPointerLast;
  bool _dragSelecting=false;
  bool _suppressNextTap=false;
  String search='';
  bool get _isMoto=>widget.state.vehicleType==VehicleType.motorcycle;

  bool _active(DeliveryPackage p)=>p.status==DeliveryStatus.pending||p.status==DeliveryStatus.current||p.status==DeliveryStatus.absent||p.status==DeliveryStatus.addressProblem;
  List<DeliveryPackage> get _route=>widget.state.packages.where(_active).toList();
  bool _hasActiveZone(DeliveryPackage p)=>p.physicalZone?.trim().isNotEmpty==true&&widget.state.activePhysicalZones.contains(p.physicalZone);
  bool get _organized=>_route.isNotEmpty&&_route.every(_hasActiveZone);

  bool _matchesSearch(DeliveryPackage p){final q=search.trim().toLowerCase();return q.isEmpty||p.label.toLowerCase().contains(q)||p.address.formatted.toLowerCase().contains(q)||p.address.raw.toLowerCase().contains(q)||p.scanNumber.toString().contains(q);}
  List<DeliveryPackage> get _visibleRoute=>_route.where((p)=>!_hasActiveZone(p)&&_matchesSearch(p)).toList();
  DeliveryPackage? _selected(){
    final id=selectedId;
    if(id==null)return null;
    for(final p in _route){if(p.id==id)return p;}
    return null;
  }

  Future<void> _assign(String zone)async{
    final ids=selectedIds.isNotEmpty?selectedIds.toList():(_selected()==null?<String>[]:[_selected()!.id]);
    if(ids.isEmpty)return;
    try{await widget.state.setPhysicalZones(ids.toSet(),zone);if(mounted)setState((){selectedId=null;selectedIds.clear();});}
    catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$e')));}
  }
  void _togglePackage(String id){if(_suppressNextTap){_suppressNextTap=false;return;}setState((){if(!multiSelect){selectedId=selectedId==id?null:id;return;}if(selectedIds.contains(id)){selectedIds.remove(id);}else{selectedIds.add(id);}});}
  void _toggleMulti(){setState((){multiSelect=!multiSelect;selectedId=null;selectedIds.clear();});}
  void _selectAll(){setState(()=>selectedIds.addAll(_route.where(_matchesSearch).map((p)=>p.id)));}
  void _selectionPointerDown(Offset pos){if(!multiSelect)return;_selectionPointerStart=pos;_selectionPointerLast=pos;_dragSelecting=false;}
  void _selectionPointerMove(Offset pos){
    if(!multiSelect||_selectionPointerStart==null)return;
    final start=_selectionPointerStart!;
    final previous=_selectionPointerLast??start;
    if(!_dragSelecting&&(pos-start).distance>10){
      _dragSelecting=true;
      _selectAt(start);
    }
    if(_dragSelecting)_selectAlong(previous,pos);
    _selectionPointerLast=pos;
  }
  void _selectAlong(Offset from,Offset to){
    final distance=(to-from).distance;
    final steps=(distance/8).ceil();
    // Long selections can cross dozens of cards in one pointer event. Keep
    // the sampling dense enough to avoid skipping cards on large routes.
    final sampleCount=steps.clamp(1,512).toInt();
    for(var step=1;step<=sampleCount;step++){
      final point=from+(to-from)*(step/sampleCount);
      _selectAt(point);
    }
  }
  void _selectionPointerUp(){if(_dragSelecting){_suppressNextTap=true;WidgetsBinding.instance.addPostFrameCallback((_){if(mounted)_suppressNextTap=false;});}_selectionPointerStart=null;_selectionPointerLast=null;_dragSelecting=false;}
  void _selectAt(Offset pos){for(final p in _visibleRoute){final ctx=_tileKeys[p.id]?.currentContext;if(ctx==null)continue;final object=ctx.findRenderObject();if(object is! RenderBox||!object.hasSize)continue;final rect=object.localToGlobal(Offset.zero)&object.size;if(rect.contains(pos)&&!selectedIds.contains(p.id)){setState(()=>selectedIds.add(p.id));break;}}}

  Future<void> _clearSelected()async{
    final ids=selectedIds.isNotEmpty?selectedIds.toList():(_selected()==null?<String>[]:[_selected()!.id]);
    if(ids.isEmpty)return;
    try{await widget.state.clearPhysicalZones(ids.toSet());if(mounted)setState((){selectedId=null;selectedIds.clear();});}
    catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$e')));}
  }

  @override Widget build(BuildContext context){
    final route=_route;
    final selected=_selected();
    final assigned=route.where(_hasActiveZone).length;
    final missing=route.length-assigned;
    return Scaffold(
      appBar:AppBar(title:Text(_isMoto?'Organizar a moto':'Organizar o carro'),actions:[IconButton(tooltip:'Configurar compartimentos',onPressed:_configureZones,icon:const Icon(Icons.tune)),IconButton(tooltip:'Selecionar vários',onPressed:_toggleMulti,icon:Icon(multiSelect?Icons.close:Icons.library_add_check)),PopupMenuButton<VehicleType>(tooltip:'Veículo',onSelected:(v)async{await widget.state.setVehicleType(v);if(mounted)setState((){selectedId=null;selectedIds.clear();});},itemBuilder:(_)=>const [PopupMenuItem(value:VehicleType.car,child:Text('🚗 Carro')),PopupMenuItem(value:VehicleType.motorcycle,child:Text('🏍️ Moto'))])]),
      body:route.isEmpty?const Center(child:Text('Nenhum pacote ativo na rota.')):Column(children:[
        Padding(padding:const EdgeInsets.fromLTRB(16,12,16,8),child:Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text('$assigned de ${route.length} pacotes posicionados',style:Theme.of(context).textTheme.titleLarge),
          if(multiSelect)Padding(padding:const EdgeInsets.only(top:6),child:Text('${selectedIds.length} pacote(s) selecionado(s)',style:TextStyle(fontWeight:FontWeight.w700,color:Theme.of(context).colorScheme.primary))),
          const SizedBox(height:6),
          Text(multiSelect?'Selecione vários pacotes e toque uma vez no compartimento para guardar todos.':(selected==null?(_isMoto?'Toque em um pacote e depois no baú, bolsa ou mochila.':'Toque em um pacote e depois na área do carro onde ele ficará.'):'Pacote ${selected.scanNumber.toString().padLeft(2,'0')} selecionado. Agora toque no compartimento do veículo.')),
          const SizedBox(height:10),
          LinearProgressIndicator(value:route.isEmpty?0:assigned/route.length),
        ])))),
        Expanded(child:SingleChildScrollView(padding:const EdgeInsets.fromLTRB(16,0,16,12),child:Column(children:[
          if(_isMoto)_motoCard(context,route) else _carDiagram(context,route),
          const SizedBox(height:14),
          if(selected!=null||selectedIds.isNotEmpty)SizedBox(width:double.infinity,child:OutlinedButton.icon(onPressed:_clearSelected,icon:const Icon(Icons.remove_circle_outline),label:Text(selectedIds.length>1?'RETIRAR ${selectedIds.length} PACOTES':'RETIRAR PACOTE SELECIONADO'))),
          const SizedBox(height:8),
          Row(children:[Expanded(child:Text(_isMoto?'Pacotes':'Pacotes para posicionar',style:Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight:FontWeight.bold))),if(multiSelect)TextButton(onPressed:_selectAll,child:const Text('Selecionar todos'))]),
          const SizedBox(height:8),
          TextField(decoration:const InputDecoration(prefixIcon:Icon(Icons.search),hintText:'Buscar pacote ou endereço',border:OutlineInputBorder(),isDense:true),onChanged:(v)=>setState(()=>search=v)),
          const SizedBox(height:8),
          Listener(behavior:HitTestBehavior.translucent,onPointerDown:(e)=>_selectionPointerDown(e.position),onPointerMove:(e)=>_selectionPointerMove(e.position),onPointerUp:(_)=>_selectionPointerUp(),onPointerCancel:(_)=>_selectionPointerUp(),child:Column(children:[for(final p in _visibleRoute)_packageTile(context,p,multiSelect?selectedIds.contains(p.id):selected?.id==p.id)])),
          if(missing==0)Padding(padding:const EdgeInsets.only(top:8),child:Text('Todos os pacotes estão posicionados. Confira a carga antes de sair.',style:TextStyle(color:Theme.of(context).colorScheme.primary,fontWeight:FontWeight.w600))),
        ]))),
        SafeArea(top:false,child:Padding(padding:const EdgeInsets.fromLTRB(16,8,16,16),child:SizedBox(width:double.infinity,child:FilledButton.icon(onPressed:_organized?()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>DeliveryScreen(state:widget.state))):null,icon:const Icon(Icons.play_arrow),label:const Padding(padding:EdgeInsets.all(15),child:Text('INICIAR ENTREGAS')))))),
      ]),
    );
  }

  Future<void> _configureZones()async{
    final defaults=_isMoto?AppState.motorcyclePhysicalZones:AppState.carPhysicalZones;
    final selected=widget.state.activePhysicalZones.toSet();
    await showDialog<void>(context:context,builder:(dialogContext)=>StatefulBuilder(builder:(context,setDialogState)=>AlertDialog(
      title:Text(_isMoto?'Compartimentos da moto':'Compartimentos do carro'),
      content:Column(mainAxisSize:MainAxisSize.min,children:[
        const Text('Ative apenas os espaços que existem no seu veículo.'),
        const SizedBox(height:8),
        for(final zone in defaults)CheckboxListTile(
          contentPadding:EdgeInsets.zero,
          dense:true,
          title:Text(zone),
          value:selected.contains(zone),
          onChanged:(value)=>setDialogState(()=>value==true?selected.add(zone):selected.remove(zone)),
        ),
      ]),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(dialogContext),child:const Text('Cancelar')),
        FilledButton(onPressed:selected.isEmpty?null:()async{
          try{await widget.state.setActivePhysicalZones(selected.toList());if(dialogContext.mounted)Navigator.pop(dialogContext);if(mounted)setState((){});}
          catch(e){if(dialogContext.mounted)ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content:Text('$e')));}
        },child:const Text('Salvar')),
      ],
    )));
  }

  Widget _motoCard(BuildContext context,List<DeliveryPackage> route){
    final zones=widget.state.activePhysicalZones;
    final sideZones=zones.where((z)=>z=='Bolsa lateral esquerda'||z=='Bolsa lateral direita').toList();
    final rearZones=zones.where((z)=>z=='Baú traseiro'||z=='Mochila de entrega').toList();
    String label(String zone)=>switch(zone){
      'Bolsa lateral esquerda'=>'BOLSA ESQUERDA',
      'Bolsa lateral direita'=>'BOLSA DIREITA',
      'Baú traseiro'=>'BAÚ TRASEIRO',
      'Mochila de entrega'=>'MOCHILA DE ENTREGA',
      _=>zone.toUpperCase(),
    };
    return Card(
      child:Padding(
        padding:const EdgeInsets.all(14),
        child:Column(children:[
          const Text('MODO MOTO',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
          const SizedBox(height:4),
          const Text('Toque no espaço da moto onde cada pacote será transportado.',textAlign:TextAlign.center),
          const SizedBox(height:12),
          const Text('FRENTE DA MOTO',style:TextStyle(fontWeight:FontWeight.w800,letterSpacing:1)),
          const SizedBox(height:8),
          Row(
            crossAxisAlignment:CrossAxisAlignment.center,
            children:[
              for(final zone in sideZones)
                Expanded(
                  child:Padding(
                    padding:const EdgeInsets.symmetric(horizontal:3),
                    child:_zone(context,zone,label(zone),route,_selected(),wide:true),
                  ),
                ),
              Expanded(
                flex:sideZones.isEmpty?1:2,
                child:Column(children:[
                  Icon(Icons.two_wheeler,size:sideZones.isEmpty?76:64,color:Theme.of(context).colorScheme.onSurfaceVariant),
                  Text('MOTO',style:Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight:FontWeight.bold)),
                ]),
              ),
            ],
          ),
          if(rearZones.isNotEmpty)...[
            const SizedBox(height:10),
            const Text('TRASEIRA E BAGAGEM',style:TextStyle(fontWeight:FontWeight.w800,letterSpacing:1)),
            const SizedBox(height:8),
            if(rearZones.length==1)
              _zone(context,rearZones.first,label(rearZones.first),route,_selected(),wide:true)
            else
              Wrap(
                spacing:8,
                runSpacing:8,
                alignment:WrapAlignment.center,
                children:[
                  for(final zone in rearZones)
                    SizedBox(
                      width:145,
                      child:_zone(context,zone,label(zone),route,_selected(),wide:true),
                    ),
                ],
              ),
          ],
          const SizedBox(height:10),
          Wrap(
            spacing:8,
            runSpacing:8,
            children:[
              for(final p in route)
                if(_hasActiveZone(p))
                  Chip(
                    avatar:const Icon(Icons.inventory_2_outlined,size:16),
                    label:Text('P${p.scanNumber.toString().padLeft(2,'0')} • ${p.physicalZone}'),
                  ),
            ],
          ),
        ]),
      ),
    );
  }

  Widget _carDiagram(BuildContext context,List<DeliveryPackage> route){
    final selected=_selected();
    final colors=Theme.of(context).colorScheme;
    return SizedBox(
      width:double.infinity,
      child:CustomPaint(
        painter:_CarSilhouettePainter(
          fill:colors.surfaceContainerLow,
          outline:colors.outline,
          glass:colors.surfaceContainerHighest,
          tire:colors.onSurface.withValues(alpha:.72),
        ),
        child:Padding(
          padding:const EdgeInsets.fromLTRB(28,20,28,22),
          child:Column(children:[
            const SizedBox(height:8),
            const Text('FRENTE',style:TextStyle(fontWeight:FontWeight.w800,letterSpacing:1.1)),
            const SizedBox(height:12),
            Container(
              height:34,
              margin:const EdgeInsets.symmetric(horizontal:30),
              decoration:BoxDecoration(
                color:colors.surfaceContainerHighest,
                borderRadius:BorderRadius.circular(18),
                border:Border.all(color:colors.outlineVariant),
              ),
              child:Center(child:Text('PARA-BRISA',style:Theme.of(context).textTheme.labelSmall)),
            ),
            const SizedBox(height:12),
            Wrap(
              spacing:8,
              runSpacing:8,
              alignment:WrapAlignment.center,
              children:[
                for(final zone in widget.state.activePhysicalZones)
                  SizedBox(
                    width:zone=='Porta-malas'?double.infinity:150,
                    child:_zone(context,zone,_carZoneLabel(zone),route,selected,wide:zone=='Porta-malas'),
                  ),
              ],
            ),
            const SizedBox(height:12),
            Container(
              height:24,
              margin:const EdgeInsets.symmetric(horizontal:42),
              decoration:BoxDecoration(
                color:colors.surfaceContainerHighest,
                borderRadius:BorderRadius.circular(12),
                border:Border.all(color:colors.outlineVariant),
              ),
              child:Center(child:Text('TRASEIRA',style:Theme.of(context).textTheme.labelSmall)),
            ),
            const SizedBox(height:8),
            const Text('Toque em um compartimento para guardar os pacotes selecionados.',textAlign:TextAlign.center),
          ]),
        ),
      ),
    );
  }

  String _carZoneLabel(String zone)=>switch(zone){
    'Frente esquerda'=>'FRENTE E',
    'Frente direita'=>'FRENTE D',
    'Traseira esquerda'=>'TRASEIRA E',
    'Traseira direita'=>'TRASEIRA D',
    'Porta-malas'=>'PORTA-MALAS',
    _=>zone.toUpperCase(),
  };

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
                InputChip(
                  visualDensity:VisualDensity.compact,
                  padding:EdgeInsets.zero,
                  selected:multiSelect?selectedIds.contains(p.id):selected?.id==p.id,
                  onSelected:(_)=>_togglePackage(p.id),
                  label:Text('P${p.scanNumber.toString().padLeft(2,'0')}'),
                ),
            ]),
        ]),
      ),
    );
  }

  Widget _packageTile(BuildContext context,DeliveryPackage p,bool selected){
    final zone=p.physicalZone?.trim();
    final address=p.address.formatted.isEmpty?p.address.raw:p.address.formatted;
    final cs=Theme.of(context).colorScheme;return Card(key:_tileKeys.putIfAbsent(p.id,()=>GlobalKey()),margin:const EdgeInsets.only(bottom:6),color:selected?cs.inverseSurface:null,child:ListTile(selected:selected,selectedColor:selected?cs.onInverseSurface:null,leading:CircleAvatar(radius:24,backgroundColor:selected?cs.onInverseSurface:cs.primaryContainer,foregroundColor:selected?cs.inverseSurface:null,child:Text(p.scanNumber.toString().padLeft(2,'0'),style:const TextStyle(fontWeight:FontWeight.w900))),title:Text(p.label,style:const TextStyle(fontWeight:FontWeight.w700)),subtitle:Text(_isMoto?address:(_hasActiveZone(p)?'$zone\n$address':'Sem posição no carro\n$address'),maxLines:2,overflow:TextOverflow.ellipsis),trailing:_isMoto?null:(_hasActiveZone(p)?const Chip(label:Text('OK')):const Chip(label:Text('Falta'))),onTap:()=>_togglePackage(p.id)));
  }
}



class _CarSilhouettePainter extends CustomPainter {
  final Color fill,outline,glass,tire;
  const _CarSilhouettePainter({required this.fill,required this.outline,required this.glass,required this.tire});

  @override
  void paint(Canvas canvas,Size size){
    final scale=size.width/360;
    final body=Path()
      ..moveTo(size.width*.34,8*scale)
      ..quadraticBezierTo(size.width*.50,-2*scale,size.width*.66,8*scale)
      ..lineTo(size.width*.82,24*scale)
      ..quadraticBezierTo(size.width*.91,34*scale,size.width*.92,54*scale)
      ..lineTo(size.width*.92,size.height-54*scale)
      ..quadraticBezierTo(size.width*.90,size.height-18*scale,size.width*.72,size.height-8*scale)
      ..quadraticBezierTo(size.width*.50,size.height+2*scale,size.width*.28,size.height-8*scale)
      ..quadraticBezierTo(size.width*.10,size.height-18*scale,size.width*.08,size.height-54*scale)
      ..lineTo(size.width*.08,54*scale)
      ..quadraticBezierTo(size.width*.09,34*scale,size.width*.18,24*scale)
      ..close();
    canvas.drawPath(body,Paint()..color=fill..style=PaintingStyle.fill);
    canvas.drawPath(body,Paint()..color=outline..style=PaintingStyle.stroke..strokeWidth=2*scale);
    final tirePaint=Paint()..color=tire;
    for(final y in [size.height*.22,size.height*.76]){
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(size.width*.045,y-25*scale,14*scale,50*scale),Radius.circular(6*scale)),tirePaint);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(size.width*.915,y-25*scale,14*scale,50*scale),Radius.circular(6*scale)),tirePaint);
    }
    final windshield=Path()
      ..moveTo(size.width*.29,30*scale)
      ..quadraticBezierTo(size.width*.50,18*scale,size.width*.71,30*scale)
      ..lineTo(size.width*.78,76*scale)
      ..quadraticBezierTo(size.width*.50,88*scale,size.width*.22,76*scale)
      ..close();
    canvas.drawPath(windshield,Paint()..color=glass..style=PaintingStyle.fill);
    canvas.drawPath(windshield,Paint()..color=outline..style=PaintingStyle.stroke..strokeWidth=1.2*scale);
    final rear=Path()
      ..moveTo(size.width*.22,size.height-70*scale)
      ..quadraticBezierTo(size.width*.50,size.height-58*scale,size.width*.78,size.height-70*scale)
      ..lineTo(size.width*.72,size.height-28*scale)
      ..quadraticBezierTo(size.width*.50,size.height-18*scale,size.width*.28,size.height-28*scale)
      ..close();
    canvas.drawPath(rear,Paint()..color=glass..style=PaintingStyle.fill);
    canvas.drawPath(rear,Paint()..color=outline..style=PaintingStyle.stroke..strokeWidth=1.2*scale);
  }
  @override
  bool shouldRepaint(covariant _CarSilhouettePainter oldDelegate)=>fill!=oldDelegate.fill||outline!=oldDelegate.outline||glass!=oldDelegate.glass||tire!=oldDelegate.tire;
}
