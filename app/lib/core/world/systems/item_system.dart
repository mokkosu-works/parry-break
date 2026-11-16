part of '../world.dart';

/// アイテム (design.md 7.10): ブロックから落ちる・パドルで取る・効果。
///
/// 抽選は [World.itemRng] だけで行い、[World.rng]・[World.aux] は引かない
/// (アイテムを取らない限り、アイテムのない頃と同じ展開になる)。
extension _ItemSystem on World {
  /// 効果と落下中のアイテムを全部消す (ミス・ラウンドクリア・ラウンドの開始)。
  void _clearItems() {
    items = [];
    effects = ItemEffects();
  }

  /// ブロック [bl] が壊れた (または崩落で落ちた)。条件を満たせば、[x], [y] にアイテムを出す。
  void _maybeDropItem(Block bl, double x, double y) {
    if (!round.items || phase != WorldPhase.playing) return;
    if (bl.noItem || !bl.behavior.dropsItem) return;
    final tun = tuning;
    breaksSinceItem++;
    if (breaksSinceItem <= tun.itemGap) return;
    if (itemsSpawned >= tun.itemMaxPerRound ||
        items.length >= tun.itemMaxOnField) {
      return;
    }
    if (itemRng.next() >= tun.itemChance) return;
    final it = Item(
      _pickItemKind(),
      clampD(x, tun.itemWidth / 2, Field.width - tun.itemWidth / 2),
      y,
    );
    items.add(it);
    itemsSpawned++;
    breaksSinceItem = 0;
    emit(ItemSpawned(it));
  }

  /// 出やすさ ([Tuning.itemWeights]) に従って種類を選ぶ。
  ItemKind _pickItemKind() {
    const kinds = ItemKind.values;
    final ws = tuning.itemWeights;
    double weight(int i) => i < ws.length ? math.max(0.0, ws[i]) : 0.0;
    var total = 0.0;
    for (var i = 0; i < kinds.length; i++) {
      total += weight(i);
    }
    var r = itemRng.next() * total;
    for (var i = 0; i < kinds.length; i++) {
      r -= weight(i);
      if (r < 0) return kinds[i];
    }
    return kinds.first;
  }

  /// 効果の残り時間を進める。
  void _tickEffects(double dt) {
    final e = effects;
    if (e.wide > 0) e.wide -= dt;
    if (e.shot > 0) e.shot -= dt;
    if (e.guard > 0) e.guard -= dt;
    if (e.cool > 0) e.cool -= dt;
    if (e.blastLock > 0) e.blastLock -= dt;
  }

  /// アイテムの落下と、パドルとの接触。
  ///
  /// パリィの判定の窓の中で触れればパリィ取得。そうでなければ、敵弾と同じく接触の後の押下
  /// (0.03 秒) を待ってから通常取得にする。スタン中は取れずに素通りする (無敵中は取れる)。
  void _updateItems(double dt) {
    final p = paddle, tun = tuning;
    final t0 = t - dt;
    final hw = tun.itemWidth / 2, hh = tun.itemHeight / 2;
    for (var i = items.length - 1; i >= 0; i--) {
      if (i >= items.length) continue;
      final it = items[i];
      final tc = it.contact;
      if (tc != null) {
        if (t - inputLag - tc > tun.perfectWindow + 1e-6) {
          it.contact = null;
          if (p.stun <= 0) {
            items.removeAt(i);
            _takeItem(it, null);
          }
        }
        continue;
      }
      final y0 = it.y;
      it.y += tun.itemFallSpeed * dt;
      if (it.y - hh > Field.height) {
        items.removeAt(i);
        continue;
      }
      if (p.stun > 0) continue;
      if ((it.x - p.x).abs() > paddleWidth / 2 + hw ||
          it.y + hh < Field.paddleY ||
          it.y - hh > Field.paddleY + Field.paddleH) {
        continue;
      }
      // 接触時刻: カプセルの下端がパドルの上面に届いた割合 (横から入ったときはステップの頭)
      final fr = it.y > y0
          ? clampD((Field.paddleY - (y0 + hh)) / (it.y - y0), 0, 1)
          : 0.0;
      final tcI = t0 + dt * fr;
      final grade = _judgeContact(tcI);
      if (grade != null) {
        items.removeAt(i);
        _takeItem(it, grade);
      } else {
        it.contact = tcI;
      }
    }
  }

  /// アイテムを取った。[grade] が null なら通常取得、そうでなければパリィ取得 (効果が強くなる)。
  ///
  /// パリィ取得はノーミスパリィ連続に数えるが、パリィの成功数・PERFECT・JUST の統計
  /// (ステージの星の条件) には数えない。
  void _takeItem(Item it, ParryGrade? grade) {
    final tun = tuning, e = effects;
    final parried = grade != null;
    var points = 0;
    if (parried) {
      parry
        ..success = true
        ..cooldownUntil = 0;
      streak++;
      maxStreak = math.max(maxStreak, streak);
      points = tun.itemParryScore * mult;
      score += points;
      addCombo(
        grade == ParryGrade.just ? tun.itemJustCombo : tun.itemParryCombo,
      );
    }
    switch (it.kind) {
      case ItemKind.wide:
        e.wide = parried ? tun.wideTimeParry : tun.wideTime;
      case ItemKind.multi:
        _spawnPhantoms(
          parried ? tun.multiCountParry : tun.multiCount,
          x: paddle.x,
          life: tun.multiLife,
          random: itemRng,
        );
      case ItemKind.shot:
        e.shot = parried ? tun.shotTimeParry : tun.shotTime;
      case ItemKind.blast:
        e.blast = math.min(
          tun.blastMax,
          e.blast + (parried ? tun.blastCountParry : tun.blastCount),
        );
      case ItemKind.guard:
        // はじめの防壁が残っていれば、それは時間では消えないのでそのまま (取得の得点・演出は同じ)
        e.guard = parried ? tun.guardTimeParry : tun.guardTime;
      case ItemKind.cool:
        e.cool = parried ? tun.coolTimeParry : tun.coolTime;
    }
    emit(
      ItemTaken(
        kind: it.kind,
        grade: grade,
        x: it.x,
        paddleX: paddle.x,
        points: points,
      ),
    );
  }

  /// SHOT: パリィに成功するたびに、パドルから上へ弾を撃つ。
  void _fireShots() {
    final tun = tuning, n = tun.shotCount;
    for (var k = 0; k < n; k++) {
      final off = n == 1 ? 0.0 : (k / (n - 1) * 2 - 1) * tun.shotSpread;
      bullets.add(
        Bullet(
          x: clampD(paddle.x + off, 8, Field.width - 8),
          y: Field.paddleY - 8,
          vx: 0,
          vy: -tun.shotSpeed,
          kind: BulletKind.shot,
        )..hostile = false,
      );
    }
    emit(ShotFired(paddle.x));
  }
}
