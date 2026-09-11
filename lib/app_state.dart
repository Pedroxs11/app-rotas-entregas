import 'package:flutter/foundation.dart';
import 'domain/models.dart';
import 'services/address_parser.dart';
import 'services/package_service.dart';
import 'services/local_store.dart';
import 'services/nominatim_geocoding_service.dart';
import 'services/route_engine.dart';

class AppState extends ChangeNotifier {
  final store=LocalStore();final geocoder=NominatimGeocodingService();final routeEngine=RouteEngine();late final PackageService packageService=PackageService(AddressParser());
  List<DeliveryPackage> packages=[];bool loading=true,locating=false,routeOptimized=false;
  int get reviewCount=>packages.where((p)=>p.status!=DeliveryStatus.delivered&&p.address.validation!=ValidationStatus.confirmed).length;
  int get deliveredCount=>packages.where((p)=>p.status==DeliveryStatus.delivered).length;
  int get locatedCount=>packages.where((p)=>p.status!=DeliveryStatus.delivered&&p.address.latitude!=null).length;
  int get retryCount=>packages.where((p)=>p.status==DeliveryStatus.absent||p.status==DeliveryStatus.addressProblem).length;
  Future<void> init()async{packages=await store.load();loading=false;notifyListeners();}
  Future<void> addFromText(String text,{String? trackingCode})async{packages=[...packages,packageService.fromOcr(text,packages,trackingCode:trackingCode)];routeOptimized=false;await _persist();}
  Future<int> addManyFromText(String text)async{final lines=text.split(RegExp(r'\r?\n')).map((e)=>e.trim()).where((e)=>e.isNotEmpty).toList();var added=0;for(final line in lines){try{packages=[...packages,packageService.fromOcr(line,packages)];added++;}catch(_){}}routeOptimized=false;await _persist();return added;}
  Future<void> addStructured(AddressData address)async{final p=packageService.fromOcr(address.raw,packages);packages=[...packages,p.copyWith(address:address)];routeOptimized=false;await _persist();if(address.validation==ValidationStatus.confirmed)await locateConfirmed();}
  Future<void> updateAddress(int index,AddressData address)async{final p=packages[index];packages=[...packages]..[index]=p.copyWith(address:address);routeOptimized=false;await _persist();if(address.validation==ValidationStatus.confirmed)await locateConfirmed();}
  Future<void> update(int index,DeliveryPackage value)async{packages=[...packages]..[index]=value;await _persist();}
  Future<void> reorder(int oldIndex,int newIndex)async{final x=[...packages];if(newIndex>oldIndex)newIndex--;final p=x.removeAt(oldIndex);x.insert(newIndex,p);packages=x;routeOptimized=false;await _persist();}
  Future<void> locateConfirmed()async{if(locating)return;locating=true;notifyListeners();final out=[...packages];for(var i=0;i<out.length;i++){final p=out[i];if(p.status==DeliveryStatus.delivered||p.address.validation!=ValidationStatus.confirmed||p.address.latitude!=null)continue;try{final a=await geocoder.locate(p.address);out[i]=p.copyWith(address:a);}catch(_){}}packages=out;locating=false;await _persist();}
  Future<void> optimizeFrom(double lat,double lng)async{final finished=packages.where((p)=>p.status!=DeliveryStatus.pending&&p.status!=DeliveryStatus.current&&p.status!=DeliveryStatus.absent&&p.status!=DeliveryStatus.addressProblem).toList();final active=packages.where((p)=>p.status==DeliveryStatus.pending||p.status==DeliveryStatus.current||p.status==DeliveryStatus.absent||p.status==DeliveryStatus.addressProblem).toList();packages=[...finished,..._optimize(active,lat,lng)];routeOptimized=true;await _persist();}
  List<DeliveryPackage> _optimize(List<DeliveryPackage> active,double lat,double lng){final pinned=<int,DeliveryPackage>{};final free=<DeliveryPackage>[];for(var i=0;i<active.length;i++){if(active[i].pinned){pinned[i]=active[i];}else{free.add(active[i]);}}final optimized=routeEngine.optimize(free,startLat:lat,startLng:lng);for(final e in pinned.entries){optimized.insert(e.key.clamp(0,optimized.length),e.value);}return optimized;}
  Future<int> prepareRetryRoute(double lat,double lng,{bool includeAddressProblems=false})async{final retry=packages.where((p)=>p.status==DeliveryStatus.absent||(includeAddressProblems&&p.status==DeliveryStatus.addressProblem)).toList();if(retry.isEmpty)return 0;final ids=retry.map((p)=>p.id).toSet();final reset=retry.map((p)=>p.copyWith(status:DeliveryStatus.pending,clearCompletedAt:true)).toList();final optimized=_optimize(reset,lat,lng);final untouched=packages.where((p)=>!ids.contains(p.id)).toList();packages=[...untouched,...optimized];routeOptimized=true;await _persist();return optimized.length;}
  Future<void> organizePhysicalLoad({int groupSize=20,bool overwrite=false})async{if(groupSize<1)throw ArgumentError.value(groupSize,'groupSize');if(!routeOptimized)throw StateError('Otimize a rota antes de organizar a carga.');var activeIndex=0;final out=<DeliveryPackage>[];for(final p in packages){final active=p.status==DeliveryStatus.pending||p.status==DeliveryStatus.current||p.status==DeliveryStatus.absent||p.status==DeliveryStatus.addressProblem;if(!active){out.add(p);continue;}final zoneIndex=activeIndex~/groupSize;final position=activeIndex%groupSize+1;final zone='${_zoneName(zoneIndex)}-${position.toString().padLeft(2,'0')}';out.add((overwrite||p.physicalZone?.trim().isNotEmpty!=true)?p.copyWith(physicalZone:zone):p);activeIndex++;}packages=out;await _persist();}
  String _zoneName(int index){var n=index+1;var name='';while(n>0){n--;name=String.fromCharCode(65+(n%26))+name;n~/=26;}return name;}
  Future<void> clear()async{packages=[];routeOptimized=false;await store.clear();notifyListeners();}
  Future<void> _persist()async{await store.save(packages);notifyListeners();}
}
