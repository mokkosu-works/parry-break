#!/usr/bin/env python3
"""週次: YouTube アナリティクスを取得して、集計 (事実だけ) を作る。読み取り専用。

  python3 weekly.py fetch              # 取得して data/raw/<日付>/ に保存
  python3 weekly.py facts [日付]       # 取得済みの生データ + 投稿の記録から、data/facts/<日付>.md/.json を作る
  python3 weekly.py run                # fetch → facts

報告の対象は「3 日前までの 7 日間」(数字の確定が遅れるため) と、その前の 7 日間。
動画の ID・パターン名・冒頭の種類は、バックアップ済みの promo/records から自動で結びつける。
"""
import csv, datetime, json, pathlib, re, statistics, sys

import yt_analytics as y

DATA = y.BASE / "data"
SNAP_ROOT = pathlib.Path("/srv/backup/parry-break")
LAG = 3
M_VIDEO = "views,engagedViews,averageViewDuration,averageViewPercentage,estimatedMinutesWatched,likes,shares,comments,subscribersGained"
M_CHANNEL = M_VIDEO
MIN_VIEWS = 100  # これ未満の動画は、率の平均から除く (データ不足)


def q(tok, start, end, **p):
    r = y.api_get(y.ANALYTICS, {"ids": "channel==MINE", "startDate": start.isoformat(), "endDate": end.isoformat(), **p}, tok)
    if "_error" in r:
        sys.exit(f"取得に失敗 {p}: {r}")
    return {"columns": [h["name"] for h in r["columnHeaders"]], "rows": r.get("rows", [])}


def fetch():
    tok = y.access_token()
    today = datetime.date.today()
    end = today - datetime.timedelta(days=LAG)
    w0 = (end - datetime.timedelta(days=6), end)
    w1 = (end - datetime.timedelta(days=13), end - datetime.timedelta(days=7))
    w28 = (end - datetime.timedelta(days=27), end)
    out = DATA / "raw" / today.isoformat()
    out.mkdir(parents=True, exist_ok=True)
    raw = {"fetched": datetime.datetime.now().isoformat(timespec="seconds"),
           "windows": {"w0": [str(d) for d in w0], "w1": [str(d) for d in w1], "w28": [str(d) for d in w28]}}
    raw["channel_w0"] = q(tok, *w0, metrics=M_CHANNEL)
    raw["channel_w1"] = q(tok, *w1, metrics=M_CHANNEL)
    raw["channel_by_type_w0"] = q(tok, *w0, dimensions="creatorContentType", metrics="views,engagedViews,averageViewDuration,averageViewPercentage")
    raw["channel_daily_w28"] = q(tok, *w28, dimensions="day", metrics="views,estimatedMinutesWatched,subscribersGained", sort="day")
    for k, w in (("videos_w0", w0), ("videos_w1", w1), ("videos_w28", w28)):
        raw[k] = q(tok, *w, dimensions="video", metrics=M_VIDEO, sort="-views", maxResults=200)
    raw["retention"] = {}
    for row in raw["videos_w28"]["rows"]:
        vid, views = row[0], row[1]
        if views < 20:
            continue
        raw["retention"][vid] = q(tok, *w28, dimensions="elapsedVideoTimeRatio",
                                  metrics="audienceWatchRatio,relativeRetentionPerformance",
                                  filters=f"video=={vid}", sort="elapsedVideoTimeRatio")
    raw["meta"] = {}
    ids = [r[0] for r in raw["videos_w28"]["rows"]]
    for i in range(0, len(ids), 50):
        r = y.api_get(y.DATA_API + "/videos", {"part": "snippet,contentDetails", "id": ",".join(ids[i:i + 50])}, tok)
        if "_error" in r:
            sys.exit(f"動画のタイトル取得に失敗: {r}")
        for it in r.get("items", []):
            pub = datetime.datetime.fromisoformat(it["snippet"]["publishedAt"].replace("Z", "+00:00"))
            jst = (pub + datetime.timedelta(hours=9)).date().isoformat()
            raw["meta"][it["id"]] = {"title": it["snippet"]["title"].strip(), "published_jst": jst}
    (out / "raw.json").write_text(json.dumps(raw, ensure_ascii=False))
    print(f"保存: {out / 'raw.json'}  (動画 {len(raw['videos_w28']['rows'])} 本、維持率 {len(raw['retention'])} 本)")
    return out.name


# ---------------------------------------------------------------- 集計
def latest_snapshot():
    ok = sorted(d for d in SNAP_ROOT.iterdir() if re.fullmatch(r"\d{4}-\d{2}-\d{2}", d.name)
                and (d / "promo/records/videos.csv").exists()) if SNAP_ROOT.exists() else []
    return ok[-1] if ok else None


def read_csv(p):
    with open(p, encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def load_records():
    """videos.csv の行を (タイトル, 投稿日) で引けるようにする (import_studio.py と同じ結びつけ方)。"""
    snap = latest_snapshot()
    if not snap:
        return {}, None
    by_key = {}
    for r in read_csv(snap / "promo/records/videos.csv"):
        by_key[(r["タイトル"].strip(), r["投稿日"].strip())] = {
            "id": r["id"], "pattern": r.get("パターン名", ""), "hook": r.get("冒頭の種類", ""),
            "title": r["タイトル"].strip(), "posted": r["投稿日"].strip(),
            "length": float(r["長さ(秒)"]) if r.get("長さ(秒)") not in (None, "") else None}
    return by_key, snap.name


def rows_to_dict(t, key=0):
    cols = t["columns"]
    return {r[key]: dict(zip(cols, r)) for r in t["rows"]}


def pct_change(a, b):
    if b in (0, None):
        return "-" if a in (0, None) else "新規"
    return f"{(a - b) / b * 100:+.0f}%"


def retention_points(curve, length):
    """3 秒時点と最後の、audienceWatchRatio。1 を超える値は、見直し・ループがある。"""
    if not curve or not curve["rows"]:
        return None, None, None, None
    by = {round(r[0], 2): r for r in curve["rows"]}
    first = by.get(0.01, curve["rows"][0])[1]
    last = curve["rows"][-1][1]
    rel = statistics.mean(r[2] for r in curve["rows"])
    at3 = None
    if length:
        idx = min(1.0, max(0.01, round(3 / length, 2)))
        at3 = by.get(idx, [None, None])[1]
    return at3, first, last, rel


def facts(day=None):
    day = day or max(p.name for p in (DATA / "raw").iterdir())
    raw = json.loads((DATA / "raw" / day / "raw.json").read_text())
    rec, snap = load_records()
    W = raw["windows"]
    v0, v1, v28 = (rows_to_dict(raw[k]) for k in ("videos_w0", "videos_w1", "videos_w28"))

    def total(vs):
        rows = list(vs.values())
        t = {k: sum(r.get(k, 0) for r in rows) for k in ("views", "engagedViews", "estimatedMinutesWatched", "likes", "shares", "comments", "subscribersGained")}
        n = t["views"]
        t["averageViewDuration"] = sum(r["averageViewDuration"] * r["views"] for r in rows) / n if n else 0
        t["averageViewPercentage"] = sum(r["averageViewPercentage"] * r["views"] for r in rows) / n if n else 0
        return t
    c0, c1 = total(v0), total(v1)
    api0 = dict(zip(raw["channel_w0"]["columns"], (raw["channel_w0"]["rows"] or [[0] * 9])[0]))
    api1 = dict(zip(raw["channel_w1"]["columns"], (raw["channel_w1"]["rows"] or [[0] * 9])[0]))
    def lookup(vid):
        m = raw.get("meta", {}).get(vid)
        return rec.get((m["title"], m["published_jst"]), {}) if m else {}
    L = []
    L.append(f"# YouTube 週次の事実 (取得日 {day})")
    L.append(f"- 対象の週: {W['w0'][0]} 〜 {W['w0'][1]} / 比較する前の週: {W['w1'][0]} 〜 {W['w1'][1]} (数字の確定が遅れるため、取得日の 3 日前まで)")
    L.append(f"- 動画の ID・パターン・冒頭の結びつけに使った記録: バックアップ {snap or 'なし'}")
    L.append(f"- 再生数が {MIN_VIEWS} 未満の動画は、率の平均から除く (データ不足)。audienceWatchRatio が 1 を超えるのは、見直しやループがあるため。")
    L.append("")
    L.append("## チャンネル全体 (動画別の合計。平均は再生数で重みづけ)")
    L.append("| 指標 | 今週 | 前週 | 変化 |")
    L.append("|---|---|---|---|")
    for k, lab in (("views", "再生数"), ("engagedViews", "エンゲージ視聴"), ("estimatedMinutesWatched", "視聴時間(分)"),
                   ("averageViewDuration", "平均視聴時間(秒)"), ("averageViewPercentage", "平均視聴割合(%)"),
                   ("likes", "いいね"), ("shares", "シェア"), ("comments", "コメント"), ("subscribersGained", "登録者の増加")):
        a, b = c0.get(k, 0), c1.get(k, 0)
        L.append(f"| {lab} | {a:g} | {b:g} | {pct_change(a, b)} |")
    diff = []
    for lab, a_, b_ in (("今週", api0, c0), ("前週", api1, c1)):
        if a_.get("views", 0) != b_["views"]:
            diff.append(f"{lab}: API のチャンネル合計 {a_.get('views', 0):g} 回 / 動画別の合計 {b_['views']:g} 回 (視聴時間 {a_.get('estimatedMinutesWatched', 0):g} 分 / {b_['estimatedMinutesWatched']:g} 分)")
    if diff:
        L.append("")
        L.append("注意: API のチャンネル合計と、動画別の合計が一致しない週がある (削除・非公開の動画などが入っている可能性。原因は未確認)。この表は動画別の合計を使う。 " + "、".join(diff))
    bt = {r[0]: r for r in raw["channel_by_type_w0"]["rows"]}
    if bt:
        L.append("")
        L.append("今週の種類別 (再生数 / エンゲージ視聴 / 平均視聴時間 / 平均視聴割合): " +
                 "、".join(f"{k}: {r[1]} / {r[2]} / {r[3]}秒 / {r[4]:.1f}%" for k, r in bt.items()))
    L.append("")
    L.append("## 動画別 (直近 28 日に再生のあったもの。今週の再生数順)")
    L.append("| ID | タイトル | パターン | 冒頭 | 投稿日 | 今週 | 前週 | 28日 | 平均視聴割合(%) | 平均視聴(秒) | エンゲージ率 | 3秒時点 | 終点 | 備考 |")
    L.append("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
    data_rows, jsonrows = [], []
    for vid, m in sorted(v28.items(), key=lambda kv: -(v0.get(kv[0], {}).get("views", 0))):
        r = lookup(vid)
        w0v, w1v = v0.get(vid, {}).get("views", 0), v1.get(vid, {}).get("views", 0)
        eng = m["engagedViews"] / m["views"] * 100 if m["views"] else 0
        at3, first, last, rel = retention_points(raw["retention"].get(vid), r.get("length"))
        note = "データ不足" if m["views"] < MIN_VIEWS else ""
        title = r.get("title") or raw.get("meta", {}).get(vid, {}).get("title", "")
        if not r:
            note = (note + " 記録なし(" + raw.get("meta", {}).get(vid, {}).get("published_jst", "?") + "公開)").strip()
        f = lambda x: "-" if x is None else f"{x:.2f}"
        L.append(f"| {r.get('id', vid)} | {title[:22]} | {r.get('pattern', '')} | {r.get('hook', '')} | {r.get('posted', '')} | "
                 f"{w0v} | {w1v} | {m['views']} | {m['averageViewPercentage']:.1f} | {m['averageViewDuration']:g} | {eng:.0f}% | {f(at3)} | {f(last)} | {note} |")
        jsonrows.append({"id": r.get("id"), "youtube_id": vid, "pattern": r.get("pattern"), "hook": r.get("hook"),
                         "views_w0": w0v, "views_w1": w1v, "views_28d": m["views"], "avg_view_pct": m["averageViewPercentage"],
                         "avg_view_sec": m["averageViewDuration"], "engaged_rate": eng, "ret_at_3s": at3, "ret_end": last,
                         "insufficient": m["views"] < MIN_VIEWS})
        if m["views"] >= MIN_VIEWS and r:
            data_rows.append((r, m, at3, last, eng))
    for key, lab in (("pattern", "パターンごと"), ("hook", "冒頭の種類ごと")):
        groups = {}
        for r, m, at3, last, eng in data_rows:
            groups.setdefault(r.get(key) or "(不明)", []).append((m, at3, last, eng))
        if not groups:
            continue
        L.append("")
        L.append(f"## {lab} (データ十分な動画のみ、28 日)")
        L.append("| 区分 | 本数 | 再生数の中央値 | 平均視聴割合の平均(%) | エンゲージ率の平均 | 3秒時点の平均 |")
        L.append("|---|---|---|---|---|---|")
        for g, items in sorted(groups.items()):
            at3s = [i[1] for i in items if i[1] is not None]
            L.append(f"| {g} | {len(items)} | {statistics.median(i[0]['views'] for i in items):g} | "
                     f"{statistics.mean(i[0]['averageViewPercentage'] for i in items):.1f} | "
                     f"{statistics.mean(i[3] for i in items):.0f}% | {('%.2f' % statistics.mean(at3s)) if at3s else '-'} |")
    out = DATA / "facts"
    out.mkdir(parents=True, exist_ok=True)
    (out / f"{day}.md").write_text("\n".join(L) + "\n")
    (out / f"{day}.json").write_text(json.dumps({"day": day, "windows": W, "channel_w0": c0, "channel_w1": c1, "videos": jsonrows},
                                                ensure_ascii=False, indent=1))
    print(f"保存: {out / (day + '.md')}")
    return out / f"{day}.md"


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "fetch":
        fetch()
    elif cmd == "facts":
        facts(sys.argv[2] if len(sys.argv) > 2 else None)
    elif cmd == "run":
        facts(fetch())
    else:
        sys.exit(__doc__)
