import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../render/palette.dart';
import '../widgets.dart';

/// タイトルのロゴ。硬い影を重ねた PARRY と BREAK を、ボールの軌跡 (ドットの点線) でつなぐ。
class TitleLogo extends StatefulWidget {
  const TitleLogo({super.key, required this.size, this.animate = true});

  /// PARRY の文字の大きさ。
  final double size;
  final bool animate;

  @override
  State<TitleLogo> createState() => _TitleLogoState();
}

class _TitleLogoState extends State<TitleLogo> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));

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

  Widget _word(String text, double size, Color color, Color shadow) {
    final o = math.max(2.0, (size / 12).roundToDouble());
    TextStyle st(Color c) => pixelFont(size, color: c, letterSpacing: 0).copyWith(height: 1);
    return Stack(children: [
      Transform.translate(offset: Offset(o * 2, o * 2), child: Text(text, style: st(Colors.black))),
      Transform.translate(offset: Offset(o, o), child: Text(text, style: st(shadow))),
      Text(text, style: st(color)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final v = widget.animate ? _c.value : 0.3;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _word('PARRY', s, Dot.mustard, Dot.brick),
            SizedBox(height: s * 0.12),
            _TrailBar(width: s * 4.7, dot: math.max(3, (s / 16).roundToDouble()), phase: v),
            SizedBox(height: s * 0.12),
            Padding(
              padding: EdgeInsets.only(left: s * 0.7),
              child: _word('BREAK', s * 0.8, Dot.sky, Dot.violet),
            ),
          ],
        );
      },
    );
  }
}

/// PARRY と BREAK の間の、ボールの軌跡。点線が流れ、先端でドットのボールが跳ねる。
class _TrailBar extends StatelessWidget {
  const _TrailBar({required this.width, required this.dot, required this.phase});
  final double width, dot, phase;

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size(width, dot * 8), painter: _TrailPainter(dot, phase));
}

class _TrailPainter extends CustomPainter {
  _TrailPainter(this.d, this.phase);
  final double d, phase;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..isAntiAlias = false;
    final y = (size.height / 2 / d).floor() * d;
    final step = d * 3;
    final off = (phase * step * 4) % step;
    final n = (size.width / step).floor();
    for (var i = 0; i < n; i++) {
      final x = i * step + off;
      if (x > size.width - d * 6) break;
      // 先端に近いほど明るい (残像)
      final k = x / size.width;
      p.color = k > 0.66 ? Dot.white : k > 0.33 ? Dot.rose : Dot.dark(Dot.rose);
      canvas.drawRect(Rect.fromLTWH(x.floorToDouble(), y, d, d), p);
    }
    // ボール (2 コマで跳ねる)
    final bx = size.width - d * 4, by = y - d * 1.5 - ((phase * 4).floor().isEven ? d : 0);
    p.color = Dot.white;
    canvas.drawRect(Rect.fromLTWH(bx + d, by, d * 2, d * 4), p);
    canvas.drawRect(Rect.fromLTWH(bx, by + d, d * 4, d * 2), p);
  }

  @override
  bool shouldRepaint(_TrailPainter old) => old.phase != phase || old.d != d;
}
