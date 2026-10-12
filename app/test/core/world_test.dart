import 'package:flutter_test/flutter_test.dart';
import 'package:parry_break/core/core.dart';

import 'helpers.dart';

// R2 の手作り配置: 2 つの吊り下げ型の塊 (要石 + 首 + 13 個)
const w2 = [
  '...K......K...',
  '...N......N...',
  '.NNNNN..NNNNN.',
  '.NNNNN..NNNNN.',
  '..NNN....NNN..',
];

Block at(World w, int row, int col) => w.blocks.firstWhere((b) =>
    b.x == Field.gridX0 + col * Field.cellW && b.y == Field.gridY0 + row * Field.cellH);

void main() {
  group('崩落', () {
    test('要石を壊すと、つながっていた塊がすべて崩れ落ちる', () {
      final w = testWorld(const SingleRoundMode(w2));
      expect(w.blocks.where((b) => b.supported).length, w.blocks.length);
      w.destroyBlock(at(w, 0, 3), DestroyCause.ball);
      final events = run(w, 2);
      expect(events.whereType<CollapseStarted>().single.count, 14);
      expect(events.whereType<BlockFell>().length, 14);
      expect(w.blocks.length, 15); // 右の塊だけが残る
      expect(w.stats.bestCollapse, 14);
    });

    test('首を断つと、その下の塊だけが崩れる', () {
      final w = testWorld(const SingleRoundMode(w2));
      w.destroyBlock(at(w, 1, 3), DestroyCause.ball);
      final events = run(w, 2);
      expect(events.whereType<CollapseStarted>().single.count, 13);
      expect(w.blocks.where((b) => b.type == 'K').length, 2);
    });

    test('崩落ボーナスは n² × 10 × 倍率', () {
      final w = testWorld(const SingleRoundMode(w2));
      w.destroyBlock(at(w, 0, 3), DestroyCause.ball);
      final before = w.score;
      final events = run(w, 2);
      final fell = events.whereType<Popup>().where((p) => p.kind == PopupKind.score).fold(0, (s, p) => s + p.amount);
      expect(w.score - before, fell + 14 * 14 * 10 * w.mult);
    });
  });

  group('分身弾 (design.md 7.4)', () {
    World inPlay() {
      final w = testWorld(const SingleRoundMode(['NNNNNNNNNNNNNN']));
      run(w, 1.1);
      w.ball
        ..attached = false
        ..vx = 0
        ..vy = -400
        ..y = 300;
      return w;
    }

    Ball phantom(World w, {required double y, required double vy}) =>
        Ball(x: 600, y: y, vy: vy, speed: 400, phantom: true, life: 5);

    test('分身弾を落としてもゲームオーバーにならない', () {
      final w = inPlay();
      w.phantoms.add(phantom(w, y: Field.height - 5, vy: 600));
      final events = run(w, 0.2);
      expect(events.whereType<GameOver>(), isEmpty);
      expect(w.phantoms, isEmpty);
    });

    test('メインのボールを落としても、分身弾が残っていればそれがメインのボールになる', () {
      final w = inPlay();
      final low = phantom(w, y: 500, vy: 400);
      final rising = phantom(w, y: 400, vy: -400);
      final high = phantom(w, y: 200, vy: -400);
      w.phantoms.addAll([low, rising, high]);
      w.ball
        ..y = Field.height - 5
        ..vy = 600;
      final events = run(w, 0.2);
      expect(events.whereType<GameOver>(), isEmpty);
      expect(w.ball, same(high)); // 上へ向かっていて、いちばん高いもの
      expect(w.ball.phantom, isFalse);
      expect(w.phantoms, unorderedEquals([low, rising]));
    });

    test('分身弾も残っていなければ、メインのボールを落とした時点でゲームオーバー', () {
      final w = inPlay();
      w.ball
        ..y = Field.height - 5
        ..vy = 600;
      final events = run(w, 0.2);
      expect(events.whereType<GameOver>().single.reason, 'BALL LOST');
    });

    test('分身弾は 5 秒で消える', () {
      final w = inPlay();
      w.phantoms.add(phantom(w, y: 300, vy: -400)..life = 0.1);
      run(w, 0.2);
      expect(w.phantoms, isEmpty);
    });

    test('OVERDRIVE が終わると分身弾は爆発する', () {
      final w = inPlay();
      w.addHeat(1000);
      expect(w.od, isTrue);
      w.phantoms.add(phantom(w, y: 300, vy: -400));
      w.odTime = 0.01;
      final events = run(w, 0.5);
      expect(events.whereType<OverdriveEnded>().single.byHit, isFalse);
      expect(events.whereType<BlastExploded>().where((e) => e.kind == BlastKind.phantom), hasLength(1));
      expect(w.heat, inInclusiveRange(240, 250)); // 段階3 (250) に戻り、その後は減衰
    });
  });

  group('決定性', () {
    (int, int, double) play() {
      final w = World(mode: endlessMode)..start();
      run(w, 90, before: autopilot(w));
      return (w.score, w.round.number, w.heat);
    }

    test('同じ入力なら同じ結果になる', () {
      expect(play(), play());
    });
  });

  test('全ラウンド (ボスとループを含む) を読み込んで進めても例外が出ない', () {
    for (var n = 1; n <= 61; n++) {
      final w = World(mode: endlessMode)..start(fromRound: n);
      expect(w.blocks, isNotEmpty, reason: 'round $n');
      run(w, 8, before: autopilot(w));
    }
  });

  test('ボス戦: コアを壊すとフェーズが進み、全部壊すとクリア', () {
    final w = World(mode: endlessMode)..start(fromRound: 10);
    run(w, 1.1);
    final core = w.blocks.firstWhere((b) => b.type == bossCoreId);
    final events = <GameEvent>[];
    for (var i = 0; i < 8; i++) {
      w.damageCore(core, 1);
      events.addAll(run(w, 0.05));
    }
    expect(events.whereType<BossPhaseChanged>().map((e) => e.phase), [2, 3]);
    expect(events.whereType<RoundCleared>(), hasLength(1));
    expect(w.bonuses.first.label, 'BOSS DESTROYED');
  });
}
