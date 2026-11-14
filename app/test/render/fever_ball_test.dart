import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parry_break/core/core.dart';
import 'package:parry_break/l10n/app_localizations.dart';
import 'package:parry_break/render/block_painters.dart';
import 'package:parry_break/render/field_painter.dart';
import 'package:parry_break/render/fx.dart';
import 'package:parry_break/render/palette.dart';
import 'package:parry_break/render/text_cache.dart';

import '../core/helpers.dart';

/// Issue #263: FEVER TIME 中でも、本物のボールが分身弾・背景・文字と見分けられる。
class _Points {
  _Points(this.color, this.width, this.count, this.x, this.y);
  final Color color;
  final double width;
  final int count;
  final double x, y;
}

class _RecordingCanvas implements Canvas {
  final points = <_Points>[];
  final rects = <(Rect, Color)>[];
  final paragraphs = <Offset>[];

  @override
  void drawRect(Rect rect, Paint paint) => rects.add((rect, paint.color));

  @override
  void drawRawPoints(PointMode pointMode, Float32List p, Paint paint) => points
      .add(_Points(paint.color, paint.strokeWidth, p.length ~/ 2, p[0], p[1]));

  @override
  void drawParagraph(Paragraph paragraph, Offset offset) =>
      paragraphs.add(offset);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

_RecordingCanvas _paint(World w, FxState fx) {
  final painter = FieldPainter(
    world: w,
    fx: fx,
    alpha: () => 1,
    time: () => 1.0,
    text: TextCache(),
    blockPainters: BlockPainterRegistry(),
    l10n: lookupAppLocalizations(const Locale('en')),
    highQuality: false,
    repaint: ValueNotifier(0),
  );
  final c = _RecordingCanvas();
  painter.paint(c, const Size(1200, 750));
  return c;
}

/// Paint の色は 8 ビットに丸められるので、丸めた値で比べる。
bool same(Color a, Color b) => a.toARGB32() == b.toARGB32();

double _luminance(Color c) {
  double f(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b);
}

double _contrast(Color a, Color b) {
  final l1 = _luminance(a), l2 = _luminance(b);
  return (math.max(l1, l2) + 0.05) / (math.min(l1, l2) + 0.05);
}

/// 本物のボール 1 個と分身弾 6 個の盤面。
(World, FxState) _scene({required bool od}) {
  final w = testWorld(endlessMode);
  w.ball
    ..attached = false
    ..x = 600
    ..y = 500
    ..vy = -400;
  w.od = od;
  if (od) {
    for (var i = 0; i < 6; i++) {
      w.phantoms.add(
        Ball(
          x: 200.0 + i * 150,
          y: 300,
          vx: 100,
          vy: -300,
          speed: 360,
          phantom: true,
          life: 5,
        ),
      );
    }
  }
  return (w, FxState(w));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'DotGothic16',
    )..addFont(rootBundle.load('assets/fonts/DotGothic16-subset.ttf'))).load();
    await (FontLoader('Silkscreen')
          ..addFont(rootBundle.load('assets/fonts/Silkscreen-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Silkscreen-Bold.ttf')))
        .load();
  });

  test('FEVER TIME: 分身弾 6 個の中で、本物のボールだけが白く大きく、輪が付く', () {
    final (w, fx) = _scene(od: true);
    final c = _paint(w, fx);
    final dim = Dot.dark(Dot.rose);
    // 分身弾: 小さく (本物の半分のドット)、暗い色、光なし
    final phantoms = c.points.where((p) => same(p.color, dim) && p.count == 12);
    expect(phantoms.length, 6);
    expect(phantoms.every((p) => p.width == Dot.px * 0.5), isTrue);
    // 本物: 白い 12 ドットの球 (分身弾の 2 倍の大きさ) と、回る白い輪 (12 ドット)
    final whites = c.points.where(
      (p) => same(p.color, Dot.white) && p.count == 12 && p.width == Dot.px,
    );
    expect(whites.length, 2, reason: '白い球 1 つと白い輪 1 つ');
    // 分身弾にはピンクの光 (外側の大きな絵) も、ボールと同じ形の残像もない
    final glow = c.points.where((p) => p.color.a < 1 && p.width == Dot.px * 2);
    expect(glow.length, 1, reason: '光は本物のボールの分だけ');
    expect(
      c.points.where((p) => same(p.color, withAlpha(Dot.rose, 0.4))),
      isEmpty,
    );
  });

  test('FEVER TIME 以外のボールは今までどおり (輪も光もない)', () {
    final (w, fx) = _scene(od: false);
    final c = _paint(w, fx);
    expect(
      c.points
          .where((p) => same(p.color, Dot.white) && p.width == Dot.px)
          .length,
      greaterThanOrEqualTo(1),
    );
    expect(c.points.where((p) => p.width == Dot.px * 2), isEmpty);
    expect(
      c.points.where((p) => p.count == 12 && p.width == Dot.px * 0.5),
      isEmpty,
    );
  });

  test('本物のボールの白と FEVER TIME の背景のコントラスト比が、通常時の 7 割以上ある', () {
    final fever = _contrast(Dot.white, Dot.odBg);
    final normal = _contrast(Dot.white, Dot.ink);
    // ignore: avoid_print
    print(
      'contrast: FEVER ${fever.toStringAsFixed(1)} / normal ${normal.toStringAsFixed(1)}',
    );
    expect(fever, greaterThan(7)); // WCAG AAA
    expect(fever / normal, greaterThan(0.7));
    // 以前のボール (ピンク) は背景に溶けていた
    expect(_contrast(Dot.rose, Dot.odBg), lessThan(fever / 2));
  });

  test('FEVER TIME の帯は、盤面の中央に画面幅の帯を広げない', () {
    final (w, fx) = _scene(od: true);
    fx.banner = FxBanner(BannerKind.feverTime, 0, null)..t = 0.8;
    final c = _paint(w, fx);
    bool band(_RecordingCanvas c) => c.rects.any(
      (r) =>
          r.$1.width >= 1200 &&
          r.$1.height >= 48 &&
          (r.$2.a - 0.85).abs() < 0.01,
    );
    expect(band(c), isFalse);
    // ほかの帯 (ラウンド開始) は今までどおり広がる
    fx.banner = FxBanner(BannerKind.round, 1, null)..t = 0.8;
    expect(band(_paint(w, fx)), isTrue);
  });

  test('「演出を控えめにする」では、流れる線を描かない', () {
    int lines(bool calm) {
      final (w, fx) = _scene(od: true);
      final f = FxState(w, reduceEffects: calm);
      return _paint(w, f).rects
          .where((r) => same(r.$2, Dot.odDither) && r.$1.height == 48)
          .length;
    }

    expect(lines(false), greaterThan(0));
    expect(lines(true), 0);
  });
}
