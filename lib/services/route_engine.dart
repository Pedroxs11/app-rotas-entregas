import 'dart:math';
import '../domain/models.dart';

class RouteEngine {
  /// Heurística nearest-neighbor para V1. Mantém o comportamento simples,
  /// mas procura o próximo ponto em uma única varredura em vez de ordenar
  /// toda a lista a cada parada. Isso reduz bastante o trabalho em rotas grandes.
  List<DeliveryPackage> optimize(
    List<DeliveryPackage> input, {
    double? startLat,
    double? startLng,
  }) {
    final located = input
        .where((p) => p.address.latitude != null && p.address.longitude != null)
        .toList();
    final unlocated = input
        .where((p) => p.address.latitude == null || p.address.longitude == null)
        .toList();

    if (located.length < 2 || startLat == null || startLng == null) {
      return [...input];
    }

    final result = <DeliveryPackage>[];
    var lat = startLat;
    var lng = startLng;

    while (located.isNotEmpty) {
      var bestIndex = 0;
      var bestDistance = _distance(
        lat,
        lng,
        located[0].address.latitude!,
        located[0].address.longitude!,
      );

      for (var i = 1; i < located.length; i++) {
        final candidate = located[i];
        final distance = _distance(
          lat,
          lng,
          candidate.address.latitude!,
          candidate.address.longitude!,
        );
        if (distance < bestDistance) {
          bestDistance = distance;
          bestIndex = i;
        }
      }

      final next = located.removeAt(bestIndex);
      result.add(next);
      lat = next.address.latitude!;
      lng = next.address.longitude!;
    }

    return [...result, ...unlocated];
  }

  double _distance(double a, double b, double c, double d) {
    final x = (d - b) * cos((a + c) / 2 * pi / 180);
    final y = c - a;
    return sqrt(x * x + y * y);
  }

  List<DeliveryPackage> move(
    List<DeliveryPackage> route,
    int oldIndex,
    int newIndex,
  ) {
    final out = [...route];
    if (newIndex > oldIndex) newIndex--;
    final item = out.removeAt(oldIndex);
    out.insert(newIndex, item);
    return out;
  }
}
