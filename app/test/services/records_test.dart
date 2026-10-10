import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parry_break/core/core.dart';
import 'package:parry_break/services/records.dart';
import 'package:parry_break/services/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('StageRecord', () {
    test('hasStar は記録より後ろの条件を未達成として扱う', () {
      const r = StageRecord(stars: [true, false]);
      expect(r.hasStar(0), isTrue);
      expect(r.hasStar(1), isFalse);
      expect(r.hasStar(2), isFalse);
      expect(r.starCount, 1);
    });

    test('JSON を往復しても同じ値になる', () {
      final r = StageRecord.fromJson(const StageRecord(cleared: true, bestScore: 1200, stars: [true, false]).toJson());
      expect(r.cleared, isTrue);
      expect(r.bestScore, 1200);
      expect(r.stars, [true, false]);
    });
  });

  test('ステージの星は一度達成したら残る', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
    addTearDown(container.dispose);
    final notifier = container.read(recordsProvider.notifier);

    StageResult result({required bool cleared, int score = 0}) =>
        StageResult(cleared: cleared, score: score, stats: RunStats());
    notifier.submitStage('1-1', result(cleared: true, score: 500), [true, false, true]);
    notifier.submitStage('1-1', result(cleared: false), [false, true, false]);

    final rec = container.read(recordsProvider).stage('1-1');
    expect(rec.stars, [true, true, true]);
    expect(rec.cleared, isTrue);
    expect(rec.bestScore, 500);
  });
}
