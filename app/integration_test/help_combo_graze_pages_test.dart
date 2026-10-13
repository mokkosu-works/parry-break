// Issue #74: 遊び方に COMBO / FEVER TIME と GRAZE / RICOCHET のページがあり、説明が画面に収まることを確かめる。
//   SHOT_DIR=build/claude flutter drive -d <デバイス ID> \
//     --driver=test_driver/integration_test.dart --target=integration_test/help_combo_graze_pages_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:parry_break/main.dart';
import 'package:parry_break/services/content.dart';
import 'package:parry_break/services/leaderboard.dart';
import 'package:parry_break/services/settings.dart';
import 'package:parry_break/ui/help_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  var surfaceConverted = false;
  Future<void> shot(WidgetTester t, String name) async {
    if (Platform.isAndroid && !surfaceConverted) {
      await binding.convertFlutterSurfaceToImage();
      surfaceConverted = true;
      await t.pump();
    }
    await binding.takeScreenshot(name);
  }

  testWidgets('遊び方に COMBO / FEVER TIME と GRAZE / RICOCHET のページがある', (t) async {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    SharedPreferences.setMockInitialValues({'settings.v1': jsonEncode(const Settings(language: 'en').toJson())});
    final prefs = await SharedPreferences.getInstance();
    final content = await GameContent.load(rootBundle);
    await t.pumpWidget(ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        contentProvider.overrideWithValue(content),
        leaderboardProvider.overrideWithValue(DisabledLeaderboard()),
      ],
      child: const ParryBreakApp(),
    ));
    await t.pump(const Duration(seconds: 3));
    await t.tap(find.text('HOW TO PLAY'));
    await t.pump(const Duration(milliseconds: 600));
    expect(find.byType(HelpScreen), findsOneWidget);

    var n = 0;
    for (final title in ['MOVE', 'LAUNCH / PARRY', 'TIMING', 'CHAIN', 'COMBO / FEVER TIME', 'GRAZE / RICOCHET']) {
      expect(find.text(title), findsOneWidget, reason: title);
      if (title.startsWith('COMBO') || title.startsWith('GRAZE')) {
        // 動く図の見どころを 2 コマ撮る (3.2 秒で 1 周)
        for (final ms in [1500, 1300]) {
          await t.pump(Duration(milliseconds: ms));
          await shot(t, 'issue74_0${++n}_${title.substring(0, 4).toLowerCase()}');
        }
      }
      await t.tap(find.text('NEXT'));
      await t.pump(const Duration(milliseconds: 600));
    }
  });
}
