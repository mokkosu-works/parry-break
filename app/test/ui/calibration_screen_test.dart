import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parry_break/app/providers.dart';
import 'package:parry_break/l10n/app_localizations.dart';
import 'package:parry_break/services/settings.dart';
import 'package:parry_break/ui/calibration_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 判定タイミングの測定の画面 (Issue #139 / #144)。
void main() {
  late AppLocalizations l;

  Future<void> pumpScreen(WidgetTester tester, {String lang = 'en', Size size = const Size(1600, 740)}) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    final binding = tester.binding;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(sp),
          timeSourceProvider.overrideWithValue(() => binding.clock.now().microsecondsSinceEpoch / 1e6),
        ],
        child: MaterialApp(
          locale: Locale(lang),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const CalibrationScreen(),
        ),
      ),
    );
    await tester.pump();
    l = AppLocalizations.of(tester.element(find.byType(CalibrationScreen)));
  }

  testWidgets('開いただけでは測定が始まらず、スタートを押すまで待つ', (tester) async {
    await pumpScreen(tester);
    expect(find.text(l.calibrationStart), findsOneWidget);
    // 説明を読んでいる間 (20 秒) に測定が終わってしまわない
    await tester.pump(const Duration(seconds: 20));
    expect(find.text(l.calibrationStart), findsOneWidget);
    expect(find.text(l.calibrationRetry), findsNothing);
  });

  for (final (lang, size) in [('en', const Size(1600, 740)), ('ja', const Size(667, 375))]) {
    testWidgets('タップが 4 回未満で終わると、失敗したことと、どうすればよいかが出る ($lang, ${size.width.toInt()}x${size.height.toInt()})', (
      tester,
    ) async {
      await pumpScreen(tester, lang: lang, size: size);
      await tester.tap(find.text(l.calibrationStart));
      await tester.pump();
      expect(find.text(l.calibrationStart), findsNothing);
      // 何もタップせずに 10 拍が過ぎる
      for (var i = 0; i < 120; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text(l.calibrationFailed('0', '4')), findsOneWidget);
      expect(find.text(l.calibrationRetry), findsOneWidget);
      expect(find.text(l.calibrationApply), findsNothing);

      // 測り直すと説明が消え、測定が始まる
      await tester.tap(find.text(l.calibrationRetry));
      await tester.pump();
      expect(find.text(l.calibrationFailed('0', '4')), findsNothing);
      expect(find.text(l.calibrationRetry), findsNothing);
    });
  }

  testWidgets('拍に合わせてタップすると、測定結果と「この値を使う」が出る', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.text(l.calibrationStart));
    await tester.pump();
    final center = tester.getCenter(find.byType(CustomPaint).last);
    // 1 拍目は 1.6 秒後、以降 0.8 秒ごと。各拍の 40ms 後にタップする
    await tester.pump(const Duration(milliseconds: 1640));
    for (var i = 0; i < 10; i++) {
      await tester.tapAt(center);
      await tester.pump(const Duration(milliseconds: 800));
    }
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text(l.calibrationResult('40')), findsOneWidget);
    expect(find.text(l.calibrationApply), findsOneWidget);
    expect(find.textContaining(l.calibrationFailed('0', '4').substring(0, 10)), findsNothing);
  });

  testWidgets('説明は画面の絵 (2 つの輪) に合い、「線」と書かない', (tester) async {
    for (final lang in ['ja', 'en']) {
      await pumpScreen(tester, lang: lang);
      final body = l.calibrationBody('10');
      expect(find.text(body), findsOneWidget);
      expect(body, isNot(contains(lang == 'ja' ? '線' : 'line')));
    }
  });
}
