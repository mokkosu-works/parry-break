import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'palette.dart';

/// ドット絵を描く道具。1 ドットは [Dot.px] (盤面の論理 px)。
/// 位置は滑らかに動かし (ドットの格子には合わせない)、絵だけをドットで描く。

final _fill = Paint()..isAntiAlias = false;
final _dots = Paint()
  ..isAntiAlias = false
  ..strokeCap = StrokeCap.square;

/// ドットの塗り (角をぼかさない)。
Paint pixelPaint(Color c) => _fill..color = c;

/// 文字列で描いた小さな絵。`#` が塗るドット、それ以外は透明。
class DotSprite {
  DotSprite(List<String> rows)
      : w = rows.fold(0, (m, r) => math.max(m, r.length)),
        h = rows.length,
        _cells = [
          for (var j = 0; j < rows.length; j++)
            for (var i = 0; i < rows[j].length; i++)
              if (rows[j][i] == '#') (i, j),
        ];

  final int w, h;
  final List<(int, int)> _cells;

  /// 左上を ([x], [y]) にして描く。[scale] はドットの大きさの倍率。
  void draw(Canvas c, double x, double y, Color color, {double scale = 1}) {
    final d = Dot.px * scale;
    final pts = Float32List(_cells.length * 2);
    for (var k = 0; k < _cells.length; k++) {
      pts[k * 2] = x + (_cells[k].$1 + 0.5) * d;
      pts[k * 2 + 1] = y + (_cells[k].$2 + 0.5) * d;
    }
    c.drawRawPoints(
        PointMode.points,
        pts,
        _dots
          ..color = color
          ..strokeWidth = d);
  }

  /// 中心を ([cx], [cy]) にして描く。
  void drawCentered(Canvas c, double cx, double cy, Color color, {double scale = 1}) =>
      draw(c, cx - w * Dot.px * scale / 2, cy - h * Dot.px * scale / 2, color, scale: scale);
}

/// 点の並び ([pts] は x, y の組) を、1 ドットの四角で描く。
void drawDots(Canvas c, Float32List pts, Color color, {double size = Dot.px}) => c.drawRawPoints(
    PointMode.points,
    pts,
    _dots
      ..color = color
      ..strokeWidth = size);

/// 上と左が明るく、下と右が暗い、1 ドットの縁の付いた四角 (ファミコン風の陰影)。
void bevelRect(Canvas c, Rect r, Color col, {double d = Dot.px}) {
  c.drawRect(r, _fill..color = col);
  _fill.color = Dot.light(col);
  c.drawRect(Rect.fromLTWH(r.left, r.top, r.width, d), _fill);
  c.drawRect(Rect.fromLTWH(r.left, r.top, d, r.height), _fill);
  _fill.color = Dot.dark(col);
  c.drawRect(Rect.fromLTWH(r.left, r.bottom - d, r.width, d), _fill);
  c.drawRect(Rect.fromLTWH(r.right - d, r.top + d, d, r.height - d), _fill);
}

/// 1 ドットの太さの枠。
void pixelFrame(Canvas c, Rect r, Color col, {double d = Dot.px}) {
  _fill.color = col;
  c.drawRect(Rect.fromLTWH(r.left, r.top, r.width, d), _fill);
  c.drawRect(Rect.fromLTWH(r.left, r.bottom - d, r.width, d), _fill);
  c.drawRect(Rect.fromLTWH(r.left, r.top, d, r.height), _fill);
  c.drawRect(Rect.fromLTWH(r.right - d, r.top, d, r.height), _fill);
}

/// 半径 [r] ドットの、ドットで描いた円 (塗り)。
void pixelDisc(Canvas c, double cx, double cy, double r, Color col, {double d = Dot.px}) {
  _fill.color = col;
  final n = r.ceil();
  for (var j = -n; j < n; j++) {
    final yc = j + 0.5;
    final half = math.sqrt(math.max(0, r * r - yc * yc));
    final k = half.round();
    if (k <= 0) continue;
    c.drawRect(Rect.fromLTWH(cx - k * d, cy + j * d, k * 2 * d, d), _fill);
  }
}

/// 半径 [r] (論理 px) の円周上に、[n] 個のドットを置いた点の並び。[from]〜[to] (ラジアン) の弧だけにもできる。
Float32List ringDots(double cx, double cy, double r, int n, {double from = 0, double to = math.pi * 2}) {
  final pts = Float32List(n * 2);
  for (var k = 0; k < n; k++) {
    final a = from + (to - from) * (n == 1 ? 0.5 : k / (to - from >= math.pi * 2 ? n : n - 1));
    pts[k * 2] = cx + math.cos(a) * r;
    pts[k * 2 + 1] = cy + math.sin(a) * r;
  }
  return pts;
}

/// 下に行くほど濃くなる市松のディザ (盤面の床)。描くたびに作らないよう、範囲ごとに使い回す。
class DitherFloor {
  DitherFloor(Rect area, {double d = Dot.px * 2}) : _pts = _build(area, d), _d = d;
  final Float32List _pts;
  final double _d;

  static Float32List _build(Rect a, double d) {
    final out = <double>[];
    final rows = (a.height / d).floor(), cols = (a.width / d).floor();
    for (var j = 0; j < rows; j++) {
      final t = j / rows;
      for (var i = 0; i < cols; i++) {
        final on = t > 0.66
            ? (i + j).isEven
            : t > 0.33
                ? i.isEven && j.isEven
                : i % 4 == 0 && j % 4 == 0;
        if (on) out.addAll([a.left + (i + 0.5) * d, a.top + (j + 0.5) * d]);
      }
    }
    return Float32List.fromList(out);
  }

  void draw(Canvas c, Color col) => drawDots(c, _pts, col, size: _d);
}
