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
  /// **'PARRY BREAK'**
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

  /// No description provided for @roundN.
  ///
  /// In ja, this message translates to:
  /// **'ラウンド {n}'**
  String roundN(String n);

  /// No description provided for @helpMoveTitle.
  ///
  /// In ja, this message translates to:
  /// **'移動'**
  String get helpMoveTitle;

  /// No description provided for @helpMoveZones.
  ///
  /// In ja, this message translates to:
  /// **'画面の左半分をドラッグして、パドルを左右に動かす'**
  String get helpMoveZones;

  /// No description provided for @helpMoveRail.
  ///
  /// In ja, this message translates to:
  /// **'左のレールをドラッグして、パドルを左右に動かす'**
  String get helpMoveRail;

  /// No description provided for @helpParryTitle.
  ///
  /// In ja, this message translates to:
  /// **'発射・パリィ'**
  String get helpParryTitle;

  /// No description provided for @helpParryZones.
  ///
  /// In ja, this message translates to:
  /// **'画面の右半分をタップすると、ボールを打ち出す\nボールや敵の弾がパドルに当たる瞬間にタップすると、強く弾き返せる(パリィ)'**
  String get helpParryZones;

  /// No description provided for @helpParryRail.
  ///
  /// In ja, this message translates to:
  /// **'PARRY ボタンを押すと、ボールを打ち出す\nボールや敵の弾がパドルに当たる瞬間に押すと、強く弾き返せる(パリィ)'**
  String get helpParryRail;

  /// No description provided for @helpTimingTitle.
  ///
  /// In ja, this message translates to:
  /// **'タイミング'**
  String get helpTimingTitle;

  /// No description provided for @helpTimingBody.
  ///
  /// In ja, this message translates to:
  /// **'当たる瞬間にぴったり合わせるほど、弾き返したボールが強くなる\nPERFECT:ボールがブロックを突き抜けて進む\nJUST(さらにぴったり):次に当たった所で衝撃波が出て、周りのブロックもまとめて壊す'**
  String get helpTimingBody;

  /// No description provided for @helpChainTitle.
  ///
  /// In ja, this message translates to:
  /// **'連鎖'**
  String get helpChainTitle;

  /// No description provided for @helpChainBody.
  ///
  /// In ja, this message translates to:
  /// **'白いブロック(要石)は、つながったブロックの塊を支えている。壊すと、支えを失った塊がまとめて崩れ落ちる\nオレンジのしま模様のブロック(爆薬)は、壊すと周りを吹き飛ばす。近くの爆薬にも次々に燃え移る'**
  String get helpChainBody;

  /// No description provided for @helpOverTitle.
  ///
  /// In ja, this message translates to:
  /// **'ゲームオーバー'**
  String get helpOverTitle;

  /// No description provided for @helpOverBody.
  ///
  /// In ja, this message translates to:
  /// **'ボールを画面の下に落とすと終わり\nブロックが赤い点線(デッドライン)まで下りてきても終わり'**
  String get helpOverBody;

  /// No description provided for @helpPauseTitle.
  ///
  /// In ja, this message translates to:
  /// **'一時停止'**
  String get helpPauseTitle;

  /// No description provided for @helpPauseBody.
  ///
  /// In ja, this message translates to:
  /// **'右上の Ⅱ をタップすると、一時停止する'**
  String get helpPauseBody;

  /// No description provided for @helpPrev.
  ///
  /// In ja, this message translates to:
  /// **'前へ'**
  String get helpPrev;

  /// No description provided for @helpNext.
  ///
  /// In ja, this message translates to:
  /// **'次へ'**
  String get helpNext;

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
  /// **'未解放'**
  String get locked;

  /// No description provided for @starClear.
  ///
  /// In ja, this message translates to:
  /// **'クリア'**
  String get starClear;

  /// No description provided for @starNoHit.
  ///
  /// In ja, this message translates to:
  /// **'一度も被弾せずにクリア'**
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
  /// **'JUST を {value} 回出す'**
  String starJust(String value);

  /// No description provided for @starPerfect.
  ///
  /// In ja, this message translates to:
  /// **'PERFECT 以上を {value} 回出す'**
  String starPerfect(String value);

  /// No description provided for @starCollapse.
  ///
  /// In ja, this message translates to:
  /// **'COLLAPSE ×{value} 以上を決める'**
  String starCollapse(String value);

  /// No description provided for @starChainBlast.
  ///
  /// In ja, this message translates to:
  /// **'CHAIN BLAST ×{value} 以上を決める'**
  String starChainBlast(String value);

  /// No description provided for @starReturnKills.
  ///
  /// In ja, this message translates to:
  /// **'撃ち返した弾でブロックを {value} 個壊す'**
  String starReturnKills(String value);

  /// No description provided for @starGraze.
  ///
  /// In ja, this message translates to:
  /// **'GRAZE を {value} 回決める'**
  String starGraze(String value);

  /// No description provided for @starRicochet.
  ///
  /// In ja, this message translates to:
  /// **'RICOCHET ×{value} 以上を決める'**
  String starRicochet(String value);

  /// No description provided for @clearAnnihilate.
  ///
  /// In ja, this message translates to:
  /// **'目標: ブロックをすべて壊す'**
  String get clearAnnihilate;

  /// No description provided for @clearScore.
  ///
  /// In ja, this message translates to:
  /// **'目標: スコア {value} に到達'**
  String clearScore(String value);

  /// No description provided for @clearSurvive.
  ///
  /// In ja, this message translates to:
  /// **'目標: {seconds}秒間耐え抜く'**
  String clearSurvive(String seconds);

  /// No description provided for @clearBoss.
  ///
  /// In ja, this message translates to:
  /// **'目標: コアをすべて破壊'**
  String get clearBoss;

  /// No description provided for @settingsTabControls.
  ///
  /// In ja, this message translates to:
  /// **'操作'**
  String get settingsTabControls;

  /// No description provided for @settingsTabSound.
  ///
  /// In ja, this message translates to:
  /// **'サウンド'**
  String get settingsTabSound;

  /// No description provided for @settingsTabDisplay.
  ///
  /// In ja, this message translates to:
  /// **'表示'**
  String get settingsTabDisplay;

  /// No description provided for @settingsTabOther.
  ///
  /// In ja, this message translates to:
  /// **'その他'**
  String get settingsTabOther;

  /// No description provided for @settingsControls.
  ///
  /// In ja, this message translates to:
  /// **'操作方法'**
  String get settingsControls;

  /// No description provided for @controlsZones.
  ///
  /// In ja, this message translates to:
  /// **'画面の左右'**
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
  /// **'画面表示やタッチの遅れを補正するため、入力をこの時間だけ早く受け付けたものとして扱います'**
  String get settingsTimingHelp;

  /// No description provided for @calibrate.
  ///
  /// In ja, this message translates to:
  /// **'測定する'**
  String get calibrate;

  /// No description provided for @settingsBgm.
  ///
  /// In ja, this message translates to:
  /// **'BGM の音量'**
  String get settingsBgm;

  /// No description provided for @settingsSfx.
  ///
  /// In ja, this message translates to:
  /// **'効果音の音量'**
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
  /// **'演出を控えめにする'**
  String get settingsReduceEffects;

  /// No description provided for @settingsReduceEffectsHelp.
  ///
  /// In ja, this message translates to:
  /// **'フラッシュ・点滅・揺れを抑えます'**
  String get settingsReduceEffectsHelp;

  /// No description provided for @settingsLanguage.
  ///
  /// In ja, this message translates to:
  /// **'言語'**
  String get settingsLanguage;

  /// No description provided for @settingsAdPrivacy.
  ///
  /// In ja, this message translates to:
  /// **'広告のプライバシー設定'**
  String get settingsAdPrivacy;

  /// No description provided for @settingsDebugMode.
  ///
  /// In ja, this message translates to:
  /// **'デバッグモード'**
  String get settingsDebugMode;

  /// No description provided for @settingsDebugModeHelp.
  ///
  /// In ja, this message translates to:
  /// **'すべてのステージを遊べます。スコアは記録されず、ランキングにも登録されません'**
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
  /// **'端末の設定に合わせる'**
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
  /// **'測り直す'**
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

  /// No description provided for @rankingEndlessRound.
  ///
  /// In ja, this message translates to:
  /// **'エンドレス: 到達ラウンド'**
  String get rankingEndlessRound;

  /// No description provided for @rankingStages.
  ///
  /// In ja, this message translates to:
  /// **'ステージ: 合計スコア'**
  String get rankingStages;

  /// No description provided for @introKeystone.
  ///
  /// In ja, this message translates to:
  /// **'NEW: 要石 — 壊すと、支えていたブロックが崩れ落ちる'**
  String get introKeystone;

  /// No description provided for @introTurret.
  ///
  /// In ja, this message translates to:
  /// **'NEW: 砲台 — 弾をパリィで撃ち返せ'**
  String get introTurret;

  /// No description provided for @introExplosive.
  ///
  /// In ja, this message translates to:
  /// **'NEW: 爆薬 — 周りを巻き込んで誘爆する。破片も撃ち返せる'**
  String get introExplosive;

  /// No description provided for @introReflector.
  ///
  /// In ja, this message translates to:
  /// **'NEW: 反射板 — 当たるとボールの向きが変わる'**
  String get introReflector;

  /// No description provided for @introMagnet.
  ///
  /// In ja, this message translates to:
  /// **'NEW: 磁石 — 近くのボールを引き寄せる'**
  String get introMagnet;

  /// No description provided for @introSplitter.
  ///
  /// In ja, this message translates to:
  /// **'NEW: 分裂 — 壊すと小さなブロックが飛び散る'**
  String get introSplitter;

  /// No description provided for @introMirror.
  ///
  /// In ja, this message translates to:
  /// **'NEW: 鏡 — 撃ち返した弾をさらに跳ね返す'**
  String get introMirror;

  /// No description provided for @introSpread.
  ///
  /// In ja, this message translates to:
  /// **'NEW: 拡散砲台 — 扇状の弾。まとめてパリィで撃ち返せ'**
  String get introSpread;

  /// No description provided for @introGatling.
  ///
  /// In ja, this message translates to:
  /// **'NEW: 連射砲台 — 追いかけてくる連射。リズムよくパリィ'**
  String get introGatling;

  /// No description provided for @introRing.
  ///
  /// In ja, this message translates to:
  /// **'NEW: 全方位砲台 — 輪の弾の隙間をくぐれ'**
  String get introRing;

  /// No description provided for @introSpiral.
  ///
  /// In ja, this message translates to:
  /// **'NEW: 回転砲台 — 渦巻く弾幕。休む間に攻めろ'**
  String get introSpiral;

  /// No description provided for @introSniper.
  ///
  /// In ja, this message translates to:
  /// **'NEW: 狙撃砲台 — 照準線が固まったら速い弾が来る'**
  String get introSniper;

  /// No description provided for @introLoop.
  ///
  /// In ja, this message translates to:
  /// **'{loop}周目 — スピードアップ'**
  String introLoop(String loop);

  /// No description provided for @introParry.
  ///
  /// In ja, this message translates to:
  /// **'ボールが当たる瞬間にタップしてパリィ'**
  String get introParry;

  /// No description provided for @introPierce.
  ///
  /// In ja, this message translates to:
  /// **'PERFECT でパリィすると貫通弾。まとめて撃ち抜け'**
  String get introPierce;

  /// No description provided for @introOverdrive.
  ///
  /// In ja, this message translates to:
  /// **'PERFECT を重ねてヒートを貯めると OVERDRIVE。全弾貫通で一気に崩せ'**
  String get introOverdrive;

  /// No description provided for @introSurvive.
  ///
  /// In ja, this message translates to:
  /// **'ブロックをデッドラインまで下ろさずに耐え抜け'**
  String get introSurvive;

  /// No description provided for @introScore.
  ///
  /// In ja, this message translates to:
  /// **'目標スコアに到達すればクリア'**
  String get introScore;

  /// No description provided for @bannerBoss.
  ///
  /// In ja, this message translates to:
  /// **'赤い弾をパリィで撃ち返し、貫通弾でコアを狙え'**
  String get bannerBoss;

  /// No description provided for @bannerOverdrive.
  ///
  /// In ja, this message translates to:
  /// **'全弾貫通 ×16 — PERFECT で分身弾'**
  String get bannerOverdrive;

  /// No description provided for @bannerPhase2.
  ///
  /// In ja, this message translates to:
  /// **'鏡のシールド展開 — ロックオンレーザーに注意'**
  String get bannerPhase2;

  /// No description provided for @bannerPhase3.
  ///
  /// In ja, this message translates to:
  /// **'要塞が変形 — 弾幕に備えろ'**
  String get bannerPhase3;

  /// No description provided for @bannerTimeOver.
  ///
  /// In ja, this message translates to:
  /// **'要塞が急降下してくる'**
  String get bannerTimeOver;

  /// No description provided for @endingSub.
  ///
  /// In ja, this message translates to:
  /// **'次の周回へ — さらに加速する'**
  String get endingSub;

  /// No description provided for @difficulty.
  ///
  /// In ja, this message translates to:
  /// **'難易度'**
  String get difficulty;

  /// No description provided for @difficultyEasy.
  ///
  /// In ja, this message translates to:
  /// **'弾が少なく遅い。パリィの判定が広く、ボス戦の時間も長い'**
  String get difficultyEasy;

  /// No description provided for @difficultyNormal.
  ///
  /// In ja, this message translates to:
  /// **'標準の難しさ'**
  String get difficultyNormal;

  /// No description provided for @difficultyHard.
  ///
  /// In ja, this message translates to:
  /// **'弾幕モード。弾が増え、壊したブロックが撃ち返してくる'**
  String get difficultyHard;
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
