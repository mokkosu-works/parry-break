import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ricochet/app/providers.dart';
import 'package:ricochet/core/core.dart';
import 'package:ricochet/game/game_screen.dart';
import 'package:ricochet/main.dart';
import 'package:ricochet/services/content.dart';
import 'package:ricochet/services/records.dart';
import 'package:ricochet/services/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/helpers.dart';

/// アプリ全体を偽の時刻で動かすテスト。
///
/// 普段は例外が出ないことだけを確かめる。画面写真を書き出すときは:
///   flutter test test/app/app_test.dart --dart-define=screenshots=true --update-goldens
/// (test/app/screenshots/ に PNG ができる)
const _shots = bool.fromEnvironment('screenshots');

final _campaign = Campaign.fromJson(
    jsonDecode(File('assets/stages/campaign.json').readAsStringSync()) as Map<String, Object?>, endlessContent);

Future<void> _loadFonts() async {
  await (FontLoader('Orbitron')..addFont(rootBundle.load('assets/fonts/Orbitron.ttf'))).load();
  if (!_shots) return;
  // 画面写真の文字を読めるようにする (テストの標準フォントは四角で描かれる)
  for (final f in ['Roboto', 'MaterialIcons']) {
    final path = f == 'Roboto'
        ? '/System/Library/Fonts/Supplemental/Arial.ttf'
        : '${Platform.environment['FLUTTER_ROOT'] ?? '/opt/homebrew/share/flutter'}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf';
    final file = File(path);
    if (file.existsSync()) {
      await (FontLoader(f)..addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())))).load();
    }
  }
}

Future<void> _pumpApp(WidgetTester tester,
    {Widget? home, Map<String, Object> prefs = const {}, Size size = const Size(1600, 740), double dpr = 1}) async {
  tester.view
    ..physicalSize = size * dpr
    ..devicePixelRatio = dpr;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({
    'settings.v1': jsonEncode(const Settings(language: 'en').toJson()),
    ...prefs,
  });
  final sp = await SharedPreferences.getInstance();
  final binding = tester.binding;
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(sp),
      contentProvider.overrideWithValue(GameContent(endless: endlessContent, campaign: _campaign)),
      timeSourceProvider.overrideWithValue(() => binding.clock.now().microsecondsSinceEpoch / 1e6),
    ],
    child: RicochetApp(home: home),
  ));
  await tester.pump();
}

Future<void> _frames(WidgetTester tester, double seconds) async {
  for (var i = 0; i < (seconds * 60).round(); i++) {
    await tester.pump(const Duration(microseconds: 16667));
  }
}

Future<void> _shot(WidgetTester tester, String name) async {
  if (!_shots) return;
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('screenshots/$name.png'));
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('タイトル → エンドレスを始めて遊び、ポーズして再開できる', (tester) async {
    await _pumpApp(tester, prefs: {
      'records': jsonEncode(const Records(endless: EndlessRecord(bestScore: 123456, bestWave: 7)).toJson()),
    });
    await _frames(tester, 2.4);
    await _shot(tester, '01_title');

    await tester.tap(find.text('ENDLESS'));
    await _frames(tester, 0.8);
    expect(find.byType(GameScreen), findsOneWidget);
    await _shot(tester, '02_wave_start');
    await _frames(tester, 0.4);

    await tester.sendKeyEvent(LogicalKeyboardKey.space); // 発射
    await _frames(tester, 1.2);
    expect(find.byType(GameScreen), findsOneWidget); // Space がタイトルのボタンを押していない
    await _shot(tester, '03_playing');

    await tester.tap(find.byIcon(Icons.pause));
    await _frames(tester, 0.2);
    expect(find.text('PAUSED'), findsWidgets);
    await _shot(tester, '04_paused');
    await tester.tap(find.text('RESUME'));
    await _frames(tester, 1.3); // 1 秒のカウントダウン
    expect(find.text('PAUSED'), findsNothing);
    await _frames(tester, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('タイトル: スマホの大きさ・初回起動 (チュートリアルへ案内)', (tester) async {
    await _pumpApp(tester, size: const Size(852, 393), dpr: 2);
    await _frames(tester, 2.4);
    expect(find.text('START'), findsOneWidget);
    expect(find.text('TUTORIAL  1-1'), findsOneWidget);
    await _shot(tester, '09_title_phone_first');
    expect(tester.takeException(), isNull);
  });

  testWidgets('タッチ操作: 左半分のドラッグで移動、右半分のタップで発射', (tester) async {
    await _pumpApp(tester, home: const GameScreen());
    await _frames(tester, 1.2);
    final w = GameScreen.debugLastController!.world;
    final x0 = w.paddle.x;
    final g = await tester.startGesture(const Offset(150, 600));
    for (var i = 0; i < 10; i++) {
      await g.moveBy(const Offset(-10, 0));
      await _frames(tester, 1 / 60);
    }
    await g.up();
    await _frames(tester, 0.1);
    // 指を 100px 動かすと、感度 ×2 なので盤面上で約 200 / 拡大率 動く
    expect(x0 - w.paddle.x, closeTo(200 / (740 / 720), 20));
    expect(w.ball.attached, isTrue);
    await tester.tapAt(const Offset(1450, 400));
    await _frames(tester, 0.1);
    expect(w.ball.attached, isFalse);
  });

  testWidgets('結果画面: エンドレスのゲームオーバー (記録更新)', (tester) async {
    await _pumpApp(tester, home: const GameScreen());
    await _frames(tester, 1.2);
    final w = GameScreen.debugLastController!.world;
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await _frames(tester, 0.3);
    w
      ..addScore(1234560)
      ..maxStreak = 17;
    w.stats
      ..just = 9
      ..graze = 23
      ..bestCollapse = 31
      ..bestBlast = 4
      ..bestRicochet = 12;
    w.ball
      ..y = Field.height - 4
      ..vy = 600;
    await _frames(tester, 3.2);
    expect(find.text('RETRY'), findsOneWidget);
    await _shot(tester, '10_result_endless');
    await tester.tap(find.text('RETRY'));
    await _frames(tester, 0.5);
    expect(find.text('RETRY'), findsNothing);
  });

  testWidgets('結果画面: ステージクリア (星 3 つ)', (tester) async {
    await _pumpApp(tester, home: GameScreen(stage: _campaign.stage('1-4')));
    await _frames(tester, 1.2);
    final w = GameScreen.debugLastController!.world;
    w.stats.returnKills = 3;
    for (final b in w.blocks.where((b) => b.behavior.clearable).toList()) {
      w.destroyBlock(b, DestroyCause.pierce);
    }
    await _frames(tester, 6.5);
    expect(find.text('NEXT STAGE'), findsOneWidget);
    await _shot(tester, '11_result_stage_clear');
  });

  testWidgets('ボスのステージ (要塞・コア・HP バー) を描ける', (tester) async {
    await _pumpApp(tester, home: GameScreen(stage: _campaign.stage('1-10')));
    await _frames(tester, 1.2);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await _frames(tester, 3.5);
    await _shot(tester, '05_boss');
    expect(tester.takeException(), isNull);
  });

  testWidgets('ステージ選択と設定の画面', (tester) async {
    await _pumpApp(tester, prefs: {
      'records': jsonEncode(const Records(stages: {
        '1-1': StageRecord(cleared: true, bestScore: 50000, stars: [true, true, false]),
        '1-2': StageRecord(cleared: true, bestScore: 80000, stars: [true, false, false]),
      }).toJson()),
    });
    await tester.tap(find.text('STAGES'));
    await _frames(tester, 0.5);
    await _shot(tester, '06_stage_select');
    await tester.tap(find.text('1-3'));
    await _frames(tester, 0.5);
    expect(find.text('START'), findsOneWidget);
    await _shot(tester, '07_stage_detail');
    await tester.tap(find.text('BACK'));
    await _frames(tester, 0.3);
    await tester.tap(find.byIcon(Icons.arrow_back));
    await _frames(tester, 0.5);
    await tester.tap(find.text('SETTINGS'));
    await _frames(tester, 0.5);
    await _shot(tester, '08_settings');
    expect(tester.takeException(), isNull);
  });
}
