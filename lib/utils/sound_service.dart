// lib/utils/sound_service.dart
//
// Centralized UI sound effects (click, popup, success, warning, app open/close).
// Sounds are ON by default; users can mute them from Preferences > Sound Effects.

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppSound { click, popup, success, warning, appOpen, appClose }

extension on AppSound {
  String get assetPath {
    switch (this) {
      case AppSound.click:
        return 'sounds/click.wav';
      case AppSound.popup:
        return 'sounds/popup.wav';
      case AppSound.success:
        return 'sounds/success.wav';
      case AppSound.warning:
        return 'sounds/warning.wav';
      case AppSound.appOpen:
        return 'sounds/app_open.wav';
      case AppSound.appClose:
        return 'sounds/app_close.wav';
    }
  }
}

class SoundService {
  SoundService._();
  static final SoundService instance = SoundService._();

  static const String _enabledKey = 'sound_effects_enabled';

  bool _enabled = true;
  bool _initialized = false;

  // A small pool of players lets overlapping sounds (e.g. rapid clicks) play
  // on top of each other instead of being cut off by a single shared player.
  final List<AudioPlayer> _pool = List.generate(4, (_) => AudioPlayer()
    ..setPlayerMode(PlayerMode.lowLatency)
    ..setReleaseMode(ReleaseMode.stop));
  int _nextPlayer = 0;

  bool get isEnabled => _enabled;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_enabledKey) ?? true;
    } catch (e) {
      debugPrint('⚠️ SoundService: failed to load preference: $e');
    }
  }

  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enabledKey, enabled);
    } catch (e) {
      debugPrint('⚠️ SoundService: failed to save preference: $e');
    }
  }

  Future<void> _play(AppSound sound) async {
    if (!_enabled) return;
    try {
      final player = _pool[_nextPlayer];
      _nextPlayer = (_nextPlayer + 1) % _pool.length;
      await player.stop();
      await player.play(AssetSource(sound.assetPath));
    } catch (e) {
      debugPrint('⚠️ SoundService: failed to play ${sound.name}: $e');
    }
  }

  Future<void> playClick() => _play(AppSound.click);
  Future<void> playPopup() => _play(AppSound.popup);
  Future<void> playSuccess() => _play(AppSound.success);
  Future<void> playWarning() => _play(AppSound.warning);
  Future<void> playAppOpen() => _play(AppSound.appOpen);
  Future<void> playAppClose() => _play(AppSound.appClose);

  Future<void> dispose() async {
    for (final p in _pool) {
      await p.dispose();
    }
  }
}
