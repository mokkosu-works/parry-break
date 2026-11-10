import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:parry_break/core/core.dart';

import 'helpers.dart';

/// ブロックの種類 → 初登場のラウンドで出す説明の翻訳キー。通常ブロック `N` は説明なし。
const blockIntros = {
  'K': 'intro.keystone',
  'T': 'intro.turret',
  'B': 'intro.explosive',
  'R': 'intro.reflector',
  'M': 'intro.magnet',
  'S': 'intro.splitter',
  'X': 'intro.mirror',
  '#': 'intro.wall',
  'F': 'intro.spread',
  'G': 'intro.gatling',
  'O': 'intro.ring',
  'Z': 'intro.spiral',
  'P': 'intro.sniper',
};

/// 別の PR で直しているもの。そちらがマージされたら外す。
/// - エンドレスの分裂 `S` は R20 がボスのため R21 で説明なしに初登場する (#158 / PR #188)
/// - ステージで `{"endless": n}` を借りた面にエンドレスの説明が引き継がれない (#71 / PR #183)
const _pendingEndless = {'S'};
const _pendingStage = {'K', 'T', 'B', 'R', 'M', 'S', 'X'};

Set<String> _ids(LayoutContent c) => {
  for (var r = 0; r < c.rows.length; r++)
    for (var k = 0; k < c.rows[r].length; k++)
      if (c.rows[r][k] != '.') c.blockIdAt(r, k),
};

/// 初登場のラウンドで、説明が付いていないブロック (`場所: 種類`)。
List<String> _missing(
  Iterable<(String, RoundSpec)> rounds,
  Set<String> pending, {
  required Set<String> appear,
}) {
  final seen = <String>{}, missing = <String>[];
  for (final (where, spec) in rounds) {
    final c = spec.content;
    if (c is! LayoutContent) continue; // ボス戦では配置も説明も使われない
    for (final id in _ids(c)) {
      if (!seen.add(id) || !blockIntros.containsKey(id)) continue;
      if (spec.introKey != blockIntros[id] && !pending.contains(id))
        missing.add('$where: $id (${spec.introKey})');
    }
  }
  expect(seen, containsAll(appear), reason: '出てくるはずの種類が出てこない');
  return missing;
}

void main() {
  final campaign = Campaign.fromJson(
    jsonDecode(File('assets/stages/campaign.json').readAsStringSync())
        as Map<String, Object?>,
    endlessContent,
  );

  test('エンドレスで、ブロックの種類ごとに初登場のラウンドに説明が付いている', () {
    final rounds = [
      for (var n = 1; n <= endlessContent.roundsPerLoop; n++)
        ('R$n', endlessMode.roundAt(n)),
    ];
    // 攻撃ブロック (F・G・O・Z・P) はステージモードだけに出てくる
    expect(
      _missing(
        rounds,
        _pendingEndless,
        appear: {'K', 'T', 'B', 'R', 'M', 'S', 'X', '#'},
      ),
      isEmpty,
    );
  });

  test('ステージモードで、ブロックの種類ごとに初登場の面に説明が付いている', () {
    final rounds = [
      for (final s in campaign.stages)
        for (final w in s.rounds) ('${s.id} の ${w.number} ラウンド目', w),
    ];
    expect(
      _missing(rounds, _pendingStage, appear: blockIntros.keys.toSet()),
      isEmpty,
    );
  });

  test('破壊不可ブロックは、エンドレスの R12 とステージの 2-8 で説明付きで初登場する', () {
    final r12 = endlessMode.roundAt(12);
    expect(r12.introKey, 'intro.wall');
    expect(_ids(r12.content as LayoutContent), contains('#'));
    // 配置は自動生成のまま (ゴールデンとの一致を崩さない)
    expect(endlessContent.handcrafted[12], isNull);
    for (var n = 1; n < 12; n++) {
      final c = endlessMode.roundAt(n).content;
      if (c is LayoutContent)
        expect(_ids(c), isNot(contains('#')), reason: 'R$n');
    }

    final s28 = campaign.stage('2-8')!.rounds.single;
    expect(s28.introKey, 'intro.wall');
    expect(_ids(s28.content as LayoutContent), contains('#'));
  });
}
