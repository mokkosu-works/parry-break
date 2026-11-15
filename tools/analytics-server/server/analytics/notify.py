#!/usr/bin/env python3
"""Discord に、週次レポートの要約と失敗の知らせを送る (標準ライブラリだけ)。@OPS_USER@ で動く。

  python3 notify.py weekly [--dry]       # 週次レポートの「状態」と「今週の要点」だけを送る
  python3 notify.py morning [--dry]      # 朝のサーバーレポートが「要確認」のときだけ送る
  python3 notify.py failure <unit名>     # 自動実行が失敗したことを送る
  python3 notify.py text '<文>'          # 任意の短い文を送る (試験用)
  python3 notify.py check                # 送信先の設定が読めるかを確認する (何も送らない)

送信先の URL (Webhook) は state/discord_webhook.txt に置く (権限 600)。URL は、持っている人が誰でも投稿できる秘密なので、
画面にもログにも出さない。未設定なら、何も送らずに終わる (自動実行を失敗させない)。
送るのは、短い要約だけ。レビューの文面や、レポート全文は送らない。@ のメンションは、すべて無効にして送る。
"""
import datetime, json, pathlib, re, subprocess, sys, urllib.error, urllib.request

BASE = pathlib.Path(__file__).resolve().parent
HOOK = BASE / "state" / "discord_webhook.txt"
REPORTS = pathlib.Path("/srv/analytics/reports")  # @BOT_USER@ のスクリプトが、完成したレポートをここへ写す
NAME = "PARRY BREAK 自動レポート"
LIMIT = 1800  # Discord の上限は 2000 文字


def webhook():
    if not HOOK.exists():
        return None
    u = HOOK.read_text().strip()
    if not re.fullmatch(r"https://(discord|discordapp)\.com/api/webhooks/\d+/[\w-]+", u):
        print("webhook の形が違う。URL を確認する (中身は表示しない)")
        return None
    return u


def post(text, dry=False):
    text = text.strip()
    if len(text) > LIMIT:
        text = text[:LIMIT].rstrip() + "\n…(長いので省略)"
    if dry:
        print("--- 送る予定の内容 ---\n" + text + "\n---------------------")
        return
    u = webhook()
    if not u:
        print("送信先 (Webhook) が未設定。何も送らない")
        return
    body = json.dumps({"content": text, "username": NAME, "allowed_mentions": {"parse": []}}).encode()
    req = urllib.request.Request(u, body, method="POST",
                                 headers={"Content-Type": "application/json", "User-Agent": "ParryBreakReports/1.0"})
    try:
        urllib.request.urlopen(req, timeout=30).read()
        print("送信した")
    except urllib.error.HTTPError as e:
        print(f"送信に失敗: HTTP {e.code}")  # 応答の本文には URL が入ることがあるので出さない
    except Exception as e:
        print(f"送信に失敗: {type(e).__name__}")


def section(md, start_pat, stop_pat):
    m = re.search(start_pat, md, re.M)
    if not m:
        return ""
    rest = md[m.end():]
    s = re.search(stop_pat, rest, re.M)
    return (rest[:s.start()] if s else rest).strip()


def next_actions(md, per=3):
    """「次にやること」の、(a) 動画の制作 / (b) ゲームの改善 から、番号つきの見出しだけを取り出す (根拠や仮説は全文にある)。"""
    sec = section(md, r"^## 4\..*$", r"^## ")
    if not sec:
        return ""
    parts = re.split(r"^###\s*\(([ab])\)[^\n]*$", sec, flags=re.M)  # [前置き, 'a', 本文, 'b', 本文]
    labels = {"a": "動画の制作", "b": "ゲームの改善の手がかり"}
    out = []
    for i in range(1, len(parts) - 1, 2):
        titles = re.findall(r"^\s*\d+\.\s*\*\*(.+?)\*\*", parts[i + 1], re.M)[:per]
        if titles:
            out.append(f"{labels.get(parts[i], parts[i])}:")
            out += [f"  ・{t.strip()}" for t in titles]
    return "\n".join(out)


def cmd_weekly(dry):
    day = datetime.date.today().isoformat()
    p = REPORTS / f"youtube-weekly-{day}.md"
    if not p.exists():
        post(f"⚠️ 週次レポート ({day}) が見つからない。分析の実行に失敗した可能性がある。", dry)
        return
    md = p.read_text()
    title = (re.search(r"^# (.+)$", md, re.M) or [None, "週次レポート"])[1]
    status = section(md, r"^## 1\..*$", r"^## ")
    h1 = re.search(r"^## 1\.\s*(.*)$", md, re.M)
    state_line = h1.group(1).replace("**", "").strip() if h1 else "状態"
    points = section(md, r"^## 2\..*$", r"^\*\*データの注意\*\*|^### 数字の注意|^## ")
    head = "🔔" if "要確認" in (state_line + status) else "✅"
    nxt = next_actions(md)
    try:
        d = json.loads((pathlib.Path("/srv/analytics/handoff/latest.json")).read_text())
        if d.get("date") == day:
            ps = d.get("proposals", [])
            nxt += f"\n(引き渡し: 提案 {len(ps)} 件 / 自動で実行してよい {sum(1 for x in ps if x['auto_executable'])} 件 / 人の承認が要る {sum(1 for x in ps if x['needs_human_approval'])} 件)"
    except Exception:
        pass
    nxt_block = f"\n\n**次にやること**\n{nxt}" if nxt else ""
    msg = f"{head} **{title}**\n\n**{state_line}**\n{status}\n\n**今週の要点**\n{points}{nxt_block}\n\n(自動生成。数字は、取得できた範囲のもの。根拠と全文は、サーバーのレポートにある)"
    post(msg, dry)


def cmd_morning(dry):
    day = datetime.date.today().isoformat()
    p = REPORTS / f"{day}.md"
    if not p.exists():
        return
    md = p.read_text()
    if "要確認" not in "\n".join(md.splitlines()[:6]):
        print("異常なし。送らない")
        return
    post("🔔 **サーバーの朝のレポート: 要確認**\n\n" + "\n".join(md.splitlines()[:14]), dry)


def cmd_failure(unit):
    now = datetime.datetime.now().strftime("%F %H:%M")
    post(f"⚠️ 自動実行が失敗した: `{unit}` ({now})。サーバーのログを確認する必要がある。")


if __name__ == "__main__":
    a = sys.argv[1:]
    dry = "--dry" in a
    a = [x for x in a if x != "--dry"]
    cmd = a[0] if a else ""
    if cmd == "weekly":
        cmd_weekly(dry)
    elif cmd == "morning":
        cmd_morning(dry)
    elif cmd == "failure" and len(a) > 1:
        cmd_failure(a[1])
    elif cmd == "text" and len(a) > 1:
        post(" ".join(a[1:]), dry)
    elif cmd == "check":
        print("設定: 読める" if webhook() else "設定: なし、または形が違う")
    else:
        sys.exit(__doc__)
