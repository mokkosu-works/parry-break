import 'package:flutter/foundation.dart';

/// 予期しない例外を一か所で受けて記録する。
///
/// 記録は端末のログ (Android は logcat の flutter、iOS はコンソール) に出す。
/// debugPrint はリリースビルドでも出る。外部のクラッシュ収集サービスには送らない
/// (送るとプライバシーの申告が変わるため。Issue #155)。
abstract final class ErrorLog {
  /// [recent] に残す件数。
  static const capacity = 20;

  /// 直近の例外の要約 (古い順)。
  static final recent = <String>[];

  /// 起動の最初に呼ぶ。Flutter の枠組みの中の例外 (描画・入力など) と、
  /// どこにも捕まえられなかった非同期の例外を受ける。
  static void install() {
    FlutterError.onError = (details) {
      // 既定と同じくログに出す (リリースビルドでも、silent でなければ要約を出す)
      FlutterError.presentError(details);
      _remember(details.exception, context: details.context?.toDescription());
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      record(error, stack, context: 'uncaught');
      return true;
    };
  }

  /// 例外をログに出して記録する。
  static void record(Object error, StackTrace? stack, {String? context}) {
    debugPrint('ERROR${context == null ? '' : ' ($context)'}: $error');
    if (stack != null) debugPrint(stack.toString());
    _remember(error, context: context);
  }

  static void _remember(Object error, {String? context}) {
    recent.add('${context == null ? '' : '[$context] '}$error');
    while (recent.length > capacity) {
      recent.removeAt(0);
    }
  }
}
