import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../app/providers.dart';
import '../l10n/app_localizations.dart';
import '../render/palette.dart';
import '../services/ads.dart';
import '../services/settings.dart';
import 'arcade.dart';
import 'calibration_screen.dart';
import 'widgets.dart';
import 'pixel_icons.dart';
import '../render/pixel.dart';

enum _Tab { controls, sound, display, other }

String _percent(double v) => '${(v * 100).round()}%';

/// 設定。左の見出しで分類を選び、右の枠にその分類の項目を出す (横画面でスクロールを減らすため)。
///
/// キーボードでは、左の見出しを ↑↓ で選び、→ か Enter で右の項目へ入る。右では ↑↓ で項目を選び、
/// ←→ で値を変え (いくつかから選ぶものは隣へ、目盛りは 1 段ずつ)、Enter でボタンを押す (選ぶものは次の値へ)。
/// Esc は、右にいれば左の見出しへ、左にいれば前の画面へ戻る。
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  _Tab _tab = _Tab.controls;

  /// 見出しの右に出す版番号 (pubspec.yaml の version の X.Y.Z)。読めるまでは空。
  String _version = '';

  /// 版番号を続けてタップした回数と、最後のタップの時刻 (デバッグモードの切り替え用)。
  int _verTaps = 0;
  DateTime _lastVerTap = DateTime(0);

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _version = info.version);
    });
  }

  /// 版番号を 3 回続けてタップすると、デバッグモードを切り替える (design.md 9.9)。
  void _tapVersion() {
    final now = DateTime.now();
    _verTaps = now.difference(_lastVerTap) < const Duration(milliseconds: 600)
        ? _verTaps + 1
        : 1;
    _lastVerTap = now;
    if (_verTaps < 3) return;
    _verTaps = 0;
    final on = !ref.read(settingsProvider).debugMode;
    ref
        .read(settingsProvider.notifier)
        .update((s) => s.copyWith(debugMode: on));
    ref.read(hapticsProvider).selection();
    final l = AppLocalizations.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(on ? l.debugModeOn : l.debugModeOff)),
      );
  }

  /// キーボードで右の項目を選んでいる (false なら左の見出しを選んでいる)。
  bool _inRows = false;

  /// キーボードで選んでいる右の項目。
  int _row = 0;

  final List<GlobalKey> _rowKeys = [];

  GlobalKey _rowKey(int i) {
    while (_rowKeys.length <= i) {
      _rowKeys.add(GlobalKey());
    }
    return _rowKeys[i];
  }

  /// 選んだ項目が枠の外にあれば、見えるところまでスクロールする。
  void _reveal({required bool down}) =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final c = _rowKey(_row).currentContext;
        if (c == null || !c.mounted) return;
        Scrollable.ensureVisible(
          c,
          alignmentPolicy: down
              ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
              : ScrollPositionAlignmentPolicy.keepVisibleAtStart,
        );
      });

  KeyEventResult _onKey(
    FocusNode node,
    KeyEvent e,
    List<_Tab> tabs,
    _Tab tab,
    List<_Row> rows,
  ) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = e.logicalKey;
    final repeat = e is KeyRepeatEvent;
    if (key == LogicalKeyboardKey.escape) {
      if (repeat) return KeyEventResult.handled;
      if (_inRows) {
        setState(() => _inRows = false);
      } else {
        Navigator.of(context).maybePop();
      }
      return KeyEventResult.handled;
    }
    // Tab で戻るボタンや −/+ にフォーカスを移しているときは、そちらの操作にまかせる
    if (!node.hasPrimaryFocus) return KeyEventResult.ignored;
    final confirm = isConfirmKey(key);
    if (!_inRows) {
      if (key == LogicalKeyboardKey.arrowUp ||
          key == LogicalKeyboardKey.arrowDown) {
        final i =
            tabs.indexOf(tab) + (key == LogicalKeyboardKey.arrowUp ? -1 : 1);
        if (i >= 0 && i < tabs.length) setState(() => _tab = tabs[i]);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowRight || confirm) {
        if (!repeat && rows.isNotEmpty) {
          setState(() {
            _inRows = true;
            _row = 0;
          });
          _reveal(down: false);
        }
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    final row = rows[_row.clamp(0, rows.length - 1)];
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      final down = key == LogicalKeyboardKey.arrowDown;
      final i = _row + (down ? 1 : -1);
      if (i >= 0 && i < rows.length) {
        setState(() => _row = i);
        _reveal(down: down);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      final dir = key == LogicalKeyboardKey.arrowLeft ? -1 : 1;
      // 値を変えられない項目 (ボタンだけ) で ← を押したら、左の見出しへ戻る
      if (!row.keyStep(dir) && dir < 0) setState(() => _inRows = false);
      return KeyEventResult.handled;
    }
    if (confirm) {
      if (!repeat) row.keyEnter();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final s = ref.watch(settingsProvider);
    final ads = ref.read(adsProvider);
    // 「その他」は中身があるときだけ出す
    final tabs = [
      _Tab.controls,
      _Tab.sound,
      _Tab.display,
      if (ads.privacyOptionsRequired || s.debugMode) _Tab.other,
    ];
    final tab = tabs.contains(_tab) ? _tab : _Tab.controls;
    // 選んでいるもの・いまの値はメインカラー (黄)
    const color = Palette.main;
    final rows = _rows(context, tab, s, color);
    if (_row >= rows.length) _row = math.max(0, rows.length - 1);
    final names = {
      _Tab.controls: l.settingsTabControls,
      _Tab.sound: l.settingsTabSound,
      _Tab.display: l.settingsTabDisplay,
      _Tab.other: l.settingsTabOther,
    };

    return Scaffold(
      body: Focus(
        autofocus: true,
        onKeyEvent: (node, e) => _onKey(node, e, tabs, tab, rows),
        child: DotBackground(
          animate: false,
          child: Stack(
            children: [
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            onPressed: () => Navigator.of(context).maybePop(),
                            icon: PixelIcon(
                              PixelIcons.back,
                              color: Palette.sub,
                            ),
                            tooltip: MaterialLocalizations.of(context)
                                .backButtonTooltip,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: PixelTitle(
                                l.menuSettings,
                                size: 26,
                                color: Palette.yellow,
                                shadow: Dot.brick,
                              ),
                            ),
                          ),
                          if (_version.isNotEmpty)
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: _tapVersion,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  minWidth: 44,
                                  minHeight: 44,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  child: Center(
                                    widthFactor: 1,
                                    child: Text(
                                      'VER $_version',
                                      style: pixelFont(
                                        12,
                                        color: Palette.pale,
                                        letterSpacing: 2,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, c) {
                            final tabW = c.maxWidth < 900 ? 132.0 : 200.0;
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SizedBox(
                                  width: tabW,
                                  child: SingleChildScrollView(
                                    child: PixelWindow(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 6,
                                      ),
                                      child: Column(
                                        children: [
                                          for (final t in tabs)
                                            _TabButton(
                                              label: names[t]!,
                                              selected: t == tab,
                                              cursor: !_inRows,
                                              onTap: () => setState(() {
                                                _tab = t;
                                                _inRows = false;
                                              }),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: withAlpha(Dot.ink, 0.92),
                                      border: Border.all(
                                        color: Palette.hudLine,
                                        width: 3,
                                      ),
                                      boxShadow: const [
                                        BoxShadow(
                                          color: Colors.black,
                                          offset: Offset(6, 6),
                                        ),
                                      ],
                                    ),
                                    child: ListView(
                                      key: PageStorageKey(tab),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                        vertical: 6,
                                      ),
                                      children: [
                                        for (
                                          var i = 0;
                                          i < rows.length;
                                          i++
                                        ) ...[
                                          if (i > 0)
                                            const Divider(
                                              height: 1,
                                              thickness: 1,
                                              color: Palette.hudLine,
                                            ),
                                          KeyedSubtree(
                                            key: _rowKey(i),
                                            child: _Selectable(
                                              selected: _inRows && i == _row,
                                              child: rows[i],
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<_Row> _rows(BuildContext context, _Tab tab, Settings s, Color color) {
    final l = AppLocalizations.of(context);
    final n = ref.read(settingsProvider.notifier);
    void volumes(Settings v) =>
        ref.read(audioProvider).setVolumes(bgm: v.bgmVolume, sfx: v.sfxVolume);
    final rows = switch (tab) {
      _Tab.controls => [
        _Row(
          label: l.settingsControls,
          child: _Choice<ControlScheme>(
            color: color,
            value: s.controls,
            options: {
              ControlScheme.zones: l.controlsZones,
              ControlScheme.railHorizontal: l.controlsRailH,
              ControlScheme.railVertical: l.controlsRailV,
            },
            onChanged: (v) => n.update((x) => x.copyWith(controls: v)),
          ),
        ),
        // 感度は 1 つにまとめ、いま選んでいる操作方法の値を変える (領域は sensitivity、レールは railSensitivity)
        _Row(
          label: l.settingsSensitivity,
          child: s.controls == ControlScheme.zones
              ? _Meter(
                  color: color,
                  value: s.sensitivity,
                  min: 1,
                  max: 4,
                  divisions: 30,
                  format: (v) => '×${v.toStringAsFixed(1)}',
                  onChanged: (v) => n.update((x) => x.copyWith(sensitivity: v)),
                )
              : _Meter(
                  color: color,
                  value: s.railSensitivity,
                  min: 0.5,
                  max: 2,
                  divisions: 15,
                  format: (v) => '×${v.toStringAsFixed(1)}',
                  onChanged: (v) =>
                      n.update((x) => x.copyWith(railSensitivity: v)),
                ),
        ),
        _Row(
          label: l.settingsTiming,
          help: l.settingsTimingHelp,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Meter(
                color: color,
                value: s.timingOffsetMs.toDouble(),
                min: 0,
                max: 100,
                divisions: 100,
                format: (v) => '${v.round()}ms',
                onChanged: (v) =>
                    n.update((x) => x.copyWith(timingOffsetMs: v.round())),
              ),
              const SizedBox(height: 6),
              _SmallButton(
                label: l.calibrate,
                icon: PixelIcons.timer,
                color: Palette.sub, // 画面を開く二番手のボタン
                onTap: () =>
                    Navigator.of(context)
                        .push(fadeRoute<void>(const CalibrationScreen())),
              ),
            ],
          ),
        ),
        _Row(
          label: l.settingsHaptics,
          child: _OnOff(
            color: color,
            value: s.haptics,
            onChanged: (v) {
              n.update((x) => x.copyWith(haptics: v));
              ref.read(hapticsProvider).selection();
            },
          ),
        ),
      ],
      _Tab.sound => [
        _Row(
          label: l.settingsBgm,
          child: _Meter(
            color: color,
            value: s.bgmVolume,
            min: 0,
            max: 1,
            divisions: 20,
            format: _percent,
            onChanged: (v) {
              n.update((x) => x.copyWith(bgmVolume: v));
              volumes(ref.read(settingsProvider));
            },
          ),
        ),
        _Row(
          label: l.settingsSfx,
          child: _Meter(
            color: color,
            value: s.sfxVolume,
            min: 0,
            max: 1,
            divisions: 20,
            format: _percent,
            onChanged: (v) {
              n.update((x) => x.copyWith(sfxVolume: v));
              volumes(ref.read(settingsProvider));
            },
            onChangeEnd: (_) => ref.read(audioProvider).play('perfect'),
          ),
        ),
      ],
      _Tab.display => [
        _Row(
          label: l.settingsQuality,
          child: _Choice<GraphicsQuality>(
            color: color,
            value: s.quality,
            options: {
              GraphicsQuality.high: l.qualityHigh,
              GraphicsQuality.low: l.qualityLow,
            },
            onChanged: (v) => n.update((x) => x.copyWith(quality: v)),
          ),
        ),
        _Row(
          label: l.settingsReduceEffects,
          help: l.settingsReduceEffectsHelp,
          child: _OnOff(
            color: color,
            value: s.reduceEffects,
            onChanged: (v) => n.update((x) => x.copyWith(reduceEffects: v)),
          ),
        ),
        _Row(
          label: l.settingsShowTiming,
          help: l.settingsShowTimingHelp,
          child: _OnOff(
            color: color,
            value: s.showTiming,
            onChanged: (v) => n.update((x) => x.copyWith(showTiming: v)),
          ),
        ),
        _Row(
          label: l.settingsLanguage,
          child: _Choice<String>(
            color: color,
            value: s.language ?? '',
            options: {'': l.languageSystem, 'ja': '日本語', 'en': 'English'},
            onChanged: (v) => n.update(
              (x) => x.copyWith(language: () => v.isEmpty ? null : v),
            ),
          ),
        ),
      ],
      _Tab.other => [
        // 同意が必要な地域 (EU など) では、同意をいつでも変えられる入口を置く
        if (ref.read(adsProvider).privacyOptionsRequired)
          _Row(
            label: l.settingsAdPrivacy,
            child: _SmallButton(
              label: '›',
              semanticLabel: l.open,
              color: color,
              onTap: ref.read(adsProvider).showPrivacyOptions,
            ),
          ),
        if (s.debugMode)
          _Row(
            label: l.settingsDebugMode,
            help: l.settingsDebugModeHelp,
            child: _OnOff(
              color: color,
              value: true,
              onChanged: (v) => n.update((x) => x.copyWith(debugMode: v)),
            ),
          ),
      ],
    };
    return rows;
  }
}

/// 左の分類の見出し。選んでいるものは色の帯と明るい地で示す。
class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.selected,
    required this.onTap,
    this.cursor = true,
  });
  final String label;
  final bool selected;

  /// 選んでいれば ▶ を出す (キーボードで右の項目を選んでいる間は出さない)。
  final bool cursor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            SizedBox(
              width: 30,
              child: selected && cursor
                  ? const Center(child: BlinkCursor(size: 16))
                  : null,
            ),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 17,
                  color: selected ? Palette.white : Palette.gray,
                  shadows: selected ? hardShadow(17) : null,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// キーボードで操作できる項目の部品。
abstract interface class _KeyControl {
  /// ←→ で値を動かす。動かせる部品なら true。
  bool keyStep(int dir);

  /// Enter / Space で押す。押せる部品なら true。
  bool keyEnter();
}

/// キーボードで選んでいる項目を白い枠で囲む (大きさを変えないよう、外側に重ねて描く)。
class _Selectable extends StatelessWidget {
  const _Selectable({required this.selected, required this.child});
  final bool selected;
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      child,
      if (selected)
        Positioned(
          left: -12,
          right: -12,
          top: 3,
          bottom: 3,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: Dot.white, width: 3),
              ),
            ),
          ),
        ),
    ],
  );
}

/// 1 項目。広い枠では名前の右に操作を、狭い枠では名前の下に操作を、どちらも左に寄せて置く。
class _Row extends StatelessWidget {
  const _Row({required this.label, required this.child, this.help});
  final String label;
  final String? help;
  final Widget child;

  /// 項目の中の、キーボードで操作できる部品 (時間の補正は目盛りと「測定する」の 2 つ)。
  List<_KeyControl> get _controls => [
    if (child case final _KeyControl c) c,
    if (child case Column(:final children))
      ...children.whereType<_KeyControl>(),
  ];

  bool keyStep(int dir) => _controls.any((c) => c.keyStep(dir));

  bool keyEnter() => _controls.any((c) => c.keyEnter());

  @override
  Widget build(BuildContext context) {
    final name = Semantics(
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 16, color: Palette.white)),
          if (help != null) ...[
            const SizedBox(height: 3),
            Text(
              help!,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: withAlpha(Palette.pale, 0.55),
              ),
            ),
          ],
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: LayoutBuilder(
        builder: (context, c) {
          if (c.maxWidth < 560) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                name,
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerLeft, child: child),
              ],
            );
          }
          return Row(
            children: [
              SizedBox(width: math.min(c.maxWidth * 0.38, 300), child: name),
              const SizedBox(width: 24),
              Expanded(
                child: Align(alignment: Alignment.centerLeft, child: child),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 四角い枠。選んでいるものは陰影の付いたブロックとして塗る。
class _SlantPainter extends CustomPainter {
  _SlantPainter({required this.color, required this.on});
  final Color color;
  final bool on;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    final p = Paint()..isAntiAlias = false;
    if (on) {
      const d = 3.0;
      canvas.drawRect(r, p..color = color);
      p.color = Dot.light(color);
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, d), p);
      canvas.drawRect(Rect.fromLTWH(0, 0, d, size.height), p);
      p.color = Dot.dark(color);
      canvas.drawRect(Rect.fromLTWH(0, size.height - d, size.width, d), p);
      canvas.drawRect(Rect.fromLTWH(size.width - d, d, d, size.height - d), p);
      return;
    }
    canvas.drawRect(r, p..color = Dot.night);
    canvas.drawRect(
      r.deflate(1),
      p
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = withAlpha(Palette.pale, 0.3),
    );
  }

  @override
  bool shouldRepaint(_SlantPainter old) => old.color != color || old.on != on;
}

/// いくつかの中から 1 つを選ぶ。
class _Choice<T> extends StatelessWidget implements _KeyControl {
  const _Choice({
    required this.value,
    required this.options,
    required this.onChanged,
    required this.color,
  });
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;
  final Color color;

  @override
  bool keyStep(int dir) {
    final keys = options.keys.toList();
    final i = keys.indexOf(value) + dir;
    if (i >= 0 && i < keys.length) onChanged(keys[i]);
    return true;
  }

  /// 次の値へ (最後なら最初へ)。
  @override
  bool keyEnter() {
    final keys = options.keys.toList();
    onChanged(keys[(keys.indexOf(value) + 1) % keys.length]);
    return true;
  }

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.start,
    spacing: 4,
    runSpacing: 6,
    children: [
      for (final MapEntry(key: k, value: label) in options.entries)
        Semantics(
          button: true,
          selected: k == value,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onChanged(k),
            child: CustomPaint(
              painter: _SlantPainter(color: color, on: k == value),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44, minWidth: 84),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Center(
                    widthFactor: 1,
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        color: k == value
                            ? Dot.ink
                            : withAlpha(Palette.pale, 0.65),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

class _OnOff extends StatelessWidget implements _KeyControl {
  const _OnOff({
    required this.value,
    required this.onChanged,
    required this.color,
  });
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color color;

  /// ← で OFF、→ で ON (並びのとおり)。
  @override
  bool keyStep(int dir) {
    final v = dir > 0;
    if (v != value) onChanged(v);
    return true;
  }

  @override
  bool keyEnter() {
    onChanged(!value);
    return true;
  }

  @override
  Widget build(BuildContext context) => _Choice<bool>(
    value: value,
    options: const {false: 'OFF', true: 'ON'},
    onChanged: onChanged,
    color: color,
  );
}

/// アーケードの音量計のような目盛り。目盛りを触るかドラッグして変え、−/+ で 1 段ずつ動かす。
class _Meter extends StatelessWidget implements _KeyControl {
  const _Meter({
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.format,
    required this.onChanged,
    required this.color,
    this.onChangeEnd,
  });

  final double value, min, max;
  final int divisions;
  final String Function(double) format;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final Color color;

  double get step => (max - min) / divisions;

  double _snap(double v) {
    return (min + ((v - min) / step).round() * step).clamp(min, max);
  }

  void _step(int dir) {
    final v = _snap(value + dir * step);
    if (v == value) return;
    onChanged(v);
    onChangeEnd?.call(v);
  }

  @override
  bool keyStep(int dir) {
    _step(dir);
    return true;
  }

  @override
  bool keyEnter() => false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final col = color;
    final k = ((value - min) / (max - min)).clamp(0.0, 1.0);
    // −/+ (48px ずつ) と数値の欄を除いた幅に収める
    return LayoutBuilder(
      builder: (context, outer) => Semantics(
        slider: true,
        value: format(value),
        increasedValue: format(_snap(value + step)),
        decreasedValue: format(_snap(value - step)),
        onIncrease: () => _step(1),
        onDecrease: () => _step(-1),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StepButton(
              icon: PixelIcons.minus,
              label: l.stepDown,
              color: col,
              onTap: value > min ? () => _step(-1) : null,
            ),
            SizedBox(
              width: (outer.maxWidth - 176).clamp(60.0, 240.0),
              child: LayoutBuilder(
                builder: (context, c) {
                  double at(Offset p) => _snap(
                    min + (p.dx / c.maxWidth).clamp(0.0, 1.0) * (max - min),
                  );
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) => onChanged(at(d.localPosition)),
                    onTapUp: (d) => onChangeEnd?.call(at(d.localPosition)),
                    onHorizontalDragUpdate: (d) =>
                        onChanged(at(d.localPosition)),
                    onHorizontalDragEnd: (_) => onChangeEnd?.call(value),
                    child: SizedBox(
                      height: 44,
                      child: CustomPaint(painter: _MeterPainter(k, col)),
                    ),
                  );
                },
              ),
            ),
            _StepButton(
              icon: PixelIcons.plus,
              label: l.stepUp,
              color: col,
              onTap: value < max ? () => _step(1) : null,
            ),
            SizedBox(
              width: 76,
              child: Text(
                format(value),
                textAlign: TextAlign.right,
                style: pixelFont(
                  17,
                  color: col,
                  weight: 800,
                ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MeterPainter extends CustomPainter {
  _MeterPainter(this.k, this.color);
  final double k;
  final Color color;

  static const _bars = 20;

  @override
  void paint(Canvas canvas, Size size) {
    const gap = 3.0;
    final w = (size.width - gap * (_bars - 1)) / _bars;
    final lit = (k * _bars).round();
    final on = Paint()
      ..color = color
      ..isAntiAlias = false;
    final top = Paint()
      ..color = Dot.light(color)
      ..isAntiAlias = false;
    final off = Paint()
      ..color = Dot.edge
      ..isAntiAlias = false;
    for (var i = 0; i < _bars; i++) {
      // 右へ行くほど 1 段ずつ高くする (4 段)
      final h = size.height * (0.4 + 0.15 * (i * 4 ~/ _bars));
      final x = (i * (w + gap)).floorToDouble();
      final r = Rect.fromLTWH(
        x,
        (size.height - h).floorToDouble(),
        w.floorToDouble(),
        h.floorToDouble(),
      );
      if (i < lit) {
        canvas.drawRect(r, on);
        canvas.drawRect(Rect.fromLTWH(r.left, r.top, r.width, 3), top);
      } else {
        canvas.drawRect(r, off);
      }
    }
  }

  @override
  bool shouldRepaint(_MeterPainter old) => old.k != k || old.color != color;
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final DotSprite icon;

  /// 読み上げる名前 (下げる / 上げる)。
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Semantics(
      label: label,
      child: IconButton(
        onPressed: onTap,
        icon: PixelIcon(icon, size: 18),
        color: color,
        disabledColor: withAlpha(Palette.pale, 0.2),
        // 押せる範囲は 44pt 以上 (目盛りの幅は、この 48 を 2 つ分引いて決めている)
        constraints: const BoxConstraints(minWidth: 48, minHeight: 44),
        padding: EdgeInsets.zero,
      ),
    ),
  );
}

/// 枠付きの小さなボタン (測定する など)。
class _SmallButton extends StatelessWidget implements _KeyControl {
  const _SmallButton({
    required this.label,
    required this.color,
    required this.onTap,
    this.icon,
    this.semanticLabel,
  });
  final String label;

  /// 読み上げる名前。見た目の [label] が記号 (›) のときに付ける。
  final String? semanticLabel;
  final DotSprite? icon;
  final Color color;
  final VoidCallback onTap;

  @override
  bool keyStep(int dir) => false;

  @override
  bool keyEnter() {
    onTap();
    return true;
  }

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    label: semanticLabel,
    // 名前を付けたときは見た目の文字を読まない (下の GestureDetector の分も外れるので、タップはここで渡す)
    excludeSemantics: semanticLabel != null,
    onTap: onTap,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: CustomPaint(
        painter: _SlantPainter(color: color, on: false),
        child: Container(
          constraints: const BoxConstraints(
            minHeight: 44,
            minWidth: 64,
          ), // 押せる範囲は 44pt 以上
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                PixelIcon(icon!, size: 16, color: color),
                const SizedBox(width: 6),
              ],
              Text(label, style: TextStyle(fontSize: 14, color: color)),
            ],
          ),
        ),
      ),
    ),
  );
}
