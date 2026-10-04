import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:games_services/games_services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'settings.dart';

/// ランキングのボード。
enum Board { endlessScore, endlessWave, stagesTotal }

/// ストアで作ったリーダーボードの ID。
///
/// App Store Connect (Game Center) と Google Play Console (Play Games Services) で
/// リーダーボードを作成し、ここに ID を書いてから、その OS のフラグを true にする。
/// Android は android/app/src/main/res/values/games-ids.xml の app_id も設定する。
/// 手順は docs/native-app-spec.md の「ランキングの設定」を参照。
abstract final class LeaderboardConfig {
  static const iosEnabled = true;
  static const androidEnabled = false;

  static bool get enabled => switch (defaultTargetPlatform) {
    TargetPlatform.iOS => iosEnabled,
    TargetPlatform.android => androidEnabled,
    _ => false,
  };

  static const ios = <Board, String>{
    Board.endlessScore: 'com.watsuwo.parrybreak.endless_score',
    Board.endlessWave: 'com.watsuwo.parrybreak.endless_wave',
    Board.stagesTotal: 'com.watsuwo.parrybreak.stages_total',
  };

  static const android = <Board, String>{
    Board.endlessScore: '',
    Board.endlessWave: '',
    Board.stagesTotal: '',
  };
}

abstract class LeaderboardService {
  bool get available;

  /// 起動時に呼ぶ。サインインし、保留していた送信を送る。
  Future<void> signIn();

  /// スコアを送る。送れなければ保留して、次のサインイン時に送る。
  Future<void> submit(Board board, int value);

  /// 端末標準のランキング画面を開く。開けなければ false。
  Future<bool> show([Board? board]);
}

class DisabledLeaderboard implements LeaderboardService {
  @override
  bool get available => false;
  @override
  Future<void> signIn() async {}
  @override
  Future<void> submit(Board board, int value) async {}
  @override
  Future<bool> show([Board? board]) async => false;
}

class GamesServicesLeaderboard implements LeaderboardService {
  GamesServicesLeaderboard(this._prefs);
  final SharedPreferences _prefs;
  static const _pendingKey = 'leaderboard.pending';
  bool _signedIn = false;

  @override
  bool get available => true;

  Map<String, int> get _pending {
    final raw = _prefs.getString(_pendingKey);
    if (raw == null) return {};
    try {
      return Map<String, int>.from(jsonDecode(raw) as Map);
    } on Object {
      return {};
    }
  }

  set _pending(Map<String, int> v) => _prefs.setString(_pendingKey, jsonEncode(v));

  Score _score(Board b, int value) => Score(
    iOSLeaderboardID: LeaderboardConfig.ios[b],
    androidLeaderboardID: LeaderboardConfig.android[b],
    value: value,
  );

  @override
  Future<void> signIn() async {
    try {
      await GamesServices.signIn();
      _signedIn = await GamesServices.isSignedIn;
    } on Object catch (e) {
      debugPrint('leaderboard sign-in failed: $e');
      _signedIn = false;
    }
    if (!_signedIn) return;
    final pending = _pending;
    final left = <String, int>{};
    for (final e in pending.entries) {
      final b = Board.values.byName(e.key);
      if (!await _send(b, e.value)) left[e.key] = e.value;
    }
    _pending = left;
  }

  Future<bool> _send(Board b, int value) async {
    try {
      await GamesServices.submitScore(score: _score(b, value));
      return true;
    } on Object catch (e) {
      debugPrint('leaderboard submit failed: $e');
      return false;
    }
  }

  @override
  Future<void> submit(Board board, int value) async {
    if (_signedIn && await _send(board, value)) return;
    // 送れなかった: ボードごとに最高値だけを保留する
    final p = _pending;
    if ((p[board.name] ?? -1) < value) p[board.name] = value;
    _pending = p;
  }

  @override
  Future<bool> show([Board? board]) async {
    if (!_signedIn) await signIn();
    if (!_signedIn) return false;
    try {
      await GamesServices.showLeaderboards(
        iOSLeaderboardID: board == null ? '' : LeaderboardConfig.ios[board]!,
        androidLeaderboardID: board == null ? '' : LeaderboardConfig.android[board]!,
      );
      return true;
    } on Object {
      return false;
    }
  }
}

final leaderboardProvider = Provider<LeaderboardService>((ref) {
  if (!LeaderboardConfig.enabled || kIsWeb) return DisabledLeaderboard();
  return GamesServicesLeaderboard(ref.read(sharedPrefsProvider));
});
