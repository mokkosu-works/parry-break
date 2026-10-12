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
    this.heatDecay = const [0, 8, 14, 22],
    this.odHeat = 700,
    this.odTime = 10,
    this.odMaxTime = 20,
    this.bossOdHurtPenalty = 3,
    this.odCoreDamageMul = 2,
    this.maxSpeed = 1400,
    this.odMaxSpeed = 1000,
    this.odStartSpeedCap = 900,
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
  });

  // パリィ判定 (秒)
  final double parryWindow, perfectWindow, justWindow, parryCooldown, stunTime;

  /// 被弾後の無敵時間 (秒、スタンを含む)。続けざまの被弾を防ぐ。
  final double hurtInvuln;

  /// 被弾したとき、パドルからこの距離 (px) 以内の敵弾を消す。
  final double hurtClearRadius;

  // パドル
  final double paddleSpeed, paddleWidth;

  // ヒート
  final List<double> stageMin;
  final List<int> stageMult;
  final List<double> stageSpeed;
  final List<double> heatDecay;
  final double odHeat, odTime, odMaxTime;

  /// ボス戦で OVERDRIVE 中に被弾したとき、OVERDRIVE を終わらせずに減らす残り時間 (秒)。
  final double bossOdHurtPenalty;

  /// OVERDRIVE 中にコアへ与えるダメージの倍率。
  final int odCoreDamageMul;

  // ボール
  final double maxSpeed, odMaxSpeed, odStartSpeedCap, minAngleDeg;

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

  /// ボールの基準速度 (px/秒)。
  double baseSpeed(int difficulty, double loopMul) {
    final b = difficulty;
    final s = b <= 10 ? 420.0 : b <= 20 ? 480.0 : b < 30 ? 540.0 : 600.0 + (b - 30) * 4;
    return s * loopMul;
  }

  /// ブロック群の降下速度 (px/秒)。
  double descentSpeed(int difficulty, double loopMul) =>
      math.min(descentMax, descentBase + descentPerRound * (difficulty - 1)) * loopMul;

  /// 砲台の発射間隔 (秒)。
  double turretInterval(int difficulty, double loopMul) =>
      math.max(turretIntervalMin, turretIntervalBase - turretIntervalPerRound * difficulty) / loopMul;

  /// 砲台の弾速 (px/秒)。
  double bulletSpeed(int difficulty, double loopMul) =>
      math.min(bulletSpeedMax, bulletSpeedBase + bulletSpeedPerRound * (difficulty - 1)) * loopMul;

  /// JSON の値で一部を上書きした Tuning を返す (ステージデータの `tuning`)。
  Tuning copyWith(Map<String, Object?> o) {
    double d(String k, double v) => (o[k] as num?)?.toDouble() ?? v;
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
      heatDecay: heatDecay,
      odHeat: d('odHeat', odHeat),
      odTime: d('odTime', odTime),
      odMaxTime: d('odMaxTime', odMaxTime),
      bossOdHurtPenalty: d('bossOdHurtPenalty', bossOdHurtPenalty),
      odCoreDamageMul: (o['odCoreDamageMul'] as num?)?.toInt() ?? odCoreDamageMul,
      maxSpeed: d('maxSpeed', maxSpeed),
      odMaxSpeed: d('odMaxSpeed', odMaxSpeed),
      odStartSpeedCap: d('odStartSpeedCap', odStartSpeedCap),
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
      turretIntervalPerRound: d('turretIntervalPerRound', turretIntervalPerRound),
      turretIntervalMin: d('turretIntervalMin', turretIntervalMin),
      bulletSpeedBase: d('bulletSpeedBase', bulletSpeedBase),
      bulletSpeedPerRound: d('bulletSpeedPerRound', bulletSpeedPerRound),
      bulletSpeedMax: d('bulletSpeedMax', bulletSpeedMax),
      returnSpeed: d('returnSpeed', returnSpeed),
      mirrorReturnSpeed: d('mirrorReturnSpeed', mirrorReturnSpeed),
      countdown: d('countdown', countdown),
    );
  }
}
