// Issue #141: ラウンド進行 (降下・コンボの減衰・FEVER TIME の時間・周回の倍率) (design.md 8.1・8.2)
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:parry_break/core/core.dart';

import 'helpers.dart';

/// カウントダウンを終えた World (ボールはパドルに付いたまま)。
World ready(List<String> rows, {int difficulty = 1, Difficulty level = Difficulty.normal}) {
  final w = World(mode: SingleRoundMode(rows, difficulty: difficulty), difficulty: level, inputLag: 0)..start();
  w.sync.identity();
  run(w, 1.1);
  return w;
}

/// ボールを何にも当たらない所で上へ飛ばし続ける (パドルから離れている間だけ減衰・FEVER TIME の時間が進む)。
void Function() keepFlying(World w) => () => w.ball
  ..attached = false
  ..x = 40
  ..y = 400
  ..vx = 0
  ..vy = -w.ball.speed;

/// 1 ステップで降下した量 (px/秒)。
double descentPerSecond(World w) {
  final oy = w.form.oy;
  w.step(World.dt);
  w.drainEvents();
  return (w.form.oy - oy) / World.dt;
}

/// 2 ラウンドあるモード。
class TwoRounds extends GameMode {
  const TwoRounds(this.first, this.second);
  final List<String> first, second;

  @override
  String get recordKey => 'test';

  @override
  RoundSpec? roundAt(int number) => switch (number) {
        1 => RoundSpec(number: 1, difficulty: 1, content: LayoutContent(first)),
        2 => RoundSpec(number: 2, difficulty: 1, content: LayoutContent(second)),
        _ => null,
      };
}

void main() {
  group('降下', () {
    test('4.5 + 0.18 × (W − 1) px/秒、上限 13px/秒', () {
      for (final (wNo, want) in [(1, 4.5), (2, 4.68), (11, 6.3), (48, 12.96), (49, 13.0), (60, 13.0)]) {
        final w = ready(['......N......N'], difficulty: wNo);
        expect(descentPerSecond(w), closeTo(want, 1e-6), reason: 'W$wNo');
      }
    });

    test('ボールがブロックに当たってから 0.5 秒は半速', () {
      final w = ready(['......N......N'], difficulty: 11);
      // ボールをブロックの真下から当てる (ブロックは壊れる。当たった時刻だけを見る)
      final b = w.blocks.first;
      w.ball
        ..attached = false
        ..x = b.x + w.form.ox + b.w / 2
        ..y = b.y + w.form.oy + b.h + Field.ballR + 4
        ..vx = 0
        ..vy = -w.ball.speed;
      w.step(World.dt);
      expect(w.lastBlockHit, w.t);
      final hit = w.lastBlockHit;
      // 以降はボールをブロックから離しておく
      final fly = keepFlying(w);
      fly();
      expect(descentPerSecond(w), closeTo(6.3 / 2, 1e-6));
      // 当たってから 0.5 秒未満は半速、0.5 秒を過ぎたら全速
      while (w.t + World.dt - hit < 0.5 - 1e-9) {
        fly();
        expect(descentPerSecond(w), closeTo(6.3 / 2, 1e-6), reason: '${w.t - hit}');
      }
      // ちょうど 0.5 秒のステップは浮動小数の誤差でどちらにもなりうるので見ない
      fly();
      descentPerSecond(w);
      fly();
      expect(w.t + World.dt - hit, greaterThan(0.5));
      expect(descentPerSecond(w), closeTo(6.3, 1e-6));
    });

    test('EASY は × 0.8', () {
      final easy = ready(['......N......N'], difficulty: 11, level: Difficulty.easy);
      expect(descentPerSecond(easy), closeTo(6.3 * 0.8, 1e-6));
      final hard = ready(['......N......N'], difficulty: 11, level: Difficulty.hard);
      expect(descentPerSecond(hard), closeTo(6.3, 1e-6));
    });

    test('カウントダウン中は降下しない', () {
      final w = World(mode: const SingleRoundMode(['......N......N']))..start();
      w.step(World.dt);
      expect(w.form.oy, 0);
    });
  });

  group('コンボの減衰', () {
    /// コンボを [combo] にし、ボールを飛ばしたまま [seconds] 秒進めた後のコンボ。
    double decayed(double combo, double seconds, {bool attached = false}) {
      final w = ready(['N............N']);
      w.combo = combo;
      run(w, seconds, before: attached ? null : keepFlying(w));
      return w.combo;
    }

    test('段階2 / 3 / 4 で −8 / −14 / −22 (/秒)', () {
      expect(decayed(200, 1), closeTo(200 - 8, 1e-6));
      expect(decayed(400, 1), closeTo(400 - 14, 1e-6));
      expect(decayed(650, 1), closeTo(650 - 22, 1e-6));
    });

    test('段階1 では減らない', () {
      expect(decayed(99, 2), 99);
      // 段階2 から減って段階1 に入ったら、そこで止まる
      final c = decayed(104, 2);
      expect(c, lessThan(100));
      expect(c, greaterThan(100 - 8 * World.dt - 1e-9));
    });

    test('ボールがパドルに付いている間は減らない', () {
      expect(decayed(400, 2, attached: true), 400);
    });
  });

  group('FEVER TIME', () {
    test('コンボ 700 で始まり、10 秒で終わってコンボ 250 に戻る', () {
      final w = ready(['N............N']);
      final fly = keepFlying(w);
      fly();
      w.addCombo(699);
      expect(w.od, isFalse);
      w.addCombo(1);
      expect(w.od, isTrue);
      expect(w.combo, 700);
      expect(w.odTime, 10);
      final t0 = w.t;
      final events = <GameEvent>[];
      while (w.od) {
        expect(w.t - t0, lessThan(11));
        fly();
        w.step(World.dt);
        events.addAll(w.drainEvents());
      }
      expect(w.t - t0, closeTo(10, World.dt + 1e-9));
      expect(events.whereType<FeverTimeEnded>().single.byHit, isFalse);
      expect(w.combo, 250);
    });

    test('FEVER TIME 中はコンボが増減しない', () {
      final w = ready(['NNN..........N']);
      w.addCombo(700);
      run(w, 1, before: keepFlying(w));
      expect(w.combo, 700); // 減衰しない
      w.destroyBlock(w.blocks.first, DestroyCause.ball);
      w.addCombo(50);
      w.addCombo(-300);
      expect(w.combo, 700);
    });

    /// FEVER TIME の残りを [left] 秒にして、接触の [offset] 秒前に押したパリィ。パリィのステップの前後の残り時間を返す。
    (ParryGrade, double, double) parryInFever(double left, double offset) {
      final w = ready(['N............N']);
      w.addCombo(700);
      w.odTime = left;
      final b = w.ball
        ..attached = false
        ..x = w.paddle.x
        ..vx = 0
        ..pierce = 0;
      b.speed = w.targetSpeed;
      b.vy = b.speed;
      b.y = Field.paddleY - Field.ballR - b.speed * 0.15;
      w.pressAction(w.t + 0.15 - offset);
      for (var i = 0; i < 40; i++) {
        final before = w.odTime;
        w.step(World.dt);
        final p = w.drainEvents().whereType<ParrySucceeded>().firstOrNull;
        if (p != null) return (p.grade, before, w.odTime);
      }
      fail('パリィにならなかった');
    }

    test('PERFECT で +1 秒、JUST で +2 秒、GOOD では増えない', () {
      final (g1, b1, a1) = parryInFever(5, 0.02);
      expect(g1, ParryGrade.perfect);
      expect(a1, closeTo(b1 - World.dt + 1, 1e-9));
      final (g2, b2, a2) = parryInFever(5, 0.005);
      expect(g2, ParryGrade.just);
      expect(a2, closeTo(b2 - World.dt + 2, 1e-9));
      final (g3, b3, a3) = parryInFever(5, 0.06);
      expect(g3, ParryGrade.good);
      expect(a3, closeTo(b3 - World.dt, 1e-9));
    });

    test('上限は 20 秒', () {
      final (g, _, a) = parryInFever(19.5, 0.005);
      expect(g, ParryGrade.just);
      expect(a, 20);
    });

    test('通常のラウンドで FEVER TIME 中に被弾すると、FEVER TIME が終わりコンボ 0 になる', () {
      final w = ready(['N............N']);
      w.addCombo(700);
      expect(w.od, isTrue);
      w.fireBullet(w.paddle.x, Field.paddleY - 30, math.pi / 2, 300);
      final events = run(w, 0.2);
      expect(events.whereType<PlayerHurt>(), hasLength(1));
      expect(events.whereType<FeverTimeEnded>().single.byHit, isTrue);
      expect(w.od, isFalse);
      expect(w.combo, 0);
    });
  });

  group('周回', () {
    World endless(int n) {
      final w = World(mode: endlessMode)..start(fromRound: n);
      return w;
    }

    test('R61 は R1 と同じ配置', () {
      final a = endless(1), b = endless(61);
      expect(b.round.loop, 1);
      expect(b.round.difficulty, 1);
      String layout(World w) => [for (final x in w.blocks) '${x.type}@${x.x},${x.y}'].join(' ');
      expect(layout(b), layout(a));
    });

    test('ボール・降下の速さが 1.15 倍', () {
      final a = endless(1), b = endless(61);
      for (var st = 0; st < 4; st++) {
        expect(b.stageSpeedOf(st), closeTo(a.stageSpeedOf(st) * 1.15, 1e-9), reason: '段階${st + 1}');
      }
      expect(b.ball.speed, closeTo(a.ball.speed * 1.15, 1e-9));
      run(a, 1.1);
      run(b, 1.1);
      expect(descentPerSecond(b), closeTo(descentPerSecond(a) * 1.15, 1e-6));
    });

    test('砲台の弾の速さが 1.15 倍、発射の間隔が ÷1.15', () {
      // 砲台のある最初のラウンド (R30 より前: 単発)
      var n = 1;
      while (!endless(n).blocks.any((b) => b.type == 'T')) {
        n++;
        expect(n, lessThan(30));
      }
      (double, double) firstShot(int round) {
        final w = endless(round);
        w.sync.identity();
        for (var i = 0; i < 60 * 30; i++) {
          w.step(World.dt);
          for (final e in w.drainEvents()) {
            if (e is BulletFired) {
              final u = w.bullets.lastWhere((u) => u.hostile && u.source?.type == 'T');
              return (math.sqrt(u.vx * u.vx + u.vy * u.vy), u.source!.fireT);
            }
          }
          // ボールを発射しないので、ブロックに当たらない。パドルは被弾しても構わない
        }
        fail('R$round の砲台が撃たなかった');
      }

      final (sp1, iv1) = firstShot(n);
      final (sp2, iv2) = firstShot(n + 60);
      expect(sp2, closeTo(sp1 * 1.15, 1e-6));
      expect(iv2, closeTo(iv1 / 1.15, 1e-9));
    });

    test('R60 のクリアで ending が付き、5 秒の演出の後に R61 が始まる', () {
      final w = endless(60);
      w.sync.identity();
      run(w, 1.1);
      for (final c in w.blocks.where((b) => b.type == bossCoreId).toList()) {
        w.damageCore(c, c.hp);
      }
      var events = run(w, World.dt);
      expect(events.whereType<RoundCleared>().single.ending, isTrue);
      events = run(w, 4.9);
      expect(events.whereType<RoundStarted>(), isEmpty);
      events = run(w, 0.2);
      final r = events.whereType<RoundStarted>().single;
      expect(r.number, 61);
      expect(r.loop, 1);
      expect(w.round.loopMul, closeTo(1.15, 1e-12));
    });

    test('R59 のクリアには ending が付かない', () {
      final w = endless(59);
      w.sync.identity();
      run(w, 1.1);
      // 分裂の子ブロックや崩落で増減するので、なくなるまで壊す
      while (w.blocks.isNotEmpty) {
        w.destroyBlock(w.blocks.first, DestroyCause.ball);
      }
      w.falling.clear();
      w.blasts.clear();
      expect(run(w, World.dt).whereType<RoundCleared>().single.ending, isFalse);
    });
  });

  test('ラウンドが変わるとき、落下待ちのブロック (崩落のひび) は得点にならずに消える', () {
    final w = testWorld(const TwoRounds([
      '...K.........N',
      '...N..........',
      '.NNNNN........',
    ], ['N............N']));
    run(w, 1.1);
    w.destroyBlock(w.blocks.firstWhere((b) => b.type == 'K'), DestroyCause.ball);
    run(w, World.dt); // 崩落が始まる
    expect(w.falling, hasLength(6));
    // 落ち始める前にラウンドをクリアさせ、次のラウンドまで落ちないようにする
    for (final f in w.falling) {
      f.delay = 10;
    }
    w.destroyBlock(w.blocks.single, DestroyCause.ball);
    var events = run(w, World.dt);
    expect(events.whereType<RoundCleared>(), hasLength(1));
    final score = w.score, mult = w.mult;
    events = run(w, 3);
    expect(events.whereType<RoundStarted>().single.number, 2);
    expect(w.falling, isEmpty);
    expect(events.whereType<BlockFell>(), isEmpty);
    // 落ちなかった 6 個の得点は入らない。崩落の集計 (6 個) はラウンドの切り替えで締められ、崩落ボーナスだけが入る
    expect(w.score - score, 6 * 6 * 10 * mult);
    expect(w.stats.bestCollapse, 6);
    // 次のラウンドでも落ちてこない
    expect(run(w, 10).whereType<BlockFell>(), isEmpty);
  });
}
