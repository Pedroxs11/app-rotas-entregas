import 'models.dart';

class RoutePlan {
  final String id;
  final DateTime createdAt;
  final List<DeliveryPackage> stops;
  final double? estimatedKm;
  final Duration? estimatedDuration;
  const RoutePlan({required this.id,required this.createdAt,required this.stops,this.estimatedKm,this.estimatedDuration});

  int get pending=>stops.where((e)=>e.status==DeliveryStatus.pending||e.status==DeliveryStatus.current).length;
  int get delivered=>stops.where((e)=>e.status==DeliveryStatus.delivered).length;
  int get failed=>stops.where((e)=>e.status==DeliveryStatus.absent||e.status==DeliveryStatus.addressProblem).length;
}

class RouteConstraint {
  final String packageId;
  final DateTime? deliverBefore;
  final bool lockedPosition;
  const RouteConstraint({required this.packageId,this.deliverBefore,this.lockedPosition=false});
}
