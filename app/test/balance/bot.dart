import 'dart:math' as math;

import 'package:parry_break/core/core.dart';

/// 難易度の確認用の自動プレイ。上手なプレイヤーを真似る:
///
/// - ボールの落下点を (左右の壁の反射を含めて) 読み、受ける位置を少しずつずらす
/// - 落ちてくる敵弾の着弾点を読み、当たりそうな場所を避ける
/// - ボール・敵弾がパドルに触れる瞬間にパリィする。押す時刻は正規分布で [sigma] 秒ぶれる
/// - パドルは [speed] px/秒 までしか動かせない (指で動かせる速さ)
///
/// 人の腕前そのものではないので、難易度どうしの比較 (NORMAL より HARD がどれだけ厳しいか) に使う。
class Bot {
  Bot(this.w, {int seed = 1, this.sigma = 0.035, this.speed = 1500}) : _r = Mulberry32(seed * 7919 + 13);

  final World w;
  final double sigma, speed;
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
      threats.add(tu < 0 ? (0.0, u.x + u.vx * 0.05, u.r + 6) : (tu, u.x + u.vx * tu, u.r));
    }
    final lasers = [for (final l in w.lasers) if (l.t < l.warn + l.fire) l];

    // 動く先を選ぶ
    var best = p.x, bestCost = double.infinity;
    for (var x = pw / 2; x <= Field.width - pw / 2 + 0.1; x += 8) {
      var cost = (x - p.x).abs() * 0.05;
      if (tb != null && land != null) {
        final want = land + _offset;
        final miss = (x - want).abs();
        // 今 x へ動いても、落下までに受けられる位置へ戻れるか
        if ((x - land).abs() - (pw / 2 - 6) > speed * math.max(0, tb - 0.03)) cost += 1e5;
        cost += miss * (tb < 0.5 ? 6 : 1.5);
      } else {
        cost += (x - b.x).abs() * 0.4;
      }
      for (final (tu, xu, r) in threats) {
        if ((xu - x).abs() < pw / 2 + r + 12) cost += 400 / (math.max(0, tu) + 0.15);
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
    if (tb != null && land != null && (land - nx).abs() <= pw / 2 + Field.ballR) next = tb;
    for (final (tu, xu, r) in threats) {
      if ((xu - nx).abs() <= pw / 2 + r && (next == null || tu < next)) next = tu;
    }
    if (next == null || next > 0.2) return;
    final at = w.t + next - 0.02 + _gauss() * sigma;
    _pending = at;
    w.pressAction(at);
  }
}

class RunResult {
  RunResult(this.cleared, this.hurt, this.time, this.reason, this.score, this.bullets);
  final bool cleared;
  final int hurt;
  final double time;
  final String reason;
  final int score;

  /// 1 秒あたりに撃たれた敵弾の平均。
  final double bullets;
}

/// [mode] を [difficulty] で最後まで (最大 [limit] 秒) 遊ぶ。
RunResult playOut(GameMode mode, Difficulty difficulty, {int seed = 1, double sigma = 0.035, double limit = 400}) {
  final w = World(mode: mode, difficulty: difficulty, inputLag: 0)..start();
  w.sync
    ..wall = 0
    ..sim = 0
    ..scale = 1;
  final bot = Bot(w, seed: seed, sigma: sigma);
  final seen = <Bullet>{};
  var fired = 0;
  final n = (limit / World.dt).round();
  for (var i = 0; i < n; i++) {
    bot();
    w.step(World.dt);
    for (final u in w.bullets) {
      if (u.hostile && seen.add(u)) fired++;
    }
    w.drainEvents();
    if (w.phase == WorldPhase.over || w.phase == WorldPhase.completed) break;
  }
  final cleared = w.phase == WorldPhase.completed;
  return RunResult(cleared, w.stats.hurt, w.stats.playTime, cleared ? 'CLEAR' : w.overReason, w.score,
      fired / math.max(1, w.stats.playTime));
}
