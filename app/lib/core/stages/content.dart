import '../entities/entities.dart';
import 'boss_def.dart';
import 'json_object.dart';
import 'procedural_generator.dart';
import 'wave_spec.dart';

/// エンドレス (アーケード) の定義。`assets/stages/endless.json` から読む。
class EndlessContent {
  const EndlessContent({
    required this.wavesPerLoop,
    required this.bossEvery,
    required this.loopSpeedup,
    required this.loopIntro,
    required this.unlock,
    required this.handcrafted,
    required this.intros,
    required this.bosses,
  });

  final int wavesPerLoop, bossEvery;
  final double loopSpeedup;
  final String? loopIntro;

  /// 自動生成で使うブロックの種類 → 解禁ウェーブ。
  final Map<String, int> unlock;

  /// 手作りの配置 (新ギミックの学習ウェーブ)。
  final Map<int, List<String>> handcrafted;

  /// ウェーブ番号 → 説明の翻訳キー。
  final Map<int, String> intros;
  final List<BossDef> bosses;

  /// [j] は `endless.json` の中身。書き間違いは [FormatException] になる。
  factory EndlessContent.fromJson(Map<String, Object?> j) {
    final r = JsonObject(j, 'endless.json');
    final hand = <int, List<String>>{}, intros = <int, String>{};
    for (final e in r.mapOf('handcrafted').keys) {
      final v = r.obj('handcrafted').obj(e);
      final wave = int.tryParse(e) ?? (throw FormatException('endless.json: handcrafted.$e: ウェーブ番号が必要'));
      final rows = v.stringsOpt('rows');
      if (rows != null) hand[wave] = rows;
      final intro = v.strOpt('intro');
      if (intro != null) intros[wave] = intro;
    }
    final bosses = r.objects('bosses');
    return EndlessContent(
      wavesPerLoop: r.integer('wavesPerLoop'),
      bossEvery: r.integer('bossEvery'),
      loopSpeedup: r.number('loopSpeedup'),
      loopIntro: r.strOpt('loopIntro'),
      unlock: r.obj('generator').intMap('unlock'),
      handcrafted: hand,
      intros: intros,
      bosses: [for (var i = 0; i < bosses.length; i++) BossDef.fromJson(i, bosses[i])],
    );
  }

  /// 難易度 [base] (1〜[wavesPerLoop]) のウェーブの中身。
  WaveContent contentFor(int base) {
    if (base % bossEvery == 0 && bosses.isNotEmpty) {
      return BossContent(bosses[(base ~/ bossEvery - 1).clamp(0, bosses.length - 1)]);
    }
    return LayoutContent(handcrafted[base] ?? generateLayout(base, unlock: unlock));
  }

  /// エンドレスの [number] 番目のウェーブ。
  WaveSpec wave(int number) {
    final base = (number - 1) % wavesPerLoop + 1;
    final loop = (number - 1) ~/ wavesPerLoop;
    return WaveSpec(
      number: number,
      difficulty: base,
      loop: loop,
      loopMul: 1 + loopSpeedup * loop,
      content: contentFor(base),
      introKey: loop > 0 && base == 1 ? loopIntro : intros[base],
      ending: base == wavesPerLoop,
    );
  }
}

// ---- ステージモード ------------------------------------------------------

/// ステージの星の条件。
sealed class StarCondition {
  const StarCondition();

  static StarCondition fromJson(JsonObject j) {
    final type = j.str('type');
    return switch (type) {
      'clear' => const ClearStar(),
      'noHit' => const NoHitStar(),
      'time' => TimeStar(j.number('value')),
      'score' => StatStar(StatKind.score, j.integer('value')),
      _ => StatStar(
          StatKind.values.asNameMap()[type] ?? (throw FormatException('${j.path}.type: 不明な星の条件 "$type"')),
          j.integer('value'),
        ),
    };
  }

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

enum StatKind { score, just, perfect, collapse, chainBlast, returnKills, graze, ricochet }

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
        StatKind.graze => r.stats.graze,
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

  factory LocalizedText.fromJson(Object? j) =>
      LocalizedText(j is Map ? Map<String, String>.from(j) : {'en': '${j ?? ''}'});

  String of(String lang) => values[lang] ?? values['en'] ?? values.values.firstOrNull ?? '';
}

class StageDef {
  const StageDef({
    required this.id,
    required this.chapterId,
    required this.title,
    required this.waves,
    required this.stars,
  });
  final String id, chapterId;
  final LocalizedText title;
  final List<WaveSpec> waves;
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
/// ウェーブの書き方:
/// - `{"rows": [...], "legend": {...}}`: 配置を直接書く
/// - `{"endless": 2}`: エンドレスの W2 と同じ中身
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

  /// [j] は `campaign.json` の中身。書き間違いは [FormatException] になる。
  factory Campaign.fromJson(Map<String, Object?> j, EndlessContent endless) {
    final r = JsonObject(j, 'campaign.json');
    return Campaign([
      for (final c in r.objects('chapters'))
        ChapterDef(id: c.str('id'), title: LocalizedText.fromJson(c.map['title']), stages: [
          for (final s in c.objects('stages'))
            StageDef(
              id: s.str('id'),
              chapterId: c.str('id'),
              title: LocalizedText.fromJson(s.map['title']),
              waves: [
                for (final (i, w) in s.objects('waves').indexed) _wave(i + 1, w, endless),
              ],
              stars: s.has('stars') ? [for (final st in s.objects('stars')) StarCondition.fromJson(st)] : const [ClearStar()],
            ),
        ]),
    ]);
  }

  static WaveSpec _wave(int number, JsonObject w, EndlessContent endless) {
    final WaveContent content;
    var difficulty = w.integerOpt('difficulty');
    if (w.has('rows')) {
      content = LayoutContent(w.strings('rows'), legend: w.stringMapOpt('legend'));
    } else if (w.has('endless')) {
      final n = w.integer('endless');
      content = endless.contentFor(n);
      difficulty ??= n;
    } else if (w.has('boss')) {
      final i = w.integer('boss');
      if (i < 0 || i >= endless.bosses.length) {
        throw FormatException('${w.path}.boss: 0〜${endless.bosses.length - 1} が必要 (実際: $i)');
      }
      content = BossContent(endless.bosses[i]);
      difficulty ??= (i + 1) * endless.bossEvery;
    } else {
      throw FormatException('${w.path}: rows, endless, boss のどれかが必要');
    }
    return WaveSpec(
      number: number,
      difficulty: difficulty ?? 1,
      content: content,
      clear: ClearCondition.fromJson(w.objOpt('clear')),
      introKey: w.strOpt('intro'),
      tuning: Map<String, Object?>.from(w.objOpt('tuning')?.map ?? const {}),
    );
  }
}
