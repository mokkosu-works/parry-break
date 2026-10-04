// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'RICOCHET OVERDRIVE';

  @override
  String get menuEndless => 'ENDLESS';

  @override
  String get menuStages => 'STAGES';

  @override
  String get menuHowToPlay => 'HOW TO PLAY';

  @override
  String get menuSettings => 'SETTINGS';

  @override
  String get menuRanking => 'RANKING';

  @override
  String get back => 'BACK';

  @override
  String get bestScore => 'BEST SCORE';

  @override
  String waveN(String n) {
    return 'WAVE $n';
  }

  @override
  String get helpMoveTitle => 'MOVE';

  @override
  String get helpMoveZones => 'Drag on the left half of the screen';

  @override
  String get helpMoveRail => 'Drag the rail on the left';

  @override
  String get helpParryTitle => 'LAUNCH / PARRY';

  @override
  String get helpParryZones =>
      'Tap the right half just as the ball or bullet hits';

  @override
  String get helpParryRail => 'Press PARRY just as the ball or bullet hits';

  @override
  String get helpTimingTitle => 'TIMING';

  @override
  String get helpTimingBody =>
      'PERFECT → Pierce\nJUST → Shockwave\nHeat widens the paddle (max 1.5×)';

  @override
  String get helpChainTitle => 'CHAIN';

  @override
  String get helpChainBody =>
      'White keystone → Collapse\nOrange explosive → Chain blast';

  @override
  String get helpOverTitle => 'GAME OVER';

  @override
  String get helpOverBody =>
      'Don\'t drop the ball\nKeep blocks above the warning line';

  @override
  String get helpPauseTitle => 'PAUSE';

  @override
  String get helpPauseBody => 'Tap Ⅱ at the top right';

  @override
  String get paused => 'PAUSED';

  @override
  String get resume => 'RESUME';

  @override
  String get retry => 'RETRY';

  @override
  String get toTitle => 'TITLE';

  @override
  String get nextStage => 'NEXT STAGE';

  @override
  String get stageSelect => 'STAGE SELECT';

  @override
  String get gameOver => 'GAME OVER';

  @override
  String get stageClear => 'STAGE CLEAR';

  @override
  String get stageFailed => 'STAGE FAILED';

  @override
  String get newRecord => 'NEW RECORD';

  @override
  String get locked => 'LOCKED';

  @override
  String get starClear => 'Clear';

  @override
  String get starNoHit => 'Clear without getting hit';

  @override
  String starTime(String seconds) {
    return 'Clear within ${seconds}s';
  }

  @override
  String starScore(String value) {
    return 'Score $value+';
  }

  @override
  String starJust(String value) {
    return '$value× JUST';
  }

  @override
  String starPerfect(String value) {
    return '$value× PERFECT or better';
  }

  @override
  String starCollapse(String value) {
    return 'COLLAPSE ×$value+';
  }

  @override
  String starChainBlast(String value) {
    return 'CHAIN BLAST ×$value+';
  }

  @override
  String starReturnKills(String value) {
    return 'Destroy $value blocks with returned shots';
  }

  @override
  String starGraze(String value) {
    return '$value× GRAZE';
  }

  @override
  String starRicochet(String value) {
    return 'RICOCHET ×$value+';
  }

  @override
  String get clearAnnihilate => 'GOAL: CLEAR ALL BLOCKS';

  @override
  String clearScore(String value) {
    return 'GOAL: SCORE $value';
  }

  @override
  String clearSurvive(String seconds) {
    return 'GOAL: SURVIVE ${seconds}s';
  }

  @override
  String get clearBoss => 'GOAL: DESTROY ALL CORES';

  @override
  String get settingsControls => 'Controls';

  @override
  String get controlsZones => 'Screen halves';

  @override
  String get controlsRailH => 'Rail (horizontal)';

  @override
  String get controlsRailV => 'Rail (vertical)';

  @override
  String get settingsSensitivity => 'Move sensitivity';

  @override
  String get settingsTiming => 'Timing offset';

  @override
  String get settingsTimingHelp =>
      'Input is treated as this much earlier, to cancel display and touch latency';

  @override
  String get calibrate => 'Calibrate';

  @override
  String get settingsBgm => 'Music volume';

  @override
  String get settingsSfx => 'Sound effects volume';

  @override
  String get settingsHaptics => 'Haptics';

  @override
  String get settingsQuality => 'Graphics';

  @override
  String get qualityHigh => 'High';

  @override
  String get qualityLow => 'Low (battery saver)';

  @override
  String get settingsReduceEffects => 'Reduce flashing';

  @override
  String get settingsReduceEffectsHelp =>
      'Tones down flashes, screen inversion and shake';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get languageSystem => 'System';

  @override
  String get calibrationTitle => 'TIMING CALIBRATION';

  @override
  String calibrationBody(String count) {
    return 'Tap the moment the ring meets the line ($count times)';
  }

  @override
  String calibrationResult(String ms) {
    return 'Result: ${ms}ms';
  }

  @override
  String get calibrationApply => 'Use this value';

  @override
  String get calibrationRetry => 'Try again';

  @override
  String get tapToStart => 'TAP TO START';

  @override
  String get rankingUnavailable => 'Leaderboards are not available';

  @override
  String get rankingEndlessScore => 'Endless: Score';

  @override
  String get rankingEndlessWave => 'Endless: Wave';

  @override
  String get rankingStages => 'Stages: Total score';

  @override
  String get introKeystone => 'NEW: KEYSTONE — BREAK IT TO COLLAPSE BLOCKS';

  @override
  String get introTurret => 'NEW: TURRET — PARRY ITS BULLETS';

  @override
  String get introExplosive =>
      'NEW: EXPLOSIVE — CHAIN BLASTS; PARRY THE DEBRIS';

  @override
  String get introReflector => 'NEW: REFLECTOR — CHANGES BALL TRAJECTORY';

  @override
  String get introMagnet => 'NEW: MAGNET — ATTRACTS THE BALL';

  @override
  String get introSplitter => 'NEW: SPLITTER — SCATTERS SMALL BLOCKS';

  @override
  String get introMirror => 'NEW: MIRROR — REFLECTS RETURNED BULLETS';

  @override
  String introLoop(String loop) {
    return 'LOOP $loop — SPEED UP';
  }

  @override
  String get introParry => 'TAP AS THE BALL HITS TO PARRY';

  @override
  String get introPierce => 'A PERFECT PARRY MAKES A PIERCING SHOT';

  @override
  String get introSurvive => 'HOLD THE BLOCKS ABOVE THE WARNING LINE';

  @override
  String get introScore => 'REACH THE TARGET SCORE';

  @override
  String get bannerBoss =>
      'HIT CORES WITH PARRIED RED BULLETS AND PIERCING SHOTS';

  @override
  String get bannerOverdrive => 'FULL PIERCE ×16 — PERFECT SPAWNS PHANTOMS';

  @override
  String get bannerPhase2 => 'MIRROR SHIELDS — LOCK-ON LASERS';

  @override
  String get bannerPhase3 => 'FORTRESS EXPANDS — BULLET STORM';

  @override
  String get bannerTimeOver => 'FORTRESS DIVING';

  @override
  String get endingSub => 'NEXT LOOP — SPEED KEEPS RISING';
}
