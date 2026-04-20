import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Service for managing app sound effects
class SoundService {
  static final SoundService _instance = SoundService._internal();
  
  static SoundService get instance => _instance;
  
  late final AudioPlayer _clickPlayer;
  bool _initialized = false;

  SoundService._internal();

  /// Initialize the sound service
  /// Call this once during app startup
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      _clickPlayer = AudioPlayer();
      // Set release mode to keep the player alive
      await _clickPlayer.setReleaseMode(ReleaseMode.release);
      _initialized = true;
    } catch (e) {
      if (kDebugMode) {
        print('Error initializing SoundService: $e');
      }
    }
  }

  /// Play click sound with error handling
  /// Returns true if successful, false if failed
  Future<bool> playClickSound({double volume = 0.5}) async {
    if (!_initialized) {
      await initialize();
    }

    try {
      await _clickPlayer.stop();
      await _clickPlayer.play(
        AssetSource('sounds/click.mp3'),
        volume: volume,
      );
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Error playing click sound: $e');
      }
      // Return false but don't throw - allow UI to continue
      return false;
    }
  }

  /// Dispose of audio resources
  Future<void> dispose() async {
    try {
      await _clickPlayer.dispose();
      _initialized = false;
    } catch (e) {
      if (kDebugMode) {
        print('Error disposing SoundService: $e');
      }
    }
  }
}
