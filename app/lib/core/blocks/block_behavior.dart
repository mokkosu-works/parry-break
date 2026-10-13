import '../entities/entities.dart';
import '../events/game_event.dart';
import '../world/world.dart';

enum HitResult {
  /// 貫通した (ボールは向きを変えずに進む)。
  pass,

  /// 跳ね返った。
  bounce,
}

/// ボールがブロックに当たったときの状況。
class BallHit {
  const BallHit(this.ball, {required this.pierce, required this.main, required this.cause});
  final Ball ball;

  /// 貫通弾として当たったか (貫通回数が残っている / FEVER TIME 中 / 分身弾)。
  final bool pierce;

  /// メインのボールか (分身弾なら false)。
  final bool main;
  final DestroyCause cause;
}

/// ブロックの種類ごとの振る舞い。
///
/// 新しいブロックを追加するときは、これを実装して [BlockRegistry] に登録する。
/// 既定の実装は「通常ブロック」の振る舞い (貫通弾なら壊れて貫通、それ以外は 1 ダメージで反射、
/// 爆風・撃ち返し弾で壊れる) になっている。
abstract class BlockBehavior {
  const BlockBehavior();

  /// ステージデータの配置で使う識別子 (1 文字)。
  String get id;

  int get hp;

  /// 壊したときの基本点。
  int basePoints(Block b, World w);

  /// ラウンドのクリア条件 (全消し) に含むか。
  bool get clearable => true;

  /// 崩落の支え合いに含むか。
  bool get structural => true;

  /// 崩落の支点か (要石・ボスのコア)。
  bool get anchor => false;

  /// ボールが当たった。
  HitResult onBall(World w, Block b, BallHit hit) {
    if (hit.pierce) {
      w.destroyBlock(b, hit.cause);
      w.consumePierce(hit);
      return HitResult.pass;
    }
    w.damage(b, 1, hit.cause);
    return HitResult.bounce;
  }

  /// ボールが跳ね返った後に呼ばれる ([nx], [ny] は当たった面の法線)。
  void afterBounce(World w, Block b, Ball ball, double nx, double ny) {}

  /// 爆風・衝撃波を受けた。[breaker] は JUST パリィの衝撃波。
  void onBlast(World w, Block b, {required bool breaker}) => w.destroyBlock(b, DestroyCause.blast);

  /// 撃ち返し弾が当たった。弾が消えるなら true を返す。
  bool onReturnedBullet(World w, Block b, Bullet u) {
    w.destroyBlock(b, DestroyCause.bullet);
    return true;
  }

  /// 壊れた直後に呼ばれる (誘爆・分裂など)。
  void onDestroyed(World w, Block b, double cx, double cy) {}

  /// ラウンド開始時に、配置の順番で呼ばれる (砲台の初期タイマーなど)。
  void onRoundStart(World w, Block b) {}

  /// 崩落して落ち始めた (得点の加算後に呼ばれる)。
  void onFell(World w, Block b, double cx, double cy) {}

  /// ラウンド進行中に毎ステップ呼ばれる (砲台の発射など)。
  void update(World w, Block b, double dt) {}

  /// ボールに力を及ぼすか ([influenceBall] を呼ぶか)。
  bool get influencesBalls => false;

  /// ボールに力を及ぼす (磁力など)。
  void influenceBall(World w, Block b, Ball ball, double dt) {}
}

/// ブロックの種類の登録簿。
class BlockRegistry {
  BlockRegistry(Iterable<BlockBehavior> behaviors) {
    for (final b in behaviors) {
      register(b);
    }
  }

  final Map<String, BlockBehavior> _byId = {};

  void register(BlockBehavior b) {
    if (_byId.containsKey(b.id)) throw ArgumentError('duplicate block id: ${b.id}');
    _byId[b.id] = b;
  }

  BlockBehavior operator [](String id) {
    final b = _byId[id];
    if (b == null) throw ArgumentError('unknown block id: $id');
    return b;
  }

  bool contains(String id) => _byId.containsKey(id);

  Iterable<BlockBehavior> get all => _byId.values;
}
