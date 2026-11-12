part of '../world.dart';

/// ボス: 要塞の構築、左右の揺れ、攻撃パターン、フェーズ移行、時間切れの急降下。
extension _BossSystem on World {
  void _buildBoss(BossDef def) {
    final tpl = def.template;
    final cols = tpl.first.length;
    final left = (Field.width - cols * Field.cellW) / 2;
    for (var r = 0; r < tpl.length; r++) {
      for (var c = 0; c < cols; c++) {
        final ch = tpl[r][c];
        if (ch == '.') continue;
        final x = left + c * Field.cellW, y = Field.gridY0 + r * Field.cellH;
        if (ch == bossCoreId) {
          addBlock(
            ch,
            x,
            y,
            Field.cellW,
            Field.cellH * 2,
            def.coreHp,
          ); // コアは 2 行分の高さ
        } else {
          addBlock(ch, x, y);
        }
      }
    }
    final cores = blocks.where((b) => b.type == bossCoreId).length;
    boss = Boss(
      def: def,
      left: left,
      cols: cols,
      amp: math.max(40, (Field.width - cols * Field.cellW) / 2 - 30),
      maxHp: cores * def.coreHp,
      patterns: [
        for (final s in def.patterns) bossPatterns.create(s),
        if (difficulty == Difficulty.hard)
          for (final s in def.hardPatterns) bossPatterns.create(s),
      ],
    )..time += difficulty.bossTimeBonus;
  }

  void _updateBoss(double dt) {
    final b = boss!;
    b.t += dt;
    if (!b.plunge) {
      b.time -= dt;
      if (b.time <= 0) {
        b
          ..time = 0
          ..plunge = true;
        emit(const BossTimeOver());
        emit(const Banner(BannerKind.timeOver));
      }
    }
    b.blend = math.max(0, b.blend - dt);
    form.ox = _swayOx(b) + b.blendOx * (b.blend / Boss.ampBlendTime);
    if (b.plunge) {
      form.oy += 520 * dt; // 時間切れ: 要塞が急降下してゲームオーバー
      return;
    }
    final cores = blocks.where((x) => x.type == bossCoreId).toList();
    if (cores.isEmpty) return;
    final rate =
        const [1.0, 1.15, 1.3][b.phase - 1] *
        (1 + b.index * 0.05) *
        round.loopMul *
        difficulty.bossFireRate;
    for (final p in b.patterns) {
      if (b.phase >= p.fromPhase) p.update(this, b, cores, dt, rate);
    }
  }

  double _swayOx(Boss b) =>
      math.sin(b.t * b.def.sway) * b.amp * math.min(1, b.t / 2);

  void _checkBossPhase() {
    final b = boss;
    if (b == null) return;
    final hp = bossHp;
    if (hp <= 0) return;
    // 2/3 のような割り切れない閾値でも、ちょうどその割合になったヒットで進むように誤差を許す
    const eps = 1e-9;
    final frac = hp / b.maxHp;
    final th = b.def.phaseThresholds;
    if (b.phase == 1 && frac <= th[0] + eps) {
      b.phase = 2;
      _bossShift();
    }
    if (b.phase == 2 && frac <= th[1] + eps) {
      b.phase = 3;
      _bossShift();
    }
  }

  bool _occupied(double x, double y) => blocks.any(
    (b) =>
        x < b.x + b.w &&
        x + Field.cellW > b.x &&
        y < b.y + b.h &&
        y + Field.cellH > b.y,
  );

  /// [x], [y] (要塞の座標) の 1 マスに、ボールが重なる (次のサブステップで入りうる) か。
  bool _ballOnCell(double x, double y) {
    final sx = x + form.ox, sy = y + form.oy;
    for (final ball in [this.ball, ...phantoms]) {
      if (ball.attached) continue;
      if (rectDist(ball.x, ball.y, sx, sy, Field.cellW, Field.cellH) <
          Field.ballR + 4) {
        return true;
      }
    }
    return false;
  }

  /// フェーズ移行: コアの下に鏡面シールド、フェーズ2 では両翼に砲台を増やす。
  /// シールドはボールが重なるマスには置かない (埋まったボールがコアとの間で往復したり、
  /// 貫通で壊してコアにもう一度当たったりするため)。
  void _bossShift() {
    final b = boss!;
    emit(BossPhaseChanged(b.phase));
    emit(Banner(BannerKind.bossPhase, value: b.phase));
    for (final c in blocks.where((x) => x.type == bossCoreId).toList()) {
      final y = c.y + c.h;
      for (var k = -1; k <= 1; k++) {
        final x = c.x + k * Field.cellW;
        if (!_occupied(x, y) && !_ballOnCell(x, y)) addBlock('X', x, y);
      }
    }
    // 両翼の砲台はフェーズ2 だけで足す (弾が増えすぎないように)
    if (b.phase == 2 && b.def.reinforce > 0) {
      for (final x in [b.left - Field.cellW, b.left + b.cols * Field.cellW]) {
        if (x < 0 || x + Field.cellW > Field.width) continue;
        if (!_occupied(x, Field.gridY0)) {
          addBlock('T', x, Field.gridY0).fireT = 1.5 + aux.next();
        }
      }
    }
    var minX = Field.width, maxX = 0.0;
    for (final x in blocks) {
      minX = math.min(minX, x.x);
      maxX = math.max(maxX, x.x + x.w);
    }
    b.amp = math.max(20, math.min(minX, Field.width - maxX) - 10);
    // 揺れ幅が変わっても今の位置から始め、[Boss.ampBlendTime] かけて新しい揺れに移る
    b
      ..blendOx = form.ox - _swayOx(b)
      ..blend = Boss.ampBlendTime;
  }
}
