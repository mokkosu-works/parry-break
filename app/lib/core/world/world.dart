import 'dart:math' as math;

import '../blocks/block_behavior.dart';
import '../blocks/standard_blocks.dart';
import '../config/difficulty.dart';
import '../config/field.dart';
import '../config/tuning.dart';
import '../entities/entities.dart';
import '../events/game_event.dart';
import '../modes/game_mode.dart';
import '../sim/geom.dart';
import '../sim/rng.dart';
import '../sim/time_sync.dart';
import '../stages/boss_def.dart';
import '../stages/round_spec.dart';

part 'systems/ball_system.dart';
part 'systems/parry_system.dart';
part 'systems/block_system.dart';
part 'systems/collapse_system.dart';
part 'systems/bullet_system.dart';
part 'systems/boss_system.dart';
part 'systems/round_system.dart';

enum WorldPhase {
  /// ラウンド進行中。
  playing,

  /// ラウンドクリアの演出中 (次のラウンドを待つ)。
  clearing,

  /// ゲームオーバー。
  over,

  /// モードの最後のラウンドをクリアした (ステージモード)。
  completed,
}

/// パドル操作の入力。タッチ・コントローラーなど入力元に依存しない形にしたもの。
class PaddleInput {
  /// 目標位置へ直接動かす (ドラッグ)。
  bool useTarget = false;
  double targetX = Field.width / 2;

  /// -1〜1 の方向入力 (キー・スティック)。[useTarget] が false のとき使う。
  double axis = 0;
}

/// 1 回のプレイのゲーム状態とシミュレーション (60Hz 固定ステップ、決定的)。
///
/// Flutter に依存しない。描画・音・振動は [drainEvents] で受け取る [GameEvent] を見て行う。
/// 各システムの処理は `systems/` の part ファイルに分けている。
class World {
  World({
    required this.mode,
    BlockRegistry? blocks,
    BossPatternRegistry? bossPatterns,
    Tuning tuning = const Tuning(),
    this.difficulty = Difficulty.normal,
    this.inputLag = 0.016,
  })  : registry = blocks ?? standardBlocks(),
        bossPatterns = bossPatterns ?? BossPatternRegistry.standard,
        baseTuning = _withDifficulty(tuning, difficulty),
        tuning = _withDifficulty(tuning, difficulty);

  static Tuning _withDifficulty(Tuning t, Difficulty d) => d.tuning.isEmpty ? t : t.copyWith(d.tuning);

  static const double dt = 1 / 60;

  final GameMode mode;
  final BlockRegistry registry;
  final BossPatternRegistry bossPatterns;
  final Tuning baseTuning;

  /// 難易度 (弾の量・速さ、パリィの判定の広さなど)。
  final Difficulty difficulty;

  /// 現在のラウンドで有効なバランス値 (ラウンドごとの上書きを反映したもの)。
  Tuning tuning;

  /// 判定タイミング補正 (秒)。入力時刻をこの値だけ早めて扱う。
  double inputLag;

  final TimeSync sync = TimeSync();
  final PaddleInput input = PaddleInput();

  // ---- 状態 ---------------------------------------------------------------
  WorldPhase phase = WorldPhase.playing;
  double t = 0;
  int score = 0;
  double combo = 0;
  bool od = false;
  double odTime = 0, odElapsed = 0;
  int streak = 0, maxStreak = 0;
  Paddle paddle = Paddle();
  ParryState parry = ParryState();
  late Ball ball;
  List<Ball> phantoms = [];
  List<Block> blocks = [];
  List<Bullet> bullets = [];
  List<Laser> lasers = [];
  List<PendingBlast> blasts = [];
  List<PendingFall> falling = [];
  final Formation form = Formation();
  Boss? boss;
  late RoundSpec round;

  /// ラウンドの固定シードの乱数 (反射ブロック・砲台の初期タイマー。ブラウザ版と同じ系列)。
  late Mulberry32 rng;

  /// ゲーム結果に影響するその他の乱数 (瓦礫・分身弾など)。これもラウンドのシードで決まる。
  late Mulberry32 aux;

  double countdown = 0, roundTime = 0;
  bool launched = false;
  double lastBlockHit = -9;
  Contact lastContact = const Contact(-9, used: true);
  bool structDirty = false;
  Vec2 lastBreak = const Vec2(Field.width / 2, Field.gridY0);

  /// 最も低いブロックの下端 (直前のステップの値)。
  double lowest = 0;

  /// ヒットストップ (シミュレーションを止める残り時間)。
  double hitstop = 0;

  /// スローモーション (×0.35) の残り時間 (実時間)。
  double slowmo = 0;

  CascadeTally cascade = CascadeTally();
  BlastChainTally blastChain = BlastChainTally();
  RunStats stats = RunStats();
  double clearT = 0, overT = 0;
  String overReason = '';
  List<Bonus> bonuses = const [];

  final List<double> _actions = [];
  final List<GameEvent> _events = [];

  // ---- 外部とのやりとり -------------------------------------------------

  /// 発射 / パリィの入力。[wallTime] は入力イベントの時刻 (秒、[TimeSync] と同じ時計)。
  void pressAction(double wallTime) => _actions.add(wallTime);

  void clearActions() => _actions.clear();

  void emit(GameEvent e) => _events.add(e);

  /// 溜まったイベントを取り出す。
  List<GameEvent> drainEvents() {
    final out = List<GameEvent>.of(_events);
    _events.clear();
    return out;
  }

  /// 新しいプレイを始める。[fromRound] で途中のラウンドから始められる (テスト・デバッグ用)。
  void start({int fromRound = 1}) {
    phase = WorldPhase.playing;
    t = 0;
    score = 0;
    combo = 0;
    od = false;
    odTime = odElapsed = 0;
    streak = maxStreak = 0;
    paddle = Paddle();
    parry = ParryState();
    phantoms = [];
    falling = [];
    hitstop = slowmo = 0;
    cascade = CascadeTally();
    blastChain = BlastChainTally();
    stats = RunStats();
    overReason = '';
    _actions.clear();
    final first = mode.roundAt(fromRound);
    if (first == null) throw StateError('mode has no rounds');
    _loadRound(first);
  }

  /// 1 ステップ進める。
  void step(double dt) {
    _savePrevious();
    t += dt;
    _processActions(dt);
    switch (phase) {
      case WorldPhase.playing:
        _updatePlay(dt);
      case WorldPhase.clearing:
        _updateClear(dt);
        _updateBlasts(dt);
      case WorldPhase.over:
        overT += dt;
      case WorldPhase.completed:
        break;
    }
    if (phase == WorldPhase.playing || phase == WorldPhase.clearing) _updateCombos(dt);
    _updateFalling(dt);
  }

  void _savePrevious() {
    form
      ..prevOx = form.ox
      ..prevOy = form.oy;
    paddle.prevX = paddle.x;
    ball
      ..prevX = ball.x
      ..prevY = ball.y;
    for (final f in phantoms) {
      f
        ..prevX = f.x
        ..prevY = f.y;
    }
    for (final u in bullets) {
      u
        ..prevX = u.x
        ..prevY = u.y;
    }
  }

  // ---- 派生値 -------------------------------------------------------------

  /// コンボ段階 (0〜3)。FEVER TIME は [od] で表す。
  int get stage {
    final m = tuning.stageMin;
    return combo >= m[3] ? 3 : combo >= m[2] ? 2 : combo >= m[1] ? 1 : 0;
  }

  /// 得点倍率。
  int get mult => od ? tuning.stageMult[4] : tuning.stageMult[stage];

  double get paddleWidth => tuning.paddleWidth;

  double get descentSpeed => tuning.descentSpeed(round.difficulty, round.loopMul) * difficulty.descent;

  /// ボールの目標速度。段階が上がると補間して加速する。
  double get targetSpeed {
    final s = tuning.baseSpeed(round.difficulty, round.loopMul);
    if (od) {
      final s4 = math.min(tuning.odStartSpeedCap, s * tuning.stageSpeed[3]);
      return s4 + (tuning.odMaxSpeed - s4) * math.min(1, odElapsed / tuning.odTime);
    }
    return math.min(tuning.maxSpeed, s * tuning.stageSpeed[stage]);
  }

  /// ブロックがデッドラインに 3 秒以内に届きそうか (画面端を赤く光らせる)。
  bool get isDanger {
    if (phase != WorldPhase.playing || blocks.isEmpty) return false;
    final b = boss;
    final sp = b != null ? (b.plunge ? 520.0 : 0.0) : descentSpeed;
    if (sp <= 0) return false;
    return (Field.warnY - lowest) / sp < 3;
  }

  /// ボスのコアの残り HP の合計。
  int get bossHp {
    var hp = 0;
    for (final b in blocks) {
      if (b.type == bossCoreId) hp += math.max(0, b.hp);
    }
    return hp;
  }

  Vec2 blockCenter(Block b) => Vec2(b.x + form.ox + b.w / 2, b.y + form.oy + b.h / 2);

  // ---- ブロック・ボスから使う操作 ---------------------------------------

  /// ブロックを置く。[w], [h], [hp] を省くと種類の既定値になる。
  Block addBlock(String id, double x, double y, [double? w, double? h, int? hp]) {
    final be = registry[id];
    final b = Block(be, x, y, w ?? Field.cellW, h ?? Field.cellH, hp ?? be.hp);
    blocks.add(b);
    return b;
  }

  /// 貫通弾の貫通回数を 1 減らす (メインのボール、FEVER TIME 中でないとき)。
  void consumePierce(BallHit hit) {
    if (hit.main && !od) hit.ball.pierce--;
  }

  /// 壊せないものに当たって弾かれた。
  void deflect(Block b) {
    b.flash = 0.05;
    emit(BlockDeflected(b));
  }

  void damage(Block b, int n, DestroyCause cause) {
    b.hp -= n;
    b.flash = 0.08;
    if (b.hp <= 0) {
      destroyBlock(b, cause);
    } else {
      emit(BlockDamaged(b));
    }
  }

  void destroyBlock(Block b, DestroyCause cause) => _destroyBlock(b, cause);

  void damageCore(Block core, int n) => _damageCore(core, n);

  void queueBlast(double x, double y, double delay, double r, {required bool shrapnel, required BlastKind kind}) =>
      blasts.add(PendingBlast(x, y, delay, r, shrapnel, kind));

  void fireBullet(double x, double y, double angle, double speed, {Block? source, bool red = false}) =>
      _spawnHostile(x, y, math.cos(angle) * speed, math.sin(angle) * speed, BulletKind.bullet, source: source, red: red);

  void fireLaser(double x) {
    final l = Laser(clampD(x, 24, Field.width - 24));
    lasers.add(l);
    emit(LaserWarned(l.x));
  }

  /// 砲台が消えると、その砲台の弾も消える。
  void killBulletsOf(Block b) {
    for (final u in bullets) {
      if (u.hostile && identical(u.source, b)) u.dead = true;
    }
  }

  void addCombo(double v) {
    if (od) return;
    combo = math.max(0, combo + v);
    if (combo >= tuning.odCombo) _startFeverTime();
  }

  void addScore(int v) => score += v;
}
