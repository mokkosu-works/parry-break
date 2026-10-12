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
      final r = StageRecord.fromJson(const StageRecord(cleared: true, bestScore: 1200, stars: [true, false]).toJson());
      expect(r.cleared, isTrue);
      expect(r.bestScore, 1200);
      expect(r.stars, [true, false]);
    });
  });

  test('ステージの星は一度達成したら残る', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
    addTearDown(container.dispose);
    final notifier = container.read(recordsProvider.notifier);

    StageResult result({required bool cleared, int score = 0}) =>
        StageResult(cleared: cleared, score: score, stats: RunStats());
    notifier.submitStage('1-1', result(cleared: true, score: 500), [true, false, true]);
    notifier.submitStage('1-1', result(cleared: false), [false, true, false]);

    final rec = container.read(recordsProvider).stage('1-1');
    expect(rec.stars, [true, true, true]);
    expect(rec.cleared, isTrue);
    expect(rec.bestScore, 500);
  });

  group('難易度', () {
    final campaign = Campaign.fromJson(
        jsonDecode(File('assets/stages/campaign.json').readAsStringSync()) as Map<String, Object?>, endlessContent);
    final s1 = campaign.stage('1-1')!, s2 = campaign.stage('1-2')!;

    Future<ProviderContainer> container([Map<String, Object> prefs = const {}]) async {
      SharedPreferences.setMockInitialValues(prefs);
      final sp = await SharedPreferences.getInstance();
      final c = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(sp)]);
      addTearDown(c.dispose);
      return c;
    }

    StageResult clear(int score) => StageResult(cleared: true, score: score, stats: RunStats());

    test('記録は難易度ごとに分けて残し、NORMAL は以前と同じキーを使う', () async {
      final c = await container();
      final n = c.read(recordsProvider.notifier);
      n.submitStage('1-1', clear(1000), [true, false, false]);
      n.submitStage('1-1', clear(5000), [true, true, false], difficulty: Difficulty.hard);
      final r = c.read(recordsProvider);
      expect(r.stage('1-1').bestScore, 1000);
      expect(r.stage('1-1', Difficulty.hard).bestScore, 5000);
      expect(r.stage('1-1', Difficulty.hard).starCount, 2);
      expect(r.stage('1-1', Difficulty.easy).cleared, isFalse);
      expect(r.toJson()['stages'], containsPair('1-1', isA<Map<String, Object?>>()));
      expect(r.toJson()['stages'], containsPair('1-1@hard', isA<Map<String, Object?>>()));
    });

    test('どの難易度でクリアしても次のステージが開く', () async {
      final c = await container();
      expect(c.read(recordsProvider).isUnlocked(campaign, s2), isFalse);
      c.read(recordsProvider.notifier).submitStage('1-1', clear(1000), [true], difficulty: Difficulty.easy);
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
      c.read(settingsProvider.notifier).update((s) => s.copyWith(difficulty: Difficulty.hard));
      final raw = (await SharedPreferences.getInstance()).getString('settings.v1')!;
      expect(Settings.fromJson(jsonDecode(raw) as Map<String, Object?>).difficulty, Difficulty.hard);
      expect(Settings.fromJson(const {}).difficulty, Difficulty.normal);
    });
  });
}
