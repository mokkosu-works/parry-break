import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../input/input_clock.dart';
import '../l10n/app_localizations.dart';
import '../render/palette.dart';
import '../render/pixel.dart';
import '../services/settings.dart';
import 'widgets.dart';

/// 判定タイミングの測定。一定の間隔で縮むリングが目標の輪に重なる瞬間にタップしてもらい、
/// 「見えてから押すまで」の平均の遅れ (画面の表示遅延 + タッチの入力遅延) を測る。
class CalibrationScreen extends ConsumerStatefulWidget {
  const CalibrationScreen({super.key});

  @override
  ConsumerState<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends ConsumerState<CalibrationScreen> with SingleTickerProviderStateMixin {
  static const _beats = 10, _interval = 0.8, _leadIn = 1.6;

  final InputClock _clock = InputClock();
  late final Ticker _ticker;
  final ValueNotifier<double> _now = ValueNotifier(0);
  late double _start;
  final List<double> _offsets = [];
  int? _result;

  @override
  void initState() {
    super.initState();
    _restart();
    _ticker = createTicker((_) {
      _now.value = _clock.now;
      if (_result == null && _clock.now > _beatTime(_beats - 1) + 0.6) _finish();
    })
      ..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _now.dispose();
    super.dispose();
  }

  double _beatTime(int i) => _start + _leadIn + i * _interval;

  void _restart() {
    _start = _clock.now;
    _offsets.clear();
    setState(() => _result = null);
  }

  void _tap(PointerDownEvent e) {
    if (_result != null) return;
    final t = _clock.eventTime(e.timeStamp);
    final i = ((t - _start - _leadIn) / _interval).round();
    if (i < 0 || i >= _beats) return;
    final d = t - _beatTime(i);
    if (d.abs() < 0.25) setState(() => _offsets.add(d));
  }

  void _finish() {
    if (_offsets.length < 4) {
      setState(() => _result = -1);
      return;
    }
    // 外れ値を除いた平均 (中央の 60%)
    final s = [..._offsets]..sort();
    final cut = (s.length * 0.2).floor();
    final mid = s.sublist(cut, s.length - cut);
    final mean = mid.reduce((a, b) => a + b) / mid.length;
    setState(() => _result = (mean * 1000).round().clamp(0, 100));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final r = _result;
    return ScreenFrame(
      title: l.calibrationTitle,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _tap,
        child: Column(children: [
          Text(l.calibrationBody('$_beats'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
          Expanded(
            child: ValueListenableBuilder(
              valueListenable: _now,
              builder: (_, now, _) => CustomPaint(
                size: Size.infinite,
                painter: _BeatPainter(now: now, beatTime: _beatTime, beats: _beats, interval: _interval, hits: _offsets.length),
              ),
            ),
          ),
          if (r != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Wrap(spacing: 16, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                if (r >= 0) Text(l.calibrationResult('$r'), style: pixelFont(20, color: Palette.accent)),
                PixelButton(label: l.calibrationRetry, icon: Icons.replay, onPressed: _restart),
                if (r >= 0)
                  PixelButton(
                    label: l.calibrationApply,
                    filled: true,
                    icon: Icons.check,
                    onPressed: () {
                      ref.read(settingsProvider.notifier).update((s) => s.copyWith(timingOffsetMs: r));
                      Navigator.of(context).pop();
                    },
                  ),
              ]),
            ),
        ]),
      ),
    );
  }
}

class _BeatPainter extends CustomPainter {
  _BeatPainter({
    required this.now,
    required this.beatTime,
    required this.beats,
    required this.interval,
    required this.hits,
  });
  final double now, interval;
  final double Function(int) beatTime;
  final int beats, hits;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = math.min(size.width, size.height) * 0.22;
    // ドットの輪: 真ん中が的、外から縮んでくる輪が拍
    int n(double rad) => math.max(12, (rad * 2 * math.pi / 14).round());
    drawDots(canvas, ringDots(c.dx, c.dy, r, n(r)), Palette.accent, size: 6);
    for (var i = 0; i < beats; i++) {
      final dt = beatTime(i) - now;
      if (dt < -0.15 || dt > interval * 1.5) continue;
      if (dt >= 0) {
        final rad = r * (1 + dt / interval * 1.6);
        drawDots(canvas, ringDots(c.dx, c.dy, rad, n(rad)), dt < interval * 0.75 ? Palette.accent2 : Dot.dark(Palette.accent2), size: 5);
      } else {
        pixelDisc(canvas, c.dx, c.dy, r / 6, withAlpha(Palette.yellow, 0.6), d: 6);
      }
    }
    final tp = TextPainter(
      text: TextSpan(text: '$hits / $beats', style: pixelFont(18, color: Palette.pale)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_BeatPainter old) => true;
}
