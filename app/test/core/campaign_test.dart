import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:parry_break/core/blocks/explosive.dart';
import 'package:parry_break/core/blocks/turret.dart';
import 'package:parry_break/core/core.dart';

import 'helpers.dart';

void main() {
  final campaign = Campaign.fromJson(
      jsonDecode(File('assets/stages/campaign.json').readAsStringSync()) as Map<String, Object?>, endlessContent);

  test('すべてのステージを読み込め、ID が重複しない', () {
    final ids = campaign.stages.map((s) => s.id).toList();
    expect(ids.toSet().length, ids.length);
    expect(campaign.chapters.first.stages.first.title.of('ja'), 'はじめの一撃');
    for (final s in campaign.stages) {
      expect(s.stars, isNotEmpty, reason: s.id);
      final w = World(mode: StageMode(s))..start();
      expect(w.blocks, isNotEmpty, reason: s.id);
    }
  });

  test('6 章あり、どの章も 10 ステージで、最後はボス 1〜6 を順に使う', () {
    expect(campaign.chapters, hasLength(6));
    for (final (i, ch) in campaign.chapters.indexed) {
      expect(ch.stages, hasLength(10), reason: ch.id);
      expect([for (final s in ch.stages) s.id], [for (var k = 1; k <= 10; k++) '${i + 1}-$k'], reason: ch.id);
      expect(ch.stages.last.rounds.single.boss?.index, i, reason: ch.id);
      expect(ch.stages.where((s) => s.rounds.any((w) => w.boss != null)), hasLength(1), reason: ch.id);
    }
  });

  test('新しい攻撃ブロックは、説明付きのステージで初めて登場する', () {
    final seen = <String>{};
    for (final s in campaign.stages) {
      for (final w in s.rounds) {
        final c = w.content;
        if (c is! LayoutContent) continue;
        final ids = {for (var r = 0; r < c.rows.length; r++) for (var k = 0; k < 14; k++) if (c.rows[r][k] != '.') c.blockIdAt(r, k)};
        for (final (id, intro) in [('F', 'spread'), ('G', 'gatling'), ('O', 'ring'), ('Z', 'spiral'), ('P', 'sniper')]) {
          if (ids.contains(id) && seen.add(id)) expect(w.introKey, 'intro.$intro', reason: '${s.id} で $id が初登場');
        }
      }
    }
    expect(seen, {'F', 'G', 'O', 'Z', 'P'});
  });

  // 同じ配置を別の面で使い回すと、遊ぶ側には同じ面に見える (#165)。
  // 意図して使い回すときは、ここに '<面>:<ラウンド>' を足して理由を書く。
  test('別の面 (同じ面の別ラウンドも) で同じ配置を使っていない', () {
    const allowed = <String>{};
    final seen = <String, String>{};
    for (final s in campaign.stages) {
      for (final (i, w) in s.rounds.indexed) {
        final c = w.content;
        if (c is! LayoutContent) continue;
        final where = '${s.id}:${i + 1}';
        final key = [
          for (var r = 0; r < c.rows.length; r++) [for (var k = 0; k < c.rows[r].length; k++) c.rows[r][k] == '.' ? '.' : c.blockIdAt(r, k)].join(),
        ].join('/');
        final prev = seen[key];
        if (prev != null && !allowed.contains(where)) fail('$where は $prev と同じ配置');
        seen[key] ??= where;
      }
    }
  });

  // design.md 6章「章とステージの並べ方」の難しさの並べ方 (#164)。ボス (10 番目) は除く。
  // 面の難易度は、その面のラウンドのうち最も高いもの (連戦は通しで見る)。
  test('難易度は章の中でおおむね上がり、章ごとに上がっていく (新しい攻撃ブロックの初登場から始まる章は例外)', () {
    const newAttackIntros = {'intro.spread', 'intro.gatling', 'intro.ring', 'intro.spiral', 'intro.sniper'};
    int level(StageDef s) => s.rounds.map((w) => w.difficulty).reduce(math.max);
    for (final (i, ch) in campaign.chapters.indexed) {
      final stages = ch.stages.where((s) => s.rounds.every((w) => w.content is! BossContent)).toList();
      // 章の中: 直前の面より 2 を超えて下げない
      for (var k = 1; k < stages.length; k++) {
        expect(level(stages[k]), greaterThanOrEqualTo(level(stages[k - 1]) - 2),
            reason: '${stages[k].id} が ${stages[k - 1].id} より下がりすぎている');
      }
      if (i == 0) continue;
      final prev = campaign.chapters[i - 1].stages.where((s) => s.rounds.every((w) => w.content is! BossContent)).toList();
      final first = stages.first;
      final prevMax = prev.map(level).reduce(math.max);
      // 章の終わり (いちばん難しい面) は、前の章より上
      expect(stages.map(level).reduce(math.max), greaterThan(prevMax), reason: ch.id);
      // 章の最初の面は前の章の最大以上。新しい攻撃ブロックの初登場から始まる章だけは下げてよい
      if (!newAttackIntros.contains(first.rounds.first.introKey)) {
        expect(level(first), greaterThanOrEqualTo(prevMax), reason: first.id);
      }
    }
  });

  test('6-9 のラウンドは第6章の難易度帯 (50 以上) にある (#165)', () {
    expect([for (final w in campaign.stage('6-9')!.rounds) w.difficulty], everyElement(greaterThanOrEqualTo(50)));
  });

  test('崩落の星がある面には、崩落の支点 (要石・ボスのコア) がある', () {
    final registry = standardBlocks();
    for (final s in campaign.stages) {
      if (!s.stars.any((c) => c is StatStar && c.kind == StatKind.collapse)) continue;
      final hasAnchor = s.rounds.any((w) => switch (w.content) {
            BossContent() => true, // ボスのコアが支点になる
            final LayoutContent c => [
                for (var r = 0; r < c.rows.length; r++)
                  for (var k = 0; k < c.rows[r].length; k++)
                    if (c.rows[r][k] != '.') c.blockIdAt(r, k),
              ].any((id) => registry[id].anchor),
          });
      expect(hasAnchor, isTrue, reason: '${s.id} は崩落の星があるのに、支点がない');
    }
  });

  test('エンドレスの配置を借りた面は、ステージ側に intro がなければエンドレスの説明を引き継ぐ', () {
    String? intro(String id) => campaign.stage(id)!.rounds.first.introKey;
    // 借りたラウンドの説明 (新しいブロックの初登場)
    expect(intro('1-2'), 'intro.keystone');
    expect(intro('1-4'), 'intro.turret');
    expect(intro('1-5'), 'intro.explosive');
    expect(intro('1-6'), 'intro.reflector');
    expect(intro('1-9'), 'intro.magnet');
    expect(intro('2-4'), 'intro.splitter');
    expect(intro('2-6'), 'intro.mirror');
    // ステージ側に intro があれば、そちらが優先される
    expect(intro('1-1'), 'intro.parry');
    expect(intro('1-3'), 'intro.pierce');
    expect(intro('1-7'), 'intro.score');
    expect(intro('1-8'), 'intro.survive');
    expect(intro('2-1'), 'intro.feverTime');
    expect(intro('4-1'), 'intro.spread');
    // 借りたラウンドに説明がなければ何も付かない (帯にはクリア条件が出る)
    expect(intro('2-2'), isNull);
    expect(intro('3-3'), isNull);
    // どの {"endless": n} の面も、ステージ側の intro か、エンドレスの R{n} の intro になる
    final raw = jsonDecode(File('assets/stages/campaign.json').readAsStringSync()) as Map<String, Object?>;
    for (final c in (raw['chapters'] as List).cast<Map<String, Object?>>()) {
      for (final s in (c['stages'] as List).cast<Map<String, Object?>>()) {
        for (final (i, r) in (s['rounds'] as List).cast<Map<String, Object?>>().indexed) {
          if (r['endless'] case final num n) {
            expect(campaign.stage(s['id'] as String)!.rounds[i].introKey, r['intro'] ?? endlessContent.intros[n.toInt()],
                reason: '${s['id']} の ${i + 1} ラウンド目');
          }
        }
      }
    }
  });

  // 敵弾を出すのは砲台・爆薬の破片・ボス。崩落の瓦礫だけでは数が足りない。
  test('グレイズ・撃ち返しの星がある面には、敵弾を出すブロック (砲台・爆薬) かボスがある', () {
    final registry = standardBlocks();
    for (final s in campaign.stages) {
      if (!s.stars.any((c) => c is StatStar && (c.kind == StatKind.graze || c.kind == StatKind.returnKills))) continue;
      final hasGun = s.rounds.any((w) => switch (w.content) {
            BossContent() => true, // ボスが弾を撃つ
            final LayoutContent c => [
                for (var r = 0; r < c.rows.length; r++)
                  for (var k = 0; k < c.rows[r].length; k++)
                    if (c.rows[r][k] != '.') c.blockIdAt(r, k),
              ].any((id) => registry[id] is GunBlock || registry[id] is ExplosiveBlock),
          });
      expect(hasGun, isTrue, reason: '${s.id} は敵弾を使う星があるのに、敵弾を出すブロックがない');
    }
  });

  test('エンドレスのボスの番号を指定したステージでも、ボスではなく配置になる', () {
    final s = campaign.stage('2-4')!; // エンドレスの R20 (分裂の学習ラウンド)
    final w = World(mode: StageMode(s))..start();
    expect(w.boss, isNull);
    expect(w.blocks.any((b) => b.type == 'S'), isTrue);
  });

  test('生存ステージは時間が来たらクリアになり、モードが終わる', () {
    final s = campaign.stage('1-8')!; // 防衛線を死守せよ (40 秒耐える)
    final w = World(mode: StageMode(s))..start();
    final events = run(w, 50, before: autopilot(w));
    if (w.phase == WorldPhase.over) return; // 自動操作が先に落とした場合は判定しない
    expect(events.whereType<RoundCleared>(), hasLength(1));
    expect(events.whereType<StageCompleted>(), hasLength(1));
    expect(w.phase, WorldPhase.completed);
  });

  test('耐久のステージは発射しないまま制限時間を過ぎてもクリアにならない (#100)', () {
    final s = campaign.stage('5-5')!; // 狙撃戦 (50 秒耐える)
    final w = World(mode: StageMode(s))..start();
    final events = run(w, 60); // 入力なし = 発射しない
    expect(events.whereType<RoundCleared>(), isEmpty);
    expect(w.roundTime, 0);
    expect(w.phase, WorldPhase.over);
    expect(w.overReason, 'BLOCKS BREACHED');
  });

  test('星の判定', () {
    final s = campaign.stage('1-4')!; // clear / returnKills 3 / noHit
    final stats = RunStats()..returnKills = 3;
    expect(s.evaluate(StageResult(cleared: true, score: 0, stats: stats)), [true, true, true]);
    stats.hurt = 1;
    expect(s.evaluate(StageResult(cleared: true, score: 0, stats: stats)), [true, true, false]);
    expect(s.evaluate(StageResult(cleared: false, score: 0, stats: stats)), [false, false, false]);
  });

  group('JSON の読み込み', () {
    test('星の条件を種類ごとに読み分ける', () {
      expect(StarCondition.fromJson({'type': 'clear'}), isA<ClearStar>());
      expect(StarCondition.fromJson({'type': 'noHit'}), isA<NoHitStar>());
      expect(StarCondition.fromJson({'type': 'time', 'value': 45}), isA<TimeStar>().having((t) => t.seconds, 'seconds', 45));
      expect(
        StarCondition.fromJson({'type': 'score', 'value': 1000}),
        isA<StatStar>().having((t) => t.kind, 'kind', StatKind.score).having((t) => t.value, 'value', 1000),
      );
      expect(StarCondition.fromJson({'type': 'just', 'value': 3}), isA<StatStar>().having((t) => t.kind, 'kind', StatKind.just));
    });

    test('星の条件の形が合わなければ例外', () {
      expect(() => StarCondition.fromJson({'type': 'time'}), throwsFormatException);
      expect(() => StarCondition.fromJson({'value': 3}), throwsFormatException);
      expect(() => StarCondition.fromJson({'type': 'unknown', 'value': 3}), throwsArgumentError);
    });

    Campaign one(Map<String, Object?> round) => Campaign.fromJson({
          'chapters': [
            {
              'id': 'c',
              'title': 'C',
              'stages': [
                {'id': 's', 'title': 'S', 'rounds': [round]},
              ],
            },
          ],
        }, endlessContent);

    test('ラウンドの書き方ごとに中身と既定の難易度が決まる', () {
      final rows = one({'rows': ['..NN..', '..XX..'], 'legend': {'X': 'T'}}).stage('s')!.rounds.single;
      expect(rows.difficulty, 1);
      expect((rows.content as LayoutContent).blockIdAt(1, 2), 'T');

      final fromEndless = one({'endless': 4}).stage('s')!.rounds.single;
      expect(fromEndless.difficulty, 4);
      expect(fromEndless.content, isA<LayoutContent>());

      final boss = one({'boss': 0}).stage('s')!.rounds.single;
      expect(boss.difficulty, endlessContent.bossEvery);
      expect(boss.boss, same(endlessContent.bosses.first));

      expect(one({'boss': 0, 'difficulty': 3}).stage('s')!.rounds.single.difficulty, 3);
    });

    test('星を書かないステージはクリアだけ、中身のないラウンドは例外', () {
      expect(one({'endless': 1}).stage('s')!.stars.single, isA<ClearStar>());
      expect(() => one({'difficulty': 2}), throwsFormatException);
    });

    test('言語ごとの文字列', () {
      expect(LocalizedText.fromJson({'ja': 'あ', 'en': 'a'}).of('ja'), 'あ');
      expect(LocalizedText.fromJson({'ja': 'あ'}).of('en'), 'あ');
      expect(LocalizedText.fromJson('plain').of('ja'), 'plain');
      expect(LocalizedText.fromJson(null).of('en'), '');
    });
  });

  // Issue #147: 鍵のかかったステージに、どれをクリアすると開くかを出す
  test('開くためにクリアするステージ: 章の途中は 1 つ前、章の最初は前の章の最後', () {
    String? by(String id) => campaign.unlockedBy(campaign.stage(id)!)?.id;
    expect(by('1-1'), isNull);
    expect(by('1-2'), '1-1');
    expect(by('1-10'), '1-9');
    expect(by('2-1'), '1-10');
    expect(by('2-2'), '2-1');
    expect(by('6-1'), '5-10');
  });
}
