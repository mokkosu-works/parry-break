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

/// 判定タイミング補正 [inputLag] の World で、真下へ落ちてくる敵弾の接触時刻 tc に対し、
/// 換算後の時刻 tc + inputLag + [after] に押したときの結果。被弾なら 'hurt'、何も起きなければ null。
Object? bulletResultFor(double inputLag, double after) {
  final w = testWorld(const SingleRoundMode(['NNNNNNNNNNNNNN']), inputLag: inputLag);
  run(w, 1.1); // カウントダウンを終える
  // ボールは上へ飛ばしておく (押してもボールの発射・パリィにならないように)
  w.ball
    ..attached = false
    ..x = 40
    ..y = Field.paddleY - 300
    ..vx = 0
    ..vy = -w.ball.speed;
  const sp = 300.0, steps = 12.5;
  final x = w.paddle.x;
  // ちょうど 12.5 ステップ後 (ステップの中央) にパドル上面へ触れる位置から撃つ
  w.fireBullet(x, Field.paddleY - 6 - sp * World.dt * steps, math.pi / 2, sp);
  final contact = w.t + World.dt * steps;
  final press = contact + inputLag + after;
  var pressed = false;
  final events = run(w, 0.5, before: () {
    if (!pressed && w.t + World.dt >= press - 0.2) {
      w.pressAction(press);
      pressed = true;
    }
  });
  if (events.whereType<PlayerHurt>().isNotEmpty) return 'hurt';
  final parries = events.whereType<ParrySucceeded>().where((e) => e.target == ParryTarget.bullet).toList();
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

  test('敵弾も接触の後に押して成立する: 補正 36ms でも接触ちょうどに押せば JUST (#94)', () {
    expect(bulletResultFor(0.036, 0), ParryGrade.just);
    expect(bulletResultFor(0.036, 0.005), ParryGrade.just);
    expect(bulletResultFor(0.036, 0.02), ParryGrade.perfect);
    expect(bulletResultFor(0.036, 0.05), 'hurt');
  });

  test('補正 0 でも、敵弾は接触の後 0.03 秒以内なら撃ち返せる (#94)', () {
    expect(bulletResultFor(0, 0), ParryGrade.just);
    expect(bulletResultFor(0, 0.02), ParryGrade.perfect);
    expect(bulletResultFor(0, 0.05), 'hurt');
    expect(bulletResultFor(0, -0.05), ParryGrade.good); // 接触の前に押した
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
}
