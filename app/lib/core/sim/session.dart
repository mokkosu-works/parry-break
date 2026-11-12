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
  /// スローモーション中の速さ (実時間 1 秒あたりに進むシミュレーション時間)。
  static const slowScale = 0.35;

  /// 浮動小数の誤差で、ステップの境目に届かないまま止まらないための余裕。
  static const _eps = 1e-9;

  double? _last;
  double _acc = 0;
  bool _paused = false;

  bool get paused => _paused;

  /// 直前のステップから次のステップまでの進み具合 (0〜1)。
  double get alpha => _acc / World.dt;

  /// [now] (秒) まで進め、その間に起きたイベントを返す。
  ///
  /// ヒットストップとスローモーションはどちらも実時間で数える。ヒットストップの間は止まり、
  /// スローモーションはヒットストップが明けてから ×[slowScale] で進む (重なっても両方が指定の時間だけ見える)。
  List<GameEvent> advance(double now) {
    if (_paused) return const [];
    final w = world;
    final last = _last ?? now;
    _last = now;
    var rem = math.min(0.1, math.max(0.0, now - last));
    while (rem > 0) {
      if (w.hitstop > 0) {
        final d = math.min(rem, w.hitstop);
        w.hitstop -= d;
        rem -= d;
        continue;
      }
      final slow = w.slowmo > 0;
      final scale = slow ? slowScale : 1.0;
      // 次のステップまで、またはスローモーションが明けるまで、の短いほう
      var d = math.min(rem, (World.dt - _acc) / scale);
      if (slow) d = math.min(d, w.slowmo);
      _acc += d * scale;
      rem -= d;
      if (slow) w.slowmo -= d;
      if (_acc >= World.dt - _eps) {
        _acc = math.max(0.0, _acc - World.dt);
        w.step(World.dt);
        onStep?.call(World.dt);
      }
    }
    if (w.hitstop < _eps) w.hitstop = 0;
    if (w.slowmo < _eps) w.slowmo = 0;
    final slow = w.slowmo > 0;
    w.sync
      ..wall = now
      ..sim = w.t + _acc
      ..hold = w.hitstop
      ..scale = slow ? slowScale : 1
      ..slow = slow ? w.slowmo : double.infinity;
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
