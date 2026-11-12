import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parry_break/core/core.dart';
import 'package:parry_break/game/result_overlay.dart';
import 'package:parry_break/l10n/app_localizations.dart';

/// Issue #66: ステージで失敗した結果画面では、HI-SCORE の横に「クリアした回のみ記録」を添える。
void main() {
  const stage = StageDef(
    id: '1-1',
    chapterId: '1',
    title: LocalizedText({'ja': 'テスト', 'en': 'TEST'}),
    rounds: [],
    stars: [ClearStar(), NoHitStar()],
  );

  Future<void> pump(
    WidgetTester t, {
    StageDef? stage,
    bool cleared = false,
    int bestScore = 0,
    String locale = 'ja',
  }) async {
    t.view
      ..physicalSize = const Size(1600, 740)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: Locale(locale),
      home: ResultOverlay(
        data: ResultData(
          score: 1700,
          round: 1,
          maxChain: 2,
          stats: RunStats(),
          reason: 'BALL LOST',
          newBest: false,
          bestScore: bestScore,
          bestRound: 1,
          stage: stage,
          cleared: cleared,
          achieved: stage == null ? null : [cleared, false],
        ),
        onRetry: () {},
        onTitle: () {},
        reduceMotion: true,
      ),
    ));
  }

  testWidgets('まだクリアしていないステージで失敗すると、HI-SCORE の行に添え書きが出る', (t) async {
    await pump(t, stage: stage);
    expect(find.text('クリアした回のみ記録'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('英語では CLEAR ONLY と出る', (t) async {
    await pump(t, stage: stage, locale: 'en');
    expect(find.text('CLEAR ONLY'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('クリア済みのステージで失敗したときも添える', (t) async {
    await pump(t, stage: stage, bestScore: 5000);
    expect(find.text('クリアした回のみ記録'), findsOneWidget);
  });

  testWidgets('クリアした結果画面には出ない', (t) async {
    await pump(t, stage: stage, cleared: true, bestScore: 1700);
    expect(find.text('クリアした回のみ記録'), findsNothing);
  });

  testWidgets('エンドレスの結果画面には出ない', (t) async {
    await pump(t, bestScore: 1700);
    expect(find.text('クリアした回のみ記録'), findsNothing);
  });
}
