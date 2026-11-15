import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parry_break/core/core.dart';
import 'package:parry_break/l10n/app_localizations.dart';
import 'package:parry_break/render/block_painters.dart';
import 'package:parry_break/render/cosmetics.dart';
import 'package:parry_break/render/field_painter.dart';
import 'package:parry_break/render/fx.dart';
import 'package:parry_break/render/palette.dart';
import 'package:parry_break/render/text_cache.dart';
import 'package:parry_break/services/progress.dart';

import '../core/helpers.dart';

/// 見た目の解放 (design.md 9.9): 解放の表・解放された色の算出・描画で選んだ色が使われること・
/// コアの結果が色の選択で変わらないこと。
class _RecordingCanvas implements Canvas {
  final rects = <(Rect, Color)>[];

  @override
  void drawRect(Rect rect, Paint paint) => rects.add((rect, paint.color));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

bool same(Color a, Color b) => a.toARGB32() == b.toARGB32();

FieldPainter _painter(World w, FxState fx) => FieldPainter(
  world: w,
  fx: fx,
  alpha: () => 1,
  time: () => 1.0,
  text: TextCache(),
  blockPainters: BlockPainterRegistry(),
  l10n: lookupAppLocalizations(const Locale('en')),
  highQuality: false,
  repaint: ValueNotifier(0),
);

_RecordingCanvas _paint(FieldPainter p) {
  final c = _RecordingCanvas();
  p.paint(c, const Size(1200, 750));
  return c;
}

// ---- 色の離れ具合 (CIELAB の距離) ----

List<double> _lab(Color c) {
  double lin(double v) =>
      v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  final r = lin(c.r), g = lin(c.g), b = lin(c.b);
  final x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047;
  final y = 0.2126 * r + 0.7152 * g + 0.0722 * b;
  final z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883;
  double f(double t) =>
      t > 0.008856 ? math.pow(t, 1 / 3).toDouble() : 7.787 * t + 16 / 116;
  return [116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z))];
}

double _deltaE(Color a, Color b) {
  final p = _lab(a), q = _lab(b);
  return math.sqrt(
    math.pow(p[0] - q[0], 2) +
        math.pow(p[1] - q[1], 2) +
        math.pow(p[2] - q[2], 2),
  );
}

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

  group('解放の表', () {
    test('既定の色は Lv1 から使える (パドルは今までの青)', () {
      expect(Cosmetics.paddleDefault.unlockLevel, 1);
      expect(Cosmetics.paddleDefault.color, Dot.sky);
      expect(Cosmetics.trailDefault.unlockLevel, 1);
      expect(Cosmetics.paddles.first, Cosmetics.paddleDefault);
      expect(Cosmetics.trails.first, Cosmetics.trailDefault);
    });

    test('パドルも軌跡も 6 種で、id は種類の中で重ならない', () {
      for (final k in CosmeticKind.values) {
        final all = Cosmetics.of(k);
        expect(all.length, 6);
        expect(all.map((c) => c.id).toSet().length, all.length);
      }
    });

    test('解放のレベルは Lv2, 4, 6, 8, 10, 13, 16, 20, 25, 30 に 1 つずつ', () {
      final levels = [
        for (final k in CosmeticKind.values)
          for (final c in Cosmetics.of(k))
            if (c.unlockLevel > 1) c.unlockLevel,
      ]..sort();
      expect(levels, [2, 4, 6, 8, 10, 13, 16, 20, 25, 30]);
    });

    test('レベル → 使えるもの', () {
      List<String> usable(CosmeticKind k, int level) => [
        for (final c in Cosmetics.of(k))
          if (c.unlockedAt(level)) c.id,
      ];
      expect(usable(CosmeticKind.paddle, 1), ['sky']);
      expect(usable(CosmeticKind.trail, 1), ['standard']);
      expect(usable(CosmeticKind.paddle, 2), ['sky', 'cyan']);
      expect(usable(CosmeticKind.trail, 3), ['standard']);
      expect(usable(CosmeticKind.trail, 4), ['standard', 'cyan']);
      expect(usable(CosmeticKind.paddle, 10), ['sky', 'cyan', 'lime', 'teal']);
      expect(usable(CosmeticKind.paddle, 99).length, 6);
      expect(usable(CosmeticKind.trail, 29).length, 5);
      expect(usable(CosmeticKind.trail, 30).length, 6);
    });

    test('最初の数日 (1 日目で Lv3、5 日目で Lv7) で 2〜3 個手に入る', () {
      int owned(int level) => [
        for (final k in CosmeticKind.values)
          for (final c in Cosmetics.of(k))
            if (c.unlockLevel > 1 && c.unlockedAt(level)) c,
      ].length;
      expect(owned(3), 1);
      expect(owned(7), 3);
    });
  });

  group('resolve (選んだ色を実際に使う色にする)', () {
    test('解放済みの色はそのまま', () {
      expect(Cosmetics.resolve(CosmeticKind.paddle, 'cyan', 2).id, 'cyan');
      expect(Cosmetics.resolve(CosmeticKind.trail, 'leaf', 30).id, 'leaf');
    });

    test('まだ解放されていない色・表にない値・null は既定', () {
      expect(Cosmetics.resolve(CosmeticKind.paddle, 'cyan', 1).id, 'sky');
      expect(Cosmetics.resolve(CosmeticKind.trail, 'leaf', 29).id, 'standard');
      expect(Cosmetics.resolve(CosmeticKind.paddle, 'nope', 99).id, 'sky');
      expect(Cosmetics.resolve(CosmeticKind.trail, null, 99).id, 'standard');
      expect(Cosmetics.resolve(CosmeticKind.trail, 3, 99).id, 'standard');
    });
  });

  group('LevelGain から新しく解放されたもの', () {
    const c = LevelCurve.standard;
    LevelGain gain(int from, int to) =>
        LevelGain(xp: 1, before: c.of(c.xpAt(from)), after: c.of(c.xpAt(to)));
    List<String> ids(LevelGain g) => [
      for (final u in g.unlocked) '${u.kind.name}:${u.item.id}',
    ];

    test('上がらない・解放のないレベルでは空', () {
      expect(gain(5, 5).unlocked, isEmpty);
      expect(gain(10, 12).unlocked, isEmpty);
      expect(gain(30, 99).unlocked, isEmpty);
    });

    test('1 つ上がって解放されたら、その 1 つ', () {
      expect(ids(gain(1, 2)), ['paddle:cyan']);
      expect(ids(gain(3, 4)), ['trail:cyan']);
      expect(ids(gain(29, 30)), ['trail:leaf']);
    });

    test('何段か上がったときは、レベルの順に全部 (すでに持っているレベルは含めない)', () {
      expect(ids(gain(1, 6)), ['paddle:cyan', 'trail:cyan', 'paddle:lime']);
      expect(ids(gain(2, 4)), ['trail:cyan']);
      expect(gain(1, 99).unlocked.length, 10);
    });
  });

  group('どの色も、紛らわしい色から離れている', () {
    // 敵弾 (橙・赤)・アイテムのカプセル (7.10)・ブロックの赤・FEVER TIME の地・ボール・パリィ中の黄・
    // クールダウンの鋼色・盤面の地
    final confusing = <String, Color>{
      'bullet': Dot.bullet,
      'bulletRed': Dot.bulletRed,
      for (final e in Palette.items.entries) 'item ${e.key.name}': e.value,
      'brick': Dot.brick,
      'violet': Dot.violet,
      'peach': Dot.peach,
      'white': Dot.white,
      'steel': Dot.steel,
      'dim': Dot.dim,
      'odBg': Dot.odBg,
      'odHud': Dot.odHud,
      'ink': Dot.ink,
      'night': Dot.night,
      'edge': Dot.edge,
    };

    for (final k in CosmeticKind.values) {
      for (final c in Cosmetics.of(k)) {
        // 既定は今までの色 (パドルの青はアイテム WIDE と同じ。軌跡の標準はボールの色そのもの)
        if (c.unlockLevel == 1) continue;
        test('${k.name} ${c.name}: ΔE 30 以上離れている', () {
          for (final e in confusing.entries) {
            expect(
              _deltaE(c.color, e.value),
              greaterThanOrEqualTo(30),
              reason: '${c.name} が ${e.key} に近い',
            );
          }
        });
      }
    }

    test('同じ種類の色どうしも ΔE 20 以上離れている', () {
      for (final k in CosmeticKind.values) {
        final all = Cosmetics.of(k);
        for (var i = 0; i < all.length; i++) {
          for (var j = i + 1; j < all.length; j++) {
            expect(
              _deltaE(all[i].color, all[j].color),
              greaterThanOrEqualTo(20),
              reason: '${k.name}: ${all[i].name} と ${all[j].name}',
            );
          }
        }
      }
    });
  });

  group('描画', () {
    World scene({bool od = false}) {
      final w = testWorld(endlessMode);
      w.ball
        ..attached = false
        ..x = 600
        ..y = 500
        ..vy = -400;
      w.od = od;
      return w;
    }

    FxState withTrail(World w) {
      final fx = FxState(w);
      fx.trails[w.ball.id] = [
        for (var i = 0; i < 12; i++) Offset(600.0, 560.0 + i * 8),
      ];
      return fx;
    }

    int trailRects(_RecordingCanvas c, Color col) => c.rects
        .where((r) => same(r.$2, col) && r.$1.center.dx == 600)
        .where((r) => r.$1.center.dy >= 560)
        .length;

    test('パドル: 選んだ色で描き、選ばなければ今までの青', () {
      final w = scene();
      final p = _painter(w, FxState(w));
      bool hasPaddle(_RecordingCanvas c, Color col) => c.rects.any(
        (r) =>
            same(r.$2, col) &&
            r.$1.top == Field.paddleY &&
            r.$1.height == Field.paddleH + 2,
      );
      expect(hasPaddle(_paint(p), Dot.sky), isTrue);
      for (final c in Cosmetics.paddles) {
        p.paddleColor = c.color;
        final cv = _paint(p);
        expect(hasPaddle(cv, c.color), isTrue, reason: c.name);
        if (c.color != Dot.sky) {
          expect(hasPaddle(cv, Dot.sky), isFalse, reason: c.name);
        }
      }
    });

    test('パドル: パリィ中・クールダウン・スタンの色は、選んだ色にかかわらず今までどおり', () {
      final cyan = Cosmetics.paddles[1].color;
      bool has(World w, Color col) {
        final p = _painter(w, FxState(w))..paddleColor = cyan;
        return _paint(p).rects
            .any((r) => same(r.$2, col) && r.$1.top == Field.paddleY);
      }

      final stun = scene()..paddle.stun = 1;
      expect(has(stun, cyan), isFalse);
      final cool = scene()..parry.cooldownUntil = 99;
      expect(has(cool, Dot.steel), isTrue);
      expect(has(cool, cyan), isFalse);
      final active = scene()..parry.active = true;
      expect(has(active, Dot.mustard), isTrue);
    });

    test('軌跡: 選んだ色で描き、既定 (null) ならボールの色', () {
      final w = scene();
      final p = _painter(w, withTrail(w));
      final base = _paint(p);
      expect(trailRects(base, Dot.white), greaterThan(0));
      for (final c in Cosmetics.trails.skip(1)) {
        p.trailColor = c.color;
        final cv = _paint(p);
        expect(trailRects(cv, c.color), greaterThan(0), reason: c.name);
        // 古い (小さい) ものは暗い色になる
        expect(trailRects(cv, Dot.dark(c.color)), greaterThan(0));
        expect(trailRects(cv, Dot.white), 0, reason: '${c.name}: 軌跡は白でなくなる');
      }
    });

    test('軌跡: FEVER TIME・貫通中は選んだ色を使わず、状態の色のまま', () {
      final cyan = Cosmetics.trails[1].color;
      final fever = scene(od: true);
      final pf = _painter(fever, withTrail(fever))..trailColor = cyan;
      expect(trailRects(_paint(pf), cyan), 0);
      expect(trailRects(_paint(pf), Dot.dark(Dot.rose)), greaterThan(0));

      final pierce = scene()..ball.pierce = 2;
      final pp = _painter(pierce, withTrail(pierce))..trailColor = cyan;
      expect(trailRects(_paint(pp), cyan), 0);
      expect(trailRects(_paint(pp), Dot.mustard), greaterThan(0));
    });

    test('「演出を控えめにする」でも、軌跡の色は選んだものになる', () {
      final w = scene();
      final fx = withTrail(w)..reduceEffects = true;
      final cyan = Cosmetics.trails[1].color;
      final p = _painter(w, fx)..trailColor = cyan;
      expect(trailRects(_paint(p), cyan), greaterThan(0));
    });

    test('ボール本体は選んだ軌跡の色に染まらない (弾・カプセルとの区別を保つ)', () {
      final w = scene();
      final lime = Cosmetics.trails[2].color;
      final p = _painter(w, FxState(w))..trailColor = lime;
      final cv = _paint(p);
      expect(
        cv.rects.where((r) => same(r.$2, lime) && r.$1.center.dx == 600),
        isEmpty,
      );
    });
  });

  group('コアの結果は色の選択で変わらない', () {
    ({int score, double x, double y, int parries, int steps}) play({
      FieldPainter Function(World, FxState)? painter,
      Color? paddle,
      Color? trail,
    }) {
      final w = testWorld(endlessMode);
      final fx = FxState(w);
      final p = painter?.call(w, fx);
      if (p != null) {
        p.paddleColor = paddle ?? p.paddleColor;
        p.trailColor = trail;
      }
      var steps = 0;
      run(
        w,
        8,
        before: () {
          steps++;
          // 同じ入力を毎回与える (入力はプレイヤーの手。色とは関係ない)
          w.paddle.x = 600 + 300 * math.sin(steps / 40);
          if (steps % 90 == 1) w.parry.active = false;
          if (p != null && steps % 4 == 0) _paint(p);
        },
      );
      return (
        score: w.score,
        x: w.ball.x,
        y: w.ball.y,
        parries: w.stats.parries,
        steps: steps,
      );
    }

    test('どの色を選んで描いても、同じ入力なら同じ結果 (描かない場合とも同じ)', () {
      final none = play();
      for (final pc in Cosmetics.paddles) {
        for (final tc in Cosmetics.trails) {
          final r = play(painter: _painter, paddle: pc.color, trail: tc.color);
          expect(r, none, reason: '${pc.name} / ${tc.name}');
        }
      }
    });

    test('パドルの当たり判定の幅は色で変わらない (World は色を知らない)', () {
      final w = testWorld(endlessMode);
      final before = (w.paddleWidth, w.paddle.x, w.tuning.paddleWidth);
      final p = _painter(w, FxState(w))
        ..paddleColor = Cosmetics.paddles.last.color;
      _paint(p);
      expect((w.paddleWidth, w.paddle.x, w.tuning.paddleWidth), before);
    });

    test('lib/core は見た目の色・設定を参照しない (DAILY の公平さ)', () {
      final offenders = <String>[];
      for (final f in Directory('lib/core').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final src = f.readAsStringSync();
        if (RegExp(r'cosmetics|paddleColor|trailColor|services/settings')
            .hasMatch(src)) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty);
    });
  });
}
