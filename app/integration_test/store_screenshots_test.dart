// App Store 用のスクリーンショットを、シミュレータで実際のアプリを動かして撮る。
// ファイル名の番号は App Store に載せる順 (最初の 1 枚が検索結果に出るので、プレイ画面から並べる)。
//
//   SHOT_DIR=build/store_screenshots/iphone flutter drive -d <デバイス ID> \
//     --driver=test_driver/integration_test.dart --target=integration_test/store_screenshots_test.dart
//
// 手順は docs/app-store.md の「スクリーンショット」を参照。
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:parry_break/core/core.dart';
import 'package:parry_break/main.dart';
import 'package:parry_break/render/field_painter.dart';
import 'package:parry_break/services/content.dart';
import 'package:parry_break/services/leaderboard.dart';
import 'package:parry_break/services/records.dart';
import 'package:parry_break/services/settings.dart';
import 'package:parry_break/ui/stage_select_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// タイトルに「ランキング」を出すための、何もしないランキング。
class _ShowcaseLeaderboard implements LeaderboardService {
  @override
  bool get available => true;
  @override
  Future<void> signIn() async {}
  @override
  Future<void> submit(Board board, int value) async {}
  @override
  Future<bool> show([Board? board]) async => false;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  const lang = String.fromEnvironment('lang', defaultValue: 'ja');
  const playWave = int.fromEnvironment('playWave', defaultValue: 28);

  Future<void> wait(WidgetTester t, double seconds) => t.pump(Duration(milliseconds: (seconds * 1000).round()));
  Future<void> shot(String name) => binding.takeScreenshot(name);

  World world(WidgetTester t) =>
      t.widgetList<CustomPaint>(find.byType(CustomPaint)).map((c) => c.painter).whereType<FieldPainter>().first.world;

  /// [seconds] だけ実際に遊ぶ。パドルでボールを追い、当たる直前に Space キーでパリィする
  /// (キー入力は実機のタッチと同じ経路でゲームの時計に換算される)。
  Future<void> play(WidgetTester t, World w, double seconds) async {
    final end = DateTime.now().add(Duration(milliseconds: (seconds * 1000).round()));
    var armed = true;
    while (DateTime.now().isBefore(end)) {
      // 撮影中は被弾させない (被弾するとヒートが下がり、HIT! が写る)。無敵中はパドルが点滅するので、撮る直前に外す
      w.paddle.invuln = 5;
      final b = w.ball;
      w.input
        ..useTarget = true
        ..targetX = b.x - 30 * math.sin(w.t * 1.3);
      if (b.vy < 0) armed = true;
      if (armed && !b.attached && b.vy > 0 && (Field.paddleY - b.y) / b.vy < 0.012) {
        armed = false;
        await t.sendKeyEvent(LogicalKeyboardKey.space);
      }
      await t.pump(const Duration(milliseconds: 4));
    }
  }

  /// 次のパリィが決まった直後まで遊ぶ (PERFECT などの表示を写すため)。
  Future<void> playUntilParry(WidgetTester t, World w, {double timeout = 6}) async {
    final before = w.stats.perfects;
    final end = DateTime.now().add(Duration(milliseconds: (timeout * 1000).round()));
    while (DateTime.now().isBefore(end) && w.stats.perfects == before) {
      await play(t, w, 0.05);
    }
    await play(t, w, 0.12);
  }

  /// 無敵を外して 1 フレーム進めてから撮る。
  Future<void> snap(WidgetTester t, World w, String name) async {
    w.paddle.invuln = 0;
    await t.pump(const Duration(milliseconds: 20));
    await shot(name);
  }

  void launch(World w) => w.ball
    ..attached = false
    ..vy = -500
    ..vx = 120;

  testWidgets('store screenshots', (t) async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SharedPreferences.setMockInitialValues({
      'settings.v1': jsonEncode(Settings(language: lang, timingOffsetMs: 0).toJson()),
      'records': jsonEncode(Records(
        endless: const EndlessRecord(bestScore: 1284600, bestWave: 27),
        stages: {
          for (var i = 1; i <= 10; i++)
            '1-$i': StageRecord(cleared: true, bestScore: 20000 + i * 3100, stars: [true, i % 3 != 0, i % 4 != 0]),
          '2-1': const StageRecord(cleared: true, bestScore: 41200, stars: [true, true, false]),
          '2-2': const StageRecord(cleared: true, bestScore: 38800, stars: [true, false, false]),
        },
      ).toJson()),
    });
    final prefs = await SharedPreferences.getInstance();
    final content = await GameContent.load(rootBundle);
    await t.pumpWidget(ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        contentProvider.overrideWithValue(content),
        leaderboardProvider.overrideWithValue(_ShowcaseLeaderboard()),
      ],
      child: const ParryBreakApp(),
    ));

    // 1. タイトル
    await wait(t, 3);
    await shot('05_title');

    // 2. ステージ選択
    await t.tap(find.text('STAGES'));
    await wait(t, 1.5);
    await shot('04_stages');
    Navigator.of(t.element(find.byType(StageSelectScreen))).pop();
    await wait(t, 1);

    // 3. エンドレスのプレイ中 (砲台の弾が飛び交い、ヒートが上がった場面)
    await t.tap(find.text('ENDLESS'));
    await wait(t, 1);
    var w = world(t)..start(fromWave: playWave);
    await wait(t, 1.3);
    launch(w);
    await play(t, w, 3);
    w.addHeat(450);
    await playUntilParry(t, w);
    await snap(t, w, '03_play');

    // 4. ボス戦 (フェーズ3・レーザー・弾幕。OVERDRIVE の手前)
    w = world(t)..start(fromWave: 20);
    await wait(t, 1.3);
    final core = w.blocks.firstWhere((b) => b.type == bossCoreId);
    for (var i = 0; i < 9; i++) {
      w.damageCore(core, 1);
    }
    launch(w);
    await play(t, w, 2.5);
    w.addHeat(500);
    w.fireLaser(w.paddle.x + 200);
    await playUntilParry(t, w);
    await snap(t, w, '01_boss');

    // 5. 崩落 (要石を1つだけ残して壊した直後。ウェーブが終わる前に撮る)
    w = world(t)..start(fromWave: 23);
    await wait(t, 1.3);
    launch(w);
    await play(t, w, 0.8);
    final keystones = w.blocks.where((b) => b.type == 'K').toList()..sort((a, b) => a.x.compareTo(b.x));
    for (final k in keystones.take(keystones.length - 1)) {
      w.destroyBlock(k, DestroyCause.pierce);
    }
    await play(t, w, 0.35);
    await snap(t, w, '02_collapse');
  });
}
