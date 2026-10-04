import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/core.dart';
import '../l10n/app_localizations.dart';
import '../render/palette.dart';
import '../ui/arcade.dart';
import '../ui/stage_text.dart';
import '../ui/widgets.dart';

/// 結果画面に出す内容。
class ResultData {
  const ResultData({
    required this.score,
    required this.wave,
    required this.maxChain,
    required this.stats,
    required this.reason,
    required this.newBest,
    required this.bestScore,
    required this.bestWave,
    this.stage,
    this.cleared = false,
    this.achieved,
  });

  final int score, wave, maxChain, bestScore, bestWave;
  final RunStats stats;
  final String reason;
  final bool newBest, cleared;
  final StageDef? stage;

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
    final color = win ? Palette.cyan : Palette.red;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        if (_c.value < 1) _c.value = 1;
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Color(0xE005040F)),
          const Scanlines(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: SizedBox(
                  width: 1000,
                  height: 470,
                  child: AnimatedBuilder(
                    animation: _c,
                    builder: (context, _) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 見出し (後ろに斜めの帯)
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
                                  ChromaticTitle(title, size: 64, color: color),
                                  const SizedBox(width: 26),
                                  if (stage != null) ...[
                                    SlashTag(
                                      'STAGE ${stage.id}',
                                      color: Palette.cyan,
                                    ),
                                    const SizedBox(width: 10),
                                  ],
                                  if (!win)
                                    SlashTag(d.reason, color: Palette.red),
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
                                width: 1,
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 28,
                                ),
                                color: withAlpha(
                                  Palette.pale,
                                  0.18 * _p(0.3, 0.5),
                                ),
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
                                SlashButton(
                                  label: 'NEXT STAGE',
                                  primary: true,
                                  icon: Icons.skip_next,
                                  onPressed: widget.onNext,
                                ),
                              SlashButton(
                                label: 'RETRY',
                                primary: widget.onNext == null,
                                icon: Icons.replay,
                                onPressed: widget.onRetry,
                              ),
                              if (widget.onStageSelect != null)
                                SlashButton(
                                  label: 'STAGES',
                                  icon: Icons.grid_view,
                                  onPressed: widget.onStageSelect,
                                ),
                              SlashButton(
                                label: 'TITLE',
                                color: Palette.magenta,
                                icon: Icons.home,
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
                style: orbitron(13, color: Palette.cyan, letterSpacing: 6),
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  formatScore(shown),
                  style: orbitron(84, weight: 900, letterSpacing: 2).copyWith(
                    fontFeatures: tab,
                    height: 1,
                    shadows: [
                      Shadow(
                        color: withAlpha(Palette.cyan, 0.8),
                        blurRadius: 22,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Container(width: 3, height: 30, color: Palette.magenta),
                  const SizedBox(width: 10),
                  Text(
                    'HI-SCORE',
                    style: orbitron(
                      11,
                      color: withAlpha(Palette.magenta, 0.9),
                      letterSpacing: 4,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    formatScore(d.bestScore),
                    style: orbitron(
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
                  child: Transform.rotate(
                    angle: -0.08,
                    alignment: Alignment.centerLeft,
                    child: Transform.scale(
                      scale: 2.4 - 1.4 * stampT,
                      alignment: Alignment.centerLeft,
                      child: const _Stamp('NEW RECORD'),
                    ),
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
      ('WAVE', '${d.wave}', d.wave >= d.bestWave && d.wave > 1),
      ('MAX CHAIN', '${d.maxChain}', false),
      ('JUST', '${s.just}', false),
      ('GRAZE', '${s.graze}', false),
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
          Transform.scale(
            scale: got ? 0.4 + 0.6 * t : 1,
            child: Transform.rotate(
              angle: got ? (1 - t) * math.pi : 0,
              child: Icon(
                got ? Icons.star_rounded : Icons.star_outline_rounded,
                size: 38,
                color: got ? Palette.yellow : withAlpha(Palette.gray, 0.7),
                shadows: got
                    ? const [Shadow(color: Palette.yellow, blurRadius: 16)]
                    : null,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w600,
                color: got ? Palette.white : withAlpha(Palette.pale, 0.5),
                fontFamilyFallback: kFontFallback,
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
      border: Border.all(color: Palette.yellow, width: 3),
      color: withAlpha(Palette.yellow, 0.12),
      boxShadow: [
        BoxShadow(color: withAlpha(Palette.yellow, 0.45), blurRadius: 18),
      ],
    ),
    child: Text(
      text,
      style: orbitron(22, color: Palette.yellow, weight: 900, letterSpacing: 4)
          .copyWith(
            shadows: const [Shadow(color: Palette.yellow, blurRadius: 10)],
          ),
    ),
  );
}

/// 背景の斜めの帯 (見出しの色)。
class _Backdrop extends CustomPainter {
  _Backdrop(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height, w = size.width * 0.75;
    final band = Path()
      ..moveTo(-40, 0)
      ..lineTo(w, 0)
      ..lineTo(w - h * 0.5, h)
      ..lineTo(-40, h)
      ..close();
    canvas.drawPath(
      band,
      Paint()
        ..shader = LinearGradient(
          colors: [withAlpha(color, 0.18), withAlpha(color, 0)],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );
    canvas.drawRect(
      Rect.fromLTWH(-40, h, w - h * 0.5 + 40, 2),
      Paint()..color = withAlpha(color, 0.55),
    );
  }

  @override
  bool shouldRepaint(_Backdrop old) => old.color != color;
}
