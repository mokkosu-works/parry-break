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
:root{--bg:#f7f7f5;--card:#fff;--fg:#1d1d1f;--muted:#6b6b70;--line:#e3e3e0;--accent:#3a6ff7;--ok:#2e9e5b;--warn:#b7791f;--bad:#d64545;--chip:#efefec}
@media (prefers-color-scheme:dark){:root{--bg:#141416;--card:#1d1d20;--fg:#ececef;--muted:#9a9aa2;--line:#2e2e33;--accent:#7c9cff;--ok:#4cc27c;--warn:#e0b04a;--bad:#ff6b6b;--chip:#2a2a2f}}
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
td.l,th.l{text-align:left;white-space:normal;min-width:120px}
td .spark{color:var(--accent);vertical-align:middle}
.chip{display:inline-block;background:var(--chip);border-radius:6px;padding:0 6px;font-size:12px;margin-right:4px}
.chip.need{background:var(--warn);color:#fff}.chip.auto{background:var(--ok);color:#fff}
.alert{border-left:4px solid var(--warn)}.muted{color:var(--muted)}
.prop h3{margin:0 0 6px}.prop dl{display:grid;grid-template-columns:auto 1fr;gap:2px 12px;margin:8px 0 0;font-size:13px}.prop dt{color:var(--muted)}
footer{margin-top:40px;color:var(--muted);font-size:12px}
"""


def kpi(label, val, p, series, good_up=True):
    return (f'<div class="card kpi"><div class="label">{e(label)}</div><div class="val">{e(val)}</div>'
            f'<div class="{delta_cls(p, good_up)}">前週比 {e(fmt_pct(p))}</div>{spark(series)}</div>')


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
    if yt["videos"]:
        out.append('<h3>動画別</h3><div class="tbl"><table><tr><th class="l">動画</th><th class="l">パターン / 冒頭</th><th>今週</th><th>前週</th>'
                   "<th>28 日</th><th>平均視聴割合</th><th>エンゲージ率</th><th>維持率 5%</th></tr>")
        for v in yt["videos"][:30]:
            name = f'{e(v["id"] or "記録なし")} <span class="muted">{e(cut(v["title"] or v["youtube_id"], 28))}</span>'
            tag = '<span class="chip">データ不足</span>' if v["insufficient"] else ""
            r5 = (v.get("retention") or {}).get("retention_r005")
            out.append(f'<tr><td class="l">{name} {tag}</td><td class="l">{e(v["pattern"] or "-")} / {e(v["hook"] or "-")}</td>'
                       f'<td>{fmt(v["views_w0"])}</td><td>{fmt(v["views_w1"])}</td><td>{fmt(v["views_28d"])}</td>'
                       f'<td>{fmt_rate(v["avg_view_pct_28d"])}</td><td>{fmt_rate(v["engaged_rate_28d"])}</td><td>{fmt(r5, 2)}</td></tr>')
        out.append("</table></div>")
    for key, lab in (("pattern", "パターンごと"), ("hook", "冒頭の種類ごと")):
        g = yt["groups"].get(key) or []
        if g:
            out.append(f'<h3>{lab} (28 日、データ十分な動画のみ)</h3><div class="tbl"><table><tr><th class="l">区分</th><th>本数</th>'
                       "<th>再生数の中央値</th><th>平均視聴割合</th><th>エンゲージ率</th></tr>")
            for x in g:
                ref = ' <span class="chip">参考値</span>' if x["reference_only"] else ""
                out.append(f'<tr><td class="l">{e(x["group"])}{ref}</td><td>{x["n"]}</td><td>{fmt(x["views_28d_median"])}</td>'
                           f'<td>{fmt_rate(x["avg_view_pct_mean"])}</td><td>{fmt_rate(x["engaged_rate_mean"])}</td></tr>')
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
