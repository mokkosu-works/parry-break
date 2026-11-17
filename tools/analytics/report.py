#!/usr/bin/env python3
"""レポート。facts.json と handoff.json から、自己完結の HTML と、Discord の通知 (embed + HTML の添付) を作る。

  python3 report.py html   --facts facts.json --handoff handoff.json --out report.html
  python3 report.py send   --facts facts.json --handoff handoff.json --html report.html [--run-url URL] [--dry]
  python3 report.py failure --run-url URL [--dry]       # ワークフローが失敗したことを送る

送信先は環境変数 DISCORD_WEBHOOK_URL (Actions の secret)。URL は秘密なので、画面にもログにも出さない。
未設定・送信失敗は、終了コード 1 (ジョブを赤にして、気づけるようにする)。
@ のメンションは、すべて無効にして送る。HTML は外部を読み込まず、スクリプトも使わない (CSP で禁止)。値はすべてエスケープする。
"""
import argparse, datetime, html, json, os, pathlib, re, sys, urllib.error, urllib.request, uuid

NAME = "PARRY BREAK 自動レポート"
HOOK_RE = re.compile(r"https://(discord|discordapp)\.com/api/webhooks/\d+/[\w-]+")
COLOR = {"ok": 0x2E9E5B, "attention": 0xE0A100, "failure": 0xD64545}
STATE_JA = {"ok": "取得できた", "ng": "取得に失敗", "no_data": "データなし", "unknown": "不明"}
OUTCOME_JA = {"improved": "改善", "no_change": "変化なし", "worse": "悪化", "insufficient_data": "データ不足"}


def e(x):
    return html.escape("" if x is None else str(x), quote=True)


def fmt(x, nd=None):
    if x is None:
        return "-"
    if isinstance(x, float):
        if nd is not None:
            return f"{x:.{nd}f}"
        return f"{x:,.0f}" if abs(x) >= 100 else f"{x:.4g}"
    if isinstance(x, int):
        return f"{x:,}"
    return str(x)


def fmt_rate(x, nd=1):
    """割合 (%) の表示。値が無ければ「-」だけ (「-%」にしない)。"""
    return "-" if x is None else f"{fmt(x, nd)}%"


def fmt_pct(p):
    return "-" if p is None else f"{p:+.0f}%"


def cut(s, n):
    s = str(s)
    return s if len(s) <= n else s[: n - 1] + "…"


# ---------------------------------------------------------------- HTML
def spark(vals, w=120, h=28):
    """古い順に並べた値の折れ線 (SVG)。None は飛ばす。"""
    pts = [(i, v) for i, v in enumerate(vals) if isinstance(v, (int, float))]
    if len(pts) < 2:
        return ""
    lo, hi = min(v for _, v in pts), max(v for _, v in pts)
    span = (hi - lo) or 1
    n = len(vals) - 1 or 1
    xy = [(2 + i * (w - 4) / n, h - 3 - (v - lo) * (h - 6) / span) for i, v in pts]
    path = " ".join(f"{x:.1f},{y:.1f}" for x, y in xy)
    lx, ly = xy[-1]
    return (f'<svg class="spark" viewBox="0 0 {w} {h}" width="{w}" height="{h}" role="img" aria-label="推移">'
            f'<polyline points="{path}" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/>'
            f'<circle cx="{lx:.1f}" cy="{ly:.1f}" r="2.4" fill="currentColor"/></svg>')


def delta_cls(p, good_up=True):
    if p is None or abs(p) < 5:
        return "flat"
    return "up" if (p > 0) == good_up else "down"


CSS = """
:root{--s1:#2a78d6;--s2:#eb6834;--s3:#1baf7a;--s4:#eda100;--s5:#e87ba4;--grid:#e1e0d9;--axis:#c3c2b7;--chart-bg:#cfcec8;--bg:#f7f7f5;--card:#fff;--fg:#1d1d1f;--muted:#6b6b70;--line:#e3e3e0;--accent:#3a6ff7;--ok:#2e9e5b;--warn:#b7791f;--bad:#d64545;--chip:#efefec}
@media (prefers-color-scheme:dark){:root{--s1:#3987e5;--s2:#d95926;--s3:#199e70;--s4:#c98500;--s5:#d55181;--grid:#2c2c2a;--axis:#383835;--chart-bg:#4a4a46;--bg:#141416;--card:#1d1d20;--fg:#ececef;--muted:#9a9aa2;--line:#2e2e33;--accent:#7c9cff;--ok:#4cc27c;--warn:#e0b04a;--bad:#ff6b6b;--chip:#2a2a2f}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.6 -apple-system,BlinkMacSystemFont,"Hiragino Sans","Noto Sans JP",sans-serif}
main{max-width:960px;margin:0 auto;padding:24px 16px 64px}
h1{font-size:22px;margin:0 0 4px}h2{font-size:17px;margin:32px 0 12px;padding-bottom:6px;border-bottom:1px solid var(--line)}h3{font-size:15px;margin:20px 0 8px}
.sub{color:var(--muted);font-size:13px}
.badge{display:inline-block;padding:2px 10px;border-radius:999px;font-size:13px;font-weight:600;color:#fff}
.badge.ok{background:var(--ok)}.badge.attention{background:var(--warn)}
.card{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:14px 16px;margin:10px 0}
.kpis{display:grid;grid-template-columns:repeat(auto-fill,minmax(200px,1fr));gap:10px}
.kpi .label{color:var(--muted);font-size:12px}.kpi .val{font-size:24px;font-weight:650;font-variant-numeric:tabular-nums}
.kpi .spark{color:var(--accent);display:block;margin-top:4px}
.up{color:var(--ok)}.down{color:var(--bad)}.flat{color:var(--muted)}
ul{padding-left:20px;margin:6px 0}li{margin:3px 0}
.tbl{overflow-x:auto}table{border-collapse:collapse;width:100%;font-size:13px;font-variant-numeric:tabular-nums}
th,td{padding:6px 8px;border-bottom:1px solid var(--line);text-align:right;white-space:nowrap}th{color:var(--muted);font-weight:600}
td.l,th.l{text-align:left;white-space:normal;min-width:120px}td.wide,th.wide{min-width:260px}
td .spark{color:var(--accent);vertical-align:middle}
.chip{display:inline-block;background:var(--chip);border-radius:6px;padding:0 6px;font-size:12px;margin-right:4px}
.chip.need{background:var(--warn);color:#fff}.chip.auto{background:var(--ok);color:#fff}
.alert{border-left:4px solid var(--warn)}.muted{color:var(--muted)}
.prop h3{margin:0 0 6px}.prop dl{display:grid;grid-template-columns:auto 1fr;gap:2px 12px;margin:8px 0 0;font-size:13px}.prop dt{color:var(--muted)}
footer{margin-top:40px;color:var(--muted);font-size:12px}
.legend{display:flex;flex-wrap:wrap;gap:4px 14px;font-size:12px;margin-bottom:6px}.key{display:inline-flex;align-items:center;gap:5px}
.sw{display:inline-block;width:14px;height:3px;border-radius:2px;background:currentColor}.bgsw{background:var(--chart-bg)}
.chart{width:100%;max-width:720px;height:auto;display:block}.chart .grid{stroke:var(--grid);stroke-width:1}.chart .axis{stroke:var(--axis);stroke-width:1}
.chart .tick{fill:var(--muted);font-size:12px}.chart .lbl{fill:var(--fg);font-size:12px;font-weight:600}
.chart .ln{fill:none;stroke-width:2;stroke-linejoin:round;stroke-linecap:round}.chart .bg{fill:none;stroke:var(--chart-bg);stroke-width:1.2}
.chart .dot{stroke:var(--card);stroke-width:2}
.s1{color:var(--s1);stroke:var(--s1)}.s2{color:var(--s2);stroke:var(--s2)}.s3{color:var(--s3);stroke:var(--s3)}.s4{color:var(--s4);stroke:var(--s4)}.s5{color:var(--s5);stroke:var(--s5)}
circle.s1{fill:var(--s1)}circle.s2{fill:var(--s2)}circle.s3{fill:var(--s3)}circle.s4{fill:var(--s4)}circle.s5{fill:var(--s5)}
"""


def kpi(label, val, p, series, good_up=True):
    return (f'<div class="card kpi"><div class="label">{e(label)}</div><div class="val">{e(val)}</div>'
            f'<div class="{delta_cls(p, good_up)}">前週比 {e(fmt_pct(p))}</div>{spark(series)}</div>')


GROUP_LABEL = {"kind": "種類ごと", "hook": "冒頭の種類ごと", "pattern": "パターンごと", "weekday": "公開の曜日ごと"}
VERDICT_CLS = {"伸びた": "up", "伸びなかった": "down"}
HILITE = 5  # 色を付ける動画の数 (残りは灰色の細い線で、比較の背景にする)


def growth_key(v):
    """伸びの順位。いちばん多くの動画を比べられる 3 日目の倍率で並べ、同じなら 7 日目、累計。"""
    g = v["growth"]
    return (g.get("d3_vs_median") or 0, g.get("d7_vs_median") or 0, g.get("views_total") or 0)


def growth_chart(videos, w=560, h=280):
    """公開日を 1 日目にした累計再生数の折れ線 (SVG、スクリプトなし)。上位 HILITE 本に色、残りは灰色。端に ID を直接書く。"""
    series = [v for v in videos if (v["growth"].get("curve") or [None])[0] is not None and len(v["growth"]["curve"]) >= 2]
    if len(series) < 1:
        return ""
    series.sort(key=growth_key, reverse=True)
    top, rest = series[:HILITE], series[HILITE:]
    pl, pr, pt, pb = 44, 56, 12, 28
    days = max(len(v["growth"]["curve"]) for v in series)
    ymax = max(max(v["growth"]["curve"]) for v in series) or 1
    step = 10 ** max(len(str(int(ymax))) - 1, 0)
    ymax = ((int(ymax) // step) + 1) * step
    X = lambda d: pl + (d - 1) * (w - pl - pr) / max(days - 1, 1)
    Y = lambda val: pt + (h - pt - pb) * (1 - val / ymax)
    o = [f'<svg class="chart" viewBox="0 0 {w} {h}" role="img" aria-label="公開からの日数ごとの累計再生数">']
    for i in range(5):  # 横の補助線と目盛り
        val = ymax * i / 4
        o.append(f'<line class="grid" x1="{pl}" x2="{w - pr}" y1="{Y(val):.1f}" y2="{Y(val):.1f}"/>'
                 f'<text class="tick" x="{pl - 6}" y="{Y(val) + 4:.1f}" text-anchor="end">{fmt(int(val))}</text>')
    for d in sorted({1, 3, 7, 14, 21, 28} & set(range(1, days + 1))):
        o.append(f'<text class="tick" x="{X(d):.1f}" y="{h - 8}" text-anchor="middle">{d}日</text>')
    o.append(f'<line class="axis" x1="{pl}" x2="{w - pr}" y1="{Y(0):.1f}" y2="{Y(0):.1f}"/>')

    def path(v):
        return " ".join(f"{X(i + 1):.1f},{Y(c):.1f}" for i, c in enumerate(v["growth"]["curve"]))

    def tip(v):
        g = v["growth"]
        return e(f'{v["id"] or v["youtube_id"]}: {len(g["curve"])} 日目まで {fmt(g["curve"][-1])} 回')
    for v in rest:
        o.append(f'<polyline class="bg" points="{path(v)}"><title>{tip(v)}</title></polyline>')
    labels = []
    for i, v in enumerate(reversed(top)):  # 上位ほど手前に描く
        k = len(top) - i
        c = v["growth"]["curve"]
        x, y = X(len(c)), Y(c[-1])
        o.append(f'<polyline class="ln s{k}" points="{path(v)}"><title>{tip(v)}</title></polyline>'
                 f'<circle class="dot s{k}" cx="{x:.1f}" cy="{y:.1f}" r="4"><title>{tip(v)}</title></circle>')
        labels.append([y, x, v["id"] or v["youtube_id"][:6]])
    labels.sort()
    for j in range(1, len(labels)):  # 端の名前が重ならないように、縦に 13px ずつ離す
        labels[j][0] = max(labels[j][0], labels[j - 1][0] + 14)
    for y, x, name in labels:
        o.append(f'<text class="lbl" x="{x + 7:.1f}" y="{y + 4:.1f}">{e(name)}</text>')
    o.append("</svg>")
    legend = "".join(f'<span class="key"><i class="sw s{k}"></i>{e(v["id"] or v["youtube_id"])}'
                     f' <span class="muted">{e(cut((v.get("content") or {}).get("hook_caption") or v["title"] or "", 18))}</span></span>'
                     for k, v in enumerate(top, 1))
    if rest:
        legend += f'<span class="key"><i class="sw bgsw"></i>ほか {len(rest)} 本</span>'
    return f'<div class="legend">{legend}</div>' + "".join(o)


def growth_section(yt, h):
    vids = yt["videos"]
    out = ["<h2>動画の伸び</h2>",
           '<p class="sub">公開日を 1 日目にそろえた累計の再生数。公開日が違う動画を、同じ日数で比べる。中央値比は、同じ日数の全動画の中央値に対する倍率。</p>']
    chart = growth_chart(vids)
    out.append(f'<div class="card">{chart}</div>' if chart else '<p class="muted">伸びを比べられる動画がまだない (公開日からのデータが要る。backfill で埋まる)。</p>')
    if vids:
        out.append('<div class="tbl"><table><tr><th class="l">動画</th><th class="l wide">投稿内容</th><th class="l">公開</th><th>経過</th>'
                   "<th>1日目</th><th>3日目</th><th>7日目</th><th>28日目</th><th>中央値比<br>(3日目)</th><th>中央値比<br>(7日目)</th><th class=\"l\">状態</th><th>平均視聴割合</th></tr>")
        for v in sorted(vids, key=growth_key, reverse=True)[:30]:
            g, c = v["growth"], v.get("content") or {}
            body = (f'{e(c.get("kind") or "")} {e(c.get("hook") or "")} {e(c.get("hook_label") or "")}<br>'
                    f'<span class="muted">冒頭「{e(c.get("hook_caption") or "-")}」 本編「{e(c.get("body_caption") or "-")}」 {e(fmt(c.get("length_sec")))}秒</span>') if c else '<span class="muted">記録なし</span>'
            pub = f'{e(v["published"] or "-")} {e(c.get("weekday") or "")}' + (f' {c["publish_hour"]}時' if c.get("publish_hour") is not None else "")
            def rcell(r):
                cls = "up" if r is not None and r >= 1.5 else "down" if r is not None and r <= 0.67 else "flat"
                return f'<td class="{cls}">{"-" if r is None else f"{r:.2f}倍"}</td>'
            out.append(f'<tr><td class="l">{e(v["id"] or v["youtube_id"])}</td><td class="l wide">{body}</td><td class="l">{pub}</td>'
                       f'<td>{fmt(g.get("age_days"))}日</td><td>{fmt(g.get("views_d1"))}</td><td>{fmt(g.get("views_d3"))}</td>'
                       f'<td>{fmt(g.get("views_d7"))}</td><td>{fmt(g.get("views_d28"))}</td>'
                       f'{rcell(g.get("d3_vs_median"))}{rcell(g.get("d7_vs_median"))}<td class="l">{e(g.get("state"))}</td>'
                       f'<td>{fmt_rate(v["avg_view_pct_28d"])}</td></tr>')
        out.append("</table></div>")
    for key, lab in GROUP_LABEL.items():
        g = yt["groups"].get(key) or []
        if len(g) >= 2:
            out.append(f'<h3>{lab}</h3><div class="tbl"><table><tr><th class="l">区分</th><th>本数</th>'
                       "<th>3日目の中央値</th><th>7日目の中央値</th><th>平均視聴割合</th></tr>")
            for x in g:
                ref = ' <span class="chip">参考値</span>' if x["reference_only"] else ""
                d7 = "-" if x["d7_median"] is None else f'{fmt(x["d7_median"])} <span class="muted">({x["n_d7"]}本)</span>'
                out.append(f'<tr><td class="l">{e(x["group"])}{ref}</td><td>{x["n"]}</td><td>{fmt(x["d3_median"])}</td>'
                           f'<td>{d7}</td><td>{fmt_rate(x["avg_view_pct_mean"])}</td></tr>')
            out.append("</table></div>")
    if h.get("content_findings"):
        out.append("<h2>投稿内容の分析</h2>")
        for f in h["content_findings"]:
            chips = ('<span class="chip">参考値 (5 本未満)</span>' if f["reference_only"] else "") + \
                    ("" if f["evidence_verified"] else '<span class="chip">根拠が事実に無い</span>')
            ev = "".join(f"<li>{e(x['metric'])}: {e(x['value'])}</li>" for x in f["evidence"])
            out.append(f'<div class="card prop"><h3>{e(f["finding"])}</h3>{chips}<dl>'
                       f'<dt>仮説</dt><dd>{e(f["hypothesis"])}</dd><dt>根拠</dt><dd><ul>{ev}</ul></dd>'
                       f'<dt>確かめ方</dt><dd>{e(f["next_test"])} (サンプル {f["sample_size"]} 本)</dd></dl></div>')
    if h.get("video_insights"):
        out.append("<h3>動画ごとの見立て</h3><ul>")
        for x in h["video_insights"]:
            mark = "" if x["evidence_verified"] else ' <span class="chip">根拠が事実に無い</span>'
            out.append(f'<li><b>{e(x["id"])}</b> <span class="{VERDICT_CLS.get(x["verdict"], "flat")}">{e(x["verdict"])}</span>: {e(x["comment"])}{mark}</li>')
        out.append("</ul>")
    return out


ASC_LABELS = {
    "engagement_impression": "インプレッション", "engagement_page_view": "製品ページの表示", "engagement_tap": "タップ",
    "engagement_total": "表示・操作の合計", "downloads_total": "ダウンロード (計)",
    "downloads_first_time_download": "初回ダウンロード", "downloads_redownload": "再ダウンロード",
    "install_total": "インストール・削除の計", "install_install": "インストール", "install_delete": "削除",
    "sessions": "セッション", "crashes": "クラッシュ",
}


def asc_label(m):
    return ASC_LABELS.get(m, m)


def asc_order(m):
    keys = list(ASC_LABELS)
    return keys.index(m) if m in keys else len(keys)


def build_html(facts, h, run_url=None):
    yt, pl = facts["youtube"], facts["play"]
    cw = yt["channel_weekly"]
    w0 = facts["weeks"][0]
    old_first = lambda k: [w.get(k) if w.get("days") else None for w in reversed(cw)]
    out = ['<!doctype html><html lang="ja"><head><meta charset="utf-8">',
           '<meta name="viewport" content="width=device-width,initial-scale=1">',
           "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; style-src 'unsafe-inline'; img-src data:\">",
           f"<title>週次レポート {e(facts['date'])}</title><style>{CSS}</style></head><body><main>"]
    st = h.get("status", "ok")
    out.append(f'<h1>PARRY BREAK 週次レポート</h1><div class="sub">取得日 {e(facts["date"])} / 対象の週 {e(w0["start"])} 〜 {e(w0["end"])}'
               f' &nbsp;<span class="badge {e(st)}">{"要確認" if st == "attention" else "異常なし"}</span></div>')
    if h.get("summary"):
        out.append(f'<div class="card">{e(h["summary"])}</div>')
    if h.get("alerts"):
        out.append('<div class="card alert"><b>要確認</b><ul>' + "".join(f"<li>{e(a['text'])}</li>" for a in h["alerts"]) + "</ul></div>")
    if h.get("highlights"):
        out.append("<h2>今週の要点</h2><ul>" + "".join(f"<li>{e(x)}</li>" for x in h["highlights"]) + "</ul>")

    # ---- YouTube
    out.append("<h2>YouTube</h2>")
    if cw and cw[0].get("days"):
        c0 = cw[0]
        prev = cw[1] if len(cw) > 1 else {}
        wow = lambda k: (None if not prev.get(k) else round((c0[k] - prev[k]) / prev[k] * 100, 1)) if isinstance(c0.get(k), (int, float)) else None
        out.append('<div class="kpis">' + "".join([
            kpi("再生数", fmt(c0["views"]), wow("views"), old_first("views")),
            kpi("エンゲージ視聴", fmt(c0["engagedViews"]), wow("engagedViews"), old_first("engagedViews")),
            kpi("平均視聴割合", fmt_rate(c0['averageViewPercentage']), wow("averageViewPercentage"), old_first("averageViewPercentage")),
            kpi("登録者の増加", fmt(c0["subscribersGained"]), wow("subscribersGained"), old_first("subscribersGained")),
        ]) + "</div>")
        out.append('<h3>週ごとの推移 (チャンネル)</h3><div class="tbl"><table><tr><th class="l">週</th><th>再生数</th><th>前週比</th>'
                   "<th>エンゲージ視聴</th><th>平均視聴割合</th><th>いいね</th><th>シェア</th><th>登録者</th></tr>")
        for w in cw:
            if not w.get("days"):
                continue
            out.append(f'<tr><td class="l">{e(w["start"][5:])}〜{e(w["end"][5:])}</td><td>{fmt(w["views"])}</td>'
                       f'<td class="{delta_cls(w.get("views_wow_pct"))}">{fmt_pct(w.get("views_wow_pct"))}</td><td>{fmt(w["engagedViews"])}</td>'
                       f'<td>{fmt_rate(w["averageViewPercentage"])}</td><td>{fmt(w["likes"])}</td><td>{fmt(w["shares"])}</td><td>{fmt(w["subscribersGained"])}</td></tr>')
        out.append("</table></div>")
    else:
        out.append('<p class="muted">今週の YouTube のデータはない。</p>')
    out += growth_section(yt, h)
    if yt["videos"]:
        out.append('<h2>動画別 (直近 28 日)</h2><div class="tbl"><table><tr><th class="l">動画</th><th class="l">パターン / 冒頭</th><th>今週</th><th>前週</th>'
                   "<th>28 日</th><th>平均視聴割合</th><th>エンゲージ率</th><th>維持率 5%</th></tr>")
        for v in yt["videos"][:30]:
            name = f'{e(v["id"] or "記録なし")} <span class="muted">{e(cut(v["title"] or v["youtube_id"], 28))}</span>'
            tag = '<span class="chip">データ不足</span>' if v["insufficient"] else ""
            r5 = (v.get("retention") or {}).get("retention_r005")
            out.append(f'<tr><td class="l">{name} {tag}</td><td class="l">{e(v["pattern"] or "-")} / {e(v["hook"] or "-")}</td>'
                       f'<td>{fmt(v["views_w0"])}</td><td>{fmt(v["views_w1"])}</td><td>{fmt(v["views_28d"])}</td>'
                       f'<td>{fmt_rate(v["avg_view_pct_28d"])}</td><td>{fmt_rate(v["engaged_rate_28d"])}</td><td>{fmt(r5, 2)}</td></tr>')
        out.append("</table></div>")
    # ---- Play
    out.append("<h2>Google Play</h2>")
    if not pl["packages"]:
        out.append('<p class="muted">Google Play のデータはない。</p>')
    for pkg, series in pl["packages"].items():
        out.append(f'<h3>{e(pkg)}</h3><div class="tbl"><table><tr><th class="l">指標</th><th>今週</th><th>前週</th><th>前週比</th><th>8 週</th><th>最新の日付</th></tr>')
        for m, s in series.items():
            good_up = not any(k in m for k in ("crash", "anr", "uninstall"))
            nd = 4 if "rate" in m else None
            out.append(f'<tr><td class="l">{e(m)}</td><td>{fmt(s["weekly"][0], nd)}</td><td>{fmt(s["weekly"][1] if len(s["weekly"]) > 1 else None, nd)}</td>'
                       f'<td class="{delta_cls(s["wow_pct"], good_up)}">{fmt_pct(s["wow_pct"])}</td><td>{spark(list(reversed(s["weekly"])), 90, 22)}</td>'
                       f'<td>{e(s["last_date"])}</td></tr>')
        out.append("</table></div>")
    if pl.get("versions_w0"):
        out.append('<h3>バージョン別 (今週)</h3><div class="tbl"><table><tr><th class="l">versionCode</th><th>クラッシュ率</th><th>ANR 率</th></tr>')
        for ver, d in pl["versions_w0"].items():
            out.append(f'<tr><td class="l">{e(ver)}</td><td>{fmt(d.get("vitals_crash_rate"), 4)}</td><td>{fmt(d.get("vitals_anr_rate"), 4)}</td></tr>')
        out.append("</table></div>")
    # ---- App Store
    out.append("<h2>App Store</h2>")
    apps = (facts.get("appstore") or {}).get("apps") or {}
    if not apps:
        out.append('<p class="muted">App Store のデータはない。</p>')
    for app, series in apps.items():
        out.append(f'<h3>Apple ID {e(app)}</h3><div class="tbl"><table><tr><th class="l">指標</th><th>今週</th><th>前週</th><th>前週比</th><th>8 週</th><th>最新の日付</th></tr>')
        for m, s in sorted(series.items(), key=lambda kv: (asc_order(kv[0]), kv[0])):
            good_up = not any(k in m for k in ("crash", "delet"))
            out.append(f'<tr><td class="l">{e(asc_label(m))}</td><td>{fmt(s["weekly"][0])}</td><td>{fmt(s["weekly"][1] if len(s["weekly"]) > 1 else None)}</td>'
                       f'<td class="{delta_cls(s["wow_pct"], good_up)}">{fmt_pct(s["wow_pct"])}</td><td>{spark(list(reversed(s["weekly"])), 90, 22)}</td>'
                       f'<td>{e(s["last_date"])}</td></tr>')
        out.append("</table></div>")

    # ---- 提案
    props = sorted(h.get("proposals", []), key=lambda p: (not p["needs_human_approval"], not p["auto_executable"]))
    out.append(f"<h2>提案 ({len(props)} 件)</h2>")
    if not props:
        out.append('<p class="muted">今週の提案はない。</p>')
    for p in props:
        chips = ('<span class="chip need">人の承認が必要</span>' if p["needs_human_approval"] else "") + \
                ('<span class="chip auto">自動で実行してよい</span>' if p["auto_executable"] else "") + \
                f'<span class="chip">{e(p["target"])}</span><span class="chip">{e(p["kind"])}</span><span class="chip">確からしさ {e(p["confidence"])}</span>' + \
                ("" if p["evidence_verified"] else '<span class="chip">根拠が事実に無い</span>')
        ev = "".join(f"<li>{e(x['metric'])}: {e(x['value'])}</li>" for x in p["evidence"])
        sm = p.get("success_metric") or {}
        out.append(f'<div class="card prop"><h3>{e(p["id"])} {e(p["action"])}</h3>{chips}<dl>'
                   f'<dt>理由</dt><dd>{e(p["rationale"])}</dd><dt>仮説</dt><dd>{e(p["hypothesis"])}</dd>'
                   f'<dt>根拠</dt><dd><ul>{ev}</ul></dd>'
                   f'<dt>成功の判定</dt><dd>{e(sm.get("metric"))} {e(sm.get("direction"))} {e(sm.get("min_change"))} (サンプル {p["sample_size"]})</dd></dl></div>')
    if h.get("experiment_reviews"):
        out.append("<h2>実験の評価</h2><ul>" + "".join(
            f"<li><b>{e(r['experiment_id'])}</b> {e(OUTCOME_JA.get(r['outcome'], r['outcome']))}: {e(r['note'])}</li>" for r in h["experiment_reviews"]) + "</ul>")
    if h.get("open_experiments"):
        out.append("<h3>実行中の実験</h3><ul>" + "".join(
            f"<li>{e(x['id'])} ({e(x['target'])}) {e(x['action'])}</li>" for x in h["open_experiments"]) + "</ul>")

    # ---- データの状態
    out.append("<h2>データの状態</h2><ul>")
    for s, v in facts.get("status", {}).items():
        out.append(f"<li>{e(s)}: {e(STATE_JA.get(v.get('state'), v.get('state')))} (最後に取れた日 {e(v.get('last_ok') or '-')})"
                   + (f" <span class='muted'>{e(cut(v.get('note', ''), 160))}</span>" if v.get("note") else "") + "</li>")
    out += [f"<li>{e(x)}</li>" for x in h.get("data_quality", [])]
    out.append("</ul>")
    if h.get("rejected"):
        out.append("<h3>検証で落とした提案</h3><ul>" + "".join(f"<li>{e(r['reason'])}: {e(r['raw_action'])}</li>" for r in h["rejected"]) + "</ul>")
    out.append(f'<footer>自動生成 ({e(h.get("generated_at"))})。数字は取得できた範囲のもの。仮説は事実ではない。'
               + (f' 実行ログ: {e(run_url)}' if run_url else "") + "</footer></main></body></html>")
    return "\n".join(out)


# ---------------------------------------------------------------- Discord
def embed(facts, h, run_url=None):
    st = h.get("status", "ok")
    cw = facts["youtube"]["channel_weekly"]
    w0 = facts["weeks"][0]
    desc = []
    if h.get("summary"):
        desc.append(cut(h["summary"], 400))
    desc += [f"• {cut(x, 180)}" for x in h.get("highlights", [])[:5]]
    fields = []
    if cw and cw[0].get("days"):
        c0 = cw[0]
        fields.append({"name": "YouTube 再生数", "value": f"{fmt(c0['views'])} ({fmt_pct(c0.get('views_wow_pct'))})", "inline": True})
        fields.append({"name": "平均視聴割合", "value": fmt_rate(c0['averageViewPercentage']), "inline": True})
        fields.append({"name": "登録者の増加", "value": fmt(c0["subscribersGained"]), "inline": True})
    ranked = [v for v in sorted(facts["youtube"]["videos"], key=growth_key, reverse=True)
              if (v["growth"].get("d3_vs_median") or 0) > 1]
    if ranked:
        lines = []
        for v in ranked[:3]:
            g = v["growth"]
            hook = (v.get("content") or {}).get("hook_caption")
            lines.append(f'• {v["id"] or v["youtube_id"]} 3日目 {fmt(g["views_d3"])} 回 (中央値の {g["d3_vs_median"]:.2f} 倍)' + (f'「{cut(hook, 20)}」' if hook else ""))
        fields.append({"name": "伸びが上位の動画 (公開 3 日目で比較)", "value": cut("\n".join(lines), 1024), "inline": False})
    if h.get("content_findings"):
        lines = [f'• {cut(f["finding"], 150)}' + (" (参考値)" if f["reference_only"] else "") for f in h["content_findings"][:3]]
        fields.append({"name": "投稿内容の気づき", "value": cut("\n".join(lines), 1024), "inline": False})
    for pkg, s in facts["play"]["packages"].items():
        ins = next((v for k, v in s.items() if "daily_user_installs" in k), None)
        cr = s.get("vitals_crash_rate")
        parts = []
        if ins:
            parts.append(f"インストール {fmt(ins['weekly'][0])} ({fmt_pct(ins['wow_pct'])})")
        if cr:
            parts.append(f"クラッシュ率 {fmt(cr['weekly'][0], 4)}")
        if parts:
            fields.append({"name": cut(f"Play {pkg}", 256), "value": " / ".join(parts), "inline": False})
    for app, s in ((facts.get("appstore") or {}).get("apps") or {}).items():
        parts = [f"{asc_label(k)} {fmt(s[k]['weekly'][0])} ({fmt_pct(s[k]['wow_pct'])})"
                 for k in ("downloads_total", "engagement_impression", "engagement_page_view") if k in s]
        if parts:
            fields.append({"name": "App Store", "value": cut(" / ".join(parts), 1024), "inline": False})
    if h.get("alerts"):
        fields.append({"name": "🔔 要確認", "value": cut("\n".join(f"• {a['text']}" for a in h["alerts"]), 1024), "inline": False})
    need = [p for p in h.get("proposals", []) if p["needs_human_approval"]]
    props = h.get("proposals", [])
    if props:
        lines = [f"提案 {len(props)} 件 / 自動で実行してよい {sum(p['auto_executable'] for p in props)} 件 / 人の承認が要る {len(need)} 件"]
        lines += [f"• {p['id']} {cut(p['action'], 120)}" for p in need[:5]]
        fields.append({"name": "提案", "value": cut("\n".join(lines), 1024), "inline": False})
    bad = [f"{s}: {STATE_JA.get(v.get('state'), v.get('state'))}" for s, v in facts.get("status", {}).items() if v.get("state") != "ok"]
    if bad:
        fields.append({"name": "データの状態", "value": cut("\n".join(bad), 1024), "inline": False})
    title = f"{'🔔' if st == 'attention' else '✅'} PARRY BREAK 週次レポート {facts['date']}"
    em = {"title": cut(title, 256), "description": cut("\n".join(desc) or f"対象の週 {w0['start']} 〜 {w0['end']}", 4000),
          "color": COLOR.get(st, COLOR["ok"]), "fields": fields[:25],
          "footer": {"text": f"対象の週 {w0['start']} 〜 {w0['end']} ・ 詳細は添付の HTML"}}
    if run_url:
        em["url"] = run_url
    return em


def webhook():
    u = os.environ.get("DISCORD_WEBHOOK_URL", "").strip()
    if not u:
        raise SystemExit("DISCORD_WEBHOOK_URL が未設定")
    if not HOOK_RE.fullmatch(u):
        raise SystemExit("DISCORD_WEBHOOK_URL の形が違う (中身は表示しない)")
    return u


def multipart(payload, files):
    """payload_json と files[n] の multipart/form-data を作る (標準ライブラリだけ)。"""
    b = uuid.uuid4().hex
    parts = [f'--{b}\r\nContent-Disposition: form-data; name="payload_json"\r\nContent-Type: application/json\r\n\r\n'.encode()
             + json.dumps(payload, ensure_ascii=False).encode() + b"\r\n"]
    for i, (name, data, ctype) in enumerate(files):
        parts.append(f'--{b}\r\nContent-Disposition: form-data; name="files[{i}]"; filename="{name}"\r\nContent-Type: {ctype}\r\n\r\n'.encode()
                     + data + b"\r\n")
    return b"".join(parts) + f"--{b}--\r\n".encode(), f"multipart/form-data; boundary={b}"


def send(payload, files=(), dry=False):
    payload = {"username": NAME, "allowed_mentions": {"parse": []}, **payload}
    if dry:
        print(json.dumps(payload, ensure_ascii=False, indent=1))
        for name, data, _ in files:
            print(f"添付: {name} ({len(data):,} バイト)")
        return
    url = webhook() + "?wait=true"
    if files:
        body, ctype = multipart(payload, files)
    else:
        body, ctype = json.dumps(payload, ensure_ascii=False).encode(), "application/json"
    req = urllib.request.Request(url, body, method="POST", headers={"Content-Type": ctype, "User-Agent": "ParryBreakReports/2.0"})
    try:
        urllib.request.urlopen(req, timeout=60).read()
    except urllib.error.HTTPError as ex:
        raise SystemExit(f"送信に失敗: HTTP {ex.code}") from None  # 応答の本文には URL が入ることがあるので出さない
    except Exception as ex:
        raise SystemExit(f"送信に失敗: {type(ex).__name__}") from None
    print("送信した")


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["html", "send", "failure"])
    ap.add_argument("--facts")
    ap.add_argument("--handoff")
    ap.add_argument("--out", default="report.html")
    ap.add_argument("--html")
    ap.add_argument("--run-url")
    ap.add_argument("--dry", action="store_true")
    a = ap.parse_args(argv)
    if a.cmd == "failure":
        now = datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=9))).strftime("%F %H:%M")
        em = {"title": "⚠️ アナリティクスの週次が失敗した", "color": COLOR["failure"],
              "description": f"{now} (JST)。実行ログを確認する。収集できた分は、データ用リポジトリに保存されている場合がある。"}
        if a.run_url:
            em["url"] = a.run_url
        send({"embeds": [em]}, dry=a.dry)
        return
    facts = json.loads(pathlib.Path(a.facts).read_text(encoding="utf-8"))
    h = json.loads(pathlib.Path(a.handoff).read_text(encoding="utf-8"))
    if a.cmd == "html":
        pathlib.Path(a.out).write_text(build_html(facts, h, a.run_url), encoding="utf-8")
        print(f"保存: {a.out}")
        return
    files = [(f"report-{facts['date']}.html", pathlib.Path(a.html).read_bytes(), "text/html; charset=utf-8")] if a.html else []
    send({"embeds": [embed(facts, h, a.run_url)]}, files, dry=a.dry)


if __name__ == "__main__":
    sys.exit(main())
