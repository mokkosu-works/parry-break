import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:games_services/games_services.dart' as gs;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/core.dart';
import 'leaderboard.dart';
import 'records.dart';
import 'settings.dart';

/// 実績。ストアに作る実績と 1 対 1 (名前・説明・点数は docs/app-store.md / docs/play-store.md の表)。
enum AchievementKind {
  // 手ほどき
  firstPerfect,
  firstJust,
  firstReturn,
  firstFever,
  // 技
  just10,
  parry30,
  collapse30,
  ricochet20,
  graze20,
  // 進行
  chapter1,
  chapter2,
  chapter3,
  chapter4,
  chapter5,
  chapter6,
  allStars,
  // エンドレス
  endlessR20,
  endlessR60,
  score1m,
  // 挑戦
  bossNoHit,
  hardClear;

  /// 進行の実績 (記録から判定する。サインインのときの見直しの対象)。
  bool get isProgress => switch (this) {
    chapter1 ||
    chapter2 ||
    chapter3 ||
    chapter4 ||
    chapter5 ||
    chapter6 ||
    allStars ||
    hardClear => true,
    _ => false,
  };
}

/// ストアで作った実績の ID。
///
/// 作り方は docs/app-store.md(Game Center)と docs/play-store.md(Play Games サービス)の
/// 「実績」。作ったら [ios] / [android] に ID を書き、[placeholders] から外す。
abstract final class AchievementConfig {
  static const iosPrefix = 'com.watsuwo.parrybreak.ach_';

  /// Game Center の実績 ID (仮)。
  static final ios = <AchievementKind, String>{
    for (final a in AchievementKind.values) a: '$iosPrefix${a.name}',
  };

  /// Play Games サービスの実績 ID。作るまでは空。
  static const android = <AchievementKind, String>{};

  /// ID がまだ仮の値の実績 (ストアで作るまで、送らない・保留もしない)。
  static final placeholders = <AchievementKind>{...AchievementKind.values};

  /// [a] の ID が決まっているか。仮なら false で、送らない。
  static bool hasId(AchievementKind a) => !placeholders.contains(a);

  /// 送れる実績が 1 つでもあるか (なければ、実績の画面への入口も出さない)。
  static bool get anyReady => AchievementKind.values.any(hasId);
}

/// 実績の点数 (Game Center 合計 1000 以下、Play Games は 5 の倍数)。docs の表と同じ。
const achievementPoints = <AchievementKind, int>{
  AchievementKind.firstPerfect: 10,
  AchievementKind.firstJust: 10,
  AchievementKind.firstReturn: 10,
  AchievementKind.firstFever: 10,
  AchievementKind.just10: 30,
  AchievementKind.parry30: 40,
  AchievementKind.collapse30: 40,
  AchievementKind.ricochet20: 40,
  AchievementKind.graze20: 30,
  AchievementKind.chapter1: 20,
  AchievementKind.chapter2: 20,
  AchievementKind.chapter3: 30,
  AchievementKind.chapter4: 30,
  AchievementKind.chapter5: 40,
  AchievementKind.chapter6: 50,
  AchievementKind.allStars: 100,
  AchievementKind.endlessR20: 30,
  AchievementKind.endlessR60: 60,
  AchievementKind.score1m: 100,
  AchievementKind.bossNoHit: 60,
  AchievementKind.hardClear: 70,
};

/// ゲームのイベントから、プレイ中に決まる実績の条件を見る (1 回のプレイにつき 1 つ)。
///
/// 条件を満たした瞬間に [onUnlock] を呼ぶ。同じプレイの中では同じ実績を 2 回呼ばない
/// (保存済みかどうかは [AchievementService] が見る)。
class AchievementTracker {
  AchievementTracker({required this.endless, required this.onUnlock});

  /// エンドレスか (エンドレスの実績はエンドレスだけで解除する)。
  final bool endless;
  final void Function(AchievementKind) onUnlock;

  /// プレイに応じた判定役。練習場では解除しないので null。デバッグモード ([debug] が true の間)
  /// は、イベントが来ても解除しない。
  static AchievementTracker? forPlay({
    required bool practice,
    required bool Function() debug,
    required bool endless,
    required void Function(AchievementKind) onUnlock,
  }) => practice
      ? null
      : AchievementTracker(
          endless: endless,
          onUnlock: (a) {
            if (!debug()) onUnlock(a);
          },
        );

  final _fired = <AchievementKind>{};
  int _just = 0, _graze = 0, _hurtInRound = 0;
  bool _boss = false;

  /// やり直しのときに、プレイ中の数え方を戻す。
  void reset() {
    _fired.clear();
    _just = _graze = _hurtInRound = 0;
    _boss = false;
  }

  void _unlock(AchievementKind a) {
    if (_fired.add(a)) onUnlock(a);
  }

  void observe(GameEvent e) {
    switch (e) {
      case RoundStarted(:final number, :final bossIndex):
        _graze = 0;
        _hurtInRound = 0;
        _boss = bossIndex != null;
        if (endless) {
          if (number >= 20) _unlock(AchievementKind.endlessR20);
          if (number >= 60) _unlock(AchievementKind.endlessR60);
        }
      case ParrySucceeded(:final grade, :final target, :final streak):
        if (grade != ParryGrade.good) _unlock(AchievementKind.firstPerfect);
        if (grade == ParryGrade.just) {
          _unlock(AchievementKind.firstJust);
          if (++_just >= 10) _unlock(AchievementKind.just10);
        }
        if (target == ParryTarget.bullet) _unlock(AchievementKind.firstReturn);
        if (streak >= 30) _unlock(AchievementKind.parry30);
      case FeverTimeStarted():
        _unlock(AchievementKind.firstFever);
      case RicochetBonus(:final count):
        if (count >= 20) _unlock(AchievementKind.ricochet20);
      case Grazed():
        if (++_graze >= 20) _unlock(AchievementKind.graze20);
      case PlayerHurt():
        _hurtInRound++;
      case RoundCleared():
        if (_boss && _hurtInRound == 0) _unlock(AchievementKind.bossNoHit);
      default:
    }
  }

  /// イベントにならない値 (崩落の途中の数・得点) を、シミュレーションの 1 ステップごとに見る。
  void observeWorld(World w) {
    if (w.cascade.n >= 30) _unlock(AchievementKind.collapse30);
    if (endless && w.score >= 1000000) _unlock(AchievementKind.score1m);
  }
}

/// 記録から決まる進行の実績 ([AchievementKind.isProgress]) のうち、いま満たしているもの。
Set<AchievementKind> progressAchievements(Records r, Campaign c) {
  final out = <AchievementKind>{};
  final chapters = [
    AchievementKind.chapter1,
    AchievementKind.chapter2,
    AchievementKind.chapter3,
    AchievementKind.chapter4,
    AchievementKind.chapter5,
    AchievementKind.chapter6,
  ];
  for (var i = 0; i < c.chapters.length && i < chapters.length; i++) {
    final stages = c.chapters[i].stages;
    if (stages.isNotEmpty && stages.every((s) => r.clearedAny(s.id))) {
      out.add(chapters[i]);
    }
  }
  final all = c.stages.toList();
  // 星は難易度をまたいで、条件ごとに一度でも取ったものを数える
  bool starred(StageDef s, int i) =>
      Difficulty.values.any((d) => r.stage(s.id, d).hasStar(i));
  if (all.isNotEmpty &&
      all.every((s) {
        for (var i = 0; i < s.stars.length; i++) {
          if (!starred(s, i)) return false;
        }
        return true;
      })) {
    out.add(AchievementKind.allStars);
  }
  if (all.any((s) => r.stage(s.id, Difficulty.hard).cleared)) {
    out.add(AchievementKind.hardClear);
  }
  return out;
}

abstract class AchievementService {
  bool get available;

  /// 起動時に呼ぶ(サインインは [LeaderboardService] がする)。送れていなかった分を送り、
  /// 実績を足す前の進行を見直す。
  Future<void> sync(Records records, Campaign campaign);

  /// 解除する。保存済みなら何もしない。送れなければ保留して、次の [sync] で送る。
  Future<void> unlock(AchievementKind a);

  /// 端末標準の実績の画面を開く。開けなければ false。
  Future<bool> show();
}

class DisabledAchievements implements AchievementService {
  @override
  bool get available => false;
  @override
  Future<void> sync(Records records, Campaign campaign) async {}
  @override
  Future<void> unlock(AchievementKind a) async {}
  @override
  Future<bool> show() async => false;
}

/// games_services の呼び出し。テストで偽の送信先に差し替えるために分けてある。
class AchievementPlatform {
  const AchievementPlatform();
  Future<bool> get isSignedIn => gs.GamesServices.isSignedIn;
  Future<void> unlock(AchievementKind a) => gs.GamesServices.unlock(
    achievement: gs.Achievement(
      androidID: AchievementConfig.android[a] ?? '',
      iOSID: AchievementConfig.ios[a] ?? '',
      percentComplete: 100,
    ),
  );
  Future<void> showAchievements() => gs.GamesServices.showAchievements();
}

class GamesServicesAchievements implements AchievementService {
  GamesServicesAchievements(
    this._prefs, [
    this._platform = const AchievementPlatform(),
  ]);
  final SharedPreferences _prefs;
  final AchievementPlatform _platform;

  /// 解除済み (ストアに送れたかは問わない)。
  static const unlockedKey = 'achievements.unlocked.v1';

  /// 解除したがストアに送れていないもの。
  static const pendingKey = 'achievements.pending.v1';

  @override
  bool get available => true;

  Set<String> _read(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return {};
    try {
      return {for (final v in jsonDecode(raw) as List) v as String};
    } on Object {
      return {};
    }
  }

  void _write(String key, Set<String> v) =>
      _prefs.setString(key, jsonEncode(v.toList()..sort()));

  bool _signedIn = false;

  @override
  Future<void> unlock(AchievementKind a) async {
    // ID が仮の実績は、解除済みにも保留にもしない (ID を決めたあとの見直しで拾える)
    if (!AchievementConfig.hasId(a)) return;
    final unlocked = _read(unlockedKey);
    // 先に保存してから送る。送っている間に同じ実績が来ても、2 回は送らない
    if (!unlocked.add(a.name)) return;
    _write(unlockedKey, unlocked);
    if (_signedIn && await _send(a)) return;
    _write(pendingKey, _read(pendingKey)..add(a.name));
  }

  Future<bool> _send(AchievementKind a) async {
    try {
      await _platform.unlock(a);
      return true;
    } on Object catch (e) {
      debugPrint('achievement unlock failed: $e');
      return false;
    }
  }

  Future<void>? _syncing;

  @override
  Future<void> sync(Records records, Campaign campaign) =>
      _syncing ??= _sync(records, campaign).whenComplete(() => _syncing = null);

  Future<void> _sync(Records records, Campaign campaign) async {
    try {
      _signedIn = await _platform.isSignedIn;
    } on Object {
      _signedIn = false;
    }
    if (!_signedIn) return;
    // 実績を足す前に取った星・クリアを、条件を見直して解除する
    for (final a in progressAchievements(records, campaign)) {
      await unlock(a);
    }
    final kinds = AchievementKind.values.asNameMap();
    final done = <String>{};
    for (final name in _read(pendingKey)) {
      final a = kinds[name];
      // 今のバージョンにない実績と、ID が仮の実績は、送り先がないので捨てる
      if (a == null || !AchievementConfig.hasId(a) || await _send(a)) {
        done.add(name);
      }
    }
    // 送っている間に unlock が書き足した分は、読み直してから消すので残る
    _write(pendingKey, _read(pendingKey)..removeAll(done));
  }

  @override
  Future<bool> show() async {
    try {
      await _platform.showAchievements();
      return true;
    } on Object {
      return false;
    }
  }
}

final achievementsProvider = Provider<AchievementService>((ref) {
  if (!LeaderboardConfig.enabled || !AchievementConfig.anyReady || kIsWeb) {
    return DisabledAchievements();
  }
  return GamesServicesAchievements(ref.read(sharedPrefsProvider));
});
