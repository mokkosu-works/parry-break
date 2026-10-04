import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../render/palette.dart';
import 'widgets.dart';

/// アーケード調の共通部品 (タイトル・結果・ポーズで使う)。

/// ブラウン管の走査線。
class Scanlines extends StatelessWidget {
  const Scanlines({super.key});

  @override
  Widget build(BuildContext context) => const IgnorePointer(child: CustomPaint(painter: _ScanlinePainter()));
}

class _ScanlinePainter extends CustomPainter {
  const _ScanlinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = const Color(0x14000000);
    for (var y = 0.0; y < size.height; y += 3) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), p);
    }
  }

  @override
  bool shouldRepaint(_ScanlinePainter old) => false;
}

/// 斜体・太字で、シアンとマゼンタの色ずれを重ねた見出し。
class ChromaticTitle extends StatelessWidget {
  const ChromaticTitle(this.text, {super.key, required this.size, required this.color, this.split = 0.03});
  final String text;
  final double size;
  final Color color;

  /// 色ずれの幅 (文字の大きさに対する割合)。
  final double split;

  @override
  Widget build(BuildContext context) {
    TextStyle st(Color c) => orbitron(size, color: c, weight: 900, letterSpacing: size * 0.04).copyWith(height: 1);
    final d = size * split;
    return Transform(
      transform: Matrix4.skewX(-0.2),
      child: Stack(children: [
        Transform.translate(offset: Offset(-d, 0), child: Text(text, style: st(withAlpha(Palette.magenta, 0.65)))),
        Transform.translate(offset: Offset(d, 0), child: Text(text, style: st(withAlpha(Palette.cyan, 0.65)))),
        Text(
          text,
          style: st(Color.lerp(color, Palette.white, 0.35)!).copyWith(shadows: [
            Shadow(color: withAlpha(color, 0.9), blurRadius: size * 0.14),
            Shadow(color: withAlpha(color, 0.45), blurRadius: size * 0.45),
          ]),
        ),
      ]),
    );
  }
}

/// 斜めに切った小さなタグ (例: BALL LOST)。
class SlashTag extends StatelessWidget {
  const SlashTag(this.text, {super.key, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _SlashPainter(fill: withAlpha(color, 0.16), edge: color, slant: 10),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 5, 20, 5),
          child: Text(text, style: orbitron(13, color: color, weight: 800, letterSpacing: 4)),
        ),
      );
}

/// 斜めに切ったボタン。[primary] は塗りつぶし。押すと一瞬明るくなる。
class SlashButton extends StatefulWidget {
  const SlashButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.primary = false,
    this.color = Palette.cyan,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  final Color color;
  final IconData? icon;

  @override
  State<SlashButton> createState() => _SlashButtonState();
}

class _SlashButtonState extends State<SlashButton> {
  bool _down = false, _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.color;
    final lit = _down || _hover;
    final fill = widget.primary ? withAlpha(c, _down ? 0.75 : (lit ? 0.5 : 0.32)) : withAlpha(c, _down ? 0.35 : (lit ? 0.16 : 0.06));
    final textColor = widget.primary ? Palette.white : (lit ? Palette.white : withAlpha(Palette.white, 0.85));
    return Semantics(
      button: true,
      label: widget.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _down = true),
          onTapCancel: () => setState(() => _down = false),
          onTapUp: (_) => setState(() => _down = false),
          onTap: widget.onPressed,
          child: AnimatedScale(
            duration: const Duration(milliseconds: 90),
            scale: _down ? 0.96 : 1,
            child: CustomPaint(
              painter: _SlashPainter(fill: fill, edge: c, slant: 14, glow: widget.primary || lit),
              child: Container(
                constraints: const BoxConstraints(minHeight: 48, minWidth: 150),
                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 10),
                child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                  if (widget.icon != null) ...[
                    Icon(widget.icon, size: 18, color: textColor),
                    const SizedBox(width: 8),
                  ],
                  Text(widget.label,
                      style: orbitron(16, color: textColor, weight: 800, letterSpacing: 3)
                          .copyWith(shadows: widget.primary ? [Shadow(color: c, blurRadius: 10)] : null)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SlashPainter extends CustomPainter {
  _SlashPainter({required this.fill, required this.edge, required this.slant, this.glow = false});
  final Color fill, edge;
  final double slant;
  final bool glow;

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(slant, size.height * 0.4);
    final path = Path()
      ..moveTo(s, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width - s, size.height)
      ..lineTo(0, size.height)
      ..close();
    if (glow) {
      canvas.drawPath(
          path,
          Paint()
            ..color = withAlpha(edge, 0.35)
            ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 10));
    }
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = withAlpha(edge, 0.9));
    // 左端の鋭いエッジ
    canvas.drawPath(
      Path()
        ..moveTo(s, 0)
        ..lineTo(s + 4, 0)
        ..lineTo(4, size.height)
        ..lineTo(0, size.height)
        ..close(),
      Paint()..color = edge,
    );
  }

  @override
  bool shouldRepaint(_SlashPainter old) =>
      old.fill != fill || old.edge != edge || old.glow != glow || old.slant != slant;
}

/// 計器風の数値表示 (小さなラベルと大きな数字)。
class StatReadout extends StatelessWidget {
  const StatReadout({super.key, required this.label, required this.value, this.highlight = false});
  final String label, value;
  final bool highlight;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: orbitron(10, color: withAlpha(Palette.pale, 0.6), letterSpacing: 3)),
          const SizedBox(height: 3),
          Text(value,
              style: orbitron(24, color: highlight ? Palette.yellow : Palette.white, weight: 900)
                  .copyWith(fontFeatures: const [FontFeature.tabularFigures()], height: 1)),
        ],
      );
}
