import 'package:flutter_test/flutter_test.dart';
import 'package:parry_break/core/core.dart';
import 'package:parry_break/render/cosmetics.dart';
import 'package:parry_break/services/settings.dart';

void main() {
  group('エンドレスの難易度 (endlessDifficulty)', () {
    test('初期値は NORMAL。項目のない古い保存データも NORMAL として読む', () {
      expect(const Settings().endlessDifficulty, Difficulty.normal);
      final old = Settings.fromJson(const {'difficulty': 'hard'});
      expect(old.endlessDifficulty, Difficulty.normal);
      expect(old.difficulty, Difficulty.hard);
    });

    test('EASY を選ぶと保存され、ステージの難易度とは別に読み戻される', () {
      final s = const Settings().copyWith(
        endlessDifficulty: Difficulty.easy,
        difficulty: Difficulty.hard,
      );
      final j = s.toJson();
      expect(j['endlessDifficulty'], 'easy');
      expect(j['difficulty'], 'hard');
      final back = Settings.fromJson(j);
      expect(back.endlessDifficulty, Difficulty.easy);
      expect(back.difficulty, Difficulty.hard);
    });

    test('HARD や知らない値は NORMAL として読む (エンドレスに HARD は出さない)', () {
      expect(
        Settings.fromJson(const {'endlessDifficulty': 'hard'})
            .endlessDifficulty,
        Difficulty.normal,
      );
      expect(
        Settings.fromJson(const {'endlessDifficulty': 3}).endlessDifficulty,
        Difficulty.normal,
      );
    });
  });

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

    // Issue #265: 感度の項目は 1 つにまとめたが、保存は 2 つの値のまま
    test('sensitivity と railSensitivity は、どちらも別々の値のまま保存される', () {
      final s = const Settings().copyWith(sensitivity: 3, railSensitivity: 1.5);
      final j = s.toJson();
      expect(j['sensitivity'], 3);
      expect(j['railSensitivity'], 1.5);
      final back = Settings.fromJson(j);
      expect(back.sensitivity, 3);
      expect(back.railSensitivity, 1.5);
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

  group('タイミングの表示 (#253)', () {
    test('項目がない古い保存データはオンになる', () {
      expect(const Settings().showTiming, isTrue);
      expect(
        Settings.fromJson(const {'reduceEffects': true}).showTiming,
        isTrue,
      );
    });

    test('オフにして保存すると、読み直してもオフ', () {
      final s = const Settings().copyWith(showTiming: false);
      expect(s.toJson()['showTiming'], isFalse);
      expect(Settings.fromJson(s.toJson()).showTiming, isFalse);
    });
  });
  group('見た目の色 (paddleColor / trailColor)', () {
    test('初期値は今までの色。項目のない古い保存データも既定として読む', () {
      const d = Settings();
      expect((d.paddleColor, d.trailColor), ('sky', 'standard'));
      final old = Settings.fromJson(const {'reduceEffects': true});
      expect((old.paddleColor, old.trailColor), ('sky', 'standard'));
      expect(old.reduceEffects, isTrue);
    });

    test('選んだ色は保存され、読み戻される (キーは追加だけで、ほかの項目はそのまま)', () {
      final s = const Settings().copyWith(
        paddleColor: 'cyan',
        trailColor: 'lime',
        showTiming: false,
      );
      final j = s.toJson();
      expect(j['paddleColor'], 'cyan');
      expect(j['trailColor'], 'lime');
      expect(j['showTiming'], isFalse);
      final back = Settings.fromJson(j);
      expect((back.paddleColor, back.trailColor), ('cyan', 'lime'));
    });

    test('表にない値・型の違う値は既定の色として読む', () {
      for (final bad in <Object?>['nope', 3, true, null, '', 'CYAN']) {
        final s = Settings.fromJson({'paddleColor': bad, 'trailColor': bad});
        expect(
          (s.paddleColor, s.trailColor),
          ('sky', 'standard'),
          reason: '$bad',
        );
      }
      // 種類をまたいだ id は読まない (軌跡に標準はあるが、パドルにはない)
      expect(
        Settings.fromJson(const {'paddleColor': 'standard'}).paddleColor,
        'sky',
      );
    });

    test('まだ解放されていない色を指していても、使う色は既定 (レベルで毎回決める)', () {
      final s = Settings.fromJson(const {
        'paddleColor': 'lavender',
        'trailColor': 'leaf',
      });
      expect(s.paddleColor, 'lavender');
      expect(
        Cosmetics.resolve(CosmeticKind.paddle, s.paddleColor, 24).id,
        'sky',
      );
      expect(
        Cosmetics.resolve(CosmeticKind.paddle, s.paddleColor, 25).id,
        'lavender',
      );
      expect(
        Cosmetics.resolve(CosmeticKind.trail, s.trailColor, 10).id,
        'standard',
      );
    });
  });
}
