// 難易度の確認: 全ステージを自動プレイで難易度ごとに遊び、クリア率・被弾数・弾の量を出す。
//
//   flutter test test/balance/balance_report.dart
//   flutter test test/balance/balance_report.dart --dart-define=stages=4-1,4-6 --dart-define=runs=20
//
// 自動プレイ (bot.dart) は人の腕前そのものではない。NORMAL と比べて HARD がどれだけ厳しいかを見る。
// 目安: NORMAL はほぼクリアでき、HARD は被弾を重ねながら半分前後クリアできる (ギリギリ)。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:parry_break/core/core.dart';

import '../core/helpers.dart';
import 'bot.dart';

const _stages = String.fromEnvironment('stages');
const _runs = int.fromEnvironment('runs', defaultValue: 8);
const _diffs = String.fromEnvironment('difficulties', defaultValue: 'easy,normal,hard');

void main() {
  test('balance report', () {
    final campaign = Campaign.fromJson(
        jsonDecode(File('assets/stages/campaign.json').readAsStringSync()) as Map<String, Object?>, endlessContent);
    final only = _stages.isEmpty ? null : _stages.split(',').toSet();
    final diffs = [for (final d in _diffs.split(',')) Difficulty.values.byName(d)];
    final out = StringBuffer()
      ..writeln('stage  ${[for (final d in diffs) d.label.padRight(30)].join()}')
      ..writeln('       ${[for (final _ in diffs) 'clear  hurt  time  bul/s  fail'.padRight(30)].join()}');
    for (final s in campaign.stages) {
      if (only != null && !only.contains(s.id)) continue;
      final cols = <String>[];
      for (final d in diffs) {
        final rs = [for (var i = 0; i < _runs; i++) playOut(StageMode(s), d, seed: i + 1)];
        final clear = rs.where((r) => r.cleared).length;
        final hurt = rs.fold(0, (a, r) => a + r.hurt) / rs.length;
        final won = rs.where((r) => r.cleared);
        final time = won.isEmpty ? 0 : won.fold(0.0, (a, r) => a + r.time) / won.length;
        final bul = rs.fold(0.0, (a, r) => a + r.bullets) / rs.length;
        final fails = <String, int>{};
        for (final r in rs.where((r) => !r.cleared)) {
          final k = r.reason.split(' ').last.substring(0, 4);
          fails[k] = (fails[k] ?? 0) + 1;
        }
        cols.add('${'$clear/$_runs'.padLeft(5)}  ${hurt.toStringAsFixed(1).padLeft(4)}  '
                '${time.toStringAsFixed(0).padLeft(4)}  ${bul.toStringAsFixed(1).padLeft(5)}  '
                '${fails.entries.map((e) => '${e.key}${e.value}').join(',')}'
            .padRight(30));
      }
      out.writeln('${s.id.padRight(6)} ${cols.join()}');
    }
    // ignore: avoid_print
    print(out);
  }, timeout: const Timeout(Duration(minutes: 30)));
}
