import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/app.dart';
import 'src/config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FirebaseCrashlytics? crashlytics;

  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      await Firebase.initializeApp();
      crashlytics = FirebaseCrashlytics.instance;
      await crashlytics.setCrashlyticsCollectionEnabled(!kDebugMode);
    } catch (error, stack) {
      debugPrint('Firebase initialization failed: $error\n$stack');
    }
  }

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exceptionAsString()}');
    crashlytics?.recordFlutterFatalError(details);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Unhandled error: $error\n$stack');
    crashlytics?.recordError(error, stack, fatal: true);
    return true;
  };

  Future<void> startApp() async {
    if (authEnabled) {
      await Supabase.initialize(
        url: supabaseUrl,
        publishableKey: supabaseClientKey,
      );
    }
    runApp(const TiagoMarketApp());
  }

  if (sentryDsn.isEmpty) {
    await startApp();
  } else {
    await SentryFlutter.init(
      (options) {
        options.dsn = sentryDsn;
        options.tracesSampleRate = 0.15;
        options.environment = const String.fromEnvironment(
          'APP_ENV',
          defaultValue: 'production',
        );
      },
      appRunner: startApp,
    );
  }
}
