#!/usr/bin/env python3
"""時系列ストア。日次の事実を、月ごとの JSON Lines に upsert する (標準ライブラリだけ)。

  store/<source>/YYYY-MM.jsonl     1 行 = 1 日 1 指標。キーは (source, metric, entity, date)
  store/status.jsonl               取得の状況 (source ごとに 1 日 1 行。ok / ng / no_data)

行の形: {"source": "youtube", "metric": "views", "entity": "VIDEO_ID", "date": "2026-11-10", "value": 123}
  entity は「何の数字か」(動画 ID、パッケージ名、"channel" など)。value は数値。
ファイルは、キー順に並べて書く (同じ内容なら同じバイト列になり、git の差分が最小になる)。
データ用の非公開リポジトリの clone / commit / push は、ワークフロー側で行う (ここは、ファイルだけを扱う)。
"""
import datetime, json, os, pathlib, tempfile

SOURCES = ("youtube", "play", "appstore")
_FIELDS = ("source", "metric", "entity", "date", "value")


def _key(r):
    return (r["source"], r["metric"], r["entity"], r["date"])


def validate(r):
    """壊れた行をストアに入れない。値は有限の数値だけ。"""
    if not isinstance(r, dict) or any(f not in r for f in _FIELDS):
        raise ValueError(f"行の形が違う: {r!r}")
    if r["source"] not in SOURCES:
        raise ValueError(f"source が不正: {r['source']!r}")
    for f in ("metric", "entity"):
        if not isinstance(r[f], str) or not r[f]:
            raise ValueError(f"{f} が空: {r!r}")
    datetime.date.fromisoformat(r["date"])  # 不正なら ValueError
    v = r["value"]
    if isinstance(v, bool) or not isinstance(v, (int, float)) or v != v or v in (float("inf"), float("-inf")):
        raise ValueError(f"value が数値でない: {r!r}")


def _path(root, source, month):
    return pathlib.Path(root) / "store" / source / f"{month}.jsonl"


def _read(p):
    if not p.exists():
        return {}
    out = {}
    for n, line in enumerate(p.read_text(encoding="utf-8").splitlines(), 1):
        if line.strip():
            try:
                r = json.loads(line)
                out[_key(r)] = r
            except (ValueError, KeyError) as e:
                raise ValueError(f"{p}:{n} が読めない: {e}") from e  # 壊れたファイルを黙って上書きしない
    return out


def _write(p, rows):
    p.parent.mkdir(parents=True, exist_ok=True)
    text = "".join(json.dumps({f: r[f] for f in _FIELDS}, ensure_ascii=False, separators=(",", ":")) + "\n"
                   for _, r in sorted(rows.items()))
    fd, tmp = tempfile.mkstemp(dir=p.parent, suffix=".tmp")  # 途中で落ちても、元のファイルを壊さない
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(text)
    os.chmod(tmp, 0o644)  # mkstemp は 600 で作るので、普通のファイルの権限に戻す
    os.replace(tmp, p)


def upsert(root, rows):
    """行を、キーで上書きして保存する。入れた行数 (新規, 更新) を返す。1 行でも不正なら、何も書かない。"""
    rows = list(rows)
    for r in rows:
        validate(r)
    by_file = {}
    for r in rows:
        by_file.setdefault((r["source"], r["date"][:7]), []).append(r)
    new = upd = 0
    loaded = {k: _read(_path(root, *k)) for k in by_file}  # 先に全部読む (読めないファイルがあれば、ここで止まる)
    for k, rs in by_file.items():
        cur = loaded[k]
        for r in rs:
            if _key(r) in cur:
                upd += cur[_key(r)]["value"] != r["value"]
            else:
                new += 1
            cur[_key(r)] = r
        _write(_path(root, *k), cur)
    return new, upd


def load(root, source, start=None, end=None, metric=None, entity=None):
    """期間 (両端を含む。ISO の日付文字列) で、行を読む。日付順。"""
    d = pathlib.Path(root) / "store" / source
    rows = []
    for p in sorted(d.glob("*.jsonl")) if d.exists() else []:
        for r in _read(p).values():
            if (start and r["date"] < start) or (end and r["date"] > end):
                continue
            if (metric and r["metric"] != metric) or (entity and r["entity"] != entity):
                continue
            rows.append(r)
    return sorted(rows, key=lambda r: (r["date"], r["metric"], r["entity"]))


def record_status(root, source, date, state, note=""):
    """取得の状況を 1 日 1 source 1 行で残す (同じ日の再実行は上書き)。state: ok / ng / no_data"""
    if state not in ("ok", "ng", "no_data"):
        raise ValueError(f"state が不正: {state}")
    p = pathlib.Path(root) / "store" / "status.jsonl"
    cur = {}
    if p.exists():
        for line in p.read_text(encoding="utf-8").splitlines():
            if line.strip():
                r = json.loads(line)
                cur[(r["source"], r["date"])] = r
    cur[(source, date)] = {"source": source, "date": date, "state": state, "note": note[:200]}
    p.parent.mkdir(parents=True, exist_ok=True)
    text = "".join(json.dumps(r, ensure_ascii=False, separators=(",", ":")) + "\n" for _, r in sorted(cur.items()))
    fd, tmp = tempfile.mkstemp(dir=p.parent, suffix=".tmp")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(text)
    os.chmod(tmp, 0o644)  # mkstemp は 600 で作るので、普通のファイルの権限に戻す
    os.replace(tmp, p)


def update_meta(root, name, entries):
    """行にできない付随情報 (動画のタイトルなど) を、store/meta/<name>.json に、キーで上書きして保存する。"""
    p = pathlib.Path(root) / "store" / "meta" / f"{name}.json"
    cur = json.loads(p.read_text(encoding="utf-8")) if p.exists() else {}
    cur.update(entries)
    p.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=p.parent, suffix=".tmp")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(cur, f, ensure_ascii=False, indent=1, sort_keys=True)
        f.write("\n")
    os.chmod(tmp, 0o644)  # mkstemp は 600 で作るので、普通のファイルの権限に戻す
    os.replace(tmp, p)
    return cur


def read_meta(root, name):
    p = pathlib.Path(root) / "store" / "meta" / f"{name}.json"
    return json.loads(p.read_text(encoding="utf-8")) if p.exists() else {}
