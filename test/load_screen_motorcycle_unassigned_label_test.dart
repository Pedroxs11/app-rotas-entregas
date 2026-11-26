import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/screens/load_screen.dart';
import 'package:app_rotas_entregas/services/package_store.dart';

class _MotorcycleLoadStore implements PackageStore {
  _MotorcycleLoadStore(this.items);

  List<DeliveryPackage> items;

  @override
  Future<void> clear() async {
    items = [];
  }

  @override
  Future<List<DeliveryPackage>> load() async => [...items];

  @override
  Future<bool> loadRouteOptimized() async => true;

  @override
  Future<void> save(
    List<DeliveryPackage> value, {
    bool? routeOptimized,
  }) async {
    items = [...value];
  }
}

DeliveryPackage _package() => DeliveryPackage(
      id: 'moto-package-7',
      scanNumber: 7,
      address: AddressData(
        raw: 'Rua Teste, 7',
        street: 'Rua Teste',
        number: '7',
        city: 'São Paulo',
        state: 'SP',
        confidence: 1,
        validation: ValidationStatus.confirmed,
      ),
      scannedAt: DateTime.utc(2026, 11, 26, 10),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'motorcycle organizer labels packages that still need a physical position',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({
        'load_vehicle_type': 'motorcycle',
      });
      final state = AppState(
        store: _MotorcycleLoadStore([_package()]),
      );
      await state.init();

      await tester.pumpWidget(
        MaterialApp(home: LoadScreen(state: state)),
      );
      await tester.pumpAndSettle();

      final packageLabel = find.text('Pacote 07');
      final scrollable = find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(Scrollable),
      ).first;
      await tester.scrollUntilVisible(
        packageLabel,
        160,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Sem posição na moto'), findsOneWidget);
      expect(find.textContaining('Sem posição no carro'), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      state.dispose();
    },
  );
}
