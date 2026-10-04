import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ja.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ja'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In ja, this message translates to:
  /// **'RICOCHET OVERDRIVE'**
  String get appTitle;

  /// No description provided for @menuEndless.
  ///
  /// In ja, this message translates to:
  /// **'エンドレス'**
  String get menuEndless;

  /// No description provided for @menuStages.
  ///
  /// In ja, this message translates to:
  /// **'ステージ'**
  String get menuStages;

  /// No description provided for @menuHowToPlay.
  ///
  /// In ja, this message translates to:
  /// **'遊び方'**
  String get menuHowToPlay;

  /// No description provided for @menuSettings.
  ///
  /// In ja, this message translates to:
  /// **'設定'**
  String get menuSettings;

  /// No description provided for @menuRanking.
  ///
  /// In ja, this message translates to:
  /// **'ランキング'**
  String get menuRanking;

  /// No description provided for @back.
  ///
  /// In ja, this message translates to:
  /// **'戻る'**
  String get back;

  /// No description provided for @bestScore.
  ///
  /// In ja, this message translates to:
  /// **'最高スコア'**
  String get bestScore;

  /// No description provided for @waveN.
  ///
  /// In ja, this message translates to:
  /// **'ウェーブ {n}'**
  String waveN(String n);

  /// No description provided for @helpMoveTitle.
  ///
  /// In ja, this message translates to:
  /// **'移動'**
  String get helpMoveTitle;

  /// No description provided for @helpMoveZones.
  ///
  /// In ja, this message translates to:
  /// **'画面の左半分をドラッグ'**
  String get helpMoveZones;

  /// No description provided for @helpMoveRail.
  ///
  /// In ja, this message translates to:
  /// **'左のレールをドラッグ'**
  String get helpMoveRail;

  /// No description provided for @helpParryTitle.
  ///
  /// In ja, this message translates to:
  /// **'発射・パリィ'**
  String get helpParryTitle;

  /// No description provided for @helpParryZones.
  ///
  /// In ja, this message translates to:
  /// **'画面の右半分を、当たる瞬間にタップ'**
  String get helpParryZones;

  /// No description provided for @helpParryRail.
  ///
  /// In ja, this message translates to:
  /// **'当たる瞬間に PARRY ボタン'**
  String get helpParryRail;

  /// No description provided for @helpTimingTitle.
  ///
  /// In ja, this message translates to:
  /// **'タイミング'**
  String get helpTimingTitle;

  /// No description provided for @helpTimingBody.
  ///
  /// In ja, this message translates to:
  /// **'PERFECT → 貫通弾\nJUST → 衝撃波\nヒートでパドルが伸びる（最大1.5倍）'**
  String get helpTimingBody;

  /// No description provided for @helpChainTitle.
  ///
  /// In ja, this message translates to:
  /// **'連鎖'**
  String get helpChainTitle;

  /// No description provided for @helpChainBody.
  ///
  /// In ja, this message translates to:
  /// **'白い要石を壊すと崩落\nオレンジの爆薬で誘爆'**
  String get helpChainBody;

  /// No description provided for @helpOverTitle.
  ///
  /// In ja, this message translates to:
  /// **'ゲーム終了'**
  String get helpOverTitle;

  /// No description provided for @helpOverBody.
  ///
  /// In ja, this message translates to:
  /// **'ボールを落とすと終了\nブロックが警告線に届いても終了'**
  String get helpOverBody;

  /// No description provided for @helpPauseTitle.
  ///
  /// In ja, this message translates to:
  /// **'一時停止'**
  String get helpPauseTitle;

  /// No description provided for @helpPauseBody.
  ///
  /// In ja, this message translates to:
  /// **'右上の Ⅱ で停止'**
  String get helpPauseBody;

  /// No description provided for @paused.
  ///
  /// In ja, this message translates to:
  /// **'一時停止中'**
  String get paused;

  /// No description provided for @resume.
  ///
  /// In ja, this message translates to:
  /// **'再開'**
  String get resume;

  /// No description provided for @retry.
  ///
  /// In ja, this message translates to:
  /// **'リトライ'**
  String get retry;

  /// No description provided for @toTitle.
  ///
  /// In ja, this message translates to:
  /// **'タイトルへ'**
  String get toTitle;

  /// No description provided for @nextStage.
  ///
  /// In ja, this message translates to:
  /// **'次のステージ'**
  String get nextStage;

  /// No description provided for @stageSelect.
  ///
  /// In ja, this message translates to:
  /// **'ステージ選択'**
  String get stageSelect;

  /// No description provided for @gameOver.
  ///
  /// In ja, this message translates to:
  /// **'GAME OVER'**
  String get gameOver;

  /// No description provided for @stageClear.
  ///
  /// In ja, this message translates to:
  /// **'STAGE CLEAR'**
  String get stageClear;

  /// No description provided for @stageFailed.
  ///
  /// In ja, this message translates to:
  /// **'STAGE FAILED'**
  String get stageFailed;

  /// No description provided for @newRecord.
  ///
  /// In ja, this message translates to:
  /// **'NEW RECORD'**
  String get newRecord;

  /// No description provided for @locked.
  ///
  /// In ja, this message translates to:
  /// **'ロック中'**
  String get locked;

  /// No description provided for @starClear.
  ///
  /// In ja, this message translates to:
  /// **'クリア'**
  String get starClear;

  /// No description provided for @starNoHit.
  ///
  /// In ja, this message translates to:
  /// **'被弾なしでクリア'**
  String get starNoHit;

  /// No description provided for @starTime.
  ///
  /// In ja, this message translates to:
  /// **'{seconds}秒以内にクリア'**
  String starTime(String seconds);

  /// No description provided for @starScore.
  ///
  /// In ja, this message translates to:
  /// **'スコア {value} 以上'**
  String starScore(String value);

  /// No description provided for @starJust.
  ///
  /// In ja, this message translates to:
  /// **'JUST を {value} 回'**
  String starJust(String value);

  /// No description provided for @starPerfect.
  ///
  /// In ja, this message translates to:
  /// **'PERFECT 以上を {value} 回'**
  String starPerfect(String value);

  /// No description provided for @starCollapse.
  ///
  /// In ja, this message translates to:
  /// **'COLLAPSE ×{value} 以上'**
  String starCollapse(String value);

  /// No description provided for @starChainBlast.
  ///
  /// In ja, this message translates to:
  /// **'CHAIN BLAST ×{value} 以上'**
  String starChainBlast(String value);

  /// No description provided for @starReturnKills.
  ///
  /// In ja, this message translates to:
  /// **'撃ち返しで {value} 個破壊'**
  String starReturnKills(String value);

  /// No description provided for @starGraze.
  ///
  /// In ja, this message translates to:
  /// **'GRAZE を {value} 回'**
  String starGraze(String value);

  /// No description provided for @starRicochet.
  ///
  /// In ja, this message translates to:
  /// **'RICOCHET ×{value} 以上'**
  String starRicochet(String value);

  /// No description provided for @clearAnnihilate.
  ///
  /// In ja, this message translates to:
  /// **'目標: 全消し'**
  String get clearAnnihilate;

  /// No description provided for @clearScore.
  ///
  /// In ja, this message translates to:
  /// **'目標: スコア {value}'**
  String clearScore(String value);

  /// No description provided for @clearSurvive.
  ///
  /// In ja, this message translates to:
  /// **'目標: {seconds}秒耐える'**
  String clearSurvive(String seconds);

  /// No description provided for @clearBoss.
  ///
  /// In ja, this message translates to:
  /// **'目標: コアをすべて破壊'**
  String get clearBoss;

  /// No description provided for @settingsControls.
  ///
  /// In ja, this message translates to:
  /// **'操作方法'**
  String get settingsControls;

  /// No description provided for @controlsZones.
  ///
  /// In ja, this message translates to:
  /// **'画面の左右で操作'**
  String get controlsZones;

  /// No description provided for @controlsRailH.
  ///
  /// In ja, this message translates to:
  /// **'レール（横）'**
  String get controlsRailH;

  /// No description provided for @controlsRailV.
  ///
  /// In ja, this message translates to:
  /// **'レール（縦）'**
  String get controlsRailV;

  /// No description provided for @settingsSensitivity.
  ///
  /// In ja, this message translates to:
  /// **'移動感度'**
  String get settingsSensitivity;

  /// No description provided for @settingsTiming.
  ///
  /// In ja, this message translates to:
  /// **'判定タイミング補正'**
  String get settingsTiming;

  /// No description provided for @settingsTimingHelp.
  ///
  /// In ja, this message translates to:
  /// **'画面とタッチの遅れを打ち消すため、入力をこの時間だけ早めて扱います'**
  String get settingsTimingHelp;

  /// No description provided for @calibrate.
  ///
  /// In ja, this message translates to:
  /// **'測定する'**
  String get calibrate;

  /// No description provided for @settingsBgm.
  ///
  /// In ja, this message translates to:
  /// **'BGM 音量'**
  String get settingsBgm;

  /// No description provided for @settingsSfx.
  ///
  /// In ja, this message translates to:
  /// **'効果音 音量'**
  String get settingsSfx;

  /// No description provided for @settingsHaptics.
  ///
  /// In ja, this message translates to:
  /// **'振動'**
  String get settingsHaptics;

  /// No description provided for @settingsQuality.
  ///
  /// In ja, this message translates to:
  /// **'画質'**
  String get settingsQuality;

  /// No description provided for @qualityHigh.
  ///
  /// In ja, this message translates to:
  /// **'高'**
  String get qualityHigh;

  /// No description provided for @qualityLow.
  ///
  /// In ja, this message translates to:
  /// **'低（省電力）'**
  String get qualityLow;

  /// No description provided for @settingsReduceEffects.
  ///
  /// In ja, this message translates to:
  /// **'刺激を弱める'**
  String get settingsReduceEffects;

  /// No description provided for @settingsReduceEffectsHelp.
  ///
  /// In ja, this message translates to:
  /// **'フラッシュ・画面反転・画面の揺れを弱めます'**
  String get settingsReduceEffectsHelp;

  /// No description provided for @settingsLanguage.
  ///
  /// In ja, this message translates to:
  /// **'言語'**
  String get settingsLanguage;

  /// No description provided for @settingsDebugMode.
  ///
  /// In ja, this message translates to:
  /// **'デバッグモード'**
  String get settingsDebugMode;

  /// No description provided for @settingsDebugModeHelp.
  ///
  /// In ja, this message translates to:
  /// **'全ステージを遊べます。記録とランキングには残りません'**
  String get settingsDebugModeHelp;

  /// No description provided for @debugModeOn.
  ///
  /// In ja, this message translates to:
  /// **'デバッグモード ON'**
  String get debugModeOn;

  /// No description provided for @debugModeOff.
  ///
  /// In ja, this message translates to:
  /// **'デバッグモード OFF'**
  String get debugModeOff;

  /// No description provided for @languageSystem.
  ///
  /// In ja, this message translates to:
  /// **'端末の設定'**
  String get languageSystem;

  /// No description provided for @calibrationTitle.
  ///
  /// In ja, this message translates to:
  /// **'判定タイミングの測定'**
  String get calibrationTitle;

  /// No description provided for @calibrationBody.
  ///
  /// In ja, this message translates to:
  /// **'リングが線に重なる瞬間にタップしてください（{count}回）'**
  String calibrationBody(String count);

  /// No description provided for @calibrationResult.
  ///
  /// In ja, this message translates to:
  /// **'測定結果: {ms}ms'**
  String calibrationResult(String ms);

  /// No description provided for @calibrationApply.
  ///
  /// In ja, this message translates to:
  /// **'この値を使う'**
  String get calibrationApply;

  /// No description provided for @calibrationRetry.
  ///
  /// In ja, this message translates to:
  /// **'もう一度'**
  String get calibrationRetry;

  /// No description provided for @tapToStart.
  ///
  /// In ja, this message translates to:
  /// **'タップで開始'**
  String get tapToStart;

  /// No description provided for @rankingUnavailable.
  ///
  /// In ja, this message translates to:
  /// **'ランキングは現在利用できません'**
  String get rankingUnavailable;

  /// No description provided for @rankingEndlessScore.
  ///
  /// In ja, this message translates to:
  /// **'エンドレス: スコア'**
  String get rankingEndlessScore;

  /// No description provided for @rankingEndlessWave.
  ///
  /// In ja, this message translates to:
  /// **'エンドレス: 到達ウェーブ'**
  String get rankingEndlessWave;

  /// No description provided for @rankingStages.
  ///
  /// In ja, this message translates to:
  /// **'ステージ: 合計スコア'**
  String get rankingStages;

  /// No description provided for @introKeystone.
  ///
  /// In ja, this message translates to:
  /// **'NEW: 要石 — 壊すと支えていたブロックが崩落'**
  String get introKeystone;

  /// No description provided for @introTurret.
  ///
  /// In ja, this message translates to:
  /// **'NEW: 砲台 — 弾をパリィで撃ち返せ'**
  String get introTurret;

  /// No description provided for @introExplosive.
  ///
  /// In ja, this message translates to:
  /// **'NEW: 爆薬 — 誘爆させろ。破片も撃ち返せる'**
  String get introExplosive;

  /// No description provided for @introReflector.
  ///
  /// In ja, this message translates to:
  /// **'NEW: 反射 — ボールの軌道が変わる'**
  String get introReflector;

  /// No description provided for @introMagnet.
  ///
  /// In ja, this message translates to:
  /// **'NEW: 磁力 — ボールを引き寄せる'**
  String get introMagnet;

  /// No description provided for @introSplitter.
  ///
  /// In ja, this message translates to:
  /// **'NEW: 分裂 — 小さなブロックを散らす'**
  String get introSplitter;

  /// No description provided for @introMirror.
  ///
  /// In ja, this message translates to:
  /// **'NEW: 鏡面 — 撃ち返した弾を跳ね返す'**
  String get introMirror;

  /// No description provided for @introLoop.
  ///
  /// In ja, this message translates to:
  /// **'周回 {loop} — スピードアップ'**
  String introLoop(String loop);

  /// No description provided for @introParry.
  ///
  /// In ja, this message translates to:
  /// **'ボールが当たる瞬間にタップしてパリィ'**
  String get introParry;

  /// No description provided for @introPierce.
  ///
  /// In ja, this message translates to:
  /// **'PERFECT パリィで貫通弾。まとめて貫け'**
  String get introPierce;

  /// No description provided for @introSurvive.
  ///
  /// In ja, this message translates to:
  /// **'ブロックが警告線に届かないよう耐えろ'**
  String get introSurvive;

  /// No description provided for @introScore.
  ///
  /// In ja, this message translates to:
  /// **'目標スコアに届けばクリア'**
  String get introScore;

  /// No description provided for @bannerBoss.
  ///
  /// In ja, this message translates to:
  /// **'パリィした赤い弾と貫通弾でコアを撃て'**
  String get bannerBoss;

  /// No description provided for @bannerOverdrive.
  ///
  /// In ja, this message translates to:
  /// **'全貫通 ×16 — PERFECT で分身弾'**
  String get bannerOverdrive;

  /// No description provided for @bannerPhase2.
  ///
  /// In ja, this message translates to:
  /// **'鏡面シールド — ロックオンレーザー'**
  String get bannerPhase2;

  /// No description provided for @bannerPhase3.
  ///
  /// In ja, this message translates to:
  /// **'要塞展開 — 弾幕'**
  String get bannerPhase3;

  /// No description provided for @bannerTimeOver.
  ///
  /// In ja, this message translates to:
  /// **'要塞が急降下'**
  String get bannerTimeOver;

  /// No description provided for @endingSub.
  ///
  /// In ja, this message translates to:
  /// **'次の周回 — さらに加速'**
  String get endingSub;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ja'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ja':
      return AppLocalizationsJa();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
