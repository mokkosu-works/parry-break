import 'dart:async';

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// AdMob の設定。
///
/// アプリ ID は次の 2 か所に書く (広告ユニット ID とは別)。
/// - ios/Runner/Info.plist の GADApplicationIdentifier
/// - android/app/src/main/AndroidManifest.xml の com.google.android.gms.ads.APPLICATION_ID
abstract final class AdsConfig {
  static const enabled = true;

  static const iosInterstitial = 'ca-app-pub-4435922675604695/2281923603';
  static const androidInterstitial = 'ca-app-pub-4435922675604695/7946499628';

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
    if (last == null) return true;
    final gap = _now().difference(DateTime.fromMillisecondsSinceEpoch(last));
    // 端末の時計が戻されて前回が未来になったときは、時計が追いつくまで出せなくならないよう、出してよいとする
    return gap.isNegative || gap >= minGap;
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

  /// 結果画面が出たときに呼ぶ。戻るときに出せるよう、広告を読み込んでおく。
  void preload();

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
  void preload() {}
  @override
  Future<void> showInterstitialIfDue() async {}
  @override
  bool get privacyOptionsRequired => false;
  @override
  Future<void> showPrivacyOptions() async {}
}

/// 読み込み済みのインタースティシャル。
abstract class LoadedInterstitial {
  /// 出して、閉じられる (または出せずに終わる) まで待つ。終わったら破棄する。
  /// 画面に出たときに [onShown] を呼ぶ。
  Future<void> show({required VoidCallback onShown});

  void dispose();
}

/// 広告の SDK (UMP・ATT・AdMob) の呼び出し。テストでは偽物に差し替える。
abstract class AdsSdk {
  /// 同意の情報を更新し、同意が必要な地域 (EU など) なら同意画面を出す。更新できたら true。
  Future<bool> gatherConsent();

  Future<bool> privacyOptionsRequired();

  /// iOS のトラッキング許可のダイアログを出す (まだ聞いていなければ)。
  Future<void> requestTracking();

  Future<bool> canRequestAds();

  Future<void> initialize();

  /// 読み込めなければ例外を投げる。
  Future<LoadedInterstitial> loadInterstitial();

  Future<void> showPrivacyOptions();
}

class AdMobAds implements AdsService {
  AdMobAds(this._policy, {AdsSdk? sdk, DateTime Function()? now, Timer Function(Duration, void Function())? timer})
    : _sdk = sdk ?? GoogleAdsSdk(),
      _now = now ?? DateTime.now,
      _timer = timer ?? Timer.new;

  final InterstitialPolicy _policy;
  final AdsSdk _sdk;
  final DateTime Function() _now;
  final Timer Function(Duration, void Function()) _timer;

  /// 読み込んだ広告はおよそ 1 時間で期限が切れて出せなくなるので、少し手前で読み込み直す。
  static const maxAge = Duration(minutes: 50);

  /// 読み込みに失敗したときの再試行の間隔。使い切ったら、次に [preload] が呼ばれるまで試さない。
  static const retryDelays = [Duration(seconds: 30), Duration(minutes: 1), Duration(minutes: 2), Duration(minutes: 4)];

  bool _initDone = false, _consentUpdated = false, _starting = false, _ready = false, _loading = false;
  LoadedInterstitial? _ad;
  DateTime? _loadedAt;
  int _failures = 0;
  Timer? _retry;
  AppLifecycleListener? _lifecycle;

  @override
  bool privacyOptionsRequired = false;

  @override
  Future<void> init() async {
    _policy.markLaunch();
    _lifecycle ??= AppLifecycleListener(onResume: () => unawaited(onResume()));
    // 同意の画面は猶予の間も最初の起動で出す。審査ではトラッキング許可のダイアログが出ることを確かめられるため
    await _gatherConsent();
    // ATT は SDK を初期化する (IDFA を読む) 前に聞く
    await _sdk.requestTracking();
    await _start();
    _initDone = true;
  }

  /// アプリが前面に戻ったとき。起動時に同意の更新や初期化でつまずいていたら、やり直す。
  @visibleForTesting
  Future<void> onResume() async {
    if (_ready) {
      preload();
      return;
    }
    // 同意画面や ATT のダイアログを閉じたときにも呼ばれるので、起動時の処理が終わるまでは何もしない
    if (!_initDone || _starting) return;
    if (!_consentUpdated) await _gatherConsent();
    await _start();
  }

  Future<void> _gatherConsent() async {
    // 失敗しても、前回までの同意で広告を出せることがある (canRequestAds で確かめる)
    _consentUpdated = await _sdk.gatherConsent();
    if (_consentUpdated) privacyOptionsRequired = await _sdk.privacyOptionsRequired();
  }

  Future<void> _start() async {
    if (_ready || _starting) return;
    _starting = true;
    try {
      if (!await _sdk.canRequestAds()) return;
      await _sdk.initialize();
      _ready = true;
    } on Object catch (e) {
      debugPrint('ads initialize failed: $e');
    } finally {
      _starting = false;
    }
    preload();
  }

  bool get _expired => _loadedAt != null && _now().difference(_loadedAt!) >= maxAge;

  void _discard() {
    _ad?.dispose();
    _ad = null;
    _loadedAt = null;
  }

  @override
  void preload() {
    if (!_ready || _loading || !_policy.pastGrace) return;
    if (_ad != null) {
      if (!_expired) return;
      _discard();
    }
    // 再試行を待っている間は、その時刻まで待つ
    if (_retry?.isActive ?? false) return;
    unawaited(_load());
  }

  Future<void> _load() async {
    _loading = true;
    try {
      _ad = await _sdk.loadInterstitial();
      _loadedAt = _now();
      _failures = 0;
    } on Object catch (e) {
      debugPrint('interstitial load failed: $e');
      if (_failures < retryDelays.length) {
        _retry = _timer(retryDelays[_failures], preload);
      }
      _failures++;
    } finally {
      _loading = false;
    }
  }

  @override
  Future<void> showInterstitialIfDue() async {
    if (_expired) _discard();
    final ad = _ad;
    if (ad == null || !_policy.due) {
      preload();
      return;
    }
    _ad = null;
    _loadedAt = null;
    await ad.show(onShown: _policy.recordShown);
    preload();
  }

  @override
  Future<void> showPrivacyOptions() => _sdk.showPrivacyOptions();

  @visibleForTesting
  void dispose() {
    _lifecycle?.dispose();
    _retry?.cancel();
    _discard();
  }
}

class GoogleAdsSdk implements AdsSdk {
  @override
  Future<bool> gatherConsent() {
    final done = Completer<bool>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () async {
        await ConsentForm.loadAndShowConsentFormIfRequired((e) {
          if (e != null) debugPrint('consent form failed: ${e.message}');
        });
        done.complete(true);
      },
      (e) {
        debugPrint('consent update failed: ${e.message}');
        done.complete(false);
      },
    );
    return done.future;
  }

  @override
  Future<bool> privacyOptionsRequired() async =>
      await ConsentInformation.instance.getPrivacyOptionsRequirementStatus() ==
      PrivacyOptionsRequirementStatus.required;

  /// AdMob の IDFA の説明メッセージ (UMP) 任せにすると、メッセージの設定や地域によっては
  /// ダイアログが出ず、審査で指摘される (Guideline 2.1)。UMP がすでに聞いていれば、ここでは何も出ない。
  @override
  Future<void> requestTracking() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    try {
      if (await AppTrackingTransparency.trackingAuthorizationStatus != TrackingStatus.notDetermined) return;
      // アプリがアクティブでないとダイアログが出ずに終わるので、前面に出るのを待つ。
      // 同意画面を閉じた直後もしばらくアクティブでないことがあるので、少し間をあける
      await _untilResumed();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await AppTrackingTransparency.requestTrackingAuthorization();
    } on PlatformException catch (e) {
      debugPrint('tracking authorization failed: ${e.message}');
    }
  }

  Future<void> _untilResumed() {
    final binding = WidgetsBinding.instance;
    if (binding.lifecycleState == AppLifecycleState.resumed) return Future.value();
    final done = Completer<void>();
    late final AppLifecycleListener listener;
    listener = AppLifecycleListener(
      onResume: () {
        listener.dispose();
        done.complete();
      },
    );
    return done.future;
  }

  @override
  Future<bool> canRequestAds() => ConsentInformation.instance.canRequestAds();

  @override
  Future<void> initialize() => MobileAds.instance.initialize();

  @override
  Future<LoadedInterstitial> loadInterstitial() {
    final done = Completer<LoadedInterstitial>();
    InterstitialAd.load(
      adUnitId: AdsConfig.interstitial,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => done.complete(_GoogleInterstitial(ad)),
        onAdFailedToLoad: (e) => done.completeError(Exception(e.message)),
      ),
    );
    return done.future;
  }

  @override
  Future<void> showPrivacyOptions() => ConsentForm.showPrivacyOptionsForm((e) {
    if (e != null) debugPrint('privacy options failed: ${e.message}');
  });
}

class _GoogleInterstitial implements LoadedInterstitial {
  _GoogleInterstitial(this._ad);
  final InterstitialAd _ad;

  @override
  Future<void> show({required VoidCallback onShown}) async {
    final closed = Completer<void>();
    void close(Ad a) {
      a.dispose();
      if (!closed.isCompleted) closed.complete();
    }

    _ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (_) => onShown(),
      onAdDismissedFullScreenContent: close,
      onAdFailedToShowFullScreenContent: (a, e) {
        debugPrint('interstitial show failed: ${e.message}');
        close(a);
      },
    );
    try {
      await _ad.show();
      await closed.future;
    } on Object catch (e) {
      debugPrint('interstitial show failed: $e');
      close(_ad);
    }
    // 広告を閉じるとシステムバーが戻ることがあるので、全画面に戻す
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() => _ad.dispose();
}

/// 起動時に main で [createAdsService] の結果に差し替える。テストでは何もしない実装のまま。
final adsProvider = Provider<AdsService>((ref) => DisabledAds());

AdsService createAdsService(SharedPreferences prefs) {
  final mobile = defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android;
  if (!AdsConfig.enabled || kIsWeb || !mobile) return DisabledAds();
  // デバッグビルドでは初日の猶予を外し、すぐに広告を確かめられるようにする
  return AdMobAds(InterstitialPolicy(prefs, grace: kDebugMode ? Duration.zero : const Duration(hours: 24)));
}
