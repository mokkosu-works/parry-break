import 'dart:math' as math;

import 'package:parry_break/core/core.dart';
import 'package:parry_break/game/autoplay_bot.dart';

export 'package:parry_break/game/autoplay_bot.dart' show Bot;

class RunResult {
  RunResult(
    this.cleared,
    this.hurt,
    this.time,
    this.reason,
    this.score,
    this.bullets,
  );
  final bool cleared;
  final int hurt;
  final double time;
  final String reason;
  final int score;

  /// 1 秒あたりに撃たれた敵弾の平均。
  final double bullets;
}

/// [mode] を [difficulty] で最後まで (最大 [limit] 秒) 遊ぶ。
RunResult playOut(
  GameMode mode,
  Difficulty difficulty, {
  int seed = 1,
  double sigma = 0.035,
  double limit = 400,
}) {
  final w = World(mode: mode, difficulty: difficulty, inputLag: 0)..start();
  w.sync
    ..wall = 0
    ..sim = 0
    ..scale = 1;
  final bot = Bot(w, seed: seed, sigma: sigma);
  final seen = <Bullet>{};
  var fired = 0;
  final n = (limit / World.dt).round();
  for (var i = 0; i < n; i++) {
    bot();
    w.step(World.dt);
    for (final u in w.bullets) {
      if (u.hostile && seen.add(u)) fired++;
    }
    w.drainEvents();
    if (w.phase == WorldPhase.over || w.phase == WorldPhase.completed) break;
  }
  final cleared = w.phase == WorldPhase.completed;
  return RunResult(
    cleared,
    w.stats.hurt,
    w.stats.playTime,
    cleared ? 'CLEAR' : w.overReason,
    w.score,
    fired / math.max(1, w.stats.playTime),
  );
}
