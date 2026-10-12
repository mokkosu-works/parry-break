import 'dart:math' as math;

import '../config/difficulty.dart';
import '../config/field.dart';
import '../entities/entities.dart';
import '../events/game_event.dart';
import '../sim/geom.dart';
import '../world/world.dart';
import 'block_behavior.dart';

/// 弾を撃つブロック (攻撃ブロック) の共通部分: 予兆 → 発射 → 間隔を空けて繰り返す。
///
/// 撃ち方は [fire] で決める。壊すと、そのブロックの飛行中の弾は消える。
/// 弾の数・頻度・速さは難易度で変わる (HARD は弾幕になる)。
abstract class GunBlock extends BlockBehavior {
  const GunBlock();

  @override
  int get hp => 2;

  @override
  int basePoints(Block b, World w) => 400;

  /// 発射前に赤く明滅する時間 (秒)。
  double get telegraphTime => 0.5;

  /// 発射間隔の、砲台 (T) に対する倍率。
  double get intervalScale => 1;

  @override
  void onDestroyed(World w, Block b, double cx, double cy) => w.killBulletsOf(b);

  /// 最初の発射までの時間をラウンドの固定シードでばらつかせる。
  @override
  void onWaveStart(World w, Block b) {
    final ti = w.tuning.turretInterval(w.wave.difficulty, w.wave.loopMul);
    b.fireT = 1.6 + ti * (0.3 + w.rng.next() * 1.2);
  }

  /// 次の斉射までの間隔 (秒)。ボス戦では要塞の砲台の間隔になる。
  double interval(World w) {
    final boss = w.boss;
    final base = boss != null
        ? math.max(1.8, 3.6 - boss.index * 0.12) / w.wave.loopMul
        : w.tuning.turretInterval(w.wave.difficulty, w.wave.loopMul);
    return base * intervalScale / w.difficulty.fireRate;
  }

  /// 敵弾の基準の速さ (px/秒)。
  double bulletSpeed(World w) =>
      w.tuning.bulletSpeed(w.wave.difficulty, w.wave.loopMul) * w.difficulty.bulletSpeed;

  /// パドルを狙う角度。[lead] はパドルの移動先を予測する割合 (0 なら今の位置)。
  double aimAtPaddle(World w, double x, double y, double sp, {double lead = 0}) {
    final p = w.paddle, pw = w.paddleWidth;
    var tx = p.x;
    if (lead > 0) {
      tx = clampD(p.x + p.vx * (hypot(p.x - x, Field.paddleY - y) / sp) * lead, pw / 2, Field.width - pw / 2);
    }
    return math.atan2(Field.paddleY - y, tx - x);
  }

  @override
  void update(World w, Block b, double dt) {
    final boss = w.boss;
    if (boss != null && boss.plunge) return;
    b.fireT -= dt;
    b.telegraph = b.fireT <= telegraphTime;
    if (b.telegraph) onTelegraph(w, b);
    if (b.fireT > 0) return;
    b.fireT = fire(w, b, b.x + w.form.ox + b.w / 2, b.y + w.form.oy + b.h);
  }

  /// 予兆の間、毎ステップ呼ばれる (狙いを付けるなど)。
  void onTelegraph(World w, Block b) {}

  /// 砲口 ([x], [y]) から撃つ。次に撃つまでの時間 (秒) を返す。
  double fire(World w, Block b, double x, double y);
}

/// 砲台。0.5 秒の予兆の後、パドルに向けて撃つ。
///
/// - R12 以降: パドルの移動先を予測して撃つ (予測移動量の 60%)
/// - R30〜39: 2 連射 / R40 以降: 3 方向弾 (ボスの砲台は単発)
/// - HARD: 3 方向弾 (R40 以降は 5 方向弾)
class TurretBlock extends GunBlock {
  const TurretBlock();

  @override
  String get id => 'T';

  @override
  double fire(World w, Block b, double x, double y) {
    final difficulty = w.wave.difficulty;
    final sp = bulletSpeed(w);
    final ang = aimAtPaddle(w, x, y, sp, lead: difficulty >= 12 ? 0.6 : 0);
    w.fireBullet(x, y, ang, sp, source: b);
    w.emit(const BulletFired());
    if (w.difficulty == Difficulty.hard) {
      final ways = difficulty >= 40 && w.boss == null ? 2 : 1;
      for (var k = 1; k <= ways; k++) {
        w.fireBullet(x, y, ang - k * 15 * deg, sp, source: b);
        w.fireBullet(x, y, ang + k * 15 * deg, sp, source: b);
      }
      return interval(w);
    }
    if (w.boss != null) return interval(w);
    if (difficulty >= 40) {
      w.fireBullet(x, y, ang - 15 * deg, sp, source: b);
      w.fireBullet(x, y, ang + 15 * deg, sp, source: b);
      return interval(w);
    }
    if (difficulty >= 30 && b.shots == 0) {
      b.shots = 1;
      return 0.16;
    }
    b.shots = 0;
    return interval(w);
  }
}

/// 拡散砲台。パドルへ向けて扇状に撃つ (EASY/NORMAL/HARD で 3/5/9 発)。
/// 同時に届くので、1 回のパリィでまとめて撃ち返せる。
class SpreadTurretBlock extends GunBlock {
  const SpreadTurretBlock();

  @override
  String get id => 'F';

  @override
  double get telegraphTime => 0.6;

  @override
  double get intervalScale => 1.35;

  @override
  double fire(World w, Block b, double x, double y) {
    final n = w.difficulty.pick(3, 5, 9);
    final spread = w.difficulty.pick(36, 56, 84) * deg;
    final sp = bulletSpeed(w) * 0.85;
    final ang = aimAtPaddle(w, x, y, sp);
    for (var i = 0; i < n; i++) {
      w.fireBullet(x, y, ang - spread / 2 + spread * i / (n - 1), sp, source: b);
    }
    w.emit(const BulletFired());
    return interval(w);
  }
}

/// 連射砲台。パドルを追いかけながら短い間隔で何発も撃つ (EASY/NORMAL/HARD で 3/5/8 発)。
class GatlingTurretBlock extends GunBlock {
  const GatlingTurretBlock();

  @override
  String get id => 'G';

  @override
  double get telegraphTime => 0.6;

  @override
  double get intervalScale => 1.6;

  @override
  double fire(World w, Block b, double x, double y) {
    final sp = bulletSpeed(w);
    w.fireBullet(x, y, aimAtPaddle(w, x, y, sp), sp, source: b);
    w.emit(const BulletFired());
    b.shots++;
    if (b.shots < w.difficulty.pick(3, 5, 8)) return w.difficulty.pick(0.14, 0.11, 0.085);
    b.shots = 0;
    return interval(w);
  }
}

/// 全方位砲台。輪の形に弾を撃ち、撃つたびに少し回す。HARD は輪を 2 重に撃つ。
class RingTurretBlock extends GunBlock {
  const RingTurretBlock();

  @override
  String get id => 'O';

  @override
  double get telegraphTime => 0.7;

  @override
  double get intervalScale => 1.5;

  @override
  double fire(World w, Block b, double x, double y) {
    final n = w.difficulty.pick(8, 12, 16);
    final sp = bulletSpeed(w) * (b.shots == 0 ? 0.7 : 0.85);
    final cy = y - b.h / 2;
    b.aim += b.shots == 0 ? 0.31 : math.pi / n;
    for (var i = 0; i < n; i++) {
      w.fireBullet(x, cy, b.aim + 2 * math.pi * i / n, sp, source: b);
    }
    w.emit(const BulletFired());
    if (w.difficulty == Difficulty.hard && b.shots == 0) {
      b.shots = 1;
      return 0.22;
    }
    b.shots = 0;
    return interval(w);
  }
}

/// 回転砲台。腕を回しながら弾を撒き続け (約 1.8 秒)、休む。
class SpiralTurretBlock extends GunBlock {
  const SpiralTurretBlock();

  @override
  String get id => 'Z';

  @override
  double get telegraphTime => 0.6;

  @override
  double get intervalScale => 1.3;

  static const double _burst = 1.8, _spin = 2.4;

  @override
  double fire(World w, Block b, double x, double y) {
    final step = w.difficulty.pick(0.3, 0.2, 0.1);
    final arms = w.difficulty.pick(2, 2, 3);
    final sp = bulletSpeed(w) * 0.75;
    final cy = y - b.h / 2;
    // 隣り合う回転砲台が同じ向きに回らないよう、置いた列で回す向きを変える
    final dir = (b.x / 60).round().isEven ? 1 : -1;
    for (var k = 0; k < arms; k++) {
      w.fireBullet(x, cy, b.aim + 2 * math.pi * k / arms, sp, source: b);
    }
    b.aim += dir * _spin * step;
    if (b.shots % 3 == 0) w.emit(const BulletFired());
    b.shots++;
    if (b.shots < (_burst / step).round()) return step;
    b.shots = 0;
    return interval(w);
  }
}

/// 狙撃砲台。長い予兆の間パドルに照準線を合わせ、発射の 0.25 秒前に固定して速い弾を撃つ。
/// HARD は固定した照準の左右にも 1 発ずつ撃つ。
class SniperTurretBlock extends GunBlock {
  const SniperTurretBlock();

  @override
  String get id => 'P';

  @override
  int basePoints(Block b, World w) => 500;

  @override
  double get telegraphTime => 1.1;

  @override
  double get intervalScale => 1.6;

  /// 発射のこの秒数前に照準を固定する。
  static const double lockTime = 0.25;

  double _speed(World w) => bulletSpeed(w) * w.difficulty.pick(1.6, 1.9, 1.9);

  @override
  void onTelegraph(World w, Block b) {
    if (b.fireT <= lockTime) return;
    final x = b.x + w.form.ox + b.w / 2, y = b.y + w.form.oy + b.h;
    b.aim = aimAtPaddle(w, x, y, _speed(w), lead: 0.5);
  }

  @override
  double fire(World w, Block b, double x, double y) {
    final sp = _speed(w);
    w.fireBullet(x, y, b.aim, sp, source: b);
    if (w.difficulty == Difficulty.hard) {
      w.fireBullet(x, y, b.aim - 7 * deg, sp, source: b);
      w.fireBullet(x, y, b.aim + 7 * deg, sp, source: b);
    }
    w.emit(const BulletFired());
    return interval(w);
  }
}
