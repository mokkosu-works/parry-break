import 'dart:math' as math;
import 'dart:typed_data';

import 'synth.dart';

/// 効果音と BGM の定義 (ブラウザ版の `SFX` と `musicTick` の移植)。
///
/// [renderSoundBank] は名前 → WAV のバイト列を返す。別の isolate で呼ぶ。
/// 効果音・BGM を追加するときは、ここに定義を足す。

/// ブラウザ版のマスター音量 (0.55) × 効果音バス (0.9)。
const _sfxGain = 0.55 * 0.9;

/// ブラウザ版のマスター音量 (0.55) × BGM バス (0.32)。
const _musicGain = 0.55 * 0.32;

typedef _Def = void Function(Synth s);

/// 崩落の音階 (ペンタトニック) の数。
const noteCount = 20;

/// コンボ段階ごとの BGM のループ数 (段階 1〜4 と FEVER TIME)。
const musicLevels = 5;

const _penta = [0, 2, 4, 7, 9];

final Map<String, (double, _Def)> _sfx = {
  'wall': (0.06, (s) => s.tone(520, 0.04, 'square', 0.04)),
  'paddle': (0.09, (s) => s.tone(392, 0.07, 'square', 0.08, f2: 300)),
  'hit': (0.07, (s) => s.tone(740, 0.05, 'square', 0.06, f2: 620)),
  'clink': (0.08, (s) => s.tone(2200, 0.06, 'triangle', 0.06, f2: 1800)),
  for (var p = 0; p < 3; p++)
    'brk$p': (
      0.11,
      (s) {
        s.noise(0.09, 0.16, 2600 + p * 400.0);
        s.tone(900 + p * 120.0, 0.07, 'triangle', 0.07, f2: 450);
      }
    ),
  'perfect': (
    0.25,
    (s) {
      s.tone(1320, 0.18, 'sawtooth', 0.1, f2: 2640);
      s.tone(1980, 0.22, 'square', 0.06);
      s.noise(0.12, 0.2, 6000);
      s.tone(80, 0.15, 'sine', 0.35, f2: 40);
    }
  ),
  'just': (
    0.35,
    (s) {
      s.tone(1760, 0.28, 'sawtooth', 0.1, f2: 3520);
      s.tone(2637, 0.32, 'square', 0.05);
      s.tone(1319, 0.32, 'square', 0.05);
      s.noise(0.2, 0.3, 8000, filter: 'highpass');
      s.tone(70, 0.3, 'sine', 0.5, f2: 30);
    }
  ),
  'good': (
    0.15,
    (s) {
      s.tone(990, 0.12, 'square', 0.09, f2: 1480);
      s.noise(0.06, 0.1, 4000);
    }
  ),
  'miss': (0.12, (s) => s.tone(220, 0.09, 'triangle', 0.08, f2: 150)),
  'fire': (0.12, (s) => s.tone(330, 0.09, 'sawtooth', 0.035, f2: 170)),
  'hurt': (
    0.45,
    (s) {
      s.tone(140, 0.4, 'sawtooth', 0.22, f2: 40);
      s.noise(0.35, 0.35, 700);
    }
  ),
  'od': (
    0.95,
    (s) {
      s.tone(220, 0.9, 'sawtooth', 0.14, f2: 1760);
      s.tone(330, 0.9, 'square', 0.06, f2: 2640);
      s.noise(0.6, 0.2, 5000, filter: 'highpass');
    }
  ),
  'odEnd': (0.55, (s) => s.tone(880, 0.5, 'sawtooth', 0.08, f2: 220)),
  'core': (
    0.3,
    (s) {
      s.tone(160, 0.25, 'square', 0.18, f2: 70);
      s.noise(0.2, 0.25, 1200);
    }
  ),
  'coreDie': (
    0.95,
    (s) {
      s.tone(90, 0.9, 'sawtooth', 0.25, f2: 30);
      s.noise(0.9, 0.45, 500);
    }
  ),
  'mirror': (0.12, (s) => s.tone(1760, 0.1, 'triangle', 0.08, f2: 2600)),
  'clear': (
    0.6,
    (s) {
      const fs = [523.0, 659.0, 784.0, 1047.0, 1319.0];
      for (var i = 0; i < fs.length; i++) {
        s.tone(fs[i], 0.25, 'square', 0.07, when: i * 0.07);
      }
    }
  ),
  'phase': (
    0.75,
    (s) {
      s.tone(110, 0.7, 'sawtooth', 0.2, f2: 55);
      s.tone(117, 0.7, 'sawtooth', 0.2, f2: 58);
    }
  ),
  'alarm': (
    1.0,
    (s) {
      for (var i = 0; i < 3; i++) {
        s.tone(880, 0.18, 'square', 0.07, when: i * 0.3);
        s.tone(660, 0.12, 'square', 0.07, when: i * 0.3 + 0.15);
      }
    }
  ),
  'over': (
    1.05,
    (s) {
      s.noise(1.0, 0.5, 300, filter: 'lowpass');
      s.tone(70, 1.0, 'sine', 0.45, f2: 25);
    }
  ),
  'count': (0.1, (s) => s.tone(660, 0.08, 'square', 0.06)),
  'launch': (0.12, (s) => s.tone(520, 0.1, 'square', 0.07, f2: 1040)),
  for (var i = 0; i < noteCount; i++)
    'note$i': (
      0.2,
      (s) {
        final st = _penta[i % 5] + 12 * math.min(3, i ~/ 5);
        final f = 330 * math.pow(2, st / 12).toDouble();
        s.tone(f, 0.16, 'triangle', 0.08);
        s.tone(f * 2, 0.07, 'square', 0.02);
      }
    ),
  'crumble': (
    0.65,
    (s) {
      s.noise(0.6, 0.3, 220, filter: 'lowpass');
      s.tone(60, 0.5, 'sine', 0.3, f2: 35);
    }
  ),
  'keystone': (
    0.4,
    (s) {
      s.tone(523, 0.35, 'triangle', 0.12, f2: 262);
      s.tone(784, 0.35, 'triangle', 0.08, f2: 392);
    }
  ),
  'blast': (
    0.55,
    (s) {
      s.noise(0.5, 0.45, 600, filter: 'lowpass');
      s.tone(110, 0.35, 'sawtooth', 0.16, f2: 30);
    }
  ),
  'breaker': (
    0.85,
    (s) {
      s.noise(0.8, 0.55, 400, filter: 'lowpass');
      s.tone(55, 0.8, 'sine', 0.55, f2: 25);
      s.tone(880, 0.4, 'sawtooth', 0.08, f2: 110);
    }
  ),
  'graze': (0.05, (s) => s.tone(3200, 0.03, 'square', 0.03)),
  'ricochet': (
    0.3,
    (s) {
      const fs = [784.0, 988.0, 1175.0, 1568.0];
      for (var i = 0; i < fs.length; i++) {
        s.tone(fs[i], 0.12, 'square', 0.05, when: i * 0.04);
      }
    }
  ),
  'phantom': (0.2, (s) => s.tone(1400, 0.15, 'sine', 0.06, f2: 2800)),
  'laserWarn': (
    0.65,
    (s) {
      for (var i = 0; i < 3; i++) {
        s.tone(1200, 0.1, 'square', 0.05, when: i * 0.25);
      }
    }
  ),
  'laser': (
    0.45,
    (s) {
      s.noise(0.4, 0.3, 3000);
      s.tone(90, 0.4, 'sawtooth', 0.2, f2: 60);
    }
  ),
};

/// BGM のテンポ (コンボ段階 1〜4、FEVER TIME)。
const musicBpm = [132.0, 136.0, 142.0, 150.0, 168.0];

/// 1 小節 (16 ステップ) の長さ (秒)。
double barSeconds(int level) => 60 / musicBpm[level] / 4 * 16;

const _bassProg = [0, 0, -4, -2];
const _lead = [12, 15, 19, 15, 12, 10, 7, 10, 12, 15, 17, 19, 22, 19, 17, 15];

/// コンボ段階 [level] の BGM (4 小節のループ)。段階が上がるほどレイヤーが増え、キーとテンポが上がる。
Synth _music(int level) {
  final sp = 60 / musicBpm[level] / 4;
  final s = Synth(sp * 64, seed: 100 + level)..wrap = true;
  double nf(num semi) => 110 * math.pow(2, semi / 12).toDouble();
  final i = level;
  for (var step = 0; step < 64; step++) {
    final t = step * sp;
    final st = step % 16, bar = step ~/ 16;
    final tr = i == 4 ? 5 : (i >= 3 ? 2 : 0);
    final root = _bassProg[bar] + tr;
    if (st % 4 == 0 || (i == 4 && st == 14)) s.tone(150, 0.16, 'sine', 0.55, f2: 40, when: t);
    if (i >= 1 && st % 4 == 2) s.noise(0.05, 0.12, 9000, when: t, filter: 'highpass');
    if (i >= 3 && st % 2 == 1) s.noise(0.025, 0.05, 11000, when: t, filter: 'highpass');
    if (i >= 2 && (st == 4 || st == 12)) s.noise(0.12, 0.18, 1800, when: t);
    if (st % 2 == 0) s.tone(nf(root - 12 + (st % 8 == 6 ? 12 : 0)), sp * 1.8, 'sawtooth', 0.1, when: t);
    if (i >= 2) {
      const ch = [0, 3, 7, 12, 15, 12, 7, 3];
      s.tone(nf(root + 12 + ch[st % 8]), sp * 0.9, 'square', 0.025, when: t);
    }
    if (i >= 3 && st % 2 == 0) {
      final n = _lead[(st + bar * 4) % 16];
      s.tone(nf(root + 12 + n), sp * 1.9, i == 4 ? 'sawtooth' : 'triangle', 0.05, when: t);
    }
  }
  return s;
}

/// タイトル・メニューの BGM のテンポ。
const titleBpm = 108.0;

const _titleRoots = [0, -4, -2, -5, 0, -4, -7, -5]; // 1 小節ごとのベースの根音
const _titleArp = [0, 7, 12, 7, 3, 10, 15, 10];

/// タイトル・メニューの BGM (8 小節のループ)。プレイ中より遅く、ベースとアルペジオを中心にして静かにする。
Synth _titleMusic() {
  final sp = 60 / titleBpm / 4;
  final s = Synth(sp * 16 * 8, seed: 200)..wrap = true;
  double nf(num semi) => 110 * math.pow(2, semi / 12).toDouble();
  for (var step = 0; step < 128; step++) {
    final t = step * sp;
    final st = step % 16, bar = step ~/ 16;
    final root = _titleRoots[bar];
    if (st == 0) {
      s.tone(150, 0.16, 'sine', 0.45, f2: 40, when: t);
      s.tone(nf(root - 12), sp * 15, 'triangle', 0.12, when: t);
    }
    if (st == 8) s.tone(150, 0.16, 'sine', 0.3, f2: 40, when: t);
    if (st % 4 == 2) s.noise(0.04, 0.06, 9000, when: t, filter: 'highpass');
    if (st % 2 == 0) s.tone(nf(root + 12 + _titleArp[(st ~/ 2) % 8]), sp * 1.6, 'square', 0.022, when: t);
    if (st == 0 && bar % 2 == 0) s.tone(nf(root + 24 + (bar >= 4 ? 3 : 7)), sp * 14, 'sine', 0.05, when: t);
  }
  return s;
}

/// すべての効果音と BGM を WAV にする。キーは効果音名、BGM は `music0`〜`music4`、タイトルは `musicTitle`。
Map<String, Uint8List> renderSoundBank([Object? _]) {
  final out = <String, Uint8List>{};
  var seed = 1;
  for (final e in _sfx.entries) {
    final (len, def) = e.value;
    final s = Synth(len, seed: seed++);
    def(s);
    out[e.key] = s.toWav(gain: _sfxGain);
  }
  for (var l = 0; l < musicLevels; l++) {
    out['music$l'] = _music(l).toWav(gain: _musicGain);
  }
  out['musicTitle'] = _titleMusic().toWav(gain: _musicGain);
  return out;
}
