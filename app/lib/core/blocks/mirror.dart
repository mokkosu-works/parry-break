import 'dart:math' as math;

import '../config/field.dart';
import '../entities/entities.dart';
import '../events/game_event.dart';
import '../world/world.dart';
import 'block_behavior.dart';

/// 鏡面ブロック。撃ち返し弾をパドルへ跳ね返す。貫通弾・ブレイカー・OVERDRIVE でのみ壊れる。
class MirrorBlock extends BlockBehavior {
  const MirrorBlock();

  @override
  String get id => 'X';

  @override
  int get hp => 1;

  @override
  int basePoints(Block b, World w) => 350;

  @override
  bool get clearable => false;

  @override
  HitResult onBall(World w, Block b, BallHit hit) {
    if (hit.pierce) {
      w.destroyBlock(b, hit.cause);
      w.consumePierce(hit);
    } else {
      w.deflect(b);
    }
    return HitResult.bounce;
  }

  @override
  void onBlast(World w, Block b, {required bool breaker}) {
    if (breaker || w.od) {
      w.destroyBlock(b, DestroyCause.blast);
    } else {
      b.flash = 0.1;
    }
  }

  @override
  bool onReturnedBullet(World w, Block b, Bullet u) {
    u
      ..hostile = true
      ..red = false
      ..source = null
      ..near = false
      ..nearMissed = false
      ..y = b.y + w.form.oy + b.h + u.r + 1;
    final a = math.atan2(Field.paddleY - u.y, w.paddle.x - u.x), sp = w.tuning.mirrorReturnSpeed * w.round.loopMul;
    u
      ..vx = math.cos(a) * sp
      ..vy = math.sin(a) * sp;
    b.flash = 0.1;
    w.emit(const BulletMirrored());
    return false;
  }
}
