import '../core/core.dart';
import '../l10n/app_localizations.dart';

/// 星の条件の説明文。
String starText(AppLocalizations l, StarCondition s) => switch (s) {
      ClearStar() => l.starClear,
      NoHitStar() => l.starNoHit,
      TimeStar(:final seconds) => l.starTime('${seconds.round()}'),
      StatStar(:final kind, :final value) => switch (kind) {
          StatKind.score => l.starScore(formatScore(value)),
          StatKind.just => l.starJust('$value'),
          StatKind.perfect => l.starPerfect('$value'),
          StatKind.collapse => l.starCollapse('$value'),
          StatKind.chainBlast => l.starChainBlast('$value'),
          StatKind.returnKills => l.starReturnKills('$value'),
          StatKind.graze => l.starGraze('$value'),
          StatKind.ricochet => l.starRicochet('$value'),
        },
    };

/// ステージの目標 (最後のウェーブのクリア条件)。
String goalText(AppLocalizations l, StageDef s) {
  final w = s.waves.last;
  return switch (w.clear) {
    AnnihilateClear() => w.boss != null ? l.clearBoss : l.clearAnnihilate,
    ScoreClear(:final target) => l.clearScore(formatScore(target)),
    SurviveClear(:final seconds) => l.clearSurvive('${seconds.round()}'),
  };
}
