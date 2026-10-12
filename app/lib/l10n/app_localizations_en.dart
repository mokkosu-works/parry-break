// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'PARRY BREAK';

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
  String get helpMoveZones =>
      'Drag on the left half of the screen to move the paddle';

  @override
  String get helpMoveRail => 'Drag the rail on the left to move the paddle';

  @override
  String get helpParryTitle => 'LAUNCH / PARRY';

  @override
  String get helpParryZones =>
      'Tap the right half to launch the ball\nTap just as the ball or an enemy shot hits the paddle to knock it back hard (parry)';

  @override
  String get helpParryRail =>
      'Press PARRY to launch the ball\nPress it just as the ball or an enemy shot hits the paddle to knock it back hard (parry)';

  @override
  String get helpTimingTitle => 'TIMING';

  @override
  String get helpTimingBody =>
      'The closer to the moment of impact, the stronger the hit\nPERFECT: the ball pierces through blocks\nJUST (even closer): its next hit sends out a shockwave that breaks nearby blocks';

  @override
  String get helpChainTitle => 'CHAIN';

  @override
  String get helpChainBody =>
      'White blocks (keystones) hold up the blocks attached to them. Break one and the whole cluster falls\nOrange striped blocks (explosives) blow up their surroundings, setting off nearby explosives in turn';

  @override
  String get helpHeatTitle => 'HEAT / OVERDRIVE';

  @override
  String get helpHeatBody =>
      'Land parries and return enemy shots to fill the HEAT meter at the top. Each stage raises your score multiplier (×1 → ×2 → ×4 → ×8) and the ball\'s speed\nFill the meter for OVERDRIVE: for a while the ball pierces blocks and the multiplier is ×16\nGetting hit by an enemy shot lowers HEAT';

  @override
  String get helpGrazeTitle => 'GRAZE / RICOCHET';

  @override
  String get helpGrazeBody =>
      'GRAZE: dodge an enemy shot by a hair, without letting it hit the paddle. It raises HEAT\nRICOCHET: break 8 or more blocks before the ball returns to the paddle. The more you break, the higher the score';

  @override
  String get helpOverTitle => 'GAME OVER';

  @override
  String get helpOverBody =>
      'The run ends if the ball falls off the bottom\nIt also ends if the blocks reach the red dotted dead line';

  @override
  String get helpPauseTitle => 'PAUSE';

  @override
  String get helpPauseBody => 'Tap Ⅱ at the top right to pause';

  @override
  String get helpPrev => 'PREV';

  @override
  String get helpNext => 'NEXT';

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
  String get settingsTabControls => 'CONTROLS';

  @override
  String get settingsTabSound => 'SOUND';

  @override
  String get settingsTabDisplay => 'DISPLAY';

  @override
  String get settingsTabOther => 'OTHER';

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
      'Tones down flashes, blinking and shake';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsAdPrivacy => 'Ad privacy settings';

  @override
  String get settingsDebugMode => 'Debug mode';

  @override
  String get settingsDebugModeHelp =>
      'All stages are playable. Results are not recorded or ranked';

  @override
  String get debugModeOn => 'Debug mode ON';

  @override
  String get debugModeOff => 'Debug mode OFF';

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
  String get introSpread => 'NEW: SPREAD TURRET — PARRY THE WHOLE FAN AT ONCE';

  @override
  String get introGatling => 'NEW: GATLING — A TRACKING BURST; PARRY IN RHYTHM';

  @override
  String get introRing => 'NEW: RING TURRET — SLIP THROUGH THE GAPS';

  @override
  String get introSpiral => 'NEW: SPIRAL TURRET — ATTACK WHILE IT RESTS';

  @override
  String get introSniper =>
      'NEW: SNIPER — WHEN THE SIGHT LOCKS, A FAST SHOT FOLLOWS';

  @override
  String introLoop(String loop) {
    return 'LOOP $loop — SPEED UP';
  }

  @override
  String get introParry => 'TAP AS THE BALL HITS TO PARRY';

  @override
  String get introPierce => 'A PERFECT PARRY MAKES A PIERCING SHOT';

  @override
  String get introOverdrive =>
      'CHAIN PERFECTS TO FILL HEAT — OVERDRIVE PIERCES EVERYTHING';

  @override
  String get introSurvive => 'HOLD THE BLOCKS ABOVE THE DEAD LINE';

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

  @override
  String get difficulty => 'Difficulty';

  @override
  String get difficultyEasy =>
      'Fewer, slower bullets. Wider parry timing and more time for bosses';

  @override
  String get difficultyNormal => 'Standard difficulty';

  @override
  String get difficultyHard =>
      'Bullet hell. More bullets, and broken blocks shoot back';
}
