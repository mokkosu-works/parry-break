part of '../world.dart';

/// 発射・パリィの入力処理、パリィの判定結果、ヒートと OVERDRIVE、被弾。
extension _ParrySystem on World {
  /// 溜まった入力を、押した時刻 (シミュレーション時刻に換算) の順に処理する。
  void _processActions(double dt) {
    final t0 = t - dt;
    while (_actions.isNotEmpty) {
      if (phase != WorldPhase.playing) {
        _actions.clear();
        return;
      }
      var st = sync.toSim(_actions.first);
      if (!st.isFinite || st > t + 0.25 || st < t0 - 0.25) st = t;
      if (st > t) break; // 次のステップで処理する
      _actions.removeAt(0);
      _onAction(math.max(st, t0) - inputLag);
    }
  }

  void _onAction(double pt) {
    final b = ball, p = paddle, pr = parry;
    if (b.attached) {
      if (countdown <= 0) _launch();
      return;
    }
    if (p.stun > 0) return;
    if (pr.active || pt < pr.cooldownUntil) return;
    // 接触の「後」に押した場合も、0.03 秒以内なら PERFECT (0.012 秒以内なら JUST)
    final dl = pt - lastContact.t;
    if (!lastContact.used && dl <= tuning.perfectWindow && dl >= -tuning.parryWindow) {
      lastContact = Contact(lastContact.t, used: true);
      pr.hits = 0;
      _applyParry(_grade(dl.abs()), ParryTarget.ball, b.x, Field.paddleY);
      return;
    }
    pr
      ..active = true
      ..press = pt
      ..success = false
      ..hits = 0;
  }

  ParryGrade _grade(double ad) => ad <= tuning.justWindow
      ? ParryGrade.just
      : ad <= tuning.perfectWindow + 1e-6
          ? ParryGrade.perfect
          : ParryGrade.good;

  /// パリィ判定の窓の中で接触したか。[tc] は接触時刻。
  ParryGrade? _judgeContact(double tc) {
    final d = tc - parry.press;
    if (parry.active && paddle.stun <= 0 && d <= tuning.parryWindow + 1e-6 && d >= -tuning.perfectWindow) {
      return _grade(d.abs());
    }
    return null;
  }

  void _launch() {
    final b = ball;
    b.attached = false;
    final a = 8 * deg * (paddle.x < Field.width / 2 ? 1 : -1);
    b.speed = targetSpeed;
    b.vx = math.sin(a) * b.speed;
    b.vy = -math.cos(a) * b.speed;
    if (!launched) {
      launched = true;
      waveTime = 0;
    }
    b.flight = 0;
    emit(const BallLaunched());
  }

  void _applyParry(ParryGrade grade, ParryTarget target, double x, double y) {
    final pr = parry;
    final just = grade == ParryGrade.just, perfect = just || grade == ParryGrade.perfect;
    final wasOd = od;
    pr
      ..success = true
      ..cooldownUntil = 0
      ..hits += 1;
    streak++;
    maxStreak = math.max(maxStreak, streak);
    score += streak * 100;
    stats.parries++;
    if (perfect) stats.perfects++;
    if (just) stats.just++;
    if (target == ParryTarget.ball) {
      final b = ball;
      addHeat(just ? 160 : perfect ? 120 : 60);
      b.pierce = math.max(b.pierce, perfect ? 3 : 1);
      if (just) b.breaker = true; // 次にブロックへ当たった瞬間に衝撃波
      hitstop = math.max(hitstop, just ? 0.1 : perfect ? 0.08 : 0.05);
      if (wasOd && perfect) _spawnPhantoms(just ? 3 : 2);
    } else {
      addHeat(just ? 70 : perfect ? 50 : 25);
      hitstop = math.max(hitstop, 0.03);
    }
    if (wasOd && perfect) odTime = math.min(odTime + (just ? 2 : 1), tuning.odMaxTime);
    if (just) slowmo = math.max(slowmo, 0.15);
    emit(ParrySucceeded(grade: grade, target: target, x: x, y: y, paddleX: paddle.x, streak: streak));
    if (pr.hits >= 3) emit(Callout(CalloutChannel.multiParry, 'MULTI PARRY ×${pr.hits}'));
    if (streak >= 2) emit(Popup(paddle.x, Field.paddleY - 64, 'CHAIN $streak', PopupKind.chain));
  }

  void _startOverdrive() {
    od = true;
    heat = tuning.odHeat;
    odTime = tuning.odTime;
    odElapsed = 0;
    emit(const OverdriveStarted());
    emit(const Banner(BannerKind.overdrive));
  }

  /// OVERDRIVE の終了。残っていた分身弾はそれぞれ爆発する (OVERDRIVE FINISH)。
  void _endOverdrive({required bool byHit}) {
    od = false;
    heat = byHit ? 0 : tuning.stageMin[2];
    if (phantoms.isNotEmpty) {
      emit(const Callout(CalloutChannel.overdriveFinish, 'OVERDRIVE FINISH'));
      _popPhantoms();
    }
    emit(OverdriveEnded(byHit: byHit));
  }

  /// 敵弾・レーザーに当たった: ヒート 0、パドルがスタン。
  /// ボス戦は弾が多くヒートが貯まらないため、ヒートを 1 段階下げるだけにする。
  /// OVERDRIVE 中なら終わらせず、残り時間を減らす (尽きたら段階 4 に戻る)。
  void _hurt() {
    if (boss != null) {
      if (od) {
        odTime -= tuning.bossOdHurtPenalty;
        if (odTime <= 0) {
          _endOverdrive(byHit: true);
          heat = tuning.stageMin[3];
        }
      } else {
        heat = stage >= 1 ? tuning.stageMin[stage - 1] : 0;
      }
    } else {
      if (od) _endOverdrive(byHit: true);
      heat = 0;
    }
    paddle
      ..stun = tuning.stunTime
      ..invuln = tuning.hurtInvuln;
    // パドル付近の敵弾を消す (続けざまの被弾を防ぐ)
    final r2 = tuning.hurtClearRadius * tuning.hurtClearRadius;
    for (final u in bullets) {
      final dx = u.x - paddle.x, dy = u.y - Field.paddleY;
      if (u.hostile && dx * dx + dy * dy <= r2) u.dead = true;
    }
    parry.active = false;
    stats.hurt++;
    emit(PlayerHurt(paddle.x));
  }

  /// OVERDRIVE 中の PERFECT / JUST で分身弾を出す (同時に最大 [Tuning.phantomMax] 個)。
  void _spawnPhantoms(int n) {
    final b = ball;
    var spawned = 0;
    for (var k = 0; k < n && phantoms.length < tuning.phantomMax; k++) {
      final a = (k - (n - 1) / 2) * 26 * deg + (k == (n - 1) / 2 ? 12 * deg : 0) + aux.range(-0.06, 0.06);
      phantoms.add(Ball(
        x: b.x,
        y: Field.paddleY - Field.ballR - 2,
        vx: math.sin(a) * b.speed,
        vy: -math.cos(a) * b.speed,
        speed: b.speed,
        phantom: true,
        life: tuning.phantomLife,
      ));
      spawned++;
    }
    if (spawned > 0) emit(PhantomsSpawned(spawned));
  }

  void _popPhantoms() {
    for (final f in phantoms) {
      queueBlast(f.x, f.y, aux.range(0.03, 0.2), tuning.phantomBlastRadius, shrapnel: false, kind: BlastKind.phantom);
    }
    phantoms = [];
  }
}
