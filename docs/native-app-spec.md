# PARRY BREAK ネイティブアプリ仕様・アーキテクチャ

Oct 4, 2026 · @watsuwo

> 実装済み(第8章に実装の状況、第9章にストア公開までの手順、第10章に残作業をまとめた)。計画から変えた点は各所に「実装メモ」として書いた。

ブラウザ版(`legacy/index.html`)を Flutter で iOS / Android のネイティブアプリにするための仕様と設計である。ゲームの仕様は [design.md](../design.md) に従い、design.md と実装が食い違う点は **実装を正とする**(design.md 冒頭)。本書はそのうえで、ネイティブ化にあたって変える点と、ステージや機能を後から足せる構造を定める。

## 1. 方針

| 項目 | 決定 |
| --- | --- |
| 対象 | iOS / Android(横画面)。**ブラウザ版(PWA)と iOS の WebView ラッパーは廃止する**。ブラウザ版の `index.html` は移植元として `legacy/` に置き、移植の検証が終わったら削除する |
| 技術 | Flutter(描画は CustomPainter)+ Riverpod(アプリ層の状態)+ flutter_soloud(音)+ games_services(ランキング)+ shared_preferences(保存) |
| ゲームモード | **エンドレス**(現行のアーケード: 60ウェーブ + ループ)と、**ステージモード**(新規: チャプター制) |
| オンライン | 初回リリースでは **ランキング**(Game Center / Google Play Games)のみ。クラウドセーブや課金は後から足せる構造にしておく |
| 収益化 | **広告のみ**(AdMob)。課金は入れない。まずはインタースティシャルだけで、結果画面からタイトル・ステージ選択へ戻るときに、頻度を制限して出す(9.3)。リワード広告と、その報酬にするボス練習モードは次の段階で作る |
| 仕様の正 | 現在の実装。明らかな不具合だけを design.md の記載どおりに直す |

## 2. 現状の実装(移植の対象)

| 領域 | 実装 |
| --- | --- |
| ループ | 60Hz の固定ステップ。ヒットストップ・スローモーション(×0.35)・入力時刻からシミュレーション時刻への換算(`SYNC`)あり |
| 判定 | パリィは、入力イベントの時刻と、サブステップ内で補間した接触時刻の差で判定する(JUST 12ms / PERFECT 30ms / GOOD 100ms)。表示遅延の補正は16ms |
| ブロック | 1文字のIDで表す: `N` 通常 / `T` 砲台 / `R` 反射 / `M` 磁力 / `S` 分裂 / `s` 分裂の子 / `X` 鏡面 / `#` 破壊不可 / `K` 要石 / `B` 爆薬 / `C` ボスのコア。挙動は `ballHits` / `explode` / `updateBullets` などの中で、種類ごとの if 文に分散している |
| ステージ | 学習ウェーブの手作り配置(`HAND`)、mulberry32 によるシード付きの自動生成(`genLayout`)、ボス要塞3種(`BOSS_T`)とコアHP・制限時間の表 |
| システム | ヒート / OVERDRIVE、崩落(支点からの幅優先探索)、誘爆、ブレイカー、分身弾、グレイズ、跳弾、ロックオンレーザー、ボスのフェーズ移行 |
| 演出・音 | Canvas の shadowBlur によるグロー、CSS filter による OVERDRIVE の画面反転、WebAudio の合成音(効果音約30種、ヒート段階で変化する16ステップの BGM) |
| UI | DOM のタイトル・遊び方・日英切替、左の操作レール(横/縦切替)、PARRY / ポーズボタン |
| 保存 | localStorage(`ro_best` / `ro_bestwave` / `ro_language` / `ro_control_axis`) |
| 状態 | すべてグローバルの `G` に集まっている。マルチボールは `G.ball` を差し替えて処理している |

## 3. ネイティブ化で直す・変える仕様

### 3.1 不具合と未実装(移植時に直す)

| # | 内容 | 対応 |
| --- | --- | --- |
| A1 | 分身弾に印が付いておらず、メインのボールと同じ扱いになっている。5秒の寿命、パドルでの自動反射、「落としてもミスにならない」が効かない。メインのボールを落としても、分身弾が残っていればゲームが続く。OVERDRIVE が終わっても分身弾が爆発しない(OVERDRIVE FINISH の表示だけが出る) | design.md 7.4 のとおりにする。OVERDRIVE の終了時(被弾による終了を含む)に分身弾を爆発させる。メインのボールを落としても分身弾が1つでも残っていれば、その1つをメインのボールに昇格させてゲームを続ける(ゲームオーバーはボールが1つも残っていないときだけ) |
| A2 | `G.ball` を差し替えてマルチボールを処理している | ボールごとに状態(跳弾数、貫通回数、ブレイカー)を持つエンティティにする |
| A3 | ゲーム結果に影響する乱数の一部が `Math.random`(瓦礫の落下位置、分身弾の角度、ボス砲台の初期タイマー) | ウェーブのシードから作る乱数に統一する。リプレイ・ランキングの検証・テストの再現性のため。演出だけの乱数(パーティクルなど)は対象外 |
| A4 | 設定メニュー・振動が未実装(design.md 第9章) | 3.2 の B3・B6 と設定画面で実装する |
| A5 | Orbitron フォントを読み込んでいない | アプリにバンドルする(`ios/fonts/Orbitron.ttf`、OFL) |

### 3.2 ネイティブ化で変える仕様

| # | 項目 | ブラウザ版 | ネイティブ版 |
| --- | --- | --- | --- |
| B1 | 画面レイアウト | 1200×720 の固定盤面 + 左右の余白 | 論理解像度は 1200×720(5:3)のまま拡大縮小する。セーフエリア(ノッチ・ホームバー)を除いた残りを左右の操作エリアにする(左右は画面幅の13%、80〜150pt)。4:3 の iPad では上下に余白が出る(HUD を盤面の外に出す配置は未対応、第10章) |
| B2 | タッチ操作 | 左の操作レール(横/縦切替)+ 右の PARRY ボタン | 標準は「**左半分ドラッグ(相対移動)・右半分タップ**」の領域方式(design.md 第9章)。現行のレール方式は設定で選べる。マルチタッチを確実に扱うため、生のポインターイベントで処理する |
| B3 | 判定タイミング補正 | 16ms 固定 | 設定値にする(初期値はタッチ 36ms / コントローラー 16ms、範囲は0〜100ms)。リズムに合わせてタップし、平均のずれを測る **キャリブレーション画面** を設ける。タッチイベントの時刻をシミュレーション時刻に換算する仕組み(`SYNC`)は移植する |
| B4 | 高リフレッシュレート | 画面の更新頻度に依存 | シミュレーションは 60Hz 固定のまま、描画では前後のステップの間を補間して 90 / 120Hz で表示する |
| B5 | 音 | WebAudio でその場で合成 | ブラウザ版の合成(`tone` / `noise` と biquad フィルタ)を Dart に移植し、**起動時に別 isolate で効果音と BGM を WAV(メモリ上)に書き出して** flutter_soloud で鳴らす。BGM はヒート段階ごとの4小節ループ(BPM 132〜168)で、段階が変わると次の小節の頭で切り替える。ミスしたら即座に止める(コアピラー4)。**実装メモ**: 計画では WAV を書き出して同梱する予定だったが、起動時に作れば素材の書き出し作業と容量(約4.4MB)が不要になるため変えた。iOS で他アプリの音楽と共存する設定は未対応(第10章) |
| B6 | 振動 | なし | design.md 第9章の振動パターンを、端末の触覚フィードバックで実装する。設定で ON / OFF |
| B7 | 中断・再開 | ウィンドウのフォーカスが外れたらポーズ | アプリがバックグラウンドに回ったら自動でポーズする。再開は「タップで再開 → 1秒のカウントダウン」にする |
| B8 | 描画の負荷 | shadowBlur を多用 | ぼかしのフィルタは重いため、グローは事前に作った画像か加算合成で描く。OVERDRIVE の画面反転はカラーマトリクスで行う。**画質設定(高 / 低)** を設ける |
| B9 | アクセシビリティ | なし | 「フラッシュ・画面反転・画面の揺れを弱める」設定を設ける(光過敏性への配慮) |
| B10 | ポーズ画面 | Canvas の画像を img に写す回避策 | 通常の重ね表示にする |
| B11 | 保存 | localStorage | 設定はキーと値、記録はスキーマのバージョン付き JSON で保存する。記録はモード別・ステージ別に持つ。ブラウザ版の記録は移行しない |
| B12 | 多言語 | メニューだけ日英、ゲーム内は英語のみ | 文言をすべて翻訳ファイル(日本語 / 英語)に移す。ウェーブ開始時の説明(`NEW: KEYSTONE …`)も翻訳する。判定やボーナス名(PERFECT、COLLAPSE など)は英語のまま |
| B13 | ランキング | なし | Game Center / Google Play Games に送る(4章)。オフライン時は送信を保留し、次の起動時に送る |
| B14 | 遊び方の導線 | 学習ウェーブで1行の説明を出すだけ | ステージモードの第1章をチュートリアルにする。初回起動時はチュートリアルに案内する |
| B15 | 入力機器 | キーボード・マウス・ゲームパッド | タッチに加えてハードウェアキーボード(←→ / A D で移動、Space / Enter で発射・パリィ、Esc / P でポーズ)に対応。コアへの入力は `PaddleInput`(目標位置 / 方向)と `pressAction`(時刻)に抽象化してあり、ゲームパッドは後から足せる |

### 3.3 設定項目

| 項目 | 初期値 | 範囲 |
| --- | --- | --- |
| 操作方式 | 領域方式 | 領域方式 / 操作レール(横) / 操作レール(縦) |
| 移動感度 | ×2.0 | ×1.0〜×4.0 |
| 判定タイミング補正 | 36ms(タッチ) | 0〜100ms(キャリブレーションで設定可) |
| BGM 音量 / 効果音音量 | 80% / 100% | 0〜100% |
| 振動 | ON | ON / OFF |
| 画質 | 高 | 高 / 低 |
| 刺激を弱める | OFF | ON / OFF(フラッシュ・画面反転・揺れ) |
| 言語 | 端末の言語 | 日本語 / English |

## 4. ステージモードとランキング

### 4.1 ステージモード

- ステージは、1つ以上のウェーブ、クリア条件、評価条件の組み合わせとする。
- クリア条件: 全消し / ボス撃破 / 目標スコア到達 / 制限時間まで生存。
- 星3つで評価する。1つめはクリアで、残り2つの条件(例: 被弾なし、JUST を N 回、M 秒以内)はステージごとにデータで決める。
- チャプター単位で解禁する(前のチャプターの最終ステージをクリアすると次が開く)。
- 第1章(10ステージ前後)は既存の学習ウェーブ(W1 / 2 / 4 / 6 / 8 / 14 / 20 / 26)とボス1をもとにしたチュートリアルにする。
- 記録とランキングはエンドレスとは別に持つ。

### 4.2 ランキング

| ボード | 値 |
| --- | --- |
| エンドレス: スコア | 1回のプレイの最終スコア |
| エンドレス: 到達ウェーブ | 最終ウェーブ番号 |
| ステージ: 合計スコア | 全ステージの最高スコアの合計(ステージごとにボードを作るとボード数が増え続けるため、合計にした) |

不正対策として、乱数の固定(A3)により「シード + 入力ログ」からスコアを再現できる構造にしておく。サーバーでの検証は将来の課題とする。

## 5. アーキテクチャ

### 5.1 原則

1. **コアのシミュレーションは Flutter に依存しない純粋な Dart にする。** 60Hz 固定・決定的に動き、単体テストで検証できるようにする。
2. **コアは描画・音・振動を直接呼ばない。** 出来事を `GameEvent` として発行し、描画・音・振動・統計がそれを購読する(ブラウザ版の `SFX.x()` や `burst()` の直接呼び出しを置き換える)。
3. **種類の違いはレジストリで、数値と配置はデータ(JSON)で扱う。** ブロック・ボスの攻撃・ステージ・モードを、既存コードの if 文を増やさずに追加できるようにする。
4. **数値は Tuning に集める。** 既定値は `core/config/tuning.dart`、ウェーブ・ステージごとの上書きはステージデータの `tuning` に書く。降下速度・砲台の発射間隔・弾速などの計算式も Tuning にまとめた。
5. **描画は状態を読むだけにする。** ゲームの状態はコアが持ち、描画(`FieldPainter`)は毎フレームその状態を読んで描く。

**実装メモ(Flame を使わなかった理由)**: コアがすべての状態を持ち、毎フレームその状態をそのまま描く作りのため、Flame のコンポーネントの木を作るとコアの状態を二重に持つことになる。CustomPainter で即時描画(ブラウザ版の Canvas と同じ書き方)にした。描画が重くなった場合や、スプライト・パーティクルの仕組みが必要になった場合に Flame を検討する。

### 5.2 層の構成

```
UI(Flutter: タイトル / モード選択 / ステージ選択 / 設定 / リザルト)
  │  Riverpod
  ▼
Session(1回のプレイ: GameMode + World + 入力 + 時刻換算)
  │                         ▲
  ▼                         │ GameEvent
Core World(純粋 Dart: エンティティ + System 列 + レジストリ)
  │
  ├─▶ Render(CustomPainter: 状態を読んで描く、イベントでエフェクトを出す)
  ├─▶ Audio(イベント → 効果音、ヒート段階 → BGM)
  ├─▶ Haptics(イベント → 振動パターン)
  └─▶ Services(記録の保存、ランキング、設定)
```

### 5.3 ディレクトリ構成

Flutter プロジェクトはリポジトリ直下の `app/` に置く。アイコンの元画像は `app/branding/icons/` に置く。

```
app/
  lib/
    core/                         # 純粋 Dart(flutter を import しない)。core.dart でまとめて公開
      sim/        session.dart(実時間 → 固定ステップ), time_sync.dart, rng.dart(mulberry32 互換), geom.dart
      config/     field.dart(盤面の座標), tuning.dart(バランス値)
      entities/   entities.dart(Block, Ball, Bullet, Laser, …)
      blocks/     block_behavior.dart(抽象 + BlockRegistry), standard_blocks.dart(登録一覧),
                  normal / turret / reflector(反射・磁力) / splitter / mirror / wall / keystone / explosive / core_block.dart
      world/      world.dart(状態・公開操作・step)
        systems/  wave_system / ball_system / parry_system / block_system / collapse_system /
                  bullet_system / boss_system.dart(World の part。システムごとに分割)
      stages/     wave_spec.dart(WaveSpec + クリア条件), procedural_generator.dart,
                  boss_def.dart(BossDef + 攻撃パターン + BossPatternRegistry),
                  content.dart(JSON の読み込み: EndlessContent / Campaign / StageDef / 星の条件)
      modes/      game_mode.dart(GameMode + EndlessMode + StageMode)
      events/     game_event.dart
    game/         game_controller.dart(実時間で進め、イベントを演出・音・振動へ配る), game_screen.dart
    render/       field_painter.dart(盤面・HUD), block_painters.dart(種類ごとの描き方の登録簿),
                  fx.dart(パーティクル・ポップアップ・コールアウトなど), glow.dart, text_cache.dart, palette.dart
    audio/        synth.dart(WebAudio 合成の移植), sound_bank.dart(効果音・BGM の定義), audio_service.dart
    haptics/      haptics_service.dart
    input/        input_clock.dart(タッチの時刻の換算), touch_controls.dart(領域方式・レール・PARRY)
    services/     settings.dart, records.dart, content.dart, leaderboard.dart
    ui/           title / stage_select / help / settings / calibration _screen.dart, widgets.dart, stage_text.dart
    l10n/         app_ja.arb(テンプレート), app_en.arb
  assets/
    stages/endless.json               # エンドレス: 手作り配置・説明・自動生成の解禁・ボス
    stages/campaign.json              # ステージモード: 章・ステージ・星の条件
    fonts/Orbitron.ttf
  branding/icons/                     # アイコンの元画像(flutter_launcher_icons で各サイズを作る)
  test/core/                          # コアの単体テスト。golden/layouts.json はブラウザ版から書き出した配置
  test/app/                           # 画面のテスト(偽の時刻でアプリ全体を動かす)と画面写真
tools/
  dump_layouts.mjs   # legacy/index.html の配置生成を実行し、W1〜60 の配置を JSON に書き出す(移植の検証用)
```

### 5.4 コアの主要な型

```dart
// ブロックの種類ごとの振る舞い (core/blocks/block_behavior.dart)。既定は「通常ブロック」の振る舞い
abstract class BlockBehavior {
  String get id;                        // 'N', 'T', … (配置の文字。legend で読み替え可)
  int get hp;
  int basePoints(Block b, World w);     // 通常ブロックは高さで変わる
  bool get clearable => true;           // 全消しの対象か
  bool get structural => true;          // 崩落の支え合いに含むか
  bool get anchor => false;             // 支点か (要石・コア)
  HitResult onBall(World w, Block b, BallHit hit);              // pass / bounce
  void afterBounce(World w, Block b, Ball ball, double nx, double ny) {}  // 反射ブロックのずれ
  void onBlast(World w, Block b, {required bool breaker});
  bool onReturnedBullet(World w, Block b, Bullet u);            // 弾が消えるなら true
  void onDestroyed(World w, Block b, double cx, double cy) {}   // 誘爆・分裂など
  void onWaveStart(World w, Block b) {}                         // 砲台の初期タイマー
  void onFell(World w, Block b, double cx, double cy) {}        // 崩落した爆薬の爆発
  void update(World w, Block b, double dt) {}                   // 砲台の発射
  void influenceBall(World w, Block b, Ball ball, double dt) {} // 磁力
}

// 1回のプレイの進め方 (core/modes/game_mode.dart)
abstract class GameMode {
  String get recordKey;                 // 記録・ランキングの保存先
  WaveSpec? waveAt(int number);         // null ならモード終了 (ステージクリア)
}

// ウェーブ (core/stages/wave_spec.dart): 中身 (配置 / ボス)、難易度、周回倍率、クリア条件、Tuning の上書き
// ボスの攻撃 (core/stages/boss_def.dart): BossPattern を実装して BossPatternRegistry に登録する

// コアが発行する出来事 (core/events/game_event.dart)。描画・音・振動・統計が購読する
sealed class GameEvent {}
// WaveStarted, ParrySucceeded, BlockDestroyed, CollapseStarted, BlockFell, BlastExploded,
// PlayerHurt, OverdriveStarted, BossPhaseChanged, WaveCleared, GameOver, StageCompleted … (約40種)
```

System は `World` が決まった順に呼ぶ(入力 → パドル → パリィの窓 → 降下 / ボス → ヒート → ボール → 砲台 → 弾 → レーザー → 爆発 → 崩落 → クリア判定)。この順序はブラウザ版の `updatePlay` に合わせる。

### 5.5 データ形式

**エンドレス**(`assets/stages/endless.json`)

```json
{
  "wavesPerLoop": 60, "bossEvery": 10, "loopSpeedup": 0.15, "loopIntro": "intro.loop",
  "generator": { "unlock": { "N": 1, "K": 2, "T": 4, "B": 6, "R": 8, "M": 14, "S": 20, "X": 26 } },
  "handcrafted": {
    "2": { "rows": ["...K......K...", "...N......N...", ".NNNNN..NNNNN.", ".NNNNN..NNNNN.", "..NNN....NNN.."],
           "intro": "intro.keystone" }
  },
  "bosses": [
    { "template": ["#T#####T#", "NNNNNNNNN", "NNN.C.NNN", "#NN...NN#"], "coreHp": 8, "timeLimit": 90,
      "patterns": [{ "type": "fan", "from": 1 }, { "type": "aimed3", "from": 2 },
                   { "type": "laser", "from": 2 }, { "type": "spiral", "from": 3 }] }
  ]
}
```

**ステージモード**(`assets/stages/campaign.json`)

```json
{
  "chapters": [{
    "id": "ch01", "title": { "ja": "第1章 基礎訓練", "en": "CHAPTER 1  BASICS" },
    "stages": [{
      "id": "1-7", "title": { "ja": "防衛線", "en": "HOLD THE LINE" },
      "waves": [{ "endless": 11, "intro": "intro.survive",
                  "clear": { "type": "survive", "value": 40 }, "tuning": { "descentBase": 7 } }],
      "stars": [{ "type": "clear" }, { "type": "graze", "value": 5 }, { "type": "noHit" }]
    }]
  }]
}
```

- ウェーブは `rows`(配置を直接書く。`legend` で文字をブロック ID に読み替え可)/ `endless`(エンドレスの W 番号の中身)/ `boss`(ボス番号)のどれかで書く。共通で `difficulty`・`clear`・`tuning`・`intro` を書ける。
- クリア条件 `clear.type`: `annihilate`(既定。ボス戦はコア全破壊)/ `score` / `survive`。
- 星 `stars[].type`: `clear` / `noHit` / `time`(秒以内)/ `score` / `just` / `perfect` / `collapse` / `chainBlast` / `returnKills` / `graze` / `ricochet`。
- 自動生成(`genLayout`)は Dart に移植した。解禁ウェーブは JSON、形の候補・出現率・上限数はコード(`procedural_generator.dart`)にある。mulberry32 は 32bit 整数演算を再現しており、ブラウザ版と同じ配置になることをテストで保証している。

### 5.6 拡張の手順

| 追加するもの | 手順 |
| --- | --- |
| ブロック | `BlockBehavior` を実装して `standard_blocks.dart` に登録する → 描き方を `BlockPainterRegistry` に登録する(省くと標準の描き方)→ 色を `Palette.blocks` に足す → 配置の文字として使う。自動生成に入れる場合は `endless.json` の `generator.unlock` と `procedural_generator.dart` の出現率に足す |
| ステージ | `campaign.json` に追記するだけ(コードの変更は不要)。章を足せば自動で解禁の順番に入る |
| ボス | `endless.json` の `bosses` に追記する。新しい攻撃が必要なら `BossPattern` を実装して `BossPatternRegistry.standard` に登録する |
| モード | `GameMode` を実装し、タイトル画面にボタンを足す(例: デイリーチャレンジ、ボスラッシュ) |
| 効果音 | `sound_bank.dart` に合成の定義を足し、`audio_service.dart` でイベントに結びつける |
| 機能 | System を1つ追加して `World` の更新順に差し込み、必要なら `GameEvent` を追加する。演出・音・振動はイベントの購読を足す |
| オンライン機能 | `services/` にインターフェースを置き、実装を差し替える(例: クラウドセーブ、課金) |

## 6. 実装の進め方

| フェーズ | 内容 | 完了の目安 |
| --- | --- | --- |
| 0 | 本書の作成、design.md を実装に合わせて更新 | 本書と design.md 第8章(当時の 8.3 / 8.4 は、のちに本文と第9章へ取り込んだ) |
| 1 | Flutter SDK の導入と `app/` の作成、コアの移植(A1〜A3 の修正を含む)、配置の一致テスト | `flutter test` で W1〜60 の配置がブラウザ版と一致する |
| 2 | 描画(CustomPainter)、タッチ操作、HUD・演出、エンドレスモード | シミュレーター / 実機でエンドレスを通しで遊べる |
| 3 | 音、振動、設定、キャリブレーション、ポーズ・中断、画質・アクセシビリティ設定、多言語化 | ブラウザ版と同等以上の体験になる |
| 4 | 配置・ボスを JSON に出し、ステージモード(第1章、星評価、解禁)を作る | ステージ選択から第1章を遊べる |
| 5 | ランキング、アイコン・起動画面、ストア用ビルド。`legacy/` を削除する | TestFlight / Play の内部テストに出せる |

## 7. 検証

- 単体テスト(`flutter test`)
  - 配置の一致: `tools/dump_layouts.mjs` の出力と Dart の生成結果が W1〜60 で完全に一致する。
  - パリィ判定の境界: 接触時刻との差が ±12 / 30 / 100ms ちょうどのときの判定。
  - 崩落: 要石の破壊、つながりの切断で、期待どおりのブロックが崩れる。
  - スコア: 崩落・連鎖爆発・跳弾のボーナス計算。
  - 決定性: 同じシードと同じ入力ログから、同じスコアになる。
- `flutter analyze` で警告がない。
- iOS シミュレーターと Android エミュレーターで W1〜W10(ボス1)を通しで遊び、ブラウザ版と並べて挙動・数値・演出を比べる。
- 実機で、OVERDRIVE 中や大崩落の最中も 60fps 以上を保つことを確認する。
- キャリブレーションで測った補正値で、判定が体感と合うことを確認する。
- ランキングは TestFlight と Play の内部テストトラックで、送信と表示を確認する。

## 8. 実装の状況

フェーズ 0〜5 のコードは実装済み。この環境には Android SDK と完全な Xcode がないため、**iOS / Android の実機・シミュレーターでの動作は未確認**である。代わりに次を確認した。

| 確認 | 結果 |
| --- | --- |
| `flutter analyze` | 指摘なし |
| `flutter test`(29件) | すべて成功。コア(配置・乱数の一致、パリィ判定、崩落、分身弾、ボスのフェーズ、決定性、全ウェーブの読み込み、ステージと星)、音の生成、アプリ全体(タイトル → エンドレス → 発射 → ポーズ → 再開、タッチ操作、ボス戦の失敗 → リザルト、ステージ選択、設定)、盤面の描画(OVERDRIVE 中のボス戦、崩落、ウェーブクリア) |
| 画面写真 | `test/app/screenshots/` に、テストで描いた画面の写真がある(作り直すには `flutter test test/app --dart-define=screenshots=true --update-goldens`) |
| Web ビルド | `flutter build web` が通る(開発中に Chrome で確認するためだけに使う。ストアには出さない。音とランキングは無効) |

### 実行のしかた

```sh
cd app
flutter pub get
flutter run                 # 接続した端末 / シミュレーターで起動
flutter test                # テスト
flutter build ipa --release # iOS (要: 署名の設定、第9章)
flutter build appbundle     # Android (要: key.properties、第9章)
```

## 9. ストア公開までの手順

掲載文・スクリーンショット・審査メモなど、App Store Connect に入力する内容は [app-store.md](app-store.md) にまとめた。Google Play Console に入力する内容は [play-store.md](play-store.md) にまとめた。

### 9.1 アプリ側で設定済みのもの

| 項目 | 設定 |
| --- | --- |
| バンドル ID | `com.watsuwo.parrybreak`(iOS / Android 共通。旧 WebView 版の `com.watsuwo.ricochet` は App Store に登録していなかったため、アプリ名に合わせて変えた) |
| 画面 | 横画面固定・全画面・ステータスバー非表示・120Hz(`CADisableMinimumFrameDurationOnPhone`) |
| 言語 | `Info.plist` の `CFBundleLocalizations` に en / ja。これがないと App Store で対応言語が英語だけになる |
| 暗号化 | `ITSAppUsesNonExemptEncryption = false`(輸出コンプライアンスの質問が出ない) |
| Game Center | `ios/Runner/Runner.entitlements`(`com.apple.developer.game-center`)を Runner の全構成に設定済み |
| ランキング | `LeaderboardConfig.iosEnabled = true`。ID は `com.watsuwo.parrybreak.endless_score` / `.endless_wave` / `.stages_total`。Android は `androidEnabled = false` のまま |
| アイコン・起動画面 | `branding/icons/` の画像から `dart run flutter_launcher_icons`、`dart run flutter_native_splash:create` で作り直せる |
| ポリシー・サポート | 別のリポジトリ `watsuwo/watsuwo.github.io` の `parry-break/privacy.html` と `parry-break/support.html` を GitHub Pages で公開している(https://watsuwo.github.io/parry-break/privacy と https://watsuwo.github.io/parry-break/support)。広告(AdMob)の `app-ads.txt` も同じリポジトリにある |

### 9.2 iOS の公開手順

1. **署名**: Xcode → Settings → Accounts に Apple ID を追加する。`app/ios/Runner.xcworkspace` を開き、Runner → Signing & Capabilities で Team を選ぶ。自動署名で Bundle ID が登録され、Game Center も有効になる。
2. **App Store Connect** → マイ App → 新規 App。プラットフォーム iOS、名前 PARRY BREAK、プライマリ言語は日本語、バンドル ID `com.watsuwo.parrybreak`、SKU `parrybreak`。
3. **Game Center**: リーダーボードを3つ作る(クラシック、整数、大きいほど上位、名前は日本語と英語)。ID は 9.1 の表のとおり。一度作った ID は削除しても使い回せない。バージョンのページの Game Center 欄で、3つをこのバージョンに含める。

   | ID | 内容 | 名前 |
   | --- | --- | --- |
   | `com.watsuwo.parrybreak.endless_score` | エンドレスの最終スコア | エンドレス: スコア / Endless: Score |
   | `com.watsuwo.parrybreak.endless_wave` | エンドレスの到達ウェーブ | エンドレス: 到達ウェーブ / Endless: Wave |
   | `com.watsuwo.parrybreak.stages_total` | 全ステージの最高スコアの合計 | ステージ: 合計スコア / Stages: Total Score |

4. **ビルドとアップロード**: `cd app && flutter build ipa --release`。できた `build/ios/archive/Runner.xcarchive` を Xcode の Organizer で開き、Distribute App → App Store Connect でアップロードする。2回目以降は `pubspec.yaml` の `version` のビルド番号(`+` の後ろ)を上げる。
5. **TestFlight**: 実機で、操作感・判定・音・振動・Game Center(サインイン、スコアの送信、ランキング画面)を確かめる。トラッキング許可のダイアログは最初の起動で出る(AdMob で IDFA の説明メッセージを作ってある場合)。広告は最初の起動から24時間たつまで出ない(9.3)。
6. **審査に出す**: [app-store.md](app-store.md) の内容(App のプライバシーでの広告の申告を含む)を入力し、スクリーンショットを載せて提出する。

### 9.3 広告の設定

広告の処理は `lib/services/ads.dart` にある。

**出すタイミング**: 結果画面の TITLE / STAGE SELECT で戻るときだけ出す。RETRY・NEXT STAGE・ポーズ中のメニュー・プレイ中には出さない。デバッグモードのプレイの後にも出さない。

**頻度の制限**(`InterstitialPolicy`)

| 制限 | 値 |
| --- | --- |
| 最初の起動からの猶予 | 24時間。この間は広告を出さない(読み込みもしない)。同意の画面(ATT・EU の同意)は猶予に関係なく最初の起動で出す。審査でトラッキング許可のダイアログを確かめられるようにするため。デバッグビルドでは猶予なし |
| 前回からの間隔 | 3分以上 |
| 1日の上限 | 8回 |

**リリース前の作業**

1. AdMob でアプリ(iOS / Android)とインタースティシャルの広告ユニットを作る。
2. テスト用の ID を本番の ID に置き換える: `AdsConfig` の広告ユニット ID、`ios/Runner/Info.plist` の `GADApplicationIdentifier`、`android/app/src/main/AndroidManifest.xml` の `com.google.android.gms.ads.APPLICATION_ID`。**iOS は置き換え済み**(アプリ `ca-app-pub-4435922675604695~8150605646`、インタースティシャル `ca-app-pub-4435922675604695/2281923603`)。Android は未登録でテスト用のまま。デバッグビルドでは、本番の ID があってもテスト用の広告ユニットを使う。
3. AdMob の「プライバシーとメッセージ」で、EU 向けの同意メッセージと、iOS の IDFA の説明メッセージを作る(起動時の同意の流れの中で ATT の許可ダイアログが出る)。
4. `Info.plist` の `SKAdNetworkItems` に、Google が公開している一覧を入れる(いまは Google のものだけ)。`NSUserTrackingUsageDescription` は英語だけなので、必要なら日本語化する。
5. App Store Connect の「App のプライバシー」と、Google Play の「データ セーフティ」に広告の利用を書く。

広告を止めるときは `AdsConfig.enabled` を `false` にする。

### 9.4 Android

- **ランキング**: Google Play Console で Play Games サービスを設定し、リーダーボードを3つ作る。リーダーボード ID を `LeaderboardConfig.android` に、プロジェクト ID を `android/app/src/main/res/values/games-ids.xml` の `app_id` に書き、`LeaderboardConfig.androidEnabled` を `true` にする。設定するまで、Android ではランキングのボタンが出ず、スコアも送らない。
- **署名**: アップロード鍵を作り、`app/android/key.properties`(git には入れない)に `storeFile` / `storePassword` / `keyAlias` / `keyPassword` を書く。ない場合はデバッグ鍵で署名される。

## 10. 残作業

| 項目 | 内容 |
| --- | --- |
| 実機での確認 | iOS / Android の実機で、操作感・判定(キャリブレーション後)・音の遅延・振動・描画速度(OVERDRIVE 中や大崩落)を確認する。画質「低」との差も見る |
| ストアの設定 | 第9章。iOS は 9.2 の手順(署名・App Store Connect・リーダーボード・スクリーンショット)が残っている。Android は 9.4 |
| iPad のレイアウト | 4:3 では上下に余白が出る。HUD を盤面の外に出す配置は未対応 |
| 音の共存 | iOS で他アプリの音楽を流しながら遊ぶ設定は未対応(オーディオセッションの設定が必要) |
| ゲームパッド | 入力は抽象化済み。ゲームパッドの読み取りは未実装 |
| 広告 | 本番 ID への置き換えなどのリリース前の作業(9.3)。リワード広告とボス練習モード |
| `legacy/` の削除 | 移植元のブラウザ版。配置の一致テストのゴールデンデータは書き出し済みなので、削除してよい(`tools/dump_layouts.mjs` も不要になる) |

