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
class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({super.key, this.stage, this.difficulty = Difficulty.normal});
  final StageDef? stage;
  final Difficulty difficulty;

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

class _GameScreenState extends ConsumerState<GameScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
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
      mode: stage != null ? StageMode(stage) : EndlessMode(content.endless),
      audio: ref.read(audioProvider),
      haptics: ref.read(hapticsProvider),
      inputLag: settings.timingOffsetMs / 1000,
      difficulty: stage != null ? widget.difficulty : Difficulty.normal,
      reduceEffects: settings.reduceEffects,
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
    })
      ..start();
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
    final records = ref.read(recordsProvider.notifier);
    final lb = ref.read(leaderboardProvider);
    final stage = widget.stage;
    if (ref.read(debugModeProvider)) {
      // デバッグモードのプレイは記録にもランキングにも残さない
      final cleared = stage != null && w.phase == WorldPhase.completed;
      final stars = stage?.evaluate(StageResult(cleared: cleared, score: w.score, stats: w.stats));
      _outcome = _Outcome(newBest: false, stars: stars, cleared: cleared);
      return;
    }
    // 結果画面を見ている間に、戻るときの広告を読み込んでおく
    ref.read(adsProvider).onResult();
    if (stage == null) {
      final newBest = records.submitEndless(score: w.score, round: w.round.number, stats: w.stats);
      ref.read(historyProvider.notifier).addEndless(score: w.score, round: w.round.number);
      lb.submit(Board.endlessScore, w.score);
      lb.submit(Board.endlessRound, w.round.number);
      _outcome = _Outcome(newBest: newBest);
    } else {
      final cleared = w.phase == WorldPhase.completed;
      final result = StageResult(cleared: cleared, score: w.score, stats: w.stats);
      final stars = stage.evaluate(result);
      final newBest = records.submitStage(stage.id, result, stars, difficulty: widget.difficulty);
      ref.read(historyProvider.notifier)
          .addStage(stage.id, score: w.score, cleared: cleared, difficulty: widget.difficulty);
      if (cleared) lb.submit(Board.stagesTotal, ref.read(recordsProvider).stagesTotal);
      _outcome = _Outcome(newBest: newBest, stars: stars, cleared: cleared);
    }
  }

  // ---- 操作 ---------------------------------------------------------------

  void _keyboardAxis() {
    final k = HardwareKeyboard.instance;
    var axis = 0.0;
    if (k.isLogicalKeyPressed(LogicalKeyboardKey.arrowLeft) || k.isLogicalKeyPressed(LogicalKeyboardKey.keyA)) axis -= 1;
    if (k.isLogicalKeyPressed(LogicalKeyboardKey.arrowRight) || k.isLogicalKeyPressed(LogicalKeyboardKey.keyD)) axis += 1;
    final input = _ctl.world.input;
    if (axis != 0) input.useTarget = false;
    input.axis = axis;
  }

  /// ポーズ中にキーボードで選んでいるボタン (RESUME / RETRY / SETTINGS / TITLE の順)。
  int _pauseIndex = 0;

  List<VoidCallback> get _pauseActions => [_ctl.requestResume, _retry, _openSettings, _toTitle];

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
        if (!await _askReview()) await ref.read(adsProvider).showInterstitialIfDue();
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
    final cleared = ref.read(contentProvider).campaign.stages.where((s) => records.clearedAny(s.id)).length;
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
    return ref.read(debugModeProvider) || ref.read(recordsProvider).isUnlocked(c, next) ? next : null;
  }

  /// 戻るボタン (Android)。プレイ中はポーズ、ポーズ中は再開のカウントダウン (カウントダウン中は何もしない)、
  /// 結果画面は TITLE (エンドレス) / STAGES (ステージ) と同じく、広告・評価の依頼の判定を通って戻る。
  void _onBack() {
    if (_ctl.finished) {
      _leaveResult(widget.stage == null ? _toTitle : () => Navigator.of(context).pop());
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
    _ctl.fx.reduceEffects = settings.reduceEffects || MediaQuery.disableAnimationsOf(context);
    // ポーズ中に設定で言語・画質を変えたら、盤面の描画役を作り直す
    if (_painter case final p?
        when p.l10n.localeName != l.localeName || p.highQuality != (settings.quality == GraphicsQuality.high)) {
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
          child: LayoutBuilder(builder: (context, c) {
            final rail = settings.controls != ControlScheme.zones;
            final layout = FieldLayout.compute(c.biggest, MediaQuery.paddingOf(context), rail: rail);
            return Stack(children: [
              Positioned.fill(child: TouchInput(controller: _ctl, layout: layout, settings: settings)),
              Positioned.fromRect(rect: layout.field, child: IgnorePointer(child: _field())),
              // レール方式だけ、左右の余白に操作を置く (領域方式は画面の左右半分をタッチするので置かない)
              if (rail) ...[
                // 左の余白: 移動
                Positioned.fromRect(
                  rect: layout.left,
                  child: SafeArea(
                    right: false,
                    child: RailControl(controller: _ctl, vertical: settings.controls == ControlScheme.railVertical, sensitivity: settings.railSensitivity),
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
                      child: ParryButton(controller: _ctl, size: (layout.right.width * 0.6).clamp(56, 84)),
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
              if (_ctl.paused && !_ctl.finished) Positioned.fill(child: _pauseOverlay(l)),
              if (_ctl.finished) Positioned.fill(child: _resultOverlay()),
            ]);
          }),
        ),
      ),
    );
  }

  static Rect _hitRect(Rect r) {
    const min = 44.0;
    return Rect.fromCenter(center: r.center, width: math.max(min, r.width), height: math.max(min, r.height));
  }

  /// 盤面。FEVER TIME の見せ方 (色の入れ替えと電飾) は FieldPainter が描く。
  Widget _field() => RepaintBoundary(child: CustomPaint(painter: _painter, size: Size.infinite));

  Widget _pauseOverlay(AppLocalizations l) {
    final rc = _ctl.resumeCountdown;
    return Stack(fit: StackFit.expand, children: [
      ColoredBox(color: withAlpha(Dot.ink, 0.8)),
      Center(
        child: rc != null
            ? PixelTitle('${rc.ceil()}', size: 96, color: Palette.yellow, shadow: Dot.brick)
            : SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const PixelTitle('PAUSED', size: 56, color: Palette.yellow, shadow: Dot.brick),
                  const SizedBox(height: 30),
                  Wrap(spacing: 14, runSpacing: 12, alignment: WrapAlignment.center, children: [
                    PixelButton(
                        label: 'RESUME',
                        filled: true,
                        icon: PixelIcons.play,
                        selected: _pauseIndex == 0,
                        onPressed: _ctl.requestResume),
                    PixelButton(label: 'RETRY', icon: PixelIcons.replay, selected: _pauseIndex == 1, onPressed: _retry),
                    PixelButton(
                        label: 'SETTINGS', icon: PixelIcons.tune, selected: _pauseIndex == 2, onPressed: _openSettings),
                    PixelButton(
                        label: 'TITLE',
                        color: Palette.gray,
                        icon: PixelIcons.home,
                        selected: _pauseIndex == 3,
                        onPressed: _toTitle),
                  ]),
                ]),
              ),
      ),
    ]);
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
        bestScore: stage == null ? records.endless.bestScore : records.stage(stage.id, widget.difficulty).bestScore,
        bestRound: records.endless.bestRound,
        stage: stage,
        difficulty: widget.difficulty,
        cleared: cleared,
        achieved: o?.stars,
      ),
      reduceMotion: ref.read(settingsProvider).reduceEffects || MediaQuery.disableAnimationsOf(context),
      onNewRecord: () => _ctl.audio.play('ricochet'),
      onRetry: _retry,
      onTitle: () => _leaveResult(_toTitle),
      onNext: next == null
          ? null
          : () => Navigator.of(context).pushReplacement(fadeRoute<void>(GameScreen(stage: next, difficulty: widget.difficulty))),
      onStageSelect: stage == null ? null : () => _leaveResult(() => Navigator.of(context).pop()),
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
        child: Row(children: [
          PixelStar(got: achieved, size: 22),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: achieved ? Palette.white : Palette.gray, fontSize: 15))),
        ]),
      );
}

/// HUD の右端のポーズボタン。HUD の線の色の 1 ドットの枠だけを描く (FEVER TIME で HUD の色が変わっても馴染むよう、塗らない)。
class _PauseButton extends StatelessWidget {
  const _PauseButton({required this.size, required this.dot, required this.onTap, required this.label});

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
                border: Border.all(color: Palette.hudLine, width: dot.roundToDouble().clamp(1, 8)),
              ),
              // スマホでもアイコンの 1 ドットが 2pt 以上になるようにする
              child: PixelIcon(PixelIcons.pause, size: math.max(size * 0.5, 14), color: Palette.hudLabel),
            ),
          ),
        ),
      );
}
