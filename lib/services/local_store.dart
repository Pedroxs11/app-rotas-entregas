import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/models.dart';

class LocalStore {
  static const _key='delivery_packages_v1';
  Future<List<DeliveryPackage>> load() async {
    final p=await SharedPreferences.getInstance();
    final raw=p.getString(_key);
    if(raw==null) return [];
    return (jsonDecode(raw) as List).map((e)=>DeliveryPackage.fromJson(Map<String,dynamic>.from(e))).toList();
  }
  Future<void> save(List<DeliveryPackage> packages) async {
    final p=await SharedPreferences.getInstance();
    await p.setString(_key,jsonEncode(packages.map((e)=>e.toJson()).toList()));
  }
  Future<void> clear() async { final p=await SharedPreferences.getInstance(); await p.remove(_key); }
}
