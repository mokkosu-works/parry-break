import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parry_break/core/core.dart';
import 'package:parry_break/game/game_screen.dart';
import 'package:parry_break/main.dart';
import 'package:parry_break/services/content.dart';
import 'package:parry_break/services/daily.dart';
import 'package:parry_break/services/leaderboard.dart';
import 'package:parry_break/services/progress.dart';
import 'package:parry_break/services/settings.dart';
import 'package:parry_break/app/providers.dart';
import 'package:parry_break/ui/title/title_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/helpers.dart';

/// プレイヤーレベル (design.md 9.9): 遊び終えた回に XP が入り、結果画面とタイトルに出る。
/// 練習場とデバッグモードのプレイには入らない。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final campaign = Campaign.fromJson(
    jsonDecode(File('assets/stages/campaign.json').readAsStringSync())
        as Map<String, Object?>,
    endlessContent,
  );

  setUpAll(() async {
    await (FontLoader(
      'DotGothic16',
    )..addFont(rootBundle.load('assets/fonts/DotGothic16-subset.ttf'))).load();
    await (FontLoader('Silkscreen')
          ..addFont(rootBundle.load('assets/fonts/Silkscreen-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Silkscreen-Bold.ttf')))
        .load();
  });

  Future<SharedPreferences> pump(
    WidgetTester tester,
    Widget home, {
    Map<String, Object> prefs = const {},
    Settings settings = const Settings(language: 'en'),
    Size size = const Size(1600, 740),
    DateTime? now,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({
      'settings.v1': jsonEncode(settings.toJson()),
      ...prefs,
    });
    final sp = await SharedPreferences.getInstance();
    final binding = tester.binding;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(sp),
          contentProvider.overrideWithValue(
            GameContent(endless: endlessContent, campaign: campaign),
          ),
          timeSourceProvider.overrideWithValue(
            () => binding.clock.now().microsecondsSinceEpoch / 1e6,
          ),
          leaderboardProvider.overrideWithValue(DisabledLeaderboard()),
          if (now != null) dailyClockProvider.overrideWithValue(() => now),
        ],
        child: ParryBreakApp(home: home),
      ),
    );
    await tester.pump();
    return sp;
  }

  Future<void> frames(WidgetTester tester, double seconds) async {
    for (var i = 0; i < (seconds * 60).round(); i++) {
      await tester.pump(const Duration(microseconds: 16667));
    }
  }

  /// ボールを落としてゲームオーバーにし、結果画面が出きるまで進める。
  Future<void> gameOver(WidgetTester tester) async {
    await frames(tester, 1.2);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await frames(tester, 0.3);
    final w = GameScreen.debugLastController!.world;
    w.effects.guardHold = false;
    w.ball
      ..y = Field.height - 4
      ..vy = 600;
    await frames(tester, 3.2);
  }

  ProviderContainer container(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));

  int savedXp(SharedPreferences sp) {
    final raw = sp.getString('progress.v1');
    if (raw == null) return 0;
    return (jsonDecode(raw) as Map<String, Object?>)['xp']! as int;
  }

  testWidgets('エンドレス: 負けた回にも XP が入り、結果画面に LV・XP が出て、保存される', (tester) async {
    final sp = await pump(tester, const GameScreen());
    await gameOver(tester);
    final w = GameScreen.debugLastController!.world;
    final xp = XpRules.standard.xpFor(
      kind: PlayKind.endless,
      stats: w.stats,
      round: w.round.number,
    );
    expect(xp, greaterThanOrEqualTo(50));
    expect(savedXp(sp), xp);
    expect(container(tester).read(progressProvider).totalXp, xp);
    expect(find.text('+$xp XP'), findsOneWidget);
    expect(find.text('LV 1'), findsOneWidget);
    expect(find.text('LEVEL UP!'), findsNothing);
    expect(tester.takeException(), isNull);

    // もう 1 回遊ぶと、累計に足される
    await tester.tap(find.text('RETRY'));
    await gameOver(tester);
    final w2 = GameScreen.debugLastController!.world;
    final xp2 = XpRules.standard.xpFor(
      kind: PlayKind.endless,
      stats: w2.stats,
      round: w2.round.number,
    );
    expect(savedXp(sp), xp + xp2);
  });

  testWidgets('EASY のエンドレスは ×0.8', (tester) async {
    final sp = await pump(
      tester,
      const GameScreen(difficulty: Difficulty.easy),
    );
    await gameOver(tester);
    final w = GameScreen.debugLastController!.world;
    final normal = XpRules.standard.xpFor(
      kind: PlayKind.endless,
      stats: w.stats,
      round: w.round.number,
    );
    final xp = XpRules.standard.xpFor(
      kind: PlayKind.endless,
      stats: w.stats,
      round: w.round.number,
      difficulty: Difficulty.easy,
    );
    expect(xp, (normal * 0.8).round());
    expect(savedXp(sp), xp);
    expect(find.text('+$xp XP'), findsOneWidget);
  });

  testWidgets('レベルが上がる回は LEVEL UP! と新しいレベルが出る', (tester) async {
    final sp = await pump(
      tester,
      const GameScreen(),
      prefs: {
        'progress.v1': jsonEncode({'version': 1, 'xp': 99}),
      },
    );
    await gameOver(tester);
    expect(find.text('LEVEL UP!'), findsOneWidget);
    expect(find.text('LV 2'), findsOneWidget);
    expect(container(tester).read(progressProvider).level, 2);
    expect(savedXp(sp), greaterThan(99));
  });

  testWidgets('DAILY: 遊び終えると XP が入る', (tester) async {
    final now = DateTime.utc(2026, 11, 13, 9);
    final sp = await pump(tester, const GameScreen(daily: true), now: now);
    await gameOver(tester);
    final w = GameScreen.debugLastController!.world;
    expect(w.mode, isA<DailyMode>());
    final xp = XpRules.standard.xpFor(
      kind: PlayKind.daily,
      stats: w.stats,
      round: w.round.number,
    );
    expect(xp, greaterThan(50), reason: 'DAILY は途中のラウンドから始まる');
    expect(savedXp(sp), xp);
    expect(find.text('+$xp XP'), findsOneWidget);
  });

  testWidgets('ステージ: クリアで +100 と星の分が入る', (tester) async {
    final sp = await pump(tester, GameScreen(stage: campaign.stage('1-4')));
    await frames(tester, 1.2);
    final w = GameScreen.debugLastController!.world;
    w.stats.returnKills = 3;
    for (final b in w.blocks.where((b) => b.behavior.clearable).toList()) {
      w.destroyBlock(b, DestroyCause.pierce);
    }
    await frames(tester, 6.5);
    expect(find.text('NEXT STAGE'), findsOneWidget);
    final stage = campaign.stage('1-4')!;
    final stars = stage
        .evaluate(StageResult(cleared: true, score: w.score, stats: w.stats))
        .where((s) => s)
        .length;
    final xp = XpRules.standard.xpFor(
      kind: PlayKind.stage,
      stats: w.stats,
      cleared: true,
      stars: stars,
    );
    expect(xp, greaterThanOrEqualTo(150));
    expect(savedXp(sp), xp);
    expect(find.text('+$xp XP'), findsOneWidget);
  });

  testWidgets('ステージ: 失敗しても基本の XP が入る (クリアの加算はない)', (tester) async {
    final sp = await pump(tester, GameScreen(stage: campaign.stage('1-4')));
    await gameOver(tester);
    final w = GameScreen.debugLastController!.world;
    expect(w.phase, isNot(WorldPhase.completed));
    expect(savedXp(sp), greaterThanOrEqualTo(50));
    expect(savedXp(sp), lessThan(150));
  });

  testWidgets('練習場: 終わりの処理が呼ばれても XP は入らない (結果画面もない)', (tester) async {
    final sp = await pump(tester, const GameScreen(practice: true));
    await frames(tester, 1.2);
    final ctl = GameScreen.debugLastController!;
    ctl.onFinished?.call(ctl.world);
    await frames(tester, 0.5);
    expect(sp.containsKey('progress.v1'), isFalse);
    expect(find.textContaining(' XP'), findsNothing);
    expect(container(tester).read(progressProvider).totalXp, 0);
  });

  for (final (name, home) in [
    ('エンドレス', const GameScreen()),
    ('DAILY', const GameScreen(daily: true)),
    ('ステージ', GameScreen(stage: campaign.stage('1-4'))),
  ]) {
    testWidgets('デバッグモード ($name): XP は入らず、保存も結果画面の表示もない', (tester) async {
      final sp = await pump(
        tester,
        home,
        settings: const Settings(language: 'en', debugMode: true),
      );
      await gameOver(tester);
      expect(find.text('RETRY'), findsOneWidget, reason: '結果画面は出る');
      expect(sp.containsKey('progress.v1'), isFalse);
      expect(sp.containsKey('progress.broken'), isFalse);
      expect(container(tester).read(progressProvider).totalXp, 0);
      expect(find.textContaining(' XP'), findsNothing);
      expect(find.textContaining('LV '), findsNothing);
    });
  }

  group('タイトルの LV', () {
    Future<void> title(
      WidgetTester tester,
      Size size, {
      String lang = 'en',
      int xp = 0,
      Map<String, Object> prefs = const {},
    }) async {
      await pump(
        tester,
        const TitleScreen(),
        size: size,
        settings: Settings(language: lang),
        prefs: {
          if (xp > 0) 'progress.v1': jsonEncode({'version': 1, 'xp': xp}),
          ...prefs,
        },
      );
      await tester.pump(const Duration(seconds: 3));
    }

    testWidgets('累計 XP から計算したレベルを小さく出す', (tester) async {
      await title(tester, const Size(844, 390), xp: 2340); // Lv10 になる XP
      expect(find.text('LV 10'), findsOneWidget);
    });

    testWidgets('はじめは LV 1', (tester) async {
      await title(tester, const Size(844, 390));
      expect(find.text('LV 1'), findsOneWidget);
    });

    testWidgets('壊れた保存データでも落ちずに LV 1', (tester) async {
      await title(tester, const Size(844, 390), prefs: {'progress.v1': '{{{'});
      expect(find.text('LV 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final size in const [
      Size(568, 320),
      Size(667, 375),
      Size(844, 390),
      Size(1280, 800),
    ]) {
      for (final lang in ['ja', 'en']) {
        testWidgets(
          '${size.width.toInt()}×${size.height.toInt()} ($lang): LV 99 でもはみ出さず、ロゴと重ならない',
          (tester) async {
            await title(tester, size, lang: lang, xp: 999999);
            expect(tester.takeException(), isNull);
            final lv = find.text('LV 99');
            expect(lv, findsOneWidget);
            final r = tester.getRect(lv);
            expect(r.left, greaterThanOrEqualTo(0));
            expect(r.right, lessThanOrEqualTo(size.width * 0.62));
            expect(r.bottom, lessThanOrEqualTo(size.height));
            // 右のメニューとは重ならない
            final menu = tester.getRect(find.text('ENDLESS'));
            expect(r.right, lessThan(menu.left));
            // ロゴ (PARRY / BREAK) の文字とは重ならない
            for (final word in ['PARRY', 'BREAK']) {
              final f = find.text(word);
              if (f.evaluate().isEmpty) continue;
              expect(
                tester.getRect(f.first).overlaps(r),
                isFalse,
                reason: word,
              );
            }
          },
        );
      }
    }
  });
}
