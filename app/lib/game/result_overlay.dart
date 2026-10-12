import 'package:flutter/material.dart';

import '../core/core.dart';
import '../l10n/app_localizations.dart';
import '../render/palette.dart';
import '../ui/arcade.dart';
import '../ui/stage_text.dart';
import '../ui/widgets.dart';
import '../ui/pixel_icons.dart';

/// 結果画面に出す内容。
class ResultData {
  const ResultData({
    required this.score,
    required this.round,
    required this.maxChain,
    required this.stats,
    required this.reason,
    required this.newBest,
    required this.bestScore,
    required this.bestRound,
    this.stage,
    this.difficulty = Difficulty.normal,
    this.cleared = false,
    this.achieved,
  });

  final int score, round, maxChain, bestScore, bestRound;
  final RunStats stats;
  final String reason;
  final bool newBest, cleared;
  final StageDef? stage;
  final Difficulty difficulty;

  /// 今回達成した星 (ステージのみ)。
  final List<bool>? achieved;
}

/// ゲームオーバー / ステージの結果画面。見出し → スコアの数え上げ → 記録更新のハンコ → 成績・星 → ボタン の順に出る。
/// どこかをタップすると演出を飛ばす。
class ResultOverlay extends StatefulWidget {
  const ResultOverlay({
    super.key,
    required this.data,
    required this.onRetry,
    required this.onTitle,
    this.onNext,
    this.onStageSelect,
    this.onNewRecord,
    this.reduceMotion = false,
  });

  final ResultData data;
  final VoidCallback onRetry, onTitle;
  final VoidCallback? onNext, onStageSelect;

  /// 記録更新のハンコが押された瞬間 (効果音用)。
  final VoidCallback? onNewRecord;
  final bool reduceMotion;

  @override
  State<ResultOverlay> createState() => _ResultOverlayState();
}

class _ResultOverlayState extends State<ResultOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );
  bool _stamped = false;

  @override
  void initState() {
    super.initState();
    if (widget.reduceMotion) {
      _c.value = 1;
    } else {
      _c.forward();
    }
    _c.addListener(() {
      if (!_stamped && widget.data.newBest && _c.value >= 0.56) {
        _stamped = true;
        widget.onNewRecord?.call();
      }
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// [a]〜[b] の間に 0 → 1 になる進み具合。
  double _p(double a, double b, [Curve curve = Curves.easeOutCubic]) =>
      curve.transform(((_c.value - a) / (b - a)).clamp(0.0, 1.0));

  Widget _in(
    double a,
    double b,
    Widget child, {
    Offset from = const Offset(0, 16),
  }) {
    final t = _p(a, b);
    return Opacity(
      opacity: t,
      child: Transform.translate(offset: from * (1 - t), child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final d = widget.data, stage = d.stage;
    final win = stage != null && d.cleared;
    final title = stage == null
        ? 'GAME OVER'
        : (win ? 'STAGE CLEAR' : 'STAGE FAILED');
    // 勝ちはメインカラー (黄)、負けはアクセントカラー (赤)
    final color = win ? Palette.main : Palette.sub;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        if (_c.value < 1) _c.value = 1;
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: withAlpha(Dot.ink, 0.88)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                // 後ろの盤面が透けて読みにくくならないよう、窓の中に置く
                child: PixelWindow(
                  padding: const EdgeInsets.fromLTRB(28, 22, 28, 26),
                  child: SizedBox(
                  width: 1000,
                  height: 470,
                  child: AnimatedBuilder(
                    animation: _c,
                    builder: (context, _) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 見出し (後ろに帯)
                        _in(
                          0,
                          0.16,
                          CustomPaint(
                            painter: _Backdrop(color),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  const SizedBox(width: 16),
                                  PixelTitle(title, size: 64, color: color),
                                  const SizedBox(width: 26),
                                  // 難易度とミスの理由が並ぶと幅が足りないことがあるので、縮めて収める
                                  Flexible(
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerLeft,
                                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                                        if (stage != null) ...[
                                          PixelTag(
                                            'STAGE ${stage.id}',
                                            color: Palette.sub,
                                          ),
                                          const SizedBox(width: 10),
                                          PixelTag(d.difficulty.label, color: difficultyColor(d.difficulty)),
                                          const SizedBox(width: 10),
                                        ],
                                        if (!win)
                                          PixelTag(d.reason, color: Palette.sub),
                                      ]),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          from: const Offset(-60, 0),
                        ),
                        const SizedBox(height: 26),
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 11, child: _score(d)),
                              Container(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 28,
                                ),
                                width: 2,
                                color: withAlpha(Dot.edge, _p(0.3, 0.5)),
                              ),
                              Expanded(
                                flex: 9,
                                child: stage == null
                                    ? _stats(d)
                                    : _stars(l, d, stage),
                              ),
                            ],
                          ),
                        ),
                        _in(
                          0.78,
                          0.95,
                          Wrap(
                            spacing: 14,
                            runSpacing: 10,
                            children: [
                              if (widget.onNext != null)
                                PixelButton(
                                  label: 'NEXT STAGE',
                                  filled: true,
                                  icon: PixelIcons.skipNext,
                                  onPressed: widget.onNext,
                                ),
                              PixelButton(
                                label: 'RETRY',
                                filled: widget.onNext == null,
                                icon: PixelIcons.replay,
                                onPressed: widget.onRetry,
                              ),
                              if (widget.onStageSelect != null)
                                PixelButton(
                                  label: 'STAGES',
                                  icon: PixelIcons.grid,
                                  onPressed: widget.onStageSelect,
                                ),
                              PixelButton(
                                label: 'TITLE',
                                color: Palette.gray,
                                icon: PixelIcons.home,
                                onPressed: widget.onTitle,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// スコア (数え上げ) と記録更新のハンコ。
  Widget _score(ResultData d) {
    final t = _p(0.12, 0.55, Curves.easeOutQuart);
    final shown = (d.score * t).round();
    final stampT = _p(0.56, 0.66, Curves.easeOutBack);
    const tab = [FontFeature.tabularFigures()];
    return _in(
      0.1,
      0.25,
      Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SCORE',
                style: pixelFont(16, color: Palette.pale, letterSpacing: 4),
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  formatScore(shown),
                  style: pixelFont(84, weight: 900, letterSpacing: 2).copyWith(
                    fontFeatures: tab,
                    height: 1,
                    shadows: hardShadow(84),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Container(width: 4, height: 30, color: Palette.main),
                  const SizedBox(width: 10),
                  Text(
                    'HI-SCORE',
                    style: pixelFont(
                      14,
                      color: Palette.main,
                      letterSpacing: 4,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    formatScore(d.bestScore),
                    style: pixelFont(
                      22,
                      weight: 900,
                    ).copyWith(fontFeatures: tab),
                  ),
                ],
              ),
              if (d.newBest) ...[
                const SizedBox(height: 22),
                Opacity(
                  opacity: stampT.clamp(0.0, 1.0),
                  // 大きく出て 1 段ずつ縮む (ドット絵らしく、なめらかには縮めない)
                  child: Transform.scale(
                    scale: 1 + ((1 - stampT.clamp(0.0, 1.0)) * 3).ceil() * 0.4,
                    alignment: Alignment.centerLeft,
                    child: const _Stamp('NEW RECORD'),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// エンドレスの成績 (計器風のタイルが順に出る)。
  Widget _stats(ResultData d) {
    final s = d.stats;
    final items = <(String, String, bool)>[
      ('ROUND', '${d.round}', d.round >= d.bestRound && d.round > 1),
      ('MAX CHAIN', '${d.maxChain}', false),
      ('JUST', '${s.just}', false),
      ('NEAR MISS', '${s.nearMiss}', false),
      ('COLLAPSE', '×${s.bestCollapse}', false),
      ('BLAST', '×${s.bestBlast}', false),
      ('RICOCHET', '×${s.bestRicochet}', false),
      ('TIME', _time(s.playTime), false),
    ];
    return Wrap(
      spacing: 0,
      runSpacing: 22,
      children: [
        for (var i = 0; i < items.length; i++)
          SizedBox(
            width: 180,
            child: _in(
              0.4 + i * 0.04,
              0.55 + i * 0.04,
              StatReadout(
                label: items[i].$1,
                value: items[i].$2,
                highlight: items[i].$3,
              ),
              from: const Offset(24, 0),
            ),
          ),
      ],
    );
  }

  /// ステージの星 (1 つずつ弾けるように付く)。
  Widget _stars(AppLocalizations l, ResultData d, StageDef stage) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < stage.stars.length; i++) ...[
          _starRow(
            starText(l, stage.stars[i]),
            d.achieved?[i] ?? false,
            0.45 + i * 0.1,
          ),
          const SizedBox(height: 14),
        ],
        const SizedBox(height: 4),
        _in(
          0.7,
          0.8,
          Row(
            children: [
              StatReadout(label: 'TIME', value: _time(d.stats.playTime)),
              const SizedBox(width: 36),
              StatReadout(label: 'JUST', value: '${d.stats.just}'),
              const SizedBox(width: 36),
              StatReadout(label: 'MAX CHAIN', value: '${d.maxChain}'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _starRow(String text, bool got, double at) {
    final t = _p(at, at + 0.12, Curves.easeOutBack);
    return Opacity(
      opacity: t.clamp(0.0, 1.0),
      child: Row(
        children: [
          // 取った星は大きく出て 1 段で収まる
          Transform.scale(
            scale: got && t < 0.6 ? 1.4 : 1,
            child: SizedBox(width: 40, child: Center(child: PixelStar(got: got, size: 36, shadow: true))),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 19,
                color: got ? Palette.white : withAlpha(Palette.pale, 0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _time(double s) {
    final m = s ~/ 60, sec = s - m * 60;
    return m > 0
        ? '$m:${sec.toStringAsFixed(1).padLeft(4, '0')}'
        : '${sec.toStringAsFixed(1)}s';
  }
}

/// 記録更新のハンコ。
class _Stamp extends StatelessWidget {
  const _Stamp(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
    decoration: BoxDecoration(
      color: Palette.yellow,
      border: Border.all(color: Dot.light(Palette.yellow), width: 3),
      boxShadow: const [BoxShadow(color: Colors.black, offset: Offset(4, 4))],
    ),
    child: Text(
      text,
      style: pixelFont(22, color: Dot.ink, weight: 900, letterSpacing: 4),
    ),
  );
}

/// 見出しの後ろの帯 (見出しの色)。濃さは 3 段の帯で、下に 1 ドットの線。
class _Backdrop extends CustomPainter {
  _Backdrop(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height, w = size.width * 0.75;
    final p = Paint()..isAntiAlias = false;
    for (var i = 0; i < 3; i++) {
      p.color = withAlpha(color, 0.2 - i * 0.06);
      canvas.drawRect(Rect.fromLTWH(w * i / 3, 0, w / 3, h), p);
    }
    canvas.drawRect(Rect.fromLTWH(0, h, w, 4), p..color = withAlpha(color, 0.7));
  }

  @override
  bool shouldRepaint(_Backdrop old) => old.color != color;
}
