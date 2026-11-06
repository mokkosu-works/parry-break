import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:parry_break/core/core.dart';

import 'helpers.dart';

/// 真下へ落ちてくるボールに対して、接触の [offset] 秒前 (負なら後) に押したときの判定。
ParryGrade? gradeFor(double offset) {
  final w = testWorld(const SingleRoundMode(['NNNNNNNNNNNNNN']));
  run(w, 1.1); // カウントダウンを終える
  final b = w.ball
    ..attached = false
    ..x = w.paddle.x
    ..vx = 0
    ..pierce = 0;
  b.speed = w.targetSpeed;
  b.vy = b.speed;
  // 0.5 秒後にパドル上面へ接触する位置に置く
  b.y = Field.paddleY - Field.ballR - b.speed * 0.5;
  final contact = w.t + 0.5;
  final press = contact - offset;
  var pressed = false;
  final events = run(w, 0.8, before: () {
    if (!pressed && w.t + World.dt >= press - 0.2) {
      w.pressAction(press);
      pressed = true;
    }
  });
  final parries = events.whereType<ParrySucceeded>().toList();
  return parries.isEmpty ? null : parries.single.grade;
}

void main() {
  test('接触の直前に押した: 差に応じて JUST / PERFECT / GOOD', () {
    expect(gradeFor(0.005), ParryGrade.just);
    expect(gradeFor(0.02), ParryGrade.perfect);
    expect(gradeFor(0.06), ParryGrade.good);
  });

  test('早すぎると判定の窓が閉じて空振り', () {
    expect(gradeFor(0.2), isNull);
  });

  test('接触の後に押しても 0.03 秒以内なら成立する', () {
    expect(gradeFor(-0.005), ParryGrade.just);
    expect(gradeFor(-0.02), ParryGrade.perfect);
    expect(gradeFor(-0.05), isNull);
  });

  test('PERFECT で貫通弾になり、JUST でブレイカーが付く', () {
    final w = testWorld(const SingleRoundMode(['NNNNNNNNNNNNNN']));
    run(w, 1.1);
    final b = w.ball
      ..attached = false
      ..x = w.paddle.x
      ..vx = 0;
    b.speed = w.targetSpeed;
    b.vy = b.speed;
    b.y = Field.paddleY - Field.ballR - b.speed * 0.3;
    final press = w.t + 0.3 - 0.004;
    var pressed = false;
    run(w, 0.4, before: () {
      if (!pressed && w.t + World.dt >= press - 0.2) {
        w.pressAction(press);
        pressed = true;
      }
    });
    expect(w.ball.pierce, 3);
    expect(w.ball.breaker, isTrue);
    expect(w.combo, inInclusiveRange(150, 160)); // JUST で +160 (その後は減衰)
  });

  test('被弾: 短く止まり、その後しばらく無敵。パドル付近の弾は消え、続けて被弾しない', () {
    final w = testWorld(const SingleRoundMode(['NNNNNNNNNNNNNN']));
    run(w, 1.1);
    final x = w.paddle.x;
    // パドルの真上に縦に並べた敵弾 (先頭が 0.1 秒後に当たる) と、遠くの敵弾
    for (var k = 0; k < 6; k++) {
      w.fireBullet(x, Field.paddleY - 30 - k * 40, math.pi / 2, 300);
    }
    w.fireBullet(80, 200, math.pi / 2, 100);
    final events = run(w, 0.2);
    expect(events.whereType<PlayerHurt>(), hasLength(1));
    expect(w.paddle.stun, closeTo(w.tuning.stunTime - 0.1, 0.05));
    expect(w.bullets.where((u) => u.hostile).map((u) => u.x), [80]); // 遠くの弾だけ残る
    // 無敵の間に当たる弾では被弾しない
    w.fireBullet(x, Field.paddleY - 30, math.pi / 2, 300);
    expect(run(w, 0.5).whereType<PlayerHurt>(), isEmpty);
    // 無敵が切れたら、また被弾する
    run(w, w.tuning.hurtInvuln);
    w.fireBullet(w.paddle.x, Field.paddleY - 30, math.pi / 2, 300);
    expect(run(w, 0.3).whereType<PlayerHurt>(), hasLength(1));
  });

  group('グレイズ (#130)', () {
    /// カウントダウンを終えた World (ボールはパドルに付いたままなので、コンボは減らない)。
    World ready() {
      final w = testWorld(const SingleRoundMode(['NNNNNNNNNNNNNN']));
      run(w, 1.1);
      return w;
    }

    test('無敵でないとき、パドルの 22px 以内をかすめた弾でグレイズになり、コンボ +8・得点 50 × 倍率が入る', () {
      final w = ready();
      final c0 = w.combo, s0 = w.score, m = w.mult;
      // パドルの右端から 10px 外 (弾の縁からは 4px) を真下へ通る
      w.fireBullet(w.paddle.x + w.paddleWidth / 2 + 6 + 10, Field.paddleY - 30, math.pi / 2, 300);
      final events = run(w, 0.5);
      expect(events.whereType<PlayerHurt>(), isEmpty);
      expect(events.whereType<Grazed>(), hasLength(1));
      expect(w.stats.graze, 1);
      expect(w.combo, c0 + 8);
      expect(w.score, s0 + 50 * m);
    });

    test('パドルから 22px より遠くを通った弾はグレイズにならない', () {
      final w = ready();
      w.fireBullet(w.paddle.x + w.paddleWidth / 2 + 6 + 23, Field.paddleY - 30, math.pi / 2, 300);
      expect(run(w, 0.5).whereType<Grazed>(), isEmpty);
    });

    test('無敵中にパドルと重なって抜けた弾は、無敵が切れた後もグレイズにならない', () {
      final w = ready();
      // 0.08 秒後にパドルに重なり、約 0.17 秒後にパドルの下へ抜ける。無敵は抜けた後、画面の下へ消える前 (0.25 秒) に切れる
      w.paddle.invuln = 0.25;
      w.fireBullet(w.paddle.x, Field.paddleY - 30, math.pi / 2, 300);
      final events = run(w, 0.5);
      expect(w.paddle.invuln, lessThanOrEqualTo(0));
      expect(events.whereType<PlayerHurt>(), isEmpty);
      expect(events.whereType<Grazed>(), isEmpty);
      expect(w.stats.graze, 0);
    });

    test('無敵中にパドルの近くを通った弾は、無敵が切れてから下へ抜けてもグレイズにならない', () {
      final w = ready();
      w.paddle.invuln = 0.25;
      w.fireBullet(w.paddle.x + w.paddleWidth / 2 + 6 + 10, Field.paddleY - 30, math.pi / 2, 300);
      expect(run(w, 0.5).whereType<Grazed>(), isEmpty);
    });
  });
}
