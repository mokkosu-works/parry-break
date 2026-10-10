import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../render/palette.dart';
import '../render/pixel.dart';

/// 英数字のドット文字。
const kPixelFont = 'Silkscreen';

/// 日本語のドット文字 (英数字のドット文字にない文字を補う)。
const kJpFont = 'DotGothic16';

const List<String> kFontFallback = [kJpFont];

/// 見出し・数字・ボタンの文字 (英数字は Silkscreen、日本語は DotGothic16)。
/// Silkscreen は字幅が広いので、文字間は詰め気味にする。
TextStyle pixelFont(double size, {Color color = Palette.white, double weight = 700, double letterSpacing = 1}) =>
    TextStyle(
      fontFamily: kPixelFont,
      fontSize: size,
      color: color,
      fontWeight: weight >= 600 ? FontWeight.w700 : FontWeight.w400,
      letterSpacing: letterSpacing * 0.5,
      fontFamilyFallback: kFontFallback,
    );

/// 1 ドットずらした硬い影 (発光の代わり)。
List<Shadow> hardShadow(double size, {Color color = Dot.ink}) {
  final o = math.max(1.0, (size / 8).roundToDouble());
  return [Shadow(color: color, offset: Offset(o, o))];
}

ThemeData buildTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    fontFamily: kJpFont,
    colorScheme: const ColorScheme.dark(primary: Palette.accent, secondary: Palette.accent2, surface: Dot.night),
    scaffoldBackgroundColor: Dot.ink,
    useMaterial3: true,
  );
  const square = RoundedRectangleBorder(borderRadius: BorderRadius.zero, side: BorderSide(color: Dot.edge, width: 2));
  return base.copyWith(
    sliderTheme: base.sliderTheme.copyWith(
      activeTrackColor: Palette.accent,
      inactiveTrackColor: Dot.edge,
      thumbColor: Dot.white,
      trackHeight: 4,
      thumbShape: const _SquareThumb(),
      overlayShape: SliderComponentShape.noOverlay,
      trackShape: const RectangularSliderTrackShape(),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Dot.white : Dot.dim),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Palette.accent : Dot.night),
      trackOutlineColor: const WidgetStatePropertyAll(Dot.edge),
    ),
    dialogTheme: const DialogThemeData(backgroundColor: Dot.night, shape: square),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: Dot.night, shape: square),
    snackBarTheme: const SnackBarThemeData(backgroundColor: Dot.night, shape: square),
  );
}

class _SquareThumb extends SliderComponentShape {
  const _SquareThumb();

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(16, 16);

  @override
  void paint(PaintingContext context, Offset center,
      {required Animation<double> activationAnimation,
      required Animation<double> enableAnimation,
      required bool isDiscrete,
      required TextPainter labelPainter,
      required RenderBox parentBox,
      required SliderThemeData sliderTheme,
      required TextDirection textDirection,
      required double value,
      required double textScaleFactor,
      required Size sizeWithOverflow}) {
    final c = context.canvas;
    c.drawRect(Rect.fromCenter(center: center + const Offset(2, 2), width: 16, height: 16), Paint()..color = Dot.ink);
    c.drawRect(Rect.fromCenter(center: center, width: 16, height: 16), Paint()..color = sliderTheme.thumbColor ?? Dot.white);
  }
}

/// 陰影の付いたブロックの見た目 (上と左が明るく、下と右が暗い)。ボタンや枠に使う。
class BevelBox extends StatelessWidget {
  const BevelBox({super.key, required this.color, required this.child, this.edge = 3, this.padding = EdgeInsets.zero});
  final Color color;
  final Widget child;
  final double edge;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _BevelPainter(color, edge),
        child: Padding(padding: padding, child: child),
      );
}

class _BevelPainter extends CustomPainter {
  _BevelPainter(this.color, this.d);
  final Color color;
  final double d;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    final p = Paint()..isAntiAlias = false;
    canvas.drawRect(r, p..color = color);
    p.color = Dot.light(color);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, d), p);
    canvas.drawRect(Rect.fromLTWH(0, 0, d, size.height), p);
    p.color = Dot.dark(color);
    canvas.drawRect(Rect.fromLTWH(0, size.height - d, size.width, d), p);
    canvas.drawRect(Rect.fromLTWH(size.width - d, d, d, size.height - d), p);
  }

  @override
  bool shouldRepaint(_BevelPainter old) => old.color != color || old.d != d;
}

/// ドット絵のボタン。[filled] は色で塗った主なボタン (陰影の付いたブロック)、そうでなければ枠だけ。
/// 押すと硬い影の分だけ沈む。
class PixelButton extends StatefulWidget {
  const PixelButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color = Palette.accent,
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
  State<PixelButton> createState() => _PixelButtonState();
}

class _PixelButtonState extends State<PixelButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final c = enabled ? widget.color : Palette.gray;
    final fg = widget.filled ? Dot.ink : Palette.white;
    final content = Container(
      constraints: const BoxConstraints(minHeight: 48, minWidth: 120),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
      decoration: widget.filled ? null : BoxDecoration(color: Dot.night, border: Border.all(color: c, width: 3)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (widget.icon != null) ...[Icon(widget.icon, color: widget.filled ? fg : c, size: widget.fontSize + 4), const SizedBox(width: 8)],
          Flexible(
            child: Text(widget.label, textAlign: TextAlign.center, style: pixelFont(widget.fontSize, color: fg)),
          ),
        ],
      ),
    );
    return Semantics(
      button: true,
      enabled: enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onPressed,
        child: Opacity(
          opacity: enabled ? 1 : 0.5,
          child: Container(
            // 硬い影 (押すと沈んで影が消える)
            margin: EdgeInsets.only(left: _down ? 4 : 0, top: _down ? 4 : 0, right: _down ? 0 : 4, bottom: _down ? 0 : 4),
            decoration: BoxDecoration(boxShadow: _down ? null : const [BoxShadow(color: Colors.black, offset: Offset(4, 4))]),
            child: widget.filled ? BevelBox(color: c, child: content) : content,
          ),
        ),
      ),
    );
  }
}

/// RPG の窓のような二重枠 (外は白、内は灰色)。メニューを囲む。
class PixelWindow extends StatelessWidget {
  const PixelWindow({super.key, required this.child, this.padding = const EdgeInsets.symmetric(vertical: 10)});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: withAlpha(Dot.ink, 0.92),
          border: Border.all(color: Dot.white, width: 3),
          boxShadow: const [BoxShadow(color: Colors.black, offset: Offset(6, 6))],
        ),
        child: Container(
          margin: const EdgeInsets.all(4),
          padding: padding,
          decoration: BoxDecoration(border: Border.all(color: Dot.dim, width: 2)),
          child: child,
        ),
      );
}

/// 選んでいる項目に付ける ▶ (点滅する。動きを減らす設定では点けたまま)。
class BlinkCursor extends StatefulWidget {
  const BlinkCursor({super.key, this.color = Palette.yellow, this.size = 18});
  final Color color;
  final double size;

  @override
  State<BlinkCursor> createState() => _BlinkCursorState();
}

class _BlinkCursorState extends State<BlinkCursor> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));

  @override
  void initState() {
    super.initState();
    _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => Opacity(
        opacity: still || _c.value < 0.6 ? 1 : 0,
        // フォントに ▶ がないので、ドットで描く
        child: CustomPaint(size: Size.square(widget.size), painter: _CursorPainter(widget.color)),
      ),
    );
  }
}

class _CursorPainter extends CustomPainter {
  _CursorPainter(this.color);
  final Color color;

  static final _sprite = DotSprite(['#...', '##..', '###.', '####', '###.', '##..', '#...']);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = (size.height / 7).floorToDouble() / Dot.px;
    _sprite.drawCentered(canvas, size.width / 2, size.height / 2, color, scale: scale);
  }

  @override
  bool shouldRepaint(_CursorPainter old) => old.color != color;
}

/// メニュー画面の背景: 遠くの星がゆっくり流れ、足元は市松のディザ。
class DotBackground extends StatefulWidget {
  const DotBackground({super.key, this.child, this.animate = true});
  final Widget? child;
  final bool animate;

  @override
  State<DotBackground> createState() => _DotBackgroundState();
}

class _DotBackgroundState extends State<DotBackground> with SingleTickerProviderStateMixin {
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
    final p = Paint()..isAntiAlias = false;
    canvas.drawRect(Offset.zero & size, p..color = Dot.ink);
    // 星 (2 段の速さで流れる)
    const d = 4.0;
    for (final (gap, speed, color) in [(96.0, 8.0, Dot.edge), (160.0, 18.0, Dot.dim)]) {
      p.color = withAlpha(color, 0.5);
      final off = (t * speed) % gap;
      var row = 0;
      for (var y = off - gap; y < size.height; y += gap, row++) {
        for (var x = (row.isEven ? 0.3 : 0.8) * gap; x < size.width; x += gap * 1.7) {
          canvas.drawRect(Rect.fromLTWH(x.roundToDouble(), y.roundToDouble(), d, d), p);
        }
      }
    }
    // 足元のディザ (下ほど濃い)
    const cell = 8.0;
    final top = size.height * 0.62;
    final rows = ((size.height - top) / cell).ceil();
    p.color = Dot.dither;
    for (var j = 0; j < rows; j++) {
      final k = j / rows;
      for (var i = 0; i * cell < size.width; i++) {
        final on = k > 0.66
            ? (i + j).isEven
            : k > 0.33
                ? i.isEven && j.isEven
                : i % 4 == 0 && j % 4 == 0;
        if (on) canvas.drawRect(Rect.fromLTWH(i * cell, top + j * cell, cell, cell), p);
      }
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
      body: DotBackground(
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
                    icon: const Icon(Icons.arrow_back, color: Palette.accent),
                    tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(title,
                        overflow: TextOverflow.ellipsis,
                        style: pixelFont(24, color: Palette.yellow).copyWith(shadows: hardShadow(24, color: Dot.brick))),
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

/// ドット文字の星 (取ったものは ★、まだのものは ☆)。
class PixelStar extends StatelessWidget {
  const PixelStar({super.key, required this.got, this.size = 18, this.shadow = false});
  final bool got;
  final double size;

  /// 硬い影を付ける (大きく出すとき)。
  final bool shadow;

  @override
  Widget build(BuildContext context) => Text(
        got ? '★' : '☆',
        style: TextStyle(
          fontFamily: kJpFont,
          fontSize: size,
          height: 1,
          color: got ? Palette.yellow : Palette.gray,
          shadows: shadow && got ? hardShadow(size, color: Dot.brick) : null,
        ),
      );
}
