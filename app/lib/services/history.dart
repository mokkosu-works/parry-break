import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/core.dart';
import 'settings.dart';

/// 1 回のプレイの結果 (結果画面まで進んだもの)。
class PlayEntry {
  const PlayEntry({
    required this.at,
    this.stageId,
    this.difficulty = Difficulty.normal,
    required this.score,
    this.round = 0,
    this.cleared = false,
    this.daily = false,
  });

  /// 結果画面が出た日時 (端末の時刻)。
  final DateTime at;

  /// 遊んだステージの ID。null ならエンドレス。
  final String? stageId;
  final Difficulty difficulty;
  final int score;

  /// エンドレスで到達したラウンド (ステージでは 0)。
  final int round;

  /// ステージをクリアしたか (エンドレスでは false)。
  final bool cleared;

  /// デイリーチャレンジか ([stageId] は null)。古い版のアプリは、エンドレスとして読む。
  final bool daily;

  /// エンドレスかデイリー (ステージではない)。到達したラウンドを出す。
  bool get endless => stageId == null;

  Map<String, Object?> toJson() => {
    'at': at.millisecondsSinceEpoch,
    if (stageId != null) 'stage': stageId,
    'difficulty': difficulty.name,
    'score': score,
    if (stageId == null) 'round': round,
    if (stageId != null) 'cleared': cleared,
    if (daily) 'daily': true,
  };

  /// 読めない (必要な項目がない・型が違う) ときは null。
  static PlayEntry? fromJson(Object? j) {
    if (j is! Map<String, Object?>) return null;
    final at = j['at'], stage = j['stage'], score = j['score'];
    final diff = j['difficulty'], round = j['round'], cleared = j['cleared'];
    final daily = j['daily'];
    if (at is! int || score is! num || !score.isFinite) return null;
    if (stage != null && stage is! String) return null;
    final difficulty = Difficulty.values
        .where((d) => d.name == diff)
        .firstOrNull;
    if (diff != null && difficulty == null) return null;
    return PlayEntry(
      at: DateTime.fromMillisecondsSinceEpoch(at),
      stageId: stage as String?,
      difficulty: difficulty ?? Difficulty.normal,
      score: score.toInt(),
      round: round is num && round.isFinite ? round.toInt() : 0,
      cleared: cleared == true,
      daily: stage == null && daily == true,
    );
  }
}

/// 最近のプレイの履歴 (新しい順)。記録 (`records`) とは別のキーに保存する。
class PlayHistory {
  const PlayHistory([this.entries = const []]);
  final List<PlayEntry> entries;

  static const version = 1;

  /// 残す件数。これより古いものは消す。
  static const maxEntries = 50;

  /// [e] を先頭に足し、[maxEntries] 件を超えたぶんの古いものを消す。
  PlayHistory add(PlayEntry e) =>
      PlayHistory([e, ...entries.take(maxEntries - 1)]);

  Map<String, Object?> toJson() => {
    'version': version,
    'entries': [for (final e in entries) e.toJson()],
  };

  /// 保存した文字列を読む。`intact` が false なら、読めない項目がある・今より新しい版のデータで、
  /// そのまま上書きすると元のデータを失う。
  static ({PlayHistory history, bool intact}) decode(String raw) {
    final Object? json;
    try {
      json = jsonDecode(raw);
    } on FormatException {
      return (history: const PlayHistory(), intact: false);
    }
    if (json is! Map<String, Object?>) {
      return (history: const PlayHistory(), intact: false);
    }
    final v = json['version'];
    var intact = v == null || (v is int && v <= version);
    final list = json['entries'];
    if (list != null && list is! List) intact = false;
    final entries = <PlayEntry>[];
    for (final item in list is List ? list : const []) {
      final e = PlayEntry.fromJson(item);
      if (e == null) {
        intact = false; // 読めないこの 1 件だけを捨てる
      } else if (entries.length < maxEntries) {
        entries.add(e);
      }
    }
    return (history: PlayHistory(entries), intact: intact);
  }
}

/// 履歴に付ける日時。テストでは偽の時刻に差し替える。
final historyClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

class PlayHistoryNotifier extends Notifier<PlayHistory> {
  static const key = 'history.v1';

  /// 読めなかった (一部でも捨てた) 元のデータの退避先。最新の 1 世代だけを残す。
  static const brokenKey = 'history.broken';

  @override
  PlayHistory build() {
    final prefs = ref.read(sharedPrefsProvider);
    final raw = prefs.getString(key);
    if (raw == null) return const PlayHistory();
    final (:history, :intact) = PlayHistory.decode(raw);
    if (!intact) prefs.setString(brokenKey, raw);
    return history;
  }

  void _add(PlayEntry e) {
    state = state.add(e);
    ref.read(sharedPrefsProvider).setString(key, jsonEncode(state.toJson()));
  }

  /// エンドレスのゲームオーバーを残す。
  void addEndless({required int score, required int round}) => _add(
    PlayEntry(at: ref.read(historyClockProvider)(), score: score, round: round),
  );

  /// デイリーチャレンジの結果を残す (練習として遊んだ 2 回目以降も)。
  void addDaily({required int score, required int round}) => _add(
    PlayEntry(
      at: ref.read(historyClockProvider)(),
      score: score,
      round: round,
      daily: true,
    ),
  );

  /// ステージの結果 (クリア・失敗) を残す。
  void addStage(
    String id, {
    required int score,
    required bool cleared,
    Difficulty difficulty = Difficulty.normal,
  }) => _add(
    PlayEntry(
      at: ref.read(historyClockProvider)(),
      stageId: id,
      difficulty: difficulty,
      score: score,
      cleared: cleared,
    ),
  );
}

final historyProvider = NotifierProvider<PlayHistoryNotifier, PlayHistory>(
  PlayHistoryNotifier.new,
);
