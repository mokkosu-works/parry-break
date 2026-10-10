import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/core.dart';
import '../game/game_controller.dart';
import '../render/palette.dart';
import '../render/pixel.dart';
import '../services/settings.dart';
import '../ui/widgets.dart';
import '../ui/pixel_icons.dart';

/// 盤面と左右の余白の配置。盤面 (1200×720) はセーフエリアの中で、左右に親指の操作エリアを残して最大化する。
class FieldLayout {
  FieldLayout._(this.screen, this.field, this.scale);

  factory FieldLayout.compute(Size size, EdgeInsets pad) {
    final avail = Rect.fromLTRB(pad.left, pad.top, size.width - pad.right, size.height - pad.bottom);
    final side = (avail.width * 0.13).clamp(80.0, 150.0);
    final scale = math.max(0.1, math.min((avail.width - side * 2) / Field.width, avail.height / Field.height));
    final field = Rect.fromCenter(center: avail.center, width: Field.width * scale, height: Field.height * scale);
    return FieldLayout._(size, field, scale);
  }

  final Size screen;
  final Rect field;

  /// 盤面の 1 単位あたりの画面のピクセル数。
  final double scale;

  Rect get left => Rect.fromLTRB(0, 0, field.left, screen.height);
  Rect get right => Rect.fromLTRB(field.right, 0, screen.width, screen.height);
}

/// 画面全体のタッチ入力 (領域方式): 左半分のドラッグで移動、右半分のタップで発射・パリィ。
/// レール方式のときは、盤面のドラッグでも移動できるようにする (左の余白は [RailControl] が受ける)。
class TouchInput extends StatefulWidget {
  const TouchInput({super.key, required this.controller, required this.layout, required this.settings});
  final GameController controller;
  final FieldLayout layout;
  final Settings settings;

  @override
  State<TouchInput> createState() => _TouchInputState();
}

class _TouchInputState extends State<TouchInput> {
  int? _drag;
  double _lastX = 0;

  World get _w => widget.controller.world;

  void _down(PointerDownEvent e) {
    final zones = widget.settings.controls == ControlScheme.zones;
    if (zones && e.position.dx >= widget.layout.screen.width / 2) {
      widget.controller.press(e.timeStamp);
      return;
    }
    if (_drag != null) return;
    _drag = e.pointer;
    _lastX = e.position.dx;
    _w.input
      ..useTarget = true
      ..targetX = _w.paddle.x;
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _drag) return;
    final dx = e.position.dx - _lastX;
    _lastX = e.position.dx;
    final zones = widget.settings.controls == ControlScheme.zones;
    // 領域方式: 指の移動量 × 感度。レール方式で盤面をなぞったときは指に追従させる
    final k = zones ? widget.settings.sensitivity / widget.layout.scale : 1 / widget.layout.scale;
    final pw = _w.paddleWidth;
    _w.input
      ..useTarget = true
      ..targetX = clampD(_w.input.targetX + dx * k, pw / 2, Field.width - pw / 2);
  }

  void _up(PointerEvent e) {
    if (e.pointer == _drag) _drag = null;
  }

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _down,
        onPointerMove: _move,
        onPointerUp: _up,
        onPointerCancel: _up,
      );
}

/// レール方式の移動操作 (左の余白)。レールの端から端でパドルが盤面の端から端まで動く。
class RailControl extends StatefulWidget {
  const RailControl({super.key, required this.controller, required this.vertical});
  final GameController controller;
  final bool vertical;

  @override
  State<RailControl> createState() => _RailControlState();
}

class _RailControlState extends State<RailControl> {
  int? _drag;
  Offset _last = Offset.zero;
  double _travel = 200;

  World get _w => widget.controller.world;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) {
        if (_drag != null) return;
        _drag = e.pointer;
        _last = e.position;
        _w.input
          ..useTarget = true
          ..targetX = _w.paddle.x;
      },
      onPointerMove: (e) {
        if (e.pointer != _drag) return;
        final d = e.position - _last;
        _last = e.position;
        final pw = _w.paddleWidth;
        final delta = widget.vertical ? d.dy : d.dx;
        _w.input.targetX = clampD(_w.input.targetX + delta * (Field.width - pw) / _travel, pw / 2, Field.width - pw / 2);
      },
      onPointerUp: (e) => e.pointer == _drag ? _drag = null : null,
      onPointerCancel: (e) => e.pointer == _drag ? _drag = null : null,
      child: LayoutBuilder(builder: (context, c) {
        final railLen = widget.vertical ? math.min(240.0, c.maxHeight * 0.45) : c.maxWidth - 24;
        _travel = math.max(1, railLen - 20);
        return Align(
          alignment: widget.vertical ? Alignment.bottomCenter : const Alignment(0, 0.6),
          child: Padding(
            padding: EdgeInsets.only(bottom: widget.vertical ? c.maxHeight * 0.12 : 0),
            child: ValueListenableBuilder(
              valueListenable: widget.controller.frame,
              builder: (_, _, _) {
                final pw = _w.paddleWidth;
                final k = ((_w.paddle.x - pw / 2) / (Field.width - pw)).clamp(0.0, 1.0);
                return _Rail(length: railLen, vertical: widget.vertical, position: k);
              },
            ),
          ),
        );
      }),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({required this.length, required this.vertical, required this.position});
  final double length, position;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final w = vertical ? 22.0 : length, h = vertical ? length : 22.0;
    final pos = 10 + (length - 20) * position;
    return SizedBox(
      width: w,
      height: h,
      child: Stack(clipBehavior: Clip.none, children: [
        Container(
          decoration: BoxDecoration(color: Dot.night, border: Border.all(color: withAlpha(Dot.sky, 0.7), width: 3)),
        ),
        Positioned(
          left: vertical ? -3 : pos - 10,
          top: vertical ? pos - 10 : -3,
          child: SizedBox(
            width: vertical ? 28 : 20,
            height: vertical ? 20 : 28,
            child: const BevelBox(color: Dot.sky, child: SizedBox.expand()),
          ),
        ),
      ]),
    );
  }
}

/// 発射・パリィのボタン (レール方式では押せる。領域方式では右半分のタップの目安として表示だけする)。
class ParryButton extends StatelessWidget {
  const ParryButton({super.key, required this.controller, required this.interactive, this.size = 72});
  final GameController controller;
  final bool interactive;
  final double size;

  @override
  Widget build(BuildContext context) {
    final button = ValueListenableBuilder(
      valueListenable: controller.frame,
      builder: (_, _, _) {
        final active = controller.world.parry.active;
        final c = active ? Palette.yellow : Palette.accent;
        return Opacity(
          opacity: interactive ? 1 : 0.5,
          child: CustomPaint(
            size: Size.square(size),
            painter: _ParryButtonPainter(c, pressed: active),
            child: SizedBox.square(
              dimension: size,
              child: Center(
                child: Padding(
                  padding: EdgeInsets.only(top: active ? size / 18 : 0),
                  child: Text('PARRY', style: pixelFont(size * 0.16, color: Dot.ink)),
                ),
              ),
            ),
          ),
        );
      },
    );
    if (!interactive) return IgnorePointer(child: button);
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) => controller.press(e.timeStamp),
      child: button,
    );
  }
}

/// ドットで描いた丸いボタン。押している間は影の分だけ沈む。
class _ParryButtonPainter extends CustomPainter {
  _ParryButtonPainter(this.color, {required this.pressed});
  final Color color;
  final bool pressed;

  @override
  void paint(Canvas canvas, Size size) {
    final d = size.width / 18, cx = size.width / 2, cy = size.height / 2;
    const r = 8.0;
    final sink = pressed ? d : 0.0;
    if (!pressed) pixelDisc(canvas, cx, cy + d, r, Dot.ink, d: d);
    pixelDisc(canvas, cx, cy + sink, r, Dot.dark(color), d: d);
    pixelDisc(canvas, cx, cy + sink - d / 2, r - 0.6, color, d: d);
    // 左上のつや (文字に重ならない位置)
    canvas.drawRect(Rect.fromLTWH(cx - d * 5, cy + sink - d * 6, d * 2, d), Paint()..color = Dot.light(color));
    canvas.drawRect(Rect.fromLTWH(cx - d * 6, cy + sink - d * 5, d, d * 2), Paint()..color = Dot.light(color));
  }

  @override
  bool shouldRepaint(_ParryButtonPainter old) => old.color != color || old.pressed != pressed;
}

/// 領域方式の移動の目安 (左の余白)。
class MoveHint extends StatelessWidget {
  const MoveHint({super.key});

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          PixelIcon(PixelIcons.swap, color: withAlpha(Dot.sky, 0.7), size: 35),
          const SizedBox(height: 6),
          Container(width: 56, height: 4, color: withAlpha(Dot.sky, 0.45)),
        ]),
      );
}
