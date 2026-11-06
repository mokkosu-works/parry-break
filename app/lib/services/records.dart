import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/core.dart';
import 'settings.dart';

/// 保存データを読む。型の違う項目は初期値に置き換え、置き換えた・捨てた項目があれば [lossy] にする。
class _Reader {
  bool lossy = false;

  Map<String, Object?> map(Object? v) {
    if (v == null) return const {};
    if (v is Map<String, Object?>) return v;
    lossy = true;
    return const {};
  }

  int int_(Object? v) {
    if (v == null) return 0;
    if (v is num && v.isFinite) return v.toInt();
    lossy = true;
    return 0;
  }

  bool bool_(Object? v) {
    if (v == null) return false;
    if (v is bool) return v;
    lossy = true;
    return false;
  }

  List<bool> bools(Object? v) {
    if (v == null) return const [];
    if (v is! List) {
      lossy = true;
      return const [];
    }
    return [for (final s in v) s is bool ? s : _invalidStar()];
  }

  bool _invalidStar() {
    lossy = true;
    return false;
  }

  EndlessRecord endless(Object? v) {
    final j = map(v);
    return EndlessRecord(
      bestScore: int_(j['bestScore']),
      bestRound: int_(j['bestRound']),
      bestCollapse: int_(j['bestCollapse']),
      bestBlast: int_(j['bestBlast']),
      bestRicochet: int_(j['bestRicochet']),
    );
  }

  StageRecord stage(Map<String, Object?> j) => StageRecord(
        cleared: bool_(j['cleared']),
        bestScore: int_(j['bestScore']),
        stars: bools(j['stars']),
      );

  Records records(Map<String, Object?> j) {
    final v = j['version'];
    // version がない古いデータは 1 として読む。今より新しい版のデータは、知っている項目だけを読む
    // (知らない項目は次の保存で失うので、元のデータを退避させる)。
    if (v != null && !(v is int && v <= Records.version)) lossy = true;
    final stages = <String, StageRecord>{};
    for (final e in map(j['stages']).entries) {
      final s = e.value;
      if (s is Map<String, Object?>) {
        stages[e.key] = stage(s);
      } else {
        lossy = true; // 形の違うこの 1 件だけを捨てる
      }
    }
    return Records(endless: endless(j['endless']), stages: stages);
  }
}

class EndlessRecord {
  const EndlessRecord({
    this.bestScore = 0,
    this.bestRound = 0,
    this.bestCollapse = 0,
    this.bestBlast = 0,
    this.bestRicochet = 0,
  });
  final int bestScore, bestRound, bestCollapse, bestBlast, bestRicochet;

  Map<String, Object?> toJson() => {
        'bestScore': bestScore,
        'bestRound': bestRound,
        'bestCollapse': bestCollapse,
        'bestBlast': bestBlast,
        'bestRicochet': bestRicochet,
      };

  /// 型の違う項目は 0 として読む。
  factory EndlessRecord.fromJson(Map<String, Object?> j) => _Reader().endless(j);
}

class StageRecord {
  const StageRecord({this.cleared = false, this.bestScore = 0, this.stars = const []});
  final bool cleared;
  final int bestScore;

  /// 条件ごとに一度でも達成したか。
  final List<bool> stars;

  int get starCount => stars.where((s) => s).length;

  /// [index] 番目の星を達成したか。記録より後に足した条件は未達成として扱う。
  bool hasStar(int index) => index < stars.length && stars[index];

  Map<String, Object?> toJson() => {'cleared': cleared, 'bestScore': bestScore, 'stars': stars};

  /// 型の違う項目は初期値として読む。
  factory StageRecord.fromJson(Map<String, Object?> j) => _Reader().stage(j);
}

/// 記録 (スキーマのバージョン付き JSON で保存する)。
class Records {
  const Records({this.endless = const EndlessRecord(), this.stages = const {}});
  final EndlessRecord endless;
  final Map<String, StageRecord> stages;

  static const version = 1;

  /// ステージの記録。難易度ごとに別に持つ (NORMAL のキーはステージ ID のまま)。
  StageRecord stage(String id, [Difficulty difficulty = Difficulty.normal]) =>
      stages[stageKey(id, difficulty)] ?? const StageRecord();

  static String stageKey(String id, Difficulty difficulty) => '$id${difficulty.recordSuffix}';

  /// どれかの難易度でクリアしたか。
  bool clearedAny(String id) => Difficulty.values.any((d) => stage(id, d).cleared);

  /// ステージごとの最高スコア (難易度をまたいだ最大) の合計。ランキングに送る。
  int get stagesTotal {
    final best = <String, int>{};
    for (final e in stages.entries) {
      final id = e.key.split('@').first;
      best[id] = math.max(best[id] ?? 0, e.value.bestScore);
    }
    return best.values.fold(0, (s, v) => s + v);
  }

  /// ステージを遊べるか: 各章の最初のステージは前の章の最後を、それ以外は同じ章の 1 つ前を
  /// (どの難易度でもよいので) クリアすると開く。
  bool isUnlocked(Campaign c, StageDef s) {
    for (var ci = 0; ci < c.chapters.length; ci++) {
      final stages = c.chapters[ci].stages;
      final si = stages.indexOf(s);
      if (si < 0) continue;
      if (si > 0) return clearedAny(stages[si - 1].id);
      if (ci == 0) return true;
      final prev = c.chapters[ci - 1].stages;
      return prev.isEmpty || clearedAny(prev.last.id);
    }
    return false;
  }

  /// 次に遊ぶステージ: 開いていて、まだクリアしていない最初のステージ。全部クリアしたら null。
  StageDef? nextStage(Campaign c) {
    for (final st in c.stages) {
      if (isUnlocked(c, st) && !clearedAny(st.id)) return st;
    }
    return null;
  }

  Map<String, Object?> toJson() => {
        'version': version,
        'endless': endless.toJson(),
        'stages': {for (final e in stages.entries) e.key: e.value.toJson()},
      };

  /// 壊れた項目 (形の違うステージの 1 件、型の違う値) だけを捨て、読める項目は残す。
  factory Records.fromJson(Map<String, Object?> j) => _Reader().records(j);

  /// 保存した文字列を読む。`intact` が false なら、捨てた項目がある・JSON として読めない・
  /// 今より新しい版のデータのどれかで、そのまま上書きすると元のデータを失う。
  static ({Records records, bool intact}) decode(String raw) {
    final Object? json;
    try {
      json = jsonDecode(raw);
    } on FormatException {
      return (records: const Records(), intact: false);
    }
    if (json is! Map<String, Object?>) return (records: const Records(), intact: false);
    final reader = _Reader();
    final records = reader.records(json);
    return (records: records, intact: !reader.lossy);
  }
}

class RecordsNotifier extends Notifier<Records> {
  static const _key = 'records';

  /// 読めなかった (一部でも捨てた) 元のデータの退避先。最新の 1 世代だけを残す。
  static const brokenKey = 'records.broken';

  @override
  Records build() {
    final prefs = ref.read(sharedPrefsProvider);
    final raw = prefs.getString(_key);
    if (raw == null) return const Records();
    final (:records, :intact) = Records.decode(raw);
    // 次の保存で records を上書きする前に、元の文字列を残しておく。
    if (!intact) prefs.setString(brokenKey, raw);
    return records;
  }

  void _save(Records r) {
    state = r;
    ref.read(sharedPrefsProvider).setString(_key, jsonEncode(r.toJson()));
  }

  /// エンドレスの結果を記録する。最高スコアを更新したら true。
  bool submitEndless({required int score, required int round, required RunStats stats}) {
    final e = state.endless;
    final newBest = score > e.bestScore;
    _save(Records(
      endless: EndlessRecord(
        bestScore: math.max(e.bestScore, score),
        bestRound: math.max(e.bestRound, round),
        bestCollapse: math.max(e.bestCollapse, stats.bestCollapse),
        bestBlast: math.max(e.bestBlast, stats.bestBlast),
        bestRicochet: math.max(e.bestRicochet, stats.bestRicochet),
      ),
      stages: state.stages,
    ));
    return newBest;
  }

  /// ステージの結果を記録する。最高スコアを更新したら true。
  bool submitStage(String id, StageResult result, List<bool> stars, {Difficulty difficulty = Difficulty.normal}) {
    final old = state.stage(id, difficulty);
    final merged = [
      for (var i = 0; i < stars.length; i++) stars[i] || old.hasStar(i),
    ];
    final newBest = result.cleared && result.score > old.bestScore;
    _save(Records(endless: state.endless, stages: {
      ...state.stages,
      Records.stageKey(id, difficulty): StageRecord(
        cleared: old.cleared || result.cleared,
        bestScore: result.cleared ? math.max(old.bestScore, result.score) : old.bestScore,
        stars: merged,
      ),
    }));
    return newBest;
  }
}

final recordsProvider = NotifierProvider<RecordsNotifier, Records>(RecordsNotifier.new);
