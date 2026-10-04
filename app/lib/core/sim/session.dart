import 'dart:math' as math;

import '../events/game_event.dart';
import '../world/world.dart';

/// 実時間でシミュレーションを進める (60Hz 固定ステップ + ヒットストップ + スローモーション)。
///
/// 描画側は毎フレーム [advance] を呼び、返ってきたイベントで演出・音・振動を出す。
/// [alpha] はステップ間の補間に使う (高リフレッシュレートの画面で滑らかに描くため)。
class Session {
  Session(this.world, {this.onStep});

  final World world;

  /// シミュレーションが 1 ステップ進むたびに呼ばれる (演出をステップ単位で進めるため)。
  final void Function(double dt)? onStep;
  double? _last;
  double _acc = 0;
  bool _paused = false;

  bool get paused => _paused;

  /// 直前のステップから次のステップまでの進み具合 (0〜1)。
  double get alpha => _acc / World.dt;

  /// [now] (秒) まで進め、その間に起きたイベントを返す。
  List<GameEvent> advance(double now) {
    if (_paused) return const [];
    final w = world;
    final last = _last ?? now;
    _last = now;
    final rdt = math.min(0.1, math.max(0.0, now - last));
    var scale = 1.0;
    if (w.slowmo > 0) {
      scale = 0.35;
      w.slowmo -= rdt;
    }
    _acc += rdt * scale;
    while (_acc >= World.dt) {
      _acc -= World.dt;
      if (w.hitstop > 0) {
        w.hitstop -= World.dt;
        continue;
      }
      w.step(World.dt);
      onStep?.call(World.dt);
    }
    w.sync
      ..wall = now
      ..sim = w.t + (w.hitstop > 0 ? 0 : _acc)
      ..scale = scale;
    return w.drainEvents();
  }

  void pause() {
    if (_paused) return;
    _paused = true;
    world.clearActions();
  }

  void resume() {
    if (!_paused) return;
    _paused = false;
    _last = null;
    _acc = 0;
    world.clearActions();
  }
}
