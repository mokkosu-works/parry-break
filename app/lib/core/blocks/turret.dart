import 'dart:math' as math;

import '../config/field.dart';
import '../entities/entities.dart';
import '../events/game_event.dart';
import '../sim/geom.dart';
import '../world/world.dart';
import 'block_behavior.dart';

/// 砲台。0.5 秒の予兆の後、パドルに向けて撃つ。
///
/// - W12 以降: パドルの移動先を予測して撃つ (予測移動量の 60%)
/// - W30〜39: 2 連射 / W40 以降: 3 方向弾 (ボスの砲台は単発)
class TurretBlock extends BlockBehavior {
  const TurretBlock();

  @override
  String get id => 'T';

  @override
  int get hp => 2;

  @override
  int basePoints(Block b, World w) => 400;

  @override
  void onDestroyed(World w, Block b, double cx, double cy) => w.killBulletsOf(b);

  /// 最初の発射までの時間をウェーブの固定シードでばらつかせる。
  @override
  void onWaveStart(World w, Block b) {
    final ti = w.tuning.turretInterval(w.wave.difficulty, w.wave.loopMul);
    b.fireT = 1.6 + ti * (0.3 + w.rng.next() * 1.2);
  }

  @override
  void update(World w, Block b, double dt) {
    final boss = w.boss;
    if (boss != null && boss.plunge) return;
    final difficulty = w.wave.difficulty;
    final interval = boss != null
        ? math.max(1.8, 3.6 - boss.index * 0.12) / w.wave.loopMul
        : w.tuning.turretInterval(difficulty, w.wave.loopMul);
    b.fireT -= dt;
    b.telegraph = b.fireT <= 0.5;
    if (b.fireT > 0) return;

    final p = w.paddle, pw = w.paddleWidth;
    final x = b.x + w.form.ox + b.w / 2, y = b.y + w.form.oy + b.h;
    final sp = w.tuning.bulletSpeed(difficulty, w.wave.loopMul);
    var tx = p.x;
    if (difficulty >= 12) {
      tx = clampD(p.x + p.vx * (hypot(p.x - x, Field.paddleY - y) / sp) * 0.6, pw / 2, Field.width - pw / 2);
    }
    final ang = math.atan2(Field.paddleY - y, tx - x);
    w.fireBullet(x, y, ang, sp, source: b);
    w.emit(const BulletFired());
    if (boss != null) {
      b.fireT = interval;
    } else if (difficulty >= 40) {
      w.fireBullet(x, y, ang - 15 * deg, sp, source: b);
      w.fireBullet(x, y, ang + 15 * deg, sp, source: b);
      b.fireT = interval;
    } else if (difficulty >= 30 && b.shots == 0) {
      b.shots = 1;
      b.fireT = 0.16;
    } else {
      b.shots = 0;
      b.fireT = interval;
    }
  }
}
