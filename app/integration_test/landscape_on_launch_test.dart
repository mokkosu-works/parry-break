// Issue #41: Android で起動した瞬間から横向きで描かれることを確かめる。
// main() の SystemChrome.setPreferredOrientations は呼ばず、AndroidManifest.xml の screenOrientation だけに頼る。
// 端末を縦向きに固定してから動かす:
//   adb shell settings put system accelerometer_rotation 0
//   adb shell settings put system user_rotation 0
//   SHOT_DIR=build/claude flutter drive -d <デバイス ID> \
//     --driver=test_driver/integration_test.dart --target=integration_test/landscape_on_launch_test.dart
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:parry_break/main.dart';
import 'package:parry_break/services/content.dart';
import 'package:parry_break/services/leaderboard.dart';
import 'package:parry_break/services/settings.dart';
import 'package:parry_break/ui/title/title_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('向きを指定しなくても、起動した最初から横向きで描かれる', (t) async {
    SharedPreferences.setMockInitialValues({});
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

    final size = t.view.physicalSize;
    expect(size.width, greaterThan(size.height), reason: '縦向きの端末でも横長に描かれる');
    expect(find.byType(TitleScreen), findsOneWidget);

    await binding.convertFlutterSurfaceToImage();
    await t.pump();
    await binding.takeScreenshot('issue41_01_title_landscape');
  });
}
