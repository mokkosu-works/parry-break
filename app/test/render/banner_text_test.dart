// Issue #149: 開始の帯の説明文を、スマホでも画面上で 11pt 以上にし、説明のある帯は読める長さだけ出す。
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
import 'package:parry_break/render/palette.dart';
import 'package:parry_break/render/text_cache.dart';

import '../core/helpers.dart';

/// 描いた文字と大きさ・幅を覚えておく TextCache。
class _RecordingText extends TextCache {
  final drawn = <({String text, double size, double width})>[];

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
    drawn.add((
      text: text,
      size: size,
      width: get(text, size, color, weight: weight, family: family).width,
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

FieldPainter _painter(World w, FxState fx, TextCache text, String locale) =>
    FieldPainter(
      world: w,
      fx: fx,
      alpha: () => 1,
      time: () => 1,
      text: text,
      blockPainters: BlockPainterRegistry(),
      l10n: lookupAppLocalizations(Locale(locale)),
      highQuality: false,
      repaint: ValueNotifier(0),
    );

/// エンドレスの [round] ラウンド目を始め、毎ステップ描きながら [seconds] 秒進める。
/// 帯が出ていた長さ (秒) と、最後に帯が出ていたときに描いた文字を返す。
({double shown, List<({String text, double size, double width})> drawn}) _play(
  int round, {
  Size size = const Size(1200, 720),
  String locale = 'ja',
  double seconds = 7,
}) {
  final w = World(mode: endlessMode)..start(fromRound: round);
  final fx = FxState(w);
  var shown = 0.0;
  var drawn = <({String text, double size, double width})>[];
  for (var i = 0; i < (seconds * 60).round(); i++) {
    // 開始の帯の間はボールを出さない (出すと別の帯が出ることがある)
    w.step(World.dt);
    w.drainEvents().forEach(fx.handle);
    fx.step(World.dt);
    if (fx.banner == null) continue;
    shown = fx.banner!.t;
    final text = _RecordingText();
    _painter(w, fx, text, locale).paint(Canvas(ui.PictureRecorder()), size);
    if (fx.banner!.open >= 1) drawn = text.drawn;
  }
  return (shown: shown, drawn: drawn);
}

/// 説明の翻訳キー。
const _introKeys = [
  'intro.keystone',
  'intro.turret',
  'intro.explosive',
  'intro.reflector',
  'intro.magnet',
  'intro.splitter', //
  'intro.mirror',
  'intro.wall',
  'intro.spread',
  'intro.gatling',
  'intro.ring',
  'intro.spiral',
  'intro.sniper',
  'intro.loop',
  'intro.parry',
  'intro.pierce',
  'intro.feverTime',
  'intro.survive',
  'intro.score',
];

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

  final ja = lookupAppLocalizations(const Locale('ja'));

  for (final rail in [false, true]) {
    final layout = FieldLayout.compute(
      const Size(844, 390),
      EdgeInsets.zero,
      rail: rail,
    );
    test(
      '844×390 の${rail ? 'レール' : '領域'}方式 (倍率 ${layout.scale.toStringAsFixed(3)}): 帯の説明文が画面上で 11pt 以上',
      () {
        final drawn = _play(6, size: layout.field.size).drawn;
        final sub = drawn.where((d) => d.text == ja.introExplosive).toList();
        expect(sub, hasLength(1), reason: '${drawn.map((d) => d.text)}');
        expect(sub.single.size * layout.scale, greaterThanOrEqualTo(11));
      },
    );
  }

  test('1280×800 などの大きい画面では、帯の説明文の大きさは今のまま 15', () {
    for (final rail in [false, true]) {
      final layout = FieldLayout.compute(
        const Size(1280, 800),
        EdgeInsets.zero,
        rail: rail,
      );
      expect(
        FieldPainter.bannerSubSize(layout.scale),
        15,
        reason: 'rail: $rail',
      );
    }
    final drawn = _play(6).drawn;
    expect(drawn.where((d) => d.text == ja.introExplosive).single.size, 15);
  });

  test('説明 (NEW: 爆薬) のある帯は、1.8 秒より長く出る', () {
    final shown = _play(6).shown;
    expect(shown, greaterThan(FxBanner.baseLife + 1));
    expect(shown, lessThanOrEqualTo(FxBanner.maxLife + World.dt));
  });

  test('説明のない帯は、今までどおり 1.8 秒で消える', () {
    final w = World(mode: endlessMode)..start(fromRound: 3);
    expect(w.round.introKey, isNull);
    expect(_play(3).shown, closeTo(FxBanner.baseLife, 2 * World.dt));
  });

  test('説明が長いほど長く出す (上限 ${FxBanner.maxLife} 秒)', () {
    expect(FxBanner.lifeFor('NEW: 要石'), FxBanner.baseLife);
    expect(FxBanner.lifeFor(ja.introExplosive), greaterThan(FxBanner.baseLife));
    expect(
      FxBanner.lifeFor(ja.introFeverTime),
      greaterThan(FxBanner.lifeFor(ja.introExplosive)),
    );
    expect(FxBanner.lifeFor('あ' * 200), FxBanner.maxLife);
  });

  test('説明がはみ出さない: 小さい端末の大きさでも、すべての説明が盤面の幅に収まるか折り返す', () {
    // ノッチのある 844×390 のレール方式がいちばん倍率が小さい
    final scale = FieldLayout.compute(
      const Size(844, 390),
      const EdgeInsets.fromLTRB(47, 0, 47, 21),
      rail: true,
    ).scale;
    final size = FieldPainter.bannerSubSize(scale);
    final text = TextCache();
    final w = World(mode: endlessMode)..start();
    for (final locale in ['ja', 'en']) {
      final l10n = lookupAppLocalizations(Locale(locale));
      final p = _painter(w, FxState(w), text, locale);
      for (final key in _introKeys) {
        for (final parryButton in [false, true]) {
          final s = introText(
            l10n,
            key,
            loop: 12,
            scoreTarget: 1200000,
            parryButton: parryButton,
          )!;
          final lines = p.wrapText(s, size, FieldPainter.bannerSubWidth);
          expect(lines.length, lessThanOrEqualTo(2), reason: '$locale $key');
          for (final l in lines) {
            expect(
              text.get(l, size, Dot.white, family: TextCache.jp).width,
              lessThanOrEqualTo(Field.width - 40),
              reason: '$locale $key: $l',
            );
          }
        }
      }
    }
  });

  test('盤面の幅に収まらない説明は、英語は空白で、日本語は字の間で折り返す', () {
    final w = World(mode: endlessMode)..start();
    final text = TextCache();
    final p = _painter(w, FxState(w), text, 'en');
    final en = p.wrapText(
      'CHAIN PERFECTS TO FILL COMBO FEVER TIME PIERCES EVERYTHING',
      24,
      300,
    );
    expect(en.length, greaterThan(1));
    expect(
      en.join(' '),
      'CHAIN PERFECTS TO FILL COMBO FEVER TIME PIERCES EVERYTHING',
    );
    for (final l in en) {
      expect(
        text.get(l, 24, Dot.white, family: TextCache.jp).width,
        lessThanOrEqualTo(300),
        reason: l,
      );
    }
    final jp = p.wrapText(ja.introFeverTime, 24, 300);
    expect(jp.length, greaterThan(1));
    expect(
      jp.join().replaceAll(' ', ''),
      ja.introFeverTime.replaceAll(' ', ''),
    );
  });
}
