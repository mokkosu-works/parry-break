import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:parry_break/core/core.dart';

import 'helpers.dart';

List<Block> coresOf(World w) => w.blocks.where((b) => b.type == bossCoreId).toList();

/// エンドレスの [index] 体目のボス戦を始める (カウントダウンは済ませる)。
World bossWorld(int index) {
  final w = World(mode: endlessMode)..start(fromWave: (index + 1) * endlessContent.bossEvery);
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

void main() {
  final bosses = endlessContent.bosses;

  test('ボスは後になるほど硬く、時間あたりに削る量が増える', () {
    int hp(BossDef b) => b.coreHp * bossCoreId.allMatches(b.template.join()).length;
    for (var i = 1; i < bosses.length; i++) {
      expect(hp(bosses[i]), greaterThan(hp(bosses[i - 1])), reason: 'boss ${i + 1}');
      expect(hp(bosses[i]) / bosses[i].timeLimit, greaterThan(hp(bosses[i - 1]) / bosses[i - 1].timeLimit),
          reason: 'boss ${i + 1}');
      expect(bosses[i].sway, greaterThanOrEqualTo(bosses[i - 1].sway), reason: 'boss ${i + 1}');
    }
  });

  test('ボスごとに要塞の配置か攻撃の組み合わせが違う', () {
    final seen = <String>{};
    for (final b in bosses) {
      final key = '${b.template}|${[for (final p in b.patterns) '${p.type}@${p.fromPhase}']}';
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
      for (var i = 0; i < bosses.length; i++) [for (var p = 1; p <= 3; p++) bulletRate(i, p)],
    ];
    for (var i = 0; i < bosses.length; i++) {
      final r = rates[i];
      for (var p = 0; p < 3; p++) {
        expect(r[p], lessThanOrEqualTo(caps[i][p]), reason: 'boss ${i + 1} phase ${p + 1}: $r');
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
    final reds = [for (final u in w.bullets) if (u.red) u.x]..sort();
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
    final armor = w.blocks.firstWhere((b) => b.type == 'N' && b.y == Field.gridY0 + Field.cellH && b.x == boss.left);
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

  /// パドルの真上から敵弾を撃ち、被弾させる。
  void hitPaddle(World w) {
    w.fireBullet(w.paddle.x, Field.paddleY - 30, math.pi / 2, 300);
    expect(run(w, 0.2).whereType<PlayerHurt>(), hasLength(1));
  }

  test('ボス戦の被弾はヒートを 1 段階下げるだけ。通常のウェーブでは 0 に戻る', () {
    final w = bossWorld(0);
    w.heat = 300; // 段階 3
    hitPaddle(w);
    expect(w.heat, closeTo(w.tuning.stageMin[1], 5));
    w.heat = 50; // 段階 1 なら 0
    run(w, w.tuning.hurtInvuln);
    hitPaddle(w);
    expect(w.heat, 0);

    final n = testWorld(const SingleWaveMode(['NNNNNNNNNNNNNN']));
    run(n, 1.1);
    n.heat = 300;
    hitPaddle(n);
    expect(n.heat, 0);
  });

  test('ボス戦の OVERDRIVE は被弾で終わらず残り時間が減り、尽きたら段階 4 に戻る', () {
    final w = bossWorld(0);
    w.addHeat(w.tuning.odHeat);
    expect(w.od, isTrue);
    final before = w.odTime;
    hitPaddle(w);
    expect(w.od, isTrue);
    expect(w.odTime, inInclusiveRange(before - w.tuning.bossOdHurtPenalty - 0.25, before - w.tuning.bossOdHurtPenalty));
    w.odTime = 1;
    run(w, w.tuning.hurtInvuln);
    hitPaddle(w);
    expect(w.od, isFalse);
    expect(w.heat, closeTo(w.tuning.stageMin[3], 5));
  });

  test('OVERDRIVE 中はコアへのダメージが倍になる', () {
    final w = bossWorld(0);
    final c = coresOf(w).first;
    final hp = c.hp;
    w.damageCore(c, 1);
    expect(c.hp, hp - 1);
    w.addHeat(w.tuning.odHeat);
    w.damageCore(c, 1);
    expect(c.hp, hp - 1 - w.tuning.odCoreDamageMul);
  });
}
