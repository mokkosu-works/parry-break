import 'dart:math' as math;

import '../entities/entities.dart';
import '../events/game_event.dart';
import '../sim/geom.dart';
import '../world/world.dart';
import 'block_behavior.dart';

/// 貫通されず、1 ダメージずつ受けて反射するブロックの共通部分 (反射・磁力)。
abstract class ToughBlock extends BlockBehavior {
  const ToughBlock();

  @override
  int get hp => 3;

  @override
  int basePoints(Block b, World w) => 200;

  @override
  HitResult onBall(World w, Block b, BallHit hit) {
    w.damage(b, 1, hit.cause);
    return HitResult.bounce;
  }

  @override
  void onBlast(World w, Block b, {required bool breaker}) => w.damage(b, 2, DestroyCause.blast);

  @override
  bool onReturnedBullet(World w, Block b, Bullet u) {
    w.damage(b, 1, DestroyCause.bullet);
    return true;
  }
}

/// 反射ブロック。当たるとボールの角度が ±25〜45° ずれる (ラウンドごとの固定シード)。
class ReflectorBlock extends ToughBlock {
  const ReflectorBlock();

  @override
  String get id => 'R';

  @override
  void afterBounce(World w, Block b, Ball ball, double nx, double ny) {
    if (ball.phantom) return;
    final sg = w.rng.next() < 0.5 ? -1 : 1;
    final a = sg * (25 + w.rng.next() * 20) * deg;
    final c = math.cos(a), s = math.sin(a);
    var vx = ball.vx * c - ball.vy * s, vy = ball.vx * s + ball.vy * c;
    final dot = vx * nx + vy * ny;
    if (dot < 0) {
      vx -= 2 * dot * nx;
      vy -= 2 * dot * ny;
    }
    ball.vx = vx;
    ball.vy = vy;
  }
}

/// 磁力ブロック。半径内のボールを引き寄せる。
class MagnetBlock extends ToughBlock {
  const MagnetBlock();

  @override
  String get id => 'M';

  @override
  bool get influencesBalls => true;

  @override
  void influenceBall(World w, Block b, Ball ball, double dt) {
    final cx = b.x + w.form.ox + b.w / 2, cy = b.y + w.form.oy + b.h / 2;
    final dx = cx - ball.x, dy = cy - ball.y, d = hypot(dx, dy);
    if (d < w.tuning.magnetRadius && d > 1) {
      ball.vx += dx / d * w.tuning.magnetAccel * dt;
      ball.vy += dy / d * w.tuning.magnetAccel * dt;
    }
  }
}

