import '../stages/content.dart';
import '../stages/wave_spec.dart';

/// 1 回のプレイの進め方。新しいモード (デイリー、ボスラッシュなど) はこれを実装する。
abstract class GameMode {
  const GameMode();

  /// 記録・ランキングの保存先を表すキー。
  String get recordKey;

  /// [number] 番目 (1 始まり) のラウンド。モードが終わりなら null。
  WaveSpec? waveAt(int number);
}

/// エンドレス (アーケード): 60 ラウンドを繰り返し、1 周ごとに速くなる。10 ラウンドごとにボス。
class EndlessMode extends GameMode {
  const EndlessMode(this.content);
  final EndlessContent content;

  @override
  String get recordKey => 'endless';

  @override
  WaveSpec waveAt(int number) => content.wave(number);
}

/// ステージモード: ステージに書かれたラウンドを順に遊び、最後をクリアしたら終わり。
class StageMode extends GameMode {
  const StageMode(this.stage);
  final StageDef stage;

  @override
  String get recordKey => 'stage:${stage.id}';

  @override
  WaveSpec? waveAt(int number) => number <= stage.waves.length ? stage.waves[number - 1] : null;
}
