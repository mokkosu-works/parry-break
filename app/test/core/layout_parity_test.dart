import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:parry_break/core/core.dart';

import 'helpers.dart';

/// ブラウザ版 (legacy/index.html) の配置生成と一致することを確かめる。
/// ゴールデンデータは `node tools/dump_layouts.mjs` で作る。
void main() {
  final golden = jsonDecode(File('test/core/golden/layouts.json').readAsStringSync()) as Map<String, dynamic>;

  test('mulberry32 はブラウザ版と同じ値を返す', () {
    final rng = golden['rng'] as Map<String, dynamic>;
    for (final e in rng.entries) {
      final r = Mulberry32(int.parse(e.key));
      for (final v in e.value as List) {
        expect(r.next(), v, reason: 'seed ${e.key}');
      }
    }
  });

  test('W1〜59 (ボス以外) の配置がブラウザ版と一致する', () {
    final waves = golden['waves'] as Map<String, dynamic>;
    expect(waves.length, 54);
    for (final e in waves.entries) {
      final c = endlessContent.contentFor(int.parse(e.key)) as LayoutContent;
      expect(c.rows, List<String>.from(e.value as List), reason: 'wave ${e.key}');
    }
  });

  test('ボス要塞の配置がブラウザ版と一致する', () {
    final bosses = golden['bosses'] as List;
    for (var i = 0; i < bosses.length; i++) {
      expect(endlessContent.bosses[i].template, List<String>.from(bosses[i] as List));
    }
  });

  test('エンドレスは 10 ウェーブごとにボス、60 でループする', () {
    final mode = endlessMode;
    expect(mode.waveAt(10).boss?.index, 0);
    expect(mode.waveAt(60).ending, isTrue);
    final w61 = mode.waveAt(61);
    expect(w61.difficulty, 1);
    expect(w61.loop, 1);
    expect(w61.loopMul, closeTo(1.15, 1e-12));
    expect(w61.introKey, 'intro.loop');
  });
}
