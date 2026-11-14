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

Block at(World w, int row, int col) => w.blocks.firstWhere(
  (b) =>
      b.x == Field.gridX0 + col * Field.cellW &&
      b.y == Field.gridY0 + row * Field.cellH,
);

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
      final fell = events
          .whereType<Popup>()
          .where((p) => p.kind == PopupKind.score)
          .fold(0, (s, p) => s + p.amount);
      expect(w.score - before, fell + 14 * 14 * 10 * w.mult);
    });
  });

  group('ラウンドの時間 (#100)', () {
    test('発射するまで roundTime は進まず、発射の前後で戻らない', () {
      final w = testWorld(const SingleRoundMode(['......N.......']));
      run(w, 5); // カウントダウンが終わってもしばらく発射しない
      expect(w.launched, isFalse);
      expect(w.roundTime, 0);
      w.pressAction(w.t);
      var prev = w.roundTime;
      run(
        w,
        2,
        before: () {
          expect(w.roundTime, greaterThanOrEqualTo(prev));
          prev = w.roundTime;
        },
      );
      expect(w.launched, isTrue);
      expect(w.roundTime, closeTo(2, 0.05));
    });

    test('全消しボーナスは発射から数えた時間で判定する (発射前の待ち時間は含めない)', () {
      final w = testWorld(const SingleRoundMode(['......N.......']));
      run(w, 15);
      w.pressAction(w.t);
      run(w, 1);
      w.destroyBlock(w.blocks.single, DestroyCause.ball);
      final events = run(w, 1);
      final bonuses = events.whereType<RoundCleared>().single.bonuses;
      expect(bonuses.any((b) => b.label.startsWith('ANNIHILATION')), isTrue);
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

    test('メインのボールを落としたら、分身弾が残っていてもゲームオーバー', () {
      final w = inPlay();
      w.phantoms.addAll([
        phantom(w, y: 500, vy: 400),
        phantom(w, y: 200, vy: -400),
      ]);
      w.ball
        ..y = Field.height - 5
        ..vy = 600;
      final events = run(w, 0.2);
      expect(events.whereType<GameOver>().single.reason, 'BALL LOST');
      expect(w.ball.phantom, isFalse);
    });

    test('分身弾がなくても、メインのボールを落とした時点でゲームオーバー', () {
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

    test('FEVER TIME が終わると分身弾は爆発する', () {
      final w = inPlay();
      w.addCombo(1000);
      expect(w.od, isTrue);
      w.phantoms.add(phantom(w, y: 300, vy: -400));
      w.odTime = 0.01;
      final events = run(w, 0.5);
      expect(events.whereType<FeverTimeEnded>().single.byHit, isFalse);
      expect(
        events.whereType<BlastExploded>().where(
          (e) => e.kind == BlastKind.phantom,
        ),
        hasLength(1),
      );
      expect(w.combo, inInclusiveRange(240, 250)); // 段階3 (250) に戻り、その後は減衰
    });
  });

  group('決定性', () {
    (int, int, double) play() {
      final w = World(mode: endlessMode)..start();
      run(w, 90, before: autopilot(w));
      return (w.score, w.round.number, w.combo);
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

  group('RETRY (#132)', () {
    test('タッチで端へ寄せたまま start() を呼び直すと、最初のステップ後のパドルは中央にある', () {
      final w = testWorld(const SingleRoundMode(['NNNNNNNNNNNNNN']));
      run(w, 1.1);
      w.input
        ..useTarget = true
        ..targetX = Field.width - w.paddleWidth / 2;
      run(w, 0.1);
      expect(w.paddle.x, Field.width - w.paddleWidth / 2);
      w.start();
      w.step(World.dt);
      expect(w.paddle.x, Field.width / 2);
      expect(w.ball.x, Field.width / 2); // ボールもパドルと一緒に中央から
    });

    test('キーの方向入力が残っていても、start() の後の最初のステップでパドルは動かない', () {
      final w = testWorld(const SingleRoundMode(['NNNNNNNNNNNNNN']));
      w.input
        ..useTarget = false
        ..axis = -1;
      run(w, 0.5);
      expect(w.paddle.x, lessThan(Field.width / 2));
      w.start();
      w.step(World.dt);
      expect(w.paddle.x, Field.width / 2);
    });

    test('start() で、前のプレイのクリア・ゲームオーバーの演出用の値も最初の状態に戻る', () {
      final fresh = World(mode: const SingleRoundMode(['NNNNNNNNNNNNNN']))
        ..start();
      final w = World(mode: const SingleRoundMode(['NNNNNNNNNNNNNN']))..start();
      w
        ..bonuses = const [Bonus('ROUND CLEAR  ×1', 5000)]
        ..clearT = 3
        ..overT = 2
        ..lastBreak = const Vec2(10, 10);
      w.start();
      expect(w.bonuses, isEmpty);
      expect(w.clearT, 0);
      expect(w.overT, 0);
      expect(w.lastBreak.x, fresh.lastBreak.x);
      expect(w.lastBreak.y, fresh.lastBreak.y);
    });
  });
}
