import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 翻訳ファイル (app_ja.arb / app_en.arb) に、画面のコードから使われないキーがないことを確かめる (#146)。
///
/// 使っているかは、`lib/` (生成物の `lib/l10n/` を除く) に `l.<キー>`・`l10n.<キー>`・
/// `AppLocalizations.of(context).<キー>` の形の参照があるかで見る。テストからの参照は数えない。
/// 別の変数名で受けて落ちたときは、`l` か `l10n` に揃えるか、下の [_receiver] に足す。
void main() {
  Map<String, Object?> arb(String lang) =>
      jsonDecode(File('lib/l10n/app_$lang.arb').readAsStringSync())
          as Map<String, Object?>;
  Iterable<String> keys(Map<String, Object?> m) =>
      m.keys.where((k) => !k.startsWith('@'));

  test('app_ja.arb と app_en.arb のキーが同じ', () {
    expect(keys(arb('en')).toSet(), keys(arb('ja')).toSet());
  });

  test('翻訳ファイルのキーは、どれも lib/ のコードから使われている', () {
    final src = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where(
          (f) =>
              f.path.endsWith('.dart') &&
              !f.path.replaceAll(r'\', '/').contains('lib/l10n/'),
        )
        .map((f) => f.readAsStringSync())
        .join('\n');

    final unused = [
      for (final k in keys(arb('ja')))
        if (!RegExp('$_receiver\\s*\\.\\s*$k\\b').hasMatch(src)) k,
    ];
    expect(
      unused,
      isEmpty,
      reason: 'どこからも使われていないキー。使わないなら両方の .arb から消す: ${unused.join(', ')}',
    );
  });
}

/// 翻訳を受ける式: 変数 `l` / `l10n`、または `AppLocalizations.of(...)`。
const _receiver = r'(?:\bl|\bl10n|AppLocalizations\.of\([^)]*\))';
