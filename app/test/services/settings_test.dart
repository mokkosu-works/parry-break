import 'package:flutter_test/flutter_test.dart';
import 'package:parry_break/services/settings.dart';

void main() {
  group('Settings.fromJson のレール感度', () {
    test('railSensitivity がない古い保存データは 1.0 になる', () {
      final s = Settings.fromJson(const {'sensitivity': 2.5});
      expect(s.railSensitivity, 1.0);
      expect(s.sensitivity, 2.5);
    });

    test('範囲外の値は 0.5〜2.0 に収まる', () {
      expect(Settings.fromJson(const {'railSensitivity': 0.1}).railSensitivity, 0.5);
      expect(Settings.fromJson(const {'railSensitivity': 9}).railSensitivity, 2.0);
    });

    test('JSON を往復しても同じ値になる', () {
      final s = const Settings().copyWith(railSensitivity: 1.5);
      expect(Settings.fromJson(s.toJson()).railSensitivity, 1.5);
    });
  });
}
