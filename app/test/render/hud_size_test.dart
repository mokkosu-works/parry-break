// Issue #68: 盤面の倍率が小さい端末で、HUD のラベルと FEVER TIME の残り秒数を画面上で 11pt 以上にする。
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parry_break/core/core.dart';
import 'package:parry_break/input/touch_controls.dart';
import 'package:parry_break/l10n/app_localizations.dart';
import 'package:parry_break/render/block_painters.dart';
import 'package:parry_break/render/field_painter.dart';
import 'package:parry_break/render/fx.dart';
import 'package:parry_break/render/text_cache.dart';

import '../core/helpers.dart';

/// 描いた文字と、その盤面上の範囲を覚えておく TextCache。
class _RecordingText extends TextCache {
  final drawn = <({String text, double size, Rect rect})>[];

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
    final tp = get(text, size, color, weight: weight, family: family);
    final left = switch (align) {
      TextAlignH.left => x,
      TextAlignH.center => x - tp.width / 2,
      TextAlignH.right => x - tp.width,
    };
    drawn.add((
      text: text,
      size: size,
      rect: Rect.fromLTWH(left, y - tp.height / 2, tp.width, tp.height),
    ));
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

void _run(World w, FxState fx, double seconds, {void Function()? before}) {
  for (var i = 0; i < (seconds * 60).round(); i++) {
    before?.call();
    w.step(World.dt);
    w.drainEvents().forEach(fx.handle);
    fx.step(World.dt);
  }
  fx.frame(1);
}

/// HUD の状態ごとの World。
final _states = <String, World Function()>{
  'エンドレス (CHAIN)': () => World(mode: endlessMode)..start(),
  'FEVER TIME': () {
    final w = World(mode: endlessMode)..start(fromRound: 9);
    w.addCombo(1000);
    return w;
  },
  'ボス戦 (BOSS n / TIME)': () => World(mode: endlessMode)..start(fromRound: 20),
  '生き残り型 (SURVIVE)': () =>
      World(mode: StageMode(_campaign.stage('2-9')!))..start(),
  'スコア目標 (GOAL)': () =>
      World(mode: StageMode(_campaign.stage('6-6')!))..start(),
};

/// [w] を [size] の盤面に描き、HUD (盤面の上の帯) に描いた文字を返す。
List<({String text, double size, Rect rect})> _hud(World w, Size size) {
  final fx = FxState(w);
  _run(w, fx, 0.5);
  // 大きな数字でも重ならないかを見る
  w.score = 99999999;
  fx.dispScore = w.score.toDouble();
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
  ).paint(Canvas(ui.PictureRecorder()), size);
  return text.drawn.where((d) => d.rect.center.dy < Field.topY).toList();
}

const _labels = {'SCORE', 'ROUND', 'TIME', 'SURVIVE', 'GOAL', 'CHAIN'};
bool _isLabel(String s) =>
    _labels.contains(s) ||
    s.startsWith('BOSS ') ||
    s.startsWith('FEVER TIME ') ||
    s.startsWith('COMBO LV');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'DotGothic16',
    )..addFont(rootBundle.load('assets/fonts/DotGothic16-subset.ttf'))).load();
    await (FontLoader('Silkscreen')
          ..addFont(rootBundle.load('assets/fonts/Silkscreen-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Silkscreen-Bold.ttf')))
        .load();
  });

  // 844×390 (iPhone 14 相当)。ノッチのある端末のセーフエリアも見る
  for (final (name, pad) in [
    ('', EdgeInsets.zero),
    (' (ノッチ)', const EdgeInsets.fromLTRB(47, 0, 47, 21)),
  ]) {
    for (final rail in [false, true]) {
      final layout = FieldLayout.compute(const Size(844, 390), pad, rail: rail);
      final scheme = rail ? 'レール方式' : '領域方式';
      group(
        '844×390$name の$scheme (倍率 ${layout.scale.toStringAsFixed(3)})',
        () {
          _states.forEach((state, make) {
            test('$state: ラベルが画面上で 11pt 以上で、項目どうしが重ならない', () {
              final hud = _hud(make(), layout.field.size);
              final labels = hud.where((d) => _isLabel(d.text)).toList();
              expect(
                labels.length,
                greaterThanOrEqualTo(4),
                reason: '${hud.map((d) => d.text)}',
              );
              for (final l in labels) {
                expect(
                  l.size * layout.scale,
                  greaterThanOrEqualTo(11),
                  reason: l.text,
                );
              }
              final want = switch (state) {
                'FEVER TIME' => 'FEVER TIME ',
                'ボス戦 (BOSS n / TIME)' => 'BOSS ',
                '生き残り型 (SURVIVE)' => 'SURVIVE',
                'スコア目標 (GOAL)' => 'GOAL',
                _ => 'CHAIN',
              };
              expect(labels.map((l) => l.text), contains(startsWith(want)));
              // 文字どうし、文字とコンボのメーター・ポーズボタンが重ならない
              final boxes = [
                ...hud.map((d) => (d.text, d.rect)),
                ('combo meter', const Rect.fromLTWH(680, 24, 340, 24)),
                ('pause', FieldPainter.pauseButton),
              ];
              for (var i = 0; i < boxes.length; i++) {
                for (var j = i + 1; j < boxes.length; j++) {
                  final a = boxes[i], b = boxes[j];
                  if (a.$1 == b.$1) continue; // 影付きの文字の影
                  final o = a.$2.intersect(b.$2);
                  expect(
                    o.width > 0.5 && o.height > 0.5,
                    isFalse,
                    reason: '"${a.$1}" ${a.$2} と "${b.$1}" ${b.$2}',
                  );
                }
              }
            });
          });
        },
      );
    }
  }

  test('1280×800 などの大きい画面では、ラベルは今のまま 16', () {
    for (final rail in [false, true]) {
      final layout = FieldLayout.compute(
        const Size(1280, 800),
        EdgeInsets.zero,
        rail: rail,
      );
      for (final make in _states.values) {
        final hud = _hud(make(), layout.field.size);
        for (final l in hud.where((d) => _isLabel(d.text))) {
          expect(l.size, 16, reason: '${l.text} (rail: $rail)');
        }
      }
    }
  });

  test('ラベルの大きさは、倍率が小さいほど大きく、16〜24 に収める', () {
    expect(FieldPainter.hudLabelSize(1), 16);
    expect(FieldPainter.hudLabelSize(11 / 16), 16);
    expect(FieldPainter.hudLabelSize(0.52) * 0.52, greaterThanOrEqualTo(11));
    expect(FieldPainter.hudLabelSize(0.3), 24);
  });
}
