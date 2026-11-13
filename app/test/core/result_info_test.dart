import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:parry_break/core/core.dart';

import 'helpers.dart';

/// Issue #254: 結果画面のランク・内訳・ミスの原因。
void main() {
  final campaign = Campaign.fromJson(
    jsonDecode(File('assets/stages/campaign.json').readAsStringSync())
        as Map<String, Object?>,
    endlessContent,
  );
  const table = RankTable.standard;

  group('エンドレスのランク', () {
    Rank rank(int round, int score) =>
        table.endless(round: round, score: score);

    test('ラウンドとスコアの境目 (両方を満たす最も高いランク)', () {
      expect(rank(35, 14000000), Rank.s);
      expect(rank(34, 14000000), Rank.a);
      expect(rank(35, 13999999), Rank.a);
      expect(rank(25, 8000000), Rank.a);
      expect(rank(24, 8000000), Rank.b);
      expect(rank(15, 4000000), Rank.b);
      expect(rank(14, 4000000), Rank.c);
      expect(rank(8, 1500000), Rank.c);
      expect(rank(7, 1500000), Rank.d);
      expect(rank(8, 1499999), Rank.d);
      expect(rank(1, 0), Rank.d);
    });

    test('スコアだけ・ラウンドだけ高くても、低い方のランクになる', () {
      expect(rank(60, 100), Rank.d);
      expect(rank(3, 99000000), Rank.d);
      expect(rank(40, 9000000), Rank.a);
    });
  });

  group('ステージのランク', () {
    // 1-6: clear / noHit / time 60
    final s = campaign.stage('1-6')!;
    Rank rank({required int hurt, required double time}) {
      final r = StageResult(
        cleared: true,
        score: 1,
        stats: RunStats()
          ..hurt = hurt
          ..playTime = time,
      );
      return table.stage(s, r, s.evaluate(r));
    }

    test('被弾なし・目標時間以内の全星は S', () {
      expect(rank(hurt: 0, time: 60), Rank.s);
      expect(rank(hurt: 0, time: 30), Rank.s);
    });

    test('時間が目標を超えるほど、被弾が増えるほど下がる', () {
      expect(rank(hurt: 0, time: 61), Rank.a);
      expect(rank(hurt: 0, time: 91), Rank.b);
      expect(rank(hurt: 1, time: 60), Rank.a);
      expect(rank(hurt: 2, time: 60), Rank.b);
      expect(rank(hurt: 5, time: 60), Rank.b);
      expect(rank(hurt: 5, time: 200), Rank.d);
    });

    test('被弾が多く時間もかかれば D', () {
      expect(rank(hurt: 9, time: 999), Rank.d);
      expect(rank(hurt: 1, time: 100), Rank.b);
    });

    test('時間の星のないステージは、星と被弾だけで決める', () {
      final n = campaign.stage('1-4')!; // clear / returnKills / noHit
      Rank r(int hurt, int kills) {
        final res = StageResult(
          cleared: true,
          score: 1,
          stats: RunStats()
            ..hurt = hurt
            ..returnKills = kills
            ..playTime = 500,
        );
        return table.stage(n, res, n.evaluate(res));
      }

      expect(r(0, 3), Rank.s);
      expect(r(0, 0), Rank.b); // 星 1 つ分 (3/6 点)
      expect(r(1, 3), Rank.a);
    });
  });

  group('プレイの内訳は、実際に数えた値と一致する', () {
    test('パリィの判定・空振り・FEVER TIME の数がイベントと一致する', () {
      final w = testWorld(endlessMode);
      final events = run(w, 40, before: autopilot(w, every: 0.21));
      final ok = events.whereType<ParrySucceeded>().toList();
      int n(ParryGrade g) => ok.where((e) => e.grade == g).length;
      final s = w.stats;
      expect(s.parries, ok.length);
      expect(s.just, n(ParryGrade.just));
      expect(s.perfects, n(ParryGrade.just) + n(ParryGrade.perfect));
      expect(s.parries - s.perfects, n(ParryGrade.good));
      expect(s.misses, events.whereType<ParryMissed>().length);
      expect(s.fevers, events.whereType<FeverTimeStarted>().length);
      expect(s.parries, greaterThan(0));
      expect(s.misses, greaterThan(0));
      expect(s.maxTier, inInclusiveRange(1, 4));
    });
  });

  group('ミスの原因', () {
    test('ボールを落とした: 最後のパリィからの時間と段階が付く', () {
      final w = testWorld(endlessMode);
      run(w, 3, before: autopilot(w));
      expect(w.phase, WorldPhase.playing);
      final at = w.lastParryT;
      w.ball
        ..y = Field.height - 5
        ..vy = 600;
      run(w, 0.3);
      final o = w.overInfo!;
      expect(o.cause, OverCause.ballLost);
      expect(o.tier, w.stage + 1);
      if (at != null) expect(o.sinceParry, closeTo(w.t - at - 0.3, 0.35));
      expect(o.gap, isNull); // エンドレスに「あと少し」はない
    });

    test('一度もパリィしていなければ、最後のパリィの時間は null', () {
      final w = testWorld(endlessMode);
      run(w, 1.2);
      w.pressAction(w.t);
      run(w, 0.1);
      w.ball
        ..y = Field.height - 5
        ..vy = 600;
      run(w, 0.3);
      expect(w.overInfo!.sinceParry, isNull);
    });

    test('ブロックが下まで来た', () {
      final w = testWorld(endlessMode);
      run(w, 1.2);
      w.form.oy += Field.height;
      run(w, 0.1);
      expect(w.overInfo!.cause, OverCause.breached);
    });

    test('ボスが急降下して時間切れ', () {
      expect(OverCause.fromReason('TIME OVER'), OverCause.timeOver);
      expect(OverCause.fromReason('BALL LOST'), OverCause.ballLost);
      expect(OverCause.fromReason('BLOCKS BREACHED'), OverCause.breached);
    });
  });

  group('ステージ失敗時の「あと少し」(4 種)', () {
    World fail(String id) {
      final w = testWorld(StageMode(campaign.stage(id)!));
      run(w, 1.2);
      return w;
    }

    void drop(World w) {
      w.pressAction(w.t); // 発射
      run(w, 0.1);
      w.ball
        ..y = Field.height - 5
        ..vy = 600;
      run(w, 0.3);
    }

    test('全消し: 残りのブロックの数', () {
      final w = fail('1-1');
      final left = w.blocks.where((b) => b.behavior.clearable).length;
      drop(w);
      final g = w.overInfo!.gap!;
      expect(g.kind, GapKind.annihilate);
      expect(g.left, left);
      expect(left, greaterThan(0));
    });

    test('スコア: 目標までの残り', () {
      final w = fail('1-7');
      w.score = 100000;
      drop(w);
      final g = w.overInfo!.gap!;
      expect(g.kind, GapKind.score);
      expect(g.left, 20000 - (w.score - 100000));
    });

    test('生き残り: 残りの秒数', () {
      final w = fail('1-8');
      w.roundTime = 30;
      drop(w);
      final g = w.overInfo!.gap!;
      expect(g.kind, GapKind.survive);
      expect(g.left, closeTo(10, 0.5));
    });

    test('ボス: コアの残り HP', () {
      final w = fail('1-10');
      final hp = w.bossHp;
      drop(w);
      final g = w.overInfo!.gap!;
      expect(g.kind, GapKind.boss);
      expect(g.left, hp);
      expect(hp, greaterThan(0));
    });
  });
}
