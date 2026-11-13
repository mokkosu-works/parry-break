import 'dart:math' as math;

/// ゲームバランスの数値 (design.md 第3〜8章)。
///
/// 既定値はブラウザ版と同じ。ステージごとに一部を上書きできる ([copyWith])。
/// [difficulty] はラウンドの難易度 (エンドレスではループを除いたラウンド番号 1〜60)、
/// [loopMul] は周回ごとの速度倍率 (1 + 0.15 × 周回数)。
class Tuning {
  const Tuning({
    this.parryWindow = 0.10,
    this.perfectWindow = 0.03,
    this.justWindow = 0.012,
    this.parryCooldown = 0.35,
    this.stunTime = 0.4,
    this.hurtInvuln = 1.2,
    this.hurtClearRadius = 220,
    this.paddleSpeed = 900,
    this.paddleWidth = 120,
    this.stageMin = const [0, 100, 250, 450],
    this.stageMult = const [1, 2, 4, 8, 16],
    this.stageSpeed = const [1, 495 / 420, 585 / 420, 690 / 420],
    this.comboDecay = const [0, 8, 14, 22],
    this.odCombo = 700,
    this.odTime = 10,
    this.odMaxTime = 20,
    this.bossOdHurtPenalty = 3,
    this.odCoreDamageMul = 2,
    this.maxSpeed = 1400,
    this.odMaxSpeed = 1000,
    this.minAngleDeg = 15,
    this.grazeDist = 22,
    this.blastRadius = 84,
    this.breakerRadius = 120,
    this.phantomMax = 6,
    this.phantomLife = 5,
    this.phantomBlastRadius = 70,
    this.magnetRadius = 140,
    this.magnetAccel = 220,
    this.descentBase = 4.5,
    this.descentPerRound = 0.18,
    this.descentMax = 13,
    this.turretIntervalBase = 2.8,
    this.turretIntervalPerRound = 0.04,
    this.turretIntervalMin = 1.2,
    this.bulletSpeedBase = 300,
    this.bulletSpeedPerRound = 4,
    this.bulletSpeedMax = 560,
    this.returnSpeed = 620,
    this.mirrorReturnSpeed = 340,
    this.countdown = 1.0,
    this.itemChance = 0.07,
    this.itemGap = 6,
    this.itemMaxOnField = 2,
    this.itemMaxPerRound = 4,
    this.itemFallSpeed = 170,
    this.itemWidth = 44,
    this.itemHeight = 20,
    this.itemWeights = const [3, 3, 2, 2, 1, 1],
    this.itemParryCombo = 30,
    this.itemJustCombo = 50,
    this.itemParryScore = 500,
    this.wideScale = 1.4,
    this.wideTime = 12,
    this.wideTimeParry = 20,
    this.multiCount = 2,
    this.multiCountParry = 3,
    this.multiLife = 8,
    this.shotTime = 10,
    this.shotTimeParry = 16,
    this.shotCount = 2,
    this.shotSpeed = 900,
    this.shotSpread = 28,
    this.blastCount = 1,
    this.blastCountParry = 2,
    this.blastMax = 3,
    this.blastInterval = 0.3,
    this.guardTime = 12,
    this.guardTimeParry = 20,
    this.coolTime = 8,
    this.coolTimeParry = 14,
    this.coolSpeedMul = 0.8,
  });

  // パリィ判定 (秒)
  final double parryWindow, perfectWindow, justWindow, parryCooldown, stunTime;

  /// 被弾後の無敵時間 (秒、スタンを含む)。続けざまの被弾を防ぐ。
  final double hurtInvuln;

  /// 被弾したとき、パドルからこの距離 (px) 以内の敵弾を消す。
  final double hurtClearRadius;

  // パドル
  final double paddleSpeed, paddleWidth;

  // コンボ
  final List<double> stageMin;
  final List<int> stageMult;
  final List<double> stageSpeed;
  final List<double> comboDecay;
  final double odCombo, odTime, odMaxTime;

  /// ボス戦で FEVER TIME 中に被弾したとき、FEVER TIME を終わらせずに減らす残り時間 (秒)。
  final double bossOdHurtPenalty;

  /// FEVER TIME 中にコアへ与えるダメージの倍率。
  final int odCoreDamageMul;

  // ボール
  /// [maxSpeed]: FEVER TIME 以外の速さの上限。
  /// [odMaxSpeed]: FEVER TIME の最高速度 (段階4 の速さがこれを超えるラウンドでは、段階4 の速さ)。
  final double maxSpeed, odMaxSpeed, minAngleDeg;

  // 各種半径・距離
  final double grazeDist, blastRadius, breakerRadius, phantomBlastRadius;
  final int phantomMax;
  final double phantomLife;
  final double magnetRadius, magnetAccel;

  // 難易度の式の係数
  final double descentBase, descentPerRound, descentMax;
  final double turretIntervalBase, turretIntervalPerRound, turretIntervalMin;
  final double bulletSpeedBase, bulletSpeedPerRound, bulletSpeedMax;
  final double returnSpeed, mirrorReturnSpeed;
  final double countdown;

  // ---- アイテム (design.md 7.10) ----

  /// ブロックを 1 個壊したときにアイテムが出る確率。
  final double itemChance;

  /// 前のアイテム (ラウンドの最初は開始) から、この数だけ壊すまでは出ない。
  final int itemGap;

  /// 同時に盤面に出る数と、1 ラウンドに出る数の上限。
  final int itemMaxOnField, itemMaxPerRound;

  /// 落ちる速さ (px/秒) と、カプセルの大きさ (px)。
  final double itemFallSpeed, itemWidth, itemHeight;

  /// 種類ごとの出やすさ (`ItemKind` の並び順: WIDE, MULTI, SHOT, BLAST, GUARD, COOL)。
  final List<double> itemWeights;

  /// パリィ取得のコンボ値 (JUST は [itemJustCombo]) と得点 (× 倍率)。
  final double itemParryCombo, itemJustCombo;
  final int itemParryScore;

  /// WIDE: パドルの幅の倍率と、続く時間 (通常取得 / パリィ取得)。
  final double wideScale, wideTime, wideTimeParry;

  /// MULTI: 出す分身弾の数 (通常取得 / パリィ取得) と寿命 (秒)。
  final int multiCount, multiCountParry;
  final double multiLife;

  /// SHOT: 続く時間 (通常取得 / パリィ取得)、パリィ 1 回で撃つ数、弾の速さ、パドルの中心からの左右のずれ。
  final double shotTime, shotTimeParry;
  final int shotCount;
  final double shotSpeed, shotSpread;

  /// BLAST: 増える回数 (通常取得 / パリィ取得)、持てる上限、続けて出るまでの間隔 (秒)。
  final int blastCount, blastCountParry, blastMax;
  final double blastInterval;

  /// GUARD: 防壁が残る時間 (通常取得 / パリィ取得)。
  final double guardTime, guardTimeParry;

  /// COOL: 続く時間 (通常取得 / パリィ取得) と、ボールの速さの倍率。
  final double coolTime, coolTimeParry, coolSpeedMul;

  /// ボールの基準速度 (px/秒)。
  double baseSpeed(int difficulty, double loopMul) {
    final b = difficulty;
    final s = b <= 10
        ? 420.0
        : b <= 20
        ? 480.0
        : b < 30
        ? 540.0
        : 600.0 + (b - 30) * 4;
    return s * loopMul;
  }

  /// ブロック群の降下速度 (px/秒)。
  double descentSpeed(int difficulty, double loopMul) =>
      math.min(descentMax, descentBase + descentPerRound * (difficulty - 1)) *
      loopMul;

  /// 砲台の発射間隔 (秒)。
  double turretInterval(int difficulty, double loopMul) =>
      math.max(
        turretIntervalMin,
        turretIntervalBase - turretIntervalPerRound * difficulty,
      ) /
      loopMul;

  /// 砲台の弾速 (px/秒)。
  double bulletSpeed(int difficulty, double loopMul) =>
      math.min(
        bulletSpeedMax,
        bulletSpeedBase + bulletSpeedPerRound * (difficulty - 1),
      ) *
      loopMul;

  /// JSON の値で一部を上書きした Tuning を返す (ステージデータの `tuning`)。
  Tuning copyWith(Map<String, Object?> o) {
    double d(String k, double v) => (o[k] as num?)?.toDouble() ?? v;
    int n(String k, int v) => (o[k] as num?)?.toInt() ?? v;
    return Tuning(
      parryWindow: d('parryWindow', parryWindow),
      perfectWindow: d('perfectWindow', perfectWindow),
      justWindow: d('justWindow', justWindow),
      parryCooldown: d('parryCooldown', parryCooldown),
      stunTime: d('stunTime', stunTime),
      hurtInvuln: d('hurtInvuln', hurtInvuln),
      hurtClearRadius: d('hurtClearRadius', hurtClearRadius),
      paddleSpeed: d('paddleSpeed', paddleSpeed),
      paddleWidth: d('paddleWidth', paddleWidth),
      stageMin: stageMin,
      stageMult: stageMult,
      stageSpeed: stageSpeed,
      comboDecay: comboDecay,
      odCombo: d('odCombo', odCombo),
      odTime: d('odTime', odTime),
      odMaxTime: d('odMaxTime', odMaxTime),
      bossOdHurtPenalty: d('bossOdHurtPenalty', bossOdHurtPenalty),
      odCoreDamageMul:
          (o['odCoreDamageMul'] as num?)?.toInt() ?? odCoreDamageMul,
      maxSpeed: d('maxSpeed', maxSpeed),
      odMaxSpeed: d('odMaxSpeed', odMaxSpeed),
      minAngleDeg: d('minAngleDeg', minAngleDeg),
      grazeDist: d('grazeDist', grazeDist),
      blastRadius: d('blastRadius', blastRadius),
      breakerRadius: d('breakerRadius', breakerRadius),
      phantomMax: (o['phantomMax'] as num?)?.toInt() ?? phantomMax,
      phantomLife: d('phantomLife', phantomLife),
      phantomBlastRadius: d('phantomBlastRadius', phantomBlastRadius),
      magnetRadius: d('magnetRadius', magnetRadius),
      magnetAccel: d('magnetAccel', magnetAccel),
      descentBase: d('descentBase', descentBase),
      descentPerRound: d('descentPerRound', descentPerRound),
      descentMax: d('descentMax', descentMax),
      turretIntervalBase: d('turretIntervalBase', turretIntervalBase),
      turretIntervalPerRound: d(
        'turretIntervalPerRound',
        turretIntervalPerRound,
      ),
      turretIntervalMin: d('turretIntervalMin', turretIntervalMin),
      bulletSpeedBase: d('bulletSpeedBase', bulletSpeedBase),
      bulletSpeedPerRound: d('bulletSpeedPerRound', bulletSpeedPerRound),
      bulletSpeedMax: d('bulletSpeedMax', bulletSpeedMax),
      returnSpeed: d('returnSpeed', returnSpeed),
      mirrorReturnSpeed: d('mirrorReturnSpeed', mirrorReturnSpeed),
      countdown: d('countdown', countdown),
      itemChance: d('itemChance', itemChance),
      itemGap: n('itemGap', itemGap),
      itemMaxOnField: n('itemMaxOnField', itemMaxOnField),
      itemMaxPerRound: n('itemMaxPerRound', itemMaxPerRound),
      itemFallSpeed: d('itemFallSpeed', itemFallSpeed),
      itemWidth: d('itemWidth', itemWidth),
      itemHeight: d('itemHeight', itemHeight),
      itemWeights: switch (o['itemWeights']) {
        final List<Object?> l => [for (final v in l) (v as num).toDouble()],
        _ => itemWeights,
      },
      itemParryCombo: d('itemParryCombo', itemParryCombo),
      itemJustCombo: d('itemJustCombo', itemJustCombo),
      itemParryScore: n('itemParryScore', itemParryScore),
      wideScale: d('wideScale', wideScale),
      wideTime: d('wideTime', wideTime),
      wideTimeParry: d('wideTimeParry', wideTimeParry),
      multiCount: n('multiCount', multiCount),
      multiCountParry: n('multiCountParry', multiCountParry),
      multiLife: d('multiLife', multiLife),
      shotTime: d('shotTime', shotTime),
      shotTimeParry: d('shotTimeParry', shotTimeParry),
      shotCount: n('shotCount', shotCount),
      shotSpeed: d('shotSpeed', shotSpeed),
      shotSpread: d('shotSpread', shotSpread),
      blastCount: n('blastCount', blastCount),
      blastCountParry: n('blastCountParry', blastCountParry),
      blastMax: n('blastMax', blastMax),
      blastInterval: d('blastInterval', blastInterval),
      guardTime: d('guardTime', guardTime),
      guardTimeParry: d('guardTimeParry', guardTimeParry),
      coolTime: d('coolTime', coolTime),
      coolTimeParry: d('coolTimeParry', coolTimeParry),
      coolSpeedMul: d('coolSpeedMul', coolSpeedMul),
    );
  }
}
