import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../render/palette.dart';
import '../widgets.dart';

/// タイトルのロゴ。斜体の PARRY (色ずれ・光の走査・ときどきグリッチ) と、線画の BREAK。
class TitleLogo extends StatefulWidget {
  const TitleLogo({super.key, required this.size, this.animate = true});

  /// PARRY の文字の大きさ。
  final double size;
  final bool animate;

  @override
  State<TitleLogo> createState() => _TitleLogoState();
}

class _TitleLogoState extends State<TitleLogo> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 5200));
  final _rnd = math.Random();

  @override
  void initState() {
    super.initState();
    if (widget.animate) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  TextStyle _style(double size, {Color color = Palette.white, double spacing = 0}) =>
      orbitron(size, color: color, weight: 900, letterSpacing: spacing).copyWith(height: 1);

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final v = widget.animate ? _c.value : 0.3;
        // 光の走査の位置と、短いグリッチ (色ずれが跳ねる)
        final sweep = v * 1.8 - 0.4;
        final glitch = widget.animate && v > 0.84 && v < 0.875;
        final jx = glitch ? (_rnd.nextDouble() - 0.5) * s * 0.12 : 0.0;
        final jy = glitch ? (_rnd.nextDouble() - 0.5) * s * 0.05 : 0.0;
        final split = s * (glitch ? 0.06 : 0.028);
        return Transform(
          transform: Matrix4.skewX(-0.2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(children: [
                Transform.translate(
                  offset: Offset(-split + jx, jy),
                  child: Text('PARRY', style: _style(s, color: withAlpha(Palette.magenta, 0.7))),
                ),
                Transform.translate(
                  offset: Offset(split, -jy),
                  child: Text('PARRY', style: _style(s, color: withAlpha(Palette.cyan, 0.7))),
                ),
                ShaderMask(
                  blendMode: BlendMode.srcIn,
                  shaderCallback: (r) => LinearGradient(
                    colors: const [Color(0xFFBFFBFF), Palette.white, Color(0xFFBFFBFF), Palette.cyan],
                    stops: [
                      (sweep - 0.12).clamp(0.0, 1.0),
                      sweep.clamp(0.0, 1.0),
                      (sweep + 0.12).clamp(0.0, 1.0),
                      1,
                    ],
                  ).createShader(r),
                  child: Text(
                    'PARRY',
                    style: _style(s).copyWith(shadows: [
                      Shadow(color: withAlpha(Palette.cyan, 0.9), blurRadius: s * 0.12),
                      Shadow(color: withAlpha(Palette.cyan, 0.5), blurRadius: s * 0.4),
                    ]),
                  ),
                ),
              ]),
              SizedBox(height: s * 0.14),
              _TrailBar(width: s * 4.7, height: math.max(2, s * 0.045), phase: v),
              SizedBox(height: s * 0.14),
              Padding(
                padding: EdgeInsets.only(left: s * 0.7),
                child: Stack(children: [
                  Text('BREAK',
                      style: _style(s * 0.68, spacing: s * 0.16).copyWith(
                        foreground: Paint()
                          ..style = PaintingStyle.stroke
                          ..strokeWidth = math.max(1.5, s * 0.026)
                          ..color = Palette.magenta,
                        shadows: [Shadow(color: Palette.magenta, blurRadius: s * 0.18)],
                      )),
                  Text('BREAK',
                      style: _style(s * 0.68, color: withAlpha(Palette.magenta, 0.16), spacing: s * 0.16)),
                ]),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// PARRY と BREAK の間の光のライン。左から伸び、先端で光の玉が脈打つ (跳ね返ったボールの軌跡)。
class _TrailBar extends StatelessWidget {
  const _TrailBar({required this.width, required this.height, required this.phase});
  final double width, height, phase;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size(width, height * 6), painter: _TrailPainter(height, phase));
}

class _TrailPainter extends CustomPainter {
  _TrailPainter(this.h, this.phase);
  final double h, phase;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final rect = Rect.fromLTWH(0, y - h / 2, size.width, h);
    canvas.drawRect(
        rect,
        Paint()
          ..shader = const LinearGradient(colors: [Color(0x00FF4DD8), Palette.magenta, Palette.cyan])
              .createShader(rect));
    final pulse = 0.75 + 0.25 * math.sin(phase * math.pi * 8);
    final c = Offset(size.width, y);
    canvas.drawCircle(c, h * 5 * pulse, Paint()..color = withAlpha(Palette.cyan, 0.18));
    canvas.drawCircle(c, h * 2.6, Paint()..color = withAlpha(Palette.cyan, 0.45));
    canvas.drawCircle(c, h * 1.6, Paint()..color = Palette.white);
  }

  @override
  bool shouldRepaint(_TrailPainter old) => old.phase != phase || old.h != h;
}
