'use strict';
// 動画レイアウト編集ツールの画面。ビルド工程なし、外部ライブラリなし。
// 文字や画像のレイヤーは、サーバーが書き出しと同じ Pillow のコードで描いた透過 PNG を置くだけにして、
// プレビューと書き出しの見た目をそろえる。

const $ = (sel, el = document) => el.querySelector(sel);
const TYPE_LABEL = { text: 'テキスト', image: '画像', video: 'ゲーム映像', rect: '枠', character: 'キャラクター' };
const POSE_LABEL = ['ポーズ 1', 'ポーズ 2', 'ポーズ 3', 'ポーズ 4', 'ポーズ 5', 'ポーズ 6'];
const HISTORY_LIMIT = 200;

const state = {
  info: null, assets: null, name: null, project: null, saved: '',
  scene: 0, selected: null, undo: [], redo: [], problems: [],
  images: new Map(),    // 描画の内容のキー → {url, dx, dy, w, h} か {error}
  lastShown: new Map(), // シーン/レイヤー id → 直前に出した画像 (読み込み中のちらつきを防ぐ)
  pending: new Set(),
  bgs: new Map(),       // 背景のキー → URL
  els: new Map(),       // シーン/レイヤー id → 画面の要素
  scale: 0.3, playing: null, drag: null, editSnap: null, exportTimer: null,
  voiceCheck: null,     // {key, lines: [{duration, end}], problems, message} 台詞の長さと重なり
  listening: null,      // 試し聞き中の Audio
};

// ---------------------------------------------------------------- 小道具

function h(tag, attrs = {}, ...children) {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (v === undefined || v === null || v === false) continue;
    if (k === 'class') el.className = v;
    else if (k.startsWith('on')) el.addEventListener(k.slice(2), v);
    else if (k === 'dataset') Object.assign(el.dataset, v);
    else if (v === true) el.setAttribute(k, '');
    else el.setAttribute(k, v);
  }
  for (const c of children.flat()) {
    if (c === null || c === undefined || c === false) continue;
    el.append(c instanceof Node ? c : document.createTextNode(String(c)));
  }
  return el;
}

async function api(method, path, body) {
  const opt = { method, headers: {} };
  if (body !== undefined) { opt.headers['Content-Type'] = 'application/json'; opt.body = JSON.stringify(body); }
  let res;
  try { res = await fetch(path, opt); } catch (e) {
    return { ok: false, status: 0, data: { error: 'サーバーに接続できません。promo/editor/server.py が動いているか確かめてください' } };
  }
  let data = null;
  try { data = await res.json(); } catch (e) { data = { error: `サーバーの返事を読めません (${res.status})` }; }
  return { ok: res.ok, status: res.status, data };
}

let toastTimer = null;
function toast(message, error = false) {
  const el = $('#toast');
  el.textContent = message;
  el.className = error ? 'error' : '';
  el.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { el.hidden = true; }, error ? 7000 : 3000);
}

const clone = (v) => JSON.parse(JSON.stringify(v));
const scene = () => state.project.scenes[state.scene];
const layerById = (id, sc = scene()) => sc.layers.find((l) => l.id === id);
const selectedLayer = () => (state.selected ? layerById(state.selected) : null);
const sceneLabel = (i) => state.info.scenes[i].label;
const elKey = (layer) => `${scene().id}/${layer.id}`;
const fmtTime = (s) => `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, '0')}`;

function assetBy(kind, suffix) {
  const items = (state.assets && state.assets[kind]) || [];
  return items.find((a) => a.label.endsWith(suffix)) || items[0];
}

// ---------------------------------------------------------------- 履歴と未保存

function snapshot() { return JSON.stringify(state.project); }

function pushHistory(before) {
  if (before === snapshot()) return false;
  state.undo.push(before);
  if (state.undo.length > HISTORY_LIMIT) state.undo.shift();
  state.redo = [];
  return true;
}

// 変更を 1 回の操作としてまとめる
function change(fn) {
  const before = snapshot();
  fn();
  if (pushHistory(before)) committed();
}

function committed() {
  renderAll();
  scheduleValidate();
}

function undo() {
  if (!state.undo.length) return;
  stopPlay();
  state.redo.push(snapshot());
  state.project = JSON.parse(state.undo.pop());
  afterHistory();
}

function redo() {
  if (!state.redo.length) return;
  stopPlay();
  state.undo.push(snapshot());
  state.project = JSON.parse(state.redo.pop());
  afterHistory();
}

function afterHistory() {
  if (state.selected && !selectedLayer()) state.selected = null;
  committed();
}

const isDirty = () => state.project && snapshot() !== state.saved;

// ---------------------------------------------------------------- 検証

let validateTimer = null;
function scheduleValidate() {
  clearTimeout(validateTimer);
  validateTimer = setTimeout(async () => {
    const r = await api('POST', '/api/validate', state.project);
    state.problems = r.ok ? r.data.problems : [{ message: r.data.error }];
    renderProblems();
  }, 350);
  scheduleVoiceCheck();
}

// ---------------------------------------------------------------- 台詞

// 台詞の並び。プロジェクトに voice がなければ、既定 (v12 と同じ) を見せる
const voiceLines = () => (state.project.voice && state.project.voice.lines) || state.info.voice.lines;
const voiceUrl = (text) => `/api/voice?text=${encodeURIComponent(text)}`;

// 書き換える前に、既定の台詞をプロジェクトへ写す
function ownVoiceLines() {
  if (!state.project.voice) state.project.voice = { lines: clone(state.info.voice.lines) };
  return state.project.voice.lines;
}

function sceneAt(t) {
  const i = state.project.scenes.findIndex((s) => t >= s.start && t < s.start + s.duration);
  return i < 0 ? '' : sceneLabel(i);
}

let voiceTimer = null;
function scheduleVoiceCheck() {
  const key = JSON.stringify(voiceLines());
  if (state.voiceCheck && state.voiceCheck.key === key) return;
  clearTimeout(voiceTimer);
  voiceTimer = setTimeout(async () => {
    const r = await api('POST', '/api/voice/check', { lines: JSON.parse(key) });
    if (key !== JSON.stringify(voiceLines())) return; // 待つ間に書き換わった
    state.voiceCheck = r.ok
      ? { key, lines: r.data.lines, problems: r.data.problems, message: r.data.message }
      : { key, lines: [], problems: [r.data.error + (r.data.hint ? ` (${r.data.hint})` : '')] };
    renderVoiceStatus();
  }, 500);
}

// 長さの表示だけを直す (打っている途中の欄は作り直さない)
function renderVoiceStatus() {
  const box = $('#voiceStatus');
  if (!box) return;
  const vc = state.voiceCheck;
  const fresh = vc && vc.key === JSON.stringify(voiceLines());
  document.querySelectorAll('[data-voice-len]').forEach((el) => {
    const t = fresh && vc.lines[Number(el.dataset.voiceLen)];
    el.textContent = t ? `長さ ${t.duration.toFixed(2)} 秒 (${t.end.toFixed(2)} 秒まで)` : '';
  });
  if (!fresh) { box.className = 'muted small'; box.textContent = '台詞の長さを確かめています…'; return; }
  if (vc.problems.length) { box.className = 'err small'; box.replaceChildren(...vc.problems.map((m) => h('div', {}, m))); return; }
  box.className = 'muted small';
  box.textContent = vc.message || '台詞は重なっていません。';
}

function listen(text, button) {
  if (state.listening) { state.listening.pause(); state.listening = null; }
  if (!text.trim()) return;
  const audio = new Audio(voiceUrl(text));
  state.listening = audio;
  button.disabled = true;
  const done = () => { button.disabled = false; };
  audio.addEventListener('ended', done);
  audio.addEventListener('pause', done);
  audio.addEventListener('error', () => { done(); toast('読み上げを作れません。VOICEVOX が起動しているか確かめてください', true); });
  audio.play().catch(() => {});
}

function renderVoiceEditor(panel) {
  const v = state.info.voice;
  const lines = voiceLines();
  const total = state.project.scenes.reduce((n, s) => n + s.duration, 0);
  panel.append(h('h3', {}, '台詞 (動画全体)'));
  const box = h('div', { class: 'voice' });
  lines.forEach((line, i) => {
    const start = h('input', { type: 'number', step: 0.1, min: 0, max: total, value: line.start, title: '話し始め (動画の頭からの秒)' });
    const text = h('input', { type: 'text', value: line.text, maxlength: v.maxText, title: '台詞' });
    // 確定したら早い順に並べ直す (bindInput より先に付けて、履歴に積む前に済ませる)
    start.addEventListener('change', () => { if (state.project.voice) state.project.voice.lines.sort((a, b) => a.start - b.start); });
    bindInput(start, (raw) => {
      const n = Number(raw);
      if (raw === '' || !Number.isFinite(n) || n < 0 || n >= total) return false;
      ownVoiceLines()[i].start = n;
      scheduleVoiceCheck(); renderVoiceStatus();
      return true;
    });
    bindInput(text, (raw) => {
      if (!raw.trim()) return false;
      ownVoiceLines()[i].text = raw;
      scheduleVoiceCheck(); renderVoiceStatus();
      return true;
    });
    const play = h('button', { type: 'button', title: 'この台詞を聞く', onclick: (e) => listen(text.value, e.currentTarget) }, '聞く');
    const del = h('button', { type: 'button', title: 'この台詞を消す', onclick: () => change(() => { ownVoiceLines().splice(i, 1); }) }, '×');
    box.append(h('div', { class: 'voice-line' }, start, text, play, del),
      h('div', { class: 'voice-meta muted small' }, h('span', {}, `${sceneAt(line.start)}`), h('span', { dataset: { voiceLen: i } })));
  });
  panel.append(box);
  const add = h('button', { type: 'button', disabled: lines.length >= v.maxLines, onclick: () => change(() => {
    const own = ownVoiceLines();
    const sc = scene();
    own.push({ start: sc.start, text: '新しい台詞' });
    own.sort((a, b) => a.start - b.start);
  }) }, 'このシーンの頭に台詞を足す');
  const reset = h('button', { type: 'button', disabled: !state.project.voice, onclick: () => change(() => { delete state.project.voice; }) }, '元の台詞に戻す');
  panel.append(h('div', { class: 'voice-actions' }, add, reset));
  panel.append(h('div', { id: 'voiceStatus', class: 'muted small' }));
  panel.append(h('div', { class: 'muted small' },
    `声は VOICEVOX: ${v.speakerName} (話者 ${v.speaker})、速さ ${v.speedScale}、抑揚 ${v.intonationScale} で固定です。` +
    `左の数は話し始めの時刻 (秒)。画面の字幕は別のレイヤーなので、台詞を変えたら字幕も合わせてください。` +
    `ゲームの音は音量 ${state.info.gameVolume}。`));
  renderVoiceStatus();
}

// ---------------------------------------------------------------- プレビュー画像

function imageKey(layer) {
  const l = clone(layer);
  for (const k of ['x', 'y', 'id', 'name', 'visible', 'bob', 'bobAmplitude']) delete l[k];
  return JSON.stringify(l);
}

function layerImage(layer) {
  const key = imageKey(layer);
  const img = state.images.get(key);
  if (img) { state.lastShown.set(elKey(layer), img); return img; }
  if (!state.pending.has(key)) fetchLayerImage(layer, key);
  return { stale: true, ...(state.lastShown.get(elKey(layer)) || {}) };
}

async function fetchLayerImage(layer, key) {
  state.pending.add(key);
  const body = { ...JSON.parse(key), x: 0, y: 0 };
  try {
    const res = await fetch('/api/preview/layer', {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body),
    });
    if (!res.ok) {
      let msg = `描けません (${res.status})`;
      try { msg = (await res.json()).error || msg; } catch (e) { /* そのまま */ }
      state.images.set(key, { error: msg });
    } else {
      const dx = Number(res.headers.get('X-Dx')) || 0;
      const dy = Number(res.headers.get('X-Dy')) || 0;
      const url = URL.createObjectURL(await res.blob());
      const size = await new Promise((resolve) => {
        const im = new Image();
        im.onload = () => resolve({ w: im.naturalWidth, h: im.naturalHeight });
        im.onerror = () => resolve({ w: 1, h: 1 });
        im.src = url;
      });
      state.images.set(key, { url, dx, dy, ...size });
    }
  } catch (e) {
    state.images.set(key, { error: 'サーバーに接続できません' });
  } finally {
    state.pending.delete(key);
  }
  if (!state.drag) { renderStage(); renderProps(true); }
}

async function loadBackground() {
  const bg = scene().background;
  const key = JSON.stringify(bg);
  const img = $('#bg');
  if (state.bgs.has(key)) { img.src = state.bgs.get(key); return; }
  img.removeAttribute('src');
  const res = await fetch('/api/preview/background', {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: key,
  });
  if (!res.ok) {
    let msg = '背景を描けません';
    try { msg = (await res.json()).error || msg; } catch (e) { /* そのまま */ }
    toast(`背景: ${msg}`, true);
    return;
  }
  const url = URL.createObjectURL(await res.blob());
  state.bgs.set(key, url);
  if (JSON.stringify(scene().background) === key) img.src = url;
}

// レイヤーの画面上の範囲 (キャンバスの座標)
function layerBox(layer) {
  switch (layer.type) {
    case 'text': {
      const img = layerImage(layer);
      if (img.url) {
        const ts = state.drag && state.drag.kind === 'scale' && state.drag.id === layer.id ? state.drag : null;
        if (ts) {
          const f = ts.f;
          return { x: ts.anchor.x + (ts.box0.x - ts.anchor.x) * f, y: ts.anchor.y + (ts.box0.y - ts.anchor.y) * f, w: ts.box0.w * f, h: ts.box0.h * f };
        }
        return { x: layer.x + img.dx, y: layer.y + img.dy, w: img.w, h: img.h };
      }
      return { x: layer.x, y: layer.y, w: Math.max(40, layer.fontSize * layer.text.length), h: layer.fontSize * 1.3 };
    }
    case 'rect': return { x: layer.x, y: layer.y, w: layer.width + 1, h: layer.height + 1 };
    case 'character': return { x: layer.x, y: layer.y, w: Math.floor(Math.round(layer.height) / 2), h: Math.round(layer.height) };
    default: return { x: layer.x, y: layer.y, w: layer.width, h: layer.height };
  }
}

// ---------------------------------------------------------------- 描画

function renderAll() {
  renderToolbar();
  renderScenes();
  renderLayers();
  renderStage();
  renderProps();
  renderProblems();
}

function renderToolbar() {
  $('#dirty').hidden = !isDirty();
  $('#undoBtn').disabled = !state.undo.length;
  $('#redoBtn').disabled = !state.redo.length;
  $('#playBtn').textContent = state.playing ? '停止' : '再生';
  document.title = `${isDirty() ? '* ' : ''}${state.name} - 動画レイアウト編集`;
}

function renderScenes() {
  const list = $('#sceneList');
  list.replaceChildren();
  state.project.scenes.forEach((sc, i) => {
    list.append(h('li', { class: i === state.scene ? 'active' : '', onclick: () => selectScene(i) },
      h('span', { class: 'name' }, sceneLabel(i)),
      h('span', { class: 'kind' }, `${fmtTime(sc.start)}〜${fmtTime(sc.start + sc.duration)} (${sc.duration} 秒)`)));
  });
}

function renderLayers() {
  const list = $('#layerList');
  list.replaceChildren();
  const layers = scene().layers;
  for (let i = layers.length - 1; i >= 0; i--) {
    const l = layers[i];
    const vis = l.visible !== false;
    list.append(h('li', {
      class: [l.id === state.selected ? 'active' : '', vis ? '' : 'hidden-layer'].join(' '),
      onclick: () => select(l.id), dataset: { id: l.id },
    },
    h('input', { type: 'checkbox', title: '表示', checked: vis, onclick: (e) => e.stopPropagation(),
      onchange: (e) => change(() => { l.visible = e.target.checked; }) }),
    h('span', { class: 'name', title: l.id }, l.name || l.id),
    h('span', { class: 'kind' }, TYPE_LABEL[l.type] || l.type),
    h('button', { title: '手前へ', disabled: i === layers.length - 1, onclick: (e) => { e.stopPropagation(); moveLayer(l.id, 1); } }, '↑'),
    h('button', { title: '奥へ', disabled: i === 0, onclick: (e) => { e.stopPropagation(); moveLayer(l.id, -1); } }, '↓')));
  }
  const add = $('#addButtons');
  add.replaceChildren(
    h('button', { onclick: () => addLayer('text') }, 'テキスト'),
    h('button', { onclick: () => addLayer('character') }, 'キャラクター'),
    h('button', { onclick: () => addLayer('icon') }, 'アプリアイコン'),
    h('button', { onclick: () => addLayer('appstore') }, 'App Store バッジ'),
    h('button', { onclick: () => addLayer('googleplay') }, 'Google Play バッジ'),
    h('button', { onclick: () => addLayer('rect') }, '枠'),
    scene().layers.some((l) => l.type === 'video') ? '' : h('button', { onclick: () => addLayer('video') }, 'ゲーム映像'),
  );
}

function renderProblems() {
  const ul = $('#problems');
  ul.replaceChildren();
  ul.className = state.problems.length ? 'problems' : 'problems none';
  $('#problemCount').textContent = state.problems.length ? `(${state.problems.length})` : '';
  if (!state.problems.length) ul.append(h('li', {}, '問題はありません'));
  for (const p of state.problems) ul.append(h('li', {}, p.message));
}

function fitStage() {
  const vp = $('#viewport');
  const s = Math.max(0.05, Math.min((vp.clientWidth - 32) / 1080, (vp.clientHeight - 32) / 1920));
  state.scale = s;
  $('#stage').style.transform = `scale(${s})`;
  const wrap = $('#stageWrap');
  wrap.style.width = `${1080 * s}px`;
  wrap.style.height = `${1920 * s}px`;
  $('#selection').style.setProperty('--h', `${Math.round(14 / s)}px`);
  $('#status').textContent = `表示 ${Math.round(s * 100)}% (1080×1920)`;
}

function renderStage() {
  const container = $('#layers');
  const sc = scene();
  const seen = new Set();
  sc.layers.forEach((layer, index) => {
    if (layer.visible === false) return;
    const key = elKey(layer);
    seen.add(key);
    let el = state.els.get(key);
    if (!el || el.dataset.type !== layer.type) {
      if (el) el.remove();
      el = h('div', { class: `layer ${layer.type}`, dataset: { id: layer.id, type: layer.type } });
      el.addEventListener('pointerdown', (e) => startMove(e, layer.id));
      state.els.set(key, el);
      container.append(el);
    }
    el.style.zIndex = String(index + 1);
    updateLayerElement(layer, el);
  });
  for (const [key, el] of state.els) {
    if (!seen.has(key)) { el.remove(); state.els.delete(key); }
  }
  $('#safe').hidden = !$('#safeToggle').checked;
  $('#stage').classList.toggle('outlines', $('#outlineToggle').checked);
  updateSelection();
}

function updateLayerElement(layer, el = state.els.get(elKey(layer))) {
  if (!el) return;
  if (layer.type === 'video') return updateVideoElement(layer, el);
  const box = layerBox(layer);
  Object.assign(el.style, { left: `${box.x}px`, top: `${box.y}px`, width: `${box.w}px`, height: `${box.h}px` });
  const img = layerImage(layer);
  el.classList.toggle('broken', !!img.error);
  el.classList.toggle('loading', !img.url && !img.error);
  if (img.error) {
    el.replaceChildren(h('span', {}, img.error));
    return;
  }
  let im = el.querySelector('img');
  if (!im) { im = h('img', { alt: '', draggable: 'false' }); el.replaceChildren(im); }
  if (img.url && im.getAttribute('src') !== img.url) im.src = img.url;
  if (!img.url) im.removeAttribute('src');
}

function mediaUrl(src) { return `/media?src=${encodeURIComponent(src)}`; }

function updateVideoElement(layer, el) {
  const box = layerBox(layer);
  Object.assign(el.style, { left: `${box.x}px`, top: `${box.y}px`, width: `${box.w}px`, height: `${box.h}px` });
  let v = el.querySelector('video');
  if (!v) {
    v = h('video', { preload: 'auto', playsinline: true, muted: true });
    v.muted = true;
    v.addEventListener('loadedmetadata', () => { if (!state.playing) seekVideo(v, Number(v.dataset.start)); });
    v.addEventListener('error', () => toast(`動画を読めません: ${v.dataset.src} (素材を選び直してください)`, true));
    el.replaceChildren(v);
  }
  const src = mediaUrl(layer.src);
  if (v.dataset.src !== layer.src) { v.dataset.src = layer.src; v.src = src; }
  if (Number(v.dataset.start) !== layer.start) {
    v.dataset.start = String(layer.start);
    if (!state.playing && v.readyState >= 1) seekVideo(v, layer.start);
  }
  // 表示範囲 (crop) を箱いっぱいに引き伸ばす。書き出しの crop → scale と同じ。
  const c = layer.crop;
  const natW = v.videoWidth || 2400, natH = v.videoHeight || 1080;
  const sx = layer.width / c.width, sy = layer.height / c.height;
  Object.assign(v.style, { width: `${natW * sx}px`, height: `${natH * sy}px`, left: `${-c.x * sx}px`, top: `${-c.y * sy}px` });
}

function seekVideo(v, t) {
  if (!Number.isFinite(t)) return;
  v.pause();
  try { v.currentTime = t; } catch (e) { /* 読み込み前 */ }
}

function updateSelection() {
  const sel = $('#selection');
  const layer = selectedLayer();
  if (!layer || layer.visible === false) { sel.hidden = true; return; }
  const b = layerBox(layer);
  sel.hidden = false;
  Object.assign(sel.style, { left: `${b.x}px`, top: `${b.y}px`, width: `${b.w}px`, height: `${b.h}px`, zIndex: '1000' });
}

// ---------------------------------------------------------------- 右パネル

function numberField(label, layer, key, opts = {}) {
  const value = key.split('.').reduce((o, k) => (o ? o[k] : undefined), layer);
  const input = h('input', { type: 'number', step: opts.step || 1, value: value ?? '', readonly: opts.readonly, dataset: { key } });
  if (!opts.readonly) bindInput(input, (raw) => {
    const n = Number(raw);
    if (raw === '' || !Number.isFinite(n)) return false;
    if (opts.min !== undefined && n < opts.min) return false;
    if (opts.max !== undefined && n > opts.max) return false;
    (opts.set || ((v) => setPath(layer, key, v)))(n);
    return true;
  });
  return [h('label', {}, label), input];
}

function setPath(obj, path, value) {
  const keys = path.split('.');
  const last = keys.pop();
  keys.reduce((o, k) => o[k], obj)[last] = value;
}

// 入力欄: 打つたびにプレビューへ反映し、確定したら 1 回の操作として履歴に積む
function bindInput(input, apply) {
  input.addEventListener('focus', () => { state.editSnap = snapshot(); });
  input.addEventListener('input', () => {
    const value = input.type === 'checkbox' ? input.checked : input.value;
    const ok = apply(value);
    input.classList.toggle('invalid', ok === false);
    if (ok !== false) { renderStage(); renderToolbar(); }
  });
  input.addEventListener('change', () => {
    const before = state.editSnap ?? snapshot();
    state.editSnap = snapshot();
    if (pushHistory(before)) { renderAll(); scheduleValidate(); }
  });
}

function selectField(label, layer, key, options, opts = {}) {
  const value = key.split('.').reduce((o, k) => (o ? o[k] : undefined), layer);
  const sel = h('select', { dataset: { key } }, options.map(([v, text]) =>
    h('option', { value: String(v), selected: String(v) === String(value) }, text)));
  if (!options.some(([v]) => String(v) === String(value))) {
    sel.prepend(h('option', { value: String(value), selected: true }, `(一覧にない) ${value}`));
  }
  bindInput(sel, (raw) => {
    const match = options.find(([v]) => String(v) === raw);
    (opts.set || ((v) => setPath(layer, key, v)))(match ? match[0] : raw);
    return true;
  });
  return [h('label', {}, label), sel];
}

function renderProps(onlyIfIdle = false) {
  const panel = $('#right');
  if (onlyIfIdle && panel.contains(document.activeElement) && document.activeElement !== document.body) {
    // 打っている途中は作り直さない。幅と高さだけ直す
    const layer = selectedLayer();
    if (layer && layer.type === 'text') {
      const b = layerBox(layer);
      const w = panel.querySelector('[data-key="_w"]'), hh = panel.querySelector('[data-key="_h"]');
      if (w) w.value = Math.round(b.w);
      if (hh) hh.value = Math.round(b.h);
    }
    return;
  }
  panel.replaceChildren();
  const layer = selectedLayer();
  if (!layer) return renderSceneProps(panel);
  const sc = scene();
  const index = sc.layers.indexOf(layer);
  panel.append(h('h2', {}, `${TYPE_LABEL[layer.type]} (${sceneLabel(state.scene)})`));
  const form = h('div', { class: 'form' });
  const nameInput = h('input', { type: 'text', value: layer.name || '' });
  bindInput(nameInput, (v) => { layer.name = v; return true; });
  form.append(h('label', {}, '名前'), nameInput);
  form.append(...numberField('X', layer, 'x'), ...numberField('Y', layer, 'y'));
  const box = layerBox(layer);
  if (layer.type === 'text') {
    form.append(h('label', {}, '幅'), h('input', { type: 'number', readonly: true, value: Math.round(box.w), dataset: { key: '_w' } }));
    form.append(h('label', {}, '高さ'), h('input', { type: 'number', readonly: true, value: Math.round(box.h), dataset: { key: '_h' } }));
    form.append(h('div', { class: 'note' }, '文字の幅と高さは文字サイズで決まります (四隅のハンドルで拡大縮小できます)。X, Y は書き出しの基準点 (行の上端) です。'));
  } else if (layer.type === 'character') {
    form.append(h('label', {}, '幅'), h('input', { type: 'number', readonly: true, value: Math.floor(Math.round(layer.height) / 2) }));
    form.append(...numberField('高さ', layer, 'height', { min: 20, max: 4000 }));
  } else if (layer.type === 'image') {
    const nat = imageNatural(layer);
    form.append(...numberField('幅', layer, 'width', { min: 1, set: (v) => { layer.width = v; if (nat) layer.height = Math.max(1, Math.round(v * nat.h / nat.w)); syncField('height', layer.height); } }));
    form.append(...numberField('高さ', layer, 'height', { min: 1, set: (v) => { layer.height = v; if (nat) layer.width = Math.max(1, Math.round(v * nat.w / nat.h)); syncField('width', layer.width); } }));
  } else {
    form.append(...numberField('幅', layer, 'width', { min: 1 }), ...numberField('高さ', layer, 'height', { min: 1 }));
  }
  const vis = h('input', { type: 'checkbox', checked: layer.visible !== false });
  bindInput(vis, (v) => { layer.visible = v; return true; });
  form.append(h('label', {}, '表示'), vis);
  form.append(...numberField('重なり順', { order: index + 1 }, 'order', {
    min: 1, max: sc.layers.length,
    set: (v) => { const i = sc.layers.indexOf(layer); sc.layers.splice(i, 1); sc.layers.splice(Math.round(v) - 1, 0, layer); },
  }));
  form.append(h('div', { class: 'note' }, `1 がいちばん奥、${sc.layers.length} がいちばん手前。`));

  if (layer.type === 'text') {
    form.append(h('h3', { class: 'full' }, 'テキスト'));
    const ta = h('textarea', {}, layer.text);
    bindInput(ta, (v) => { if (!v.trim()) return false; layer.text = v; return true; });
    form.append(h('label', {}, '文言'), ta);
    form.append(...selectField('フォント', layer, 'font', state.assets.font.map((a) => [a.src, a.label.split('/').pop()])));
    form.append(...numberField('サイズ', layer, 'fontSize', { min: 4, max: 600 }));
    form.append(...colorField('色', layer, 'color'));
    form.append(...numberField('縁取り', layer, 'strokeWidth', { min: 0, max: 60 }));
    form.append(...colorField('縁取りの色', layer, 'strokeColor'));
    form.append(...selectField('行揃え', layer, 'align', [['left', '左'], ['center', '中央'], ['right', '右']]));
    form.append(h('div', { class: 'note' }, '行揃えは複数行 (改行を含む) のときに効きます。'));
  } else if (layer.type === 'image') {
    form.append(h('h3', { class: 'full' }, '画像'));
    form.append(...selectField('素材', layer, 'src', state.assets.image.map((a) => [a.src, a.label]), {
      set: (v) => { layer.src = v; const nat = imageNatural(layer); if (nat) layer.height = Math.max(1, Math.round(layer.width * nat.h / nat.w)); },
    }));
    form.append(...numberField('透明度', layer, 'opacity', { min: 0, max: 1, step: 0.05 }));
    form.append(h('div', { class: 'note' }, '透明度は 1 で不透明、0 で見えません。'));
  } else if (layer.type === 'video') {
    form.append(h('h3', { class: 'full' }, 'ゲーム映像'));
    form.append(...selectField('素材動画', layer, 'src', state.assets.video.map((a) => [a.src, a.label.split('/').pop()])));
    form.append(...numberField('開始時刻', layer, 'start', { min: 0, step: 0.1 }));
    form.append(h('div', { class: 'note' }, `元の動画の ${layer.start} 秒から ${sc.duration} 秒分を使います。`));
    form.append(h('h3', { class: 'full' }, '表示範囲 (元の動画から切り出す範囲)'));
    form.append(...numberField('左', layer, 'crop.x', { min: 0 }), ...numberField('上', layer, 'crop.y', { min: 0 }));
    form.append(...numberField('幅', layer, 'crop.width', { min: 2 }), ...numberField('高さ', layer, 'crop.height', { min: 2 }));
    form.append(h('div', { class: 'note' }, '切り出した範囲を、上の幅×高さの箱いっぱいに引き伸ばします (v12 は 1800×1080 を左 245 から)。'));
  } else if (layer.type === 'character') {
    form.append(h('h3', { class: 'full' }, 'キャラクター'));
    form.append(...selectField('素材', layer, 'src', state.assets.image.filter((a) => a.width >= 362 * 6).map((a) => [a.src, a.label])));
    form.append(...selectField('ポーズ', layer, 'pose', POSE_LABEL.map((t, i) => [i, t])));
    const bob = h('input', { type: 'checkbox', checked: layer.bob !== false });
    bindInput(bob, (v) => { layer.bob = v; return true; });
    form.append(h('label', {}, '揺れ'), bob);
    form.append(...numberField('揺れの振幅', layer, 'bobAmplitude', { min: 0, max: 200 }));
    form.append(h('div', { class: 'note' }, `揺れは縦に 振幅×sin(2π×${state.info.bobHz}×t) px。再生で確かめられます。揺れはシーンごとに切り替えます。`));
  } else if (layer.type === 'rect') {
    form.append(h('h3', { class: 'full' }, '枠'));
    form.append(...colorField('色', layer, 'color'));
    form.append(...numberField('太さ', layer, 'strokeWidth', { min: 1, max: 200 }));
  }
  panel.append(form);
  panel.append(h('div', { class: 'actions' },
    h('button', { onclick: () => applyToAll(layer.id), title: 'ほかのシーンの同じ id のレイヤーに、位置・大きさ・見た目を写す' }, '全シーンに適用'),
    h('button', { onclick: () => duplicateLayer(layer.id) }, '複製'),
    h('button', { class: 'danger', onclick: () => deleteLayer(layer.id) }, '削除')));
  panel.append(h('p', { class: 'muted small' }, `id: ${layer.id}`));
}

function syncField(key, value) {
  const el = $(`#right [data-key="${key}"]`);
  if (el && document.activeElement !== el) el.value = value;
}

function colorField(label, layer, key) {
  const input = h('input', { type: 'color', value: layer[key] });
  bindInput(input, (v) => { layer[key] = v; return true; });
  return [h('label', {}, label), input];
}

function imageNatural(layer) {
  const a = state.assets.image.find((x) => x.src === layer.src);
  return a ? { w: a.width, h: a.height } : null;
}

function renderSceneProps(panel) {
  const sc = scene();
  panel.append(h('h2', {}, `シーン「${sceneLabel(state.scene)}」`));
  const form = h('div', { class: 'form' });
  form.append(h('label', {}, '開始'), h('input', { type: 'text', readonly: true, value: `${sc.start} 秒` }));
  form.append(h('label', {}, '長さ'), h('input', { type: 'text', readonly: true, value: `${sc.duration} 秒` }));
  form.append(h('div', { class: 'note' }, '初版では、シーンの順序と長さは変えられません (24 秒の構成のまま)。'));
  form.append(h('h3', { class: 'full' }, '背景 (ゲームのフレームをぼかして暗くしたもの)'));
  form.append(...selectField('素材動画', sc.background, 'src', state.assets.video.map((a) => [a.src, a.label.split('/').pop()])));
  form.append(...numberField('時刻', sc.background, 'time', { min: 0, step: 0.1 }));
  panel.append(form);
  panel.append(h('p', { class: 'muted small' }, 'レイヤーをクリックすると、その設定をここで変えられます。'));
  renderVoiceEditor(panel);
}

// ---------------------------------------------------------------- レイヤーの操作

function select(id) {
  state.selected = id;
  renderLayers();
  updateSelection();
  renderProps();
}

function selectScene(i) {
  if (i === state.scene) return;
  stopPlay();
  state.scene = i;
  if (state.selected && !layerById(state.selected)) state.selected = null;
  $('#layers').replaceChildren();
  state.els.clear();
  loadBackground();
  renderAll();
}

function uniqueId(base, sc = scene()) {
  if (!sc.layers.some((l) => l.id === base)) return base;
  for (let n = 2; ; n++) if (!sc.layers.some((l) => l.id === `${base}-${n}`)) return `${base}-${n}`;
}

function addLayer(kind) {
  const sc = scene();
  let layer;
  const font = assetBy('font', 'DotGothic16-Regular.ttf');
  if (kind === 'text') {
    layer = { id: uniqueId('text'), type: 'text', name: 'テキスト', visible: true, x: 200, y: 700, text: 'テキスト',
      font: font && font.src, fontSize: 60, color: '#ffffff', strokeWidth: 3, strokeColor: '#0b0b1a', align: 'left' };
  } else if (kind === 'character') {
    const sheet = assetBy('image', 'character_sheet_v2.png');
    layer = { id: uniqueId('character'), type: 'character', name: 'キャラクター', visible: true, x: 300, y: 900, height: 600,
      src: sheet && sheet.src, pose: 0, bob: true, bobAmplitude: 4 };
  } else if (kind === 'icon') {
    const icon = assetBy('image', 'icon-512.png');
    layer = { id: uniqueId('app-icon'), type: 'image', name: 'アプリアイコン', visible: true, x: 200, y: 700, width: 108, height: 108,
      src: icon && icon.src, opacity: 1, resample: 'lanczos' };
  } else if (kind === 'appstore' || kind === 'googleplay') {
    const badge = assetBy('image', `badges/${kind}.png`);
    const height = 76;
    const width = badge ? Math.round(height * badge.width / badge.height) : 200;
    layer = { id: uniqueId(`badge-${kind}`), type: 'image', name: kind === 'appstore' ? 'App Store バッジ' : 'Google Play バッジ',
      visible: true, x: 200, y: 800, width, height, src: badge && badge.src, opacity: 1, resample: 'bicubic' };
  } else if (kind === 'rect') {
    layer = { id: uniqueId('frame'), type: 'rect', name: '枠', visible: true, x: 200, y: 600, width: 400, height: 300, color: '#ffc61a', strokeWidth: 10 };
  } else if (kind === 'video') {
    const video = assetBy('video', '.mp4');
    layer = { id: uniqueId('game'), type: 'video', name: 'ゲーム映像', visible: true, x: 40, y: 304, width: 1000, height: 600,
      src: video && video.src, start: 0, crop: { x: 245, y: 0, width: 1800, height: 1080 } };
  }
  if (!layer || Object.values(layer).includes(undefined)) {
    toast('追加できる素材がリポジトリ内に見つかりません', true);
    return;
  }
  change(() => {
    // 動画とキャラクターの下ではなく、いちばん手前に足す
    sc.layers.push(layer);
    state.selected = layer.id;
  });
}

function duplicateLayer(id) {
  const sc = scene();
  const layer = layerById(id);
  if (!layer) return;
  const copy = clone(layer);
  copy.id = uniqueId(layer.id.replace(/-\d+$/, ''));
  copy.name = `${layer.name || layer.id} のコピー`;
  copy.x += 30; copy.y += 30;
  change(() => {
    sc.layers.splice(sc.layers.indexOf(layer) + 1, 0, copy);
    state.selected = copy.id;
  });
}

function deleteLayer(id) {
  const sc = scene();
  const i = sc.layers.findIndex((l) => l.id === id);
  if (i < 0) return;
  change(() => {
    sc.layers.splice(i, 1);
    if (state.selected === id) state.selected = null;
  });
}

function moveLayer(id, delta) {
  const sc = scene();
  const i = sc.layers.findIndex((l) => l.id === id);
  const j = i + delta;
  if (i < 0 || j < 0 || j >= sc.layers.length) return;
  change(() => { [sc.layers[i], sc.layers[j]] = [sc.layers[j], sc.layers[i]]; });
}

// 全シーンに適用: ほかのシーンの同じ id のレイヤーへ、位置・大きさ・見た目を写す。
// 中身 (文言、動画の素材と開始時刻、キャラクターのポーズ) と、シーンごとの揺れは写さない。
const CONTENT_KEYS = new Set(['id', 'name', 'type', 'text', 'start', 'pose', 'bob', 'bobAmplitude']);
function applyToAll(id) {
  const src = layerById(id);
  if (!src) return;
  const updates = [], additions = [];
  state.project.scenes.forEach((sc, i) => {
    if (i === state.scene) return;
    const target = layerById(id, sc);
    if (target && target.type === src.type) updates.push(i);
    else if (!target && src.type !== 'video') additions.push(i);
  });
  if (!updates.length && !additions.length) { toast('ほかのシーンに当てはまるレイヤーがありません'); return; }
  const lines = [];
  if (updates.length) lines.push(`位置・大きさ・見た目を合わせる: ${updates.map(sceneLabel).join('、')}`);
  if (additions.length) lines.push(`同じレイヤーを新しく足す: ${additions.map(sceneLabel).join('、')}`);
  lines.push('(文言、動画の素材と開始時刻、ポーズ、揺れは写しません。元に戻すで取り消せます)');
  if (!confirm(`「${src.name || src.id}」を全シーンに適用します。\n\n${lines.join('\n')}`)) return;
  change(() => {
    for (const i of updates) {
      const target = layerById(id, state.project.scenes[i]);
      for (const [k, v] of Object.entries(src)) if (!CONTENT_KEYS.has(k) && !(src.type === 'video' && k === 'src')) target[k] = clone(v);
    }
    for (const i of additions) {
      const layers = state.project.scenes[i].layers;
      const at = Math.min(scene().layers.indexOf(src), layers.length);
      layers.splice(at, 0, clone(src));
    }
  });
  toast('全シーンに適用しました');
}

// ---------------------------------------------------------------- ドラッグ

function stagePoint(e) {
  const r = $('#stage').getBoundingClientRect();
  return { x: (e.clientX - r.left) / state.scale, y: (e.clientY - r.top) / state.scale };
}

function startMove(e, id) {
  if (e.button !== 0 || state.playing) return;
  e.preventDefault();
  if (state.selected !== id) select(id);
  const layer = layerById(id);
  const p = stagePoint(e);
  state.drag = { kind: 'move', id, before: snapshot(), p0: p, x0: layer.x, y0: layer.y, moved: false };
  $('#stage').setPointerCapture(e.pointerId);
}

function startScale(e, handle) {
  const layer = selectedLayer();
  if (!layer || e.button !== 0 || state.playing) return;
  e.preventDefault();
  e.stopPropagation();
  const box0 = layerBox(layer);
  const anchor = {
    x: handle.includes('w') ? box0.x + box0.w : box0.x,
    y: handle.includes('n') ? box0.y + box0.h : box0.y,
  };
  state.drag = { kind: 'scale', id: layer.id, handle, before: snapshot(), p0: stagePoint(e), box0, anchor, orig: clone(layer), f: 1, moved: false };
  $('#stage').setPointerCapture(e.pointerId);
}

function onPointerMove(e) {
  const d = state.drag;
  if (!d) return;
  const layer = layerById(d.id);
  if (!layer) return;
  const p = stagePoint(e);
  const dx = p.x - d.p0.x, dy = p.y - d.p0.y;
  if (Math.abs(dx) + Math.abs(dy) > 0.5) d.moved = true;
  if (d.kind === 'move') {
    layer.x = Math.round(d.x0 + dx);
    layer.y = Math.round(d.y0 + dy);
  } else {
    const sx = d.handle.includes('e') ? 1 : -1, sy = d.handle.includes('s') ? 1 : -1;
    const fx = (d.box0.w + sx * dx) / d.box0.w, fy = (d.box0.h + sy * dy) / d.box0.h;
    const minF = 8 / Math.min(d.box0.w, d.box0.h);
    d.f = Math.max(minF, (fx + fy) / 2);
    applyScale(layer, d.orig, d.f, d.anchor);
  }
  updateLayerElement(layer);
  updateSelection();
  syncField('x', layer.x); syncField('y', layer.y);
  for (const k of ['width', 'height', 'fontSize']) if (k in layer) syncField(k, layer[k]);
  renderToolbar();
}

// 縦横比を保ったまま、反対側の角 (anchor) を止めて f 倍にする
function applyScale(layer, orig, f, anchor) {
  layer.x = Math.round(anchor.x + (orig.x - anchor.x) * f);
  layer.y = Math.round(anchor.y + (orig.y - anchor.y) * f);
  if (layer.type === 'text') layer.fontSize = Math.max(4, Math.round(orig.fontSize * f));
  else if (layer.type === 'character') layer.height = Math.max(20, Math.round(orig.height * f));
  else {
    layer.width = Math.max(1, Math.round(orig.width * f));
    layer.height = Math.max(1, Math.round(orig.height * f));
  }
}

function onPointerUp() {
  const d = state.drag;
  if (!d) return;
  state.drag = null;
  if (d.moved && pushHistory(d.before)) committed();
  else { renderStage(); renderProps(); }
}

// ---------------------------------------------------------------- 再生

function togglePlay() { if (state.playing) stopPlay(); else startPlay(); }

function startPlay() {
  const sc = scene();
  const videos = sc.layers.filter((l) => l.type === 'video' && l.visible !== false)
    .map((l) => ({ layer: l, el: state.els.get(elKey(l)) && state.els.get(elKey(l)).querySelector('video') }))
    .filter((v) => v.el);
  videos.forEach((v, i) => {
    v.el.currentTime = v.layer.start;
    v.el.muted = i !== 0; // 書き出しと同じく、最初のゲーム映像の音だけを出す
    v.el.volume = state.info.gameVolume;
    v.el.play().catch((e) => toast(`再生できません: ${e.message}`, true));
  });
  // このシーンの間に話し始める台詞を、同じ時刻に鳴らす
  const voices = voiceLines().filter((l) => l.start >= sc.start && l.start < sc.start + sc.duration && l.text.trim())
    .map((l) => ({ at: l.start - sc.start, audio: new Audio(voiceUrl(l.text)), started: false }));
  state.playing = { t0: performance.now(), videos, voices, sceneIndex: state.scene };
  renderToolbar();
  requestAnimationFrame(tick);
}

function tick(now) {
  const p = state.playing;
  if (!p) return;
  const sc = scene();
  // ゲーム映像があれば、その再生位置を時計にする (読み込み待ちの間に揺れや尺がずれないように)
  const lead = p.videos[0];
  const t = lead ? Math.max(0, lead.el.currentTime - lead.layer.start) : (now - p.t0) / 1000;
  if (t >= sc.duration || (lead && lead.el.ended)) { stopPlay(); return; }
  for (const l of sc.layers) {
    if (l.type !== 'character' || l.visible === false) continue;
    const el = state.els.get(elKey(l));
    const amp = l.bob !== false ? (l.bobAmplitude ?? 4) : 0;
    if (el) el.style.transform = `translateY(${amp * Math.sin(2 * Math.PI * t * state.info.bobHz)}px)`;
  }
  for (const v of p.voices) {
    if (!v.started && t >= v.at) { v.started = true; v.audio.play().catch(() => {}); }
  }
  $('#playTime').textContent = `${t.toFixed(1)} / ${sc.duration} 秒`;
  requestAnimationFrame(tick);
}

function stopPlay() {
  const p = state.playing;
  if (!p) return;
  state.playing = null;
  for (const v of p.videos) { v.el.muted = true; seekVideo(v.el, v.layer.start); }
  for (const v of p.voices) v.audio.pause();
  for (const el of state.els.values()) el.style.transform = '';
  $('#playTime').textContent = '';
  renderToolbar();
}

// ---------------------------------------------------------------- 保存と読み込み

async function save() {
  stopPlay();
  const r = await api('POST', '/api/project', state.project);
  if (!r.ok) {
    if (r.data.problems) { state.problems = r.data.problems; renderProblems(); }
    toast(`${r.data.error}${r.data.problems ? ` (${r.data.problems.length} 件。左の「問題」を見てください)` : ''}`, true);
    return false;
  }
  state.saved = snapshot();
  state.problems = [];
  renderAll();
  toast(`保存しました: ${r.data.path}`);
  return true;
}

async function openProject(name) {
  const r = await api('GET', `/api/project?name=${encodeURIComponent(name)}`);
  if (!r.ok) { toast(r.data.error, true); return; }
  stopPlay();
  state.name = name;
  state.project = r.data.project;
  state.saved = snapshot();
  state.undo = []; state.redo = [];
  state.scene = 0; state.selected = null;
  $('#layers').replaceChildren();
  state.els.clear();
  history.replaceState(null, '', `?project=${encodeURIComponent(name)}`);
  if (!Array.isArray(state.project.scenes) || state.project.scenes.length !== state.info.scenes.length) {
    toast('プロジェクトのシーンの数が合いません。JSON を確かめてください', true);
    return;
  }
  loadBackground();
  renderAll();
  scheduleValidate();
}

// ---------------------------------------------------------------- 書き出し

function showExport(...content) {
  $('#exportContent').replaceChildren(...content);
  $('#exportPanel').hidden = false;
}

async function startExport() {
  stopPlay();
  showExport(h('p', {}, '確かめています…'));
  if (isDirty()) {
    if (!confirm('保存していない変更があります。保存してから書き出します。')) { $('#exportPanel').hidden = true; return; }
    if (!(await save())) {
      showExport(h('p', { class: 'err' }, '保存できませんでした。左の「問題」を直してから、もう一度書き出してください。'),
        problemList(state.problems));
      return;
    }
  }
  const vv = await api('GET', '/api/voicevox');
  if (!vv.ok || !vv.data.ok) {
    showExport(h('p', { class: 'err' }, (vv.data && vv.data.message) || 'VOICEVOX を確かめられません'),
      h('p', {}, (vv.data && vv.data.hint) || ''), h('p', { class: 'muted small' }, '書き出しは始めていません。編集内容はそのままです。'));
    return;
  }
  const r = await api('POST', '/api/export', { name: state.name });
  if (!r.ok) {
    showExport(h('p', { class: 'err' }, r.data.error), r.data.hint ? h('p', {}, r.data.hint) : null, problemList(r.data.problems || []),
      h('p', { class: 'muted small' }, '書き出しは始めていません。編集内容はそのままです。'));
    return;
  }
  pollExport();
}

function problemList(problems) {
  return problems.length ? h('ul', { class: 'problems' }, problems.map((p) => h('li', {}, p.message))) : null;
}

async function pollExport() {
  clearTimeout(state.exportTimer);
  const r = await api('GET', '/api/export/status');
  const job = r.data || {};
  if (job.state === 'idle') return;
  const out = [];
  if (job.state === 'running') {
    out.push(h('p', {}, `書き出し中: ${job.message}`),
      h('div', { class: 'progress' }, h('div', { style: `width:${Math.round((job.fraction || 0) * 100)}%` })),
      h('p', { class: 'muted small' }, `${Math.round((job.fraction || 0) * 100)}%。画面はこのまま編集を続けても構いません (書き出すのは保存した内容です)。`));
    state.exportTimer = setTimeout(pollExport, 1000);
  } else if (job.state === 'done') {
    const res = job.result;
    const allOk = res.checks.every((c) => c.ok);
    out.push(h('p', { class: allOk ? 'ok' : 'err' }, allOk ? '書き出しました。確認はすべて通りました。' : '書き出しましたが、確認で問題が見つかりました。'),
      h('div', { class: 'readonly' }, h('table', {},
        h('tr', {}, h('td', {}, '保存場所'), h('td', {}, h('code', {}, res.path))),
        h('tr', {}, h('td', {}, '尺'), h('td', {}, `映像 ${res.duration.toFixed(2)} 秒 / 音声 ${res.audioDuration.toFixed(2)} 秒`)),
        h('tr', {}, h('td', {}, '解像度'), h('td', {}, `${res.width}×${res.height}`)))),
      h('h3', {}, '書き出し後の確認'),
      h('ul', { class: 'checks' }, res.checks.map((c) => h('li', { class: c.ok ? 'ok' : 'err' }, `${c.ok ? 'OK' : 'NG'}  ${c.name}: ${c.detail}`))));
  } else if (job.state === 'failed') {
    out.push(h('p', { class: 'err' }, `書き出しに失敗しました: ${job.error}`),
      job.hint ? h('p', {}, `直し方: ${job.hint}`) : null, problemList(job.problems || []),
      h('p', { class: 'muted small' }, '編集内容と保存したプロジェクトはそのままです。'));
  }
  if (job.log && job.log.length) {
    out.push(h('details', {}, h('summary', { class: 'muted small' }, '経過'), h('ol', { class: 'log' }, job.log.map((m) => h('li', {}, m)))));
  }
  showExport(...out);
}

// ---------------------------------------------------------------- 起動

function bindGlobal() {
  $('#saveBtn').onclick = save;
  $('#undoBtn').onclick = undo;
  $('#redoBtn').onclick = redo;
  $('#playBtn').onclick = togglePlay;
  $('#exportBtn').onclick = startExport;
  $('#exportClose').onclick = () => { $('#exportPanel').hidden = true; };
  $('#safeToggle').onchange = renderStage;
  $('#outlineToggle').onchange = renderStage;
  $('#projectSelect').onchange = (e) => {
    if (isDirty() && !confirm('保存していない変更は失われます。開きますか？')) { e.target.value = state.name; return; }
    openProject(e.target.value);
  };
  const stage = $('#stage');
  stage.addEventListener('pointermove', onPointerMove);
  stage.addEventListener('pointerup', onPointerUp);
  stage.addEventListener('pointercancel', onPointerUp);
  stage.addEventListener('pointerdown', (e) => {
    if (!e.target.closest('.layer') && !e.target.closest('.handle') && !state.playing) select(null);
  });
  for (const hd of document.querySelectorAll('#selection .handle')) {
    hd.addEventListener('pointerdown', (e) => startScale(e, hd.dataset.handle));
  }
  window.addEventListener('resize', fitStage);
  new ResizeObserver(fitStage).observe($('#viewport'));
  window.addEventListener('beforeunload', (e) => { if (isDirty()) { e.preventDefault(); e.returnValue = ''; } });
  document.addEventListener('keydown', onKey);
}

function onKey(e) {
  const typing = /^(INPUT|TEXTAREA|SELECT)$/.test(document.activeElement && document.activeElement.tagName);
  const mod = e.ctrlKey || e.metaKey;
  if (mod && e.key.toLowerCase() === 's') { e.preventDefault(); save(); return; }
  if (typing) return;
  if (mod && e.key.toLowerCase() === 'z') { e.preventDefault(); if (e.shiftKey) redo(); else undo(); return; }
  if (mod && e.key.toLowerCase() === 'y') { e.preventDefault(); redo(); return; }
  if (e.key === ' ') { e.preventDefault(); togglePlay(); return; }
  const layer = selectedLayer();
  if (!layer) return;
  if (e.key === 'Delete' || e.key === 'Backspace') { e.preventDefault(); deleteLayer(layer.id); return; }
  const step = e.shiftKey ? 10 : 1;
  const moves = { ArrowLeft: [-step, 0], ArrowRight: [step, 0], ArrowUp: [0, -step], ArrowDown: [0, step] };
  if (moves[e.key]) {
    e.preventDefault();
    change(() => { layer.x += moves[e.key][0]; layer.y += moves[e.key][1]; });
  }
}

async function init() {
  const [info, assets, projects] = await Promise.all([api('GET', '/api/info'), api('GET', '/api/assets'), api('GET', '/api/projects')]);
  if (!info.ok || !assets.ok || !projects.ok) {
    document.body.replaceChildren(h('p', { class: 'err', style: 'padding:20px' },
      (info.data && info.data.error) || (assets.data && assets.data.error) || 'サーバーに接続できません。promo/editor/server.py を起動してください'));
    return;
  }
  state.info = info.data;
  state.assets = assets.data;
  const names = projects.data.projects;
  const wanted = new URLSearchParams(location.search).get('project');
  const name = names.includes(wanted) ? wanted : (names.includes('character-promo') ? 'character-promo' : names[0]);
  $('#projectSelect').replaceChildren(...names.map((n) => h('option', { value: n, selected: n === name }, n)));
  bindGlobal();
  fitStage();
  if (!name) { toast('promo/editor/projects/ にプロジェクトがありません', true); return; }
  await openProject(name);
  pollExport();
}

// 画面の試験から状態を見られるようにする
window.promoEditor = { state, select, selectScene, undo, redo, save, addLayer, deleteLayer, duplicateLayer, applyToAll, layerBox, isDirty };

init();
