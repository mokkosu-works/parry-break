// アイテム (design.md 7.10) の影響の確認: 同じ自動プレイで、アイテムなし (足す前と同じ展開) と
// アイテムありを比べる。エンドレス (到達ラウンド・スコア) と、ステージ (クリア率・被弾・スコア)。
//
//   flutter test test/balance/item_report.dart
//   flutter test test/balance/item_report.dart --dart-define=stages=2-1,3-5 --dart-define=runs=20
//
// 自動プレイ (bot.dart) はアイテムを取りに行かない (ボールと敵弾だけを見て動く)。
// 「あり」で見えるのは「落ちてきたものをたまたま取る」範囲の影響。狙って取る人の上限として、
// 出たアイテムを全部その場で通常取得にした「全部取る」も並べる (パリィ取得の強化は入らない)。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:parry_break/core/core.dart';

import '../core/helpers.dart';
import 'bot.dart';

const _stages = String.fromEnvironment(
  'stages',
  defaultValue: '2-1,2-5,2-10,3-5,3-10,4-5,4-10,5-5,5-10,6-5,6-10',
);
const _runs = int.fromEnvironment('runs', defaultValue: 12);
const _endlessRuns = int.fromEnvironment('endlessRuns', defaultValue: 20);
const _from = String.fromEnvironment('from', defaultValue: '1,11,21,31');

const _variants = ['なし', 'あり', '全部取る'];

String _f(num v, [int d = 1]) => v.toStringAsFixed(d);

double _mean(Iterable<num> xs) =>
    xs.isEmpty ? 0 : xs.fold(0.0, (a, b) => a + b) / xs.length;

double _median(Iterable<num> xs) {
  final l = xs.map((x) => x.toDouble()).toList()..sort();
  if (l.isEmpty) return 0;
  return l.length.isOdd
      ? l[l.length ~/ 2]
      : (l[l.length ~/ 2 - 1] + l[l.length ~/ 2]) / 2;
}

/// エンドレスを [from] ラウンドから、ミスするまで (最大 [limit] 秒) 遊ぶ。
RunResult _endless(
  GameMode mode,
  int from,
  int seed, {
  double limit = 900,
  bool grab = false,
}) {
  final w = World(mode: mode, inputLag: 0)..start(fromRound: from);
  w.sync.identity();
  final bot = Bot(w, seed: seed);
  var spawned = 0, taken = 0, parried = 0;
  final n = (limit / World.dt).round();
  for (var i = 0; i < n; i++) {
    bot();
    if (grab) grabItems(w);
    w.step(World.dt);
    for (final e in w.drainEvents()) {
      if (e is ItemSpawned) spawned++;
      if (e is ItemTaken) {
        taken++;
        if (e.parried) parried++;
      }
    }
    if (w.phase == WorldPhase.over) break;
  }
  return RunResult(
    w.phase != WorldPhase.over,
    w.stats.hurt,
    w.stats.playTime,
    w.overReason,
    w.score,
    0,
    round: w.round.number,
    itemsSpawned: spawned,
    itemsTaken: taken,
    itemsParried: parried,
  );
}

void main() {
  test('item report', () {
    final out = StringBuffer();

    out.writeln('## エンドレス (NORMAL, 各 $_endlessRuns 回, ミスまで・最大 900 秒)');
    out.writeln(
      '| 開始 | | 到達 R (平均) | 到達 R (中央) | スコア (中央) | 被弾 | 出た | 取った | うちパリィ |',
    );
    out.writeln('| --- | --- | --- | --- | --- | --- | --- | --- | --- |');
    for (final from in _from.split(',').map(int.parse)) {
      for (final v in _variants) {
        final GameMode mode = v == 'なし'
            ? NoItemsMode(endlessMode)
            : endlessMode;
        final rs = [
          for (var i = 0; i < _endlessRuns; i++)
            _endless(mode, from, i + 1, grab: v == '全部取る'),
        ];
        out.writeln(
          '| R$from | $v | ${_f(_mean(rs.map((r) => r.round)))} | '
          '${_f(_median(rs.map((r) => r.round)))} | '
          '${formatScore(_median(rs.map((r) => r.score)))} | '
          '${_f(_mean(rs.map((r) => r.hurt)))} | '
          '${_f(_mean(rs.map((r) => r.itemsSpawned)))} | '
          '${_f(_mean(rs.map((r) => r.itemsTaken)))} | '
          '${_f(_mean(rs.map((r) => r.itemsParried)))} |',
        );
      }
    }

    final campaign = Campaign.fromJson(
      jsonDecode(File('assets/stages/campaign.json').readAsStringSync())
          as Map<String, Object?>,
      endlessContent,
    );
    out.writeln();
    out.writeln('## ステージ (各 $_runs 回)');
    out.writeln('| 面 | 難易度 | | クリア | 被弾 | 時間 (クリア時) | スコア (中央) | 出た | 取った |');
    out.writeln('| --- | --- | --- | --- | --- | --- | --- | --- | --- |');
    for (final id in _stages.split(',')) {
      final s = campaign.stage(id)!;
      for (final d in [Difficulty.normal, Difficulty.hard]) {
        for (final v in _variants) {
          final GameMode mode = v == 'なし'
              ? NoItemsMode(StageMode(s))
              : StageMode(s);
          final rs = [
            for (var i = 0; i < _runs; i++)
              playOut(mode, d, seed: i + 1, grab: v == '全部取る'),
          ];
          final won = rs.where((r) => r.cleared);
          out.writeln(
            '| $id | ${d.label} | $v | ${won.length}/$_runs | '
            '${_f(_mean(rs.map((r) => r.hurt)))} | '
            '${_f(_mean(won.map((r) => r.time)), 0)} | '
            '${formatScore(_median(rs.map((r) => r.score)))} | '
            '${_f(_mean(rs.map((r) => r.itemsSpawned)))} | '
            '${_f(_mean(rs.map((r) => r.itemsTaken)))} |',
          );
        }
      }
    }
    // ignore: avoid_print
    print(out);
  }, timeout: const Timeout(Duration(minutes: 60)));
}
