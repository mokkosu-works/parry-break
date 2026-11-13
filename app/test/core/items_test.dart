// Issue #252: ブロックから落ちてくるアイテム (design.md 7.10)。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:parry_break/core/core.dart';
import 'package:parry_break/game/autoplay_bot.dart';

import 'helpers.dart';

const _rows = [
  'NNNNNNNNNNNNNN',
  'NNNNNNNNNNNNNN',
  'NNNNNNNNNNNNNN',
  'NNNNNNNNNNNNNN',
];

/// アイテムの出る 1 ラウンド ([items] が false なら出ない) を、[rounds] 回繰り返すモード。
class _ItemMode extends GameMode {
  const _ItemMode({
    this.rows = _rows,
    this.items = true,
    this.tuning = const {},
    this.rounds = 1,
  });
  final List<String> rows;
  final bool items;
  final Map<String, Object?> tuning;
  final int rounds;

  @override
  String get recordKey => 'test';

  @override
  RoundSpec? roundAt(int number) => number <= rounds
      ? RoundSpec(
          number: number,
          difficulty: 1,
          content: LayoutContent(rows),
          tuning: tuning,
          items: items,
        )
      : null;
}

/// ボールを発射した直後の World (降下は止める)。
World _world({
  List<String> rows = _rows,
  bool items = true,
  Map<String, Object?> tuning = const {},
  int rounds = 1,
}) {
  final w = testWorld(
    _ItemMode(
      rows: rows,
      items: items,
      tuning: {'descentBase': 0, 'descentPerRound': 0, ...tuning},
      rounds: rounds,
    ),
  );
  run(w, 1.05);
  w.pressAction(w.t);
  run(w, 0.05);
  expect(w.ball.attached, isFalse);
  return w;
}

const _fall = 170.0, _hh = 10.0;

/// パドルの真上に [kind] を置き、取るまで進める。出たイベントを返す。
///
/// [pressOffset] を渡すと、接触の時刻からその秒数だけずらして押す (0 なら JUST、負なら接触の前)。
List<GameEvent> _take(World w, ItemKind kind, {double? pressOffset}) {
  const lead = 0.2;
  w.items.add(Item(kind, w.paddle.x, Field.paddleY - _hh - _fall * lead));
  if (pressOffset != null) w.pressAction(w.t + lead + pressOffset);
  final ev = run(w, lead + 0.1);
  expect(w.items, isEmpty, reason: 'アイテムを取り終えている');
  return ev;
}

void _breakBlocks(World w, int n) {
  for (var i = 0; i < n; i++) {
    w.destroyBlock(w.blocks.last, DestroyCause.ball);
  }
}

void main() {
  group('出るモード', () {
    test('エンドレスは R3 から出る。R1・R2 では出ない。説明の帯は R3 だけ', () {
      expect(endlessMode.roundAt(1).items, isFalse);
      expect(endlessMode.roundAt(2).items, isFalse);
      for (final n in [3, 4, 10, 60, 61, 62]) {
        expect(endlessMode.roundAt(n).items, isTrue, reason: 'R$n');
      }
      expect(
        [
          for (var n = 1; n <= 130; n++)
            if (endlessMode.roundAt(n).itemIntro) n,
        ],
        [3],
      );
    });

    test('ステージモードは 2-1 から出る。第 1 章では出ない。説明の帯は 2-1 だけ', () {
      final campaign = Campaign.fromJson(
        jsonDecode(File('assets/stages/campaign.json').readAsStringSync())
            as Map<String, Object?>,
        endlessContent,
      );
      for (final s in campaign.stages) {
        for (final r in s.rounds) {
          expect(r.items, s.chapterId != 'ch01', reason: s.id);
        }
      }
      expect(
        [
          for (final s in campaign.stages)
            for (final r in s.rounds)
              if (r.itemIntro) '${s.id}:${r.number}',
        ],
        ['2-1:1'],
      );
    });

    test('"items": false は章・ステージ・ラウンドで書け、内側が優先される', () {
      Map<String, Object?> stage(String id, [Map<String, Object?>? extra]) => {
        'id': id,
        'title': {'ja': id, 'en': id},
        'rounds': [
          {'endless': 1},
          {'endless': 2, 'items': ?extra?['round2']},
        ],
        'items': ?extra?['stage'],
      };
      final c = Campaign.fromJson({
        'chapters': [
          {
            'id': 'a',
            'title': {'ja': 'a', 'en': 'a'},
            'items': false,
            'stages': [
              stage('a1'),
              stage('a2', {'stage': true, 'round2': false}),
            ],
          },
          {
            'id': 'b',
            'title': {'ja': 'b', 'en': 'b'},
            'stages': [
              stage('b1', {'stage': false, 'round2': true}),
              stage('b2'),
            ],
          },
        ],
      }, endlessContent);
      List<bool> items(String id) => [
        for (final r in c.stage(id)!.rounds) r.items,
      ];
      expect(items('a1'), [false, false]);
      expect(items('a2'), [true, false]);
      expect(items('b1'), [false, true]);
      expect(items('b2'), [true, true]);
      // 説明は、アイテムが出る最初のステージの 1 ラウンド目
      expect(c.stage('a2')!.rounds.first.itemIntro, isTrue);
      expect(c.stage('b2')!.rounds.first.itemIntro, isFalse);
    });

    test('"items": false の面では、確率を 1 にしても出ない', () {
      final w = _world(items: false, tuning: {'itemChance': 1});
      _breakBlocks(w, 30);
      expect(w.items, isEmpty);
      expect(w.itemsSpawned, 0);
    });

    test('エンドレスの itemsFromRound を 0 にすると出ない', () {
      final j = jsonDecode(
        File('assets/stages/endless.json').readAsStringSync(),
      ) as Map<String, Object?>;
      expect(j['itemsFromRound'], 3);
      final off = EndlessContent.fromJson({...j, 'itemsFromRound': 0});
      expect(off.round(3).items, isFalse);
      expect(off.round(30).itemIntro, isFalse);
    });
  });

  group('落ち方', () {
    test('既定の数値は Issue のとおり', () {
      const t = Tuning();
      expect(t.itemChance, 0.07);
      expect(t.itemGap, 6);
      expect(t.itemMaxOnField, 2);
      expect(t.itemMaxPerRound, 4);
      expect(t.itemFallSpeed, 170);
      expect((t.itemWidth, t.itemHeight), (44, 20));
      expect(t.itemWeights, [3, 3, 2, 2, 1, 1]);
      expect(t.itemWeights.length, ItemKind.values.length);
    });

    test('6 個壊すまでは出ない。7 個目で出て、その場からまっすぐ下に落ちる', () {
      final w = _world(tuning: {'itemChance': 1});
      _breakBlocks(w, 6);
      expect(w.items, isEmpty);
      final b = w.blocks.last;
      final c = w.blockCenter(b);
      w.destroyBlock(b, DestroyCause.ball);
      expect(w.items, hasLength(1));
      final it = w.items.single;
      expect((it.x, it.y), (c.x, c.y));
      expect(w.drainEvents().whereType<ItemSpawned>().single.item, same(it));
      run(w, 1);
      expect(it.x, c.x);
      expect(it.y, closeTo(c.y + 170, 1e-6));
    });

    test('同時に 2 個まで、1 ラウンドに 4 個まで', () {
      final w = _world(
        rows: [for (var i = 0; i < 8; i++) 'NNNNNNNNNNNNNN'],
        tuning: {'itemChance': 1},
      );
      _breakBlocks(w, 7);
      expect(w.items, hasLength(1));
      _breakBlocks(w, 6);
      expect(w.items, hasLength(1), reason: '前のアイテムから 6 個');
      _breakBlocks(w, 1);
      expect(w.items, hasLength(2));
      _breakBlocks(w, 20);
      expect(w.items, hasLength(2), reason: '盤面に 2 個あるうちは出ない');
      w.items.clear();
      _breakBlocks(w, 1);
      expect(w.items, hasLength(1));
      w.items.clear();
      _breakBlocks(w, 7);
      expect(w.items, hasLength(1));
      expect(w.itemsSpawned, 4);
      w.items.clear();
      _breakBlocks(w, 30);
      expect(w.items, isEmpty, reason: '1 ラウンドに 4 個まで');
      expect(w.itemsSpawned, 4);
    });

    test('画面の下に出たら消える (ミスにはならない)', () {
      final w = _world();
      w.items.add(Item(ItemKind.wide, 40, Field.height - 5));
      run(w, 0.2);
      expect(w.items, isEmpty);
      expect(w.phase, WorldPhase.playing);
      expect(w.effects.active, isEmpty);
    });

    test('撃ち返し弾・爆風・SHOT の弾で壊しても出る', () {
      for (final cause in [
        DestroyCause.bullet,
        DestroyCause.blast,
        DestroyCause.shot,
        DestroyCause.pierce,
      ]) {
        final w = _world(tuning: {'itemChance': 1, 'itemGap': 0});
        w.destroyBlock(w.blocks.last, cause);
        expect(w.items, hasLength(1), reason: '$cause');
      }
    });

    test('崩落で落ちたブロックからも出る', () {
      final w = _world(
        rows: ['......K......K', '......N.......', '......N.......'],
        tuning: {'itemChance': 1, 'itemGap': 1},
      );
      w.destroyBlock(
        w.blocks.firstWhere((b) => b.type == 'K'),
        DestroyCause.ball,
      );
      expect(w.items, isEmpty, reason: '要石が 1 個目');
      final ev = run(w, 0.5);
      expect(ev.whereType<BlockFell>(), hasLength(2));
      expect(ev.whereType<ItemSpawned>(), hasLength(1));
    });

    test('分裂の子・ボスの増援・作り直した装甲からは出ない (数にも入れない)', () {
      final w = _world(
        rows: ['......S.......'],
        tuning: {'itemChance': 1, 'itemGap': 0},
      );
      w.destroyBlock(w.blocks.single, DestroyCause.ball);
      expect(w.items, hasLength(1), reason: '分裂ブロックそのものからは出る');
      w.items.clear();
      expect(w.blocks.map((b) => b.type).toSet(), {'s'});
      for (final b in List.of(w.blocks)) {
        w.destroyBlock(b, DestroyCause.ball);
      }
      expect(w.items, isEmpty);
      final extra = w.addBlock('N', 100, 100)..noItem = true;
      w.destroyBlock(extra, DestroyCause.ball);
      expect(w.items, isEmpty);
      expect(w.breaksSinceItem, 0);
    });

    test('ボス戦: フェーズ移行の増援と作り直した装甲には noItem が付く。コアからは出ない', () {
      final w = World(mode: endlessMode)..start(fromRound: 50);
      w.sync.identity();
      expect(w.round.items, isTrue);
      expect(w.blocks.any((b) => b.noItem), isFalse);
      final before = w.blocks.toSet();
      // 再生要塞 (ボス 5) は装甲を作り直す
      run(w, 1.05);
      w.pressAction(w.t);
      for (final b in w.blocks.where((b) => b.type == 'N').take(6).toList()) {
        w.destroyBlock(b, DestroyCause.ball);
      }
      w.drainEvents();
      final ev = run(
        w,
        20,
        before: () {
          w.input
            ..useTarget = true
            ..targetX = w.ball.x;
        },
      );
      final repaired = ev.whereType<BlockRepaired>().toList();
      expect(repaired, isNotEmpty);
      expect(repaired.every((e) => e.block.noItem), isTrue);
      // コアを削ってフェーズを進めると、増援 (鏡面・砲台) が出る
      final core = w.blocks.firstWhere((b) => b.type == bossCoreId);
      final spawnedBefore = w.itemsSpawned;
      while (w.boss!.phase < 2) {
        w.damageCore(core, 1);
      }
      final added = w.blocks.where(
        (b) => !before.contains(b) && (b.type == 'X' || b.type == 'T'),
      );
      expect(added, isNotEmpty);
      expect(added.every((b) => b.noItem), isTrue);
      expect(w.itemsSpawned, spawnedBefore, reason: 'コアへのダメージでは出ない');
    });
  });

  group('決定性', () {
    List<String> spawns(int seed) {
      final w = World(mode: endlessMode, inputLag: 0)..start(fromRound: 3);
      w.sync.identity();
      final bot = Bot(w, seed: seed);
      final out = <String>[];
      for (var i = 0; i < 60 * 60; i++) {
        bot();
        w.step(World.dt);
        for (final e in w.drainEvents()) {
          if (e is ItemSpawned) {
            out.add(
              '${w.round.number} ${w.t} ${e.item.kind} ${e.item.x} ${e.item.y}',
            );
          }
        }
        if (w.phase == WorldPhase.over) break;
      }
      return out;
    }

    test('同じ種・同じ入力なら、アイテムの出る場所・種類・時刻が毎回同じ', () {
      final a = spawns(5), b = spawns(5);
      expect(a, isNotEmpty);
      expect(a, b);
    });

    test('アイテムの抽選は、ほかの乱数 (反射・瓦礫・打ち返し) を引く回数を変えない', () {
      // 落ちないアイテム (速さ 0) を確率 1 で出しても、アイテムなしと同じ展開になる
      String play({required bool items}) {
        final w = World(
          mode: _ItemMode(
            rows: const [
              'NNNRRNNKNNRRNN',
              'NBNNNNNNNNNNBN',
              'NNNNTNNNNTNNNN',
              'NNNNNNNNNNNNNN',
            ],
            items: items,
            tuning: const {'itemChance': 1, 'itemFallSpeed': 0, 'itemGap': 0},
          ),
          difficulty: Difficulty.hard,
          inputLag: 0,
        )..start();
        w.sync.identity();
        final bot = Bot(w, seed: 3);
        var spawned = 0;
        for (var i = 0; i < 60 * 40; i++) {
          bot();
          w.step(World.dt);
          spawned += w.drainEvents().whereType<ItemSpawned>().length;
          if (w.phase != WorldPhase.playing) break;
        }
        expect(spawned, items ? greaterThan(0) : 0);
        return '${w.t} ${w.score} ${w.combo} ${w.ball.x} ${w.ball.y} '
            '${w.stats.hurt} ${w.blocks.length} ${w.rng.next()} ${w.aux.next()}';
      }

      expect(play(items: true), play(items: false));
    });

    test('アイテムの乱数のシードは、ラウンドのほかの乱数と別', () {
      final s = endlessMode.roundAt(3);
      expect(s.itemSeed, isNot(s.seed));
      expect(s.itemSeed, isNot(s.seed * 7 + 1));
    });
  });

  group('取り方', () {
    test('パドルに触れると取れる (通常取得)。コンボ・得点・連続は変わらない', () {
      final w = _world();
      final score = w.score, combo = w.combo;
      final ev = _take(w, ItemKind.wide);
      final taken = ev.whereType<ItemTaken>().single;
      expect(taken.kind, ItemKind.wide);
      expect(taken.parried, isFalse);
      expect(taken.points, 0);
      expect(w.score, score);
      expect(w.combo, combo);
      expect(w.streak, 0);
    });

    test('パドルから外れていれば取れない', () {
      final w = _world();
      w.items.add(Item(ItemKind.wide, w.paddle.x + 60 + 22 + 2, 600));
      final ev = run(w, 1);
      expect(ev.whereType<ItemTaken>(), isEmpty);
      expect(w.items, isEmpty);
      // 端が少しでも重なれば取れる
      w.items.add(Item(ItemKind.wide, w.paddle.x + 60 + 22 - 2, 600));
      expect(run(w, 1).whereType<ItemTaken>(), hasLength(1));
    });

    test('パリィの窓の中で触れるとパリィ取得: コンボ +30、得点 500 × 倍率、連続 +1', () {
      final w = _world();
      w.combo = 120; // 段階 2 (×2)
      expect(w.mult, 2);
      final score = w.score, combo = w.combo;
      final ev = _take(w, ItemKind.wide, pressOffset: -0.05);
      final taken = ev.whereType<ItemTaken>().single;
      expect(taken.grade, ParryGrade.good);
      expect(taken.points, 1000);
      expect(w.score, score + 1000);
      // コンボは段階 2 の減衰 (8/秒) があるので、増えた分だけを見る
      expect(w.combo, closeTo(combo + 30 - 8 * 0.3, 0.2));
      expect(w.streak, 1);
      expect(ev.whereType<ParryMissed>(), isEmpty);
      expect(w.t >= w.parry.cooldownUntil, isTrue);
    });

    test('JUST のパリィ取得はコンボ +50。接触の後 0.03 秒以内の押下もパリィ取得になる', () {
      var w = _world();
      var ev = _take(w, ItemKind.cool, pressOffset: 0);
      expect(ev.whereType<ItemTaken>().single.grade, ParryGrade.just);
      expect(w.combo, 50);
      w = _world();
      ev = _take(w, ItemKind.cool, pressOffset: 0.025);
      expect(ev.whereType<ItemTaken>().single.grade, ParryGrade.perfect);
      expect(w.combo, 30);
      w = _world();
      ev = _take(w, ItemKind.cool, pressOffset: 0.045);
      expect(ev.whereType<ItemTaken>().single.parried, isFalse, reason: '遅すぎ');
    });

    test('パリィ取得はパリィの成功数・PERFECT・JUST (星の条件) には数えない', () {
      final w = _world();
      _take(w, ItemKind.wide, pressOffset: 0);
      expect(w.streak, 1);
      expect((w.stats.parries, w.stats.perfects, w.stats.just), (0, 0, 0));
    });

    test('早すぎる押下は今までどおり空振り (クールダウン・連続 0)。アイテムは通常取得になる', () {
      final w = _world();
      w.streak = 3;
      final ev = _take(w, ItemKind.wide, pressOffset: -0.15);
      expect(ev.whereType<ParryMissed>(), hasLength(1));
      expect(w.streak, 0);
      expect(
        w.parry.cooldownUntil,
        closeTo(w.parry.press + w.tuning.parryCooldown, 1e-9),
      );
      expect(ev.whereType<ItemTaken>().single.parried, isFalse);
    });

    test('スタン中は取れずに素通りする。無敵中は取れる', () {
      var w = _world();
      w.paddle
        ..stun = 0.6
        ..invuln = 1.2;
      w.items.add(Item(ItemKind.wide, w.paddle.x, Field.paddleY - 30));
      var ev = run(w, 0.7);
      expect(ev.whereType<ItemTaken>(), isEmpty);
      expect(w.items, isEmpty, reason: '下へ抜けた');
      expect(w.effects.wide, 0);

      w = _world();
      w.paddle.invuln = 1.2;
      ev = _take(w, ItemKind.wide);
      expect(ev.whereType<ItemTaken>(), hasLength(1));
    });
  });

  group('種類ごとの効果', () {
    test('WIDE: パドルの幅 120 → 168 を 12 秒 (パリィ取得は 20 秒)', () {
      var w = _world();
      expect(w.paddleWidth, 120);
      _take(w, ItemKind.wide);
      expect(w.paddleWidth, closeTo(168, 1e-9));
      expect(w.effects.wide, closeTo(12, 0.1));
      w = _world();
      _take(w, ItemKind.wide, pressOffset: 0);
      expect(w.effects.wide, closeTo(20, 0.15));
    });

    test('WIDE: 時間が過ぎると元の幅に戻る。広い間は端まで届かない', () {
      final w = _world(tuning: {'wideTime': 0.5});
      _take(w, ItemKind.wide);
      w.input
        ..useTarget = true
        ..targetX = 0;
      run(w, 0.1);
      expect(w.paddle.x, closeTo(84, 1e-9));
      run(w, 0.5);
      expect(w.paddleWidth, 120);
      expect(w.paddle.x, 60);
    });

    test('MULTI: 分身弾を 2 個 (パリィ取得は 3 個)、寿命 8 秒', () {
      var w = _world();
      var ev = _take(w, ItemKind.multi);
      expect(ev.whereType<PhantomsSpawned>().single.count, 2);
      expect(w.phantoms, hasLength(2));
      expect(w.phantoms.every((f) => f.phantom && f.vy < 0), isTrue);
      expect(w.phantoms.first.life, closeTo(8, 0.15));
      expect(w.od, isFalse);
      w = _world();
      ev = _take(w, ItemKind.multi, pressOffset: 0);
      expect(w.phantoms, hasLength(3));
    });

    test('MULTI: 分身弾は 8 秒で消える。同時に 6 個まで', () {
      final w = _world(tuning: {'multiLife': 0.5});
      _take(w, ItemKind.multi);
      run(w, 0.6);
      expect(w.phantoms, isEmpty);
      final w2 = _world();
      for (var i = 0; i < 3; i++) {
        _take(w2, ItemKind.multi, pressOffset: 0);
      }
      expect(w2.phantoms.length, lessThanOrEqualTo(6));
    });

    test('SHOT: 10 秒 (パリィ取得は 16 秒) の間、パリィ成功のたびに上へ 2 発撃つ', () {
      var w = _world();
      _take(w, ItemKind.shot, pressOffset: 0);
      expect(w.effects.shot, closeTo(16, 0.15));
      w = _world(rows: ['NNNNNNNNNNNNNN']);
      _take(w, ItemKind.shot);
      expect(w.effects.shot, closeTo(10, 0.1));
      expect(w.bullets, isEmpty, reason: '取っただけでは撃たない');
      // 敵弾をパリィする
      w.fireBullet(w.paddle.x, Field.paddleY - 6 - 30, 3.14159265 / 2, 300);
      w.pressAction(w.t + 0.1);
      final blocks = w.blocks.length;
      final ev = run(w, 0.2);
      expect(ev.whereType<ParrySucceeded>(), hasLength(1));
      expect(ev.whereType<ShotFired>(), hasLength(1));
      final shots = w.bullets.where((u) => u.kind == BulletKind.shot).toList();
      expect(shots, hasLength(2));
      expect(shots.every((u) => !u.hostile && u.vy < 0 && u.vx == 0), isTrue);
      expect(shots.map((u) => u.x - w.paddle.x), unorderedEquals([-28, 28]));
      // 上まで飛んで、通常ブロックを 1 個ずつ壊して消える。基本点はそのまま (撃ち返し弾の 2 倍にならない)
      final returnKills = w.stats.returnKills;
      final ev2 = run(w, 1);
      final byShot = ev2
          .whereType<BlockDestroyed>()
          .where((e) => e.cause == DestroyCause.shot)
          .toList();
      expect(byShot, hasLength(2));
      expect(byShot.every((e) => e.points == 100 * w.mult), isTrue);
      expect(w.bullets.where((u) => u.kind == BulletKind.shot), isEmpty);
      // 撃ち返し弾で壊した数には入らない (星の条件)
      expect(
        w.stats.returnKills - returnKills,
        ev2
            .whereType<BlockDestroyed>()
            .where((e) => e.cause == DestroyCause.bullet)
            .length,
      );
      expect(w.blocks.length, lessThanOrEqualTo(blocks - 2));
    });

    test('SHOT: 効果が切れたら撃たない。耐久のあるブロックは 1 ダメージ、壊せないものには弾かれる', () {
      final w = _world(
        rows: ['...K#.......NN'],
        tuning: {'shotTime': 0.4, 'shotSpread': 30},
      );
      _take(w, ItemKind.shot);
      // 要石 (耐久 3) と破壊不可の真下から撃つ
      w.input
        ..useTarget = true
        ..targetX = Field.gridX0 + 4 * Field.cellW;
      run(w, 0.02);
      w.fireBullet(w.paddle.x, Field.paddleY - 6 - 9, 3.14159265 / 2, 300);
      w.pressAction(w.t + 0.03);
      var ev = run(w, 0.05);
      expect(ev.whereType<ShotFired>(), hasLength(1));
      ev = run(w, 1);
      // 要石 (耐久 3) は SHOT では 1 ダメージだけ。破壊不可には弾かれる
      expect(
        ev.whereType<BlockDamaged>().where((e) => e.block.type == 'K'),
        hasLength(1),
      );
      expect(
        ev.whereType<BlockDeflected>().where((e) => e.block.type == '#'),
        hasLength(1),
      );
      expect(
        ev.whereType<BlockDestroyed>().where(
          (e) => e.cause == DestroyCause.shot,
        ),
        isEmpty,
      );
      expect(w.blocks.any((b) => b.type == '#'), isTrue);
      expect(w.effects.shot, lessThanOrEqualTo(0));
      w.fireBullet(w.paddle.x, Field.paddleY - 6 - 9, 3.14159265 / 2, 300);
      w.pressAction(w.t + 0.03);
      ev = run(w, 0.05);
      expect(ev.whereType<ParrySucceeded>(), hasLength(1));
      expect(ev.whereType<ShotFired>(), isEmpty);
    });

    test('BLAST: 次にボールがブロックに当たったときブレイカーが 1 回 (パリィ取得は 2 回)。上限 3', () {
      var w = _world();
      _take(w, ItemKind.blast);
      expect(w.effects.blast, 1);
      _take(w, ItemKind.blast, pressOffset: 0);
      expect(w.effects.blast, 3);
      _take(w, ItemKind.blast, pressOffset: 0);
      expect(w.effects.blast, 3, reason: '上限');

      w = _world();
      _take(w, ItemKind.blast);
      final blocks = w.blocks.length;
      // ボールを最下段のすぐ下に置いて、上へ飛ばす
      w.ball
        ..x = 600
        ..y = Field.gridY0 + 4 * Field.cellH + 30
        ..vx = 0
        ..vy = -w.ball.speed
        ..pierce = 0
        ..breaker = false;
      final ev = run(w, 0.3);
      expect(ev.whereType<BreakerTriggered>(), hasLength(1));
      expect(ev.whereType<BlastExploded>().single.kind, BlastKind.breaker);
      expect(w.effects.blast, 0);
      expect(blocks - w.blocks.length, greaterThan(3));
    });

    test('BLAST: 2 回分は、間隔 (0.3 秒) を空けて 1 回ずつ出る', () {
      final w = _world(rows: [for (var i = 0; i < 8; i++) 'NNNNNNNNNNNNNN']);
      _take(w, ItemKind.blast, pressOffset: 0);
      expect(w.effects.blast, 2);
      w.ball
        ..x = 600
        ..y = Field.gridY0 + 8 * Field.cellH + 12
        ..vx = 0
        ..vy = -w.ball.speed
        ..pierce = 9
        ..breaker = false;
      var ev = run(w, 0.1);
      expect(ev.whereType<BreakerTriggered>(), hasLength(1));
      expect(w.effects.blast, 1);
      ev = run(w, 3, before: () => w.input.targetX = w.ball.x);
      expect(ev.whereType<BreakerTriggered>(), hasLength(1));
      expect(w.effects.blast, 0);
    });

    test('GUARD: 防壁はボールを 1 回だけ跳ね返して消える。12 秒 (パリィ取得は 20 秒) で消える', () {
      var w = _world();
      _take(w, ItemKind.guard, pressOffset: 0);
      expect(w.effects.guard, closeTo(20, 0.15));
      w = _world();
      _take(w, ItemKind.guard);
      expect(w.effects.guard, closeTo(12, 0.1));
      void dropBall() {
        w.input
          ..useTarget = true
          ..targetX = 100;
        run(w, 0.02);
        w.ball
          ..x = 900
          ..y = Field.paddleY + 10
          ..vx = 0
          ..vy = w.ball.speed;
      }

      dropBall();
      var ev = run(w, 0.2);
      expect(ev.whereType<GuardBounced>(), hasLength(1));
      expect(w.ball.vy, lessThan(0));
      expect(w.effects.guard, 0, reason: '1 回で消える');
      expect(w.phase, WorldPhase.playing);
      dropBall();
      ev = run(w, 0.3);
      expect(ev.whereType<GuardBounced>(), isEmpty);
      expect(w.phase, WorldPhase.over);

      // 時間切れ
      w = _world(tuning: {'guardTime': 0.3});
      _take(w, ItemKind.guard);
      run(w, 0.3);
      expect(w.effects.guard, lessThanOrEqualTo(0));
      dropBall();
      run(w, 0.3);
      expect(w.phase, WorldPhase.over);
    });

    test('GUARD: 分身弾と敵弾は素通りする', () {
      final w = _world();
      _take(w, ItemKind.guard);
      _take(w, ItemKind.multi);
      w.input
        ..useTarget = true
        ..targetX = 100;
      run(w, 0.02);
      for (final f in w.phantoms) {
        f
          ..x = 900
          ..y = Field.paddleY + 10
          ..vx = 0
          ..vy = f.speed;
      }
      w.fireBullet(900, Field.paddleY + 10, 3.14159265 / 2, 300);
      final ev = run(w, 0.5);
      expect(ev.whereType<GuardBounced>(), isEmpty);
      expect(w.phantoms, isEmpty);
      expect(w.bullets.where((u) => u.hostile), isEmpty);
      expect(w.effects.guard, greaterThan(0));
    });

    test('COOL: ボールの速さを 8 秒 (パリィ取得は 14 秒) の間 ×0.8。コンボと倍率はそのまま', () {
      var w = _world();
      _take(w, ItemKind.cool, pressOffset: -0.05);
      expect(w.effects.cool, closeTo(14, 0.15));
      w = _world();
      w.combo = 300; // 段階 3 (×4)
      final base = w.targetSpeed;
      _take(w, ItemKind.cool);
      expect(w.effects.cool, closeTo(8, 0.1));
      expect(w.stage, 2);
      expect(w.mult, 4);
      expect(w.targetSpeed, closeTo(base * 0.8, 1e-9));
      run(w, 0.6, before: () => w.combo = 300);
      expect(w.ball.speed, closeTo(base * 0.8, base * 0.08));
      expect(w.ball.speed, lessThan(base * 0.9));
    });

    test('COOL: FEVER TIME 中の速さにもかかる。切れたら元に戻る', () {
      final w = _world(tuning: {'coolTime': 0.5});
      w.addCombo(700);
      expect(w.od, isTrue);
      final base = w.targetSpeed;
      _take(w, ItemKind.cool);
      expect(w.od, isTrue);
      expect(w.targetSpeed, lessThan(base));
      expect(
        w.targetSpeed / w.tuning.coolSpeedMul,
        greaterThanOrEqualTo(w.stageSpeedOf(3)),
      );
      run(w, 0.5);
      expect(w.effects.cool, lessThanOrEqualTo(0));
      expect(w.targetSpeed, greaterThanOrEqualTo(base));
    });

    test('同じ種類を重ねて取ると、残り時間を新しいほうで上書きする', () {
      final w = _world();
      _take(w, ItemKind.wide, pressOffset: 0);
      expect(w.effects.wide, closeTo(20, 0.15));
      _take(w, ItemKind.wide);
      expect(w.effects.wide, closeTo(12, 0.15));
    });

    test('FEVER TIME 中も出るし取れる', () {
      final w = _world(tuning: {'itemChance': 1, 'itemGap': 0});
      w.addCombo(700);
      expect(w.od, isTrue);
      w.destroyBlock(w.blocks.last, DestroyCause.pierce);
      expect(w.items, hasLength(1));
      w.items.clear();
      _take(w, ItemKind.wide, pressOffset: 0);
      expect(w.effects.wide, greaterThan(0));
    });

    test('HUD 用の一覧: 効いている効果と残り', () {
      final w = _world();
      expect(w.effects.active, isEmpty);
      _take(w, ItemKind.cool);
      _take(w, ItemKind.blast, pressOffset: 0);
      final a = w.effects.active;
      expect(a.map((e) => e.$1), [ItemKind.blast, ItemKind.cool]);
      expect(a.first.$2, 2);
    });
  });

  group('消えるとき', () {
    World loaded() {
      final w = _world(rounds: 2, tuning: {'itemChance': 0});
      for (final k in [
        ItemKind.wide,
        ItemKind.shot,
        ItemKind.blast,
        ItemKind.guard,
        ItemKind.cool,
      ]) {
        _take(w, k);
      }
      w.items.add(Item(ItemKind.multi, 300, 300));
      w.effects.blast = 2; // 途中でボールがブロックに当たって使っていても、残っている状態にする
      expect(w.effects.active, hasLength(5));
      return w;
    }

    void expectCleared(World w) {
      expect(w.items, isEmpty);
      expect(w.effects.active, isEmpty);
      expect(w.paddleWidth, 120);
    }

    test('ミス (ボールを落とす) で、効果と落下中のアイテムが消える', () {
      final w = loaded();
      w.effects.guard = 0; // 防壁があると 1 回は助かる
      w.ball
        ..x = 1100
        ..y = Field.paddleY + 20
        ..vx = 0
        ..vy = 400;
      w.input
        ..useTarget = true
        ..targetX = 100;
      run(w, 0.5);
      expect(w.phase, WorldPhase.over);
      expectCleared(w);
    });

    test('ラウンドクリアで消え、次のラウンドにも持ち越さない', () {
      final w = loaded();
      for (final b in List.of(w.blocks)) {
        w.destroyBlock(b, DestroyCause.ball);
      }
      run(w, 0.05);
      expect(w.phase, WorldPhase.clearing);
      expectCleared(w);
      run(w, 3);
      expect(w.round.number, 2);
      expect(w.phase, WorldPhase.playing);
      expectCleared(w);
      expect(w.itemsSpawned, 0);
      expect(w.breaksSinceItem, 0);
    });

    test('RETRY (start の呼び直し) で消える', () {
      final w = loaded();
      w.start();
      expectCleared(w);
      expect(w.itemsSpawned, 0);
    });
  });

  group('数値の上書き', () {
    test('ステージの tuning でアイテムの数値を上書きできる', () {
      final t = const Tuning().copyWith({
        'itemChance': 0.2,
        'itemGap': 3,
        'itemMaxOnField': 1,
        'itemMaxPerRound': 9,
        'itemWeights': [1, 0, 0, 0, 0, 0],
        'wideScale': 1.2,
        'multiCount': 1,
        'blastMax': 5,
        'coolSpeedMul': 0.9,
      });
      expect(t.itemChance, 0.2);
      expect((t.itemGap, t.itemMaxOnField, t.itemMaxPerRound), (3, 1, 9));
      expect(t.itemWeights, [1, 0, 0, 0, 0, 0]);
      expect((t.wideScale, t.multiCount, t.blastMax), (1.2, 1, 5));
      expect(t.coolSpeedMul, 0.9);
      expect(t.guardTime, 12, reason: '書かなければ既定値');
    });

    test('出やすさ: 重みを 1 種類だけにすると、その種類しか出ない。既定では高 > 低', () {
      final w = _world(
        rows: [for (var i = 0; i < 8; i++) 'NNNNNNNNNNNNNN'],
        tuning: {
          'itemChance': 1,
          'itemGap': 0,
          'itemMaxOnField': 99,
          'itemMaxPerRound': 99,
          'itemWeights': [0, 0, 0, 0, 1, 0],
        },
      );
      _breakBlocks(w, 40);
      expect(w.items.map((i) => i.kind).toSet(), {ItemKind.guard});

      final count = {for (final k in ItemKind.values) k: 0};
      for (var n = 3; n < 200; n++) {
        final w = testWorld(
          _ItemMode(
            rows: [for (var i = 0; i < 8; i++) 'NNNNNNNNNNNNNN'],
            tuning: const {
              'itemChance': 1,
              'itemGap': 0,
              'itemMaxOnField': 99,
              'itemMaxPerRound': 99,
            },
          ),
        );
        // ラウンドごとに乱数が変わるよう、シードを差し替える
        w.itemRng = Mulberry32(n * 977);
        _breakBlocks(w, 12);
        for (final it in w.items) {
          count[it.kind] = count[it.kind]! + 1;
        }
      }
      expect(count.values.every((v) => v > 0), isTrue);
      final hi = count[ItemKind.wide]! + count[ItemKind.multi]!;
      final mid = count[ItemKind.shot]! + count[ItemKind.blast]!;
      final lo = count[ItemKind.guard]! + count[ItemKind.cool]!;
      expect(hi, greaterThan(mid));
      expect(mid, greaterThan(lo));
    });
  });
}
