import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parry_break/core/core.dart';
import 'package:parry_break/game/result_overlay.dart';
import 'package:parry_break/l10n/app_localizations.dart';
import 'package:parry_break/ui/widgets.dart';

import '../core/helpers.dart';

/// Issue #121: スマホの横画面でも、結果画面のボタンは 44pt 以上、文字は 11pt 以上で、はみ出さない。
/// 大きい画面では、今までどおり 1000×470 の箱を組んで出す。
void main() {
  final campaign = Campaign.fromJson(
    jsonDecode(File('assets/stages/campaign.json').readAsStringSync())
        as Map<String, Object?>,
    endlessContent,
  );

  setUpAll(() async {
    // 文字の幅を実機に近づける (テストの標準フォントは 1 文字が正方形で、実際より広い)
    await (FontLoader(
      'DotGothic16',
    )..addFont(rootBundle.load('assets/fonts/DotGothic16-subset.ttf'))).load();
    await (FontLoader('Silkscreen')
          ..addFont(rootBundle.load('assets/fonts/Silkscreen-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Silkscreen-Bold.ttf')))
        .load();
  });

  /// 画面の大きさとセーフエリア (pt)。844×390 は iPhone 14 の横画面 (左右 47・下 21)。
  Future<void> pump(
    WidgetTester t,
    ResultData data, {
    required Size size,
    EdgeInsets safe = EdgeInsets.zero,
    String lang = 'en',
    bool stage = false,
  }) async {
    t.view
      ..physicalSize = size
      ..devicePixelRatio = 1
      ..padding = FakeViewPadding(
        left: safe.left,
        top: safe.top,
        right: safe.right,
        bottom: safe.bottom,
      );
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: kJpFont),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale(lang),
        home: ResultOverlay(
          data: data,
          onRetry: () {},
          onTitle: () {},
          onNext: stage ? () {} : null,
          onStageSelect: stage ? () {} : null,
        ),
      ),
    );
    await t.pump(const Duration(seconds: 3)); // 演出が出きるまで
  }

  ResultData endless() => ResultData(
    score: 123456789,
    round: 27,
    maxChain: 117,
    stats: RunStats()
      ..just = 999
      ..graze = 999
      ..bestCollapse = 99
      ..bestBlast = 99
      ..bestRicochet = 99
      ..playTime = 3599,
    reason: 'BLOCKS BREACHED',
    newBest: true,
    bestScore: 123456789,
    bestRound: 27,
  );

  ResultData stageResult(StageDef s, {required bool cleared}) => ResultData(
    score: 9876543,
    round: 1,
    maxChain: 117,
    stats: RunStats()
      ..just = 999
      ..playTime = 3599,
    reason: 'BLOCKS BREACHED',
    newBest: cleared,
    bestScore: cleared ? 9876543 : 0,
    bestRound: 1,
    stage: s,
    difficulty: Difficulty.normal,
    cleared: cleared,
    achieved: [for (var i = 0; i < s.stars.length; i++) i.isEven],
  );

  /// 画面上のボタンの高さ (縮めた分を含む) と、画面上の文字の大きさの最小。
  ({double button, double text}) measure(WidgetTester t) {
    var button = double.infinity;
    for (final e in find.byType(PixelButton).evaluate()) {
      button = button < t.getRect(find.byWidget(e.widget)).height
          ? button
          : t.getRect(find.byWidget(e.widget)).height;
    }
    var text = double.infinity;
    for (final e
        in find
            .descendant(
              of: find.byType(ResultOverlay),
              matching: find.byType(RichText),
            )
            .evaluate()) {
      final r = e.renderObject! as RenderParagraph;
      double? smallest;
      r.text.visitChildren((span) {
        final s = span.style?.fontSize;
        if (s != null && (smallest == null || s < smallest!)) smallest = s;
        return true;
      });
      final scale = r.getTransformTo(null).getMaxScaleOnAxis();
      final onScreen = (smallest ?? 14) * scale;
      if (onScreen < text) text = onScreen;
    }
    return (button: button, text: text);
  }

  const phones = {
    '667×375': (Size(667, 375), EdgeInsets.zero),
    '844×390 (セーフエリアあり)': (Size(844, 390), EdgeInsets.fromLTRB(47, 0, 47, 21)),
  };

  for (final MapEntry(key: name, value: (size, safe)) in phones.entries) {
    testWidgets('$name: エンドレスの結果画面がはみ出さず、ボタンは 44pt 以上、文字は 11pt 以上', (t) async {
      await pump(t, endless(), size: size, safe: safe);
      expect(t.takeException(), isNull);
      final m = measure(t);
      expect(m.button, greaterThanOrEqualTo(44));
      expect(m.text, greaterThanOrEqualTo(11));
      // 8 つの成績をどれも出す
      for (final label in [
        'ROUND',
        'MAX CHAIN',
        'JUST',
        'GRAZE',
        'COLLAPSE',
        'BLAST',
        'RICOCHET',
        'TIME',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('NEW RECORD'), findsOneWidget);
    });

    for (final lang in ['en', 'ja']) {
      testWidgets(
        '$name ($lang): どのステージの結果画面 (クリア / 失敗) もはみ出さず、ボタンは 44pt 以上、文字は 11pt 以上',
        (t) async {
          for (final s in campaign.stages) {
            for (final cleared in [true, false]) {
              await pump(
                t,
                stageResult(s, cleared: cleared),
                size: size,
                safe: safe,
                lang: lang,
                stage: true,
              );
              final reason = 'stage ${s.id} cleared=$cleared';
              expect(t.takeException(), isNull, reason: reason);
              final m = measure(t);
              expect(m.button, greaterThanOrEqualTo(44), reason: reason);
              expect(m.text, greaterThanOrEqualTo(11), reason: reason);
              expect(
                find.byType(PixelButton),
                findsNWidgets(4),
                reason: reason,
              );
            }
          }
        },
      );
    }
  }

  testWidgets('1280×800 では、今までどおり 1000×470 の箱を組み、ほぼ縮めずに出す', (t) async {
    await pump(t, endless(), size: const Size(1280, 800));
    expect(t.takeException(), isNull);
    final box = find.byWidgetPredicate(
      (w) => w is SizedBox && w.width == 1000 && w.height == 470,
    );
    expect(box, findsOneWidget);
    expect(
      t.getRect(box).width,
      closeTo(1000, 0.5),
    ); // 1074×536 が 1256×776 に入るので縮めない
    expect(measure(t).button, greaterThanOrEqualTo(48));
  });
}
