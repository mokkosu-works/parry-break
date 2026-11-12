// Issue #138: タッチの時刻の換算 (InputClock)
import 'package:flutter_test/flutter_test.dart';
import 'package:parry_break/input/input_clock.dart';

/// 偽の時計と、イベントの時刻の基準 (ゲームの時計 + [base] 秒)。
class Fake {
  double now = 10;
  static const base = 1000.0;
  late final clock = InputClock(source: () => now);

  /// 実時間 [pressed] に押したイベントが、[latency] 秒遅れて届いた。
  double deliver(double pressed, double latency) {
    now = pressed + latency;
    return clock.eventTime(Duration(microseconds: ((pressed + base) * 1e6).round()));
  }
}

void main() {
  test('イベントの時刻と届いた時刻の差が一定なら、イベントの時刻の間隔どおりに換算される', () {
    final f = Fake();
    final t1 = f.deliver(10, 0.01);
    final t2 = f.deliver(10.37, 0.01);
    final t3 = f.deliver(10.5, 0.01);
    expect(t1, closeTo(10.01, 1e-6)); // 最初は届いた時刻
    expect(t2 - t1, closeTo(0.37, 1e-6));
    expect(t3 - t2, closeTo(0.13, 1e-6));
  });

  test('届くのが遅れたイベントは、遅れの最も小さかったイベントを基準に、押した時刻へ戻す', () {
    final f = Fake();
    f.deliver(10, 0.005);
    // 0.025 秒遅れて届いた: 届いた時刻ではなく、押した時刻 (+ 基準の遅れ 0.005) になる
    final t = f.deliver(10.5, 0.025);
    expect(t, closeTo(10.5 + 0.005, 0.001));
    expect(f.now - t, closeTo(0.02, 0.001));
  });

  test('届いた時刻より後にはならない', () {
    final f = Fake();
    f.deliver(10, 0.03);
    // 前より遅れが小さい (基準より後の時刻になる) イベント
    final t = f.deliver(11, 0.001);
    expect(t, closeTo(f.now, 1e-9));
    expect(t, lessThanOrEqualTo(f.now));
  });

  test('0.2 秒より古い時刻は、届いた時刻に丸められる', () {
    final f = Fake();
    f.deliver(10, 0.005);
    final ok = f.deliver(11, 0.005 + 0.19);
    expect(f.now - ok, closeTo(0.19, 0.002));
    final old = f.deliver(12, 0.005 + 0.3);
    expect(old, f.now);
    final veryOld = f.deliver(13, 0.005 + 0.8);
    expect(veryOld, closeTo(f.now, 1e-9));
  });

  test('時刻のないイベント (Duration.zero) は届いた時刻になる', () {
    final f = Fake();
    f.deliver(10, 0.005);
    f.now = 20;
    expect(f.clock.eventTime(Duration.zero), 20);
  });

  test('source を渡さなければ実時間の時計で進む', () {
    final c = InputClock();
    final a = c.now;
    expect(a, greaterThanOrEqualTo(0));
    expect(c.now, greaterThanOrEqualTo(a));
  });
}
