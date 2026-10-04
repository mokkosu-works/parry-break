import 'package:flutter_test/flutter_test.dart';
import 'package:parry_break/audio/sound_bank.dart';

void main() {
  test('効果音と BGM がすべて WAV として書き出せる', () {
    final sw = Stopwatch()..start();
    final bank = renderSoundBank();
    final ms = sw.elapsedMilliseconds;
    expect(bank.keys, containsAll(['just', 'perfect', 'good', 'note0', 'note19', 'music0', 'music4', 'brk2']));
    for (final e in bank.entries) {
      final w = e.value;
      expect(String.fromCharCodes(w.sublist(0, 4)), 'RIFF', reason: e.key);
      // 無音でないこと
      var peak = 0;
      for (var i = 44; i + 1 < w.length; i += 2) {
        final v = (w[i] | (w[i + 1] << 8)).toSigned(16).abs();
        if (v > peak) peak = v;
      }
      expect(peak, greaterThan(100), reason: e.key);
    }
    // ignore: avoid_print
    print('rendered ${bank.length} sounds in ${ms}ms, '
        '${(bank.values.fold(0, (s, w) => s + w.length) / 1e6).toStringAsFixed(1)}MB');
  });
}
