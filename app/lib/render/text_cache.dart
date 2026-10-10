import 'dart:collection';

import 'package:flutter/painting.dart';

enum TextAlignH { left, center, right }

/// 描画する文字のレイアウト結果を使い回す (毎フレーム TextPainter を作ると重いため)。
class TextCache {
  TextCache({this.capacity = 400});
  final int capacity;
  final LinkedHashMap<String, TextPainter> _cache = LinkedHashMap();

  /// 英数字のドット文字。日本語は [jp] で補う。
  static const pixel = 'Silkscreen';

  /// 日本語のドット文字 (説明文など)。
  static const jp = 'DotGothic16';

  TextPainter get(String text, double size, Color color, {double weight = 700, double glow = 0, String? family}) {
    final key = '$text|${size.toStringAsFixed(1)}|${color.toARGB32()}|$weight|$glow|$family';
    final hit = _cache.remove(key);
    if (hit != null) {
      _cache[key] = hit; // 最近使ったものを末尾へ
      return hit;
    }
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: family ?? pixel,
          fontFamilyFallback: const [jp],
          fontSize: size,
          color: color,
          fontWeight: FontWeight.values[((weight / 100).round() - 1).clamp(0, 8)],
          fontVariations: [FontVariation('wght', weight.clamp(400, 900))],
          shadows: glow > 0 ? [Shadow(color: color, blurRadius: glow)] : null,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    _cache[key] = tp;
    if (_cache.length > capacity) {
      final old = _cache.keys.first;
      _cache.remove(old)?.dispose();
    }
    return tp;
  }

  /// [y] を文字の縦の中心として描く。
  void draw(Canvas canvas, String text, double x, double y, double size, Color color,
      {TextAlignH align = TextAlignH.center, double weight = 700, double glow = 0, String? family}) {
    final tp = get(text, size, color, weight: weight, glow: glow, family: family);
    final dx = switch (align) {
      TextAlignH.left => x,
      TextAlignH.center => x - tp.width / 2,
      TextAlignH.right => x - tp.width,
    };
    tp.paint(canvas, Offset(dx, y - tp.height / 2));
  }

  double width(String text, double size, {double weight = 700}) =>
      get(text, size, const Color(0xFFFFFFFF), weight: weight).width;

  void clear() {
    for (final tp in _cache.values) {
      tp.dispose();
    }
    _cache.clear();
  }
}
