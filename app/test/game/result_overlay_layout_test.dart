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
      ..perfects = 999
      ..parries = 999
      ..misses = 999
      ..fevers = 99
      ..returnKills = 99
      ..maxTier = 4
      ..playTime = 3599,
    reason: 'BLOCKS BREACHED',
    newBest: true,
    bestScore: 123456789,
    bestRound: 27,
    rank: Rank.s,
    over: const OverInfo(cause: OverCause.ballLost, tier: 5, sinceParry: 12.3),
  );

  ResultData stageResult(StageDef s, {required bool cleared}) => ResultData(
    score: 9876543,
    round: 1,
    maxChain: 117,
    stats: RunStats()
      ..just = 999
      ..perfects = 999
      ..parries = 999
      ..misses = 999
      ..fevers = 99
      ..graze = 999
      ..bestCollapse = 99
      ..bestBlast = 99
      ..bestRicochet = 99
      ..returnKills = 99
      ..maxTier = 4
      ..playTime = 3599,
    reason: 'BLOCKS BREACHED',
    newBest: cleared,
    bestScore: cleared ? 9876543 : 0,
    bestRound: 1,
    stage: s,
    difficulty: Difficulty.normal,
    cleared: cleared,
    achieved: [for (var i = 0; i < s.stars.length; i++) i.isEven],
    rank: cleared ? Rank.s : null,
    over: OverInfo(
      cause: OverCause.breached,
      tier: 3,
      gap: ClearGap(GapKind.score, 12345678),
    ),
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

  /// Tab で 2 ページ目に切り替える。
  Future<void> page2(WidgetTester t) async {
    await t.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await t.pump();
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
      expect(find.text('S'), findsOneWidget); // ランク

      // 2 ページ目 (パリィの内訳・ミスの原因)
      await page2(t);
      expect(t.takeException(), isNull);
      final m2 = measure(t);
      expect(m2.button, greaterThanOrEqualTo(44));
      expect(m2.text, greaterThanOrEqualTo(11));
      for (final label in ['JUST', 'PERFECT', 'GOOD', 'MISS', 'JUST RATE']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('The ball was dropped'), findsWidgets);
      expect(
        find.text('12.3s after the last parry, during FEVER TIME'),
        findsOneWidget,
      );
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
              // ランク (クリア) か「あと少し」(失敗) が出る
              if (cleared) {
                expect(find.text('RANK'), findsOneWidget, reason: reason);
              } else {
                expect(
                  find.text(lang == 'ja' ? 'あと少し' : 'SO CLOSE'),
                  findsOneWidget,
                  reason: reason,
                );
              }
              await page2(t);
              expect(t.takeException(), isNull, reason: '$reason page2');
              final m2 = measure(t);
              expect(m2.button, greaterThanOrEqualTo(44), reason: reason);
              expect(m2.text, greaterThanOrEqualTo(11), reason: reason);
              expect(find.text('RICOCHET'), findsOneWidget, reason: reason);
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

  for (final lang in ['en', 'ja']) {
    testWidgets('1280×800 ($lang): 2 ページ目もはみ出さず、文字は 11pt 以上', (t) async {
      for (final data in [
        endless(),
        stageResult(campaign.stages.first, cleared: true),
        stageResult(campaign.stages.first, cleared: false),
      ]) {
        await pump(
          t,
          data,
          size: const Size(1280, 800),
          lang: lang,
          stage: data.stage != null,
        );
        await page2(t);
        expect(t.takeException(), isNull);
        expect(measure(t).text, greaterThanOrEqualTo(11));
        expect(measure(t).button, greaterThanOrEqualTo(44));
      }
    });
  }

  testWidgets('2 ページ目は、Tab・PageUp / PageDown とタップで行き来できる', (t) async {
    await pump(t, endless(), size: const Size(844, 390));
    expect(find.text('JUST RATE'), findsNothing);
    await page2(t);
    expect(find.text('JUST RATE'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.pageUp);
    await t.pump();
    expect(find.text('JUST RATE'), findsNothing);
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
    expect(find.text('JUST RATE'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
    expect(find.text('JUST RATE'), findsNothing);
    // 成績の欄のタップでも切り替わる
    await t.tap(find.text('DETAILS ▸'));
    await t.pump();
    expect(find.text('JUST RATE'), findsOneWidget);
    await t.tap(find.text('◂ BACK'));
    await t.pump();
    expect(find.text('JUST RATE'), findsNothing);
  });

  testWidgets('ページを切り替えても、Enter でボタンを決められる', (t) async {
    var retry = 0;
    t.view
      ..physicalSize = const Size(1280, 800)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: ResultOverlay(
          data: endless(),
          onRetry: () => retry++,
          onTitle: () {},
          reduceMotion: true,
        ),
      ),
    );
    await page2(t);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(retry, 1);
  });

  testWidgets('演出を控えめにする: ランクは待たずに 1 倍で出る。ふだんは大きく出て縮む', (t) async {
    double scaleOfRank() {
      final e = find.ancestor(
        of: find.text('RANK'),
        matching: find.byType(Transform),
      );
      return t
          .widgetList<Transform>(e)
          .map((w) => w.transform.getMaxScaleOnAxis())
          .reduce((a, b) => a > b ? a : b);
    }

    Future<void> mount({required bool reduce}) async {
      t.view
        ..physicalSize = const Size(1280, 800)
        ..devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: ResultOverlay(
            key: UniqueKey(),
            data: endless(),
            onRetry: () {},
            onTitle: () {},
            reduceMotion: reduce,
          ),
        ),
      );
    }

    await mount(reduce: true);
    expect(find.text('RANK'), findsOneWidget);
    expect(scaleOfRank(), 1.0);

    await mount(reduce: false);
    await t.pump(const Duration(milliseconds: 1600)); // 出始め
    expect(scaleOfRank(), greaterThan(1.0));
    await t.pump(const Duration(seconds: 3));
    expect(scaleOfRank(), 1.0);
  });

  // Issue #255: デイリーの結果画面 (今日のスコア・その日の最高得点・連続日数・記録をどうしたか)
  ResultData daily({required DailyOutcome outcome, required bool cleared}) {
    final e = endless();
    return ResultData(
      score: e.score,
      round: 48,
      maxChain: e.maxChain,
      stats: e.stats,
      reason: e.reason,
      newBest: outcome == DailyOutcome.updated,
      bestScore: 123456789,
      bestRound: 0,
      cleared: cleared,
      rank: Rank.s,
      over: cleared ? null : e.over,
      daily: DailyResult(outcome: outcome, streak: 365),
    );
  }

  for (final (size, safe) in [
    ...phones.values,
    (const Size(1280, 800), EdgeInsets.zero),
  ]) {
    for (final lang in ['en', 'ja']) {
      testWidgets(
        '${size.width.toInt()}×${size.height.toInt()} ($lang): デイリーの結果画面がはみ出さず、連続日数と記録をどうしたかが出る',
        (t) async {
          for (final outcome in DailyOutcome.values) {
            for (final cleared in [true, false]) {
              await pump(
                t,
                daily(outcome: outcome, cleared: cleared),
                size: size,
                safe: safe,
                lang: lang,
              );
              final why = 'outcome=$outcome cleared=$cleared';
              expect(t.takeException(), isNull, reason: why);
              final m = measure(t);
              expect(m.button, greaterThanOrEqualTo(44), reason: why);
              expect(m.text, greaterThanOrEqualTo(11), reason: why);
              expect(find.text('DAILY'), findsOneWidget, reason: why);
              expect(find.text('TODAY BEST'), findsOneWidget, reason: why);
              expect(
                find.text(cleared ? 'DAILY CLEAR' : 'GAME OVER'),
                findsWidgets, // 見出しは影と重ねて描く
                reason: why,
              );
              final note = switch ((lang, outcome)) {
                ('ja', DailyOutcome.first) => '今日の記録として残しました・365日連続プレイ中',
                ('ja', DailyOutcome.updated) => '今日の記録を更新しました・365日連続プレイ中',
                ('ja', DailyOutcome.kept) => '今日の記録は更新ならず・365日連続プレイ中',
                (_, DailyOutcome.first) =>
                  "Saved as today's record · 365-day streak",
                (_, DailyOutcome.updated) =>
                  'New record for today · 365-day streak',
                _ => "Today's record stands · 365-day streak",
              };
              final r = t.getRect(find.text(note));
              expect(r.left, greaterThanOrEqualTo(0), reason: why);
              expect(r.right, lessThanOrEqualTo(size.width), reason: why);
              expect(r.bottom, lessThanOrEqualTo(size.height), reason: why);
              final p = t.renderObject<RenderParagraph>(find.text(note));
              expect(p.didExceedMaxLines, isFalse, reason: why);
            }
          }
        },
      );
    }
  }
}
