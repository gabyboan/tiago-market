import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tiago_market_app/src/app.dart';
import 'package:tiago_market_app/src/config.dart';
import 'package:tiago_market_app/src/controllers/search_controller.dart'
    as local;
import 'package:tiago_market_app/src/models/models.dart';
import 'package:tiago_market_app/src/pages/business_coming_soon.dart';
import 'package:tiago_market_app/src/pages/role_selection.dart';
import 'package:tiago_market_app/src/pages/search_page.dart';
import 'package:tiago_market_app/src/pages/welcome_page.dart';

// Run with --dart-define=SUPABASE_URL=https://test.supabase.co
// --dart-define=SUPABASE_PUBLISHABLE_KEY=test-public-key. All HTTP is mocked.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final user = <String, dynamic>{
    'id': 'a424e8c7-7ff8-4c2b-83ea-04a849b71201',
    'aud': 'authenticated',
    'role': 'authenticated',
    'email': 'buyer@tiago.example',
    'created_at': '2026-10-07T00:00:00Z',
    'app_metadata': {'provider': 'google'},
    'user_metadata': <String, dynamic>{},
  };
  var savedCart = <dynamic>[];
  final token = 'e30.${base64Url.encode(utf8.encode(jsonEncode({
            'sub': user['id'],
            'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
          }))).replaceAll('=', '')}.signature';

  setUpAll(() async {
    if (!authEnabled) return;
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabaseClientKey,
      debug: false,
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
      httpClient: MockClient((request) async {
        final path = request.url.path;
        dynamic response = <dynamic>[];
        if (path.endsWith('/token')) {
          response = {
            'access_token': token,
            'refresh_token': 'fake-refresh-token',
            'token_type': 'bearer',
            'expires_in': 3600,
            'user': user,
          };
        } else if (path.endsWith('/user')) {
          if (request.method == 'PUT') {
            user['user_metadata'] = jsonDecode(request.body)['data'];
          }
          response = user;
        } else if (path.endsWith('/logout')) {
          response = {};
        } else if (path.endsWith('/shopping_carts')) {
          if (request.method == 'POST') {
            savedCart = jsonDecode(request.body)['items'] as List;
          } else {
            response = savedCart.isEmpty
                ? []
                : [
                    {'items': savedCart}
                  ];
          }
        }
        return http.Response(jsonEncode(response), 200,
            headers: {'content-type': 'application/json'}, request: request);
      }),
    );
  });

  tearDownAll(() async {
    if (authEnabled) await Supabase.instance.dispose();
  });

  testWidgets(
      'invitado, Google, rol, cambio de modo y logout mantienen el gate',
      (tester) async {
    await tester.pumpWidget(const TiagoMarketApp());
    await tester.pumpAndSettle();
    expect(find.byType(WelcomePage), findsOneWidget);
    await tester.tap(find.text('Continuar sin cuenta'));
    await tester.pumpAndSettle();
    final controller = Provider.of<local.SearchController>(
      tester.element(find.byType(SearchPage)),
      listen: false,
    );
    await controller.addToShoppingList(ProductComparisonGroup(
      comparisonKey: 'milk',
      productName: 'Leche',
      prices: const [],
    ));
    await tester.runAsync(() => Supabase.instance.client.auth.signInWithIdToken(
          provider: OAuthProvider.google,
          idToken: 'fake-google-id-token',
        ));
    await tester.pumpAndSettle();
    expect(find.byType(RoleSelectionPage), findsOneWidget);
    await tester.tap(find.text('Quiero comprar'));
    await tester.pumpAndSettle();
    expect(find.byType(SearchPage), findsOneWidget);
    expect(controller.shoppingItems.single.quantity, 1);
    expect(controller.cartSignedIn, isTrue);
    expect(savedCart, hasLength(1));
    await tester.runAsync(() => Supabase.instance.client.auth.updateUser(
          UserAttributes(data: {'role': 'seller'}),
        ));
    await tester.pumpAndSettle();
    expect(find.byType(BusinessComingSoonPage), findsOneWidget);
    await tester.tap(find.text('Volver al modo comprador'));
    await tester.pumpAndSettle();
    expect(find.byType(SearchPage), findsOneWidget);
    await tester.runAsync(() => Supabase.instance.client.auth.signOut());
    await tester.pumpAndSettle();
    expect(find.byType(WelcomePage), findsOneWidget);
    expect(controller.shoppingItems, isEmpty);
    // Dispose the app controller and its lifecycle observer.
    await tester.pumpWidget(const SizedBox.shrink());
  }, skip: !authEnabled);
}
