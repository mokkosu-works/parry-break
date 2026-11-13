import 'package:flutter_test/flutter_test.dart';
import 'package:parry_break/core/core.dart';

import 'helpers.dart';

/// Issue #255: デイリーチャレンジの日付・種・ラウンド番号。
void main() {
  List<String> rowsOf(RoundSpec s) => switch (s.content) {
    LayoutContent(:final rows) => rows,
    _ => const ['boss'],
  };

  test('同じ UTC の日付なら、時刻・時差によらず同じ種・同じラウンド番号になる (固定値)', () {
    final a = DailyChallenge.of(DateTime.utc(2026, 11, 13, 0, 0, 1));
    final b = DailyChallenge.of(DateTime.utc(2026, 11, 13, 23, 59, 59));
    // 日本時間の 11/14 8:00 は UTC の 11/13 23:00
    final c = DailyChallenge.of(DateTime.utc(2026, 11, 13, 23).toLocal());
    for (final d in [a, b, c]) {
      expect(d.day, 20770);
      expect(d.seed, 164477647);
      expect(d.startRound, 44);
      expect(d.lastRound, 48);
      expect(d.label, '2026-11-13');
    }
    expect(DailyChallenge.of(DateTime.utc(2026, 11, 14)).startRound, 9);
    expect(DailyChallenge.of(DateTime.utc(2027, 1, 1)).startRound, 12);
  });

  test('デイリーのモード: その日の 5 ラウンドだけを、エンドレスと同じ配置で遊ぶ', () {
    final m = DailyMode(endlessContent, const DailyChallenge(20770));
    expect(m.firstRound, 44);
    expect(m.roundAt(43), isNull);
    expect(m.roundAt(49), isNull);
    for (var n = 44; n <= 48; n++) {
      final r = m.roundAt(n)!;
      expect(r.number, n);
      expect(r.seed, endlessContent.round(n).seed);
      expect(rowsOf(r), rowsOf(endlessContent.round(n)));
      expect(r.items, isTrue, reason: 'アイテムはエンドレスと同じく出る');
    }
    // 配置そのものも固定値と比べる (自動生成の式が変わると、日付が同じでも配置が変わってしまう)
    expect(rowsOf(m.roundAt(44)!), const [
      'KNSSNRKKRNSSNK',
      '#T.NN.NN.NN.T#',
      'NN.NS.NN.SN.NN',
      'NN.XN.##.NX.NN',
      'NN.NN.KK.NN.NN',
      'SN.RN.NN.NR.NS',
      'BM.NT.NN.TN.MB',
      'TB.NN.NN.NN.BT',
    ]);
  });

  test('ボスのラウンドが入る日もある', () {
    final m = DailyMode(endlessContent, const DailyChallenge(20771)); // R9〜R13
    expect(m.roundAt(10)!.content, isA<BossContent>());
  });

  test('日付が変わると、始まりのラウンド (= 配置) が変わる。1 周目の中に収まる', () {
    final start = DailyChallenge.of(DateTime.utc(2026, 1, 1)).day;
    final seen = <int>{};
    for (var d = start; d < start + 400; d++) {
      final a = DailyChallenge(d), b = DailyChallenge(d + 1);
      expect(a.startRound, isNot(b.startRound), reason: 'day $d');
      expect(
        rowsOf(DailyMode(endlessContent, a).roundAt(a.startRound)!),
        isNot(rowsOf(DailyMode(endlessContent, b).roundAt(b.startRound)!)),
        reason: 'day $d',
      );
      expect(a.startRound, inInclusiveRange(DailyChallenge.minStart, 56));
      expect(a.lastRound, lessThanOrEqualTo(endlessContent.roundsPerLoop));
      seen.add(a.startRound);
    }
    expect(seen.length, DailyChallenge.maxStart - DailyChallenge.minStart + 1);
  });

  test('World: その日の最初のラウンドから、エンドレスと同じ速さ (1 周目) で始まる', () {
    final w = World(
      mode: DailyMode(endlessContent, const DailyChallenge(20770)),
      inputLag: 0,
    )..start();
    expect(w.round.number, 44);
    expect(w.round.difficulty, 44);
    expect(w.round.loop, 0);
  });
}
