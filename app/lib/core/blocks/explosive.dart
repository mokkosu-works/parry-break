import '../entities/entities.dart';
import '../world/world.dart';
import 'block_behavior.dart';

/// 爆薬。壊れると 0.07 秒後に周囲を爆破し、範囲内の爆薬に誘爆する。
class ExplosiveBlock extends BlockBehavior {
  const ExplosiveBlock();

  @override
  String get id => 'B';

  @override
  int get hp => 1;

  @override
  int basePoints(Block b, World w) => 300;

  @override
  void onDestroyed(World w, Block b, double cx, double cy) =>
      w.queueBlast(cx, cy, 0.07, w.tuning.blastRadius, shrapnel: true, kind: BlastKind.bomb);

  /// 崩落した爆薬は落下と同時に爆発する。
  @override
  void onFell(World w, Block b, double cx, double cy) =>
      w.queueBlast(cx, cy, 0.12, w.tuning.blastRadius, shrapnel: true, kind: BlastKind.bomb);
}
