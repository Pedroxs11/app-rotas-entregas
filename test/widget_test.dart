import 'package:flutter_test/flutter_test.dart';
import 'package:app_rotas_entregas/main.dart';

void main() {
  testWidgets('app starts', (tester) async {
    await tester.pumpWidget(const DeliveryApp());
    expect(find.text('Minha rota'), findsOneWidget);
  });
}
