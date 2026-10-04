import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../render/palette.dart';
import '../services/settings.dart';
import 'widgets.dart';

class HelpScreen extends ConsumerWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final zones = ref.watch(settingsProvider).controls == ControlScheme.zones;
    final cards = [
      (Icons.swap_horiz, l.helpMoveTitle, zones ? l.helpMoveZones : l.helpMoveRail, Palette.cyan),
      (Icons.touch_app, l.helpParryTitle, zones ? l.helpParryZones : l.helpParryRail, const Color(0xFFFFB8ED)),
      (Icons.gps_fixed, l.helpTimingTitle, l.helpTimingBody, Palette.yellow),
      (Icons.account_tree_outlined, l.helpChainTitle, l.helpChainBody, Palette.orange),
      (Icons.south, l.helpOverTitle, l.helpOverBody, Palette.red),
      (Icons.pause, l.helpPauseTitle, l.helpPauseBody, Palette.cyan),
    ];
    return ScreenFrame(
      title: l.menuHowToPlay,
      child: LayoutBuilder(builder: (context, c) {
        final cols = c.maxWidth > 720 ? 3 : 2;
        return GridView.count(
          crossAxisCount: cols,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.7,
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            for (final (icon, title, body, color) in cards)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF16152A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF343352)),
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(icon, color: color, size: 32, shadows: [Shadow(color: withAlpha(color, 0.6), blurRadius: 6)]),
                  const SizedBox(height: 6),
                  Text(title, style: orbitron(17, color: Palette.cyan)),
                  const SizedBox(height: 4),
                  Flexible(
                    child: Text(body,
                        textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, height: 1.35, color: Palette.white)),
                  ),
                ]),
              ),
          ],
        );
      }),
    );
  }
}
