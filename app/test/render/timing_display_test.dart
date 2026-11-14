import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parry_break/core/core.dart';
import 'package:parry_break/l10n/app_localizations.dart';
import 'package:parry_break/render/block_painters.dart';
import 'package:parry_break/render/field_painter.dart';
import 'package:parry_break/render/fx.dart';
import 'package:parry_break/render/text_cache.dart';

import '../core/helpers.dart';

/// 描いた文字を覚えておく。
class _RecordingText extends TextCache {
  final drawn = <String>[];

  @override
  void draw(
    Canvas canvas,
    String text,
    double x,
    double y,
    double size,
    Color color, {
    TextAlignH align = TextAlignH.center,
    double weight = 700,
    String? family,
  }) => drawn.add(text);
}

ParrySucceeded _parry(ParryGrade grade, double offset) => ParrySucceeded(
  grade: grade,
  target: ParryTarget.ball,
  x: 600,
  y: Field.paddleY,
  paddleX: 600,
  streak: 1,
  offset: offset,
);

/// [w] と [fx] の盤面を描き、描いた文字を返す。
Future<List<String>> _paint(WidgetTester tester, World w, FxState fx) async {
  tester.view
    ..physicalSize = const Size(1200, 720)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final text = _RecordingText();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: CustomPaint(
        painter: FieldPainter(
          world: w,
          fx: fx,
          alpha: () => 1,
          time: () => 0.1,
          text: text,
          blockPainters: BlockPainterRegistry(),
          l10n: lookupAppLocalizations(const Locale('en')),
          highQuality: true,
          repaint: ValueNotifier(0),
        ),
        size: const Size(1200, 720),
      ),
    ),
  );
  expect(tester.takeException(), isNull);
  return text.drawn;
}

void main() {
  test('ずれの表示は EARLY / LATE と ms', () {
    expect(timingLabel(-0.018), 'EARLY 18ms');
    expect(timingLabel(0.007), 'LATE 7ms');
    expect(timingLabel(0.0001), '0ms');
  });

  group('判定の下のずれ (#253)', () {
    final w = testWorld(endlessMode);

    test('PERFECT / GOOD / MISS には出し、JUST には出さない', () {
      final fx = FxState(w);
      fx.handle(_parry(ParryGrade.perfect, -0.018));
      expect(fx.judge!.sub, 'EARLY 18ms');
      fx.handle(_parry(ParryGrade.good, 0.045));
      expect(fx.judge!.sub, 'LATE 45ms');
      fx.handle(_parry(ParryGrade.just, -0.004));
      expect(fx.judge!.text, 'JUST!!');
      expect(fx.judge!.sub, isNull);
      fx.handle(const ParryMissed(offset: -0.12));
      expect(fx.judge!.sub, 'EARLY 120ms');
      fx.handle(const ParryMissed());
      expect(fx.judge!.text, 'MISS');
      expect(fx.judge!.sub, isNull);
    });

    test('設定の「タイミングの表示」がオフなら出さない', () {
      final fx = FxState(w, showTiming: false);
      fx.handle(_parry(ParryGrade.perfect, -0.018));
      expect(fx.judge!.sub, isNull);
      fx.handle(const ParryMissed(offset: 0.1));
      expect(fx.judge!.sub, isNull);
    });

    testWidgets('盤面に、判定の文字とずれを描く', (tester) async {
      final fx = FxState(w)..handle(_parry(ParryGrade.perfect, 0.007));
      final drawn = await _paint(tester, w, fx);
      expect(drawn, containsAll(['PERFECT', 'LATE 7ms']));
    });
  });

  testWidgets('練習場の盤面に、直近の判定の内訳とずれの平均・ばらつきを描く (#253)', (tester) async {
    final mode = PracticeMode();
    final w = testWorld(mode);
    mode.log
      ..add(ParryGrade.just, 0)
      ..add(ParryGrade.perfect, -0.02)
      ..add(ParryGrade.good, -0.04)
      ..add(null, null);
    final drawn = await _paint(tester, w, FxState(w));
    expect(
      drawn,
      containsAll([
        'PRACTICE',
        'LV1',
        'LAST 4/20',
        'JUST',
        'PERFECT',
        'GOOD',
        'MISS',
        'EARLY 20ms', // 平均 (0 - 20 - 40) / 3
        '16ms', // ばらつき √((20² + 0² + 20²) / 3) ≒ 16.3
      ]),
    );
  });
}
