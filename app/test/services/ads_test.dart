import 'package:flutter_test/flutter_test.dart';
import 'package:parry_break/services/ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences prefs;
  late DateTime now;
  InterstitialPolicy policy() => InterstitialPolicy(prefs, now: () => now);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    now = DateTime(2026, 10, 4, 12);
  });

  test('最初の起動から 24 時間は出さない', () {
    final p = policy();
    expect(p.due, isFalse); // 起動を記録する前
    p.markLaunch();
    now = now.add(const Duration(hours: 23, minutes: 59));
    expect(p.due, isFalse);
    now = now.add(const Duration(minutes: 1));
    expect(p.due, isTrue);
  });

  test('2 回目以降の起動で最初の起動の時刻を上書きしない', () {
    policy().markLaunch();
    now = now.add(const Duration(hours: 25));
    policy().markLaunch();
    expect(policy().pastGrace, isTrue);
  });

  test('前回から 3 分あける', () {
    final p = policy()..markLaunch();
    now = now.add(const Duration(days: 1));
    p.recordShown();
    now = now.add(const Duration(minutes: 2, seconds: 59));
    expect(p.due, isFalse);
    now = now.add(const Duration(seconds: 1));
    expect(p.due, isTrue);
  });

  test('1 日 8 回まで。日付が変わると数え直す', () {
    final p = policy()..markLaunch();
    now = DateTime(2026, 10, 5, 13);
    for (var i = 0; i < InterstitialPolicy.dailyCap; i++) {
      expect(p.due, isTrue, reason: '$i 回目');
      p.recordShown();
      now = now.add(InterstitialPolicy.minGap);
    }
    expect(p.due, isFalse);
    now = DateTime(2026, 10, 6, 0, 1);
    expect(p.due, isTrue);
  });

  test('猶予なしの設定 (デバッグビルド) では初回の起動から出せる', () {
    final p = InterstitialPolicy(prefs, now: () => now, grace: Duration.zero)..markLaunch();
    expect(p.due, isTrue);
  });
}
