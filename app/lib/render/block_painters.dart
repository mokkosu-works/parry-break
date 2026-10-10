import 'dart:math' as math;
import 'dart:ui';

import '../core/core.dart';
import 'palette.dart';
import 'pixel.dart';
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

const _d = Dot.px;

Rect _inner(Rect r) => r.deflate(2);

// 種類ごとの印 (ドット絵)
final _turret = DotSprite(['#####', '##.##', '..#..']);
final _magnet = DotSprite(['#.#', '#.#', '###']);
final _crack = DotSprite(['#...', '.#.#', '..#.']);
final _diamond = DotSprite(['.#.', '###', '.#.']);
final _crackL = DotSprite(['#.', '.#', '#.']);
final _crackR = DotSprite(['.#', '#.', '.#']);

/// 内側のドット (縁を除く) を (列, 段) で回す。
void _eachInnerDot(Rect i, void Function(int col, int row, double x, double y) fn) {
  final cols = (i.width / _d).floor() - 2, rows = (i.height / _d).floor() - 2;
  for (var row = 0; row < rows; row++) {
    for (var col = 0; col < cols; col++) {
      fn(col, row, i.left + _d + col * _d, i.top + _d + row * _d);
    }
  }
}

/// 通常・砲台・反射・磁力・分裂の描き方 (陰影の付いた四角 + 種類ごとのドットの印 + 残り HP)。
void paintStandardBlock(BlockPaintContext ctx, Block b, Rect r) {
  final c = ctx.canvas, col = ctx.colorOf(b), i = _inner(r);
  final warn = b.type == 'T' && b.telegraph && (ctx.time * 16).floor().isEven;
  bevelRect(c, i, warn ? Dot.white : col);
  final cx = r.center.dx, cy = r.center.dy;
  switch (b.type) {
    case 'T':
      _turret.drawCentered(c, cx, cy, Dot.dark(col));
      c.drawRect(Rect.fromLTWH(cx - _d / 2, cy - _d / 2, _d, _d), pixelPaint(b.telegraph ? Dot.bulletRed : Dot.white));
    case 'R':
      final p = pixelPaint(Dot.light(col));
      _eachInnerDot(i, (col, row, x, y) {
        if ((col + row) % 3 == 0) c.drawRect(Rect.fromLTWH(x, y, _d, _d), p);
      });
    case 'M':
      _magnet.drawCentered(c, cx, cy, Dot.light(col));
    case 'S':
      _crack.drawCentered(c, cx, cy, Dot.dark(col));
  }
  if (b.maxHp > 1 && b.hp > 0) {
    final p = pixelPaint(Dot.white);
    for (var k = 0; k < b.hp; k++) {
      c.drawRect(Rect.fromLTWH(i.right - _d * 2 - k * _d * 2, i.bottom - _d * 2, _d, _d), p);
    }
  }
}

void _mirror(BlockPaintContext ctx, Block b, Rect r) {
  final c = ctx.canvas, i = _inner(r);
  bevelRect(c, i, Dot.steel);
  // 斜めに流れる光 (2 ドット幅)
  final sx = ((ctx.time * 20 + b.x / _d) % 22).floor() - 4;
  final p = pixelPaint(Dot.white);
  _eachInnerDot(i, (col, row, x, y) {
    final k = col + row - sx;
    if (k == 0 || k == 1) c.drawRect(Rect.fromLTWH(x, y, _d, _d), p);
  });
}

void _wall(BlockPaintContext ctx, Block b, Rect r) {
  final c = ctx.canvas, i = _inner(r);
  bevelRect(c, i, Dot.edge);
  final p = pixelPaint(Dot.night);
  _eachInnerDot(i, (col, row, x, y) {
    if ((col + row).isEven) c.drawRect(Rect.fromLTWH(x, y, _d, _d), p);
  });
}

void _keystone(BlockPaintContext ctx, Block b, Rect r) {
  final c = ctx.canvas, i = _inner(r);
  // 外側の枠が 2 段階で明滅する (要石だと分かるように)
  if ((ctx.time * 3).floor().isEven) pixelFrame(c, i.inflate(2), withAlpha(Dot.white, 0.5), d: 2);
  bevelRect(c, i, Dot.white);
  _diamond.drawCentered(c, r.center.dx, r.center.dy, Dot.mustard);
  if (b.hp < b.maxHp) {
    _crackL.draw(c, i.left + _d * 2, i.top + _d, Dot.violet);
    if (b.hp < b.maxHp - 1) _crackR.draw(c, i.right - _d * 4, i.top + _d, Dot.violet);
  }
}

void _explosive(BlockPaintContext ctx, Block b, Rect r) {
  final c = ctx.canvas, i = _inner(r), col = ctx.colorOf(b);
  bevelRect(c, i, Dot.dark(col));
  final p = pixelPaint(col);
  _eachInnerDot(i, (cl, row, x, y) {
    if ((cl + row) % 4 < 2) c.drawRect(Rect.fromLTWH(x, y, _d, _d), p);
  });
  final on = math.sin(ctx.time * 10 + b.x) > 0;
  c.drawRect(Rect.fromCenter(center: r.center, width: _d * 2, height: _d * 2), pixelPaint(on ? Dot.white : Dot.brick));
}

void _core(BlockPaintContext ctx, Block b, Rect r) {
  final c = ctx.canvas, col = Palette.blocks['C']!;
  final cx = r.center.dx, cy = r.center.dy;
  bevelRect(c, r.deflate(2), Dot.dark(Dot.dark(col)));
  pixelFrame(c, r.deflate(2), col);
  // 脈打つ核 (半径が 1 ドットずつ変わる)
  final pulse = (ctx.time * 6).floor() % 4 == 0 ? 1 : 0;
  pixelDisc(c, cx, cy, 4.0 + pulse, b.flash > 0 ? Dot.white : col);
  pixelDisc(c, cx, cy, 2, Dot.white);
  // 残り HP を、円周に並べたドットで表す
  const n = 24;
  final lit = (n * math.max(0, b.hp) / b.maxHp).ceil();
  final all = ringDots(cx, cy, 26, n, from: -math.pi / 2, to: math.pi * 1.5);
  drawDots(c, all, Dot.edge, size: 3);
  if (lit > 0) drawDots(c, all.sublist(0, lit * 2), Dot.brick, size: 3);
  ctx.text.draw(c, '${math.max(0, b.hp)}', cx, cy + 1, 8, Dot.ink, family: TextCache.pixel);
}
