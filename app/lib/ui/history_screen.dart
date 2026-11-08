import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/core.dart';
import '../l10n/app_localizations.dart';
import '../render/palette.dart';
import '../services/history.dart';
import 'widgets.dart';

/// 最近のプレイの履歴 (新しい順に最大 [PlayHistory.maxEntries] 件)。
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final entries = ref.watch(historyProvider).entries;
    return ScreenFrame(
      title: l.menuHistory,
      actions: [
        if (entries.isNotEmpty)
          Text('${entries.length} / ${PlayHistory.maxEntries}', style: pixelFont(14, color: Palette.pale)),
        const SizedBox(width: 8),
      ],
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: PixelWindow(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: entries.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(l.historyEmpty,
                        textAlign: TextAlign.center, style: pixelFont(16, color: Palette.pale, weight: 400)),
                  ),
                )
              : ListView.separated(
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => Container(height: 1, color: Dot.edge),
                  itemBuilder: (context, i) => HistoryRow(entry: entries[i], latest: i == 0),
                ),
        ),
      ),
    );
  }
}

/// `2026/11/08 14:05` (端末の時刻で)。
String formatPlayedAt(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}/${two(t.month)}/${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}

/// 履歴の 1 行: 日時・モード・(到達ラウンド / クリアしたか)・スコア。
class HistoryRow extends StatelessWidget {
  const HistoryRow({super.key, required this.entry, this.latest = false});
  final PlayEntry entry;
  final bool latest;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    const tab = [FontFeature.tabularFigures()];
    final e = entry;
    final mode = e.endless ? l.menuEndless : 'STAGE ${e.stageId}  ${e.difficulty.label}';
    final (detail, detailColor) = e.endless
        ? (l.roundN(e.round.toString().padLeft(2, '0')), Palette.pale)
        : e.cleared
            ? (l.historyCleared, Dot.mint)
            : (l.historyFailed, Palette.sub);
    Widget cell(String text, TextStyle style, {TextAlign align = TextAlign.left}) => FittedBox(
          fit: BoxFit.scaleDown,
          alignment: align == TextAlign.right ? Alignment.centerRight : Alignment.centerLeft,
          child: Text(text, maxLines: 1, style: style.copyWith(fontFeatures: tab)),
        );
    return SizedBox(
      height: 40,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          SizedBox(width: 14, child: latest ? const BlinkCursor(size: 12) : null),
          const SizedBox(width: 6),
          Expanded(flex: 5, child: cell(formatPlayedAt(e.at), pixelFont(12, color: Palette.gray, letterSpacing: 1))),
          const SizedBox(width: 12),
          Expanded(flex: 5, child: cell(mode, pixelFont(14, color: e.endless ? Palette.accent : Palette.white))),
          const SizedBox(width: 12),
          Expanded(flex: 3, child: cell(detail, pixelFont(13, color: detailColor))),
          const SizedBox(width: 12),
          Expanded(
            flex: 4,
            child: cell(formatScore(e.score), pixelFont(16, weight: 900, color: Palette.yellow), align: TextAlign.right),
          ),
        ]),
      ),
    );
  }
}
