import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Android 16 (API 36) を対象にすると、最小幅 600dp 以上の画面 (タブレット・折りたたみ) では
/// 画面の向きの固定 (screenOrientation・resizeableActivity) が無視される。ゲームとして
/// 申告したアプリは対象外になるので、横向きの固定を保つために appCategory="game" が要る (Issue #157)。
void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

  test('AndroidManifest の <application> に android:appCategory="game" がある', () {
    final application = RegExp(r'<application\b[^>]*>').firstMatch(manifest)?.group(0);
    expect(application, isNotNull);
    expect(application, contains('android:appCategory="game"'));
  });

  test('MainActivity は横向きに固定している', () {
    expect(manifest, contains('android:screenOrientation="sensorLandscape"'));
  });
}
