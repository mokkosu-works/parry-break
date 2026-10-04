part of '../world.dart';

/// 崩落: 要石・ボスのコアを支点に、辺で接するブロックが支え合う。
/// 支点から辿れなくなった塊は、ひびが入ってから順に落ちる。
extension _CollapseSystem on World {
  void _initSupport() {
    for (final b in blocks) {
      b.supported = false;
    }
    _computeSupport(init: true);
  }

  /// 支点からの幅優先探索。[init] のときは支点に繋がる塊を「支えられたブロック」にする。
  /// それ以外のときは、支えられていたのに支点から辿れなくなったブロックを返す。
  List<Block> _computeSupport({required bool init}) {
    final s = blocks.where((b) => b.behavior.structural && (init || b.supported)).toList();
    final n = s.length;
    final adj = List.generate(n, (_) => <int>[]);
    for (var i = 0; i < n; i++) {
      for (var j = i + 1; j < n; j++) {
        if (_adjacent(s[i], s[j])) {
          adj[i].add(j);
          adj[j].add(i);
        }
      }
    }
    final depth = List.filled(n, -1);
    final q = <int>[];
    for (var i = 0; i < n; i++) {
      if (s[i].behavior.anchor) {
        depth[i] = 0;
        q.add(i);
      }
    }
    for (var h = 0; h < q.length; h++) {
      final i = q[h];
      for (final j in adj[i]) {
        if (depth[j] < 0) {
          depth[j] = depth[i] + 1;
          q.add(j);
        }
      }
    }
    final lost = <Block>[];
    for (var i = 0; i < n; i++) {
      if (depth[i] >= 0) {
        s[i]
          ..supported = true
          ..depth = depth[i];
      } else if (!init) {
        lost.add(s[i]);
      }
    }
    return lost;
  }

  /// 辺で接しているか (角だけの接触は含めない)。
  bool _adjacent(Block a, Block b) {
    final ox = math.min(a.x + a.w, b.x + b.w) - math.max(a.x, b.x);
    final oy = math.min(a.y + a.h, b.y + b.h) - math.max(a.y, b.y);
    return (ox.abs() <= 1.5 && oy > 2) || (oy.abs() <= 1.5 && ox > 2);
  }

  void _collapse(List<Block> list, Vec2 origin) {
    for (final b in list) {
      blocks.remove(b);
      b.removed = true;
      killBulletsOf(b); // 崩落した砲台の弾は消える
      final c = blockCenter(b);
      final d = hypot(c.x - origin.x, c.y - origin.y);
      // 壊れた位置に近い順にひびが入り、落ちる
      falling.add(PendingFall(b, 0.06 + d / 1100, origin.x, b.behavior.basePoints(b, this)));
    }
    final c = cascade;
    c.n += list.length;
    c.t = 0.9;
    if (c.n >= 5) emit(Callout(CalloutChannel.collapse, _collapseText(c.n), hold: true, level: _collapseLevel(c.n)));
    // 崩落の瓦礫が降ってくる (パリィで撃ち返せる)
    if (list.length >= 4 && phase == WorldPhase.playing) {
      final k = math.min(6, (list.length / 5).ceil());
      for (var j = 0; j < k; j++) {
        final b = list[(aux.next() * list.length).floor()];
        _spawnHostile(b.x + form.ox + b.w / 2, b.y + form.oy + b.h, aux.range(-50, 50),
            aux.range(170, 240) * wave.loopMul, BulletKind.shard);
      }
    }
    if (list.length >= 14) slowmo = math.max(slowmo, 0.35);
    emit(CollapseStarted(list.length));
  }

  static String _collapseText(int n) =>
      '${n >= 40 ? 'CATASTROPHE' : n >= 20 ? 'MEGA COLLAPSE' : 'COLLAPSE'} ×$n';

  static int _collapseLevel(int n) => n >= 40 ? 2 : n >= 20 ? 1 : 0;

  /// ひびが入ったブロックを、遅延が過ぎたものから落とす。落ち始めた時点で 1 個ずつ得点になる。
  void _updateFalling(double dt) {
    for (var i = falling.length - 1; i >= 0; i--) {
      if (i >= falling.length) continue;
      final f = falling[i];
      f.delay -= dt;
      if (f.delay > 0) continue;
      falling.removeAt(i);
      final b = f.block;
      final x = b.x + form.ox, y = b.y + form.oy;
      final cx = x + b.w / 2, cy = y + b.h / 2;
      emit(BlockFell(b, x, y, f.originX, cascade.notes));
      if (phase == WorldPhase.over) continue;
      final v = f.points * mult;
      score += v;
      addHeat(2);
      emit(Popup(cx, cy, '+${formatScore(v)}', PopupKind.score, amount: v));
      cascade.notes++;
      b.behavior.onFell(this, b, cx, cy);
    }
  }

  void _updateCombos(double dt) {
    final c = cascade;
    if (c.n > 0) {
      c.t -= dt;
      if (c.t <= 0 && falling.isEmpty) _finishCascade();
    }
    final bc = blastChain;
    if (bc.n > 0) {
      bc.t -= dt;
      if (bc.t <= 0 && blasts.isEmpty) _finishBlastChain();
    }
  }

  /// 崩落ボーナス: 0.9 秒途切れるまでの合計 n が 5 以上なら n² × 10 × 倍率。
  void _finishCascade() {
    final c = cascade;
    if (c.n <= 0) return;
    var bonus = 0;
    if (c.n >= 5 && phase != WorldPhase.over) {
      bonus = c.n * c.n * 10 * mult;
      score += bonus;
    }
    stats.bestCollapse = math.max(stats.bestCollapse, c.n);
    if (c.n >= 5) {
      emit(Callout(CalloutChannel.collapse, _collapseText(c.n),
          sub: bonus > 0 ? '+${formatScore(bonus)}' : '', release: true, level: _collapseLevel(c.n)));
    }
    c
      ..n = 0
      ..notes = 0;
  }

  /// 連鎖爆発ボーナス: 0.7 秒途切れるまでの爆発数 n が 2 以上なら n² × 300 × 倍率。
  void _finishBlastChain() {
    final bc = blastChain;
    if (bc.n <= 0) return;
    var bonus = 0;
    if (bc.n >= 2 && phase != WorldPhase.over) {
      bonus = bc.n * bc.n * 300 * mult;
      score += bonus;
    }
    stats.bestBlast = math.max(stats.bestBlast, bc.n);
    if (bc.n >= 3) {
      emit(Callout(CalloutChannel.chainBlast, 'CHAIN BLAST ×${bc.n}',
          sub: bonus > 0 ? '+${formatScore(bonus)}' : '', release: true));
    } else if (bonus > 0) {
      emit(Popup(Field.width / 2, 260, 'CHAIN BLAST ×${bc.n}  +${formatScore(bonus)}', PopupKind.chainBlast,
          amount: bonus));
    }
    bc.n = 0;
  }
}
