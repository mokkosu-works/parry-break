import 'package:flutter_test/flutter_test.dart';
import 'package:parry_break/core/core.dart';

import 'helpers.dart';

/// 偽の実時間の刻み (秒)。
const tick = 1 / 1000;

/// [Session] を偽の時刻で進め、実時間とシミュレーション時刻の対応を記録する。
class Clock {
  Clock(World w) : session = Session(w) {
    session.advance(0);
  }

  final Session session;
  World get w => session.world;
  double now = 0;
  final events = <GameEvent>[];

  /// 補間込みのシミュレーション時刻。
  double get sim => w.t + session.alpha * World.dt;

  void advance(double seconds) {
    final n = (seconds / tick).round();
    for (var i = 0; i < n; i++) {
      now += tick;
      events.addAll(session.advance(now));
    }
  }

  /// [found] が真になるまで進め、その実時間を返す。
  double until(bool Function() found, {double limit = 3}) {
    final end = now + limit;
    while (!found()) {
      if (now > end) fail('時間内に起きなかった');
      now += tick;
      events.addAll(session.advance(now));
    }
    return now;
  }

  /// 実時間 [from]〜[to] (今からの相対) にシミュレーション時刻が進んだ量。
  double simDuring(double from, double to) {
    advance(from);
    final s0 = sim;
    advance(to - from);
    return sim - s0;
  }
}

/// ヒットストップが [hitstop] 秒 (実時間) 続き、その後 [slowmo] 秒 (実時間) は 0.35 倍、その後は等速で進むか。
///
/// [c] は、ヒットストップとスローモーションが始まった直後の状態。
void expectStopThenSlow(Clock c, {required double hitstop, required double slowmo}) {
  final start = c.now;
  final s0 = c.sim;
  final resumed = c.until(() => c.sim > s0 + 1e-9) - tick;
  // 止まっている時間: 指定の時間 (±1 ステップ)
  expect(resumed - start, closeTo(hitstop, World.dt + tick));
  // 止まっている間にスローモーションは減らない (明けてから始まる)
  final slowStart = start + hitstop;
  // スローモーションの区間 (端は 0.01 秒あける): 0.35 倍
  final from = slowStart + 0.01 - c.now;
  expect(c.simDuring(from, from + slowmo - 0.02), closeTo(0.35 * (slowmo - 0.02), 0.003));
  // スローモーションが明けた後: 等速
  final after = slowStart + slowmo + 0.01 - c.now;
  expect(c.simDuring(after, after + 0.1), closeTo(0.1, 0.003));
}

/// 真下へ落ちてくるボールに対して、接触の [offset] 秒前に押す World と、押す時刻 (実時間)。
(Clock, double) parrySetup(double offset) {
  final w = testWorld(const SingleRoundMode(['NNNNNNNNNNNNNN']));
  run(w, 1.1); // カウントダウンを終える
  final b = w.ball
    ..attached = false
    ..x = w.paddle.x
    ..vx = 0
    ..pierce = 0;
  b.speed = w.targetSpeed;
  b.vy = b.speed;
  b.y = Field.paddleY - Field.ballR - b.speed * 0.5;
  final c = Clock(w);
  // 実時間 0 = シミュレーション時刻 w.t。0.5 秒後に接触する
  return (c, 0.5 - offset);
}

void main() {
  test('JUST: 0.10 秒止まり、その後 0.15 秒は 0.35 倍で動く', () {
    final (c, press) = parrySetup(0.005);
    c
      ..advance(press - 0.1)
      ..w.pressAction(press);
    c.until(() => c.events.whereType<ParrySucceeded>().isNotEmpty);
    expect(c.events.whereType<ParrySucceeded>().single.grade, ParryGrade.just);
    expect(c.w.hitstop, greaterThan(0));
    expectStopThenSlow(c, hitstop: 0.1, slowmo: 0.15);
  });

  test('ブレイカー: 0.06 秒止まり、その後 0.25 秒は 0.35 倍で動く', () {
    final w = testWorld(const SingleRoundMode(['NNNNNNNNNNNNNN']));
    run(w, 1.1);
    final target = w.blocks.first;
    final b = w.ball
      ..attached = false
      ..breaker = true
      ..pierce = 0
      ..x = target.x + w.form.ox + target.w / 2
      ..vx = 0;
    b.speed = w.targetSpeed;
    b.vy = -b.speed;
    // ブロックの下端の少し下から真上へ
    b.y = target.y + w.form.oy + target.h + Field.ballR + 2;
    final c = Clock(w);
    c.until(() => c.events.whereType<BreakerTriggered>().isNotEmpty);
    expectStopThenSlow(c, hitstop: 0.06, slowmo: 0.25);
  });

  test('コア撃破: 0.05 秒止まり、その後 0.5 秒は 0.35 倍で動く', () {
    final w = World(mode: endlessMode)..start(fromRound: 10);
    run(w, 1.1);
    final core = w.blocks.firstWhere((b) => b.type == bossCoreId)..hp = 1;
    final c = Clock(w);
    w.damageCore(core, 1);
    expect(c.w.drainEvents().whereType<CoreDestroyed>(), hasLength(1));
    expectStopThenSlow(c, hitstop: 0.05, slowmo: 0.5);
  });

  group('入力時刻の換算', () {
    test('ヒットストップ中に押した時刻は、止まった時刻に換算される', () {
      final w = testWorld(const SingleRoundMode(['NNNNNNNNNNNNNN']));
      run(w, 1.1);
      final c = Clock(w);
      w
        ..hitstop = 0.1
        ..slowmo = 0.15;
      c.advance(0.02);
      final frozen = c.sim;
      expect(w.sync.toSim(c.now + 0.05), closeTo(frozen, 1e-9));
      // 明けた後は 0.35 倍
      expect(w.sync.toSim(c.now + 0.08 + 0.1), closeTo(frozen + 0.35 * 0.1, 1e-9));
      // スローモーションも明けた後は等速
      expect(w.sync.toSim(c.now + 0.08 + 0.15 + 0.1), closeTo(frozen + 0.35 * 0.15 + 0.1, 1e-9));
    });

    test('JUST の直後のスローモーション中に、次の接触の直前に押すと JUST になる', () {
      final (c, press) = parrySetup(0.005);
      c
        ..advance(press - 0.1)
        ..w.pressAction(press);
      c.until(() => c.events.whereType<ParrySucceeded>().isNotEmpty);
      // ヒットストップが明けて、スローモーションに入るまで進める
      final t0 = c.w.t;
      c.until(() => c.w.t > t0);
      expect(c.w.slowmo, greaterThan(0));
      // ボールを戻し、シミュレーション時刻で 0.04 秒後に接触させる (実時間では約 0.1 秒後)
      final w = c.w;
      final b = w.ball
        ..x = w.paddle.x
        ..vx = 0
        ..pierce = 0
        ..breaker = false;
      b.vy = b.speed;
      b.y = Field.paddleY - Field.ballR - b.speed * (0.04 + c.session.alpha * World.dt);
      // 前のパリィの判定の窓を閉じておく
      w.parry
        ..active = false
        ..cooldownUntil = 0;
      // 接触はシミュレーション時刻 sim + 0.04。その 0.005 秒前 (シミュレーション時刻) に当たる実時間で押す
      final pressWall = c.now + (0.04 - 0.005) / 0.35;
      expect(w.sync.toSim(pressWall), closeTo(c.sim + 0.035, 1e-6));
      c.events.clear();
      // 押す時刻より前に届く (シミュレーション時刻で 0.25 秒以上先の入力は「今」とみなされるため、直前に積む)
      c.advance(0.05);
      w.pressAction(pressWall);
      c.until(() => c.events.whereType<ParrySucceeded>().isNotEmpty);
      expect(c.events.whereType<ParrySucceeded>().single.grade, ParryGrade.just);
    });
  });
}
