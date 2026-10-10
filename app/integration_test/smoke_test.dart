// 起動してから一通りの画面を通り、落ちないことを確かめる (エミュレーター・シミュレータで動かす)。
// PR ごとに CI (pr.yml) の Android エミュレーターで動き、Issue から実装するときは Claude も使う。
//
//   SHOT_DIR=build/smoke flutter drive -d <デバイス ID> \
//     --driver=test_driver/integration_test.dart --target=integration_test/smoke_test.dart
//
// 撮った画面は SHOT_DIR に PNG で残る。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:parry_break/core/core.dart';
import 'package:parry_break/game/game_screen.dart';
import 'package:parry_break/main.dart';
import 'package:parry_break/render/field_painter.dart';
import 'package:parry_break/services/content.dart';
import 'package:parry_break/services/leaderboard.dart';
import 'package:parry_break/services/settings.dart';
import 'package:parry_break/ui/stage_select_screen.dart';
import 'package:parry_break/ui/title/title_screen.dart';
import 'package:parry_break/ui/pixel_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  Future<void> wait(WidgetTester t, double seconds) => t.pump(Duration(milliseconds: (seconds * 1000).round()));

  var surfaceConverted = false;
  Future<void> shot(WidgetTester t, String name) async {
    // Android は描画面を画像に切り替えてからでないと撮れない (1 回だけ)
    if (Platform.isAndroid && !surfaceConverted) {
      await binding.convertFlutterSurfaceToImage();
      surfaceConverted = true;
      await t.pump();
    }
    await binding.takeScreenshot(name);
  }

  World world(WidgetTester t) =>
      t.widgetList<CustomPaint>(find.byType(CustomPaint)).map((c) => c.painter).whereType<FieldPainter>().first.world;

  testWidgets('起動してタイトル・ステージ選択・エンドレスを通り、タイトルに戻る', (t) async {
    // main() と同じく横向きに固定する (Android の向きは AndroidManifest.xml でも決めているが、iOS のシミュレータでも動かすため)
    await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // 初めて起動したときと同じ (記録も設定もない)
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final content = await GameContent.load(rootBundle);
    await t.pumpWidget(ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        contentProvider.overrideWithValue(content),
        // Game Center / Play Games のサインインの画面を出さない
        leaderboardProvider.overrideWithValue(DisabledLeaderboard()),
      ],
      child: const ParryBreakApp(),
    ));

    // タイトル
    await wait(t, 3);
    expect(find.byType(TitleScreen), findsOneWidget);
    expect(find.text('ENDLESS'), findsOneWidget);
    await shot(t, '01_title');

    // ステージ選択を開いて戻る
    await t.tap(find.text('STAGES'));
    await wait(t, 1.5);
    expect(find.byType(StageSelectScreen), findsOneWidget);
    await shot(t, '02_stages');
    Navigator.of(t.element(find.byType(StageSelectScreen))).pop();
    await wait(t, 1);

    // エンドレスを数秒遊ぶ。パリィの入力 (Space キー。タッチと同じ経路) でボールを出し、パドルでボールを追う
    await t.tap(find.text('ENDLESS'));
    await wait(t, 1);
    expect(find.byType(GameScreen), findsOneWidget);
    final w = world(t);
    final launchBy = DateTime.now().add(const Duration(seconds: 5));
    while (w.ball.attached && DateTime.now().isBefore(launchBy)) {
      await t.sendKeyEvent(LogicalKeyboardKey.space);
      await wait(t, 0.3);
    }
    expect(w.ball.attached, isFalse, reason: 'パリィの入力でボールが出る');
    final end = DateTime.now().add(const Duration(seconds: 8));
    while (DateTime.now().isBefore(end) && w.phase != WorldPhase.over) {
      w.input
        ..useTarget = true
        ..targetX = w.ball.x;
      await t.pump(const Duration(milliseconds: 16));
    }
    expect(w.phase, isNot(WorldPhase.over), reason: 'パドルがボールを追っていればゲームオーバーにならない');
    await shot(t, '03_endless');

    // 一時停止してタイトルに戻る
    await t.tap(find.byWidgetPredicate((w) => w is PixelIcon && w.glyph == PixelIcons.pause));
    await wait(t, 0.5);
    expect(find.text('PAUSED'), findsWidgets); // 色ずれの演出で重ねて描くので複数ある
    await shot(t, '04_paused');
    await t.tap(find.text('TITLE'));
    await wait(t, 1.5);
    expect(find.byType(GameScreen), findsNothing);
    expect(find.byType(TitleScreen), findsOneWidget);
    await shot(t, '05_back_to_title');
  });
}
