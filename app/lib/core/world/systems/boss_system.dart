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
          addBlock(ch, x, y, Field.cellW, Field.cellH * 2, def.coreHp); // コアは 2 行分の高さ
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
      patterns: [for (final s in def.patterns) bossPatterns.create(s)],
    );
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
    form.ox = math.sin(b.t * 0.55) * b.amp * math.min(1, b.t / 2);
    if (b.plunge) {
      form.oy += 520 * dt; // 時間切れ: 要塞が急降下してゲームオーバー
      return;
    }
    final cores = blocks.where((x) => x.type == bossCoreId).toList();
    if (cores.isEmpty) return;
    final rate = const [1.0, 1.3, 1.7][b.phase - 1] * (1 + b.index * 0.08) * wave.loopMul;
    for (final p in b.patterns) {
      if (b.phase >= p.fromPhase) p.update(this, b, cores, dt, rate);
    }
  }

  void _checkBossPhase() {
    final b = boss;
    if (b == null) return;
    final hp = bossHp;
    if (hp <= 0) return;
    final frac = hp / b.maxHp;
    final th = b.def.phaseThresholds;
    if (b.phase == 1 && frac <= th[0]) {
      b.phase = 2;
      _bossShift();
    }
    if (b.phase == 2 && frac <= th[1]) {
      b.phase = 3;
      _bossShift();
    }
  }

  bool _occupied(double x, double y) =>
      blocks.any((b) => x < b.x + b.w && x + Field.cellW > b.x && y < b.y + b.h && y + Field.cellH > b.y);

  /// フェーズ移行: コアの下に鏡面シールド、両翼に砲台を増やす。
  void _bossShift() {
    final b = boss!;
    emit(BossPhaseChanged(b.phase));
    emit(Banner(BannerKind.bossPhase, value: b.phase));
    for (final c in blocks.where((x) => x.type == bossCoreId).toList()) {
      final y = c.y + c.h;
      for (var k = -1; k <= 1; k++) {
        final x = c.x + k * Field.cellW;
        if (!_occupied(x, y)) addBlock('X', x, y);
      }
    }
    final xs = [b.left - Field.cellW, b.left + b.cols * Field.cellW];
    if (b.phase == 3) xs.addAll([b.left - 2 * Field.cellW, b.left + (b.cols + 1) * Field.cellW]);
    for (final x in xs) {
      if (x < 0 || x + Field.cellW > Field.width) continue;
      final y = b.phase == 3 ? Field.gridY0 + Field.cellH : Field.gridY0;
      if (!_occupied(x, y)) addBlock('T', x, y).fireT = 1.5 + aux.next();
    }
    var minX = Field.width, maxX = 0.0;
    for (final x in blocks) {
      minX = math.min(minX, x.x);
      maxX = math.max(maxX, x.x + x.w);
    }
    b.amp = math.max(20, math.min(minX, Field.width - maxX) - 10);
  }
}
