import 'package:flutter/widgets.dart';

import '../render/palette.dart';
import '../render/pixel.dart';

/// ドット絵のアイコン (7 ドット四方)。なめらかな線のアイコン (Material Icons) の代わりに使う。
abstract final class PixelIcons {
  static final back = DotSprite([
    '...#...',
    '..#....',
    '.#.....',
    '#######',
    '.#.....',
    '..#....',
    '...#...',
  ]);
  static final chevronLeft = DotSprite([
    '...#',
    '..#.',
    '.#..',
    '#...',
    '.#..',
    '..#.',
    '...#',
  ]);
  static final play = DotSprite([
    '#......',
    '###....',
    '#####..',
    '#######',
    '#####..',
    '###....',
    '#......',
  ]);
  static final pause = DotSprite([
    '##..##',
    '##..##',
    '##..##',
    '##..##',
    '##..##',
    '##..##',
    '##..##',
  ]);
  static final skipNext = DotSprite([
    '#....#',
    '##...#',
    '###..#',
    '####.#',
    '###..#',
    '##...#',
    '#....#',
  ]);
  // ↺ (左上が矢印の先)
  static final replay = DotSprite([
    '#.###..',
    '##...#.',
    '###...#',
    '......#',
    '#.....#',
    '.#...#.',
    '..###..',
  ]);
  static final home = DotSprite([
    '...#...',
    '..###..',
    '.#####.',
    '#######',
    '.#####.',
    '.##.##.',
    '.##.##.',
  ]);
  static final tune = DotSprite([
    '..#....',
    '#######',
    '..#....',
    '.......',
    '.....#.',
    '#######',
    '.....#.',
  ]);
  static final grid = DotSprite([
    '###.###',
    '###.###',
    '###.###',
    '.......',
    '###.###',
    '###.###',
    '###.###',
  ]);
  static final lock = DotSprite([
    '..###..',
    '.#...#.',
    '.#...#.',
    '#######',
    '###.###',
    '###.###',
    '#######',
  ]);
  static final check = DotSprite([
    '......#',
    '.....##',
    '#...##.',
    '##.##..',
    '.###...',
    '..#....',
    '.......',
  ]);
  static final plus = DotSprite([
    '...#...',
    '...#...',
    '...#...',
    '#######',
    '...#...',
    '...#...',
    '...#...',
  ]);
  static final minus = DotSprite([
    '.......',
    '.......',
    '.......',
    '#######',
    '.......',
    '.......',
    '.......',
  ]);
  static final timer = DotSprite([
    '..###..',
    '...#...',
    '.#####.',
    '#..#..#',
    '#..##.#',
    '#.....#',
    '.#####.',
  ]);
  static final swap = DotSprite([
    '..#....',
    '.#.....',
    '#######',
    '.......',
    '#######',
    '.....#.',
    '....#..',
  ]);
}

/// ドット絵のアイコン。色と大きさを省くと、周りの [IconTheme] (IconButton など) に従う。
class PixelIcon extends StatelessWidget {
  const PixelIcon(this.glyph, {super.key, this.size, this.color});
  final DotSprite glyph;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final s = size ?? theme.size ?? 24;
    final c = color ?? theme.color ?? Dot.white;
    return SizedBox.square(dimension: s, child: CustomPaint(painter: _IconPainter(glyph, c)));
  }
}

class _IconPainter extends CustomPainter {
  _IconPainter(this.glyph, this.color);
  final DotSprite glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // 1 ドットは整数の px にする (ぼやけないように)
    final d = (size.height / 7).floorToDouble().clamp(1.0, double.infinity);
    glyph.drawCentered(canvas, size.width / 2, size.height / 2, color, scale: d / Dot.px);
  }

  @override
  bool shouldRepaint(_IconPainter old) => old.glyph != glyph || old.color != color;
}
