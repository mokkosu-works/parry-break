import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../l10n/app_localizations.dart';
import '../render/palette.dart';
import '../services/ads.dart';
import '../services/settings.dart';
import 'calibration_screen.dart';
import 'widgets.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final ads = ref.read(adsProvider);
    void volumes(Settings v) => ref.read(audioProvider).setVolumes(bgm: v.bgmVolume, sfx: v.sfxVolume);

    return ScreenFrame(
      title: l.menuSettings,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _Section(l.settingsControls, [
            SegmentedButton<ControlScheme>(
              segments: [
                ButtonSegment(value: ControlScheme.zones, label: Text(l.controlsZones)),
                ButtonSegment(value: ControlScheme.railHorizontal, label: Text(l.controlsRailH)),
                ButtonSegment(value: ControlScheme.railVertical, label: Text(l.controlsRailV)),
              ],
              selected: {s.controls},
              onSelectionChanged: (v) => n.update((x) => x.copyWith(controls: v.first)),
            ),
          ]),
          _SliderTile(
            label: l.settingsSensitivity,
            value: s.sensitivity,
            min: 1,
            max: 4,
            divisions: 30,
            display: '×${s.sensitivity.toStringAsFixed(1)}',
            enabled: s.controls == ControlScheme.zones,
            onChanged: (v) => n.update((x) => x.copyWith(sensitivity: v)),
          ),
          _SliderTile(
            label: l.settingsTiming,
            help: l.settingsTimingHelp,
            value: s.timingOffsetMs.toDouble(),
            min: 0,
            max: 100,
            divisions: 100,
            display: '${s.timingOffsetMs}ms',
            onChanged: (v) => n.update((x) => x.copyWith(timingOffsetMs: v.round())),
            trailing: TextButton.icon(
              onPressed: () => Navigator.of(context).push(fadeRoute(const CalibrationScreen())),
              icon: const Icon(Icons.timer_outlined),
              label: Text(l.calibrate),
            ),
          ),
          _SliderTile(
            label: l.settingsBgm,
            value: s.bgmVolume,
            min: 0,
            max: 1,
            divisions: 20,
            display: '${(s.bgmVolume * 100).round()}%',
            onChanged: (v) {
              n.update((x) => x.copyWith(bgmVolume: v));
              volumes(ref.read(settingsProvider));
            },
          ),
          _SliderTile(
            label: l.settingsSfx,
            value: s.sfxVolume,
            min: 0,
            max: 1,
            divisions: 20,
            display: '${(s.sfxVolume * 100).round()}%',
            onChanged: (v) {
              n.update((x) => x.copyWith(sfxVolume: v));
              volumes(ref.read(settingsProvider));
            },
            onChangeEnd: (_) => ref.read(audioProvider).play('perfect'),
          ),
          SwitchListTile(
            title: Text(l.settingsHaptics),
            value: s.haptics,
            onChanged: (v) {
              n.update((x) => x.copyWith(haptics: v));
              ref.read(hapticsProvider).selection();
            },
          ),
          _Section(l.settingsQuality, [
            SegmentedButton<GraphicsQuality>(
              segments: [
                ButtonSegment(value: GraphicsQuality.high, label: Text(l.qualityHigh)),
                ButtonSegment(value: GraphicsQuality.low, label: Text(l.qualityLow)),
              ],
              selected: {s.quality},
              onSelectionChanged: (v) => n.update((x) => x.copyWith(quality: v.first)),
            ),
          ]),
          SwitchListTile(
            title: Text(l.settingsReduceEffects),
            subtitle: Text(l.settingsReduceEffectsHelp),
            value: s.reduceEffects,
            onChanged: (v) => n.update((x) => x.copyWith(reduceEffects: v)),
          ),
          _Section(l.settingsLanguage, [
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: '', label: Text(l.languageSystem)),
                const ButtonSegment(value: 'ja', label: Text('日本語')),
                const ButtonSegment(value: 'en', label: Text('English')),
              ],
              selected: {s.language ?? ''},
              onSelectionChanged: (v) => n.update((x) => x.copyWith(language: () => v.first.isEmpty ? null : v.first)),
            ),
          ]),
          // 同意が必要な地域 (EU など) では、同意をいつでも変えられる入口を置く
          if (ads.privacyOptionsRequired)
            ListTile(
              title: Text(l.settingsAdPrivacy),
              trailing: const Icon(Icons.chevron_right),
              onTap: ads.showPrivacyOptions,
            ),
          if (s.debugMode)
            SwitchListTile(
              title: Text(l.settingsDebugMode),
              subtitle: Text(l.settingsDebugModeHelp),
              value: true,
              onChanged: (v) => n.update((x) => x.copyWith(debugMode: v)),
            ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.label, this.children);
  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 8),
          SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: children)),
        ]),
      );
}

class _SliderTile extends StatelessWidget {
  const _SliderTile({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.display,
    required this.onChanged,
    this.onChangeEnd,
    this.help,
    this.trailing,
    this.enabled = true,
  });

  final String label, display;
  final String? help;
  final double value, min, max;
  final int divisions;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final Widget? trailing;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(label, style: TextStyle(fontSize: 16, color: enabled ? null : Palette.gray))),
            Text(display, style: orbitron(15, color: enabled ? Palette.cyan : Palette.gray)),
            ?trailing,
          ]),
          if (help != null) Text(help!, style: const TextStyle(fontSize: 12, color: Palette.gray)),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: enabled ? onChanged : null,
            onChangeEnd: onChangeEnd,
          ),
        ]),
      );
}
