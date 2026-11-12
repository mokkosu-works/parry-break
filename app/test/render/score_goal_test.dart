// Issue #72: スコア目標の面で、HUD と開始の帯に目標スコアが出る。
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

/// [id] の面 (null ならエンドレス) を始め、帯が開ききるまで進めてから 1 枚描き、描いた文字を返す。
List<String> _draw(String? id, String lang, {double seconds = 0.6}) {
  final w = World(
    mode: id == null ? endlessMode : StageMode(_campaign.stage(id)!),
  )..start();
  final fx = FxState(w);
  for (var i = 0; i < (seconds * 60).round(); i++) {
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
    l10n: lookupAppLocalizations(Locale(lang)),
    highQuality: false,
    repaint: ValueNotifier(0),
  ).paint(Canvas(ui.PictureRecorder()), const Size(1200, 720));
  return text.drawn;
}

void main() {
  test('スコア目標の面では HUD に GOAL と目標スコアが出る', () {
    for (final (id, goal) in [
      ('1-7', '120,000'),
      ('2-8', '400,000'),
      ('3-5', '450,000'),
      ('5-7', '500,000'),
      ('6-6', '600,000'),
    ]) {
      final drawn = _draw(id, 'en');
      expect(drawn, containsAll(['GOAL', goal]), reason: id);
      expect(drawn, isNot(contains('CHAIN')), reason: id);
    }
  });

  test('スコア目標の面の開始の帯に目標の数字が出る', () {
    expect(_draw('1-7', 'ja'), contains('スコア 120,000 に到達すればクリア'));
    expect(_draw('6-6', 'en'), contains('REACH SCORE 600,000'));
  });

  test('全消し・生き残り・エンドレスの HUD は変わらない', () {
    final annihilate = _draw('1-1', 'en');
    expect(annihilate, contains('CHAIN'));
    expect(annihilate, isNot(contains('GOAL')));
    final survive = _draw('1-8', 'en');
    expect(survive, contains('SURVIVE'));
    expect(survive, isNot(contains('GOAL')));
    final endless = _draw(null, 'en');
    expect(endless, contains('CHAIN'));
    expect(endless, isNot(contains('GOAL')));
  });

  test('生き残りの面の帯は今のまま', () {
    final l = lookupAppLocalizations(const Locale('ja'));
    expect(_draw('1-8', 'ja'), contains(l.introSurvive));
  });
}
