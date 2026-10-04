import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../render/palette.dart';
import '../services/settings.dart';
import 'arcade.dart';
import 'widgets.dart';

/// 遊び方。番号付きの斜めに切ったパネルを並べるアーケード調の画面。
class HelpScreen extends ConsumerWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final zones = ref.watch(settingsProvider).controls == ControlScheme.zones;
    final cards = [
      (Icons.swap_horiz, l.helpMoveTitle, zones ? l.helpMoveZones : l.helpMoveRail, Palette.cyan),
      (Icons.touch_app, l.helpParryTitle, zones ? l.helpParryZones : l.helpParryRail, Palette.justPink),
      (Icons.gps_fixed, l.helpTimingTitle, l.helpTimingBody, Palette.yellow),
      (Icons.account_tree_outlined, l.helpChainTitle, l.helpChainBody, Palette.orange),
      (Icons.south, l.helpOverTitle, l.helpOverBody, Palette.red),
      (Icons.pause, l.helpPauseTitle, l.helpPauseBody, Palette.pale),
    ];
    return Scaffold(
      body: NeonBackground(
        animate: false,
        child: Stack(children: [
          const Positioned.fill(child: Scanlines()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back, color: Palette.cyan),
                    tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: ChromaticTitle(l.menuHowToPlay, size: 30, color: Palette.cyan),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(child: Container(height: 2, color: withAlpha(Palette.cyan, 0.35))),
                ]),
                const SizedBox(height: 12),
                Expanded(
                  child: LayoutBuilder(builder: (context, c) {
                    final cols = c.maxWidth > 720 ? 3 : 2;
                    final rows = (cards.length / cols).ceil();
                    const gap = 12.0;
                    final w = (c.maxWidth - gap * (cols - 1)) / cols;
                    final h = (c.maxHeight - gap * (rows - 1)) / rows;
                    return SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Wrap(spacing: gap, runSpacing: gap, children: [
                        for (var i = 0; i < cards.length; i++)
                          SizedBox(
                            width: w,
                            height: h.clamp(104.0, 280.0),
                            child: _HelpPanel(
                              index: i + 1,
                              icon: cards[i].$1,
                              title: cards[i].$2,
                              body: cards[i].$3,
                              color: cards[i].$4,
                            ),
                          ),
                      ]),
                    );
                  }),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _HelpPanel extends StatelessWidget {
  const _HelpPanel({required this.index, required this.icon, required this.title, required this.body, required this.color});
  final int index;
  final IconData icon;
  final String title, body;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _PanelPainter(color),
      child: Stack(children: [
        // 背景の大きな番号 (線だけ)
        Positioned(
          right: 14,
          bottom: -4,
          child: Text(
            index.toString().padLeft(2, '0'),
            style: orbitron(64, weight: 900).copyWith(
              height: 1,
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.5
                ..color = withAlpha(color, 0.28),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 12, 14, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, color: color, size: 22, shadows: [Shadow(color: withAlpha(color, 0.8), blurRadius: 8)]),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: orbitron(17, color: color, weight: 800, letterSpacing: 2)),
              ),
            ]),
            const SizedBox(height: 8),
            Expanded(
              child: Text(body,
                  style: TextStyle(fontSize: 16, height: 1.5, color: withAlpha(Palette.white, 0.92), fontFamilyFallback: kFontFallback)),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// 右上を斜めに切り、左端に色つきの帯を置いたパネル。
class _PanelPainter extends CustomPainter {
  _PanelPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const cut = 18.0;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width - cut, 0)
      ..lineTo(size.width, cut)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(colors: [withAlpha(color, 0.14), const Color(0xCC0D0B1C)])
              .createShader(Offset.zero & size));
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = withAlpha(color, 0.4));
    canvas.drawRect(Rect.fromLTWH(0, 0, 5, size.height), Paint()..color = color);
    canvas.drawRect(
        Rect.fromLTWH(0, 0, 5, size.height),
        Paint()
          ..color = withAlpha(color, 0.5)
          ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 6));
  }

  @override
  bool shouldRepaint(_PanelPainter old) => old.color != color;
}
