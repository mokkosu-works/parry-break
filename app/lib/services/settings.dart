import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 端末に保存する設定 (docs/native-app-spec.md 3.3)。
enum ControlScheme {
  /// 画面の左半分をドラッグして移動、右半分をタップしてパリィ。
  zones,

  /// 左の操作レールを横にドラッグ、右の PARRY ボタン。
  railHorizontal,

  /// 左の操作レールを縦にドラッグ、右の PARRY ボタン。
  railVertical,
}

enum GraphicsQuality { high, low }

class Settings {
  const Settings({
    this.controls = ControlScheme.zones,
    this.sensitivity = 2.0,
    this.timingOffsetMs = 36,
    this.bgmVolume = 0.8,
    this.sfxVolume = 1.0,
    this.haptics = true,
    this.quality = GraphicsQuality.high,
    this.reduceEffects = false,
    this.language,
    this.debugMode = false,
  });

  final ControlScheme controls;

  /// 移動感度 (指の移動量に対するパドルの移動量)。×1.0〜×4.0。
  final double sensitivity;

  /// 判定タイミング補正 (ms)。入力時刻をこの値だけ早めて扱う。0〜100。
  final int timingOffsetMs;

  final double bgmVolume, sfxVolume;
  final bool haptics;
  final GraphicsQuality quality;

  /// フラッシュ・点滅・画面の揺れを弱める。
  final bool reduceEffects;

  /// 'ja' / 'en'。null なら端末の言語。
  final String? language;

  /// 開発者向け: 全ステージを開け、結果を記録・ランキングに残さない。タイトルの版番号を 3 回タップで切り替える。
  final bool debugMode;

  Settings copyWith({
    ControlScheme? controls,
    double? sensitivity,
    int? timingOffsetMs,
    double? bgmVolume,
    double? sfxVolume,
    bool? haptics,
    GraphicsQuality? quality,
    bool? reduceEffects,
    String? Function()? language,
    bool? debugMode,
  }) =>
      Settings(
        controls: controls ?? this.controls,
        sensitivity: sensitivity ?? this.sensitivity,
        timingOffsetMs: timingOffsetMs ?? this.timingOffsetMs,
        bgmVolume: bgmVolume ?? this.bgmVolume,
        sfxVolume: sfxVolume ?? this.sfxVolume,
        haptics: haptics ?? this.haptics,
        quality: quality ?? this.quality,
        reduceEffects: reduceEffects ?? this.reduceEffects,
        language: language != null ? language() : this.language,
        debugMode: debugMode ?? this.debugMode,
      );

  Map<String, Object?> toJson() => {
        'controls': controls.name,
        'sensitivity': sensitivity,
        'timingOffsetMs': timingOffsetMs,
        'bgmVolume': bgmVolume,
        'sfxVolume': sfxVolume,
        'haptics': haptics,
        'quality': quality.name,
        'reduceEffects': reduceEffects,
        'language': language,
        'debugMode': debugMode,
      };

  factory Settings.fromJson(Map<String, Object?> j) {
    const d = Settings();
    T pick<T extends Enum>(List<T> values, Object? v, T fallback) =>
        values.where((e) => e.name == v).firstOrNull ?? fallback;
    double num_(Object? v, double fallback, double lo, double hi) =>
        v is num ? v.toDouble().clamp(lo, hi) : fallback;
    return Settings(
      controls: pick(ControlScheme.values, j['controls'], d.controls),
      sensitivity: num_(j['sensitivity'], d.sensitivity, 1, 4),
      timingOffsetMs: num_(j['timingOffsetMs'], d.timingOffsetMs.toDouble(), 0, 100).round(),
      bgmVolume: num_(j['bgmVolume'], d.bgmVolume, 0, 1),
      sfxVolume: num_(j['sfxVolume'], d.sfxVolume, 0, 1),
      haptics: j['haptics'] as bool? ?? d.haptics,
      quality: pick(GraphicsQuality.values, j['quality'], d.quality),
      reduceEffects: j['reduceEffects'] as bool? ?? d.reduceEffects,
      language: switch (j['language']) { 'ja' => 'ja', 'en' => 'en', _ => null },
      debugMode: j['debugMode'] as bool? ?? d.debugMode,
    );
  }
}

/// アプリ起動時に main で差し替える。
final sharedPrefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError());

class SettingsNotifier extends Notifier<Settings> {
  static const _key = 'settings.v1';

  @override
  Settings build() {
    final raw = ref.read(sharedPrefsProvider).getString(_key);
    if (raw == null) return const Settings();
    try {
      return Settings.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } on Object {
      return const Settings();
    }
  }

  void update(Settings Function(Settings) f) {
    state = f(state);
    ref.read(sharedPrefsProvider).setString(_key, jsonEncode(state.toJson()));
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, Settings>(SettingsNotifier.new);
