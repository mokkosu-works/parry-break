import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parry_break/render/palette.dart';
import 'package:parry_break/ui/arcade.dart';

/// Issue #114: 影を重ねて描く見出しが、読み上げで 1 回だけ読まれること。
void main() {
  testWidgets('PixelTitle は影を読み上げず、見出しとして 1 回だけ読まれる', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: PixelTitle('PAUSED', size: 56, color: Palette.yellow)),
    ));

    expect(find.bySemanticsLabel('PAUSED'), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel('PAUSED')),
      matchesSemantics(label: 'PAUSED', isHeader: true, textDirection: TextDirection.ltr),
    );
    handle.dispose();
  });
}
