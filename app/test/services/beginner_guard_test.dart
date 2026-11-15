// はじめの防壁を付けるかの判定 (回数の数え方と、対象のモード)。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:parry_break/core/core.dart';
import 'package:parry_break/services/beginner_guard.dart';
import 'package:parry_break/services/history.dart';
import 'package:parry_break/services/records.dart';

import '../core/helpers.dart';

PlayEntry _endless() =>
    PlayEntry(at: DateTime(2026, 11, 14), score: 1000, round: 3);

PlayHistory _history(int endless, {int stages = 0}) => PlayHistory([
  for (var i = 0; i < endless; i++) _endless(),
  for (var i = 0; i < stages; i++)
    PlayEntry(
      at: DateTime(2026, 11, 14),
      score: 5,
      stageId: '1-1',
      cleared: true,
    ),
]);

Records _records(int plays, {int best = 0}) => Records(
  endless: EndlessRecord(plays: plays, bestScore: best),
);

bool _guard(GameMode mode, Records r, PlayHistory h) =>
    beginnerGuardFor(mode: mode, records: r, history: h);

void main() {
  test('回数は Tuning の 1 か所にある (3)', () {
    expect(const Tuning().beginnerGuardPlays, 3);
  });

  test('エンドレス: 0〜2 回は付き、3 回以降は付かない', () {
    for (var n = 0; n < 6; n++) {
      expect(
        _guard(endlessMode, _records(n, best: n > 0 ? 100 : 0), _history(n)),
        n < 3,
        reason: '$n 回',
      );
    }
  });

  test('DAILY・ステージ・練習場には、0 回でも付けない', () {
    final r = _records(0), h = _history(0);
    expect(
      _guard(DailyMode(endlessContent, const DailyChallenge(20000)), r, h),
      isFalse,
    );
    expect(_guard(PracticeMode(), r, h), isFalse);
    final campaign = Campaign.fromJson(
      jsonDecode(File('assets/stages/campaign.json').readAsStringSync())
          as Map<String, Object?>,
      endlessContent,
    );
    expect(_guard(StageMode(campaign.stages.first), r, h), isFalse);
  });

  test('回数: 記録の plays、履歴のエンドレス、最高スコアのうち一番大きいもの', () {
    expect(endlessPlayCount(const Records(), const PlayHistory()), 0);
    expect(endlessPlayCount(_records(2), const PlayHistory()), 2);
    expect(endlessPlayCount(const Records(), _history(4)), 4);
    // plays を足す前から遊んでいた人 (最高スコアだけある) は 1 回以上
    expect(endlessPlayCount(_records(0, best: 500), const PlayHistory()), 1);
    // ステージとデイリーの履歴は数えない
    final h = PlayHistory([
      ..._history(1, stages: 5).entries,
      PlayEntry(at: DateTime(2026, 11, 14), score: 9, round: 2, daily: true),
    ]);
    expect(endlessPlayCount(const Records(), h), 1);
  });

  test('plays のない古い記録も読める。plays があれば読む', () {
    final old = Records.decode(
      '{"version":1,"endless":{"bestScore":5000,"bestRound":7},"stages":{}}',
    );
    expect(old.intact, isTrue);
    expect(old.records.endless.plays, 0);
    expect(old.records.endless.bestScore, 5000);
    final now = Records.decode(
      '{"version":1,"endless":{"bestScore":5,"plays":2},"stages":{}}',
    );
    expect(now.records.endless.plays, 2);
    expect(now.records.endless.toJson()['plays'], 2);
  });
}
