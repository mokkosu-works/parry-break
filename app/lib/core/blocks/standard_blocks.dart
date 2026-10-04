import 'block_behavior.dart';
import 'core_block.dart';
import 'explosive.dart';
import 'keystone.dart';
import 'mirror.dart';
import 'normal.dart';
import 'reflector.dart';
import 'splitter.dart';
import 'turret.dart';
import 'wall.dart';

/// 標準のブロック一式を登録した登録簿。新しいブロックはここに追加する。
BlockRegistry standardBlocks() => BlockRegistry(const [
      NormalBlock(),
      TurretBlock(),
      ReflectorBlock(),
      MagnetBlock(),
      SplitterBlock(),
      SplitChildBlock(),
      MirrorBlock(),
      WallBlock(),
      KeystoneBlock(),
      ExplosiveBlock(),
      CoreBlock(),
    ]);
