import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  _Tab _tab = _Tab.controls;


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
    final names = {
      _Tab.controls: l.settingsTabControls,
      _Tab.sound: l.settingsTabSound,
      _Tab.display: l.settingsTabDisplay,
      _Tab.other: l.settingsTabOther,
    };

    return Scaffold(
      body: DotBackground(
        animate: false,
        child: Stack(children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: PixelIcon(PixelIcons.back, color: Palette.sub),
                    tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: PixelTitle(l.menuSettings, size: 26, color: Palette.yellow, shadow: Dot.brick),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                Expanded(
                  child: LayoutBuilder(builder: (context, c) {
                    final tabW = c.maxWidth < 900 ? 132.0 : 200.0;
                    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      SizedBox(
                        width: tabW,
                        child: SingleChildScrollView(
                          child: PixelWindow(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Column(children: [
                              for (final t in tabs)
                                _TabButton(
                                  label: names[t]!,
                                  selected: t == tab,
                                  onTap: () => setState(() => _tab = t),
                                ),
                            ]),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: withAlpha(Dot.ink, 0.92),
                            border: Border.all(color: Palette.hudLine, width: 3),
                            boxShadow: const [BoxShadow(color: Colors.black, offset: Offset(6, 6))],
                          ),
                          child: ListView(
                            key: PageStorageKey(tab),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                            children: _rows(context, tab, s, color),
                          ),
                        ),
                      ),
                    ]);
                  }),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  List<Widget> _rows(BuildContext context, _Tab tab, Settings s, Color color) {
    final l = AppLocalizations.of(context);
    final n = ref.read(settingsProvider.notifier);
    void volumes(Settings v) => ref.read(audioProvider).setVolumes(bgm: v.bgmVolume, sfx: v.sfxVolume);
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
          _Row(
            label: l.settingsSensitivity,
            enabled: s.controls == ControlScheme.zones,
            child: _Meter(
              color: color,
              value: s.sensitivity,
              min: 1,
              max: 4,
              divisions: 30,
              format: (v) => '×${v.toStringAsFixed(1)}',
              enabled: s.controls == ControlScheme.zones,
              onChanged: (v) => n.update((x) => x.copyWith(sensitivity: v)),
            ),
          ),
          _Row(
            label: l.settingsTiming,
            help: l.settingsTimingHelp,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _Meter(
                color: color,
                value: s.timingOffsetMs.toDouble(),
                min: 0,
                max: 100,
                divisions: 100,
                format: (v) => '${v.round()}ms',
                onChanged: (v) => n.update((x) => x.copyWith(timingOffsetMs: v.round())),
              ),
              const SizedBox(height: 6),
              _SmallButton(
                label: l.calibrate,
                icon: PixelIcons.timer,
                color: Palette.sub, // 画面を開く二番手のボタン
                onTap: () => Navigator.of(context).push(fadeRoute<void>(const CalibrationScreen())),
              ),
            ]),
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
              options: {GraphicsQuality.high: l.qualityHigh, GraphicsQuality.low: l.qualityLow},
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
            label: l.settingsLanguage,
            child: _Choice<String>(
              color: color,
              value: s.language ?? '',
              options: {'': l.languageSystem, 'ja': '日本語', 'en': 'English'},
              onChanged: (v) => n.update((x) => x.copyWith(language: () => v.isEmpty ? null : v)),
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
                color: color,
                onTap: ref.read(adsProvider).showPrivacyOptions,
              ),
            ),
          if (s.debugMode)
            _Row(
              label: l.settingsDebugMode,
              help: l.settingsDebugModeHelp,
              child: _OnOff(color: color, value: true, onChanged: (v) => n.update((x) => x.copyWith(debugMode: v))),
            ),
        ],
    };
    return [
      for (var i = 0; i < rows.length; i++) ...[
        if (i > 0) const Divider(height: 1, thickness: 1, color: Palette.hudLine),
        rows[i],
      ],
    ];
  }
}

/// 左の分類の見出し。選んでいるものは色の帯と明るい地で示す。
class _TabButton extends StatelessWidget {
  const _TabButton({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
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
            child: Row(children: [
              SizedBox(width: 30, child: selected ? const Center(child: BlinkCursor(size: 16)) : null),
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
            ]),
          ),
        ),
      );
}

/// 1 項目。広い枠では名前の右に操作を、狭い枠では名前の下に操作を、どちらも左に寄せて置く。
class _Row extends StatelessWidget {
  const _Row({required this.label, required this.child, this.help, this.enabled = true});
  final String label;
  final String? help;
  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final name = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(label,
          style: TextStyle(
              fontSize: 16,
              color: enabled ? Palette.white : Palette.gray)),
      if (help != null) ...[
        const SizedBox(height: 3),
        Text(help!,
            style: TextStyle(
                fontSize: 12, height: 1.4, color: withAlpha(Palette.pale, 0.55))),
      ],
    ]);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: LayoutBuilder(builder: (context, c) {
        if (c.maxWidth < 560) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            name,
            const SizedBox(height: 10),
            Align(alignment: Alignment.centerLeft, child: child),
          ]);
        }
        return Row(children: [
          SizedBox(width: math.min(c.maxWidth * 0.38, 300), child: name),
          const SizedBox(width: 24),
          Expanded(child: Align(alignment: Alignment.centerLeft, child: child)),
        ]);
      }),
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
          ..color = withAlpha(Palette.pale, 0.3));
  }

  @override
  bool shouldRepaint(_SlantPainter old) => old.color != color || old.on != on;
}

/// いくつかの中から 1 つを選ぶ。
class _Choice<T> extends StatelessWidget {
  const _Choice({required this.value, required this.options, required this.onChanged, required this.color});
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;
  final Color color;

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
                        child: Text(label,
                            style: TextStyle(
                                fontSize: 14,
                                color: k == value ? Dot.ink : withAlpha(Palette.pale, 0.65))),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
}

class _OnOff extends StatelessWidget {
  const _OnOff({required this.value, required this.onChanged, required this.color});
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      _Choice<bool>(value: value, options: const {false: 'OFF', true: 'ON'}, onChanged: onChanged, color: color);
}

/// アーケードの音量計のような目盛り。目盛りを触るかドラッグして変え、−/+ で 1 段ずつ動かす。
class _Meter extends StatelessWidget {
  const _Meter({
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.format,
    required this.onChanged,
    required this.color,
    this.onChangeEnd,
    this.enabled = true,
  });

  final double value, min, max;
  final int divisions;
  final String Function(double) format;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final Color color;
  final bool enabled;

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
  Widget build(BuildContext context) {
    final col = enabled ? color : Palette.gray;
    final k = ((value - min) / (max - min)).clamp(0.0, 1.0);
    // −/+ (48px ずつ) と数値の欄を除いた幅に収める
    return LayoutBuilder(
        builder: (context, outer) => Semantics(
              slider: true,
              value: format(value),
              increasedValue: format(_snap(value + step)),
              decreasedValue: format(_snap(value - step)),
              enabled: enabled,
              onIncrease: enabled ? () => _step(1) : null,
              onDecrease: enabled ? () => _step(-1) : null,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _StepButton(icon: PixelIcons.minus, color: col, onTap: enabled && value > min ? () => _step(-1) : null),
                SizedBox(
                  width: (outer.maxWidth - 176).clamp(60.0, 240.0),
                  child: LayoutBuilder(builder: (context, c) {
                    double at(Offset p) => _snap(min + (p.dx / c.maxWidth).clamp(0.0, 1.0) * (max - min));
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: enabled ? (d) => onChanged(at(d.localPosition)) : null,
                      onTapUp: enabled ? (d) => onChangeEnd?.call(at(d.localPosition)) : null,
                      onHorizontalDragUpdate: enabled ? (d) => onChanged(at(d.localPosition)) : null,
                      onHorizontalDragEnd: enabled ? (_) => onChangeEnd?.call(value) : null,
                      child: SizedBox(height: 44, child: CustomPaint(painter: _MeterPainter(k, col))),
                    );
                  }),
                ),
                _StepButton(icon: PixelIcons.plus, color: col, onTap: enabled && value < max ? () => _step(1) : null),
                SizedBox(
                  width: 76,
                  child: Text(format(value),
                      textAlign: TextAlign.right,
                      style: pixelFont(17, color: col, weight: 800)
                          .copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                ),
              ]),
            ));
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
      final r = Rect.fromLTWH(x, (size.height - h).floorToDouble(), w.floorToDouble(), h.floorToDouble());
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
  const _StepButton({required this.icon, required this.color, required this.onTap});
  final DotSprite icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => IconButton(
        onPressed: onTap,
        icon: PixelIcon(icon, size: 18),
        color: color,
        disabledColor: withAlpha(Palette.pale, 0.2),
        constraints: const BoxConstraints(minWidth: 40, minHeight: 44),
        padding: EdgeInsets.zero,
      );
}

/// 枠付きの小さなボタン (測定する など)。
class _SmallButton extends StatelessWidget {
  const _SmallButton({required this.label, required this.color, required this.onTap, this.icon});
  final String label;
  final DotSprite? icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: CustomPaint(
            painter: _SlantPainter(color: color, on: false),
            child: Container(
              constraints: const BoxConstraints(minHeight: 40, minWidth: 64),
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (icon != null) ...[PixelIcon(icon!, size: 16, color: color), const SizedBox(width: 6)],
                Text(label,
                    style: TextStyle(
                        fontSize: 14, color: color)),
              ]),
            ),
          ),
        ),
      );
}
