import 'dart:ui';

import 'palette.dart';

// 見た目の解放 (design.md 9.9)。プレイヤーレベルに応じて、パドルの色とボールの軌跡の色が増える。
// 描画だけを変える (当たり判定・大きさ・速さ・コアの結果は変えない)。色の値と解放のレベルはここだけに置く。

/// 選べる見た目の種類。
enum CosmeticKind {
  /// パドルの色。
  paddle,

  /// ボールの軌跡 (残像) の色。
  trail,
}

/// 1 つの色。[id] は保存する値 (変えない)、[name] は画面に出す名前 (日英共通)。
class CosmeticColor {
  const CosmeticColor(this.id, this.name, this.color, {this.unlockLevel = 1});

  final String id, name;
  final Color color;

  /// このレベルから使える (1 は最初から)。
  final int unlockLevel;

  bool unlockedAt(int level) => level >= unlockLevel;
}

/// 解放で手に入ったもの (どの種類の、どの色か)。
class CosmeticUnlock {
  const CosmeticUnlock(this.kind, this.item);
  final CosmeticKind kind;
  final CosmeticColor item;

  @override
  bool operator ==(Object other) =>
      other is CosmeticUnlock && other.kind == kind && other.item.id == item.id;

  @override
  int get hashCode => Object.hash(kind, item.id);
}

/// 色の表と解放の表。
///
/// 色は、敵弾 (橙・赤)・アイテムのカプセル (design.md 7.10)・FEVER TIME の桃色の地・
/// ブロックの色と紛らわしくならないものだけを選ぶ (`test/render/cosmetics_test.dart` が、
/// どの色もこれらから一定以上離れていることを確かめる)。パドルの既定の青はアイテム WIDE と同じ色で、今までどおり。
/// パリィ中の黄・クールダウンの鋼色・スタンの赤・被弾後の点滅は、選んだ色にかかわらず今までどおりで、
/// FEVER TIME 中の軌跡も今までどおりの桃色 (状態を伝える色は入れ替えない)。
abstract final class Cosmetics {
  /// 最初から使える色 (今までの色)。
  static const paddleDefault = CosmeticColor('sky', 'SKY', Dot.sky);

  /// 軌跡の既定は、ボール本体の色 (白・ステージで桃。貫通・FEVER TIME などの状態の色も今までどおり)。
  static const trailDefault = CosmeticColor('standard', 'STANDARD', Dot.white);

  static const _cyan = Color(0xFF1FD8F0);
  static const _teal = Color(0xFF12B5A6);
  static const _leaf = Color(0xFF5BD62E);
  static const _lime = Color(0xFFB5F23D);
  static const _lavender = Color(0xFFB9A8FF);

  /// パドルの色。解放は Lv2 / 6 / 10 / 16 / 25。
  static const paddles = [
    paddleDefault,
    CosmeticColor('cyan', 'CYAN', _cyan, unlockLevel: 2),
    CosmeticColor('lime', 'LIME', _lime, unlockLevel: 6),
    CosmeticColor('teal', 'TEAL', _teal, unlockLevel: 10),
    CosmeticColor('leaf', 'LEAF', _leaf, unlockLevel: 16),
    CosmeticColor('lavender', 'LAVENDER', _lavender, unlockLevel: 25),
  ];

  /// 軌跡の色。解放は Lv4 / 8 / 13 / 20 / 30。
  static const trails = [
    trailDefault,
    CosmeticColor('cyan', 'CYAN', _cyan, unlockLevel: 4),
    CosmeticColor('lime', 'LIME', _lime, unlockLevel: 8),
    CosmeticColor('lavender', 'LAVENDER', _lavender, unlockLevel: 13),
    CosmeticColor('teal', 'TEAL', _teal, unlockLevel: 20),
    CosmeticColor('leaf', 'LEAF', _leaf, unlockLevel: 30),
  ];

  static List<CosmeticColor> of(CosmeticKind kind) => switch (kind) {
    CosmeticKind.paddle => paddles,
    CosmeticKind.trail => trails,
  };

  static CosmeticColor defaultOf(CosmeticKind kind) => of(kind).first;

  /// 保存した [id] が表にある値か (なければ既定として読むので、保存の読み込みで使う)。
  static String known(CosmeticKind kind, Object? id) =>
      of(kind).where((c) => c.id == id).firstOrNull?.id ?? defaultOf(kind).id;

  /// 選んでいる [id] を、レベル [level] で実際に使う色にする。
  /// 表にない値・まだ解放されていない値は既定にする。
  static CosmeticColor resolve(CosmeticKind kind, Object? id, int level) {
    final c = of(kind).where((c) => c.id == id).firstOrNull;
    return c != null && c.unlockedAt(level) ? c : defaultOf(kind);
  }

  /// レベル [from] から [to] に上がったときに新しく解放されるもの (解放のレベルの順。同じレベルならパドルが先)。
  static List<CosmeticUnlock> unlockedBetween(int from, int to) {
    final out = <CosmeticUnlock>[
      for (final kind in CosmeticKind.values)
        for (final c in of(kind))
          if (c.unlockLevel > from && c.unlockLevel <= to)
            CosmeticUnlock(kind, c),
    ];
    // List.sort は安定ではないので、(レベル, 種類) で決める
    out.sort((a, b) {
      final l = a.item.unlockLevel.compareTo(b.item.unlockLevel);
      return l != 0 ? l : a.kind.index.compareTo(b.kind.index);
    });
    return out;
  }
}
