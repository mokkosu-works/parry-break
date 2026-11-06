import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parry_break/l10n/app_localizations.dart';
import 'package:parry_break/render/field_painter.dart';

import '../core/block_intro_test.dart' show blockIntros;

/// JSON の中の `"intro": "..."` をすべて集める。
Set<String> _introKeys(Object? j) => switch (j) {
      {'intro': final String k} => {k, ...(j as Map).values.expand(_introKeys)},
      final Map<Object?, Object?> m => m.values.expand(_introKeys).toSet(),
      final List<Object?> l => l.expand(_introKeys).toSet(),
      _ => const {},
    };

void main() {
  final ja = lookupAppLocalizations(const Locale('ja')), en = lookupAppLocalizations(const Locale('en'));

  test('ステージとエンドレスで使う説明のキーと、ブロックの説明のキーは、日英どちらでも文言を引ける', () {
    final keys = {
      for (final f in ['assets/stages/campaign.json', 'assets/stages/endless.json'])
        ..._introKeys(jsonDecode(File(f).readAsStringSync())),
      ...blockIntros.values,
      'intro.loop',
    };
    for (final k in keys) {
      expect(introText(ja, k), isNotEmpty, reason: 'ja: $k');
      expect(introText(en, k), isNotEmpty, reason: 'en: $k');
    }
    expect(introText(ja, 'intro.unknown'), isNull);
    expect(introText(ja, null), isNull);
  });

  test('破壊不可ブロックの説明は、全消しに数えないことと FEVER TIME 中だけ壊せることを書く', () {
    expect(introText(ja, 'intro.wall'), ja.introWall);
    expect(ja.introWall, allOf(contains('壊せない'), contains('全消し'), contains('FEVER TIME')));
    expect(en.introWall, allOf(contains('UNBREAKABLE'), contains('CLEAR'), contains('FEVER TIME')));
  });

  test('鏡の説明に、貫通弾でしか壊れないことを書く', () {
    expect(ja.introMirror, contains('貫通弾でしか壊れない'));
    expect(en.introMirror, contains('ONLY PIERCE BREAKS IT'));
  });

  test('周回の説明は周回数を入れる', () {
    expect(introText(en, 'intro.loop', loop: 3), en.introLoop('3'));
  });
}
