import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ストアの評価の依頼 (OS 標準のダイアログ) を出してよいかの判定。
///
/// 気持ちよく遊べた直後 (ステージを星 3 つでクリア) に、次の条件がそろったときだけ出す。
/// OS 側にも回数の制限があり、実際にダイアログが出るかは OS が決める。
/// - ステージを [minClears] 面クリアしたあと (遊び始めには聞かない)
/// - 前回の依頼から [minGap] 以上あける
/// - 通算 [maxAsks] 回まで
class ReviewPolicy {
  ReviewPolicy(this._prefs, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  final SharedPreferences _prefs;
  final DateTime Function() _now;

  static const minClears = 5;
  static const minGap = Duration(days: 60);
  static const maxAsks = 3;

  static const _lastKey = 'review.lastAsked';
  static const _countKey = 'review.count';

  /// [clearedStages] はクリア済みのステージの数。
  bool due({required int clearedStages}) {
    if (clearedStages < minClears) return false;
    final count = _prefs.getInt(_countKey) ?? 0;
    if (count >= maxAsks) return false;
    final last = _prefs.getInt(_lastKey);
    if (last == null) return true;
    final gap = _now().difference(DateTime.fromMillisecondsSinceEpoch(last));
    // 端末の時計が戻されて前回が未来になったときは、出せなくならないよう出してよいとする
    return gap.isNegative || gap >= minGap;
  }

  void recordAsked() {
    _prefs
      ..setInt(_lastKey, _now().millisecondsSinceEpoch)
      ..setInt(_countKey, (_prefs.getInt(_countKey) ?? 0) + 1);
  }
}

abstract class ReviewService {
  /// 条件がそろっていれば評価の依頼を出す。出したら true。
  /// [clearedStages] はクリア済みのステージの数。
  Future<bool> askIfDue({required int clearedStages});
}

class DisabledReview implements ReviewService {
  @override
  Future<bool> askIfDue({required int clearedStages}) async => false;
}

class StoreReview implements ReviewService {
  StoreReview(this._policy, {InAppReview? review}) : _review = review ?? InAppReview.instance;

  final ReviewPolicy _policy;
  final InAppReview _review;

  @override
  Future<bool> askIfDue({required int clearedStages}) async {
    if (!_policy.due(clearedStages: clearedStages)) return false;
    try {
      if (!await _review.isAvailable()) return false;
      // 出す前に記録する (ダイアログが出たかどうかはアプリからは分からないため)
      _policy.recordAsked();
      await _review.requestReview();
      return true;
    } catch (e) {
      debugPrint('review: $e');
      return false;
    }
  }
}

/// 起動時に main で [createReviewService] の結果に差し替える。テストでは何もしない実装のまま。
final reviewProvider = Provider<ReviewService>((ref) => DisabledReview());

ReviewService createReviewService(SharedPreferences prefs) {
  final mobile = defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android;
  if (kIsWeb || !mobile) return DisabledReview();
  return StoreReview(ReviewPolicy(prefs));
}
