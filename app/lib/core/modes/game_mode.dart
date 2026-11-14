import 'dart:math' as math;

import '../events/game_event.dart';
import '../stages/content.dart';
import '../stages/round_spec.dart';

/// 1 回のプレイの進め方。新しいモード (デイリー、ボスラッシュなど) はこれを実装する。
abstract class GameMode {
  const GameMode();

  /// 記録・ランキングの保存先を表すキー。
  String get recordKey;

  /// [number] 番目 (1 始まり) のラウンド。モードが終わりなら null。
  RoundSpec? roundAt(int number);

  /// 最初に遊ぶラウンドの番号。
  int get firstRound => 1;
}

/// エンドレス (アーケード): 60 ラウンドを繰り返し、1 周ごとに速くなる。10 ラウンドごとにボス。
class EndlessMode extends GameMode {
  const EndlessMode(this.content);
  final EndlessContent content;

  @override
  String get recordKey => 'endless';

  @override
  RoundSpec roundAt(int number) => content.round(number);
}

/// ステージモード: ステージに書かれたラウンドを順に遊び、最後をクリアしたら終わり。
class StageMode extends GameMode {
  const StageMode(this.stage);
  final StageDef stage;

  @override
  String get recordKey => 'stage:${stage.id}';

  @override
  RoundSpec? roundAt(int number) =>
      number <= stage.rounds.length ? stage.rounds[number - 1] : null;
}

/// デイリーチャレンジの 1 日分: その日 (UTC の日付) から決まる、エンドレスの続いた [rounds] ラウンド。
///
/// 配置・乱数はラウンドの番号から決まるので、同じ日付なら、どの端末でも同じ配置・同じアイテムになる。
class DailyChallenge {
  const DailyChallenge(this.day);

  /// [time] の UTC の日付の [DailyChallenge]。
  factory DailyChallenge.of(DateTime time) => DailyChallenge(dayOf(time));

  /// 1970-01-01 (UTC) からの日数。
  final int day;

  /// 1 日に遊ぶラウンドの数。
  static const rounds = 5;

  /// 始まりのラウンドの範囲 (エンドレスの 1 周目の中に収める。最初の数ラウンドは練習寄りなので外す)。
  static const minStart = 6, maxStart = 56;

  /// 始まりの候補の数。
  static const _span = maxStart - minStart + 1;

  /// [time] の UTC の日付の、1970-01-01 からの日数。
  static int dayOf(DateTime time) {
    final u = time.toUtc();
    return DateTime.utc(u.year, u.month, u.day).millisecondsSinceEpoch ~/
        Duration.millisecondsPerDay;
  }

  /// その日の種。始まりのラウンドを決める。
  int get seed => day * 7919 + 17;

  /// 始まりのラウンドの番号。[_span] と互いに素な数ずつずらすので、隣り合う日は必ず違う番号になり、
  /// [_span] 日のうちに同じ番号は 2 度出ない。
  int get startRound => minStart + (seed * 23) % _span;

  /// 最後のラウンドの番号。
  int get lastRound => startRound + rounds - 1;

  /// UTC の日付 (YYYY-MM-DD)。
  String get label {
    final d = DateTime.fromMillisecondsSinceEpoch(
      day * Duration.millisecondsPerDay,
      isUtc: true,
    );
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }
}

/// デイリーチャレンジ (DAILY): その日のエンドレスの [DailyChallenge.rounds] ラウンドを続けて遊ぶ。
/// ミスしたらそこで終わり。難易度は NORMAL 固定。
class DailyMode extends GameMode {
  const DailyMode(this.content, this.challenge);
  final EndlessContent content;
  final DailyChallenge challenge;

  @override
  String get recordKey => 'daily';

  @override
  int get firstRound => challenge.startRound;

  @override
  RoundSpec? roundAt(int number) =>
      number >= challenge.startRound && number <= challenge.lastRound
      ? content.round(number)
      : null;
}

/// 練習場のボールの速さ。
enum PracticeSpeed {
  /// コンボ段階 1 の速さ。
  stage1,

  /// コンボ段階 3 の速さ。
  stage3,

  /// FEVER TIME の最高速度。
  fever,
}

/// 練習場 (PRACTICE): ブロックのない盤面でボールを弾き続ける。ボールを落としても出直し、
/// ゲームオーバーにならない。記録・ランキング・履歴・広告の回数には数えない。
///
/// [speed] と [bullets] はプレイの途中で変えられる (`World.setPractice`)。
class PracticeMode extends GameMode {
  PracticeMode({this.speed = PracticeSpeed.stage1, this.bullets = false});

  PracticeSpeed speed;

  /// 敵弾の撃ち返しの練習 (ボールを出さず、上から一定の間隔で敵弾が落ちてくる)。
  bool bullets;

  /// 直近の判定の内訳とずれ。
  final PracticeLog log = PracticeLog();

  @override
  String get recordKey => 'practice';

  @override
  RoundSpec? roundAt(int number) => number == 1
      ? const RoundSpec(number: 1, difficulty: 1, content: LayoutContent([]))
      : null;
}

/// 練習場の直近 [capacity] 回の判定 (JUST / PERFECT / GOOD / MISS) と、接触とのずれ。
class PracticeLog {
  static const capacity = 20;

  final List<({ParryGrade? grade, double? offset})> _entries = [];

  /// 古い順。grade が null なら MISS。offset は秒 (負なら早い)。MISS で近くに何もなければ null。
  List<({ParryGrade? grade, double? offset})> get entries =>
      List.unmodifiable(_entries);

  void add(ParryGrade? grade, double? offset) {
    _entries.add((grade: grade, offset: offset));
    if (_entries.length > capacity) _entries.removeAt(0);
  }

  /// 判定のイベントなら記録する。
  void observe(GameEvent e) {
    switch (e) {
      case ParrySucceeded(:final grade, :final offset):
        add(grade, offset);
      case ParryMissed(:final offset):
        add(null, offset);
      default:
    }
  }

  void clear() => _entries.clear();

  int get length => _entries.length;

  /// [grade] の回数。null なら MISS の回数。
  int count(ParryGrade? grade) =>
      _entries.where((e) => e.grade == grade).length;

  Iterable<double> get _offsets => _entries.map((e) => e.offset).nonNulls;

  /// ずれの平均 (秒、負なら早い)。ずれのある判定がなければ null。
  double? get mean {
    final o = _offsets.toList();
    if (o.isEmpty) return null;
    return o.fold(0.0, (s, v) => s + v) / o.length;
  }

  /// ずれのばらつき (標準偏差、秒)。ずれのある判定がなければ null。
  double? get spread {
    final m = mean;
    if (m == null) return null;
    final o = _offsets.toList();
    final v = o.fold(0.0, (s, x) => s + (x - m) * (x - m)) / o.length;
    return math.sqrt(v);
  }
}
