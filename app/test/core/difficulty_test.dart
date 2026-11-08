import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:parry_break/core/blocks/turret.dart';
import 'package:parry_break/core/core.dart';

import 'helpers.dart';

/// [rows] の 1 ラウンドを [difficulty] で始め、カウントダウンを済ませた World。
World gunWorld(List<String> rows, Difficulty difficulty, {int level = 30}) {
  final w = World(mode: SingleRoundMode(rows, difficulty: level), difficulty: difficulty, inputLag: 0)..start();
  w.sync
    ..wall = 0
    ..sim = 0
    ..scale = 1;
  run(w, 1.1);
  return w;
}

/// [seconds] 秒の間に撃たれた敵弾の数 (ボールは発射しない)。
int bulletsFired(World w, double seconds) {
  final seen = Set<Bullet>.identity();
  run(w, seconds, before: () {
    for (final u in w.bullets) {
      if (u.hostile) seen.add(u);
    }
  });
  return seen.length;
}

/// 最初の斉射 (同じステップに撃たれた弾) の数。
int firstVolley(World w) {
  for (var i = 0; i < 60 * 10; i++) {
    w.step(World.dt);
    w.drainEvents();
    final n = w.bullets.where((u) => u.hostile).length;
    if (n > 0) return n;
  }
  return 0;
}

const _row = 'NNNNNNNNNNNNNN';

void main() {
  group('攻撃ブロック', () {
    test('拡散砲台は扇状に EASY/NORMAL/HARD で 3/5/9 発撃つ', () {
      for (final (d, n) in [(Difficulty.easy, 3), (Difficulty.normal, 5), (Difficulty.hard, 9)]) {
        final w = gunWorld(['......F.......', _row], d);
        expect(firstVolley(w), n, reason: d.name);
        final xs = [for (final u in w.bullets) u.vx / u.vy]..sort();
        for (var i = 1; i < xs.length; i++) {
          expect(xs[i], greaterThan(xs[i - 1]), reason: '${d.name}: 同じ向きの弾が重ならない');
        }
      }
    });

    test('連射砲台はパドルを追いかけながら連射する', () {
      final w = gunWorld(['......G.......', _row], Difficulty.normal);
      expect(firstVolley(w), 1);
      w.input
        ..useTarget = true
        ..targetX = 100;
      run(w, 0.6);
      final angles = [for (final u in w.bullets) math.atan2(u.vy, u.vx)];
      expect(angles.length, 5);
      expect(angles.toSet().length, greaterThan(1), reason: '撃つたびに狙い直す');
    });

    test('全方位砲台は輪の形に撃ち、HARD は 2 重の輪', () {
      final normal = gunWorld(['......O.......', _row], Difficulty.normal);
      expect(firstVolley(normal), 12);
      final hard = gunWorld(['......O.......', _row], Difficulty.hard);
      expect(firstVolley(hard), 16);
      run(hard, 0.3);
      expect(hard.bullets.where((u) => u.hostile).length, greaterThan(16));
    });

    test('回転砲台は撃つたびに向きを回す', () {
      final w = gunWorld(['......Z.......', _row], Difficulty.normal);
      expect(firstVolley(w), 2);
      final a0 = math.atan2(w.bullets.first.vy, w.bullets.first.vx);
      run(w, 0.25);
      final last = w.bullets.last;
      expect((math.atan2(last.vy, last.vx) - a0).abs(), greaterThan(0.1));
    });

    test('狙撃砲台は発射の直前に照準を固定し、その向きへ速い弾を撃つ', () {
      final w = gunWorld(['......P.......', _row], Difficulty.normal);
      final b = w.blocks.firstWhere((b) => b.type == 'P');
      // 照準を固定するまで進める
      while (b.fireT > SniperTurretBlock.lockTime - 0.02) {
        w.step(World.dt);
      }
      final locked = b.aim;
      // 固定した後にパドルを動かしても、照準は変わらない
      w.input
        ..useTarget = true
        ..targetX = 80;
      final volley = firstVolley(w);
      expect(volley, 1);
      final u = w.bullets.first;
      expect(math.atan2(u.vy, u.vx), closeTo(locked, 1e-9));
      expect(math.sqrt(u.vx * u.vx + u.vy * u.vy), greaterThan(w.tuning.bulletSpeed(30, 1) * 1.5));
    });

    test('攻撃ブロックを壊すと、その弾は消える', () {
      final w = gunWorld(['......F.......', _row], Difficulty.hard);
      firstVolley(w);
      final b = w.blocks.firstWhere((b) => b.type == 'F');
      w.destroyBlock(b, DestroyCause.ball);
      run(w, World.dt);
      expect(w.bullets.where((u) => identical(u.source, b)), isEmpty);
    });
  });

  group('難易度', () {
    test('同じ配置でも、弾の量は EASY < NORMAL < HARD', () {
      final rows = ['T..F..OZ..G..P', _row, _row];
      final n = [for (final d in Difficulty.values) bulletsFired(gunWorld(rows, d), 20)];
      expect(n[0], lessThan(n[1]), reason: '$n');
      expect(n[2], greaterThan(n[1] * 2), reason: '$n');
    });

    test('HARD だけ、壊したブロックが撃ち返してくる (爆風では撃たない)', () {
      int revenge(Difficulty d, DestroyCause cause) {
        final w = gunWorld([_row, _row, _row], d);
        var n = 0;
        for (final b in List.of(w.blocks).take(20)) {
          w.bullets.clear();
          w.destroyBlock(b, cause);
          n += w.bullets.where((u) => u.hostile).length;
        }
        return n;
      }

      expect(revenge(Difficulty.normal, DestroyCause.ball), 0);
      expect(revenge(Difficulty.easy, DestroyCause.pierce), 0);
      expect(revenge(Difficulty.hard, DestroyCause.blast), 0);
      final hard = revenge(Difficulty.hard, DestroyCause.ball);
      expect(hard, greaterThan(0));
      expect(hard % 3, 0, reason: '3 方向弾');
    });

    test('EASY はパリィの判定が広く、降下が遅い', () {
      final easy = gunWorld([_row], Difficulty.easy), normal = gunWorld([_row], Difficulty.normal);
      expect(easy.tuning.parryWindow, greaterThan(normal.tuning.parryWindow));
      expect(easy.tuning.perfectWindow, greaterThan(normal.tuning.perfectWindow));
      expect(easy.descentSpeed, lessThan(normal.descentSpeed));
    });

    test('ラウンドごとのバランスの上書きがあっても、難易度の上書きは残る', () {
      final mode = SingleRoundMode([_row]);
      final w = World(mode: mode, difficulty: Difficulty.easy)..start();
      expect(w.tuning.parryWindow, Difficulty.easy.tuning['parryWindow']);
    });

    test('HARD のボスは攻撃が増え、EASY は制限時間が長い', () {
      final def = endlessContent.bosses.first;
      World boss(Difficulty d) => World(mode: endlessMode, difficulty: d)..start(fromRound: endlessContent.bossEvery);
      expect(boss(Difficulty.normal).boss!.patterns.length, def.patterns.length);
      expect(boss(Difficulty.hard).boss!.patterns.length, def.patterns.length + def.hardPatterns.length);
      expect(boss(Difficulty.easy).boss!.time, def.timeLimit + Difficulty.easy.bossTimeBonus);
      for (final b in endlessContent.bosses) {
        expect(b.hardPatterns, isNotEmpty, reason: 'boss ${b.index + 1}');
      }
    });

    test('HARD のボスは、全フェーズで NORMAL より弾が多い', () {
      double rate(int index, Difficulty d) {
        final w = World(mode: endlessMode, difficulty: d)..start(fromRound: (index + 1) * endlessContent.bossEvery);
        run(w, 1.1);
        return bulletsFired(w, 20) / 20;
      }

      for (var i = 0; i < endlessContent.bosses.length; i++) {
        expect(rate(i, Difficulty.hard), greaterThan(rate(i, Difficulty.normal) * 1.5), reason: 'boss ${i + 1}');
      }
    });

    test('NORMAL の砲台はこれまでと同じ間隔・速さで撃つ', () {
      final w = gunWorld(['......T.......', _row], Difficulty.normal, level: 20);
      final t = const Tuning();
      firstVolley(w);
      final u = w.bullets.single;
      expect(math.sqrt(u.vx * u.vx + u.vy * u.vy), closeTo(t.bulletSpeed(20, 1), 1e-9));
      expect(w.blocks.firstWhere((b) => b.type == 'T').fireT, closeTo(t.turretInterval(20, 1), 1e-9));
    });
  });

  group('倍率がかからなかった攻撃 (#126)', () {
    /// [index] 体目のボス戦 ([loop] 周目)。カウントダウンは済ませる。
    World bossAt(Difficulty d, int index, {int loop = 0}) {
      final c = endlessContent;
      final w = World(mode: endlessMode, difficulty: d)
        ..start(fromRound: loop * c.roundsPerLoop + (index + 1) * c.bossEvery);
      run(w, 1.1);
      return w;
    }

    /// [p] だけを [seconds] 秒動かし、撃ったレーザーの本数と敵弾の数を返す。
    (int, int) fire(World w, BossPattern p, double seconds) {
      final cores = w.blocks.where((b) => b.type == bossCoreId).toList();
      var lasers = 0, bullets = 0;
      for (var i = 0; i < (seconds / World.dt).round(); i++) {
        w.lasers.clear();
        w.bullets.clear();
        p.update(w, w.boss!, cores, World.dt, 1);
        lasers += w.lasers.length;
        bullets += w.bullets.length;
      }
      return (lasers, bullets);
    }

    test('ロックオン・レーザー格子の頻度は、難易度と周回で変わる', () {
      for (final make in <BossPattern Function(int)>[LaserPattern.new, LaserGridPattern.new]) {
        int n(Difficulty d, {int loop = 0}) => fire(bossAt(d, 3, loop: loop), make(1), 120).$1;
        final easy = n(Difficulty.easy), normal = n(Difficulty.normal), hard = n(Difficulty.hard);
        final name = make(1).runtimeType;
        expect(easy, lessThan(normal), reason: '$name: $easy $normal $hard');
        expect(hard, greaterThan(normal), reason: '$name: $easy $normal $hard');
        expect(n(Difficulty.normal, loop: 1), greaterThan(normal), reason: '$name: 2 周目');
      }
    });

    test('渦巻きの頻度は、難易度と周回で変わる (フェーズの倍率はかけない)', () {
      int n(Difficulty d, {int loop = 0, int phase = 1}) {
        final w = bossAt(d, 1, loop: loop);
        w.boss!.phase = phase;
        return fire(w, SpiralPattern(1), 20).$2;
      }

      final normal = n(Difficulty.normal);
      expect(n(Difficulty.easy), lessThan(normal));
      expect(n(Difficulty.hard), greaterThan(normal));
      expect(n(Difficulty.normal, loop: 1), greaterThan(normal));
      expect(n(Difficulty.normal, phase: 3), normal);
    });

    /// [d] の [rows] で [act] を行い、そのあと 2 秒の間に出た [kind] の敵弾の、出たときの速度 (vx, vy)。
    List<(double, double)> speeds(Difficulty d, List<String> rows, BulletKind kind, void Function(World) act) {
      final w = gunWorld(rows, d, level: 1);
      w.bullets.clear();
      act(w);
      final seen = <Bullet, (double, double)>{};
      run(w, 2, before: () {
        for (final u in w.bullets) {
          if (u.kind == kind) seen.putIfAbsent(u, () => (u.vx, u.vy));
        }
      });
      return seen.values.toList();
    }

    /// EASY / HARD の下向きの速さが、NORMAL の速さに難易度の弾速をかけたものになっている。
    /// [sideways] のときは横向きの速さにもかける (瓦礫の横の揺れはかけない)。
    void expectScaled(List<(double, double)> Function(Difficulty) of, {bool sideways = true}) {
      final normal = of(Difficulty.normal);
      expect(normal, isNotEmpty);
      for (final d in [Difficulty.easy, Difficulty.hard]) {
        final v = of(d);
        expect(v.length, normal.length, reason: d.name);
        for (var i = 0; i < v.length; i++) {
          expect(v[i].$2, closeTo(normal[i].$2 * d.bulletSpeed, 1e-6), reason: d.name);
          expect(v[i].$1, closeTo(normal[i].$1 * (sideways ? d.bulletSpeed : 1), 1e-6), reason: d.name);
        }
      }
    }

    void bomb(World w) => w.queueBlast(Field.width / 2, 600, 0, 10, shrapnel: true, kind: BlastKind.bomb);

    test('爆発の破片の速さに、難易度の弾速がかかる', () {
      expectScaled((d) => speeds(d, [_row], BulletKind.shrapnel, bomb));
      for (final (vx, vy) in speeds(Difficulty.normal, [_row], BulletKind.shrapnel, bomb)) {
        expect(math.sqrt(vx * vx + vy * vy), closeTo(250, 1e-6), reason: 'NORMAL はこれまでと同じ');
      }
    });

    test('崩落の瓦礫の速さに、難易度の弾速がかかる', () {
      const rows = ['...K......K...', '...N......N...', '.NNNNN..NNNNN.', '.NNNNN..NNNNN.'];
      expectScaled((d) => speeds(d, rows, BulletKind.shard, (w) {
            // 爆風で壊す (HARD の撃ち返しで乱数の順番が変わらないように)
            w.destroyBlock(w.blocks.firstWhere((b) => b.type == 'K'), DestroyCause.blast);
          }), sideways: false);
    });

    test('鏡面が跳ね返す弾の速さに、難易度の弾速がかかる', () {
      double speed(Difficulty d) {
        final w = gunWorld(['......X.......', _row], d);
        final m = w.blocks.firstWhere((b) => b.type == 'X');
        final c = w.blockCenter(m);
        final u = Bullet(x: c.x, y: c.y, vx: 0, vy: -400, kind: BulletKind.bullet)..hostile = false;
        m.behavior.onReturnedBullet(w, m, u);
        expect(u.hostile, isTrue);
        return math.sqrt(u.vx * u.vx + u.vy * u.vy);
      }

      const t = Tuning();
      for (final d in Difficulty.values) {
        expect(speed(d), closeTo(t.mirrorReturnSpeed * d.bulletSpeed, 1e-6), reason: d.name);
      }
    });
  });
}
