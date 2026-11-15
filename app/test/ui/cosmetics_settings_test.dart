import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:parry_break/core/core.dart';
import 'package:parry_break/main.dart';
import 'package:parry_break/render/cosmetics.dart';
import 'package:parry_break/services/content.dart';
import 'package:parry_break/services/leaderboard.dart';
import 'package:parry_break/services/progress.dart';
import 'package:parry_break/services/settings.dart';
import 'package:parry_break/ui/settings_screen.dart';

import '../core/helpers.dart';

import 'package:shared_preferences/shared_preferences.dart';

/// 設定の「見た目」(design.md 9.4・9.9): レベルで解放された色だけ選べる。まだのものは鍵と解放のレベルを出す。
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

  /// [level] のプレイヤーで設定を開き、表示の分類まで進める。
  Future<ProviderContainer> open(
    WidgetTester t, {
    int level = 1,
    String lang = 'en',
    Size size = const Size(844, 390),
    Settings settings = const Settings(),
  }) async {
    t.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    PackageInfo.setMockInitialValues(
      appName: 'PARRY BREAK',
      packageName: 'parry_break',
      version: '9.8.7',
      buildNumber: '1',
      buildSignature: '',
    );
    SharedPreferences.setMockInitialValues({
      'settings.v1': jsonEncode(
        settings.copyWith(language: () => lang).toJson(),
      ),
      'progress.v1': jsonEncode({
        'version': 1,
        'xp': LevelCurve.standard.xpAt(level),
      }),
    });
    final sp = await SharedPreferences.getInstance();
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(sp),
          contentProvider.overrideWithValue(
            GameContent(endless: endlessContent, campaign: campaign),
          ),
          leaderboardProvider.overrideWithValue(DisabledLeaderboard()),
        ],
        child: const ParryBreakApp(home: SettingsScreen()),
      ),
    );
    await t.pump(const Duration(milliseconds: 600));
    await t.tap(find.text(lang == 'ja' ? '表示' : 'DISPLAY'));
    await t.pump();
    return ProviderScope.containerOf(t.element(find.byType(SettingsScreen)));
  }

  /// 見た目の色の 1 つ分 (大きさ 150×48 の枠)。
  Finder tiles() => find.byWidgetPredicate(
    (w) => w is SizedBox && w.width == 150 && w.height == 48,
  );

  /// 見た目の項目まで、一覧をスクロールする。
  Future<void> scrollToEnd(WidgetTester t) async {
    final list = find.byType(ListView).last;
    await t.drag(list, const Offset(0, -2000));
    await t.pump();
  }

  Finder tileOf(String name, {bool last = false}) {
    final f = find.descendant(of: tiles(), matching: find.text(name));
    return last ? f.last : f.first;
  }

  for (final (name, size) in const [
    ('568×320', Size(568, 320)),
    ('667×375', Size(667, 375)),
    ('844×390', Size(844, 390)),
    ('1280×800', Size(1280, 800)),
  ]) {
    for (final lang in ['ja', 'en']) {
      testWidgets('$name ($lang): 見た目の項目がはみ出さず、押せる範囲は 44pt 以上', (t) async {
        await open(t, size: size, lang: lang);
        // 画面ぜんたいを少しずつスクロールして、出てくる枠をすべて確かめる
        final seen = <String>{};
        for (var i = 0; i < 8; i++) {
          expect(t.takeException(), isNull, reason: 'scroll $i');
          for (final e in tiles().evaluate()) {
            final r = t.getRect(find.byWidget(e.widget));
            expect(r.width, greaterThanOrEqualTo(44));
            expect(r.height, greaterThanOrEqualTo(44));
            expect(r.left, greaterThanOrEqualTo(0));
            expect(r.right, lessThanOrEqualTo(size.width));
            seen.add('${r.left},${r.top},$i');
          }
          await t.drag(find.byType(ListView).last, const Offset(0, -150));
          await t.pump();
        }
        expect(seen, isNotEmpty);
        await scrollToEnd(t);
        expect(t.takeException(), isNull);
        // 12 の枠 (パドル 6 + 軌跡 6) のうち、見える範囲にある分は押せる大きさ
        expect(tiles(), findsWidgets);
      });
    }
  }

  testWidgets('Lv1: 既定の色だけ選べて、残りは鍵と「Unlocks at LV n」(日本語は「LV n で解放」)', (
    t,
  ) async {
    await open(t);
    await scrollToEnd(t);
    expect(find.text('Paddle color'), findsOneWidget);
    expect(find.text('Ball trail color'), findsOneWidget);
    expect(find.text('Unlocks at LV 2'), findsOneWidget);
    expect(find.text('Unlocks at LV 30'), findsOneWidget);
    expect(find.text('SKY'), findsOneWidget);
    expect(find.text('STANDARD'), findsOneWidget);
  });

  testWidgets('日本語: 「LV 10 で解放」と出る', (t) async {
    await open(t, lang: 'ja');
    await scrollToEnd(t);
    expect(find.text('パドルの色'), findsOneWidget);
    expect(find.text('ボールの軌跡の色'), findsOneWidget);
    expect(find.text('LV 10 で解放'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('解放した色をタップすると、設定に保存される。未解放の色は選べない', (t) async {
    final c = await open(t, level: 6);
    await scrollToEnd(t);
    Settings s() => c.read(settingsProvider);
    expect(s().paddleColor, 'sky');

    // Lv6: パドルは CYAN (Lv2)・LIME (Lv6)、軌跡は CYAN (Lv4)
    await t.tap(tileOf('LIME'));
    await t.pump();
    expect(s().paddleColor, 'lime');
    final stored = jsonDecode(
      (await SharedPreferences.getInstance()).getString('settings.v1')!,
    ) as Map<String, Object?>;
    expect(stored['paddleColor'], 'lime');
    expect(stored['trailColor'], 'standard');

    // 未解放 (TEAL は Lv10) はタップしても変わらない
    await t.tap(tileOf('TEAL'));
    await t.pump();
    expect(s().paddleColor, 'lime');
    // 軌跡 (CYAN は Lv4 で解放済み。LAVENDER は Lv13)
    await t.tap(tileOf('CYAN', last: true));
    await t.pump();
    expect(s().trailColor, 'cyan');
    await t.tap(tileOf('LAVENDER', last: true));
    await t.pump();
    expect(s().trailColor, 'cyan');
    expect(t.takeException(), isNull);
  });

  testWidgets('キーボード: ←→ で、解放済みの隣の色へ (鍵の色は飛ばす)', (t) async {
    final c = await open(t, level: 10);
    Settings s() => c.read(settingsProvider);
    // 表示の分類へ入り、見た目の最初の項目 (パドル) まで ↓
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    for (var i = 0; i < 4; i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pump();
    }
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pump();
    expect(s().paddleColor, 'cyan');
    for (var i = 0; i < 5; i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pump();
    }
    // Lv10 で使えるパドルは SKY・CYAN・LIME・TEAL まで
    expect(s().paddleColor, 'teal');
    await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await t.pump();
    expect(s().paddleColor, 'lime');
  });

  test('保存の型: 設定は paddleColor / trailColor を文字列で持つ', () {
    final j = const Settings().toJson();
    expect(j['paddleColor'], isA<String>());
    expect(j['trailColor'], isA<String>());
    for (final k in CosmeticKind.values) {
      expect(Cosmetics.of(k).first.id, Cosmetics.known(k, j['${k.name}Color']));
    }
  });
}
