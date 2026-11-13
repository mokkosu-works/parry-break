import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../core/core.dart';
import '../input/touch_controls.dart';
import '../l10n/app_localizations.dart';
import '../render/block_painters.dart';
import '../render/field_painter.dart';
import '../render/palette.dart';
import '../render/pixel.dart';
import '../render/text_cache.dart';
import '../services/ads.dart';
import '../services/content.dart';
import '../services/history.dart';
import '../services/leaderboard.dart';
import '../services/records.dart';
import '../services/review.dart';
import '../services/settings.dart';
import '../ui/settings_screen.dart';
import '../ui/arcade.dart';
import '../ui/widgets.dart';
import 'game_controller.dart';
import 'result_overlay.dart';
import '../ui/pixel_icons.dart';

/// プレイ画面。[stage] があればステージモード、なければエンドレス (エンドレスは常に NORMAL)。
/// [practice] なら練習場 (記録・ランキング・履歴・広告の回数・評価の依頼に数えない)。
class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({
    super.key,
    this.stage,
    this.difficulty = Difficulty.normal,
    this.practice = false,
  });
  final StageDef? stage;
  final Difficulty difficulty;
  final bool practice;

  /// 最後に作られたプレイの進行役 (テストから状態を確かめるため)。
  @visibleForTesting
  static GameController? debugLastController;

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

/// プレイの結果 (オーバーレイの表示用)。
class _Outcome {
  const _Outcome({required this.newBest, this.stars, this.cleared = false});
  final bool newBest, cleared;
  final List<bool>? stars;
}

class _GameScreenState extends ConsumerState<GameScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final GameController _ctl;
  late final Ticker _ticker;
  final TextCache _text = TextCache();
  final BlockPainterRegistry _blockPainters = BlockPainterRegistry();
  final FocusNode _focus = FocusNode();
  FieldPainter? _painter;
  _Outcome? _outcome;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    final content = ref.read(contentProvider);
    final stage = widget.stage;
    _ctl = GameController(
      mode: widget.practice
          ? PracticeMode()
          : stage != null
          ? StageMode(stage)
          : EndlessMode(content.endless),
      audio: ref.read(audioProvider),
      haptics: ref.read(hapticsProvider),
      inputLag: settings.timingOffsetMs / 1000,
      difficulty: stage != null ? widget.difficulty : Difficulty.normal,
      reduceEffects: settings.reduceEffects,
      showTiming: settings.showTiming,
      timeSource: ref.read(timeSourceProvider),
    )..onFinished = _onFinished;
    GameScreen.debugLastController = _ctl;
    _ctl.addListener(_onControllerChange);
    _ctl.audio.enterGame();
    _applySettings(settings);
    _ctl.start();
    _ticker = createTicker((_) {
      _keyboardAxis();
      _ctl.tick();
    })..start();
    WidgetsBinding.instance.addObserver(this);
    // 前の画面のボタンにキーボードのフォーカスが残らないようにする (Space で押されてしまう)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _ctl.removeListener(_onControllerChange);
    _ctl.dispose();
    _ctl.audio.leaveGame();
    _text.clear();
    _focus.dispose();
    super.dispose();
  }

  bool _wasPaused = false;

  void _onControllerChange() {
    // ポーズするたびに、キーボードで選ぶボタンを RESUME に戻す
    if (_ctl.paused && !_wasPaused) _pauseIndex = 0;
    _wasPaused = _ctl.paused;
    setState(() {});
  }

  /// アプリが隠れたら自動でポーズする。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _ctl.pause();
  }

  void _applySettings(Settings s) {
    _ctl.setInputLag(s.timingOffsetMs / 1000);
    _ctl.audio.setVolumes(bgm: s.bgmVolume, sfx: s.sfxVolume);
  }

  // ---- 結果の記録 ---------------------------------------------------------

  void _onFinished(World w) {
    // 練習場はゲームオーバーにならないが、念のため何にも数えない
    if (widget.practice) return;
    final records = ref.read(recordsProvider.notifier);
    final lb = ref.read(leaderboardProvider);
    final stage = widget.stage;
    if (ref.read(debugModeProvider)) {
      // デバッグモードのプレイは記録にもランキングにも残さない
      final cleared = stage != null && w.phase == WorldPhase.completed;
      final stars = stage?.evaluate(
        StageResult(cleared: cleared, score: w.score, stats: w.stats),
      );
      _outcome = _Outcome(newBest: false, stars: stars, cleared: cleared);
      return;
    }
    // 結果画面を見ている間に、戻るときの広告を読み込んでおく
    ref.read(adsProvider).onResult();
    if (stage == null) {
      final newBest = records.submitEndless(
        score: w.score,
        round: w.round.number,
        stats: w.stats,
      );
      ref
          .read(historyProvider.notifier)
          .addEndless(score: w.score, round: w.round.number);
      lb.submit(Board.endlessScore, w.score);
      lb.submit(Board.endlessRound, w.round.number);
      _outcome = _Outcome(newBest: newBest);
    } else {
      final cleared = w.phase == WorldPhase.completed;
      final result = StageResult(
        cleared: cleared,
        score: w.score,
        stats: w.stats,
      );
      final stars = stage.evaluate(result);
      final newBest = records.submitStage(
        stage.id,
        result,
        stars,
        difficulty: widget.difficulty,
      );
      ref
          .read(historyProvider.notifier)
          .addStage(
            stage.id,
            score: w.score,
            cleared: cleared,
            difficulty: widget.difficulty,
          );
      if (cleared) {
        lb.submit(Board.stagesTotal, ref.read(recordsProvider).stagesTotal);
      }
      _outcome = _Outcome(newBest: newBest, stars: stars, cleared: cleared);
    }
  }

  // ---- 操作 ---------------------------------------------------------------

  void _keyboardAxis() {
    final k = HardwareKeyboard.instance;
    var axis = 0.0;
    if (k.isLogicalKeyPressed(LogicalKeyboardKey.arrowLeft) ||
        k.isLogicalKeyPressed(LogicalKeyboardKey.keyA)) {
      axis -= 1;
    }
    if (k.isLogicalKeyPressed(LogicalKeyboardKey.arrowRight) ||
        k.isLogicalKeyPressed(LogicalKeyboardKey.keyD)) {
      axis += 1;
    }
    final input = _ctl.world.input;
    if (axis != 0) input.useTarget = false;
    input.axis = axis;
  }

  /// ポーズ中にキーボードで選んでいるボタン ([_pauseActions] の順)。
  int _pauseIndex = 0;

  /// ポーズのボタン。RESUME / RETRY / SETTINGS / TITLE、練習場は RESUME / 速さ / 練習の対象 / SETTINGS / TITLE。
  List<VoidCallback> get _pauseActions => [
    _ctl.requestResume,
    if (widget.practice) ...[_cycleSpeed, _toggleBullets] else _retry,
    _openSettings,
    _toTitle,
  ];

  PracticeMode? get _practice => _ctl.world.practice;

  /// 練習場のボールの速さを 段階 1 → 段階 3 → FEVER TIME → 段階 1 と切り替える。
  void _cycleSpeed() {
    final p = _practice;
    if (p == null) return;
    const all = PracticeSpeed.values;
    setState(
      () => _ctl.world.setPractice(
        speed: all[(p.speed.index + 1) % all.length],
        bullets: p.bullets,
      ),
    );
  }

  /// 練習場の対象を、ボールと敵弾の撃ち返しで切り替える。
  void _toggleBullets() {
    final p = _practice;
    if (p == null) return;
    setState(() => _ctl.world.setPractice(speed: p.speed, bullets: !p.bullets));
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    // 結果画面のキーは ResultOverlay が受ける
    if (_ctl.finished) return KeyEventResult.ignored;
    final key = e.logicalKey;
    final menu = _ctl.paused && _ctl.resumeCountdown == null;
    if (menu) {
      if (arrowStep(key) case final step?) {
        final n = _pauseActions.length;
        setState(() => _pauseIndex = (_pauseIndex + step + n) % n);
        return KeyEventResult.handled;
      }
      if (isConfirmKey(key)) {
        _pauseActions[_pauseIndex]();
        return KeyEventResult.handled;
      }
    }
    if (isConfirmKey(key)) {
      if (!_ctl.paused) _ctl.press(e.timeStamp);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.keyP) {
      _ctl.paused ? _ctl.requestResume() : _ctl.pause();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// リトライのたびに増やす (結果画面の演出を最初から出すため)。
  int _runId = 0;

  void _retry() {
    _outcome = null;
    _runId++;
    _ctl.start();
    // 結果画面がキーボードのフォーカスを持っていたので、盤面に戻す
    _focus.requestFocus();
  }

  void _toTitle() => Navigator.of(context).popUntil((r) => r.isFirst);

  bool _leaving = false;

  /// 結果画面からタイトルやステージ選択へ戻る。広告を出してよければ出してから戻る
  /// (すぐ次を遊ぶリトライ・次のステージでは出さない)。
  Future<void> _leaveResult(VoidCallback go) async {
    if (_leaving) return;
    _leaving = true;
    // デバッグモードのプレイでは出さない (開発者が本番の広告を表示・クリックしないように)
    if (!ref.read(debugModeProvider)) {
      _ctl.audio.setPaused(true);
      try {
        // ステージを星 3 つでクリアして戻るときは、評価の依頼を出す (出したときは、続けて広告は出さない)
        if (!await _askReview()) {
          await ref.read(adsProvider).showInterstitialIfDue();
        }
      } on Object catch (e) {
        // 広告や評価の依頼でつまずいても、結果画面に閉じ込めない
        debugPrint('leave result failed: $e');
      } finally {
        _ctl.audio.setPaused(false);
      }
    }
    if (mounted) go();
  }

  /// 星 3 つでクリアしたあとなら、ストアの評価の依頼を出す。出したら true。
  Future<bool> _askReview() {
    final stars = _outcome?.stars;
    if (stars == null || !stars.every((s) => s)) return Future.value(false);
    final records = ref.read(recordsProvider);
    final cleared = ref
        .read(contentProvider)
        .campaign
        .stages
        .where((s) => records.clearedAny(s.id))
        .length;
    return ref.read(reviewProvider).askIfDue(clearedStages: cleared);
  }

  StageDef? get _nextStage {
    final stage = widget.stage;
    if (stage == null) return null;
    final c = ref.read(contentProvider).campaign;
    final all = c.stages.toList();
    final i = all.indexOf(stage);
    if (i < 0 || i + 1 >= all.length) return null;
    final next = all[i + 1];
    return ref.read(debugModeProvider) ||
            ref.read(recordsProvider).isUnlocked(c, next)
        ? next
        : null;
  }

  /// 戻るボタン (Android)。プレイ中はポーズ、ポーズ中は再開のカウントダウン (カウントダウン中は何もしない)、
  /// 結果画面は TITLE (エンドレス) / STAGES (ステージ) と同じく、広告・評価の依頼の判定を通って戻る。
  void _onBack() {
    if (_ctl.finished) {
      _leaveResult(
        widget.stage == null ? _toTitle : () => Navigator.of(context).pop(),
      );
    } else if (!_ctl.paused) {
      _ctl.pause();
    } else if (_ctl.resumeCountdown == null) {
      _ctl.requestResume();
    }
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(fadeRoute<void>(const SettingsScreen()));
    if (mounted) _applySettings(ref.read(settingsProvider));
  }

  // ---- 表示 ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final settings = ref.watch(settingsProvider);
    // 盤面のフラッシュ・揺れ・点滅は、アプリの「演出を控えめにする」か、端末の動きを減らす設定
    // (iOS の「視差効果を減らす」、Android の「アニメーションを削除」) のどちらかで控えめにする。
    // どちらも変われば build し直されるので、遊んでいる途中の変更も反映される
    _ctl.fx.reduceEffects =
        settings.reduceEffects || MediaQuery.disableAnimationsOf(context);
    _ctl.fx.showTiming = settings.showTiming;
    // ポーズ中に設定で言語・画質を変えたら、盤面の描画役を作り直す
    if (_painter case final p?
        when p.l10n.localeName != l.localeName ||
            p.highQuality != (settings.quality == GraphicsQuality.high)) {
      _painter = null;
    }
    _painter ??= FieldPainter(
      world: _ctl.world,
      fx: _ctl.fx,
      alpha: () => _ctl.session.alpha,
      time: () => _ctl.clock.now,
      text: _text,
      blockPainters: _blockPainters,
      l10n: l,
      highQuality: settings.quality == GraphicsQuality.high,
      repaint: _ctl.frame,
    );
    _painter!.parryButton = settings.controls != ControlScheme.zones;
    return PopScope(
      // 戻るボタン (Android) で画面を閉じず、ポーズや結果画面のボタンと同じ処理にする (_onBack)
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        backgroundColor: Dot.ink,
        body: Focus(
          focusNode: _focus,
          autofocus: true,
          onKeyEvent: _onKey,
          child: LayoutBuilder(
            builder: (context, c) {
              final rail = settings.controls != ControlScheme.zones;
              final layout = FieldLayout.compute(
                c.biggest,
                MediaQuery.paddingOf(context),
                rail: rail,
              );
              return Stack(
                children: [
                  Positioned.fill(
                    child: TouchInput(
                      controller: _ctl,
                      layout: layout,
                      settings: settings,
                    ),
                  ),
                  Positioned.fromRect(
                    rect: layout.field,
                    child: IgnorePointer(child: _field()),
                  ),
                  // レール方式だけ、左右の余白に操作を置く (領域方式は画面の左右半分をタッチするので置かない)
                  if (rail) ...[
                    // 左の余白: 移動
                    Positioned.fromRect(
                      rect: layout.left,
                      child: SafeArea(
                        right: false,
                        child: RailControl(
                          controller: _ctl,
                          vertical:
                              settings.controls == ControlScheme.railVertical,
                          sensitivity: settings.railSensitivity,
                        ),
                      ),
                    ),
                    // 右の余白: パリィ
                    Positioned(
                      left: layout.right.left,
                      width: layout.right.width,
                      bottom: 0,
                      height: c.maxHeight * 0.55,
                      child: SafeArea(
                        left: false,
                        child: Center(
                          child: ParryButton(
                            controller: _ctl,
                            size: (layout.right.width * 0.6).clamp(56, 84),
                          ),
                        ),
                      ),
                    ),
                  ],
                  // ポーズ: HUD の右端 (見た目は小さく、押せる範囲は 44pt 以上にする)
                  Positioned.fromRect(
                    rect: _hitRect(layout.toScreen(FieldPainter.pauseButton)),
                    child: _PauseButton(
                      size: FieldPainter.pauseButton.width * layout.scale,
                      dot: Dot.px * layout.scale,
                      onTap: _ctl.finished ? null : _ctl.pause,
                      label: l.pauseGame,
                    ),
                  ),
                  if (_ctl.paused && !_ctl.finished)
                    Positioned.fill(child: _pauseOverlay(l)),
                  if (_ctl.finished) Positioned.fill(child: _resultOverlay()),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  static Rect _hitRect(Rect r) {
    const min = 44.0;
    return Rect.fromCenter(
      center: r.center,
      width: math.max(min, r.width),
      height: math.max(min, r.height),
    );
  }

  /// 盤面。FEVER TIME の見せ方 (色の入れ替えと電飾) は FieldPainter が描く。
  Widget _field() => RepaintBoundary(
    child: CustomPaint(painter: _painter, size: Size.infinite),
  );

  Widget _pauseOverlay(AppLocalizations l) {
    final rc = _ctl.resumeCountdown;
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: withAlpha(Dot.ink, 0.8)),
        Center(
          child: rc != null
              ? PixelTitle(
                  '${rc.ceil()}',
                  size: 96,
                  color: Palette.yellow,
                  shadow: Dot.brick,
                )
              : SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const PixelTitle(
                        'PAUSED',
                        size: 56,
                        color: Palette.yellow,
                        shadow: Dot.brick,
                      ),
                      const SizedBox(height: 30),
                      Wrap(
                        spacing: 14,
                        runSpacing: 12,
                        alignment: WrapAlignment.center,
                        children: [
                          PixelButton(
                            label: 'RESUME',
                            filled: true,
                            icon: PixelIcons.play,
                            selected: _pauseIndex == 0,
                            onPressed: _ctl.requestResume,
                          ),
                          for (final (i, b) in _pauseButtons().indexed)
                            PixelButton(
                              label: b.label,
                              color: b.color,
                              icon: b.icon,
                              selected: _pauseIndex == i + 1,
                              onPressed: _pauseActions[i + 1],
                            ),
                        ],
                      ),
                      if (_practice != null) ...[
                        const SizedBox(height: 20),
                        Text(
                          l.practiceHelp,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Palette.gray,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  /// ポーズの RESUME の後に並べるボタン ([_pauseActions] と同じ順)。
  List<({String label, DotSprite icon, Color? color})> _pauseButtons() {
    final p = _practice;
    return [
      if (p != null) ...[
        (
          label: 'SPEED ${practiceSpeedLabel(p.speed)}',
          icon: PixelIcons.skipNext,
          color: null,
        ),
        (
          label: p.bullets ? 'MODE BULLETS' : 'MODE BALL',
          icon: PixelIcons.swap,
          color: null,
        ),
      ] else
        (label: 'RETRY', icon: PixelIcons.replay, color: null),
      (label: 'SETTINGS', icon: PixelIcons.tune, color: null),
      (label: 'TITLE', icon: PixelIcons.home, color: Palette.gray),
    ];
  }

  Widget _resultOverlay() {
    final w = _ctl.world, o = _outcome, stage = widget.stage;
    final records = ref.read(recordsProvider);
    final cleared = o?.cleared ?? false;
    final next = cleared ? _nextStage : null;
    return ResultOverlay(
      key: ValueKey(_runId),
      data: ResultData(
        score: w.score,
        round: w.round.number,
        maxChain: w.maxStreak,
        stats: w.stats,
        reason: w.overReason,
        newBest: o?.newBest ?? false,
        bestScore: stage == null
            ? records.endless.bestScore
            : records.stage(stage.id, widget.difficulty).bestScore,
        bestRound: records.endless.bestRound,
        stage: stage,
        difficulty: widget.difficulty,
        cleared: cleared,
        achieved: o?.stars,
        rank: stage == null
            ? RankTable.standard.endless(score: w.score, round: w.round.number)
            : cleared && o?.stars != null
            ? RankTable.standard.stage(
                stage,
                StageResult(cleared: true, score: w.score, stats: w.stats),
                o!.stars!,
              )
            : null,
        over: w.overInfo,
      ),
      reduceMotion:
          ref.read(settingsProvider).reduceEffects ||
          MediaQuery.disableAnimationsOf(context),
      onNewRecord: () => _ctl.audio.play('ricochet'),
      onRetry: _retry,
      onTitle: () => _leaveResult(_toTitle),
      onNext: next == null
          ? null
          : () => Navigator.of(context).pushReplacement(
              fadeRoute<void>(
                GameScreen(stage: next, difficulty: widget.difficulty),
              ),
            ),
      onStageSelect: stage == null
          ? null
          : () => _leaveResult(() => Navigator.of(context).pop()),
    );
  }
}

class StarLine extends StatelessWidget {
  const StarLine({super.key, required this.achieved, required this.text});
  final bool achieved;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        PixelStar(got: achieved, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: achieved ? Palette.white : Palette.gray,
              fontSize: 15,
            ),
          ),
        ),
      ],
    ),
  );
}

/// HUD の右端のポーズボタン。HUD の線の色の 1 ドットの枠だけを描く (FEVER TIME で HUD の色が変わっても馴染むよう、塗らない)。
class _PauseButton extends StatelessWidget {
  const _PauseButton({
    required this.size,
    required this.dot,
    required this.onTap,
    required this.label,
  });

  /// 見た目の大きさと、1 ドットの大きさ (画面の px)。
  final double size, dot;
  final VoidCallback? onTap;
  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Center(
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(
              color: Palette.hudLine,
              width: dot.roundToDouble().clamp(1, 8),
            ),
          ),
          // スマホでもアイコンの 1 ドットが 2pt 以上になるようにする
          child: PixelIcon(
            PixelIcons.pause,
            size: math.max(size * 0.5, 14),
            color: Palette.hudLabel,
          ),
        ),
      ),
    ),
  );
}
