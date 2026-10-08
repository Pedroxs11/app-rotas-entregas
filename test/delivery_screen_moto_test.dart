import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_rotas_entregas/app_state.dart';
import 'package:app_rotas_entregas/domain/models.dart';
import 'package:app_rotas_entregas/screens/delivery_screen.dart';
import 'package:app_rotas_entregas/services/package_store.dart';

class _DeliveryStore implements PackageStore {
  _DeliveryStore(this.items);
  List<DeliveryPackage> items;
  @override Future<void> clear() async {}
  @override Future<List<DeliveryPackage>> load() async => [...items];
  @override Future<bool> loadRouteOptimized() async => true;
  @override Future<void> save(List<DeliveryPackage> value,{bool? routeOptimized}) async {
    items=[...value];
  }
}

DeliveryPackage _package(int n,String street) => DeliveryPackage(
  id:'p$n',
  scanNumber:n,
  address:AddressData(
    raw:'$street, $n',
    street:street,
    number:'$n',
    city:'São Paulo',
    state:'SP',
    confidence:1,
    validation:ValidationStatus.confirmed,
  ),
  scannedAt:DateTime.utc(2026,10,5,10,n),
);

void main() {
  testWidgets('moto highlights the next package number and address', (tester) async {
    final first=_package(7,'Rua Teste');
    final second=_package(12,'Avenida Próxima');
    final store=_DeliveryStore([first,second]);
    final state=AppState(store:store);
    await state.init();
    state.setVehicleType(VehicleType.motorcycle);

    await tester.pumpWidget(MaterialApp(home:DeliveryScreen(state:state)));
    await tester.pumpAndSettle();

    expect(find.text('PEGUE ESTE PACOTE'),findsOneWidget);
    expect(find.text(first.label),findsWidgets);
    expect(find.text('Rua Teste, 7, São Paulo, SP'),findsOneWidget);
    expect(find.textContaining('Entrega 1 de 2'),findsOneWidget);

    final packageTexts=tester.widgetList<Text>(find.text(first.label));
    expect(packageTexts.any((text)=>text.style?.fontSize==34),isTrue);
  });
}
