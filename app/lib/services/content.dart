import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/core.dart';

/// assets/stages/ から読み込んだゲームの中身。
class GameContent {
  const GameContent({required this.endless, required this.campaign});
  final EndlessContent endless;
  final Campaign campaign;

  static Future<GameContent> load(AssetBundle bundle) async {
    Future<Map<String, Object?>> json(String path) async =>
        jsonDecode(await bundle.loadString(path)) as Map<String, Object?>;
    final endless = EndlessContent.fromJson(await json('assets/stages/endless.json'));
    final campaign = Campaign.fromJson(await json('assets/stages/campaign.json'), endless);
    return GameContent(endless: endless, campaign: campaign);
  }
}

/// アプリ起動時に main で差し替える。
final contentProvider = Provider<GameContent>((ref) => throw UnimplementedError());
