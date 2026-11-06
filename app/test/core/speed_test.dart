import 'package:flutter_test/flutter_test.dart';
import 'package:parry_break/core/core.dart';

import 'helpers.dart';

/// エンドレスのラウンド [n] を始めた World の、段階ごとの速さと FEVER TIME の速さ。
({List<double> stages, double odStart, double odTop}) speedsAt(int n) {
  final w = World(mode: endlessMode)..start(fromRound: n);
  final t = w.tuning;
  final stages = <double>[];
  for (var i = 0; i < 4; i++) {
    w.combo = t.stageMin[i].toDouble();
    stages.add(w.targetSpeed);
  }
  w.addCombo(t.odCombo.toDouble());
  expect(w.od, isTrue);
  w.odElapsed = 0;
  final odStart = w.targetSpeed;
  w.odElapsed = t.odTime;
  final odTop = w.targetSpeed;
  return (stages: stages, odStart: odStart, odTop: odTop);
}

void main() {
  test('R1〜R60 と 2 周目: 段階4 の速さ ≤ FEVER TIME の開始時の速さ ≤ FEVER TIME の最高速度', () {
    for (var n = 1; n <= 120; n++) {
      final s = speedsAt(n);
      expect(s.stages[3], lessThanOrEqualTo(s.odStart + 1e-9), reason: 'R$n 段階4 ${s.stages[3]} / 開始 ${s.odStart}');
      expect(s.odStart, lessThanOrEqualTo(s.odTop + 1e-9), reason: 'R$n 開始 ${s.odStart} / 最高 ${s.odTop}');
      for (var i = 0; i < 4; i++) {
        expect(s.stages[i], lessThanOrEqualTo(s.odTop + 1e-9), reason: 'R$n 段階${i + 1} ${s.stages[i]} / 最高 ${s.odTop}');
      }
    }
  });

  test('前半のラウンドの速さは変わらない (段階4 から 1,000px/秒 まで)', () {
    final s = speedsAt(1);
    expect(s.stages[3], closeTo(690, 1e-9));
    expect(s.odStart, closeTo(690, 1e-9));
    expect(s.odTop, closeTo(1000, 1e-9));
  });

  test('R60 で段階4 から FEVER TIME に入っても、ボールが減速しない', () {
    final w = World(mode: endlessMode)..start(fromRound: 60);
    run(w, 1.1);
    w.combo = w.tuning.stageMin[3].toDouble();
    final s4 = w.targetSpeed;
    expect(s4, greaterThan(1000));
    final b = w.ball
      ..attached = false
      ..x = Field.width / 2
      ..y = Field.paddleY - 200
      ..vx = 0;
    b.speed = s4;
    b.vy = -s4;
    w.addCombo(w.tuning.odCombo.toDouble());
    expect(w.od, isTrue);
    w.step(World.dt);
    expect(w.ball.speed, greaterThanOrEqualTo(s4 - 1e-9));
  });
}
