import 'dart:ui';

import '../core/core.dart';
import 'palette.dart';
import 'pixel.dart';
import 'text_cache.dart';

/// アイテム (design.md 7.10) のカプセルを、中心 ([cx], [cy]) に描く。
///
/// 横長で角を 1 ドット落とした形に、種類の色と 1 文字の記号。丸い敵弾とは形で見分けられ、
/// 種類は記号で見分けられる (色だけに頼らない)。[lit] は明滅の明るいコマ。
void drawItemCapsule(
  Canvas c,
  TextCache text,
  ItemKind kind,
  double cx,
  double cy, {
  double w = 44,
  double h = 20,
  bool lit = false,
}) {
  const d = Dot.px;
  final col = Palette.items[kind]!;
  final x = cx - w / 2, y = cy - h / 2;
  // 縁 (暗い色)
  final edge = pixelPaint(Dot.dark(col));
  c.drawRect(Rect.fromLTWH(x + d, y, w - d * 2, h), edge);
  c.drawRect(Rect.fromLTWH(x, y + d, w, h - d * 2), edge);
  // 中身と、上の 1 ドットの照り
  c.drawRect(
    Rect.fromLTWH(x + d, y + d, w - d * 2, h - d * 2),
    pixelPaint(lit ? Dot.light(col) : col),
  );
  c.drawRect(
    Rect.fromLTWH(x + d * 2, y + d, w - d * 4, d),
    pixelPaint(lit ? Dot.white : Dot.light(col)),
  );
  // 記号の札
  c.drawRect(
    Rect.fromCenter(center: Offset(cx, cy), width: d * 5, height: h - d * 2),
    pixelPaint(Dot.ink),
  );
  text.draw(c, kind.symbol, cx, cy, 16, Dot.white, family: TextCache.pixel);
}
