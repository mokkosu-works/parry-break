import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:parry_break/core/core.dart';
import 'package:parry_break/services/achievements.dart';
import 'package:parry_break/services/records.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/helpers.dart';

final campaign = Campaign.fromJson(
  jsonDecode(File('assets/stages/campaign.json').readAsStringSync())
      as Map<String, Object?>,
  endlessContent,
);

ParrySucceeded parry(
  ParryGrade g, {
  ParryTarget t = ParryTarget.ball,
  int streak = 1,
}) =>
    ParrySucceeded(grade: g, target: t, x: 0, y: 0, paddleX: 0, streak: streak);

RoundStarted round(int n, {int? boss}) =>
    RoundStarted(number: n, loop: 0, bossIndex: boss);

/// イベントを流して、解除された実績を返す。
Set<AchievementKind> run_(Iterable<GameEvent> events, {bool endless = true}) {
  final got = <AchievementKind>{};
  final t = AchievementTracker(endless: endless, onUnlock: got.add);
  events.forEach(t.observe);
  return got;
}

void main() {
  group('プレイ中の実績', () {
    test('手ほどき: 解除される場合とされない場合', () {
      expect(run_([parry(ParryGrade.good)]), isEmpty);
      expect(run_([parry(ParryGrade.perfect)]), {AchievementKind.firstPerfect});
      expect(run_([parry(ParryGrade.just)]), {
        AchievementKind.firstPerfect,
        AchievementKind.firstJust,
      });
      expect(run_([parry(ParryGrade.good, t: ParryTarget.bullet)]), {
        AchievementKind.firstReturn,
      });
      expect(run_([const FeverTimeStarted()]), {AchievementKind.firstFever});
      expect(run_([const FeverTimeEnded(byHit: true)]), isEmpty);
    });

    test('1 プレイで JUST 10 回 (9 回では解除しない)', () {
      expect(
        run_(List.filled(9, parry(ParryGrade.just))),
        isNot(contains(AchievementKind.just10)),
      );
      expect(
        run_(List.filled(10, parry(ParryGrade.just))),
        contains(AchievementKind.just10),
      );
    });

    test('ノーミスパリィ 30 連続', () {
      expect(
        run_([parry(ParryGrade.good, streak: 29)]),
        isNot(contains(AchievementKind.parry30)),
      );
      expect(
        run_([parry(ParryGrade.good, streak: 30)]),
        contains(AchievementKind.parry30),
      );
    });

    test('RICOCHET ×20', () {
      expect(run_([const RicochetBonus(19, 1)]), isEmpty);
      expect(run_([const RicochetBonus(20, 1)]), {AchievementKind.ricochet20});
    });

    test('1 ラウンドでグレイズ 20 (ラウンドをまたぐと数え直す)', () {
      final g = const Grazed(0);
      expect(run_([round(1), ...List.filled(19, g)]), isEmpty);
      expect(run_([round(1), ...List.filled(20, g)]), {
        AchievementKind.graze20,
      });
      expect(
        run_([
          round(1),
          ...List.filled(19, g),
          round(2),
          ...List.filled(19, g),
        ]),
        isEmpty,
      );
    });

    test('崩落 ×30 と 1,000,000 点は World の値から見る', () {
      final got = <AchievementKind>{};
      final t = AchievementTracker(endless: true, onUnlock: got.add);
      final w = testWorld(endlessMode);
      t.observeWorld(w);
      expect(got, isEmpty);
      w.cascade.n = 30;
      w.score = 999999;
      t.observeWorld(w);
      expect(got, {AchievementKind.collapse30});
      w.score = 1000000;
      t.observeWorld(w);
      expect(got, {AchievementKind.collapse30, AchievementKind.score1m});
    });

    test('エンドレス: R20 / R60 到達。ステージとデイリーでは解除しない', () {
      expect(run_([round(19)]), isEmpty);
      expect(run_([round(20)]), {AchievementKind.endlessR20});
      expect(run_([round(60)]), {
        AchievementKind.endlessR20,
        AchievementKind.endlessR60,
      });
      expect(run_([round(60)], endless: false), isEmpty);
      final got = <AchievementKind>{};
      final t = AchievementTracker(endless: false, onUnlock: got.add);
      final w = testWorld(endlessMode)..score = 2000000;
      t.observeWorld(w);
      expect(got, isEmpty);
    });

    test('ボスを被弾なしで撃破 (被弾したラウンド・ボスでないラウンドは対象外)', () {
      const cleared = RoundCleared(bonuses: [], remaining: [], ending: false);
      expect(run_([round(10, boss: 0), cleared]), {AchievementKind.bossNoHit});
      expect(run_([round(10, boss: 0), const PlayerHurt(0), cleared]), isEmpty);
      expect(run_([round(9), cleared]), isEmpty);
      // 前のラウンドの被弾は数えない
      expect(
        run_([round(9), const PlayerHurt(0), round(10, boss: 0), cleared]),
        {AchievementKind.bossNoHit},
      );
    });

    test('同じプレイで同じ実績を 2 回呼ばない。reset で数え直す', () {
      var n = 0;
      final t = AchievementTracker(endless: true, onUnlock: (_) => n++);
      t.observe(parry(ParryGrade.perfect));
      t.observe(parry(ParryGrade.perfect));
      expect(n, 1);
      t.reset();
      t.observe(parry(ParryGrade.perfect));
      expect(n, 2);
    });
  });

  group('デバッグモードと練習場', () {
    test('練習場は判定役がない。デバッグモードの間は解除しない', () {
      expect(
        AchievementTracker.forPlay(
          practice: true,
          debug: () => false,
          endless: true,
          onUnlock: (_) {},
        ),
        isNull,
      );
      var debug = true;
      final got = <AchievementKind>{};
      final t = AchievementTracker.forPlay(
        practice: false,
        debug: () => debug,
        endless: true,
        onUnlock: got.add,
      )!;
      t.observe(parry(ParryGrade.just));
      expect(got, isEmpty);
      debug = false;
      t.observe(const FeverTimeStarted());
      expect(got, {AchievementKind.firstFever});
    });
  });

  group('進行の実績', () {
    StageRecord cleared([List<bool>? stars, bool c = true]) =>
        StageRecord(cleared: c, stars: stars ?? const []);

    Map<String, StageRecord> chapter(int i, {String suffix = ''}) => {
      for (final s in campaign.chapters[i].stages) '${s.id}$suffix': cleared(),
    };

    test('章のクリアは、その章の全ステージをクリアしたとき', () {
      final r = Records(stages: chapter(0));
      expect(progressAchievements(r, campaign), {AchievementKind.chapter1});
      final partial = Records(
        stages: {...chapter(1)}..remove(campaign.chapters[1].stages.last.id),
      );
      expect(progressAchievements(partial, campaign), isEmpty);
      final all = Records(stages: {for (var i = 0; i < 6; i++) ...chapter(i)});
      expect(
        progressAchievements(
          all,
          campaign,
        ).where((a) => a.name.startsWith('chapter')),
        hasLength(6),
      );
      // どの難易度でもよい
      expect(
        progressAchievements(
          Records(stages: chapter(2, suffix: Difficulty.hard.recordSuffix)),
          campaign,
        ),
        containsAll([AchievementKind.chapter3, AchievementKind.hardClear]),
      );
    });

    test('全ステージで星 3 つ (1 つ欠けても解除しない)', () {
      Map<String, StageRecord> full({String? missing}) => {
        for (final s in campaign.stages)
          s.id: cleared([
            for (var i = 0; i < s.stars.length; i++) s.id != missing || i > 0,
          ]),
      };
      expect(
        progressAchievements(Records(stages: full()), campaign),
        contains(AchievementKind.allStars),
      );
      expect(
        progressAchievements(Records(stages: full(missing: '3-4')), campaign),
        isNot(contains(AchievementKind.allStars)),
      );
    });

    test('HARD で任意の章をクリア: NORMAL のクリアだけでは解除しない', () {
      expect(
        progressAchievements(Records(stages: chapter(0)), campaign),
        isNot(contains(AchievementKind.hardClear)),
      );
      final hard = Records(
        stages: {'1-1${Difficulty.hard.recordSuffix}': cleared()},
      );
      expect(progressAchievements(hard, campaign), {AchievementKind.hardClear});
    });
  });

  group('送信と保存', () {
    late SharedPreferences prefs;
    late _Platform platform;
    late GamesServicesAchievements svc;

    Future<void> init([Map<String, Object> initial = const {}]) async {
      SharedPreferences.setMockInitialValues(initial);
      prefs = await SharedPreferences.getInstance();
      platform = _Platform();
      svc = GamesServicesAchievements(prefs, platform);
    }

    Set<String> stored(String key) => {
      for (final v in jsonDecode(prefs.getString(key) ?? '[]') as List)
        v as String,
    };

    setUp(() {
      AchievementConfig.placeholders.clear(); // ストアで作った後の状態
      addTearDown(
        () => AchievementConfig.placeholders.addAll(AchievementKind.values),
      );
    });

    test('サインイン後は解除の時点で 1 回だけ送る', () async {
      await init();
      await svc.sync(const Records(), campaign);
      await svc.unlock(AchievementKind.firstJust);
      await svc.unlock(AchievementKind.firstJust);
      expect(platform.sent, [AchievementKind.firstJust]);
      expect(stored(GamesServicesAchievements.pendingKey), isEmpty);
    });

    test('同時に 2 回呼んでも 1 回だけ送る', () async {
      await init();
      await svc.sync(const Records(), campaign);
      platform.hold = true;
      final a = svc.unlock(AchievementKind.firstJust);
      final b = svc.unlock(AchievementKind.firstJust);
      platform.release();
      await Future.wait([a, b]);
      expect(platform.sent, hasLength(1));
    });

    test('サインインしていない・送れない分は保留し、次の sync で送る', () async {
      await init();
      platform.signedIn = false;
      await svc.sync(const Records(), campaign);
      await svc.unlock(AchievementKind.firstFever);
      expect(platform.sent, isEmpty);
      expect(stored(GamesServicesAchievements.pendingKey), {'firstFever'});
      platform.signedIn = true;
      platform.fail = true;
      await svc.sync(const Records(), campaign);
      expect(stored(GamesServicesAchievements.pendingKey), {'firstFever'});
      platform.fail = false;
      await svc.sync(const Records(), campaign);
      expect(platform.sent, [AchievementKind.firstFever]);
      expect(stored(GamesServicesAchievements.pendingKey), isEmpty);
      // 解除済みなので、もう一度解除しても送らない
      await svc.unlock(AchievementKind.firstFever);
      expect(platform.sent, hasLength(1));
    });

    test('送信中に増えた保留を消さない', () async {
      await init({
        GamesServicesAchievements.unlockedKey: jsonEncode(['firstFever']),
        GamesServicesAchievements.pendingKey: jsonEncode(['firstFever']),
      });
      platform.hold = true;
      final sync = svc.sync(const Records(), campaign);
      await Future<void>.delayed(Duration.zero);
      platform.failOn.add(AchievementKind.firstJust);
      final other = svc.unlock(AchievementKind.firstJust);
      platform.release();
      await Future.wait([sync, other]);
      expect(stored(GamesServicesAchievements.pendingKey), {'firstJust'});
    });

    test('解除済みの保存は新しいキーで、records と保留のキーには触らない。古い・壊れたデータでも消えない', () async {
      await init({
        'records': '{"version":1}',
        'leaderboard.pending': '{"endlessScore":5}',
        GamesServicesAchievements.unlockedKey: 'broken',
      });
      await svc.sync(const Records(), campaign);
      await svc.unlock(AchievementKind.firstJust);
      expect(prefs.getString('records'), '{"version":1}');
      expect(prefs.getString('leaderboard.pending'), '{"endlessScore":5}');
      expect(GamesServicesAchievements.unlockedKey, isNot('records'));
      expect(stored(GamesServicesAchievements.unlockedKey), {'firstJust'});
    });

    test('最初のサインインで、実績を足す前の星・クリアから進行の実績を解除する', () async {
      await init();
      final r = Records(
        stages: {
          for (final s in campaign.chapters[0].stages)
            s.id: const StageRecord(cleared: true),
        },
      );
      await svc.sync(r, campaign);
      expect(platform.sent, [AchievementKind.chapter1]);
      await svc.sync(r, campaign);
      expect(platform.sent, hasLength(1));
    });

    test('ID が仮の実績は送らず、解除済みにも保留にもしない', () async {
      await init();
      AchievementConfig.placeholders.add(AchievementKind.firstJust);
      await svc.sync(const Records(), campaign);
      await svc.unlock(AchievementKind.firstJust);
      expect(platform.sent, isEmpty);
      expect(stored(GamesServicesAchievements.unlockedKey), isEmpty);
      expect(stored(GamesServicesAchievements.pendingKey), isEmpty);
    });

    test('実績の仮 ID は初期状態で全部仮 (送らない)', () {
      AchievementConfig.placeholders.addAll(AchievementKind.values);
      expect(AchievementConfig.anyReady, isFalse);
      expect(AchievementKind.values, hasLength(21));
      expect(achievementPoints.keys.toSet(), AchievementKind.values.toSet());
    });
  });
}

class _Platform extends AchievementPlatform {
  bool signedIn = true, fail = false, hold = false;
  final failOn = <AchievementKind>{};
  final sent = <AchievementKind>[];
  final _gate = <Completer<void>>[];

  void release() {
    hold = false;
    for (final c in _gate) {
      c.complete();
    }
    _gate.clear();
  }

  @override
  Future<bool> get isSignedIn async => signedIn;

  @override
  Future<void> unlock(AchievementKind a) async {
    if (hold) {
      final c = Completer<void>();
      _gate.add(c);
      await c.future;
    }
    if (fail || failOn.contains(a)) throw Exception('x');
    sent.add(a);
  }

  @override
  Future<void> showAchievements() async {}
}
