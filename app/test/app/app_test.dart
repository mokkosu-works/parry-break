import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:parry_break/app/providers.dart';
import 'package:parry_break/audio/audio_service.dart';
import 'package:parry_break/core/core.dart';
import 'package:parry_break/game/game_screen.dart';
import 'package:parry_break/main.dart';
import 'package:parry_break/services/ads.dart';
import 'package:parry_break/services/content.dart';
import 'package:parry_break/services/records.dart';
import 'package:parry_break/services/settings.dart';
import 'package:parry_break/ui/help_screen.dart';
import 'package:parry_break/ui/pixel_icons.dart';
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
  await (FontLoader('DotGothic16')..addFont(rootBundle.load('assets/fonts/DotGothic16-subset.ttf'))).load();
  await (FontLoader('Silkscreen')
        ..addFont(rootBundle.load('assets/fonts/Silkscreen-Regular.ttf'))
        ..addFont(rootBundle.load('assets/fonts/Silkscreen-Bold.ttf')))
      .load();
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
    {Widget? home,
    Map<String, Object> prefs = const {},
    Size size = const Size(1600, 740),
    double dpr = 1,
    AdsService? ads,
    AudioService? audio}) async {
  tester.view
    ..physicalSize = size * dpr
    ..devicePixelRatio = dpr;
  addTearDown(tester.view.reset);
  PackageInfo.setMockInitialValues(
      appName: 'PARRY BREAK', packageName: 'parry_break', version: '9.8.7', buildNumber: '1', buildSignature: '');
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
      if (ads != null) adsProvider.overrideWithValue(ads),
      if (audio != null) audioProvider.overrideWithValue(audio),
    ],
    child: ParryBreakApp(home: home),
  ));
  await tester.pump();
}

Future<void> _frames(WidgetTester tester, double seconds) async {
  for (var i = 0; i < (seconds * 60).round(); i++) {
    await tester.pump(const Duration(microseconds: 16667));
  }
}

/// ボールを落としてゲームオーバーにし、結果画面が出るまで進める。
Future<void> _gameOver(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.space); // 発射
  await _frames(tester, 0.3);
  GameScreen.debugLastController!.world.ball
    ..y = Field.height - 4
    ..vy = 600;
  await _frames(tester, 3.2);
}

/// 広告を出す代わりに回数を数える。
class _FakeAds extends DisabledAds {
  int shown = 0;
  @override
  Future<void> showInterstitialIfDue() async => shown++;
}

/// BGM に関わる呼び出しを覚える。
class _FakeAudio extends SilentAudio {
  bool menu = false;
  int games = 0;
  bool active = true;

  /// プレイ中の BGM が鳴っているはずか (SoLoudAudio と同じく、最後のゲーム画面が閉じたら止まる)。
  bool music = false;

  /// タイトル用の BGM が鳴っているはずか (SoLoudAudio と同じ条件)。
  bool get titlePlaying => menu && games == 0 && active;

  @override
  void setMenuMusic(bool on) => menu = on;
  @override
  void enterGame() => games++;
  @override
  void leaveGame() {
    if (--games == 0) music = false;
  }

  @override
  void startMusic() => music = true;
  @override
  void cutMusic() => music = false;
  @override
  void setAppActive(bool active) => this.active = active;
}

Future<void> _shot(WidgetTester tester, String name) async {
  if (!_shots) return;
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('screenshots/$name.png'));
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('タイトル → エンドレスを始めて遊び、ポーズして再開できる', (tester) async {
    await _pumpApp(tester, prefs: {
      'records': jsonEncode(const Records(endless: EndlessRecord(bestScore: 123456, bestRound: 7)).toJson()),
    });
    await _frames(tester, 2.4);
    await _shot(tester, '01_title');

    await tester.tap(find.text('ENDLESS'));
    await _frames(tester, 0.8);
    expect(find.byType(GameScreen), findsOneWidget);
    await _shot(tester, '02_round_start');
    await _frames(tester, 0.4);

    await tester.sendKeyEvent(LogicalKeyboardKey.space); // 発射
    await _frames(tester, 1.2);
    expect(find.byType(GameScreen), findsOneWidget); // Space がタイトルのボタンを押していない
    await _shot(tester, '03_playing');

    await tester.tap(find.byWidgetPredicate((w) => w is PixelIcon && w.glyph == PixelIcons.pause));
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

  testWidgets('タイトル: 2 回目からは CONTINUE で次のステージを遊べ、全部クリアしたら出ない', (tester) async {
    await _pumpApp(tester, prefs: {
      'records': jsonEncode(const Records(stages: {'1-1': StageRecord(cleared: true)}).toJson()),
    });
    await _frames(tester, 2.4);
    expect(find.text('START'), findsNothing);
    expect(find.text('STAGE  1-2'), findsOneWidget);
    await tester.tap(find.text('CONTINUE'));
    await _frames(tester, 0.8);
    expect(find.byWidgetPredicate((w) => w is GameScreen && w.stage?.id == '1-2'), findsOneWidget);
    await _frames(tester, 1);

    await _pumpApp(tester, prefs: {
      'records': jsonEncode(Records(stages: {
        for (final st in _campaign.stages) st.id: const StageRecord(cleared: true),
      }).toJson()),
    });
    await _frames(tester, 2.4);
    expect(find.text('CONTINUE'), findsNothing);
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
    final ads = _FakeAds();
    await _pumpApp(tester, home: const GameScreen(), ads: ads);
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
    expect(ads.shown, 0); // すぐ次を遊ぶときは広告を出さない
  });

  testWidgets('結果画面: TITLE で戻るときは広告を出す', (tester) async {
    final ads = _FakeAds();
    await _pumpApp(tester, home: const GameScreen(), ads: ads);
    await _frames(tester, 1.2);
    await _gameOver(tester);
    await tester.tap(find.text('TITLE'));
    await _frames(tester, 0.1);
    expect(ads.shown, 1);
  });

  testWidgets('タイトル用の BGM: メニューでは鳴り、ゲーム中は止まり、戻ると鳴る', (tester) async {
    final audio = _FakeAudio();
    await _pumpApp(tester, audio: audio);
    await _frames(tester, 1);
    expect(audio.titlePlaying, isTrue);

    await tester.tap(find.text('SETTINGS'));
    await _frames(tester, 0.5);
    expect(audio.titlePlaying, isTrue); // メニュー画面でも続く
    await tester.tap(find.byWidgetPredicate((w) => w is PixelIcon && w.glyph == PixelIcons.back));
    await _frames(tester, 0.5);

    await tester.tap(find.text('ENDLESS'));
    await _frames(tester, 0.8);
    expect(find.byType(GameScreen), findsOneWidget);
    expect(audio.titlePlaying, isFalse);

    await _frames(tester, 0.6);
    await _gameOver(tester);
    expect(audio.titlePlaying, isFalse); // 結果画面の間は鳴らさない
    await tester.tap(find.text('TITLE'));
    await _frames(tester, 1);
    expect(find.byType(GameScreen), findsNothing);
    expect(audio.titlePlaying, isTrue);
  });

  testWidgets('結果画面: デバッグモードのプレイでは広告を出さない', (tester) async {
    final debugAds = _FakeAds();
    await _pumpApp(tester,
        home: const GameScreen(),
        ads: debugAds,
        prefs: {'settings.v1': jsonEncode(const Settings(language: 'en', debugMode: true).toJson())});
    await _frames(tester, 1.2);
    await _gameOver(tester);
    await tester.tap(find.text('TITLE'));
    await _frames(tester, 0.1);
    expect(debugAds.shown, 0);
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

  testWidgets('結果画面: 次のステージへ進んでも BGM が止まらない', (tester) async {
    final audio = _FakeAudio();
    await _pumpApp(tester, home: GameScreen(stage: _campaign.stage('1-4')), audio: audio);
    for (var round = 0; round < 2; round++) {
      await _frames(tester, 1.2);
      final w = GameScreen.debugLastController!.world;
      for (final b in w.blocks.where((b) => b.behavior.clearable).toList()) {
        w.destroyBlock(b, DestroyCause.pierce);
      }
      await _frames(tester, 6.5);
      await tester.tap(find.text('NEXT STAGE'));
      await _frames(tester, 1); // 前の画面が閉じるまで
      expect(audio.games, 1);
      expect(audio.music, isTrue);
    }
    expect(tester.takeException(), isNull);
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
    await tester.tap(find.byWidgetPredicate((w) => w is PixelIcon && w.glyph == PixelIcons.back));
    await _frames(tester, 0.5);
    await tester.tap(find.text('SETTINGS'));
    await _frames(tester, 0.5);
    await _shot(tester, '08_settings');
    expect(tester.takeException(), isNull);
  });

  testWidgets('デバッグモード: 版番号を 3 回タップで入り、未クリアのステージを遊べ、記録は残さない', (tester) async {
    await _pumpApp(tester);
    await _frames(tester, 2.4);
    // 版番号はアプリの版 (pubspec.yaml の version) を出す
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('VER 9.8.7'));
      await _frames(tester, 0.1);
    }
    expect(find.text('Debug mode ON'), findsOneWidget);
    await _frames(tester, 5); // SnackBar が消えるまで待つ
    await tester.tap(find.text('STAGES'));
    await _frames(tester, 0.5);
    await tester.tap(find.text('1-6'));
    await _frames(tester, 0.5);
    await tester.tap(find.text('START'));
    await _frames(tester, 1.2);
    final w = GameScreen.debugLastController!.world;
    for (final b in w.blocks.where((b) => b.behavior.clearable).toList()) {
      w.destroyBlock(b, DestroyCause.pierce);
    }
    await _frames(tester, 6.5);
    expect(find.text('NEXT STAGE'), findsOneWidget); // 1-7 も未クリアのまま開いている
    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('records'), isNull);
  });

  testWidgets('遊び方の画面', (tester) async {
    await _pumpApp(tester);
    await tester.tap(find.text('HOW TO PLAY'));
    await _frames(tester, 0.5);
    expect(find.byType(HelpScreen), findsOneWidget);
    await _shot(tester, '12_help');
    expect(tester.takeException(), isNull);
  });

  for (final size in const [Size(667, 375), Size(1280, 720)]) {
    testWidgets('遊び方の COMBO / GRAZE のページが ${size.width.toInt()}×${size.height.toInt()} ではみ出さない', (tester) async {
      await _pumpApp(tester, home: const HelpScreen(), size: size);
      await _frames(tester, 0.5);
      for (final title in ['MOVE', 'LAUNCH / PARRY', 'TIMING', 'CHAIN', 'COMBO / FEVER TIME', 'GRAZE / RICOCHET']) {
        expect(find.text(title), findsOneWidget, reason: title);
        expect(tester.takeException(), isNull, reason: '$title がはみ出さない');
        await tester.tap(find.text('NEXT'));
        await _frames(tester, 0.5);
      }
    });
  }
}
