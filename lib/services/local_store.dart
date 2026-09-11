import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/models.dart';

class LocalStore {
  static const _key='delivery_packages_v1';
  static const _routeOptimizedKey='route_optimized_v1';
  Future<List<DeliveryPackage>> load() async {final p=await SharedPreferences.getInstance();final raw=p.getString(_key);if(raw==null)return [];return (jsonDecode(raw) as List).map((e)=>DeliveryPackage.fromJson(Map<String,dynamic>.from(e))).toList();}
  Future<bool> loadRouteOptimized()async{final p=await SharedPreferences.getInstance();return p.getBool(_routeOptimizedKey)??false;}
  Future<void> save(List<DeliveryPackage> packages,{bool? routeOptimized}) async {final p=await SharedPreferences.getInstance();await p.setString(_key,jsonEncode(packages.map((e)=>e.toJson()).toList()));if(routeOptimized!=null)await p.setBool(_routeOptimizedKey,routeOptimized);}
  Future<void> clear() async {final p=await SharedPreferences.getInstance();await p.remove(_key);await p.remove(_routeOptimizedKey);}
}
