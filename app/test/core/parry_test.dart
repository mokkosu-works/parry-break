import 'package:flutter_test/flutter_test.dart';
import 'package:ricochet/core/core.dart';

import 'helpers.dart';

/// 真下へ落ちてくるボールに対して、接触の [offset] 秒前 (負なら後) に押したときの判定。
ParryGrade? gradeFor(double offset) {
  final w = testWorld(const SingleWaveMode(['NNNNNNNNNNNNNN']));
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
    final w = testWorld(const SingleWaveMode(['NNNNNNNNNNNNNN']));
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
    expect(w.heat, inInclusiveRange(150, 160)); // JUST で +160 (その後は減衰)
  });
}
