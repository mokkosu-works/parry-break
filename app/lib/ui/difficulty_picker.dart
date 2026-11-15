import 'package:flutter/material.dart';

import '../core/core.dart';
import '../render/palette.dart';
import 'stage_text.dart';
import 'widgets.dart';

/// 難易度の切り替え (ステージ選択は EASY / NORMAL / HARD、エンドレスは [values] で絞る)。選んでいるものは難易度の色で塗る。
class DifficultyPicker extends StatelessWidget {
  const DifficultyPicker({
    super.key,
    required this.value,
    this.values = Difficulty.values,
    required this.label,
    required this.onChanged,
  });
  final Difficulty value;

  /// 選べる難易度 (並べる順)。
  final List<Difficulty> values;
  final String label;
  final ValueChanged<Difficulty> onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final d in values)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Semantics(
              button: true,
              selected: d == value,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(d),
                // 見た目の枠はそのままで、押せる範囲を上下に広げて高さ 44pt 以上にする
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Align(
                    widthFactor: 1,
                    heightFactor: 1,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: d == value ? difficultyColor(d) : Dot.night,
                        border: Border.all(
                          color: d == value ? difficultyColor(d) : Dot.edge,
                          width: 3,
                        ),
                      ),
                      child: Text(
                        d.label,
                        style: pixelFont(
                          13,
                          color: d == value ? Dot.ink : Palette.gray,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
