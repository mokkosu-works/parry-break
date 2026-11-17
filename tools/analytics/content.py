"""動画の投稿内容 (何を、どう見せたか) を promo/ の記録から集める。AI は使わない。

  records/videos.csv           ID・パターン名・冒頭の種類・タイトル・説明文・投稿日・長さ
  records/youtube_uploads.csv  ID と YouTube の動画 ID・公開予約の日時 (あれば、結びつけはこれを優先する)
  build/specs/spec.<パターン>.json  冒頭の字幕 (A/B/C)・本編の字幕・ハッシュタグ

返すのは {管理ID: 内容} と {YouTube の動画 ID: 管理ID}。記録が欠けていても、分かる項目だけで返す。
"""
import csv, datetime, json, pathlib

HOOK_LABEL = {"A": "惜しい失敗", "B": "見栄えのする場面", "C": "結果の瞬間"}
WEEKDAY = "月火水木金土日"


def _csv(p):
    if not p.exists():
        return []
    with open(p, encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def _kind(pattern, has_spec):
    if has_spec:
        return "プレイ動画"
    if pattern.startswith("character-promo"):
        return "キャラクター動画"
    return "その他"


def load(promo_dir):
    promo = pathlib.Path(promo_dir) if promo_dir else None
    if not promo or not promo.exists():
        return {}, {}
    uploads = {r["id"]: r for r in _csv(promo / "records/youtube_uploads.csv") if r.get("id")}
    catalog, by_yt = {}, {}
    for r in _csv(promo / "records/videos.csv"):
        vid = (r.get("id") or "").strip()
        if not vid:
            continue
        pattern, hook = (r.get("パターン名") or "").strip(), (r.get("冒頭の種類") or "").strip()
        sp = promo / f"build/specs/spec.{pattern}.json"
        spec = json.loads(sp.read_text(encoding="utf-8")) if sp.exists() else {}
        up = uploads.get(vid, {})
        publish_at = (up.get("公開予約") or "").strip() or None
        d = None
        try:
            d = datetime.datetime.fromisoformat(publish_at).date() if publish_at else datetime.date.fromisoformat(r.get("投稿日", "").strip())
        except ValueError:
            pass
        try:
            length = float(r["長さ(秒)"]) if r.get("長さ(秒)") else None
        except ValueError:
            length = None
        c = {
            "id": vid, "kind": _kind(pattern, bool(spec)), "pattern": pattern or None,
            "hook": hook or None, "hook_label": HOOK_LABEL.get(hook),
            "hook_caption": ((spec.get("hooks") or {}).get(hook) or {}).get("caption"),
            "body_caption": (spec.get("body") or {}).get("caption"),
            "title": (r.get("タイトル") or "").strip() or spec.get("title"),
            "hashtags": spec.get("hashtags"),
            "length_sec": length, "posted": (r.get("投稿日") or "").strip() or None,
            "publish_at": publish_at, "weekday": WEEKDAY[d.weekday()] if d else None,
            "publish_hour": int(publish_at[11:13]) if publish_at and len(publish_at) >= 13 else None,
            "youtube_id": (up.get("動画ID") or "").strip() or None,
        }
        catalog[vid] = c
        if c["youtube_id"]:
            by_yt[c["youtube_id"]] = vid
    return catalog, by_yt


def match(catalog, by_yt, youtube_id, title, published):
    """YouTube の動画を、管理 ID の内容に結びつける。動画 ID が記録にあればそれ、なければ (タイトル, 投稿日)。"""
    if youtube_id in by_yt:
        return catalog[by_yt[youtube_id]]
    for c in catalog.values():
        if c["title"] == (title or "").strip() and c["posted"] == published:
            return c
    return None
