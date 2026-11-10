import 'package:supabase_flutter/supabase_flutter.dart';
import '../DME/Misc/dme_config.dart';

/// Configuration for the Expo module in Supabase.
///
/// Uses the existing Supabase instance (configured in [DmeConfig]) and
/// isolates all Expo tables inside the dedicated Postgres schema `expo`.
class ExpoSupabaseConfig {
  ExpoSupabaseConfig._();

  /// Postgres schema dedicated for Expo tables
  static const String schema = 'expo';

  /// Storage bucket used for item photos and payment proofs
  static const String storageBucket = 'expo';

  /// Supabase Client instance from DmeConfig
  static SupabaseClient get client {
    final client = DmeConfig.client;
    if (client != null) return client;

    // Fallback if DmeConfig.client wasn't initialized yet
    return SupabaseClient(
      DmeConfig.supabaseUrl,
      DmeConfig.supabaseAnonKey,
    );
  }
}
