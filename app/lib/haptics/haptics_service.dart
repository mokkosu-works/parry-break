import 'dart:async';

import 'package:flutter/services.dart';

import '../core/core.dart';

enum _Pulse { light, medium, heavy, long }

/// 振動 (design.md 第9章)。コアのイベントを端末の触覚フィードバックのパターンにする。
class HapticsService {
  bool enabled = true;
  final List<Timer> _timers = [];

  /// [pattern] は (開始までのミリ秒, 強さ) の並び。新しいパターンは前のものを打ち切る。
  void _play(List<(int, _Pulse)> pattern) {
    if (!enabled) return;
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    for (final (ms, p) in pattern) {
      if (ms == 0) {
        _fire(p);
      } else {
        _timers.add(Timer(Duration(milliseconds: ms), () => _fire(p)));
      }
    }
  }

  void _fire(_Pulse p) {
    switch (p) {
      case _Pulse.light:
        HapticFeedback.lightImpact();
      case _Pulse.medium:
        HapticFeedback.mediumImpact();
      case _Pulse.heavy:
        HapticFeedback.heavyImpact();
      case _Pulse.long:
        HapticFeedback.vibrate();
    }
  }

  void handle(GameEvent e) {
    switch (e) {
      case ParrySucceeded(:final grade):
        _play(switch (grade) {
          ParryGrade.good => const [(0, _Pulse.light)],
          ParryGrade.perfect => const [(0, _Pulse.medium)],
          ParryGrade.just => const [(0, _Pulse.heavy), (60, _Pulse.heavy), (120, _Pulse.heavy)],
        });
      case PlayerHurt():
        _play(const [(0, _Pulse.long)]);
      case CollapseStarted(:final count) when count >= 14:
        _play(const [(0, _Pulse.medium), (80, _Pulse.medium)]);
      case BreakerTriggered():
        _play(const [(0, _Pulse.heavy), (50, _Pulse.medium)]);
      case CoreDestroyed():
        _play(const [(0, _Pulse.heavy), (100, _Pulse.heavy), (200, _Pulse.heavy)]);
      case OverdriveStarted():
        _play(const [(0, _Pulse.heavy), (70, _Pulse.medium), (140, _Pulse.light)]);
      case GameOver():
        _play(const [(0, _Pulse.long), (150, _Pulse.long), (300, _Pulse.heavy)]);
      default:
        break;
    }
  }

  void selection() {
    if (enabled) HapticFeedback.selectionClick();
  }
}
