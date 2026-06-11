import 'package:flutter_test/flutter_test.dart';
import 'package:tiago_market_app/main.dart';

void main() {
  testWidgets('muestra la comparación demo', (tester) async {
    await tester.pumpWidget(const TiagoMarketApp());

    expect(find.text('Tiago Market'), findsOneWidget);
    expect(find.text('Mejores precios'), findsOneWidget);
    expect(find.text('BODEGA AURRERA'), findsOneWidget);
    expect(find.text('\$15.00'), findsOneWidget);
  });
}
