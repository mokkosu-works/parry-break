import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/core.dart';
import '../render/cosmetics.dart';
import 'settings.dart';

// プレイヤーレベル (design.md 9.9)。遊び終えるたびに経験値 (XP) が貯まり、累計 XP からレベルが決まる。
// XP はゲームの外で、終わった結果 (`RunStats` など) から計算する。コアの挙動には関わらない。

/// 何を遊んだか (XP の決め方が違う)。練習場は結果画面がないので入れない。
enum PlayKind {
  /// エンドレス (NORMAL / EASY)。
  endless,

  /// デイリーチャレンジ。
  daily,

  /// ステージモード。
  stage,
}

/// XP の決め方の数値。ここ以外に直書きしない。
/// 今日のお題 (9.10) の報酬は別枠で、`QuestRules` (`quests.dart`) にある。
class XpRules {
  const XpRules({
    this.base = 50,
    this.perParry = 2,
    this.perJust = 4,
    this.perRound = 15,
    this.stageClear = 100,
    this.perStar = 30,
    this.perFever = 20,
    this.cap = 1500,
    this.easyScale = 0.8,
  });

  /// 1 回遊ぶごとの基本 (負けた回も入る)。
  final int base;

  /// パリィ 1 回あたり。JUST は [perJust] (GOOD・PERFECT は [perParry])。
  final int perParry, perJust;

  /// 到達ラウンド 1 つあたり (エンドレス・デイリー)。
  final int perRound;

  /// ステージをクリアしたときの加算と、今回達成した星 1 つあたり。
  final int stageClear, perStar;

  /// FEVER TIME に入った 1 回あたり。
  final int perFever;

  /// 1 回のプレイで入る XP の上限 (難易度の倍率をかけたあとの値に効かせる)。
  /// 数十分の長いプレイで一気に上がりすぎないようにする。
  final int cap;

  /// EASY で遊んだときの倍率。
  final double easyScale;

  static const standard = XpRules();

  /// 1 回のプレイで入る XP。遊んだ中身だけで決まる (スコアは使わない。モードで桁が違うので)。
  /// [round] は到達ラウンド (ステージでは使わない)。[stars] はステージで今回達成した星の数。
  int xpFor({
    required PlayKind kind,
    required RunStats stats,
    int round = 0,
    bool cleared = false,
    int stars = 0,
    Difficulty difficulty = Difficulty.normal,
  }) {
    // parries は JUST・PERFECT を含む成功の総数
    final just = math.min(stats.just, stats.parries);
    final parry = (stats.parries - just) * perParry + just * perJust;
    final mode = switch (kind) {
      PlayKind.endless || PlayKind.daily => math.max(0, round) * perRound,
      PlayKind.stage =>
        (cleared ? stageClear : 0) + math.max(0, stars) * perStar,
    };
    final raw = base + parry + mode + math.max(0, stats.fevers) * perFever;
    final scaled = difficulty == Difficulty.easy ? raw * easyScale : raw * 1.0;
    return math.min(cap, scaled.round());
  }
}

/// レベルの曲線。Lv1 から始まり、Lv n から n+1 に要る XP は `base + (n-1) * step`。
class LevelCurve {
  const LevelCurve({this.base = 100, this.step = 40, this.maxLevel = 99});

  /// Lv1 → Lv2 に要る XP と、1 レベルごとの増え方。
  final int base, step;

  /// 上限のレベル。
  final int maxLevel;

  static const standard = LevelCurve();

  /// レベル [level] から次のレベルに要る XP (上限のレベルでは 0)。
  int xpToNext(int level) =>
      level >= maxLevel ? 0 : base + (math.max(1, level) - 1) * step;

  /// レベル [level] になるのに要る累計 XP (Lv1 は 0)。
  int xpAt(int level) {
    final n = level.clamp(1, maxLevel) - 1;
    return base * n + step * n * (n - 1) ~/ 2;
  }

  /// 上限のレベルになる累計 XP。これを超えた分は数えない。
  int get maxXp => xpAt(maxLevel);

  /// 累計 XP [total] のときのレベルと進み。
  PlayerLevel of(int total) {
    final t = total.clamp(0, maxXp);
    var level = 1;
    // 99 回までの繰り返し。二次式を解くより、曲線を変えても壊れない。
    while (level < maxLevel && t >= xpAt(level + 1)) {
      level++;
    }
    return PlayerLevel._(
      level: level,
      into: t - xpAt(level),
      need: xpToNext(level),
    );
  }
}

/// 累計 XP から計算した、いまのレベルと次のレベルまでの進み。
class PlayerLevel {
  const PlayerLevel._({
    required this.level,
    required this.into,
    required this.need,
  });

  final int level;

  /// このレベルになってから貯めた XP と、次のレベルまでに要る XP (上限のレベルでは 0)。
  final int into, need;

  bool get isMax => need == 0;

  /// 次のレベルまでの進み (0〜1)。上限のレベルでは 1。
  double get fraction => isMax ? 1 : into / need;

  /// 次のレベルまであと何 XP か (上限のレベルでは 0)。
  int get remaining => need - into;
}

/// プレイヤーの進み (保存する)。保存するのは累計 XP だけで、レベルはそこから計算する。
class Progress {
  const Progress({this.totalXp = 0, this.curve = LevelCurve.standard});

  final int totalXp;
  final LevelCurve curve;

  static const version = 1;

  PlayerLevel get player => curve.of(totalXp);
  int get level => player.level;

  Map<String, Object?> toJson() => {'version': version, 'xp': totalXp};

  /// 保存した文字列を読む。壊れたデータ (JSON として読めない・型が違う・負の値) は 0 として読む。
  /// `intact` が false なら、そのまま上書きすると元のデータを失う
  /// (読めない・型が違う・今より新しい版のどれか)。
  static ({Progress progress, bool intact}) decode(String raw) {
    final Object? json;
    try {
      json = jsonDecode(raw);
    } on FormatException {
      return (progress: const Progress(), intact: false);
    }
    if (json is! Map<String, Object?>) {
      return (progress: const Progress(), intact: false);
    }
    var intact = true;
    final v = json['version'];
    if (v != null && !(v is int && v <= version)) intact = false;
    final xp = json['xp'];
    var total = 0;
    if (xp is num && xp.isFinite && xp >= 0) {
      total = xp.toInt();
    } else if (xp != null) {
      intact = false;
    }
    // 上限を超えた値 (手で書き換えたデータなど) は、上限として読む
    return (
      progress: Progress(totalXp: math.min(total, LevelCurve.standard.maxXp)),
      intact: intact,
    );
  }
}

/// 1 回のプレイで XP が入ったときの変化。レベルが上がったかはここだけで決める
/// (前のレベル → 新しいレベル。見た目の解放など、レベルに結びつく処理はここを見る)。
class LevelGain {
  const LevelGain({
    required this.xp,
    required this.before,
    required this.after,
  });

  /// 入った XP (上限のレベルでは、数えきれずに捨てた分も含む)。
  final int xp;
  final PlayerLevel before, after;

  int get fromLevel => before.level;
  int get toLevel => after.level;
  bool get leveledUp => toLevel > fromLevel;

  /// 今回の上がりで新しく解放された見た目 (パドルの色・軌跡の色。解放の表は [Cosmetics])。
  List<CosmeticUnlock> get unlocked =>
      Cosmetics.unlockedBetween(fromLevel, toLevel);

  /// 今回新しく届いたレベル (一度に何段か上がったときは全部)。
  Iterable<int> get reached sync* {
    for (var l = fromLevel + 1; l <= toLevel; l++) {
      yield l;
    }
  }
}

class ProgressNotifier extends Notifier<Progress> {
  static const key = 'progress.v1';

  /// 読めなかった (一部でも捨てた) 元のデータの退避先。最新の 1 世代だけを残す。
  static const brokenKey = 'progress.broken';

  @override
  Progress build() {
    final prefs = ref.read(sharedPrefsProvider);
    final raw = prefs.getString(key);
    if (raw == null) return const Progress();
    final (:progress, :intact) = Progress.decode(raw);
    if (!intact) prefs.setString(brokenKey, raw);
    return progress;
  }

  /// [xp] を足して保存し、レベルの変化を返す。
  LevelGain award(int xp) {
    final old = state;
    final int total = math.min(old.curve.maxXp, old.totalXp + math.max(0, xp));
    final next = Progress(totalXp: total, curve: old.curve);
    if (total != old.totalXp) {
      state = next;
      ref.read(sharedPrefsProvider).setString(key, jsonEncode(next.toJson()));
    }
    return LevelGain(
      xp: math.max(0, xp),
      before: old.player,
      after: next.player,
    );
  }
}

final progressProvider = NotifierProvider<ProgressNotifier, Progress>(
  ProgressNotifier.new,
);
