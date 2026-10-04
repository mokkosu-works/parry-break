import '../entities/entities.dart';
import '../events/game_event.dart';
import '../world/world.dart';
import 'block_behavior.dart';

/// 要石。崩落の支点になり、壊すとつながっていた塊が崩れ落ちる。
class KeystoneBlock extends BlockBehavior {
  const KeystoneBlock();

  @override
  String get id => 'K';

  @override
  int get hp => 3;

  @override
  int basePoints(Block b, World w) => 500;

  @override
  bool get anchor => true;

  @override
  void onDestroyed(World w, Block b, double cx, double cy) => w.emit(KeystoneBroken(cx, cy));
}
