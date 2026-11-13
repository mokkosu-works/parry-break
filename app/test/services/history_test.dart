import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parry_break/core/core.dart';
import 'package:parry_break/services/history.dart';
import 'package:parry_break/services/records.dart';
import 'package:parry_break/services/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  var now = DateTime(2026, 11, 8, 14, 5);

  Future<(ProviderContainer, SharedPreferences)> load([
    Map<String, Object> prefs = const {},
  ]) async {
    SharedPreferences.setMockInitialValues(prefs);
    final sp = await SharedPreferences.getInstance();
    final c = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(sp),
        historyClockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(c.dispose);
    return (c, sp);
  }

  test('一度も遊んでいなければ履歴は空', () async {
    final (c, _) = await load();
    expect(c.read(historyProvider).entries, isEmpty);
  });

  test('エンドレスとステージの結果を新しい順に残す', () async {
    final (c, _) = await load();
    final n = c.read(historyProvider.notifier);
    n.addEndless(score: 12000, round: 7);
    now = now.add(const Duration(minutes: 3));
    n.addStage('1-3', score: 800, cleared: false, difficulty: Difficulty.hard);
    final e = c.read(historyProvider).entries;
    expect(e, hasLength(2));
    expect(e[0].stageId, '1-3');
    expect(e[0].difficulty, Difficulty.hard);
    expect(e[0].cleared, isFalse);
    expect(e[0].score, 800);
    expect(e[0].at, now);
    expect(e[1].endless, isTrue);
    expect(e[1].round, 7);
    expect(e[1].score, 12000);
  });

  test('51 件目を足すと一番古いものが消えて 50 件のまま', () async {
    final (c, sp) = await load();
    final n = c.read(historyProvider.notifier);
    for (var i = 1; i <= PlayHistory.maxEntries; i++) {
      n.addEndless(score: i, round: 1);
    }
    expect(c.read(historyProvider).entries, hasLength(50));
    expect(c.read(historyProvider).entries.last.score, 1);
    n.addEndless(score: 51, round: 1);
    final e = c.read(historyProvider).entries;
    expect(e, hasLength(50));
    expect(e.first.score, 51);
    expect(e.last.score, 2);
    final saved = PlayHistory.decode(sp.getString(PlayHistoryNotifier.key)!);
    expect(saved.history.entries, hasLength(50));
  });

  test('保存した履歴は、読み込み直しても同じ内容で残る', () async {
    final (c, sp) = await load();
    c.read(historyProvider.notifier)
      ..addEndless(score: 4500, round: 3)
      ..addStage(
        '2-1',
        score: 9900,
        cleared: true,
        difficulty: Difficulty.easy,
      );
    final raw = sp.getString(PlayHistoryNotifier.key)!;

    final (c2, sp2) = await load({PlayHistoryNotifier.key: raw});
    final e = c2.read(historyProvider).entries;
    expect(e, hasLength(2));
    expect(e[0].stageId, '2-1');
    expect(e[0].difficulty, Difficulty.easy);
    expect(e[0].cleared, isTrue);
    expect(e[0].score, 9900);
    expect(e[0].at, now);
    expect(e[1].endless, isTrue);
    expect(e[1].round, 3);
    expect(sp2.getString(PlayHistoryNotifier.brokenKey), isNull);
  });

  test('履歴を足す前の保存データ: 最高記録・進み具合・難易度ごとの星はそのまま読め、上書きもされない', () async {
    // 履歴を足す前 (version 1) の records。NORMAL はステージ ID、ほかの難易度は @easy / @hard が付く
    const old =
        '{"version":1,'
        '"endless":{"bestScore":123456,"bestRound":9,"bestCollapse":4,"bestBlast":2,"bestRicochet":5},'
        '"stages":{"1-1":{"cleared":true,"bestScore":5000,"stars":[true,false,true]},'
        '"1-1@hard":{"cleared":true,"bestScore":7000,"stars":[true,true,false]},'
        '"1-2@easy":{"cleared":false,"bestScore":0,"stars":[false,true]}}}';
    final (c, sp) = await load({'records': old});
    expect(c.read(historyProvider).entries, isEmpty);

    // 結果画面と同じ順で、記録と履歴に残す
    c.read(historyProvider.notifier).addEndless(score: 100, round: 1);
    expect(sp.getString('records'), old, reason: '履歴は別のキーに保存し、records には触らない');
    c
        .read(recordsProvider.notifier)
        .submitEndless(score: 100, round: 1, stats: RunStats());
    c.read(historyProvider.notifier).addStage('1-2', score: 10, cleared: false);

    final r = Records.fromJson(
      jsonDecode(sp.getString('records')!) as Map<String, Object?>,
    );
    expect(r.endless.bestScore, 123456);
    expect(r.endless.bestRound, 9);
    expect(r.endless.bestRicochet, 5);
    expect(r.stage('1-1').cleared, isTrue);
    expect(r.stage('1-1').bestScore, 5000);
    expect(r.stage('1-1').stars, [true, false, true]);
    expect(r.stage('1-1', Difficulty.hard).bestScore, 7000);
    expect(r.stage('1-1', Difficulty.hard).stars, [true, true, false]);
    expect(r.stage('1-2', Difficulty.easy).stars, [false, true]);
    expect(sp.getString('records.broken'), isNull);
    expect(c.read(historyProvider).entries, hasLength(2));
  });

  group('壊れた履歴', () {
    test('読めない 1 件だけを捨てて残りは読み、元のデータを退避する', () async {
      final raw = jsonEncode({
        'version': 1,
        'entries': [
          {'at': 1000, 'difficulty': 'normal', 'score': 500, 'round': 4},
          'x',
          {'at': 'yesterday', 'score': 1},
          {'at': 2000, 'stage': '1-1', 'difficulty': 'nightmare', 'score': 1},
          {
            'at': 3000,
            'stage': '1-2',
            'difficulty': 'hard',
            'score': 900,
            'cleared': true,
          },
        ],
      });
      final (c, sp) = await load({PlayHistoryNotifier.key: raw});
      final e = c.read(historyProvider).entries;
      expect(e, hasLength(2));
      expect(e[0].round, 4);
      expect(e[1].stageId, '1-2');
      expect(e[1].difficulty, Difficulty.hard);
      expect(sp.getString(PlayHistoryNotifier.brokenKey), raw);
    });

    test('JSON として読めなければ空にして、元のデータを退避する', () async {
      final (c, sp) = await load({PlayHistoryNotifier.key: '{oops'});
      expect(c.read(historyProvider).entries, isEmpty);
      expect(sp.getString(PlayHistoryNotifier.brokenKey), '{oops');
    });

    test('今より新しい版のデータは、読める項目を読んで元のデータを退避する', () async {
      final raw = jsonEncode({
        'version': 2,
        'entries': [
          {'at': 1000, 'score': 5, 'round': 1, 'extra': true},
        ],
      });
      final (c, sp) = await load({PlayHistoryNotifier.key: raw});
      expect(c.read(historyProvider).entries.single.score, 5);
      expect(sp.getString(PlayHistoryNotifier.brokenKey), raw);
    });
  });

  test('デイリーは DAILY として残り、古い版のデータ (daily がない) はエンドレスとして読む (#255)', () async {
    final (c, sp) = await load();
    c.read(historyProvider.notifier).addDaily(score: 4200, round: 46);
    final e = c.read(historyProvider).entries.single;
    expect(e.daily, isTrue);
    expect(e.endless, isTrue);
    expect(e.round, 46);
    final saved = jsonDecode(sp.getString(PlayHistoryNotifier.key)!) as Map;
    expect((saved['entries'] as List).single, containsPair('daily', true));

    final old = PlayEntry.fromJson({
      'at': 0,
      'difficulty': 'normal',
      'score': 10,
      'round': 3,
    })!;
    expect(old.daily, isFalse);
    expect(old.toJson().containsKey('daily'), isFalse);
  });
}
