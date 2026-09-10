import 'package:flutter/foundation.dart';
import 'domain/models.dart';
import 'services/address_parser.dart';
import 'services/package_service.dart';
import 'services/local_store.dart';

class AppState extends ChangeNotifier {
  final store=LocalStore();
  late final PackageService packageService=PackageService(AddressParser());
  List<DeliveryPackage> packages=[];
  bool loading=true;

  int get reviewCount=>packages.where((p)=>p.address.validation!=ValidationStatus.confirmed).length;
  int get deliveredCount=>packages.where((p)=>p.status==DeliveryStatus.delivered).length;

  Future<void> init() async { packages=await store.load(); loading=false; notifyListeners(); }
  Future<void> addFromText(String text,{String? trackingCode}) async { packages=[...packages,packageService.fromOcr(text,packages,trackingCode:trackingCode)]; await _persist(); }
  Future<void> update(int index,DeliveryPackage value) async { packages=[...packages]..[index]=value; await _persist(); }
  Future<void> reorder(int oldIndex,int newIndex) async { final x=[...packages]; if(newIndex>oldIndex)newIndex--; final p=x.removeAt(oldIndex); x.insert(newIndex,p); packages=x; await _persist(); }
  Future<void> clear() async { packages=[]; await store.clear(); notifyListeners(); }
  Future<void> _persist() async { await store.save(packages); notifyListeners(); }
}
