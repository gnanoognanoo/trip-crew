import 'dart:developer' as developer;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:tripcrew/firebase_options.dart';

/// Centralized service handling safe multi-platform Firebase initialization.
class FirebaseService {
  static bool _initialized = false;
  static bool get isInitialized => _initialized;

  static Future<void> initialize() async {
    if (_initialized) return;

    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      _initialized = true;
      developer.log(
        'Firebase initialized successfully',
        name: 'FirebaseService',
      );

      // Initialize Crashlytics on supported platforms (non-web)
      if (!kIsWeb) {
        FlutterError.onError = (errorDetails) {
          FirebaseCrashlytics.instance.recordFlutterFatalError(errorDetails);
        };
        PlatformDispatcher.instance.onError = (error, stack) {
          FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
          return true;
        };
      }
    } catch (e, stack) {
      developer.log(
        'Firebase initialization warning (running with local/offline fallback): $e',
        name: 'FirebaseService',
        stackTrace: stack,
      );
      // Allow app to continue gracefully in development/offline modes
      _initialized = false;
    }
  }
}
