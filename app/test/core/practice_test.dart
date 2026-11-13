import 'package:flutter_test/flutter_test.dart';
import 'package:parry_break/core/core.dart';

import 'helpers.dart';

void main() {
  group('練習場 (#253)', () {
    test('ブロックもアイテムもなく、ボールを落としてもゲームオーバーにならず 1 秒後に出直す', () {
      final mode = PracticeMode();
      final w = testWorld(mode);
      expect(w.blocks, isEmpty);
      expect(w.round.items, isFalse);
      run(w, 1.1);
      w.pressAction(w.t); // 発射
      run(w, 0.1);
      expect(w.ball.attached, isFalse);
      w.ball
        ..y = Field.height - 4
        ..vy = 600;
      final events = run(w, 0.5);
      expect(events.whereType<GameOver>(), isEmpty);
      expect(w.phase, WorldPhase.playing);
      expect(w.ball.lost, isTrue);
      run(w, 0.6);
      expect(w.phase, WorldPhase.playing);
      expect(w.ball.lost, isFalse);
      expect(w.ball.attached, isTrue);
      // 出直したボールはまた発射できる
      w.pressAction(w.t);
      run(w, 0.1);
      expect(w.ball.attached, isFalse);
    });

    test('自動で 30 秒遊んでも、クリアにもゲームオーバーにもならず、FEVER TIME にも入らない', () {
      final w = testWorld(PracticeMode());
      final events = run(w, 30, before: autopilot(w));
      expect(w.phase, WorldPhase.playing);
      expect(events.whereType<RoundCleared>(), isEmpty);
      expect(events.whereType<GameOver>(), isEmpty);
      expect(events.whereType<ItemSpawned>(), isEmpty);
      expect(events.whereType<ParrySucceeded>(), isNotEmpty);
      expect(w.od, isFalse);
    });

    test('ボールの速さは 段階 1 / 段階 3 / FEVER TIME の 3 段階', () {
      final mode = PracticeMode();
      final w = testWorld(mode);
      final endless = testWorld(const SingleRoundMode(['NNNNNNNNNNNNNN']));
      expect(w.targetSpeed, endless.stageSpeedOf(0));
      w.setPractice(speed: PracticeSpeed.stage3, bullets: false);
      expect(w.targetSpeed, endless.stageSpeedOf(2));
      w.setPractice(speed: PracticeSpeed.fever, bullets: false);
      expect(w.targetSpeed, endless.odTopSpeed);
      run(w, 1.1);
      w.pressAction(w.t);
      run(w, 0.05);
      expect(w.ball.speed, closeTo(endless.odTopSpeed, 1e-6));
    });

    test('敵弾の撃ち返しの練習: ボールを出さず、敵弾が一定の間隔で落ちてきて撃ち返せる', () {
      final mode = PracticeMode(bullets: true);
      final w = testWorld(mode);
      run(w, 1.1);
      w.pressAction(w.t); // ボールは発射されない
      run(w, 0.1);
      expect(w.ballInPlay, isFalse);
      expect(w.ball.attached, isTrue);
      final events = run(
        w,
        8,
        before: () {
          final u = w.bullets.where((u) => u.hostile).firstOrNull;
          if (u == null) return;
          w.input
            ..useTarget = true
            ..targetX = u.x;
          // パドルの上面に届く少し前に押す
          final tc = w.t + (Field.paddleY - u.r - u.y) / u.vy;
          if (tc - w.t < World.dt && tc >= w.t && !w.parry.active) {
            w.pressAction(tc - 0.005);
          }
        },
      );
      final spawned = (8 / w.tuning.practiceBulletInterval).floor();
      expect(
        events
            .whereType<ParrySucceeded>()
            .where((e) => e.target == ParryTarget.bullet)
            .length,
        greaterThanOrEqualTo(spawned - 2),
      );
      expect(events.whereType<GameOver>(), isEmpty);
      expect(mode.log.length, greaterThan(0));
    });

    test('切り替えると直近の判定は消え、ボールはパドルの上から出直す', () {
      final mode = PracticeMode();
      final w = testWorld(mode);
      run(w, 6, before: autopilot(w));
      expect(mode.log.length, greaterThan(0));
      w.setPractice(speed: PracticeSpeed.stage3, bullets: false);
      expect(mode.log.length, 0);
      expect(w.ball.attached, isTrue);
      expect(mode.speed, PracticeSpeed.stage3);
    });
  });

  group('PracticeLog (#253)', () {
    test('直近 20 回の内訳と、ずれの平均・ばらつき', () {
      final log = PracticeLog();
      expect(log.mean, isNull);
      expect(log.spread, isNull);
      // 古い 5 回は押し出される
      for (var i = 0; i < 5; i++) {
        log.add(ParryGrade.good, -0.09);
      }
      for (var i = 0; i < 5; i++) {
        log.add(ParryGrade.just, 0);
      }
      for (var i = 0; i < 8; i++) {
        log.add(ParryGrade.perfect, i.isEven ? -0.02 : 0.02);
      }
      for (var i = 0; i < 4; i++) {
        log.add(ParryGrade.good, 0.05);
      }
      log
        ..add(null, -0.15)
        ..add(null, null) // 近くに何もなかった空振り
        ..add(null, 0.15);
      expect(log.length, 20);
      expect(log.count(ParryGrade.just), 5);
      expect(log.count(ParryGrade.perfect), 8);
      expect(log.count(ParryGrade.good), 4);
      expect(log.count(null), 3);
      // ずれのある 19 回: 0 ×5、±0.02 ×4 ずつ、+0.05 ×4、±0.15。合計 0.2
      const m = 0.2 / 19;
      expect(log.mean, closeTo(m, 1e-9));
      double sq(double v, int n) => (v - m) * (v - m) * n;
      final variance =
          (sq(0, 5) +
              sq(-0.02, 4) +
              sq(0.02, 4) +
              sq(0.05, 4) +
              sq(-0.15, 1) +
              sq(0.15, 1)) /
          19;
      expect(log.spread! * log.spread!, closeTo(variance, 1e-12));
    });

    test('判定のイベントから記録する', () {
      final log = PracticeLog()
        ..observe(
          const ParrySucceeded(
            grade: ParryGrade.perfect,
            target: ParryTarget.ball,
            x: 0,
            y: 0,
            paddleX: 0,
            streak: 1,
            offset: -0.018,
          ),
        )
        ..observe(const ParryMissed(offset: 0.2))
        ..observe(const PlayerHurt(0));
      expect(log.length, 2);
      expect(log.count(ParryGrade.perfect), 1);
      expect(log.count(null), 1);
      expect(log.mean, closeTo(0.091, 1e-9));
    });
  });
}
