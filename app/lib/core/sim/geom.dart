import 'dart:math' as math;

const double deg = math.pi / 180;

double clampD(double v, double a, double b) => v < a ? a : (v > b ? b : v);

/// 円と矩形が重なっているか。
bool circleRect(double cx, double cy, double r, double x, double y, double w, double h) {
  final nx = clampD(cx, x, x + w), ny = clampD(cy, y, y + h);
  final dx = cx - nx, dy = cy - ny;
  return dx * dx + dy * dy <= r * r;
}

/// 点から矩形までの距離。
double rectDist(double px, double py, double x, double y, double w, double h) {
  final dx = px - clampD(px, x, x + w), dy = py - clampD(py, y, y + h);
  return math.sqrt(dx * dx + dy * dy);
}

double hypot(double x, double y) => math.sqrt(x * x + y * y);

class Vec2 {
  const Vec2(this.x, this.y);
  final double x, y;
}
