import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ricochet/core/core.dart';
import 'package:ricochet/l10n/app_localizations.dart';
import 'package:ricochet/render/block_painters.dart';
import 'package:ricochet/render/field_painter.dart';
import 'package:ricochet/render/fx.dart';
import 'package:ricochet/render/text_cache.dart';

import '../core/helpers.dart';

/// 盤面の描画を、さまざまな状態 (OVERDRIVE、ボス、崩落、ウェーブクリア) で行う。
/// 例外が出ないことを確かめ、`--dart-define=screenshots=true --update-goldens` で画面写真を書き出す。
const _shots = bool.fromEnvironment('screenshots');

Future<void> _paint(WidgetTester tester, World w, FxState fx, String name) async {
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
    glow: null,
    blockPainters: BlockPainterRegistry(),
    l10n: lookupAppLocalizations(const Locale('en')),
    highQuality: true,
    repaint: ValueNotifier(0),
  );
  await tester.pumpWidget(Directionality(
    textDirection: TextDirection.ltr,
    child: RepaintBoundary(child: CustomPaint(painter: painter, size: const Size(1200, 720))),
  ));
  expect(tester.takeException(), isNull);
  if (_shots) await expectLater(find.byType(RepaintBoundary).first, matchesGoldenFile('screenshots/$name.png'));
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

void main() {
  setUpAll(() async {
    await (FontLoader('Orbitron')..addFont(rootBundle.load('assets/fonts/Orbitron.ttf'))).load();
  });

  testWidgets('OVERDRIVE 中のボス戦 (フェーズ3・レーザー・分身弾・弾幕)', (tester) async {
    final w = World(mode: endlessMode)..start(fromWave: 20);
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
    w.addHeat(1000);
    w.phantoms.add(Ball(x: 300, y: 400, vx: 200, vy: -300, speed: 360, phantom: true, life: 5));
    w.fireLaser(w.paddle.x + 200);
    _run(w, fx, 0.3, before: autopilot(w));
    expect(w.od || w.phase != WorldPhase.playing, isTrue);
    await _paint(tester, w, fx, 'p1_boss_overdrive');
  });

  testWidgets('崩落の最中 (ひび・落下・コールアウト・瓦礫)', (tester) async {
    final w = World(mode: endlessMode)..start(fromWave: 23);
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

  testWidgets('ウェーブクリアの画面', (tester) async {
    final w = World(mode: endlessMode)..start(fromWave: 6);
    final fx = FxState(w);
    _run(w, fx, 1.2);
    for (final b in w.blocks.where((b) => b.behavior.clearable).toList()) {
      w.destroyBlock(b, DestroyCause.blast);
    }
    _run(w, fx, 1.6);
    expect(w.phase, WorldPhase.clearing);
    await _paint(tester, w, fx, 'p3_wave_clear');
  });
}
