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
      await crashlytics.setCrashlyticsCollectionEnabled(
        kReleaseMode && crashlyticsEnabled,
      );
      await crashlytics.setCustomKey('environment', appEnvironment);
    } catch (error, stack) {
      debugPrint('Firebase initialization failed: $error\n$stack');
    }
  }

  Future<void> startApp() async {
    // Install after Sentry initialization so both reporters keep their handlers.
    final previousFlutterHandler = FlutterError.onError;
    final previousPlatformHandler = PlatformDispatcher.instance.onError;
    FlutterError.onError = (details) {
      previousFlutterHandler?.call(details);
      crashlytics?.recordFlutterFatalError(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      final previouslyHandled = previousPlatformHandler?.call(error, stack);
      crashlytics?.recordError(error, stack, fatal: true);
      return crashlytics != null || (previouslyHandled ?? false);
    };
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
        options.environment = appEnvironment;
      },
      appRunner: startApp,
    );
  }
}
