import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tiago_market_app/src/config.dart';
import 'package:tiago_market_app/src/pages/business_coming_soon.dart';
import 'package:tiago_market_app/src/pages/role_selection.dart';
import 'package:tiago_market_app/src/pages/search_page.dart';
import 'package:tiago_market_app/src/pages/welcome_page.dart';
import 'package:tiago_market_app/src/widgets/session_loading_page.dart';

class AuthFlowGate extends StatefulWidget {
  const AuthFlowGate({super.key});

  @override
  State<AuthFlowGate> createState() => _AuthFlowGateState();
}

class _AuthFlowGateState extends State<AuthFlowGate> {
  StreamSubscription<AuthState>? _authSubscription;
  Timer? _minimumLoadingTimer;
  User? _user;
  bool _minimumLoadingFinished = !authEnabled;
  bool _guest = false;

  @override
  void initState() {
    super.initState();
    if (!authEnabled) return;
    final auth = Supabase.instance.client.auth;
    _user = auth.currentUser;
    _minimumLoadingTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _minimumLoadingFinished = true);
    });
    // Stay mounted during guest browsing, login, role changes and logout.
    _authSubscription = auth.onAuthStateChange.listen((event) {
      if (!mounted) return;
      setState(() {
        _user = event.session?.user;
        if (event.event == AuthChangeEvent.signedOut) _guest = false;
      });
      if (event.event == AuthChangeEvent.signedOut) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    });
  }

  @override
  void dispose() {
    _minimumLoadingTimer?.cancel();
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_minimumLoadingFinished) {
      return SessionLoadingPage(returningUser: _user != null);
    }
    final user = _user;
    if (user == null) {
      return _guest
          ? const SearchPage()
          : WelcomePage(onContinueAsGuest: () => setState(() => _guest = true));
    }
    final role = user.userMetadata?['role'];
    if (role == 'buyer') return const SearchPage();
    if (role == 'seller') return const BusinessComingSoonPage();
    return RoleSelectionPage(
      user: user,
      onRoleSelected: () {
        if (mounted) {
          setState(() => _user = Supabase.instance.client.auth.currentUser);
        }
      },
    );
  }
}
