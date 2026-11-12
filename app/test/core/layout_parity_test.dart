import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:parry_break/core/core.dart';

import 'helpers.dart';

/// ブラウザ版のあとで手作りの配置に差し替えたラウンド。
/// R21: R20 がボスで分裂の学習ラウンドが遊べないため、分裂の初登場をここで手作りにした (#158)。
const _handcraftedSinceBrowser = {21};

/// ブラウザ版 (削除済み) の配置生成と一致することを確かめる。
/// ゴールデンデータはブラウザ版から書き出したもので、作り直すことはできない。
void main() {
  final golden = jsonDecode(
    File('test/core/golden/layouts.json').readAsStringSync(),
  ) as Map<String, dynamic>;

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
    final rounds = golden['rounds'] as Map<String, dynamic>;
    expect(rounds.length, 54);
    for (final e in rounds.entries) {
      final n = int.parse(e.key);
      // ブラウザ版のあとで手作りにしたラウンドは、自動生成のほうがゴールデンと一致することを確かめる
      final rows = _handcraftedSinceBrowser.contains(n)
          ? generateLayout(n, unlock: endlessContent.unlock)
          : (endlessContent.contentFor(n) as LayoutContent).rows;
      expect(
        rows,
        List<String>.from(e.value as List),
        reason: 'round ${e.key}',
      );
    }
  });

  test('ボス要塞の配置がブラウザ版と一致する', () {
    final bosses = golden['bosses'] as List;
    for (var i = 0; i < bosses.length; i++) {
      expect(
        endlessContent.bosses[i].template,
        List<String>.from(bosses[i] as List),
      );
    }
  });

  test('エンドレスは 10 ラウンドごとにボス、60 でループする', () {
    final mode = endlessMode;
    expect(mode.roundAt(10).boss?.index, 0);
    expect(mode.roundAt(60).ending, isTrue);
    final w61 = mode.roundAt(61);
    expect(w61.difficulty, 1);
    expect(w61.loop, 1);
    expect(w61.loopMul, closeTo(1.15, 1e-12));
    expect(w61.introKey, 'intro.loop');
  });
}
