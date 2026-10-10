import 'dart:ui';

/// 画面の色。値はすべて 16 色のパレット [Dot] から取る (名前は役割を表す)。
abstract final class Palette {
  static const bg = Dot.ink;
  static const hudBg = Dot.night;
  static const hudLine = Dot.edge;
  static const hudLabel = Dot.dim;

  // ---- 画面の 3 色 (盤面の外の UI で使う。盤面の中は Dot の色を大胆に使ってよい) ----

  /// メインカラー (黄)。ロゴの PARRY・見出し・いま選んでいるもの (▶)・主なボタン・記録 (ハイスコア・星)。
  static const main = Dot.mustard;

  /// サブカラー (青)。プレイヤーの色 (パドル・BREAK)。二番手のボタン・戻る / めくる・補足の見出し。
  static const sub = Dot.sky;

  /// アクセントカラー (赤)。危険と衝撃だけに使う (GAME OVER・BALL LOST・危険ライン・PARRY ボタン)。見出しの影にも使う。
  static const accent = Dot.brick;
  static const yellow = Dot.mustard;
  static const orange = Dot.orange;
  static const red = Dot.bulletRed;
  static const white = Dot.white;
  static const pale = Color(0xFFD9D5EA);
  static const gray = Dot.dim;
  static const justPink = Dot.rose;

  /// ブロックの色。通常ブロックは高さの段で変わる。
  static const normalTiers = [Dot.orange, Dot.violet, Dot.mustard];
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
  static const heatBar = [Dot.sky, Dot.mint, Dot.mustard, Dot.orange];
  static const multColor = [Dot.white, Dot.peach, Dot.mint, Dot.mustard, Dot.rose];
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
  static const sky = Color(0xFF2E7BFF);
  static const violet = Color(0xFF9A45FF);
  static const steel = Color(0xFFA6A2BC);
  static const orange = Color(0xFFFF7A0F);
  static const rose = Color(0xFFFF2FA8);
  static const blush = Color(0xFFFF9ADB);
  /// 撃ち返した弾・GOOD・跳弾など、こちらの手柄の淡い色。
  static const peach = Color(0xFFFFC9A8);

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
