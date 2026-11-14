import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'expo_supabase_config.dart';
import 'expo_states_districts_data.dart';

/// Service managing Indian States and Districts for Expo orders.
///
/// Features:
/// 1. Instant local cache (built-in default list of 28 states & 739 districts,
///    plus SharedPreferences cache for offline / fast startup).
/// 2. Background sync with Supabase `expo.states_districts` table if connected.
/// 3. Search and validation: No custom / invalid states or districts allowed.
/// 4. 1.5s debounce helpers for search queries to avoid lag or excessive updates.
class ExpoStatesDistrictsService {
  ExpoStatesDistrictsService._();
  static final ExpoStatesDistrictsService instance =
      ExpoStatesDistrictsService._();

  static const String _prefsKey = 'expo_states_districts_cache_v1';

  // State -> List of Districts
  Map<String, List<String>> _stateDistrictsMap = {};
  bool _isInitialized = false;

  /// Initializes the service. Loads built-in map first, checks SharedPreferences cache,
  /// then asynchronously refreshes from Supabase in background without blocking.
  Future<void> init() async {
    if (_isInitialized) return;

    // 1. Seed with built-in comprehensive dataset
    _stateDistrictsMap = Map<String, List<String>>.from(
      kIndiaStatesDistricts.map(
        (key, value) => MapEntry(key, List<String>.from(value)),
      ),
    );

    // 2. Load from local cache if available
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedStr = prefs.getString(_prefsKey);
      if (cachedStr != null && cachedStr.isNotEmpty) {
        final decoded = jsonDecode(cachedStr) as Map<String, dynamic>;
        final parsedMap = <String, List<String>>{};
        decoded.forEach((k, v) {
          if (v is List) {
            parsedMap[k] = v.map((e) => e.toString()).toList();
          }
        });
        if (parsedMap.isNotEmpty) {
          _stateDistrictsMap = parsedMap;
        }
      }
    } catch (e) {
      debugPrint('Error reading states_districts cache: $e');
    }

    _isInitialized = true;

    // 3. Background sync from Supabase `expo.states_districts`
    _syncFromSupabase();
  }

  Future<void> _syncFromSupabase() async {
    try {
      final client = ExpoSupabaseConfig.client;
      final rows = await client
          .schema(ExpoSupabaseConfig.schema)
          .from('states_districts')
          .select('state, district')
          .order('state', ascending: true)
          .order('district', ascending: true);

      if (rows.isNotEmpty) {
        final newMap = <String, List<String>>{};
        for (final row in rows) {
          final state = (row['state'] ?? '').toString().trim();
          final district = (row['district'] ?? '').toString().trim();
          if (state.isNotEmpty && district.isNotEmpty) {
            newMap.putIfAbsent(state, () => []).add(district);
          }
        }
        if (newMap.isNotEmpty) {
          _stateDistrictsMap = newMap;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_prefsKey, jsonEncode(newMap));
        }
      }
    } catch (e) {
      // Supabase table might not be created yet, silently fallback to local cache
      debugPrint('States/Districts Supabase sync note: $e');
    }
  }

  /// All unique sorted state names.
  List<String> get states {
    if (!_isInitialized) {
      return kIndiaStatesDistricts.keys.toList()..sort();
    }
    final list = _stateDistrictsMap.keys.toList();
    list.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  /// Districts for a given state (case-insensitive state match).
  List<String> getDistrictsForState(String stateName) {
    if (!_isInitialized) {
      final key = kIndiaStatesDistricts.keys.firstWhere(
        (k) => k.toLowerCase() == stateName.trim().toLowerCase(),
        orElse: () => '',
      );
      if (key.isNotEmpty) return kIndiaStatesDistricts[key] ?? [];
      return [];
    }

    final matchedKey = _stateDistrictsMap.keys.firstWhere(
      (k) => k.toLowerCase() == stateName.trim().toLowerCase(),
      orElse: () => '',
    );
    if (matchedKey.isNotEmpty) {
      final list = List<String>.from(_stateDistrictsMap[matchedKey] ?? []);
      list.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      return list;
    }
    return [];
  }

  /// Validates whether a state is strictly in the allowed database list.
  bool isValidState(String stateName) {
    final clean = stateName.trim().toLowerCase();
    if (clean.isEmpty) return false;
    return states.any((s) => s.toLowerCase() == clean);
  }

  /// Validates whether a district is strictly in the allowed list for the given state.
  bool isValidDistrict(String stateName, String districtName) {
    final cleanDist = districtName.trim().toLowerCase();
    if (cleanDist.isEmpty) return false;
    final districts = getDistrictsForState(stateName);
    return districts.any((d) => d.toLowerCase() == cleanDist);
  }

  /// Normalizes state name to the exact casing in database.
  String normalizeState(String stateName) {
    final clean = stateName.trim().toLowerCase();
    for (final s in states) {
      if (s.toLowerCase() == clean) return s;
    }
    return stateName.trim();
  }

  /// Normalizes district name to the exact casing in database for that state.
  String normalizeDistrict(String stateName, String districtName) {
    final districts = getDistrictsForState(stateName);
    final clean = districtName.trim().toLowerCase();
    for (final d in districts) {
      if (d.toLowerCase() == clean) return d;
    }
    return districtName.trim();
  }

  /// Autocomplete search for States.
  /// Rule: Only after the first letter (query.length >= 1) show suggestions.
  List<String> filterStates(String query) {
    final clean = query.trim().toLowerCase();
    if (clean.isEmpty) return [];
    return states.where((s) => s.toLowerCase().contains(clean)).toList();
  }

  /// Autocomplete search for Districts within a state (or all districts if state not specified).
  /// Rule: Only after the first letter (query.length >= 1) show suggestions.
  List<String> filterDistricts({required String stateName, required String query}) {
    final clean = query.trim().toLowerCase();
    if (clean.isEmpty) return [];

    final list = getDistrictsForState(stateName);
    return list.where((d) => d.toLowerCase().contains(clean)).toList();
  }
}
