/// ゲームの時計と、タッチイベントの時刻の換算。
///
/// Flutter のポインターイベントの時刻 ([PointerEvent.timeStamp]) は「任意の基準」の時刻で、
/// 画面更新の時刻と同じ基準である保証がない。そこで、イベントが届いた瞬間のこの時計の値との差を
/// 記録し、差が最も大きい (= 届くまでの遅れが最も小さい) ものを基準のずれとみなして換算する。
/// これにより、パリィの判定には「指が触れた時刻」を使える (届くまでの遅れの影響を受けない)。
class InputClock {
  /// [source] を渡すとその時計を使う (テストで偽の時刻を使うため)。
  InputClock({this.source});

  final double Function()? source;
  final Stopwatch _watch = Stopwatch()..start();

  /// イベントの時刻 − 届いた時刻 の最大値 (秒)。
  double? _offset;
  double _offsetAt = 0;

  /// ゲームの時計 (秒)。
  double get now => source?.call() ?? _watch.elapsedMicroseconds / 1e6;

  /// ポインターイベントの時刻をゲームの時計に換算する。
  double eventTime(Duration timeStamp) {
    final arrival = now;
    if (timeStamp == Duration.zero) return arrival; // 時刻が付いていない (テストなど)
    final ts = timeStamp.inMicroseconds / 1e6;
    final sample = ts - arrival;
    final off = _offset;
    // 時計のずれ (ドリフト) に追従するため、古い基準は少しずつ弱める
    final decayed = off == null ? null : off - (arrival - _offsetAt) * 0.001;
    if (decayed == null || sample > decayed || (decayed - sample) > 0.5) {
      _offset = sample;
    } else {
      _offset = decayed;
    }
    _offsetAt = arrival;
    final t = ts - _offset!;
    // 届いた時刻より後や、極端に古い時刻にはしない
    return t > arrival ? arrival : (arrival - t > 0.2 ? arrival : t);
  }
}
