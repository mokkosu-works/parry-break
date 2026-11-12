// Issue #136: ブロックごとの挙動・ロックオンレーザー・ボスの時間切れ (design.md 5章・7章)
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:parry_break/core/core.dart';

import 'helpers.dart';

/// カウントダウンを終えた World (ボールはパドルに付いたまま)。
World ready(List<String> rows) {
  final w = testWorld(SingleRoundMode(rows));
  run(w, 1.1);
  return w;
}

Block cell(World w, int row, int col) => w.blocks.firstWhere(
  (b) =>
      b.x == Field.gridX0 + col * Field.cellW &&
      b.y == Field.gridY0 + row * Field.cellH,
);

/// [b] の下から、ボール [ball] を真上へ飛ばす ([dx] は中心からの横のずれ)。
void aimUp(World w, Ball ball, Block b, {double dx = 0}) {
  ball
    ..attached = false
    ..x = b.x + w.form.ox + b.w / 2 + dx
    ..y = b.y + w.form.oy + b.h + Field.ballR + 12
    ..vx = 0
    ..vy = -ball.speed;
}

/// [b] に何かが起きる (壊れる・ダメージ・弾かれる) まで 1 ステップずつ進め、そこまでのイベントを返す。
List<GameEvent> untilHit(World w, Block b, {int limit = 30}) {
  final events = <GameEvent>[];
  bool hit(GameEvent e) => switch (e) {
    BlockDestroyed(:final block) ||
    BlockDamaged(:final block) ||
    BlockDeflected(:final block) => identical(block, b),
    _ => false,
  };
  for (var i = 0; i < limit && !events.any(hit); i++) {
    w.step(World.dt);
    events.addAll(w.drainEvents());
  }
  expect(events.any(hit), isTrue, reason: 'ブロックに当たらなかった');
  return events;
}

/// ボールの向きが真下から何度ずれているか。
double degFromDown(Ball b) => (math.atan2(b.vx, b.vy) / deg).abs();

void main() {
  group('反射ブロック', () {
    (double, double) reflect() {
      final w = ready(['......R......N']);
      final r = cell(w, 0, 6);
      aimUp(w, w.ball, r);
      final events = untilHit(w, r);
      expect(events.whereType<BlockDamaged>().single.block, same(r));
      expect(r.hp, 2);
      return (w.ball.vx, w.ball.vy);
    }

    test('当たると角度が 25〜45° ずれる', () {
      final (vx, vy) = reflect();
      expect(vy, greaterThan(0)); // 跳ね返って下へ
      final a = (math.atan2(vx, vy) / deg).abs();
      expect(a, inInclusiveRange(25 - 1e-6, 45 + 1e-6));
    });

    test('同じラウンドなら毎回同じ角度になる (シード固定)', () {
      expect(reflect(), reflect());
    });

    test('分身弾は角度がずれず、乱数を引かない', () {
      final w = ready(['......R......N']);
      final r = cell(w, 0, 6);
      final f = Ball(x: 0, y: 0, speed: w.targetSpeed, phantom: true, life: 5);
      w.phantoms.add(f);
      aimUp(w, f, r);
      untilHit(w, r);
      expect(f.vy, greaterThan(0));
      expect(f.vx, closeTo(0, 1e-9)); // そのまま跳ね返る
      // ラウンドの乱数はまだ 1 つも引かれていない
      expect(w.rng.next(), Mulberry32(w.round.seed).next());
    });
  });

  group('磁力ブロック', () {
    /// 磁力ブロックの中心から右へ [dist] px の位置を真下へ進むボールの、1 ステップ後の vx。
    double pullAt(double dist) {
      final w = ready(['......M......N']);
      final m = cell(w, 0, 6);
      final cx = m.x + w.form.ox + m.w / 2, cy = m.y + w.form.oy + m.h / 2;
      w.ball
        ..attached = false
        ..x = cx + dist
        ..y = cy
        ..vx = 0
        ..vy = w.ball.speed;
      w.step(World.dt);
      return w.ball.vx;
    }

    test('半径 140px 内のボールは引き寄せられる', () {
      expect(pullAt(100), lessThan(0));
      expect(pullAt(139), lessThan(0));
    });

    test('半径の外では曲がらない', () {
      expect(pullAt(141), 0);
      expect(pullAt(200), 0);
    });
  });

  group('鏡面ブロック', () {
    test('通常のボールでははじかれ、壊れない', () {
      final w = ready(['......X......N']);
      final x = cell(w, 0, 6);
      aimUp(w, w.ball, x);
      final events = untilHit(w, x);
      expect(events.whereType<BlockDeflected>(), hasLength(1));
      expect(x.removed, isFalse);
      expect(w.ball.vy, greaterThan(0));
    });

    test('貫通弾で壊れる', () {
      final w = ready(['......X......N']);
      final x = cell(w, 0, 6);
      aimUp(w, w.ball, x);
      w.ball.pierce = 1;
      untilHit(w, x);
      expect(x.removed, isTrue);
    });

    test('ブレイカーの衝撃波で壊れる', () {
      final w = ready(['......X......N']);
      final x = cell(w, 0, 6);
      aimUp(w, w.ball, x);
      w.ball.breaker = true;
      final events = untilHit(w, x);
      expect(events.whereType<BreakerTriggered>(), hasLength(1));
      expect(x.removed, isTrue);
      expect(
        events.whereType<BlockDestroyed>().single.cause,
        DestroyCause.blast,
      );
    });

    test('FEVER TIME 中のボールで壊れる', () {
      final w = ready(['......X......N']);
      w.addCombo(w.tuning.odCombo);
      expect(w.od, isTrue);
      final x = cell(w, 0, 6);
      aimUp(w, w.ball, x);
      untilHit(w, x);
      expect(x.removed, isTrue);
    });

    test('爆薬の爆風では壊れない', () {
      final w = ready(['BX...........N']);
      w.destroyBlock(cell(w, 0, 0), DestroyCause.ball);
      expect(run(w, 0.3).whereType<BlastExploded>(), hasLength(1));
      expect(cell(w, 0, 1).removed, isFalse);
    });

    test('撃ち返し弾をパドルへ跳ね返す (敵弾に戻る)', () {
      final w = ready(['......X......N']);
      final x = cell(w, 0, 6);
      w.fireBullet(
        x.x + w.form.ox + x.w / 2 - 100,
        x.y + w.form.oy + x.h + 40,
        -math.pi / 2,
        600,
      );
      final u = w.bullets.single..hostile = false;
      u.x = x.x + w.form.ox + x.w / 2;
      final events = run(w, 0.1);
      expect(events.whereType<BulletMirrored>(), hasLength(1));
      expect(w.bullets, contains(u)); // 弾は消えない
      expect(u.hostile, isTrue);
      expect(u.vy, greaterThan(0));
      // パドルの方へ向かう
      final toPaddle = math.atan2(Field.paddleY - u.y, w.paddle.x - u.x);
      expect(math.atan2(u.vy, u.vx), closeTo(toPaddle, 0.05));
      expect(x.removed, isFalse);
    });

    test('全消しに数えない (鏡面が残っていてもクリアになる)', () {
      final w = ready(['......X......N']);
      w.destroyBlock(cell(w, 0, 13), DestroyCause.ball);
      final events = run(w, World.dt);
      expect(events.whereType<RoundCleared>(), hasLength(1));
      expect(
        events.whereType<RoundCleared>().single.remaining.map((b) => b.type),
        ['X'],
      );
    });
  });

  group('破壊不可ブロック', () {
    test('貫通弾でははじかれて壊れず、貫通回数も減らない', () {
      final w = ready(['......#......N']);
      final b = cell(w, 0, 6);
      aimUp(w, w.ball, b);
      w.ball.pierce = 2;
      final events = untilHit(w, b);
      expect(events.whereType<BlockDeflected>(), hasLength(1));
      expect(b.removed, isFalse);
      expect(w.ball.pierce, 2);
      expect(w.ball.vy, greaterThan(0));
    });

    test('爆風では壊れない', () {
      final w = ready(['B#...........N']);
      w.destroyBlock(cell(w, 0, 0), DestroyCause.ball);
      expect(run(w, 0.3).whereType<BlastExploded>(), hasLength(1));
      expect(cell(w, 0, 1).removed, isFalse);
    });

    test('FEVER TIME 中のボールでは壊れて貫通する', () {
      final w = ready(['......#......N']);
      w.addCombo(w.tuning.odCombo);
      final b = cell(w, 0, 6);
      aimUp(w, w.ball, b);
      untilHit(w, b);
      expect(b.removed, isTrue);
      expect(w.ball.vy, lessThan(0)); // 貫通して上へ進む
    });

    test('FEVER TIME 中の爆風では壊れる', () {
      final w = ready(['B#...........N']);
      w.addCombo(w.tuning.odCombo);
      final wall = cell(w, 0, 1);
      w.destroyBlock(cell(w, 0, 0), DestroyCause.ball);
      run(w, 0.3);
      expect(wall.removed, isTrue);
    });
  });

  group('分裂ブロック', () {
    test('壊すと子ブロック 3 個が下に落ちる', () {
      final w = ready(['......S......N']);
      final s = cell(w, 0, 6);
      w.destroyBlock(s, DestroyCause.ball);
      final kids = w.blocks.where((b) => b.type == 's').toList();
      expect(kids, hasLength(3));
      run(w, 0.5);
      final drops = [for (final k in kids) k.y - (s.y + 6)]..sort();
      expect(drops, [closeTo(34, 1e-6), closeTo(44, 1e-6), closeTo(44, 1e-6)]);
      for (final k in kids) {
        expect(k.fall, 0);
      }
    });

    test('子ブロックは崩落の支えに含まない', () {
      // 要石 → 分裂 → 通常ブロック、と縦につながった塊
      final w = ready(const [
        '......K......N',
        '......S.......',
        '......N.......',
      ]);
      final s = cell(w, 1, 6), n = cell(w, 2, 6);
      expect(n.supported, isTrue);
      w.destroyBlock(s, DestroyCause.ball);
      final kids = w.blocks.where((b) => b.type == 's').toList();
      expect(kids, hasLength(3));
      final events = run(w, World.dt);
      // 子ブロックが間にあっても、下の通常ブロックは支えを失って崩れる
      expect(events.whereType<CollapseStarted>().single.count, 1);
      expect(n.removed, isTrue);
      expect(kids.every((k) => !k.removed && !k.supported), isTrue);
    });
  });

  group('爆薬', () {
    test('0.07 秒後に半径 84px を爆破し、破片を 3 発出す', () {
      final w = ready(['......B......N']);
      final b = cell(w, 0, 6);
      final c = w.blockCenter(b);
      w.destroyBlock(b, DestroyCause.ball);
      w.drainEvents();
      var steps = 0;
      BlastExploded? e;
      while (e == null && steps < 20) {
        w.step(World.dt);
        steps++;
        e = w.drainEvents().whereType<BlastExploded>().firstOrNull;
      }
      // 0.07 秒 = 4.2 ステップ: 5 ステップ目に爆発する
      expect(steps, 5);
      expect(e!.r, 84);
      expect(e.kind, BlastKind.bomb);
      expect(e.x, closeTo(c.x, 1e-6));
      expect(e.y, closeTo(c.y, 1e-6));
      final shrapnel = w.bullets
          .where((u) => u.kind == BulletKind.shrapnel)
          .toList();
      expect(shrapnel, hasLength(3));
      expect(shrapnel.every((u) => u.hostile && u.vy > 0), isTrue);
    });

    test('範囲内の爆薬は誘爆し、範囲外の爆薬は誘爆しない', () {
      final chain = ready(['BB...........N']);
      chain.destroyBlock(cell(chain, 0, 0), DestroyCause.ball);
      expect(run(chain, 0.5).whereType<BlastExploded>(), hasLength(2));

      // 中心から 120px 先のブロック (近い辺までは 90px) には届かない
      final apart = ready(['B.B..........N']);
      apart.destroyBlock(cell(apart, 0, 0), DestroyCause.ball);
      expect(run(apart, 0.5).whereType<BlastExploded>(), hasLength(1));
      expect(cell(apart, 0, 2).removed, isFalse);
    });

    test('反射・磁力ブロックには 2 ダメージ', () {
      final w = ready(['RBM..........N']);
      final r = cell(w, 0, 0), m = cell(w, 0, 2);
      w.destroyBlock(cell(w, 0, 1), DestroyCause.ball);
      run(w, 0.3);
      expect(r.hp, 1);
      expect(m.hp, 1);
      expect(r.removed || m.removed, isFalse);
    });
  });

  group('要石', () {
    test('通常のボールでは 3 回で壊れる', () {
      final w = ready(['......K......N']);
      final k = cell(w, 0, 6);
      for (var i = 0; i < 2; i++) {
        aimUp(w, w.ball, k);
        untilHit(w, k);
        expect(k.removed, isFalse);
      }
      expect(k.hp, 1);
      aimUp(w, w.ball, k);
      final events = untilHit(w, k);
      expect(k.removed, isTrue);
      expect(events.whereType<KeystoneBroken>(), hasLength(1));
    });

    test('貫通弾では 1 回で壊れる', () {
      final w = ready(['......K......N']);
      final k = cell(w, 0, 6);
      aimUp(w, w.ball, k);
      w.ball.pierce = 1;
      untilHit(w, k);
      expect(k.removed, isTrue);
    });

    test('爆風では 1 回で壊れる', () {
      final w = ready(['BK...........N']);
      final k = cell(w, 0, 1);
      w.destroyBlock(cell(w, 0, 0), DestroyCause.ball);
      run(w, 0.3);
      expect(k.removed, isTrue);
    });
  });

  group('ブレイカー', () {
    test('次に当たったブロックで半径 120px の衝撃波が出て、鏡面も壊す', () {
      // 当てるのは 6 列目。7 列目の鏡面 (近い辺まで 30px) と 8 列目 (90px) は範囲内、
      // 9 列目 (150px) は範囲外
      final w = ready(['......NXNN...N']);
      final target = cell(w, 0, 6), mirror = cell(w, 0, 7);
      aimUp(w, w.ball, target);
      w.ball.breaker = true;
      final events = untilHit(w, target);
      expect(w.ball.breaker, isFalse);
      final e = events.whereType<BlastExploded>().single;
      expect(e.kind, BlastKind.breaker);
      expect(e.r, 120);
      expect(target.removed, isTrue);
      expect(mirror.removed, isTrue); // 鏡面
      expect(
        w.blocks.any((b) => b.x == Field.gridX0 + 8 * Field.cellW),
        isFalse,
      );
      expect(
        w.blocks.any((b) => b.x == Field.gridX0 + 9 * Field.cellW),
        isTrue,
      );
    });

    test('ボスのコアに 2 ダメージ', () {
      final w = World(mode: endlessMode)..start(fromRound: 10);
      w.sync.identity();
      run(w, 1.1);
      final core = w.blocks.firstWhere((b) => b.type == bossCoreId);
      final hp = core.hp;
      final ball = w.ball;
      aimUp(w, ball, core);
      ball
        ..pierce = 0
        ..breaker = true;
      final events = <GameEvent>[];
      for (
        var k = 0;
        k < 60 && !events.any((e) => e is BreakerTriggered);
        k++
      ) {
        ball.x = core.x + w.form.ox + core.w / 2; // 揺れに合わせて真下を保つ
        w.step(World.dt);
        events.addAll(w.drainEvents());
      }
      expect(events.whereType<CoreDamaged>().map((e) => e.amount), [2]);
      expect(core.hp, hp - 2);
    });
  });

  group('ロックオンレーザー', () {
    /// パドルから [dx] だけ横にレーザーを撃ち、[seconds] 秒進めたイベント。
    (World, List<GameEvent>) laser(
      double dx, {
      double seconds = 1.3,
      void Function(World w)? before,
    }) {
      final w = ready(['N............N']);
      // ボールは上へ飛ばしておく (押してもボールの発射にならないように)
      w.ball
        ..attached = false
        ..x = 40
        ..y = 300
        ..vx = 0
        ..vy = -w.ball.speed;
      w.fireLaser(w.paddle.x + dx);
      final t0 = w.t;
      final events = <GameEvent>[...w.drainEvents()];
      final n = (seconds / World.dt).round();
      for (var i = 0; i < n; i++) {
        before?.call(w);
        w.step(World.dt);
        final es = w.drainEvents();
        for (final e in es) {
          if (e is LaserFired || e is PlayerHurt) {
            // 照射と被弾は予兆の 0.85 秒が過ぎたステップで起きる
            expect(
              w.t - t0,
              inInclusiveRange(0.85 - 1e-9, 0.85 + World.dt + 1e-9),
            );
          }
        }
        events.addAll(es);
      }
      return (w, events);
    }

    test('予兆 0.85 秒の後に照射し、範囲内のパドルが被弾する', () {
      final (_, events) = laser(0);
      expect(events.whereType<LaserWarned>(), hasLength(1));
      expect(events.whereType<LaserFired>(), hasLength(1));
      expect(events.whereType<PlayerHurt>(), hasLength(1));
    });

    test('範囲 (中心から 74px 未満) の外なら被弾しない', () {
      expect(laser(73).$2.whereType<PlayerHurt>(), hasLength(1));
      expect(laser(74).$2.whereType<PlayerHurt>(), isEmpty);
    });

    test('パリィでは防げない', () {
      var pressed = false;
      final (w, events) = laser(
        0,
        before: (w) {
          if (!pressed &&
              w.lasers.isNotEmpty &&
              w.lasers.single.t >= 0.85 - 0.04) {
            w.pressAction(w.t);
            pressed = true;
          }
        },
      );
      expect(pressed, isTrue);
      expect(events.whereType<ParrySucceeded>(), isEmpty);
      expect(events.whereType<PlayerHurt>(), hasLength(1));
      expect(w.stats.hurt, 1);
    });

    test('無敵中は当たらない', () {
      final (w, events) = laser(
        0,
        before: (w) {
          if (w.paddle.invuln <= 0 && w.stats.hurt == 0) w.paddle.invuln = 2;
        },
      );
      expect(events.whereType<LaserFired>(), hasLength(1));
      expect(events.whereType<PlayerHurt>(), isEmpty);
      expect(w.stats.hurt, 0);
    });
  });

  group('ボスの時間切れ', () {
    test('残り時間が 0 で要塞が急降下し、TIME OVER でゲームオーバーになる。急降下中は砲台が撃たない', () {
      final w = World(mode: endlessMode)..start(fromRound: 10);
      run(w, 1.1);
      final boss = w.boss!..time = 0.1;
      final events = <GameEvent>[];
      while (!events.any((e) => e is BossTimeOver)) {
        expect(w.t, lessThan(10), reason: '時間切れにならない');
        w.step(World.dt);
        events.addAll(w.drainEvents());
      }
      expect(boss.plunge, isTrue);
      expect(boss.time, 0);
      final before = Set<Bullet>.identity()..addAll(w.bullets);
      final lasers = w.lasers.length;
      var oy = w.form.oy;
      final after = <GameEvent>[];
      while (w.phase == WorldPhase.playing) {
        expect(w.t, lessThan(20), reason: 'ゲームオーバーにならない');
        w.step(World.dt);
        after.addAll(w.drainEvents());
        if (w.phase == WorldPhase.playing) {
          expect(w.form.oy - oy, closeTo(520 * World.dt, 1e-6)); // 急降下
          oy = w.form.oy;
        }
        // 新しい敵弾・レーザーが出ない
        expect(w.bullets.where((u) => !before.contains(u)), isEmpty);
        expect(w.lasers.length, lessThanOrEqualTo(lasers));
      }
      expect(after.whereType<GameOver>().single.reason, 'TIME OVER');
      expect(w.overReason, 'TIME OVER');
    });
  });

  test('ブロックがデッドラインに届くと BLOCKS BREACHED でゲームオーバーになる', () {
    final w = ready(['......N......N']);
    final b = cell(w, 0, 6);
    // 下端がデッドラインの 1px 上に来るまで下ろす
    w.form.oy = Field.warnY - 1 - (b.y + b.h);
    final events = <GameEvent>[];
    var bottom = 0.0;
    while (w.phase == WorldPhase.playing) {
      expect(w.t, lessThan(5));
      bottom = b.y + w.form.oy + b.h;
      w.step(World.dt);
      events.addAll(w.drainEvents());
      if (w.phase == WorldPhase.playing) expect(bottom, lessThan(Field.warnY));
    }
    expect(w.lowest, greaterThanOrEqualTo(Field.warnY));
    expect(events.whereType<GameOver>().single.reason, 'BLOCKS BREACHED');
  });
}
