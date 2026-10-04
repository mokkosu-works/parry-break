/// 盤面の座標系 (論理解像度 1200×720)。ステージによって変えない値。
abstract final class Field {
  static const double width = 1200;
  static const double height = 720;

  /// 上壁 (HUD の下端)。
  static const double topY = 56;

  static const double paddleY = 670;
  static const double paddleH = 14;

  /// 警告ライン: パドルの上 120px。
  static const double warnY = paddleY - 120;

  static const double ballR = 8;

  /// 14 列のグリッド。1 マス 60×24px、盤面の中央に置く。
  static const int cols = 14;
  static const double cellW = 60;
  static const double cellH = 24;
  static const double gridX0 = (width - cols * cellW) / 2;
  static const double gridY0 = 84;
}
