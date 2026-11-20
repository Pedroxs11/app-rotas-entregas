import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'domain/models.dart';
import 'services/address_parser.dart';import 'services/package_service.dart';import 'services/local_store.dart';import 'services/package_store.dart';import 'services/sqlite_package_store.dart';import 'services/migrating_package_store.dart';import 'services/nominatim_geocoding_service.dart';import 'services/route_engine.dart';import 'services/cep_service.dart';import 'services/bounded_async.dart';
enum VehicleType { car, motorcycle }

class AppState extends ChangeNotifier {
 VehicleType vehicleType=VehicleType.car;
 static const carPhysicalZones=<String>['Frente esquerda','Frente direita','Traseira esquerda','Traseira direita','Porta-malas'];
 static const motorcyclePhysicalZones=<String>['Baú traseiro','Bolsa lateral esquerda','Bolsa lateral direita','Mochila de entrega'];
 List<String> activePhysicalZones=[...carPhysicalZones];
 Future<void> _packageMutationTail=Future<void>.value();
 Future<T> _serializePackageMutation<T>(Future<T> Function() operation){
  final previous=_packageMutationTail;
  final release=Completer<void>();
  _packageMutationTail=release.future;
  return ()async{
   await previous;
   try{
    return await operation();
   }finally{
    release.complete();
   }
  }();
 }
 String get _zonesPreferenceKey=>vehicleType==VehicleType.car?'load_zones_car':'load_zones_motorcycle';
 List<String> _restorePhysicalZones(List<String>? savedZones,List<String> defaults){
  if(savedZones==null)return <String>[...defaults];
  // Preferences can outlive app versions or be edited externally. Normalize
  // whitespace before filtering so a valid compartment is not discarded.
  final normalizedZones=savedZones
      .map((zone)=>zone.trim())
      .where((zone)=>zone.isNotEmpty)
      .toSet();
  final restored=defaults.where(normalizedZones.contains).toList();
  return restored.isEmpty?<String>[...defaults]:restored;
 }
 Future<void> _restorePreferenceValue(SharedPreferences prefs,String key,Object? value)async{
  await prefs.remove(key);
  if(value==null)return;
  if(value is String){
   await prefs.setString(key,value);
  }else if(value is bool){
   await prefs.setBool(key,value);
  }else if(value is int){
   await prefs.setInt(key,value);
  }else if(value is double){
   await prefs.setDouble(key,value);
  }else if(value is List&&value.every((entry)=>entry is String)){
   await prefs.setStringList(key,value.cast<String>());
  }
 }
 Future<void> _loadVehicleSettings()async{
  try{
   final prefs=await SharedPreferences.getInstance();
   var repairVehiclePreference=false;
   try{
    final savedVehicleType=prefs.getString('load_vehicle_type');
    vehicleType=savedVehicleType=='motorcycle'?VehicleType.motorcycle:VehicleType.car;
    repairVehiclePreference=savedVehicleType!=null&&savedVehicleType!='car'&&savedVehicleType!='motorcycle';
   }catch(e){
    vehicleType=VehicleType.car;
    repairVehiclePreference=true;
    debugPrint('Could not read saved vehicle type: $e');
   }
   if(repairVehiclePreference){
    await prefs.setString('load_vehicle_type',vehicleType.name);
   }
   final defaults=vehicleType==VehicleType.car?carPhysicalZones:motorcyclePhysicalZones;
   List<String>? savedZones;
   var invalidPreferenceType=false;
   try{
    savedZones=prefs.getStringList(_zonesPreferenceKey);
   }catch(e){
    invalidPreferenceType=true;
    debugPrint('Could not read saved vehicle compartments: $e');
   }
   // Restore the canonical physical order and repair stale, duplicate,
   // unknown, empty, or incorrectly typed preference values.
   activePhysicalZones=_restorePhysicalZones(savedZones,defaults);
   if(invalidPreferenceType||(savedZones!=null&&!listEquals(savedZones,activePhysicalZones))){
    await prefs.setStringList(_zonesPreferenceKey,activePhysicalZones);
   }
  }catch(e){
   activePhysicalZones=[...(vehicleType==VehicleType.car?carPhysicalZones:motorcyclePhysicalZones)];
   debugPrint('Could not load vehicle settings: $e');
  }
 }
 Future<void> setVehicleType(VehicleType value) {
  return _serializePackageMutation(()async{
  if(vehicleType==value)return;
  final previousVehicleType=vehicleType;
  final previousZones=[...activePhysicalZones];
  final previousPackages=packages;
  final prefs=await SharedPreferences.getInstance();
  const vehiclePreferenceKey='load_vehicle_type';
  final targetZonesKey=value==VehicleType.car?'load_zones_car':'load_zones_motorcycle';
  final previousVehiclePreference=prefs.get(vehiclePreferenceKey);
  final previousTargetZonesPreference=prefs.get(targetZonesKey);
  final defaults=value==VehicleType.car?carPhysicalZones:motorcyclePhysicalZones;
  List<String>? savedZones;
  try{
   savedZones=prefs.getStringList(targetZonesKey);
  }catch(e){
   // A preference saved with the wrong type must not block switching vehicles.
   debugPrint('Could not read saved vehicle compartments: $e');
  }
  final nextZones=_restorePhysicalZones(savedZones,defaults);
  final nextPackages=packages.map((p)=>p.status==DeliveryStatus.delivered?p:p.copyWith(clearPhysicalZone:true)).toList();
  final packagesChanged=packages.any((p)=>p.status!=DeliveryStatus.delivered&&p.physicalZone!=null);
  try{
   if(!await prefs.setString(vehiclePreferenceKey,value.name)){
    throw StateError('Could not save selected vehicle.');
   }
   if(!await prefs.setStringList(targetZonesKey,nextZones)){
    throw StateError('Could not save vehicle compartments.');
   }
   if(packagesChanged){
    await store.save(nextPackages,routeOptimized:routeOptimized);
   }
   vehicleType=value;
   activePhysicalZones=nextZones;
   if(packagesChanged)packages=nextPackages;
   notifyListeners();
  }catch(error){
   vehicleType=previousVehicleType;
   activePhysicalZones=previousZones;
   packages=previousPackages;
   try{
    await _restorePreferenceValue(prefs,vehiclePreferenceKey,previousVehiclePreference);
   }catch(rollbackError){
    debugPrint('Could not roll back vehicle preference: $rollbackError');
   }
   try{
    await _restorePreferenceValue(prefs,targetZonesKey,previousTargetZonesPreference);
   }catch(rollbackError){
    debugPrint('Could not roll back compartment preference: $rollbackError');
   }
   notifyListeners();
   rethrow;
  }
 
  });
 }
 Future<void> setActivePhysicalZones(List<String> zones) {
  return _serializePackageMutation(()async{
  final defaults=vehicleType==VehicleType.car?carPhysicalZones:motorcyclePhysicalZones;
  // Accept values restored from forms or integrations with harmless whitespace.
  final requested=zones.map((zone)=>zone.trim()).where((zone)=>zone.isNotEmpty).toSet();
  // The visual diagram uses this order to preserve the real left/right sides.
  final cleaned=defaults.where(requested.contains).toList();
  if(cleaned.isEmpty)throw ArgumentError('Ative pelo menos um compartimento.');
  final zonesUnchanged=cleaned.length==activePhysicalZones.length&&cleaned.every(activePhysicalZones.contains);
  final knownZones=<String>{...carPhysicalZones,...motorcyclePhysicalZones};
  final next=[...packages];
  var packagesChanged=false;
  for(var i=0;i<next.length;i++){
   final p=next[i];
   final rawZone=p.physicalZone;
   if(p.status==DeliveryStatus.delivered||rawZone==null)continue;
   final normalizedZone=rawZone.trim();
   final belongsToDisabledZone=knownZones.contains(normalizedZone)&&
       !cleaned.contains(normalizedZone);
   if(normalizedZone.isEmpty||belongsToDisabledZone){
    next[i]=p.copyWith(clearPhysicalZone:true);
    packagesChanged=true;
   }else if(normalizedZone!=rawZone){
    next[i]=p.copyWith(physicalZone:normalizedZone);
    packagesChanged=true;
   }
  }
  if(zonesUnchanged&&!packagesChanged)return;
  final previousZones=[...activePhysicalZones];
  final previousPackages=packages;
  final prefs=await SharedPreferences.getInstance();
  final previousPreference=prefs.get(_zonesPreferenceKey);
  try{
   if(!await prefs.setStringList(_zonesPreferenceKey,cleaned)){
    throw StateError('Could not save vehicle compartments.');
   }
   if(packagesChanged){
    await store.save(next,routeOptimized:routeOptimized);
   }
   activePhysicalZones=cleaned;
   if(packagesChanged)packages=next;
   notifyListeners();
  }catch(error){
   activePhysicalZones=previousZones;
   packages=previousPackages;
   try{
    await _restorePreferenceValue(prefs,_zonesPreferenceKey,previousPreference);
   }catch(rollbackError){
    debugPrint('Could not roll back compartment preference: $rollbackError');
   }
   notifyListeners();
   rethrow;
  }
 
  });
 }
 final PackageStore store;final geocoder=NominatimGeocodingService();final routeEngine=RouteEngine();final CepService cepService=ViaCepService();late final PackageService packageService=PackageService(AddressParser());List<DeliveryPackage> packages=[];bool loading=true,locating=false,routeOptimized=false;String? startupError;int lastLocateAttempted=0,lastLocateSucceeded=0,lastLocateFailed=0;
 AppState({PackageStore? store}):store=store??MigratingPackageStore(primary:SqlitePackageStore(),legacy:LocalStore());
 int get reviewCount=>packages.where((p)=>p.status!=DeliveryStatus.delivered&&p.address.validation!=ValidationStatus.confirmed).length;int get deliveredCount=>packages.where((p)=>p.status==DeliveryStatus.delivered).length;int get locatedCount=>packages.where((p)=>p.status!=DeliveryStatus.delivered&&p.address.latitude!=null&&p.address.longitude!=null).length;int get retryCount=>packages.where((p)=>p.status==DeliveryStatus.absent||p.status==DeliveryStatus.addressProblem||p.status==DeliveryStatus.skipped).length;
 bool _reconcileLoadedPhysicalZones(){
  var changed=false;
  final allowedZones=activePhysicalZones.toSet();
  final knownZones=<String>{
   ...carPhysicalZones,
   ...motorcyclePhysicalZones,
  };
  packages=packages.map((p){
   final rawZone=p.physicalZone;
   if(p.status==DeliveryStatus.delivered||rawZone==null)return p;
   final normalizedZone=rawZone.trim();
   if(normalizedZone.isEmpty){
    changed=true;
    return p.copyWith(clearPhysicalZone:true);
   }
   final belongsToOtherVehicle=knownZones.contains(normalizedZone)&&
       !allowedZones.contains(normalizedZone);
   if(belongsToOtherVehicle){
    changed=true;
    return p.copyWith(clearPhysicalZone:true);
   }
   if(normalizedZone!=rawZone){
    changed=true;
    return p.copyWith(physicalZone:normalizedZone);
   }
   return p;
  }).toList();
  return changed;
 }
 Future<void> init()async{
  try{
   await _loadVehicleSettings();
   packages=await store.load();
   routeOptimized=await store.loadRouteOptimized();
   if(_reconcileLoadedPhysicalZones()){
    await store.save(packages,routeOptimized:routeOptimized);
   }
   startupError=null;
  }catch(e,st){
   startupError=e.toString();
   debugPrint('Storage startup failed: $e\n$st');
  }finally{
   loading=false;
   notifyListeners();
  }
 }
 Future<void> addFromText(String text,{String? trackingCode})async{
  // Parse and enrich outside the mutation queue; re-parse against the latest
  // package list inside it so overlapping scans cannot reuse scan numbers or
  // overwrite a compartment assignment made while CEP lookup was running.
  final parsed=packageService.fromOcr(text,[...packages],trackingCode:trackingCode);
  final enrichedAddress=await _enrichCep(parsed.address);
  DeliveryPackage? added;
  await _serializePackageMutation(()async{
   final current=packageService.fromOcr(text,packages,trackingCode:trackingCode)
       .copyWith(address:enrichedAddress);
   await _persistPackageMutation([...packages,current],nextRouteOptimized:false);
   added=current;
  });
  if(added!.address.validation==ValidationStatus.confirmed)await locateConfirmed();
 }
 Future<int> addManyFromText(String text)async{
  final lines=text.split(RegExp(r'\r?\n')).map((e)=>e.trim()).where((e)=>e.isNotEmpty).toList();
  final candidateLines=<String>[];
  final candidateAddresses=<AddressData>[];
  final provisional=[...packages];
  for(final line in lines){
   try{
    final parsed=packageService.fromOcr(line,provisional);
    provisional.add(parsed);
    candidateLines.add(line);
    candidateAddresses.add(parsed.address);
   }catch(_){ }
  }
  if(candidateLines.isEmpty)return 0;
  final enriched=await mapBounded(candidateAddresses,(address)=>_enrichCep(address),concurrency:4);
  var addedCount=0;
  await _serializePackageMutation(()async{
   final next=[...packages];
   for(var i=0;i<candidateLines.length;i++){
    try{
     final parsed=packageService.fromOcr(candidateLines[i],next)
         .copyWith(address:enriched[i]);
     next.add(parsed);
     addedCount++;
    }catch(_){ }
   }
   if(addedCount>0){
    // A new stop invalidates optimization, but must not erase positions that
    // the driver has already assigned to the other packages.
    await _persistPackageMutation(next,nextRouteOptimized:false);
   }
  });
  if(addedCount>0&&packages.any((p)=>p.status!=DeliveryStatus.delivered&&
      p.address.validation==ValidationStatus.confirmed&&
      (p.address.latitude==null||p.address.longitude==null))){
   await locateConfirmed();
  }
  return addedCount;
 }
 Future<AddressData> _enrichCep(AddressData a)async{if(a.cep==null||a.cep!.replaceAll(RegExp(r'\D'),'').length!=8)return a;try{final c=await cepService.lookup(a.cep!);if(c==null)return a;final number=a.number?.trim();final hasNumber=number?.isNotEmpty==true;return AddressData(raw:a.raw,street:c.street.isNotEmpty?c.street:a.street,number:number,complement:a.complement,neighborhood:c.neighborhood.isNotEmpty?c.neighborhood:a.neighborhood,city:c.city.isNotEmpty?c.city:a.city,state:c.state.isNotEmpty?c.state:a.state,cep:c.cep,latitude:a.latitude,longitude:a.longitude,confidence:hasNumber?1.0:.70,validation:hasNumber?ValidationStatus.confirmed:ValidationStatus.needsReview);}catch(_){return a;}}
 Future<void> addStructured(AddressData address)async{
  await _serializePackageMutation(()async{
   final parsed=packageService.fromOcr(address.raw,packages).copyWith(address:address);
   await _persistPackageMutation([...packages,parsed],nextRouteOptimized:false);
  });
  if(address.validation==ValidationStatus.confirmed)await locateConfirmed();
 }
 Future<void> updateAddress(int index,AddressData address) async {
  await _serializePackageMutation(() async {
   final p=packages[index];
   final previousPackages=packages;
   final previousOptimized=routeOptimized;
   final next=[...packages]..[index]=p.copyWith(address:address);
   packages=_clearLoadLabels(next);
   routeOptimized=false;
   try{
    await _persist();
   }catch(error){
    packages=previousPackages;
    routeOptimized=previousOptimized;
    notifyListeners();
    rethrow;
   }
  });
  // Network geocoding must not hold the package-mutation queue while it runs.
  if(address.validation==ValidationStatus.confirmed)await locateConfirmed();
 }
 Future<void> update(int index,DeliveryPackage value) {
  return _serializePackageMutation(() async {
   var targetIndex=index;
   if(targetIndex<0||targetIndex>=packages.length||packages[targetIndex].id!=value.id){
    targetIndex=packages.indexWhere((p)=>p.id==value.id);
   }
   if(targetIndex<0)throw StateError('Pacote não encontrado.');
   final current=packages[targetIndex];
   // Generic delivery updates must not overwrite a compartment changed by a
   // concurrent organizer action. Physical positions are changed only through
   // setPhysicalZone(s), so the latest committed position always wins.
   value=value.copyWith(
    physicalZone:current.physicalZone,
    clearPhysicalZone:current.physicalZone==null,
   );
   final rawZone=value.physicalZone;
   if(value.status!=DeliveryStatus.delivered&&rawZone!=null){
    final normalizedZone=rawZone.trim();
    final knownZones=<String>{...carPhysicalZones,...motorcyclePhysicalZones};
    final belongsToDisabledZone=knownZones.contains(normalizedZone)&&
        !activePhysicalZones.contains(normalizedZone);
    if(normalizedZone.isEmpty||belongsToDisabledZone){
     value=value.copyWith(clearPhysicalZone:true);
    }else if(normalizedZone!=rawZone){
     value=value.copyWith(physicalZone:normalizedZone);
    }
   }
   final next=[...packages]..[targetIndex]=value;
   await _persistPackageMutation(next);
  });
 }
 Future<void> removePackage(String packageId)async=>removePackages({packageId});
 Future<void> removePackages(Set<String> packageIds) {
  return _serializePackageMutation(() async {if(packageIds.isEmpty)return;final next=packages.where((p)=>!packageIds.contains(p.id)).toList();if(next.length==packages.length)return;packages=next;routeOptimized=false;await _persist();
  });
 }
 Future<void> reorder(int oldIndex,int newIndex) {
  return _serializePackageMutation(() async {if(newIndex>oldIndex)newIndex--;if(newIndex==oldIndex)return;final x=[...packages];final p=x.removeAt(oldIndex);x.insert(newIndex,p);packages=_clearLoadLabels(x);routeOptimized=false;await _persist();
  });
 }
 bool _sameAddress(AddressData left,AddressData right)=>
      left.raw==right.raw&&left.street==right.street&&left.number==right.number&&
      left.complement==right.complement&&left.neighborhood==right.neighborhood&&
      left.city==right.city&&left.state==right.state&&left.cep==right.cep&&
      left.latitude==right.latitude&&left.longitude==right.longitude&&
      left.confidence==right.confidence&&left.validation==right.validation;
 bool _locateRequestedAgain=false;
 Future<void> locateConfirmed()async{
  if(locating){
   _locateRequestedAgain=true;
   return;
  }
  final candidates=packages.where((p)=>p.status!=DeliveryStatus.delivered&&
      p.address.validation==ValidationStatus.confirmed&&
      (p.address.latitude==null||p.address.longitude==null)).toList();
  lastLocateAttempted=candidates.length;
  lastLocateSucceeded=0;
  lastLocateFailed=0;
  if(candidates.isEmpty){notifyListeners();return;}
  locating=true;
  notifyListeners();
  final locatedById=<String,AddressData>{};
  try{
   for(final candidate in candidates){
    try{
     final located=await geocoder.locate(candidate.address);
     if(located.latitude!=null&&located.longitude!=null){
      locatedById[candidate.id]=located;
     }
    }catch(error){
     debugPrint('Could not locate package ${candidate.id}: $error');
    }
   }
   var applied=0;
   if(locatedById.isNotEmpty){
    await _serializePackageMutation(()async{
     final next=[...packages];
     for(final candidate in candidates){
      final result=locatedById[candidate.id];
      if(result==null)continue;
      final index=next.indexWhere((p)=>p.id==candidate.id);
      if(index<0)continue;
      final current=next[index];
      // Do not revive a delivered/removed package or overwrite an address
      // edited while the network geocoding request was in flight.
      if(current.status==DeliveryStatus.delivered||
         !_sameAddress(current.address,candidate.address)){
        continue;
       }
      final original=current.address;
      next[index]=current.copyWith(address:AddressData(
       raw:original.raw,
       street:original.street,
       number:original.number,
       complement:original.complement,
       neighborhood:original.neighborhood,
       city:original.city,
       state:original.state,
       cep:original.cep,
       latitude:result.latitude??original.latitude,
       longitude:result.longitude??original.longitude,
       confidence:original.confidence,
       validation:original.validation,
      ));
      applied++;
     }
     if(applied>0)await _persistPackageMutation(next);
    });
   }
   lastLocateSucceeded=applied;
   lastLocateFailed=lastLocateAttempted-applied;
  }finally{
   locating=false;
   notifyListeners();
   if(_locateRequestedAgain){
    _locateRequestedAgain=false;
    await locateConfirmed();
   }
  }
 }
 Future<void> optimizeFrom(double lat,double lng) {
  return _serializePackageMutation(() async {final activeStatuses={DeliveryStatus.pending,DeliveryStatus.current,DeliveryStatus.absent,DeliveryStatus.addressProblem};final finished=packages.where((p)=>!activeStatuses.contains(p.status)).toList();final active=packages.where((p)=>activeStatuses.contains(p.status)).toList();packages=[...finished,..._optimize(active,lat,lng)];routeOptimized=true;await _persist();
  });
 }
 List<DeliveryPackage> _optimize(List<DeliveryPackage> active,double lat,double lng){final pinned=<int,DeliveryPackage>{};final free=<DeliveryPackage>[];for(var i=0;i<active.length;i++){if(active[i].pinned){pinned[i]=active[i];}else{free.add(active[i]);}}final optimized=routeEngine.optimize(free,startLat:lat,startLng:lng);for(final e in pinned.entries){final insertAt=e.key<0?0:(e.key>optimized.length?optimized.length:e.key);optimized.insert(insertAt,e.value);}return optimized;}
 Future<int> prepareRetryRoute(double lat,double lng,{bool includeAddressProblems=false,bool includeSkipped=false}) {
  return _serializePackageMutation(() async {
   final retry=packages.where((p)=>p.status==DeliveryStatus.absent||(includeAddressProblems&&p.status==DeliveryStatus.addressProblem)||(includeSkipped&&p.status==DeliveryStatus.skipped)).toList();
   if(retry.isEmpty)return 0;
   final ids=retry.map((p)=>p.id).toSet();
   final reset=retry.map((p)=>p.copyWith(status:DeliveryStatus.pending,clearCompletedAt:true)).toList();
   final optimized=_optimize(reset,lat,lng);
   final untouched=packages.where((p)=>!ids.contains(p.id)).toList();
   packages=_clearLoadLabels([...untouched,...optimized]);
   routeOptimized=true;
   await _persist();
   return optimized.length;
  });
 }
 bool _isPhysicalLoadActive(DeliveryStatus status)=>status==DeliveryStatus.pending||status==DeliveryStatus.current||status==DeliveryStatus.absent||status==DeliveryStatus.addressProblem;
 void _validatePhysicalPackageIds(Set<String> packageIds){final byId={for(final p in packages)p.id:p};final missing=packageIds.where((id)=>!byId.containsKey(id)).toList();if(missing.isNotEmpty)throw StateError('Pacote(s) não encontrado(s): ${missing.join(', ')}');final inactive=packageIds.where((id)=>!_isPhysicalLoadActive(byId[id]!.status)).toList();if(inactive.isNotEmpty)throw StateError('Pacote fora da rota ativa não pode ser reorganizado: ${inactive.join(', ')}');}
 Future<void> setPhysicalZones(Set<String> packageIds,String zone){
  return _serializePackageMutation(()async{
   if(!routeOptimized)throw StateError('Otimize a rota antes de organizar a carga.');
   final normalizedZone=zone.trim();
   if(!activePhysicalZones.contains(normalizedZone))throw ArgumentError.value(zone,'zone','posição física inválida');
   if(packageIds.isEmpty)return;
   _validatePhysicalPackageIds(packageIds);
   final current={for(final p in packages)p.id:p};
   if(packageIds.every((id)=>current[id]!.physicalZone==normalizedZone))return;
   final next=[...packages];
   for(var i=0;i<next.length;i++){
    final p=next[i];
    if(packageIds.contains(p.id))next[i]=p.copyWith(physicalZone:normalizedZone);
   }
   await _persistPackageMutation(next);
  });
 }
 Future<void> clearPhysicalZones(Set<String> packageIds){
  return _serializePackageMutation(()async{
   if(!routeOptimized)throw StateError('Otimize a rota antes de organizar a carga.');
   if(packageIds.isEmpty)return;
   _validatePhysicalPackageIds(packageIds);
   final current={for(final p in packages)p.id:p};
   if(packageIds.every((id)=>current[id]!.physicalZone==null||current[id]!.physicalZone!.isEmpty))return;
   final next=[...packages];
   for(var i=0;i<next.length;i++){
    final p=next[i];
    if(packageIds.contains(p.id))next[i]=p.copyWith(clearPhysicalZone:true);
   }
   await _persistPackageMutation(next);
  });
 }
 Future<void> setPhysicalZone(String packageId,String? zone){
  return _serializePackageMutation(()async{
   if(!routeOptimized)throw StateError('Otimize a rota antes de organizar a carga.');
   final trimmedZone=zone?.trim();
   final normalizedZone=trimmedZone==null||trimmedZone.isEmpty?null:trimmedZone;
   if(normalizedZone!=null&&!activePhysicalZones.contains(normalizedZone))throw ArgumentError.value(zone,'zone','posição física inválida');
   final index=packages.indexWhere((p)=>p.id==packageId);
   if(index<0)throw StateError('Pacote não encontrado.');
   final p=packages[index];
   if(!_isPhysicalLoadActive(p.status))throw StateError('Pacote fora da rota ativa não pode ser reorganizado.');
   if(p.physicalZone==normalizedZone)return;
   final next=[...packages]..[index]=p.copyWith(physicalZone:normalizedZone,clearPhysicalZone:normalizedZone==null);
   await _persistPackageMutation(next);
  });
 }
 List<DeliveryPackage> _clearLoadLabels(List<DeliveryPackage> source)=>source.map((p)=>p.status==DeliveryStatus.delivered?p:p.copyWith(clearPhysicalZone:true)).toList();
 Future<void> clear() {
  return _serializePackageMutation(() async {
   final previousPackages=packages;
   final previousOptimized=routeOptimized;
   packages=[];
   routeOptimized=false;
   try{
    await store.clear();
    lastLocateAttempted=lastLocateSucceeded=lastLocateFailed=0;
    notifyListeners();
   }catch(error){
    packages=previousPackages;
    routeOptimized=previousOptimized;
    notifyListeners();
    rethrow;
   }
  });
 }
 Future<void> _persist()async{await store.save(packages,routeOptimized:routeOptimized);notifyListeners();}
 Future<void> _persistPackageMutation(List<DeliveryPackage> next,{bool? nextRouteOptimized})async{
  final previousPackages=packages;
  final previousOptimized=routeOptimized;
  packages=next;
  if(nextRouteOptimized!=null)routeOptimized=nextRouteOptimized;
  try{
   await _persist();
  }catch(_){
   packages=previousPackages;
   routeOptimized=previousOptimized;
   notifyListeners();
   rethrow;
  }
 }
}