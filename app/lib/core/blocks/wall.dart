import '../entities/entities.dart';
import '../events/game_event.dart';
import '../world/world.dart';
import 'block_behavior.dart';

/// 破壊不可ブロック。OVERDRIVE 中だけ壊せる。クリア条件・崩落の支えには含めない。
class WallBlock extends BlockBehavior {
  const WallBlock();

  @override
  String get id => '#';

  @override
  int get hp => 1;

  @override
  int basePoints(Block b, World w) => 500;

  @override
  bool get clearable => false;

  @override
  bool get structural => false;

  @override
  HitResult onBall(World w, Block b, BallHit hit) {
    if (w.od) {
      w.destroyBlock(b, hit.cause);
      return HitResult.pass;
    }
    w.deflect(b);
    return HitResult.bounce;
  }

  @override
  void onBlast(World w, Block b, {required bool breaker}) {
    if (w.od) {
      w.destroyBlock(b, DestroyCause.blast);
    } else {
      b.flash = 0.08;
    }
  }

  @override
  bool onReturnedBullet(World w, Block b, Bullet u) {
    w.deflect(b);
    return true;
  }
}
