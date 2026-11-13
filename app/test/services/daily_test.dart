import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parry_break/services/daily.dart';
import 'package:parry_break/services/history.dart';
import 'package:parry_break/services/records.dart';
import 'package:parry_break/services/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Issue #255: デイリーチャレンジの記録 (1 日 1 回・連続日数・保存データ)。
void main() {
  Future<(ProviderContainer, SharedPreferences)> load([
    Map<String, Object> prefs = const {},
  ]) async {
    SharedPreferences.setMockInitialValues(prefs);
    final sp = await SharedPreferences.getInstance();
    final c = ProviderContainer(
      overrides: [sharedPrefsProvider.overrideWithValue(sp)],
    );
    addTearDown(c.dispose);
    return (c, sp);
  }

  test('その日の最初の 1 回だけを数え、2 回目以降は数えない', () async {
    final (c, _) = await load();
    final n = c.read(dailyProvider.notifier);
    expect(n.submit(100, 5000), (counted: true, newBest: true));
    expect(n.submit(100, 9000), (counted: false, newBest: false));
    final r = c.read(dailyProvider);
    expect(r.lastScore, 5000);
    expect(r.bestScore, 5000);
    expect(r.streak, 1);
    expect(r.playedOn(100), isTrue);
    expect(r.playedOn(101), isFalse);
    // 次の日の 1 回目は数える。自己ベストを下回れば newBest は false
    expect(n.submit(101, 3000), (counted: true, newBest: false));
    expect(c.read(dailyProvider).bestScore, 5000);
    expect(c.read(dailyProvider).lastScore, 3000);
  });

  test('連続日数: 続けば 1 ずつ増え、1 日空くと 1 に戻る', () {
    var r = const DailyRecord();
    expect(r.streakOn(10), 0);
    for (var d = 10; d <= 12; d++) {
      r = r.submit(d, 100).record;
      expect(r.streak, d - 9);
    }
    expect(r.streakOn(12), 3); // 今日遊んだ
    expect(r.streakOn(13), 3); // 昨日まで続いている (今日はまだ)
    expect(r.streakOn(14), 0); // 1 日空いた
    r = r.submit(14, 100).record;
    expect(r.streak, 1);
  });

  test('端末の時計を巻き戻しても、数え直して連続日数が増えすぎない', () {
    var r = const DailyRecord();
    r = r.submit(20, 100).record;
    r = r.submit(21, 100).record;
    expect(r.streak, 2);
    // 20 日に戻した: 遊んだ日として扱い、数えない
    final back = r.submit(20, 999);
    expect(back.counted, isFalse);
    expect(back.record.streak, 2);
    expect(r.playedOn(20), isTrue);
    expect(r.submit(19, 999).counted, isFalse);
    // 本当の次の日には、1 つだけ増える
    expect(r.submit(22, 100).record.streak, 3);
  });

  test('新しいキーに保存し、記録・履歴・設定の保存データを変えない', () async {
    final records = jsonEncode(
      const Records(endless: EndlessRecord(bestScore: 77)).toJson(),
    );
    final history = jsonEncode(const PlayHistory().toJson());
    final settings = jsonEncode(const Settings(language: 'ja').toJson());
    final (c, sp) = await load({
      'records': records,
      PlayHistoryNotifier.key: history,
      'settings.v1': settings,
    });
    c.read(dailyProvider.notifier).submit(100, 1234);
    expect(DailyNotifier.key, 'daily.v1');
    expect(
      jsonDecode(sp.getString(DailyNotifier.key)!),
      containsPair('bestScore', 1234),
    );
    expect(sp.getString('records'), records);
    expect(sp.getString(PlayHistoryNotifier.key), history);
    expect(sp.getString('settings.v1'), settings);
  });

  test('保存したデイリーの記録を読み直せる。古いデータ (デイリーのキーがない) を読んでも消えない', () async {
    final records = jsonEncode(
      const Records(endless: EndlessRecord(bestScore: 77)).toJson(),
    );
    final (c, sp) = await load({'records': records});
    expect(c.read(dailyProvider).lastDay, -1);
    expect(c.read(recordsProvider).endless.bestScore, 77);
    expect(sp.getString('records'), records);
    expect(sp.getString(DailyNotifier.brokenKey), isNull);

    c.read(dailyProvider.notifier).submit(50, 300);
    final (c2, _) = await load({
      DailyNotifier.key: sp.getString(DailyNotifier.key)!,
    });
    final r = c2.read(dailyProvider);
    expect((r.lastDay, r.lastScore, r.bestScore, r.streak), (50, 300, 300, 1));
  });

  test('読めないデイリーの記録は、元の文字列を退避してから初期値で読む', () async {
    const raw = '{"version":1,"bestScore":"x","streak":4}';
    final (c, sp) = await load({DailyNotifier.key: raw});
    final r = c.read(dailyProvider);
    expect(r.bestScore, 0);
    expect(r.streak, 4);
    expect(sp.getString(DailyNotifier.brokenKey), raw);
  });
}
