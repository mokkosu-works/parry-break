import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:parry_break/core/core.dart';

import 'helpers.dart';

List<Block> coresOf(World w) =>
    w.blocks.where((b) => b.type == bossCoreId).toList();

/// エンドレスの [index] 体目のボス戦を始める (カウントダウンは済ませる)。
World bossWorld(int index) {
  final w = World(mode: endlessMode)
    ..start(fromRound: (index + 1) * endlessContent.bossEvery);
  run(w, 1.1);
  return w;
}

/// [index] 体目のボスを [phase] まで削り、30 秒間に撃たれた敵弾の数 (1 秒あたり) を返す。
/// ボールは発射せず、パドルも動かさない。
double bulletRate(int index, int phase) {
  final w = bossWorld(index);
  for (var p = 2; p <= phase; p++) {
    var left = w.bossHp - (w.boss!.maxHp * (p == 2 ? 0.6 : 0.3)).floor();
    for (final c in coresOf(w)) {
      final d = math.min(left, c.hp - 1);
      if (d > 0) {
        w.damageCore(c, d);
        left -= d;
      }
    }
    run(w, 0.05);
  }
  expect(w.boss!.phase, phase);
  final seen = Set<Bullet>.identity();
  for (var k = 0; k < 30 * 60; k++) {
    w.step(World.dt);
    w.drainEvents();
    for (final u in w.bullets) {
      if (u.hostile) seen.add(u);
    }
  }
  return seen.length / 30;
}

/// ボスの残り HP が [target] になるまで、コアを壊さないように削る。
void damageTo(World w, int target) {
  var left = w.bossHp - target;
  for (final c in coresOf(w)) {
    final d = math.min(left, c.hp - 1);
    if (d > 0) {
      w.damageCore(c, d);
      left -= d;
    }
  }
  expect(w.bossHp, target);
}

/// フェーズが進む残り HP (合計の 2/3・1/3 以下になる最大の値)。
(int, int) phaseHps(World w) => ((w.boss!.maxHp * 2) ~/ 3, w.boss!.maxHp ~/ 3);

/// ボールがブロックに重なっているか。
bool overlaps(World w, Ball ball, Block b) {
  final ax = b.x + w.form.ox, ay = b.y + w.form.oy;
  final nx = ball.x.clamp(ax, ax + b.w), ny = ball.y.clamp(ay, ay + b.h);
  return math.pow(ball.x - nx, 2) + math.pow(ball.y - ny, 2) <=
      Field.ballR * Field.ballR;
}

/// コアの真下からボールを真上へ飛ばし、コアに当たったステップまで進める。そのステップまでのイベントを返す。
List<GameEvent> shootCoreFromBelow(World w, Block core, {int pierce = 1}) {
  final ball = w.ball
    ..attached = false
    ..x = core.x + w.form.ox + core.w / 2
    ..y = core.y + w.form.oy + core.h + 40
    ..vx = 0
    ..vy = -w.ball.speed
    ..pierce = pierce;
  w.drainEvents();
  final events = <GameEvent>[];
  for (var k = 0; k < 60 && !events.any((e) => e is CoreDamaged); k++) {
    ball.x = core.x + w.form.ox + core.w / 2; // 揺れに合わせて真下を保つ
    w.step(World.dt);
    events.addAll(w.drainEvents());
  }
  expect(events.whereType<CoreDamaged>(), hasLength(1));
  return events;
}

void main() {
  group('ボス戦の撃ち返し弾の行き先', returnedBulletTests);

  final bosses = endlessContent.bosses;

  test('ボスは後になるほど硬く、時間あたりに削る量が増える', () {
    int hp(BossDef b) =>
        b.coreHp * bossCoreId.allMatches(b.template.join()).length;
    for (var i = 1; i < bosses.length; i++) {
      expect(
        hp(bosses[i]),
        greaterThan(hp(bosses[i - 1])),
        reason: 'boss ${i + 1}',
      );
      expect(
        hp(bosses[i]) / bosses[i].timeLimit,
        greaterThan(hp(bosses[i - 1]) / bosses[i - 1].timeLimit),
        reason: 'boss ${i + 1}',
      );
      expect(
        bosses[i].sway,
        greaterThanOrEqualTo(bosses[i - 1].sway),
        reason: 'boss ${i + 1}',
      );
    }
  });

  test('ボスごとに要塞の配置か攻撃の組み合わせが違う', () {
    final seen = <String>{};
    for (final b in bosses) {
      final key =
          '${b.template}|${[for (final p in b.patterns) '${p.type}@${p.fromPhase}']}';
      expect(seen.add(key), isTrue, reason: key);
    }
  });

  test('弾の量: ボス・フェーズごとの上限に収まり、フェーズが進むと増える', () {
    // 1 秒あたりの敵弾の数の上限 (砲台を含む。レーザーは数えない)。調整したら測り直して更新する
    const caps = [
      [2.5, 4.0, 6.0],
      [3.5, 6.5, 9.5],
      [4.0, 7.0, 11.0],
      [4.5, 7.5, 11.5],
      [5.0, 8.5, 12.0],
      [6.0, 9.5, 13.5],
    ];
    final rates = [
      for (var i = 0; i < bosses.length; i++)
        [for (var p = 1; p <= 3; p++) bulletRate(i, p)],
    ];
    for (var i = 0; i < bosses.length; i++) {
      final r = rates[i];
      for (var p = 0; p < 3; p++) {
        expect(
          r[p],
          lessThanOrEqualTo(caps[i][p]),
          reason: 'boss ${i + 1} phase ${p + 1}: $r',
        );
      }
      expect(r[1], greaterThan(r[0]), reason: 'boss ${i + 1}: $r');
      expect(r[2], greaterThan(r[1]), reason: 'boss ${i + 1}: $r');
    }
    // 最初のボスがいちばん少なく、最後のボスがいちばん多い
    for (final p in [0, 2]) {
      final col = [for (final r in rates) r[p]];
      expect(col.first, col.reduce(math.min), reason: 'phase ${p + 1}: $col');
      expect(col.last, col.reduce(math.max), reason: 'phase ${p + 1}: $col');
    }
  });

  test('全ボスの全フェーズを進めても例外が出ない', () {
    for (var i = 0; i < bosses.length; i++) {
      for (var phase = 1; phase <= 3; phase++) {
        final w = bossWorld(i);
        w.boss!.phase = phase;
        run(w, 12, before: autopilot(w));
        expect(w.boss, isNotNull, reason: 'boss ${i + 1} phase $phase');
      }
    }
  });

  test('弾の壁: 隙間を 1 か所空けて横一列に落とし、隙間の両脇は赤い弾', () {
    final w = bossWorld(2);
    w.bullets.clear();
    CurtainPattern(1).update(w, w.boss!, coresOf(w), 10, 1);
    final xs = [for (final u in w.bullets) u.x]..sort();
    expect(xs.length, 17);
    expect(w.bullets.every((u) => u.vx.abs() < 1e-9 && u.vy > 0), isTrue);
    var gapAt = 0;
    for (var i = 1; i < xs.length; i++) {
      if (xs[i] - xs[i - 1] > 60 + 1e-6) {
        expect(gapAt, 0, reason: '隙間は 1 か所');
        gapAt = i;
        expect(xs[i] - xs[i - 1], closeTo(60 * 4, 1e-6));
      }
    }
    expect(gapAt, greaterThan(0));
    final reds = [
      for (final u in w.bullets)
        if (u.red) u.x,
    ]..sort();
    expect(reds, [xs[gapAt - 1], xs[gapAt]]);
  });

  test('レーザーの格子: 等間隔に何本も同時に撃ち、間に逃げ場がある', () {
    final w = bossWorld(3);
    w.lasers.clear();
    LaserGridPattern(1).update(w, w.boss!, coresOf(w), 10, 1);
    final xs = [for (final l in w.lasers) l.x]..sort();
    expect(xs.length, greaterThanOrEqualTo(4));
    for (var i = 1; i < xs.length; i++) {
      // パドル (幅 120) が 2 本の間に収まる
      expect(xs[i] - xs[i - 1] - 40, greaterThan(w.paddleWidth + 40));
    }
  });

  test('修復: 壊された装甲を、支えのあるブロックに接する場所に作り直す', () {
    final w = bossWorld(4);
    final boss = w.boss!;
    final armor = w.blocks.firstWhere(
      (b) =>
          b.type == 'N' &&
          b.y == Field.gridY0 + Field.cellH &&
          b.x == boss.left,
    );
    w.blocks.remove(armor);
    final events = <GameEvent>[];
    final p = RepairPattern(1);
    for (var k = 0; k < 3 && !events.any((e) => e is BlockRepaired); k++) {
      p.update(w, boss, coresOf(w), 10, 1);
      events.addAll(w.drainEvents());
    }
    final fixed = events.whereType<BlockRepaired>().single.block;
    expect((fixed.x, fixed.y, fixed.type), (armor.x, armor.y, 'N'));
    expect(fixed.supported, isTrue);
    // 空きがなければ何もしない
    p.update(w, boss, coresOf(w), 10, 1);
    expect(w.drainEvents().whereType<BlockRepaired>(), isEmpty);
  });

  // design.md「ボス一覧」の新要素の説明どおりに働くか (#168)。
  test('ボス6の爆薬: 壊すと隣の装甲を吹き飛ばして破片を撒くが、爆風はコアに届かない', () {
    final w = bossWorld(5);
    final bombs = w.blocks.where((b) => b.type == 'B').toList();
    expect(bombs, hasLength(2));
    final hp = [for (final c in coresOf(w)) c.hp];
    for (final bomb in bombs) {
      final side = w.blocks.firstWhere(
        (b) =>
            b.type == 'N' &&
            b.y == bomb.y &&
            (b.x - bomb.x).abs() == Field.cellW,
      );
      w.destroyBlock(bomb, DestroyCause.ball);
      final events = run(w, 0.2);
      expect(events.whereType<BlastExploded>(), hasLength(1));
      expect(side.removed, isTrue, reason: '爆薬の隣 (コアの下の装甲) は吹き飛ぶ');
      expect(
        w.bullets.where((u) => u.kind == BulletKind.shrapnel),
        isNotEmpty,
        reason: '破片を撒く',
      );
    }
    expect(
      [for (final c in coresOf(w)) c.hp],
      hp,
      reason: '爆風 (半径 84px) はコアに届かない',
    );
  });

  /// パドルの真上から敵弾を撃ち、被弾させる。
  void hitPaddle(World w) {
    w.fireBullet(w.paddle.x, Field.paddleY - 30, math.pi / 2, 300);
    expect(run(w, 0.2).whereType<PlayerHurt>(), hasLength(1));
  }

  test('ボス戦の被弾はコンボを 1 段階下げるだけ。通常のラウンドでは 0 に戻る', () {
    final w = bossWorld(0);
    w.combo = 300; // 段階 3
    hitPaddle(w);
    expect(w.combo, closeTo(w.tuning.stageMin[1], 5));
    w.combo = 50; // 段階 1 なら 0
    run(w, w.tuning.hurtInvuln);
    hitPaddle(w);
    expect(w.combo, 0);

    final n = testWorld(const SingleRoundMode(['NNNNNNNNNNNNNN']));
    run(n, 1.1);
    n.combo = 300;
    hitPaddle(n);
    expect(n.combo, 0);
  });

  test('ボス戦の FEVER TIME は被弾で終わらず残り時間が減り、尽きたら段階 4 に戻る', () {
    final w = bossWorld(0);
    w.addCombo(w.tuning.odCombo);
    expect(w.od, isTrue);
    final before = w.odTime;
    hitPaddle(w);
    expect(w.od, isTrue);
    expect(
      w.odTime,
      inInclusiveRange(
        before - w.tuning.bossOdHurtPenalty - 0.25,
        before - w.tuning.bossOdHurtPenalty,
      ),
    );
    w.odTime = 1;
    run(w, w.tuning.hurtInvuln);
    hitPaddle(w);
    expect(w.od, isFalse);
    expect(w.combo, closeTo(w.tuning.stageMin[3], 5));
  });

  test('FEVER TIME 中はコアへのダメージが倍になる', () {
    final w = bossWorld(0);
    final c = coresOf(w).first;
    final hp = c.hp;
    w.damageCore(c, 1);
    expect(c.hp, hp - 1);
    w.addCombo(w.tuning.odCombo);
    w.damageCore(c, 1);
    expect(c.hp, hp - 1 - w.tuning.odCoreDamageMul);
  });

  test('フェーズ移行: 残り HP が合計の 2/3・1/3 ちょうどになったヒットでフェーズが進む (#103)', () {
    for (var i = 0; i < bosses.length; i++) {
      final w = bossWorld(i);
      final (hp2, hp3) = phaseHps(w);
      damageTo(w, hp2 + 1);
      expect(w.boss!.phase, 1, reason: 'boss ${i + 1}');
      damageTo(w, hp2);
      expect(
        w.boss!.phase,
        2,
        reason: 'boss ${i + 1}: 残り $hp2 / ${w.boss!.maxHp}',
      );
      damageTo(w, hp3 + 1);
      expect(w.boss!.phase, 2, reason: 'boss ${i + 1}');
      damageTo(w, hp3);
      expect(
        w.boss!.phase,
        3,
        reason: 'boss ${i + 1}: 残り $hp3 / ${w.boss!.maxHp}',
      );
    }
  });

  test('フェーズ移行: 1 回のダメージで 2 段階進むときもフェーズ2 と 3 の移行が両方起きる (#103)', () {
    // FEVER TIME 中 (2 倍) のブレイカーの爆風 (2) = 4 ダメージ
    final w = bossWorld(0);
    final c = coresOf(w).single;
    final (hp2, hp3) = phaseHps(w);
    damageTo(w, hp2 + 1);
    expect(hp2 + 1 - 2 * w.tuning.odCoreDamageMul, lessThanOrEqualTo(hp3));
    w.addCombo(w.tuning.odCombo);
    expect(w.od, isTrue);
    w.drainEvents();
    c.behavior.onBlast(w, c, breaker: true);
    final phases = [
      for (final e in w.drainEvents())
        if (e is BossPhaseChanged) e.phase,
    ];
    expect(phases, [2, 3]);
    expect(w.boss!.phase, 3);
  });

  test('フェーズ移行の鏡面シールドは、コアを下から打ったボールに重ねて置かない (#107)', () {
    final w = bossWorld(0);
    final core = coresOf(w).single;
    damageTo(w, phaseHps(w).$1 + 1);
    final events = shootCoreFromBelow(w, core);
    expect(events.whereType<BossPhaseChanged>().map((e) => e.phase), [2]);
    final mirrors = w.blocks.where((b) => b.type == 'X').toList();
    expect(mirrors, isNotEmpty, reason: 'ボールに重ならない場所には置く');
    for (final ball in [w.ball, ...w.phantoms]) {
      for (final m in mirrors) {
        expect(overlaps(w, ball, m), isFalse, reason: '(${m.x}, ${m.y})');
      }
    }
    // 貫通が尽きたボールはコアの下で往復せず、そのまま下へ離れていく
    final after = run(w, 0.5);
    expect(after.whereType<CoreDamaged>(), isEmpty);
    expect(after.whereType<BlockDeflected>(), isEmpty);
    expect(w.ball.vy, greaterThan(0));
  });

  for (final fever in [false, true]) {
    test(
      'フェーズ移行のヒットでコアに入るダメージは 1 回だけ${fever ? ' (FEVER TIME 中は 2)' : ''} (#107)',
      () {
        final w = bossWorld(0);
        final core = coresOf(w).single;
        damageTo(w, phaseHps(w).$1 + 1);
        if (fever) w.addCombo(w.tuning.odCombo);
        expect(w.od, fever);
        final hp = core.hp;
        final events = [
          ...shootCoreFromBelow(w, core, pierce: 3),
          ...run(w, 0.5),
        ];
        expect(events.whereType<BossPhaseChanged>().map((e) => e.phase), [2]);
        expect(events.whereType<CoreDamaged>(), hasLength(1));
        expect(hp - core.hp, fever ? w.tuning.odCoreDamageMul : 1);
      },
    );
  }

  test('フェーズ移行の前後で要塞の位置がつながっている (#110)', () {
    for (var i = 0; i < bosses.length; i++) {
      final w = bossWorld(i);
      final b = w.boss!;
      final (hp2, hp3) = phaseHps(w);
      for (final target in [hp2, hp3]) {
        // 揺れの端 (移行で揺れ幅が変わると最も大きく飛ぶ所) まで進める
        run(w, 2);
        while (math.sin(b.t * b.def.sway).abs() < 0.97) {
          run(w, World.dt);
        }
        final amp0 = b.amp;
        final phase0 = b.phase;
        damageTo(w, target);
        expect(b.phase, phase0 + 1, reason: 'boss ${i + 1}');
        // 通常の 1 ステップの揺れの最大
        final normal = b.def.sway * math.max(amp0, b.amp) * World.dt;
        var prev = w.form.ox;
        for (var k = 0; k < 120; k++) {
          run(w, World.dt);
          expect(
            (w.form.ox - prev).abs(),
            lessThanOrEqualTo(normal * 1.6),
            reason:
                'boss ${i + 1} phase ${b.phase} step $k: amp $amp0 -> ${b.amp}',
          );
          prev = w.form.ox;
        }
      }
    }
  });

  test('フェーズ移行後の揺れで、増援の砲台が画面の外に出ない (#110)', () {
    for (var i = 0; i < bosses.length; i++) {
      if (bosses[i].reinforce == 0) continue;
      final w = bossWorld(i);
      final b = w.boss!;
      final before = w.blocks.toSet();
      run(w, 2);
      while (math.sin(b.t * b.def.sway).abs() < 0.97) {
        run(w, World.dt);
      }
      damageTo(w, phaseHps(w).$1);
      final added = w.blocks
          .where((x) => x.type == 'T' && !before.contains(x))
          .toList();
      expect(added, hasLength(2), reason: 'boss ${i + 1}');
      run(w, Boss.ampBlendTime);
      // 1 周期以上揺らす
      for (
        var k = 0;
        k < (2 * math.pi / b.def.sway / World.dt).ceil() + 60;
        k++
      ) {
        run(w, World.dt);
        for (final t in added) {
          expect(
            t.x + w.form.ox,
            greaterThanOrEqualTo(-1e-6),
            reason: 'boss ${i + 1}',
          );
          expect(
            t.x + w.form.ox + t.w,
            lessThanOrEqualTo(Field.width + 1e-6),
            reason: 'boss ${i + 1}',
          );
        }
      }
    }
  });
}

/// パドルの真上から敵弾を落とし、接触の少し前に押して撃ち返す。撃ち返した弾を返す。
Bullet parryBulletFrom(World w, Block? source, {required bool red}) {
  w.bullets.clear();
  w.fireBullet(
    w.paddle.x,
    Field.paddleY - 30,
    math.pi / 2,
    300,
    source: source,
    red: red,
  );
  final u = w.bullets.last;
  // 弾の下端がパドル上面に触れるのは 24px / 300 = 0.08 秒後
  final press = w.t + 0.07;
  var pressed = false;
  final events = run(
    w,
    0.12,
    before: () {
      if (!pressed && w.t + World.dt >= press - 0.2) {
        w.pressAction(press);
        pressed = true;
      }
    },
  );
  expect(
    events.whereType<ParrySucceeded>().where(
      (e) => e.target == ParryTarget.bullet,
    ),
    hasLength(1),
  );
  expect(u.hostile, isFalse);
  return u;
}

/// [u] の進む向きが、[u] から [b] の中心への向きと合っているか。
bool headsTo(World w, Bullet u, Block b) {
  final o = w.blockCenter(b);
  final want = math.atan2(o.y - u.y, o.x - u.x), cur = math.atan2(u.vy, u.vx);
  return (want - cur).abs() < 0.03;
}

/// [u] から見て、自分より上にある最寄りのクリア対象ブロック。
Block nearestClearable(World w, Bullet u) {
  final cand = w.blocks
      .where((b) => b.behavior.clearable && w.blockCenter(b).y <= u.y)
      .toList();
  double d2(Block b) {
    final o = w.blockCenter(b);
    return (o.x - u.x) * (o.x - u.x) + (o.y - u.y) * (o.y - u.y);
  }

  return cand.reduce((a, b) => d2(a) <= d2(b) ? a : b);
}

void returnedBulletTests() {
  /// ボス1 (入力時刻 = シミュレーション時刻)。ボールはパドルに付けたまま、パドルの下に置いておく。
  World boss() {
    final w = World(mode: endlessMode, inputLag: 0)
      ..start(fromRound: endlessContent.bossEvery);
    w.sync.identity();
    run(w, 1.1);
    w.ball
      ..attached = false
      ..x = 40
      ..y = Field.paddleY - 300
      ..vx = 0
      ..vy = -w.ball.speed;
    return w;
  }

  test('ボスのコアが撃った赤くない弾を撃ち返すと、コアではなく最寄りのクリア対象ブロックへ向かう (#123)', () {
    final w = boss();
    final core = coresOf(w).first;
    final u = parryBulletFrom(w, core, red: false);
    expect(headsTo(w, u, core), isFalse);
    expect(headsTo(w, u, nearestClearable(w, u)), isTrue);
  });

  test('ボスの赤い弾は、これまでどおり最寄りのコアへ誘導される (#123)', () {
    final w = boss();
    final core = coresOf(w).first;
    final u = parryBulletFrom(w, core, red: true);
    expect(u.target, same(core));
    expect(headsTo(w, u, core), isTrue);
  });

  test('砲台の弾は、これまでどおり発射元の砲台へ向かう (#123)', () {
    final w = testWorld(const SingleRoundMode(['NNNNNNTNNNNNNN']));
    run(w, 1.1);
    w.ball
      ..attached = false
      ..x = 40
      ..y = Field.paddleY - 300
      ..vx = 0
      ..vy = -w.ball.speed;
    final turret = w.blocks.firstWhere((b) => b.type == 'T');
    final u = parryBulletFrom(w, turret, red: false);
    expect(headsTo(w, u, turret), isTrue);
  });
}
