import 'package:flutter/foundation.dart';
import 'domain/models.dart';
import 'services/address_parser.dart';
import 'services/package_service.dart';
import 'services/local_store.dart';
import 'services/nominatim_geocoding_service.dart';
import 'services/route_engine.dart';

class AppState extends ChangeNotifier {
  final store=LocalStore();
  final geocoder=NominatimGeocodingService();
  final routeEngine=RouteEngine();
  late final PackageService packageService=PackageService(AddressParser());
  List<DeliveryPackage> packages=[];
  bool loading=true, locating=false;
  int get reviewCount=>packages.where((p)=>p.address.validation!=ValidationStatus.confirmed).length;
  int get deliveredCount=>packages.where((p)=>p.status==DeliveryStatus.delivered).length;
  int get locatedCount=>packages.where((p)=>p.address.latitude!=null).length;
  Future<void> init()async{packages=await store.load();loading=false;notifyListeners();}
  Future<void> addFromText(String text,{String? trackingCode})async{packages=[...packages,packageService.fromOcr(text,packages,trackingCode:trackingCode)];await _persist();}
  Future<void> update(int index,DeliveryPackage value)async{packages=[...packages]..[index]=value;await _persist();}
  Future<void> reorder(int oldIndex,int newIndex)async{final x=[...packages];if(newIndex>oldIndex)newIndex--;final p=x.removeAt(oldIndex);x.insert(newIndex,p);packages=x;await _persist();}
  Future<void> locateConfirmed()async{locating=true;notifyListeners();final out=[...packages];for(var i=0;i<out.length;i++){final p=out[i];if(p.address.validation!=ValidationStatus.confirmed||p.address.latitude!=null)continue;try{final a=await geocoder.locate(p.address);out[i]=p.copyWith(address:a);}catch(_){/* permanece sem coordenada e aparece como pendência */}}packages=out;locating=false;await _persist();}
  Future<void> optimizeFrom(double lat,double lng)async{final pinned=<int,DeliveryPackage>{};for(var i=0;i<packages.length;i++){if(packages[i].pinned)pinned[i]=packages[i];}var result=routeEngine.optimize(packages.where((p)=>!p.pinned).toList(),startLat:lat,startLng:lng);for(final e in pinned.entries){result.insert(e.key.clamp(0,result.length),e.value);}packages=result;await _persist();}
  Future<void> clear()async{packages=[];await store.clear();notifyListeners();}
  Future<void> _persist()async{await store.save(packages);notifyListeners();}
}
