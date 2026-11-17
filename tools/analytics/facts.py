#!/usr/bin/env python3
"""分析の材料 (facts.json) を、ストアの時系列から、決まった規則で作る。AI は使わない。

  python3 facts.py --root <データ用リポジトリ> --promo promo [--date YYYY-MM-DD] [--out facts.json]

週は「取得日の 3 日前まで」を区切りにした 7 日ずつ (w0 = 今週、w1 = 前週 … w7)。数字の確定が遅れるため。
含めるもの: チャンネルの週ごとの推移 (8 週)、動画別の今週・前週・28 日、パターン・冒頭ごとの比較、Play の週ごとの推移、
動画ごとの伸び (公開日からの日数をそろえた累計) と投稿内容 (promo/ の記録)、取得の状況、要確認の判定 (alerts)。レビューの文面は、ストアにもここにも無い (件数と星だけ)。
"""
import argparse, datetime, json, pathlib, statistics, sys

import content, store

LAG = 3
WEEKS = 8
MIN_VIEWS = 100  # 28 日でこれ未満の動画は、率の比較に使わない (データ不足)
YT_SUM = ("views", "engagedViews", "estimatedMinutesWatched", "likes", "shares", "comments", "subscribersGained")
YT_WEIGHTED = ("averageViewDuration", "averageViewPercentage")  # 再生数で重みづけした平均


def windows(today, weeks=WEEKS):
    end = today - datetime.timedelta(days=LAG)
    return [(end - datetime.timedelta(days=7 * i + 6), end - datetime.timedelta(days=7 * i)) for i in range(weeks)]


def in_win(r, w):
    return w[0].isoformat() <= r["date"] <= w[1].isoformat()


def pct(a, b):
    if a is None or b is None:
        return None
    if b == 0:
        return None
    return round((a - b) / b * 100, 1)


def r2(x, n=2):
    return None if x is None else round(x, n)


# ---------------------------------------------------------------- YouTube
def yt_agg(rows, w):
    """日次の行 (1 つの entity) から、窓の合計と、再生数で重みづけした平均を作る。"""
    by_day = {}
    for r in rows:
        if in_win(r, w):
            by_day.setdefault(r["date"], {})[r["metric"]] = r["value"]
    # 取れていない指標は 0 ではなく None にする (0 と「データなし」を区別する)。再生数だけは 0 で埋める
    out = {k: (sum(d.get(k, 0) for d in by_day.values()) if k == "views" or any(k in d for d in by_day.values()) else None) for k in YT_SUM}
    v = out["views"]
    for k in YT_WEIGHTED:
        ds = [d for d in by_day.values() if k in d]
        vv = sum(d.get("views", 0) for d in ds)
        out[k] = r2(sum(d[k] * d.get("views", 0) for d in ds) / vv) if vv else None
    out["engagedRate"] = r2(out["engagedViews"] / v * 100, 1) if v and out["engagedViews"] is not None else None
    out["days"] = len(by_day)
    return out


GROWTH_DAYS = (1, 3, 7, 14, 28)  # 公開日を 1 日目として、この日数までの累計再生数を比べる (公開日の違いを消すため)
CURVE_DAYS = 28


def growth(daily, pub, as_of, covered):
    """1 本の動画の伸び。daily は {日付: 再生数}。covered はストアに公開日からのデータがあるか (無ければ累計は出さない)。"""
    if not pub:
        return {"age_days": None}
    p = datetime.date.fromisoformat(pub)
    age = (as_of - p).days + 1
    out = {"age_days": age, "covered_from_publish": covered}
    cum, curve = 0, []
    for i in range(min(max(age, 0), CURVE_DAYS)):
        cum += daily.get((p + datetime.timedelta(days=i)).isoformat(), 0)
        curve.append(cum)
    for n in GROWTH_DAYS:
        out[f"views_d{n}"] = curve[n - 1] if covered and age >= n and len(curve) >= n else None
    out["curve"] = curve if covered and curve else None
    total = sum(v for d, v in daily.items() if pub <= d <= as_of.isoformat())
    out["views_total"] = total if covered else None
    # 再生数が最も多かった日 (同じ数なら早い日)
    peak = min(((-v, d) for d, v in daily.items() if pub <= d <= as_of.isoformat()), default=(0, None))
    out["peak_day"] = (datetime.date.fromisoformat(peak[1]) - p).days + 1 if peak[1] and covered else None
    return out


def growth_state(g, views_w0):
    """規則で決める伸びの状態。公開 7 日以内は「公開直後」。"""
    age, total = g.get("age_days"), g.get("views_total")
    if age is None or total is None:
        return "不明"
    if age <= 7:
        return "公開直後"
    share = views_w0 / total if total else 0
    if share >= 0.3:
        return "伸び続けている"
    if share < 0.1 and age > 14:
        return "落ち着いた"
    return "ゆるやか"


def youtube_facts(root, ws, promo_dir):
    catalog, by_yt = content.load(promo_dir)
    rows = store.load(root, "youtube", start=ws[-1][0].isoformat(), end=ws[0][1].isoformat())
    by_ent = {}
    for r in rows:
        by_ent.setdefault(r["entity"], []).append(r)
    ch = by_ent.pop("channel", [])
    trend = []
    for i, w in enumerate(ws):
        a = yt_agg(ch, w)
        trend.append({"week": f"w{i}", "start": w[0].isoformat(), "end": w[1].isoformat(), **a})
    for i in range(len(trend) - 1):
        trend[i]["views_wow_pct"] = pct(trend[i]["views"], trend[i + 1]["views"])
    meta = store.read_meta(root, "youtube_videos")
    as_of = ws[0][1]
    w28 = (ws[3][0], as_of)
    # 伸びは、公開日からの全期間の日次の再生数で見る (8 週の窓に限らない)
    all_views = store.load(root, "youtube", metric="views")
    first_date = min((r["date"] for r in all_views if r["entity"] == "channel"), default=None)
    daily_by = {}
    for r in all_views:
        if r["entity"] != "channel":
            daily_by.setdefault(r["entity"], {})[r["date"]] = r["value"]
    latest_ret = {}
    for r in store.load(root, "youtube", start=(as_of - datetime.timedelta(days=60)).isoformat()):
        if r["metric"].startswith("retention_"):
            cur = latest_ret.setdefault(r["entity"], {})
            if r["date"] > cur.get("_date", ""):
                cur.clear()
                cur["_date"] = r["date"]
            if r["date"] == cur["_date"]:
                cur[r["metric"]] = r["value"]
    videos = []
    for vid in set(by_ent) | set(daily_by):
        vr = by_ent.get(vid, [])
        a0, a1, a28 = yt_agg(vr, ws[0]), yt_agg(vr, ws[1]), yt_agg(vr, w28)
        m = meta.get(vid, {})
        c = content.match(catalog, by_yt, vid, m.get("title"), m.get("published_jst")) or {}
        pub = m.get("published_jst") or (c.get("publish_at") or "")[:10] or None
        covered = bool(first_date and pub and first_date <= pub)
        g = growth(daily_by.get(vid, {}), pub, as_of, covered)
        ret = {k: v for k, v in latest_ret.get(vid, {}).items() if not k.startswith("_")}
        videos.append({
            "id": c.get("id"), "youtube_id": vid, "title": m.get("title") or c.get("title"), "published": pub,
            "content": {k: c.get(k) for k in ("kind", "pattern", "hook", "hook_label", "hook_caption", "body_caption",
                                               "length_sec", "weekday", "publish_hour", "hashtags")} if c else None,
            "pattern": c.get("pattern"), "hook": c.get("hook"), "kind": c.get("kind"),
            "length_sec": c.get("length_sec"),
            "views_w0": a0["views"], "views_w1": a1["views"], "views_28d": a28["views"],
            "avg_view_pct_28d": a28["averageViewPercentage"], "avg_view_sec_28d": a28["averageViewDuration"],
            "engaged_rate_28d": a28["engagedRate"], "likes_28d": a28["likes"], "shares_28d": a28["shares"],
            "subscribers_28d": a28["subscribersGained"],
            "retention": ret or None, "insufficient": a28["views"] < MIN_VIEWS, "in_records": bool(c),
            "growth": {**g, "state": growth_state(g, a0["views"])},
        })
    # 同じ日数での比較: 各日数の中央値に対する倍率
    for n in (3, 7):
        k = f"views_d{n}"
        vals = [v["growth"][k] for v in videos if v["growth"].get(k) is not None]
        med = statistics.median(vals) if vals else None
        for v in videos:
            x = v["growth"].get(k)
            v["growth"][f"d{n}_vs_median"] = r2(x / med) if x is not None and med else None
    videos.sort(key=lambda v: (-v["views_w0"], -v["views_28d"]))
    groups = {}
    for key in ("kind", "hook", "pattern", "weekday"):
        g = {}
        for v in videos:
            val = (v.get("content") or {}).get(key) if key == "weekday" else v.get(key)
            if v["in_records"] and v["growth"].get("views_d3") is not None:
                g.setdefault(val or "(なし)", []).append(v)
        groups[key] = [{
            "group": k, "n": len(vs),
            "d3_median": statistics.median(x["growth"]["views_d3"] for x in vs),
            "d7_median": (statistics.median(d7) if (d7 := [x["growth"]["views_d7"] for x in vs if x["growth"]["views_d7"] is not None]) else None),
            "n_d7": len(d7),
            "avg_view_pct_mean": r2(statistics.mean(x["avg_view_pct_28d"] or 0 for x in vs), 1),
            "reference_only": len(vs) < 5,
        } for k, vs in sorted(g.items(), key=lambda kv: str(kv[0]))]
    vid_sum = sum(v["views_w0"] for v in videos)
    last = max((r["date"] for r in ch), default=None)
    return {"channel_weekly": trend, "videos": videos, "groups": groups, "videos_w0_sum": vid_sum,
            "last_date": last, "collection_start": first_date}


# ---------------------------------------------------------------- Play
def play_mode(metric):
    """週への畳み方。率・平均は平均、累計・現在値は最後の値、件数は合計。"""
    m = metric.lower()
    if "rate" in m or "average" in m or "avg" in m:
        return "mean"
    if "total" in m or "active" in m or "distinct" in m:
        return "last"
    return "sum"


def play_facts(root, ws):
    rows = store.load(root, "play", start=ws[-1][0].isoformat(), end=ws[0][1].isoformat())
    pk = {}
    for r in rows:
        if "#" in r["entity"]:  # バージョン別は、別に扱う
            continue
        pk.setdefault(r["entity"], {}).setdefault(r["metric"], []).append(r)
    out = {}
    for pkg, metrics in pk.items():
        series = {}
        for metric, rs in sorted(metrics.items()):
            mode = play_mode(metric)
            vals = []
            for w in ws:
                xs = sorted((r for r in rs if in_win(r, w)), key=lambda r: r["date"])
                if not xs:
                    vals.append(None)
                elif mode == "mean":
                    vals.append(r2(statistics.mean(x["value"] for x in xs), 5))
                elif mode == "last":
                    vals.append(xs[-1]["value"])
                else:
                    vals.append(sum(x["value"] for x in xs))
            series[metric] = {"mode": mode, "weekly": vals, "wow_pct": pct(vals[0], vals[1]) if len(vals) > 1 else None,
                              "last_date": max(r["date"] for r in rs)}
        out[pkg] = series
    by_ver = {}
    for r in rows:
        if "#" in r["entity"] and in_win(r, ws[0]) and r["metric"] in ("vitals_crash_rate", "vitals_anr_rate"):
            by_ver.setdefault(r["entity"].split("#", 1)[1], {}).setdefault(r["metric"], []).append(r["value"])
    versions = {v: {k: r2(statistics.mean(xs), 5) for k, xs in d.items()} for v, d in sorted(by_ver.items())}
    return {"packages": out, "versions_w0": versions}


# ---------------------------------------------------------------- 状態と要確認
def source_status(root, today):
    p = pathlib.Path(root) / "store" / "status.jsonl"
    latest = {}
    if p.exists():
        for line in p.read_text(encoding="utf-8").splitlines():
            if line.strip():
                r = json.loads(line)
                if r["date"] <= today.isoformat() and r["date"] >= latest.get(r["source"], {}).get("date", ""):
                    latest[r["source"]] = r
    last_ok = {}
    if p.exists():
        for line in p.read_text(encoding="utf-8").splitlines():
            if line.strip():
                r = json.loads(line)
                if r["state"] == "ok":
                    last_ok[r["source"]] = max(last_ok.get(r["source"], ""), r["date"])
    return {s: {**latest.get(s, {"state": "unknown"}), "last_ok": last_ok.get(s)} for s in ("youtube", "play", "appstore")
            if s in latest or s in last_ok}


def alerts(yt, pl, status, ws):
    out = []
    t = yt["channel_weekly"]
    if len(t) > 1 and t[1]["views"] >= 100 and t[0]["views"] <= t[1]["views"] / 2:
        out.append({"level": "warn", "code": "views_halved", "text": f"再生数が前週の半分以下 ({t[1]['views']:g} → {t[0]['views']:g})"})
    for s, st in status.items():
        if st.get("state") == "ng":
            out.append({"level": "warn", "code": f"{s}_fetch_ng", "text": f"{s} の取得に失敗 ({st.get('note', '')[:100]})"})
    stale = (ws[0][1] - datetime.timedelta(days=7)).isoformat()
    if yt["last_date"] and yt["last_date"] < stale:
        out.append({"level": "warn", "code": "youtube_stale", "text": f"YouTube の最新データが古い ({yt['last_date']})"})
    for pkg, series in pl["packages"].items():
        for k in ("vitals_crash_rate", "vitals_anr_rate"):
            s = series.get(k)
            if s and s["weekly"][0] is not None and s["weekly"][1] is not None:
                a, b = s["weekly"][0], s["weekly"][1]
                if a > b * 1.5 and a >= 0.005:  # 1.5 倍以上、かつ 0.5% 以上
                    out.append({"level": "warn", "code": f"{k}_up", "text": f"{pkg} の {k} が上昇 ({b:.4f} → {a:.4f})"})
    return out


def data_quality(yt):
    out = []
    ch_views = yt["channel_weekly"][0]["views"]
    if ch_views != yt["videos_w0_sum"]:
        out.append(f"今週のチャンネル合計 {ch_views:g} 回と、動画別の合計 {yt['videos_w0_sum']:g} 回が一致しない (削除・非公開の動画などの可能性。原因は未確認)")
    missing = [v["youtube_id"] for v in yt["videos"] if not v["in_records"]]
    if missing:
        out.append(f"promo/records に記録のない動画が {len(missing)} 本 (投稿内容と結びつかない)")
    uncovered = [v for v in yt["videos"] if v["growth"].get("covered_from_publish") is False]
    if uncovered:
        out.append(f"公開日より後から蓄積を始めた動画が {len(uncovered)} 本 (伸びの比較から外れる。backfill で埋まる)")
    weeks_with_data = sum(1 for w in yt["channel_weekly"] if w["days"])
    if weeks_with_data < 4:
        out.append(f"YouTube の時系列は {weeks_with_data} 週分しかない。推移の判断は参考程度")
    return out


def build(root, promo_dir, today):
    ws = windows(today)
    yt = youtube_facts(root, ws, promo_dir)
    pl = play_facts(root, ws)
    st = source_status(root, today)
    return {"schema": 1, "date": today.isoformat(),
            "weeks": [{"week": f"w{i}", "start": w[0].isoformat(), "end": w[1].isoformat()} for i, w in enumerate(ws)],
            "status": st, "alerts": alerts(yt, pl, st, ws), "data_quality": data_quality(yt),
            "youtube": yt, "play": pl}


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True)
    ap.add_argument("--promo", default="promo", help="promo/ のディレクトリ (投稿内容の記録)")
    ap.add_argument("--date")
    ap.add_argument("--out", default="facts.json")
    a = ap.parse_args(argv)
    today = datetime.date.fromisoformat(a.date) if a.date else datetime.date.today()
    f = build(a.root, a.promo, today)
    pathlib.Path(a.out).write_text(json.dumps(f, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"保存: {a.out} (動画 {len(f['youtube']['videos'])} 本、要確認 {len(f['alerts'])} 件)")  # 数字そのものは出さない


if __name__ == "__main__":
    sys.exit(main())
