import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../render/palette.dart';

const kOrbitron = 'Orbitron';

/// 足りない文字を補うフォント。Web では端末のフォントを使えないため、同梱の日本語フォントを使う。
const List<String>? kFontFallback = kIsWeb ? ['NotoSansJP'] : null;

TextStyle orbitron(double size, {Color color = Palette.white, double weight = 700, double letterSpacing = 1}) =>
    TextStyle(
      fontFamily: kOrbitron,
      fontSize: size,
      color: color,
      fontWeight: FontWeight.values[((weight / 100).round() - 1).clamp(0, 8)],
      fontVariations: [FontVariation('wght', weight)],
      letterSpacing: letterSpacing,
      fontFamilyFallback: kFontFallback,
    );

ThemeData buildTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    fontFamily: kIsWeb ? 'NotoSansJP' : null,
    colorScheme: const ColorScheme.dark(primary: Palette.cyan, secondary: Palette.magenta, surface: Color(0xFF16152A)),
    scaffoldBackgroundColor: const Color(0xFF070610),
    useMaterial3: true,
  );
  return base.copyWith(
    sliderTheme: base.sliderTheme.copyWith(activeTrackColor: Palette.cyan, thumbColor: Palette.cyan),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Palette.cyan : null),
    ),
  );
}

/// ネオン調のボタン。
class NeonButton extends StatelessWidget {
  const NeonButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color = Palette.cyan,
    this.filled = false,
    this.icon,
    this.fontSize = 18,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final bool filled;
  final IconData? icon;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final c = enabled ? color : Palette.gray;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            constraints: const BoxConstraints(minHeight: 48, minWidth: 120),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
            decoration: BoxDecoration(
              color: filled ? withAlpha(c, 0.14) : const Color(0xFF171630),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c, width: filled ? 2 : 1),
              boxShadow: [BoxShadow(color: withAlpha(c, 0.3), blurRadius: 16)],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[Icon(icon, color: c, size: fontSize + 4), const SizedBox(width: 8)],
                Flexible(
                  child: Text(label,
                      textAlign: TextAlign.center,
                      style: orbitron(fontSize, color: filled ? Color.lerp(c, Palette.white, 0.6)! : Palette.white)
                          .copyWith(shadows: [Shadow(color: c, blurRadius: 8)])),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// タイトル画面の背景: 流れるグリッドと漂う光の玉。
class NeonBackground extends StatefulWidget {
  const NeonBackground({super.key, this.child, this.animate = true});
  final Widget? child;
  final bool animate;

  @override
  State<NeonBackground> createState() => _NeonBackgroundState();
}

class _NeonBackgroundState extends State<NeonBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 60));

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

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context) || !widget.animate;
    return CustomPaint(
      painter: _BackgroundPainter(_c, still: reduce),
      child: widget.child,
    );
  }
}

class _BackgroundPainter extends CustomPainter {
  _BackgroundPainter(this.anim, {required this.still}) : super(repaint: anim);
  final Animation<double> anim;
  final bool still;

  @override
  void paint(Canvas canvas, Size size) {
    final t = still ? 0.0 : anim.value * 60;
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF070610));
    final grid = Paint()
      ..color = const Color(0x154DFCFF)
      ..strokeWidth = 1;
    final off = (t * 12) % 48;
    for (var x = 0.0; x < size.width; x += 48) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = -48 + off; y < size.height; y += 48) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    for (final (cx, cy, color, r) in [
      (0.2, 0.3, Palette.cyan, 0.45),
      (0.8, 0.7, Palette.magenta, 0.45),
    ]) {
      final c = Offset(size.width * cx, size.height * cy), rad = size.shortestSide * r;
      canvas.drawCircle(
          c,
          rad,
          Paint()
            ..shader = RadialGradient(colors: [withAlpha(color, 0.15), withAlpha(color, 0)])
                .createShader(Rect.fromCircle(center: c, radius: rad)));
    }
    // 漂う光の玉
    for (final (i, color, r) in [(0, Palette.white, 9.0), (1, const Color(0xFFFFB8EC), 8.0), (2, Palette.yellow, 5.0)]) {
      final p = t * (0.09 + i * 0.03) + i * 2.1;
      final x = size.width * (0.5 + 0.42 * math.sin(p * 1.3 + i));
      final y = size.height * (0.5 + 0.38 * math.cos(p * 0.9 + i * 2));
      final glowColor = i == 1 ? Palette.magenta : Palette.cyan;
      canvas.drawCircle(Offset(x, y), r * 4, Paint()..color = withAlpha(glowColor, 0.12));
      canvas.drawCircle(Offset(x, y), r * 2, Paint()..color = withAlpha(glowColor, 0.25));
      canvas.drawCircle(Offset(x, y), r, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_BackgroundPainter old) => false;
}

/// 画面上部に戻るボタンと見出しを持つ、スクロールできる画面の枠。
class ScreenFrame extends StatelessWidget {
  const ScreenFrame({super.key, required this.title, required this.child, this.actions = const []});
  final String title;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: NeonBackground(
        animate: false,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back, color: Palette.cyan),
                    tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(title,
                        overflow: TextOverflow.ellipsis,
                        style: orbitron(24, weight: 900).copyWith(shadows: const [Shadow(color: Palette.cyan, blurRadius: 10)])),
                  ),
                  ...actions,
                ]),
                const SizedBox(height: 8),
                Expanded(child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Route<T> fadeRoute<T>(Widget page) => PageRouteBuilder<T>(
      pageBuilder: (_, _, _) => page,
      transitionDuration: const Duration(milliseconds: 220),
      transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
    );
