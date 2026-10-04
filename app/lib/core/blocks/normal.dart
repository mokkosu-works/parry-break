import '../config/field.dart';
import '../entities/entities.dart';
import '../world/world.dart';
import 'block_behavior.dart';

/// 通常ブロック。下段ほど高得点 (落下ラインに近く危険なため)。
class NormalBlock extends BlockBehavior {
  const NormalBlock();

  @override
  String get id => 'N';

  @override
  int get hp => 1;

  @override
  int basePoints(Block b, World w) => const [100, 150, 300][tierOf(b, w)];

  /// 高さの段 (0: 上段 / 1: 中段 / 2: 下段)。
  static int tierOf(Block b, World w) {
    final d = Field.warnY - (b.y + w.form.oy + b.h / 2);
    return d < 140 ? 2 : d < 280 ? 1 : 0;
  }
}
