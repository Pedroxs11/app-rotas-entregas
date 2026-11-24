import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
  // Only rows currently mounted by the lazy list are registered here.
  // This keeps pointer hit-testing proportional to the visible rows, not the full load.
  final Map<String, RenderBox> _mountedTileBoxes = <String, RenderBox>{};
  final Map<String, int> _dragSelectionIndexById = <String, int>{};
  static const int _initialZonePackageCount = 8;
  static const int _zonePackagePageSize = 24;
  final Map<String, int> _visibleZonePackageCount = <String, int>{};
  ScrollController _scrollController=ScrollController(keepScrollOffset:false);
  GlobalKey _scrollViewportKey=GlobalKey();
  Timer? _autoScrollTimer;
  Offset? _lastSelectionPointer;
  List<DeliveryPackage> _dragSelectionPackages = const [];
  int? _lastSelectionIndex;
  String? _selectionStartPackageId;
  double _autoScrollDirection=0;
  double _autoScrollSpeed=0;
  bool multiSelect=false;
  bool _dragSelecting=false;
  int? _selectionPointerId;
  String? _selectionPointerPackageId;
  bool _suppressNextTap=false;
  bool _vehicleSwitching=false;
  bool _loadMutationInProgress=false;
  String search='';
  final TextEditingController _searchController=TextEditingController();
  bool get _isMoto=>widget.state.vehicleType==VehicleType.motorcycle;

  @override
  void dispose(){
    _autoScrollTimer?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  bool _active(DeliveryPackage p)=>p.status==DeliveryStatus.pending||p.status==DeliveryStatus.current||p.status==DeliveryStatus.absent||p.status==DeliveryStatus.addressProblem;
  List<DeliveryPackage> get _route=>widget.state.packages.where(_active).toList();

  String? _normalizedPhysicalZone(DeliveryPackage package) {
    final zone = package.physicalZone?.trim();
    return zone == null || zone.isEmpty ? null : zone;
  }

  bool _isPackageInZone(DeliveryPackage package, String zone) =>
      _normalizedPhysicalZone(package) == zone;

  bool _hasActiveZone(DeliveryPackage package) {
    final zone = _normalizedPhysicalZone(package);
    return zone != null && widget.state.activePhysicalZones.contains(zone);
  }

  String _normalizeSearchText(String value) => value.toLowerCase()
      .replaceAll(RegExp(r'[áàâãäå]'), 'a')
      .replaceAll(RegExp(r'[éèêë]'), 'e')
      .replaceAll(RegExp(r'[íìîï]'), 'i')
      .replaceAll(RegExp(r'[óòôõöø]'), 'o')
      .replaceAll(RegExp(r'[úùûü]'), 'u')
      .replaceAll('ç', 'c')
      .replaceAll('ñ', 'n')
      .replaceAll(RegExp(r'[ýÿ]'), 'y');

  bool _matchesSearch(DeliveryPackage p, String query){
    // The query is normalized once per filtering pass, not once per package.
    // Drivers often type addresses without accents, so "Sao Paulo" still finds
    // "São Paulo" without changing the displayed address.
    if(query.isEmpty)return true;
    final number=p.scanNumber.toString();
    final paddedNumber=number.padLeft(2,'0');
    final normalizedQuery=query.replaceAll(RegExp(r'[^a-z0-9]'),'');
    final codeNumber=normalizedQuery.startsWith('p')
        ?normalizedQuery.substring(1)
        :'';
    final matchesCode=codeNumber==number||codeNumber==paddedNumber;
    return _normalizeSearchText(p.label).contains(query)||
        matchesCode||
        number.contains(query)||
        paddedNumber.contains(query)||
        _normalizeSearchText(p.address.formatted).contains(query)||
        _normalizeSearchText(p.address.raw).contains(query);
  }
  List<DeliveryPackage> _visibleRouteForQuery(String query)=>_route
      .where((p)=>!_hasActiveZone(p)&&_matchesSearch(p,query))
      .toList(growable:false);
  List<DeliveryPackage> get _visibleRoute=>
      _visibleRouteForQuery(_normalizeSearchText(search.trim()));
  DeliveryPackage? _selected(List<DeliveryPackage> route){
    final id=selectedId;
    if(id==null)return null;
    for(final package in route){if(package.id==id)return package;}
    return null;
  }

  Future<void> _assign(String zone) async {
    if (_vehicleSwitching || _loadMutationInProgress) return;
    final route = _route;
    final selectedPackage = _selected(route);
    final ids = selectedIds.isNotEmpty
        ? selectedIds.toSet()
        : selectedPackage == null
            ? <String>{}
            : <String>{selectedPackage.id};
    if (ids.isEmpty) return;
    final targetZoneWasEmpty =
        !route.any((package) => _isPackageInZone(package, zone));

    // Stop any active drag/autoscroll before locking the screen. The timer
    // runs independently of pointer hit-testing, so AbsorbPointer alone
    // would not stop it from scrolling the old load while persistence waits.
    _cancelDragSelection();
    _suppressNextTap = false;

    // Do not queue a second UI mutation while the first save is pending. The
    // state layer serializes writes, but without this screen-level lock two
    // rapid compartment taps could move the same packages twice.
    setState(() => _loadMutationInProgress = true);
    try {
      await widget.state.setPhysicalZones(ids, zone);
      if (!mounted) return;
      setState(() {
        // A compartment that was empty may still have a stale expansion count
        // from an earlier load. Start its next load with the compact preview.
        if (targetZoneWasEmpty) _visibleZonePackageCount.remove(zone);
        _pruneEmptyZonePreviews();
        selectedId = null;
        selectedIds.clear();
        _loadMutationInProgress = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadMutationInProgress = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    }
  }

  Future<void> _switchVehicle(VehicleType value) async {
    if (value == widget.state.vehicleType ||
        _vehicleSwitching ||
        _loadMutationInProgress) {
      return;
    }

    // End the drag session and lock the organizer before asynchronous
    // persistence. Otherwise a second gesture could start against the old
    // vehicle layout while the first vehicle change is still being saved.
    _cancelDragSelection();
    _suppressNextTap = false;

    setState(() {
      _vehicleSwitching = true;
      selectedId = null;
      selectedIds.clear();
    });

    try {
      await widget.state.setVehicleType(value);
    } catch (error) {
      if (!mounted) return;
      setState(() => _vehicleSwitching = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível trocar o veículo: $error')),
      );
      return;
    }
    if (!mounted) return;

    _mountedTileBoxes.clear();

    // A vehicle change replaces the diagram and changes the sliver extents.
    // Recreate the scrollable with a fresh controller so Flutter cannot
    // restore the previous vehicle's offset during the next layout pass.
    final previousController = _scrollController;
    final nextController = ScrollController(keepScrollOffset: false);
    _searchController.clear();
    setState(() {
      _scrollController = nextController;
      _scrollViewportKey = GlobalKey();
      search = '';
      selectedId = null;
      selectedIds.clear();
      _visibleZonePackageCount.clear();
      _vehicleSwitching = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      previousController.dispose();
    });
  }
  void _togglePackage(String id){if(_loadMutationInProgress||_vehicleSwitching)return;if(_suppressNextTap){_suppressNextTap=false;return;}setState((){if(!multiSelect){selectedId=selectedId==id?null:id;return;}if(selectedIds.contains(id)){selectedIds.remove(id);}else{selectedIds.add(id);}});}
  void _toggleMulti(){
    if (_loadMutationInProgress || _vehicleSwitching) return;
    // A second pointer can toggle multi-select while another finger is still
    // dragging. Stop its timer before changing modes so it cannot keep
    // scrolling or adding selections after multi-select has been disabled.
    _cancelDragSelection();
    setState(() {
      multiSelect = !multiSelect;
      selectedId = null;
      selectedIds.clear();
    });
  }
  void _updateSearch(String value) {
    if (value == search) return;
    if (_dragSelecting || _selectionPointerId != null) {
      _cancelDragSelection();
    }
    setState(() => search = value);
  }

  bool _allVisiblePackagesSelected(List<DeliveryPackage> visible) =>
      visible.isNotEmpty && visible.every((package) => selectedIds.contains(package.id));

  void _toggleSelectAll(List<DeliveryPackage> visible) {
    if (visible.isEmpty || _loadMutationInProgress || _vehicleSwitching) return;
    setState(() {
      final ids = visible.map((package) => package.id).toSet();
      if (ids.every(selectedIds.contains)) {
        selectedIds.removeAll(ids);
      } else {
        selectedIds.addAll(ids);
      }
    });
  }
  void _registerTileBox(String id, RenderBox box, bool attached) {
    if (attached) {
      _mountedTileBoxes[id] = box;
    } else if (identical(_mountedTileBoxes[id], box)) {
      _mountedTileBoxes.remove(id);
    }
  }

  void _selectionPointerDown(Offset pos, String packageId) {
    // LongPressStartDetails does not expose its pointer id. The ancestor
    // Listener reserves the first pointer's package, so a second finger's
    // long press cannot replace the active selection anchor.
    if (!multiSelect ||
        _selectionPointerId == null ||
        _selectionPointerPackageId != packageId ||
        _dragSelecting) {
      return;
    }
    _dragSelectionPackages = _visibleRoute;
    _dragSelectionIndexById.clear();
    for (var index = 0; index < _dragSelectionPackages.length; index++) {
      _dragSelectionIndexById[_dragSelectionPackages[index].id] = index;
    }
    _selectionStartPackageId =
        _dragSelectionIndexById.containsKey(packageId) ? packageId : null;
    _lastSelectionPointer = pos;
    _lastSelectionIndex = _selectionStartPackageId == null
        ? null
        : _dragSelectionIndexById[_selectionStartPackageId!];
    _dragSelecting = _selectionStartPackageId != null;
    if (_dragSelecting && !selectedIds.contains(_selectionStartPackageId)) {
      setState(() => selectedIds.add(_selectionStartPackageId!));
    }
  }

  void _selectionPointerMove(Offset pos) {
    if (!multiSelect || !_dragSelecting) return;
    _lastSelectionPointer = pos;
    _selectAt(pos);
    _updateSelectionAutoScroll();
  }

  void _updateSelectionAutoScroll(){
    if(!_dragSelecting||_lastSelectionPointer==null||!_scrollController.hasClients){
      _stopSelectionAutoScroll();
      return;
    }
    final viewportContext=_scrollViewportKey.currentContext;
    final viewportObject=viewportContext?.findRenderObject();
    if(viewportObject is! RenderBox||!viewportObject.hasSize){
      _stopSelectionAutoScroll();
      return;
    }
    final viewport=viewportObject.localToGlobal(Offset.zero)&viewportObject.size;
    final pointerY=_lastSelectionPointer!.dy;
    const edgeSize=64.0;
    if(pointerY<viewport.top+edgeSize){
      _autoScrollDirection=-1;
      _autoScrollSpeed=(6+((viewport.top+edgeSize-pointerY)/edgeSize).clamp(0.0,1.0)*22).toDouble();
    }else if(pointerY>viewport.bottom-edgeSize){
      _autoScrollDirection=1;
      _autoScrollSpeed=(6+((pointerY-(viewport.bottom-edgeSize))/edgeSize).clamp(0.0,1.0)*22).toDouble();
    }else{
      _stopSelectionAutoScroll();
      return;
    }
    _autoScrollTimer??=Timer.periodic(const Duration(milliseconds:16),_autoScrollTick);
  }

  void _autoScrollTick(Timer timer){
    if(!mounted||!_dragSelecting||!_scrollController.hasClients){
      _stopSelectionAutoScroll();
      return;
    }
    final position=_scrollController.position;
    final next=(position.pixels+_autoScrollDirection*_autoScrollSpeed).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    ).toDouble();
    if((next-position.pixels).abs()<0.5){
      _stopSelectionAutoScroll();
      return;
    }
    _scrollController.jumpTo(next);
    final pointer=_lastSelectionPointer;
    if(pointer!=null)_selectAt(pointer);
  }

  void _stopSelectionAutoScroll(){
    _autoScrollTimer?.cancel();
    _autoScrollTimer=null;
    _autoScrollDirection=0;
    _autoScrollSpeed=0;
  }

  void _cancelDragSelection() {
    _stopSelectionAutoScroll();
    _selectionStartPackageId = null;
    _lastSelectionPointer = null;
    _dragSelectionPackages = const [];
    _dragSelectionIndexById.clear();
    _lastSelectionIndex = null;
    _dragSelecting = false;
    _selectionPointerId = null;
    _selectionPointerPackageId = null;
  }

  void _selectionPointerUp(int pointer) {
    // The list can receive multiple simultaneous pointers. Only the pointer
    // that started the long-press selection may finish that drag session.
    if (_selectionPointerId != pointer) return;
    _selectionPointerId = null;
    final wasDragging = _dragSelecting;
    if (wasDragging) {
      _suppressNextTap = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _suppressNextTap = false;
      });
    }
    _cancelDragSelection();
  }
  String? _mountedPackageIdAt(Offset pos) {
    for (final entry in _mountedTileBoxes.entries) {
      final box = entry.value;
      if (!box.attached || !box.hasSize) continue;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      if (rect.contains(pos)) return entry.key;
    }
    return null;
  }

  String? _packageIdAt(Offset pos) {
    for (final entry in _mountedTileBoxes.entries) {
      final box = entry.value;
      if (!box.attached || !box.hasSize ||
          !_dragSelectionIndexById.containsKey(entry.key)) {
        continue;
      }
      final rect = box.localToGlobal(Offset.zero) & box.size;
      if (rect.contains(pos)) return entry.key;
    }
    return null;
  }

  void _selectAt(Offset pos) {
    final visible = _dragSelectionPackages;
    if (visible.isEmpty) return;

    final currentId = _packageIdAt(pos);
    if (currentId == null) return;

    final currentIndex = _dragSelectionIndexById[currentId];
    if (currentIndex == null) return;

    final previousIndex = _lastSelectionIndex ?? currentIndex;
    if (currentIndex == previousIndex) return;

    final first = previousIndex < currentIndex ? previousIndex : currentIndex;
    final last = previousIndex > currentIndex ? previousIndex : currentIndex;
    final matches = <String>{};
    for (var index = first; index <= last; index++) {
      final id = visible[index].id;
      if (!selectedIds.contains(id)) matches.add(id);
    }
    _lastSelectionIndex = currentIndex;
    if (matches.isNotEmpty) setState(() => selectedIds.addAll(matches));
  }

  Set<String> _selectedAssignedPackageIds(List<DeliveryPackage> route) {
    final selected = selectedIds.isNotEmpty
        ? selectedIds
        : selectedId == null
            ? const <String>{}
            : <String>{selectedId!};
    return route
        .where((package) =>
            selected.contains(package.id) && _hasActiveZone(package))
        .map((package) => package.id)
        .toSet();
  }

  void _pruneEmptyZonePreviews() {
    final occupiedZones = <String>{};
    for (final package in _route) {
      final zone = package.physicalZone?.trim();
      if (zone != null && zone.isNotEmpty) occupiedZones.add(zone);
    }
    _visibleZonePackageCount.removeWhere(
      (zone, _) => !occupiedZones.contains(zone),
    );
  }

  Future<void> _clearSelected() async {
    if (_vehicleSwitching || _loadMutationInProgress) return;
    final ids = _selectedAssignedPackageIds(_route);
    if (ids.isEmpty) return;

    // Cancel drag selection and its periodic auto-scroll before persistence.
    _cancelDragSelection();
    _suppressNextTap = false;

    setState(() => _loadMutationInProgress = true);
    try {
      await widget.state.clearPhysicalZones(ids);
      if (!mounted) return;
      setState(() {
        // Do not carry a large preview count into a compartment after its
        // final assigned package has been removed.
        _pruneEmptyZonePreviews();
        if (multiSelect) {
          // Keep any selected packages that were already unassigned. Only
          // consume the selection that this removal operation actually changed.
          selectedIds.removeAll(ids);
        } else {
          selectedId = null;
        }
        _loadMutationInProgress = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadMutationInProgress = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    }
  }

  void _startDeliveries(){
    _cancelDragSelection();
    setState((){
      selectedId=null;
      selectedIds.clear();
      multiSelect=false;
      _dragSelecting=false;
    });
    Navigator.push(
      context,
      MaterialPageRoute(builder:(_)=>DeliveryScreen(state:widget.state)),
    );
  }

  @override Widget build(BuildContext context){
    final route=_route;
    // Build the filtered list once per frame. Recomputing this getter for every
    // lazy SliverList child would repeatedly scan all packages on large loads.
    final normalizedSearch=_normalizeSearchText(search.trim());
    final visibleRoute=route
        .where((p)=>!_hasActiveZone(p)&&_matchesSearch(p,normalizedSearch))
        .toList(growable:false);
    // Index every active compartment once per frame. This avoids scanning the
    // full route and normalizing every address separately for each vehicle zone.
    final zonePackageGroups = _groupPackagesByZone(route, normalizedSearch);
    final selected=_selected(route);
    final removableIds = _selectedAssignedPackageIds(route);
    final assigned=route.where(_hasActiveZone).length;
    final organized = route.isNotEmpty && route.every(_hasActiveZone);
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final compactViewport = MediaQuery.sizeOf(context).width < 360 ||
        MediaQuery.sizeOf(context).height < 600 ||
        textScale >= 1.2;
    return Scaffold(
      appBar:AppBar(title:Text(_isMoto?'Organizar a moto':'Organizar o carro'),actions:[
        if(_vehicleSwitching || _loadMutationInProgress)
          const Padding(
            padding:EdgeInsets.symmetric(horizontal:12),
            child:SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)),
          ),
        IconButton(tooltip:'Configurar compartimentos',onPressed:_vehicleSwitching||_loadMutationInProgress?null:_configureZones,icon:const Icon(Icons.tune)),
        IconButton(tooltip:'Selecionar vários',onPressed:_vehicleSwitching||_loadMutationInProgress?null:_toggleMulti,icon:Icon(multiSelect?Icons.close:Icons.library_add_check)),
        PopupMenuButton<VehicleType>(tooltip:'Veículo',enabled:!_vehicleSwitching&&!_loadMutationInProgress,onSelected:_switchVehicle,itemBuilder:(_)=>const [PopupMenuItem(value:VehicleType.car,child:Text('🚗 Carro')),PopupMenuItem(value:VehicleType.motorcycle,child:Text('🏍️ Moto'))]),
      ]),
      body:AbsorbPointer(absorbing:_vehicleSwitching||_loadMutationInProgress,child:route.isEmpty?const Center(child:Text('Nenhum pacote ativo na rota.')):Column(children:[
        Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            compactViewport ? 6 : 12,
            16,
            compactViewport ? 4 : 8,
          ),
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(compactViewport ? 10 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$assigned de ${route.length} pacotes posicionados',
                    style: compactViewport
                        ? Theme.of(context).textTheme.titleMedium
                        : Theme.of(context).textTheme.titleLarge,
                  ),
                  if (multiSelect)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '${selectedIds.length} pacote(s) selecionado(s)',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  SizedBox(height: compactViewport ? 4 : 6),
                  Text(
                    compactViewport
                        ? (multiSelect
                            ? 'Selecione pacotes e toque no compartimento.'
                            : selected == null
                                ? 'Escolha um pacote e depois o compartimento.'
                                : 'Toque no compartimento para guardar o pacote.')
                        : (multiSelect
                            ? 'Toque para marcar; mantenha pressionado e arraste para selecionar vários. Depois toque no compartimento para guardar todos.'
                            : (selected == null
                                ? (_isMoto
                                    ? 'Toque em um pacote e depois no baú, bolsa ou mochila.'
                                    : 'Toque em um pacote e depois na área do carro onde ele ficará.')
                                : 'Pacote ${selected.scanNumber.toString().padLeft(2, '0')} selecionado. Agora toque no compartimento do veículo.')),
                    maxLines: compactViewport ? 2 : null,
                    overflow: compactViewport ? TextOverflow.ellipsis : TextOverflow.visible,
                  ),
                  SizedBox(height: compactViewport ? 6 : 10),
                  LinearProgressIndicator(value: route.isEmpty ? 0 : assigned / route.length),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (event) {
              final packageId = _mountedPackageIdAt(event.position);
              if (multiSelect &&
                  !_dragSelecting &&
                  _selectionPointerId == null &&
                  packageId != null) {
                _selectionPointerId = event.pointer;
                _selectionPointerPackageId = packageId;
              }
            },
            onPointerMove: (event) {
              if (_selectionPointerId == event.pointer) {
                _selectionPointerMove(event.position);
              }
            },
            onPointerUp: (event) => _selectionPointerUp(event.pointer),
            onPointerCancel: (event) => _selectionPointerUp(event.pointer),
            child: CustomScrollView(
              key: _scrollViewportKey,
              controller: _scrollController,
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: search.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: 'Limpar busca',
                                    onPressed: () {
                                      _searchController.clear();
                                      _updateSearch('');
                                    },
                                    icon: const Icon(Icons.close),
                                  ),
                            hintText: 'Buscar pacote ou endereço',
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                          onChanged: _updateSearch,
                        ),
                        const SizedBox(height: 10),
                        if (search.trim().isNotEmpty && visibleRoute.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Column(
                              children: [
                                const Icon(Icons.search_off, size: 36),
                                const SizedBox(height: 8),
                                Text(
                                  route.any((package)=>_matchesSearch(package,normalizedSearch))
                                      ? 'O pacote encontrado já está posicionado em um compartimento.'
                                      : 'Nenhum pacote encontrado para essa busca.',
                                  textAlign: TextAlign.center,
                                ),
                                TextButton.icon(
                                  onPressed: () {
                                    _searchController.clear();
                                    _updateSearch('');
                                  },
                                  icon: const Icon(Icons.clear),
                                  label: const Text('Limpar busca'),
                                ),
                              ],
                            ),
                          ),
                        if (_isMoto)
                          _motoCard(context, route, selected, zonePackageGroups)
                        else
                          _carDiagram(context, route, selected, zonePackageGroups),
                        const SizedBox(height: 14),
                        SizedBox(
                          height: 48,
                          width: double.infinity,
                          child: removableIds.isNotEmpty
                              ? OutlinedButton.icon(
                                  onPressed: _clearSelected,
                                  icon: const Icon(Icons.remove_circle_outline),
                                  label: Text(
                                    removableIds.length > 1
                                        ? 'RETIRAR ${removableIds.length} PACOTES'
                                        : 'RETIRAR PACOTE SELECIONADO',
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Pacotes sem posição',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                            ),
                            if (multiSelect && visibleRoute.isNotEmpty)
                              TextButton(
                                onPressed: () => _toggleSelectAll(visibleRoute),
                                child: Text(
                                  _allVisiblePackagesSelected(visibleRoute)
                                      ? (search.trim().isEmpty
                                          ? 'Desmarcar lista'
                                          : 'Desmarcar resultados')
                                      : (search.trim().isEmpty
                                          ? 'Selecionar lista'
                                          : 'Selecionar resultados'),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final package = visibleRoute[index];
                        return _packageTile(
                          context,
                          package,
                          multiSelect
                              ? selectedIds.contains(package.id)
                              : selected?.id == package.id,
                        );
                      },
                      childCount: visibleRoute.length,
                    ),
                  ),
                ),
                if (assigned == route.length)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    sliver: SliverToBoxAdapter(
                      child: Text(
                        'Todos os pacotes estão posicionados. Confira a carga antes de sair.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        SafeArea(top:false,child:Padding(padding:const EdgeInsets.fromLTRB(16,8,16,16),child:SizedBox(width:double.infinity,child:FilledButton.icon(onPressed:organized?_startDeliveries:null,icon:const Icon(Icons.play_arrow),label:const Padding(padding:EdgeInsets.all(15),child:Text('INICIAR ENTREGAS')))))),
      ])),
    );
  }

  Map<String, _ZonePackageGroup> _groupPackagesByZone(
    List<DeliveryPackage> route,
    String normalizedSearch,
  ) {
    final groups = <String, _ZonePackageGroup>{
      for (final zone in widget.state.activePhysicalZones)
        zone: _ZonePackageGroup(),
    };
    for (final package in route) {
      final zone = _normalizedPhysicalZone(package);
      if (zone == null) continue;
      final group = groups[zone];
      if (group == null) continue;
      group.allPackages.add(package);
      if (_matchesSearch(package, normalizedSearch)) {
        group.matchingPackages.add(package);
      }
    }
    return groups;
  }

  Future<void> _configureZones() async {
    final defaults = _isMoto
        ? AppState.motorcyclePhysicalZones
        : AppState.carPhysicalZones;
    final selected = widget.state.activePhysicalZones.toSet();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          scrollable: true,
          title: Text(
            _isMoto ? 'Compartimentos da moto' : 'Compartimentos do carro',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Ative apenas os espaços que existem no seu veículo.'),
              const SizedBox(height: 8),
              for (final zone in defaults)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(zone),
                  value: selected.contains(zone),
                  onChanged: (value) => setDialogState(
                    () => value == true
                        ? selected.add(zone)
                        : selected.remove(zone),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () async {
                      final knownZones = <String>{
                        ...AppState.carPhysicalZones,
                        ...AppState.motorcyclePhysicalZones,
                      };
                      final affectedCount = widget.state.packages.where(
                        (package) {
                          if (package.status == DeliveryStatus.delivered) {
                            return false;
                          }
                          final zone = package.physicalZone?.trim();
                          return zone != null &&
                              knownZones.contains(zone) &&
                              !selected.contains(zone);
                        },
                      ).length;

                      if (affectedCount > 0) {
                        final packageMessage = affectedCount == 1
                            ? '1 pacote não entregue perderá sua posição atual.'
                            : '$affectedCount pacotes não entregues perderão suas posições atuais.';
                        final confirmed = await showDialog<bool>(
                          context: dialogContext,
                          builder: (confirmationContext) => AlertDialog(
                            title: const Text(
                              'Confirmar alteração dos compartimentos',
                            ),
                            content: Text(
                              '$packageMessage Os pacotes não serão excluídos; '
                              'ficarão sem compartimento e poderão ser '
                              'organizados novamente.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(
                                  confirmationContext,
                                  false,
                                ),
                                child: const Text('Voltar'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(
                                  confirmationContext,
                                  true,
                                ),
                                child: const Text('Desativar e continuar'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed != true || !dialogContext.mounted) {
                          return;
                        }
                      }

                      try {
                        await widget.state.setActivePhysicalZones(
                          selected.toList(),
                        );
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext);
                        }
                        if (mounted) {
                          setState(
                            () => _visibleZonePackageCount.removeWhere(
                              (zone, _) => !selected.contains(zone),
                            ),
                          );
                        }
                      } catch (error) {
                        if (dialogContext.mounted) {
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            SnackBar(content: Text('$error')),
                          );
                        }
                      }
                    },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _motoCard(
    BuildContext context,
    List<DeliveryPackage> route,
    DeliveryPackage? selected,
    Map<String, _ZonePackageGroup> zonePackageGroups,
  ){
    final zones=widget.state.activePhysicalZones;
    final leftSideZone=zones.contains('Bolsa lateral esquerda')?'Bolsa lateral esquerda':null;
    final rightSideZone=zones.contains('Bolsa lateral direita')?'Bolsa lateral direita':null;
    final rearZones=zones.where((z)=>z=='Baú traseiro'||z=='Mochila de entrega').toList();
    String label(String zone)=>switch(zone){
      'Bolsa lateral esquerda'=>'BOLSA ESQUERDA',
      'Bolsa lateral direita'=>'BOLSA DIREITA',
      'Baú traseiro'=>'BAÚ TRASEIRO',
      'Mochila de entrega'=>'MOCHILA DE ENTREGA',
      _=>zone.toUpperCase(),
    };
    Widget sideZone(String zone)=>Padding(
      padding:const EdgeInsets.symmetric(horizontal:3),
      child:_zone(
        context,
        zone,
        label(zone),
        zonePackageGroups[zone]!,
        selected,
        wide:true,
      ),
    );
    Widget rearZone(String zone)=>_zone(
      context,
      zone,
      label(zone),
      zonePackageGroups[zone]!,
      selected,
      wide:true,
    );

    return LayoutBuilder(
      builder:(context,constraints){
        // Side bags become narrow on 320–390 px Android phones when they flank
        // the motorcycle icon. Stack the icon above a two-column bag row on
        // compact screens (and whenever the user enlarges system text).
        final compact=constraints.maxWidth<380||
            MediaQuery.textScalerOf(context).scale(14)/14>=1.2;
        final motorcycleGraphic=Column(children:[
          Icon(Icons.two_wheeler,size:64,color:Theme.of(context).colorScheme.onSurfaceVariant),
          Text('MOTO',style:Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight:FontWeight.bold)),
        ]);

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
              if(compact)...[
                motorcycleGraphic,
                if(leftSideZone!=null||rightSideZone!=null)...[
                  const SizedBox(height:8),
                  Row(
                    crossAxisAlignment:CrossAxisAlignment.start,
                    children:[
                      // Keep both physical halves reserved even when one bag is
                      // disabled. Otherwise the remaining bag expands to the
                      // full row and appears centered instead of on its real side.
                      Expanded(
                        child:leftSideZone==null
                            ?const SizedBox.shrink()
                            :sideZone(leftSideZone),
                      ),
                      const SizedBox(width:8),
                      Expanded(
                        child:rightSideZone==null
                            ?const SizedBox.shrink()
                            :sideZone(rightSideZone),
                      ),
                    ],
                  ),
                ],
              ]else
                Row(
                  crossAxisAlignment:CrossAxisAlignment.center,
                  children:[
                    Expanded(
                      child:leftSideZone==null
                          ?const SizedBox.shrink()
                          :sideZone(leftSideZone),
                    ),
                    Expanded(flex:2,child:motorcycleGraphic),
                    Expanded(
                      child:rightSideZone==null
                          ?const SizedBox.shrink()
                          :sideZone(rightSideZone),
                    ),
                  ],
                ),
              if(rearZones.isNotEmpty)...[
                const SizedBox(height:10),
                const Text('TRASEIRA E BAGAGEM',style:TextStyle(fontWeight:FontWeight.w800,letterSpacing:1)),
                const SizedBox(height:8),
                if(rearZones.length==1)
                  rearZone(rearZones.first)
                else if(compact)
                  Row(
                    crossAxisAlignment:CrossAxisAlignment.start,
                    children:[
                      Expanded(child:rearZone(rearZones[0])),
                      const SizedBox(width:8),
                      Expanded(child:rearZone(rearZones[1])),
                    ],
                  )
                else
                  Wrap(
                    spacing:8,
                    runSpacing:8,
                    alignment:WrapAlignment.center,
                    children:[
                      for(final zone in rearZones)
                        SizedBox(width:145,child:rearZone(zone)),
                    ],
                  ),
              ],
              if(route.any(_hasActiveZone))
                Padding(
                  padding:const EdgeInsets.only(top:8),
                  child:Text(
                    'Cada pacote está identificado no compartimento correspondente.',
                    textAlign:TextAlign.center,
                    style:Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ]),
          ),
        );
      },
    );
  }

  Widget _carDiagram(
    BuildContext context,
    List<DeliveryPackage> route,
    DeliveryPackage? selected,
    Map<String, _ZonePackageGroup> zonePackageGroups,
  ){
    final zones=widget.state.activePhysicalZones;
    final hasFrontZones=zones.contains('Frente esquerda')||zones.contains('Frente direita');
    final hasRearZones=zones.contains('Traseira esquerda')||zones.contains('Traseira direita');
    final hasTrunk=zones.contains('Porta-malas');
    final colors=Theme.of(context).colorScheme;

    // Keep fixed left/right slots even when only one seat is enabled.
    // Otherwise the remaining compartment shifts to the left in the diagram.
    Widget zoneRow(String leftZone,String rightZone)=>Row(
      children:[
        Expanded(
          child:zones.contains(leftZone)
              ?_zone(
                  context,
                  leftZone,
                  _carZoneLabel(leftZone),
                  zonePackageGroups[leftZone]!,
                  selected,
                )
              :const SizedBox.shrink(),
        ),
        const SizedBox(width:8),
        Expanded(
          child:zones.contains(rightZone)
              ?_zone(
                  context,
                  rightZone,
                  _carZoneLabel(rightZone),
                  zonePackageGroups[rightZone]!,
                  selected,
                )
              :const SizedBox.shrink(),
        ),
      ],
    );

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
            if(hasFrontZones)...[
              const SizedBox(height:12),
              zoneRow('Frente esquerda','Frente direita'),
            ],
            if(hasRearZones)...[
              const SizedBox(height:8),
              zoneRow('Traseira esquerda','Traseira direita'),
            ],
            if(hasTrunk)...[
              const SizedBox(height:8),
              _zone(
                context,
                'Porta-malas',
                'PORTA-MALAS',
                zonePackageGroups['Porta-malas']!,
                selected,
                wide:true,
              ),
            ],
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

  Widget _zone(
    BuildContext context,
    String zone,
    String shortName,
    _ZonePackageGroup group,
    DeliveryPackage? selected, {
    bool wide = false,
  }) {
    final allPackages = group.allPackages;
    final packages = group.matchingPackages;
    final activeZone=multiSelect
        ?allPackages.any((package)=>selectedIds.contains(package.id))
        :selected!=null&&_isPackageInZone(selected, zone);
    final highlighted=selected!=null||selectedIds.isNotEmpty;
    final hasSearch=search.trim().isNotEmpty;
    final visibleCount = (_visibleZonePackageCount[zone] ?? _initialZonePackageCount)
        .clamp(0, packages.length)
        .toInt();
    final visiblePackages = packages.take(visibleCount).toList(growable: false);
    final remainingPackages = packages.length - visiblePackages.length;
    final nextBatch = remainingPackages < _zonePackagePageSize
        ? remainingPackages
        : _zonePackagePageSize;
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
            if(allPackages.isNotEmpty)Text(
              hasSearch?'${packages.length}/${allPackages.length}':'${allPackages.length}',
              style:const TextStyle(fontWeight:FontWeight.bold),
            ),
          ]),
          const SizedBox(height:6),
          if(packages.isEmpty)
            SizedBox(
              height:allPackages.isEmpty?72:40,
              child:Center(child:Text(
                allPackages.isEmpty?'Vazio':'Sem resultados',
                style:const TextStyle(fontSize:12),
              )),
            )
          else ...[
            Wrap(spacing:3,runSpacing:3,children:[
              for(final p in visiblePackages)
                InputChip(
                  visualDensity:VisualDensity.compact,
                  padding:EdgeInsets.zero,
                  selected:multiSelect?selectedIds.contains(p.id):selected?.id==p.id,
                  onSelected:(_)=>_togglePackage(p.id),
                  label:Text('P${p.scanNumber.toString().padLeft(2,'0')}'),
                ),
            ]),
            if (packages.length > _initialZonePackageCount)
              Wrap(
                spacing: 4,
                runSpacing: 0,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (visiblePackages.length > _initialZonePackageCount)
                    TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: Size.zero,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () => setState(
                        () => _visibleZonePackageCount.remove(zone),
                      ),
                      child: const Text('Mostrar menos'),
                    ),
                  if (remainingPackages > 0)
                    TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: Size.zero,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () => setState(() {
                        _visibleZonePackageCount[zone] =
                            (visiblePackages.length + _zonePackagePageSize)
                                .clamp(_initialZonePackageCount, packages.length)
                                .toInt();
                      }),
                      child: Text('Ver mais $nextBatch'),
                    ),
                  if (remainingPackages > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        '$remainingPackages restantes',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                ],
              ),
          ],
        ]),
      ),
    );
  }

  Widget _packageTile(BuildContext context, DeliveryPackage p, bool selected) {
    final zone = p.physicalZone?.trim();
    final address = p.address.formatted.isEmpty ? p.address.raw : p.address.formatted;
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPressStart: multiSelect
          ? (details) => _selectionPointerDown(details.globalPosition, p.id)
          : null,
      // Pointer movement is handled once by the ancestor Listener so long
      // drags do not run the same hit-test twice for every movement event.
      child: _TrackedPackageTile(
        packageId: p.id,
        onChanged: _registerTileBox,
        child: Card(
          margin: const EdgeInsets.only(bottom: 6),
        color: selected ? cs.inverseSurface : null,
        child: ListTile(
          selected: selected,
          selectedColor: selected ? cs.onInverseSurface : null,
          leading: CircleAvatar(
            radius: 24,
            backgroundColor: selected ? cs.onInverseSurface : cs.primaryContainer,
            foregroundColor: selected ? cs.inverseSurface : null,
            child: Text(
              p.scanNumber.toString().padLeft(2, '0'),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          title: Text(p.label, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(
            _isMoto
                ? address
                : (_hasActiveZone(p) ? '$zone\n$address' : 'Sem posição no carro\n$address'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: _isMoto
              ? null
              : (_hasActiveZone(p) ? const Chip(label: Text('OK')) : const Chip(label: Text('Falta'))),
          onTap: () => _togglePackage(p.id),
        ),
        ),
      ),
    );
  }
}



class _ZonePackageGroup {
  final List<DeliveryPackage> allPackages = <DeliveryPackage>[];
  final List<DeliveryPackage> matchingPackages = <DeliveryPackage>[];
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


class _TrackedPackageTile extends SingleChildRenderObjectWidget {
  const _TrackedPackageTile({
    required this.packageId,
    required this.onChanged,
    required super.child,
  });

  final String packageId;
  final void Function(String id, RenderBox box, bool attached) onChanged;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _TrackedPackageTileRenderBox(packageId, onChanged);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _TrackedPackageTileRenderBox renderObject,
  ) {
    renderObject.updateRegistration(packageId, onChanged);
  }
}

class _TrackedPackageTileRenderBox extends RenderProxyBox {
  _TrackedPackageTileRenderBox(this.packageId, this.onChanged);

  String packageId;
  void Function(String id, RenderBox box, bool attached) onChanged;

  void updateRegistration(
    String nextPackageId,
    void Function(String id, RenderBox box, bool attached) nextOnChanged,
  ) {
    if (packageId != nextPackageId) {
      onChanged(packageId, this, false);
      packageId = nextPackageId;
    }
    onChanged = nextOnChanged;
    if (attached) onChanged(packageId, this, true);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    onChanged(packageId, this, true);
  }

  @override
  void detach() {
    onChanged(packageId, this, false);
    super.detach();
  }
}
