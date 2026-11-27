import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/screens/load_screen.dart';
import 'package:app_rotas_entregas/services/package_store.dart';

class _LargeSearchStore implements PackageStore {
  _LargeSearchStore(this.items);

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

DeliveryPackage _largeSearchPackage(int number) => DeliveryPackage(
      id: 'large-search-$number',
      scanNumber: number,
      trackingCode: number == 1000 ? 'BR-TRACK-FIM-1000' : 'BR-TRACK-$number',
      recipient: number == 1000 ? 'João Último' : 'Destinatário $number',
      address: AddressData(
        raw: 'Rua das Entregas, $number',
        street: 'Rua das Entregas',
        number: '$number',
        city: 'São Paulo',
        state: 'SP',
        confidence: 1,
        validation: ValidationStatus.confirmed,
      ),
      scannedAt: DateTime.utc(2026, 11, 26).add(Duration(minutes: number)),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'search finds the last package in a 1000-package car and motorcycle load',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (final vehicle in VehicleType.values) {
        SharedPreferences.setMockInitialValues({
          'load_vehicle_type': vehicle.name,
        });
        final state = AppState(
          store: _LargeSearchStore(
            List.generate(1000, (index) => _largeSearchPackage(index + 1)),
          ),
        );
        await state.init();

        await tester.pumpWidget(
          MaterialApp(home: LoadScreen(state: state)),
        );
        await tester.pumpAndSettle();

        // The match is deliberately at the end of the 1000-package route and
        // differs by accents and punctuation from the stored recipient name.
        await tester.enterText(find.byType(TextField), 'joao-ultimo');
        await tester.pumpAndSettle();

        // The package list is lazy and sits below the vehicle diagram. Scroll
        // to the filtered row before asserting that the end-of-route match is
        // mounted in the viewport.
        final scrollable = find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first;
        await tester.scrollUntilVisible(
          find.text('Pacote 1000'),
          300,
          scrollable: scrollable,
        );
        await tester.pumpAndSettle();

        expect(find.text('Pacote 1000'), findsOneWidget);
        expect(
          find.text('Nenhum pacote encontrado para essa busca.'),
          findsNothing,
        );

        // The same last package must also be discoverable by its tracking
        // code and by the compact scan-code notation used by drivers.
        for (final query in ['br-track-fim-1000', 'p1000']) {
          await tester.enterText(find.byType(TextField), query);
          await tester.pumpAndSettle();

          expect(
            find.text('Pacote 1000'),
            findsOneWidget,
            reason: 'The final package must match the search "$query".',
          );
          expect(
            find.text('Nenhum pacote encontrado para essa busca.'),
            findsNothing,
          );
          expect(tester.takeException(), isNull);
        }

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        state.dispose();
      }
    },
  );
}
