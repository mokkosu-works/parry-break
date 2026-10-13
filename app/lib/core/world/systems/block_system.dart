part of '../world.dart';

/// ブロックの破壊、ボスのコアへのダメージ、爆発 (爆薬・ブレイカー・分身弾)。
extension _BlockSystem on World {
  void _destroyBlock(Block bl, DestroyCause cause) {
    if (bl.removed) return;
    blocks.remove(bl);
    bl.removed = true;
    final c = blockCenter(bl);
    if (bl.supported) {
      structDirty = true;
      lastBreak = c;
    }
    var pts = bl.behavior.basePoints(bl, this);
    if (cause == DestroyCause.bullet) {
      pts *= 2; // 撃ち返し弾で壊すと 2 倍
      stats.returnKills++;
    }
    final v = pts * mult;
    score += v;
    addCombo(cause == DestroyCause.pierce ? 10 : cause == DestroyCause.blast ? 4 : 2);
    if (cause == DestroyCause.ball || cause == DestroyCause.pierce) ball.flight++;
    emit(BlockDestroyed(bl, c.x, c.y, cause, v));
    bl.behavior.onDestroyed(this, bl, c.x, c.y);
    if (cause != DestroyCause.blast) _revenge(c.x, c.y);
  }

  /// 撃ち返し弾 (打ち返し): HARD では、壊されたブロックが一定の確率でパドルへ 3 方向弾を撃ってくる。
  /// パドルのすぐ近くからは撃たない (避けようがないため)。
  void _revenge(double x, double y) {
    final chance = difficulty.revengeChance;
    if (chance <= 0 || phase != WorldPhase.playing || bullets.length >= 160) return;
    if (aux.next() >= chance) return;
    if (hypot(paddle.x - x, Field.paddleY - y) < 240) return;
    final a = math.atan2(Field.paddleY - y, paddle.x - x) + aux.range(-0.06, 0.06);
    final sp = 230 * difficulty.bulletSpeed * round.loopMul;
    for (var k = -1; k <= 1; k++) {
      fireBullet(x, y, a + k * 11 * deg, sp);
    }
  }

  void _damageCore(Block core, int n) {
    if (core.removed) return;
    if (od) n *= tuning.odCoreDamageMul;
    core.hp -= n;
    core.flash = 0.15;
    final c = blockCenter(core);
    final v = 1000 * n * mult;
    score += v;
    emit(CoreDamaged(c.x, c.y, n));
    emit(Popup(c.x, c.y - 30, '+${formatScore(v)}', PopupKind.coreDamage, amount: v));
    hitstop = math.max(hitstop, 0.05);
    if (core.hp <= 0) {
      blocks.remove(core);
      core.removed = true;
      structDirty = true;
      lastBreak = c;
      slowmo = math.max(slowmo, 0.5);
      emit(CoreDestroyed(c.x, c.y));
    }
    _checkBossPhase();
  }

  void _updateBlasts(double dt) {
    for (var i = blasts.length - 1; i >= 0; i--) {
      if (i >= blasts.length) continue;
      final e = blasts[i];
      e.delay -= dt;
      if (e.delay > 0) continue;
      blasts.removeAt(i);
      _explode(e);
    }
  }

  void _explode(PendingBlast e) {
    final breaker = e.kind == BlastKind.breaker;
    emit(BlastExploded(e.x, e.y, e.r, e.kind));
    if (phase == WorldPhase.playing) {
      final hits = blocks
          .where((b) => circleRect(e.x, e.y, e.r, b.x + form.ox, b.y + form.oy, b.w, b.h))
          .toList();
      for (final b in hits) {
        if (!b.removed) b.behavior.onBlast(this, b, breaker: breaker);
      }
    }
    if (e.kind != BlastKind.bomb) return;
    final bc = blastChain;
    bc.n++;
    bc.t = 0.7;
    if (bc.n >= 3) emit(Callout(CalloutChannel.chainBlast, 'CHAIN BLAST ×${bc.n}', hold: true));
    if (bc.n >= 4) slowmo = math.max(slowmo, 0.25);
    // 破片: 下方向へ 3 発 (パリィで撃ち返せる)
    if (e.shrapnel && phase == WorldPhase.playing) {
      for (var k = -1; k <= 1; k++) {
        final a = math.pi / 2 + k * 28 * deg + aux.range(-0.1, 0.1);
        final sp = 250 * round.loopMul;
        _spawnHostile(e.x, e.y, math.cos(a) * sp, math.sin(a) * sp, BulletKind.shrapnel);
      }
    }
  }

  /// JUST パリィ後のボールがブロックに当たった: 衝撃波。
  void _triggerBreaker(double x, double y) {
    queueBlast(x, y, 0, tuning.breakerRadius, shrapnel: false, kind: BlastKind.breaker);
    hitstop = math.max(hitstop, 0.06);
    slowmo = math.max(slowmo, 0.25);
    emit(BreakerTriggered(x, y));
  }
}
