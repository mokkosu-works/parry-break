import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  }) {
    drawn.add(text);
    super.draw(
      canvas,
      text,
      x,
      y,
      size,
      color,
      align: align,
      weight: weight,
      family: family,
    );
  }
}

/// 1-1 を始めた直後 (帯が開き、ボールがパドルに乗っている) の盤面を描き、描いた文字を返す。
Future<List<String>> _paintStart(
  WidgetTester tester, {
  required bool parryButton,
  required String locale,
}) async {
  tester.view
    ..physicalSize = const Size(1200, 720)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final campaign = Campaign.fromJson(
    jsonDecode(File('assets/stages/campaign.json').readAsStringSync())
        as Map<String, Object?>,
    endlessContent,
  );
  final w = World(
    mode: StageMode(campaign.stages.firstWhere((s) => s.id == '1-1')),
  )..start();
  final fx = FxState(w);
  // 帯が開ききり、READY のカウントダウンが終わるまで進める
  for (var i = 0; i < 60 * 3; i++) {
    w.step(World.dt);
    w.drainEvents().forEach(fx.handle);
    fx.step(World.dt);
    if (w.countdown <= 0 && fx.banner != null && fx.banner!.t > 0.5) break;
  }
  expect(w.ball.attached, isTrue);
  expect(w.countdown, lessThanOrEqualTo(0));
  expect(fx.banner, isNotNull);
  final text = _RecordingText();
  final painter = FieldPainter(
    world: w,
    fx: fx,
    alpha: () => 1,
    time: () => 0.1, // TAP / PARRY が点灯している時刻
    text: text,
    blockPainters: BlockPainterRegistry(),
    l10n: lookupAppLocalizations(Locale(locale)),
    highQuality: true,
    repaint: ValueNotifier(0),
    parryButton: parryButton,
  );
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: CustomPaint(painter: painter, size: const Size(1200, 720)),
    ),
  );
  expect(tester.takeException(), isNull);
  return text.drawn;
}

void main() {
  setUpAll(() async {
    await (FontLoader(
      'DotGothic16',
    )..addFont(rootBundle.load('assets/fonts/DotGothic16-subset.ttf'))).load();
    await (FontLoader(
      'Silkscreen',
    )..addFont(rootBundle.load('assets/fonts/Silkscreen-Regular.ttf'))).load();
  });

  testWidgets('領域方式: 発射前に TAP、帯に「タップしてパリィ」', (tester) async {
    final drawn = await _paintStart(tester, parryButton: false, locale: 'ja');
    expect(drawn, contains('TAP'));
    expect(drawn, isNot(contains('PARRY')));
    expect(drawn, contains('ボールが当たる瞬間にタップしてパリィ'));
  });

  testWidgets('レール方式: 発射前に PARRY、帯は PARRY ボタンを指す', (tester) async {
    final drawn = await _paintStart(tester, parryButton: true, locale: 'ja');
    expect(drawn, contains('PARRY'));
    expect(drawn, isNot(contains('TAP')));
    expect(drawn, contains('ボールが当たる瞬間に PARRY を押してパリィ'));
    expect(drawn, isNot(contains('ボールが当たる瞬間にタップしてパリィ')));
  });

  testWidgets('レール方式 (英語): 帯は PARRY ボタンを指す', (tester) async {
    final drawn = await _paintStart(tester, parryButton: true, locale: 'en');
    expect(drawn, contains('PRESS PARRY AS THE BALL HITS'));
    expect(drawn, isNot(contains('TAP AS THE BALL HITS TO PARRY')));
  });
}
