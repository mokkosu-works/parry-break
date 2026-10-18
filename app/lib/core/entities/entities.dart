import '../blocks/block_behavior.dart';
import '../config/field.dart';

/// 盤面上のブロック。種類ごとの振る舞いは [behavior] が持つ。
///
/// 座標 [x], [y] は隊列 (Formation) の原点からの相対位置。画面上の位置は
/// `x + form.ox`, `y + form.oy` になる。
class Block {
  Block(this.behavior, this.x, this.y, this.w, this.h, int hp)
      : hp = hp,
        maxHp = hp;

  final BlockBehavior behavior;
  double x, y;
  final double w, h;
  int hp;
  final int maxHp;

  /// 盤面から取り除かれたら true (破壊・崩落・ラウンド終了)。
  bool removed = false;

  /// 被弾時の白い明滅の残り時間 (描画用)。
  double flash = 0;

  // 攻撃ブロック (砲台など)
  double fireT = 0;
  bool telegraph = false;
  int shots = 0;

  /// 狙い・回転の角度 (ラジアン)。狙撃砲台の照準線、全方位・回転砲台の向き。
  double aim = 0;

  /// 分裂の子ブロックが落ちていく残り距離。
  double fall = 0;

  // 崩落の支え
  bool supported = false;
  int depth = 0;

  String get type => behavior.id;
}

/// 隊列の原点。ブロック群全体の降下やボスの左右移動を表す。
class Formation {
  double ox = 0, oy = 0;

  /// 直前のステップの値 (描画でステップ間を補間するため)。
  double prevOx = 0, prevOy = 0;
}

class Paddle {
  double x = Field.width / 2, vx = 0, stun = 0;

  /// 被弾後の無敵の残り時間。この間は敵弾・レーザーに当たらない (パリィはできる)。
  double invuln = 0;

  /// 直前のステップの値 (描画でステップ間を補間するため)。
  double prevX = Field.width / 2;
}

class ParryState {
  bool active = false;
  double press = -9;
  bool success = false;

  /// 1 回のパリィ判定で弾いた数 (MULTI PARRY)。
  int hits = 0;

  /// クールダウンが明けるシミュレーション時刻。
  double cooldownUntil = 0;
}

class Ball {
  Ball({
    required this.x,
    required this.y,
    this.vx = 0,
    this.vy = 0,
    required this.speed,
    this.attached = false,
    this.phantom = false,
    this.life = 0,
  }) : id = _nextId++;

  static int _nextId = 0;

  /// 描画側で軌跡などを対応づけるための識別子。
  final int id;
  double x, y, vx, vy, speed;
  bool attached;

  /// 残りの貫通回数。
  int pierce = 0;

  /// JUST パリィ後、次にブロックへ当たった瞬間に衝撃波を出す。
  bool breaker = false;

  /// パドルを離れてから壊したブロック数 (跳弾ボーナス)。
  int flight = 0;

  /// FEVER TIME 中に生まれる分身弾。落としてもミスにならない。
  /// メインのボールを落としたときは、残っている分身弾の1つが昇格してメインのボールになる。
  bool phantom;

  /// 分身弾の残り寿命 (秒)。
  double life;

  bool lost = false;

  /// 直前のステップの位置 (描画でステップ間を補間するため)。
  late double prevX = x, prevY = y;
}

enum BulletKind { bullet, shard, shrapnel }

class Bullet {
  Bullet({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.kind,
    this.red = false,
    this.source,
  }) : r = kind == BulletKind.shard ? 7 : 6;

  double x, y, vx, vy;
  final double r;
  final BulletKind kind;

  /// 敵弾なら true、撃ち返した弾なら false。
  bool hostile = true;

  /// 赤い弾: 撃ち返すとコアへ誘導される。
  bool red;

  /// 撃った砲台・コア。
  Block? source;

  /// 撃ち返した赤い弾の誘導先。
  Block? target;

  double life = 0;
  bool dead = false;

  /// パドルの近く (グレイズ判定の範囲) を通ったか。
  bool near = false;
  bool grazed = false;

  /// 直前のステップの位置 (描画でステップ間を補間するため)。
  late double prevX = x, prevY = y;
}

class Laser {
  Laser(this.x);
  final double x;
  final double w = 40;
  double t = 0;
  final double warn = 0.85, fire = 0.3;
  bool hit = false, fired = false;
}

enum BlastKind { bomb, breaker, phantom }

/// 起爆待ちの爆発。
class PendingBlast {
  PendingBlast(this.x, this.y, this.delay, this.r, this.shrapnel, this.kind);
  final double x, y, r;
  double delay;
  final bool shrapnel;
  final BlastKind kind;
}

/// 崩落してひびが入り、落下を待っているブロック。
class PendingFall {
  PendingFall(this.block, this.delay, this.originX, this.points);
  final Block block;
  double delay;
  final double originX;
  final int points;
}

/// 崩落の連続 (0.9 秒途切れるまで) の集計。
class CascadeTally {
  int n = 0, notes = 0;
  double t = 0;
}

/// 連鎖爆発 (0.7 秒途切れるまで) の集計。
class BlastChainTally {
  int n = 0;
  double t = 0;
}

class RunStats {
  int just = 0, graze = 0, bestCollapse = 0, bestBlast = 0, bestRicochet = 0, hurt = 0;

  /// パリィの成功数 / うち PERFECT 以上の数 / 撃ち返し弾で壊したブロック数。
  int parries = 0, perfects = 0, returnKills = 0;

  /// ラウンドを進めていた時間の合計 (カウントダウン・クリア演出を除く)。
  double playTime = 0;
}

class Bonus {
  const Bonus(this.label, this.points);
  final String label;
  final int points;
}

/// ボールがパドルに最後に触れた時刻。接触の後に押したパリィ (0.03 秒以内) の判定に使う。
class Contact {
  const Contact(this.t, {required this.used});
  final double t;
  final bool used;
}
