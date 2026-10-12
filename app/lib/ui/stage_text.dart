import 'dart:ui';

import '../core/core.dart';
import '../l10n/app_localizations.dart';
import '../render/palette.dart';

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

/// ステージの目標 (最後のラウンドのクリア条件)。
String goalText(AppLocalizations l, StageDef s) {
  final w = s.waves.last;
  return switch (w.clear) {
    AnnihilateClear() => w.boss != null ? l.clearBoss : l.clearAnnihilate,
    ScoreClear(:final target) => l.clearScore(formatScore(target)),
    SurviveClear(:final seconds) => l.clearSurvive('${seconds.round()}'),
  };
}

/// 難易度の色 (EASY 緑 / NORMAL 黄 / HARD 赤)。
Color difficultyColor(Difficulty d) => d.pick(Dot.mint, Dot.mustard, Dot.bulletRed);

/// 難易度の説明文。
String difficultyText(AppLocalizations l, Difficulty d) => d.pick(l.difficultyEasy, l.difficultyNormal, l.difficultyHard);
