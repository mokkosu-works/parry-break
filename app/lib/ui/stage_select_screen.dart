import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../core/core.dart';
import '../game/game_screen.dart';
import '../l10n/app_localizations.dart';
import '../render/palette.dart';
import '../services/content.dart';
import '../services/records.dart';
import '../services/settings.dart';
import 'pixel_icons.dart';
import 'stage_text.dart';
import 'widgets.dart';

/// ステージ選択。章を 1 つずつめくり、ステージをワールドマップのように点線でつないで並べる。
/// 選んだステージの目標・星の条件・記録は右の窓に出し、START で遊ぶ。
/// 難易度は右上で選び、星・クリア・最高スコアは選んだ難易度のものを出す (鍵はどの難易度のクリアでも開く)。
class StageSelectScreen extends ConsumerStatefulWidget {
  const StageSelectScreen({super.key});

  @override
  ConsumerState<StageSelectScreen> createState() => _StageSelectScreenState();
}

class _StageSelectScreenState extends ConsumerState<StageSelectScreen> {
  int? _chapter;
  String? _selected;

  /// 開いたときに選んでおくステージ: 開いていて、まだクリアしていない最初のステージ。
  /// なければ (全部クリア) 最後のステージ。
  StageDef _initial(Campaign c, Records r, bool debug) {
    if (!debug) return r.nextStage(c) ?? c.stages.last;
    for (final st in c.stages) {
      if (!r.clearedAny(st.id)) return st;
    }
    return c.stages.last;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final campaign = ref.watch(contentProvider).campaign;
    final records = ref.watch(recordsProvider);
    final debug = ref.watch(debugModeProvider);
    final diff = ref.watch(settingsProvider.select((s) => s.difficulty));
    StageRecord recordOf(String id) => records.stage(id, diff);
    final totalStars = campaign.stages.fold(0, (s, st) => s + st.stars.length);
    final gotStars = campaign.stages.fold(0, (s, st) => s + recordOf(st.id).starCount);

    final selected = campaign.stage(_selected ?? '') ?? _initial(campaign, records, debug);
    final chapterIndex = _chapter ?? campaign.chapters.indexWhere((c) => c.id == selected.chapterId);
    final chapter = campaign.chapters[chapterIndex];
    bool unlocked(StageDef st) => debug || records.isUnlocked(campaign, st);

    return ScreenFrame(
      title: l.menuStages,
      actions: [
        _DifficultyPicker(
          value: diff,
          label: l.difficulty,
          onChanged: (d) {
            ref.read(audioProvider).play('count');
            ref.read(settingsProvider.notifier).update((s) => s.copyWith(difficulty: d));
          },
        ),
        const SizedBox(width: 16),
        const PixelStar(got: true, size: 22),
        const SizedBox(width: 6),
        Text('$gotStars / $totalStars', style: pixelFont(16)),
        const SizedBox(width: 8),
      ],
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: LayoutBuilder(builder: (context, c) {
          final panelW = math.min(320.0, c.maxWidth * 0.38);
          return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _ChapterPager(
                  title: chapter.title.of(lang),
                  index: chapterIndex,
                  count: campaign.chapters.length,
                  onChange: (i) {
                    ref.read(audioProvider).play('count');
                    setState(() {
                      _chapter = i;
                      // めくった章のうち、遊べる最後のステージを選ぶ
                      final stages = campaign.chapters[i].stages;
                      _selected = (stages.lastWhere(unlocked, orElse: () => stages.first)).id;
                    });
                  },
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: _StageMap(
                    stages: chapter.stages,
                    selected: selected.id,
                    recordOf: recordOf,
                    unlocked: unlocked,
                    onSelect: (st) => setState(() {
                      _selected = st.id;
                      _chapter = chapterIndex;
                    }),
                  ),
                ),
              ]),
            ),
            const SizedBox(width: 16),
            SizedBox(
              width: panelW,
              child: _StageDetail(
                stage: selected,
                title: selected.title.of(lang),
                record: recordOf(selected.id),
                difficulty: diff,
                unlocked: unlocked(selected),
                onStart: () =>
                    Navigator.of(context).push(fadeRoute<void>(GameScreen(stage: selected, difficulty: diff))),
              ),
            ),
          ]);
        }),
      ),
    );
  }
}

/// 「◀ CHAPTER 1  BASICS ▶」。章の数だけ点を並べ、いまの章を黄にする。
class _ChapterPager extends StatelessWidget {
  const _ChapterPager({required this.title, required this.index, required this.count, required this.onChange});
  final String title;
  final int index, count;
  final ValueChanged<int> onChange;

  @override
  Widget build(BuildContext context) {
    Widget arrow(bool next) {
      final to = index + (next ? 1 : -1);
      final enabled = to >= 0 && to < count;
      return IconButton(
        onPressed: enabled ? () => onChange(to) : null,
        color: Palette.sub,
        disabledColor: withAlpha(Palette.pale, 0.15),
        icon: next
            ? Transform.flip(flipX: true, child: PixelIcon(PixelIcons.chevronLeft, size: 21))
            : PixelIcon(PixelIcons.chevronLeft, size: 21),
      );
    }

    return Row(children: [
      arrow(false),
      Expanded(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(title, style: pixelFont(20, color: Palette.main).copyWith(shadows: hardShadow(20, color: Palette.sub))),
          ),
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < count; i++)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == index ? 20 : 8,
                height: 4,
                color: i == index ? Palette.main : Dot.edge,
              ),
          ]),
        ]),
      ),
      arrow(true),
    ]);
  }
}

/// 章のステージを、ジグザグの点線でつないだマップに並べる (1 段 5 つ。偶数段は左から、奇数段は右から)。
class _StageMap extends StatelessWidget {
  const _StageMap({
    required this.stages,
    required this.selected,
    required this.recordOf,
    required this.unlocked,
    required this.onSelect,
  });
  final List<StageDef> stages;
  final String selected;
  final StageRecord Function(String id) recordOf;
  final bool Function(StageDef) unlocked;
  final ValueChanged<StageDef> onSelect;

  static const _cols = 5;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final rows = (stages.length / _cols).ceil();
        final cellW = c.maxWidth / _cols;
        // ブロックは画面の大きさに合わせる (横は列の幅、縦は段の数で決まる上限まで)
        final tileW = math.min(150.0, cellW - 28);
        final tileH = math.max(40.0, math.min(tileW * 0.62, (c.maxHeight - 14) / rows - 46));
        // 1 段の高さ: ブロック + 星 + すき間
        final rowH = tileH + 46;
        // 上下の中央に置く
        final top = math.max(14.0, (c.maxHeight - rowH * rows) / 2 + 14);
        Offset center(int i) {
          final r = i ~/ _cols, k = i % _cols;
          final col = r.isEven ? k : _cols - 1 - k;
          return Offset(cellW * (col + 0.5), top + rowH * r + tileH / 2);
        }

        final centers = [for (var i = 0; i < stages.length; i++) center(i)];
        final cleared = [for (final st in stages) recordOf(st.id).cleared];
        // 段の折り返しは、ブロックの外側を回り込む (星の上を横切らない)
        final turn = tileW / 2 + 12;
        return SingleChildScrollView(
          child: SizedBox(
            height: math.max(c.maxHeight, 14 + rowH * rows),
            child: Stack(children: [
              Positioned.fill(child: CustomPaint(painter: _PathPainter(centers, cleared, turn))),
              for (var i = 0; i < stages.length; i++)
                Positioned(
                  left: centers[i].dx - tileW / 2,
                  top: centers[i].dy - tileH / 2,
                  child: _StageTile(
                    stage: stages[i],
                    record: recordOf(stages[i].id),
                    unlocked: unlocked(stages[i]),
                    selected: stages[i].id == selected,
                    width: tileW,
                    height: tileH,
                    onTap: () => onSelect(stages[i]),
                  ),
                ),
            ]),
          ),
        );
      });
}

/// ステージをつなぐ点線 (コース)。クリアした区間は黄、まだの区間は暗い色。
class _PathPainter extends CustomPainter {
  _PathPainter(this.centers, this.cleared, this.turn);
  final List<Offset> centers;
  final List<bool> cleared;

  /// 段を折り返すとき、ブロックの中心から横へ回り込む距離。
  final double turn;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..isAntiAlias = false;
    void dots(Offset a, Offset b) {
      final d = b - a, len = d.distance;
      for (var t = 0.0; t < len; t += 12) {
        canvas.drawRect(Rect.fromCenter(center: a + d * (t / len), width: 6, height: 6), p);
      }
    }

    for (var i = 0; i + 1 < centers.length; i++) {
      final a = centers[i], b = centers[i + 1];
      p.color = cleared[i] ? Palette.main : Dot.edge;
      if ((a.dy - b.dy).abs() < 1) {
        dots(a, b);
        continue;
      }
      // 外側 (右端の列なら右、左端の列なら左) へ出て下り、次の段へ戻る
      final side = a.dx > size.width / 2 ? turn : -turn;
      final a1 = Offset(a.dx + side, a.dy), b1 = Offset(b.dx + side, b.dy);
      dots(a, a1);
      dots(a1, b1);
      dots(b1, b);
    }
  }

  @override
  bool shouldRepaint(_PathPainter old) => true;
}

/// マップの 1 ステージ。クリア済みは黄のブロック、遊べるが未クリアは赤い枠、開いていなければ灰色と鍵。
/// 選んでいるものは白い枠で囲み、上に ▼ を出す。
class _StageTile extends StatelessWidget {
  const _StageTile({
    required this.stage,
    required this.record,
    required this.unlocked,
    required this.selected,
    required this.width,
    required this.height,
    required this.onTap,
  });
  final StageDef stage;
  final StageRecord record;
  final bool unlocked, selected;
  final double width, height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = Text(stage.id,
        style: pixelFont((height * 0.28).clamp(14.0, 24.0), color: record.cleared ? Dot.ink : unlocked ? Palette.white : Palette.gray));
    final face = record.cleared
        ? BevelBox(color: Palette.main, child: Center(child: label))
        : Container(
            decoration: BoxDecoration(
              color: Dot.night,
              border: Border.all(color: unlocked ? Palette.sub : Dot.edge, width: 3),
            ),
            child: Center(
              child: unlocked
                  ? label
                  : Padding(
                      padding: const EdgeInsets.all(3),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          PixelIcon(PixelIcons.lock, size: 14, color: Palette.gray),
                          const SizedBox(height: 4),
                          label,
                        ]),
                      ),
                    ),
            ),
          );
    return Semantics(
      button: true,
      selected: selected,
      label: stage.id,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: width,
          height: height + 30,
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned(
              left: 0,
              top: 0,
              width: width,
              height: height,
              child: Container(
                decoration: BoxDecoration(
                  boxShadow: const [BoxShadow(color: Colors.black, offset: Offset(4, 4))],
                  border: selected ? Border.all(color: Dot.white, width: 3) : null,
                ),
                padding: selected ? const EdgeInsets.all(2) : EdgeInsets.zero,
                child: face,
              ),
            ),
            // 星 (取ったものは ★)
            Positioned(
              left: 0,
              right: 0,
              top: height + 8,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (var i = 0; i < stage.stars.length; i++) PixelStar(got: record.hasStar(i), size: 14),
              ]),
            ),
            if (selected)
              Positioned(
                left: width / 2 - 8,
                top: -20,
                child: const RotatedBox(quarterTurns: 1, child: BlinkCursor(size: 16)),
              ),
          ]),
        ),
      ),
    );
  }
}

/// 右の窓: 選んだステージの名前・目標・星の条件・記録と START。
class _StageDetail extends StatelessWidget {
  const _StageDetail({
    required this.stage,
    required this.title,
    required this.record,
    required this.difficulty,
    required this.unlocked,
    required this.onStart,
  });
  final StageDef stage;
  final String title;
  final StageRecord record;
  final Difficulty difficulty;
  final bool unlocked;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return PixelWindow(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('STAGE ${stage.id}', style: pixelFont(14, color: Palette.sub, letterSpacing: 2)),
          const Spacer(),
          Text(difficulty.label, style: pixelFont(14, color: difficultyColor(difficulty), letterSpacing: 2)),
        ]),
        const SizedBox(height: 6),
        Text(title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: pixelFont(22, color: Palette.white).copyWith(shadows: hardShadow(22), height: 1.2)),
        const SizedBox(height: 10),
        Container(height: 2, color: Dot.edge),
        const SizedBox(height: 10),
        Expanded(
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(goalText(l, stage), style: const TextStyle(fontSize: 15, color: Palette.main)),
              const SizedBox(height: 4),
              Text(difficultyText(l, difficulty), style: TextStyle(fontSize: 12, color: difficultyColor(difficulty))),
              const SizedBox(height: 10),
              for (var i = 0; i < stage.stars.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    PixelStar(got: record.hasStar(i), size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(starText(l, stage.stars[i]),
                          style: TextStyle(fontSize: 14, color: record.hasStar(i) ? Palette.white : Palette.pale)),
                    ),
                  ]),
                ),
              if (record.bestScore > 0) ...[
                const SizedBox(height: 6),
                Row(children: [
                  Text('BEST', style: pixelFont(12, color: Palette.main, letterSpacing: 2)),
                  const SizedBox(width: 10),
                  Text(formatScore(record.bestScore), style: pixelFont(18)),
                ]),
              ],
            ]),
          ),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: unlocked
              ? PixelButton(label: 'START', filled: true, icon: PixelIcons.play, onPressed: onStart)
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  PixelIcon(PixelIcons.lock, size: 14, color: Palette.gray),
                  const SizedBox(width: 8),
                  Text('LOCKED', style: pixelFont(14, color: Palette.gray, letterSpacing: 2)),
                ]),
        ),
      ]),
    );
  }
}

/// 難易度の切り替え (EASY / NORMAL / HARD)。選んでいるものは難易度の色で塗る。
class _DifficultyPicker extends StatelessWidget {
  const _DifficultyPicker({required this.value, required this.label, required this.onChanged});
  final Difficulty value;
  final String label;
  final ValueChanged<Difficulty> onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
        label: label,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (final d in Difficulty.values)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Semantics(
                button: true,
                selected: d == value,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(d),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: d == value ? difficultyColor(d) : Dot.night,
                      border: Border.all(color: d == value ? difficultyColor(d) : Dot.edge, width: 3),
                    ),
                    child: Text(d.label,
                        style: pixelFont(13, color: d == value ? Dot.ink : Palette.gray, letterSpacing: 1.5)),
                  ),
                ),
              ),
            ),
        ]),
      );
}
