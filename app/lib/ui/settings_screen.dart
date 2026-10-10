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

  static const _colors = {
    _Tab.controls: Palette.cyan,
    _Tab.sound: Palette.yellow,
    _Tab.display: Palette.justPink,
    _Tab.other: Palette.pale,
  };

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
    final color = _colors[tab]!;
    final names = {
      _Tab.controls: l.settingsTabControls,
      _Tab.sound: l.settingsTabSound,
      _Tab.display: l.settingsTabDisplay,
      _Tab.other: l.settingsTabOther,
    };

    return Scaffold(
      body: NeonBackground(
        animate: false,
        child: Stack(children: [
          const Positioned.fill(child: Scanlines()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back, color: Palette.cyan),
                    tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: ChromaticTitle(l.menuSettings, size: 26, color: Palette.cyan),
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
                          child: Column(children: [
                            for (final t in tabs)
                              _TabButton(
                                label: names[t]!,
                                color: _colors[t]!,
                                selected: t == tab,
                                onTap: () => setState(() => _tab = t),
                              ),
                          ]),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: const Color(0xB30D0B1C),
                            border: Border(
                              top: BorderSide(color: color, width: 2),
                              left: const BorderSide(color: Palette.hudLine),
                              right: const BorderSide(color: Palette.hudLine),
                              bottom: const BorderSide(color: Palette.hudLine),
                            ),
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
                icon: Icons.timer_outlined,
                color: color,
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
  const _TabButton({required this.label, required this.color, required this.selected, required this.onTap});
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: 54,
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.only(left: 16, right: 8),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [withAlpha(color, selected ? 0.28 : 0.04), withAlpha(color, 0)]),
              border: Border(left: BorderSide(color: selected ? color : withAlpha(color, 0.25), width: 4)),
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
                color: selected ? Palette.white : withAlpha(Palette.pale, 0.6),
                shadows: selected ? [Shadow(color: color, blurRadius: 10)] : null,
                fontFamilyFallback: kFontFallback,
              ),
            ),
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
              fontWeight: FontWeight.w700,
              color: enabled ? Palette.white : Palette.gray,
              fontFamilyFallback: kFontFallback)),
      if (help != null) ...[
        const SizedBox(height: 3),
        Text(help!,
            style: TextStyle(
                fontSize: 12, height: 1.4, color: withAlpha(Palette.pale, 0.55), fontFamilyFallback: kFontFallback)),
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

/// 斜めに切った枠。選んでいるものは色で塗る。
class _SlantPainter extends CustomPainter {
  _SlantPainter({required this.color, required this.on});
  final Color color;
  final bool on;

  @override
  void paint(Canvas canvas, Size size) {
    const s = 10.0;
    final path = Path()
      ..moveTo(s, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width - s, size.height)
      ..lineTo(0, size.height)
      ..close();
    if (on) {
      canvas.drawPath(
          path,
          Paint()
            ..color = withAlpha(color, 0.4)
            ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 8));
    }
    canvas.drawPath(path, Paint()..color = on ? withAlpha(color, 0.3) : const Color(0x33000000));
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = on ? 1.5 : 1
          ..color = on ? color : withAlpha(Palette.pale, 0.25));
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
                                fontWeight: k == value ? FontWeight.w800 : FontWeight.w500,
                                color: k == value ? Palette.white : withAlpha(Palette.pale, 0.65),
                                fontFamilyFallback: kFontFallback)),
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
                _StepButton(icon: Icons.remove, color: col, onTap: enabled && value > min ? () => _step(-1) : null),
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
                _StepButton(icon: Icons.add, color: col, onTap: enabled && value < max ? () => _step(1) : null),
                SizedBox(
                  width: 76,
                  child: Text(format(value),
                      textAlign: TextAlign.right,
                      style: orbitron(17, color: col, weight: 800)
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
    final on = Paint()..color = color;
    final off = Paint()..color = withAlpha(Palette.pale, 0.12);
    final glow = Paint()
      ..color = withAlpha(color, 0.45)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    for (var i = 0; i < _bars; i++) {
      // 右へ行くほど少し高くする
      final h = size.height * (0.45 + 0.4 * i / (_bars - 1));
      final x = i * (w + gap);
      final r = Rect.fromLTWH(x, (size.height - h) / 2 + 2, w, h - 4);
      final path = Path()
        ..moveTo(r.left + math.min(3, w / 3), r.top)
        ..lineTo(r.right, r.top)
        ..lineTo(r.right - math.min(3, w / 3), r.bottom)
        ..lineTo(r.left, r.bottom)
        ..close();
      if (i < lit) {
        canvas.drawPath(path, glow);
        canvas.drawPath(path, on);
      } else {
        canvas.drawPath(path, off);
      }
    }
  }

  @override
  bool shouldRepaint(_MeterPainter old) => old.k != k || old.color != color;
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.color, required this.onTap});
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => IconButton(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
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
  final IconData? icon;
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
                if (icon != null) ...[Icon(icon, size: 16, color: color), const SizedBox(width: 6)],
                Text(label,
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700, color: color, fontFamilyFallback: kFontFallback)),
              ]),
            ),
          ),
        ),
      );
}
