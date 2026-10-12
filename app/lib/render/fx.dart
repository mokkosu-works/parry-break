import 'dart:math' as math;
import 'dart:ui';

import '../core/blocks/normal.dart';
import '../core/core.dart';
import 'palette.dart';

class Particle {
  Particle(this.x, this.y, this.vx, this.vy, this.max, this.color, this.size);
  double x, y, vx, vy, life = 0;
  final double max, size;
  final Color color;
}

class FxPopup {
  FxPopup(this.x, this.y, this.text, this.color, this.size);
  double x, y, t = 0;
  final String text;
  final Color color;
  final double size;
}

class FxRing {
  FxRing(this.x, this.y, this.r, this.color, this.width);
  final double x, y, r, width;
  final Color color;
  double t = 0;
  static const life = 0.45;
}

class FxCallout {
  FxCallout(this.channel, this.text, this.sub, this.color, this.size, {required this.hold});
  final CalloutChannel channel;
  String text, sub;
  Color color;
  double size;
  bool hold;
  double t = 0;
  static const life = 1.6;
}

class FxJudge {
  FxJudge(this.text, this.color, {this.big = false});
  final String text;
  final Color color;
  final bool big;
  double t = 0;
}

class FxBanner {
  FxBanner(this.kind, this.value, this.introKey);
  final BannerKind kind;
  final int value;
  final String? introKey;
  double t = 0;
}

/// 崩れ落ちるブロック (崩落・ラウンドクリア)。
class FxDebris {
  FxDebris(this.x, this.y, this.w, this.h, this.color, {this.delay = 0, this.originX});
  double x, y, vx = 0, vy = 0, rot = 0, vr = 0;
  final double w, h;
  final Color color;

  /// 落ち始めるまでの時間 (この間はその場で震える)。
  double delay;
  final double? originX;
  bool get dropped => delay <= 0;
}

/// 演出の状態。コアのイベントを受けて作り、シミュレーションのステップごとに進める。
class FxState {
  FxState(this.world, {this.reduceEffects = false});

  final World world;
  bool reduceEffects;
  final math.Random _rnd = math.Random();

  final particles = <Particle>[];
  final popups = <FxPopup>[];
  final rings = <FxRing>[];
  final callouts = <FxCallout>[];
  final debris = <FxDebris>[];
  FxJudge? judge;
  FxBanner? banner;
  double shake = 0, flash = 0;
  Color flashColor = Dot.white;

  /// ボールごとの軌跡 (ステップごとの位置)。
  final trails = <int, List<Offset>>{};

  /// 表示上のスコア (加算されたスコアへ回りながら追いつく)。
  double dispScore = 0;

  double _r(double a, double b) => a + _rnd.nextDouble() * (b - a);

  Color blockColor(Block b) =>
      b.type == 'N' ? Palette.normalTiers[NormalBlock.tierOf(b, world)] : Palette.blocks[b.type] ?? Palette.white;

  void burst(double x, double y, int n, Color color, double sp) {
    for (var i = 0; i < n; i++) {
      if (particles.length > 600) particles.removeAt(0);
      final a = _rnd.nextDouble() * math.pi * 2, v = sp * (0.2 + _rnd.nextDouble() * 0.8);
      particles.add(Particle(x, y, math.cos(a) * v, math.sin(a) * v, 0.3 + _rnd.nextDouble() * 0.4, color,
          1.5 + _rnd.nextDouble() * 2.5));
    }
  }

  void popup(double x, double y, String text, Color color, double size) {
    if (popups.length > 50) popups.removeAt(0);
    popups.add(FxPopup(x, y, text, color, size));
  }

  void ring(double x, double y, double r, Color color, double width) {
    if (rings.length > 40) rings.removeAt(0);
    rings.add(FxRing(x, y, r, color, width));
  }

  void _shake(double v) => shake = math.max(shake, reduceEffects ? v * 0.3 : v);

  void _flash(double v, [Color color = Dot.white]) {
    flash = math.max(flash, reduceEffects ? math.min(v, 0.08) : v);
    flashColor = color;
  }

  void _callout(Callout e) {
    final (color, size) = switch (e.channel) {
      CalloutChannel.collapse => (
          const [Dot.white, Dot.mustard, Dot.rose][e.level],
          const [32.0, 40.0, 48.0][e.level]
        ),
      CalloutChannel.chainBlast => (Dot.orange, 32.0),
      CalloutChannel.multiParry => (Dot.peach, 32.0),
      CalloutChannel.ricochet => (Dot.peach, 32.0),
      CalloutChannel.overdriveFinish => (Dot.rose, 32.0),
    };
    // 同じ種類のコールアウトが表示中なら、新しく出さずに書き換える
    final cur = callouts.where((c) => c.channel == e.channel).lastOrNull;
    final updatable = e.channel != CalloutChannel.ricochet && e.channel != CalloutChannel.overdriveFinish;
    if (cur != null && updatable && (cur.hold || e.release || e.channel == CalloutChannel.multiParry)) {
      cur
        ..text = e.text
        ..color = color
        ..size = size;
      if (e.release) {
        cur
          ..hold = false
          ..t = 0.3
          ..sub = e.sub;
      } else {
        cur.t = math.min(cur.t, 0.12);
      }
      return;
    }
    if (e.release) return;
    callouts.add(FxCallout(e.channel, e.text, e.sub, color, size, hold: e.hold));
    if (callouts.length > 3) callouts.removeAt(0);
  }

  /// コアのイベントを演出にする。
  void handle(GameEvent e) {
    switch (e) {
      case RoundStarted():
        trails.clear();
        debris.removeWhere((d) => !d.dropped);
      case Banner(:final kind, :final value, :final introKey):
        banner = FxBanner(kind, value, introKey);
      case Callout():
        _callout(e);
      case Popup(:final x, :final y, :final text, :final kind, :final amount):
        final (color, size) = switch (kind) {
          PopupKind.score => (Dot.white, amount >= 2000 ? 24.0 : 16.0),
          PopupKind.returnedScore => (Dot.mustard, amount >= 2000 ? 24.0 : 16.0),
          PopupKind.chain => (Dot.white, 16.0),
          PopupKind.ricochet => (Dot.peach, 16.0),
          PopupKind.chainBlast => (Dot.orange, 24.0),
          PopupKind.graze => (Dot.peach, 16.0),
          PopupKind.noDamage => (Dot.dim, 16.0),
          PopupKind.coreDamage => (Dot.mustard, 24.0),
        };
        popup(x, y, text, color, size);
      case ParrySucceeded(:final grade, :final target, :final x, :final y):
        final just = grade == ParryGrade.just, perfect = grade != ParryGrade.good;
        final col = just ? Dot.rose : perfect ? Dot.mustard : Dot.peach;
        judge = FxJudge(just ? 'JUST!!' : grade.name.toUpperCase(), col, big: just);
        burst(x, y, just ? 40 : perfect ? 28 : 14, col, just ? 520 : perfect ? 420 : 280);
        ring(x, Field.paddleY, just ? 110 : perfect ? 70 : 40, col, just ? 5 : 3);
        _shake(target == ParryTarget.ball ? (just ? 12 : perfect ? 9 : 5) : 4);
        if (just) _flash(0.15, Dot.blush);
      case ParryMissed():
        judge = FxJudge('MISS', Dot.dim);
      case BlockDestroyed(:final block, :final cx, :final cy, :final cause, :final points):
        final returned = cause == DestroyCause.bullet;
        popup(cx, cy, '+${formatScore(points)}', returned ? Dot.mustard : Dot.white, points >= 2000 ? 24 : 16);
        burst(cx, cy, cause == DestroyCause.pierce || cause == DestroyCause.blast ? 14 : 9, blockColor(block), 240);
      case KeystoneBroken(:final x, :final y):
        ring(x, y, 100, Dot.white, 4);
        _shake(6);
      case CoreDamaged(:final x, :final y):
        burst(x, y, 18, Palette.blocks['C']!, 320);
        _shake(8);
      case BlockRepaired(:final block, :final x, :final y):
        burst(x, y, 8, blockColor(block), 160);
        ring(x, y, 34, Dot.peach, 2);
      case CoreDestroyed(:final x, :final y):
        burst(x, y, 60, Palette.blocks['C']!, 520);
        burst(x, y, 30, Dot.white, 300);
        ring(x, y, 160, Palette.blocks['C']!, 6);
        _shake(18);
        _flash(0.3, Dot.mustard);
      case CollapseStarted(:final count):
        _shake(math.min(16, 4 + count * 0.4));
      case BlockFell(:final block, :final x, :final y, :final originX):
        final d = FxDebris(x, y, block.w, block.h, blockColor(block), originX: originX);
        _drop(d);
        debris.add(d);
        burst(x + block.w / 2, y + block.h / 2, 5, d.color, 160);
      case RoundCleared(:final remaining):
        for (final b in remaining) {
          debris.add(FxDebris(b.x + world.form.ox, b.y + world.form.oy, b.w, b.h, blockColor(b),
              delay: _r(0.05, 0.5), originX: Field.width / 2));
        }
        trails.clear();
      case BlastExploded(:final x, :final y, :final r, :final kind):
        final big = kind == BlastKind.breaker;
        ring(x, y, r, big ? Dot.blush : kind == BlastKind.phantom ? Dot.rose : Dot.orange, big ? 7 : 4);
        burst(x, y, big ? 50 : 24, big ? Dot.blush : Dot.orange, big ? 520 : 360);
        _shake(big ? 16 : 9);
      case BreakerTriggered():
        _flash(0.2, Dot.blush);
      case PlayerHurt(:final x):
        judge = FxJudge('HIT!', Dot.bulletRed);
        burst(x, Field.paddleY, 20, Dot.bulletRed, 300);
        _shake(12);
        _flash(0.25, Dot.bulletRed);
      case Grazed(:final x):
        burst(x, Field.paddleY + 6, 6, Dot.white, 200);
      case OverdriveStarted():
        _flash(0.5);
        _shake(14);
      case BossPhaseChanged():
        _shake(16);
        _flash(0.3, Dot.orange);
      case LaserFired():
        _shake(6);
      case GameOver():
        final b = world.ball;
        burst(b.x, math.min(b.y, Field.height - 10), 40, Dot.white, 400);
        _shake(20);
        _flash(0.4, Dot.bulletRed);
      default:
        break;
    }
  }

  void _drop(FxDebris d) {
    final cx = d.x + d.w / 2;
    d
      ..delay = 0
      ..vx = (cx - (d.originX ?? cx)) * 0.7 + _r(-60, 60)
      ..vy = _r(-160, -40)
      ..vr = _r(-7, 7);
  }

  /// シミュレーションの 1 ステップごとに呼ぶ。
  void step(double dt) {
    for (var i = particles.length - 1; i >= 0; i--) {
      final p = particles[i];
      p
        ..life += dt
        ..x += p.vx * dt
        ..y += p.vy * dt
        ..vx *= 0.94
        ..vy *= 0.94;
      if (p.life >= p.max) particles.removeAt(i);
    }
    for (var i = popups.length - 1; i >= 0; i--) {
      final p = popups[i]
        ..t += dt
        ..y -= 30 * dt;
      if (p.t > 0.8) popups.removeAt(i);
    }
    for (var i = rings.length - 1; i >= 0; i--) {
      if ((rings[i].t += dt) > FxRing.life) rings.removeAt(i);
    }
    for (var i = callouts.length - 1; i >= 0; i--) {
      final c = callouts[i]..t += dt;
      if (c.hold && c.t > 0.3) c.t = 0.3;
      if (c.t > FxCallout.life) callouts.removeAt(i);
    }
    for (var i = debris.length - 1; i >= 0; i--) {
      final d = debris[i];
      if (!d.dropped) {
        d.delay -= dt;
        if (d.dropped) _drop(d);
        continue;
      }
      d
        ..vy += 1500 * dt
        ..x += d.vx * dt
        ..y += d.vy * dt
        ..rot += d.vr * dt;
      if (d.y > Field.height + 60) debris.removeAt(i);
    }
    final j = judge;
    if (j != null && (j.t += dt) > 0.6) judge = null;
    final b = banner;
    if (b != null && (b.t += dt) > 1.8) banner = null;
    shake = math.max(0, shake - 60 * dt);
    flash = math.max(0, flash - dt);
    _updateTrails();
  }

  void _updateTrails() {
    final w = world;
    final len = w.od ? 24 : const [0, 6, 9, 16][w.stage];
    final live = <int>{};
    for (final b in [w.ball, ...w.phantoms]) {
      live.add(b.id);
      final tr = trails.putIfAbsent(b.id, () => []);
      if (b.attached || w.phase != WorldPhase.playing) {
        tr.clear();
        continue;
      }
      tr.add(Offset(b.x, b.y));
      while (tr.length > len) {
        tr.removeAt(0);
      }
    }
    trails.removeWhere((id, _) => !live.contains(id));
  }

  /// 毎フレーム (実時間) 呼ぶ。
  void frame(double rdt) {
    dispScore += (world.score - dispScore) * math.min(1, rdt * 12);
    if ((world.score - dispScore).abs() < 1) dispScore = world.score.toDouble();
  }

  void reset() {
    particles.clear();
    popups.clear();
    rings.clear();
    callouts.clear();
    debris.clear();
    trails.clear();
    judge = null;
    banner = null;
    shake = flash = 0;
    dispScore = 0;
  }
}
