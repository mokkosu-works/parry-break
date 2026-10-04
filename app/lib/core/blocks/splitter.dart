import '../entities/entities.dart';
import '../world/world.dart';
import 'block_behavior.dart';

/// 分裂ブロック。壊れると小ブロックを 3 個、下方に散らす。
class SplitterBlock extends BlockBehavior {
  const SplitterBlock();

  @override
  String get id => 'S';

  @override
  int get hp => 1;

  @override
  int basePoints(Block b, World w) => 250;

  @override
  void onDestroyed(World w, Block b, double cx, double cy) {
    for (var k = -1; k <= 1; k++) {
      final c = w.addBlock(SplitChildBlock.id_, b.x + b.w / 2 - 13 + k * 30, b.y + 6, 26, 14);
      c.fall = 34 + k.abs() * 10;
    }
  }
}

/// 分裂ブロックの子。崩落の支えには含めない。
class SplitChildBlock extends BlockBehavior {
  const SplitChildBlock();

  static const id_ = 's';

  @override
  String get id => id_;

  @override
  int get hp => 1;

  @override
  int basePoints(Block b, World w) => 80;

  @override
  bool get structural => false;
}
