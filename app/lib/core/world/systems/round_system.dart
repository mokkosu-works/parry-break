part of '../world.dart';

/// ラウンドの開始・進行・クリア・ゲームオーバー。
extension _RoundSystem on World {
  void _loadRound(RoundSpec spec) {
    _finishCascade();
    _finishBlastChain();
    round = spec;
    tuning = spec.tuning.isEmpty ? baseTuning : baseTuning.copyWith(spec.tuning);
    rng = Mulberry32(spec.seed);
    aux = Mulberry32(spec.seed * 7 + 1);
    form
      ..ox = 0
      ..oy = 0;
    bullets = [];
    blasts = [];
    lasers = [];
    phantoms = [];
    falling = []; // ひびが入って落下待ちのものは、得点にならずに消える
    boss = null;
    blocks = [];
    switch (spec.content) {
      case LayoutContent c:
        for (var r = 0; r < c.rows.length; r++) {
          for (var col = 0; col < Field.cols; col++) {
            if (c.rows[r][col] == '.') continue;
            addBlock(c.blockIdAt(r, col), Field.gridX0 + col * Field.cellW, Field.gridY0 + r * Field.cellH);
          }
        }
      case BossContent c:
        _buildBoss(c.boss);
    }
    for (final b in List.of(blocks)) {
      b.behavior.onRoundStart(this, b);
    }
    _initSupport();
    ball = Ball(x: paddle.x, y: Field.paddleY - Field.ballR - 1, speed: targetSpeed, attached: true);
    countdown = tuning.countdown;
    roundTime = 0;
    launched = false;
    lastBlockHit = -9;
    lastContact = const Contact(-9, used: true);
    parry.active = false;
    structDirty = false;
    phase = WorldPhase.playing;
    lowest = 0;
    final b = boss;
    emit(RoundStarted(number: spec.number, loop: spec.loop, bossIndex: b?.index, introKey: spec.introKey));
    emit(b != null
        ? Banner(BannerKind.boss, value: b.index + 1)
        : Banner(BannerKind.round, value: spec.number, introKey: spec.introKey));
  }

  void _updatePlay(double dt) {
    final p = paddle, pr = parry;
    // パドル
    final px0 = p.x;
    if (p.invuln > 0) p.invuln -= dt;
    if (p.stun > 0) {
      p.stun -= dt;
    } else {
      if (input.useTarget) {
        p.x = input.targetX;
      } else {
        p.x += clampD(input.axis, -1, 1) * tuning.paddleSpeed * dt;
      }
      p.x = clampD(p.x, paddleWidth / 2, Field.width - paddleWidth / 2);
    }
    p.vx = (p.x - px0) / dt;
    // パリィ判定の窓の終了
    if (pr.active && t - pr.press > tuning.parryWindow) {
      pr.active = false;
      if (!pr.success) {
        pr.cooldownUntil = pr.press + tuning.parryCooldown;
        streak = 0;
        emit(const ParryMissed());
      }
    }
    if (countdown > 0) {
      countdown -= dt;
      if (countdown <= 0) emit(const CountdownFinished());
    }
    final active = countdown <= 0;
    if (active) {
      roundTime += dt;
      stats.playTime += dt;
      if (boss != null) {
        _updateBoss(dt);
      } else {
        // 降下: ボールが最後にブロックへ当たってから 0.5 秒間は半速
        form.oy += descentSpeed * (t - lastBlockHit < 0.5 ? 0.5 : 1) * dt;
      }
    }
    // ヒート減衰 / OVERDRIVE
    if (!ball.attached) {
      if (od) {
        odTime -= dt;
        odElapsed += dt;
        if (odTime <= 0) _endOverdrive(byHit: false);
      } else {
        final st = stage;
        if (st >= 1) heat = math.max(0, heat - tuning.heatDecay[st] * dt);
      }
    }
    _updateAllBalls(dt);
    if (phase != WorldPhase.playing) return;
    if (active) {
      for (var i = 0; i < blocks.length; i++) {
        blocks[i].behavior.update(this, blocks[i], dt);
      }
    }
    _updateBullets(dt);
    if (phase != WorldPhase.playing) return;
    _updateLasers(dt);
    _updateBlasts(dt);
    // 支えを失った塊を崩落させる
    if (structDirty) {
      structDirty = false;
      final lost = _computeSupport(init: false);
      if (lost.isNotEmpty) _collapse(lost, lastBreak);
    }
    for (final b in blocks) {
      if (b.flash > 0) b.flash -= dt;
      if (b.fall > 0) {
        final d = math.min(b.fall, 180 * dt);
        b.y += d;
        b.fall -= d;
      }
    }
    // クリア判定 (lowest は直前のステップの値 = 最後のブロックを含む)
    final annihilated = boss != null
        ? !blocks.any((b) => b.type == bossCoreId)
        : !blocks.any((b) => b.behavior.clearable);
    final cleared = annihilated ||
        switch (round.clear) {
          AnnihilateClear() => false,
          ScoreClear(:final target) => score >= target,
          SurviveClear(:final seconds) => roundTime >= seconds,
        };
    if (cleared) {
      _roundClear();
      return;
    }
    var low = 0.0;
    for (final b in blocks) {
      low = math.max(low, b.y + form.oy + b.h);
    }
    lowest = low;
    if (low >= Field.warnY) _gameOver(boss?.plunge ?? false ? 'TIME OVER' : 'BLOCKS BREACHED');
  }

  void _roundClear() {
    final m = mult, bon = <Bonus>[];
    final b = boss;
    if (b != null) bon.add(Bonus('BOSS DESTROYED', 50000 + b.time.floor() * 500));
    bon.add(Bonus('ROUND CLEAR  ×$m', 5000 * m));
    if (b == null) {
      final dist = math.max(0.0, Field.warnY - lowest).round();
      bon.add(Bonus('DISTANCE ${dist}px', dist * 20));
      if (roundTime <= 10) bon.add(Bonus('ANNIHILATION  ×$m', 20000 * m));
    }
    if (streak > 0) bon.add(Bonus('NO-MISS CHAIN $streak', streak * 500));
    if (round.ending) bon.add(const Bonus('ALL ROUNDS CLEAR', 1000000));
    for (final x in bon) {
      score += x.points;
    }
    bonuses = bon;
    // 残ったブロック (破壊不可など) は崩れ落ちる演出だけ
    final remaining = blocks;
    for (final r in remaining) {
      r.removed = true;
    }
    blocks = [];
    bullets = [];
    lasers = [];
    if (phantoms.isNotEmpty) _popPhantoms();
    phase = WorldPhase.clearing;
    clearT = 0;
    emit(RoundCleared(bonuses: bon, remaining: remaining, ending: round.ending));
  }

  void _updateClear(double dt) {
    clearT += dt;
    if (clearT <= (round.ending ? 5 : 2.8)) return;
    final next = mode.roundAt(round.number + 1);
    if (next == null) {
      phase = WorldPhase.completed;
      emit(StageCompleted(score: score));
    } else {
      _loadRound(next);
    }
  }

  void _gameOver(String reason) {
    if (phase == WorldPhase.over) return;
    phase = WorldPhase.over;
    overT = 0;
    overReason = reason;
    od = false;
    parry.active = false;
    phantoms = [];
    lasers = [];
    _finishCascade();
    _finishBlastChain();
    emit(GameOver(reason: reason, score: score, round: round.number, stats: stats));
  }
}
