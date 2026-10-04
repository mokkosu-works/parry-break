import 'dart:math' as math;
import 'dart:typed_data';

/// ブラウザ版の WebAudio 合成 (`tone` / `noise`) を、オフラインで波形に書き出す小さなシンセ。
///
/// 起動時に効果音と BGM のループを WAV (メモリ上) として作り、再生エンジンに渡す。
/// 純粋な Dart なので、別の isolate で実行できる。
class Synth {
  Synth(double seconds, {this.sampleRate = 44100, int seed = 1})
      : buf = Float32List((seconds * sampleRate).ceil()),
        _rnd = math.Random(seed);

  final int sampleRate;
  final Float32List buf;
  final math.Random _rnd;

  /// ループ素材として書き出すとき、末尾からはみ出した音を先頭に回す。
  bool wrap = false;

  void _add(int i, double v) {
    if (i < buf.length) {
      buf[i] += v;
    } else if (wrap) {
      buf[i % buf.length] += v;
    }
  }

  static double _osc(String type, double phase) {
    final p = phase - phase.floorToDouble();
    return switch (type) {
      'sine' => math.sin(p * 2 * math.pi),
      'square' => p < 0.5 ? 1.0 : -1.0,
      'sawtooth' => 2 * p - 1,
      'triangle' => 1 - 4 * (p - 0.5).abs(),
      _ => 0.0,
    };
  }

  /// 指数ランプ (WebAudio の exponentialRampToValueAtTime と同じ形)。
  static double _exp(double v0, double v1, double k) => v0 * math.pow(v1 / v0, k.clamp(0.0, 1.0));

  /// `tone(f, d, type, v, f2, when)`: 周波数 [f] (→ [f2]) の発振器を、音量 [v] から 0 へ指数的に減衰させる。
  void tone(double f, double d, String type, double v, {double f2 = 0, double when = 0}) {
    final start = (when * sampleRate).round();
    final n = ((d + 0.02) * sampleRate).round();
    var phase = 0.0;
    for (var i = 0; i < n; i++) {
      final t = i / sampleRate;
      final k = t / d;
      final freq = f2 > 0 ? _exp(f, f2, k) : f;
      phase += freq / sampleRate;
      final g = t < d ? _exp(v, 0.0001, k) : 0.0001;
      _add(start + i, _osc(type, phase) * g);
    }
  }

  /// `noise(d, v, freq, when, ftype)`: ホワイトノイズを biquad フィルタ (Q=1) に通し、指数的に減衰させる。
  void noise(double d, double v, double freq, {double when = 0, String filter = 'bandpass'}) {
    final start = (when * sampleRate).round();
    final n = ((d + 0.02) * sampleRate).round();
    final bq = _Biquad(filter, freq, sampleRate.toDouble());
    for (var i = 0; i < n; i++) {
      final t = i / sampleRate;
      final g = t < d ? _exp(v, 0.0001, t / d) : 0.0001;
      _add(start + i, bq.process(_rnd.nextDouble() * 2 - 1) * g);
    }
  }

  /// 16bit モノラルの WAV にする。[gain] を掛け、はみ出しは柔らかく抑える。
  Uint8List toWav({double gain = 1}) {
    final pcm = Int16List(buf.length);
    for (var i = 0; i < buf.length; i++) {
      final x = buf[i] * gain;
      final y = x.abs() < 0.9 ? x : x.sign * (0.9 + 0.1 * _tanh((x.abs() - 0.9) / 0.1));
      pcm[i] = (y.clamp(-1.0, 1.0) * 32767).round();
    }
    final data = pcm.buffer.asUint8List();
    final h = ByteData(44);
    void str(int o, String s) {
      for (var i = 0; i < 4; i++) {
        h.setUint8(o + i, s.codeUnitAt(i));
      }
    }

    str(0, 'RIFF');
    h.setUint32(4, 36 + data.length, Endian.little);
    str(8, 'WAVE');
    str(12, 'fmt ');
    h.setUint32(16, 16, Endian.little);
    h.setUint16(20, 1, Endian.little);
    h.setUint16(22, 1, Endian.little);
    h.setUint32(24, sampleRate, Endian.little);
    h.setUint32(28, sampleRate * 2, Endian.little);
    h.setUint16(32, 2, Endian.little);
    h.setUint16(34, 16, Endian.little);
    str(36, 'data');
    h.setUint32(40, data.length, Endian.little);
    return Uint8List.fromList([...h.buffer.asUint8List(), ...data]);
  }

  static double _tanh(double x) {
    final e = math.exp(2 * x);
    return (e - 1) / (e + 1);
  }
}

/// RBJ cookbook の biquad (WebAudio の BiquadFilterNode と同じ式、Q=1)。
class _Biquad {
  _Biquad(String type, double f0, double fs) {
    const q = 1.0;
    final w0 = 2 * math.pi * f0.clamp(10, fs / 2 - 10) / fs;
    final cw = math.cos(w0), alpha = math.sin(w0) / (2 * q);
    double b0, b1, b2;
    switch (type) {
      case 'lowpass':
        b0 = (1 - cw) / 2;
        b1 = 1 - cw;
        b2 = (1 - cw) / 2;
      case 'highpass':
        b0 = (1 + cw) / 2;
        b1 = -(1 + cw);
        b2 = (1 + cw) / 2;
      default: // bandpass (ピークのゲイン 0dB)
        b0 = alpha;
        b1 = 0;
        b2 = -alpha;
    }
    final a0 = 1 + alpha;
    _b0 = b0 / a0;
    _b1 = b1 / a0;
    _b2 = b2 / a0;
    _a1 = -2 * cw / a0;
    _a2 = (1 - alpha) / a0;
  }

  late final double _b0, _b1, _b2, _a1, _a2;
  double _x1 = 0, _x2 = 0, _y1 = 0, _y2 = 0;

  double process(double x) {
    final y = _b0 * x + _b1 * _x1 + _b2 * _x2 - _a1 * _y1 - _a2 * _y2;
    _x2 = _x1;
    _x1 = x;
    _y2 = _y1;
    _y1 = y;
    return y;
  }
}
