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
import '../services/leaderboard.dart';
import '../services/records.dart';
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

  void _onControllerChange() => setState(() {});

  /// アプリが隠れたら自動でポーズする。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _ctl.pause();
  }

  void _applySettings(Settings s) {
    _ctl
      ..setInputLag(s.timingOffsetMs / 1000)
      ..fx.reduceEffects = s.reduceEffects;
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
      final newBest = records.submitEndless(score: w.score, wave: w.wave.number, stats: w.stats);
      lb.submit(Board.endlessScore, w.score);
      lb.submit(Board.endlessWave, w.wave.number);
      _outcome = _Outcome(newBest: newBest);
    } else {
      final cleared = w.phase == WorldPhase.completed;
      final result = StageResult(cleared: cleared, score: w.score, stats: w.stats);
      final stars = stage.evaluate(result);
      final newBest = records.submitStage(stage.id, result, stars, difficulty: widget.difficulty);
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

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final key = e.logicalKey;
    if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.enter) {
      if (_ctl.paused) {
        _ctl.requestResume();
      } else {
        _ctl.press(e.timeStamp);
      }
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
      await ref.read(adsProvider).showInterstitialIfDue();
      _ctl.audio.setPaused(false);
    }
    if (mounted) go();
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

  Future<void> _openSettings() async {
    await Navigator.of(context).push(fadeRoute<void>(const SettingsScreen()));
    if (mounted) _applySettings(ref.read(settingsProvider));
  }

  // ---- 表示 ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final settings = ref.watch(settingsProvider);
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
    return Scaffold(
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
                  child: RailControl(controller: _ctl, vertical: settings.controls == ControlScheme.railVertical),
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
                label: l.paused,
              ),
            ),
            if (_ctl.paused && !_ctl.finished) Positioned.fill(child: _pauseOverlay(l)),
            if (_ctl.finished) Positioned.fill(child: _resultOverlay()),
          ]);
        }),
      ),
    );
  }

  static Rect _hitRect(Rect r) {
    const min = 44.0;
    return Rect.fromCenter(center: r.center, width: math.max(min, r.width), height: math.max(min, r.height));
  }

  /// 盤面。OVERDRIVE の見せ方 (色の入れ替えと電飾) は FieldPainter が描く。
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
                    PixelButton(label: 'RESUME', filled: true, icon: PixelIcons.play, onPressed: _ctl.requestResume),
                    PixelButton(label: 'RETRY', icon: PixelIcons.replay, onPressed: _retry),
                    PixelButton(label: 'SETTINGS', icon: PixelIcons.tune, onPressed: _openSettings),
                    PixelButton(label: 'TITLE', color: Palette.gray, icon: PixelIcons.home, onPressed: _toTitle),
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
        wave: w.wave.number,
        maxChain: w.maxStreak,
        stats: w.stats,
        reason: w.overReason,
        newBest: o?.newBest ?? false,
        bestScore: stage == null ? records.endless.bestScore : records.stage(stage.id, widget.difficulty).bestScore,
        bestWave: records.endless.bestWave,
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

/// HUD の右端のポーズボタン。HUD の線の色の 1 ドットの枠だけを描く (OVERDRIVE で HUD の色が変わっても馴染むよう、塗らない)。
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
