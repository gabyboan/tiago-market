import 'package:flutter/material.dart';
import 'src/app.dart';
import 'src/config.dart';
import 'src/demo/demo_market_api.dart';

/// Standalone entry point. It never initializes authentication or telemetry.
void main() {
  if (supabaseUrl.isNotEmpty ||
      supabaseClientKey.isNotEmpty ||
      apiBaseUrl.isNotEmpty ||
      sentryDsn.isNotEmpty) {
    throw StateError('Build the portfolio demo without service configuration.');
  }
  WidgetsFlutterBinding.ensureInitialized();
  runApp(TiagoMarketApp(marketApi: DemoMarketApi()));
}
