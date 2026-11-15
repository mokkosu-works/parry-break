import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parry_break/core/core.dart';
import 'package:parry_break/main.dart';
import 'package:parry_break/services/content.dart';
import 'package:parry_break/services/leaderboard.dart';
import 'package:parry_break/services/records.dart';
import 'package:parry_break/services/settings.dart';
import 'package:parry_break/ui/title/title_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// タイトルの ENDLESS の難易度 (NORMAL / EASY) の選択。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> pumpTitle(
    WidgetTester tester, {
    required Size size,
    String lang = 'en',
    Settings settings = const Settings(),
    Records records = const Records(),
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({
      'records': jsonEncode(records.toJson()),
      'settings.v1': jsonEncode(
        settings.copyWith(language: () => lang).toJson(),
      ),
    });
    final prefs = await SharedPreferences.getInstance();
    final content = (await tester.runAsync(
      () => GameContent.load(rootBundle),
    ))!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          contentProvider.overrideWithValue(content),
          leaderboardProvider.overrideWithValue(DisabledLeaderboard()),
        ],
        child: const ParryBreakApp(home: TitleScreen()),
      ),
    );
    await tester.pump(const Duration(seconds: 3));
    return ProviderScope.containerOf(tester.element(find.byType(TitleScreen)));
  }

  const records = Records(
    endless: EndlessRecord(bestScore: 111000, bestRound: 5),
    endlessEasy: EndlessRecord(bestScore: 222000, bestRound: 8),
  );

  testWidgets('初期値は NORMAL。EASY を押すと設定に保存され、HI-SCORE が EASY の記録になる', (
    tester,
  ) async {
    final c = await pumpTitle(
      tester,
      size: const Size(844, 390),
      records: records,
    );
    expect(c.read(settingsProvider).endlessDifficulty, Difficulty.normal);
    expect(find.text('111,000'), findsOneWidget);
    expect(find.text('222,000'), findsNothing);

    await tester.tap(find.text('EASY'));
    await tester.pump();
    expect(c.read(settingsProvider).endlessDifficulty, Difficulty.easy);
    expect(c.read(settingsProvider).difficulty, Difficulty.normal);
    expect(find.text('222,000'), findsOneWidget);
    expect(find.text('111,000'), findsNothing);

    await tester.tap(find.text('NORMAL'));
    await tester.pump();
    expect(c.read(settingsProvider).endlessDifficulty, Difficulty.normal);
    expect(find.text('111,000'), findsOneWidget);
  });

  testWidgets('HARD は選べない', (tester) async {
    await pumpTitle(tester, size: const Size(844, 390));
    expect(find.text('HARD'), findsNothing);
  });

  for (final size in const [
    Size(568, 320),
    Size(667, 375),
    Size(844, 390),
    Size(1280, 800),
  ]) {
    for (final lang in const ['ja', 'en']) {
      testWidgets(
        '選ぶ部品がはみ出さず、押せる範囲は 44pt 以上 ($lang ${size.width.toInt()}x${size.height.toInt()})',
        (tester) async {
          await pumpTitle(
            tester,
            size: size,
            lang: lang,
            records: records,
            settings: const Settings(endlessDifficulty: Difficulty.easy),
          );
          expect(tester.takeException(), isNull);
          for (final label in const ['EASY', 'NORMAL']) {
            final hit = tester.getRect(
              find
                  .ancestor(
                    of: find.text(label),
                    matching: find.byType(ConstrainedBox),
                  )
                  .first,
            );
            // 568x320 (iPhone SE 1 世代) だけは、窓に入るよう 1 割ほど縮む
            expect(
              hit.height,
              greaterThanOrEqualTo(size.width < 600 ? 38 : 44),
              reason: label,
            );
            final t = tester.getRect(find.text(label));
            expect(t.left, greaterThanOrEqualTo(0));
            expect(t.right, lessThanOrEqualTo(size.width));
            expect(t.bottom, lessThanOrEqualTo(size.height));
          }
        },
      );
    }
  }
}
