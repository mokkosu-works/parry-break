// 使い方: node check.mjs [build/web のパス] [出力フォルダ]
// build/web を配信してヘッドレス Chromium で開き、コンソールのエラー、AudioContext の状態、
// 実際に音が出ているか (出力のレベル) を調べて、スクリーンショットを撮る。
import { chromium } from 'playwright-core';
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(process.argv[2] ?? '../../app/build/web');
const out = path.resolve(process.argv[3] ?? './out');
fs.mkdirSync(out, { recursive: true });

const types = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.wasm': 'application/wasm',
  '.json': 'application/json', '.png': 'image/png', '.ttf': 'font/ttf', '.otf': 'font/otf' };
const server = http.createServer((req, res) => {
  const url = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  let file = path.join(root, url === '/' ? 'index.html' : url);
  if (!file.startsWith(root) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
    res.writeHead(404).end();
    return;
  }
  res.writeHead(200, { 'Content-Type': types[path.extname(file)] ?? 'application/octet-stream' });
  fs.createReadStream(file).pipe(res);
}).listen(0);
const base = `http://localhost:${server.address().port}/`;

const browser = await chromium.launch({
  executablePath: process.env.CHROME_EXECUTABLE ?? '/opt/pw-browsers/chromium',
  args: ['--no-sandbox', '--use-gl=swiftshader', '--enable-unsafe-swiftshader'],
});
const page = await browser.newPage({ viewport: { width: 844, height: 390 } });

// 音の出力を横取りして、レベルを測る
await page.addInitScript(() => {
  window.__audio = { contexts: [], peak: 0 };
  const origConnect = AudioNode.prototype.connect;
  AudioNode.prototype.connect = function (dest, ...rest) {
    const r = origConnect.call(this, dest, ...rest);
    if (dest instanceof AudioDestinationNode) {
      const ctx = dest.context;
      if (!ctx.__tap) {
        const an = ctx.createAnalyser();
        an.fftSize = 2048;
        origConnect.call(this, an);
        ctx.__tap = an;
        window.__audio.contexts.push(ctx);
        const buf = new Float32Array(an.fftSize);
        setInterval(() => {
          an.getFloatTimeDomainData(buf);
          for (const v of buf) window.__audio.peak = Math.max(window.__audio.peak, Math.abs(v));
        }, 50);
      }
    }
    return r;
  };
});

const logs = [];
page.on('console', (m) => logs.push(`[${m.type()}] ${m.text()}`));
page.on('pageerror', (e) => logs.push(`[pageerror] ${e.message}`));

const state = () => page.evaluate(() => ({
  contexts: window.__audio.contexts.map((c) => c.state),
  peak: Number(window.__audio.peak.toFixed(4)),
  isolated: window.crossOriginIsolated,
}));

await page.goto(base);
await page.waitForTimeout(15000); // Flutter の起動 + 音の書き出し
await page.screenshot({ path: path.join(out, '1-title.png') });
const before = await state();

await page.mouse.click(422, 195); // 最初の操作 (ブラウザの自動再生の制限を外す)
await page.waitForTimeout(3000);
await page.screenshot({ path: path.join(out, '2-after-tap.png') });
const after = await state();

console.log(JSON.stringify({ before, after }, null, 2));
console.log(logs.filter((l) => !l.startsWith('[log]') || /audio|soloud|error/i.test(l)).slice(0, 30).join('\n'));
await browser.close();
server.close();
const ok = after.contexts.length > 0 && after.contexts.every((s) => s === 'running') && after.peak > 0.001;
console.log(ok ? 'AUDIO OK' : 'AUDIO NOT PLAYING');
process.exit(ok ? 0 : 1);
