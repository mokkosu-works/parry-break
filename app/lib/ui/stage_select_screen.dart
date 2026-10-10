import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../core/core.dart';
import '../game/game_screen.dart';
import '../l10n/app_localizations.dart';
import '../render/palette.dart';
import '../services/content.dart';
import '../services/records.dart';
import 'stage_text.dart';
import 'widgets.dart';

/// ステージ選択。章ごとにステージを並べ、選ぶと目標と星の条件を出す。
class StageSelectScreen extends ConsumerWidget {
  const StageSelectScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final campaign = ref.watch(contentProvider).campaign;
    final records = ref.watch(recordsProvider);
    final debug = ref.watch(debugModeProvider);
    final totalStars = campaign.stages.fold(0, (s, st) => s + st.stars.length);
    final gotStars = campaign.stages.fold(0, (s, st) => s + records.stage(st.id).starCount);

    return ScreenFrame(
      title: l.menuStages,
      actions: [
        const PixelStar(got: true, size: 22),
        const SizedBox(width: 4),
        Text('$gotStars / $totalStars', style: pixelFont(16)),
        const SizedBox(width: 8),
      ],
      child: ListView(
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          for (final ch in campaign.chapters) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
              child: Text(ch.title.of(lang), style: pixelFont(18, color: Palette.magenta, weight: 800)),
            ),
            Wrap(spacing: 10, runSpacing: 10, children: [
              for (final st in ch.stages)
                _StageTile(
                  stage: st,
                  title: st.title.of(lang),
                  record: records.stage(st.id),
                  unlocked: debug || records.isUnlocked(campaign, st),
                  onTap: () => _showDetail(context, l, st, st.title.of(lang), records.stage(st.id)),
                ),
            ]),
          ],
        ],
      ),
    );
  }

  void _showDetail(BuildContext context, AppLocalizations l, StageDef st, String title, StageRecord rec) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: const RoundedRectangleBorder(side: BorderSide(color: Palette.cyan, width: 3)),
        title: Text('${st.id}  $title', style: pixelFont(20, weight: 800)),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(goalText(l, st), style: const TextStyle(color: Palette.cyan, fontSize: 15)),
            const SizedBox(height: 10),
            for (var i = 0; i < st.stars.length; i++)
              StarLine(achieved: rec.hasStar(i), text: starText(l, st.stars[i])),
            if (rec.bestScore > 0) ...[
              const SizedBox(height: 8),
              Text('BEST  ${formatScore(rec.bestScore)}', style: pixelFont(15, color: Palette.pale)),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(l.back)),
          PixelButton(
            label: 'START',
            filled: true,
            icon: Icons.play_arrow,
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).push(fadeRoute<void>(GameScreen(stage: st)));
            },
          ),
        ],
      ),
    );
  }
}

class _StageTile extends StatelessWidget {
  const _StageTile({
    required this.stage,
    required this.title,
    required this.record,
    required this.unlocked,
    required this.onTap,
  });
  final StageDef stage;
  final String title;
  final StageRecord record;
  final bool unlocked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = record.cleared ? Palette.cyan : unlocked ? Palette.pale : Palette.gray;
    return Opacity(
      opacity: unlocked ? 1 : 0.45,
      child: GestureDetector(
        onTap: unlocked ? onTap : null,
        child: Container(
          width: 148,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Dot.night,
            border: Border.all(color: c, width: record.cleared ? 3 : 2),
            boxShadow: unlocked ? const [BoxShadow(color: Colors.black, offset: Offset(4, 4))] : null,
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(stage.id, style: pixelFont(18, color: c, weight: 900)),
              const Spacer(),
              if (!unlocked) const Icon(Icons.lock, size: 16, color: Palette.gray),
            ]),
            const SizedBox(height: 4),
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Palette.white)),
            const SizedBox(height: 6),
            Row(children: [
              for (var i = 0; i < stage.stars.length; i++) PixelStar(got: record.hasStar(i)),
            ]),
          ]),
        ),
      ),
    );
  }
}
