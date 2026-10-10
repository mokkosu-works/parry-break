import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../render/palette.dart';
import '../services/settings.dart';
import 'arcade.dart';
import 'help_diagram.dart';
import 'widgets.dart';

/// 遊び方の 1 ページ分の中身。
typedef HelpPage = ({HelpTopic topic, String title, String body, Color color});

List<HelpPage> helpPages(AppLocalizations l, ControlScheme controls) {
  final zones = controls == ControlScheme.zones;
  return [
    (
      topic: HelpTopic.move,
      title: l.helpMoveTitle,
      body: zones ? l.helpMoveZones : l.helpMoveRail,
      color: Palette.cyan,
    ),
    (
      topic: HelpTopic.parry,
      title: l.helpParryTitle,
      body: zones ? l.helpParryZones : l.helpParryRail,
      color: Palette.yellow,
    ),
    (topic: HelpTopic.timing, title: l.helpTimingTitle, body: l.helpTimingBody, color: Palette.justPink),
    (topic: HelpTopic.chain, title: l.helpChainTitle, body: l.helpChainBody, color: Palette.orange),
    (topic: HelpTopic.over, title: l.helpOverTitle, body: l.helpOverBody, color: Palette.red),
    (topic: HelpTopic.pause, title: l.helpPauseTitle, body: l.helpPauseBody, color: Palette.pale),
  ];
}

/// 遊び方。1 ページに 1 項目を、動く図と短い説明で見せる。左右のスワイプかボタンでめくる。
class HelpScreen extends ConsumerStatefulWidget {
  const HelpScreen({super.key});

  @override
  ConsumerState<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends ConsumerState<HelpScreen> {
  final PageController _pages = PageController();
  int _index = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _go(int i, int count) {
    if (i < 0) return;
    if (i >= count) {
      Navigator.of(context).maybePop();
      return;
    }
    _pages.animateToPage(i, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final s = ref.watch(settingsProvider);
    final pages = helpPages(l, s.controls);
    final last = _index == pages.length - 1;
    final page = pages[_index];
    return Scaffold(
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _go(_index - 1, pages.length),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () => _go(_index + 1, pages.length),
        },
        child: Focus(
          autofocus: true,
          child: DotBackground(
            animate: false,
            child: Stack(
              children: [
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
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
                            Expanded(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: PixelTitle(l.menuHowToPlay, size: 26, color: Palette.cyan),
                              ),
                            ),
                            Text('${_index + 1}'.padLeft(2, '0'), style: pixelFont(22, color: page.color, weight: 900)),
                            Text(
                              ' / ${pages.length.toString().padLeft(2, '0')}',
                              style: pixelFont(14, color: withAlpha(Palette.pale, 0.5), weight: 700),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: PageView.builder(
                            controller: _pages,
                            itemCount: pages.length,
                            onPageChanged: (i) => setState(() => _index = i),
                            itemBuilder: (context, i) =>
                                _Page(page: pages[i], controls: s.controls, animate: !s.reduceEffects && i == _index),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            IconButton(
                              onPressed: _index == 0 ? null : () => _go(_index - 1, pages.length),
                              icon: const Icon(Icons.chevron_left),
                              color: Palette.cyan,
                              disabledColor: withAlpha(Palette.pale, 0.2),
                              tooltip: l.helpPrev,
                            ),
                            const Spacer(),
                            for (var i = 0; i < pages.length; i++)
                              GestureDetector(
                                onTap: () => _go(i, pages.length),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  margin: const EdgeInsets.symmetric(horizontal: 4),
                                  width: i == _index ? 26 : 10,
                                  height: 6,
                                  color: i == _index ? page.color : withAlpha(Palette.pale, i < _index ? 0.5 : 0.18),
                                ),
                              ),
                            const Spacer(),
                            PixelButton(
                              label: last ? l.back : l.helpNext,
                              filled: last,
                              color: page.color,
                              onPressed: () => _go(_index + 1, pages.length),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({required this.page, required this.controls, required this.animate});
  final HelpPage page;
  final ControlScheme controls;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final diagram = HelpDiagram(topic: page.topic, controls: controls, animate: animate);
    return LayoutBuilder(
      builder: (context, c) {
        // 背の低い画面 (スマホの横向き) では文字を小さくして、説明が 1 画面に収まるようにする
        final compact = c.maxHeight < 420;
        final words = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(page.title,
                style: pixelFont(compact ? 22 : 30, color: page.color, weight: 900, letterSpacing: 2)
                    .copyWith(shadows: hardShadow(compact ? 22 : 30, color: Dot.dark(page.color)))),
            Container(
                margin: EdgeInsets.symmetric(vertical: compact ? 10 : 14), width: 48, height: 3, color: page.color),
            // 改行ごとに 1 つの段落にする
            for (final line in page.body.split('\n'))
              Padding(
                padding: EdgeInsets.only(bottom: compact ? 8 : 12),
                child: Text(line,
                    style: TextStyle(
                        fontSize: compact ? 14 : 18,
                        height: 1.55,
                        color: withAlpha(Palette.white, 0.92),
                        fontFamilyFallback: kFontFallback)),
              ),
          ],
        );
        // 横長なら図と説明を左右に、縦に余裕があれば上下に並べる
        if (c.maxWidth / c.maxHeight > 1.3) {
          return Row(
            children: [
              Expanded(flex: compact ? 1 : 3, child: Center(child: diagram)),
              SizedBox(width: compact ? 24 : 32),
              Expanded(flex: compact ? 1 : 2, child: SingleChildScrollView(child: words)),
            ],
          );
        }
        return Column(
          children: [
            Flexible(child: Center(child: diagram)),
            const SizedBox(height: 16),
            words,
          ],
        );
      },
    );
  }
}
