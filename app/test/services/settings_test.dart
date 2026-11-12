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
      expect(
        Settings.fromJson(const {'railSensitivity': 0.1}).railSensitivity,
        0.5,
      );
      expect(
        Settings.fromJson(const {'railSensitivity': 9}).railSensitivity,
        2.0,
      );
    });

    test('JSON を往復しても同じ値になる', () {
      final s = const Settings().copyWith(railSensitivity: 1.5);
      expect(Settings.fromJson(s.toJson()).railSensitivity, 1.5);
    });
  });

  group('Settings.fromJson の型の違う項目 (Issue #145)', () {
    test('bool の項目の型が違うときは、その項目だけ初期値になる', () {
      final s = Settings.fromJson(const {
        'haptics': 'no',
        'reduceEffects': 1,
        'debugMode': 'true',
        'sensitivity': 3.0,
        'bgmVolume': 0.2,
        'controls': 'railVertical',
      });
      expect(s.haptics, isTrue);
      expect(s.reduceEffects, isFalse);
      expect(s.debugMode, isFalse);
      expect(s.sensitivity, 3.0);
      expect(s.bgmVolume, 0.2);
      expect(s.controls, ControlScheme.railVertical);
    });

    test('bool の項目が正しい型なら、その値を読む', () {
      final s = Settings.fromJson(const {
        'haptics': false,
        'reduceEffects': true,
        'debugMode': true,
      });
      expect(s.haptics, isFalse);
      expect(s.reduceEffects, isTrue);
      expect(s.debugMode, isTrue);
    });
  });
}
