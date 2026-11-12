import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parry_break/core/core.dart';
import 'package:parry_break/services/records.dart';
import 'package:parry_break/services/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/helpers.dart';

void main() {
  group('StageRecord', () {
    test('hasStar は記録より後ろの条件を未達成として扱う', () {
      const r = StageRecord(stars: [true, false]);
      expect(r.hasStar(0), isTrue);
      expect(r.hasStar(1), isFalse);
      expect(r.hasStar(2), isFalse);
      expect(r.starCount, 1);
    });

    test('JSON を往復しても同じ値になる', () {
      final r = StageRecord.fromJson(
        const StageRecord(
          cleared: true,
          bestScore: 1200,
          stars: [true, false],
        ).toJson(),
      );
      expect(r.cleared, isTrue);
      expect(r.bestScore, 1200);
      expect(r.stars, [true, false]);
    });
  });

  test('ステージの星は一度達成したら残る', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    final notifier = container.read(recordsProvider.notifier);

    StageResult result({required bool cleared, int score = 0}) =>
        StageResult(cleared: cleared, score: score, stats: RunStats());
    notifier.submitStage('1-1', result(cleared: true, score: 500), [
      true,
      false,
      true,
    ]);
    notifier.submitStage('1-1', result(cleared: false), [false, true, false]);

    final rec = container.read(recordsProvider).stage('1-1');
    expect(rec.stars, [true, true, true]);
    expect(rec.cleared, isTrue);
    expect(rec.bestScore, 500);
  });

  group('難易度', () {
    final campaign = Campaign.fromJson(
      jsonDecode(File('assets/stages/campaign.json').readAsStringSync())
          as Map<String, Object?>,
      endlessContent,
    );
    final s1 = campaign.stage('1-1')!, s2 = campaign.stage('1-2')!;

    Future<ProviderContainer> container([
      Map<String, Object> prefs = const {},
    ]) async {
      SharedPreferences.setMockInitialValues(prefs);
      final sp = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [sharedPrefsProvider.overrideWithValue(sp)],
      );
      addTearDown(c.dispose);
      return c;
    }

    StageResult clear(int score) =>
        StageResult(cleared: true, score: score, stats: RunStats());

    test('記録は難易度ごとに分けて残し、NORMAL は以前と同じキーを使う', () async {
      final c = await container();
      final n = c.read(recordsProvider.notifier);
      n.submitStage('1-1', clear(1000), [true, false, false]);
      n.submitStage('1-1', clear(5000), [
        true,
        true,
        false,
      ], difficulty: Difficulty.hard);
      final r = c.read(recordsProvider);
      expect(r.stage('1-1').bestScore, 1000);
      expect(r.stage('1-1', Difficulty.hard).bestScore, 5000);
      expect(r.stage('1-1', Difficulty.hard).starCount, 2);
      expect(r.stage('1-1', Difficulty.easy).cleared, isFalse);
      expect(
        r.toJson()['stages'],
        containsPair('1-1', isA<Map<String, Object?>>()),
      );
      expect(
        r.toJson()['stages'],
        containsPair('1-1@hard', isA<Map<String, Object?>>()),
      );
    });

    test('どの難易度でクリアしても次のステージが開く', () async {
      final c = await container();
      expect(c.read(recordsProvider).isUnlocked(campaign, s2), isFalse);
      c.read(recordsProvider.notifier).submitStage('1-1', clear(1000), [
        true,
      ], difficulty: Difficulty.easy);
      expect(c.read(recordsProvider).isUnlocked(campaign, s2), isTrue);
      expect(c.read(recordsProvider).isUnlocked(campaign, s1), isTrue);
    });

    test('ランキングの合計は、ステージごとに難易度をまたいだ最高スコアを足す', () async {
      final c = await container();
      final n = c.read(recordsProvider.notifier);
      n.submitStage('1-1', clear(1000), [true]);
      n.submitStage('1-1', clear(3000), [true], difficulty: Difficulty.hard);
      n.submitStage('1-2', clear(2000), [true], difficulty: Difficulty.easy);
      expect(c.read(recordsProvider).stagesTotal, 5000);
    });

    test('選んだ難易度は設定に保存される', () async {
      final c = await container();
      c
          .read(settingsProvider.notifier)
          .update((s) => s.copyWith(difficulty: Difficulty.hard));
      final raw = (await SharedPreferences.getInstance()).getString(
        'settings.v1',
      )!;
      expect(
        Settings.fromJson(jsonDecode(raw) as Map<String, Object?>).difficulty,
        Difficulty.hard,
      );
      expect(Settings.fromJson(const {}).difficulty, Difficulty.normal);
    });
  });

  group('壊れた保存データ (Issue #145)', () {
    Future<(ProviderContainer, SharedPreferences)> load(String raw) async {
      SharedPreferences.setMockInitialValues({'records': raw});
      final sp = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [sharedPrefsProvider.overrideWithValue(sp)],
      );
      addTearDown(c.dispose);
      return (c, sp);
    }

    StageResult clear(int score) =>
        StageResult(cleared: true, score: score, stats: RunStats());

    test('ステージの 1 件が壊れていても、他のステージとエンドレスの記録は読める', () async {
      const raw =
          '{"version":1,"endless":{"bestScore":5000},"stages":{"1-1":{"cleared":true},"1-2":"x"}}';
      final (c, sp) = await load(raw);
      final r = c.read(recordsProvider);
      expect(r.endless.bestScore, 5000);
      expect(r.stage('1-1').cleared, isTrue);
      expect(r.stages.containsKey('1-2'), isFalse);
      expect(
        sp.getString('records.broken'),
        raw,
        reason: '捨てた項目があるので、元のデータを退避する',
      );

      c
          .read(recordsProvider.notifier)
          .submitEndless(score: 100, round: 1, stats: RunStats());
      final saved = Records.fromJson(
        jsonDecode(sp.getString('records')!) as Map<String, Object?>,
      );
      expect(saved.endless.bestScore, 5000);
      expect(saved.stage('1-1').cleared, isTrue);
      expect(sp.getString('records.broken'), raw);
    });

    test('項目の型が違うときは、その項目だけ初期値にして残りは読む', () async {
      const raw =
          '{"version":1,"endless":{"bestScore":"x","bestRound":7},'
          '"stages":{"1-1":{"cleared":"yes","bestScore":800,"stars":[true,false]},"1-2":{"cleared":true,"stars":3}}}';
      final (c, sp) = await load(raw);
      final r = c.read(recordsProvider);
      expect(r.endless.bestScore, 0);
      expect(r.endless.bestRound, 7);
      expect(r.stage('1-1').cleared, isFalse);
      expect(r.stage('1-1').bestScore, 800);
      expect(r.stage('1-1').stars, [true, false]);
      expect(r.stage('1-2').cleared, isTrue);
      expect(r.stage('1-2').stars, isEmpty);
      expect(sp.getString('records.broken'), raw);
    });

    test('JSON として読めないときは、元の文字列を records.broken に残して初期値で始める', () async {
      const raw = '{"version":1,"endless":{"bestScore":50';
      final (c, sp) = await load(raw);
      expect(c.read(recordsProvider).endless.bestScore, 0);
      expect(sp.getString('records.broken'), raw);

      c.read(recordsProvider.notifier).submitStage('1-1', clear(300), [true]);
      expect(sp.getString('records.broken'), raw, reason: '保存しても退避したデータは残る');
      expect(sp.getString('records'), isNot(raw));
    });

    test('最上位が JSON のオブジェクトでないときも退避して初期値で始める', () async {
      final (c, sp) = await load('[1,2]');
      expect(c.read(recordsProvider).stages, isEmpty);
      expect(sp.getString('records.broken'), '[1,2]');
    });

    test('今より新しい version のデータは、読める項目を読み、元のデータを退避する', () async {
      final raw = jsonEncode({
        'version': Records.version + 1,
        'endless': {'bestScore': 9000, 'newField': 1},
        'stages': {
          '1-1': {
            'cleared': true,
            'bestScore': 700,
            'stars': [true],
          },
        },
        'future': {'x': 1},
      });
      final (c, sp) = await load(raw);
      final r = c.read(recordsProvider);
      expect(r.endless.bestScore, 9000);
      expect(r.stage('1-1').bestScore, 700);
      expect(sp.getString('records.broken'), raw);

      c
          .read(recordsProvider.notifier)
          .submitEndless(score: 10, round: 1, stats: RunStats());
      expect(sp.getString('records.broken'), raw, reason: '新しい版のデータは上書きで失わない');
    });

    test('正しいデータでは退避しない', () async {
      final raw = jsonEncode(
        const Records(
          endless: EndlessRecord(bestScore: 10),
          stages: {
            '1-1': StageRecord(
              cleared: true,
              bestScore: 5,
              stars: [true, false],
            ),
          },
        ).toJson(),
      );
      final (c, sp) = await load(raw);
      expect(c.read(recordsProvider).stage('1-1').stars, [true, false]);
      expect(sp.getString('records.broken'), isNull);
    });

    test('version がない古い形式も、退避せずに読む', () async {
      final (c, sp) = await load('{"endless":{"bestScore":42},"stages":{}}');
      expect(c.read(recordsProvider).endless.bestScore, 42);
      expect(sp.getString('records.broken'), isNull);
    });
  });
}
