/// プレイの難易度 (ステージモードで選ぶ)。
///
/// NORMAL が基準 (エンドレスも NORMAL)。HARD は弾幕モードで、砲台・ボスの弾が増え、
/// ブロックを壊すと撃ち返し弾 (打ち返し) が飛んでくる。
enum Difficulty {
  easy,
  normal,
  hard;

  T pick<T>(T easy, T normal, T hard) => switch (this) {
        Difficulty.easy => easy,
        Difficulty.normal => normal,
        Difficulty.hard => hard,
      };

  /// 攻撃ブロック (砲台など) の発射頻度の倍率 (大きいほど頻繁に撃つ)。
  double get fireRate => pick(0.7, 1.0, 1.5);

  /// ボスの攻撃頻度の倍率。HARD は攻撃の種類が増えるので、頻度は控えめに上げる。
  double get bossFireRate => pick(0.75, 1.0, 1.1);

  /// 敵弾の速さの倍率。HARD は数で攻めるため、少しだけ遅くして見切れるようにする。
  double get bulletSpeed => pick(0.85, 1.0, 0.92);

  /// ブロック群の降下速度の倍率。
  double get descent => pick(0.8, 1.0, 1.0);

  /// ボールかパリィでブロックを壊したとき、そのブロックがパドルへ撃ち返してくる確率。
  double get revengeChance => pick(0.0, 0.0, 0.4);

  /// ボス戦の制限時間に足す秒数。
  double get bossTimeBonus => pick(30.0, 0.0, 0.0);

  /// バランス値の上書き ([Tuning.copyWith])。EASY はパリィの判定を広げる。
  Map<String, Object?> get tuning => pick(
        const {'parryWindow': 0.13, 'perfectWindow': 0.04, 'justWindow': 0.016},
        const {},
        const {},
      );

  /// 記録の保存キーに付ける接尾辞 (NORMAL は付けない。以前の記録と互換にするため)。
  String get recordSuffix => this == Difficulty.normal ? '' : '@$name';

  String get label => name.toUpperCase();
}
