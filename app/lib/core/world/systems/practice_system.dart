part of '../world.dart';

/// 練習場 ([PracticeMode]): ボールの出直しと、敵弾の撃ち返しの練習で落ちてくる敵弾。
extension _PracticeSystem on World {
  /// ボールを落とした。ゲームオーバーにせず、[Tuning.practiceRespawn] 秒後にパドルの上から出直す。
  void _losePracticeBall() {
    if (practiceRespawn > 0) return;
    practiceRespawn = tuning.practiceRespawn;
    streak = 0;
  }

  void _updatePractice(double dt) {
    if (practiceRespawn > 0) {
      practiceRespawn -= dt;
      if (practiceRespawn <= 0) {
        practiceRespawn = 0;
        _resetPracticeBall();
      }
    }
    if (!(practice?.bullets ?? false)) return;
    practiceBulletT += dt;
    final iv = tuning.practiceBulletInterval;
    if (practiceBulletT < iv) return;
    practiceBulletT -= iv;
    // パドルの近くへ真下に落とす (止まっていても、少し動けば受けられる範囲)
    final x = clampD(paddle.x + aux.range(-90, 90), 24, Field.width - 24);
    fireBullet(
      x,
      Field.topY + 8,
      math.pi / 2,
      tuning.bulletSpeed(round.difficulty, round.loopMul),
    );
  }

  void _resetPracticeBall() {
    ball = Ball(
      x: paddle.x,
      y: Field.paddleY - Field.ballR - 1,
      speed: targetSpeed,
      attached: true,
    );
    lastContact = const Contact(-9, used: true);
  }

  void _setPractice(PracticeSpeed speed, bool withBullets) {
    final p = practice;
    if (p == null) return;
    p
      ..speed = speed
      ..bullets = withBullets;
    p.log.clear();
    bullets = [];
    practiceRespawn = practiceBulletT = 0;
    parry.active = false;
    _actions.clear();
    _resetPracticeBall();
  }
}
