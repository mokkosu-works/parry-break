import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/core.dart';
import 'settings.dart';

/// デイリーチャレンジの記録。記録 (`records`)・履歴とは別のキーに保存する。
///
/// 1 日に記録として数えるのは最初の 1 回だけ。2 回目以降は練習として遊べるが、ここには残さない。
class DailyRecord {
  const DailyRecord({
    this.lastDay = -1,
    this.lastScore = 0,
    this.bestScore = 0,
    this.streak = 0,
  });

  /// 最後に記録として数えた日 ([DailyChallenge.day])。まだなければ -1。
  final int lastDay;

  /// [lastDay] のスコア。
  final int lastScore;

  /// デイリーの中での自己ベスト。
  final int bestScore;

  /// [lastDay] までの連続日数。
  final int streak;

  static const version = 1;

  /// [today] にもう記録として遊んだか。端末の時計を巻き戻して [lastDay] より前の日になったときも、
  /// 遊んだものとして扱う (数え直して連続日数が増えすぎないように)。
  bool playedOn(int today) => lastDay >= today;

  /// [today] の時点の連続日数。昨日か今日に遊んでいれば続いている。1 日空いたら 0。
  int streakOn(int today) => lastDay >= today - 1 ? streak : 0;

  /// [day] のスコア [score] を記録する。その日の最初の 1 回なら `counted` が true。
  ({DailyRecord record, bool counted}) submit(int day, int score) {
    if (playedOn(day)) return (record: this, counted: false);
    return (
      record: DailyRecord(
        lastDay: day,
        lastScore: score,
        bestScore: math.max(bestScore, score),
        streak: lastDay == day - 1 ? streak + 1 : 1,
      ),
      counted: true,
    );
  }

  Map<String, Object?> toJson() => {
    'version': version,
    'lastDay': lastDay,
    'lastScore': lastScore,
    'bestScore': bestScore,
    'streak': streak,
  };

  /// 保存した文字列を読む。`intact` が false なら、型の違う項目がある・JSON として読めない・
  /// 今より新しい版のデータのどれかで、そのまま上書きすると元のデータを失う。
  static ({DailyRecord record, bool intact}) decode(String raw) {
    final Object? json;
    try {
      json = jsonDecode(raw);
    } on FormatException {
      return (record: const DailyRecord(), intact: false);
    }
    if (json is! Map<String, Object?>) {
      return (record: const DailyRecord(), intact: false);
    }
    final map = json;
    var intact = true;
    int read(String key, int fallback) {
      final v = map[key];
      if (v == null) return fallback;
      if (v is num && v.isFinite) return v.toInt();
      intact = false;
      return fallback;
    }

    final v = json['version'];
    if (v != null && !(v is int && v <= version)) intact = false;
    final record = DailyRecord(
      lastDay: read('lastDay', -1),
      lastScore: read('lastScore', 0),
      bestScore: read('bestScore', 0),
      streak: read('streak', 0),
    );
    return (record: record, intact: intact);
  }
}

/// デイリーの日付を決める時刻。テストでは偽の時刻に差し替える。
final dailyClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

class DailyNotifier extends Notifier<DailyRecord> {
  static const key = 'daily.v1';

  /// 読めなかった (一部でも捨てた) 元のデータの退避先。最新の 1 世代だけを残す。
  static const brokenKey = 'daily.broken';

  @override
  DailyRecord build() {
    final prefs = ref.read(sharedPrefsProvider);
    final raw = prefs.getString(key);
    if (raw == null) return const DailyRecord();
    final (:record, :intact) = DailyRecord.decode(raw);
    if (!intact) prefs.setString(brokenKey, raw);
    return record;
  }

  /// [day] のデイリーの結果を記録する。その日の最初の 1 回なら `counted` が true、
  /// そのうえで自己ベストを更新したら `newBest` が true。
  ({bool counted, bool newBest}) submit(int day, int score) {
    final old = state;
    final (:record, :counted) = old.submit(day, score);
    if (!counted) return (counted: false, newBest: false);
    state = record;
    ref.read(sharedPrefsProvider).setString(key, jsonEncode(record.toJson()));
    return (counted: true, newBest: score > old.bestScore);
  }
}

final dailyProvider = NotifierProvider<DailyNotifier, DailyRecord>(
  DailyNotifier.new,
);
