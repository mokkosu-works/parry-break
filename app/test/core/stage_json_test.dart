// Issue #167: campaign.json / endless.json の中身を、全ステージ・全ラウンドについて静的に確かめる。
//
// 読み込み (Campaign.fromJson) は形しか見ないので、中身の誤り (短い行・存在しないブロック・
// 説明や調整のキーの綴り違いなど) は、遊んだその場で例外になるか、黙って無視される。
// ここでは [stageProblems] が誤りを一覧にし、本物の JSON では空であること、
// わざと壊した JSON ではその誤りを見つけることを確かめる。
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:parry_break/core/blocks/explosive.dart';
import 'package:parry_break/core/core.dart';
import 'package:parry_break/l10n/app_localizations.dart';
import 'package:parry_break/render/field_painter.dart' show introText;

/// 手で並べる配置の行数の上限。自動生成 (procedural_generator.dart) の上限と同じ 8 行にする。
/// 8 行なら最下段は盤面の y = 84 + 8 × 24 = 276 で、デッドライン (550) まで 11 行分あく。
const maxLayoutRows = 8;

/// 読み込んだ 1 ラウンドだけを遊ぶモード (2・3 ラウンド目も 1 ラウンド目として並べる)。
class _OneRound extends GameMode {
  const _OneRound(this.spec);
  final RoundSpec spec;

  @override
  String get recordKey => 'test';

  @override
  RoundSpec? roundAt(int number) =>
      number == 1 ? spec.copyWith(number: 1) : null;
}

/// 読まれたキーを覚える Map。[Tuning.copyWith] が読むキー (= 上書きできるキー) を集めるのに使う。
class _KeyRecorder extends MapBase<String, Object?> {
  final read = <String>{};
  @override
  Object? operator [](Object? key) {
    read.add(key! as String);
    return null;
  }

  @override
  void operator []=(String key, Object? value) {}
  @override
  void clear() {}
  @override
  Iterable<String> get keys => const [];
  @override
  Object? remove(Object? key) => null;
}

/// ステージの `tuning` に書けるキー。
final Set<String> tuningKeys = () {
  final r = _KeyRecorder();
  const Tuning().copyWith(r);
  return r.read;
}();

final _l10n = [
  lookupAppLocalizations(const Locale('ja')),
  lookupAppLocalizations(const Locale('en')),
];

/// 説明のキーが、どの言語でも文言になるか。
bool _introOk(String key, {int? scoreTarget}) => _l10n.every(
  (l) => introText(l, key, loop: 2, scoreTarget: scoreTarget) != null,
);

/// 配置の行 ([rows]) の誤り。[where] は誤りの場所の名前。
List<String> _rowProblems(
  String where,
  List<String> rows,
  Map<String, String> legend,
  BlockRegistry reg, {
  required bool annihilate,
}) {
  final out = <String>[];
  if (rows.length > maxLayoutRows) {
    out.add('$where: 行が ${rows.length} 行ある (上限 $maxLayoutRows)');
  }
  var clearable = 0;
  for (final (r, row) in rows.indexed) {
    if (row.length != Field.cols) {
      out.add('$where: ${r + 1} 行目が ${row.length} 文字 (14 文字にする)');
    }
    for (final ch in row.split('')) {
      if (ch == '.') continue;
      final id = legend[ch] ?? ch;
      if (!reg.contains(id)) {
        out.add('$where: 存在しないブロック "$ch"${id == ch ? '' : ' (→ "$id")'}');
      } else if (reg[id].clearable) {
        clearable++;
      }
    }
  }
  if (annihilate && clearable == 0) out.add('$where: 全消しのラウンドに、全消し対象のブロックがない');
  return out;
}

/// ボスの要塞の誤り。
List<String> _bossProblems(String where, List<String> tpl, BlockRegistry reg) {
  final out = <String>[];
  final w = tpl.first.length;
  for (final (r, row) in tpl.indexed) {
    if (row.length != w) {
      out.add(
        '$where: template の ${r + 1} 行目の長さ ${row.length} が 1 行目 ($w) と違う',
      );
    }
    for (var c = 0; c < row.length; c++) {
      final ch = row[c];
      if (ch == '.') continue;
      if (!reg.contains(ch)) out.add('$where: 存在しないブロック "$ch"');
      if (ch == bossCoreId) {
        // コアは 2 行分の高さなので、真下のマスは空けておく
        final below = r + 1 < tpl.length && c < tpl[r + 1].length
            ? tpl[r + 1][c]
            : null;
        if (below != '.') {
          out.add('$where: コアの真下 (${r + 2} 行目 ${c + 1} 列) が "." でない');
        }
      }
    }
  }
  return out;
}

/// 1 ラウンドを実際に並べる。並べられなければ誤り。
List<String> _placeProblems(String where, RoundSpec spec) {
  try {
    final w = World(mode: _OneRound(spec))..start();
    if (w.blocks.isEmpty) return ['$where: ブロックが 1 つも並ばない'];
    return const [];
  } on Object catch (e) {
    return ['$where: 並べると例外 ($e)'];
  }
}

/// [campaignJson] と [endlessJson] の誤りの一覧 (なければ空)。
List<String> stageProblems(
  Map<String, Object?> campaignJson,
  Map<String, Object?> endlessJson,
) {
  final reg = standardBlocks();
  final out = <String>[];

  // ---- endless.json
  final EndlessContent endless;
  try {
    endless = EndlessContent.fromJson(endlessJson);
  } on Object catch (e) {
    return ['endless.json を読めない ($e)'];
  }
  if (endlessJson['loopIntro'] case final String k when !_introOk(k)) {
    out.add('endless.json loopIntro: 説明 "$k" がない');
  }
  for (final MapEntry(:key, :value)
      in (endlessJson['handcrafted'] as Map<String, Object?>).entries) {
    final where = 'endless.json R$key';
    final n = int.tryParse(key);
    if (n == null || n < 1 || n > endless.roundsPerLoop) {
      out.add('$where: ラウンド番号が 1〜${endless.roundsPerLoop} の外');
    }
    final v = value! as Map<String, Object?>;
    if (v['intro'] case final String k when !_introOk(k)) {
      out.add('$where: 説明 "$k" がない');
    }
    if (v['rows'] case final List<Object?> rows) {
      out.addAll(
        _rowProblems(
          where,
          rows.cast<String>(),
          const {},
          reg,
          annihilate: true,
        ),
      );
    }
  }
  for (final (i, b) in endless.bosses.indexed) {
    out.addAll(_bossProblems('endless.json boss $i', b.template, reg));
  }

  // ---- campaign.json
  // 番号の範囲は、読み込み (endless は黙って自動生成、boss は RangeError) の前に見る
  final rawStages = [
    for (final c
        in (campaignJson['chapters'] as List).cast<Map<String, Object?>>())
      ...(c['stages'] as List).cast<Map<String, Object?>>(),
  ];
  for (final s in rawStages) {
    for (final (i, r)
        in (s['rounds'] as List).cast<Map<String, Object?>>().indexed) {
      final where = '${s['id']} の ${i + 1} ラウンド目';
      if (r['endless'] case final num n
          when n < 1 || n > endless.roundsPerLoop) {
        out.add('$where: endless $n が 1〜${endless.roundsPerLoop} の外');
      }
      if (r['boss'] case final num n when n < 0 || n >= endless.bosses.length) {
        out.add('$where: boss $n が 0〜${endless.bosses.length - 1} の外');
      }
      if (r['tuning'] case final Map<Object?, Object?> t) {
        for (final k in t.keys) {
          if (!tuningKeys.contains(k)) {
            out.add('$where: tuning のキー "$k" は Tuning にない');
          }
        }
      }
    }
  }
  if (out.isNotEmpty) return out;

  final Campaign campaign;
  try {
    campaign = Campaign.fromJson(campaignJson, endless);
  } on Object catch (e) {
    return ['campaign.json を読めない ($e)'];
  }
  for (final s in campaign.stages) {
    for (final (i, w) in s.rounds.indexed) {
      final where = '${s.id} の ${i + 1} ラウンド目';
      if (w.introKey case final k?) {
        final target = switch (w.clear) {
          ScoreClear(:final target) => target,
          _ => null,
        };
        if (!_introOk(k, scoreTarget: target)) {
          out.add('$where: 説明 "$k" がない (またはクリア条件と合わない)');
        }
      }
      if (w.content case final LayoutContent c) {
        out.addAll(
          _rowProblems(
            where,
            c.rows,
            c.legend,
            reg,
            annihilate: w.clear is AnnihilateClear,
          ),
        );
      }
      out.addAll(_placeProblems(where, w));
    }

    // 連鎖爆発の星: どれかのラウンドに、目標の数以上の爆薬がある (連鎖の数は爆薬の爆発だけを数える)
    for (final st in s.stars) {
      if (st case StatStar(kind: StatKind.chainBlast, :final value)) {
        final most = s.rounds
            .map(
              (w) => switch (w.content) {
                final LayoutContent c => [
                  for (var r = 0; r < c.rows.length; r++)
                    for (var k = 0; k < c.rows[r].length; k++)
                      if (c.rows[r][k] != '.' &&
                          reg.contains(c.blockIdAt(r, k)))
                        reg[c.blockIdAt(r, k)],
                ].whereType<ExplosiveBlock>().length,
                BossContent() => 0,
              },
            )
            .fold(0, (a, b) => a > b ? a : b);
        if (most < value) {
          out.add('${s.id}: 連鎖爆発 ×$value の星があるのに、爆薬が多くて $most 個');
        }
      }
    }
  }
  return out;
}

Map<String, Object?> _load(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;

/// JSON の深いコピー (壊すテスト用)。
Map<String, Object?> _copy(Map<String, Object?> j) =>
    jsonDecode(jsonEncode(j)) as Map<String, Object?>;

void main() {
  final campaignJson = _load('assets/stages/campaign.json');
  final endlessJson = _load('assets/stages/endless.json');

  test('Tuning.copyWith で上書きできるキーを集められる', () {
    expect(
      tuningKeys,
      containsAll(['descentBase', 'descentMax', 'parryWindow', 'countdown']),
    );
    expect(tuningKeys, isNot(contains('descentbase')));
  });

  test('campaign.json / endless.json に誤りがない (全ステージ・全ラウンド)', () {
    expect(stageProblems(campaignJson, endlessJson), isEmpty);
  });

  test('2・3 ラウンド目も含めて、全ラウンドを並べている', () {
    final campaign = Campaign.fromJson(
      campaignJson,
      EndlessContent.fromJson(endlessJson),
    );
    final later = [
      for (final s in campaign.stages)
        for (final (i, _) in s.rounds.indexed.skip(1)) '${s.id}:${i + 1}',
    ];
    // 2 ラウンド以上ある面 (2-2, 3-9, 4-9, 5-9, 6-9) の 2・3 ラウンド目
    expect(
      later,
      containsAll([
        '2-2:2',
        '3-9:2',
        '3-9:3',
        '4-9:2',
        '5-9:2',
        '6-9:2',
        '6-9:3',
      ]),
    );
    for (final s in campaign.stages) {
      for (final (i, w) in s.rounds.indexed) {
        expect(_placeProblems('${s.id}:${i + 1}', w), isEmpty);
      }
    }
  });

  group('わざと壊した JSON で誤りを見つける', () {
    /// [stageId] の面の (0 始まりの) [round] 番目のラウンドの JSON。
    Map<String, Object?> roundOf(
      Map<String, Object?> c,
      String stageId,
      int round,
    ) {
      for (final ch in (c['chapters'] as List).cast<Map<String, Object?>>()) {
        for (final s in (ch['stages'] as List).cast<Map<String, Object?>>()) {
          if (s['id'] == stageId) {
            return (s['rounds'] as List)[round] as Map<String, Object?>;
          }
        }
      }
      throw StateError(stageId);
    }

    Map<String, Object?> stageOf(Map<String, Object?> c, String stageId) {
      for (final ch in (c['chapters'] as List).cast<Map<String, Object?>>()) {
        for (final s in (ch['stages'] as List).cast<Map<String, Object?>>()) {
          if (s['id'] == stageId) return s;
        }
      }
      throw StateError(stageId);
    }

    /// campaign.json を [edit] で壊すと、[expected] を含む誤りが出る。
    void campaignBreaks(
      String name,
      void Function(Map<String, Object?> c) edit,
      String expected,
    ) {
      test(name, () {
        final c = _copy(campaignJson);
        edit(c);
        expect(stageProblems(c, endlessJson), contains(contains(expected)));
      });
    }

    void endlessBreaks(
      String name,
      void Function(Map<String, Object?> e) edit,
      String expected,
    ) {
      test(name, () {
        final e = _copy(endlessJson);
        edit(e);
        expect(stageProblems(campaignJson, e), contains(contains(expected)));
      });
    }

    // 4-9 の 2 ラウンド目は rows で書いてある (1 ラウンド目だけ並べるテストでは見つからない)
    campaignBreaks('2 ラウンド目の行が短い', (c) {
      final rows = roundOf(c, '4-9', 1)['rows']! as List;
      rows[0] = (rows[0] as String).substring(0, 13);
    }, '4-9 の 2 ラウンド目: 1 行目が 13 文字');

    campaignBreaks('2 ラウンド目の行が短いと、並べると例外になる', (c) {
      final rows = roundOf(c, '4-9', 1)['rows']! as List;
      rows[0] = (rows[0] as String).substring(0, 13);
    }, '4-9 の 2 ラウンド目: 並べると例外');

    campaignBreaks('存在しないブロックの文字', (c) {
      final rows = roundOf(c, '4-9', 1)['rows']! as List;
      rows[0] = '?${(rows[0] as String).substring(1)}';
    }, '存在しないブロック "?"');

    campaignBreaks('legend の読み替え先が存在しない', (c) {
      final r = roundOf(c, '4-9', 1);
      final rows = r['rows']! as List;
      rows[0] = 'q${(rows[0] as String).substring(1)}';
      r['legend'] = {'q': '?'};
    }, '存在しないブロック "q" (→ "?")');

    campaignBreaks(
      '存在しない説明のキー',
      (c) => roundOf(c, '1-1', 0)['intro'] = 'intro.nope',
      '説明 "intro.nope" がない',
    );

    campaignBreaks(
      'スコアのクリア条件がない面に intro.score',
      (c) => roundOf(c, '1-2', 0)['intro'] = 'intro.score',
      '説明 "intro.score" がない',
    );

    campaignBreaks(
      '3 ラウンド目の存在しない tuning のキー',
      (c) => roundOf(c, '6-9', 2)['tuning'] = {'descentbase': 2},
      '6-9 の 3 ラウンド目: tuning のキー "descentbase"',
    );

    campaignBreaks(
      'endless の番号が範囲外',
      (c) => roundOf(c, '2-2', 1)['endless'] = 61,
      'endless 61 が 1〜60 の外',
    );

    campaignBreaks(
      'boss の番号が範囲外',
      (c) => roundOf(c, '1-10', 0)['boss'] = 6,
      'boss 6 が 0〜5 の外',
    );

    campaignBreaks('全消しのラウンドに全消し対象のブロックがない', (c) {
      final r = roundOf(c, '4-9', 1);
      r['rows'] = ['##############', '..............'];
      r.remove('legend');
      r.remove('clear');
    }, '全消し対象のブロックがない');

    campaignBreaks('行が多すぎる', (c) {
      final r = roundOf(c, '4-9', 1);
      r['rows'] = [for (var i = 0; i < 12; i++) 'NNNNNNNNNNNNNN'];
      r.remove('legend');
    }, '行が 12 行ある');

    campaignBreaks('連鎖爆発の星の数より爆薬が少ない', (c) {
      final s = stageOf(c, '1-1');
      s['stars'] = [
        {'type': 'clear'},
        {'type': 'chainBlast', 'value': 3},
      ];
    }, '1-1: 連鎖爆発 ×3 の星があるのに');

    endlessBreaks('ボスの template の行の長さが揃っていない', (e) {
      final tpl =
          ((e['bosses'] as List)[0] as Map<String, Object?>)['template']!
              as List;
      tpl[1] = '${tpl[1]}N';
    }, 'endless.json boss 0: template の 2 行目の長さ');

    endlessBreaks('ボスのコアの真下が空いていない', (e) {
      final tpl =
          ((e['bosses'] as List)[0] as Map<String, Object?>)['template']!
              as List<Object?>;
      final r = tpl.indexWhere((row) => (row! as String).contains(bossCoreId));
      final c = (tpl[r]! as String).indexOf(bossCoreId);
      final below = (tpl[r + 1]! as String).split('');
      below[c] = 'N';
      tpl[r + 1] = below.join();
    }, 'コアの真下');

    endlessBreaks('エンドレスの手作りラウンドの説明のキーが存在しない', (e) {
      final hand = e['handcrafted']! as Map<String, Object?>;
      (hand.values.first! as Map<String, Object?>)['intro'] = 'intro.nope';
    }, '説明 "intro.nope" がない');

    endlessBreaks(
      'エンドレスの loopIntro が存在しない',
      (e) => e['loopIntro'] = 'intro.loops',
      'loopIntro: 説明 "intro.loops"',
    );

    endlessBreaks('エンドレスの手作りラウンドの行が短い', (e) {
      final hand = e['handcrafted']! as Map<String, Object?>;
      final withRows = hand.values.cast<Map<String, Object?>>().firstWhere(
        (v) => v['rows'] != null,
      );
      final rows = withRows['rows']! as List;
      rows[0] = (rows[0] as String).substring(1);
    }, '1 行目が 13 文字');
  });
}
