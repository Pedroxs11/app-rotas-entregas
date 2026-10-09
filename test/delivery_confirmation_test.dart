import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/screens/delivery_screen.dart';
import 'package:app_rotas_entregas/services/package_store.dart';

class _DeliveryStore implements PackageStore {
  _DeliveryStore(this.items);
  List<DeliveryPackage> items;

  @override
  Future<void> clear() async {}

  @override
  Future<List<DeliveryPackage>> load() async => [...items];

  @override
  Future<bool> loadRouteOptimized() async => true;

  @override
  Future<void> save(List<DeliveryPackage> packages, {bool? routeOptimized}) async {
    items = [...packages];
  }
}

DeliveryPackage _package(int number) => DeliveryPackage(
  id: 'package-$number',
  scanNumber: number,
  address: AddressData(
    raw: 'Rua de teste, $number',
    street: 'Rua de teste',
    number: '$number',
    city: 'São Paulo',
    state: 'SP',
    confidence: 1,
    validation: ValidationStatus.confirmed,
  ),
  scannedAt: DateTime.utc(2026, 10, 9, 10, number),
);

void main() {
  testWidgets('delivery confirmation stays for 1.5 seconds then advances', (tester) async {
    final state = AppState(store: _DeliveryStore([_package(1), _package(2)]));
    await state.init();

    await tester.pumpWidget(MaterialApp(home: DeliveryScreen(state: state)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('ENTREGUE • PRÓXIMO'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Maria');
    await tester.tap(find.text('Confirmar entrega'));
    await tester.pump();

    expect(find.text('Pacote entregue!'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1499));
    expect(find.text('Pacote entregue!'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();

    expect(find.text('Pacote entregue!'), findsNothing);
    expect(find.text('Entrega 2 de 2'), findsOneWidget);
    expect(state.packages.first.status, DeliveryStatus.delivered);
    expect(state.packages.first.receivedBy, 'Maria');
  });
}
