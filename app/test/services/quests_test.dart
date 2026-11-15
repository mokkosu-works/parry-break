import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parry_break/core/core.dart';
import 'package:parry_break/services/daily.dart';
import 'package:parry_break/services/progress.dart';
import 'package:parry_break/services/quests.dart';
import 'package:parry_break/services/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 今日のお題 (design.md 9.10): 日付からの選び方・進みの数え方・報酬・保存。
void main() {
  RunStats stats({
    int parries = 0,
    int perfects = 0,
    int just = 0,
    int fevers = 0,
    int returnKills = 0,
  }) => RunStats()
    ..parries = parries
    ..perfects = perfects
    ..just = just
    ..fevers = fevers
    ..returnKills = returnKills;

  QuestPlay play(
    PlayKind kind, {
    RunStats? s,
    int round = 1,
    int score = 0,
    bool cleared = false,
  }) => QuestPlay(
    kind: kind,
    stats: s ?? stats(),
    round: round,
    score: score,
    cleared: cleared,
  );

  /// 1 つ 1 種類だけのお題の板 (数え方を種類ごとに確かめる)。
  QuestBoard single(QuestKind kind, QuestTier tier) {
    final others = [
      for (final k in QuestKind.values)
        if (k != kind && k.target(QuestTier.normal) != null) k,
    ];
    // 残りの 2 つは、確かめる種類と重ならない、動かない種類 (進み 0 のまま)
    return QuestBoard(
      day: 1,
      quests: [
        for (final t in QuestTier.values)
          if (t == tier)
            Quest(kind: kind, tier: t)
          else
            Quest(
              kind: others[t.index == 0 ? 0 : 1],
              tier: t,
            ), // 使うのは tier の 1 つだけ
      ],
    );
  }

  Quest only(QuestKind kind, QuestTier tier, QuestPlay p) {
    final (:board, :result) = single(kind, tier).apply(p);
    return board.quests.firstWhere((q) => q.kind == kind);
  }

  group('お題の表', () {
    test('どの種類も、出す難しさの目標は正で、難しさとともに増える', () {
      for (final k in QuestKind.values) {
        final ts = [
          for (final t in QuestTier.values)
            if (k.target(t) != null) k.target(t)!,
        ];
        expect(ts, isNotEmpty, reason: k.name);
        expect(ts.every((n) => n > 0), isTrue, reason: k.name);
        expect(ts, [...ts]..sort(), reason: k.name);
      }
    });

    test('どの難しさにも、3 つ選べるだけの種類がある', () {
      for (final t in QuestTier.values) {
        expect(
          QuestKind.values.where((k) => k.target(t) != null).length,
          greaterThanOrEqualTo(3),
          reason: t.name,
        );
      }
    });

    test('保存に使う名前は種類ごとに違う', () {
      final ids = {for (final k in QuestKind.values) k.id};
      expect(ids.length, QuestKind.values.length);
      for (final k in QuestKind.values) {
        expect(QuestKind.byId(k.id), k);
      }
      expect(QuestKind.byId('nope'), isNull);
    });

    test('XP: 易しい 100 / ふつう 150 / 少し難しい 250、全部終えると +200', () {
      const r = QuestRules.standard;
      expect(r.xpOf(QuestTier.easy), 100);
      expect(r.xpOf(QuestTier.normal), 150);
      expect(r.xpOf(QuestTier.hard), 250);
      expect(r.allClear, 200);
    });
  });

  group('日付からのお題の選び方', () {
    test('同じ日なら、何度作っても同じ 3 つ', () {
      for (var day = 20000; day < 20400; day++) {
        final a = QuestBoard.generate(day), b = QuestBoard.generate(day);
        expect(
          [for (final q in a.quests) (q.kind, q.tier)],
          [for (final q in b.quests) (q.kind, q.tier)],
        );
      }
    });

    test('易しい・ふつう・少し難しいが 1 つずつで、同じ種類は重ならず、進みは 0 (1 年分)', () {
      for (var day = 20000; day < 20400; day++) {
        final b = QuestBoard.generate(day);
        expect(b.day, day);
        expect([for (final q in b.quests) q.tier], QuestTier.values);
        expect({for (final q in b.quests) q.kind}.length, 3, reason: '$day');
        for (final q in b.quests) {
          expect(q.kind.target(q.tier), isNotNull, reason: '$day');
          expect(q.progress, 0);
          expect(q.done, isFalse);
        }
      }
    });

    test('日付が変わると別の 3 つになる (同じ並びが続かない・どの種類も出る)', () {
      final seen = <QuestKind>{};
      var same = 0;
      QuestBoard? prev;
      for (var day = 20000; day < 20400; day++) {
        final b = QuestBoard.generate(day);
        seen.addAll(b.quests.map((q) => q.kind));
        if (prev != null &&
            [for (final q in b.quests) q.kind].toString() ==
                [for (final q in prev.quests) q.kind].toString()) {
          same++;
        }
        prev = b;
      }
      expect(seen, QuestKind.values.toSet());
      expect(same, lessThan(10), reason: '400 日のうち、前の日と同じ並びは数日');
    });

    test('日付の区切りは DAILY と同じ (UTC)', () {
      final a = QuestBoard.generate(
        DailyChallenge.dayOf(DateTime.utc(2026, 11, 15, 0, 1)),
      );
      final b = QuestBoard.generate(
        DailyChallenge.dayOf(DateTime.utc(2026, 11, 15, 23, 59)),
      );
      final c = QuestBoard.generate(
        DailyChallenge.dayOf(DateTime.utc(2026, 11, 16)),
      );
      expect(a.day, b.day);
      expect(c.day, a.day + 1);
      // 同じ UTC の日なら、時差のある時刻で数えても同じ日
      expect(
        DailyChallenge.dayOf(DateTime.parse('2026-11-15T20:00:00-09:00')),
        a.day + 1,
      );
    });

    test('on(): 同じ日ならそのまま、別の日ならその日の新しいお題', () {
      final b = QuestBoard.generate(100);
      expect(identical(b.on(100), b), isTrue);
      expect(b.on(101).day, 101);
      expect(b.on(101).doneCount, 0);
    });
  });

  group('進みの数え方', () {
    test('合計 (plays): どのモードでも 1 回ずつ', () {
      var q = Quest(kind: QuestKind.plays, tier: QuestTier.easy);
      for (final k in PlayKind.values) {
        q = only(QuestKind.plays, QuestTier.easy, play(k));
        expect(q.progress, 1, reason: k.name);
      }
    });

    test('DAILY を遊ぶ: DAILY だけが数える', () {
      expect(
        only(QuestKind.dailyPlay, QuestTier.easy, play(PlayKind.endless)).done,
        isFalse,
      );
      expect(
        only(QuestKind.dailyPlay, QuestTier.easy, play(PlayKind.stage)).done,
        isFalse,
      );
      expect(
        only(QuestKind.dailyPlay, QuestTier.easy, play(PlayKind.daily)).done,
        isTrue,
      );
    });

    test('PERFECT 以上 (JUST を含む perfects)・JUST・FEVER・撃ち返しは、全プレイの合計', () {
      for (final (kind, s) in [
        (QuestKind.perfect, stats(perfects: 4)),
        (QuestKind.just, stats(just: 4)),
        (QuestKind.fever, stats(fevers: 4)),
        (QuestKind.returnKills, stats(returnKills: 4)),
      ]) {
        final tier = QuestTier.hard;
        var board = single(kind, tier);
        for (final pk in PlayKind.values) {
          board = board.apply(play(pk, s: s)).board;
        }
        // 3 つのモードの合計 (目標を超えないよう上限は目標)
        expect(
          board.quests.firstWhere((q) => q.kind == kind).progress,
          kind.target(tier)! < 12 ? kind.target(tier)! : 12,
          reason: kind.name,
        );
      }
    });

    test('エンドレスのラウンド・スコアは、合計ではなく 1 回のプレイの最高。DAILY・ステージは数えない', () {
      var board = single(QuestKind.endlessRound, QuestTier.normal);
      // 3 回遊んで、1 回ごとは目標 (8) に届かない。足し合わせたら 9 になるが、届いたことにはならない
      for (final r in [3, 3, 3]) {
        board = board.apply(play(PlayKind.endless, round: r)).board;
      }
      var q = board.quests.firstWhere((q) => q.kind == QuestKind.endlessRound);
      expect((q.progress, q.done), (3, false));
      // 最高を更新する
      board = board.apply(play(PlayKind.endless, round: 6)).board;
      board = board.apply(play(PlayKind.endless, round: 2)).board;
      q = board.quests.firstWhere((q) => q.kind == QuestKind.endlessRound);
      expect(q.progress, 6);
      // DAILY・ステージのラウンドは数えない
      board = board.apply(play(PlayKind.daily, round: 10)).board;
      board = board.apply(play(PlayKind.stage, round: 10)).board;
      expect(
        board.quests
            .firstWhere((q) => q.kind == QuestKind.endlessRound)
            .progress,
        6,
      );
      // 届いたら達成
      final r = board.apply(play(PlayKind.endless, round: 8));
      expect(r.result.cleared.single.kind, QuestKind.endlessRound);

      final s = single(QuestKind.endlessScore, QuestTier.easy);
      final a = s.apply(play(PlayKind.endless, score: 300000)).board;
      final b = a.apply(play(PlayKind.endless, score: 300000)).board;
      expect(
        b.quests.firstWhere((q) => q.kind == QuestKind.endlessScore).done,
        isFalse,
        reason: '合計 60 万点でも、1 回では 50 万点に届いていない',
      );
      expect(
        b.apply(play(PlayKind.daily, score: 9000000)).result.isEmpty,
        isTrue,
        reason: 'DAILY のスコアは数えない',
      );
      expect(
        b.apply(play(PlayKind.endless, score: 500000)).result.cleared.length,
        1,
      );
    });

    test('ステージ: クリアした回だけ数える (失敗・ほかのモードは数えない)', () {
      var board = single(QuestKind.stageClear, QuestTier.hard);
      board = board.apply(play(PlayKind.stage, cleared: false)).board;
      board = board.apply(play(PlayKind.endless, cleared: true)).board;
      board = board.apply(play(PlayKind.daily, cleared: true)).board;
      expect(
        board.quests.firstWhere((q) => q.kind == QuestKind.stageClear).progress,
        0,
      );
      board = board.apply(play(PlayKind.stage, cleared: true)).board;
      board = board.apply(play(PlayKind.stage, cleared: true)).board;
      expect(
        board.quests.firstWhere((q) => q.kind == QuestKind.stageClear).progress,
        2,
      );
    });

    test('進みは目標で止まる。割合は 0〜1', () {
      final q = only(
        QuestKind.perfect,
        QuestTier.easy,
        play(PlayKind.endless, s: stats(perfects: 999)),
      );
      expect(q.progress, q.target);
      expect(q.fraction, 1);
      expect(
        only(
          QuestKind.perfect,
          QuestTier.easy,
          play(PlayKind.endless, s: stats(perfects: 5)),
        ).fraction,
        0.5,
      );
    });
  });

  group('達成と報酬', () {
    QuestBoard threeSimple() => const QuestBoard(
      day: 5,
      quests: [
        Quest(kind: QuestKind.plays, tier: QuestTier.easy),
        Quest(kind: QuestKind.perfect, tier: QuestTier.normal),
        Quest(kind: QuestKind.fever, tier: QuestTier.hard),
      ],
    );

    test('達成したお題の XP は難しさで決まる。1 つ達成なら全部終えた追加はない', () {
      var board = threeSimple();
      var r = QuestResult();
      // plays 3 回 (易しい 100)
      for (var i = 0; i < 3; i++) {
        final x = board.apply(play(PlayKind.endless));
        board = x.board;
        r = x.result;
      }
      expect(r.cleared.single.kind, QuestKind.plays);
      expect(r.xp, 100);
      expect(r.allClear, isFalse);
      expect(board.doneCount, 1);
    });

    test('1 回で複数達成できる。3 つ全部を終えた回だけ +200 が付く', () {
      var board = threeSimple();
      // 3 回遊んで plays だけ達成
      for (var i = 0; i < 3; i++) {
        board = board.apply(play(PlayKind.endless)).board;
      }
      // perfect 20 と fever 4 を一度に (ふつう 150 + 少し難しい 250 + 全部の 200)
      final x = board.apply(
        play(PlayKind.endless, s: stats(perfects: 20, fevers: 4)),
      );
      expect(x.result.cleared.map((q) => q.kind), [
        QuestKind.perfect,
        QuestKind.fever,
      ]);
      expect(x.result.allClear, isTrue);
      expect(x.result.xp, 150 + 250 + 200);
      expect(x.board.allDone, isTrue);
    });

    test('一度達成したお題は二度と払わない。全部終えたあとに遊んでも追加は出ない', () {
      var board = threeSimple();
      final big = play(PlayKind.endless, s: stats(perfects: 99, fevers: 99));
      for (var i = 0; i < 3; i++) {
        board = board.apply(big).board;
      }
      expect(board.allDone, isTrue);
      final again = board.apply(big);
      expect(again.result.isEmpty, isTrue);
      expect(again.result.xp, 0);
      expect(again.result.allClear, isFalse);
    });

    test('結果が空なら XP は 0', () {
      expect(const QuestResult().xp, 0);
      expect(const QuestResult().isEmpty, isTrue);
    });
  });

  group('保存', () {
    final clock = DateTime.utc(2026, 11, 14, 12);
    final today = DailyChallenge.dayOf(clock);

    Future<(ProviderContainer, SharedPreferences)> load(
      Map<String, Object> prefs, {
      DateTime? now,
    }) async {
      SharedPreferences.setMockInitialValues(prefs);
      final sp = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(sp),
          dailyClockProvider.overrideWithValue(() => now ?? clock),
        ],
      );
      addTearDown(c.dispose);
      return (c, sp);
    }

    test('まだ何もなければ、その日のお題を作る (保存はまだしない)', () async {
      final (c, sp) = await load({});
      final b = c.read(questsProvider);
      expect(b.day, today);
      expect(b.quests.length, 3);
      expect(sp.containsKey(QuestNotifier.key), isFalse);
      expect(QuestNotifier.key, 'quests.v1');
    });

    test('遊ぶたびに保存し、読み直すと同じ進み・達成済みが戻る', () async {
      final (c, sp) = await load({});
      final n = c.read(questsProvider.notifier);
      final first = c.read(questsProvider).quests.first;
      // どの種類の目標にも届く結果を、3 回 (合計で遊ぶ回数にも届く)
      for (var i = 0; i < 3; i++) {
        n.record(
          QuestPlay(
            kind: PlayKind.endless,
            stats: stats(
              parries: 99,
              perfects: 99,
              just: 99,
              fevers: 99,
              returnKills: 99,
            ),
            round: 99,
            score: 99000000,
            cleared: true,
          ),
        );
      }
      final saved = sp.getString(QuestNotifier.key)!;
      final json = jsonDecode(saved) as Map<String, Object?>;
      expect(json['version'], 1);
      expect(json['day'], today);
      expect((json['quests']! as List).length, 3);
      final (c2, _) = await load({QuestNotifier.key: saved});
      final b = c2.read(questsProvider);
      expect(b.day, today);
      expect(b.quests.first.kind, first.kind);
      expect(b.quests.first.done, isTrue);
      expect(b.toJson(), c.read(questsProvider).toJson());
    });

    test('ほかのキーには触らない', () async {
      final (c, sp) = await load({
        'records': '{"version":1}',
        'daily.v1': '{"version":1}',
        'settings.v1': '{}',
        'history.v1': '{}',
        'progress.v1': '{"version":1,"xp":5}',
      });
      c
          .read(questsProvider.notifier)
          .record(QuestPlay(kind: PlayKind.endless, stats: stats()));
      expect(sp.getString('records'), '{"version":1}');
      expect(sp.getString('daily.v1'), '{"version":1}');
      expect(sp.getString('settings.v1'), '{}');
      expect(sp.getString('history.v1'), '{}');
      expect(sp.getString('progress.v1'), '{"version":1,"xp":5}');
      expect(sp.getKeys(), isNot(contains(QuestNotifier.brokenKey)));
    });

    test('日付が変わったら、進みを引き継がずその日の新しいお題を作り直す', () async {
      final yesterday = QuestBoard(
        day: today - 1,
        quests: [
          for (final t in QuestTier.values)
            Quest(
              kind: [
                QuestKind.plays,
                QuestKind.perfect,
                QuestKind.fever,
              ][t.index],
              tier: t,
              progress: 2,
              done: t == QuestTier.easy,
            ),
        ],
      );
      final (c, sp) = await load({
        QuestNotifier.key: jsonEncode(yesterday.toJson()),
      });
      final b = c.read(questsProvider);
      expect(b.day, today);
      expect(b.doneCount, 0);
      expect(b.quests.every((q) => q.progress == 0), isTrue);
      expect(b.toJson(), QuestBoard.generate(today).toJson());
      // 古い日のデータは壊れてはいないので、退避はしない
      expect(sp.containsKey(QuestNotifier.brokenKey), isFalse);
      // 1 回遊ぶと、その日のお題として保存される
      c
          .read(questsProvider.notifier)
          .record(QuestPlay(kind: PlayKind.endless, stats: stats()));
      expect(
        (jsonDecode(sp.getString(QuestNotifier.key)!) as Map)['day'],
        today,
      );
    });

    test('アプリを開いたまま日付が変わっても、record は新しい日のお題に数える', () async {
      var now = clock;
      SharedPreferences.setMockInitialValues({});
      final sp = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(sp),
          dailyClockProvider.overrideWithValue(() => now),
        ],
      );
      addTearDown(c.dispose);
      final n = c.read(questsProvider.notifier);
      n.record(QuestPlay(kind: PlayKind.endless, stats: stats()));
      expect(c.read(questsProvider).day, today);
      now = clock.add(const Duration(days: 1));
      n.record(QuestPlay(kind: PlayKind.endless, stats: stats()));
      expect(c.read(questsProvider).day, today + 1);
      expect(
        c.read(questsProvider).toJson(),
        isNot(QuestBoard.generate(today).toJson()),
      );
    });

    for (final (name, raw) in [
      ('JSON として読めない', 'not json'),
      ('配列', '[1,2]'),
      ('day がない', '{"version":1,"quests":[]}'),
      ('お題が 3 つない', '{"version":1,"day":5,"quests":[]}'),
      (
        '知らない種類',
        '{"version":1,"day":5,"quests":['
            '{"kind":"zzz","tier":0,"progress":0,"done":false},'
            '{"kind":"perfect","tier":1,"progress":0,"done":false},'
            '{"kind":"fever","tier":2,"progress":0,"done":false}]}',
      ),
      (
        '進みが文字列',
        '{"version":1,"day":5,"quests":['
            '{"kind":"plays","tier":0,"progress":"x","done":false},'
            '{"kind":"perfect","tier":1,"progress":0,"done":false},'
            '{"kind":"fever","tier":2,"progress":0,"done":false}]}',
      ),
      (
        'その難しさでは出さない種類',
        '{"version":1,"day":5,"quests":['
            '{"kind":"just","tier":0,"progress":0,"done":false},'
            '{"kind":"perfect","tier":1,"progress":0,"done":false},'
            '{"kind":"fever","tier":2,"progress":0,"done":false}]}',
      ),
      (
        '種類が重なる',
        '{"version":1,"day":5,"quests":['
            '{"kind":"plays","tier":0,"progress":0,"done":false},'
            '{"kind":"perfect","tier":1,"progress":0,"done":false},'
            '{"kind":"perfect","tier":2,"progress":0,"done":false}]}',
      ),
      (
        '今より新しい版',
        '{"version":2,"day":5,"quests":['
            '{"kind":"plays","tier":0,"progress":0,"done":false},'
            '{"kind":"perfect","tier":1,"progress":0,"done":false},'
            '{"kind":"fever","tier":2,"progress":0,"done":false}]}',
      ),
    ]) {
      test('壊れたデータ ($name) は、その日の新しいお題にして、元の文字列を退避する', () async {
        final (c, sp) = await load({QuestNotifier.key: raw});
        expect(
          c.read(questsProvider).toJson(),
          QuestBoard.generate(today).toJson(),
        );
        expect(sp.getString(QuestNotifier.brokenKey), raw);
      });
    }

    test('進みが目標を超えた値・小数・負でない値は丸めて読む。負の進みは壊れたデータ', () {
      final r = QuestBoard.decode(
        '{"version":1,"day":5,"quests":['
        '{"kind":"plays","tier":0,"progress":999,"done":true},'
        '{"kind":"perfect","tier":1,"progress":7.9,"done":false},'
        '{"kind":"fever","tier":2,"progress":0,"done":false}]}',
      );
      expect(r.intact, isTrue);
      expect(r.board!.quests[0].progress, 3);
      expect(r.board!.quests[1].progress, 7);
      final neg = QuestBoard.decode(
        '{"version":1,"day":5,"quests":['
        '{"kind":"plays","tier":0,"progress":-1,"done":true},'
        '{"kind":"perfect","tier":1,"progress":0,"done":false},'
        '{"kind":"fever","tier":2,"progress":0,"done":false}]}',
      );
      expect(neg.board, isNull);
    });
  });
}
