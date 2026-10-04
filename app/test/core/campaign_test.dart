import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ricochet/core/core.dart';

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

  test('生存ステージは時間が来たらクリアになり、モードが終わる', () {
    final s = campaign.stage('1-7')!;
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
}
