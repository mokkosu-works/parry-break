// はじめの防壁 (design.md 7.10): エンドレスの最初の数回、各ラウンドの開始に張る防壁。
import 'package:flutter_test/flutter_test.dart';
import 'package:parry_break/core/core.dart';

import 'helpers.dart';

class _TwoRounds extends GameMode {
  const _TwoRounds();

  @override
  String get recordKey => 'test';

  @override
  RoundSpec? roundAt(int number) => number <= 2
      ? RoundSpec(
          number: number,
          difficulty: 1,
          content: const LayoutContent(['NNNNNNNNNNNNNN', 'NNNNNNNNNNNNNN']),
          tuning: const {'descentBase': 0, 'descentPerRound': 0},
        )
      : null;
}

World _world({bool guard = false}) {
  final w = World(mode: const _TwoRounds(), inputLag: 0, beginnerGuard: guard)
    ..start();
  w.sync.identity();
  return w;
}

/// メインのボールを、パドルから離れた x で防壁へ向かって落とす。
void _dropBall(World w) {
  w.input
    ..useTarget = true
    ..targetX = 100;
  run(w, 0.02);
  w.ball
    ..attached = false
    ..x = 900
    ..y = Field.paddleY + 10
    ..vx = 0
    ..vy = w.ball.speed;
}

void _clearRound(World w) {
  for (final b in [...w.blocks]) {
    w.destroyBlock(b, DestroyCause.ball);
  }
}

void main() {
  test('フラグ on: ラウンドの開始から防壁が張られている (時間では消えない)', () {
    final w = _world(guard: true);
    expect(w.effects.guardUp, isTrue);
    expect(w.effects.guardHold, isTrue);
    run(w, 30); // アイテムの GUARD (12 秒) より長く待っても消えない
    expect(w.effects.guardUp, isTrue);
  });

  test('フラグ off (既定): 防壁はない', () {
    expect(World(mode: const _TwoRounds()).beginnerGuard, isFalse);
    expect(_world().effects.guardUp, isFalse);
  });

  test('メインのボールを 1 回跳ね返して消える', () {
    final w = _world(guard: true);
    _dropBall(w);
    final ev = run(w, 0.3);
    expect(ev.whereType<GuardBounced>(), hasLength(1));
    expect(w.ball.vy, lessThan(0));
    expect(w.effects.guardUp, isFalse);
    expect(w.phase, WorldPhase.playing);
    // 2 回目は落ちる
    _dropBall(w);
    run(w, 0.3);
    expect(w.phase, WorldPhase.over);
  });

  test('防壁が消えたあとでも、次のラウンドの開始でまた張る', () {
    final w = _world(guard: true);
    _dropBall(w);
    run(w, 0.3);
    expect(w.effects.guardUp, isFalse);
    _clearRound(w);
    run(w, 4); // クリアの演出を終えて、次のラウンドへ
    expect(w.round.number, 2);
    expect(w.effects.guardHold, isTrue);
  });

  test('張ったままラウンドクリアしても、次のラウンドで 1 枚のまま', () {
    final w = _world(guard: true);
    _clearRound(w);
    run(w, 4);
    expect(w.round.number, 2);
    expect(w.effects.guardHold, isTrue);
    expect(w.effects.guard, 0);
  });

  test('防壁が残っている間に GUARD を取っても、はじめの防壁は消えない (跳ね返したら両方消える)', () {
    final w = _world(guard: true);
    w.items.add(Item(ItemKind.guard, w.paddle.x, Field.paddleY - 10 - 34));
    run(w, 0.3);
    expect(w.items, isEmpty);
    expect(w.effects.guardHold, isTrue);
    expect(w.effects.guard, greaterThan(0));
    _dropBall(w);
    final ev = run(w, 0.3);
    expect(ev.whereType<GuardBounced>(), hasLength(1));
    expect(w.effects.guardUp, isFalse, reason: '1 回で両方消える');
  });

  group('決定性', () {
    /// 同じ入力を与えて、状態の指紋を取る。
    List<Object> play(World w, {int seconds = 20}) {
      run(
        w,
        seconds.toDouble(),
        before: () {
          w.input
            ..useTarget = true
            ..targetX = w.ball.x;
          if (w.ball.attached && w.t > 1.2) w.pressAction(w.t);
        },
      );
      return [
        w.score,
        w.round.number,
        w.ball.x.toStringAsFixed(6),
        w.ball.y.toStringAsFixed(6),
        w.blocks.length,
        w.rng.next(),
        w.aux.next(),
        w.itemRng.next(),
      ];
    }

    World make({bool? guard}) {
      final w = guard == null
          ? World(mode: endlessMode, inputLag: 0)
          : World(mode: endlessMode, inputLag: 0, beginnerGuard: guard);
      w.start();
      w.sync.identity();
      return w;
    }

    test('フラグ off は、引数を渡さない World と同じ展開になる', () {
      expect(play(make(guard: false)), play(make()));
    });

    test('フラグ on でも、防壁に当たらない間は乱数を引く回数が同じ (展開が変わらない)', () {
      // パドルがボールを追うので防壁には当たらない
      expect(play(make(guard: true), seconds: 10), play(make(), seconds: 10));
    });
  });
}
