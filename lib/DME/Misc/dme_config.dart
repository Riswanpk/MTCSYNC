import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// DME Configuration
/// Replace the placeholders with your actual Supabase project URL and publishable API key.
class DmeConfig {
  /// Supabase Project URL (e.g., https://xyzcompany.supabase.co)
  static const String supabaseUrl = 'https://gvhvwauaodugfpwanfou.supabase.co';

  /// Supabase Publishable / Anon API Key
  static const String supabaseAnonKey = 'sb_publishable_wiAL_7zuWwyCN5LbkJFuig_QNsDUt_l';

  /// Supabase Service Role Key (if needed for admin operations, keep secure!)
  static const String supabaseServiceRoleKey = '';

  /// Whether Supabase credentials are configured
  static bool get isConfigured =>
      supabaseUrl.isNotEmpty &&
      supabaseUrl != 'YOUR_SUPABASE_URL_HERE' &&
      supabaseAnonKey.isNotEmpty &&
      supabaseAnonKey != 'YOUR_SUPABASE_ANON_KEY_HERE';

  /// Safely ensures Supabase is initialized and returns the client instance
  static Future<SupabaseClient?> getClient() async {
    if (!isConfigured) return null;
    try {
      return Supabase.instance.client;
    } catch (_) {
      try {
        await Supabase.initialize(
          url: supabaseUrl,
          anonKey: supabaseAnonKey,
        );
        return Supabase.instance.client;
      } catch (e) {
        debugPrint('DmeConfig: Failed to initialize Supabase client: $e');
        return null;
      }
    }
  }

  /// Synchronous getter with fallback catch
  static SupabaseClient? get client {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }
}
