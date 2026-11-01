import 'package:flutter_test/flutter_test.dart';
import 'package:parry_break/services/review.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences prefs;
  var now = DateTime(2026, 11, 1);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    now = DateTime(2026, 11, 1);
  });

  ReviewPolicy policy() => ReviewPolicy(prefs, now: () => now);

  test('クリアした面が少ないうちは聞かない', () {
    expect(policy().due(clearedStages: ReviewPolicy.minClears - 1), isFalse);
    expect(policy().due(clearedStages: ReviewPolicy.minClears), isTrue);
  });

  test('一度聞いたら、間隔があくまで聞かない', () {
    final p = policy()..recordAsked();
    expect(p.due(clearedStages: 20), isFalse);
    now = now.add(ReviewPolicy.minGap - const Duration(days: 1));
    expect(p.due(clearedStages: 20), isFalse);
    now = now.add(const Duration(days: 1));
    expect(p.due(clearedStages: 20), isTrue);
  });

  test('通算の回数の上限で聞かなくなる', () {
    final p = policy();
    for (var i = 0; i < ReviewPolicy.maxAsks; i++) {
      p.recordAsked();
      now = now.add(ReviewPolicy.minGap);
    }
    expect(p.due(clearedStages: 20), isFalse);
  });

  test('端末の時計が戻されても、聞けなくならない', () {
    final p = policy()..recordAsked();
    now = now.subtract(const Duration(days: 30));
    expect(p.due(clearedStages: 20), isTrue);
  });
}
