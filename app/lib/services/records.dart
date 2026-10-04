import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/core.dart';
import 'settings.dart';

class EndlessRecord {
  const EndlessRecord({
    this.bestScore = 0,
    this.bestWave = 0,
    this.bestCollapse = 0,
    this.bestBlast = 0,
    this.bestRicochet = 0,
  });
  final int bestScore, bestWave, bestCollapse, bestBlast, bestRicochet;

  Map<String, Object?> toJson() => {
        'bestScore': bestScore,
        'bestWave': bestWave,
        'bestCollapse': bestCollapse,
        'bestBlast': bestBlast,
        'bestRicochet': bestRicochet,
      };

  factory EndlessRecord.fromJson(Map<String, Object?> j) {
    int i(String k) => (j[k] as num?)?.toInt() ?? 0;
    return EndlessRecord(
      bestScore: i('bestScore'),
      bestWave: i('bestWave'),
      bestCollapse: i('bestCollapse'),
      bestBlast: i('bestBlast'),
      bestRicochet: i('bestRicochet'),
    );
  }
}

class StageRecord {
  const StageRecord({this.cleared = false, this.bestScore = 0, this.stars = const []});
  final bool cleared;
  final int bestScore;

  /// 条件ごとに一度でも達成したか。
  final List<bool> stars;

  int get starCount => stars.where((s) => s).length;

  Map<String, Object?> toJson() => {'cleared': cleared, 'bestScore': bestScore, 'stars': stars};

  factory StageRecord.fromJson(Map<String, Object?> j) => StageRecord(
        cleared: j['cleared'] as bool? ?? false,
        bestScore: (j['bestScore'] as num?)?.toInt() ?? 0,
        stars: [for (final s in (j['stars'] as List?) ?? const []) s == true],
      );
}

/// 記録 (スキーマのバージョン付き JSON で保存する)。
class Records {
  const Records({this.endless = const EndlessRecord(), this.stages = const {}});
  final EndlessRecord endless;
  final Map<String, StageRecord> stages;

  static const version = 1;

  StageRecord stage(String id) => stages[id] ?? const StageRecord();

  /// ステージを遊べるか: 各章の最初のステージは前の章の最後をクリアすると、
  /// それ以外は同じ章の 1 つ前をクリアすると開く。
  bool isUnlocked(Campaign c, StageDef s) {
    for (var ci = 0; ci < c.chapters.length; ci++) {
      final stages = c.chapters[ci].stages;
      final si = stages.indexOf(s);
      if (si < 0) continue;
      if (si > 0) return stage(stages[si - 1].id).cleared;
      if (ci == 0) return true;
      final prev = c.chapters[ci - 1].stages;
      return prev.isEmpty || stage(prev.last.id).cleared;
    }
    return false;
  }

  Map<String, Object?> toJson() => {
        'version': version,
        'endless': endless.toJson(),
        'stages': {for (final e in stages.entries) e.key: e.value.toJson()},
      };

  factory Records.fromJson(Map<String, Object?> j) => Records(
        endless: EndlessRecord.fromJson((j['endless'] as Map<String, Object?>?) ?? const {}),
        stages: {
          for (final e in ((j['stages'] as Map<String, Object?>?) ?? const {}).entries)
            e.key: StageRecord.fromJson(e.value as Map<String, Object?>),
        },
      );
}

class RecordsNotifier extends Notifier<Records> {
  static const _key = 'records';

  @override
  Records build() {
    final raw = ref.read(sharedPrefsProvider).getString(_key);
    if (raw == null) return const Records();
    try {
      return Records.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } on Object {
      return const Records();
    }
  }

  void _save(Records r) {
    state = r;
    ref.read(sharedPrefsProvider).setString(_key, jsonEncode(r.toJson()));
  }

  /// エンドレスの結果を記録する。最高スコアを更新したら true。
  bool submitEndless({required int score, required int wave, required RunStats stats}) {
    final e = state.endless;
    final newBest = score > e.bestScore;
    _save(Records(
      endless: EndlessRecord(
        bestScore: math.max(e.bestScore, score),
        bestWave: math.max(e.bestWave, wave),
        bestCollapse: math.max(e.bestCollapse, stats.bestCollapse),
        bestBlast: math.max(e.bestBlast, stats.bestBlast),
        bestRicochet: math.max(e.bestRicochet, stats.bestRicochet),
      ),
      stages: state.stages,
    ));
    return newBest;
  }

  /// ステージの結果を記録する。最高スコアを更新したら true。
  bool submitStage(String id, StageResult result, List<bool> stars) {
    final old = state.stage(id);
    final merged = [
      for (var i = 0; i < stars.length; i++) stars[i] || (i < old.stars.length && old.stars[i]),
    ];
    final newBest = result.cleared && result.score > old.bestScore;
    _save(Records(endless: state.endless, stages: {
      ...state.stages,
      id: StageRecord(
        cleared: old.cleared || result.cleared,
        bestScore: result.cleared ? math.max(old.bestScore, result.score) : old.bestScore,
        stars: merged,
      ),
    }));
    return newBest;
  }
}

final recordsProvider = NotifierProvider<RecordsNotifier, Records>(RecordsNotifier.new);
