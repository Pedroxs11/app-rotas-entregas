import 'package:flutter_test/flutter_test.dart';
import 'package:app_rotas_entregas/main.dart';

void main() {
  testWidgets('app bootstraps without crashing', (tester) async {
    await tester.pumpWidget(const DeliveryApp());
    expect(find.byType(DeliveryApp), findsOneWidget);
  });
}
