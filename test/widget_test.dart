import 'package:flutter_test/flutter_test.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/main.dart';
import 'package:app_rotas_entregas/services/package_store.dart';

class _MemoryStore implements PackageStore {
  @override
  Future<void> clear() async {}

  @override
  Future<List<DeliveryPackage>> load() async => [];

  @override
  Future<bool> loadRouteOptimized() async => false;

  @override
  Future<void> save(List<DeliveryPackage> packages,{bool? routeOptimized}) async {}
}

void main() {
  testWidgets('app bootstraps without crashing', (tester) async {
    await tester.pumpWidget(DeliveryApp(store:_MemoryStore()));
    await tester.pump();
    expect(find.byType(DeliveryApp), findsOneWidget);
  });
}
