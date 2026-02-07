import 'package:shared_preferences/shared_preferences.dart';

/// Helper class to track navigation state for activity recreation recovery.
/// When Android destroys the Flutter activity (e.g., when camera opens),
/// this helps restore the user to their previous location.
class NavigationState {
  static const String _key = 'pending_navigation_state';
  static const String _userDataKey = 'pending_navigation_user_data';

  /// Save the current navigation state (e.g., 'marketing')
  static Future<void> saveState(String state,
      {Map<String, String>? userData}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, state);
    if (userData != null) {
      // Store user data as simple key-value pairs
      final userDataStr =
          userData.entries.map((e) => '${e.key}=${e.value}').join('|');
      await prefs.setString(_userDataKey, userDataStr);
    }
  }

  /// Get the pending navigation state (returns null if none)
  static Future<String?> getState() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  /// Get saved user data for navigation restoration
  static Future<Map<String, String>?> getUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString(_userDataKey);
    if (str == null || str.isEmpty) return null;

    final map = <String, String>{};
    for (final pair in str.split('|')) {
      final parts = pair.split('=');
      if (parts.length == 2) {
        map[parts[0]] = parts[1];
      }
    }
    return map.isEmpty ? null : map;
  }

  /// Clear the pending navigation state (call after successful restoration or form submission)
  static Future<void> clearState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    await prefs.remove(_userDataKey);
  }
}
