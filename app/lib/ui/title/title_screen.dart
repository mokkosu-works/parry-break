import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../audio/audio_service.dart';
import '../../core/core.dart';
import '../../game/game_screen.dart';
import '../../l10n/app_localizations.dart';
import '../../render/palette.dart';
import '../../services/content.dart';
import '../../services/leaderboard.dart';
import '../../services/records.dart';
import '../../services/settings.dart';
import '../help_screen.dart';
import '../settings_screen.dart';
import '../stage_select_screen.dart';
import '../widgets.dart';
import 'attract_demo.dart';
import 'title_logo.dart';

class _MenuEntry {
  const _MenuEntry(this.label, this.action, {this.meta = '', this.primary = false});
  final String label, meta;
  final VoidCallback action;
  final bool primary;
}

/// タイトル画面: 奥で流れるデモプレイ、ロゴ、アーケード風の縦メニュー、ハイスコア。
class TitleScreen extends ConsumerStatefulWidget {
  const TitleScreen({super.key});

  @override
  ConsumerState<TitleScreen> createState() => _TitleScreenState();
}

class _TitleScreenState extends ConsumerState<TitleScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _intro =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1300));
  final FocusNode _focus = FocusNode();
  int _selected = 0;
  int? _firing;

  /// 版番号を続けてタップした回数と、最後のタップの時刻 (デバッグモードの切り替え用)。
  int _verTaps = 0;
  DateTime _lastVerTap = DateTime(0);

  @override
  void initState() {
    super.initState();
    _intro.forward();
    _audio.setMenuMusic(true);
  }

  // dispose では ref を読めないので、ここで握っておく
  late final AudioService _audio = ref.read(audioProvider);

  @override
  void dispose() {
    _audio.setMenuMusic(false);
    _intro.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _still => MediaQuery.disableAnimationsOf(context) || ref.read(settingsProvider).reduceEffects;

  List<_MenuEntry> _entries() {
    final records = ref.watch(recordsProvider);
    final content = ref.read(contentProvider);
    final lb = ref.read(leaderboardProvider);
    final nav = Navigator.of(context);
    final firstTime = records.endless.bestScore == 0 && records.stages.isEmpty;
    final stars = content.campaign.stages.fold(0, (s, st) => s + records.stage(st.id).starCount);
    final totalStars = content.campaign.stages.fold(0, (s, st) => s + st.stars.length);
    void push(Widget w) => nav.push(fadeRoute<void>(w));
    return [
      if (firstTime)
        _MenuEntry('START', () => push(GameScreen(stage: content.campaign.stages.first)),
            meta: 'TUTORIAL  1-1', primary: true),
      _MenuEntry('ENDLESS', () => push(const GameScreen()), meta: 'SCORE ATTACK', primary: !firstTime),
      _MenuEntry('STAGES', () => push(const StageSelectScreen()), meta: '$stars / $totalStars STARS'),
      _MenuEntry('HOW TO PLAY', () => push(const HelpScreen())),
      _MenuEntry('SETTINGS', () => push(const SettingsScreen())),
      if (lb.available)
        _MenuEntry('RANKING', () async {
          final ok = await lb.show();
          if (!ok && mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).rankingUnavailable)));
          }
        }),
    ];
  }

  Future<void> _activate(List<_MenuEntry> entries, int i) async {
    if (_firing != null) return;
    ref.read(audioProvider).play('launch');
    ref.read(hapticsProvider).selection();
    setState(() {
      _selected = i;
      _firing = i;
    });
    await Future<void>.delayed(const Duration(milliseconds: 140));
    if (!mounted) return;
    setState(() => _firing = null);
    entries[i].action();
  }

  void _tapVersion() {
    final now = DateTime.now();
    _verTaps = now.difference(_lastVerTap) < const Duration(milliseconds: 600) ? _verTaps + 1 : 1;
    _lastVerTap = now;
    if (_verTaps < 3) return;
    _verTaps = 0;
    final on = !ref.read(settingsProvider).debugMode;
    ref.read(settingsProvider.notifier).update((s) => s.copyWith(debugMode: on));
    ref.read(hapticsProvider).selection();
    final l = AppLocalizations.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(on ? l.debugModeOn : l.debugModeOff)));
  }

  void _select(int i) {
    if (i == _selected) return;
    ref.read(audioProvider).play('count');
    setState(() => _selected = i);
  }

  KeyEventResult _onKey(List<_MenuEntry> entries, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    switch (e.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        _select((_selected + 1) % entries.length);
      case LogicalKeyboardKey.arrowUp:
        _select((_selected - 1 + entries.length) % entries.length);
      case LogicalKeyboardKey.enter || LogicalKeyboardKey.space:
        _activate(entries, _selected);
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  /// [from]〜[to] (0〜1) の間に 0 → 1 になる、登場アニメーションの進み具合。
  double _stage(double from, double to) =>
      _still ? 1 : Curves.easeOutCubic.transform(((_intro.value - from) / (to - from)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    final entries = _entries();
    if (_selected >= entries.length) _selected = 0;
    final records = ref.watch(recordsProvider);
    final still = _still;
    return Scaffold(
      backgroundColor: Palette.bg,
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: (_, e) => _onKey(entries, e),
        child: Stack(fit: StackFit.expand, children: [
          // 後ろで流れるデモプレイ (ドットが歪まないよう、傾けずに暗くして置く)
          Opacity(opacity: 0.4, child: AttractDemo(animate: !still)),
          const _Shade(),
          SafeArea(
            child: LayoutBuilder(builder: (context, c) {
              final logoSize = math.min(c.maxWidth * 0.085, c.maxHeight * 0.17);
              return AnimatedBuilder(
                animation: _intro,
                builder: (context, _) => Padding(
                  padding: EdgeInsets.fromLTRB(c.maxWidth * 0.05, 16, c.maxWidth * 0.04, 12),
                  child: Row(children: [
                    // 左: ロゴとハイスコア
                    Expanded(
                      flex: 11,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Spacer(flex: 3),
                        Opacity(
                          opacity: _stage(0, 0.45),
                          child: Transform.translate(
                            offset: Offset(-60 * (1 - _stage(0, 0.45)), 0),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: TitleLogo(size: logoSize, animate: !still),
                            ),
                          ),
                        ),
                        const Spacer(flex: 4),
                        if (records.endless.bestScore > 0)
                          Opacity(
                            opacity: _stage(0.5, 0.9),
                            child: _HiScore(record: records.endless),
                          ),
                      ]),
                    ),
                    // 右: メニュー
                    Expanded(
                      flex: 7,
                      child: Center(
                        child: Opacity(
                          opacity: _stage(0.25, 0.6),
                          child: _MenuWindow(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (var i = 0; i < entries.length; i++)
                                  Opacity(
                                    opacity: _stage(0.25 + i * 0.07, 0.6 + i * 0.07),
                                    child: _MenuItem(
                                      entry: entries[i],
                                      selected: i == _selected,
                                      firing: _firing == i,
                                      onHover: () => _select(i),
                                      onTap: () => _activate(entries, i),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ]),
                ),
              );
            }),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: SafeArea(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _tapVersion,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Text('VER 1.0.0', style: pixelFont(10, color: withAlpha(Palette.pale, 0.4), letterSpacing: 3)),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// 文字を読みやすくするための暗幕 (デモの上に重ねる。ロゴ側を濃くする)。
class _Shade extends StatelessWidget {
  const _Shade();

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Row(children: [
          Expanded(flex: 11, child: ColoredBox(color: withAlpha(Dot.ink, 0.7))),
          Expanded(flex: 7, child: ColoredBox(color: withAlpha(Dot.ink, 0.45))),
        ]),
      );
}

/// メニューを囲む、RPG の窓のような二重枠。
class _MenuWindow extends StatelessWidget {
  const _MenuWindow({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: withAlpha(Dot.ink, 0.92),
          border: Border.all(color: Dot.white, width: 3),
          boxShadow: const [BoxShadow(color: Colors.black, offset: Offset(6, 6))],
        ),
        child: Container(
          margin: const EdgeInsets.all(4),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(border: Border.all(color: Dot.dim, width: 2)),
          child: child,
        ),
      );
}

/// メニューの 1 項目。選ぶと ▶ が点滅し、決めた瞬間は項目が反転する。
class _MenuItem extends StatelessWidget {
  const _MenuItem({
    required this.entry,
    required this.selected,
    required this.firing,
    required this.onHover,
    required this.onTap,
  });

  final _MenuEntry entry;
  final bool selected, firing;
  final VoidCallback onHover, onTap;

  @override
  Widget build(BuildContext context) {
    final size = entry.primary ? 24.0 : 18.0;
    final color = firing ? Dot.ink : selected ? Palette.white : Palette.gray;
    return Semantics(
      button: true,
      label: entry.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => onHover(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => onHover(),
          onTap: onTap,
          child: SizedBox(
            height: entry.primary ? 58 : 46,
            child: Stack(alignment: Alignment.centerLeft, children: [
              if (firing) const Positioned.fill(child: ColoredBox(color: Palette.yellow)),
              if (selected && !firing) const Positioned(left: 10, child: _Cursor()),
              Padding(
                padding: const EdgeInsets.only(left: 34, right: 16),
                child: Row(children: [
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        entry.label,
                        style: pixelFont(size, color: color, weight: 800, letterSpacing: 2)
                            .copyWith(shadows: selected && !firing ? hardShadow(size) : null),
                      ),
                    ),
                  ),
                  if (entry.meta.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    Text(entry.meta,
                        style: pixelFont(10, color: firing ? Dot.ink : selected ? Palette.yellow : Palette.gray, letterSpacing: 2)
                            .copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                  ],
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// 選択中の項目の ▶ (点滅する)。
class _Cursor extends StatefulWidget {
  const _Cursor();

  @override
  State<_Cursor> createState() => _CursorState();
}

class _CursorState extends State<_Cursor> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));

  @override
  void initState() {
    super.initState();
    _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => Opacity(
        opacity: still || _c.value < 0.6 ? 1 : 0,
        child: const Text('▶', style: TextStyle(fontFamily: kJpFont, fontSize: 18, color: Palette.yellow, height: 1)),
      ),
    );
  }
}

/// 左下のハイスコア表示 (アーケードの計器風)。
class _HiScore extends StatelessWidget {
  const _HiScore({required this.record});
  final EndlessRecord record;

  @override
  Widget build(BuildContext context) {
    const tab = [FontFeature.tabularFigures()];
    return Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
      Container(width: 3, height: 44, color: Palette.magenta, margin: const EdgeInsets.only(right: 12)),
      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text('HI-SCORE', style: pixelFont(10, color: withAlpha(Palette.magenta, 0.9), letterSpacing: 4)),
        const SizedBox(height: 2),
        Text(formatScore(record.bestScore),
            style: pixelFont(28, weight: 900, letterSpacing: 2).copyWith(fontFeatures: tab)),
      ]),
      const SizedBox(width: 22),
      Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text('MAX WAVE ${record.bestWave.toString().padLeft(2, '0')}',
            style: pixelFont(11, color: withAlpha(Palette.pale, 0.7), letterSpacing: 3).copyWith(fontFeatures: tab)),
      ),
    ]);
  }
}
