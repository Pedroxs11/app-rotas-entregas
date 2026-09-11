import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_rotas_entregas/services/local_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('route starts as not optimized when nothing was saved', () async {
    final store = LocalStore();
    expect(await store.loadRouteOptimized(), isFalse);
  });

  test('persists optimized route state across store instances', () async {
    final first = LocalStore();
    await first.save(const [], routeOptimized: true);

    final reopened = LocalStore();
    expect(await reopened.loadRouteOptimized(), isTrue);
    expect(await reopened.load(), isEmpty);
  });

  test('clear removes packages and optimized route state', () async {
    final store = LocalStore();
    await store.save(const [], routeOptimized: true);
    await store.clear();

    expect(await store.load(), isEmpty);
    expect(await store.loadRouteOptimized(), isFalse);
  });
}
