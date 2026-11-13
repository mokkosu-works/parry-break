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
    this.bullets, {
    this.round = 1,
    this.itemsSpawned = 0,
    this.itemsTaken = 0,
    this.itemsParried = 0,
  });
  final bool cleared;
  final int hurt;
  final double time;
  final String reason;
  final int score;

  /// 1 秒あたりに撃たれた敵弾の平均。
  final double bullets;

  /// 最後にいたラウンド (エンドレスの到達ラウンド)。
  final int round;

  /// 出たアイテム・取ったアイテム・そのうちパリィ取得の数。
  final int itemsSpawned, itemsTaken, itemsParried;
}

/// [inner] と同じ中身で、アイテム (design.md 7.10) だけを出さないモード。
/// アイテムの抽選はほかの乱数を引かないので、アイテムを足す前と同じ展開になる (前後の比較に使う)。
class NoItemsMode extends GameMode {
  const NoItemsMode(this.inner);
  final GameMode inner;

  @override
  String get recordKey => inner.recordKey;

  @override
  RoundSpec? roundAt(int number) =>
      inner.roundAt(number)?.copyWith(items: false);
}

/// 出たアイテムを、その場でパドルの真上に移す (次のステップで通常取得になる)。
/// 「落ちてきたアイテムを全部、危険なしに取れた」場合の上限を見るのに使う。
void grabItems(World w) {
  for (var i = 0; i < w.items.length; i++) {
    final it = w.items[i];
    if (it.contact != null || it.x == w.paddle.x) continue;
    w.items[i] = Item(
      it.kind,
      w.paddle.x,
      Field.paddleY - w.tuning.itemHeight / 2 - 1,
    );
  }
}

/// [mode] を [difficulty] で最後まで (最大 [limit] 秒) 遊ぶ。[grab] なら出たアイテムを全部取る ([grabItems])。
RunResult playOut(
  GameMode mode,
  Difficulty difficulty, {
  int seed = 1,
  double sigma = 0.035,
  double limit = 400,
  bool grab = false,
}) {
  final w = World(mode: mode, difficulty: difficulty, inputLag: 0)..start();
  w.sync
    ..wall = 0
    ..sim = 0
    ..scale = 1;
  final bot = Bot(w, seed: seed, sigma: sigma);
  final seen = <Bullet>{};
  var fired = 0, spawned = 0, taken = 0, parried = 0;
  final n = (limit / World.dt).round();
  for (var i = 0; i < n; i++) {
    bot();
    if (grab) grabItems(w);
    w.step(World.dt);
    for (final u in w.bullets) {
      if (u.hostile && seen.add(u)) fired++;
    }
    for (final e in w.drainEvents()) {
      if (e is ItemSpawned) spawned++;
      if (e is ItemTaken) {
        taken++;
        if (e.parried) parried++;
      }
    }
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
    round: w.round.number,
    itemsSpawned: spawned,
    itemsTaken: taken,
    itemsParried: parried,
  );
}
