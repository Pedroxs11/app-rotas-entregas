enum ValidationStatus { confirmed, needsReview, invalid }
enum DeliveryStatus { pending, current, delivered, absent, skipped, addressProblem }

class AddressData {
  final String raw;
  final String? street, number, complement, neighborhood, city, state, cep;
  final double? latitude, longitude;
  final double confidence;
  final ValidationStatus validation;
  const AddressData({required this.raw,this.street,this.number,this.complement,this.neighborhood,this.city,this.state,this.cep,this.latitude,this.longitude,required this.confidence,required this.validation});
  String get formatted=>[if(street?.isNotEmpty==true)street,if(number?.isNotEmpty==true)number,if(complement?.isNotEmpty==true)complement,if(neighborhood?.isNotEmpty==true)neighborhood,if(city?.isNotEmpty==true)city,if(state?.isNotEmpty==true)state,if(cep?.isNotEmpty==true)cep].whereType<String>().join(', ');
  Map<String,dynamic> toJson()=>{'raw':raw,'street':street,'number':number,'complement':complement,'neighborhood':neighborhood,'city':city,'state':state,'cep':cep,'latitude':latitude,'longitude':longitude,'confidence':confidence,'validation':validation.name};
  factory AddressData.fromJson(Map<String,dynamic> j)=>AddressData(raw:j['raw']??'',street:j['street'],number:j['number'],complement:j['complement'],neighborhood:j['neighborhood'],city:j['city'],state:j['state'],cep:j['cep'],latitude:(j['latitude'] as num?)?.toDouble(),longitude:(j['longitude'] as num?)?.toDouble(),confidence:(j['confidence'] as num? ??0).toDouble(),validation:ValidationStatus.values.byName(j['validation']??'needsReview'));
}

class DeliveryPackage {
  final String id;
  final int scanNumber;
  final String? trackingCode,recipient,physicalZone,receivedBy;
  final AddressData address;
  final DateTime scannedAt;
  final DateTime? completedAt;
  final bool pinned;
  final DeliveryStatus status;
  const DeliveryPackage({required this.id,required this.scanNumber,this.trackingCode,this.recipient,this.physicalZone,this.receivedBy,required this.address,required this.scannedAt,this.completedAt,this.pinned=false,this.status=DeliveryStatus.pending});
  String get label=>'Pacote ${scanNumber.toString().padLeft(2,'0')}';
  String get physicalLabel=>physicalZone?.trim().isNotEmpty==true?physicalZone!.trim():label;
  String? get shortTracking{final value=trackingCode?.trim();if(value==null||value.isEmpty)return null;return value.length<=12?value:'…${value.substring(value.length-12)}';}
  DeliveryPackage copyWith({AddressData? address,bool? pinned,DeliveryStatus? status,String? physicalZone,String? trackingCode,String? recipient,String? receivedBy,DateTime? completedAt,bool clearPhysicalZone=false,bool clearTrackingCode=false,bool clearRecipient=false,bool clearCompletedAt=false})=>DeliveryPackage(id:id,scanNumber:scanNumber,trackingCode:clearTrackingCode?null:(trackingCode??this.trackingCode),recipient:clearRecipient?null:(recipient??this.recipient),physicalZone:clearPhysicalZone?null:(physicalZone??this.physicalZone),receivedBy:receivedBy??this.receivedBy,address:address??this.address,scannedAt:scannedAt,completedAt:clearCompletedAt?null:(completedAt??this.completedAt),pinned:pinned??this.pinned,status:status??this.status);
  Map<String,dynamic> toJson()=>{'id':id,'scanNumber':scanNumber,'trackingCode':trackingCode,'recipient':recipient,'physicalZone':physicalZone,'receivedBy':receivedBy,'address':address.toJson(),'scannedAt':scannedAt.toIso8601String(),'completedAt':completedAt?.toIso8601String(),'pinned':pinned,'status':status.name};
  factory DeliveryPackage.fromJson(Map<String,dynamic> j)=>DeliveryPackage(id:j['id'],scanNumber:j['scanNumber'],trackingCode:j['trackingCode'],recipient:j['recipient'],physicalZone:j['physicalZone'],receivedBy:j['receivedBy'],address:AddressData.fromJson(Map<String,dynamic>.from(j['address'])),scannedAt:DateTime.parse(j['scannedAt']),completedAt:j['completedAt']==null?null:DateTime.tryParse(j['completedAt'].toString()),pinned:j['pinned']??false,status:DeliveryStatus.values.byName(j['status']??'pending'));
}
