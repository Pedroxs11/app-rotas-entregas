import 'package:geolocator/geolocator.dart';

class LocationService {
  Future<Position> current() async {
    if(!await Geolocator.isLocationServiceEnabled()) throw Exception('Ative a localização do aparelho.');
    var permission=await Geolocator.checkPermission();
    if(permission==LocationPermission.denied) permission=await Geolocator.requestPermission();
    if(permission==LocationPermission.denied||permission==LocationPermission.deniedForever) throw Exception('Permissão de localização necessária para iniciar a rota.');
    return Geolocator.getCurrentPosition(locationSettings:const LocationSettings(accuracy:LocationAccuracy.high));
  }
}
