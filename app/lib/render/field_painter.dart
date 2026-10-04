import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import '../core/core.dart';
import '../l10n/app_localizations.dart';
import 'block_painters.dart';
import 'fx.dart';
import 'glow.dart';
import 'palette.dart';
import 'text_cache.dart';

/// 盤面 (1200×720) を描く。HUD・コールアウト・バナー・ウェーブクリアの表示も含む。
class FieldPainter extends CustomPainter {
  FieldPainter({
    required this.world,
    required this.fx,
    required this.alpha,
    required this.time,
    required this.text,
    required this.glow,
    required this.blockPainters,
    required this.l10n,
    required this.highQuality,
    required super.repaint,
    this.attract = false,
  });

  final World world;
  final FxState fx;

  /// ステップ間の補間の割合 (0〜1)。
  final double Function() alpha;

  /// 実時間 (秒)。
  final double Function() time;
  final TextCache text;
  final GlowSprite? glow;
  final BlockPainterRegistry blockPainters;
  final AppLocalizations l10n;
  final bool highQuality;

  /// タイトル画面のデモ表示。HUD・文字の演出を描かない。
  final bool attract;

  static const _w = Field.width, _h = Field.height;
  final _fill = Paint();
  final _stroke = Paint()..style = PaintingStyle.stroke;
  final _rnd = math.Random();

  late Canvas _c;
  late double _t, _a, _ox, _oy;

  double _lerp(double a, double b) => a + (b - a) * _a;

  @override
  void paint(Canvas canvas, Size size) {
    _c = canvas;
    _t = time();
    _a = alpha().clamp(0.0, 1.0);
    final w = world;
    _ox = _lerp(w.form.prevOx, w.form.ox);
    _oy = _lerp(w.form.prevOy, w.form.oy);
    canvas.save();
    canvas.scale(size.width / _w);
    canvas.clipRect(const Rect.fromLTWH(0, 0, _w, _h));
    canvas.drawRect(const Rect.fromLTWH(0, 0, _w, _h), _fill..color = Palette.bg);
    canvas.save();
    if (fx.shake > 0) {
      canvas.translate((_rnd.nextDouble() - 0.5) * fx.shake, (_rnd.nextDouble() - 0.5) * fx.shake);
    }
    _background();
    _field();
    for (final b in w.blocks) {
      if (b.behavior.influencesBalls) _magnetField(b);
    }
    final ctx = BlockPaintContext(canvas, text, _t, fx.blockColor);
    for (final b in w.blocks) {
      _block(ctx, b, Rect.fromLTWH(b.x + _ox, b.y + _oy, b.w, b.h));
    }
    _cracking();
    _debris();
    _bullets();
    for (final f in w.phantoms) {
      _ball(f);
    }
    if (w.phase == WorldPhase.playing) _ball(w.ball);
    _paddle();
    _lasers();
    _rings();
    _particles();
    if (!attract) _popups();
    canvas.restore();
    _edgeFx();
    if (!attract) {
      _hud();
      _callouts();
      _banner();
      if (w.phase == WorldPhase.clearing) _clearScreen();
    }
    if (fx.flash > 0) {
      canvas.drawRect(const Rect.fromLTWH(0, 0, _w, _h),
          _fill..color = withAlpha(fx.flashColor, math.min(0.6, fx.flash)));
    }
    canvas.restore();
  }

  void _txt(String s, double x, double y, double size, Color color,
          {TextAlignH align = TextAlignH.center, double weight = 700, String? family}) =>
      text.draw(_c, s, x, y, size, color, align: align, weight: weight, family: family);

  void _glowTxt(String s, double x, double y, double size, Color color,
          {double blur = 18, TextAlignH align = TextAlignH.center}) =>
      text.draw(_c, s, x, y, size, color, align: align, weight: 900, glow: highQuality ? blur * 0.6 : 0);

  void _glow(double x, double y, double d, Color c, {double opacity = 1}) =>
      glow?.draw(_c, x, y, d, d, c, opacity: opacity);

  void _dashedLine(double x0, double y0, double x1, double y1, double dash, double gap, double offset, Paint p) {
    final len = x1 - x0;
    var x = -(offset % (dash + gap));
    final path = Path();
    while (x < len) {
      final a = math.max(0.0, x), b = math.min(len, x + dash);
      if (b > a) {
        path
          ..moveTo(x0 + a, y0)
          ..lineTo(x0 + b, y1);
      }
      x += dash + gap;
    }
    _c.drawPath(path, p);
  }

  // ---- 背景・盤面 ---------------------------------------------------------

  void _background() {
    final p = Path();
    for (var x = 0.0; x <= _w; x += 60) {
      p
        ..moveTo(x + 0.5, 0)
        ..lineTo(x + 0.5, _h);
    }
    final off = (_t * 20) % 48;
    for (var y = -48 + off; y <= _h; y += 48) {
      p
        ..moveTo(0, y + 0.5)
        ..lineTo(_w, y + 0.5);
    }
    _c.drawPath(p, _stroke
      ..color = const Color.fromRGBO(120, 100, 255, 0.06)
      ..strokeWidth = 1);
  }

  void _field() {
    _c.drawRect(const Rect.fromLTWH(0, 0, _w, Field.topY), _fill..color = Palette.hudBg);
    _c.drawLine(const Offset(0, Field.topY), const Offset(_w, Field.topY), _stroke
      ..color = Palette.hudLine
      ..strokeWidth = 2);
    final danger = world.isDanger;
    _stroke
      ..color = danger
          ? Color.fromRGBO(255, 40, 70, (0.6 + 0.4 * math.sin(_t * 14)).clamp(0, 1))
          : const Color.fromRGBO(255, 60, 90, 0.35)
      ..strokeWidth = 2;
    _dashedLine(0, Field.warnY, _w, Field.warnY, 12, 8, -_t * 30, _stroke);
    if (attract) return;
    _txt('WARNING LINE', _w - 16, Field.warnY - 18, 22, const Color.fromRGBO(255, 110, 140, 0.9),
        align: TextAlignH.right);
  }

  void _magnetField(Block b) {
    final x = b.x + _ox + b.w / 2, y = b.y + _oy + b.h / 2;
    final rad = world.tuning.magnetRadius;
    _stroke
      ..color = const Color.fromRGBO(77, 132, 255, 0.18)
      ..strokeWidth = 1;
    // 点線の円
    final path = Path();
    const seg = 10 * math.pi / 180;
    final start = (_t * 20 / rad) % (seg * 2);
    for (var a = start; a < math.pi * 2 + start; a += seg * 2) {
      path.addArc(Rect.fromCircle(center: Offset(x, y), radius: rad), a, seg * 0.6);
    }
    _c.drawPath(path, _stroke);
    final r = rad - ((_t * 60) % rad);
    _c.drawCircle(Offset(x, y), r, _stroke..color = Color.fromRGBO(77, 132, 255, 0.15 * r / rad));
  }

  void _block(BlockPaintContext ctx, Block b, Rect r) {
    blockPainters.of(b.type)(ctx, b, r);
    final i = r.deflate(2);
    // 支えの脈動: 要石から塊へ光が伝わる (どこが繋がっているかが分かる)
    if (b.supported && !b.behavior.anchor) {
      final ph = (_t * 8) % 16;
      final k = math.max(0.0, 1 - (ph - b.depth).abs() / 1.5);
      if (k > 0) _c.drawRect(i, _fill..color = Color.fromRGBO(255, 255, 255, 0.2 * k));
    }
    if (b.flash > 0) _c.drawRect(i, _fill..color = Color.fromRGBO(255, 255, 255, math.min(1, b.flash * 10)));
  }

  /// ひびが入って落下を待つブロック (その場で震える)。
  void _cracking() {
    for (final f in world.falling) {
      final b = f.block;
      final x = b.x + _ox + (_rnd.nextDouble() - 0.5) * 3, y = b.y + _oy + (_rnd.nextDouble() - 0.5) * 3;
      _debrisRect(Rect.fromLTWH(x, y, b.w, b.h), fx.blockColor(b), cracking: true);
    }
    for (final d in fx.debris) {
      if (d.dropped) continue;
      final x = d.x + (_rnd.nextDouble() - 0.5) * 3, y = d.y + (_rnd.nextDouble() - 0.5) * 3;
      _debrisRect(Rect.fromLTWH(x, y, d.w, d.h), d.color, cracking: true);
    }
  }

  void _debris() {
    for (final d in fx.debris) {
      if (!d.dropped) continue;
      _c.save();
      _c.translate(d.x + d.w / 2, d.y + d.h / 2);
      _c.rotate(d.rot);
      final a = (1 - (d.y - Field.warnY) / 260).clamp(0.15, 1.0);
      _debrisRect(Rect.fromCenter(center: Offset.zero, width: d.w, height: d.h), d.color, alpha: a);
      _c.restore();
    }
  }

  void _debrisRect(Rect r, Color col, {bool cracking = false, double alpha = 1}) {
    _c.drawRect(r.deflate(2), _fill..color = withAlpha(col, 0x55 / 255 * alpha));
    _c.drawRect(r.deflate(3), _stroke
      ..color = withAlpha(col, alpha)
      ..strokeWidth = 2);
    if (cracking) {
      _c.drawRect(r.deflate(2), _fill..color = Color.fromRGBO(255, 255, 255, 0.3 + 0.3 * math.sin(_t * 50)));
    }
  }

  // ---- 弾・ボール・パドル --------------------------------------------------

  void _bullets() {
    for (final u in world.bullets) {
      if (u.dead) continue;
      final x = _lerp(u.prevX, u.x), y = _lerp(u.prevY, u.y);
      final Color c;
      if (!u.hostile) {
        c = u.red ? Palette.yellow : Palette.cyan;
      } else if (u.kind == BulletKind.shard) {
        c = const Color(0xFFD9A066);
      } else if (u.kind == BulletKind.shrapnel) {
        c = const Color(0xFFFFB347);
      } else {
        c = u.red ? const Color(0xFFFF2A3D) : const Color(0xFFFF9D4D);
      }
      _c.drawCircle(Offset(x, y), u.r + 5, _fill..color = withAlpha(c, 0.25));
      if (u.hostile && u.kind == BulletKind.shard) {
        _c.save();
        _c.translate(x, y);
        _c.rotate(u.life * 8);
        final p = Path()
          ..moveTo(0, -u.r - 2)
          ..lineTo(u.r + 1, u.r)
          ..lineTo(-u.r, u.r - 1)
          ..close();
        _c.drawPath(p, _fill..color = c);
        _c.drawPath(p, _stroke
          ..color = const Color(0xFFFFF3E0)
          ..strokeWidth = 1);
        _c.restore();
        continue;
      }
      _c.drawCircle(Offset(x, y), u.r, _fill..color = c);
      _c.drawCircle(Offset(x, y), u.r * 0.45, _fill..color = Palette.white);
      if (u.hostile && u.red) {
        _c.drawCircle(Offset(x, y), u.r + 4, _stroke
          ..color = const Color.fromRGBO(255, 42, 61, 0.7)
          ..strokeWidth = 1.5);
      }
    }
  }

  void _ball(Ball b) {
    final w = world;
    final st = w.stage;
    final pierce = b.pierce > 0 || w.od || b.phantom;
    final col = w.od || b.phantom
        ? Palette.magenta
        : b.breaker
            ? Palette.justPink
            : pierce
                ? Palette.yellow
                : const [Color(0xFFFFFFFF), Color(0xFFBFF8FF), Color(0xFF7FF0FF), Palette.cyan][st];
    final tr = fx.trails[b.id] ?? const <Offset>[];
    for (var i = 0; i < tr.length; i++) {
      final a = (i + 1) / tr.length;
      if (w.od && i % 4 == 0) {
        _c.drawCircle(tr[i], Field.ballR, _stroke
          ..color = Color.fromRGBO(255, 77, 216, a * 0.5)
          ..strokeWidth = 2);
      }
      _c.drawCircle(tr[i], Field.ballR * (0.3 + 0.7 * a), _fill..color = withAlpha(col, a * 0.45));
    }
    final x = _lerp(b.prevX, b.x), y = _lerp(b.prevY, b.y);
    _glow(x, y, (Field.ballR + (pierce ? 26 : 14)) * 2, col, opacity: 0.8);
    _c.drawCircle(Offset(x, y), Field.ballR, _fill..color = col);
    _c.drawCircle(Offset(x, y), Field.ballR * 0.5, _fill..color = Palette.white);
    if (b.breaker) {
      final a0 = _t * 1000 / 120;
      final p = Path();
      for (var k = 0; k < 8; k++) {
        final a = a0 + k * math.pi / 4;
        p
          ..moveTo(x + math.cos(a) * 11, y + math.sin(a) * 11)
          ..lineTo(x + math.cos(a) * 20, y + math.sin(a) * 20);
      }
      _c.drawPath(p, _stroke
        ..color = Palette.justPink
        ..strokeWidth = 2);
    }
    if (b.pierce > 0 && !w.od && !b.phantom) {
      for (var k = 0; k < b.pierce; k++) {
        final a = _t * 1000 / 150 + k * math.pi * 2 / b.pierce;
        _c.drawCircle(Offset(x + math.cos(a) * 14, y + math.sin(a) * 14), 2.5, _fill..color = Palette.yellow);
      }
    }
    if (b.phantom || attract) return;
    if (b.flight >= 5 && !b.attached) {
      _txt('${b.flight} HIT', x, y - 24, 11, b.flight >= 15 ? Palette.yellow : Palette.pale);
    }
    if (b.attached) {
      if (w.countdown > 0) {
        _txt('READY', x, y - 30, 22, Palette.yellow);
      } else if ((_t * 2).floor().isEven) {
        _txt('TAP', x, y - 32, 22, Palette.pale);
      }
    }
  }

  void _paddle() {
    final w = world, p = w.paddle, pr = w.parry;
    final pw = w.paddleWidth;
    final px = _lerp(p.prevX, p.x);
    final x = px - pw / 2;
    const y = Field.paddleY;
    final stunned = p.stun > 0;
    final cooling = w.t < pr.cooldownUntil;
    var col = Palette.cyan;
    if (stunned) {
      col = math.sin(_t * 40) > 0 ? Palette.red : const Color(0xFF55556A);
    } else if (cooling) {
      col = const Color(0xFF5A6A80);
    } else if (pr.active) {
      col = Palette.yellow;
    }
    _glow(px, y + Field.paddleH / 2, pw + 60, col, opacity: pr.active ? 0.9 : 0.5);
    final rr = RRect.fromRectAndRadius(Rect.fromLTWH(x, y, pw, Field.paddleH), const Radius.circular(7));
    _c.drawRRect(rr, _fill..color = col);
    _c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x + 6, y + 3, pw - 12, 3), const Radius.circular(2)),
        _fill..color = const Color.fromRGBO(255, 255, 255, 0.7));
    if (pr.active && w.phase == WorldPhase.playing) {
      final k = ((w.t - pr.press) / w.tuning.parryWindow).clamp(0.0, 1.0);
      _c.drawArc(
          Rect.fromCenter(center: Offset(px, y + 2), width: (pw / 2 + 8 + k * 14) * 2, height: (14 + k * 10) * 2),
          math.pi,
          math.pi,
          false,
          _stroke
            ..color = Color.fromRGBO(255, 225, 77, 1 - k)
            ..strokeWidth = 3);
    }
    if (cooling && !stunned) {
      final k = ((pr.cooldownUntil - w.t) / w.tuning.parryCooldown).clamp(0.0, 1.0);
      _c.drawRect(Rect.fromLTWH(x, y + Field.paddleH + 4, pw * k, 2), _fill..color = const Color(0x59FFFFFF));
    }
    if (stunned) {
      _c.drawRect(Rect.fromLTWH(x, y + Field.paddleH + 4, pw * (p.stun / w.tuning.stunTime), 2),
          _fill..color = Palette.red);
    }
  }

  void _lasers() {
    for (final l in world.lasers) {
      if (l.t < l.warn) {
        final blink = math.sin(_t * 40) > 0;
        _c.drawRect(Rect.fromLTWH(l.x - l.w / 2, Field.topY, l.w, _h - Field.topY),
            _fill..color = const Color.fromRGBO(255, 40, 70, 0.08));
        _stroke
          ..color = Color.fromRGBO(255, 40, 70, blink ? 0.9 : 0.35)
          ..strokeWidth = 2;
        for (final lx in [l.x - l.w / 2, l.x + l.w / 2]) {
          for (var y = Field.topY; y < _h; y += 18) {
            _c.drawLine(Offset(lx, y), Offset(lx, math.min(_h, y + 10)), _stroke);
          }
        }
        if (blink) _txt('!', l.x, Field.paddleY - 40, 22, Palette.red);
      } else {
        final k = math.max(0.0, 1 - (l.t - l.warn) / l.fire);
        _c.drawRect(
            Rect.fromLTWH(l.x - l.w, Field.topY, l.w * 2, _h - Field.topY),
            _fill
              ..shader = ui.Gradient.linear(Offset(l.x - l.w, 0), Offset(l.x + l.w, 0), [
                const Color.fromRGBO(255, 40, 70, 0),
                Color.fromRGBO(255, 40, 70, 0.6 * k),
                Color.fromRGBO(255, 255, 255, k),
                Color.fromRGBO(255, 40, 70, 0.6 * k),
                const Color.fromRGBO(255, 40, 70, 0),
              ], const [0, 0.3, 0.5, 0.7, 1]));
        _fill.shader = null;
      }
    }
  }

  // ---- エフェクト ---------------------------------------------------------

  void _rings() {
    for (final r in fx.rings) {
      final k = r.t / FxRing.life;
      _c.drawCircle(Offset(r.x, r.y), r.r * (0.2 + 0.8 * math.sqrt(k)), _stroke
        ..color = withAlpha(r.color, 1 - k)
        ..strokeWidth = r.width * (1 - k) + 0.5);
    }
  }

  void _particles() {
    for (final p in fx.particles) {
      final a = 1 - p.life / p.max;
      _c.drawRect(Rect.fromCenter(center: Offset(p.x, p.y), width: p.size, height: p.size),
          _fill..color = withAlpha(p.color, a));
    }
  }

  void _popups() {
    for (final p in fx.popups) {
      _txt(p.text, p.x, p.y, p.size, withAlpha(p.color, 1 - p.t / 0.8));
    }
  }

  void _edgeFx() {
    final w = world;
    if (w.phase != WorldPhase.playing) return;
    final st = w.od ? 4 : w.stage;
    if (st >= 2) {
      final c = st == 4 ? Palette.magenta : st == 3 ? const Color(0xFFFFB43C) : Palette.cyan;
      _edgeGlow(c, 0.25 + 0.1 * math.sin(_t * 8), 40);
    }
    if (w.isDanger) _edgeGlow(const Color(0xFFFF1E3C), 0.35 + 0.35 * math.sin(_t * 7).abs(), 70);
  }

  void _edgeGlow(Color c, double a, double sz) {
    final on = withAlpha(c, a), off = withAlpha(c, 0);
    void band(Rect r, Offset from, Offset to) {
      _c.drawRect(r, _fill..shader = ui.Gradient.linear(from, to, [on, off]));
    }

    band(Rect.fromLTWH(0, 0, sz, _h), Offset.zero, Offset(sz, 0));
    band(Rect.fromLTWH(_w - sz, 0, sz, _h), const Offset(_w, 0), Offset(_w - sz, 0));
    band(Rect.fromLTWH(0, _h - sz, _w, sz), const Offset(0, _h), Offset(0, _h - sz));
    _fill.shader = null;
  }

  // ---- HUD・表示 ------------------------------------------------------------

  void _hud() {
    final w = world;
    _txt('SCORE', 20, 14, 18, Palette.hudLabel, align: TextAlignH.left);
    _txt(formatScore(fx.dispScore), 20, 38, 32, Palette.white, align: TextAlignH.left, weight: 900);
    final boss = w.boss;
    _txt(boss != null ? 'BOSS ${boss.index + 1}' : 'WAVE', 400, 14, 18, Palette.hudLabel);
    _txt('${w.wave.number}${w.wave.loop > 0 ? '  L${w.wave.loop + 1}' : ''}', 400, 38, 30, Palette.white,
        weight: 900);
    final clear = w.wave.clear;
    if (boss != null) {
      final tm = boss.time.ceil();
      _txt('TIME', 530, 14, 18, Palette.hudLabel);
      _txt('$tm', 530, 38, 30, tm <= 10 ? Palette.red : Palette.white, weight: 900);
    } else if (clear is SurviveClear) {
      final left = math.max(0, (clear.seconds - w.waveTime).ceil());
      _txt('SURVIVE', 530, 14, 18, Palette.hudLabel);
      _txt('$left', 530, 38, 30, left <= 5 ? Palette.yellow : Palette.white, weight: 900);
    } else {
      _txt('CHAIN', 530, 14, 18, Palette.hudLabel);
      _txt('${w.streak}', 530, 38, 30, Palette.white, weight: 900);
    }
    // ヒート
    const bx = 680.0, by = 30.0, bw = 340.0, bh = 16.0;
    final st = w.od ? 4 : w.stage;
    _txt(w.od ? 'OVERDRIVE ${math.max(0, w.odTime).toStringAsFixed(1)}s' : 'HEAT  LV${st + 1}', bx, 14, 18,
        w.od ? Palette.magenta : Palette.hudLabel,
        align: TextAlignH.left);
    _c.drawRect(const Rect.fromLTWH(bx, by, bw, bh), _fill..color = const Color(0xFF16132C));
    final tun = w.tuning;
    if (w.od) {
      final k = (w.odTime / tun.odMaxTime).clamp(0.0, 1.0);
      _c.drawRect(
          Rect.fromLTWH(bx, by, bw * k, bh),
          _fill
            ..shader = ui.Gradient.linear(
                const Offset(bx, 0), const Offset(bx + bw, 0), const [Palette.magenta, Palette.yellow]));
      _fill.shader = null;
      _c.drawRect(Rect.fromLTWH(bx + bw * (tun.odTime / tun.odMaxTime), by - 2, 1, bh + 4),
          _fill..color = const Color(0x80FFFFFF));
    } else {
      final k = (w.heat / tun.odHeat).clamp(0.0, 1.0);
      _c.drawRect(Rect.fromLTWH(bx, by, bw * k, bh), _fill..color = Palette.heatBar[st]);
      _fill.color = const Color(0x66FFFFFF);
      for (final m in tun.stageMin.skip(1)) {
        _c.drawRect(Rect.fromLTWH(bx + bw * m / tun.odHeat, by - 2, 1, bh + 4), _fill);
      }
    }
    _c.drawRect(const Rect.fromLTWH(bx + 0.5, by + 0.5, bw, bh), _stroke
      ..color = const Color(0xFF2F2A5A)
      ..strokeWidth = 1);
    final m = w.mult, mc = Palette.multColor[st];
    if (m >= 4) {
      _glowTxt('×$m', _w - 16, 34, 34, mc, blur: 14, align: TextAlignH.right);
    } else {
      _txt('×$m', _w - 16, 34, 34, mc, align: TextAlignH.right, weight: 900);
    }
    if (boss != null) {
      final hp = w.bossHp;
      const bw2 = 360.0, x = _w / 2 - bw2 / 2, y = Field.topY + 6;
      _c.drawRect(const Rect.fromLTWH(x, y, bw2, 6), _fill..color = const Color(0xFF1A1206));
      _c.drawRect(Rect.fromLTWH(x, y, bw2 * hp / boss.maxHp, 6), _fill..color = Palette.blocks['C']!);
      _fill.color = const Color(0x99000000);
      for (final th in boss.def.phaseThresholds) {
        _c.drawRect(Rect.fromLTWH(x + bw2 * th, y, 1, 6), _fill);
      }
    }
    final j = fx.judge;
    if (j != null && w.phase == WorldPhase.playing) {
      final s = 1 + math.max(0.0, 0.15 - j.t) * 3;
      _glowTxt(j.text, w.paddle.x, Field.paddleY - 36 - j.t * 20, (j.big ? 34 : 28) * s,
          withAlpha(j.color, 1 - j.t / 0.6),
          blur: 16);
    }
  }

  void _callouts() {
    if (world.phase == WorldPhase.over) return;
    for (var i = 0; i < fx.callouts.length; i++) {
      final c = fx.callouts[i];
      final a = c.t < 0.1
          ? c.t / 0.1
          : c.t > FxCallout.life - 0.3
              ? math.max(0.0, (FxCallout.life - c.t) / 0.3)
              : 1.0;
      final s = c.t < 0.12 ? 1.5 - 0.5 * (c.t / 0.12) : 1.0;
      final y = 210.0 + i * 64;
      _c.save();
      _c.translate(_w / 2, y);
      _c.scale(s);
      _glowTxt(c.text, 0, 0, c.size, withAlpha(c.color, a * 0.92), blur: 20);
      _c.restore();
      if (c.sub.isNotEmpty) _txt(c.sub, _w / 2, y + c.size * 0.8, 16, withAlpha(Palette.white, a), weight: 900);
    }
  }

  /// ウェーブ開始時などの帯。副題は翻訳する。
  void _banner() {
    final b = fx.banner;
    if (b == null || world.phase == WorldPhase.over) return;
    final a = b.t < 0.15 ? b.t / 0.15 : b.t > 1.4 ? math.max(0.0, (1.8 - b.t) / 0.4) : 1.0;
    final (title, sub, color) = switch (b.kind) {
      BannerKind.wave => ('WAVE ${b.value}', _introText(b.introKey) ?? _goalText(), Palette.white),
      BannerKind.boss => ('WARNING', 'BOSS ${b.value}  —  ${l10n.bannerBoss}', Palette.red),
      BannerKind.overdrive => ('OVERDRIVE', l10n.bannerOverdrive, Palette.magenta),
      BannerKind.bossPhase => ('PHASE ${b.value}', b.value == 2 ? l10n.bannerPhase2 : l10n.bannerPhase3, Palette.white),
      BannerKind.timeOver => ('TIME OVER', l10n.bannerTimeOver, Palette.red),
    };
    _c.drawRect(const Rect.fromLTWH(0, 330, _w, 90), _fill..color = Color.fromRGBO(5, 4, 15, 0.55 * a));
    _glowTxt(title, _w / 2, 362, 40, withAlpha(color, a), blur: 22);
    if (sub != null && sub.isNotEmpty) {
      _txt(sub, _w / 2, 400, 15, withAlpha(Palette.pale, a), family: 'system');
    }
  }

  String? _introText(String? key) => switch (key) {
        'intro.keystone' => l10n.introKeystone,
        'intro.turret' => l10n.introTurret,
        'intro.explosive' => l10n.introExplosive,
        'intro.reflector' => l10n.introReflector,
        'intro.magnet' => l10n.introMagnet,
        'intro.splitter' => l10n.introSplitter,
        'intro.mirror' => l10n.introMirror,
        'intro.loop' => l10n.introLoop('${world.wave.loop + 1}'),
        'intro.parry' => l10n.introParry,
        'intro.pierce' => l10n.introPierce,
        'intro.survive' => l10n.introSurvive,
        'intro.score' => l10n.introScore,
        _ => null,
      };

  /// ステージモードでは、説明がなければクリア条件を出す。
  String? _goalText() {
    if (world.mode is! StageMode) return null;
    return switch (world.wave.clear) {
      AnnihilateClear() => l10n.clearAnnihilate,
      ScoreClear(:final target) => l10n.clearScore(formatScore(target)),
      SurviveClear(:final seconds) => l10n.clearSurvive('${seconds.round()}'),
    };
  }

  void _clearScreen() {
    final w = world;
    final k = math.min(1.0, w.clearT / 0.3);
    _c.drawRect(const Rect.fromLTWH(0, 0, _w, _h), _fill..color = Color.fromRGBO(5, 4, 15, 0.75 * k));
    final last = w.mode.waveAt(w.wave.number + 1) == null;
    final title = w.wave.ending
        ? 'ALL WAVES CLEAR'
        : last && w.mode is StageMode
            ? 'STAGE CLEAR'
            : w.boss != null
                ? 'BOSS DESTROYED'
                : 'WAVE ${w.wave.number} CLEAR';
    _glowTxt(title, _w / 2, 220, 36, withAlpha(w.wave.ending ? Palette.magenta : Palette.cyan, k), blur: 24);
    final bon = w.bonuses;
    for (var i = 0; i < bon.length; i++) {
      if (w.clearT < 0.3 + i * 0.18) continue;
      final y = 290.0 + i * 34;
      _txt(bon[i].label, _w / 2 - 220, y, 15, withAlpha(Palette.pale, k), align: TextAlignH.left);
      _txt('+${formatScore(bon[i].points)}', _w / 2 + 220, y, 17, withAlpha(Palette.yellow, k),
          align: TextAlignH.right, weight: 900);
    }
    final y = 290.0 + bon.length * 34 + 20;
    if (w.clearT > 0.3 + bon.length * 0.18) {
      _c.drawRect(Rect.fromLTWH(_w / 2 - 220, y - 14, 440, 1), _fill..color = const Color(0xFF2F2A5A));
      _txt('SCORE', _w / 2 - 220, y + 10, 15, Palette.hudLabel, align: TextAlignH.left);
      _txt(formatScore(fx.dispScore), _w / 2 + 220, y + 10, 22, Palette.white, align: TextAlignH.right, weight: 900);
    }
    if (w.wave.ending) _txt(l10n.endingSub, _w / 2, y + 60, 16, Palette.magenta, family: 'system');
  }

  @override
  bool shouldRepaint(FieldPainter old) => true;
}
