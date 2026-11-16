import 'stages/content.dart';

/// 結果画面のランク。保存はしない (結果画面で毎回、結果から決める)。
enum Rank {
  s('S'),
  a('A'),
  b('B'),
  c('C'),
  d('D');

  const Rank(this.label);
  final String label;
}

/// ランクの基準。エンドレスは到達ラウンドとスコアの両方、ステージは星・被弾・時間の達成度で決める。
///
/// 基準の根拠は自動プレイ (test/balance/rank_dist.dart) の分布。エンドレスの S は、
/// 自動プレイ 36 回のうち上位 1 割 (ラウンド 35 以上) になる。
class RankTable {
  const RankTable({
    this.endlessRounds = const [35, 25, 15, 8],
    this.endlessScores = const [14000000, 8000000, 4000000, 1500000],
    this.stageRatios = const [0.9, 0.7, 0.5, 0.3],
    this.hurtPoints = const [3, 2, 1, 1],
    this.timeSlack = const [1.0, 1.5, 2.0],
  });

  /// S / A / B / C の下限 (これ未満は D)。エンドレスはラウンドとスコアの両方を満たす最も高いランク。
  final List<int> endlessRounds, endlessScores;

  /// ステージ: 得点率 (0〜1) の S / A / B / C の下限。
  final List<double> stageRatios;

  /// ステージ: 被弾 0 / 1 / 2 / 3 回の点 (4 回以上は 0)。先頭が満点。
  final List<int> hurtPoints;

  /// ステージ: 時間の星の目標に対する倍率 (以内ならそれぞれ 3 / 2 / 1 点)。
  final List<double> timeSlack;

  static const standard = RankTable();

  static Rank _pick(num v, List<num> mins) {
    for (var i = 0; i < mins.length; i++) {
      if (v >= mins[i]) return Rank.values[i];
    }
    return Rank.d;
  }

  Rank endless({required int round, required int score}) {
    final a = _pick(round, endlessRounds), b = _pick(score, endlessScores);
    return a.index > b.index ? a : b;
  }

  /// エンドレス (と DAILY) で、いまのランク [current] の 1 つ上に足りないもの。S なら null。
  /// 到達ラウンドとスコアの両方が要るので、足りないほうだけが 0 より大きい (両方足りなければ両方)。
  RankGap? gapToNext({
    required Rank current,
    required int round,
    required int score,
  }) {
    if (current.index == 0) return null;
    final next = Rank.values[current.index - 1];
    return RankGap(
      next,
      rounds: (endlessRounds[next.index] - round).clamp(0, 1 << 31),
      score: (endlessScores[next.index] - score).clamp(0, 1 << 31),
    );
  }

  /// クリアしたステージのランク。[achieved] は [StageDef.evaluate] の結果。
  Rank stage(StageDef s, StageResult r, List<bool> achieved) {
    var pts = 0, max = 0;
    TimeStar? time;
    for (var i = 0; i < s.stars.length; i++) {
      final c = s.stars[i];
      // クリア・被弾・時間は、下で被弾の数と時間の長さから細かく採点する
      if (c is TimeStar) time ??= c;
      if (c is ClearStar || c is NoHitStar || c is TimeStar) continue;
      max += 3;
      if (i < achieved.length && achieved[i]) pts += 3;
    }
    max += hurtPoints.first;
    final h = r.stats.hurt;
    pts += h < hurtPoints.length ? hurtPoints[h] : 0;
    if (time != null) {
      max += 3;
      for (var i = 0; i < timeSlack.length; i++) {
        if (r.stats.playTime <= time.seconds * timeSlack[i]) {
          pts += 3 - i;
          break;
        }
      }
    }
    return _pick(max == 0 ? 1.0 : pts / max, stageRatios);
  }
}

/// 次のランクまでに足りないラウンド数とスコア (足りているほうは 0)。
class RankGap {
  const RankGap(this.next, {required this.rounds, required this.score});
  final Rank next;
  final int rounds, score;
}

/// エンドレスと DAILY のゲームオーバーで出す「あと少し」: 記録までと、次のランクまで。
class RunGap {
  const RunGap({this.toBest, this.toRank});

  /// 記録 (自己ベスト / その日の記録) までの点。記録を更新した (またはまだ記録がない) ときは null。
  final int? toBest;

  /// 次のランクまで。ランクを出さないとき・S のときは null。
  final RankGap? toRank;

  bool get isEmpty => toBest == null && toRank == null;
}

/// [beatRecord] は今回、記録を更新した (その日の最初の 1 回を含む) か。[rank] はいま出しているランク
/// (出さないなら null)。[bestScore] は今回を含めた記録。
RunGap runGap({
  required int score,
  required int round,
  required int bestScore,
  required bool beatRecord,
  Rank? rank,
  RankTable table = RankTable.standard,
}) => RunGap(
  toBest: !beatRecord && bestScore > score ? bestScore - score : null,
  toRank: rank == null
      ? null
      : table.gapToNext(current: rank, round: round, score: score),
);

/// ゲームオーバーの原因。
enum OverCause {
  ballLost,
  breached,
  timeOver;

  /// [World] が持つ理由の文字列から。
  static OverCause fromReason(String reason) => switch (reason) {
    'BALL LOST' => ballLost,
    'TIME OVER' => timeOver,
    _ => breached,
  };
}

/// ステージで失敗したときの、クリア条件までの残り。
enum GapKind { annihilate, score, survive, boss }

class ClearGap {
  const ClearGap(this.kind, this.left);
  final GapKind kind;

  /// 残りのブロックの数 / 目標までのスコア / 残りの秒数 / ボスのコアの残り HP。
  final num left;
}

/// ゲームオーバーの詳細 (ミスの原因と、ステージの失敗時の残り)。
class OverInfo {
  const OverInfo({
    required this.cause,
    required this.tier,
    this.sinceParry,
    this.gap,
  });
  final OverCause cause;

  /// 終わった瞬間のボールの速さの段階 (1〜4、FEVER TIME は 5)。
  final int tier;

  /// 最後のパリィから終わるまでの秒数。一度もパリィしていなければ null。
  final double? sinceParry;

  /// ステージのときだけ。
  final ClearGap? gap;
}
