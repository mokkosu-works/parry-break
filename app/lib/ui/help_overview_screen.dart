import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../render/palette.dart';
import '../services/settings.dart';
import 'arcade.dart';
import 'help_diagram.dart';
import 'help_screen.dart';
import 'widgets.dart';

/// 遊び方 (案 1)。動く図と短い説明を 1 画面に並べる。
class HelpOverviewScreen extends ConsumerWidget {
  const HelpOverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final s = ref.watch(settingsProvider);
    final pages = helpPages(l, s.controls);
    return Scaffold(
      body: NeonBackground(
        animate: false,
        child: Stack(
          children: [
            const Positioned.fill(child: Scanlines()),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
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
                            child: ChromaticTitle(l.menuHowToPlay, size: 26, color: Palette.cyan),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, c) {
                          const gap = 20.0;
                          const runGap = 22.0, caption = 56.0;
                          final cols = c.maxWidth > 600 ? 3 : 2;
                          final colW = (c.maxWidth - gap * (cols - 1)) / cols;
                          // 2 段が 1 画面に収まる大きさにする。狭い画面では小さくしすぎず、スクロールさせる
                          final fitW = (c.maxHeight - runGap - caption * 2) / 2 * 5 / 3;
                          final w = math.min(colW, math.max(fitW, 240.0));
                          return SingleChildScrollView(
                            padding: const EdgeInsets.only(bottom: 20),
                            child: Wrap(
                              spacing: gap,
                              runSpacing: runGap,
                              alignment: WrapAlignment.center,
                              children: [
                                for (final p in pages)
                                  SizedBox(
                                    width: w,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        HelpDiagram(topic: p.topic, controls: s.controls, animate: !s.reduceEffects),
                                        const SizedBox(height: 10),
                                        Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Container(
                                              margin: const EdgeInsets.only(top: 4, right: 10),
                                              width: 3,
                                              height: 16,
                                              color: p.color,
                                            ),
                                            Expanded(
                                              child: Text.rich(
                                                TextSpan(
                                                  children: [
                                                    TextSpan(
                                                      text: '${p.title}  ',
                                                      style: orbitron(
                                                        15,
                                                        color: p.color,
                                                        weight: 900,
                                                        letterSpacing: 1.5,
                                                      ),
                                                    ),
                                                    TextSpan(
                                                      text: p.body.replaceAll('\n', ' / '),
                                                      style: TextStyle(
                                                        fontSize: 15,
                                                        height: 1.5,
                                                        color: withAlpha(Palette.white, 0.88),
                                                        fontFamilyFallback: kFontFallback,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
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
    );
  }
}
