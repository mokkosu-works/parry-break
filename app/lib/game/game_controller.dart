import 'package:flutter/foundation.dart';

import '../audio/audio_service.dart';
import '../core/core.dart';
import '../haptics/haptics_service.dart';
import '../input/input_clock.dart';
import '../render/fx.dart';

/// 1 回のプレイの進行役。シミュレーションを実時間で進め、イベントを演出・音・振動へ配る。
///
/// 画面の再描画は [frame] (毎フレーム通知)、オーバーレイの切り替えは [ChangeNotifier] で知らせる。
class GameController extends ChangeNotifier {
  GameController({
    required this.mode,
    required this.audio,
    required this.haptics,
    required double inputLag,
    Difficulty difficulty = Difficulty.normal,
    bool reduceEffects = false,
    double Function()? timeSource,
  })  : world = World(mode: mode, difficulty: difficulty, inputLag: inputLag),
        clock = InputClock(source: timeSource) {
    fx = FxState(world, reduceEffects: reduceEffects);
    session = Session(world, onStep: _onStep);
  }

  final GameMode mode;
  final World world;
  final AudioService audio;
  final HapticsService haptics;
  late final FxState fx;
  late final Session session;
  final InputClock clock;

  /// 毎フレーム増える (盤面の再描画の合図)。
  final ValueNotifier<int> frame = ValueNotifier(0);

  /// プレイが終わった (ゲームオーバー / ステージ完了) ときに 1 回呼ばれる。
  void Function(World world)? onFinished;

  bool _finished = false;
  bool get finished => _finished;

  bool get paused => session.paused;

  /// 再開前のカウントダウンの残り (秒)。null なら再開待ちではない。
  double? resumeCountdown;

  double _lastFrame = 0;

  void start() {
    world.start();
    fx.reset();
    _finished = false;
    resumeCountdown = null;
    if (session.paused) session.resume();
    audio.setPaused(false);
    audio.startMusic();
    notifyListeners();
  }

  void _onStep(double dt) {
    world.drainEvents().forEach(_dispatch);
    fx.step(dt);
  }

  void _dispatch(GameEvent e) {
    fx.handle(e);
    audio.handle(e);
    haptics.handle(e);
    if (e is GameOver || e is StageCompleted) _finish();
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    onFinished?.call(world);
    notifyListeners();
  }

  /// 毎フレーム呼ぶ。
  void tick() {
    final now = clock.now;
    final rdt = (now - _lastFrame).clamp(0.0, 0.1);
    _lastFrame = now;
    final rc = resumeCountdown;
    if (rc != null) {
      final left = rc - rdt;
      if (left <= 0) {
        resumeCountdown = null;
        session.resume();
        audio.setPaused(false);
      } else {
        resumeCountdown = left;
      }
      notifyListeners();
    }
    if (!session.paused) {
      // ステップの外で起きたイベント (ラウンド開始など) もここで配る
      session.advance(now).forEach(_dispatch);
      fx.frame(rdt);
      // 終わったプレイが、次のステージの画面の BGM を切り替えないようにする
      if (!_finished) audio.setMusicLevel(world.od ? 4 : world.stage);
    }
    frame.value++;
  }

  /// 発射 / パリィ。[timeStamp] は入力イベントの時刻。
  void press(Duration timeStamp) {
    if (session.paused || _finished) return;
    world.pressAction(clock.eventTime(timeStamp));
  }

  void pressNow() {
    if (session.paused || _finished) return;
    world.pressAction(clock.now);
  }

  void pause() {
    if (_finished || session.paused) {
      resumeCountdown = null;
      return;
    }
    session.pause();
    resumeCountdown = null;
    audio.setPaused(true);
    notifyListeners();
  }

  /// 「タップで再開 → 1 秒のカウントダウン」で再開する。
  void requestResume() {
    if (!session.paused || resumeCountdown != null) return;
    resumeCountdown = 1.0;
    notifyListeners();
  }

  void setInputLag(double seconds) => world.inputLag = seconds;

  /// BGM は止めない (次のステージの画面が先に鳴らし始めているため)。止めるのは [AudioService.leaveGame]。
  @override
  void dispose() {
    frame.dispose();
    super.dispose();
  }
}
