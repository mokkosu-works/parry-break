// ブラウザ版 (index.html) のウェーブ配置生成をそのまま実行し、結果を JSON に書き出す。
// Flutter 版の配置生成がブラウザ版と一致することを確かめるためのゴールデンデータを作る。
//
//   node tools/dump_layouts.mjs > app/test/core/golden/layouts.json
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const html = readFileSync(fileURLToPath(new URL('../legacy/index.html', import.meta.url)), 'utf8');

// start から end の直前までを切り出す (end を含まない)
function slice(start, end) {
  const i = html.indexOf(start);
  const j = html.indexOf(end, i + start.length);
  if (i < 0 || j < 0) throw new Error(`marker not found: ${start} … ${end}`);
  return html.slice(i, j);
}

const src = [
  slice('function mulberry32', 'function circleRect'),
  slice('const CLEARABLE', 'const THRU'),
  slice('const HAND = {', '// ボス要塞'),
  slice('const BOSS_T = [', 'const BOSS_CORE_HP'),
  'return { genLayout, BOSS_T, mulberry32 };',
].join('\n');

const { genLayout, BOSS_T, mulberry32 } = new Function(src)();

const waves = {};
for (let b = 1; b <= 60; b++) if (b % 10 !== 0) waves[b] = genLayout(b);

// 乱数の一致確認用: いくつかのシードの先頭 8 個
const rng = {};
for (const seed of [0, 1, 3, 7919 + 3, 131 + 7, 123456789, -5]) {
  const r = mulberry32(seed);
  rng[seed] = Array.from({ length: 8 }, () => r());
}

process.stdout.write(JSON.stringify({ waves, bosses: BOSS_T, rng }, null, 1) + '\n');
