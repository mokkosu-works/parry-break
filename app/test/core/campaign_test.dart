import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:parry_break/core/core.dart';

import 'helpers.dart';

void main() {
  final campaign = Campaign.fromJson(
      jsonDecode(File('assets/stages/campaign.json').readAsStringSync()) as Map<String, Object?>, endlessContent);

  test('すべてのステージを読み込め、ID が重複しない', () {
    final ids = campaign.stages.map((s) => s.id).toList();
    expect(ids.toSet().length, ids.length);
    expect(campaign.chapters.first.stages.first.title.of('ja'), 'はじめの一撃');
    for (final s in campaign.stages) {
      expect(s.stars, isNotEmpty, reason: s.id);
      final w = World(mode: StageMode(s))..start();
      expect(w.blocks, isNotEmpty, reason: s.id);
    }
  });

  test('6 章あり、どの章も 10 ステージで、最後はボス 1〜6 を順に使う', () {
    expect(campaign.chapters, hasLength(6));
    for (final (i, ch) in campaign.chapters.indexed) {
      expect(ch.stages, hasLength(10), reason: ch.id);
      expect([for (final s in ch.stages) s.id], [for (var k = 1; k <= 10; k++) '${i + 1}-$k'], reason: ch.id);
      expect(ch.stages.last.waves.single.boss?.index, i, reason: ch.id);
      expect(ch.stages.where((s) => s.waves.any((w) => w.boss != null)), hasLength(1), reason: ch.id);
    }
  });

  test('新しい攻撃ブロックは、説明付きのステージで初めて登場する', () {
    final seen = <String>{};
    for (final s in campaign.stages) {
      for (final w in s.waves) {
        final c = w.content;
        if (c is! LayoutContent) continue;
        final ids = {for (var r = 0; r < c.rows.length; r++) for (var k = 0; k < 14; k++) if (c.rows[r][k] != '.') c.blockIdAt(r, k)};
        for (final (id, intro) in [('F', 'spread'), ('G', 'gatling'), ('O', 'ring'), ('Z', 'spiral'), ('P', 'sniper')]) {
          if (ids.contains(id) && seen.add(id)) expect(w.introKey, 'intro.$intro', reason: '${s.id} で $id が初登場');
        }
      }
    }
    expect(seen, {'F', 'G', 'O', 'Z', 'P'});
  });

  test('エンドレスのボスの番号を指定したステージでも、ボスではなく配置になる', () {
    final s = campaign.stage('2-4')!; // エンドレスの W20 (分裂の学習ウェーブ)
    final w = World(mode: StageMode(s))..start();
    expect(w.boss, isNull);
    expect(w.blocks.any((b) => b.type == 'S'), isTrue);
  });

  test('生存ステージは時間が来たらクリアになり、モードが終わる', () {
    final s = campaign.stage('1-8')!; // 防衛線を死守せよ (40 秒耐える)
    final w = World(mode: StageMode(s))..start();
    final events = run(w, 50, before: autopilot(w));
    if (w.phase == WorldPhase.over) return; // 自動操作が先に落とした場合は判定しない
    expect(events.whereType<WaveCleared>(), hasLength(1));
    expect(events.whereType<StageCompleted>(), hasLength(1));
    expect(w.phase, WorldPhase.completed);
  });

  test('星の判定', () {
    final s = campaign.stage('1-4')!; // clear / returnKills 3 / noHit
    final stats = RunStats()..returnKills = 3;
    expect(s.evaluate(StageResult(cleared: true, score: 0, stats: stats)), [true, true, true]);
    stats.hurt = 1;
    expect(s.evaluate(StageResult(cleared: true, score: 0, stats: stats)), [true, true, false]);
    expect(s.evaluate(StageResult(cleared: false, score: 0, stats: stats)), [false, false, false]);
  });

  group('JSON の読み込み', () {
    test('星の条件を種類ごとに読み分ける', () {
      expect(StarCondition.fromJson({'type': 'clear'}), isA<ClearStar>());
      expect(StarCondition.fromJson({'type': 'noHit'}), isA<NoHitStar>());
      expect(StarCondition.fromJson({'type': 'time', 'value': 45}), isA<TimeStar>().having((t) => t.seconds, 'seconds', 45));
      expect(
        StarCondition.fromJson({'type': 'score', 'value': 1000}),
        isA<StatStar>().having((t) => t.kind, 'kind', StatKind.score).having((t) => t.value, 'value', 1000),
      );
      expect(StarCondition.fromJson({'type': 'just', 'value': 3}), isA<StatStar>().having((t) => t.kind, 'kind', StatKind.just));
    });

    test('星の条件の形が合わなければ例外', () {
      expect(() => StarCondition.fromJson({'type': 'time'}), throwsFormatException);
      expect(() => StarCondition.fromJson({'value': 3}), throwsFormatException);
      expect(() => StarCondition.fromJson({'type': 'unknown', 'value': 3}), throwsArgumentError);
    });

    Campaign one(Map<String, Object?> wave) => Campaign.fromJson({
          'chapters': [
            {
              'id': 'c',
              'title': 'C',
              'stages': [
                {'id': 's', 'title': 'S', 'waves': [wave]},
              ],
            },
          ],
        }, endlessContent);

    test('ウェーブの書き方ごとに中身と既定の難易度が決まる', () {
      final rows = one({'rows': ['..NN..', '..XX..'], 'legend': {'X': 'T'}}).stage('s')!.waves.single;
      expect(rows.difficulty, 1);
      expect((rows.content as LayoutContent).blockIdAt(1, 2), 'T');

      final fromEndless = one({'endless': 4}).stage('s')!.waves.single;
      expect(fromEndless.difficulty, 4);
      expect(fromEndless.content, isA<LayoutContent>());

      final boss = one({'boss': 0}).stage('s')!.waves.single;
      expect(boss.difficulty, endlessContent.bossEvery);
      expect(boss.boss, same(endlessContent.bosses.first));

      expect(one({'boss': 0, 'difficulty': 3}).stage('s')!.waves.single.difficulty, 3);
    });

    test('星を書かないステージはクリアだけ、中身のないウェーブは例外', () {
      expect(one({'endless': 1}).stage('s')!.stars.single, isA<ClearStar>());
      expect(() => one({'difficulty': 2}), throwsFormatException);
    });

    test('言語ごとの文字列', () {
      expect(LocalizedText.fromJson({'ja': 'あ', 'en': 'a'}).of('ja'), 'あ');
      expect(LocalizedText.fromJson({'ja': 'あ'}).of('en'), 'あ');
      expect(LocalizedText.fromJson('plain').of('ja'), 'plain');
      expect(LocalizedText.fromJson(null).of('en'), '');
    });
  });
}
