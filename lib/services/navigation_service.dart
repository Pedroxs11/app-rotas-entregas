import 'package:url_launcher/url_launcher.dart';
import '../domain/models.dart';

class NavigationService {
  Future<bool> openWaze(DeliveryPackage package) async {
    final a=package.address;
    final Uri uri;
    if(a.latitude!=null && a.longitude!=null){
      uri=Uri.parse('https://waze.com/ul?ll=${a.latitude},${a.longitude}&navigate=yes');
    } else {
      uri=Uri.parse('https://waze.com/ul?q=${Uri.encodeComponent(a.formatted)}&navigate=yes');
    }
    return launchUrl(uri,mode:LaunchMode.externalApplication);
  }
}
