import 'dart:developer' as developer;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Centralized service managing safe Supabase initialization.
class SupabaseService {
  static bool _initialized = false;
  static bool get isInitialized => _initialized;

  static SupabaseClient get client => Supabase.instance.client;

  static const String defaultUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://xyzcompany.supabase.co',
  );

  static const String defaultAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.dummy_anon_key',
  );

  static Future<void> initialize({
    String? url,
    String? anonKey,
  }) async {
    if (_initialized) return;

    final targetUrl = url ?? defaultUrl;
    final targetAnonKey = anonKey ?? defaultAnonKey;

    try {
      await Supabase.initialize(
        url: targetUrl,
        anonKey: targetAnonKey,
      );
      _initialized = true;
      developer.log(
        'Supabase initialized successfully ($targetUrl)',
        name: 'SupabaseService',
      );
    } catch (e, stack) {
      developer.log(
        'Supabase initialization warning (running in offline fallback mode): $e',
        name: 'SupabaseService',
        stackTrace: stack,
      );
      _initialized = false;
    }
  }
}
