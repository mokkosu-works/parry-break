// ランクの基準の確認: 自動プレイ (bot.dart) の結果からランクの分布を出す。
//
//   flutter test test/balance/rank_dist.dart
//   flutter test test/balance/rank_dist.dart --dart-define=runs=6
//
// エンドレスは腕前 (sigma) を 3 段階、ステージは NORMAL で各ステージ runs 回。
// S が全体の 1 割前後になるように基準 (RankTable) を決めた。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:parry_break/core/core.dart';

import '../core/helpers.dart';
import 'bot.dart';

const _runs = int.fromEnvironment('runs', defaultValue: 3);

String _tally(Iterable<Rank> rs) {
  final n = rs.length;
  final counts = [
    for (final r in Rank.values) '${r.label} ${rs.where((x) => x == r).length}',
  ];
  return '${counts.join('  ')}  (計 $n)';
}

void main() {
  test('endless rank distribution', () {
    final ranks = <Rank>[];
    for (final sigma in [0.02, 0.035, 0.06]) {
      for (var seed = 1; seed <= 12; seed++) {
        final w = World(
          mode: endlessMode,
          difficulty: Difficulty.normal,
          inputLag: 0,
        )..start();
        w.sync
          ..wall = 0
          ..sim = 0
          ..scale = 1;
        final bot = Bot(w, seed: seed, sigma: sigma);
        for (var i = 0; i < (900 / World.dt).round(); i++) {
          bot();
          w.step(World.dt);
          w.drainEvents();
          if (w.phase == WorldPhase.over) break;
        }
        ranks.add(
          RankTable.standard.endless(round: w.round.number, score: w.score),
        );
      }
    }
    // ignore: avoid_print
    print('endless: ${_tally(ranks)}');
  }, timeout: const Timeout(Duration(minutes: 20)));

  test('stage rank distribution', () {
    final campaign = Campaign.fromJson(
      jsonDecode(File('assets/stages/campaign.json').readAsStringSync())
          as Map<String, Object?>,
      endlessContent,
    );
    final ranks = <Rank>[];
    var played = 0;
    for (final s in campaign.stages) {
      for (var i = 0; i < _runs; i++) {
        played++;
        final w = World(
          mode: StageMode(s),
          difficulty: Difficulty.normal,
          inputLag: 0,
        )..start();
        w.sync
          ..wall = 0
          ..sim = 0
          ..scale = 1;
        final bot = Bot(w, seed: i + 1);
        for (var k = 0; k < (400 / World.dt).round(); k++) {
          bot();
          w.step(World.dt);
          w.drainEvents();
          if (w.phase == WorldPhase.over || w.phase == WorldPhase.completed) {
            break;
          }
        }
        if (w.phase != WorldPhase.completed) continue;
        final r = StageResult(cleared: true, score: w.score, stats: w.stats);
        ranks.add(RankTable.standard.stage(s, r, s.evaluate(r)));
      }
    }
    // ignore: avoid_print
    print('stage (clear ${ranks.length}/$played): ${_tally(ranks)}');
  }, timeout: const Timeout(Duration(minutes: 30)));
}
