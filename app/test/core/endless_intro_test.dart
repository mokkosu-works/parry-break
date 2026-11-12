import 'package:flutter_test/flutter_test.dart';
import 'package:parry_break/core/core.dart';

import 'helpers.dart';

/// ブロックの種類 → 初登場で出す説明の翻訳キー。
const _intros = {
  'K': 'intro.keystone',
  'T': 'intro.turret',
  'B': 'intro.explosive',
  'R': 'intro.reflector',
  'M': 'intro.magnet',
  'S': 'intro.splitter',
  'X': 'intro.mirror',
};

void main() {
  test('エンドレスの各ブロックの初登場ラウンドに、そのブロックの説明が付いている (ボスのラウンドは数えない)', () {
    final first = <String, int>{};
    for (var n = 1; n <= endlessContent.roundsPerLoop; n++) {
      final spec = endlessMode.roundAt(n);
      final c = spec.content;
      if (c is! LayoutContent) continue; // ボス戦では配置も説明も使われない
      for (var r = 0; r < c.rows.length; r++) {
        for (var k = 0; k < c.rows[r].length; k++) {
          if (c.rows[r][k] == '.') continue;
          final id = c.blockIdAt(r, k);
          if (first.containsKey(id)) continue;
          first[id] = n;
          if (_intros[id] case final intro?) {
            expect(spec.introKey, intro, reason: 'R$n で $id が初登場');
          }
        }
      }
    }
    expect(first.keys, containsAll(_intros.keys));
  });

  test('分裂はエンドレスの R21 (ボス2 の次) で、分裂が主役の手作りの配置として初登場する', () {
    final spec = endlessMode.roundAt(21);
    expect(spec.introKey, 'intro.splitter');
    expect(endlessContent.handcrafted[21], isNotNull);
    final ids = (spec.content as LayoutContent).rows.join().split('').toSet()
      ..remove('.');
    expect(ids, {'S', 'N'});
    // ステージ 2-4 が借りている R20 の配置は変えない
    expect(endlessContent.handcrafted[20], endlessContent.handcrafted[21]);
  });
}
