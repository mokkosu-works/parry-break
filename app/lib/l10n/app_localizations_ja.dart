// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get appTitle => 'PARRY BREAK';

  @override
  String get menuEndless => 'エンドレス';

  @override
  String get menuStages => 'ステージ';

  @override
  String get menuHowToPlay => '遊び方';

  @override
  String get menuSettings => '設定';

  @override
  String get menuRanking => 'ランキング';

  @override
  String get back => '戻る';

  @override
  String get bestScore => '最高スコア';

  @override
  String waveN(String n) {
    return 'ウェーブ $n';
  }

  @override
  String get helpMoveTitle => '移動';

  @override
  String get helpMoveZones => '画面の左半分をドラッグして、パドルを左右に動かす';

  @override
  String get helpMoveRail => '左のレールをドラッグして、パドルを左右に動かす';

  @override
  String get helpParryTitle => '発射・パリィ';

  @override
  String get helpParryZones =>
      '画面の右半分をタップすると、ボールを打ち出す\nボールや敵の弾がパドルに当たる瞬間にタップすると、強く弾き返せる(パリィ)';

  @override
  String get helpParryRail =>
      'PARRY ボタンを押すと、ボールを打ち出す\nボールや敵の弾がパドルに当たる瞬間に押すと、強く弾き返せる(パリィ)';

  @override
  String get helpTimingTitle => 'タイミング';

  @override
  String get helpTimingBody =>
      '当たる瞬間にぴったり合わせるほど、弾き返したボールが強くなる\nPERFECT:ボールがブロックを突き抜けて進む\nJUST(さらにぴったり):次に当たった所で衝撃波が出て、周りのブロックもまとめて壊す';

  @override
  String get helpChainTitle => '連鎖';

  @override
  String get helpChainBody =>
      '白いブロック(要石)は、つながったブロックの塊を支えている。壊すと、支えを失った塊がまとめて崩れ落ちる\nオレンジのしま模様のブロック(爆薬)は、壊すと周りを吹き飛ばす。近くの爆薬にも次々に燃え移る';

  @override
  String get helpOverTitle => 'ゲームオーバー';

  @override
  String get helpOverBody => 'ボールを画面の下に落とすと終わり\nブロックが赤い点線(デッドライン)まで下りてきても終わり';

  @override
  String get helpPauseTitle => '一時停止';

  @override
  String get helpPauseBody => '右上の Ⅱ をタップすると、一時停止する';

  @override
  String get helpPrev => '前へ';

  @override
  String get helpNext => '次へ';

  @override
  String get paused => '一時停止中';

  @override
  String get resume => '再開';

  @override
  String get retry => 'リトライ';

  @override
  String get toTitle => 'タイトルへ';

  @override
  String get nextStage => '次のステージ';

  @override
  String get stageSelect => 'ステージ選択';

  @override
  String get gameOver => 'GAME OVER';

  @override
  String get stageClear => 'STAGE CLEAR';

  @override
  String get stageFailed => 'STAGE FAILED';

  @override
  String get newRecord => 'NEW RECORD';

  @override
  String get locked => '未解放';

  @override
  String get starClear => 'クリア';

  @override
  String get starNoHit => '一度も被弾せずにクリア';

  @override
  String starTime(String seconds) {
    return '$seconds秒以内にクリア';
  }

  @override
  String starScore(String value) {
    return 'スコア $value 以上';
  }

  @override
  String starJust(String value) {
    return 'JUST を $value 回出す';
  }

  @override
  String starPerfect(String value) {
    return 'PERFECT 以上を $value 回出す';
  }

  @override
  String starCollapse(String value) {
    return 'COLLAPSE ×$value 以上を決める';
  }

  @override
  String starChainBlast(String value) {
    return 'CHAIN BLAST ×$value 以上を決める';
  }

  @override
  String starReturnKills(String value) {
    return '撃ち返した弾でブロックを $value 個壊す';
  }

  @override
  String starGraze(String value) {
    return 'GRAZE を $value 回決める';
  }

  @override
  String starRicochet(String value) {
    return 'RICOCHET ×$value 以上を決める';
  }

  @override
  String get clearAnnihilate => '目標: ブロックをすべて壊す';

  @override
  String clearScore(String value) {
    return '目標: スコア $value に到達';
  }

  @override
  String clearSurvive(String seconds) {
    return '目標: $seconds秒間耐え抜く';
  }

  @override
  String get clearBoss => '目標: コアをすべて破壊';

  @override
  String get settingsTabControls => '操作';

  @override
  String get settingsTabSound => 'サウンド';

  @override
  String get settingsTabDisplay => '表示';

  @override
  String get settingsTabOther => 'その他';

  @override
  String get settingsControls => '操作方法';

  @override
  String get controlsZones => '画面の左右';

  @override
  String get controlsRailH => 'レール（横）';

  @override
  String get controlsRailV => 'レール（縦）';

  @override
  String get settingsSensitivity => '移動感度';

  @override
  String get settingsTiming => '判定タイミング補正';

  @override
  String get settingsTimingHelp =>
      '画面表示やタッチの遅れを補正するため、入力をこの時間だけ早く受け付けたものとして扱います';

  @override
  String get calibrate => '測定する';

  @override
  String get settingsBgm => 'BGM の音量';

  @override
  String get settingsSfx => '効果音の音量';

  @override
  String get settingsHaptics => '振動';

  @override
  String get settingsQuality => '画質';

  @override
  String get qualityHigh => '高';

  @override
  String get qualityLow => '低（省電力）';

  @override
  String get settingsReduceEffects => '演出を控えめにする';

  @override
  String get settingsReduceEffectsHelp => 'フラッシュ・点滅・揺れを抑えます';

  @override
  String get settingsLanguage => '言語';

  @override
  String get settingsAdPrivacy => '広告のプライバシー設定';

  @override
  String get settingsDebugMode => 'デバッグモード';

  @override
  String get settingsDebugModeHelp => 'すべてのステージを遊べます。スコアは記録されず、ランキングにも登録されません';

  @override
  String get debugModeOn => 'デバッグモード ON';

  @override
  String get debugModeOff => 'デバッグモード OFF';

  @override
  String get languageSystem => '端末の設定に合わせる';

  @override
  String get calibrationTitle => '判定タイミングの測定';

  @override
  String calibrationBody(String count) {
    return 'リングが線に重なる瞬間にタップしてください（$count回）';
  }

  @override
  String calibrationResult(String ms) {
    return '測定結果: ${ms}ms';
  }

  @override
  String get calibrationApply => 'この値を使う';

  @override
  String get calibrationRetry => '測り直す';

  @override
  String get tapToStart => 'タップで開始';

  @override
  String get rankingUnavailable => 'ランキングは現在利用できません';

  @override
  String get rankingEndlessScore => 'エンドレス: スコア';

  @override
  String get rankingEndlessWave => 'エンドレス: 到達ウェーブ';

  @override
  String get rankingStages => 'ステージ: 合計スコア';

  @override
  String get introKeystone => 'NEW: 要石 — 壊すと、支えていたブロックが崩れ落ちる';

  @override
  String get introTurret => 'NEW: 砲台 — 弾をパリィで撃ち返せ';

  @override
  String get introExplosive => 'NEW: 爆薬 — 周りを巻き込んで誘爆する。破片も撃ち返せる';

  @override
  String get introReflector => 'NEW: 反射板 — 当たるとボールの向きが変わる';

  @override
  String get introMagnet => 'NEW: 磁石 — 近くのボールを引き寄せる';

  @override
  String get introSplitter => 'NEW: 分裂 — 壊すと小さなブロックが飛び散る';

  @override
  String get introMirror => 'NEW: 鏡 — 撃ち返した弾をさらに跳ね返す';

  @override
  String introLoop(String loop) {
    return '$loop周目 — スピードアップ';
  }

  @override
  String get introParry => 'ボールが当たる瞬間にタップしてパリィ';

  @override
  String get introPierce => 'PERFECT でパリィすると貫通弾。まとめて撃ち抜け';

  @override
  String get introSurvive => 'ブロックをデッドラインまで下ろさずに耐え抜け';

  @override
  String get introScore => '目標スコアに到達すればクリア';

  @override
  String get bannerBoss => '赤い弾をパリィで撃ち返し、貫通弾でコアを狙え';

  @override
  String get bannerOverdrive => '全弾貫通 ×16 — PERFECT で分身弾';

  @override
  String get bannerPhase2 => '鏡のシールド展開 — ロックオンレーザーに注意';

  @override
  String get bannerPhase3 => '要塞が変形 — 弾幕に備えろ';

  @override
  String get bannerTimeOver => '要塞が急降下してくる';

  @override
  String get endingSub => '次の周回へ — さらに加速する';
}
