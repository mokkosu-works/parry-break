import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/core.dart';
import 'daily.dart';
import 'progress.dart';
import 'settings.dart';

// 今日のお題 (design.md 9.10)。毎日 3 つ (易しい・ふつう・少し難しいを 1 つずつ) の小さな目標で、
// 達成すると XP が入る。お題の進みは、遊び終えた結果 (`RunStats` など) から数える。
// 日付の区切りは DAILY と同じ (UTC の日付 = `DailyChallenge.day`)。コアの挙動には関わらない。

/// お題の難しさ。1 日に 1 つずつ出る。
enum QuestTier { easy, normal, hard }

/// 報酬の数値。ここ以外に直書きしない。プレイの XP の 1 回上限 ([XpRules.cap]) とは別枠で足す。
class QuestRules {
  const QuestRules({
    this.easy = 100,
    this.normal = 150,
    this.hard = 250,
    this.allClear = 200,
  });

  /// お題 1 つを達成したときの XP (難しさごと)。
  final int easy, normal, hard;

  /// 3 つ全部を達成したときの追加。
  final int allClear;

  static const standard = QuestRules();

  int xpOf(QuestTier tier) => switch (tier) {
    QuestTier.easy => easy,
    QuestTier.normal => normal,
    QuestTier.hard => hard,
  };
}

/// 1 回のプレイの結果のうち、お題の数え方に使うもの。練習場・デバッグモードでは作らない。
class QuestPlay {
  const QuestPlay({
    required this.kind,
    required this.stats,
    this.round = 0,
    this.score = 0,
    this.cleared = false,
  });

  final PlayKind kind;
  final RunStats stats;

  /// 到達ラウンドとスコア (エンドレス)。
  final int round, score;

  /// ステージをクリアしたか。
  final bool cleared;
}

/// お題の種類と、難しさごとの目標の値。値はこの表だけにある。
/// `targets` は [易しい, ふつう, 少し難しい] の目標で、null はその難しさでは出さない。
enum QuestKind {
  /// その日の全プレイの合計遊んだ回数。
  plays('plays', [3, 5, null]),

  /// DAILY を遊ぶ。
  dailyPlay('daily', [1, null, null]),

  /// PERFECT 以上 (JUST を含む) のパリィの合計。
  perfect('perfect', [10, 20, 40]),

  /// JUST の合計。
  just('just', [null, 5, 10]),

  /// FEVER TIME に入った合計。
  fever('fever', [null, 2, 4]),

  /// エンドレス 1 回のプレイで届いたラウンド (合計ではなく 1 回の最高)。
  endlessRound('round', [4, 8, 12]),

  /// クリアしたステージの数 (合計)。
  stageClear('stage', [1, 2, 3]),

  /// 撃ち返した弾で壊したブロックの数 (合計)。
  returnKills('returnKills', [3, 8, 15]),

  /// エンドレス 1 回のプレイのスコア (合計ではなく 1 回の最高)。
  endlessScore('score', [500000, 1500000, 4000000]);

  const QuestKind(this.id, this.targets);

  /// 保存に使う名前。
  final String id;
  final List<int?> targets;

  /// 難しさ [tier] での目標 (出さないなら null)。
  int? target(QuestTier tier) => targets[tier.index];

  /// 1 回のプレイの最高で決まる (合計ではない) 種類。
  bool get perRun => this == endlessRound || this == endlessScore;

  /// [p] の 1 回のプレイが、この種類に足す値 (perRun は、そのプレイの値)。
  int valueOf(QuestPlay p) {
    final endless = p.kind == PlayKind.endless;
    return switch (this) {
      plays => 1,
      dailyPlay => p.kind == PlayKind.daily ? 1 : 0,
      perfect => p.stats.perfects,
      just => p.stats.just,
      fever => p.stats.fevers,
      endlessRound => endless ? p.round : 0,
      stageClear => p.kind == PlayKind.stage && p.cleared ? 1 : 0,
      returnKills => p.stats.returnKills,
      endlessScore => endless ? p.score : 0,
    };
  }

  static QuestKind? byId(Object? id) {
    for (final k in values) {
      if (k.id == id) return k;
    }
    return null;
  }
}

/// 今日のお題の 1 つ。
class Quest {
  const Quest({
    required this.kind,
    required this.tier,
    this.progress = 0,
    this.done = false,
  }) : assert(progress >= 0);

  final QuestKind kind;
  final QuestTier tier;

  /// 進み (目標を超えた分は数えない)。
  final int progress;

  /// 達成して報酬を受け取ったか。
  final bool done;

  int get target => kind.target(tier)!;
  int get xp => QuestRules.standard.xpOf(tier);

  /// 進みの割合 (0〜1)。
  double get fraction => done ? 1 : (progress / target).clamp(0.0, 1.0);

  Quest _with(int progress, bool done) =>
      Quest(kind: kind, tier: tier, progress: progress, done: done);

  Map<String, Object?> toJson() => {
    'kind': kind.id,
    'tier': tier.index,
    'progress': progress,
    'done': done,
  };
}

/// 1 回のプレイで起きたお題の変化。
class QuestResult {
  const QuestResult({this.cleared = const [], this.allClear = false});

  /// 今回新しく達成したお題 (易しい順)。
  final List<Quest> cleared;

  /// 今回で 3 つ全部が終わった (追加の XP が入る)。
  final bool allClear;

  bool get isEmpty => cleared.isEmpty;

  /// 今回入るお題の XP (全部終えた追加を含む)。
  int get xp =>
      cleared.fold(0, (s, q) => s + q.xp) +
      (allClear ? QuestRules.standard.allClear : 0);
}

/// ある日の 3 つのお題と進み (保存する)。
class QuestBoard {
  const QuestBoard({required this.day, required this.quests});

  /// 日付 ([DailyChallenge.day]。UTC)。
  final int day;

  /// 易しい・ふつう・少し難しいの順に 3 つ。
  final List<Quest> quests;

  static const version = 1;

  int get doneCount => quests.where((q) => q.done).length;
  bool get allDone => quests.every((q) => q.done);

  /// [day] の日のお題 (すべて進み 0)。日付だけから決まる (同じ日なら何度でも同じ)。
  /// 難しさごとに、その難しさで出せる種類のうち、すでに選んだものを除いて 1 つ選ぶ (種類は重ならない)。
  factory QuestBoard.generate(int day) {
    final used = <QuestKind>{};
    final quests = <Quest>[];
    for (final tier in QuestTier.values) {
      final pool = [
        for (final k in QuestKind.values)
          if (k.target(tier) != null && !used.contains(k)) k,
      ];
      final kind = pool[_mix(day, tier.index) % pool.length];
      used.add(kind);
      quests.add(Quest(kind: kind, tier: tier));
    }
    return QuestBoard(day: day, quests: quests);
  }

  /// 日付と番号から作る 32 ビットの値 (ビットの混ぜ合わせ。同じ入力なら同じ値)。
  static int _mix(int day, int salt) {
    const m = 0xFFFFFFFF;
    var x = (day * 0x9E3779B1 + salt * 0x85EBCA6B + 0x27D4EB2F) & m;
    x ^= x >> 15;
    x = (x * 0x2C1B3C6D) & m;
    x ^= x >> 12;
    x = (x * 0x297A2D39) & m;
    x ^= x >> 15;
    return x;
  }

  /// [today] の日のお題。保存してあるのが別の日なら、その日の新しいお題。
  QuestBoard on(int today) => day == today ? this : QuestBoard.generate(today);

  /// 1 回のプレイを数える。達成済みのお題は変えない。
  ({QuestBoard board, QuestResult result}) apply(QuestPlay play) {
    final next = <Quest>[];
    final cleared = <Quest>[];
    for (final q in quests) {
      if (q.done) {
        next.add(q);
        continue;
      }
      final v = q.kind.valueOf(play);
      final int raw = q.kind.perRun
          ? math.max(q.progress, v)
          : q.progress + math.max(0, v);
      final int progress = math.min(q.target, raw);
      final n = q._with(progress, progress >= q.target);
      next.add(n);
      if (n.done) cleared.add(n);
    }
    final board = QuestBoard(day: day, quests: next);
    return (
      board: board,
      // 全部が終わるのは、今回の達成で最後の 1 つが埋まったときだけ (すでに終えていれば cleared は空)
      result: QuestResult(
        cleared: cleared,
        allClear: cleared.isNotEmpty && board.allDone,
      ),
    );
  }

  Map<String, Object?> toJson() => {
    'version': version,
    'day': day,
    'quests': [for (final q in quests) q.toJson()],
  };

  /// 保存した文字列を読む。`board` が null なら使えない (JSON として読めない・型が違う・3 つそろっていない・
  /// 知らない種類) ので、その日の新しいお題を作り直す。`intact` が false なら、そのまま上書きすると
  /// 元のデータを失う (使えない・今より新しい版のどちらか)。
  static ({QuestBoard? board, bool intact}) decode(String raw) {
    const broken = (board: null, intact: false);
    final Object? json;
    try {
      json = jsonDecode(raw);
    } on FormatException {
      return broken;
    }
    if (json is! Map<String, Object?>) return broken;
    final v = json['version'];
    final intact = v == null || (v is int && v <= version);
    final day = json['day'];
    final list = json['quests'];
    if (day is! num || !day.isFinite || day < 0 || list is! List) {
      return broken;
    }
    final quests = <Quest>[];
    for (final e in list) {
      if (e is! Map<String, Object?>) return broken;
      final kind = QuestKind.byId(e['kind']);
      final t = e['tier'];
      final p = e['progress'];
      final done = e['done'];
      if (kind == null ||
          t is! int ||
          t < 0 ||
          t >= QuestTier.values.length ||
          p is! num ||
          !p.isFinite ||
          p < 0 ||
          done is! bool) {
        return broken;
      }
      final tier = QuestTier.values[t];
      final target = kind.target(tier);
      if (target == null) return broken;
      quests.add(
        Quest(
          kind: kind,
          tier: tier,
          progress: math.min(target, p.toInt()),
          done: done,
        ),
      );
    }
    quests.sort((a, b) => a.tier.index.compareTo(b.tier.index));
    final tiers = {for (final q in quests) q.tier};
    final kinds = {for (final q in quests) q.kind};
    if (quests.length != QuestTier.values.length ||
        tiers.length != quests.length ||
        kinds.length != quests.length) {
      return broken;
    }
    return (
      board: QuestBoard(day: day.toInt(), quests: quests),
      intact: intact,
    );
  }
}

class QuestNotifier extends Notifier<QuestBoard> {
  static const key = 'quests.v1';

  /// 読めなかった (一部でも捨てた) 元のデータの退避先。最新の 1 世代だけを残す。
  static const brokenKey = 'quests.broken';

  int _today() => DailyChallenge.of(ref.read(dailyClockProvider)()).day;

  @override
  QuestBoard build() {
    final prefs = ref.read(sharedPrefsProvider);
    final raw = prefs.getString(key);
    final today = _today();
    if (raw == null) return QuestBoard.generate(today);
    final (:board, :intact) = QuestBoard.decode(raw);
    if (!intact) prefs.setString(brokenKey, raw);
    // 別の日・壊れたデータは、その日の新しいお題 (最初のプレイを数えるときに保存する)
    return board?.on(today) ?? QuestBoard.generate(today);
  }

  /// 1 回のプレイを数えて保存し、新しく達成したお題を返す (XP は足さない。呼ぶ側が [QuestResult.xp] を
  /// プレイの XP と合わせて `ProgressNotifier.award` に渡す)。練習場・デバッグモードでは呼ばない。
  QuestResult record(QuestPlay play) {
    final (:board, :result) = state.on(_today()).apply(play);
    state = board;
    ref.read(sharedPrefsProvider).setString(key, jsonEncode(board.toJson()));
    return result;
  }
}

final questsProvider = NotifierProvider<QuestNotifier, QuestBoard>(
  QuestNotifier.new,
);
