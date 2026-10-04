/// ブラウザ版の `mulberry32` と同じ値を返す乱数。
///
/// JavaScript の 32bit 整数演算 (`|0`, `>>>`, `Math.imul`) を再現しているため、
/// 同じシードからブラウザ版と同じ配置・同じ反射角が得られる。
/// 掛け算は 16bit ずつに分けて行うので、Web (整数が 53bit の倍精度) でも同じ値になる。
class Mulberry32 {
  Mulberry32(num seed) : _a = _toInt32(seed);

  int _a;

  /// 0 以上 1 未満の値を返す。
  double next() {
    _a = (_a + 0x6D2B79F5).toSigned(32);
    var t = _imul(_a ^ _ushr(_a, 15), 1 | _a);
    t = ((t + _imul(t ^ _ushr(t, 7), 61 | t)).toSigned(32) ^ t).toSigned(32);
    return ((t ^ _ushr(t, 14)) & 0xFFFFFFFF) / 4294967296;
  }

  /// [a] 以上 [b] 未満の値を返す。
  double range(double a, double b) => a + next() * (b - a);

  static int _toInt32(num v) => v.toInt().toSigned(32);
  static int _ushr(int v, int n) => (v & 0xFFFFFFFF) >> n;
  static int _imul(int a, int b) {
    final ah = (a >> 16) & 0xFFFF, al = a & 0xFFFF;
    final bh = (b >> 16) & 0xFFFF, bl = b & 0xFFFF;
    return (al * bl + (((ah * bl + al * bh) & 0xFFFF) << 16)).toSigned(32);
  }
}
