import 'dart:math' as math;

import '../sim/rng.dart';

const _clearable = {'N', 'T', 'R', 'M', 'S', 's', 'K', 'B'};
const _cols = 14, _half = 7;

/// ウェーブ番号を種にした、決定的な配置の自動生成 (ブラウザ版 `genLayout` の移植)。
///
/// 同じウェーブ番号からは常に同じ配置ができる (覚えて攻略できる)。
/// 乱数を引く順番もブラウザ版と同じにしてあり、テストで一致を確認している。
/// [unlock] はブロックの種類 → 解禁ウェーブ。出現率は種類ごとにこの関数の中で決めている
/// (新しいブロックを自動生成に入れるときは、ここに出現率を足す)。
List<String> generateLayout(int b, {required Map<String, int> unlock}) {
  final rng = Mulberry32(b * 7919 + 3);
  final types = [for (final e in unlock.entries) if (b >= e.value) e.key];
  final cellTypes = types.where((t) => t != 'K').toList();
  final newest = cellTypes.last;
  final combo = b % 2 == 0; // 偶数: 組み合わせ / 奇数: 最新ギミックの学習寄り
  final rows = math.min(8, 4 + b ~/ 7);
  const shapes = ['full', 'checker', 'diamond', 'pillars', 'vee', 'holes', 'ladder'];
  final shape = shapes[(rng.next() * shapes.length).floor()];

  bool mask(int r, int c) => switch (shape) {
        'checker' => (r + c) % 2 == 0 || r == 0,
        'diamond' => (6 - c) + (r - (rows - 1) / 2).abs() * 1.6 <= 6.8,
        'pillars' => c % 3 != 2 || r == 0,
        'vee' => c >= r * 0.8 - 0.5,
        'holes' => rng.next() < 0.74,
        'ladder' => r % 3 != 1 || c % 2 == 0,
        _ => true,
      };

  final grid = List.generate(rows, (_) => List.filled(_cols, '.'));
  final caps = {'T': math.min(3, 1 + b ~/ 15), 'M': 2, 'X': 3, 'B': 2 + b ~/ 15, '#': 2};
  final cnt = {'T': 0, 'M': 0, 'X': 0, 'B': 0, '#': 0};
  for (var r = 0; r < rows; r++) {
    for (var c = 0; c < _half; c++) {
      if (!mask(r, c)) continue;
      // キーの順番 (= 抽選の順番) はブラウザ版と同じにする
      final w = <String, double>{'N': 1};
      if (cellTypes.contains('T')) w['T'] = r <= 1 ? 0.12 : 0.03;
      if (cellTypes.contains('B')) w['B'] = 0.07;
      if (cellTypes.contains('R')) w['R'] = 0.09;
      if (cellTypes.contains('M')) w['M'] = 0.045;
      if (cellTypes.contains('S')) w['S'] = r >= rows - 2 ? 0.05 : 0.1;
      if (cellTypes.contains('X')) w['X'] = r >= 1 ? 0.07 : 0.02;
      if (!combo && newest != 'N') {
        for (final k in w.keys.toList()) {
          if (k != 'N') w[k] = w[k]! * (k == newest ? 2.2 : 0.5);
        }
      }
      for (final k in cnt.keys) {
        if (cnt[k]! >= caps[k]! && (w[k] ?? 0) != 0) w[k] = 0;
      }
      var tot = 0.0;
      for (final v in w.values) {
        tot += v;
      }
      var x = rng.next() * tot;
      var pick = 'N';
      for (final e in w.entries) {
        x -= e.value;
        if (x <= 0) {
          pick = e.key;
          break;
        }
      }
      if (b >= 12 && r > 0 && cnt['#']! < caps['#']! && rng.next() < 0.05) pick = '#';
      if (cnt.containsKey(pick)) cnt[pick] = cnt[pick]! + 1;
      grid[r][c] = pick;
      grid[r][_cols - 1 - c] = pick;
    }
  }
  if (types.contains('K')) _placeKeystones(grid, rng);
  var n = 0;
  for (final row in grid) {
    for (final ch in row) {
      if (_clearable.contains(ch)) n++;
    }
  }
  if (n < 14) grid[0] = List.filled(_cols, 'N');
  return [for (final r in grid) r.join()];
}

/// 塊ごとに最上段へ要石を置く (左右対称)。要石を失った塊は崩落する。
void _placeKeystones(List<List<String>> grid, Mulberry32 rng) {
  final rows = grid.length;
  final seen = List.generate(rows, (_) => List.filled(_cols, false));
  bool structural(String ch) => ch != '.' && ch != '#';
  for (var r = 0; r < rows; r++) {
    for (var c = 0; c < _cols; c++) {
      if (seen[r][c] || !structural(grid[r][c])) continue;
      final cells = <(int, int)>[];
      final q = <(int, int)>[(r, c)];
      seen[r][c] = true;
      while (q.isNotEmpty) {
        final (y, x) = q.removeLast();
        cells.add((y, x));
        for (final (dy, dx) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
          final ny = y + dy, nx = x + dx;
          if (ny < 0 || ny >= rows || nx < 0 || nx >= _cols || seen[ny][nx] || !structural(grid[ny][nx])) continue;
          seen[ny][nx] = true;
          q.add((ny, nx));
        }
      }
      if (cells.length < 5) continue;
      if (!cells.any((e) => e.$2 <= 6)) continue; // 右側だけの塊は左の鏡像で処理済み
      if (cells.any((e) => grid[e.$1][e.$2] == 'K')) continue;
      final left = cells.where((e) => e.$2 <= 6).toList();
      final top = left.map((e) => e.$1).reduce(math.min);
      final cand = left.where((e) => e.$1 == top).toList()..sort((a, b) => a.$2 - b.$2);
      final picks = cells.length >= 36 && cand.length > 1
          ? [cand.first, cand.last]
          : [cand[(rng.next() * cand.length).floor()]];
      for (final (y, x) in picks) {
        grid[y][x] = 'K';
        grid[y][_cols - 1 - x] = 'K';
      }
    }
  }
}
