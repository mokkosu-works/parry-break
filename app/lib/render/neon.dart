import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../core/core.dart';
import 'fx.dart';
import 'palette.dart';

/// 盤面をネオン調で描く部品。線と面を、太さと濃さを変えて加算合成 ([BlendMode.plus]) で重ねて光らせる。
///
/// MaskFilter (ブラー) は使わない (弾やボールが数十個あっても軽くするため)。
/// [glow] が false のときは外側の光を省く (画質設定「低」)。
abstract final class Neon {
  static const _w = Field.width, _h = Field.height;

  static final _fill = Paint();
  static final _stroke = Paint()..style = PaintingStyle.stroke;
  static final _add = Paint()..blendMode = BlendMode.plus;
  static final _addStroke = Paint()
    ..style = PaintingStyle.stroke
    ..blendMode = BlendMode.plus
    ..strokeCap = StrokeCap.round;
  static final _dots = Paint()
    ..style = PaintingStyle.stroke
    ..blendMode = BlendMode.plus
    ..strokeCap = StrokeCap.round;

  static final _bgNormal = Paint()
    ..shader = Gradient.linear(
      Offset.zero,
      const Offset(0, _h),
      const [Color(0xFF070312), Color(0xFF130833), Color(0xFF2A0C52)],
      const [0.0, 0.55, 1.0],
    );
  static final _bgOd = Paint()
    ..shader = Gradient.linear(
      Offset.zero,
      const Offset(0, _h),
      const [Color(0xFF1A0420), Color(0xFF3A0A48), Color(0xFF6A1260)],
      const [0.0, 0.55, 1.0],
    );

  // ---- 背景 ---------------------------------------------------------------

  /// 暗い紫のグラデーションの地 (OVERDRIVE 中は赤紫)。
  static void background(Canvas c, {required bool od}) =>
      c.drawRect(const Rect.fromLTWH(0, 0, _w, _h), od ? _bgOd : _bgNormal);

  /// 手前へ流れる格子。[speed] が大きいほど速く、[a] が濃いほど明るい。
  static void grid(Canvas c, double t, {required Color col, double speed = 16, double a = 0.07}) {
    _stroke
      ..color = col.withValues(alpha: a)
      ..strokeWidth = 1.5;
    final off = (t * speed) % 80;
    for (var y = Field.topY + off; y < _h; y += 80) {
      c.drawLine(Offset(0, y), Offset(_w, y), _stroke);
    }
    for (var x = 0.0; x <= _w; x += 100) {
      c.drawLine(Offset(x, Field.topY), Offset(x, _h), _stroke);
    }
  }

  /// 遠くの光の点 (ゆっくり流れる)。
  static void stars(Canvas c, double t, Color col) {
    final off = (t * 10) % 120;
    final pts = <double>[];
    for (var row = 0; row < 7; row++) {
      final y = off - 120 + row * 120;
      for (var x = 40.0; x < _w; x += 150) {
        pts.addAll([x + (row.isEven ? 0 : 75), y + (x * 7) % 40]);
      }
    }
    _dots
      ..color = col.withValues(alpha: 0.35)
      ..strokeWidth = 3;
    c.drawRawPoints(PointMode.points, Float32List.fromList(pts), _dots);
  }

  // ---- 形 -----------------------------------------------------------------

  static void _halo(Canvas c, RRect rr, Color col, bool glow, {double k = 1}) {
    if (!glow) return;
    _addStroke
      ..color = col.withValues(alpha: 0.10 * k)
      ..strokeWidth = 10;
    c.drawRRect(rr, _addStroke);
    _addStroke
      ..color = col.withValues(alpha: 0.22 * k)
      ..strokeWidth = 5;
    c.drawRRect(rr, _addStroke);
  }

  /// 光る枠の角丸四角。[fill] は中の塗りの濃さ。
  static void box(Canvas c, Rect r, Color col, {double fill = 0.2, double width = 2, bool glow = true, double radius = 5}) {
    final rr = RRect.fromRectAndRadius(r, Radius.circular(radius));
    _fill.color = col.withValues(alpha: fill);
    c.drawRRect(rr, _fill);
    _halo(c, rr, col, glow);
    _stroke
      ..color = Dot.light(col)
      ..strokeWidth = width;
    c.drawRRect(rr, _stroke);
  }

  static void line(Canvas c, Offset a, Offset b, Color col, {double width = 2, bool glow = true}) {
    if (glow) {
      _addStroke
        ..color = col.withValues(alpha: 0.18)
        ..strokeWidth = width + 6;
      c.drawLine(a, b, _addStroke);
    }
    _addStroke
      ..color = col
      ..strokeWidth = width;
    c.drawLine(a, b, _addStroke);
  }

  static void circle(Canvas c, Offset o, double r, Color col, {double width = 2, bool glow = true, double fill = 0}) {
    if (fill > 0) {
      _fill.color = col.withValues(alpha: fill);
      c.drawCircle(o, r, _fill);
    }
    if (glow) {
      _addStroke
        ..color = col.withValues(alpha: 0.18)
        ..strokeWidth = width + 6;
      c.drawCircle(o, r, _addStroke);
    }
    _addStroke
      ..color = col
      ..strokeWidth = width;
    c.drawCircle(o, r, _addStroke);
  }

  static void arc(Canvas c, Rect oval, double start, double sweep, Color col, {double width = 2, bool glow = true}) {
    if (glow) {
      _addStroke
        ..color = col.withValues(alpha: 0.18)
        ..strokeWidth = width + 6;
      c.drawArc(oval, start, sweep, false, _addStroke);
    }
    _addStroke
      ..color = col
      ..strokeWidth = width;
    c.drawArc(oval, start, sweep, false, _addStroke);
  }

  /// 丸い端の細い棒 (メーターの目盛り・残り時間)。
  static void bar(Canvas c, Rect r, Color col, {double a = 1, bool glow = true}) {
    final rr = RRect.fromRectAndRadius(r, Radius.circular(r.shortestSide / 2));
    if (glow) {
      _addStroke
        ..color = col.withValues(alpha: 0.2 * a)
        ..strokeWidth = 6;
      c.drawRRect(rr, _addStroke);
    }
    _add.color = col.withValues(alpha: a);
    c.drawRRect(rr, _add);
  }

  /// 暗い面 (メーターの溝・HUD の帯)。
  static void well(Canvas c, Rect r, Color col, double a, {double radius = 4}) {
    _fill.color = col.withValues(alpha: a);
    c.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(radius)), _fill);
  }

  /// 光の点 (弾やボールの芯)。
  static void orb(Canvas c, Offset o, double r, Color col, {bool glow = true}) {
    if (glow) {
      _add.color = col.withValues(alpha: 0.07);
      c.drawCircle(o, r * 3.4, _add);
      _add.color = col.withValues(alpha: 0.16);
      c.drawCircle(o, r * 2.1, _add);
    }
    _add.color = col.withValues(alpha: 0.9);
    c.drawCircle(o, r * 1.15, _add);
    _fill.color = Dot.white;
    c.drawCircle(o, r * 0.55, _fill);
  }

  // ---- ブロック -----------------------------------------------------------

  /// ブロック 1 個。種類ごとの印は線で描く。[t] は実時間 (明滅用)。
  static void block(Canvas c, Block b, Rect r, Color col, double t, {required bool glow}) {
    final i = r.deflate(2);
    final cx = r.center.dx, cy = r.center.dy;
    final warn = b.telegraph && (t * 16).floor().isEven;
    switch (b.type) {
      case 'X': // 鏡: 白銀の面に光が流れる
        box(c, i, Dot.steel, fill: 0.28, glow: glow);
        final k = ((t * 0.9 + b.x / 200) % 1.6) - 0.3;
        final x0 = i.left + i.width * k;
        c.save();
        c.clipRRect(RRect.fromRectAndRadius(i, const Radius.circular(5)));
        line(c, Offset(x0, i.bottom), Offset(x0 + i.height, i.top), Dot.white, width: 4, glow: false);
        c.restore();
        return;
      case '#': // 壁: 壊せない。暗い格子
        box(c, i, Dot.edge, fill: 0.5, glow: false, width: 1.5);
        _stroke
          ..color = Dot.edge.withValues(alpha: 0.9)
          ..strokeWidth = 1;
        c.drawLine(i.topLeft, i.bottomRight, _stroke);
        c.drawLine(i.topRight, i.bottomLeft, _stroke);
        return;
      case 'K': // 要石: 脈打つ白い菱形
        final pulse = 0.5 + 0.5 * math.sin(t * 4);
        box(c, i.inflate(1.5 * pulse), Dot.white, fill: 0.16, glow: glow);
        final d = Path()
          ..moveTo(cx, cy - 12)
          ..lineTo(cx + 12, cy)
          ..lineTo(cx, cy + 12)
          ..lineTo(cx - 12, cy)
          ..close();
        _addStroke
          ..color = Dot.mustard
          ..strokeWidth = 2.5;
        c.drawPath(d, _addStroke);
        if (b.hp < b.maxHp) line(c, Offset(cx - 8, cy - 10), Offset(cx - 2, cy), Dot.violet, glow: false);
        if (b.hp < b.maxHp - 1) line(c, Offset(cx + 8, cy - 10), Offset(cx + 2, cy + 2), Dot.violet, glow: false);
        return;
      case 'B': // 爆薬: 脈打つ核
        box(c, i, col, fill: 0.14, glow: glow);
        final on = math.sin(t * 10 + b.x) > 0;
        orb(c, Offset(cx, cy), 5 + (on ? 1.5 : 0), on ? Dot.white : Dot.brick, glow: glow);
        return;
      case 'C': // ボスのコア
        _core(c, b, r, t, glow);
        return;
    }
    // 通常・砲台・反射・磁力・分裂: 色の枠 + 種類ごとの印 + 残り耐久の内枠
    box(c, i, warn ? Dot.white : col, fill: 0.2, glow: glow);
    final dark = Dot.light(col).withValues(alpha: 0.85);
    void muzzle() => orb(c, Offset(cx, cy + 6), 2.5, b.telegraph ? Dot.bulletRed : Dot.white, glow: false);
    _stroke
      ..color = dark
      ..strokeWidth = 2;
    switch (b.type) {
      case 'T': // 砲台: 下向きの砲身
        c.drawLine(Offset(cx, cy - 8), Offset(cx, cy + 5), _stroke);
        muzzle();
      case 'F': // 扇: 3 方向
        for (final dx in [-9.0, 0.0, 9.0]) {
          c.drawLine(Offset(cx, cy - 6), Offset(cx + dx, cy + 6), _stroke);
        }
        muzzle();
      case 'G': // ガトリング: 2 本の砲身
        c.drawLine(Offset(cx - 5, cy - 8), Offset(cx - 5, cy + 6), _stroke);
        c.drawLine(Offset(cx + 5, cy - 8), Offset(cx + 5, cy + 6), _stroke);
        muzzle();
      case 'O': // 全方位
        c.drawCircle(Offset(cx, cy), 8, _stroke);
        muzzle();
      case 'Z': // 回転: 向きを示す線
        final a = b.aim;
        c.drawLine(Offset(cx - math.cos(a) * 9, cy - math.sin(a) * 9),
            Offset(cx + math.cos(a) * 9, cy + math.sin(a) * 9), _stroke);
        c.drawCircle(Offset(cx, cy), 2, _stroke);
      case 'P': // 狙撃: 照準
        c.drawCircle(Offset(cx, cy), 7, _stroke);
        c.drawLine(Offset(cx, cy - 11), Offset(cx, cy + 11), _stroke);
        c.drawLine(Offset(cx - 11, cy), Offset(cx + 11, cy), _stroke);
        muzzle();
      case 'R': // 反射: 斜めの筋
        _stroke.strokeWidth = 1.5;
        for (var k = -1; k <= 1; k++) {
          c.drawLine(Offset(cx - 14 + k * 9, cy + 8), Offset(cx - 2 + k * 9, cy - 8), _stroke);
        }
      case 'M': // 磁力: 馬蹄
        final p = Path()
          ..moveTo(cx - 8, cy - 8)
          ..lineTo(cx - 8, cy + 2)
          ..arcToPoint(Offset(cx + 8, cy + 2), radius: const Radius.circular(8))
          ..lineTo(cx + 8, cy - 8);
        c.drawPath(p, _stroke);
      case 'S': // 分裂: ひび
        final p = Path()
          ..moveTo(cx - 10, cy - 8)
          ..lineTo(cx - 2, cy)
          ..lineTo(cx - 6, cy + 2)
          ..lineTo(cx + 8, cy + 9);
        c.drawPath(p, _stroke);
    }
    for (var k = 1; k < math.min(b.hp, 4); k++) {
      _stroke
        ..color = col.withValues(alpha: 0.7)
        ..strokeWidth = 1.5;
      c.drawRRect(RRect.fromRectAndRadius(i.deflate(k * 4.0 + 1), const Radius.circular(3)), _stroke);
    }
    if (b.flash > 0) {
      _fill.color = Dot.white.withValues(alpha: 0.7);
      c.drawRRect(RRect.fromRectAndRadius(i, const Radius.circular(5)), _fill);
    }
  }

  static void _core(Canvas c, Block b, Rect r, double t, bool glow) {
    final col = Palette.blocks['C']!;
    final o = r.center;
    box(c, r.deflate(2), col, fill: 0.12, glow: glow, radius: 8);
    final pulse = 1 + 0.12 * math.sin(t * 6);
    orb(c, o, 9 * pulse, b.flash > 0 ? Dot.white : col, glow: glow);
    // 残り HP を円弧で表す
    const radius = 28.0;
    _stroke
      ..color = Dot.edge
      ..strokeWidth = 3;
    c.drawCircle(o, radius, _stroke);
    final k = math.max(0, b.hp) / b.maxHp;
    if (k > 0) {
      _addStroke
        ..color = Dot.brick
        ..strokeWidth = 3;
      c.drawArc(Rect.fromCircle(center: o, radius: radius), -math.pi / 2, math.pi * 2 * k, false, _addStroke);
    }
  }

  // ---- 弾・ボール・パドル --------------------------------------------------

  /// 敵弾・撃ち返した弾。
  static void bullet(Canvas c, Offset o, Color col, {required double r, required bool glow, bool strong = false}) {
    orb(c, o, r, col, glow: glow);
    if (strong) circle(c, o, r * 1.9, col, width: 1.5, glow: false);
  }

  /// 光るボール。
  static void ball(Canvas c, Offset o, Color col, {required bool glow, double r = Field.ballR}) => orb(c, o, r, col, glow: glow);

  /// 尾を引く光の筋 (古いほど細く暗い)。
  static void trail(Canvas c, List<Offset> tr, Color col) {
    for (var i = 1; i < tr.length; i++) {
      final k = i / tr.length;
      _addStroke
        ..color = col.withValues(alpha: 0.5 * k)
        ..strokeWidth = 1 + 5 * k;
      c.drawLine(tr[i - 1], tr[i], _addStroke);
    }
  }

  /// 光るパドル。
  static void paddle(Canvas c, Rect r, Color col, {required bool glow}) {
    final rr = RRect.fromRectAndRadius(r, const Radius.circular(6));
    if (glow) {
      _addStroke
        ..color = col.withValues(alpha: 0.18)
        ..strokeWidth = 12;
      c.drawRRect(rr, _addStroke);
    }
    _add.color = col.withValues(alpha: 0.85);
    c.drawRRect(rr, _add);
    if (r.width < 20) return;
    _fill.color = Dot.white.withValues(alpha: 0.8);
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(r.left + 6, r.top + 2, r.width - 12, 3), const Radius.circular(2)),
        _fill);
  }

  // ---- 光線・輪・火花 -------------------------------------------------------

  /// レーザーの予告 (細い縦線 2 本) と発射 (太い光の柱)。
  static void laserWarn(Canvas c, double x, double halfW, bool blink) {
    _fill.color = Dot.bulletRed.withValues(alpha: 0.07);
    c.drawRect(Rect.fromLTRB(x - halfW, Field.topY, x + halfW, _h), _fill);
    for (final lx in [x - halfW, x + halfW]) {
      _dots
        ..color = (blink ? Dot.bulletRed : Dot.dark(Dot.brick)).withValues(alpha: 0.9)
        ..strokeWidth = 2;
      final pts = <double>[];
      for (var y = Field.topY; y < _h; y += 14) {
        pts.addAll([lx, y]);
      }
      c.drawRawPoints(PointMode.points, Float32List.fromList(pts), _dots);
    }
  }

  static void laserBeam(Canvas c, double x, double halfW, double k) {
    for (final (f, col, a) in [(1.0, Dot.brick, 0.25), (0.62, Dot.bulletRed, 0.6), (0.3, Dot.white, 0.95)]) {
      final hw = halfW * f * (0.4 + 0.6 * k);
      _add.color = col.withValues(alpha: a * k);
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(x - hw, Field.topY, x + hw, _h), Radius.circular(hw)), _add);
    }
  }

  /// 広がる光の輪。[k] は 0 (出た瞬間) 〜 1 (消える)。
  static void ring(Canvas c, double x, double y, double rad, Color col, double width, double k) {
    final a = (1 - k) * (1 - k);
    _addStroke
      ..color = col.withValues(alpha: 0.25 * a)
      ..strokeWidth = width * 3 * (1 - k) + 4;
    c.drawCircle(Offset(x, y), rad, _addStroke);
    _addStroke
      ..color = Color.lerp(col, Dot.white, 0.5)!.withValues(alpha: a)
      ..strokeWidth = width * (1 - k) + 1.5;
    c.drawCircle(Offset(x, y), rad, _addStroke);
  }

  /// 火花。色と濃さ・大きさごとにまとめて 1 回で描く (数百個あっても点の描画は数回で済む)。
  static void particles(Canvas c, List<Particle> ps) {
    final groups = <int, List<double>>{};
    for (final p in ps) {
      final a = (1 - p.life / p.max).clamp(0.0, 1.0);
      final step = a > 0.66 ? 3 : a > 0.33 ? 2 : 1;
      final big = p.size > 3 ? 1 : 0;
      final key = (p.color.toARGB32() & 0xFFFFFF) << 8 | step << 4 | big;
      (groups[key] ??= []).addAll([p.x, p.y]);
    }
    for (final e in groups.entries) {
      final step = (e.key >> 4) & 0xF, big = e.key & 1;
      _dots
        ..color = Color(0xFF000000 | (e.key >> 8)).withValues(alpha: 0.3 * step)
        ..strokeWidth = big == 1 ? 6.0 : 4.0;
      c.drawRawPoints(PointMode.points, Float32List.fromList(e.value), _dots);
    }
  }

  // ---- 画面の縁 -----------------------------------------------------------

  /// 左右と下の縁から内側へ消えていく光 (段階が上がる・危険のとき)。
  static void edgeGlow(Canvas c, Color col, double a, double depth) {
    final from = col.withValues(alpha: a), to = col.withValues(alpha: 0);
    void band(Rect r, Offset start, Offset end) {
      _add.shader = Gradient.linear(start, end, [from, to]);
      c.drawRect(r, _add);
    }

    band(Rect.fromLTWH(0, Field.topY, depth, _h - Field.topY), const Offset(0, 0), Offset(depth, 0));
    band(Rect.fromLTWH(_w - depth, Field.topY, depth, _h - Field.topY), const Offset(_w, 0), Offset(_w - depth, 0));
    band(Rect.fromLTWH(0, _h - depth, _w, depth), const Offset(0, _h), Offset(0, _h - depth));
    _add.shader = null;
  }

  /// OVERDRIVE 中、縁を流れる光の点。
  static void marquee(Canvas c, double phase, List<Color> cols) {
    const step = 24.0, inset = 8.0;
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
    final ph = phase.floor();
    for (var i = 0; i < 3; i++) {
      final col = cols[(i + ph) % 3];
      _dots
        ..color = col.withValues(alpha: 0.25)
        ..strokeWidth = 14;
      c.drawRawPoints(PointMode.points, Float32List.fromList(pts[i]), _dots);
      _dots
        ..color = col
        ..strokeWidth = 6;
      c.drawRawPoints(PointMode.points, Float32List.fromList(pts[i]), _dots);
    }
  }
}
