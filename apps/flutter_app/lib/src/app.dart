import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tiago_market_app/src/navigation/app_routes.dart';
import 'package:tiago_market_app/src/pages/auth_flow.dart';
import 'package:tiago_market_app/src/pages/business_coming_soon.dart';
import 'package:tiago_market_app/src/pages/role_selection.dart';
import 'package:tiago_market_app/src/pages/legal_info_page.dart';
import 'package:tiago_market_app/src/pages/search_page.dart';
import 'package:tiago_market_app/src/pages/welcome_page.dart';

class TiagoMarketApp extends StatelessWidget {
  const TiagoMarketApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Tiago Market',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF006C51)),
        scaffoldBackgroundColor: const Color(0xFFF5F7F5),
        splashFactory: InkRipple.splashFactory,
        useMaterial3: true,
        cardTheme: const CardThemeData(
          margin: EdgeInsets.zero,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(20)),
            side: BorderSide(color: Color(0xFFE1E8E4)),
          ),
        ),
      ),
      home: const AuthFlowGate(),
      routes: {
        AppRoutes.welcome: (_) => const WelcomePage(),
        AppRoutes.search: (_) => const SearchPage(),
        AppRoutes.roleSelection: (context) {
          final user = ModalRoute.of(context)!.settings.arguments as User?;
          return RoleSelectionPage(user: user!);
        },
        AppRoutes.sellerComingSoon: (_) => const BusinessComingSoonPage(),
        AppRoutes.legalInfo: (_) => const LegalInfoPage(),
      },
    );
  }
}
