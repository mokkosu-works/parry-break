// Issue #133: スコアとボーナスの計算 (design.md 4章・7章・8.2)
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:parry_break/core/core.dart';

import 'helpers.dart';

/// カウントダウンを終えた World (ボールはパドルに付いたまま。コンボは減らない)。
World ready(List<String> rows) {
  final w = testWorld(SingleRoundMode(rows));
  run(w, 1.1);
  return w;
}

/// ボールを発射した World。
World launched(List<String> rows) {
  final w = ready(rows);
  w.pressAction(w.t);
  run(w, 0.1);
  expect(w.launched, isTrue);
  return w;
}

/// 残っているブロックを壊してから 1 ステップ進め、ラウンドクリアのボーナスを返す。
List<Bonus> clearNow(World w) {
  for (final b in List.of(w.blocks)) {
    w.destroyBlock(b, DestroyCause.ball);
  }
  return run(w, World.dt).whereType<RoundCleared>().single.bonuses;
}

/// ボス戦の残りのコアをすべて壊してから 1 ステップ進め、ラウンドクリアのボーナスを返す。
List<Bonus> destroyBoss(World w) {
  for (final c in w.blocks.where((b) => b.type == bossCoreId).toList()) {
    w.damageCore(c, c.hp);
  }
  return run(w, World.dt).whereType<RoundCleared>().single.bonuses;
}

Bonus? bonus(List<Bonus> list, String prefix) {
  for (final b in list) {
    if (b.label.startsWith(prefix)) return b;
  }
  return null;
}

/// [y] (ブロックの中心の高さ) に通常ブロックを置いてボールで壊したときの得点。
int normalPoints(World w, double centerY) {
  final b = w.addBlock('N', Field.gridX0, centerY - w.form.oy - Field.cellH / 2);
  w.destroyBlock(b, DestroyCause.ball);
  return w.drainEvents().whereType<BlockDestroyed>().single.points;
}

/// パドルへ真下に落ちてくるボールを、接触の 0.005 秒前に押してパリィする (JUST)。
List<GameEvent> parryOnce(World w) {
  final b = w.ball
    ..attached = false
    ..x = w.paddle.x
    ..vx = 0
    ..pierce = 0
    ..breaker = false
    ..flight = 0;
  b.vy = b.speed;
  b.y = Field.paddleY - Field.ballR - b.speed * 0.2;
  w.parry
    ..active = false
    ..cooldownUntil = 0;
  w.pressAction(w.t + 0.2 - 0.005);
  return run(w, 0.3);
}

void main() {
  group('ラウンドクリアのボーナス', () {
    test('ROUND CLEAR は 5,000 × 倍率、DISTANCE は残り距離 × 20、NO-MISS CHAIN は連続数 × 500', () {
      final w = launched(['......N.......']);
      w
        ..combo = 300 // 段階3 (倍率 4)
        ..streak = 3;
      final blk = w.blocks.single;
      final bottom = blk.y + w.form.oy + blk.h;
      expect(w.lowest, closeTo(bottom, 1e-9));
      final dist = (Field.warnY - bottom).round();
      final before = w.score + blk.behavior.basePoints(blk, w) * w.mult;
      final bonuses = clearNow(w);
      expect(w.mult, 4);
      expect(bonus(bonuses, 'ROUND CLEAR')!.points, 5000 * 4);
      expect(bonus(bonuses, 'DISTANCE')!.label, 'DISTANCE ${dist}px');
      expect(bonus(bonuses, 'DISTANCE')!.points, dist * 20);
      expect(bonus(bonuses, 'NO-MISS CHAIN')!.points, 3 * 500);
      expect(bonus(bonuses, 'BOSS DESTROYED'), isNull);
      expect(bonus(bonuses, 'ALL ROUNDS CLEAR'), isNull);
      // ボーナスはすべて得点に入る
      expect(w.score - before, bonuses.fold<int>(0, (s, b) => s + b.points));
    });

    test('パリィの連続がなければ NO-MISS CHAIN は付かない', () {
      final w = launched(['......N.......']);
      w.streak = 0;
      expect(bonus(clearNow(w), 'NO-MISS CHAIN'), isNull);
    });

    test('10 秒以内の全消しで ANNIHILATION 20,000 × 倍率、10 秒を超えたら付かない', () {
      final inTime = launched(['......N.......']);
      inTime
        ..combo = 100 // 段階2 (倍率 2)
        ..roundTime = 10 - World.dt - 0.001; // クリアのステップで 9.999 秒
      final a = bonus(clearNow(inTime), 'ANNIHILATION');
      expect(inTime.mult, 2);
      expect(a!.points, 20000 * 2);

      final late = launched(['......N.......']);
      late.roundTime = 10 - World.dt + 0.001; // クリアのステップで 10.001 秒
      expect(bonus(clearNow(late), 'ANNIHILATION'), isNull);
    });
  });

  group('ボス撃破', () {
    World boss(int round) {
      final w = World(mode: endlessMode)..start(fromRound: round);
      w.sync.identity();
      run(w, 1.1);
      return w;
    }

    test('BOSS DESTROYED は 50,000 + 残り時間 (切り捨て) × 500。DISTANCE と ANNIHILATION は付かない', () {
      final w = boss(10);
      w.boss!.time = 37.5; // クリアのステップで 37.48 秒
      final bonuses = destroyBoss(w);
      expect(bonuses.first.label, 'BOSS DESTROYED');
      expect(bonuses.first.points, 50000 + 37 * 500);
      expect(bonus(bonuses, 'ROUND CLEAR')!.points, 5000 * w.mult);
      expect(bonus(bonuses, 'DISTANCE'), isNull);
      expect(bonus(bonuses, 'ANNIHILATION'), isNull);
      expect(bonus(bonuses, 'ALL ROUNDS CLEAR'), isNull);
    });

    test('R60 のクリアで ALL ROUNDS CLEAR +1,000,000', () {
      final w = boss(60);
      final bonuses = destroyBoss(w);
      expect(bonus(bonuses, 'ALL ROUNDS CLEAR')!.points, 1000000);
    });
  });

  group('ブロックの得点', () {
    test('通常ブロック: 上段 100・中段 150・下段 300 (デッドラインから 280px / 140px で分かれる)', () {
      final w = ready(['.............N']);
      expect(w.mult, 1);
      expect(normalPoints(w, Field.warnY - 139), 300);
      expect(normalPoints(w, Field.warnY - 140), 150);
      expect(normalPoints(w, Field.warnY - 279), 150);
      expect(normalPoints(w, Field.warnY - 280), 100);
      expect(normalPoints(w, Field.gridY0), 100);
    });

    test('通常ブロックの得点に倍率が掛かる', () {
      final w = ready(['.............N']);
      w.combo = 450; // 段階4 (倍率 8)
      expect(w.mult, 8);
      expect(normalPoints(w, Field.warnY - 100), 300 * 8);
      w.combo = 100; // 段階2 (倍率 2)
      expect(normalPoints(w, Field.warnY - 200), 150 * 2);
    });

    test('撃ち返し弾で壊すと基本点 × 2 になり、stats.returnKills が増える', () {
      final w = ready(['N............N']);
      final target = w.blocks.first;
      final base = target.behavior.basePoints(target, w);
      // ブロックの真下から、撃ち返した弾を真上へ飛ばす
      w.fireBullet(target.x + w.form.ox + target.w / 2, target.y + w.form.oy + target.h + 40, -math.pi / 2, 600);
      w.bullets.last.hostile = false;
      final s0 = w.score;
      final events = run(w, 0.2);
      final d = events.whereType<BlockDestroyed>().single;
      expect(d.cause, DestroyCause.bullet);
      expect(d.points, base * 2 * 1);
      expect(w.score - s0, base * 2);
      expect(w.stats.returnKills, 1);
    });

    test('ボールで壊したときは returnKills が増えない', () {
      final w = ready(['N............N']);
      w.destroyBlock(w.blocks.first, DestroyCause.ball);
      expect(w.stats.returnKills, 0);
    });
  });

  group('連鎖爆発ボーナス (n² × 300 × 倍率、n ≥ 2)', () {
    /// 左端に置いた爆薬の列の 1 つ目を壊し、連鎖が終わるまでの得点の増分を返す。
    (int, World) chain(String bombs) {
      final row = '${bombs.padRight(13, '.')}N';
      final w = ready([row]);
      // 破片がパドルの近くを通ってグレイズにならないよう、パドルを右端へ寄せる
      w.input
        ..useTarget = true
        ..targetX = Field.width - 60;
      run(w, World.dt);
      w.combo = 100; // 段階2 (倍率 2)。ボールはパドルに付いているので減らない
      final s0 = w.score;
      w.destroyBlock(w.blocks.first, DestroyCause.ball);
      run(w, 1.5);
      expect(w.blastChain.n, 0, reason: '連鎖の集計が終わっている');
      return (w.score - s0, w);
    }

    test('爆発 1 回ではボーナスは付かない', () {
      final (gain, w) = chain('B');
      expect(w.mult, 2);
      expect(gain, 300 * 2);
      expect(w.stats.bestBlast, 1);
    });

    test('2 回の連鎖で 2² × 300 × 倍率', () {
      final (gain, w) = chain('BB');
      expect(w.stats.bestBlast, 2);
      expect(gain, 2 * 300 * 2 + 2 * 2 * 300 * 2);
    });

    test('3 回の連鎖で 3² × 300 × 倍率', () {
      final (gain, w) = chain('BBB');
      expect(w.stats.bestBlast, 3);
      expect(gain, 3 * 300 * 2 + 3 * 3 * 300 * 2);
    });
  });

  group('跳弾ボーナス (n ≥ 8 で n² × 25 × 倍率、コンボ +2n)', () {
    /// パドルを離れてから [flight] 個壊したボールが、パドルに当たって跳ね返る (パリィはしない)。
    (List<GameEvent>, World, int) bounce(int flight) {
      final w = ready(['N............N']);
      final b = w.ball
        ..attached = false
        ..x = w.paddle.x
        ..vx = 0
        ..flight = flight;
      b.vy = b.speed;
      b.y = Field.paddleY - Field.ballR - 10;
      final s0 = w.score;
      final events = run(w, 0.1);
      expect(events.whereType<PaddleBounced>(), hasLength(1));
      expect(w.ball.flight, 0);
      return (events, w, w.score - s0);
    }

    test('n = 8 で 8² × 25 × 倍率、コンボ +16', () {
      final (events, w, gain) = bounce(8);
      final r = events.whereType<RicochetBonus>().single;
      expect(r.count, 8);
      expect(r.points, 8 * 8 * 25 * 1);
      expect(gain, 8 * 8 * 25);
      expect(w.combo, 16); // 段階1 なので減らない
      expect(w.stats.bestRicochet, 8);
    });

    test('n = 7 では付かない', () {
      final (events, w, gain) = bounce(7);
      expect(events.whereType<RicochetBonus>(), isEmpty);
      expect(gain, 0);
      expect(w.combo, 0);
    });

    test('倍率が掛かる', () {
      final w = ready(['N............N']);
      w.combo = 460; // 段階4 (倍率 8)。ボールが飛んでいる間は 22/秒で減るので、少し余裕を持たせる
      final b = w.ball
        ..attached = false
        ..x = w.paddle.x
        ..vx = 0
        ..flight = 10;
      b.vy = b.speed;
      b.y = Field.paddleY - Field.ballR - 10;
      final r = run(w, 0.1).whereType<RicochetBonus>().single;
      expect(r.points, 10 * 10 * 25 * 8);
      expect(w.combo, greaterThanOrEqualTo(450 + 20)); // +2n
    });
  });

  group('パリィの連続', () {
    test('連続数 × 100 が入り、MISS で 0 に戻る', () {
      final w = ready(['N............N']);
      var s0 = w.score;
      var events = parryOnce(w);
      expect(events.whereType<ParrySucceeded>().single.streak, 1);
      expect(w.score - s0, 100);
      s0 = w.score;
      events = parryOnce(w);
      expect(events.whereType<ParrySucceeded>().single.streak, 2);
      expect(w.score - s0, 200);
      s0 = w.score;
      events = parryOnce(w);
      expect(w.streak, 3);
      expect(w.score - s0, 300);
      // 何もないときに押す: 判定の窓が閉じて MISS
      w.ball
        ..vy = -w.ball.speed
        ..y = 300;
      w.pressAction(w.t);
      events = run(w, 0.2);
      expect(events.whereType<ParryMissed>(), hasLength(1));
      expect(w.streak, 0);
      expect(w.maxStreak, 3);
      // MISS の後は 1 から数え直す
      run(w, 0.4); // クールダウンを明ける
      s0 = w.score;
      events = parryOnce(w);
      expect(events.whereType<ParrySucceeded>().single.streak, 1);
      expect(w.score - s0, 100);
    });
  });

  group('コアのダメージ', () {
    World bossWorld() {
      final w = World(mode: endlessMode)..start(fromRound: 10);
      run(w, 1.1);
      return w;
    }

    test('1,000 × ダメージ × 倍率', () {
      final w = bossWorld();
      final c = w.blocks.firstWhere((b) => b.type == bossCoreId);
      w.combo = 100; // 倍率 2
      var s0 = w.score;
      w.damageCore(c, 1);
      expect(w.score - s0, 1000 * 1 * 2);
      s0 = w.score;
      w.damageCore(c, 2);
      expect(w.score - s0, 1000 * 2 * 2);
    });

    test('FEVER TIME 中はダメージが 2 倍になり、得点も 2 倍のダメージで数える', () {
      final w = bossWorld();
      final c = w.blocks.firstWhere((b) => b.type == bossCoreId);
      w.addCombo(w.tuning.odCombo);
      expect(w.od, isTrue);
      expect(w.mult, 16);
      final s0 = w.score;
      w.damageCore(c, 1);
      expect(w.drainEvents().whereType<CoreDamaged>().last.amount, 2);
      expect(w.score - s0, 1000 * 2 * 16);
    });
  });

  test('グレイズ: コンボ +8、50 × 倍率 (既存の parry_test.dart の「グレイズ (#130)」で確かめている)', () {
    // ここでは倍率が掛かることだけを確かめる
    final w = ready(['N............N']);
    w.combo = 100; // 倍率 2
    final s0 = w.score;
    w.fireBullet(w.paddle.x + w.paddleWidth / 2 + 6 + 10, Field.paddleY - 30, math.pi / 2, 300);
    final events = run(w, 0.5);
    expect(events.whereType<Grazed>(), hasLength(1));
    expect(w.score - s0, 50 * 2);
    expect(w.combo, 108);
  });

  test('ゲームオーバーの後に落ちた崩落ブロックと、切れた崩落の集計では得点が増えない', () {
    final w = ready(const [
      '...K..........',
      '...N..........',
      '.NNNNN........',
      '.NNNNN........',
      '..NNN........N',
    ]);
    final keystone = w.blocks.firstWhere((b) => b.type == 'K');
    w.destroyBlock(keystone, DestroyCause.ball);
    run(w, World.dt); // 崩落が始まり、ひびが入る
    expect(w.falling, isNotEmpty);
    expect(w.cascade.n, greaterThanOrEqualTo(5));
    // ボールを落としてゲームオーバーにする (まだ 1 つも落ちていない)
    w.ball
      ..attached = false
      ..vx = 0
      ..vy = 600
      ..y = Field.height + 20;
    final events = run(w, World.dt);
    expect(events.whereType<GameOver>(), hasLength(1));
    final score = events.whereType<GameOver>().single.score;
    expect(w.score, score);
    final after = run(w, 2);
    expect(after.whereType<BlockFell>(), isNotEmpty); // 落ちる演出は出る
    expect(w.score, score);
    expect(w.stats.bestCollapse, greaterThanOrEqualTo(5)); // 集計は記録に残る
  });
}
