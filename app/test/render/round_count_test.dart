// Issue #73: 連戦の面で、HUD と開始の帯に「いま / 全体」のラウンド数が出る。
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parry_break/core/core.dart';
import 'package:parry_break/l10n/app_localizations.dart';
import 'package:parry_break/render/block_painters.dart';
import 'package:parry_break/render/field_painter.dart';
import 'package:parry_break/render/fx.dart';
import 'package:parry_break/render/text_cache.dart';

import '../core/helpers.dart';

/// 描いた文字を覚えておく TextCache。
class _RecordingText extends TextCache {
  final drawn = <String>[];

  @override
  void draw(
    Canvas canvas,
    String text,
    double x,
    double y,
    double size,
    Color color, {
    TextAlignH align = TextAlignH.center,
    double weight = 700,
    String? family,
  }) {
    drawn.add(text);
    super.draw(
      canvas,
      text,
      x,
      y,
      size,
      color,
      align: align,
      weight: weight,
      family: family,
    );
  }
}

final _campaign = Campaign.fromJson(
  jsonDecode(File('assets/stages/campaign.json').readAsStringSync())
      as Map<String, Object?>,
  endlessContent,
);

/// [id] の面 (null ならエンドレス) を [round] ラウンド目から始め、帯が開ききるまで進めてから 1 枚描き、描いた文字を返す。
List<String> _draw(String? id, {int round = 1}) {
  final w = World(
    mode: id == null ? endlessMode : StageMode(_campaign.stage(id)!),
  )..start(fromRound: round);
  final fx = FxState(w);
  for (var i = 0; i < 36; i++) {
    w.step(World.dt);
    w.drainEvents().forEach(fx.handle);
    fx.step(World.dt);
  }
  fx.frame(1);
  final text = _RecordingText();
  FieldPainter(
    world: w,
    fx: fx,
    alpha: () => 1,
    time: () => 1,
    text: text,
    blockPainters: BlockPainterRegistry(),
    l10n: lookupAppLocalizations(const Locale('en')),
    highQuality: false,
    repaint: ValueNotifier(0),
  ).paint(Canvas(ui.PictureRecorder()), const Size(1200, 720));
  return text.drawn;
}

void main() {
  test('2-2 の 1 ラウンド目は HUD に STAGE 2-2 と 1/2、帯に STAGE 2-2  1/2 が出る', () {
    expect(_draw('2-2'), containsAll(['STAGE 2-2', '1/2', 'STAGE 2-2  1/2']));
  });

  test('2-2 の 2 ラウンド目は 2/2 が出る', () {
    expect(_draw('2-2', round: 2), containsAll(['2/2', 'STAGE 2-2  2/2']));
  });

  test('3-9 / 6-9 は /3、4-9 / 5-9 は /2 で出る', () {
    for (final (id, total) in [
      ('3-9', 3),
      ('6-9', 3),
      ('4-9', 2),
      ('5-9', 2),
    ]) {
      expect(
        _draw(id),
        containsAll(['1/$total', 'STAGE $id  1/$total']),
        reason: id,
      );
    }
  });

  test('1 ラウンドだけの面は、ラウンドではなくステージの番号を出す', () {
    for (final id in ['1-1', '1-3']) {
      final drawn = _draw(id);
      expect(drawn, containsAll(['STAGE', id, 'STAGE $id']), reason: id);
      expect(drawn, isNot(contains('ROUND 1')), reason: id);
      expect(drawn.where((s) => s.contains('/')), isEmpty, reason: id);
    }
  });

  test('エンドレスは今のまま ROUND を出す', () {
    final drawn = _draw(null);
    expect(drawn, containsAll(['ROUND', '1', 'ROUND 1']));
    expect(drawn.where((s) => s.contains('/')), isEmpty);
  });
}
