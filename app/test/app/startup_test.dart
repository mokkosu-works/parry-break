import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parry_break/main.dart';
import 'package:parry_break/services/error_log.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ステージの JSON を読もうとすると例外を投げる。
class _BrokenBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) => throw FlutterError('broken asset: $key');
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ErrorLog.recent.clear();
  });

  testWidgets('ステージの読み込みで例外が出たら、エラー画面を出す', (tester) async {
    final root = await tester.runAsync(() => buildRoot(_BrokenBundle()));
    await tester.pumpWidget(root!);
    await tester.pump();
    expect(find.byType(StartupErrorApp), findsOneWidget);
    expect(find.byType(ProviderScope), findsNothing);
    expect(find.text("Couldn't start"), findsOneWidget);
    expect(ErrorLog.recent, hasLength(1));
    expect(ErrorLog.recent.single, contains('broken asset'));
  });

  testWidgets('エラー画面は日本語でも出る', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('ja')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(StartupErrorApp(error: Exception('x')));
    await tester.pump();
    expect(find.text('起動できませんでした'), findsOneWidget);
  });

  test('FlutterError と、捕まえられなかった非同期の例外を記録する', () {
    final flutterOnError = FlutterError.onError;
    final dispatcher = PlatformDispatcher.instance;
    final platformOnError = dispatcher.onError;
    addTearDown(() {
      FlutterError.onError = flutterOnError;
      dispatcher.onError = platformOnError;
    });

    ErrorLog.install();
    FlutterError.reportError(FlutterErrorDetails(exception: StateError('build failed')));
    expect(dispatcher.onError!(StateError('async failed'), StackTrace.current), isTrue);
    expect(ErrorLog.recent, hasLength(2));
    expect(ErrorLog.recent[0], contains('build failed'));
    expect(ErrorLog.recent[1], contains('async failed'));
  });

  test('記録は直近の分だけ残す', () {
    for (var i = 0; i < ErrorLog.capacity + 5; i++) {
      ErrorLog.record(Exception('e$i'), null);
    }
    expect(ErrorLog.recent, hasLength(ErrorLog.capacity));
    expect(ErrorLog.recent.last, contains('e${ErrorLog.capacity + 4}'));
  });
}
