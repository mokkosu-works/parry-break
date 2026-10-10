import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../render/palette.dart';
import 'widgets.dart';

/// ドット絵の共通部品 (タイトル・結果・ポーズで使う)。

/// 硬い影を 2 段重ねた見出し (ドット絵のロゴのように)。
class PixelTitle extends StatelessWidget {
  const PixelTitle(this.text, {super.key, required this.size, required this.color, this.shadow});
  final String text;
  final double size;
  final Color color;

  /// 1 段目の影の色。省くと [color] を暗くした色。
  final Color? shadow;

  @override
  Widget build(BuildContext context) {
    final o = math.max(1.0, (size / 10).roundToDouble());
    TextStyle st(Color c) => pixelFont(size, color: c).copyWith(height: 1);
    return Stack(children: [
      Transform.translate(offset: Offset(o * 2, o * 2), child: Text(text, style: st(Dot.ink))),
      Transform.translate(offset: Offset(o, o), child: Text(text, style: st(shadow ?? Dot.dark(color)))),
      Text(text, style: st(color)),
    ]);
  }
}

/// 小さな札 (例: BALL LOST)。
class PixelTag extends StatelessWidget {
  const PixelTag(this.text, {super.key, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(12, 5, 12, 5),
        decoration: BoxDecoration(color: withAlpha(color, 0.16), border: Border.all(color: color, width: 2)),
        child: Text(text, style: pixelFont(13, color: color, letterSpacing: 2)),
      );
}

/// 計器風の数値表示 (小さなラベルと大きな数字)。
class StatReadout extends StatelessWidget {
  const StatReadout({super.key, required this.label, required this.value, this.highlight = false});
  final String label, value;
  final bool highlight;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: pixelFont(14, color: Palette.pale, letterSpacing: 2)),
          const SizedBox(height: 6),
          Text(value,
              style: pixelFont(28, color: highlight ? Palette.main : Palette.white, weight: 900)
                  .copyWith(fontFeatures: const [FontFeature.tabularFigures()], height: 1)),
        ],
      );
}
