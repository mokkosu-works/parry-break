import '../entities/entities.dart';
import 'boss_def.dart';
import 'procedural_generator.dart';
import 'round_spec.dart';

/// エンドレス (アーケード) の定義。`assets/stages/endless.json` から読む。
class EndlessContent {
  const EndlessContent({
    required this.roundsPerLoop,
    required this.bossEvery,
    required this.loopSpeedup,
    required this.loopIntro,
    required this.unlock,
    required this.handcrafted,
    required this.intros,
    required this.bosses,
  });

  final int roundsPerLoop, bossEvery;
  final double loopSpeedup;
  final String? loopIntro;

  /// 自動生成で使うブロックの種類 → 解禁ラウンド。
  final Map<String, int> unlock;

  /// 手作りの配置 (新ギミックの学習ラウンド)。
  final Map<int, List<String>> handcrafted;

  /// ラウンド番号 → 説明の翻訳キー。
  final Map<int, String> intros;
  final List<BossDef> bosses;

  factory EndlessContent.fromJson(Map<String, Object?> j) {
    final hand = <int, List<String>>{}, intros = <int, String>{};
    for (final e in (j['handcrafted'] as Map<String, Object?>).entries) {
      final w = int.parse(e.key), v = e.value as Map<String, Object?>;
      if (v['rows'] != null) hand[w] = List<String>.from(v['rows'] as List);
      if (v['intro'] != null) intros[w] = v['intro'] as String;
    }
    final bosses = (j['bosses'] as List).cast<Map<String, Object?>>();
    return EndlessContent(
      roundsPerLoop: (j['roundsPerLoop'] as num).toInt(),
      bossEvery: (j['bossEvery'] as num).toInt(),
      loopSpeedup: (j['loopSpeedup'] as num).toDouble(),
      loopIntro: j['loopIntro'] as String?,
      unlock: {
        for (final e in ((j['generator'] as Map)['unlock'] as Map<String, Object?>).entries)
          e.key: (e.value as num).toInt(),
      },
      handcrafted: hand,
      intros: intros,
      bosses: [for (var i = 0; i < bosses.length; i++) BossDef.fromJson(i, bosses[i])],
    );
  }

  /// 難易度 [base] (1〜[roundsPerLoop]) のラウンドの中身。
  RoundContent contentFor(int base) {
    if (base % bossEvery == 0 && bosses.isNotEmpty) {
      return BossContent(bosses[(base ~/ bossEvery - 1).clamp(0, bosses.length - 1)]);
    }
    return layoutFor(base);
  }

  /// 難易度 [base] の配置 (ボスのラウンド番号でも、ボスではなく配置を返す)。
  LayoutContent layoutFor(int base) => LayoutContent(handcrafted[base] ?? generateLayout(base, unlock: unlock));

  /// エンドレスの [number] 番目のラウンド。
  RoundSpec round(int number) {
    final base = (number - 1) % roundsPerLoop + 1;
    final loop = (number - 1) ~/ roundsPerLoop;
    return RoundSpec(
      number: number,
      difficulty: base,
      loop: loop,
      loopMul: 1 + loopSpeedup * loop,
      content: contentFor(base),
      introKey: loop > 0 && base == 1 ? loopIntro : intros[base],
      ending: base == roundsPerLoop,
    );
  }
}

// ---- ステージモード ------------------------------------------------------

/// ステージの星の条件。
sealed class StarCondition {
  const StarCondition();

  /// `{"type": ..., "value": ...}` から読む。`clear` / `noHit` は `value` を持たない。
  ///
  /// 形が合わない、または `type` が [StatKind] にない場合は例外を投げる。
  static StarCondition fromJson(Map<String, Object?> j) => switch (j) {
        {'type': 'clear'} => const ClearStar(),
        {'type': 'noHit'} => const NoHitStar(),
        {'type': 'time', 'value': final num v} => TimeStar(v.toDouble()),
        {'type': final String type, 'value': final num v} => StatStar(StatKind.values.byName(type), v.toInt()),
        _ => throw FormatException('invalid star condition: $j'),
      };

  bool achieved(StageResult r);
}

final class ClearStar extends StarCondition {
  const ClearStar();
  @override
  bool achieved(StageResult r) => r.cleared;
}

/// 被弾なしでクリア。
final class NoHitStar extends StarCondition {
  const NoHitStar();
  @override
  bool achieved(StageResult r) => r.cleared && r.stats.hurt == 0;
}

/// [seconds] 秒以内にクリア。
final class TimeStar extends StarCondition {
  const TimeStar(this.seconds);
  final double seconds;
  @override
  bool achieved(StageResult r) => r.cleared && r.stats.playTime <= seconds;
}

enum StatKind { score, just, perfect, collapse, chainBlast, returnKills, nearMiss, ricochet }

/// 数値の目標 (例: JUST を 3 回、COLLAPSE ×14)。クリアしたときだけ数える。
final class StatStar extends StarCondition {
  const StatStar(this.kind, this.value);
  final StatKind kind;
  final int value;

  int actual(StageResult r) => switch (kind) {
        StatKind.score => r.score,
        StatKind.just => r.stats.just,
        StatKind.perfect => r.stats.perfects,
        StatKind.collapse => r.stats.bestCollapse,
        StatKind.chainBlast => r.stats.bestBlast,
        StatKind.returnKills => r.stats.returnKills,
        StatKind.nearMiss => r.stats.nearMiss,
        StatKind.ricochet => r.stats.bestRicochet,
      };

  @override
  bool achieved(StageResult r) => r.cleared && actual(r) >= value;
}

class StageResult {
  const StageResult({required this.cleared, required this.score, required this.stats});
  final bool cleared;
  final int score;
  final RunStats stats;
}

/// 言語ごとの文字列 (`{"ja": "...", "en": "..."}`)。
class LocalizedText {
  const LocalizedText(this.values);
  final Map<String, String> values;

  /// 言語ごとの Map から読む。文字列 1 つだけなら英語として扱う。
  factory LocalizedText.fromJson(Object? j) => LocalizedText(switch (j) {
        final Map<Object?, Object?> m => Map<String, String>.from(m),
        _ => {'en': '${j ?? ''}'},
      });

  String of(String lang) => values[lang] ?? values['en'] ?? values.values.firstOrNull ?? '';
}

class StageDef {
  const StageDef({
    required this.id,
    required this.chapterId,
    required this.title,
    required this.rounds,
    required this.stars,
  });
  final String id, chapterId;
  final LocalizedText title;
  final List<RoundSpec> rounds;
  final List<StarCondition> stars;

  /// 達成した星 (条件ごと)。
  List<bool> evaluate(StageResult r) => [for (final s in stars) s.achieved(r)];
}

class ChapterDef {
  const ChapterDef({required this.id, required this.title, required this.stages});
  final String id;
  final LocalizedText title;
  final List<StageDef> stages;
}

/// ステージモードの定義。`assets/stages/campaign.json` から読む。
///
/// ラウンドの書き方:
/// - `{"rows": [...], "legend": {...}}`: 配置を直接書く
/// - `{"endless": 2}`: エンドレスの R2 と同じ配置 (ボスの番号でもボスにはならない。ボスは `boss` で書く)
/// - `{"boss": 0}`: エンドレスの 1 体目のボス
/// 共通で `difficulty`(既定 1)、`clear`、`tuning`、`intro` を書ける。
class Campaign {
  const Campaign(this.chapters);
  final List<ChapterDef> chapters;

  Iterable<StageDef> get stages => chapters.expand((c) => c.stages);

  StageDef? stage(String id) {
    for (final s in stages) {
      if (s.id == id) return s;
    }
    return null;
  }

  factory Campaign.fromJson(Map<String, Object?> j, EndlessContent endless) {
    return Campaign([
      for (final c in (j['chapters'] as List).cast<Map<String, Object?>>())
        ChapterDef(id: c['id'] as String, title: LocalizedText.fromJson(c['title']), stages: [
          for (final s in (c['stages'] as List).cast<Map<String, Object?>>())
            StageDef(
              id: s['id'] as String,
              chapterId: c['id'] as String,
              title: LocalizedText.fromJson(s['title']),
              rounds: [
                for (final (i, w) in (s['rounds'] as List).cast<Map<String, Object?>>().indexed)
                  _round(i + 1, w, endless),
              ],
              stars: [
                for (final st in (s['stars'] as List? ?? const [{'type': 'clear'}]).cast<Map<String, Object?>>())
                  StarCondition.fromJson(st),
              ],
            ),
        ]),
    ]);
  }

  static RoundSpec _round(int number, Map<String, Object?> w, EndlessContent endless) {
    // 中身と、`difficulty` を省いたときの難易度
    final (RoundContent content, int defaultDifficulty) = switch (w) {
      {'rows': final List<Object?> rows} => (
          LayoutContent(List<String>.from(rows), legend: Map<String, String>.from((w['legend'] as Map?) ?? const {})),
          1,
        ),
      {'endless': final num n} => (endless.layoutFor(n.toInt()), n.toInt()),
      {'boss': final num i} => (BossContent(endless.bosses[i.toInt()]), (i.toInt() + 1) * endless.bossEvery),
      _ => throw const FormatException('round needs rows, endless or boss'),
    };
    return RoundSpec(
      number: number,
      difficulty: (w['difficulty'] as num?)?.toInt() ?? defaultDifficulty,
      content: content,
      clear: ClearCondition.fromJson(w['clear'] as Map<String, Object?>?),
      introKey: w['intro'] as String?,
      tuning: Map<String, Object?>.from((w['tuning'] as Map?) ?? const {}),
    );
  }
}
