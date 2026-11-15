import '../core/core.dart';
import 'history.dart';
import 'records.dart';

/// エンドレスを遊び終えた回数。
///
/// 記録の `endless.plays` を主にし、この項目を足す前から遊んでいた人のために、履歴 (デイリーを除く
/// エンドレスの件数) と、最高スコアがあれば 1 回以上、で下から支える。どれも減らないので、
/// 一番大きいものを取る。
int endlessPlayCount(Records records, PlayHistory history) {
  final fromHistory = history.entries
      .where((e) => e.endless && !e.daily)
      .length;
  final fromBest = records.endless.bestScore > 0 ? 1 : 0;
  return [
    records.endless.plays,
    fromHistory,
    fromBest,
  ].reduce((a, b) => a > b ? a : b);
}

/// このプレイに「はじめの防壁」(design.md 7.10) を付けるか。
///
/// エンドレスだけ (デイリー・ステージ・練習場は付けない)。遊び終えた回数が
/// [Tuning.beginnerGuardPlays] 未満の間。
bool beginnerGuardFor({
  required GameMode mode,
  required Records records,
  required PlayHistory history,
  Tuning tuning = const Tuning(),
}) =>
    mode is EndlessMode &&
    endlessPlayCount(records, history) < tuning.beginnerGuardPlays;
