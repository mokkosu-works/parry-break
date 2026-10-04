import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:parry_break/core/core.dart';

/// assets のエンドレスの定義。
final endlessContent =
    EndlessContent.fromJson(jsonDecode(File('assets/stages/endless.json').readAsStringSync()) as Map<String, Object?>);

final endlessMode = EndlessMode(endlessContent);

/// 指定した配置の 1 ウェーブだけのモード。
class SingleWaveMode extends GameMode {
  const SingleWaveMode(this.rows, {this.difficulty = 1});
  final List<String> rows;
  final int difficulty;

  @override
  String get recordKey => 'test';

  @override
  WaveSpec? waveAt(int number) => number == 1
      ? WaveSpec(number: 1, difficulty: difficulty, content: LayoutContent(rows))
      : null;
}

/// 入力時刻 = シミュレーション時刻になるようにした World。
World testWorld(GameMode mode, {double inputLag = 0}) {
  final w = World(mode: mode, inputLag: inputLag)..start();
  w.sync
    ..wall = 0
    ..sim = 0
    ..scale = 1;
  return w;
}

/// [seconds] だけ進める。各ステップの前に [before] を呼ぶ。発生したイベントを返す。
List<GameEvent> run(World w, double seconds, {void Function()? before}) {
  final events = <GameEvent>[];
  final n = (seconds / World.dt).round();
  for (var i = 0; i < n; i++) {
    before?.call();
    w.step(World.dt);
    events.addAll(w.drainEvents());
  }
  return events;
}

/// パドルがメインのボールを追いかけ、一定間隔でボタンを押す自動操作。
/// 中心で受けると真上に返って同じ列ばかり叩くため、受ける位置を左右に揺らす。
void Function() autopilot(World w, {double every = 0.37}) {
  var next = 0.0;
  return () {
    w.input
      ..useTarget = true
      ..targetX = w.ball.x - 40 * math.sin(w.t * 1.3);
    if (w.t >= next) {
      w.pressAction(w.t);
      next = w.t + every;
    }
  };
}
