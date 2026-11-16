import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parry_break/core/core.dart';
import 'package:parry_break/services/progress.dart';
import 'package:parry_break/services/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// プレイヤーレベル (design.md 9.9): XP の計算・レベルの曲線・保存・レベルアップの検出。
void main() {
  const rules = XpRules.standard;
  const curve = LevelCurve.standard;

  RunStats stats({int parries = 0, int just = 0, int fevers = 0}) => RunStats()
    ..parries = parries
    ..just = just
    ..perfects = just
    ..fevers = fevers;

  group('XP の計算', () {
    test('何もしなくても基本の 50 は入る (負けた回も入る)', () {
      expect(rules.xpFor(kind: PlayKind.endless, stats: stats()), 50);
      expect(
        rules.xpFor(kind: PlayKind.stage, stats: stats(), cleared: false),
        50,
      );
    });

    test('パリィは 1 回 +2、JUST は +4', () {
      expect(
        rules.xpFor(kind: PlayKind.stage, stats: stats(parries: 10)),
        50 + 20,
      );
      // 10 回のうち 3 回が JUST: 7×2 + 3×4
      expect(
        rules.xpFor(kind: PlayKind.stage, stats: stats(parries: 10, just: 3)),
        50 + 14 + 12,
      );
    });

    test('エンドレスと DAILY は到達ラウンド × 15', () {
      for (final k in [PlayKind.endless, PlayKind.daily]) {
        expect(rules.xpFor(kind: k, stats: stats(), round: 1), 50 + 15);
        expect(rules.xpFor(kind: k, stats: stats(), round: 10), 50 + 150);
      }
      // ステージにはラウンドの項はない
      expect(rules.xpFor(kind: PlayKind.stage, stats: stats(), round: 10), 50);
    });

    test('ステージはクリアで +100、今回達成した星 1 つにつき +30', () {
      expect(
        rules.xpFor(
          kind: PlayKind.stage,
          stats: stats(),
          cleared: true,
          stars: 3,
        ),
        50 + 100 + 90,
      );
      // 失敗しても星は星 (達成していれば数える。クリアの加算だけがない)
      expect(
        rules.xpFor(kind: PlayKind.stage, stats: stats(), stars: 1),
        50 + 30,
      );
      // エンドレスは星を数えない
      expect(rules.xpFor(kind: PlayKind.endless, stats: stats(), stars: 3), 50);
    });

    test('FEVER TIME に入った回数 × 20', () {
      expect(
        rules.xpFor(kind: PlayKind.stage, stats: stats(fevers: 3)),
        50 + 60,
      );
    });

    test('スコアでは変わらない (遊んだ中身だけで決まる)', () {
      final a = stats(parries: 5), b = stats(parries: 5);
      expect(
        rules.xpFor(kind: PlayKind.endless, stats: a, round: 4),
        rules.xpFor(kind: PlayKind.endless, stats: b, round: 4),
      );
    });

    test('1 回の上限は 1,500 (長いプレイでも超えない)', () {
      final long = stats(parries: 3000, just: 1000, fevers: 100);
      expect(rules.xpFor(kind: PlayKind.endless, stats: long, round: 80), 1500);
      // 上限のすぐ下は、そのまま入る: 50 + 15×96 = 1490
      expect(
        rules.xpFor(kind: PlayKind.endless, stats: stats(), round: 96),
        1490,
      );
      expect(
        rules.xpFor(kind: PlayKind.endless, stats: stats(), round: 97),
        1500,
      );
    });

    test('EASY は ×0.8 (四捨五入)。上限は倍率のあとの値に効く', () {
      // (50 + 15×4) = 110 → 88
      expect(
        rules.xpFor(
          kind: PlayKind.endless,
          stats: stats(),
          round: 4,
          difficulty: Difficulty.easy,
        ),
        88,
      );
      // 基本だけ: 50 → 40
      expect(
        rules.xpFor(
          kind: PlayKind.endless,
          stats: stats(),
          difficulty: Difficulty.easy,
        ),
        40,
      );
      // NORMAL と HARD は等倍
      for (final d in [Difficulty.normal, Difficulty.hard]) {
        expect(
          rules.xpFor(
            kind: PlayKind.endless,
            stats: stats(),
            round: 4,
            difficulty: d,
          ),
          110,
        );
      }
      final long = stats(parries: 3000);
      expect(
        rules.xpFor(
          kind: PlayKind.endless,
          stats: long,
          round: 80,
          difficulty: Difficulty.easy,
        ),
        1500,
      );
    });

    test('数値は XpRules にまとめてあり、差し替えられる', () {
      const custom = XpRules(base: 10, perRound: 1, cap: 12);
      expect(
        custom.xpFor(kind: PlayKind.endless, stats: stats(), round: 1),
        11,
      );
      expect(
        custom.xpFor(kind: PlayKind.endless, stats: stats(), round: 9),
        12,
      );
    });

    test('異常な値 (負のラウンド・星) でも 0 未満にならない', () {
      expect(
        rules.xpFor(
          kind: PlayKind.endless,
          stats: stats(),
          round: -5,
          stars: -2,
        ),
        50,
      );
    });
  });

  group('レベルの曲線', () {
    test('次のレベルに要る XP は 100 + (lv-1)×40 で、少しずつ増える', () {
      expect(curve.xpToNext(1), 100);
      expect(curve.xpToNext(2), 140);
      expect(curve.xpToNext(10), 460);
      expect(curve.xpToNext(98), 100 + 97 * 40);
      expect(curve.xpToNext(99), 0, reason: '上限のレベルには次がない');
    });

    test('累計 XP → レベルと進み', () {
      expect(curve.of(0).level, 1);
      expect(curve.of(0).into, 0);
      expect(curve.of(0).fraction, 0);
      expect(curve.of(99).level, 1);
      expect(curve.of(99).remaining, 1);
      expect(curve.of(100).level, 2);
      expect(curve.of(100).into, 0);
      final p = curve.of(100 + 70);
      expect((p.level, p.into, p.need), (2, 70, 140));
      expect(p.fraction, closeTo(0.5, 1e-9));
      expect(p.remaining, 70);
      expect(curve.of(239).level, 2);
      expect(curve.of(240).level, 3);
    });

    test('レベルに届く累計 XP は、1 つずつ足した値と同じ', () {
      var sum = 0;
      for (var lv = 1; lv < curve.maxLevel; lv++) {
        expect(curve.xpAt(lv), sum, reason: 'Lv$lv');
        expect(curve.of(sum).level, lv);
        expect(curve.of(sum - 1 < 0 ? 0 : sum - 1).level, lv == 1 ? 1 : lv - 1);
        sum += curve.xpToNext(lv);
      }
      expect(curve.xpAt(curve.maxLevel), sum);
      expect(curve.maxXp, 199920);
    });

    test('Lv99 が上限: 超えても上がらず、進みは満タン', () {
      final max = curve.of(curve.maxXp);
      expect(max.level, 99);
      expect(max.isMax, isTrue);
      expect(max.fraction, 1);
      expect(max.remaining, 0);
      expect(curve.of(curve.maxXp * 10).level, 99);
      expect(curve.of(-5).level, 1);
    });
  });

  group('保存', () {
    Future<(ProviderContainer, SharedPreferences)> load([
      Map<String, Object> prefs = const {},
    ]) async {
      SharedPreferences.setMockInitialValues(prefs);
      final sp = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [sharedPrefsProvider.overrideWithValue(sp)],
      );
      addTearDown(c.dispose);
      return (c, sp);
    }

    test('はじめは 0 XP・Lv1 で、何も書かない', () async {
      final (c, sp) = await load();
      expect(c.read(progressProvider).totalXp, 0);
      expect(c.read(progressProvider).level, 1);
      expect(sp.containsKey(ProgressNotifier.key), isFalse);
    });

    test('累計 XP を progress.v1 に保存し、次の起動で読み直せる', () async {
      final (c, sp) = await load();
      c.read(progressProvider.notifier).award(130);
      c.read(progressProvider.notifier).award(70);
      expect(ProgressNotifier.key, 'progress.v1');
      expect(jsonDecode(sp.getString('progress.v1')!), {
        'version': 1,
        'xp': 200,
      });
      final (c2, _) = await load({'progress.v1': sp.getString('progress.v1')!});
      expect(c2.read(progressProvider).totalXp, 200);
      expect(c2.read(progressProvider).level, 2);
    });

    test('ほかのキーには触らない', () async {
      final (c, sp) = await load({
        'records': '{"version":1}',
        'daily.v1': '{"version":1}',
        'settings.v1': '{}',
        'history.v1': '{}',
      });
      c.read(progressProvider.notifier).award(500);
      expect(sp.getString('records'), '{"version":1}');
      expect(sp.getString('daily.v1'), '{"version":1}');
      expect(sp.getString('settings.v1'), '{}');
      expect(sp.getString('history.v1'), '{}');
      expect(sp.getKeys(), isNot(contains(ProgressNotifier.brokenKey)));
    });

    for (final (name, raw) in [
      ('JSON として読めない', 'not json'),
      ('配列', '[1,2]'),
      ('xp が文字列', '{"version":1,"xp":"many"}'),
      ('xp が負', '{"version":1,"xp":-50}'),
      ('xp が真偽値', '{"xp":true}'),
      ('今より新しい版', '{"version":2,"xp":900}'),
    ]) {
      test('壊れたデータ ($name) は 0 として読み、元の文字列を退避する', () async {
        final (c, sp) = await load({'progress.v1': raw});
        final p = c.read(progressProvider);
        // 新しい版は知っている項目 (xp) を読むが、上書きで失わないよう退避する
        expect(p.totalXp, raw.contains('"version":2') ? 900 : 0, reason: name);
        expect(sp.getString(ProgressNotifier.brokenKey), raw);
      });
    }

    test('上限を超えた xp は上限として読む', () async {
      final (c, _) = await load({'progress.v1': '{"version":1,"xp":99999999}'});
      expect(c.read(progressProvider).totalXp, curve.maxXp);
      expect(c.read(progressProvider).level, 99);
    });

    test('version がなくても xp があれば読める。小数は切り捨てる', () async {
      final (c, sp) = await load({'progress.v1': '{"xp":150.9}'});
      expect(c.read(progressProvider).totalXp, 150);
      expect(sp.containsKey(ProgressNotifier.brokenKey), isFalse);
    });
  });

  group('レベルアップの検出', () {
    Future<ProgressNotifier> notifier([int xp = 0]) async {
      SharedPreferences.setMockInitialValues({
        if (xp > 0) 'progress.v1': jsonEncode({'version': 1, 'xp': xp}),
      });
      final sp = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [sharedPrefsProvider.overrideWithValue(sp)],
      );
      addTearDown(c.dispose);
      return c.read(progressProvider.notifier);
    }

    test('上がらないときは前後のレベルが同じ', () async {
      final n = await notifier();
      final g = n.award(60);
      expect(g.xp, 60);
      expect((g.fromLevel, g.toLevel), (1, 1));
      expect(g.leveledUp, isFalse);
      expect(g.reached, isEmpty);
      expect(g.before.fraction, 0);
      expect(g.after.fraction, closeTo(0.6, 1e-9));
    });

    test('Lv1 → Lv2: 前のレベルと新しいレベルを 1 か所で返す', () async {
      final n = await notifier(90);
      final g = n.award(20);
      expect((g.fromLevel, g.toLevel), (1, 2));
      expect(g.leveledUp, isTrue);
      expect(g.reached, [2]);
      expect(g.after.into, 10);
    });

    test('一度に何段か上がったときは、届いたレベルを全部返す', () async {
      final n = await notifier();
      final g = n.award(700); // Lv5 は 640、Lv6 は 900
      expect((g.fromLevel, g.toLevel), (1, 5));
      expect(g.reached, [2, 3, 4, 5]);
    });

    test('ちょうど境目 (Lv2 の 100) で上がる', () async {
      final n = await notifier(99);
      expect(n.award(1).toLevel, 2);
    });

    test('Lv99 では上がらず、XP の保存も増えない', () async {
      final n = await notifier(curve.maxXp);
      final g = n.award(1000);
      expect(g.leveledUp, isFalse);
      expect(g.toLevel, 99);
      expect(g.after.isMax, isTrue);
    });

    test('負の XP は足さない', () async {
      final n = await notifier(50);
      final g = n.award(-30);
      expect(g.xp, 0);
      expect(n.state.totalXp, 50);
    });
  });

  group('典型的なプレイの XP', () {
    // レベルの曲線の妥当さの根拠 (design.md 9.9 の表)。
    test('初心者のエンドレス R3〜5 は 100 前後、慣れた人の R15 は 400 前後', () {
      int endless(int round, int parries, int just, int fevers) => rules.xpFor(
        kind: PlayKind.endless,
        stats: stats(parries: parries, just: just, fevers: fevers),
        round: round,
      );
      final novice = endless(4, 12, 1, 0);
      expect(novice, inInclusiveRange(100, 160));
      final mid = endless(15, 90, 15, 1);
      expect(mid, inInclusiveRange(400, 600));
      final expert = endless(35, 220, 80, 6);
      expect(expert, inInclusiveRange(900, 1500));
    });
  });
}
