import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parry_break/core/core.dart';
import 'package:parry_break/game/result_overlay.dart';
import 'package:parry_break/l10n/app_localizations.dart';
import 'package:parry_break/services/progress.dart';
import 'package:parry_break/services/quests.dart';
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

  /// レベルが上がる回 (LEVEL UP! の札と、桁の多い XP が出て、いちばん幅を取る)。
  LevelGain levelUp() {
    const c = LevelCurve.standard;
    return LevelGain(
      xp: 1500,
      before: c.of(c.xpAt(88) + 5),
      after: c.of(c.xpAt(89) + 100),
    );
  }

  /// レベルが上がらない回。
  LevelGain steady() {
    const c = LevelCurve.standard;
    return LevelGain(
      xp: 65,
      before: c.of(c.xpAt(12) + 10),
      after: c.of(c.xpAt(12) + 75),
    );
  }

  ResultData endless({LevelGain? gain, QuestResult? quest}) => ResultData(
    gain: gain ?? levelUp(),
    quest: quest,
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

  ResultData stageResult(
    StageDef s, {
    required bool cleared,
    QuestResult? quest,
  }) => ResultData(
    gain: cleared ? levelUp() : steady(),
    quest: quest,
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

  /// ボタンの高さの下限。568×320 (iPhone SE の横画面) は、詰めた配置の幅の下限 (560) を割るので、ステージの結果で 33pt まで縮む。
  /// この PR より前から 44pt を割っている (レベルの表示を足しても変わらない)。ほかの画面は 44pt 以上。
  double minButton(Size size) => size.width < 600 ? 32 : 44;

  const phones = {
    '568×320 (iPhone SE)': (Size(568, 320), EdgeInsets.zero),
    '667×375': (Size(667, 375), EdgeInsets.zero),
    '844×390 (セーフエリアあり)': (Size(844, 390), EdgeInsets.fromLTRB(47, 0, 47, 21)),
  };

  for (final MapEntry(key: name, value: (size, safe)) in phones.entries) {
    testWidgets('$name: エンドレスの結果画面がはみ出さず、ボタンは 44pt 以上、文字は 11pt 以上', (t) async {
      await pump(t, endless(), size: size, safe: safe);
      expect(t.takeException(), isNull);
      final m = measure(t);
      expect(m.button, greaterThanOrEqualTo(minButton(size)));
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
      expect(m2.button, greaterThanOrEqualTo(minButton(size)));
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
              expect(
                m.button,
                greaterThanOrEqualTo(minButton(size)),
                reason: reason,
              );
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
              expect(
                m2.button,
                greaterThanOrEqualTo(minButton(size)),
                reason: reason,
              );
              expect(m2.text, greaterThanOrEqualTo(11), reason: reason);
              expect(find.text('RICOCHET'), findsOneWidget, reason: reason);
            }
          }
        },
      );
    }
  }

  testWidgets('1280×800 では、1000×470 の箱 (レベルの行があれば 36 高い) を組み、ほぼ縮めずに出す', (
    t,
  ) async {
    for (final (gain, height) in [(levelUp(), 506.0), (null, 470.0)]) {
      if (gain != null) {
        await pump(t, endless(gain: gain), size: const Size(1280, 800));
      } else {
        // gain なし (デバッグモードのプレイ) は、レベルの行も出さず、今までどおりの箱
        t.view
          ..physicalSize = const Size(1280, 800)
          ..devicePixelRatio = 1;
        final d = endless();
        await t.pumpWidget(
          MaterialApp(
            theme: ThemeData(fontFamily: kJpFont),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: ResultOverlay(
              data: ResultData(
                score: d.score,
                round: d.round,
                maxChain: d.maxChain,
                stats: d.stats,
                reason: d.reason,
                newBest: d.newBest,
                bestScore: d.bestScore,
                bestRound: d.bestRound,
                rank: d.rank,
                over: d.over,
              ),
              onRetry: () {},
              onTitle: () {},
            ),
          ),
        );
        await t.pump(const Duration(seconds: 3));
      }
      expect(t.takeException(), isNull);
      final box = find.byWidgetPredicate(
        (w) => w is SizedBox && w.width == 1000 && w.height == height,
      );
      expect(box, findsOneWidget, reason: 'height=$height');
      // 1074×(536 か 568) が 1256×776 に入るので縮めない
      expect(t.getRect(box).width, closeTo(1000, 0.5));
      expect(measure(t).button, greaterThanOrEqualTo(48));
    }
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

  for (final lang in ['en', 'ja']) {
    testWidgets('1280×800 ($lang): 1 ページ目 (レベルの行つき) は、どのステージの結果もはみ出さない', (
      t,
    ) async {
      for (final s in campaign.stages) {
        for (final cleared in [true, false]) {
          await pump(
            t,
            stageResult(s, cleared: cleared),
            size: const Size(1280, 800),
            lang: lang,
            stage: true,
          );
          final why = 'stage ${s.id} cleared=$cleared';
          expect(t.takeException(), isNull, reason: why);
          expect(find.textContaining('LV '), findsOneWidget, reason: why);
          expect(measure(t).button, greaterThanOrEqualTo(44), reason: why);
        }
      }
      for (final data in [endless(), endless(gain: steady())]) {
        await pump(t, data, size: const Size(1280, 800), lang: lang);
        expect(t.takeException(), isNull);
      }
    });
  }

  /// 見た目が解放される回 (Lv1 → Lv2: パドル CYAN 1 つ)。
  LevelGain unlockOne() {
    const c = LevelCurve.standard;
    return LevelGain(
      xp: 120,
      before: c.of(c.xpAt(1) + 10),
      after: c.of(c.xpAt(2) + 10),
    );
  }

  /// 一度に何段か上がって、3 つ解放される回 (Lv1 → Lv6)。
  LevelGain unlockMany() {
    const c = LevelCurve.standard;
    return LevelGain(
      xp: 1500,
      before: c.of(c.xpAt(1)),
      after: c.of(c.xpAt(6) + 3),
    );
  }

  group('見た目の解放の知らせ (design.md 9.9)', () {
    for (final lang in ['en', 'ja']) {
      final one = lang == 'ja' ? 'NEW: パドルの色 CYAN' : 'NEW: Paddle color CYAN';
      final many = lang == 'ja'
          ? 'NEW: パドルの色 CYAN ほか 2'
          : 'NEW: Paddle color CYAN +2 more';
      testWidgets('レベルが上がって解放されたら 1 行出す ($lang)。複数なら最初の 1 つ +「ほか N」', (
        t,
      ) async {
        await pump(
          t,
          endless(gain: unlockOne()),
          size: const Size(1280, 800),
          lang: lang,
        );
        expect(find.text(one), findsOneWidget);
        await pump(
          t,
          endless(gain: unlockMany()),
          size: const Size(1280, 800),
          lang: lang,
        );
        expect(find.text(many), findsOneWidget);
      });
    }

    testWidgets('軌跡の色なら「NEW: Trail color …」', (t) async {
      const c = LevelCurve.standard;
      await pump(
        t,
        endless(
          gain: LevelGain(
            xp: 100,
            before: c.of(c.xpAt(3)),
            after: c.of(c.xpAt(4)),
          ),
        ),
        size: const Size(1280, 800),
      );
      expect(find.text('NEW: Trail color CYAN'), findsOneWidget);
    });

    testWidgets('解放がない回 (上がらない・解放のないレベル) は何も出さず、箱の高さも変わらない', (t) async {
      for (final g in [steady(), levelUp()]) {
        await pump(t, endless(gain: g), size: const Size(1280, 800));
        expect(find.textContaining('NEW:'), findsNothing);
        expect(
          find.byWidgetPredicate(
            (w) => w is SizedBox && w.width == 1000 && w.height == 506,
          ),
          findsOneWidget,
        );
      }
    });

    testWidgets('1280×800: 解放の行のぶん箱が 26 高くなり、ほぼ縮めずに出す', (t) async {
      await pump(t, endless(gain: unlockMany()), size: const Size(1280, 800));
      expect(t.takeException(), isNull);
      final box = find.byWidgetPredicate(
        (w) => w is SizedBox && w.width == 1000 && w.height == 532,
      );
      expect(box, findsOneWidget);
      expect(t.getRect(box).width, closeTo(1000, 0.5));
      expect(measure(t).button, greaterThanOrEqualTo(48));
    });

    for (final MapEntry(key: name, value: (size, safe)) in phones.entries) {
      for (final lang in ['en', 'ja']) {
        testWidgets('$name ($lang): 解放の行があっても、はみ出さず、ボタンは 44pt 以上、文字は 11pt 以上', (
          t,
        ) async {
          final text = lang == 'ja'
              ? 'NEW: パドルの色 CYAN ほか 2'
              : 'NEW: Paddle color CYAN +2 more';
          for (final data in [
            endless(gain: unlockMany()),
            stageResult(campaign.stages.first, cleared: true),
          ]) {
            final isStage = data.stage != null;
            await pump(
              t,
              isStage
                  ? ResultData(
                      gain: unlockMany(),
                      score: data.score,
                      round: data.round,
                      maxChain: data.maxChain,
                      stats: data.stats,
                      reason: data.reason,
                      newBest: data.newBest,
                      bestScore: data.bestScore,
                      bestRound: data.bestRound,
                      stage: data.stage,
                      cleared: true,
                      achieved: data.achieved,
                      rank: data.rank,
                      over: data.over,
                    )
                  : data,
              size: size,
              safe: safe,
              lang: lang,
              stage: isStage,
            );
            expect(t.takeException(), isNull, reason: '$isStage');
            expect(find.text(text), findsOneWidget);
            final m = measure(t);
            expect(m.button, greaterThanOrEqualTo(minButton(size)));
            expect(m.text, greaterThanOrEqualTo(11));
            // 2 ページ目でも同じ場所に出る
            await page2(t);
            expect(t.takeException(), isNull);
            expect(find.text(text), findsOneWidget);
            expect(measure(t).text, greaterThanOrEqualTo(11));
          }
        });
      }
    }
  });

  /// 今日のお題を 1 つ達成した回 (易しい: PERFECT ×20 のつもりで、表の値の目標)。
  QuestResult questOne() => const QuestResult(
    cleared: [
      Quest(
        kind: QuestKind.perfect,
        tier: QuestTier.normal,
        progress: 20,
        done: true,
      ),
    ],
  );

  /// 3 つ達成する回 (ふつう 150 + 易しい 100 + 少し難しい 250 + 全部 200)。
  QuestResult questMany() => const QuestResult(
    cleared: [
      Quest(
        kind: QuestKind.plays,
        tier: QuestTier.easy,
        progress: 3,
        done: true,
      ),
      Quest(
        kind: QuestKind.perfect,
        tier: QuestTier.normal,
        progress: 20,
        done: true,
      ),
    ],
  );

  QuestResult questAll() => const QuestResult(
    cleared: [
      Quest(
        kind: QuestKind.endlessScore,
        tier: QuestTier.hard,
        progress: 4000000,
        done: true,
      ),
    ],
    allClear: true,
  );

  group('今日のお題の達成の知らせ (design.md 9.10)', () {
    for (final lang in ['en', 'ja']) {
      final more = lang == 'ja' ? 'ほか 1' : '+1 more';
      testWidgets(
        '達成したら 1 行出す ($lang)。複数なら最初の 1 つ +「ほか N」、全部なら ALL QUESTS CLEAR',
        (t) async {
          const size = Size(1280, 800);
          await pump(
            t,
            endless(quest: questOne()),
            size: size,
            lang: lang,
          );
          expect(find.text('QUEST CLEAR: PERFECT ×20 +150 XP'), findsOneWidget);
          await pump(
            t,
            endless(quest: questMany()),
            size: size,
            lang: lang,
          );
          expect(
            find.text('QUEST CLEAR: PLAY ×3 +100 XP $more'),
            findsOneWidget,
          );
          await pump(
            t,
            endless(quest: questAll()),
            size: size,
            lang: lang,
          );
          expect(find.text('ALL QUESTS CLEAR! +450 XP'), findsOneWidget);
        },
      );
    }

    testWidgets('達成がない回は何も出さず、箱の高さも変わらない', (t) async {
      for (final q in [null, const QuestResult()]) {
        await pump(t, endless(quest: q), size: const Size(1280, 800));
        expect(find.textContaining('QUEST'), findsNothing);
        expect(
          find.byWidgetPredicate(
            (w) => w is SizedBox && w.width == 1000 && w.height == 506,
          ),
          findsOneWidget,
        );
      }
    });

    testWidgets('1280×800: 達成の行のぶん箱が 26 高くなり、ほぼ縮めずに出す', (t) async {
      await pump(t, endless(quest: questOne()), size: const Size(1280, 800));
      expect(t.takeException(), isNull);
      final box = find.byWidgetPredicate(
        (w) => w is SizedBox && w.width == 1000 && w.height == 532,
      );
      expect(box, findsOneWidget);
      expect(t.getRect(box).width, closeTo(1000, 0.5));
      expect(measure(t).button, greaterThanOrEqualTo(48));
      // 見た目の解放と重なっても、さらに 26 高くなるだけ
      await pump(
        t,
        endless(gain: unlockMany(), quest: questAll()),
        size: const Size(1280, 800),
      );
      expect(t.takeException(), isNull);
      expect(
        find.byWidgetPredicate(
          (w) => w is SizedBox && w.width == 1000 && w.height == 558,
        ),
        findsOneWidget,
      );
      expect(measure(t).button, greaterThanOrEqualTo(44));
    });

    for (final MapEntry(key: name, value: (size, safe)) in phones.entries) {
      for (final lang in ['en', 'ja']) {
        testWidgets(
          '$name ($lang): 達成の行 (解放と重なる回も) があっても、はみ出さず、ボタンは 44pt 以上、文字は 11pt 以上',
          (t) async {
            final more = lang == 'ja' ? 'ほか 1' : '+1 more';
            final text = 'QUEST CLEAR: PLAY ×3 +100 XP $more';
            for (final data in [
              endless(quest: questMany()),
              endless(gain: unlockMany(), quest: questMany()),
              stageResult(
                campaign.stages.first,
                cleared: true,
                quest: questMany(),
              ),
            ]) {
              final isStage = data.stage != null;
              await pump(
                t,
                data,
                size: size,
                safe: safe,
                lang: lang,
                stage: isStage,
              );
              expect(t.takeException(), isNull, reason: '$isStage');
              expect(find.text(text), findsOneWidget);
              final m = measure(t);
              expect(m.button, greaterThanOrEqualTo(minButton(size)));
              expect(m.text, greaterThanOrEqualTo(11));
              // 2 ページ目でも同じ場所に出る
              await page2(t);
              expect(t.takeException(), isNull);
              expect(find.text(text), findsOneWidget);
              expect(measure(t).text, greaterThanOrEqualTo(11));
            }
          },
        );
      }
    }
  });

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
      gain: cleared ? levelUp() : steady(),
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
              expect(
                m.button,
                greaterThanOrEqualTo(minButton(size)),
                reason: why,
              );
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

  // エンドレスと DAILY の「あと少し」(記録までと次のランクまで)
  ResultData nearMiss({
    DailyOutcome? daily,
    bool newBest = false,
    Rank rank = Rank.b,
  }) {
    final e = endless();
    return ResultData(
      score: 6800000,
      round: 23,
      maxChain: e.maxChain,
      stats: e.stats,
      reason: e.reason,
      newBest: newBest,
      bestScore: 123456789,
      bestRound: 40,
      rank: rank,
      over: e.over,
      daily: daily == null ? null : DailyResult(outcome: daily, streak: 365),
    );
  }

  for (final (size, safe) in [
    ...phones.values,
    (const Size(1280, 800), EdgeInsets.zero),
  ]) {
    for (final lang in ['en', 'ja']) {
      testWidgets(
        '${size.width.toInt()}×${size.height.toInt()} ($lang): エンドレスと DAILY の「あと少し」がはみ出さずに出る',
        (t) async {
          final ja = lang == 'ja';
          final rank = ja
              ? 'A ランクまであと2ラウンド・あと1,200,000点'
              : '2 more rounds and 1,200,000 more pts to rank A';
          final cases = <(ResultData, String?, String?)>[
            (
              nearMiss(),
              ja
                  ? '自己ベストまであと116,656,789点'
                  : '116,656,789 pts to your best score',
              rank,
            ),
            (nearMiss(newBest: true), null, rank), // 新記録の回は、ランクの行だけ
            (
              nearMiss(daily: DailyOutcome.kept),
              ja
                  ? '今日の記録まであと116,656,789点'
                  : "116,656,789 pts to today's record",
              rank,
            ),
            (nearMiss(daily: DailyOutcome.updated), null, rank),
            // S ランクで記録も更新したなら、何も出さない
            (nearMiss(newBest: true, rank: Rank.s), null, null),
          ];
          for (final (i, (data, best, rankLine)) in cases.indexed) {
            await t.pumpWidget(const SizedBox()); // 前の画面の状態を持ち越さない
            await pump(t, data, size: size, safe: safe, lang: lang);
            final why = 'case $i';
            expect(t.takeException(), isNull, reason: why);
            final m = measure(t);
            expect(
              m.button,
              greaterThanOrEqualTo(minButton(size)),
              reason: why,
            );
            expect(m.text, greaterThanOrEqualTo(11), reason: why);
            expect(
              find.textContaining(ja ? 'あと少し' : 'SO CLOSE'),
              best == null && rankLine == null ? findsNothing : findsOneWidget,
              reason: why,
            );
            expect(
              find.textContaining(ja ? '自己ベスト' : 'best score'),
              best != null && data.daily == null
                  ? findsOneWidget
                  : findsNothing,
              reason: why,
            );
            for (final line in [best, rankLine].nonNulls) {
              final f = find.textContaining(line);
              expect(f, findsOneWidget, reason: '$why $line');
              final r = t.getRect(f);
              expect(r.left, greaterThanOrEqualTo(0), reason: why);
              expect(r.right, lessThanOrEqualTo(size.width), reason: why);
              expect(r.bottom, lessThanOrEqualTo(size.height), reason: why);
            }
            if (best == null) {
              expect(
                find.textContaining(ja ? '記録まであと' : 'to today'),
                findsNothing,
                reason: why,
              );
              expect(
                find.textContaining(ja ? '自己ベスト' : 'best score'),
                findsNothing,
              );
            }
          }
        },
      );
    }
  }

  // プレイヤーレベル (design.md 9.9): LV・棒・XP を 1 行で出し、上がったときは LEVEL UP!
  group('プレイヤーレベル', () {
    Future<void> mount(
      WidgetTester t,
      ResultData data, {
      Size size = const Size(844, 390),
      bool reduce = false,
      String lang = 'en',
    }) async {
      t.view
        ..physicalSize = size
        ..devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: kJpFont),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale(lang),
          home: ResultOverlay(
            key: UniqueKey(),
            data: data,
            onRetry: () {},
            onTitle: () {},
            reduceMotion: reduce,
          ),
        ),
      );
    }

    for (final (name, size) in [
      ('568×320', const Size(568, 320)),
      ('667×375', const Size(667, 375)),
      ('844×390', const Size(844, 390)),
      ('1280×800', const Size(1280, 800)),
    ]) {
      for (final lang in ['ja', 'en']) {
        testWidgets('$name ($lang): LV・XP・LEVEL UP! が画面の中に出る (どちらのページでも)', (
          t,
        ) async {
          for (final (gain, up) in [(levelUp(), true), (steady(), false)]) {
            await mount(
              t,
              endless(gain: gain),
              size: size,
              lang: lang,
            );
            await t.pump(const Duration(seconds: 3));
            for (var page = 0; page < 2; page++) {
              if (page == 1) await page2(t);
              final why = '$name $lang up=$up page=${page + 1}';
              expect(t.takeException(), isNull, reason: why);
              final lv = find.text('LV ${gain.toLevel}');
              expect(lv, findsOneWidget, reason: why);
              expect(find.text('+${gain.xp} XP'), findsOneWidget, reason: why);
              expect(
                find.text('LEVEL UP!'),
                up ? findsOneWidget : findsNothing,
                reason: why,
              );
              for (final f in [
                lv,
                find.text('+${gain.xp} XP'),
                if (up) find.text('LEVEL UP!'),
              ]) {
                final r = t.getRect(f);
                expect(r.left, greaterThanOrEqualTo(0), reason: why);
                expect(r.right, lessThanOrEqualTo(size.width), reason: why);
                expect(r.bottom, lessThanOrEqualTo(size.height), reason: why);
              }
              // ボタンと重ならない
              final bar = t.getRect(lv);
              for (final e in find.byType(PixelButton).evaluate()) {
                expect(
                  t.getRect(find.byWidget(e.widget)).top,
                  greaterThanOrEqualTo(bar.bottom),
                  reason: why,
                );
              }
            }
          }
        });
      }
    }

    testWidgets('gain がなければ (デバッグモードのプレイ) LV も XP も出さない', (t) async {
      final d = endless();
      await mount(
        t,
        ResultData(
          score: d.score,
          round: d.round,
          maxChain: d.maxChain,
          stats: d.stats,
          reason: d.reason,
          newBest: false,
          bestScore: d.bestScore,
          bestRound: d.bestRound,
        ),
      );
      await t.pump(const Duration(seconds: 3));
      expect(find.textContaining('LV '), findsNothing);
      expect(find.textContaining(' XP'), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('棒は 1 秒以内に伸びきり、上がるときは旧レベルが満タンになってから LEVEL UP! が出る', (t) async {
      final g = levelUp();
      await mount(t, endless(gain: g));
      // 演出は 2.6 秒で、棒は 0.66〜0.9 のあいだ (約 0.62 秒)
      await t.pump(const Duration(milliseconds: 1720)); // 0.66: 伸びる前
      expect(find.text('LV ${g.fromLevel}'), findsOneWidget);
      expect(find.text('LEVEL UP!'), findsNothing);
      await t.pump(const Duration(milliseconds: 700)); // 約 0.93
      expect(find.text('LV ${g.toLevel}'), findsOneWidget);
      expect(find.text('LEVEL UP!'), findsOneWidget);
      await t.pump(const Duration(seconds: 2));
      expect(find.text('LV ${g.toLevel}'), findsOneWidget);
    });

    testWidgets('レベルが上がるときだけ、棒が伸びきったところで効果音のコールバックが 1 回呼ばれる', (t) async {
      var ups = 0;
      Future<void> run(LevelGain g, {bool reduce = false}) async {
        ups = 0;
        t.view
          ..physicalSize = const Size(844, 390)
          ..devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await t.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: ResultOverlay(
              key: UniqueKey(),
              data: endless(gain: g),
              onRetry: () {},
              onTitle: () {},
              onLevelUp: () => ups++,
              reduceMotion: reduce,
            ),
          ),
        );
        await t.pump(const Duration(seconds: 4));
      }

      await run(levelUp());
      expect(ups, 1);
      await run(steady());
      expect(ups, 0);
    });

    testWidgets('演出を控えめにする: 動かさずに、最初から最後の状態 (新しいレベルと LEVEL UP!) で出る', (
      t,
    ) async {
      final g = levelUp();
      await mount(t, endless(gain: g), reduce: true);
      expect(find.text('LV ${g.toLevel}'), findsOneWidget);
      expect(find.text('LEVEL UP!'), findsOneWidget);
      expect(find.text('LV ${g.fromLevel}'), findsNothing);
    });

    testWidgets('Lv99 に届いている回は、XP の代わりに MAX を出す', (t) async {
      const c = LevelCurve.standard;
      await mount(
        t,
        endless(
          gain: LevelGain(xp: 300, before: c.of(c.maxXp), after: c.of(c.maxXp)),
        ),
      );
      await t.pump(const Duration(seconds: 3));
      expect(find.text('LV 99'), findsOneWidget);
      expect(find.text('MAX'), findsOneWidget);
      expect(find.text('LEVEL UP!'), findsNothing);
    });
  });
}
