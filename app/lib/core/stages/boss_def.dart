import 'dart:math' as math;

import '../config/field.dart';
import '../entities/entities.dart';
import '../events/game_event.dart';
import '../sim/geom.dart';
import '../world/world.dart';

/// ボスのコアのブロック ID。
const bossCoreId = 'C';

/// 攻撃パターンの指定 (ボスの定義に書く)。
class PatternSpec {
  const PatternSpec(this.type, {required this.fromPhase, this.params = const {}});
  final String type;

  /// このフェーズ以降で動く (1〜3)。
  final int fromPhase;
  final Map<String, Object?> params;
}

/// ボスの定義。Phase 4 で JSON (assets/bosses/) から読み込む。
class BossDef {
  const BossDef({
    required this.index,
    required this.template,
    required this.coreHp,
    required this.timeLimit,
    required this.patterns,
    this.hardPatterns = const [],
    this.phaseThresholds = const [0.66, 0.33],
    this.sway = 0.55,
    this.reinforce = 2,
  });

  /// 何体目のボスか (0 始まり)。攻撃頻度の強化に使う。
  final int index;

  /// 要塞の配置。`C` はコア (2 行分の高さ)。
  final List<String> template;
  final int coreHp;
  final double timeLimit;
  final List<PatternSpec> patterns;

  /// HARD (弾幕) のときだけ足す攻撃 (JSON の `hard`)。
  final List<PatternSpec> hardPatterns;

  /// コアの残り HP の割合がこれ以下になるとフェーズが進む。
  final List<double> phaseThresholds;

  /// 左右に揺れる速さ (角速度、ラジアン/秒)。速いほどコアを狙いにくい。
  final double sway;

  /// フェーズ2 で両翼に足す砲台の数 (0 か 2)。
  final int reinforce;

  factory BossDef.fromJson(int index, Map<String, Object?> j) => BossDef(
        index: index,
        template: List<String>.from(j['template'] as List),
        coreHp: (j['coreHp'] as num).toInt(),
        timeLimit: (j['timeLimit'] as num).toDouble(),
        patterns: _patterns(j['patterns'] as List<Object?>),
        hardPatterns: _patterns(j['hard'] as List<Object?>? ?? const []),
        phaseThresholds: [
          for (final v in (j['phases'] as List?) ?? const [0.66, 0.33]) (v as num).toDouble(),
        ],
        sway: (j['sway'] as num?)?.toDouble() ?? 0.55,
        reinforce: (j['reinforce'] as num?)?.toInt() ?? 2,
      );

  static List<PatternSpec> _patterns(List<Object?> l) => [
        for (final p in l.cast<Map<String, Object?>>())
          PatternSpec(p['type'] as String, fromPhase: (p['from'] as num?)?.toInt() ?? 1, params: p),
      ];
}

/// 戦闘中のボスの状態。
class Boss {
  Boss({
    required this.def,
    required this.left,
    required this.cols,
    required this.amp,
    required this.maxHp,
    required this.patterns,
  }) : time = def.timeLimit;

  final BossDef def;
  final double left;
  final int cols;

  /// 左右に揺れる振幅。
  double amp;
  final int maxHp;
  final List<BossPattern> patterns;
  int phase = 1;

  /// 残り時間。0 になると要塞が急降下する。
  double time;
  double t = 0;
  bool plunge = false;

  int get index => def.index;
}

/// ボスの攻撃パターン。新しい攻撃はこれを実装して [BossPatternRegistry] に登録する。
abstract class BossPattern {
  BossPattern(this.fromPhase);
  final int fromPhase;

  /// [rate] はフェーズとボスの強さによる攻撃頻度の倍率。
  void update(World w, Boss boss, List<Block> cores, double dt, double rate);
}

typedef BossPatternFactory = BossPattern Function(int fromPhase, Map<String, Object?> params);

class BossPatternRegistry {
  BossPatternRegistry(this._factories);
  final Map<String, BossPatternFactory> _factories;

  BossPattern create(PatternSpec s) {
    final f = _factories[s.type];
    if (f == null) throw ArgumentError('unknown boss pattern: ${s.type}');
    return f(s.fromPhase, s.params);
  }

  static final standard = BossPatternRegistry({
    'fan': (p, _) => FanPattern(p),
    'aimed3': (p, _) => AimedPattern(p),
    'laser': (p, _) => LaserPattern(p),
    'spiral': (p, _) => SpiralPattern(p),
    'curtain': (p, _) => CurtainPattern(p),
    'laserGrid': (p, _) => LaserGridPattern(p),
    'repair': (p, _) => RepairPattern(p),
    'ring': (p, _) => RingPattern(p),
    'rain': (p, _) => RainPattern(p),
  });
}

double _bulletSpeed(World w, Boss b) => (230 + b.index * 15) * w.round.loopMul * w.difficulty.bulletSpeed;

/// 扇状の弾幕 (赤い弾を含む)。コアが複数あるときは 1 つずつ順番に撃つ。
class FanPattern extends BossPattern {
  FanPattern(super.fromPhase);
  double _t = 2.5;
  int _n = 0;

  @override
  void update(World w, Boss boss, List<Block> cores, double dt, double rate) {
    _t -= dt * rate;
    if (_t > 0) return;
    _t = 3.6;
    final sp = _bulletSpeed(w, boss);
    final c = cores[_n++ % cores.length], o = w.blockCenter(c);
    final n = 2 + boss.phase * 2 + w.difficulty.pick(0, 0, 2);
    final spread = w.difficulty.pick(80, 80, 96) * deg;
    for (var i = 0; i < n; i++) {
      final a = math.pi / 2 - spread / 2 + spread * i / (n - 1);
      w.fireBullet(o.x, o.y + 20, a, sp, source: c, red: i % 3 == 1);
    }
    w.emit(const BulletFired());
  }
}

/// 自機狙いの 3 連弾 (中央は赤い弾)。コアが複数あるときは 1 つずつ順番に撃つ。
class AimedPattern extends BossPattern {
  AimedPattern(super.fromPhase);
  double _t = 2;
  int _n = 0;

  @override
  void update(World w, Boss boss, List<Block> cores, double dt, double rate) {
    _t -= dt * rate;
    if (_t > 0) return;
    _t = 2.8;
    final sp = _bulletSpeed(w, boss);
    final c = cores[_n++ % cores.length], o = w.blockCenter(c);
    final a = math.atan2(Field.paddleY - o.y, w.paddle.x - o.x);
    final side = w.difficulty.pick(1, 1, 2);
    for (var k = -side; k <= side; k++) {
      w.fireBullet(o.x, o.y + 20, a + k * 10 * deg, sp * 1.25, source: c, red: k == 0);
    }
    w.emit(const BulletFired());
  }
}

/// ロックオンレーザー。ボス2以降のフェーズ3では、移動方向の先にもう 1 本撃つ。
class LaserPattern extends BossPattern {
  LaserPattern(super.fromPhase);
  double _t = 3;

  @override
  void update(World w, Boss boss, List<Block> cores, double dt, double rate) {
    _t -= dt;
    if (_t > 0) return;
    _t = (boss.phase == 3 ? 3.4 : 5) / (1 + boss.index * 0.06);
    w.fireLaser(w.paddle.x);
    if (boss.phase == 3 && boss.index >= 1) w.fireLaser(w.paddle.x + (w.paddle.vx >= 0 ? 1 : -1) * 160);
  }
}

/// 渦巻き弾幕 (2 秒照射 / 3 秒休止)。
class SpiralPattern extends BossPattern {
  SpiralPattern(super.fromPhase);
  double _t = 0, _angle = 0, _cycle = 0;
  int _n = 0;

  @override
  void update(World w, Boss boss, List<Block> cores, double dt, double rate) {
    _cycle = (_cycle + dt) % 5;
    if (_cycle >= 2) return;
    _t -= dt;
    if (_t > 0) return;
    _t = 0.18 / (1 + boss.index * 0.05) / w.difficulty.bossFireRate;
    _angle += 0.45;
    final c = cores[_n++ % cores.length], o = w.blockCenter(c);
    w.fireBullet(o.x, o.y + 20, math.pi / 2 + math.sin(_angle) * 70 * deg, _bulletSpeed(w, boss),
        source: c, red: _n % 5 == 0);
    if (_n % 3 == 0) w.emit(const BulletFired());
  }
}

/// 弾の壁: 盤面の端から端まで、1 か所だけ隙間を空けて弾を並べて落とす。
/// 隙間の両脇は赤い弾 (隙間の際で撃ち返せばコアに届く)。
class CurtainPattern extends BossPattern {
  CurtainPattern(super.fromPhase);
  double _t = 3.5;

  static const double _step = 60;
  static const int _gapSlots = 3;

  @override
  void update(World w, Boss boss, List<Block> cores, double dt, double rate) {
    _t -= dt * rate;
    if (_t > 0) return;
    _t = 10;
    var y = 0.0;
    for (final b in w.blocks) {
      y = math.max(y, b.y + w.form.oy + b.h);
    }
    final n = (Field.width / _step).floor();
    final gap = 1 + (w.aux.next() * (n - _gapSlots - 1)).floor();
    final sp = _bulletSpeed(w, boss) * 0.75;
    for (var i = 0; i < n; i++) {
      if (i >= gap && i < gap + _gapSlots) continue;
      final red = i == gap - 1 || i == gap + _gapSlots;
      w.fireBullet(_step / 2 + i * _step, y + 10, math.pi / 2, sp, red: red);
    }
    w.emit(const BulletFired());
  }
}

/// レーザーの格子: 等間隔に並べて同時に撃つ (パリィ不可)。格子の間へ逃げる。
class LaserGridPattern extends BossPattern {
  LaserGridPattern(super.fromPhase);
  double _t = 4;

  /// レーザーの間隔。間の安全地帯はパドルの中心で 100px ほど。
  static const double _spacing = 250;

  @override
  void update(World w, Boss boss, List<Block> cores, double dt, double rate) {
    _t -= dt;
    if (_t > 0) return;
    _t = (boss.phase == 3 ? 5.5 : 7.5) / (1 + boss.index * 0.06);
    for (var x = w.aux.next() * _spacing; x < Field.width; x += _spacing) {
      w.fireLaser(x);
    }
  }
}

/// 修復: 壊された装甲 (要塞の配置にある通常ブロック) を一定間隔で 1 つずつ作り直す。
/// 支えのあるブロックに接する場所だけを直す (宙に浮いたブロックは作らない)。
class RepairPattern extends BossPattern {
  RepairPattern(super.fromPhase);
  double _t = 4;

  @override
  void update(World w, Boss boss, List<Block> cores, double dt, double rate) {
    _t -= dt * rate;
    if (_t > 0) return;
    _t = 2.6;
    final tpl = boss.def.template;
    final cand = <(double, double, Block)>[];
    for (var r = 0; r < tpl.length; r++) {
      for (var c = 0; c < tpl[r].length; c++) {
        if (tpl[r][c] != 'N') continue;
        final x = boss.left + c * Field.cellW, y = Field.gridY0 + r * Field.cellH;
        if (_blockAt(w, x, y) != null || _ballNear(w, x, y)) continue;
        final from = _supportedNeighbor(w, x, y);
        if (from != null) cand.add((x, y, from));
      }
    }
    if (cand.isEmpty) return;
    final (x, y, from) = cand[(w.aux.next() * cand.length).floor()];
    final b = w.addBlock('N', x, y)
      ..supported = true
      ..depth = from.depth + 1
      ..flash = 0.25;
    w.emit(BlockRepaired(b, x + w.form.ox + b.w / 2, y + w.form.oy + b.h / 2));
  }

  /// マス (x, y) に重なるブロック (要塞の座標系)。
  static Block? _blockAt(World w, double x, double y) {
    for (final b in w.blocks) {
      if (x + 2 < b.x + b.w && x + Field.cellW - 2 > b.x && y + 2 < b.y + b.h && y + Field.cellH - 2 > b.y) return b;
    }
    return null;
  }

  /// 上下左右のマスにある、支えのあるブロック。
  static Block? _supportedNeighbor(World w, double x, double y) {
    for (final (dx, dy) in const [(0.0, -1.0), (-1.0, 0.0), (1.0, 0.0), (0.0, 1.0)]) {
      final b = _blockAt(w, x + dx * Field.cellW, y + dy * Field.cellH);
      if (b != null && b.supported && b.behavior.structural) return b;
    }
    return null;
  }

  /// ボール (分身弾を含む) がマスのすぐ近くにあるか。ボールをブロックに埋めないようにする。
  static bool _ballNear(World w, double x, double y) {
    final sx = x + w.form.ox, sy = y + w.form.oy;
    for (final ball in [w.ball, ...w.phantoms]) {
      if (rectDist(ball.x, ball.y, sx, sy, Field.cellW, Field.cellH) < Field.ballR + 40) return true;
    }
    return false;
  }
}

/// 全方位弾: コアから輪の形に弾を撃つ (撃つたびに少し回す)。コアが複数あるときは 1 つずつ順番に撃つ。
class RingPattern extends BossPattern {
  RingPattern(super.fromPhase);
  double _t = 3, _rot = 0;
  int _n = 0;

  @override
  void update(World w, Boss boss, List<Block> cores, double dt, double rate) {
    _t -= dt * rate;
    if (_t > 0) return;
    _t = 5;
    final c = cores[_n++ % cores.length], o = w.blockCenter(c);
    final n = w.difficulty.pick(10, 14, 16) + boss.phase * 2;
    final sp = _bulletSpeed(w, boss) * 0.8;
    _rot += 0.37;
    for (var i = 0; i < n; i++) {
      w.fireBullet(o.x, o.y + 20, _rot + 2 * math.pi * i / n, sp, source: c, red: i % 5 == 0);
    }
    w.emit(const BulletFired());
  }
}

/// 弾の雨: 要塞の下端のあちこちから、少しずつ斜めに弾を降らせる。
class RainPattern extends BossPattern {
  RainPattern(super.fromPhase);
  double _t = 2;

  @override
  void update(World w, Boss boss, List<Block> cores, double dt, double rate) {
    _t -= dt * rate;
    if (_t > 0) return;
    _t = 1.8;
    var y = 0.0;
    for (final b in w.blocks) {
      y = math.max(y, b.y + w.form.oy + b.h);
    }
    final n = w.difficulty.pick(2, 2, 3) + boss.phase;
    final sp = _bulletSpeed(w, boss) * 0.7;
    for (var i = 0; i < n; i++) {
      final x = 40 + w.aux.next() * (Field.width - 80);
      w.fireBullet(x, y + 10, math.pi / 2 + w.aux.range(-0.18, 0.18), sp * w.aux.range(0.85, 1.15));
    }
    w.emit(const BulletFired());
  }
}
