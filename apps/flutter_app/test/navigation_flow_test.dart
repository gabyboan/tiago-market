import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiago_market_app/src/navigation/app_routes.dart';
import 'package:tiago_market_app/src/pages/search_page.dart';
import 'package:tiago_market_app/src/pages/welcome_page.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('welcome page navega a SearchPage por ruta nombrada',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        initialRoute: AppRoutes.welcome,
        routes: {
          AppRoutes.welcome: (_) => const WelcomePage(),
          AppRoutes.search: (_) => const SearchPage(),
        },
      ),
    );

    expect(find.text('Continuar sin cuenta'), findsOneWidget);
    await tester.tap(find.text('Continuar sin cuenta'));
    await tester.pumpAndSettle();

    expect(find.byType(SearchPage), findsOneWidget);
  });

  testWidgets('SearchPage renderiza el buscador y la cabecera', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: SearchPage()),
    );

    await tester.pumpAndSettle();

    expect(find.text('Compara antes\nde comprar.'), findsOneWidget);
    expect(find.byType(SearchBar), findsOneWidget);
  });
}
