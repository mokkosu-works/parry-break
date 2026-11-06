import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// 日本語のドット文字 (DotGothic16 のサブセット) に、アプリが日本語で出す文字が
/// すべて入っていることを確かめる。落ちたら tools/subset_jp_font.sh で作り直す。
void main() {
  test('app_ja.arb とステージの JSON の文字が、すべて DotGothic16 のサブセットにある', () {
    final cmap = _readCmap(File('assets/fonts/DotGothic16-subset.ttf').readAsBytesSync());

    final files = <File>[
      File('lib/l10n/app_ja.arb'),
      ...Directory('assets/stages').listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList()
        ..sort((a, b) => a.path.compareTo(b.path)),
    ];
    expect(files.length, greaterThan(1));

    final missing = <String, Set<String>>{};
    for (final f in files) {
      for (final s in _strings(jsonDecode(f.readAsStringSync()))) {
        for (final r in s.runes) {
          if (r < 0x80 || cmap.contains(r)) continue;
          missing.putIfAbsent(f.path, () => <String>{}).add(String.fromCharCode(r));
        }
      }
    }
    expect(
      missing,
      isEmpty,
      reason: 'DotGothic16-subset.ttf にない文字がある。tools/subset_jp_font.sh で作り直す:\n'
          '${missing.entries.map((e) => '  ${e.key}: ${e.value.join()}').join('\n')}',
    );
  });
}

/// JSON の中の文字列 (値。キーも含める) をすべて集める。
Iterable<String> _strings(Object? v) sync* {
  if (v is String) {
    yield v;
  } else if (v is List) {
    for (final e in v) {
      yield* _strings(e);
    }
  } else if (v is Map) {
    for (final e in v.entries) {
      yield e.key as String;
      yield* _strings(e.value);
    }
  }
}

/// TrueType の cmap (Windows Unicode BMP, format 4) から、グリフのある文字の集合を作る。
Set<int> _readCmap(Uint8List bytes) {
  final d = ByteData.sublistView(bytes);
  final numTables = d.getUint16(4);
  int? cmapOff;
  for (var i = 0; i < numTables; i++) {
    final rec = 12 + i * 16;
    if (ascii.decode(bytes.sublist(rec, rec + 4)) == 'cmap') cmapOff = d.getUint32(rec + 8);
  }
  if (cmapOff == null) throw StateError('cmap がない');

  final n = d.getUint16(cmapOff + 2);
  int? sub;
  for (var i = 0; i < n; i++) {
    final rec = cmapOff + 4 + i * 8;
    final platform = d.getUint16(rec), encoding = d.getUint16(rec + 2);
    final off = cmapOff + d.getUint32(rec + 4);
    if (d.getUint16(off) != 4) continue;
    if ((platform == 3 && encoding == 1) || platform == 0) sub = off;
  }
  if (sub == null) throw StateError('format 4 の cmap がない');

  final segX2 = d.getUint16(sub + 6);
  final ends = sub + 14;
  final starts = ends + segX2 + 2;
  final deltas = starts + segX2;
  final ranges = deltas + segX2;
  final out = <int>{};
  for (var s = 0; s < segX2 ~/ 2; s++) {
    final end = d.getUint16(ends + s * 2);
    final start = d.getUint16(starts + s * 2);
    final delta = d.getUint16(deltas + s * 2);
    final rangeAddr = ranges + s * 2;
    final rangeOffset = d.getUint16(rangeAddr);
    for (var c = start; c <= end && c != 0xFFFF; c++) {
      int glyph;
      if (rangeOffset == 0) {
        glyph = (c + delta) & 0xFFFF;
      } else {
        final g = d.getUint16(rangeAddr + rangeOffset + (c - start) * 2);
        glyph = g == 0 ? 0 : (g + delta) & 0xFFFF;
      }
      if (glyph != 0) out.add(c);
    }
  }
  return out;
}
