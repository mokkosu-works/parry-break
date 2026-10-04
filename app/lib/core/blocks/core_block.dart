import '../entities/entities.dart';
import '../events/game_event.dart';
import '../world/world.dart';
import 'block_behavior.dart';

/// ボスのコア。貫通弾・赤い撃ち返し弾・爆風・分身弾でダメージを受ける。崩落の支点になる。
/// HP はボスの定義で決まる。
class CoreBlock extends BlockBehavior {
  const CoreBlock();

  @override
  String get id => 'C';

  @override
  int get hp => 1;

  @override
  int basePoints(Block b, World w) => 0;

  @override
  bool get clearable => false;

  @override
  bool get anchor => true;

  @override
  HitResult onBall(World w, Block b, BallHit hit) {
    final ball = hit.ball;
    if (ball.phantom) {
      w.damageCore(b, 1);
      ball.life = 0; // 分身弾はコアに当たると消える
    } else if (hit.pierce) {
      w.damageCore(b, 1);
      w.consumePierce(hit);
    } else {
      w.deflect(b);
      w.emit(Popup(ball.x, ball.y - 14, 'NO DAMAGE', PopupKind.noDamage));
    }
    return HitResult.bounce;
  }

  @override
  void onBlast(World w, Block b, {required bool breaker}) => w.damageCore(b, breaker ? 2 : 1);

  @override
  bool onReturnedBullet(World w, Block b, Bullet u) {
    if (u.red) {
      w.damageCore(b, 1);
    } else {
      w.deflect(b);
    }
    return true;
  }
}
