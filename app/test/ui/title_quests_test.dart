import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parry_break/core/core.dart';
import 'package:parry_break/l10n/app_localizations.dart';
import 'package:parry_break/main.dart';
import 'package:parry_break/services/content.dart';
import 'package:parry_break/services/daily.dart';
import 'package:parry_break/services/leaderboard.dart';
import 'package:parry_break/services/progress.dart';
import 'package:parry_break/services/quests.dart';
import 'package:parry_break/services/records.dart';
import 'package:parry_break/services/settings.dart';
import 'package:parry_break/ui/quest_text.dart';
import 'package:parry_break/ui/title/title_screen.dart';
import 'package:parry_break/ui/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// タイトルの今日のお題の札 (`TODAY 1/3`) とパネル (design.md 9.10)。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime.utc(2026, 11, 15, 9);
  final today = DailyChallenge.dayOf(now);

  setUpAll(() async {
    await (FontLoader(
      'DotGothic16',
    )..addFont(rootBundle.load('assets/fonts/DotGothic16-subset.ttf'))).load();
    await (FontLoader('Silkscreen')
          ..addFont(rootBundle.load('assets/fonts/Silkscreen-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Silkscreen-Bold.ttf')))
        .load();
  });

  Future<ProviderContainer> pumpTitle(
    WidgetTester tester, {
    required Size size,
    String lang = 'en',
    QuestBoard? board,
    DateTime? clock,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({
      'settings.v1': jsonEncode(
        const Settings().copyWith(language: () => lang).toJson(),
      ),
      'records': jsonEncode(
        const Records(
          endless: EndlessRecord(bestScore: 123456789, bestRound: 27),
          endlessEasy: EndlessRecord(bestScore: 222000, bestRound: 8),
        ).toJson(),
      ),
      if (board != null) QuestNotifier.key: jsonEncode(board.toJson()),
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
          dailyClockProvider.overrideWithValue(() => clock ?? now),
        ],
        child: const ParryBreakApp(home: TitleScreen()),
      ),
    );
    await tester.pump(const Duration(seconds: 3));
    return ProviderScope.containerOf(tester.element(find.byType(TitleScreen)));
  }

  /// 画面上の文字の大きさの最小 (縮めた分を含む)。
  double smallestText(WidgetTester t, Finder within) {
    var text = double.infinity;
    for (final e
        in find
            .descendant(of: within, matching: find.byType(RichText))
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
    return text;
  }

  QuestBoard partly() {
    final b = QuestBoard.generate(today);
    return QuestBoard(
      day: today,
      quests: [
        for (final (i, q) in b.quests.indexed)
          Quest(
            kind: q.kind,
            tier: q.tier,
            progress: i == 0 ? q.target : q.target ~/ 2,
            done: i == 0,
          ),
      ],
    );
  }

  testWidgets('札は、まだ何も達成していなければ TODAY 0/3、達成するたびに増える', (tester) async {
    final c = await pumpTitle(tester, size: const Size(844, 390));
    expect(find.text('TODAY 0/3'), findsOneWidget);
    // 1 つ達成する (どの種類でも届く結果を、3 回)
    final n = c.read(questsProvider.notifier);
    for (var i = 0; i < 3; i++) {
      n.record(
        QuestPlay(
          kind: PlayKind.endless,
          stats: RunStats()
            ..perfects = 99
            ..just = 99
            ..fevers = 99
            ..returnKills = 99,
          round: 99,
          score: 99000000,
          cleared: true,
        ),
      );
    }
    await tester.pump();
    expect(find.text('TODAY 3/3'), findsOneWidget);
  });

  testWidgets('保存してあるのが前の日のお題なら、札はその日の新しいお題 (0/3)', (tester) async {
    final yesterday = partly();
    await pumpTitle(
      tester,
      size: const Size(844, 390),
      board: QuestBoard(day: today - 1, quests: yesterday.quests),
    );
    expect(find.text('TODAY 0/3'), findsOneWidget);
    await tester.tap(find.text('TODAY 0/3'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('DONE'), findsNothing);
  });

  testWidgets('札をタップするとパネルが開き、3 つのお題・進み・報酬が出る。CLOSE で閉じる', (tester) async {
    final board = partly();
    await pumpTitle(tester, size: const Size(844, 390), board: board);
    expect(find.text('TODAY 1/3'), findsOneWidget);
    await tester.tap(find.text('TODAY 1/3'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text("TODAY'S QUESTS"), findsOneWidget);
    expect(tester.takeException(), isNull);
    final l = await _en();
    for (final q in board.quests) {
      expect(find.text(questText(l, q)), findsOneWidget);
      expect(find.text('+${q.xp} XP'), findsOneWidget);
    }
    expect(find.text('DONE'), findsOneWidget);
    expect(find.text('All 3 done: +200 XP'), findsOneWidget);
    await tester.tap(find.text('CLOSE'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text("TODAY'S QUESTS"), findsNothing);
  });

  for (final size in const [
    Size(568, 320),
    Size(667, 375),
    Size(844, 390),
    Size(1280, 800),
  ]) {
    for (final lang in const ['ja', 'en']) {
      final label = '$lang ${size.width.toInt()}x${size.height.toInt()}';
      testWidgets('札: ほかの要素とぶつからず、押せる範囲は 44pt 以上 ($label)', (tester) async {
        await pumpTitle(tester, size: size, lang: lang, board: partly());
        expect(tester.takeException(), isNull);
        final tag = find.text('TODAY 1/3');
        expect(tag, findsOneWidget);
        // 押せる範囲 (札を包む ConstrainedBox)
        final hit = tester.getRect(
          find.ancestor(of: tag, matching: find.byType(ConstrainedBox)).first,
        );
        expect(hit.height, greaterThanOrEqualTo(44), reason: label);
        expect(hit.width, greaterThanOrEqualTo(44), reason: label);
        // 文字は 11pt 以上
        expect(
          smallestText(tester, find.byType(TitleScreen)),
          greaterThanOrEqualTo(10),
        );
        expect(tester.getSize(tag).height, greaterThan(0));
        final text = tester.getRect(tag);
        expect(text.left, greaterThanOrEqualTo(0));
        expect(text.right, lessThanOrEqualTo(size.width));
        // 左の列のほかの要素 (難易度の切り替え・HI-SCORE・DAILY / PRACTICE の窓) と重ならない
        for (final other in [
          'EASY',
          'NORMAL',
          'HI-SCORE',
          'DAILY',
          'PRACTICE',
        ]) {
          final f = find.textContaining(other);
          for (final e in f.evaluate()) {
            final r = tester.getRect(find.byWidget(e.widget));
            expect(
              hit.overlaps(r),
              isFalse,
              reason: '$label: 札の押せる範囲が $other と重なる ($hit / $r)',
            );
          }
        }
        // 右のメニュー (列の右半分) にも食い込まない
        final menu = tester.getRect(find.text('ENDLESS'));
        expect(hit.right, lessThan(menu.left), reason: label);
        // LV の表示とも重ならない
        final lv = tester.getRect(find.textContaining('LV '));
        expect(hit.top, greaterThanOrEqualTo(lv.bottom - 1), reason: label);
      });

      testWidgets('パネル: はみ出さず、CLOSE は 44pt 以上、文字は 11pt 以上 ($label)', (
        tester,
      ) async {
        await pumpTitle(tester, size: size, lang: lang, board: partly());
        await tester.tap(find.text('TODAY 1/3'));
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull, reason: label);
        final panel = find.byType(Dialog);
        expect(panel, findsOneWidget);
        final rect = tester.getRect(panel);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(size.width));
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.bottom, lessThanOrEqualTo(size.height));
        final close = tester.getRect(find.byType(PixelButton));
        expect(close.height, greaterThanOrEqualTo(44), reason: label);
        expect(close.bottom, lessThanOrEqualTo(size.height), reason: label);
        expect(
          smallestText(tester, panel),
          greaterThanOrEqualTo(11),
          reason: label,
        );
        // 3 つのお題がどれも画面の中に出る (狭い画面は送れる)
        final l = lang == 'ja' ? await _ja() : await _en();
        for (final q in partly().quests) {
          expect(find.text(questText(l, q)), findsOneWidget, reason: label);
        }
        // ESC のかわりに、枠の外をタップしても閉じる
        await tester.tapAt(const Offset(2, 2));
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byType(Dialog), findsNothing, reason: label);
      });
    }
  }
}

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));
Future<AppLocalizations> _ja() =>
    AppLocalizations.delegate.load(const Locale('ja'));
