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

  /// No description provided for @menuHistory.
  ///
  /// In ja, this message translates to:
  /// **'プレイ記録'**
  String get menuHistory;

  /// No description provided for @historyEmpty.
  ///
  /// In ja, this message translates to:
  /// **'まだ記録がありません。結果画面まで遊ぶと、ここに残ります'**
  String get historyEmpty;

  /// No description provided for @historyCleared.
  ///
  /// In ja, this message translates to:
  /// **'クリア'**
  String get historyCleared;

  /// No description provided for @historyFailed.
  ///
  /// In ja, this message translates to:
  /// **'未クリア'**
  String get historyFailed;

  /// No description provided for @back.
  ///
  /// In ja, this message translates to:
  /// **'戻る'**
  String get back;

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

  /// No description provided for @helpComboTitle.
  ///
  /// In ja, this message translates to:
  /// **'COMBO・FEVER TIME'**
  String get helpComboTitle;

  /// No description provided for @helpComboBody.
  ///
  /// In ja, this message translates to:
  /// **'パリィや敵弾の撃ち返しを決めると、上の COMBO メーターが満ちていく。段階が上がるほど、得点の倍率(×1 → ×2 → ×4 → ×8)とボールの速さが上がる\nメーターが満ちると FEVER TIME。しばらくの間、ボールがブロックを貫き、倍率は ×16\n敵の弾に当たると、COMBO は下がる'**
  String get helpComboBody;

  /// No description provided for @helpGrazeTitle.
  ///
  /// In ja, this message translates to:
  /// **'GRAZE・RICOCHET'**
  String get helpGrazeTitle;

  /// No description provided for @helpGrazeBody.
  ///
  /// In ja, this message translates to:
  /// **'GRAZE:敵の弾をパドルに当てず、すれすれでよけると決まる。COMBO が上がる\nRICOCHET:ボールがパドルに戻るまでに、続けて 8 個以上壊すと決まる。数が多いほど高得点'**
  String get helpGrazeBody;

  /// No description provided for @helpItemTitle.
  ///
  /// In ja, this message translates to:
  /// **'ITEM'**
  String get helpItemTitle;

  /// No description provided for @helpItemBody.
  ///
  /// In ja, this message translates to:
  /// **'ブロックを壊すと、ときどきカプセルが落ちてくる。パドルで受けると取れる\nパリィで受けると、効果が強くなる(名前に + が付く)\nW:パドルが広がる M:分身弾が出る S:パリィのたびに弾を撃つ\nB:次に当たった所で衝撃波 G:下に防壁ができる C:ボールが遅くなる'**
  String get helpItemBody;

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

  /// No description provided for @helpKeysMove.
  ///
  /// In ja, this message translates to:
  /// **'キーボード:←→ か A / D で移動'**
  String get helpKeysMove;

  /// No description provided for @helpKeysParry.
  ///
  /// In ja, this message translates to:
  /// **'キーボード:Space か Enter で発射・パリィ'**
  String get helpKeysParry;

  /// No description provided for @helpKeysPause.
  ///
  /// In ja, this message translates to:
  /// **'キーボード:Esc か P で一時停止'**
  String get helpKeysPause;

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

  /// No description provided for @bestScoreClearOnly.
  ///
  /// In ja, this message translates to:
  /// **'クリアした回のみ記録'**
  String get bestScoreClearOnly;

  /// No description provided for @resultCauseBall.
  ///
  /// In ja, this message translates to:
  /// **'ボールを落とした'**
  String get resultCauseBall;

  /// No description provided for @resultCauseBreached.
  ///
  /// In ja, this message translates to:
  /// **'ブロックが下まで来た'**
  String get resultCauseBreached;

  /// No description provided for @resultCauseTime.
  ///
  /// In ja, this message translates to:
  /// **'時間切れ'**
  String get resultCauseTime;

  /// No description provided for @resultCauseDetail.
  ///
  /// In ja, this message translates to:
  /// **'最後のパリィから{sec}秒・ボールは段階{tier}'**
  String resultCauseDetail(String sec, String tier);

  /// No description provided for @resultCauseDetailFever.
  ///
  /// In ja, this message translates to:
  /// **'最後のパリィから{sec}秒・FEVER TIME 中'**
  String resultCauseDetailFever(String sec);

  /// No description provided for @resultCauseNoParry.
  ///
  /// In ja, this message translates to:
  /// **'一度もパリィしないまま'**
  String get resultCauseNoParry;

  /// No description provided for @resultGapTitle.
  ///
  /// In ja, this message translates to:
  /// **'あと少し'**
  String get resultGapTitle;

  /// No description provided for @resultGapAnnihilate.
  ///
  /// In ja, this message translates to:
  /// **'全消しまで残り{n}個'**
  String resultGapAnnihilate(String n);

  /// No description provided for @resultGapScore.
  ///
  /// In ja, this message translates to:
  /// **'目標スコアまで残り{n}'**
  String resultGapScore(String n);

  /// No description provided for @resultGapSurvive.
  ///
  /// In ja, this message translates to:
  /// **'生き残りまで残り{n}秒'**
  String resultGapSurvive(String n);

  /// No description provided for @resultGapBoss.
  ///
  /// In ja, this message translates to:
  /// **'ボスの残り HP {n}'**
  String resultGapBoss(String n);

  /// No description provided for @unlockBy.
  ///
  /// In ja, this message translates to:
  /// **'{stage} をクリアすると開く'**
  String unlockBy(String stage);

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
  /// **'レール(横)'**
  String get controlsRailH;

  /// No description provided for @controlsRailV.
  ///
  /// In ja, this message translates to:
  /// **'レール(縦)'**
  String get controlsRailV;

  /// No description provided for @settingsSensitivity.
  ///
  /// In ja, this message translates to:
  /// **'移動感度'**
  String get settingsSensitivity;

  /// No description provided for @settingsRailSensitivity.
  ///
  /// In ja, this message translates to:
  /// **'レール感度'**
  String get settingsRailSensitivity;

  /// No description provided for @settingsZonesOnly.
  ///
  /// In ja, this message translates to:
  /// **'操作方法が「画面の左右」のときに使います'**
  String get settingsZonesOnly;

  /// No description provided for @settingsRailOnly.
  ///
  /// In ja, this message translates to:
  /// **'操作方法が「レール」のときに使います'**
  String get settingsRailOnly;

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
  /// **'低(省電力)'**
  String get qualityLow;

  /// No description provided for @settingsReduceEffects.
  ///
  /// In ja, this message translates to:
  /// **'演出を控えめにする'**
  String get settingsReduceEffects;

  /// No description provided for @settingsReduceEffectsHelp.
  ///
  /// In ja, this message translates to:
  /// **'フラッシュ・点滅・画面の揺れと、メニューの動きを抑えます'**
  String get settingsReduceEffectsHelp;

  /// No description provided for @settingsShowTiming.
  ///
  /// In ja, this message translates to:
  /// **'タイミングの表示'**
  String get settingsShowTiming;

  /// No description provided for @settingsShowTimingHelp.
  ///
  /// In ja, this message translates to:
  /// **'パリィの判定の下に、早い (EARLY)・遅い (LATE) とずれ (ms) を出します'**
  String get settingsShowTimingHelp;

  /// No description provided for @practiceHelp.
  ///
  /// In ja, this message translates to:
  /// **'ボールは落としても 1 秒で出直します。ここでのプレイは記録に残りません'**
  String get practiceHelp;

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
  /// **'縮んでくる輪が、中央の輪に重なる瞬間にタップしてください({count}回)'**
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

  /// No description provided for @calibrationStart.
  ///
  /// In ja, this message translates to:
  /// **'スタート'**
  String get calibrationStart;

  /// No description provided for @calibrationFailed.
  ///
  /// In ja, this message translates to:
  /// **'うまく測れませんでした(輪に合ったタップ: {hits}回。{min}回以上必要です)。縮んでくる輪が、中央の輪に重なる瞬間にタップしてください'**
  String calibrationFailed(String hits, String min);

  /// No description provided for @rankingUnavailable.
  ///
  /// In ja, this message translates to:
  /// **'ランキングは現在利用できません'**
  String get rankingUnavailable;

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
  /// **'NEW: 鏡 — 撃ち返した弾をさらに跳ね返す。貫通弾でしか壊れない'**
  String get introMirror;

  /// No description provided for @introWall.
  ///
  /// In ja, this message translates to:
  /// **'NEW: 壊せない壁 — 全消しには数えない。FEVER TIME 中だけ壊せる'**
  String get introWall;

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

  /// No description provided for @introParryButton.
  ///
  /// In ja, this message translates to:
  /// **'ボールが当たる瞬間に PARRY を押してパリィ'**
  String get introParryButton;

  /// No description provided for @introPierce.
  ///
  /// In ja, this message translates to:
  /// **'PERFECT でパリィすると貫通弾。まとめて撃ち抜け'**
  String get introPierce;

  /// No description provided for @introFeverTime.
  ///
  /// In ja, this message translates to:
  /// **'PERFECT を重ねてコンボを貯めると FEVER TIME。全弾貫通で一気に崩せ'**
  String get introFeverTime;

  /// No description provided for @introSurvive.
  ///
  /// In ja, this message translates to:
  /// **'ブロックをデッドラインまで下ろさずに耐え抜け'**
  String get introSurvive;

  /// No description provided for @introItem.
  ///
  /// In ja, this message translates to:
  /// **'NEW: アイテム — 落ちてくるカプセルをパドルで取れ。パリィで取ると効果が強くなる'**
  String get introItem;

  /// No description provided for @introScore.
  ///
  /// In ja, this message translates to:
  /// **'スコア {value} に到達すればクリア'**
  String introScore(String value);

  /// No description provided for @bannerBoss.
  ///
  /// In ja, this message translates to:
  /// **'赤い弾をパリィで撃ち返し、貫通弾でコアを狙え'**
  String get bannerBoss;

  /// No description provided for @bannerFeverTime.
  ///
  /// In ja, this message translates to:
  /// **'全弾貫通 ×16 — PERFECT で分身弾'**
  String get bannerFeverTime;

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

  /// No description provided for @startupErrorTitle.
  ///
  /// In ja, this message translates to:
  /// **'起動できませんでした'**
  String get startupErrorTitle;

  /// No description provided for @startupErrorBody.
  ///
  /// In ja, this message translates to:
  /// **'ゲームのデータを読み込めませんでした。アプリを終了して、もう一度起動してください。直らないときは、アプリを最新版に更新してください。'**
  String get startupErrorBody;

  /// No description provided for @chapterPrev.
  ///
  /// In ja, this message translates to:
  /// **'前の章'**
  String get chapterPrev;

  /// No description provided for @chapterNext.
  ///
  /// In ja, this message translates to:
  /// **'次の章'**
  String get chapterNext;

  /// No description provided for @stepDown.
  ///
  /// In ja, this message translates to:
  /// **'下げる'**
  String get stepDown;

  /// No description provided for @stepUp.
  ///
  /// In ja, this message translates to:
  /// **'上げる'**
  String get stepUp;

  /// No description provided for @open.
  ///
  /// In ja, this message translates to:
  /// **'開く'**
  String get open;

  /// No description provided for @pauseGame.
  ///
  /// In ja, this message translates to:
  /// **'一時停止する'**
  String get pauseGame;

  /// No description provided for @stageTileCleared.
  ///
  /// In ja, this message translates to:
  /// **'{id} {title}、クリア済み、星 {got} / {total}'**
  String stageTileCleared(String id, String title, String got, String total);

  /// No description provided for @stageTileNotCleared.
  ///
  /// In ja, this message translates to:
  /// **'{id} {title}、未クリア、星 {got} / {total}'**
  String stageTileNotCleared(String id, String title, String got, String total);

  /// No description provided for @stageTileLocked.
  ///
  /// In ja, this message translates to:
  /// **'{id}、未解放'**
  String stageTileLocked(String id);
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
