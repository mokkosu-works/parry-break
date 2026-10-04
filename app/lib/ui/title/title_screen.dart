import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
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

  @override
  void initState() {
    super.initState();
    _intro.forward();
  }

  @override
  void dispose() {
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
    void push(Widget w) => nav.push(fadeRoute(w));
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

  void _select(int i) {
    if (i == _selected) return;
    ref.read(audioProvider).play('count');
    setState(() => _selected = i);
  }

  KeyEventResult _onKey(List<_MenuEntry> entries, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowDown) {
      _select((_selected + 1) % entries.length);
    } else if (k == LogicalKeyboardKey.arrowUp) {
      _select((_selected - 1 + entries.length) % entries.length);
    } else if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.space) {
      _activate(entries, _selected);
    } else {
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
          // 奥に傾けたデモプレイ
          Transform(
            alignment: const Alignment(0, -0.2),
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0011)
              ..rotateX(-0.62)
              ..scaleByDouble(1.3, 1.3, 1, 1),
            child: Opacity(opacity: 0.5, child: AttractDemo(animate: !still)),
          ),
          const _Shade(),
          const IgnorePointer(child: CustomPaint(painter: _ScanlinePainter())),
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
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < entries.length; i++)
                            Opacity(
                              opacity: _stage(0.25 + i * 0.07, 0.6 + i * 0.07),
                              child: Transform.translate(
                                offset: Offset(50 * (1 - _stage(0.25 + i * 0.07, 0.6 + i * 0.07)), 0),
                                child: _MenuItem(
                                  entry: entries[i],
                                  selected: i == _selected,
                                  firing: _firing == i,
                                  onHover: () => _select(i),
                                  onTap: () => _activate(entries, i),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ]),
                ),
              );
            }),
          ),
          Positioned(
            right: 16,
            bottom: 8,
            child: SafeArea(
              child: Text('VER 1.0.0', style: orbitron(10, color: withAlpha(Palette.pale, 0.4), letterSpacing: 3)),
            ),
          ),
        ]),
      ),
    );
  }
}

/// 文字を読みやすくするための陰影 (左はロゴ、右はメニューの後ろを暗く、四隅を落とす)。
class _Shade extends StatelessWidget {
  const _Shade();

  @override
  Widget build(BuildContext context) => const IgnorePointer(
        child: Stack(fit: StackFit.expand, children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xE607060F), Color(0x6607060F), Color(0x3307060F), Color(0xCC07060F)],
                stops: [0, 0.45, 0.62, 1],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF07060F), Color(0x0007060F), Color(0x0007060F), Color(0xF207060F)],
                stops: [0, 0.22, 0.7, 1],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(radius: 1.1, colors: [Color(0x00000000), Color(0x99000000)], stops: [0.6, 1]),
            ),
          ),
        ]),
      );
}

/// ブラウン管の走査線。
class _ScanlinePainter extends CustomPainter {
  const _ScanlinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = const Color(0x14000000);
    for (var y = 0.0; y < size.height; y += 3) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), p);
    }
  }

  @override
  bool shouldRepaint(_ScanlinePainter old) => false;
}

/// メニューの 1 項目。選ぶと斜めの光の帯が出る。
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
    final size = entry.primary ? 27.0 : 21.0;
    final color = selected ? Palette.white : withAlpha(Palette.white, 0.58);
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
              Positioned.fill(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 160),
                  opacity: selected ? 1 : 0,
                  child: CustomPaint(painter: _SlashBar(bright: firing, primary: entry.primary)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 30, right: 12),
                child: Row(children: [
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        entry.label,
                        style: orbitron(size, color: color, weight: 800, letterSpacing: 3).copyWith(
                          shadows: selected ? [Shadow(color: Palette.cyan, blurRadius: entry.primary ? 16 : 10)] : null,
                        ),
                      ),
                    ),
                  ),
                  if (entry.meta.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    Text(entry.meta,
                        style: orbitron(10, color: selected ? Palette.cyan : withAlpha(Palette.pale, 0.45), letterSpacing: 2)
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

/// 選択中の項目の後ろに引く、斜めに切った光の帯。
class _SlashBar extends CustomPainter {
  _SlashBar({required this.bright, required this.primary});
  final bool bright, primary;

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height, slant = h * 0.45;
    final band = Path()
      ..moveTo(slant, 4)
      ..lineTo(size.width, 4)
      ..lineTo(size.width - slant, h - 4)
      ..lineTo(0, h - 4)
      ..close();
    canvas.drawPath(
      band,
      Paint()
        ..shader = LinearGradient(colors: [
          withAlpha(Palette.cyan, bright ? 0.7 : (primary ? 0.32 : 0.22)),
          withAlpha(Palette.cyan, 0),
        ]).createShader(Offset.zero & size),
    );
    // 左端の鋭いエッジと、矢印
    final edge = Path()
      ..moveTo(slant, 4)
      ..lineTo(slant + 5, 4)
      ..lineTo(5, h - 4)
      ..lineTo(0, h - 4)
      ..close();
    canvas.drawPath(edge, Paint()..color = bright ? Palette.white : Palette.cyan);
    final cy = h / 2;
    canvas.drawPath(
      Path()
        ..moveTo(14, cy - 5)
        ..lineTo(21, cy)
        ..lineTo(14, cy + 5)
        ..close(),
      Paint()..color = Palette.white,
    );
  }

  @override
  bool shouldRepaint(_SlashBar old) => old.bright != bright || old.primary != primary;
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
        Text('HI-SCORE', style: orbitron(10, color: withAlpha(Palette.magenta, 0.9), letterSpacing: 4)),
        const SizedBox(height: 2),
        Text(formatScore(record.bestScore),
            style: orbitron(28, weight: 900, letterSpacing: 2).copyWith(fontFeatures: tab)),
      ]),
      const SizedBox(width: 22),
      Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text('MAX WAVE ${record.bestWave.toString().padLeft(2, '0')}',
            style: orbitron(11, color: withAlpha(Palette.pale, 0.7), letterSpacing: 3).copyWith(fontFeatures: tab)),
      ),
    ]);
  }
}
