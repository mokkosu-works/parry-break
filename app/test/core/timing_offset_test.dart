import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:parry_break/core/core.dart';

import 'helpers.dart';

/// 真下へ落ちてくるボールに対して、接触の [before] 秒前 (負なら後) を「判定に使う時刻」として押したときの
/// イベント。入力の時刻は判定タイミングの補正 [inputLag] の分だけ遅らせて渡す (World が差し引く)。
List<GameEvent> pressBeforeContact(double before, {double inputLag = 0}) {
  final w = testWorld(
    const SingleRoundMode(['NNNNNNNNNNNNNN']),
    inputLag: inputLag,
  );
  run(w, 1.1); // カウントダウンを終える
  final b = w.ball
    ..attached = false
    ..x = w.paddle.x
    ..vx = 0
    ..pierce = 0;
  b.speed = w.targetSpeed;
  b.vy = b.speed;
  const after = 0.5;
  b.y = Field.paddleY - Field.ballR - b.speed * after;
  final contact = w.t + after;
  final press = contact - before + inputLag;
  var pressed = false;
  return run(
    w,
    0.9,
    before: () {
      if (!pressed && w.t + World.dt >= press - 0.2) {
        w.pressAction(press);
        pressed = true;
      }
    },
  );
}

void main() {
  group('パリィのずれ (#253)', () {
    test('接触より前に押すと負 (EARLY)、後に押すと正 (LATE)', () {
      final early = pressBeforeContact(0.02).whereType<ParrySucceeded>().single;
      expect(early.grade, ParryGrade.perfect);
      expect(early.offset, closeTo(-0.02, 1e-3));

      final late = pressBeforeContact(-0.02).whereType<ParrySucceeded>().single;
      expect(late.grade, ParryGrade.perfect);
      expect(late.offset, closeTo(0.02, 1e-3));

      final good = pressBeforeContact(0.06).whereType<ParrySucceeded>().single;
      expect(good.grade, ParryGrade.good);
      expect(good.offset, closeTo(-0.06, 1e-3));

      final just = pressBeforeContact(0.005).whereType<ParrySucceeded>().single;
      expect(just.grade, ParryGrade.just);
      expect(just.offset, closeTo(-0.005, 1e-3));
    });

    test('ずれは、判定タイミングの補正を差し引いた後の入力の時刻と接触の時刻の差', () {
      for (final lag in [0.0, 0.036, 0.08]) {
        final e = pressBeforeContact(
          0.02,
          inputLag: lag,
        ).whereType<ParrySucceeded>().single;
        expect(e.grade, ParryGrade.perfect, reason: 'lag $lag');
        expect(e.offset, closeTo(-0.02, 1e-3), reason: 'lag $lag');
      }
    });

    test('敵弾の撃ち返しにもずれが付く', () {
      final w = testWorld(const SingleRoundMode(['NNNNNNNNNNNNNN']));
      run(w, 1.1);
      w.ball
        ..attached = false
        ..x = 40
        ..y = Field.paddleY - 300
        ..vx = 0
        ..vy = -w.ball.speed;
      const sp = 300.0, steps = 12.5;
      w.fireBullet(
        w.paddle.x,
        Field.paddleY - 6 - sp * World.dt * steps,
        math.pi / 2,
        sp,
      );
      final contact = w.t + World.dt * steps;
      var pressed = false;
      final events = run(
        w,
        0.5,
        before: () {
          if (!pressed && w.t + World.dt >= contact - 0.2) {
            w.pressAction(contact - 0.02);
            pressed = true;
          }
        },
      );
      final e = events.whereType<ParrySucceeded>().single;
      expect(e.target, ParryTarget.bullet);
      expect(e.offset, closeTo(-0.02, 2e-3));
    });

    test('空振り: 早すぎたときは、これから来るボールとのずれ', () {
      final e = pressBeforeContact(0.15).whereType<ParryMissed>().first;
      expect(e.offset, closeTo(-0.15, 2e-3));
    });

    test('空振り: 遅すぎたときは、跳ね返ったボールの接触とのずれ', () {
      final events = pressBeforeContact(-0.06);
      expect(events.whereType<ParrySucceeded>(), isEmpty);
      final e = events.whereType<ParryMissed>().single;
      expect(e.offset, closeTo(0.06, 2e-3));
    });

    test('空振り: 近くに何もなければ出さない', () {
      final e = pressBeforeContact(0.3).whereType<ParryMissed>().first;
      expect(e.offset, isNull);
    });
  });
}
