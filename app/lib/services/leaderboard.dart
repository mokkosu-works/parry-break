import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:games_services/games_services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'settings.dart';

/// ランキングのボード。
enum Board { endlessScore, endlessRound, stagesTotal }

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
    Board.endlessRound: 'com.watsuwo.parrybreak.endless_wave',
    Board.stagesTotal: 'com.watsuwo.parrybreak.stages_total',
  };

  static const android = <Board, String>{
    Board.endlessScore: '',
    Board.endlessRound: '',
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

/// games_services の呼び出し。テストで偽の送信先に差し替えるために分けてある。
class LeaderboardPlatform {
  const LeaderboardPlatform();
  Future<void> signIn() => GamesServices.signIn();
  Future<bool> get isSignedIn => GamesServices.isSignedIn;
  Future<void> submitScore(Score score) =>
      GamesServices.submitScore(score: score);
  Future<void> showLeaderboards({
    required String iOSLeaderboardID,
    required String androidLeaderboardID,
  }) => GamesServices.showLeaderboards(
    iOSLeaderboardID: iOSLeaderboardID,
    androidLeaderboardID: androidLeaderboardID,
  );
}

class GamesServicesLeaderboard implements LeaderboardService {
  GamesServicesLeaderboard(
    this._prefs, [
    this._platform = const LeaderboardPlatform(),
  ]);
  final SharedPreferences _prefs;
  final LeaderboardPlatform _platform;
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

  set _pending(Map<String, int> v) =>
      _prefs.setString(_pendingKey, jsonEncode(v));

  Score _score(Board b, int value) => Score(
    iOSLeaderboardID: LeaderboardConfig.ios[b],
    androidLeaderboardID: LeaderboardConfig.android[b],
    value: value,
  );

  /// 実行中の signIn。起動時と RANKING の signIn が重なっても、送信と書き戻しを 1 回にする。
  Future<void>? _signingIn;

  @override
  Future<void> signIn() =>
      _signingIn ??= _signIn().whenComplete(() => _signingIn = null);

  Future<void> _signIn() async {
    try {
      await _platform.signIn();
      _signedIn = await _platform.isSignedIn;
    } on Object catch (e) {
      debugPrint('leaderboard sign-in failed: $e');
      _signedIn = false;
    }
    if (!_signedIn) return;
    final boards = Board.values.asNameMap();
    // 消してよいもの: 送れた分 (送った値) と、今のバージョンにないボード
    // (過去のバージョンで保留したもの。送り先がないので捨てる)
    final done = <String, int?>{};
    for (final e in _pending.entries) {
      final b = boards[e.key];
      if (b == null) {
        done[e.key] = null;
      } else if (await _send(b, e.value)) {
        done[e.key] = e.value;
      }
    }
    // 送っている間に submit が保留を書き足していることがあるので、読み直してから消す。
    // 送った値より高いスコアが書き足されていれば、それはまだ送れていないので残す。
    final p = _pending;
    for (final e in done.entries) {
      final sent = e.value;
      if (sent == null || (p[e.key] ?? sent) <= sent) p.remove(e.key);
    }
    _pending = p;
  }

  Future<bool> _send(Board b, int value) async {
    try {
      await _platform.submitScore(_score(b, value));
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
      await _platform.showLeaderboards(
        iOSLeaderboardID: board == null ? '' : LeaderboardConfig.ios[board]!,
        androidLeaderboardID: board == null
            ? ''
            : LeaderboardConfig.android[board]!,
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
