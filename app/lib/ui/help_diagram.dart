import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/core.dart';
import '../render/block_painters.dart';
import '../render/palette.dart';
import '../render/pixel.dart';
import '../render/text_cache.dart';
import '../services/settings.dart';

/// 遊び方の図で見せる場面。
enum HelpTopic { move, parry, timing, chain, over, pause }

/// 遊び方の 1 場面を、本物のブロックの描き方を使って小さな盤面に描き、繰り返し動かす。
class HelpDiagram extends StatefulWidget {
  const HelpDiagram({super.key, required this.topic, required this.controls, this.animate = true});
  final HelpTopic topic;
  final ControlScheme controls;

  /// false なら見どころの 1 コマで止める (動きを減らす設定のとき)。
  final bool animate;

  @override
  State<HelpDiagram> createState() => _HelpDiagramState();
}

class _HelpDiagramState extends State<HelpDiagram> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200));
  final TextCache _text = TextCache(capacity: 40);

  @override
  void initState() {
    super.initState();
    if (widget.animate) _c.repeat();
  }

  @override
  void didUpdateWidget(HelpDiagram old) {
    super.didUpdateWidget(old);
    if (widget.animate && !_c.isAnimating) _c.repeat();
    if (!widget.animate) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    _text.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = !widget.animate || MediaQuery.disableAnimationsOf(context);
    return AspectRatio(
      aspectRatio: _DiagramPainter.w / _DiagramPainter.h,
      child: RepaintBoundary(
        child: CustomPaint(painter: _DiagramPainter(widget.topic, widget.controls, _c, _text, still: still)),
      ),
    );
  }
}

class _DiagramPainter extends CustomPainter {
  _DiagramPainter(this.topic, this.controls, this.anim, this.text, {required this.still}) : super(repaint: anim);
  final HelpTopic topic;
  final ControlScheme controls;
  final Animation<double> anim;
  final TextCache text;
  final bool still;

  /// 盤面の一部を実寸 (ブロック 60×24px) で切り出した大きさ。
  static const w = 600.0, h = 360.0;
  static const paddleY = 300.0, paddleW = 120.0, paddleH = 14.0, ballR = 8.0;

  static final _blocks = standardBlocks();
  static final _painters = BlockPainterRegistry();

  late Canvas _c;
  late double _t;
  final _fill = Paint();
  final _stroke = Paint()..style = PaintingStyle.stroke;

  /// 動きを止めたときに見せるコマ。
  static const _stillAt = {
    HelpTopic.move: 0.2,
    HelpTopic.parry: 0.5,
    HelpTopic.timing: 0.3,
    HelpTopic.chain: 0.36,
    HelpTopic.over: 0.42,
    HelpTopic.pause: 0.5,
  };

  @override
  void paint(Canvas canvas, Size size) {
    _c = canvas;
    _t = still ? _stillAt[topic]! : anim.value;
    final s = size.width / w;
    canvas.save();
    canvas.scale(s);
    canvas.clipRect(const Rect.fromLTWH(0, 0, w, h));
    _field();
    switch (topic) {
      case HelpTopic.move:
        _move();
      case HelpTopic.parry:
        _parry();
      case HelpTopic.timing:
        _timing();
      case HelpTopic.chain:
        _chain();
      case HelpTopic.over:
        _over();
      case HelpTopic.pause:
        _pause();
    }
    canvas.restore();
    canvas.drawRect(
      (Offset.zero & size).deflate(0.5),
      _stroke
        ..color = Palette.hudLine
        ..strokeWidth = 1,
    );
  }

  // ---- 部品 ----

  void _field() {
    _c.drawRect(const Rect.fromLTWH(0, 0, w, h), _fill..color = Palette.bg);
    _grid ??= Float32List.fromList([
      for (var y = 12.0; y < h; y += 24)
        for (var x = 30.0; x < w; x += 60) ...[x, y],
    ]);
    drawDots(_c, _grid!, Dot.night);
  }

  static Float32List? _grid;
  static final _ballSprite = DotSprite(['.##.', '####', '####', '.##.']);

  void _paddle(double x, {Color col = Dot.sky, bool parry = false}) {
    bevelRect(_c, Rect.fromLTWH(x - paddleW / 2, paddleY, paddleW, paddleH + 2), col);
    if (parry) {
      final rx = paddleW / 2 + 15;
      final n = (rx / 5).round();
      drawDots(
          _c,
          Float32List.fromList([
            for (var i = 0; i < n; i++) ...[
              x + math.cos(math.pi + math.pi * i / (n - 1)) * rx,
              paddleY + 2 + math.sin(math.pi + math.pi * i / (n - 1)) * 20,
            ],
          ]),
          Palette.yellow);
    }
  }

  void _ball(Offset p, {Color col = Palette.white, List<Offset> trail = const []}) {
    // 残像: 古いものほど小さく暗い
    for (var i = 0; i < trail.length; i++) {
      final k = 1 - i / trail.length;
      final s = k > 0.66 ? 12.0 : k > 0.33 ? 8.0 : 4.0;
      _c.drawRect(Rect.fromCenter(center: trail[i], width: s, height: s), _fill..color = k > 0.33 ? Dot.dark(col) : Dot.edge);
    }
    _ballSprite.drawCentered(_c, p.dx, p.dy, col);
  }

  void _block(String type, double x, double y, {int hp = 1, double alpha = 1, int tier = -1}) {
    final b = Block(_blocks[type], x, y, 60, 24, hp);
    final ctx = BlockPaintContext(
      _c,
      text,
      _t * 3.2,
      (b) =>
          type == 'N' ? Palette.normalTiers[tier >= 0 ? tier : (y ~/ 24) % 3] : Palette.blocks[b.type] ?? Palette.white,
    );
    if (alpha < 1) _c.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, alpha));
    _painters.of(type)(ctx, b, Rect.fromLTWH(x, y, 60, 24));
    if (alpha < 1) _c.restore();
  }

  void _label(String s, double x, double y, Color col, {double size = 22}) {
    text.draw(_c, s, x + size / 8, y + size / 8, size, Dot.dark(col), weight: 900);
    text.draw(_c, s, x, y, size, col, weight: 900);
  }

  /// 指の位置。[down] なら押している。
  void _finger(Offset p, {bool down = true}) {
    // ドットの丸: 押しているときは薄い輪と芯を足す
    if (down) pixelDisc(_c, p.dx, p.dy, 6.5, withAlpha(Dot.white, 0.2), d: 4);
    drawDots(_c, ringDots(p.dx, p.dy, 16, 16), withAlpha(Dot.white, 0.9));
    if (down) pixelDisc(_c, p.dx, p.dy, 2, withAlpha(Dot.white, 0.9), d: 4);
  }

  void _ring(Offset p, double r, Color col, double a) => drawDots(
      _c, ringDots(p.dx, p.dy, r, math.max(10, (r * 2 * math.pi / 12).round())), withAlpha(col, a.clamp(0.0, 1.0)));

  void _arrow(Offset from, Offset to, Color col) {
    _stroke
      ..color = col
      ..strokeWidth = 3;
    _c.drawLine(from, to, _stroke);
    final d = to - from, a = math.atan2(d.dy, d.dx);
    for (final s in [-1, 1]) {
      _c.drawLine(to, to - Offset.fromDirection(a + s * 0.5, 12), _stroke);
    }
  }

  void _dashedH(double y, Color col, {double x0 = 0, double x1 = w}) {
    _stroke
      ..color = col
      ..strokeWidth = 2;
    for (var x = x0; x < x1; x += 18) {
      _c.drawLine(Offset(x, y), Offset(math.min(x1, x + 10), y), _stroke);
    }
  }

  static double _ease(double t) => t * t * (3 - 2 * t);

  /// [t] を [a]〜[b] の区間の進み具合 (0〜1) にする。
  static double _span(double t, double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);

  // ---- 場面 ----

  /// 操作する場所を示す。領域方式なら左右の半分、レールなら左右の余白の帯とボタン。
  void _zones({required bool left, required bool lit}) {
    final col = left ? Dot.sky : Palette.accent;
    if (controls == ControlScheme.zones) {
      final r = left ? const Rect.fromLTWH(0, 0, w / 2, h) : const Rect.fromLTWH(w / 2, 0, w / 2, h);
      _c.drawRect(r, _fill..color = withAlpha(Dot.white, lit ? 0.07 : 0.03));
      _stroke
        ..color = withAlpha(Palette.pale, 0.35)
        ..strokeWidth = 2;
      for (var y = 0.0; y < h; y += 16) {
        _c.drawLine(Offset(w / 2, y), Offset(w / 2, y + 8), _stroke);
      }
    } else if (left) {
      _c.drawRect(_rail, _fill..color = withAlpha(Dot.white, lit ? 0.1 : 0.04));
      pixelFrame(_c, _rail, withAlpha(col, 0.7), d: 3);
    } else {
      pixelDisc(_c, _parryButton.dx, _parryButton.dy + 4, 8.5, Dot.dark(col), d: 4);
      pixelDisc(_c, _parryButton.dx, _parryButton.dy, 8.5, lit ? col : withAlpha(col, 0.35), d: 4);
      text.draw(_c, 'PARRY', _parryButton.dx, _parryButton.dy, 12, lit ? Dot.ink : col, weight: 800);
    }
  }

  bool get _vertical => controls == ControlScheme.railVertical;
  Rect get _rail => _vertical ? const Rect.fromLTWH(14, 60, 28, 260) : const Rect.fromLTWH(20, 316, 220, 28);
  static const _parryButton = Offset(548, 286);

  void _move() {
    final k = math.sin(_t * math.pi * 2);
    final px = w / 2 + k * 170;
    _zones(left: true, lit: true);
    final Offset f;
    if (controls == ControlScheme.zones) {
      f = Offset(150 + k * 80, 200);
      _arrow(Offset(f.dx - 34, f.dy), Offset(f.dx - 70, f.dy), withAlpha(Dot.sky, 0.8));
      _arrow(Offset(f.dx + 34, f.dy), Offset(f.dx + 70, f.dy), withAlpha(Dot.sky, 0.8));
    } else {
      final r = _rail;
      f = _vertical ? Offset(r.center.dx, r.center.dy - k * 100) : Offset(r.center.dx + k * 80, r.center.dy);
    }
    _ball(Offset(px, paddleY - ballR - 1));
    _paddle(px);
    _finger(f);
  }

  void _parry() {
    // 0〜0.5: ボールが落ちてくる。0.5: パリィ。0.5〜: 黄色い貫通弾で上がっていく
    const hitX = 330.0, top = Offset(470, 20);
    final t = _t;
    final hit = Offset(hitX, paddleY - ballR);
    final hitNow = t >= 0.46 && t < 0.62;
    _zones(left: false, lit: hitNow);
    for (var i = 0; i < 4; i++) {
      _block('N', 180.0 + i * 60, 24);
    }
    if (t < 0.5) {
      final k = _span(t, 0, 0.5);
      final p = Offset.lerp(top, hit, k)!;
      _ball(p, trail: [for (var i = 1; i < 6; i++) Offset.lerp(top, hit, math.max(0, k - i * 0.03))!]);
    } else {
      final k = _span(t, 0.5, 0.95);
      final to = Offset(hitX - 120, 60);
      final p = Offset.lerp(hit, to, k)!;
      if (t < 0.95) {
        _ball(
          p,
          col: Palette.yellow,
          trail: [for (var i = 1; i < 8; i++) Offset.lerp(hit, to, math.max(0, k - i * 0.03))!],
        );
      }
    }
    _paddle(hitX, col: hitNow ? Palette.yellow : Dot.sky, parry: hitNow);
    if (hitNow) {
      final k = _span(t, 0.5, 0.62);
      _ring(hit, 20 + k * 70, Palette.yellow, 1 - k);
      _label('PARRY!', hitX, paddleY - 70 - k * 14, Palette.yellow);
    }
    final tap = controls == ControlScheme.zones ? const Offset(470, 200) : _parryButton;
    _finger(tap, down: hitNow);
    if (t > 0.3 && t < 0.5) {
      final k = _span(t, 0.3, 0.5);
      text.draw(_c, 'TAP', tap.dx, tap.dy - 50, 18, withAlpha(Palette.pale, 0.5 + 0.5 * k), weight: 800);
    }
  }

  void _timing() {
    // 前半: PERFECT で貫通弾が縦に並んだブロックを突き抜ける。後半: JUST で衝撃波が周りを壊す
    final first = _t < 0.5;
    final t = first ? _span(_t, 0, 0.5) : _span(_t, 0.5, 1);
    const cx = 300.0;
    if (first) {
      final y = paddleY - ballR - _ease(_span(t, 0.15, 0.85)) * 310;
      for (var i = 0; i < 4; i++) {
        final by = 24.0 + i * 24;
        if (y > by + 24) _block('N', cx - 30, by);
        for (final dx in [-90.0, 90.0]) {
          _block('N', cx + dx - 30, by);
        }
      }
      if (t > 0.15 && t < 0.85) {
        _ball(Offset(cx, y), col: Palette.yellow, trail: [for (var i = 1; i < 8; i++) Offset(cx, y + i * 12)]);
      }
      _paddle(cx, col: t < 0.3 ? Palette.yellow : Dot.sky, parry: t < 0.3);
      if (t < 0.6) _label('PERFECT', cx, paddleY - 60, Palette.yellow, size: 26);
    } else {
      const hit = Offset(cx, 120);
      final k = _span(t, 0.35, 0.7);
      for (var i = 0; i < 3; i++) {
        for (var j = -2; j <= 2; j++) {
          final b = Offset(cx + j * 60, 36.0 + i * 24);
          final d = (b + const Offset(0, 12) - hit).distance;
          if (k * 170 < d) _block('N', b.dx - 30, b.dy);
        }
      }
      if (t < 0.35) {
        final p = Offset.lerp(const Offset(cx, paddleY - ballR), hit, _span(t, 0.05, 0.35))!;
        _ball(p, col: Palette.justPink);
      }
      if (k > 0 && k < 1) _ring(hit, k * 170, Palette.justPink, 1 - k);
      _paddle(cx, col: t < 0.2 ? Palette.justPink : Dot.sky, parry: t < 0.2);
      if (t < 0.6) _label('JUST', cx, paddleY - 60, Palette.justPink, size: 26);
    }
  }

  void _chain() {
    // 前半: 要石を割ると、ぶら下がっていたブロックが崩れ落ちる。後半: 爆薬が隣へ次々に誘爆する
    final first = _t < 0.5;
    final t = first ? _span(_t, 0, 0.5) : _span(_t, 0.5, 1);
    if (first) {
      const kx = 270.0, ky = 24.0;
      final broken = t > 0.35;
      final fall = _ease(_span(t, 0.4, 0.95));
      _block('#', kx - 120, ky);
      _block('#', kx + 120, ky);
      if (!broken) _block('K', kx, ky, hp: 3);
      for (var i = 1; i <= 4; i++) {
        for (var j = -1; j <= 1; j++) {
          _block('N', kx + j * 60, ky + i * 24 + fall * (200 + i * 20), alpha: 1 - fall * 0.8, tier: i % 3);
        }
      }
      final hit = const Offset(kx + 90, ky + 24 + ballR);
      if (t < 0.35) {
        _ball(Offset.lerp(const Offset(kx + 200, paddleY - 20), hit, _span(t, 0, 0.35))!);
      } else if (t < 0.6) {
        _ring(const Offset(kx + 30, ky + 12), 30 + _span(t, 0.35, 0.6) * 90, Palette.white, 1 - _span(t, 0.35, 0.6));
      }
      if (broken) _label('COLLAPSE', 470, 150, Palette.white);
    } else {
      const y = 120.0;
      const xs = [90.0, 150.0, 210.0, 270.0, 330.0, 390.0, 450.0];
      const start = 0.25, step = 0.08;
      for (var i = 0; i < xs.length; i++) {
        final at = start + i * step;
        if (t < at) {
          _block(i.isEven ? 'B' : 'N', xs[i], y);
        } else if (i.isEven) {
          final k = _span(t, at, at + 0.25);
          if (k < 0.3) pixelDisc(_c, xs[i] + 30, y + 12, 6, Palette.orange, d: 4);
          _ring(Offset(xs[i] + 30, y + 12), 20 + k * 70, Palette.orange, 1 - k);
        }
      }
      if (t < start) {
        _ball(Offset.lerp(const Offset(160, paddleY - 20), Offset(xs[0] + 30, y + 24 + ballR), _span(t, 0, start))!);
      }
      if (t > start + 0.2) _label('CHAIN BLAST', w / 2, 250, Palette.orange);
    }
  }

  void _over() {
    // 前半: ボールが下へ抜ける。後半: ブロックが警告線まで下りてくる
    final first = _t < 0.5;
    final t = first ? _span(_t, 0, 0.5) : _span(_t, 0.5, 1);
    const warnY = 230.0;
    if (first) {
      final p = Offset.lerp(const Offset(200, 40), const Offset(420, h + 20), _ease(_span(t, 0, 0.7)))!;
      _paddle(170);
      _ball(p, trail: [for (var i = 1; i < 6; i++) p - Offset(22.0 * i * 0.6, 40.0 * i * 0.6)]);
      if (t > 0.6) {
        _c.drawRect(const Rect.fromLTWH(0, h - 6, w, 6), _fill..color = withAlpha(Palette.red, 0.8));
        _label('BALL LOST', w / 2, 170, Palette.red, size: 26);
      }
    } else {
      final down = _ease(_span(t, 0, 0.6)) * 110;
      final reached = t >= 0.6;
      final blink = reached && math.sin(_t * 60) > 0;
      _dashedH(warnY, withAlpha(Palette.red, blink ? 1 : 0.6));
      for (var i = 0; i < 4; i++) {
        for (var j = 0; j < 6; j++) {
          _block('N', 120.0 + j * 60, 24.0 + down + i * 24);
        }
      }
      _paddle(300);
      if (reached) {
        _c.drawRect(const Rect.fromLTWH(0, 0, w, h), _fill..color = withAlpha(Palette.red, 0.12));
        _label('WARNING LINE', w / 2, warnY + 26, Palette.red);
      }
    }
  }

  void _pause() {
    // 上の帯 (HUD) と右上の Ⅱ。押すと PAUSED
    _c.drawRect(const Rect.fromLTWH(0, 0, w, 52), _fill..color = Palette.hudBg);
    _c.drawLine(
      const Offset(0, 52),
      const Offset(w, 52),
      _stroke
        ..color = Palette.hudLine
        ..strokeWidth = 2,
    );
    text.draw(_c, 'SCORE', 24, 18, 11, Palette.hudLabel, align: TextAlignH.left);
    text.draw(_c, '048200', 24, 36, 18, Palette.white, align: TextAlignH.left, weight: 800);
    const btn = Offset(560, 26);
    final pressed = _t > 0.35 && _t < 0.45;
    final paused = _t >= 0.4;
    for (var i = 0; i < 4; i++) {
      _block('N', 180.0 + i * 60, 96);
    }
    _paddle(300);
    _ball(const Offset(330, 230));
    if (paused) {
      _c.drawRect(const Rect.fromLTWH(0, 53, w, h - 53), _fill..color = withAlpha(Dot.ink, 0.7));
      _label('PAUSED', w / 2, 200, Palette.yellow, size: 30);
    }
    final b = Rect.fromCenter(center: btn, width: 40, height: 36);
    _c.drawRect(b, _fill..color = withAlpha(Palette.sub, pressed ? 0.5 : 0.15));
    pixelFrame(_c, b, Palette.sub, d: 3);
    for (final dx in [-6.0, 6.0]) {
      _c.drawRect(Rect.fromCenter(center: btn + Offset(dx, 0), width: 5, height: 16), _fill..color = Palette.white);
    }
    if (_t > 0.2 && _t < 0.4) _arrow(const Offset(480, 110), const Offset(540, 56), withAlpha(Palette.pale, 0.7));
    _finger(btn + const Offset(-10, 46), down: pressed);
    if (pressed) _ring(btn, 24 + _span(_t, 0.35, 0.45) * 30, Palette.sub, 1 - _span(_t, 0.35, 0.45));
  }

  @override
  bool shouldRepaint(_DiagramPainter old) => old.topic != topic || old.controls != controls || old.still != still;
}
