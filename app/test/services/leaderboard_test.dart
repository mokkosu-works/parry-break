import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:games_services/games_services.dart';
import 'package:parry_break/services/leaderboard.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 送信の結果をテストから決められる偽の送信先。
class _FakePlatform implements LeaderboardPlatform {
  int signInCalls = 0;
  final sent = <Score>[];

  /// submitScore の呼び出しごとに 1 つ作る。テストが complete / completeError する。
  final submits = <Completer<void>>[];

  @override
  Future<void> signIn() async => signInCalls++;

  @override
  Future<bool> get isSignedIn async => true;

  @override
  Future<void> submitScore(Score score) {
    sent.add(score);
    final c = Completer<void>();
    submits.add(c);
    return c.future;
  }

  @override
  Future<void> showLeaderboards({
    required String iOSLeaderboardID,
    required String androidLeaderboardID,
  }) async {}
}

void main() {
  late SharedPreferences prefs;
  late _FakePlatform platform;

  Future<void> setPending(Map<String, int> p) async {
    SharedPreferences.setMockInitialValues({
      'leaderboard.pending': jsonEncode(p),
    });
    prefs = await SharedPreferences.getInstance();
  }

  Map<String, int> pending() => Map<String, int>.from(
    jsonDecode(prefs.getString('leaderboard.pending') ?? '{}') as Map,
  );

  /// 待っている非同期の処理を進める。
  Future<void> flush() => Future<void>.delayed(Duration.zero);

  setUp(() {
    platform = _FakePlatform();
  });

  test('保留の送信中に submit が失敗しても、そのスコアが保留に残る', () async {
    await setPending({'endlessScore': 100});
    final lb = GamesServicesLeaderboard(prefs, platform);

    final signingIn = lb.signIn();
    await flush();
    expect(platform.submits, hasLength(1)); // 保留の endlessScore=100 を送っている

    // 保留を送っている間にプレイが終わり、送信が失敗する
    final submitting = lb.submit(Board.endlessRound, 7);
    await flush();
    platform.submits[1].completeError(Exception('offline'));
    await submitting;
    expect(pending()['endlessRound'], 7);

    // 保留の送信が終わって書き戻しても、途中で書き足した分は消えない
    platform.submits[0].complete();
    await signingIn;
    expect(pending(), {'endlessRound': 7});
  });

  test('保留の送信中に同じボードへ高いスコアが保留されたら、それは消さない', () async {
    await setPending({'endlessScore': 100});
    final lb = GamesServicesLeaderboard(prefs, platform);

    final signingIn = lb.signIn();
    await flush();
    final submitting = lb.submit(Board.endlessScore, 250);
    await flush();
    platform.submits[1].completeError(Exception('offline'));
    await submitting;

    platform.submits[0].complete();
    await signingIn;
    expect(pending(), {'endlessScore': 250});
  });

  test('送れた保留は消え、送れなかった保留は残る', () async {
    await setPending({'endlessScore': 100, 'endlessRound': 5, 'oldBoard': 1});
    final lb = GamesServicesLeaderboard(prefs, platform);

    final signingIn = lb.signIn();
    await flush();
    platform.submits[0].complete();
    await flush();
    platform.submits[1].completeError(Exception('offline'));
    await signingIn;
    expect(pending(), {'endlessRound': 5});
  });

  test('signIn を同時に 2 回呼んでも、送信と書き戻しは 1 回ずつ', () async {
    await setPending({'endlessScore': 100});
    final lb = GamesServicesLeaderboard(prefs, platform);

    final a = lb.signIn();
    final b = lb.signIn();
    await flush();
    expect(platform.submits, hasLength(1));
    platform.submits[0].complete();
    await Future.wait([a, b]);

    expect(platform.signInCalls, 1);
    expect(platform.sent, hasLength(1));
    expect(pending(), isEmpty);
  });
}
