/// 入力イベントの時刻 (実時間) をシミュレーション時刻へ換算する。
///
/// 毎フレームの終わりに「その時点の実時間とシミュレーション時刻」と、その先の時間の進み方
/// (ヒットストップの残り・スローモーションの残り) を記録しておき、次のフレームで届いた入力の時刻を換算する。
/// これによりパリィの判定はフレーム単位に丸められず、押した瞬間の時刻で行われる。
class TimeSync {
  double wall = 0, sim = 0;

  /// [wall] から [hold] 秒 (実時間) の間は、シミュレーションが止まっている (ヒットストップの残り)。
  double hold = 0;

  /// [hold] が明けてから [slow] 秒 (実時間) の間、実時間 1 秒あたりに進むシミュレーション時間
  /// (スローモーション中は 0.35)。その後は 1。
  double scale = 1;

  /// [scale] で進む時間 (実時間)。スローモーションでなければ無限。
  double slow = double.infinity;

  /// 実時間とシミュレーション時刻を同じにする (ボットやテストが、シミュレーション時刻で入力を積むとき)。
  void identity() {
    wall = sim = hold = 0;
    scale = 1;
    slow = double.infinity;
  }

  double toSim(double wallTime) {
    var e = wallTime - wall;
    if (e <= 0) return sim + (hold > 0 ? 0 : e * scale);
    if (e <= hold) return sim;
    e -= hold;
    if (e <= slow) return sim + e * scale;
    return sim + slow * scale + (e - slow);
  }
}
