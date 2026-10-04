import 'dart:math' as math;
import 'dart:ui';

import '../core/core.dart';
import 'palette.dart';
import 'text_cache.dart';

/// ブロックを描くときに使えるもの。
class BlockPaintContext {
  BlockPaintContext(this.canvas, this.text, this.time, this.colorOf);
  final Canvas canvas;
  final TextCache text;

  /// 実時間 (秒)。明滅などのアニメーションに使う。
  double time;
  final Color Function(Block) colorOf;
}

/// [rect] (画面上の位置) にブロック [b] を描く。
typedef BlockPainterFn = void Function(BlockPaintContext ctx, Block b, Rect rect);

/// ブロックの種類 ID → 描き方。新しいブロックを追加したら、ここにも描き方を登録する。
/// 登録がない種類は [paintStandardBlock] で描く。
class BlockPainterRegistry {
  BlockPainterRegistry([Map<String, BlockPainterFn>? painters]) : _painters = {..._defaults, ...?painters};
  final Map<String, BlockPainterFn> _painters;

  void register(String id, BlockPainterFn fn) => _painters[id] = fn;

  BlockPainterFn of(String id) => _painters[id] ?? paintStandardBlock;

  static final Map<String, BlockPainterFn> _defaults = {
    'X': _mirror,
    '#': _wall,
    'K': _keystone,
    'B': _explosive,
    'C': _core,
  };
}

final _fill = Paint();
final _stroke = Paint()..style = PaintingStyle.stroke;

Rect _inner(Rect r) => r.deflate(2);

/// 通常・砲台・反射・磁力・分裂の描き方 (半透明の地 + 枠 + 種類ごとの印 + 残り HP)。
void paintStandardBlock(BlockPaintContext ctx, Block b, Rect r) {
  final c = ctx.canvas, col = ctx.colorOf(b), i = _inner(r);
  c.drawRect(i, _fill..color = withAlpha(col, 0x30 / 255));
  if (b.type == 'T' && b.telegraph) {
    final a = 0.4 + 0.6 * math.sin(ctx.time * 30).abs();
    c.drawRect(i, _fill..color = Color.fromRGBO(255, 60, 90, a * 0.7));
  }
  c.drawRect(i.deflate(1), _stroke
    ..color = col
    ..strokeWidth = 2);
  c.drawRect(Rect.fromLTWH(i.left + 3, i.top + 3, i.width - 6, 2), _fill..color = withAlpha(col, 0x90 / 255));
  final cx = r.center.dx, cy = r.center.dy;
  _stroke
    ..color = col
    ..strokeWidth = 1.5;
  switch (b.type) {
    case 'T':
      _fill.color = b.telegraph ? Palette.white : col;
      c.drawRect(Rect.fromLTWH(cx - 5, r.bottom - 4, 10, 6), _fill);
      c.drawCircle(Offset(cx, cy), 5, _fill);
    case 'R':
      c.save();
      c.clipRect(i);
      final p = Path();
      for (var k = -i.height; k < i.width; k += 10) {
        p
          ..moveTo(i.left + k, i.top)
          ..lineTo(i.left + k + i.height, i.bottom);
      }
      c.drawPath(p, _stroke..color = withAlpha(col, 0.5));
      c.restore();
    case 'M':
      c.drawCircle(Offset(cx, cy), 6, _stroke);
      c.drawCircle(Offset(cx, cy), 2, _fill..color = col);
    case 'S':
      c.drawPath(
          Path()
            ..moveTo(cx - 8, r.top + 5)
            ..lineTo(cx, cy)
            ..lineTo(cx - 4, r.bottom - 5)
            ..moveTo(cx, cy)
            ..lineTo(cx + 9, cy + 2),
          _stroke);
  }
  if (b.maxHp > 1 && b.hp > 0) {
    _fill.color = Palette.white;
    for (var k = 0; k < b.hp; k++) {
      c.drawRect(Rect.fromLTWH(i.right - 6 - k * 6, i.bottom - 5, 3, 3), _fill);
    }
  }
}

void _mirror(BlockPaintContext ctx, Block b, Rect r) {
  final c = ctx.canvas, i = _inner(r);
  c.drawRect(
      i,
      _fill
        ..shader = Gradient.linear(i.topLeft, i.bottomRight, const [
          Color(0xFF8A96A8),
          Color(0xFFF4F8FF),
          Color(0xFFC8D2E0),
          Color(0xFF6A7688),
        ], const [0, 0.45, 0.55, 1]));
  _fill.shader = null;
  final sx = ((ctx.time * 80 + b.x) % (i.width + 30)) - 15;
  c.save();
  c.clipRect(i);
  c.drawPath(
      Path()
        ..moveTo(i.left + sx, i.top)
        ..lineTo(i.left + sx + 8, i.top)
        ..lineTo(i.left + sx - 2, i.bottom)
        ..lineTo(i.left + sx - 10, i.bottom)
        ..close(),
      _fill..color = const Color(0x99FFFFFF));
  c.restore();
}

void _wall(BlockPaintContext ctx, Block b, Rect r) {
  final c = ctx.canvas, i = _inner(r);
  c.drawRect(i, _fill..color = const Color(0xFF1B1B26));
  c.save();
  c.clipRect(i);
  final p = Path();
  for (var k = -i.height; k < i.width; k += 8) {
    p
      ..moveTo(i.left + k, i.bottom)
      ..lineTo(i.left + k + i.height, i.top);
  }
  c.drawPath(p, _stroke
    ..color = const Color(0xFF33334A)
    ..strokeWidth = 2);
  c.restore();
  c.drawRect(i, _stroke
    ..color = ctx.colorOf(b)
    ..strokeWidth = 2);
}

void _keystone(BlockPaintContext ctx, Block b, Rect r) {
  final c = ctx.canvas, i = _inner(r);
  c.drawRect(i,
      _fill..shader = Gradient.linear(i.topCenter, i.bottomCenter, const [Color(0xFFFFFFFF), Color(0xFFCFC6FF)]));
  _fill.shader = null;
  final cx = r.center.dx, cy = r.center.dy;
  const gold = Color(0xFFFFB800);
  c.drawPath(
      Path()
        ..moveTo(cx, cy - 7)
        ..lineTo(cx + 9, cy)
        ..lineTo(cx, cy + 7)
        ..lineTo(cx - 9, cy)
        ..close(),
      _fill..color = gold);
  c.drawRect(i.deflate(1), _stroke
    ..color = gold
    ..strokeWidth = 1.5);
  if (b.hp < b.maxHp) {
    final p = Path()
      ..moveTo(i.left + 6, i.top + 1)
      ..lineTo(i.left + 16, i.top + i.height / 2)
      ..lineTo(i.left + 10, i.bottom - 1);
    if (b.hp < b.maxHp - 1) {
      p
        ..moveTo(i.right - 8, i.top + 1)
        ..lineTo(i.right - 18, i.top + i.height / 2 + 2)
        ..lineTo(i.right - 12, i.bottom - 1);
    }
    c.drawPath(p, _stroke..color = const Color(0xFF3A2A60));
  }
  c.drawRect(i.inflate(2), _stroke
    ..color = Color.fromRGBO(255, 255, 255, 0.35 + 0.25 * math.sin(ctx.time * 5))
    ..strokeWidth = 2);
}

void _explosive(BlockPaintContext ctx, Block b, Rect r) {
  final c = ctx.canvas, i = _inner(r), col = ctx.colorOf(b);
  c.drawRect(i, _fill..color = const Color(0xFF3A1500));
  c.save();
  c.clipRect(i);
  final p = Path();
  for (var k = -i.height; k < i.width; k += 12) {
    p
      ..moveTo(i.left + k, i.bottom)
      ..lineTo(i.left + k + 6, i.bottom)
      ..lineTo(i.left + k + 6 + i.height, i.top)
      ..lineTo(i.left + k + i.height, i.top)
      ..close();
  }
  c.drawPath(p, _fill..color = col);
  c.restore();
  c.drawRect(i.deflate(1), _stroke
    ..color = col
    ..strokeWidth = 2);
  c.drawCircle(r.center, 4, _fill..color = math.sin(ctx.time * 10 + b.x) > 0 ? Palette.white : const Color(0xFFFF3D1A));
}

void _core(BlockPaintContext ctx, Block b, Rect r) {
  final c = ctx.canvas, col = Palette.blocks['C']!;
  final cx = r.center.dx, cy = r.center.dy;
  final pulse = 1 + 0.08 * math.sin(ctx.time * 6);
  c.drawRect(r.deflate(2), _fill..color = const Color(0xFF2A1E05));
  c.drawRect(r.deflate(3), _stroke
    ..color = col
    ..strokeWidth = 2);
  final rr = 18 * pulse;
  c.drawCircle(
      Offset(cx, cy),
      rr,
      _fill
        ..shader = Gradient.radial(Offset(cx, cy), rr, [
          Palette.white,
          b.flash > 0 ? Palette.white : col,
          const Color(0x33FF7800),
        ], const [0, 0.4, 1]));
  _fill.shader = null;
  c.drawArc(Rect.fromCircle(center: Offset(cx, cy), radius: 24), -math.pi / 2,
      math.pi * 2 * math.max(0, b.hp) / b.maxHp, false, _stroke
        ..color = const Color(0xFFFF5A3D)
        ..strokeWidth = 3);
  ctx.text.draw(c, '${math.max(0, b.hp)}', cx, cy + 1, 12, const Color(0xFF1A1000));
}
