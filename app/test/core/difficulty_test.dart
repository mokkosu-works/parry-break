import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:parry_break/core/blocks/turret.dart';
import 'package:parry_break/core/core.dart';

import 'helpers.dart';

/// [rows] の 1 ウェーブを [difficulty] で始め、カウントダウンを済ませた World。
World gunWorld(List<String> rows, Difficulty difficulty, {int level = 30}) {
  final w = World(mode: SingleWaveMode(rows, difficulty: level), difficulty: difficulty, inputLag: 0)..start();
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

    test('ウェーブごとのバランスの上書きがあっても、難易度の上書きは残る', () {
      final mode = SingleWaveMode([_row]);
      final w = World(mode: mode, difficulty: Difficulty.easy)..start();
      expect(w.tuning.parryWindow, Difficulty.easy.tuning['parryWindow']);
    });

    test('HARD のボスは攻撃が増え、EASY は制限時間が長い', () {
      final def = endlessContent.bosses.first;
      World boss(Difficulty d) => World(mode: endlessMode, difficulty: d)..start(fromWave: endlessContent.bossEvery);
      expect(boss(Difficulty.normal).boss!.patterns.length, def.patterns.length);
      expect(boss(Difficulty.hard).boss!.patterns.length, def.patterns.length + def.hardPatterns.length);
      expect(boss(Difficulty.easy).boss!.time, def.timeLimit + Difficulty.easy.bossTimeBonus);
      for (final b in endlessContent.bosses) {
        expect(b.hardPatterns, isNotEmpty, reason: 'boss ${b.index + 1}');
      }
    });

    test('HARD のボスは、全フェーズで NORMAL より弾が多い', () {
      double rate(int index, Difficulty d) {
        final w = World(mode: endlessMode, difficulty: d)..start(fromWave: (index + 1) * endlessContent.bossEvery);
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
}
