import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import '../core/core.dart';
import 'sound_bank.dart';

/// 音の再生。コアのイベントを効果音にし、ヒート段階に合わせて BGM を切り替える。
abstract class AudioService {
  Future<void> init();

  void handle(GameEvent e);

  /// BGM の段階 (0〜3: ヒート段階、4: OVERDRIVE)。毎フレーム呼んでよい。
  void setMusicLevel(int level);

  void startMusic();

  /// ミスしたとき: BGM を即座に止める (コアピラー4)。
  void cutMusic();

  void setPaused(bool paused);

  void setVolumes({required double bgm, required double sfx});

  void play(String name);
}

/// 音を出さない実装 (Web のプレビューやテスト)。
class SilentAudio implements AudioService {
  @override
  Future<void> init() async {}
  @override
  void handle(GameEvent e) {}
  @override
  void setMusicLevel(int level) {}
  @override
  void startMusic() {}
  @override
  void cutMusic() {}
  @override
  void setPaused(bool paused) {}
  @override
  void setVolumes({required double bgm, required double sfx}) {}
  @override
  void play(String name) {}
}

class SoLoudAudio implements AudioService {
  final SoLoud _sl = SoLoud.instance;
  final Map<String, AudioSource> _src = {};
  final Map<String, double> _last = {};
  final Stopwatch _clock = Stopwatch()..start();
  final math.Random _rnd = math.Random();
  bool _ready = false;
  double _bgm = 0.8, _sfx = 1;

  SoundHandle? _music;
  int _level = 0, _targetLevel = 0;
  double _musicStartedAt = 0;
  Timer? _switch;
  bool _musicOn = false;

  @override
  Future<void> init() async {
    try {
      await _sl.init(bufferSize: 512);
      _sl.setMaxActiveVoiceCount(48);
      final bank = await compute(renderSoundBank, null);
      for (final e in bank.entries) {
        _src[e.key] = await _sl.loadMem('${e.key}.wav', e.value);
      }
      _ready = true;
    } on Object catch (e) {
      debugPrint('audio disabled: $e');
    }
  }

  double get _now => _clock.elapsedMicroseconds / 1e6;

  /// 同じ音が短い間隔で重なりすぎないようにする (ブラウザ版の throttle)。
  bool _throttle(String key, double gap) {
    final t = _now;
    if (t - (_last[key] ?? -1) < gap) return false;
    _last[key] = t;
    return true;
  }

  @override
  void play(String name, {double gap = 0}) {
    if (!_ready || _sfx <= 0) return;
    if (gap > 0 && !_throttle(name, gap)) return;
    final s = _src[name];
    if (s != null) _sl.play(s, volume: _sfx);
  }

  @override
  void handle(GameEvent e) {
    switch (e) {
      case WallBounced():
        play('wall', gap: 0.03);
      case PaddleBounced():
        play('paddle');
      case BlockDamaged():
        play('hit', gap: 0.025);
      case BlockDeflected():
        play('clink', gap: 0.04);
      case BlockDestroyed():
        if (_throttle('brk', 0.022)) play('brk${_rnd.nextInt(3)}');
      case ParrySucceeded(:final grade):
        play(switch (grade) { ParryGrade.just => 'just', ParryGrade.perfect => 'perfect', ParryGrade.good => 'good' });
      case ParryMissed():
        play('miss');
      case BulletFired():
        play('fire', gap: 0.03);
      case PlayerHurt():
        play('hurt');
        _duckMusic();
      case OverdriveStarted():
        play('od');
      case OverdriveEnded():
        play('odEnd');
      case CoreDamaged():
        play('core');
      case CoreDestroyed():
        play('coreDie');
      case BulletMirrored():
        play('mirror');
      case WaveCleared():
        play('clear');
      case BossPhaseChanged():
        play('phase');
      case WaveStarted(:final bossIndex):
        if (bossIndex != null) play('alarm');
      case BossTimeOver():
        play('alarm');
      case GameOver():
        cutMusic();
        play('over');
      case CountdownFinished():
        play('count');
      case BallLaunched():
        play('launch');
      case BlockFell(:final noteIndex):
        if (_throttle('note', 0.018)) play('note${math.min(noteIndex, noteCount - 1)}');
      case CollapseStarted():
        play('crumble', gap: 0.1);
      case KeystoneBroken():
        play('keystone');
      case BlastExploded(:final kind):
        if (kind == BlastKind.breaker) {
          play('breaker');
        } else {
          play('blast', gap: 0.05);
        }
      case Grazed():
        play('graze', gap: 0.04);
      case RicochetBonus():
        play('ricochet');
      case PhantomsSpawned():
        play('phantom');
      case LaserWarned():
        play('laserWarn');
      case LaserFired():
        play('laser');
      case StageCompleted():
        cutMusic();
      default:
        break;
    }
  }

  @override
  void startMusic() {
    if (!_ready) return;
    _stopMusic();
    _musicOn = true;
    _startLoop(_targetLevel, 0);
  }

  void _startLoop(int level, int bar) {
    final s = _src['music$level'];
    if (s == null) return;
    final h = _sl.play(s, volume: _bgm, looping: true);
    final offset = bar * barSeconds(level);
    if (offset > 0) _sl.seek(h, Duration(microseconds: (offset * 1e6).round()));
    _music = h;
    _level = level;
    _musicStartedAt = _now - offset;
  }

  void _stopMusic() {
    _switch?.cancel();
    _switch = null;
    final h = _music;
    if (h != null) _sl.stop(h);
    _music = null;
  }

  @override
  void setMusicLevel(int level) {
    _targetLevel = level;
    if (!_musicOn || _music == null || level == _level || _switch != null) return;
    // 次の小節の頭で切り替える (ベースの進行の位置は保つ)
    final bar = barSeconds(_level), loop = bar * 4;
    final pos = (_now - _musicStartedAt) % loop;
    final next = (pos / bar).floor() + 1;
    final wait = next * bar - pos;
    _switch = Timer(Duration(microseconds: (wait * 1e6).round()), () {
      _switch = null;
      if (!_musicOn) return;
      final old = _music;
      _startLoop(_targetLevel, next % 4);
      if (old != null) _sl.stop(old);
    });
  }

  void _duckMusic() {
    final h = _music;
    if (h == null) return;
    _sl.setVolume(h, 0);
    _sl.fadeVolume(h, _bgm, const Duration(milliseconds: 900));
  }

  @override
  void cutMusic() {
    _musicOn = false;
    _stopMusic();
  }

  @override
  void setPaused(bool paused) {
    if (!_ready) return;
    final h = _music;
    if (h != null) _sl.setPause(h, paused);
    _sl.setGlobalVolume(paused ? 0 : 1);
    if (!paused && h != null) _musicStartedAt = _now - _sl.getPosition(h).inMicroseconds / 1e6;
  }

  @override
  void setVolumes({required double bgm, required double sfx}) {
    _bgm = bgm;
    _sfx = sfx;
    final h = _music;
    if (_ready && h != null) _sl.setVolume(h, bgm);
  }
}

AudioService createAudioService() => kIsWeb ? SilentAudio() : SoLoudAudio();
