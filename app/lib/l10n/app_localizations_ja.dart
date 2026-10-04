// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get appTitle => 'RICOCHET OVERDRIVE';

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
  String get helpMoveZones => '画面の左半分をドラッグ';

  @override
  String get helpMoveRail => '左のレールをドラッグ';

  @override
  String get helpParryTitle => '発射・パリィ';

  @override
  String get helpParryZones => '画面の右半分を、当たる瞬間にタップ';

  @override
  String get helpParryRail => '当たる瞬間に PARRY ボタン';

  @override
  String get helpTimingTitle => 'タイミング';

  @override
  String get helpTimingBody => 'PERFECT → 貫通弾\nJUST → 衝撃波\nヒートでパドルが伸びる（最大1.5倍）';

  @override
  String get helpChainTitle => '連鎖';

  @override
  String get helpChainBody => '白い要石を壊すと崩落\nオレンジの爆薬で誘爆';

  @override
  String get helpOverTitle => 'ゲーム終了';

  @override
  String get helpOverBody => 'ボールを落とすと終了\nブロックが警告線に届いても終了';

  @override
  String get helpPauseTitle => '一時停止';

  @override
  String get helpPauseBody => '右上の Ⅱ で停止';

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
  String get locked => 'ロック中';

  @override
  String get starClear => 'クリア';

  @override
  String get starNoHit => '被弾なしでクリア';

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
    return 'JUST を $value 回';
  }

  @override
  String starPerfect(String value) {
    return 'PERFECT 以上を $value 回';
  }

  @override
  String starCollapse(String value) {
    return 'COLLAPSE ×$value 以上';
  }

  @override
  String starChainBlast(String value) {
    return 'CHAIN BLAST ×$value 以上';
  }

  @override
  String starReturnKills(String value) {
    return '撃ち返しで $value 個破壊';
  }

  @override
  String starGraze(String value) {
    return 'GRAZE を $value 回';
  }

  @override
  String starRicochet(String value) {
    return 'RICOCHET ×$value 以上';
  }

  @override
  String get clearAnnihilate => '目標: 全消し';

  @override
  String clearScore(String value) {
    return '目標: スコア $value';
  }

  @override
  String clearSurvive(String seconds) {
    return '目標: $seconds秒耐える';
  }

  @override
  String get clearBoss => '目標: コアをすべて破壊';

  @override
  String get settingsControls => '操作方法';

  @override
  String get controlsZones => '画面の左右で操作';

  @override
  String get controlsRailH => 'レール（横）';

  @override
  String get controlsRailV => 'レール（縦）';

  @override
  String get settingsSensitivity => '移動感度';

  @override
  String get settingsTiming => '判定タイミング補正';

  @override
  String get settingsTimingHelp => '画面とタッチの遅れを打ち消すため、入力をこの時間だけ早めて扱います';

  @override
  String get calibrate => '測定する';

  @override
  String get settingsBgm => 'BGM 音量';

  @override
  String get settingsSfx => '効果音 音量';

  @override
  String get settingsHaptics => '振動';

  @override
  String get settingsQuality => '画質';

  @override
  String get qualityHigh => '高';

  @override
  String get qualityLow => '低（省電力）';

  @override
  String get settingsReduceEffects => '刺激を弱める';

  @override
  String get settingsReduceEffectsHelp => 'フラッシュ・画面反転・画面の揺れを弱めます';

  @override
  String get settingsLanguage => '言語';

  @override
  String get settingsDebugMode => 'デバッグモード';

  @override
  String get settingsDebugModeHelp => '全ステージを遊べます。記録とランキングには残りません';

  @override
  String get debugModeOn => 'デバッグモード ON';

  @override
  String get debugModeOff => 'デバッグモード OFF';

  @override
  String get languageSystem => '端末の設定';

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
  String get calibrationRetry => 'もう一度';

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
  String get introKeystone => 'NEW: 要石 — 壊すと支えていたブロックが崩落';

  @override
  String get introTurret => 'NEW: 砲台 — 弾をパリィで撃ち返せ';

  @override
  String get introExplosive => 'NEW: 爆薬 — 誘爆させろ。破片も撃ち返せる';

  @override
  String get introReflector => 'NEW: 反射 — ボールの軌道が変わる';

  @override
  String get introMagnet => 'NEW: 磁力 — ボールを引き寄せる';

  @override
  String get introSplitter => 'NEW: 分裂 — 小さなブロックを散らす';

  @override
  String get introMirror => 'NEW: 鏡面 — 撃ち返した弾を跳ね返す';

  @override
  String introLoop(String loop) {
    return '周回 $loop — スピードアップ';
  }

  @override
  String get introParry => 'ボールが当たる瞬間にタップしてパリィ';

  @override
  String get introPierce => 'PERFECT パリィで貫通弾。まとめて貫け';

  @override
  String get introSurvive => 'ブロックが警告線に届かないよう耐えろ';

  @override
  String get introScore => '目標スコアに届けばクリア';

  @override
  String get bannerBoss => 'パリィした赤い弾と貫通弾でコアを撃て';

  @override
  String get bannerOverdrive => '全貫通 ×16 — PERFECT で分身弾';

  @override
  String get bannerPhase2 => '鏡面シールド — ロックオンレーザー';

  @override
  String get bannerPhase3 => '要塞展開 — 弾幕';

  @override
  String get bannerTimeOver => '要塞が急降下';

  @override
  String get endingSub => '次の周回 — さらに加速';
}
