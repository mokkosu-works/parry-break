import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parry_break/services/settings.dart';
import 'package:parry_break/ui/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// [BlinkCursor] を出し、0.05 秒ずつ 2 秒進めながら、その時々の不透明度を返す。
Future<List<double>> _opacities(
  WidgetTester tester, {
  bool reduceEffects = false,
  bool disableAnimations = false,
}) async {
  SharedPreferences.setMockInitialValues({'settings.v1': jsonEncode(Settings(reduceEffects: reduceEffects).toJson())});
  final sp = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPrefsProvider.overrideWithValue(sp)],
      child: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: BlinkCursor()),
        ),
      ),
    ),
  );
  final out = <double>[];
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    out.add(
      tester.widget<Opacity>(find.descendant(of: find.byType(BlinkCursor), matching: find.byType(Opacity))).opacity,
    );
  }
  return out;
}

void main() {
  testWidgets('ふだんは点滅する', (tester) async {
    final o = await _opacities(tester);
    expect(o, contains(0.0));
    expect(o, contains(1.0));
  });

  testWidgets('「演出を控えめにする」が ON なら点滅しない (#102)', (tester) async {
    final o = await _opacities(tester, reduceEffects: true);
    expect(o, everyElement(1.0));
  });

  testWidgets('端末の「アニメーションを減らす」が ON なら点滅しない', (tester) async {
    final o = await _opacities(tester, disableAnimations: true);
    expect(o, everyElement(1.0));
  });
}
