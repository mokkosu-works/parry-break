import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parry_break/core/core.dart';
import 'package:parry_break/l10n/app_localizations.dart';
import 'package:parry_break/render/block_painters.dart';
import 'package:parry_break/render/field_painter.dart';
import 'package:parry_break/render/fx.dart';
import 'package:parry_break/render/palette.dart';
import 'package:parry_break/render/text_cache.dart';

import '../core/helpers.dart';

/// 盤面の描画を、さまざまな状態 (FEVER TIME、ボス、崩落、ラウンドクリア) で行う。
/// 例外が出ないことを確かめ、`--dart-define=screenshots=true --update-goldens` で画面写真を書き出す。
const _shots = bool.fromEnvironment('screenshots');

Future<void> _paint(
  WidgetTester tester,
  World w,
  FxState fx,
  String name,
) async {
  tester.view
    ..physicalSize = const Size(1200, 720)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final painter = FieldPainter(
    world: w,
    fx: fx,
    alpha: () => 1,
    time: () => 1.234,
    text: TextCache(),
    blockPainters: BlockPainterRegistry(),
    l10n: lookupAppLocalizations(const Locale('en')),
    highQuality: true,
    repaint: ValueNotifier(0),
  );
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: RepaintBoundary(
        child: CustomPaint(painter: painter, size: const Size(1200, 720)),
      ),
    ),
  );
  expect(tester.takeException(), isNull);
  if (_shots) {
    await expectLater(
      find.byType(RepaintBoundary).first,
      matchesGoldenFile('screenshots/$name.png'),
    );
  }
}

/// イベントを演出に流しながら進める。
void _run(World w, FxState fx, double seconds, {void Function()? before}) {
  for (var i = 0; i < (seconds * 60).round(); i++) {
    before?.call();
    w.step(World.dt);
    w.drainEvents().forEach(fx.handle);
    fx.step(World.dt);
  }
  fx.frame(1);
}

/// 描いた色 (文字は段落) ごとの回数を数える Canvas。
class _CountingCanvas implements Canvas {
  final counts = <Object, int>{};
  void _add(Object k) => counts[k] = (counts[k] ?? 0) + 1;

  @override
  void drawRect(Rect rect, Paint paint) => _add(paint.color);

  @override
  void drawRawPoints(PointMode pointMode, Float32List points, Paint paint) =>
      _add(paint.color);

  @override
  void drawParagraph(Paragraph paragraph, Offset offset) => _add(paragraph);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// 点滅しうるものをまとめて出した盤面 (砲台の予告・狙撃の照準・崩れる前のブロック・敵弾・
/// レーザーの予告・危険の表示・被弾で動けないパドル・ポップアップ・コールアウト)。
(World, FxState) _blinkScene({required bool reduceEffects}) {
  final w = testWorld(
    const SingleRoundMode(['NNNNTNNNNPNNNN', 'NNNNNNNNNNNNNN']),
  );
  final fx = FxState(w, reduceEffects: reduceEffects);
  for (final b in w.blocks) {
    if (b.type == 'T') b.telegraph = true;
    if (b.type == 'P') {
      b
        ..telegraph = true
        ..fireT = 0.1; // 照準が固定された
    }
  }
  final f = w.addBlock('N', 300, 200);
  w.blocks.remove(f);
  w.falling.add(PendingFall(f, 1, f.x, 10));
  w.fireBullet(500, 400, 1.2, 100);
  w.fireBullet(700, 400, 1.2, 100, red: true);
  w.fireLaser(900);
  w.lowest = Field.warnY - 10;
  w.paddle.stun = 1;
  fx.popup(400, 300, '+100', Dot.white, 16);
  fx.callouts.add(
    FxCallout(
      CalloutChannel.collapse,
      'COLLAPSE',
      '',
      Dot.white,
      32,
      hold: false,
    ),
  );
  return (w, fx);
}

/// 時刻を 1/60 秒ずつ進めて 2 秒描き、色 (文字は段落) ごとに、描いた回数が変わった回数を数える。
/// 戻り値は、いちばん速く点滅したものの 1 秒あたりの点滅の回数 (点いて消えるで 1 回)。
double _fastestBlink(World w, FxState fx, {void Function(int frame)? before}) {
  var t = 1.0;
  final painter = FieldPainter(
    world: w,
    fx: fx,
    alpha: () => 1,
    time: () => t,
    text: TextCache(),
    blockPainters: BlockPainterRegistry(),
    l10n: lookupAppLocalizations(const Locale('en')),
    highQuality: false,
    repaint: ValueNotifier(0),
  );
  const frames = 120;
  final history = <Map<Object, int>>[];
  for (var i = 0; i < frames; i++) {
    t = 1.0 + i / 60;
    // ポップアップ・コールアウトは自分の経過時間で点滅するので、それも進める
    for (final p in fx.popups) {
      p.t = 0.6 + i / 60;
    }
    for (final c in fx.callouts) {
      c.t = FxCallout.life - 0.29 + i / 600;
    }
    before?.call(i);
    final c = _CountingCanvas();
    painter.paint(c, const Size(1200, 720));
    history.add(c.counts);
  }
  final keys = {for (final h in history) ...h.keys}
    ..remove(const Color(0x40FFFFFF)); // 支えの脈動 (流れる光)
  var most = 0;
  for (final k in keys) {
    var n = 0;
    for (var i = 1; i < frames; i++) {
      if ((history[i][k] ?? 0) != (history[i - 1][k] ?? 0)) n++;
    }
    most = math.max(most, n);
  }
  return most / 2 / (frames / 60);
}

void main() {
  setUpAll(() async {
    await (FontLoader(
      'DotGothic16',
    )..addFont(rootBundle.load('assets/fonts/DotGothic16-subset.ttf'))).load();
    await (FontLoader('Silkscreen')
          ..addFont(rootBundle.load('assets/fonts/Silkscreen-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Silkscreen-Bold.ttf')))
        .load();
  });

  testWidgets('FEVER TIME 中のボス戦 (フェーズ3・レーザー・分身弾・弾幕)', (tester) async {
    final w = World(mode: endlessMode)..start(fromRound: 20);
    final fx = FxState(w);
    _run(w, fx, 1.2);
    final core = w.blocks.firstWhere((b) => b.type == bossCoreId);
    for (var i = 0; i < 9; i++) {
      w.damageCore(core, 1); // フェーズ 3 まで進める
    }
    w.ball
      ..attached = false
      ..vy = -500
      ..vx = 120;
    _run(w, fx, 3, before: autopilot(w));
    w.addCombo(1000);
    w.phantoms.add(
      Ball(
        x: 300,
        y: 400,
        vx: 200,
        vy: -300,
        speed: 360,
        phantom: true,
        life: 5,
      ),
    );
    w.fireLaser(w.paddle.x + 200);
    _run(w, fx, 0.3, before: autopilot(w));
    expect(w.od || w.phase != WorldPhase.playing, isTrue);
    await _paint(tester, w, fx, 'p1_boss_fever_time');
  });

  testWidgets('崩落の最中 (ひび・落下・コールアウト・瓦礫)', (tester) async {
    final w = World(mode: endlessMode)..start(fromRound: 23);
    final fx = FxState(w);
    _run(w, fx, 1.2);
    final keystones = w.blocks.where((b) => b.type == 'K').toList();
    for (final k in keystones) {
      w.destroyBlock(k, DestroyCause.pierce);
    }
    _run(w, fx, 0.35);
    expect(w.stats.bestCollapse + w.cascade.n, greaterThan(0));
    await _paint(tester, w, fx, 'p2_collapse');
  });

  testWidgets('ラウンドクリアの画面', (tester) async {
    final w = World(mode: endlessMode)..start(fromRound: 6);
    final fx = FxState(w);
    _run(w, fx, 1.2);
    for (final b in w.blocks.where((b) => b.behavior.clearable).toList()) {
      w.destroyBlock(b, DestroyCause.blast);
    }
    _run(w, fx, 1.6);
    expect(w.phase, WorldPhase.clearing);
    await _paint(tester, w, fx, 'p3_round_clear');
  });

  // Issue #252: アイテム (落下中のカプセル・効いている効果・GUARD の防壁・SHOT の弾・取ったときの名前)
  (World, FxState) itemScene({bool reduceEffects = false}) {
    final w = World(mode: endlessMode)..start(fromRound: 3);
    final fx = FxState(w, reduceEffects: reduceEffects);
    _run(w, fx, 1.2);
    w.items
      ..add(Item(ItemKind.wide, 300, 400))
      ..add(Item(ItemKind.guard, 800, 500));
    w.effects
      ..wide = 10
      ..shot = 2.5
      ..blast = 2
      ..guard = 5
      ..cool = 7;
    w.bullets.add(
      Bullet(x: 600, y: 500, vx: 0, vy: -900, kind: BulletKind.shot)
        ..hostile = false,
    );
    for (final e in [
      ItemTaken(
        kind: ItemKind.multi,
        grade: ParryGrade.just,
        x: w.paddle.x,
        paddleX: w.paddle.x,
        points: 500,
      ),
      ItemSpawned(w.items.first),
      const GuardBounced(600),
    ]) {
      fx.handle(e);
    }
    return (w, fx);
  }

  testWidgets('アイテム: カプセル・効果の一覧・防壁・SHOT の弾・取ったときの名前', (tester) async {
    final (w, fx) = itemScene();
    expect(fx.popups.map((p) => p.text), contains('MULTI+'));
    expect(fx.flash, greaterThan(0), reason: 'パリィ取得は光る');
    await _paint(tester, w, fx, 'p4_items');
    expect(w.paddleWidth, closeTo(168, 1e-9));
  });

  testWidgets('アイテム: 演出を控えめにするとパリィ取得でも光らせず、1 秒に 3 回を超えて点滅しない', (tester) async {
    final (w, fx) = itemScene(reduceEffects: true);
    expect(fx.flash, 0);
    expect(fx.popups.map((p) => p.text), contains('MULTI+'));
    fx.popups.clear();
    w.ball.attached = false; // TAP の点滅を出さない
    expect(_fastestBlink(w, fx), lessThanOrEqualTo(3));
    final normal = FxState(w)
      ..handle(
        const ItemTaken(
          kind: ItemKind.wide,
          grade: null,
          x: 0,
          paddleX: 600,
          points: 0,
        ),
      );
    expect(normal.popups.single.text, 'WIDE');
    expect(normal.flash, 0, reason: '通常取得は光らせない');
  });

  group('演出を控えめにする (#102)', () {
    testWidgets('OFF では速い点滅がある (このテストが点滅を見分けられること)', (tester) async {
      final (w, fx) = _blinkScene(reduceEffects: false);
      expect(w.isDanger, isTrue);
      expect(_fastestBlink(w, fx), greaterThan(3));
    });

    testWidgets('ON では 1 秒に 3 回を超えて点滅しない', (tester) async {
      final (w, fx) = _blinkScene(reduceEffects: true);
      expect(w.isDanger, isTrue);
      expect(_fastestBlink(w, fx), lessThanOrEqualTo(3));
    });

    testWidgets('ON では被弾後の無敵のパドルも 1 秒に 3 回を超えて点滅しない', (tester) async {
      final (w, fx) = _blinkScene(reduceEffects: true);
      w.paddle
        ..stun = 0
        ..invuln = 5;
      expect(_fastestBlink(w, fx), lessThanOrEqualTo(3));
      fx.reduceEffects = false;
      expect(_fastestBlink(w, fx), greaterThan(3));
    });

    test('ON でも、予告中の砲台は点けたままで見分けられる', () {
      Color drawn(bool telegraph, double time) {
        final w = testWorld(const SingleRoundMode(['NNNNNNTNNNNNNN']));
        final b = w.blocks.firstWhere((b) => b.type == 'T')
          ..telegraph = telegraph;
        final c = _CountingCanvas();
        final ctx = BlockPaintContext(
          c,
          TextCache(),
          time,
          (_) => Palette.blocks['T']!,
          calm: true,
        );
        paintStandardBlock(ctx, b, const Rect.fromLTWH(0, 0, 60, 24));
        return c.counts.keys.whereType<Color>().first;
      }

      for (final t in [0.0, 1 / 32, 1 / 16, 0.1, 0.5]) {
        expect(drawn(true, t), isNot(drawn(false, t)));
        expect(drawn(true, t), drawn(true, 0));
      }
    });
  });
}
