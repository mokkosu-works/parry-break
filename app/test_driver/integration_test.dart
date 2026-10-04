// integration_test/store_screenshots_test.dart の撮った画面を、PNG として書き出す。
// 書き出し先は環境変数 SHOT_DIR (省略時は build/store_screenshots)。
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() => integrationDriver(
      onScreenshot: (name, bytes, [args]) async {
        final dir = Platform.environment['SHOT_DIR'] ?? 'build/store_screenshots';
        final file = File('$dir/$name.png');
        await file.create(recursive: true);
        await file.writeAsBytes(bytes);
        return true;
      },
    );
