import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parry_break/core/core.dart';
import 'package:parry_break/haptics/haptics_service.dart';

ParrySucceeded _parry(ParryGrade g) =>
    ParrySucceeded(grade: g, target: ParryTarget.ball, x: 0, y: 0, paddleX: 0, streak: 1);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// HapticFeedback がプラットフォームに送った種類 ('HapticFeedbackType.heavyImpact' など、vibrate は null)。
  late List<String?> calls;
  late HapticsService h;

  setUp(() {
    calls = [];
    h = HapticsService();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (
      call,
    ) async {
      if (call.method == 'HapticFeedback.vibrate') calls.add(call.arguments as String?);
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  const heavy = 'HapticFeedbackType.heavyImpact';
  const medium = 'HapticFeedbackType.mediumImpact';
  const light = 'HapticFeedbackType.lightImpact';

  testWidgets('振動が OFF のときは何も呼ばない', (tester) async {
    h.enabled = false;
    h
      ..handle(_parry(ParryGrade.just))
      ..handle(const PlayerHurt(0))
      ..handle(GameOver(reason: 'deadline', score: 0, round: 1, stats: RunStats()))
      ..selection();
    await tester.pump(const Duration(seconds: 1));
    expect(calls, isEmpty);
  });

  testWidgets('JUST のパリィで 3 回の強い振動 (0 / 60 / 120ms)', (tester) async {
    h.handle(_parry(ParryGrade.just));
    expect(calls, [heavy]);
    await tester.pump(const Duration(milliseconds: 59));
    expect(calls, [heavy]);
    await tester.pump(const Duration(milliseconds: 1));
    expect(calls, [heavy, heavy]);
    await tester.pump(const Duration(milliseconds: 60));
    expect(calls, [heavy, heavy, heavy]);
    await tester.pump(const Duration(seconds: 1));
    expect(calls, hasLength(3));
  });

  testWidgets('PERFECT は中くらい 1 回、GOOD は弱い 1 回、被弾は長い振動 1 回', (tester) async {
    h.handle(_parry(ParryGrade.perfect));
    h.handle(_parry(ParryGrade.good));
    h.handle(const PlayerHurt(0));
    await tester.pump(const Duration(seconds: 1));
    expect(calls, [medium, light, null]);
  });

  testWidgets('新しいパターンが前のパターンの残りを打ち切る', (tester) async {
    h.handle(_parry(ParryGrade.just)); // 0ms に強、60・120ms に強が残る
    await tester.pump(const Duration(milliseconds: 30));
    h.handle(_parry(ParryGrade.good)); // ここで残りを打ち切る
    await tester.pump(const Duration(seconds: 1));
    expect(calls, [heavy, light]);
  });

  testWidgets('振動しないイベントでは、前のパターンの残りを打ち切らない', (tester) async {
    h.handle(_parry(ParryGrade.just));
    h.handle(const ParryMissed());
    await tester.pump(const Duration(seconds: 1));
    expect(calls, [heavy, heavy, heavy]);
  });

  testWidgets('selection は選択のクリックを鳴らす', (tester) async {
    h.selection();
    expect(calls, ['HapticFeedbackType.selectionClick']);
  });
}
