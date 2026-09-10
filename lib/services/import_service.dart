import '../domain/models.dart';
import 'package_service.dart';

class ImportService {
  final PackageService packages;
  ImportService(this.packages);

  List<DeliveryPackage> fromLines(String text,List<DeliveryPackage> existing){
    final out=[...existing];
    for(final line in text.split('\n').map((e)=>e.trim()).where((e)=>e.isNotEmpty)){
      try { out.add(packages.fromOcr(line,out)); } on DuplicatePackageException { /* ignora duplicata na importação */ }
    }
    return out;
  }
}
