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
import 'package:parry_break/render/field_painter.dart';
import 'package:parry_break/services/ads.dart';
import 'package:parry_break/services/content.dart';
import 'package:parry_break/services/history.dart';
import 'package:parry_break/services/leaderboard.dart';
import 'package:parry_break/services/records.dart';
import 'package:parry_break/services/settings.dart';
import 'package:parry_break/ui/calibration_screen.dart';
import 'package:parry_break/ui/help_screen.dart';
import 'package:parry_break/ui/history_screen.dart';
import 'package:parry_break/ui/pixel_icons.dart';
import 'package:parry_break/ui/settings_screen.dart';
import 'package:parry_break/ui/stage_select_screen.dart';
import 'package:parry_break/ui/widgets.dart';
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
    AudioService? audio,
    LeaderboardService? leaderboard}) async {
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
      if (leaderboard != null) leaderboardProvider.overrideWithValue(leaderboard),
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

/// 広告を出そうとすると例外を投げる。
class _ThrowingAds extends DisabledAds {
  int calls = 0;
  @override
  Future<void> showInterstitialIfDue() async {
    calls++;
    throw Exception('ads broken');
  }
}

/// ランキングを使える (タイトルに RANKING が出る)。
class _AvailableLeaderboard extends DisabledLeaderboard {
  @override
  bool get available => true;
}

/// 履歴の先頭の 1 件。
PlayEntry _latestPlay(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(MaterialApp))).read(historyProvider).entries.first;

/// 音の一時停止 (setPaused) を覚える。
class _PauseAudio extends SilentAudio {
  final paused = <bool>[];
  @override
  void setPaused(bool paused) => this.paused.add(paused);
}

/// 広告の同意が必要な地域 (設定に「広告のプライバシー設定」が出る)。
class _PrivacyAds extends DisabledAds {
  @override
  bool get privacyOptionsRequired => true;
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

  testWidgets('ポーズ中に設定で言語・画質を変えると、盤面にすぐ反映される (#98)', (tester) async {
    await _pumpApp(tester);
    await tester.tap(find.text('ENDLESS'));
    await _frames(tester, 0.8);
    FieldPainter painter() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((w) => w.painter)
        .whereType<FieldPainter>()
        .single;
    expect(painter().l10n.localeName, 'en');
    expect(painter().highQuality, isTrue);

    Future<void> changeSettings(Settings Function(Settings) f) async {
      await tester.tap(find.byWidgetPredicate((w) => w is PixelIcon && w.glyph == PixelIcons.pause));
      await _frames(tester, 0.2);
      await tester.tap(find.text('SETTINGS'));
      await _frames(tester, 0.5);
      ProviderScope.containerOf(tester.element(find.byType(MaterialApp))).read(settingsProvider.notifier).update(f);
      await tester.tap(find.byWidgetPredicate((w) => w is PixelIcon && w.glyph == PixelIcons.back));
      await _frames(tester, 0.5);
      expect(find.byType(GameScreen), findsOneWidget);
    }

    await changeSettings((s) => s.copyWith(language: () => 'ja', quality: GraphicsQuality.low));
    expect(painter().l10n.localeName, 'ja'); // 帯の説明は新しい言語で出る
    expect(painter().highQuality, isFalse); // 床のディザを描かない

    await tester.tap(find.text('RESUME'));
    await _frames(tester, 1.3);
    await changeSettings((s) => s.copyWith(quality: GraphicsQuality.high));
    expect(painter().highQuality, isTrue);
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

  // Issue #92: Android の戻るボタンで、確認なしにプレイが終わっていた
  testWidgets('戻るボタン: プレイ中はポーズ、ポーズ中は再開のカウントダウン、カウントダウン中は何もしない', (tester) async {
    await _pumpApp(tester);
    await _frames(tester, 2.4);
    await tester.tap(find.text('ENDLESS'));
    await _frames(tester, 1.2);
    final ctl = GameScreen.debugLastController!;
    await tester.sendKeyEvent(LogicalKeyboardKey.space); // 発射
    await _frames(tester, 0.5);

    // プレイ中: ポーズになり、画面は閉じない
    await tester.binding.handlePopRoute();
    await _frames(tester, 0.2);
    expect(find.byType(GameScreen), findsOneWidget);
    expect(ctl.paused, isTrue);
    expect(ctl.resumeCountdown, isNull);
    expect(find.text('PAUSED'), findsWidgets);

    // ポーズ中: 再開のカウントダウンが始まる (RESUME と同じ)
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(microseconds: 16667));
    expect(find.byType(GameScreen), findsOneWidget);
    expect(ctl.resumeCountdown, isNotNull);

    // カウントダウン中: 何もしない (カウントダウンは続き、画面も閉じない)
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(microseconds: 16667));
    expect(find.byType(GameScreen), findsOneWidget);
    expect(ctl.resumeCountdown, isNotNull);
    await _frames(tester, 1.3);
    expect(ctl.paused, isFalse);
    expect(find.text('PAUSED'), findsNothing);
    expect(ctl.finished, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('戻るボタン: エンドレスの結果画面では TITLE と同じく広告の判定を通ってタイトルへ戻る', (tester) async {
    final ads = _FakeAds();
    await _pumpApp(tester, ads: ads);
    await _frames(tester, 2.4);
    await tester.tap(find.text('ENDLESS'));
    await _frames(tester, 1.2);
    await _gameOver(tester);
    expect(find.text('RETRY'), findsOneWidget);
    expect(ads.shown, 0);

    await tester.binding.handlePopRoute();
    await _frames(tester, 1);
    expect(ads.shown, 1);
    expect(find.byType(GameScreen), findsNothing);
    expect(find.text('ENDLESS'), findsOneWidget); // タイトル
    expect(tester.takeException(), isNull);
  });

  testWidgets('戻るボタン: ステージの結果画面では STAGES と同じく広告の判定を通ってステージ選択へ戻る', (tester) async {
    final ads = _FakeAds();
    await _pumpApp(tester, ads: ads);
    await _frames(tester, 2.4);
    await tester.tap(find.text('STAGES'));
    await _frames(tester, 0.5);
    await tester.tap(find.text('1-1'));
    await _frames(tester, 0.5);
    await tester.tap(find.text('START'));
    await _frames(tester, 1.2);
    expect(find.byType(GameScreen), findsOneWidget);
    await _gameOver(tester);
    expect(find.text('RETRY'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await _frames(tester, 1);
    expect(ads.shown, 1);
    expect(find.byType(GameScreen), findsNothing);
    expect(find.text('1-1'), findsOneWidget); // ステージ選択
    expect(tester.takeException(), isNull);
  });

  testWidgets('結果画面: 広告で例外が出ても、音を戻してタイトルへ戻る', (tester) async {
    final ads = _ThrowingAds();
    final audio = _PauseAudio();
    await _pumpApp(tester, ads: ads, audio: audio);
    await _frames(tester, 1);
    await tester.tap(find.text('ENDLESS'));
    await _frames(tester, 1.4);
    await _gameOver(tester);
    audio.paused.clear();
    await tester.tap(find.text('TITLE'));
    await _frames(tester, 1);
    expect(ads.calls, 1);
    expect(audio.paused, [true, false]);
    expect(find.byType(GameScreen), findsNothing);
    expect(tester.takeException(), isNull);
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
    expect(sp.getString(PlayHistoryNotifier.key), isNull, reason: '履歴にも残さない');
  });

  testWidgets('遊び方の画面', (tester) async {
    await _pumpApp(tester);
    await tester.tap(find.text('HOW TO PLAY'));
    await _frames(tester, 0.5);
    expect(find.byType(HelpScreen), findsOneWidget);
    await _shot(tester, '12_help');
    expect(tester.takeException(), isNull);
  });

  // Issue #111: 遊び方の「移動」「発射・パリィ」「一時停止」にキーボードの操作を書く
  for (final language in ['en', 'ja']) {
    testWidgets('遊び方にキーボードの操作が出る ($language)', (tester) async {
      await _pumpApp(tester,
          home: const HelpScreen(),
          size: const Size(667, 375),
          prefs: {'settings.v1': jsonEncode(Settings(language: language).toJson())});
      await _frames(tester, 0.5);
      final ja = language == 'ja';
      final keys = {
        0: ja ? 'キーボード:←→ か A / D で移動' : 'Keyboard: ←→ or A / D to move',
        1: ja ? 'キーボード:Space か Enter で発射・パリィ' : 'Keyboard: Space or Enter to launch / parry',
        7: ja ? 'キーボード:Esc か P で一時停止' : 'Keyboard: Esc or P to pause',
      };
      for (var page = 0; page < 8; page++) {
        if (keys[page] case final text?) {
          expect(find.text(text), findsOneWidget, reason: 'page ${page + 1}');
        }
        expect(tester.takeException(), isNull, reason: 'page ${page + 1} がはみ出さない');
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await _frames(tester, 0.5);
      }
    });
  }

  // Issue #69: 狭い画面でタイルの番号が折り返して切れていた
  for (final size in const [Size(667, 375), Size(1280, 800)]) {
    for (final cleared in [false, true]) {
      testWidgets('ステージ選択: ${size.width.toInt()}x${size.height.toInt()} ${cleared ? 'クリア済み' : '選択中・未クリア'}のタイルの番号が 1 行で収まる',
          (tester) async {
        await _pumpApp(tester, size: size, prefs: {
          'settings.v1': jsonEncode(const Settings(language: 'en', debugMode: true).toJson()),
          if (cleared)
            'records': jsonEncode(const Records(stages: {
              '1-1': StageRecord(cleared: true),
              '1-10': StageRecord(cleared: true),
            }).toJson()),
        });
        await tester.tap(find.text('STAGES'));
        await _frames(tester, 0.5);
        final heights = <double>[];
        for (final id in ['1-1', '1-10']) {
          final label = find.text(id);
          expect(label, findsOneWidget);
          final tile = find.ancestor(of: label, matching: find.byType(GestureDetector)).first;
          final l = tester.getRect(label), t = tester.getRect(tile);
          expect(l.left, greaterThanOrEqualTo(t.left), reason: id);
          expect(l.right, lessThanOrEqualTo(t.right), reason: id);
          heights.add(l.height);
        }
        // 1 行のまま縮んでいる (折り返すと、文字の多い 1-10 のほうが高くなる)
        expect(heights[1], lessThanOrEqualTo(heights[0]));
        expect(tester.takeException(), isNull);
      });
    }
  }

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
  // Issue #122: 押せる範囲が 44pt より小さいボタンがあった
  group('押せる範囲が 44pt 以上', () {
    Size hitSize(WidgetTester tester, Finder f) =>
        tester.getSize(find.ancestor(of: f, matching: find.byType(GestureDetector)).first);

    testWidgets('ステージ選択の難易度の切り替え', (tester) async {
      await _pumpApp(tester, size: const Size(667, 375));
      await tester.tap(find.text('STAGES'));
      await _frames(tester, 0.5);
      for (final d in ['EASY', 'NORMAL', 'HARD']) {
        // 先に見つかるのが右上の切り替え (右の窓にも難易度の名前が出る)
        expect(hitSize(tester, find.text(d).first).height, greaterThanOrEqualTo(44), reason: d);
      }
      // 押した位置が枠の上下の外 (広げた範囲) でも切り替わる
      final easy = find.ancestor(of: find.text('EASY').first, matching: find.byType(GestureDetector)).first;
      await tester.tapAt(tester.getRect(easy).topCenter + const Offset(0, 2));
      await _frames(tester, 0.2);
      final sp = await SharedPreferences.getInstance();
      expect(Settings.fromJson(jsonDecode(sp.getString('settings.v1')!) as Map<String, Object?>).difficulty,
          Difficulty.easy);
      expect(tester.takeException(), isNull);
    });

    testWidgets('設定の − / + と、測定する・広告のプライバシー設定', (tester) async {
      await _pumpApp(tester, size: const Size(667, 375), ads: _PrivacyAds());
      await tester.tap(find.text('SETTINGS'));
      await _frames(tester, 0.5);
      for (final icon in [PixelIcons.minus, PixelIcons.plus]) {
        final buttons = find.ancestor(
            of: find.byWidgetPredicate((w) => w is PixelIcon && w.glyph == icon), matching: find.byType(IconButton));
        expect(buttons, findsWidgets);
        for (final b in buttons.evaluate()) {
          final size = tester.getSize(find.byWidget(b.widget));
          expect(size.width, greaterThanOrEqualTo(44));
          expect(size.height, greaterThanOrEqualTo(44));
        }
      }
      // 狭い画面では下のほうにあるので、項目の枠を送って出す
      await tester.scrollUntilVisible(find.text('Calibrate'), 80,
          scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)));
      await _frames(tester, 0.1);
      expect(hitSize(tester, find.text('Calibrate')).height, greaterThanOrEqualTo(44));
      await tester.tap(find.text('OTHER'));
      await _frames(tester, 0.3);
      expect(hitSize(tester, find.text('›')).height, greaterThanOrEqualTo(44));
      expect(tester.takeException(), isNull);
    });

    testWidgets('遊び方のページの点は押せない飾り', (tester) async {
      await _pumpApp(tester, home: const HelpScreen(), size: const Size(667, 375));
      await _frames(tester, 0.5);
      final dots = find.byType(AnimatedContainer);
      expect(dots, findsNWidgets(8));
      expect(find.ancestor(of: dots, matching: find.byType(GestureDetector)), findsNothing);
      expect(find.ancestor(of: dots, matching: find.byType(ExcludeSemantics)), findsWidgets);
    });
  });

  // Issue #147: 鍵のかかったステージは LOCKED と出るだけで、どうすれば開くかが分からなかった
  testWidgets('ステージ選択: 鍵のかかったステージに、開くためにクリアするステージが出る', (tester) async {
    await _pumpApp(tester, prefs: {
      'records': jsonEncode(const Records(stages: {'1-1': StageRecord(cleared: true)}).toJson()),
    });
    await tester.tap(find.text('STAGES'));
    await _frames(tester, 0.5);
    expect(find.text('START'), findsOneWidget); // 開いている 1-2 を選んでいる
    expect(find.textContaining('to unlock'), findsNothing);
    await tester.tap(find.text('1-3'));
    await _frames(tester, 0.3);
    expect(find.text('LOCKED'), findsOneWidget);
    expect(find.text('Clear 1-2 to unlock'), findsOneWidget);
    // 次の章へめくると 2-1 (鍵) を選び、前の章の最後が出る
    await tester.tap(find
        .ancestor(
            of: find.byWidgetPredicate((w) => w is PixelIcon && w.glyph == PixelIcons.chevronLeft),
            matching: find.byType(IconButton))
        .last);
    await _frames(tester, 0.3);
    expect(find.text('STAGE 2-1'), findsOneWidget);
    expect(find.text('Clear 1-10 to unlock'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ステージ選択: 開くためのステージの案内は日本語でも出る', (tester) async {
    await _pumpApp(tester, home: const StageSelectScreen(), size: const Size(667, 375), prefs: {
      'settings.v1': jsonEncode(const Settings(language: 'ja').toJson()),
    });
    await _frames(tester, 0.5);
    await tester.tap(find.text('1-2'));
    await _frames(tester, 0.3);
    expect(find.text('1-1 をクリアすると開く'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // Issue #109: ポーズ・結果・ステージ選択・設定をキーボードで操作する
  group('キーボード操作', () {
    bool selected(WidgetTester tester, String label) =>
        tester.widget<PixelButton>(find.widgetWithText(PixelButton, label)).selected;

    testWidgets('ポーズ: 矢印キーで選び、Enter で決め、Esc で再開する', (tester) async {
      await _pumpApp(tester, home: const GameScreen());
      await _frames(tester, 1.2);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _frames(tester, 0.2);
      expect(find.text('PAUSED'), findsWidgets);
      expect(selected(tester, 'RESUME'), isTrue);

      // → で RETRY → SETTINGS、← で戻る。端から先は反対の端へ回る
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(selected(tester, 'RETRY'), isTrue);
      expect(selected(tester, 'RESUME'), isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(selected(tester, 'SETTINGS'), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(selected(tester, 'TITLE'), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(selected(tester, 'RESUME'), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(selected(tester, 'SETTINGS'), isTrue);

      // Enter で設定を開き、Esc で閉じるとポーズに戻る
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await _frames(tester, 0.5);
      expect(find.byType(SettingsScreen), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _frames(tester, 0.5);
      expect(find.byType(SettingsScreen), findsNothing);
      expect(find.text('PAUSED'), findsWidgets);

      // RETRY を Enter で決めると、最初からやり直す
      final ctl = GameScreen.debugLastController!;
      ctl.world.addScore(500);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(selected(tester, 'RETRY'), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await _frames(tester, 0.2);
      expect(find.text('PAUSED'), findsNothing);
      expect(ctl.world.score, 0);

      // ポーズし直すと RESUME から。Esc でも Enter でも再開のカウントダウンに入る
      await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
      await _frames(tester, 0.2);
      expect(selected(tester, 'RESUME'), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await _frames(tester, 1.3);
      expect(find.text('PAUSED'), findsNothing);
      expect(ctl.paused, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _frames(tester, 0.2);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _frames(tester, 1.3);
      expect(ctl.paused, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('結果画面: 演出中の Enter は演出を飛ばし、そのあと矢印キーで選んで Enter で決める', (tester) async {
      final ads = _FakeAds();
      await _pumpApp(tester, home: GameScreen(stage: _campaign.stage('1-4')), ads: ads, prefs: {
        'settings.v1': jsonEncode(const Settings(language: 'en', debugMode: true).toJson()),
      });
      await _frames(tester, 1.2);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await _frames(tester, 0.3);
      final ctl = GameScreen.debugLastController!;
      ctl.world.ball
        ..y = Field.height - 4
        ..vy = 600;
      for (var i = 0; i < 300 && !ctl.finished; i++) {
        await tester.pump(const Duration(microseconds: 16667));
      }
      expect(ctl.finished, isTrue);
      await _frames(tester, 0.2);
      // 演出中: ボタンはまだ押せない。Enter で演出が終わり、押せるようになる (ボタンは押さない)
      bool ignoring() => tester
          .widgetList<IgnorePointer>(find.ancestor(of: find.text('RETRY'), matching: find.byType(IgnorePointer)))
          .any((w) => w.ignoring);
      expect(ignoring(), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(ignoring(), isFalse);
      expect(ctl.finished, isTrue);

      // RETRY / STAGES / TITLE (失敗なので NEXT STAGE はない)
      expect(selected(tester, 'RETRY'), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(selected(tester, 'STAGES'), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(selected(tester, 'TITLE'), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(selected(tester, 'RETRY'), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(selected(tester, 'TITLE'), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();

      // RETRY を Enter で決めると、もう一度遊べ、盤面のキー (Space で発射) が効く
      expect(selected(tester, 'RETRY'), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await _frames(tester, 1.2);
      expect(ctl.finished, isFalse);
      expect(find.text('RETRY'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await _frames(tester, 0.3);
      expect(ctl.world.ball.attached, isFalse);
      expect(ads.shown, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('結果画面: TITLE を Enter で決めると、広告の判定を通ってタイトルへ戻る', (tester) async {
      final ads = _FakeAds();
      await _pumpApp(tester, ads: ads);
      await tester.tap(find.text('ENDLESS'));
      await _frames(tester, 1.2);
      await _gameOver(tester);
      await _frames(tester, 3); // 演出が終わるまで
      expect(selected(tester, 'RETRY'), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await _frames(tester, 1);
      expect(ads.shown, 1);
      expect(find.byType(GameScreen), findsNothing);
      expect(find.text('ENDLESS'), findsOneWidget);
    });

    testWidgets('ステージ選択: 矢印キーでステージを選び、Enter で START、Esc で戻る', (tester) async {
      await _pumpApp(tester, prefs: {
        'records': jsonEncode(const Records(stages: {
          '1-1': StageRecord(cleared: true),
          '1-2': StageRecord(cleared: true),
        }).toJson()),
      });
      await tester.tap(find.text('STAGES'));
      await _frames(tester, 0.5);
      expect(find.text('STAGE 1-3'), findsOneWidget); // 開いていて未クリアの最初のステージ

      Future<void> key(LogicalKeyboardKey k) async {
        await tester.sendKeyEvent(k);
        await tester.pump();
      }

      await key(LogicalKeyboardKey.arrowLeft);
      expect(find.text('STAGE 1-2'), findsOneWidget);
      await key(LogicalKeyboardKey.arrowRight);
      await key(LogicalKeyboardKey.arrowRight);
      expect(find.text('STAGE 1-4'), findsOneWidget);
      // 下の段はジグザグ (右から左へ) なので、1-4 の真下は 1-7
      await key(LogicalKeyboardKey.arrowDown);
      expect(find.text('STAGE 1-7'), findsOneWidget);
      // 開いていないステージは Enter で始まらない
      await key(LogicalKeyboardKey.enter);
      await _frames(tester, 0.5);
      expect(find.byType(GameScreen), findsNothing);
      await key(LogicalKeyboardKey.arrowUp);
      expect(find.text('STAGE 1-4'), findsOneWidget);
      // 段の右端から先は次の章へ
      await key(LogicalKeyboardKey.arrowRight);
      expect(find.text('STAGE 1-5'), findsOneWidget);
      await key(LogicalKeyboardKey.arrowRight);
      expect(find.text('STAGE 2-1'), findsOneWidget);
      await key(LogicalKeyboardKey.arrowLeft);
      expect(find.text('STAGE 1-5'), findsOneWidget);

      // 開いているステージは Enter で始まる
      for (var i = 0; i < 2; i++) {
        await key(LogicalKeyboardKey.arrowLeft);
      }
      expect(find.text('STAGE 1-3'), findsOneWidget);
      await key(LogicalKeyboardKey.enter);
      await _frames(tester, 0.8);
      final game = find.byType(GameScreen);
      expect(game, findsOneWidget);
      expect(tester.widget<GameScreen>(game).stage?.id, '1-3');

      // ゲームから戻ると、またキーで選べる。Esc でタイトルへ戻る
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await _frames(tester, 0.8);
      await key(LogicalKeyboardKey.arrowRight);
      expect(find.text('STAGE 1-4'), findsOneWidget);
      await key(LogicalKeyboardKey.escape);
      await _frames(tester, 0.5);
      expect(find.byType(StageSelectScreen), findsNothing);
      expect(find.text('STAGES'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('設定: 矢印キーで分類・項目・値を選び、Esc で戻る', (tester) async {
      await _pumpApp(tester);
      await tester.tap(find.text('SETTINGS'));
      await _frames(tester, 0.5);
      expect(find.byType(SettingsScreen), findsOneWidget);
      final container = ProviderScope.containerOf(tester.element(find.byType(SettingsScreen)));
      Settings s() => container.read(settingsProvider);

      Future<void> key(LogicalKeyboardKey k) async {
        await tester.sendKeyEvent(k);
        await tester.pump();
      }

      // 左の見出し: ↓ で SOUND
      await key(LogicalKeyboardKey.arrowDown);
      expect(find.text('Music volume'), findsOneWidget);
      // → で項目へ入り、→ で BGM の音量を 1 段 (5%) 上げる
      final bgm = s().bgmVolume;
      await key(LogicalKeyboardKey.arrowRight);
      await key(LogicalKeyboardKey.arrowRight);
      expect(s().bgmVolume, closeTo(bgm + 0.05, 1e-9));
      // ↓ で効果音、← で 1 段下げる
      final sfx = s().sfxVolume;
      await key(LogicalKeyboardKey.arrowDown);
      await key(LogicalKeyboardKey.arrowLeft);
      expect(s().sfxVolume, closeTo(sfx - 0.05, 1e-9));
      expect(s().bgmVolume, closeTo(bgm + 0.05, 1e-9));

      // Esc で見出しへ戻り、↓ で DISPLAY。Enter で項目へ入り、↓↓ で言語、← で日本語
      await key(LogicalKeyboardKey.escape);
      expect(find.byType(SettingsScreen), findsOneWidget);
      await key(LogicalKeyboardKey.arrowDown);
      await key(LogicalKeyboardKey.enter);
      // 画質: → で LOW、Enter で次 (最後なら最初) の HIGH へ
      await key(LogicalKeyboardKey.arrowRight);
      expect(s().quality, GraphicsQuality.low);
      await key(LogicalKeyboardKey.enter);
      expect(s().quality, GraphicsQuality.high);
      // 動きを減らす: → で ON、← で OFF
      await key(LogicalKeyboardKey.arrowDown);
      await key(LogicalKeyboardKey.arrowRight);
      expect(s().reduceEffects, isTrue);
      await key(LogicalKeyboardKey.arrowLeft);
      expect(s().reduceEffects, isFalse);
      await key(LogicalKeyboardKey.arrowDown);
      await key(LogicalKeyboardKey.arrowLeft);
      expect(s().language, 'ja');
      await key(LogicalKeyboardKey.arrowRight);
      expect(s().language, 'en');

      // 操作の分類: 「測定する」は Enter で開き、Esc で閉じる
      await key(LogicalKeyboardKey.escape);
      await key(LogicalKeyboardKey.arrowUp);
      await key(LogicalKeyboardKey.arrowUp);
      await key(LogicalKeyboardKey.arrowRight);
      for (var i = 0; i < 3; i++) {
        await key(LogicalKeyboardKey.arrowDown);
      }
      await key(LogicalKeyboardKey.enter);
      await _frames(tester, 0.5);
      expect(find.byType(CalibrationScreen), findsOneWidget);
      await key(LogicalKeyboardKey.escape);
      await _frames(tester, 0.5);
      expect(find.byType(CalibrationScreen), findsNothing);
      // 補正の目盛りも ←→ で動く (戻ったあともキーが効く)
      final timing = s().timingOffsetMs;
      await key(LogicalKeyboardKey.arrowRight);
      expect(s().timingOffsetMs, timing + 1);

      // Esc で見出しへ、もう一度 Esc で設定を閉じる
      await key(LogicalKeyboardKey.escape);
      await key(LogicalKeyboardKey.escape);
      await _frames(tester, 0.5);
      expect(find.byType(SettingsScreen), findsNothing);
      expect(find.text('SETTINGS'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // Issue #151: 使えない感度の項目は灰色になるだけで、理由が書かれていなかった
  testWidgets('設定: 使えない感度の項目に理由が出て、操作方法を切り替えると入れ替わる', (tester) async {
    await _pumpApp(tester, size: const Size(667, 375));
    await tester.tap(find.text('SETTINGS'));
    await _frames(tester, 0.5);
    // 領域方式 (既定): レール感度の下に理由が出る
    expect(find.text('Used when Controls is "Rail"'), findsOneWidget);
    expect(find.text('Used when Controls is "Screen halves"'), findsNothing);
    await tester.tap(find.text('Rail (horizontal)'));
    await _frames(tester, 0.3);
    expect(find.text('Used when Controls is "Screen halves"'), findsOneWidget);
    expect(find.text('Used when Controls is "Rail"'), findsNothing);
    await tester.tap(find.text('Screen halves'));
    await _frames(tester, 0.3);
    expect(find.text('Used when Controls is "Rail"'), findsOneWidget);
    expect(find.text('Used when Controls is "Screen halves"'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('設定: 使えない理由は日本語でも出る', (tester) async {
    await _pumpApp(tester, home: const SettingsScreen(), prefs: {
      'settings.v1': jsonEncode(const Settings(language: 'ja', controls: ControlScheme.railVertical).toJson()),
    });
    await _frames(tester, 0.5);
    expect(find.text('操作方法が「画面の左右」のときに使います'), findsOneWidget);
    expect(find.text('操作方法が「レール」のときに使います'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // Issue #13: スコア履歴
  testWidgets('HISTORY: タイトルから開き、遊んでいなければ記録がないと出て、戻るとタイトル', (tester) async {
    await _pumpApp(tester);
    await _frames(tester, 2.4);
    await tester.tap(find.text('HISTORY'));
    await _frames(tester, 0.5);
    expect(find.byType(HistoryScreen), findsOneWidget);
    expect(find.text('No plays yet. Your results appear here after each game'), findsOneWidget);
    expect(find.byType(HistoryRow), findsNothing);
    await tester.tap(find.byWidgetPredicate((w) => w is PixelIcon && w.glyph == PixelIcons.back));
    await _frames(tester, 0.5);
    expect(find.byType(HistoryScreen), findsNothing);
    expect(find.text('HISTORY'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('HISTORY: エンドレスのゲームオーバーが一番上に、日時・ENDLESS・スコア・到達ラウンドで出る', (tester) async {
    await _pumpApp(tester, ads: _FakeAds(), prefs: {
      PlayHistoryNotifier.key: jsonEncode(PlayHistory([
        PlayEntry(at: DateTime(2026, 1, 2, 3, 4), stageId: '1-1', score: 777, cleared: true),
      ]).toJson()),
    });
    await _frames(tester, 2.4);
    await tester.tap(find.text('ENDLESS'));
    await _frames(tester, 1.2);
    GameScreen.debugLastController!.world.addScore(4321);
    await _gameOver(tester);
    final round = GameScreen.debugLastController!.world.round.number;
    await tester.tap(find.text('TITLE'));
    await _frames(tester, 0.8);
    await tester.tap(find.text('HISTORY'));
    await _frames(tester, 0.5);
    final rows = tester.widgetList<HistoryRow>(find.byType(HistoryRow)).toList();
    expect(rows, hasLength(2));
    final top = rows.first.entry;
    expect(top.endless, isTrue);
    expect(top.score, 4321);
    expect(top.round, round);
    final row = find.byType(HistoryRow).first;
    expect(find.descendant(of: row, matching: find.text('ENDLESS')), findsOneWidget);
    expect(find.descendant(of: row, matching: find.text(formatScore(4321))), findsOneWidget);
    expect(find.descendant(of: row, matching: find.text('ROUND ${round.toString().padLeft(2, '0')}')), findsOneWidget);
    expect(find.descendant(of: row, matching: find.text(formatPlayedAt(top.at))), findsOneWidget);
    expect(find.text('2026/01/02 03:04'), findsOneWidget); // 前の記録は 2 行目に残る
    await _shot(tester, '12_history');
    expect(tester.takeException(), isNull);
  });

  testWidgets('HISTORY: ステージの結果 (クリアも失敗も) が、番号・難易度・スコア・クリアしたかで一番上に出る', (tester) async {
    await _pumpApp(tester, home: GameScreen(stage: _campaign.stage('1-4'), difficulty: Difficulty.hard));
    await _frames(tester, 1.2);
    var w = GameScreen.debugLastController!.world;
    for (final b in w.blocks.where((b) => b.behavior.clearable).toList()) {
      w.destroyBlock(b, DestroyCause.pierce);
    }
    await _frames(tester, 6.5);
    expect(find.text('NEXT STAGE'), findsOneWidget);
    var top = _latestPlay(tester);
    expect(top.stageId, '1-4');
    expect(top.difficulty, Difficulty.hard);
    expect(top.cleared, isTrue);
    expect(top.score, w.score);

    await tester.tap(find.text('RETRY'));
    await _frames(tester, 1.2);
    w = GameScreen.debugLastController!.world;
    for (var i = 0; i < 10 && find.text('STAGE FAILED').evaluate().isEmpty; i++) {
      await _gameOver(tester);
    }
    expect(find.text('STAGE FAILED'), findsWidgets);
    top = _latestPlay(tester);
    expect(top.stageId, '1-4');
    expect(top.cleared, isFalse);
    expect(top.score, w.score);
    expect(ProviderScope.containerOf(tester.element(find.byType(MaterialApp))).read(historyProvider).entries,
        hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('HISTORY: ステージの行に番号・難易度・クリアしたかが出る', (tester) async {
    await _pumpApp(tester, home: const HistoryScreen(), prefs: {
      PlayHistoryNotifier.key: jsonEncode(PlayHistory([
        PlayEntry(at: DateTime(2026, 11, 8, 9, 30), stageId: '1-4', difficulty: Difficulty.hard, score: 1500),
        PlayEntry(at: DateTime(2026, 11, 8, 9, 0), stageId: '1-3', score: 9000, cleared: true),
      ]).toJson()),
    });
    await _frames(tester, 0.5);
    final rows = find.byType(HistoryRow);
    Finder inRow(int i, String text) => find.descendant(of: rows.at(i), matching: find.text(text));
    expect(inRow(0, '2026/11/08 09:30'), findsOneWidget);
    expect(inRow(0, 'STAGE 1-4  HARD'), findsOneWidget);
    expect(inRow(0, 'FAILED'), findsOneWidget);
    expect(inRow(0, formatScore(1500)), findsOneWidget);
    expect(inRow(1, 'STAGE 1-3  NORMAL'), findsOneWidget);
    expect(inRow(1, 'CLEAR'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('HISTORY: 日本語の文言が出る', (tester) async {
    await _pumpApp(tester, home: const HistoryScreen(), prefs: {
      'settings.v1': jsonEncode(const Settings(language: 'ja').toJson()),
    });
    await _frames(tester, 0.5);
    expect(find.text('プレイ記録'), findsOneWidget);
    expect(find.text('まだ記録がありません。結果画面まで遊ぶと、ここに残ります'), findsOneWidget);
  });

  for (final size in const [Size(667, 375), Size(852, 393)]) {
    testWidgets('タイトル: HISTORY を足しても ${size.width.toInt()}x${size.height.toInt()} でメニューがはみ出さない', (tester) async {
      await _pumpApp(tester, size: size, leaderboard: _AvailableLeaderboard(), prefs: {
        'records': jsonEncode(const Records(stages: {'1-1': StageRecord(cleared: true)}).toJson()),
      });
      await _frames(tester, 2.4);
      for (final label in ['CONTINUE', 'ENDLESS', 'STAGES', 'HISTORY', 'HOW TO PLAY', 'SETTINGS', 'RANKING']) {
        final r = tester.getRect(find.text(label));
        expect(r.top, greaterThanOrEqualTo(0), reason: label);
        expect(r.bottom, lessThanOrEqualTo(size.height), reason: label);
        final hit = find.ancestor(of: find.text(label), matching: find.byType(GestureDetector)).first;
        expect(tester.getSize(hit).height, greaterThanOrEqualTo(44), reason: '$label を押せる範囲 (#122)');
      }
      expect(tester.takeException(), isNull);
    });
  }

  group('端末の動きを減らす設定 (#105)', () {
    // 端末の設定 (iOS の「視差効果を減らす」、Android の「アニメーションを削除」) は、
    // MaterialApp の MediaQuery に disableAnimations として届く
    void setDisableAnimations(WidgetTester tester, bool on) {
      tester.platformDispatcher.accessibilityFeaturesTestValue = FakeAccessibilityFeatures(disableAnimations: on);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    }

    testWidgets('アプリの「演出を控えめにする」が OFF でも、盤面のフラッシュ・揺れを控えめにする', (tester) async {
      setDisableAnimations(tester, true);
      await _pumpApp(tester, home: const GameScreen());
      await _frames(tester, 0.2);
      final fx = GameScreen.debugLastController!.fx;
      expect(fx.reduceEffects, isTrue);
      fx.handle(const FeverTimeStarted()); // 画面全体のフラッシュ (0.5) と同じ
      expect(fx.flash, lessThanOrEqualTo(0.08));
    });

    testWidgets('遊んでいる途中で端末の設定を変えても反映される', (tester) async {
      await _pumpApp(tester, home: const GameScreen());
      await _frames(tester, 0.2);
      final fx = GameScreen.debugLastController!.fx;
      expect(fx.reduceEffects, isFalse);

      setDisableAnimations(tester, true);
      await _frames(tester, 0.1);
      expect(fx.reduceEffects, isTrue);

      setDisableAnimations(tester, false);
      await _frames(tester, 0.1);
      expect(fx.reduceEffects, isFalse);
    });

    testWidgets('端末の設定が OFF でも、アプリの設定が ON なら控えめのまま', (tester) async {
      setDisableAnimations(tester, false);
      await _pumpApp(tester, home: const GameScreen(), prefs: {
        'settings.v1': jsonEncode(const Settings(language: 'en', reduceEffects: true).toJson()),
      });
      await _frames(tester, 0.2);
      expect(GameScreen.debugLastController!.fx.reduceEffects, isTrue);
    });
  });
}
