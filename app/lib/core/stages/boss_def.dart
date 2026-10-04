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
    this.phaseThresholds = const [0.66, 0.33],
  });

  /// 何体目のボスか (0 始まり)。攻撃頻度の強化に使う。
  final int index;

  /// 要塞の配置。`C` はコア (2 行分の高さ)。
  final List<String> template;
  final int coreHp;
  final double timeLimit;
  final List<PatternSpec> patterns;

  /// コアの残り HP の割合がこれ以下になるとフェーズが進む。
  final List<double> phaseThresholds;

  factory BossDef.fromJson(int index, Map<String, Object?> j) => BossDef(
        index: index,
        template: List<String>.from(j['template'] as List),
        coreHp: (j['coreHp'] as num).toInt(),
        timeLimit: (j['timeLimit'] as num).toDouble(),
        patterns: [
          for (final p in (j['patterns'] as List).cast<Map<String, Object?>>())
            PatternSpec(p['type'] as String, fromPhase: (p['from'] as num?)?.toInt() ?? 1, params: p),
        ],
        phaseThresholds: [
          for (final v in (j['phases'] as List?) ?? const [0.66, 0.33]) (v as num).toDouble(),
        ],
      );
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
  });
}

double _bulletSpeed(World w, Boss b) => (230 + b.index * 15) * w.wave.loopMul;

/// 扇状の弾幕 (赤い弾を含む)。
class FanPattern extends BossPattern {
  FanPattern(super.fromPhase);
  double _t = 2.5;

  @override
  void update(World w, Boss boss, List<Block> cores, double dt, double rate) {
    _t -= dt * rate;
    if (_t > 0) return;
    _t = 3.2;
    final sp = _bulletSpeed(w, boss);
    for (final c in cores) {
      final o = w.blockCenter(c);
      final n = const [5, 4, 3][math.min(cores.length, 3) - 1] + boss.phase * 2;
      const spread = 80 * deg;
      for (var i = 0; i < n; i++) {
        final a = math.pi / 2 - spread / 2 + spread * i / (n - 1);
        w.fireBullet(o.x, o.y + 20, a, sp, source: c, red: i % 3 == 1);
      }
    }
    w.emit(const BulletFired());
  }
}

/// 自機狙いの 3 連弾 (中央は赤い弾)。
class AimedPattern extends BossPattern {
  AimedPattern(super.fromPhase);
  double _t = 2;

  @override
  void update(World w, Boss boss, List<Block> cores, double dt, double rate) {
    _t -= dt * rate;
    if (_t > 0) return;
    _t = 2.2;
    final sp = _bulletSpeed(w, boss);
    for (final c in cores) {
      final o = w.blockCenter(c);
      final a = math.atan2(Field.paddleY - o.y, w.paddle.x - o.x);
      for (var k = -1; k <= 1; k++) {
        w.fireBullet(o.x, o.y + 20, a + k * 10 * deg, sp * 1.25, source: c, red: k == 0);
      }
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

/// 渦巻き弾幕 (2.5 秒照射 / 2 秒休止)。
class SpiralPattern extends BossPattern {
  SpiralPattern(super.fromPhase);
  double _t = 0, _angle = 0, _cycle = 0;
  int _n = 0;

  @override
  void update(World w, Boss boss, List<Block> cores, double dt, double rate) {
    _cycle = (_cycle + dt) % 4.5;
    if (_cycle >= 2.5) return;
    _t -= dt;
    if (_t > 0) return;
    _t = 0.1 / (1 + boss.index * 0.1);
    _angle += 0.45;
    final c = cores[_n++ % cores.length], o = w.blockCenter(c);
    w.fireBullet(o.x, o.y + 20, math.pi / 2 + math.sin(_angle) * 70 * deg, _bulletSpeed(w, boss),
        source: c, red: _n % 5 == 0);
    if (_n % 3 == 0) w.emit(const BulletFired());
  }
}
