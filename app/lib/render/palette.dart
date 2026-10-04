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
  static const normalTiers = [Color(0xFF3EE0FF), Color(0xFFA66BFF), Color(0xFFFFD84D)];
  static const blocks = <String, Color>{
    'T': Color(0xFFFF3D5A),
    'R': Color(0xFF3DFF9B),
    'M': Color(0xFF4D84FF),
    'S': Color(0xFFFF5EC8),
    's': Color(0xFFFF9EE0),
    'X': Color(0xFFD8E4F0),
    '#': Color(0xFF55556A),
    'C': Color(0xFFFFDE3D),
    'K': Color(0xFFFFFFFF),
    'B': Color(0xFFFF7A1A),
  };

  /// ヒート段階 (1〜4, OVERDRIVE) の色。
  static const heatBar = [Color(0xFF5A6AFF), cyan, Color(0xFF3DFF9B), Color(0xFFFFB43C)];
  static const multColor = [white, cyan, Color(0xFF3DFF9B), Color(0xFFFFB43C), magenta];
}

Color withAlpha(Color c, double a) => c.withValues(alpha: (c.a * a).clamp(0.0, 1.0));
