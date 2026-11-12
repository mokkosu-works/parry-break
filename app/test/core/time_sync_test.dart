// Issue #138: 時間の進め方 (Session) と、実時間 → シミュレーション時刻の換算 (TimeSync)
// ヒットストップとスローモーションの長さ・重なり、その間の入力の換算は session_test.dart で確かめている。
import 'package:flutter_test/flutter_test.dart';
import 'package:parry_break/core/core.dart';

import 'helpers.dart';

/// カウントダウンを終えた World と、実時間 0 から動かし始めた Session。
(World, Session) setUp() {
  final w = testWorld(const SingleRoundMode(['N............N']));
  run(w, 1.1);
  final s = Session(w)..advance(0);
  return (w, s);
}

void main() {
  group('Session', () {
    test('1 フレームが 0.1 秒を超えても、0.1 秒分しか進まない', () {
      final (w, s) = setUp();
      final t0 = w.t;
      s.advance(0.5);
      expect(w.t - t0, closeTo(0.1, 1e-9));
      // 次のフレームからは普通に進む
      s.advance(0.5 + 3 * World.dt);
      expect(w.t - t0, closeTo(0.1 + 3 * World.dt, 1e-9));
    });

    test('0.1 秒ちょうどのフレームはそのまま進む', () {
      final (w, s) = setUp();
      final t0 = w.t;
      s.advance(0.1);
      expect(w.t - t0, closeTo(0.1, 1e-9));
    });

    test('ヒットストップ中はステップが進まない', () {
      final (w, s) = setUp();
      final t0 = w.t;
      w.hitstop = 0.05;
      s.advance(0.04);
      expect(w.t, t0);
      expect(w.hitstop, closeTo(0.01, 1e-9));
      s.advance(0.06 + World.dt);
      expect(w.hitstop, 0);
      expect(w.t, greaterThan(t0));
    });

    test('スローモーション中は 0.35 倍で進む', () {
      final (w, s) = setUp();
      w.slowmo = 1;
      var now = 0.0;
      // 0.5 秒 (実時間) を 1/120 秒ごとのフレームで進める
      final sim0 = w.t + s.alpha * World.dt;
      for (var i = 0; i < 60; i++) {
        now += 1 / 120;
        s.advance(now);
      }
      expect(w.t + s.alpha * World.dt - sim0, closeTo(0.35 * 0.5, 1e-6));
      expect(w.slowmo, closeTo(0.5, 1e-6));
    });

    test('ポーズ中に溜まった入力は捨てられ、ポーズ中は進まない', () {
      final (w, s) = setUp();
      expect(w.ball.attached, isTrue);
      w.pressAction(0); // 発射の入力 (まだ処理されていない)
      s.pause();
      w.pressAction(0.01); // ポーズ中に届いた入力
      expect(s.advance(1), isEmpty);
      final t = w.t;
      s.resume();
      s.advance(2);
      s.advance(2 + 5 * World.dt);
      expect(w.t, greaterThan(t));
      expect(w.ball.attached, isTrue, reason: 'ポーズの前後の入力で発射しない');
      expect(w.launched, isFalse);
    });

    test('再開の最初のフレームで時間が飛ばない', () {
      final (w, s) = setUp();
      s.advance(1);
      final t0 = w.t;
      s.pause();
      s.advance(30); // ポーズ中のフレーム
      expect(w.t, t0);
      s.resume();
      s.advance(31); // 再開の最初のフレーム: ポーズ中の 30 秒 (上限の 0.1 秒も) は進めない
      expect(w.t, t0);
      expect(s.alpha, 0);
      s.advance(31 + World.dt);
      expect(w.t, closeTo(t0 + World.dt, 1e-9));
    });
  });

  group('TimeSync', () {
    test('フレームの途中に押した入力は、押した瞬間のシミュレーション時刻に換算される', () {
      final (w, s) = setUp();
      s.advance(0.004); // ステップの途中で止まる
      final sim = w.t + s.alpha * World.dt;
      expect(s.alpha, greaterThan(0));
      expect(w.sync.sim, closeTo(sim, 1e-12));
      // このフレームの後 7ms (次のフレームの前) に押した
      expect(w.sync.toSim(0.004 + 0.007), closeTo(sim + 0.007, 1e-9));
      // このフレームの前 3ms に押した (遅れて届いた)
      expect(w.sync.toSim(0.004 - 0.003), closeTo(sim - 0.003, 1e-9));
    });

    test('スローモーション中は 0.35 倍で換算される', () {
      final (w, s) = setUp();
      w.slowmo = 0.2;
      s.advance(0.05);
      final sim = w.sync.sim;
      expect(w.sync.scale, 0.35);
      expect(w.sync.toSim(0.05 + 0.1), closeTo(sim + 0.035, 1e-9));
      // スローモーションが明けた後は等速
      expect(
        w.sync.toSim(0.05 + 0.15 + 0.1),
        closeTo(sim + 0.15 * 0.35 + 0.1, 1e-9),
      );
      // 押した後に届くまでに進んだ分も 0.35 倍で戻す
      expect(w.sync.toSim(0.05 - 0.02), closeTo(sim - 0.02 * 0.35, 1e-9));
    });

    test('換算の式 (ヒットストップ → スローモーション → 等速)', () {
      final ts = TimeSync()
        ..wall = 1
        ..sim = 10
        ..hold = 0.05
        ..scale = 0.35
        ..slow = 0.2;
      expect(ts.toSim(0.99), 10); // 止まっている間は、前に押した入力も止まった時刻
      expect(ts.toSim(1.03), 10);
      expect(ts.toSim(1.05), 10);
      expect(ts.toSim(1.15), closeTo(10 + 0.1 * 0.35, 1e-12));
      expect(ts.toSim(1.35), closeTo(10 + 0.2 * 0.35 + 0.1, 1e-12));
      ts.identity();
      expect(ts.toSim(3.5), 3.5);
    });
  });
}
