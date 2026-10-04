import 'boss_def.dart';
import 'json_object.dart';

/// 1 ウェーブの中身。配置 ([LayoutContent]) かボス ([BossContent]) のどちらか。
sealed class WaveContent {
  const WaveContent();
}

/// グリッド配置のウェーブ。
///
/// [rows] は 1 行 14 文字の文字列で、`.` は空き。それ以外の文字は [legend] で
/// ブロックの種類 ID に読み替える (legend にない文字はそのまま ID として扱う)。
final class LayoutContent extends WaveContent {
  const LayoutContent(this.rows, {this.legend = const {}});
  final List<String> rows;
  final Map<String, String> legend;

  String blockIdAt(int r, int c) {
    final ch = rows[r][c];
    return legend[ch] ?? ch;
  }
}

final class BossContent extends WaveContent {
  const BossContent(this.boss);
  final BossDef boss;
}

/// ウェーブのクリア条件。
sealed class ClearCondition {
  const ClearCondition();

  static ClearCondition fromJson(JsonObject? j) => switch (j?.strOpt('type')) {
        null || 'annihilate' => const AnnihilateClear(),
        'score' => ScoreClear(j!.integer('value')),
        'survive' => SurviveClear(j!.number('value')),
        final t => throw FormatException('${j!.path}.type: 不明なクリア条件 "$t"'),
      };
}

/// 全消し (ボス戦ではコアをすべて壊す)。
final class AnnihilateClear extends ClearCondition {
  const AnnihilateClear();
}

/// プレイ全体のスコアが [target] に届く (全消しでもクリア)。
final class ScoreClear extends ClearCondition {
  const ScoreClear(this.target);
  final int target;
}

/// [seconds] 秒生き残る (全消しでもクリア)。
final class SurviveClear extends ClearCondition {
  const SurviveClear(this.seconds);
  final double seconds;
}

/// 1 ウェーブの定義。ゲームモードが番号ごとに作る。
class WaveSpec {
  const WaveSpec({
    required this.number,
    required this.difficulty,
    required this.content,
    this.loop = 0,
    this.loopMul = 1,
    this.clear = const AnnihilateClear(),
    this.introKey,
    this.ending = false,
    this.tuning = const {},
  });

  /// 画面に出すウェーブ番号。乱数のシードにも使う。
  final int number;

  /// 難易度 (エンドレスではループを除いたウェーブ番号 1〜60)。速度・砲台などの式に使う。
  final int difficulty;

  /// 周回数 (0 始まり)。
  final int loop;

  /// 周回ごとの速度倍率 (ボール・弾・降下の速度、砲台の発射頻度)。
  final double loopMul;

  final ClearCondition clear;

  final WaveContent content;

  /// 新ギミックの説明の翻訳キー。
  final String? introKey;

  /// 最終ウェーブ (クリアで大ボーナス)。
  final bool ending;

  /// このウェーブだけ上書きするバランス値 ([Tuning.copyWith])。
  final Map<String, Object?> tuning;

  /// 反射ブロック・砲台の初期タイマーに使う固定シード (ブラウザ版と同じ式)。
  int get seed => number * 131 + 7;

  WaveSpec copyWith({int? number, int? loop, double? loopMul, String? introKey, bool? ending}) => WaveSpec(
        number: number ?? this.number,
        difficulty: difficulty,
        content: content,
        loop: loop ?? this.loop,
        loopMul: loopMul ?? this.loopMul,
        clear: clear,
        introKey: introKey ?? this.introKey,
        ending: ending ?? this.ending,
        tuning: tuning,
      );

  BossDef? get boss => switch (content) {
        BossContent(:final boss) => boss,
        LayoutContent() => null,
      };
}
