import '../entities/entities.dart';

/// コアのシミュレーションが発行する出来事。
///
/// 描画 (エフェクト・ポップアップ)、音、振動、統計はこれを購読する。
/// コアから描画や音を直接呼ばないことで、表現の追加・差し替えをコアに触れずに行える。
sealed class GameEvent {
  const GameEvent();
}

enum ParryGrade { just, perfect, good }

enum ParryTarget { ball, bullet }

enum DestroyCause { ball, pierce, phantom, blast, bullet }

enum BannerKind { round, boss, feverTime, bossPhase, timeOver }

enum CalloutChannel { collapse, chainBlast, multiParry, ricochet, feverFinish }

enum PopupKind { score, returnedScore, chain, ricochet, chainBlast, graze, noDamage, coreDamage }

// ---- ラウンド ----------------------------------------------------------

final class RoundStarted extends GameEvent {
  const RoundStarted({required this.number, required this.loop, this.bossIndex, this.introKey});
  final int number, loop;
  final int? bossIndex;

  /// 新ギミックの説明の翻訳キー (例: `intro.keystone`)。
  final String? introKey;
}

final class CountdownFinished extends GameEvent {
  const CountdownFinished();
}

final class RoundCleared extends GameEvent {
  const RoundCleared({required this.bonuses, required this.remaining, required this.ending});
  final List<Bonus> bonuses;

  /// 消えずに残っていたブロック (崩れ落ちる演出用)。
  final List<Block> remaining;
  final bool ending;
}

final class GameOver extends GameEvent {
  const GameOver({required this.reason, required this.score, required this.round, required this.stats});
  final String reason;
  final int score, round;
  final RunStats stats;
}

final class StageCompleted extends GameEvent {
  const StageCompleted({required this.score});
  final int score;
}

final class Banner extends GameEvent {
  const Banner(this.kind, {this.value = 0, this.introKey});
  final BannerKind kind;

  /// ラウンド番号・ボス番号・フェーズ番号など。
  final int value;
  final String? introKey;
}

final class Callout extends GameEvent {
  /// 同じ [channel] のコールアウトが表示中なら、新しく出さずに文字を差し替える。
  /// [hold] が true の間は消えずに残り、[release] で消え始める。
  const Callout(this.channel, this.text, {this.sub = '', this.hold = false, this.release = false, this.level = 0});
  final CalloutChannel channel;
  final String text, sub;
  final bool hold, release;

  /// 強調の段階 (COLLAPSE: 0 / MEGA: 1 / CATASTROPHE: 2)。
  final int level;
}

final class Popup extends GameEvent {
  const Popup(this.x, this.y, this.text, this.kind, {this.amount = 0});
  final double x, y;
  final String text;
  final PopupKind kind;
  final int amount;
}

// ---- ボール・パドル ----------------------------------------------------

final class BallLaunched extends GameEvent {
  const BallLaunched();
}

final class WallBounced extends GameEvent {
  const WallBounced();
}

final class PaddleBounced extends GameEvent {
  const PaddleBounced(this.x);
  final double x;
}

final class ParrySucceeded extends GameEvent {
  const ParrySucceeded({
    required this.grade,
    required this.target,
    required this.x,
    required this.y,
    required this.paddleX,
    required this.streak,
  });
  final ParryGrade grade;
  final ParryTarget target;
  final double x, y, paddleX;
  final int streak;
}

final class ParryMissed extends GameEvent {
  const ParryMissed();
}

final class PlayerHurt extends GameEvent {
  const PlayerHurt(this.x);
  final double x;
}

final class Grazed extends GameEvent {
  const Grazed(this.x);
  final double x;
}

final class RicochetBonus extends GameEvent {
  const RicochetBonus(this.count, this.points);
  final int count, points;
}

// ---- ブロック ----------------------------------------------------------

final class BlockDamaged extends GameEvent {
  const BlockDamaged(this.block);
  final Block block;
}

/// 壊せないものに当たって弾かれた (破壊不可・鏡面・ボスのコア)。
final class BlockDeflected extends GameEvent {
  const BlockDeflected(this.block);
  final Block block;
}

final class BlockDestroyed extends GameEvent {
  const BlockDestroyed(this.block, this.cx, this.cy, this.cause, this.points);
  final Block block;
  final double cx, cy;
  final DestroyCause cause;
  final int points;
}

final class KeystoneBroken extends GameEvent {
  const KeystoneBroken(this.x, this.y);
  final double x, y;
}

final class CoreDamaged extends GameEvent {
  const CoreDamaged(this.x, this.y, this.amount);
  final double x, y;
  final int amount;
}

final class CoreDestroyed extends GameEvent {
  const CoreDestroyed(this.x, this.y);
  final double x, y;
}

final class CollapseStarted extends GameEvent {
  const CollapseStarted(this.count);
  final int count;
}

/// 崩落したブロックが落ち始めた。[noteIndex] は崩落の音階の何音目か。
final class BlockFell extends GameEvent {
  const BlockFell(this.block, this.x, this.y, this.originX, this.noteIndex);
  final Block block;
  final double x, y, originX;
  final int noteIndex;
}

final class BlastExploded extends GameEvent {
  const BlastExploded(this.x, this.y, this.r, this.kind);
  final double x, y, r;
  final BlastKind kind;
}

final class BreakerTriggered extends GameEvent {
  const BreakerTriggered(this.x, this.y);
  final double x, y;
}

// ---- 弾・ボス ------------------------------------------------------------

final class BulletFired extends GameEvent {
  const BulletFired();
}

final class BulletMirrored extends GameEvent {
  const BulletMirrored();
}

final class LaserWarned extends GameEvent {
  const LaserWarned(this.x);
  final double x;
}

final class LaserFired extends GameEvent {
  const LaserFired(this.x);
  final double x;
}

/// ボスが装甲のブロックを作り直した。[x], [y] は画面上の中心。
final class BlockRepaired extends GameEvent {
  const BlockRepaired(this.block, this.x, this.y);
  final Block block;
  final double x, y;
}

final class BossPhaseChanged extends GameEvent {
  const BossPhaseChanged(this.phase);
  final int phase;
}

final class BossTimeOver extends GameEvent {
  const BossTimeOver();
}

// ---- FEVER TIME -----------------------------------------------------------

final class FeverTimeStarted extends GameEvent {
  const FeverTimeStarted();
}

final class FeverTimeEnded extends GameEvent {
  const FeverTimeEnded({required this.byHit});
  final bool byHit;
}

final class PhantomsSpawned extends GameEvent {
  const PhantomsSpawned(this.count);
  final int count;
}
