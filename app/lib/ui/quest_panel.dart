import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../render/palette.dart';
import '../services/quests.dart';
import 'quest_text.dart';
import 'widgets.dart';

/// 今日のお題のパネル (タイトルの `TODAY 1/3` から開く)。3 つのお題と進みの棒、報酬を出す。
/// 狭い画面では中身が縦に収まらないので、パネルの中だけ送れる。
Future<void> showQuestPanel(BuildContext context, QuestBoard board) =>
    showDialog<void>(
      context: context,
      builder: (_) => _QuestPanel(board: board),
    );

class _QuestPanel extends StatelessWidget {
  const _QuestPanel({required this.board});
  final QuestBoard board;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(12),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: PixelWindow(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            // 端末の文字を大きくしても収まるよう、拡大は 1.2 倍まで
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.2,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            "TODAY'S QUESTS",
                            style: pixelFont(
                              16,
                              color: Palette.main,
                              weight: 800,
                              letterSpacing: 2,
                            ),
                          ),
                        ),
                      ),
                      Text(
                        '${board.doneCount}/${board.quests.length}',
                        style: pixelFont(16, weight: 800, letterSpacing: 2),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final q in board.quests) _QuestRow(quest: q),
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              l.questAllBonus(QuestRules.standard.allClear),
                              style: pixelFont(
                                12,
                                color: board.allDone
                                    ? Dot.mint
                                    : withAlpha(Palette.pale, 0.85),
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    child: PixelButton(
                      label: 'CLOSE',
                      fontSize: 16,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// お題 1 つ: 説明文、進みの棒と数、報酬。
class _QuestRow extends StatelessWidget {
  const _QuestRow({required this.quest});
  final Quest quest;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final done = quest.done;
    final color = done ? Dot.mint : Palette.main;
    const tab = [FontFeature.tabularFigures()];
    final text = questText(l, quest);
    return Semantics(
      label:
          '$text ${questCount(quest)}'
          '${done ? ' ${l.questDone}' : ''}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              text,
              style: pixelFont(13, color: done ? Palette.gray : Palette.white),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 10,
                    decoration: BoxDecoration(
                      color: Dot.night,
                      border: Border.all(color: Dot.edge, width: 2),
                    ),
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: quest.fraction,
                      child: ColoredBox(color: color),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  done ? l.questDone : questCount(quest),
                  style: pixelFont(
                    11,
                    color: color,
                    letterSpacing: 1,
                  ).copyWith(fontFeatures: tab),
                ),
                const SizedBox(width: 10),
                Text(
                  '+${quest.xp} XP',
                  style: pixelFont(
                    12,
                    color: done ? Palette.gray : Palette.yellow,
                    letterSpacing: 1,
                  ).copyWith(fontFeatures: tab),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
