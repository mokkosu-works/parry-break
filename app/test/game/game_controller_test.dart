// Issue #138: GameController 経由 (press(timeStamp) → tick()) のパリィの判定と、MISS の後のクールダウン
import 'package:flutter_test/flutter_test.dart';
import 'package:parry_break/audio/audio_service.dart';
import 'package:parry_break/core/core.dart';
import 'package:parry_break/game/game_controller.dart';
import 'package:parry_break/haptics/haptics_service.dart';

import '../core/helpers.dart';

/// 音を出さずに、配られたイベントを記録する。
class RecordingAudio extends SilentAudio {
  final events = <GameEvent>[];
  @override
  void handle(GameEvent e) => events.add(e);
}

/// 偽の時計で動かす GameController。タッチの時刻は「ゲームの時計 + [base] 秒」の基準で付く。
class Harness {
  Harness() {
    c = GameController(
      mode: const SingleRoundMode(['N.............']),
      audio: audio,
      haptics: HapticsService()..enabled = false,
      inputLag: 0,
      timeSource: () => now,
    )..start();
    c.tick();
  }

  static const base = 500.0;

  /// 30fps (1 フレームに 2 ステップ)。
  static const frame = 1 / 30;

  final audio = RecordingAudio();
  late final GameController c;
  double now = 0;

  World get w => c.world;

  /// 実時間 [pressed] に押したタッチの時刻。
  Duration stamp(double pressed) =>
      Duration(microseconds: ((pressed + base) * 1e6).round());

  /// [seconds] だけフレームを進める。各フレームの前に [before] を呼ぶ。
  void frames(double seconds, {void Function()? before}) {
    final end = now + seconds;
    while (now < end - 1e-9) {
      before?.call();
      now += frame;
      c.tick();
    }
  }

  /// カウントダウンを終え、遅れなく届いたタッチで発射する (タッチの時刻の基準もここで決まる)。
  void launch() {
    frames(1.1);
    c.press(stamp(now));
    frames(frame);
    expect(w.launched, isTrue);
  }

  /// 真下へ落ちてくるボールを、シミュレーション時刻で [inSim] 秒後にパドルへ接触させる。接触の実時間を返す。
  double dropBall(double inSim) {
    final b = w.ball
      ..x = w.paddle.x
      ..vx = 0
      ..pierce = 0
      ..breaker = false;
    b.vy = b.speed;
    // 置いた位置は次のステップから動く。接触は w.t + inSim (シミュレーション時刻)
    b.y = Field.paddleY - Field.ballR - b.speed * inSim;
    return now + (w.t + inSim - w.sync.sim);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 接触の 0.005 秒前に押す。押したのはフレームの直後 (+0.002 秒) で、次のフレームの直前 (-0.001 秒) に届く。
  /// [useStamp] が false なら、タッチの時刻を使わず届いた時刻 (pressNow) で押す。
  ParryGrade? pressBetweenFrames({required bool useStamp}) {
    final h = Harness()..launch();
    // 押す時刻 = 今のフレームから 9 フレーム後 + 0.002 秒 になるように、接触の時刻を決める
    final contact = h.dropBall(
      9 * Harness.frame + 0.002 + 0.005 + (h.w.sync.sim - h.w.t),
    );
    final pressed = contact - 0.005;
    expect(pressed - h.now, closeTo(9 * Harness.frame + 0.002, 1e-9));
    var sent = false;
    h.audio.events.clear();
    h.frames(
      0.5,
      before: () {
        if (!sent && pressed >= h.now && pressed < h.now + Harness.frame) {
          final last = h.now;
          h.now = last + Harness.frame - 0.001; // 届いた時刻 (次のフレームの前)
          useStamp ? h.c.press(h.stamp(pressed)) : h.c.pressNow();
          h.now = last;
          sent = true;
        }
      },
    );
    expect(sent, isTrue);
    final parries = h.audio.events.whereType<ParrySucceeded>().toList();
    return parries.isEmpty ? null : parries.single.grade;
  }

  test('フレームの間に押したパリィが、押した時刻で判定される (press(timeStamp) → tick())', () {
    expect(pressBetweenFrames(useStamp: true), ParryGrade.just);
  });

  test('比較: 届いた時刻 (pressNow) で判定すると、同じ押し方でも接触の 0.024 秒後になり JUST にならない', () {
    expect(pressBetweenFrames(useStamp: false), ParryGrade.perfect);
  });

  test('ポーズ中の入力は受け付けない', () {
    final h = Harness();
    h.frames(1.1);
    h.c.pause();
    h.c.press(h.stamp(h.now));
    h.c.requestResume();
    h.frames(1.2); // 再開のカウントダウン
    h.frames(0.2);
    expect(h.c.paused, isFalse);
    expect(h.w.launched, isFalse);
  });

  group('MISS の後のクールダウン (0.35 秒)', () {
    /// 何もないときに押して MISS にした World と、その押した時刻。
    (World, double) missed() {
      final w = testWorld(const SingleRoundMode(['N............N']));
      run(w, 1.1);
      // ボールは上へ飛ばしておく
      w.ball
        ..attached = false
        ..x = 40
        ..y = 300
        ..vx = 0
        ..vy = -w.ball.speed;
      final t0 = w.t;
      w.pressAction(t0);
      expect(run(w, 0.15).whereType<ParryMissed>(), hasLength(1));
      expect(w.parry.cooldownUntil, closeTo(t0 + 0.35, 1e-9));
      return (w, t0);
    }

    /// 押した時刻 t0 から [contactAfter] 秒後に接触するボールを、その 0.005 秒前に押したときの判定。
    ParryGrade? pressBefore(double contactAfter) {
      final (w, t0) = missed();
      final b = w.ball
        ..x = w.paddle.x
        ..vx = 0
        ..pierce = 0;
      b.vy = b.speed;
      b.y = Field.paddleY - Field.ballR - b.speed * (t0 + contactAfter - w.t);
      w.pressAction(t0 + contactAfter - 0.005);
      final parries = run(w, 0.4).whereType<ParrySucceeded>().toList();
      return parries.isEmpty ? null : parries.single.grade;
    }

    test('押した時刻から 0.35 秒は次のパリィが受け付けられない', () {
      expect(pressBefore(0.345), isNull); // 0.34 秒に押した
    });

    test('0.35 秒を過ぎれば受け付ける', () {
      expect(pressBefore(0.36), ParryGrade.just); // 0.355 秒に押した
    });
  });
}
