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
  final events = run(
    w,
    0.8,
    before: () {
      if (!pressed && w.t + World.dt >= press - 0.2) {
        w.pressAction(press);
        pressed = true;
      }
    },
  );
  final parries = events.whereType<ParrySucceeded>().toList();
  return parries.isEmpty ? null : parries.single.grade;
}

/// 判定タイミング補正 [inputLag] の World で、真下へ落ちてくる敵弾の接触時刻 tc に対し、
/// 換算後の時刻 tc + inputLag + [after] に押したときの結果。被弾なら 'hurt'、何も起きなければ null。
Object? bulletResultFor(double inputLag, double after) {
  final w = testWorld(
    const SingleRoundMode(['NNNNNNNNNNNNNN']),
    inputLag: inputLag,
  );
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
  final events = run(
    w,
    0.5,
    before: () {
      if (!pressed && w.t + World.dt >= press - 0.2) {
        w.pressAction(press);
        pressed = true;
      }
    },
  );
  if (events.whereType<PlayerHurt>().isNotEmpty) return 'hurt';
  final parries = events
      .whereType<ParrySucceeded>()
      .where((e) => e.target == ParryTarget.bullet)
      .toList();
  return parries.isEmpty ? null : parries.single.grade;
}

/// ボールを真下へ落とし、[seconds] 秒後にパドルへ当てる。[press] が null でなければ、接触の [press] 秒前に押す。
List<GameEvent> dropOnPaddle(World w, double seconds, {double? press}) {
  final b = w.ball
    ..attached = false
    ..x = w.paddle.x
    ..vx = 0;
  b.speed = w.targetSpeed;
  b.vy = b.speed;
  b.y = Field.paddleY - Field.ballR - b.speed * seconds;
  final at = press == null ? null : w.t + seconds - press;
  var pressed = false;
  return run(
    w,
    seconds + 0.1,
    before: () {
      if (at != null && !pressed && w.t + World.dt >= at - 0.2) {
        w.pressAction(at);
        pressed = true;
      }
    },
  );
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
    run(
      w,
      0.4,
      before: () {
        if (!pressed && w.t + World.dt >= press - 0.2) {
          w.pressAction(press);
          pressed = true;
        }
      },
    );
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

  group('スタン明けのパドル (#128)', () {
    /// カウントダウンを終えてから [setUp] で入力を整え、スタンさせて、明けるまで進めた World を返す。
    /// スタン中は各ステップの前に [during] を呼ぶ。
    World stunThenRecover(
      void Function(World w) during, {
      void Function(World w)? setUp,
    }) {
      final w = testWorld(const SingleRoundMode(['NNNNNNNNNNNNNN']));
      run(w, 1.1);
      setUp?.call(w);
      w.paddle.stun = w.tuning.stunTime;
      while (w.paddle.stun > 0) {
        during(w);
        w.step(World.dt);
      }
      return w;
    }

    test('タッチ: スタン中の目標の動きは捨て、明けた後の入力の分だけ動く', () {
      late double x0;
      final w = stunThenRecover(
        setUp: (w) {
          w.input
            ..useTarget = true
            ..targetX = w.paddle.x;
          x0 = w.paddle.x;
        },
        // 指を右へ動かし続ける (タッチ操作と同じく、前の目標に移動量を足す)
        (w) => w.input.targetX += 20,
      );
      expect(w.paddle.x, x0); // スタンの間は止まっている
      // 明けた直後のステップ: 新しい入力がなければ動かない
      w.step(World.dt);
      expect(w.paddle.x, x0);
      // 明けた後の指の動きの分だけ動く
      w.input.targetX += 5;
      w.step(World.dt);
      expect(w.paddle.x, closeTo(x0 + 5, 1e-9));
    });

    test('キーボード: スタンが明けると、押している方向へ速さの上限どおりに動く', () {
      late double x0;
      final w = stunThenRecover(
        setUp: (w) {
          w.input
            ..useTarget = false
            ..axis = 1;
          x0 = w.paddle.x;
        },
        (w) {},
      );
      expect(w.paddle.x, x0);
      w.step(World.dt);
      expect(w.paddle.x, closeTo(x0 + w.tuning.paddleSpeed * World.dt, 1e-9));
    });
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
      w.fireBullet(
        w.paddle.x + w.paddleWidth / 2 + 6 + 10,
        Field.paddleY - 30,
        math.pi / 2,
        300,
      );
      final events = run(w, 0.5);
      expect(events.whereType<PlayerHurt>(), isEmpty);
      expect(events.whereType<Grazed>(), hasLength(1));
      expect(w.stats.graze, 1);
      expect(w.combo, c0 + 8);
      expect(w.score, s0 + 50 * m);
    });

    test('パドルから 22px より遠くを通った弾はグレイズにならない', () {
      final w = ready();
      w.fireBullet(
        w.paddle.x + w.paddleWidth / 2 + 6 + 23,
        Field.paddleY - 30,
        math.pi / 2,
        300,
      );
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
      w.fireBullet(
        w.paddle.x + w.paddleWidth / 2 + 6 + 10,
        Field.paddleY - 30,
        math.pi / 2,
        300,
      );
      expect(run(w, 0.5).whereType<Grazed>(), isEmpty);
    });
  });

  test('PERFECT の後、ブロックに当たらずパドルで通常反射すると貫通が消える (#119)', () {
    final w = testWorld(const SingleRoundMode(['NNNNNNNNNNNNNN']));
    run(w, 1.1);
    dropOnPaddle(w, 0.3, press: 0.02); // PERFECT
    expect(w.ball.pierce, 3);
    dropOnPaddle(w, 0.3); // 押さずに通常反射
    expect(w.ball.pierce, 0);
    // パリィで跳ね返したときは、そのパリィの値で上書きする
    w.ball.pierce = 3;
    dropOnPaddle(w, 0.3, press: 0.06); // GOOD
    expect(w.ball.pierce, 1);
  });

  test('接触の後に押したパリィでは、通常反射の後でも貫通が付く (#119)', () {
    final w = testWorld(const SingleRoundMode(['NNNNNNNNNNNNNN']));
    run(w, 1.1);
    dropOnPaddle(w, 0.3, press: -0.02); // 接触の 0.02 秒後に押す: PERFECT
    expect(w.ball.pierce, 3);
  });

  test('ボス戦: PERFECT の後に通常反射したボールはコアを削れない (#119)', () {
    final w = World(mode: endlessMode, inputLag: 0)
      ..start(fromRound: endlessContent.bossEvery);
    w.sync.identity();
    run(w, 1.1);
    w.bullets.clear();
    dropOnPaddle(w, 0.3, press: 0.02); // PERFECT
    expect(w.ball.pierce, 3);
    dropOnPaddle(w, 0.3); // 押さずに通常反射
    // コアの真下からコアへ当てる
    w.bullets.clear();
    final core = w.blocks.firstWhere((b) => b.type == bossCoreId);
    final o = w.blockCenter(core);
    final b = w.ball
      ..x = o.x
      ..y = o.y + core.h / 2 + Field.ballR + 2
      ..vx = 0;
    b.vy = -b.speed;
    final events = run(w, 0.1);
    expect(
      events.whereType<BlockDeflected>().where((e) => identical(e.block, core)),
      isNotEmpty,
    );
    expect(events.whereType<CoreDamaged>(), isEmpty);
  });
}
