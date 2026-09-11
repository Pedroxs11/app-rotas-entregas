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
  Future<int> addManyFromText(String text)async{final lines=text.split(RegExp(r'\r?\n')).map((e)=>e.trim()).where((e)=>e.isNotEmpty).toList();var added=0;for(final line in lines){try{packages=[...packages,packageService.fromOcr(line,packages)];added++;}catch(_){}}await _persist();return added;}
  Future<void> addStructured(AddressData address)async{final p=packageService.fromOcr(address.raw,packages);packages=[...packages,p.copyWith(address:address)];await _persist();}
  Future<void> updateAddress(int index,AddressData address)async{final p=packages[index];await update(index,p.copyWith(address:address));}
  Future<void> update(int index,DeliveryPackage value)async{packages=[...packages]..[index]=value;await _persist();}
  Future<void> reorder(int oldIndex,int newIndex)async{final x=[...packages];if(newIndex>oldIndex)newIndex--;final p=x.removeAt(oldIndex);x.insert(newIndex,p);packages=x;await _persist();}
  Future<void> locateConfirmed()async{locating=true;notifyListeners();final out=[...packages];for(var i=0;i<out.length;i++){final p=out[i];if(p.address.validation!=ValidationStatus.confirmed||p.address.latitude!=null)continue;try{final a=await geocoder.locate(p.address);out[i]=p.copyWith(address:a);}catch(_){}}packages=out;locating=false;await _persist();}
  Future<void> optimizeFrom(double lat,double lng)async{
    final finished=packages.where((p)=>p.status!=DeliveryStatus.pending&&p.status!=DeliveryStatus.current).toList();
    final active=packages.where((p)=>p.status==DeliveryStatus.pending||p.status==DeliveryStatus.current).toList();
    final pinned=<int,DeliveryPackage>{};
    final free=<DeliveryPackage>[];
    for(var i=0;i<active.length;i++){if(active[i].pinned){pinned[i]=active[i];}else{free.add(active[i]);}}
    var optimized=routeEngine.optimize(free,startLat:lat,startLng:lng);
    for(final e in pinned.entries){final at=e.key.clamp(0,optimized.length);optimized.insert(at,e.value);}
    // Entregas já processadas ficam intactas; apenas o restante da rota muda de ordem.
    packages=[...finished,...optimized];
    await _persist();
  }
  Future<void> clear()async{packages=[];await store.clear();notifyListeners();}
  Future<void> _persist()async{await store.save(packages);notifyListeners();}
}
