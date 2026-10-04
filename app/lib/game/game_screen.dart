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
import '../render/glow.dart';
import '../render/palette.dart';
import '../render/text_cache.dart';
import '../services/content.dart';
import '../services/leaderboard.dart';
import '../services/records.dart';
import '../services/settings.dart';
import '../ui/arcade.dart';
import '../ui/settings_screen.dart';
import '../ui/widgets.dart';
import 'game_controller.dart';
import 'result_overlay.dart';

/// プレイ画面。[stage] があればステージモード、なければエンドレス。
class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({super.key, this.stage});
  final StageDef? stage;

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
  GlowSprite? _glow;
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
      reduceEffects: settings.reduceEffects,
      timeSource: ref.read(timeSourceProvider),
    )..onFinished = _onFinished;
    GameScreen.debugLastController = _ctl;
    _ctl.addListener(_onControllerChange);
    _applySettings(settings);
    _ctl.start();
    _glow = settings.quality == GraphicsQuality.high ? GlowSprite.create() : null;
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
    if (stage == null) {
      final newBest = records.submitEndless(score: w.score, wave: w.wave.number, stats: w.stats);
      lb.submit(Board.endlessScore, w.score);
      lb.submit(Board.endlessWave, w.wave.number);
      _outcome = _Outcome(newBest: newBest);
    } else {
      final cleared = w.phase == WorldPhase.completed;
      final result = StageResult(cleared: cleared, score: w.score, stats: w.stats);
      final stars = stage.evaluate(result);
      final newBest = records.submitStage(stage.id, result, stars);
      if (cleared) {
        final total = ref.read(recordsProvider).stages.values.fold(0, (s, r) => s + r.bestScore);
        lb.submit(Board.stagesTotal, total);
      }
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

  StageDef? get _nextStage {
    final stage = widget.stage;
    if (stage == null) return null;
    final c = ref.read(contentProvider).campaign;
    final all = c.stages.toList();
    final i = all.indexOf(stage);
    if (i < 0 || i + 1 >= all.length) return null;
    final next = all[i + 1];
    return ref.read(recordsProvider).isUnlocked(c, next) ? next : null;
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(fadeRoute(const SettingsScreen()));
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
      glow: _glow,
      blockPainters: _blockPainters,
      l10n: l,
      highQuality: settings.quality == GraphicsQuality.high,
      repaint: _ctl.frame,
    );
    return Scaffold(
      backgroundColor: const Color(0xFF030208),
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: LayoutBuilder(builder: (context, c) {
          final layout = FieldLayout.compute(c.biggest, MediaQuery.paddingOf(context));
          final rail = settings.controls != ControlScheme.zones;
          return Stack(children: [
            Positioned.fill(child: TouchInput(controller: _ctl, layout: layout, settings: settings)),
            Positioned.fromRect(rect: layout.field, child: IgnorePointer(child: _field(settings))),
            // 左の余白: 移動
            Positioned.fromRect(
              rect: layout.left,
              child: SafeArea(
                right: false,
                child: rail
                    ? RailControl(controller: _ctl, vertical: settings.controls == ControlScheme.railVertical)
                    : const Align(alignment: Alignment(0, 0.55), child: MoveHint()),
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
                  child: ParryButton(controller: _ctl, interactive: rail, size: (layout.right.width * 0.6).clamp(56, 84)),
                ),
              ),
            ),
            Positioned(
              right: 0,
              top: 0,
              child: SafeArea(
                left: false,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: _RoundIcon(icon: Icons.pause, onTap: _ctl.finished ? null : _ctl.pause, label: l.paused),
                ),
              ),
            ),
            if (_ctl.paused && !_ctl.finished) Positioned.fill(child: _pauseOverlay(l)),
            if (_ctl.finished) Positioned.fill(child: _resultOverlay()),
          ]);
        }),
      ),
    );
  }

  Widget _field(Settings settings) {
    final paint = RepaintBoundary(child: CustomPaint(painter: _painter, size: Size.infinite));
    return ValueListenableBuilder(
      valueListenable: _ctl.frame,
      builder: (_, _, child) {
        final w = _ctl.world;
        final invert = w.od && w.phase == WorldPhase.playing && !settings.reduceEffects && !_ctl.paused;
        // OVERDRIVE 中は画面の色を反転する (ブラウザ版の invert(1) hue-rotate(180deg))
        return invert ? ColorFiltered(colorFilter: _odInvert, child: child) : child!;
      },
      child: paint,
    );
  }

  static const _odInvert = ColorFilter.matrix([
    0.574, -1.43, -0.144, 0, 255, //
    -0.426, -0.43, -0.144, 0, 255,
    -0.426, -1.43, 0.856, 0, 255,
    0, 0, 0, 1, 0,
  ]);

  Widget _pauseOverlay(AppLocalizations l) {
    final rc = _ctl.resumeCountdown;
    return Stack(fit: StackFit.expand, children: [
      const ColoredBox(color: Color(0xCC05040F)),
      const Scanlines(),
      Center(
        child: rc != null
            ? ChromaticTitle('${rc.ceil()}', size: 96, color: Palette.cyan)
            : SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const ChromaticTitle('PAUSED', size: 56, color: Palette.cyan),
                  const SizedBox(height: 30),
                  Wrap(spacing: 14, runSpacing: 12, alignment: WrapAlignment.center, children: [
                    SlashButton(label: 'RESUME', primary: true, icon: Icons.play_arrow, onPressed: _ctl.requestResume),
                    SlashButton(label: 'RETRY', icon: Icons.replay, onPressed: _retry),
                    SlashButton(label: 'SETTINGS', icon: Icons.tune, onPressed: _openSettings),
                    SlashButton(label: 'TITLE', color: Palette.magenta, icon: Icons.home, onPressed: _toTitle),
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
        bestScore: stage == null ? records.endless.bestScore : records.stage(stage.id).bestScore,
        bestWave: records.endless.bestWave,
        stage: stage,
        cleared: cleared,
        achieved: o?.stars,
      ),
      reduceMotion: ref.read(settingsProvider).reduceEffects || MediaQuery.disableAnimationsOf(context),
      onNewRecord: () => _ctl.audio.play('ricochet'),
      onRetry: _retry,
      onTitle: _toTitle,
      onNext: next == null ? null : () => Navigator.of(context).pushReplacement(fadeRoute(GameScreen(stage: next))),
      onStageSelect: stage == null ? null : () => Navigator.of(context).pop(),
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
          Icon(achieved ? Icons.star : Icons.star_border, color: achieved ? Palette.yellow : Palette.gray, size: 24),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: achieved ? Palette.white : Palette.gray, fontSize: 15))),
        ]),
      );
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.onTap, required this.label});
  final IconData icon;
  final VoidCallback? onTap;
  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF0B1523),
              border: Border.all(color: Palette.cyan),
              boxShadow: [BoxShadow(color: withAlpha(Palette.cyan, 0.35), blurRadius: 12)],
            ),
            child: Icon(icon, color: const Color(0xFFA8FFFF)),
          ),
        ),
      );
}
