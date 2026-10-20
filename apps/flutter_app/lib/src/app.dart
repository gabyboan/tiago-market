import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:tiago_market_app/src/controllers/search_controller.dart'
    as local;
import 'package:tiago_market_app/src/navigation/app_routes.dart';
import 'package:tiago_market_app/src/pages/auth_flow.dart';
import 'package:tiago_market_app/src/pages/business_coming_soon.dart';
import 'package:tiago_market_app/src/pages/role_selection.dart';
import 'package:tiago_market_app/src/pages/legal_info_page.dart';
import 'package:tiago_market_app/src/pages/search_page.dart';
import 'package:tiago_market_app/src/pages/welcome_page.dart';
import 'package:tiago_market_app/src/widgets/startup_splash.dart';
import 'package:tiago_market_app/src/services/market_api.dart';
import 'package:tiago_market_app/src/demo/demo_frame.dart';

class TiagoMarketApp extends StatelessWidget {
  const TiagoMarketApp({this.marketApi, super.key});

  final MarketApi? marketApi;

  @override
  Widget build(BuildContext context) {
    final demo = marketApi?.isDemo ?? false;
    return ChangeNotifierProvider<local.SearchController>(
      create: (_) => local.SearchController(api: marketApi),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Tiago Market',
        builder: (context, child) => StartupSplash(
          child: demo ? DemoFrame(child: child!) : child!,
        ),
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
        home: demo ? const SearchPage() : const AuthFlowGate(),
        routes: {
          AppRoutes.welcome: (_) =>
              demo ? const SearchPage() : const WelcomePage(),
          AppRoutes.search: (_) => const SearchPage(),
          AppRoutes.roleSelection: (context) {
            final user = ModalRoute.of(context)!.settings.arguments as User?;
            return RoleSelectionPage(user: user);
          },
          AppRoutes.sellerComingSoon: (_) => const BusinessComingSoonPage(),
          AppRoutes.legalInfo: (_) =>
              demo ? const DemoInfoPage() : const LegalInfoPage(),
        },
      ),
    );
  }
}
