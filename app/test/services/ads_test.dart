import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parry_break/services/ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late DateTime now;
  InterstitialPolicy policy() => InterstitialPolicy(prefs, now: () => now);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    now = DateTime(2026, 10, 4, 12);
  });

  /// 猶予 (結果画面 3 回) を抜けた状態にする。
  InterstitialPolicy played() {
    final p = policy();
    for (var i = 0; i <= p.freeResults; i++) {
      p.recordResult();
    }
    return p;
  }

  test('結果画面を 3 回見るまでは出さず、4 回目から出せる', () {
    final p = policy();
    for (var i = 0; i < 3; i++) {
      p.recordResult();
      expect(p.due, isFalse, reason: '${i + 1} 回目');
    }
    p.recordResult();
    expect(p.due, isTrue);
  });

  test('猶予を抜けたら数えるのをやめる', () {
    final p = played();
    for (var i = 0; i < 10; i++) {
      p.recordResult();
    }
    expect(prefs.getInt('ads.results'), 4);
  });

  test('前回から 3 分あける', () {
    final p = played();
    p.recordShown();
    now = now.add(const Duration(minutes: 2, seconds: 59));
    expect(p.due, isFalse);
    now = now.add(const Duration(seconds: 1));
    expect(p.due, isTrue);
  });

  test('1 日 8 回まで。日付が変わると数え直す', () {
    final p = played();
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

  test('猶予なしの設定 (デバッグビルド) では最初の結果画面から出せる', () {
    final p = InterstitialPolicy(prefs, now: () => now, freeResults: 0);
    expect(p.due, isFalse);
    p.recordResult();
    expect(p.due, isTrue);
  });

  test('端末の時計が戻されて前回が未来になっても出せる', () {
    final p = played();
    p.recordShown();
    now = now.subtract(const Duration(hours: 1));
    expect(p.due, isTrue);
  });

  group('AdMobAds', () {
    late FakeSdk sdk;
    late List<(Duration, void Function())> timers;
    late AdMobAds ads;

    /// [fresh] が false なら、猶予を抜けた状態で始める。
    AdMobAds create({bool fresh = false}) {
      final a = AdMobAds(
        fresh ? policy() : played(),
        sdk: sdk,
        now: () => now,
        timer: (d, f) {
          timers.add((d, f));
          // 時刻が来て呼ばれたときと同じく、もう動いていないタイマーを返す
          return Timer(Duration.zero, () {})..cancel();
        },
      );
      addTearDown(a.dispose);
      return a;
    }

    Future<void> start() async {
      await ads.init();
      await pumpEventQueue();
    }

    setUp(() {
      sdk = FakeSdk();
      timers = [];
    });

    test('読み込み済みなら出し、出した後に次を読み込む', () async {
      ads = create();
      await start();
      expect(sdk.loads, 1);
      await ads.showInterstitialIfDue();
      expect(sdk.shown, 1);
      expect(sdk.loads, 2);
    });

    test('頻度の制限に当たるときは出さず、読み込んだ広告は取っておく', () async {
      ads = create();
      await start();
      await ads.showInterstitialIfDue();
      await ads.showInterstitialIfDue(); // 3 分たっていない
      expect(sdk.shown, 1);
      expect(sdk.loads, 2);
    });

    test('猶予の間は読み込まず、猶予を抜けた結果画面で読み込んで、戻るときに出せる', () async {
      ads = create(fresh: true);
      await start();
      for (var i = 0; i < 3; i++) {
        ads.onResult();
        await pumpEventQueue();
        await ads.showInterstitialIfDue();
      }
      expect(sdk.loads, 0);
      ads.onResult();
      await pumpEventQueue();
      expect(sdk.loads, 1);
      await ads.showInterstitialIfDue();
      expect(sdk.shown, 1);
    });

    test('期限が近い広告は捨てて読み込み直す', () async {
      ads = create();
      await start();
      final first = sdk.ads.single;
      now = now.add(AdMobAds.maxAge);
      await ads.showInterstitialIfDue();
      expect(first.disposed, isTrue);
      expect(sdk.shown, 0);
      expect(sdk.loads, 2);
      await pumpEventQueue();
      await ads.showInterstitialIfDue();
      expect(sdk.shown, 1);
    });

    test('読み込みに失敗したら間隔を延ばして再試行し、使い切ったら止める', () async {
      sdk.failLoads = 100;
      ads = create();
      await start();
      for (var i = 0; i < AdMobAds.retryDelays.length; i++) {
        expect(timers, hasLength(i + 1));
        expect(timers.last.$1, AdMobAds.retryDelays[i]);
        timers.last.$2();
        await pumpEventQueue();
      }
      expect(sdk.loads, AdMobAds.retryDelays.length + 1);
      expect(timers, hasLength(AdMobAds.retryDelays.length));
      // 使い切った後も、結果画面ではもう一度試す
      sdk.failLoads = 0;
      ads.onResult();
      await pumpEventQueue();
      await ads.showInterstitialIfDue();
      expect(sdk.shown, 1);
    });

    test('起動時に広告を出せなかったら、前面に戻ったときに同意から確かめ直す', () async {
      sdk
        ..consentOk = false
        ..canRequest = false;
      ads = create();
      await start();
      expect(sdk.initialized, isFalse);
      expect(sdk.loads, 0);

      sdk
        ..consentOk = true
        ..canRequest = true;
      await ads.onResume();
      expect(sdk.consentCalls, 2);
      expect(sdk.initialized, isTrue);
      await pumpEventQueue();
      expect(sdk.loads, 1);
    });

    test('起動時の処理の途中 (同意画面を閉じたときなど) に前面に戻っても、同意の処理を重ねない', () async {
      final consent = Completer<bool>();
      sdk.consentResult = consent.future;
      ads = create();
      final init = ads.init();
      await ads.onResume();
      expect(sdk.consentCalls, 1);
      consent.complete(true);
      await init;
      expect(sdk.initialized, isTrue);
    });

    test('同意の更新が済んでいれば、前面に戻ったときに同意の画面を出し直さない', () async {
      sdk.canRequest = false;
      ads = create();
      await start();
      sdk.canRequest = true;
      await ads.onResume();
      expect(sdk.consentCalls, 1);
      expect(sdk.initialized, isTrue);
    });
  });
}

class FakeSdk implements AdsSdk {
  bool consentOk = true, canRequest = true, initialized = false;
  int consentCalls = 0, loads = 0, shown = 0, failLoads = 0;
  final ads = <FakeInterstitial>[];
  Future<bool>? consentResult;

  @override
  Future<bool> gatherConsent() async {
    consentCalls++;
    return consentResult ?? consentOk;
  }

  @override
  Future<bool> privacyOptionsRequired() async => false;

  @override
  Future<void> requestTracking() async {}

  @override
  Future<bool> canRequestAds() async => canRequest;

  @override
  Future<void> initialize() async => initialized = true;

  @override
  Future<LoadedInterstitial> loadInterstitial() async {
    loads++;
    if (failLoads > 0) {
      failLoads--;
      throw Exception('no fill');
    }
    final ad = FakeInterstitial(this);
    ads.add(ad);
    return ad;
  }

  @override
  Future<void> showPrivacyOptions() async {}
}

class FakeInterstitial implements LoadedInterstitial {
  FakeInterstitial(this._sdk);
  final FakeSdk _sdk;
  bool disposed = false;

  @override
  Future<void> show({required VoidCallback onShown}) async {
    _sdk.shown++;
    onShown();
    disposed = true;
  }

  @override
  void dispose() => disposed = true;
}
