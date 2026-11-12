import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parry_break/core/core.dart';
import 'package:parry_break/game/result_overlay.dart';
import 'package:parry_break/l10n/app_localizations.dart';

/// Issue #95: 演出中は見えていないボタンを押せず、タップは演出を飛ばすだけにする。
void main() {
  late int retry, title;

  Future<void> pump(WidgetTester t, {bool reduceMotion = false}) async {
    t.view
      ..physicalSize = const Size(1600, 740)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    retry = 0;
    title = 0;
    await t.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: ResultOverlay(
          data: ResultData(
            score: 12345,
            round: 3,
            maxChain: 4,
            stats: RunStats(),
            reason: 'MISS',
            newBest: false,
            bestScore: 20000,
            bestRound: 5,
          ),
          onRetry: () => retry++,
          onTitle: () => title++,
          reduceMotion: reduceMotion,
        ),
      ),
    );
  }

  testWidgets('演出中にボタンの位置をタップすると、演出が飛ぶだけでボタンは呼ばれない', (t) async {
    await pump(t);
    await t.pump(const Duration(milliseconds: 300)); // スコアの数え上げ中
    await t.tap(find.text('TITLE'), warnIfMissed: false);
    await t.pump();
    expect(title, 0);
    expect(retry, 0);

    // 1 回目のタップで演出が終わっているので、次のタップは届く
    await t.tap(find.text('TITLE'));
    await t.pump();
    expect(title, 1);
  });

  testWidgets('演出が終わったあとはボタンが押せる', (t) async {
    await pump(t);
    await t.pump(const Duration(seconds: 3));
    await t.tap(find.text('RETRY'));
    await t.pump();
    expect(retry, 1);
  });

  testWidgets('演出を控えめにする が ON なら、すぐボタンが押せる', (t) async {
    await pump(t, reduceMotion: true);
    await t.tap(find.text('TITLE'));
    await t.pump();
    expect(title, 1);
  });
}
