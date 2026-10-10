import 'dart:ui';

/// 色 (ブラウザ版と同じ値)。
abstract final class Palette {
  static const bg = Color(0xFF07060F);
  static const hudBg = Color(0xFF0D0B1C);
  static const hudLine = Color(0xFF2A2550);
  static const hudLabel = Color(0xFF7A74B0);
  static const cyan = Color(0xFF4DFCFF);
  static const magenta = Color(0xFFFF4DD8);
  static const yellow = Color(0xFFFFE14D);
  static const orange = Color(0xFFFF9A3D);
  static const red = Color(0xFFFF4060);
  static const white = Color(0xFFFFFFFF);
  static const pale = Color(0xFFCFD6FF);
  static const gray = Color(0xFF8A8AA0);
  static const justPink = Color(0xFFFF6BF0);

  /// ブロックの色。通常ブロックは高さの段で変わる。
  static const normalTiers = [Dot.teal, Dot.violet, Dot.mustard];
  static const blocks = <String, Color>{
    'T': Dot.brick,
    'R': Dot.mint,
    'M': Dot.sky,
    'S': Dot.rose,
    's': Dot.blush,
    'X': Dot.steel,
    '#': Dot.edge,
    'C': Dot.mustard,
    'K': Dot.white,
    'B': Dot.orange,
  };

  /// ヒート段階 (1〜4, OVERDRIVE) の色。
  static const heatBar = [Dot.sky, Dot.teal, Dot.mint, Dot.mustard];
  static const multColor = [Dot.white, Dot.ice, Dot.mint, Dot.mustard, Dot.rose];
}

/// 盤面のドット絵の色 (16 色)。陰影は [Dot.light] / [Dot.dark] で作る。
abstract final class Dot {
  static const ink = Color(0xFF07060A);
  static const night = Color(0xFF15111C);
  static const dither = Color(0xFF1D1830);
  static const edge = Color(0xFF3B3352);
  static const dim = Color(0xFF9C96B8);
  static const white = Color(0xFFFFFFFF);
  static const brick = Color(0xFFF2381F);
  static const mustard = Color(0xFFFFC414);
  static const mint = Color(0xFF14E08A);
  static const teal = Color(0xFF0FCBE0);
  static const sky = Color(0xFF2E7BFF);
  static const violet = Color(0xFF9A45FF);
  static const steel = Color(0xFFA6A2BC);
  static const orange = Color(0xFFFF7A0F);
  static const rose = Color(0xFFFF2FA8);
  static const blush = Color(0xFFFF9ADB);
  static const ice = Color(0xFF6EF7FF);

  /// OVERDRIVE 中の地・床・HUD (パレットを入れ替えて、ひと目で分かるようにする)。
  static const odBg = Color(0xFF3A0532);
  static const odDither = Color(0xFF64104F);
  static const odHud = Color(0xFF520A47);

  /// 敵弾 (赤い弾は避けるしかない)。
  static const bullet = Color(0xFFFF7A0F);
  static const bulletRed = Color(0xFFFF1F4B);

  /// 1 ドットの大きさ (盤面の論理 px)。
  static const px = 4.0;

  static Color light(Color c) => Color.lerp(c, white, 0.55)!;
  static Color dark(Color c) => Color.lerp(c, ink, 0.6)!;
}

Color withAlpha(Color c, double a) => c.withValues(alpha: (c.a * a).clamp(0.0, 1.0));
