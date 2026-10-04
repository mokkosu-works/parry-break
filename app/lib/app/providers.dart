import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audio/audio_service.dart';
import '../haptics/haptics_service.dart';
import '../services/settings.dart';

/// 音 (起動時に main で初期化したものに差し替える)。
final audioProvider = Provider<AudioService>((ref) => SilentAudio());

/// 振動。設定の ON/OFF に追従する。
final hapticsProvider = Provider<HapticsService>((ref) {
  final h = HapticsService();
  ref.listen(settingsProvider.select((s) => s.haptics), (_, on) => h.enabled = on, fireImmediately: true);
  return h;
});

/// デバッグモード中か (設定の [Settings.debugMode])。
final debugModeProvider = Provider<bool>((ref) => ref.watch(settingsProvider.select((s) => s.debugMode)));

/// ゲームの時計 (秒)。null なら実時間。テストでは偽の時刻に差し替える。
final timeSourceProvider = Provider<double Function()?>((ref) => null);
