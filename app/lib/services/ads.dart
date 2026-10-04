import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// AdMob の設定。
///
/// アプリ ID は次の 2 か所に書く (広告ユニット ID とは別)。
/// - ios/Runner/Info.plist の GADApplicationIdentifier
/// - android/app/src/main/AndroidManifest.xml の com.google.android.gms.ads.APPLICATION_ID
///
/// Android はまだ AdMob に登録していないので、アプリ ID も広告ユニット ID も Google のテスト用のまま。
abstract final class AdsConfig {
  static const enabled = true;

  static const iosInterstitial = 'ca-app-pub-4435922675604695/2281923603';
  static const androidInterstitial = 'ca-app-pub-3940256099942544/1033173712';

  // Google のテスト用の広告ユニット。デバッグビルドではこちらを使う
  // (開発中に本番の広告を表示・クリックすると、AdMob の規約違反になるため)。
  static const _testIosInterstitial = 'ca-app-pub-3940256099942544/4411468910';
  static const _testAndroidInterstitial = 'ca-app-pub-3940256099942544/1033173712';

  static String get interstitial {
    final ios = defaultTargetPlatform == TargetPlatform.iOS;
    if (kDebugMode) return ios ? _testIosInterstitial : _testAndroidInterstitial;
    return ios ? iosInterstitial : androidInterstitial;
  }
}

/// インタースティシャルを出してよいかの判定 (頻度の制限)。
///
/// - 最初の起動から [grace] の間は出さない (初日のプレイヤーには広告を見せない。同意の画面は最初の起動で出す)
/// - 前回から [minGap] 以上あける
/// - 1 日 [dailyCap] 回まで
class InterstitialPolicy {
  InterstitialPolicy(this._prefs, {DateTime Function()? now, this.grace = const Duration(hours: 24)})
      : _now = now ?? DateTime.now;

  final SharedPreferences _prefs;
  final DateTime Function() _now;
  final Duration grace;
  static const minGap = Duration(minutes: 3);
  static const dailyCap = 8;

  static const _firstLaunchKey = 'ads.firstLaunch';
  static const _lastShownKey = 'ads.lastShown';
  static const _dayKey = 'ads.day';
  static const _dayCountKey = 'ads.dayCount';

  /// 起動時に呼ぶ。最初の起動の時刻を覚える。
  void markLaunch() {
    if (_prefs.getInt(_firstLaunchKey) == null) {
      _prefs.setInt(_firstLaunchKey, _now().millisecondsSinceEpoch);
    }
  }

  bool get pastGrace {
    final first = _prefs.getInt(_firstLaunchKey);
    if (first == null) return false;
    return _now().difference(DateTime.fromMillisecondsSinceEpoch(first)) >= grace;
  }

  String get _today {
    final d = _now();
    return '${d.year}-${d.month}-${d.day}';
  }

  int get _countToday => _prefs.getString(_dayKey) == _today ? _prefs.getInt(_dayCountKey) ?? 0 : 0;

  bool get due {
    if (!pastGrace || _countToday >= dailyCap) return false;
    final last = _prefs.getInt(_lastShownKey);
    return last == null || _now().difference(DateTime.fromMillisecondsSinceEpoch(last)) >= minGap;
  }

  void recordShown() {
    final count = _countToday + 1;
    _prefs
      ..setInt(_lastShownKey, _now().millisecondsSinceEpoch)
      ..setString(_dayKey, _today)
      ..setInt(_dayCountKey, count);
  }
}

abstract class AdsService {
  /// 起動後に呼ぶ。同意を集め (EU の同意画面、iOS のトラッキング許可)、出せる時期なら広告を読み込んでおく。
  Future<void> init();

  /// 結果画面からタイトルなどへ戻るときに呼ぶ。出してよければ出し、閉じられるまで待つ。
  Future<void> showInterstitialIfDue();

  /// 設定画面に「広告のプライバシー設定」を出す必要があるか (EU など)。
  bool get privacyOptionsRequired;

  Future<void> showPrivacyOptions();
}

class DisabledAds implements AdsService {
  @override
  Future<void> init() async {}
  @override
  Future<void> showInterstitialIfDue() async {}
  @override
  bool get privacyOptionsRequired => false;
  @override
  Future<void> showPrivacyOptions() async {}
}

class AdMobAds implements AdsService {
  AdMobAds(this._policy);
  final InterstitialPolicy _policy;
  bool _ready = false, _loading = false;
  InterstitialAd? _ad;

  @override
  bool privacyOptionsRequired = false;

  @override
  Future<void> init() async {
    _policy.markLaunch();
    // 同意の画面は猶予の間も最初の起動で出す。審査ではトラッキング許可のダイアログが出ることを確かめられるため
    await _gatherConsent();
    if (!await ConsentInformation.instance.canRequestAds()) return;
    await MobileAds.instance.initialize();
    _ready = true;
    _load();
  }

  /// 同意が必要な地域なら同意画面を出す。iOS のトラッキング許可は、AdMob の
  /// 「プライバシーとメッセージ」で IDFA の説明メッセージを作っておくと、この流れで出る。
  Future<void> _gatherConsent() {
    final done = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(ConsentRequestParameters(), () async {
      await ConsentForm.loadAndShowConsentFormIfRequired((e) {
        if (e != null) debugPrint('consent form failed: ${e.message}');
      });
      privacyOptionsRequired = await ConsentInformation.instance.getPrivacyOptionsRequirementStatus() ==
          PrivacyOptionsRequirementStatus.required;
      done.complete();
    }, (e) {
      // 失敗しても、前回までの同意で広告を出せることがある (canRequestAds で確かめる)
      debugPrint('consent update failed: ${e.message}');
      done.complete();
    });
    return done.future;
  }

  void _load() {
    if (!_ready || _loading || _ad != null || !_policy.pastGrace) return;
    _loading = true;
    InterstitialAd.load(
      adUnitId: AdsConfig.interstitial,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _loading = false;
          _ad = ad;
        },
        onAdFailedToLoad: (e) {
          // 次に出す機会に読み込み直す
          _loading = false;
          debugPrint('interstitial load failed: ${e.message}');
        },
      ),
    );
  }

  @override
  Future<void> showInterstitialIfDue() async {
    final ad = _ad;
    if (ad == null || !_policy.due) {
      _load();
      return;
    }
    _ad = null;
    final closed = Completer<void>();
    void close(Ad a) {
      a.dispose();
      if (!closed.isCompleted) closed.complete();
    }

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (_) => _policy.recordShown(),
      onAdDismissedFullScreenContent: close,
      onAdFailedToShowFullScreenContent: (a, e) {
        debugPrint('interstitial show failed: ${e.message}');
        close(a);
      },
    );
    try {
      await ad.show();
      await closed.future;
    } on Object catch (e) {
      debugPrint('interstitial show failed: $e');
      close(ad);
    }
    // 広告を閉じるとシステムバーが戻ることがあるので、全画面に戻す
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _load();
  }

  @override
  Future<void> showPrivacyOptions() => ConsentForm.showPrivacyOptionsForm((e) {
        if (e != null) debugPrint('privacy options failed: ${e.message}');
      });
}

/// 起動時に main で [createAdsService] の結果に差し替える。テストでは何もしない実装のまま。
final adsProvider = Provider<AdsService>((ref) => DisabledAds());

AdsService createAdsService(SharedPreferences prefs) {
  final mobile = defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android;
  if (!AdsConfig.enabled || kIsWeb || !mobile) return DisabledAds();
  // デバッグビルドでは初日の猶予を外し、すぐに広告を確かめられるようにする
  return AdMobAds(InterstitialPolicy(prefs, grace: kDebugMode ? Duration.zero : const Duration(hours: 24)));
}
