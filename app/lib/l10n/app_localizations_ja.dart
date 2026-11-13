// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get menuStages => 'ステージ';

  @override
  String get menuHowToPlay => '遊び方';

  @override
  String get menuSettings => '設定';

  @override
  String get menuHistory => 'プレイ記録';

  @override
  String get historyEmpty => 'まだ記録がありません。結果画面まで遊ぶと、ここに残ります';

  @override
  String get historyCleared => 'クリア';

  @override
  String get historyFailed => '未クリア';

  @override
  String get back => '戻る';

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
  String get helpComboTitle => 'COMBO・FEVER TIME';

  @override
  String get helpComboBody =>
      'パリィや敵弾の撃ち返しを決めると、上の COMBO メーターが満ちていく。段階が上がるほど、得点の倍率(×1 → ×2 → ×4 → ×8)とボールの速さが上がる\nメーターが満ちると FEVER TIME。しばらくの間、ボールがブロックを貫き、倍率は ×16\n敵の弾に当たると、COMBO は下がる';

  @override
  String get helpGrazeTitle => 'GRAZE・RICOCHET';

  @override
  String get helpGrazeBody =>
      'GRAZE:敵の弾をパドルに当てず、すれすれでよけると決まる。COMBO が上がる\nRICOCHET:ボールがパドルに戻るまでに、続けて 8 個以上壊すと決まる。数が多いほど高得点';

  @override
  String get helpItemTitle => 'ITEM';

  @override
  String get helpItemBody =>
      'ブロックを壊すと、ときどきカプセルが落ちてくる。パドルで受けると取れる\nパリィで受けると、効果が強くなる(名前に + が付く)\nW:パドルが広がる M:分身弾が出る S:パリィのたびに弾を撃つ\nB:次に当たった所で衝撃波 G:下に防壁ができる C:ボールが遅くなる';

  @override
  String get helpOverTitle => 'ゲームオーバー';

  @override
  String get helpOverBody => 'ボールを画面の下に落とすと終わり\nブロックが赤い点線(デッドライン)まで下りてきても終わり';

  @override
  String get helpPauseTitle => '一時停止';

  @override
  String get helpPauseBody => '右上の Ⅱ をタップすると、一時停止する';

  @override
  String get helpKeysMove => 'キーボード:←→ か A / D で移動';

  @override
  String get helpKeysParry => 'キーボード:Space か Enter で発射・パリィ';

  @override
  String get helpKeysPause => 'キーボード:Esc か P で一時停止';

  @override
  String get helpPrev => '前へ';

  @override
  String get helpNext => '次へ';

  @override
  String get bestScoreClearOnly => 'クリアした回のみ記録';

  @override
  String get resultCauseBall => 'ボールを落とした';

  @override
  String get resultCauseBreached => 'ブロックが下まで来た';

  @override
  String get resultCauseTime => '時間切れ';

  @override
  String resultCauseDetail(String sec, String tier) {
    return '最後のパリィから$sec秒・ボールは段階$tier';
  }

  @override
  String resultCauseDetailFever(String sec) {
    return '最後のパリィから$sec秒・FEVER TIME 中';
  }

  @override
  String get resultCauseNoParry => '一度もパリィしないまま';

  @override
  String get resultGapTitle => 'あと少し';

  @override
  String resultGapAnnihilate(String n) {
    return '全消しまで残り$n個';
  }

  @override
  String resultGapScore(String n) {
    return '目標スコアまで残り$n';
  }

  @override
  String resultGapSurvive(String n) {
    return '生き残りまで残り$n秒';
  }

  @override
  String resultGapBoss(String n) {
    return 'ボスの残り HP $n';
  }

  @override
  String unlockBy(String stage) {
    return '$stage をクリアすると開く';
  }

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
  String get controlsRailH => 'レール(横)';

  @override
  String get controlsRailV => 'レール(縦)';

  @override
  String get settingsSensitivity => '移動感度';

  @override
  String get settingsRailSensitivity => 'レール感度';

  @override
  String get settingsZonesOnly => '操作方法が「画面の左右」のときに使います';

  @override
  String get settingsRailOnly => '操作方法が「レール」のときに使います';

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
  String get qualityLow => '低(省電力)';

  @override
  String get settingsReduceEffects => '演出を控えめにする';

  @override
  String get settingsReduceEffectsHelp => 'フラッシュ・点滅・画面の揺れと、メニューの動きを抑えます';

  @override
  String get settingsShowTiming => 'タイミングの表示';

  @override
  String get settingsShowTimingHelp =>
      'パリィの判定の下に、早い (EARLY)・遅い (LATE) とずれ (ms) を出します';

  @override
  String get practiceHelp => 'ボールは落としても 1 秒で出直します。ここでのプレイは記録に残りません';

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
    return '縮んでくる輪が、中央の輪に重なる瞬間にタップしてください($count回)';
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
  String get calibrationStart => 'スタート';

  @override
  String calibrationFailed(String hits, String min) {
    return 'うまく測れませんでした(輪に合ったタップ: $hits回。$min回以上必要です)。縮んでくる輪が、中央の輪に重なる瞬間にタップしてください';
  }

  @override
  String get rankingUnavailable => 'ランキングは現在利用できません';

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
  String get introMirror => 'NEW: 鏡 — 撃ち返した弾をさらに跳ね返す。貫通弾でしか壊れない';

  @override
  String get introWall => 'NEW: 壊せない壁 — 全消しには数えない。FEVER TIME 中だけ壊せる';

  @override
  String get introSpread => 'NEW: 拡散砲台 — 扇状の弾。まとめてパリィで撃ち返せ';

  @override
  String get introGatling => 'NEW: 連射砲台 — 追いかけてくる連射。リズムよくパリィ';

  @override
  String get introRing => 'NEW: 全方位砲台 — 輪の弾の隙間をくぐれ';

  @override
  String get introSpiral => 'NEW: 回転砲台 — 渦巻く弾幕。休む間に攻めろ';

  @override
  String get introSniper => 'NEW: 狙撃砲台 — 照準線が固まったら速い弾が来る';

  @override
  String introLoop(String loop) {
    return '$loop周目 — スピードアップ';
  }

  @override
  String get introParry => 'ボールが当たる瞬間にタップしてパリィ';

  @override
  String get introParryButton => 'ボールが当たる瞬間に PARRY を押してパリィ';

  @override
  String get introPierce => 'PERFECT でパリィすると貫通弾。まとめて撃ち抜け';

  @override
  String get introFeverTime => 'PERFECT を重ねてコンボを貯めると FEVER TIME。全弾貫通で一気に崩せ';

  @override
  String get introSurvive => 'ブロックをデッドラインまで下ろさずに耐え抜け';

  @override
  String get introItem => 'NEW: アイテム — 落ちてくるカプセルをパドルで取れ。パリィで取ると効果が強くなる';

  @override
  String introScore(String value) {
    return 'スコア $value に到達すればクリア';
  }

  @override
  String get bannerBoss => '赤い弾をパリィで撃ち返し、貫通弾でコアを狙え';

  @override
  String get bannerFeverTime => '全弾貫通 ×16 — PERFECT で分身弾';

  @override
  String get bannerPhase2 => '鏡のシールド展開 — ロックオンレーザーに注意';

  @override
  String get bannerPhase3 => '要塞が変形 — 弾幕に備えろ';

  @override
  String get bannerTimeOver => '要塞が急降下してくる';

  @override
  String get endingSub => '次の周回へ — さらに加速する';

  @override
  String get difficulty => '難易度';

  @override
  String get difficultyEasy => '弾が少なく遅い。パリィの判定が広く、ボス戦の時間も長い';

  @override
  String get difficultyNormal => '標準の難しさ';

  @override
  String get difficultyHard => '弾幕モード。弾が増え、壊したブロックが撃ち返してくる';

  @override
  String get startupErrorTitle => '起動できませんでした';

  @override
  String get startupErrorBody =>
      'ゲームのデータを読み込めませんでした。アプリを終了して、もう一度起動してください。直らないときは、アプリを最新版に更新してください。';

  @override
  String get chapterPrev => '前の章';

  @override
  String get chapterNext => '次の章';

  @override
  String get stepDown => '下げる';

  @override
  String get stepUp => '上げる';

  @override
  String get open => '開く';

  @override
  String get pauseGame => '一時停止する';

  @override
  String stageTileCleared(String id, String title, String got, String total) {
    return '$id $title、クリア済み、星 $got / $total';
  }

  @override
  String stageTileNotCleared(
    String id,
    String title,
    String got,
    String total,
  ) {
    return '$id $title、未クリア、星 $got / $total';
  }

  @override
  String stageTileLocked(String id) {
    return '$id、未解放';
  }

  @override
  String dailyCounted(int n) {
    return '今日の記録・連続$n日';
  }

  @override
  String dailyPractice(int n) {
    return '2回目以降は記録に数えない・連続$n日';
  }
}
