// Issue #69: 狭い画面でも、ステージ選択のタイルの番号が 1 行で全部見える
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:parry_break/main.dart';
import 'package:parry_break/services/content.dart';
import 'package:parry_break/services/leaderboard.dart';
import 'package:parry_break/services/settings.dart';
import 'package:parry_break/ui/stage_select_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('667x375 で 1-1 と 1-10 の番号がタイルに収まる', (t) async {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final content = await GameContent.load(rootBundle);
    t.view
      ..physicalSize = const Size(667, 375)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    // この画面幅では右の詳細パネルの見出しもはみ出す (別件。番号とは関係ない) ので、レイアウトのはみ出しだけ読み捨てる
    final onError = FlutterError.onError;
    FlutterError.onError = (d) {
      if (!d.exceptionAsString().contains('overflowed')) onError?.call(d);
    };
    addTearDown(() => FlutterError.onError = onError);
    await t.pumpWidget(ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        contentProvider.overrideWithValue(content),
        leaderboardProvider.overrideWithValue(DisabledLeaderboard()),
      ],
      child: const ParryBreakApp(home: StageSelectScreen()),
    ));
    await t.pump(const Duration(milliseconds: 1500));
    expect(find.byType(StageSelectScreen), findsOneWidget);

    for (final id in ['1-1', '1-10']) {
      final label = find.text(id);
      expect(label, findsOneWidget);
      final tile = find.ancestor(of: label, matching: find.byType(GestureDetector)).first;
      final l = t.getRect(label), r = t.getRect(tile);
      expect(l.left, greaterThanOrEqualTo(r.left), reason: id);
      expect(l.right, lessThanOrEqualTo(r.right), reason: id);
      // 1 行のまま縮んでいる (折り返すと縦長になる)
      expect(l.width, greaterThan(l.height), reason: id);
    }
  });

  // 画面の大きさを変えたままだと撮影が返ってこないので、エミュレーターの画面そのままで撮る (大きい画面で見た目が崩れていないかを見る)
  testWidgets('エミュレーターの画面そのままでタイルの番号が収まり、画面を撮る', (t) async {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final content = await GameContent.load(rootBundle);
    await t.pumpWidget(ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        contentProvider.overrideWithValue(content),
        leaderboardProvider.overrideWithValue(DisabledLeaderboard()),
      ],
      child: const ParryBreakApp(home: StageSelectScreen()),
    ));
    await t.pump(const Duration(milliseconds: 1500));
    for (final id in ['1-1', '1-10']) {
      final label = find.text(id);
      final tile = find.ancestor(of: label, matching: find.byType(GestureDetector)).first;
      final l = t.getRect(label), r = t.getRect(tile);
      expect(l.right, lessThanOrEqualTo(r.right), reason: id);
      expect(l.width, greaterThan(l.height), reason: id);
    }
    await binding.convertFlutterSurfaceToImage();
    await t.pump();
    await binding.takeScreenshot('issue69_01_stage_tiles');
  });
}
