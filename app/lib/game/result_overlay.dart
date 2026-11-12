import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/core.dart';
import '../l10n/app_localizations.dart';
import '../render/palette.dart';
import '../render/pixel.dart';
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
/// どこかをタップすると演出を飛ばす。キーボードでは、演出中の Enter / Space で演出を飛ばし、
/// 出きったあとは矢印キーでボタンを選んで Enter / Space で決める。
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
  final FocusNode _focus = FocusNode(debugLabel: 'ResultOverlay');

  /// キーボードで選んでいるボタン (並びは [_buttons] の順)。
  int _selected = 0;

  @override
  void initState() {
    super.initState();
    // 盤面がキーボードのフォーカスを持っているので、結果画面に移す (autofocus では移らない)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
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
    _focus.dispose();
    super.dispose();
  }

  /// 結果画面のボタン (NEXT STAGE / RETRY / STAGES / TITLE のうち出すもの)。
  List<
    ({
      String label,
      DotSprite icon,
      VoidCallback onPressed,
      bool filled,
      Color? color,
    })
  >
  get _buttons => [
    if (widget.onNext case final next?)
      (
        label: 'NEXT STAGE',
        icon: PixelIcons.skipNext,
        onPressed: next,
        filled: true,
        color: null,
      ),
    (
      label: 'RETRY',
      icon: PixelIcons.replay,
      onPressed: widget.onRetry,
      filled: widget.onNext == null,
      color: null,
    ),
    if (widget.onStageSelect case final stages?)
      (
        label: 'STAGES',
        icon: PixelIcons.grid,
        onPressed: stages,
        filled: false,
        color: null,
      ),
    (
      label: 'TITLE',
      icon: PixelIcons.home,
      onPressed: widget.onTitle,
      filled: false,
      color: Palette.gray,
    ),
  ];

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final key = e.logicalKey;
    if (_c.value < 1) {
      // 演出中は、決めるキーで演出を飛ばすだけ (見えていないボタンを押さない)
      if (!isConfirmKey(key)) return KeyEventResult.ignored;
      _c.value = 1;
      return KeyEventResult.handled;
    }
    final buttons = _buttons;
    if (arrowStep(key) case final step?) {
      setState(
        () => _selected = (_selected + step + buttons.length) % buttons.length,
      );
      return KeyEventResult.handled;
    }
    if (isConfirmKey(key)) {
      buttons[_selected.clamp(0, buttons.length - 1)].onPressed();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
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
    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: GestureDetector(
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
                child: LayoutBuilder(
                  builder: (context, c) {
                    // 大きい画面は 1000×470 の箱を組んで縮める。そのまま縮めるとボタンが 44pt、
                    // 文字が 11pt を下回る画面 (スマホの横画面) では、文字を小さめにした詰めた配置にし、
                    // 縮めずに (または少しだけ縮めて) 出す。
                    final compact =
                        c.maxWidth < _wideSize.width * _minWideScale ||
                        c.maxHeight < _wideSize.height * _minWideScale;
                    final Widget body;
                    final EdgeInsets padding;
                    if (compact) {
                      padding = const EdgeInsets.fromLTRB(16, 12, 16, 14);
                      final w =
                          (c.maxWidth - _windowChrome - padding.horizontal)
                              .clamp(_compactMinWidth, _compactMaxWidth);
                      body = SizedBox(
                        width: w,
                        child: AnimatedBuilder(
                          animation: _c,
                          builder: (context, _) =>
                              _compact(l, d, title, color, win),
                        ),
                      );
                    } else {
                      padding = const EdgeInsets.fromLTRB(28, 22, 28, 26);
                      body = SizedBox(
                        width: 1000,
                        height: 470,
                        child: AnimatedBuilder(
                          animation: _c,
                          builder: (context, _) =>
                              _wide(l, d, title, color, win),
                        ),
                      );
                    }
                    return Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        // 後ろの盤面が透けて読みにくくならないよう、窓の中に置く
                        child: PixelWindow(padding: padding, child: body),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 大きい画面の箱の大きさ (窓の枠と余白を足すと約 1074×536)。
  static const _wideSize = Size(1074, 536);

  /// 大きい画面の箱をこれより縮めると、ボタン (高さ 48) が 44pt を下回る。
  static const _minWideScale = 44 / 48;

  /// 窓の枠 (外の線 3 + 隙間 4 + 内の線 2) の左右の合計。
  static const _windowChrome = 18.0;

  /// 詰めた配置の幅。これより狭い画面では、この幅で組んで縮める。広くても間延びしないよう上限を置く。
  static const _compactMinWidth = 560.0, _compactMaxWidth = 760.0;

  /// 見出し (後ろに帯) と、ステージ・難易度・ミスの理由の札。
  Widget _header(
    ResultData d,
    String title,
    Color color,
    bool win, {
    required bool compact,
  }) {
    final stage = d.stage;
    final tags = [
      if (stage != null) ...[
        PixelTag('STAGE ${stage.id}', color: Palette.sub),
        PixelTag(d.difficulty.label, color: difficultyColor(d.difficulty)),
      ],
      if (!win) PixelTag(d.reason, color: Palette.sub),
    ];
    if (compact) {
      // 札は縮めると読めなくなるので、見出しの下に折り返して並べる
      return _in(
        0,
        0.16,
        CustomPaint(
          painter: _Backdrop(color),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 8, 8),
            child: Wrap(
              spacing: 16,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                PixelTitle(title, size: 30, color: color),
                if (tags.isNotEmpty)
                  Wrap(spacing: 8, runSpacing: 6, children: tags),
              ],
            ),
          ),
        ),
        from: const Offset(-60, 0),
      );
    }
    return _in(
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
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final (i, t) in tags.indexed) ...[
                        if (i > 0) const SizedBox(width: 10),
                        t,
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      from: const Offset(-60, 0),
    );
  }

  /// ボタンの並び。出きるまでは押せない (演出を飛ばすつもりのタップが、見えていないボタンに当たらないように)。
  Widget _buttonRow({
    double fontSize = 18,
    double spacing = 14,
    bool dense = false,
  }) => IgnorePointer(
    ignoring: _p(0.78, 0.95) < 1,
    child: _in(
      0.78,
      0.95,
      Wrap(
        spacing: spacing,
        runSpacing: 10,
        children: [
          for (final (i, b) in _buttons.indexed)
            PixelButton(
              label: b.label,
              filled: b.filled,
              color: b.color,
              icon: b.icon,
              fontSize: fontSize,
              dense: dense,
              selected: i == _selected,
              onPressed: b.onPressed,
            ),
        ],
      ),
    ),
  );

  /// 大きい画面の配置 (1000×470 の箱)。
  Widget _wide(
    AppLocalizations l,
    ResultData d,
    String title,
    Color color,
    bool win,
  ) {
    final stage = d.stage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(d, title, color, win, compact: false),
        const SizedBox(height: 26),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 11, child: _score(d)),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 28),
                width: 2,
                color: withAlpha(Dot.edge, _p(0.3, 0.5)),
              ),
              Expanded(
                flex: 9,
                child: stage == null ? _stats(d) : _stars(l, d, stage),
              ),
            ],
          ),
        ),
        _buttonRow(),
      ],
    );
  }

  /// スマホの横画面などの狭い画面の配置。文字は 12 以上、ボタンは高さ 48 のまま、縮めずに出す。
  Widget _compact(
    AppLocalizations l,
    ResultData d,
    String title,
    Color color,
    bool win,
  ) {
    final stage = d.stage;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(d, title, color, win, compact: true),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 9, child: _score(d, compact: true)),
            const SizedBox(width: 14),
            // 区切りの線は右の欄の左の縁に引く (欄の高さが中身で決まるので)
            Expanded(
              flex: 12,
              child: Container(
                padding: const EdgeInsets.only(left: 14),
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(
                      color: withAlpha(Dot.edge, _p(0.3, 0.5)),
                      width: 2,
                    ),
                  ),
                ),
                child: stage == null
                    ? _stats(d, compact: true)
                    : _stars(l, d, stage, compact: true),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buttonRow(fontSize: 14, spacing: 8, dense: true),
      ],
    );
  }

  /// スコア (数え上げ) と記録更新のハンコ。
  Widget _score(ResultData d, {bool compact = false}) {
    final big = compact ? 44.0 : 84.0;
    // ステージの最高記録はクリアした回だけ残るので、失敗したときは 0 などに見える理由を添える
    final note = d.stage != null && !d.cleared
        ? AppLocalizations.of(context).bestScoreClearOnly
        : null;
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
                style: pixelFont(
                  compact ? 13 : 16,
                  color: Palette.pale,
                  letterSpacing: compact ? 3 : 4,
                ),
              ),
              SizedBox(height: compact ? 2 : 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  formatScore(shown),
                  style: pixelFont(big, weight: 900, letterSpacing: 2).copyWith(
                    fontFeatures: tab,
                    height: 1,
                    shadows: hardShadow(big),
                  ),
                ),
              ),
              SizedBox(height: compact ? 10 : 14),
              Row(
                children: [
                  Container(
                    width: 4,
                    height: compact ? 22 : 30,
                    color: Palette.main,
                  ),
                  SizedBox(width: compact ? 8 : 10),
                  Text(
                    'HI-SCORE',
                    style: pixelFont(
                      compact ? 12 : 14,
                      color: Palette.main,
                      letterSpacing: compact ? 2 : 4,
                    ),
                  ),
                  SizedBox(width: compact ? 10 : 14),
                  if (compact)
                    // 狭い欄では、桁の多い記録を折り返さずに少し縮める
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          formatScore(d.bestScore),
                          style: pixelFont(
                            18,
                            weight: 900,
                          ).copyWith(fontFeatures: tab),
                        ),
                      ),
                    )
                  else
                    Text(
                      formatScore(d.bestScore),
                      style: pixelFont(
                        22,
                        weight: 900,
                      ).copyWith(fontFeatures: tab),
                    ),
                  if (note != null && !compact) ...[
                    const SizedBox(width: 14),
                    Flexible(
                      child: Text(
                        note,
                        overflow: TextOverflow.ellipsis,
                        style: pixelFont(13, color: Palette.pale, weight: 400),
                      ),
                    ),
                  ],
                ],
              ),
              // 狭い画面では HI-SCORE の横に入らないので、下に折り返して出す
              if (note != null && compact) ...[
                const SizedBox(height: 6),
                Text(
                  note,
                  style: pixelFont(12, color: Palette.pale, weight: 400),
                ),
              ],
              if (d.newBest) ...[
                SizedBox(height: compact ? 14 : 22),
                Opacity(
                  opacity: stampT.clamp(0.0, 1.0),
                  // 大きく出て 1 段ずつ縮む (ドット絵らしく、なめらかには縮めない)
                  child: Transform.scale(
                    scale: 1 + ((1 - stampT.clamp(0.0, 1.0)) * 3).ceil() * 0.4,
                    alignment: Alignment.centerLeft,
                    child: _Stamp('NEW RECORD', size: compact ? 16 : 22),
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
  Widget _stats(ResultData d, {bool compact = false}) {
    final s = d.stats;
    final items = <(String, String, bool)>[
      ('ROUND', '${d.round}', d.round >= d.bestRound && d.round > 1),
      ('MAX CHAIN', '${d.maxChain}', false),
      ('JUST', '${s.just}', false),
      ('GRAZE', '${s.graze}', false),
      ('COLLAPSE', '×${s.bestCollapse}', false),
      ('BLAST', '×${s.bestBlast}', false),
      ('RICOCHET', '×${s.bestRicochet}', false),
      ('TIME', _time(s.playTime), false),
    ];
    // 狭い画面では 3 列に並べる (2 列だと縦に入らない)
    return LayoutBuilder(
      builder: (context, c) => Wrap(
        spacing: 0,
        runSpacing: compact ? 12 : 22,
        children: [
          for (var i = 0; i < items.length; i++)
            SizedBox(
              width: compact ? (c.maxWidth / 3).floorToDouble() : 180,
              child: _in(
                0.4 + i * 0.04,
                0.55 + i * 0.04,
                StatReadout(
                  label: items[i].$1,
                  value: items[i].$2,
                  highlight: items[i].$3,
                  compact: compact,
                ),
                from: const Offset(24, 0),
              ),
            ),
        ],
      ),
    );
  }

  /// ステージの星 (1 つずつ弾けるように付く)。
  Widget _stars(
    AppLocalizations l,
    ResultData d,
    StageDef stage, {
    bool compact = false,
  }) {
    final gap = compact ? 14.0 : 36.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < stage.stars.length; i++) ...[
          _starRow(
            starText(l, stage.stars[i]),
            d.achieved?[i] ?? false,
            0.45 + i * 0.1,
            compact: compact,
          ),
          SizedBox(height: compact ? 6 : 14),
        ],
        SizedBox(height: compact ? 2 : 4),
        _in(
          0.7,
          0.8,
          Wrap(
            spacing: gap,
            runSpacing: 8,
            children: [
              StatReadout(
                label: 'TIME',
                value: _time(d.stats.playTime),
                compact: compact,
              ),
              StatReadout(
                label: 'JUST',
                value: '${d.stats.just}',
                compact: compact,
              ),
              StatReadout(
                label: 'MAX CHAIN',
                value: '${d.maxChain}',
                compact: compact,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _starRow(String text, bool got, double at, {bool compact = false}) {
    final t = _p(at, at + 0.12, Curves.easeOutBack);
    return Opacity(
      opacity: t.clamp(0.0, 1.0),
      child: Row(
        children: [
          // 取った星は大きく出て 1 段で収まる
          Transform.scale(
            scale: got && t < 0.6 ? 1.4 : 1,
            child: SizedBox(
              width: compact ? 26 : 40,
              child: Center(
                child: PixelStar(
                  got: got,
                  size: compact ? 22 : 36,
                  shadow: true,
                ),
              ),
            ),
          ),
          SizedBox(width: compact ? 10 : 14),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: compact ? 14 : 19,
                height: compact ? 1.25 : null,
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
  const _Stamp(this.text, {this.size = 22});
  final String text;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(
      horizontal: size * 16 / 22,
      vertical: size * 7 / 22,
    ),
    decoration: BoxDecoration(
      color: Palette.yellow,
      border: Border.all(color: Dot.light(Palette.yellow), width: 3),
      boxShadow: const [BoxShadow(color: Colors.black, offset: Offset(4, 4))],
    ),
    child: Text(
      text,
      style: pixelFont(size, color: Dot.ink, weight: 900, letterSpacing: 4),
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
    canvas.drawRect(
      Rect.fromLTWH(0, h, w, 4),
      p..color = withAlpha(color, 0.7),
    );
  }

  @override
  bool shouldRepaint(_Backdrop old) => old.color != color;
}
