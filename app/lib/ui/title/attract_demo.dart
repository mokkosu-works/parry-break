import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/core.dart';
import '../../input/input_clock.dart';
import '../../l10n/app_localizations.dart';
import '../../render/block_painters.dart';
import '../../render/field_painter.dart';
import '../../render/fx.dart';
import '../../render/text_cache.dart';
import '../../services/content.dart';

/// タイトル画面の背景で流すデモプレイ (アーケードのアトラクトモード)。
///
/// 本物のコアを自動操作で動かす。ボールの落下点を予測してパドルを寄せ、当たる直前にパリィするので、
/// JUST・貫通・FEVER TIME・崩落が次々に起きる。音は出さない。
class AttractDemo extends ConsumerStatefulWidget {
  const AttractDemo({super.key, this.animate = true});

  /// false なら最初の 1 コマで止める (動きを減らす設定のとき)。
  final bool animate;

  @override
  ConsumerState<AttractDemo> createState() => _AttractDemoState();
}

class _AttractDemoState extends ConsumerState<AttractDemo> with SingleTickerProviderStateMixin {
  /// 見栄えのするラウンド (要石・爆薬・砲台・鏡面が揃うもの) を順に流す。
  static const _rounds = [23, 6, 26, 12, 21, 3, 17];
  static const _runSeconds = 32.0;

  late final Ticker _ticker;
  late final InputClock _clock = InputClock(source: ref.read(timeSourceProvider));
  final TextCache _text = TextCache();
  final ValueNotifier<int> _frame = ValueNotifier(0);
  final math.Random _rnd = math.Random();
  late World _world;
  late Session _session;
  late FxState _fx;
  FieldPainter? _painter;
  int _run = 0;
  double _startedAt = 0, _lastFrame = 0, _paddleX = Field.width / 2, _launchAt = 0;
  bool _armed = true;

  @override
  void initState() {
    super.initState();
    _newRun();
    _ticker = createTicker((_) => _tick());
    if (widget.animate) _ticker.start();
    // 動きを止める設定でも、少し進めた見栄えのする 1 コマを描く
    if (!widget.animate) {
      _launchAt = 1.2;
      for (var i = 0; i < 60 * 6; i++) {
        _pilot(i / 60);
        _world.step(World.dt);
        _onStep(World.dt);
      }
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    _text.clear();
    super.dispose();
  }

  void _newRun() {
    final content = ref.read(contentProvider);
    _world = World(mode: EndlessMode(content.endless), inputLag: 0)..start(fromRound: _rounds[_run++ % _rounds.length]);
    _fx = FxState(_world, reduceEffects: true);
    _session = Session(_world, onStep: _onStep);
    _startedAt = _clock.now;
    _launchAt = _startedAt + 1.4;
    _paddleX = _world.paddle.x;
    _painter = null;
  }

  void _onStep(double dt) {
    _world.drainEvents().forEach(_fx.handle);
    _fx.step(dt);
  }

  void _tick() {
    final now = _clock.now;
    final rdt = (now - _lastFrame).clamp(0.0, 0.1);
    _lastFrame = now;
    final w = _world;
    final over = w.phase == WorldPhase.over && w.overT > 1.2;
    if (over || now - _startedAt > _runSeconds) {
      setState(_newRun);
      return;
    }
    _pilot(now);
    _session.advance(now).forEach(_fx.handle);
    _fx.frame(rdt);
    _frame.value++;
  }

  /// 自動操作。
  void _pilot(double now) {
    final w = _world, b = w.ball, input = w.input;
    if (w.phase != WorldPhase.playing) return;
    if (b.attached) {
      if (w.countdown <= 0 && now >= _launchAt) {
        w.pressAction(now);
        _launchAt = now + 1;
      }
      return;
    }
    // 落下点を予測する (左右の壁での反射を含む)
    var target = b.x;
    if (b.vy > 0) {
      final t = (Field.paddleY - Field.ballR - b.y) / b.vy;
      final span = Field.width - Field.ballR * 2;
      var x = b.x - Field.ballR + b.vx * t;
      x = x % (span * 2);
      if (x < 0) x += span * 2;
      target = (x > span ? span * 2 - x : x) + Field.ballR;
    }
    // 受ける位置を少しずらして、打ち返す角度を変える
    target += math.sin(w.t * 0.9) * w.paddleWidth * 0.3;
    final maxStep = 1500 * World.dt;
    _paddleX += (target - _paddleX).clamp(-maxStep, maxStep);
    input
      ..useTarget = true
      ..targetX = _paddleX;

    // 当たる直前に押す (ボールと、パドルに向かう敵弾)
    var soon = false;
    if (b.vy > 0) {
      final ttc = (Field.paddleY - (b.y + Field.ballR)) / b.vy;
      soon = ttc > 0 && ttc < 0.016 && (b.x - w.paddle.x).abs() < w.paddleWidth / 2 + 8;
    } else {
      _armed = true;
    }
    for (final u in w.bullets) {
      if (!u.hostile || u.vy <= 0) continue;
      final ttc = (Field.paddleY - (u.y + u.r)) / u.vy;
      if (ttc > 0 && ttc < 0.016 && (u.x - w.paddle.x).abs() < w.paddleWidth / 2 + u.r) soon = true;
    }
    if (soon && _armed && _rnd.nextDouble() < 0.97) {
      w.pressAction(now);
      _armed = false;
    }
    if (!soon && b.vy < 0) _armed = true;
  }

  @override
  Widget build(BuildContext context) {
    _painter ??= FieldPainter(
      world: _world,
      fx: _fx,
      alpha: () => _session.alpha,
      time: () => _clock.now,
      text: _text,
      blockPainters: BlockPainterRegistry(),
      l10n: AppLocalizations.of(context),
      highQuality: true,
      repaint: _frame,
      attract: true,
    );
    return IgnorePointer(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: Field.width,
          height: Field.height,
          child: RepaintBoundary(child: CustomPaint(painter: _painter)),
        ),
      ),
    );
  }
}
