import 'dart:typed_data';

import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parry_break/audio/audio_service.dart';
import 'package:parry_break/core/core.dart';

/// 再生した音 1 つ分の状態。
class _Voice {
  _Voice(this.name, {required this.volume, required this.looping, required this.paused});
  final String name;
  double volume;
  final bool looping;
  bool paused;
  bool stopped = false;

  bool get playing => !stopped && !paused;
}

/// SoLoud の代わりに、呼ばれた操作を記録する。音源は名前の文字列をそのまま使う。
class _FakeBackend implements AudioBackend {
  final voices = <int, _Voice>{};
  double globalVolume = 1;
  int _next = 1;

  /// [name] の音で、止められていないもの。
  Iterable<_Voice> live(String name) => voices.values.where((v) => v.name == name && !v.stopped);

  @override
  Future<void> init() async {}
  @override
  Future<Object> loadMem(String path, Uint8List bytes) async => path.replaceAll('.wav', '');
  @override
  SoundHandle play(Object source, {double volume = 1, bool looping = false, bool paused = false}) {
    final id = _next++;
    voices[id] = _Voice(source as String, volume: volume, looping: looping, paused: paused);
    return SoundHandle(id);
  }

  @override
  void stop(SoundHandle h) => voices[h.id]!.stopped = true;
  @override
  void setPause(SoundHandle h, bool paused) => voices[h.id]!.paused = paused;
  @override
  void setVolume(SoundHandle h, double volume) => voices[h.id]!.volume = volume;
  @override
  void fadeVolume(SoundHandle h, double to, Duration time) => voices[h.id]!.volume = to;
  @override
  void seek(SoundHandle h, Duration time) {}
  @override
  Duration getPosition(SoundHandle h) => Duration.zero;
  @override
  void setGlobalVolume(double volume) => globalVolume = volume;
}

void main() {
  late _FakeBackend be;
  late SoLoudAudio audio;

  /// タイトル用の BGM が鳴っているか (止められておらず、一時停止もしていないものが 1 つ)。
  bool titlePlaying() => be.live('musicTitle').where((v) => !v.paused).length == 1;

  /// プレイ中の BGM (music0〜4) で止められていないもの。
  Iterable<_Voice> music() => be.voices.values.where((v) => v.name.startsWith('music') && v.name != 'musicTitle' && !v.stopped);

  setUp(() async {
    be = _FakeBackend();
    final bank = {
      for (final n in ['musicTitle', 'music0', 'music1', 'music2', 'music3', 'music4', 'over', 'hurt', 'clear'])
        n: Uint8List(0),
    };
    audio = SoLoudAudio(backend: be, bank: () async => bank);
    await audio.init();
  });

  test('タイトルにいるとタイトル BGM が流れ、ゲーム画面に入ると止まり、出ると戻る', () {
    expect(be.live('musicTitle'), isEmpty);
    audio.setMenuMusic(true);
    expect(titlePlaying(), isTrue);
    expect(be.live('musicTitle').single.looping, isTrue);

    audio.enterGame();
    expect(be.live('musicTitle'), isEmpty);
    audio.startMusic();
    expect(music(), hasLength(1));

    audio.leaveGame();
    expect(music(), isEmpty); // プレイ中の BGM は止める
    expect(titlePlaying(), isTrue);

    audio.setMenuMusic(false); // メニューの外 (遊び方など) では鳴らさない
    expect(be.live('musicTitle'), isEmpty);
  });

  test('新しいゲーム画面が先に開いてから前の画面が閉じても、新しい画面の BGM は止まらない', () {
    audio.setMenuMusic(true);
    audio.enterGame(); // 1 つ目のステージ
    audio.startMusic();

    // 「次のステージ」: 次の画面が先に開いて BGM を流し、そのあとで前の画面が閉じる
    audio.enterGame();
    audio.startMusic();
    final next = music().single;
    audio.leaveGame();
    expect(next.playing, isTrue);
    expect(be.live('musicTitle'), isEmpty);

    audio.leaveGame(); // 最後の画面が閉じた
    expect(next.stopped, isTrue);
    expect(titlePlaying(), isTrue);
  });

  test('leaveGame を enterGame より多く呼んでも、次の enterGame でタイトル BGM が止まる', () {
    audio.setMenuMusic(true);
    audio.leaveGame();
    audio.enterGame();
    expect(be.live('musicTitle'), isEmpty);
  });

  test('背面に回るとタイトル BGM が一時停止し、前面に戻ると再開する', () {
    audio.setMenuMusic(true);
    final title = be.live('musicTitle').single;

    audio.setAppActive(false);
    expect(title.paused, isTrue);
    expect(title.stopped, isFalse);

    audio.setAppActive(true);
    expect(title.playing, isTrue);
    expect(be.live('musicTitle'), hasLength(1)); // 新しく流し直さない
  });

  test('背面にいる間にメニューに戻っても、前面に戻るまでは鳴らさない', () {
    audio.enterGame();
    audio.setMenuMusic(true);
    audio.setAppActive(false);
    audio.leaveGame();
    expect(be.live('musicTitle').single.paused, isTrue);

    audio.setAppActive(true);
    expect(titlePlaying(), isTrue);
  });

  test('ポーズで全体の音量が 0 になり、ゲーム画面を閉じると戻る', () {
    audio.enterGame();
    audio.startMusic();
    audio.setPaused(true);
    expect(be.globalVolume, 0);
    expect(music().single.paused, isTrue);

    audio.leaveGame(); // ポーズのままタイトルへ戻る
    expect(be.globalVolume, 1);
    expect(music(), isEmpty);
  });

  test('ポーズを解くと全体の音量と BGM が戻る', () {
    audio.enterGame();
    audio.startMusic();
    audio.setPaused(true);
    audio.setPaused(false);
    expect(be.globalVolume, 1);
    expect(music().single.playing, isTrue);
  });

  test('GameOver で BGM が止まる', () {
    audio.enterGame();
    audio.startMusic();
    audio.handle(GameOver(reason: 'deadline', score: 0, round: 1, stats: RunStats()));
    expect(music(), isEmpty);
    expect(be.voices.values.where((v) => v.name == 'over'), hasLength(1));
  });

  test('StageCompleted で BGM が止まる', () {
    audio.enterGame();
    audio.startMusic();
    audio.handle(const StageCompleted(score: 100));
    expect(music(), isEmpty);
  });

  test('BGM の音量を変えると、流れているタイトル BGM の音量も変わる', () {
    audio.setMenuMusic(true);
    audio.setVolumes(bgm: 0.3, sfx: 1);
    expect(be.live('musicTitle').single.volume, 0.3);
  });

  test('初期化に失敗したら、どの呼び出しも何もしない', () async {
    final failing = SoLoudAudio(backend: be, bank: () async => throw Exception('no audio'));
    await failing.init();
    failing
      ..setMenuMusic(true)
      ..enterGame()
      ..startMusic()
      ..setPaused(true)
      ..leaveGame();
    expect(be.voices, isEmpty);
    expect(be.globalVolume, 1);
  });
}
