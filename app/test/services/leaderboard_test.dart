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
  Future<void> showLeaderboards({required String iOSLeaderboardID, required String androidLeaderboardID}) async {}
}

/// サインインと送信の成否を設定で決める偽の送信先。送信はすぐに終わる。
class _ScriptedPlatform implements LeaderboardPlatform {
  /// signIn が例外を投げる。
  bool signInThrows = false;

  /// signIn のあとの isSignedIn の値。
  bool signedIn = true;

  /// submitScore が例外を投げる。
  bool submitFails = false;

  /// showLeaderboards が例外を投げる。
  bool showFails = false;

  int signInCalls = 0;
  final sent = <Score>[];
  final shown = <String>[];

  @override
  Future<void> signIn() async {
    signInCalls++;
    if (signInThrows) throw Exception('sign-in failed');
  }

  @override
  Future<bool> get isSignedIn async => signedIn;

  @override
  Future<void> submitScore(Score score) async {
    if (submitFails) throw Exception('offline');
    sent.add(score);
  }

  @override
  Future<void> showLeaderboards({required String iOSLeaderboardID, required String androidLeaderboardID}) async {
    if (showFails) throw Exception('cannot show');
    shown.add(iOSLeaderboardID);
  }
}

void main() {
  late SharedPreferences prefs;
  late _FakePlatform platform;

  Future<void> setPending(Map<String, int> p) async {
    SharedPreferences.setMockInitialValues({'leaderboard.pending': jsonEncode(p)});
    prefs = await SharedPreferences.getInstance();
  }

  Map<String, int> pending() =>
      Map<String, int>.from(jsonDecode(prefs.getString('leaderboard.pending') ?? '{}') as Map);

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
  group('送信と保留', () {
    late _ScriptedPlatform sp;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      sp = _ScriptedPlatform();
    });

    test('サインインで例外が出たら、送らずに保留する', () async {
      sp.signInThrows = true;
      final lb = GamesServicesLeaderboard(prefs, sp);
      await lb.signIn();
      await lb.submit(Board.endlessScore, 120);

      expect(sp.sent, isEmpty);
      expect(pending(), {'endlessScore': 120});
    });

    test('サインインできなかった (isSignedIn が false) なら、送らずに保留する', () async {
      sp.signedIn = false;
      final lb = GamesServicesLeaderboard(prefs, sp);
      await lb.signIn();
      await lb.submit(Board.endlessRound, 9);

      expect(sp.sent, isEmpty);
      expect(pending(), {'endlessRound': 9});
    });

    test('サインインした後で送信に失敗したら、ボードごとに最高値だけを保留する', () async {
      sp.submitFails = true;
      final lb = GamesServicesLeaderboard(prefs, sp);
      await lb.signIn();

      await lb.submit(Board.endlessScore, 300);
      await lb.submit(Board.endlessScore, 100); // 低いので上書きしない
      await lb.submit(Board.endlessScore, 500);
      await lb.submit(Board.stagesTotal, 12);

      expect(sp.sent, isEmpty);
      expect(pending(), {'endlessScore': 500, 'stagesTotal': 12});
    });

    test('サインイン済みで送れたら保留しない', () async {
      final lb = GamesServicesLeaderboard(prefs, sp);
      await lb.signIn();
      await lb.submit(Board.endlessScore, 42);

      expect(sp.sent.single.value, 42);
      expect(sp.sent.single.iOSLeaderboardID, LeaderboardConfig.ios[Board.endlessScore]);
      expect(pending(), isEmpty);
    });

    test('サインインで保留を送り、送れた分を消す。今の版にないボードの保留は送らずに捨てる', () async {
      await setPending({'endlessScore': 800, 'stagesTotal': 20, 'oldBoard': 5});
      final lb = GamesServicesLeaderboard(prefs, sp);
      await lb.signIn();

      expect(sp.sent.map((s) => (s.iOSLeaderboardID, s.value)), {
        (LeaderboardConfig.ios[Board.endlessScore], 800),
        (LeaderboardConfig.ios[Board.stagesTotal], 20),
      });
      expect(pending(), isEmpty);
    });

    test('サインインに失敗しても、保留は消さずに次に回す', () async {
      await setPending({'endlessScore': 800});
      sp.signInThrows = true;
      final lb = GamesServicesLeaderboard(prefs, sp);
      await lb.signIn();
      expect(sp.sent, isEmpty);
      expect(pending(), {'endlessScore': 800});

      sp.signInThrows = false;
      await lb.signIn();
      expect(sp.sent.single.value, 800);
      expect(pending(), isEmpty);
    });

    for (final raw in ['{not json', '[1, 2]', '{"endlessScore": "high"}', '"x"']) {
      test('保留の JSON が壊れていても落ちない ($raw)', () async {
        SharedPreferences.setMockInitialValues({'leaderboard.pending': raw});
        prefs = await SharedPreferences.getInstance();
        final lb = GamesServicesLeaderboard(prefs, sp);

        await lb.signIn();
        expect(sp.sent, isEmpty);

        // 壊れた保留は空として扱い、新しい保留で上書きできる
        sp.submitFails = true;
        await lb.submit(Board.endlessRound, 3);
        expect(pending(), {'endlessRound': 3});
      });
    }

    test('未サインインで show を呼ぶとサインインを試し、失敗したら false', () async {
      sp.signInThrows = true;
      final lb = GamesServicesLeaderboard(prefs, sp);

      expect(await lb.show(Board.endlessScore), isFalse);
      expect(sp.signInCalls, 1);
      expect(sp.shown, isEmpty);
    });

    test('未サインインで show を呼び、サインインできたら開いて true', () async {
      final lb = GamesServicesLeaderboard(prefs, sp);

      expect(await lb.show(Board.endlessScore), isTrue);
      expect(sp.signInCalls, 1);
      expect(sp.shown, [LeaderboardConfig.ios[Board.endlessScore]]);

      // サインイン済みなら、もう一度は試さない
      expect(await lb.show(), isTrue);
      expect(sp.signInCalls, 1);
      expect(sp.shown.last, '');
    });

    test('ランキング画面を開けなければ false', () async {
      sp.showFails = true;
      final lb = GamesServicesLeaderboard(prefs, sp);
      await lb.signIn();
      expect(await lb.show(), isFalse);
    });
  });
}
