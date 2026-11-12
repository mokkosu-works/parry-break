import 'dart:math' as math;

import '../core/core.dart';

/// 撮影用ビルドでだけ自動プレイを有効にする。`--dart-define=PROMO_AUTOPLAY=true` を付けたときだけ true。
/// 通常のビルドでは const の false になり、ボットはビルドに含まれない。
const bool kPromoAutoplay = bool.fromEnvironment('PROMO_AUTOPLAY');

/// 撮影用ボットの腕前。見た人が「自分のほうがうまい」と思えるよう、初期値は下手めにしてある。
/// - PROMO_SIGMA: パリィを押す時刻のぶれ (秒)。判定は ±0.10 秒で通常、±0.03 秒で PERFECT、±0.012 秒で JUST。
///   0.06 だと PERFECT は時々、通常のパリィが多く、1 割ほどは外す
/// - PROMO_SPEED: パドルの最高速 (px/秒)。遅いほど、遠い弾や球に間に合わず取りこぼす
final double kPromoSigma =
    double.tryParse(const String.fromEnvironment('PROMO_SIGMA')) ?? 0.06;
final double kPromoSpeed =
    double.tryParse(const String.fromEnvironment('PROMO_SPEED')) ?? 650;

/// PROMO_BIAS: 接触の何秒前に押すか (JUST 狙い版は 0)。PROMO_LAG_COMP=true で入力補正を打ち消す (JUST 狙い版)
final double kPromoBias =
    double.tryParse(const String.fromEnvironment('PROMO_BIAS')) ?? 0.02;
const bool kPromoLagComp = bool.fromEnvironment('PROMO_LAG_COMP');

/// 難易度の確認用の自動プレイ。上手なプレイヤーを真似る:
///
/// - ボールの落下点を (左右の壁の反射を含めて) 読み、受ける位置を少しずつずらす
/// - 落ちてくる敵弾の着弾点を読み、当たりそうな場所を避ける
/// - ボール・敵弾がパドルに触れる瞬間にパリィする。押す時刻は正規分布で [sigma] 秒ぶれる
/// - パドルは [speed] px/秒 までしか動かせない (指で動かせる速さ)
///
/// 人の腕前そのものではないので、難易度どうしの比較 (NORMAL より HARD がどれだけ厳しいか) に使う。
class Bot {
  /// [bias] はパリィを接触の何秒前に押すか。既定の 0.02 は PERFECT (±0.03 秒) を狙う押し方で、JUST (±0.012 秒) は出ない。
  /// [lagComp] が true のときは、ゲーム側の入力補正 ([World.inputLag]) を打ち消すように押す。撮影用の JUST 狙い版が使う。
  Bot(
    this.w, {
    int seed = 1,
    this.sigma = 0.035,
    this.speed = 1500,
    this.bias = 0.02,
    this.lagComp = false,
  }) : _r = Mulberry32(seed * 7919 + 13);

  final World w;
  final double sigma, speed, bias;
  final bool lagComp;
  final Mulberry32 _r;

  double? _pending;
  double _offset = 0;
  bool _wasDescending = false;

  double _gauss() {
    final u1 = math.max(1e-9, _r.next()), u2 = _r.next();
    return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
  }

  /// 左右の壁で反射させて、[t] 秒後の x を返す。
  static double _fold(double x, double vx, double t) {
    const lo = Field.ballR, hi = Field.width - Field.ballR, span = hi - lo;
    var p = (x - lo + vx * t) % (2 * span);
    if (p < 0) p += 2 * span;
    return lo + (p <= span ? p : 2 * span - p);
  }

  void call() {
    if (w.phase != WorldPhase.playing) return;
    final b = w.ball, p = w.paddle, pw = w.paddleWidth;
    w.input.useTarget = true;
    if (b.attached) {
      w.input.targetX = p.x;
      if (w.countdown <= 0) w.pressAction(w.t);
      return;
    }

    // ボールの落下点
    final descending = b.vy > 0;
    if (descending && !_wasDescending) _offset = (_r.next() - 0.5) * (pw - 40);
    _wasDescending = descending;
    double? tb, land;
    if (descending) {
      tb = (Field.paddleY - Field.ballR - b.y) / b.vy;
      land = _fold(b.x, b.vx, tb);
    }

    // 落ちてくる敵弾 (着弾までの時間と、そのときの x)
    final threats = <(double, double, double)>[];
    for (final u in w.bullets) {
      if (!u.hostile || u.dead || u.vy <= 0) continue;
      final tu = (Field.paddleY - u.r - u.y) / u.vy;
      if (tu > 0.9 || u.y > Field.paddleY + Field.paddleH + u.r) continue;
      // すでにパドルの高さにある弾は、横から当たらないように避ける
      threats.add(
        tu < 0 ? (0.0, u.x + u.vx * 0.05, u.r + 6) : (tu, u.x + u.vx * tu, u.r),
      );
    }
    final lasers = [
      for (final l in w.lasers)
        if (l.t < l.warn + l.fire) l,
    ];

    // 動く先を選ぶ
    var best = p.x, bestCost = double.infinity;
    for (var x = pw / 2; x <= Field.width - pw / 2 + 0.1; x += 8) {
      var cost = (x - p.x).abs() * 0.05;
      if (tb != null && land != null) {
        final want = land + _offset;
        final miss = (x - want).abs();
        // 今 x へ動いても、落下までに受けられる位置へ戻れるか
        if ((x - land).abs() - (pw / 2 - 6) > speed * math.max(0, tb - 0.03)) {
          cost += 1e5;
        }
        cost += miss * (tb < 0.5 ? 6 : 1.5);
      } else {
        cost += (x - b.x).abs() * 0.4;
      }
      for (final (tu, xu, r) in threats) {
        if ((xu - x).abs() < pw / 2 + r + 12) {
          cost += 400 / (math.max(0, tu) + 0.15);
        }
      }
      for (final l in lasers) {
        if ((x - l.x).abs() < pw / 2 + l.w / 2 + 6) cost += 3000;
      }
      if (cost < bestCost) {
        bestCost = cost;
        best = x;
      }
    }
    final step = speed * World.dt;
    final nx = p.stun > 0 ? p.x : p.x + (best - p.x).clamp(-step, step);
    w.input.targetX = nx;

    // パリィ: 次にパドルへ触れるもの (ボールか敵弾) に合わせて押す
    final pending = _pending;
    if (pending != null && w.t < pending + 0.02) return;
    _pending = null;
    final pr = w.parry;
    if (pr.active || w.t < pr.cooldownUntil || p.stun > 0) return;
    double? next;
    if (tb != null &&
        land != null &&
        (land - nx).abs() <= pw / 2 + Field.ballR) {
      next = tb;
    }
    for (final (tu, xu, r) in threats) {
      if ((xu - nx).abs() <= pw / 2 + r && (next == null || tu < next)) {
        next = tu;
      }
    }
    if (next == null || next > 0.2) return;
    final at =
        w.t + next - bias + (lagComp ? w.inputLag : 0) + _gauss() * sigma;
    _pending = at;
    w.pressAction(at);
  }
}
