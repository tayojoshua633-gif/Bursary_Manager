// lib/utils/active_session_term_notifier.dart
import 'package:flutter/foundation.dart';

/// Fires whenever the active session/term changes, so every visible
/// indicator (home screen strip, sidebar header, ...) can refresh
/// immediately — even when the screen that made the change sits in the same
/// route as the indicator (no push/pop to hook a reload onto).
class ActiveSessionTermNotifier {
  ActiveSessionTermNotifier._();

  static final ValueNotifier<int> _tick = ValueNotifier<int>(0);

  static Listenable get listenable => _tick;

  static void notifyChanged() {
    _tick.value++;
  }
}
