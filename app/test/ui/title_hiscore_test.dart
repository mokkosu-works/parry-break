import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parry_break/main.dart';
import 'package:parry_break/services/content.dart';
import 'package:parry_break/services/leaderboard.dart';
import 'package:parry_break/services/records.dart';
import 'package:parry_break/services/settings.dart';
import 'package:parry_break/ui/title/title_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Issue #261: 最高記録が 9 桁でも、タイトルの HI-SCORE が左の枠からはみ出さない。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpTitle(
    WidgetTester tester, {
    required int score,
    required String lang,
    required Size size,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({
      'records': jsonEncode(
        Records(endless: EndlessRecord(bestScore: score, bestRound: 12))
            .toJson(),
      ),
      'settings.v1': jsonEncode(Settings(language: lang).toJson()),
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
    // 登場の演出が終わるまで進める
    await tester.pump(const Duration(seconds: 3));
  }

  for (final size in const [Size(667, 375), Size(844, 390), Size(1280, 800)]) {
    for (final lang in const ['ja', 'en']) {
      testWidgets(
        'HI-SCORE 999,999,999 がはみ出さない ($lang ${size.width.toInt()}x${size.height.toInt()})',
        (tester) async {
          await pumpTitle(tester, score: 999999999, lang: lang, size: size);
          expect(tester.takeException(), isNull);
          final r = tester.getRect(find.text('999,999,999'));
          expect(r.right, lessThanOrEqualTo(size.width * 0.5));
          expect(r.left, greaterThanOrEqualTo(0));
        },
      );
    }
  }

  testWidgets('6 桁のときは縮めない', (tester) async {
    await pumpTitle(
      tester,
      score: 123456,
      lang: 'en',
      size: const Size(667, 375),
    );
    final style = tester.widget<Text>(find.text('123,456')).style!;
    final box = tester.renderObject<RenderBox>(find.text('123,456'));
    // 28 の文字がそのままの大きさで描かれる (FittedBox の縮小がかからない)
    expect(style.fontSize, 28);
    final scale = tester.firstWidget<FittedBox>(
      find.ancestor(of: find.text('123,456'), matching: find.byType(FittedBox)),
    );
    expect(scale.fit, BoxFit.scaleDown);
    expect(box.size.height, greaterThan(0));
  });
}
