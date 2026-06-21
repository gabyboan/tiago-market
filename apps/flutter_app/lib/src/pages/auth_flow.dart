import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tiago_market_app/src/config.dart';
import 'package:tiago_market_app/src/navigation/app_routes.dart';
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
  bool _checkingSession = authEnabled;
  bool _minimumLoadingFinished = !authEnabled;
  bool _navigationScheduled = false;

  @override
  void initState() {
    super.initState();
    if (!authEnabled) return;
    final auth = Supabase.instance.client.auth;
    _user = auth.currentSession?.user;
    _checkingSession = false;
    _minimumLoadingTimer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      setState(() => _minimumLoadingFinished = true);
    });
    _authSubscription = auth.onAuthStateChange.listen((event) {
      if (!mounted) return;
      setState(() {
        _user = event.session?.user;
        _checkingSession = false;
      });
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
    if (_checkingSession || !_minimumLoadingFinished) {
      return SessionLoadingPage(returningUser: _user != null);
    }

    if (_navigationScheduled) {
      return const SizedBox.shrink();
    }

    final user = _user;
    final targetRoute = user == null
        ? AppRoutes.welcome
        : (user.userMetadata?['role'] as String?) == 'buyer'
            ? AppRoutes.search
            : (user.userMetadata?['role'] as String?) == 'seller'
                ? AppRoutes.sellerComingSoon
                : AppRoutes.roleSelection;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _navigationScheduled = true;
      });
      if (targetRoute == AppRoutes.roleSelection) {
        Navigator.of(context).pushReplacementNamed(
          targetRoute,
          arguments: user,
        );
      } else {
        Navigator.of(context).pushReplacementNamed(targetRoute);
      }
    });

    return const SizedBox.shrink();
  }
}
