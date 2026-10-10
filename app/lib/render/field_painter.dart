import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/rendering.dart';

import '../core/core.dart';
import '../l10n/app_localizations.dart';
import 'block_painters.dart';
import 'fx.dart';
import 'palette.dart';
import 'pixel.dart';
import 'text_cache.dart';

/// 盤面 (1200×720) を描く。HUD・コールアウト・バナー・ウェーブクリアの表示も含む。
///
/// 見た目は 16 色のドット絵 (1 ドット = [Dot.px])。発光やぼかしは使わず、
/// 陰影は 1 ドットの縁、影は 1 ドットずらしの硬い影、グラデーションはディザや段階の帯で表す。
/// 位置は補間して滑らかに動かす (ドットの格子には合わせない)。
class FieldPainter extends CustomPainter {
  FieldPainter({
    required this.world,
    required this.fx,
    required this.alpha,
    required this.time,
    required this.text,
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
  final BlockPainterRegistry blockPainters;
  final AppLocalizations l10n;

  /// 床のディザなど、なくても遊べる飾りを描くか。
  final bool highQuality;

  /// タイトル画面のデモ表示。HUD・文字の演出を描かない。
  final bool attract;

  static const _w = Field.width, _h = Field.height, _d = Dot.px;
  static final _floor = DitherFloor(const Rect.fromLTWH(0, 440, _w, _h - 440));
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
    canvas.drawRect(const Rect.fromLTWH(0, 0, _w, _h), pixelPaint(w.od ? Dot.odBg : Dot.ink));
    canvas.save();
    if (fx.shake > 0) {
      // 揺れもドット単位で動かす
      double q(double v) => (v / 2).roundToDouble() * 2;
      canvas.translate(q((_rnd.nextDouble() - 0.5) * fx.shake), q((_rnd.nextDouble() - 0.5) * fx.shake));
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
      // 光の強さは段階に丸める (なめらかに消えるとドット絵らしくない)
      final k = (math.min(0.35, fx.flash) * 6).floor() / 6;
      if (k > 0) canvas.drawRect(const Rect.fromLTWH(0, 0, _w, _h), pixelPaint(withAlpha(fx.flashColor, k)));
    }
    canvas.restore();
  }

  /// ドット文字。[size] は 8 の倍数にするとドットが揃う。
  void _txt(String s, double x, double y, double size, Color color,
          {TextAlignH align = TextAlignH.center, double weight = 700, String? family}) =>
      text.draw(_c, s, x, y, size, color, align: align, weight: weight, family: family ?? TextCache.pixel);

  /// 1 ドット右下にずらした硬い影を付けた文字 (見出し・判定)。
  void _bigTxt(String s, double x, double y, double size, Color color, {Color? shadow, TextAlignH align = TextAlignH.center}) {
    final o = size / 8;
    final a = color.a;
    _txt(s, x + o, y + o, size, withAlpha(shadow ?? Dot.dark(color), a), align: align);
    _txt(s, x, y, size, color, align: align);
  }

  /// 点線 (ドットの破線)。
  void _dashedLine(double x0, double y, double x1, double dash, double gap, double offset, Color col, {double h = _d}) {
    final p = pixelPaint(col);
    var x = x0 - (offset % (dash + gap));
    while (x < x1) {
      final a = math.max(x0, x), b = math.min(x1, x + dash);
      if (b > a) _c.drawRect(Rect.fromLTWH(a, y - h / 2, b - a, h), p);
      x += dash + gap;
    }
  }

  // ---- 背景・盤面 ---------------------------------------------------------

  void _background() {
    final od = world.od;
    if (highQuality) _floor.draw(_c, od ? Dot.odDither : Dot.dither);
    if (od) {
      // OVERDRIVE: 速く流れる線 (加速している感じ)
      final p = pixelPaint(Dot.odDither);
      final off = (_t * 900) % 240;
      for (var x = 60.0; x < _w; x += 90) {
        final y0 = off - 240 + (x * 7) % 240;
        for (var y = y0; y < _h; y += 240) {
          _c.drawRect(Rect.fromLTWH(x, y, _d, 48), p);
        }
      }
      return;
    }
    // 遠くの星のような点 (ゆっくり流れる)
    final p = pixelPaint(Dot.night);
    final off = (_t * 12) % 96;
    for (var row = 0; row < 6; row++) {
      final y = off - 96 + row * 96;
      for (var x = 30.0; x < _w; x += 120) {
        _c.drawRect(Rect.fromLTWH(x + (row.isEven ? 0 : 60), y, _d, _d), p);
      }
    }
  }

  void _field() {
    _c.drawRect(const Rect.fromLTWH(0, 0, _w, Field.topY), pixelPaint(world.od ? Dot.odHud : Dot.night));
    _c.drawRect(const Rect.fromLTWH(0, Field.topY - _d, _w, _d), pixelPaint(Dot.edge));
    final danger = world.isDanger;
    final col = danger ? ((_t * 7).floor().isEven ? Dot.bulletRed : Dot.brick) : Dot.dark(Dot.brick);
    _dashedLine(0, Field.warnY, _w, 16, 8, -_t * 32, col);
    if (attract) return;
    _txt('WARNING LINE', _w - 16, Field.warnY - 18, 16, danger ? Dot.bulletRed : Dot.brick, align: TextAlignH.right);
  }

  void _magnetField(Block b) {
    final x = b.x + _ox + b.w / 2, y = b.y + _oy + b.h / 2;
    final rad = world.tuning.magnetRadius;
    final n = (rad * 2 * math.pi / 24).round();
    final spin = (_t * 20 / rad) % (math.pi * 2 / n);
    drawDots(_c, ringDots(x, y, rad, n, from: spin, to: spin + math.pi * 2), withAlpha(Dot.sky, 0.35), size: 3);
    final r = rad - ((_t * 60) % rad);
    final m = math.max(6, (r * 2 * math.pi / 20).round());
    drawDots(_c, ringDots(x, y, r, m), withAlpha(Dot.sky, 0.3 * r / rad), size: 3);
  }

  void _block(BlockPaintContext ctx, Block b, Rect r) {
    blockPainters.of(b.type)(ctx, b, r);
    final i = r.deflate(2);
    // 支えの脈動: 要石から塊へ光が伝わる (どこが繋がっているかが分かる)
    if (b.supported && !b.behavior.anchor) {
      final ph = (_t * 8) % 16;
      if ((ph - b.depth).abs() < 0.75) _c.drawRect(i, pixelPaint(const Color(0x40FFFFFF)));
    }
    if (b.flash > 0) _c.drawRect(i, pixelPaint(Dot.white));
  }

  /// ひびが入って落下を待つブロック (その場で震える)。
  void _cracking() {
    final on = (_t * 25).floor().isEven;
    for (final f in world.falling) {
      final b = f.block;
      final x = b.x + _ox + ((_rnd.nextInt(3) - 1) * 2), y = b.y + _oy + ((_rnd.nextInt(3) - 1) * 2);
      _debrisRect(Rect.fromLTWH(x, y, b.w, b.h), on ? Dot.white : fx.blockColor(b));
    }
    for (final d in fx.debris) {
      if (d.dropped) continue;
      final x = d.x + ((_rnd.nextInt(3) - 1) * 2), y = d.y + ((_rnd.nextInt(3) - 1) * 2);
      _debrisRect(Rect.fromLTWH(x, y, d.w, d.h), on ? Dot.white : d.color);
    }
  }

  void _debris() {
    for (final d in fx.debris) {
      if (!d.dropped) continue;
      _c.save();
      _c.translate(d.x + d.w / 2, d.y + d.h / 2);
      // 回転は 45 度ずつ (ドット絵のコマ送り)
      _c.rotate((d.rot / (math.pi / 4)).round() * math.pi / 4);
      final a = (1 - (d.y - Field.warnY) / 260).clamp(0.15, 1.0);
      _debrisRect(Rect.fromCenter(center: Offset.zero, width: d.w, height: d.h), withAlpha(d.color, a));
      _c.restore();
    }
  }

  void _debrisRect(Rect r, Color col) => bevelRect(_c, r.deflate(2), col);

  // ---- 弾・ボール・パドル --------------------------------------------------

  static final _bullet = DotSprite(['.#.', '###', '.#.']);
  static final _bulletBig = DotSprite(['.##.', '####', '####', '.##.']);
  static final _shard = [
    DotSprite(['.#.', '.#.', '###']),
    DotSprite(['#..', '###', '#..']),
    DotSprite(['###', '.#.', '.#.']),
    DotSprite(['..#', '###', '..#']),
  ];

  void _bullets() {
    for (final u in world.bullets) {
      if (u.dead) continue;
      final x = _lerp(u.prevX, u.x), y = _lerp(u.prevY, u.y);
      final c = switch (u) {
        Bullet(hostile: false, :final red) => red ? Dot.mustard : Dot.ice,
        Bullet(kind: BulletKind.shard) => Dot.steel,
        Bullet(kind: BulletKind.shrapnel) => Dot.orange,
        Bullet(:final red) => red ? Dot.bulletRed : Dot.bullet,
      };
      if (u.hostile && u.kind == BulletKind.shard) {
        // 回転は 4 コマ
        final f = _shard[(u.life * 8 / (math.pi / 2)).floor() % 4];
        f.drawCentered(_c, x, y, c);
        continue;
      }
      // 2 コマで明滅する縁 (弾幕が派手に見え、背景から浮く)
      final blink = ((_t * 12).floor() + u.hashCode).isEven;
      if (u.hostile && u.red) {
        _bulletBig.drawCentered(_c, x, y, blink ? Dot.white : c, scale: 1.25);
        _bulletBig.drawCentered(_c, x, y, c);
      } else {
        _bulletBig.drawCentered(_c, x, y, blink ? Dot.light(c) : Dot.dark(c), scale: 1.25);
        _bullet.drawCentered(_c, x, y, c);
      }
      _c.drawRect(Rect.fromCenter(center: Offset(x, y), width: _d, height: _d), pixelPaint(Dot.white));
    }
  }

  static final _ballSprite = DotSprite(['.##.', '####', '####', '.##.']);

  void _ball(Ball b) {
    final w = world;
    final st = w.stage;
    final pierce = b.pierce > 0 || w.od || b.phantom;
    final col = w.od || b.phantom
        ? Dot.rose
        : b.breaker
            ? Dot.blush
            : pierce
                ? Dot.mustard
                : const [Dot.white, Dot.white, Dot.ice, Dot.teal][st];
    final tr = fx.trails[b.id] ?? const <Offset>[];
    // 残像: 古いものほど小さく暗い (3 段階)
    for (var i = 0; i < tr.length; i++) {
      final a = (i + 1) / tr.length;
      final s = a > 0.66 ? 3.0 : a > 0.33 ? 2.0 : 1.0;
      final c = a > 0.66 ? col : a > 0.33 ? Dot.dark(col) : Dot.edge;
      if (w.od && i % 4 == 0) {
        _ballSprite.drawCentered(_c, tr[i].dx, tr[i].dy, withAlpha(Dot.rose, 0.4));
      }
      _c.drawRect(Rect.fromCenter(center: tr[i], width: _d * s, height: _d * s), pixelPaint(c));
    }
    final x = _lerp(b.prevX, b.x), y = _lerp(b.prevY, b.y);
    if (pierce) _ballSprite.drawCentered(_c, x, y, withAlpha(col, 0.35), scale: 1.75);
    _ballSprite.drawCentered(_c, x, y, col);
    _c.drawRect(Rect.fromLTWH(x - _d, y - _d, _d, _d), pixelPaint(Dot.white));
    if (b.breaker) {
      final a0 = (_t * 1000 / 120 / (math.pi / 4)).floor() * math.pi / 4;
      drawDots(_c, ringDots(x, y, 16, 8, from: a0, to: a0 + math.pi * 2), Dot.blush);
    }
    if (b.pierce > 0 && !w.od && !b.phantom) {
      final pts = <double>[];
      for (var k = 0; k < b.pierce; k++) {
        final a = _t * 1000 / 150 + k * math.pi * 2 / b.pierce;
        pts.addAll([x + math.cos(a) * 16, y + math.sin(a) * 16]);
      }
      drawDots(_c, Float32List.fromList(pts), Dot.mustard);
    }
    if (b.phantom || attract) return;
    if (b.flight >= 5 && !b.attached) {
      _txt('${b.flight} HIT', x, y - 24, 16, b.flight >= 15 ? Dot.mustard : Dot.dim);
    }
    if (b.attached) {
      if (w.countdown > 0) {
        _bigTxt('READY', x, y - 32, 24, Dot.mustard, shadow: Dot.brick);
      } else if ((_t * 2).floor().isEven) {
        _bigTxt('TAP', x, y - 32, 24, Dot.white, shadow: Dot.edge);
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
    var col = Dot.sky;
    if (stunned) {
      col = (_t * 20).floor().isEven ? Dot.brick : Dot.edge;
    } else if (p.invuln > 0 && (_t * 15).floor().isEven) {
      col = Dot.edge; // 被弾後の無敵: 点滅
    } else if (cooling) {
      col = Dot.steel;
    } else if (pr.active) {
      col = Dot.mustard;
    }
    bevelRect(_c, Rect.fromLTWH(x, y, pw, Field.paddleH + 2), col);
    // 両端の印
    final dark = pixelPaint(Dot.dark(col));
    _c.drawRect(Rect.fromLTWH(x + _d * 2, y + _d, _d, _d), dark);
    _c.drawRect(Rect.fromLTWH(x + pw - _d * 3, y + _d, _d, _d), dark);
    if (pr.active && w.phase == WorldPhase.playing) {
      // パリィの受付: 広がるドットの弧
      final k = ((w.t - pr.press) / w.tuning.parryWindow).clamp(0.0, 1.0);
      final rx = pw / 2 + 8 + k * 14, ry = 14 + k * 10;
      final n = (rx / 5).round();
      final pts = Float32List(n * 2);
      for (var i = 0; i < n; i++) {
        final a = math.pi + math.pi * i / (n - 1);
        pts[i * 2] = px + math.cos(a) * rx;
        pts[i * 2 + 1] = y + 2 + math.sin(a) * ry;
      }
      drawDots(_c, pts, (k * 3).floor().isEven ? Dot.mustard : Dot.white);
    }
    if (cooling && !stunned) {
      final k = ((pr.cooldownUntil - w.t) / w.tuning.parryCooldown).clamp(0.0, 1.0);
      _c.drawRect(Rect.fromLTWH(x, y + Field.paddleH + 6, pw * k, _d), pixelPaint(Dot.dim));
    }
    if (stunned) {
      _c.drawRect(Rect.fromLTWH(x, y + Field.paddleH + 6, pw * (p.stun / w.tuning.stunTime), _d), pixelPaint(Dot.brick));
    }
  }

  void _lasers() {
    for (final l in world.lasers) {
      if (l.t < l.warn) {
        final blink = (_t * 12).floor().isEven;
        _c.drawRect(Rect.fromLTWH(l.x - l.w / 2, Field.topY, l.w, _h - Field.topY), pixelPaint(const Color(0x14FF3B5C)));
        final p = pixelPaint(blink ? Dot.bulletRed : Dot.dark(Dot.brick));
        for (final lx in [l.x - l.w / 2, l.x + l.w / 2]) {
          for (var y = Field.topY; y < _h; y += 16) {
            _c.drawRect(Rect.fromLTWH(lx - _d / 2, y, _d, 8), p);
          }
        }
        if (blink) _bigTxt('!', l.x, Field.paddleY - 40, 32, Dot.bulletRed);
      } else {
        // 発射: 中心ほど明るい段階の帯 (グラデーションの代わり)
        final k = math.max(0.0, 1 - (l.t - l.warn) / l.fire);
        for (final (f, c) in [(1.0, Dot.dark(Dot.brick)), (0.66, Dot.bulletRed), (0.33, Dot.white)]) {
          final hw = l.w * f * (0.4 + 0.6 * k);
          _c.drawRect(Rect.fromLTWH(l.x - hw, Field.topY, hw * 2, _h - Field.topY), pixelPaint(withAlpha(c, k)));
        }
      }
    }
  }

  // ---- エフェクト ---------------------------------------------------------

  void _rings() {
    for (final r in fx.rings) {
      final k = r.t / FxRing.life;
      final rad = r.r * (0.2 + 0.8 * math.sqrt(k));
      final n = math.max(8, (rad * 2 * math.pi / 14).round());
      drawDots(_c, ringDots(r.x, r.y, rad, n), withAlpha(r.color, k < 0.66 ? 1 : 0.5),
          size: math.max(2.0, r.width * (1 - k) + 2));
    }
  }

  void _particles() {
    for (final p in fx.particles) {
      final a = 1 - p.life / p.max;
      // 大きさは 1 ドットか 2 ドット、色は途中で暗くなる
      final s = p.size > 3 && a > 0.5 ? _d * 2 : _d;
      _c.drawRect(Rect.fromCenter(center: Offset(p.x, p.y), width: s, height: s),
          pixelPaint(a > 0.4 ? p.color : Dot.dark(p.color)));
    }
  }

  void _popups() {
    for (final p in fx.popups) {
      if (p.t > 0.6 && (p.t * 20).floor().isEven) continue; // 消える前に点滅
      _txt(p.text, p.x, p.y, p.size, p.color);
    }
  }

  void _edgeFx() {
    final w = world;
    if (w.phase != WorldPhase.playing) return;
    if (w.od) {
      _marquee();
    } else if (w.stage >= 2) {
      _edgeBands(w.stage == 3 ? Dot.mustard : Dot.teal, 0.3, (_t * 4).floor().isEven ? 3 : 2);
    }
    if (w.isDanger) _edgeBands(Dot.bulletRed, 0.45, (_t * 7).floor().isEven ? 4 : 2);
  }

  /// OVERDRIVE 中、盤面のふちを回る電飾 (ゲーム筐体の電飾のように、色が順に送られる)。
  /// 残り 2 秒を切ると全体が点滅して、終わりが近いことを知らせる。
  void _marquee() {
    final w = world;
    if (w.odTime < 2 && (_t * 8).floor().isEven) return;
    const step = 24.0, inset = _d * 2;
    final pts = <List<double>>[[], [], []];
    var k = 0;
    void put(double x, double y) => pts[k++ % 3].addAll([x, y]);
    for (var x = inset; x < _w - inset; x += step) {
      put(x, Field.topY + inset);
    }
    for (var y = Field.topY + inset; y < _h - inset; y += step) {
      put(_w - inset, y);
    }
    for (var x = _w - inset; x > inset; x -= step) {
      put(x, _h - inset);
    }
    for (var y = _h - inset; y > Field.topY + inset; y -= step) {
      put(inset, y);
    }
    final phase = (_t * 12).floor();
    final cols = [Dot.white, Dot.rose, Dot.dark(Dot.rose)];
    for (var i = 0; i < 3; i++) {
      drawDots(_c, Float32List.fromList(pts[i]), cols[(i + phase) % 3], size: _d * 2);
    }
  }

  /// 画面の左右と下の端に、外側ほど濃い段階の帯を描く (発光の代わり)。
  void _edgeBands(Color c, double a, int steps) {
    for (var i = 0; i < steps; i++) {
      final p = pixelPaint(withAlpha(c, a * (1 - i / steps)));
      final o = i * _d * 2, s = _d * 2;
      _c.drawRect(Rect.fromLTWH(o, Field.topY, s, _h - Field.topY), p);
      _c.drawRect(Rect.fromLTWH(_w - o - s, Field.topY, s, _h - Field.topY), p);
      _c.drawRect(Rect.fromLTWH(o + s, _h - o - s, _w - (o + s) * 2, s), p);
    }
  }

  // ---- HUD・表示 ------------------------------------------------------------

  void _hud() {
    final w = world;
    _txt('SCORE', 20, 14, 16, Dot.dim, align: TextAlignH.left);
    _txt(formatScore(fx.dispScore), 20, 38, 24, Dot.white, align: TextAlignH.left);
    final boss = w.boss;
    _txt(boss != null ? 'BOSS ${boss.index + 1}' : 'WAVE', 400, 14, 16, Dot.dim);
    _txt('${w.wave.number}${w.wave.loop > 0 ? ' L${w.wave.loop + 1}' : ''}', 400, 38, 24, Dot.white);
    final clear = w.wave.clear;
    if (boss != null) {
      final tm = boss.time.ceil();
      _txt('TIME', 530, 14, 16, Dot.dim);
      _txt('$tm', 530, 38, 24, tm <= 10 ? Dot.bulletRed : Dot.white);
    } else if (clear is SurviveClear) {
      final left = math.max(0, (clear.seconds - w.waveTime).ceil());
      _txt('SURVIVE', 530, 14, 16, Dot.dim);
      _txt('$left', 530, 38, 24, left <= 5 ? Dot.mustard : Dot.white);
    } else {
      _txt('CHAIN', 530, 14, 16, Dot.dim);
      _txt('${w.streak}', 530, 38, 24, Dot.white);
    }
    // ヒート: ドットのマスを並べたメーター
    const bx = 680.0, by = 28.0, bw = 340.0, bh = 16.0;
    final st = w.od ? 4 : w.stage;
    _txt(w.od ? 'OVERDRIVE ${math.max(0, w.odTime).toStringAsFixed(1)}s' : 'HEAT LV${st + 1}', bx, 14, 16,
        w.od ? Dot.rose : Dot.dim,
        align: TextAlignH.left);
    final tun = w.tuning;
    const cell = 12.0, gap = 4.0;
    final cells = ((bw + gap) / (cell + gap)).floor();
    final k = w.od ? (w.odTime / tun.odMaxTime).clamp(0.0, 1.0) : (w.heat / tun.odHeat).clamp(0.0, 1.0);
    final lit = (cells * k).ceil();
    for (var i = 0; i < cells; i++) {
      final r = Rect.fromLTWH(bx + i * (cell + gap), by, cell, bh);
      if (i >= lit) {
        _c.drawRect(r, pixelPaint(Dot.dither));
        continue;
      }
      final c = w.od ? ((i + (_t * 12).floor()) % 3 == 0 ? Dot.white : Dot.rose) : Palette.heatBar[st];
      bevelRect(_c, r, c);
    }
    if (!w.od) {
      // 段階の境目
      final p = pixelPaint(Dot.dim);
      for (final m in tun.stageMin.skip(1)) {
        final i = (cells * m / tun.odHeat).round();
        _c.drawRect(Rect.fromLTWH(bx + i * (cell + gap) - gap / 2 - 1, by - 4, 2, bh + 8), p);
      }
    }
    final m = w.mult, mc = Palette.multColor[st];
    _bigTxt('×$m', _w - 16, 34, 32, mc, align: TextAlignH.right);
    if (boss != null) {
      final hp = w.bossHp;
      const bw2 = 360.0, x = _w / 2 - bw2 / 2, y = Field.topY + 6;
      _c.drawRect(const Rect.fromLTWH(x, y, bw2, 8), pixelPaint(Dot.night));
      bevelRect(_c, Rect.fromLTWH(x, y, bw2 * hp / boss.maxHp, 8), Palette.blocks['C']!, d: 2);
      final p = pixelPaint(Dot.ink);
      for (final th in boss.def.phaseThresholds) {
        _c.drawRect(Rect.fromLTWH(x + bw2 * th - 1, y, 2, 8), p);
      }
    }
    final j = fx.judge;
    if (j != null && w.phase == WorldPhase.playing) {
      // 出た瞬間だけ 1 段大きく (なめらかに縮めない)
      final size = (j.big ? 40.0 : 32.0) + (j.t < 0.08 ? 8 : 0);
      _bigTxt(j.text, w.paddle.x, Field.paddleY - 36 - (j.t * 20 / 4).floor() * 4, size, j.color);
    }
  }

  void _callouts() {
    if (world.phase == WorldPhase.over) return;
    for (var i = 0; i < fx.callouts.length; i++) {
      final c = fx.callouts[i];
      final fading = c.t > FxCallout.life - 0.3;
      if (fading && (c.t * 20).floor().isEven) continue;
      final pop = c.t < 0.08 ? 8.0 : 0.0;
      final y = 210.0 + i * 64;
      _bigTxt(c.text, _w / 2, y, c.size + pop, c.color);
      if (c.sub.isNotEmpty) _txt(c.sub, _w / 2, y + c.size * 0.8, 16, Dot.white);
    }
  }

  /// ウェーブ開始時などの帯。副題は翻訳する。
  void _banner() {
    final b = fx.banner;
    if (b == null || world.phase == WorldPhase.over) return;
    // 帯は上下から開いて閉じる (高さを 4 段階で変える)
    final open = b.t < 0.15 ? b.t / 0.15 : b.t > 1.4 ? math.max(0.0, (1.8 - b.t) / 0.4) : 1.0;
    final h = (90 * open / 24).ceil() * 24.0;
    final (title, sub, color) = switch (b.kind) {
      BannerKind.wave => ('WAVE ${b.value}', _introText(b.introKey) ?? _goalText(), Dot.white),
      BannerKind.boss => ('WARNING', 'BOSS ${b.value}  —  ${l10n.bannerBoss}', Dot.bulletRed),
      BannerKind.overdrive => ('OVERDRIVE', l10n.bannerOverdrive, Dot.rose),
      BannerKind.bossPhase => ('PHASE ${b.value}', b.value == 2 ? l10n.bannerPhase2 : l10n.bannerPhase3, Dot.white),
      BannerKind.timeOver => ('TIME OVER', l10n.bannerTimeOver, Dot.bulletRed),
    };
    if (h <= 0) return;
    final band = Rect.fromLTWH(0, 375 - h / 2, _w, h);
    _c.drawRect(band, pixelPaint(withAlpha(Dot.ink, 0.85)));
    _c.drawRect(Rect.fromLTWH(0, band.top, _w, _d), pixelPaint(color));
    _c.drawRect(Rect.fromLTWH(0, band.bottom - _d, _w, _d), pixelPaint(color));
    if (open < 0.7) return;
    _bigTxt(title, _w / 2, 360, 40, color, shadow: color == Dot.white ? Dot.edge : Dot.dark(color));
    if (sub != null && sub.isNotEmpty) {
      _txt(sub, _w / 2, 400, 15, Dot.white, family: TextCache.system);
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
    _c.drawRect(const Rect.fromLTWH(0, 0, _w, _h), pixelPaint(withAlpha(Dot.ink, (k * 3).ceil() / 3 * 0.8)));
    if (k < 1) return;
    final last = w.mode.waveAt(w.wave.number + 1) == null;
    final title = w.wave.ending
        ? 'ALL WAVES CLEAR'
        : last && w.mode is StageMode
            ? 'STAGE CLEAR'
            : w.boss != null
                ? 'BOSS DESTROYED'
                : 'WAVE ${w.wave.number} CLEAR';
    _bigTxt(title, _w / 2, 220, 40, w.wave.ending ? Dot.rose : Dot.mustard,
        shadow: w.wave.ending ? Dot.violet : Dot.brick);
    final bon = w.bonuses;
    for (var i = 0; i < bon.length; i++) {
      if (w.clearT < 0.3 + i * 0.18) continue;
      final y = 290.0 + i * 34;
      _txt(bon[i].label, _w / 2 - 220, y, 16, Dot.dim, align: TextAlignH.left);
      _txt('+${formatScore(bon[i].points)}', _w / 2 + 220, y, 16, Dot.mustard, align: TextAlignH.right);
    }
    final y = 290.0 + bon.length * 34 + 20;
    if (w.clearT > 0.3 + bon.length * 0.18) {
      _dashedLine(_w / 2 - 220, y - 14, _w / 2 + 220, 8, 4, 0, Dot.edge);
      _txt('SCORE', _w / 2 - 220, y + 10, 16, Dot.dim, align: TextAlignH.left);
      _txt(formatScore(fx.dispScore), _w / 2 + 220, y + 10, 24, Dot.white, align: TextAlignH.right);
    }
    if (w.wave.ending) _txt(l10n.endingSub, _w / 2, y + 60, 16, Dot.rose, family: TextCache.system);
  }

  @override
  bool shouldRepaint(FieldPainter old) => true;
}
