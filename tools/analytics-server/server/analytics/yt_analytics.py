#!/usr/bin/env python3
"""YouTube アナリティクスの取得 (読み取り専用)。標準ライブラリだけで動く。

  python3 yt_analytics.py auth-start             # 許可のための URL を作る
  python3 yt_analytics.py auth-finish '<URL>'    # 許可後に出るエラー画面のアドレスを貼って、鍵を保存する
  python3 yt_analytics.py check                  # つながるか、取れる指標は何かを確認する

鍵 (client_secret.json と token.json) は、このスクリプトの隣の state/ に置く (権限 600)。
使う権限は、読み取りだけ: yt-analytics.readonly と youtube.readonly。動画の投稿や、設定の変更はできない。
"""
import argparse, base64, datetime, hashlib, json, pathlib, secrets, sys
import urllib.error, urllib.parse, urllib.request

BASE = pathlib.Path(__file__).resolve().parent
STATE = BASE / "state"
SCOPES = ["https://www.googleapis.com/auth/yt-analytics.readonly",
          "https://www.googleapis.com/auth/youtube.readonly"]
AUTH_URI, TOKEN_URI = "https://accounts.google.com/o/oauth2/v2/auth", "https://oauth2.googleapis.com/token"
ANALYTICS = "https://youtubeanalytics.googleapis.com/v2/reports"
DATA_API = "https://www.googleapis.com/youtube/v3"
REDIRECT = "http://127.0.0.1:8791"
PENDING = STATE / "pending_auth.json"


def die(msg):
    sys.exit(f"エラー: {msg}")


def client():
    p = STATE / "client_secret.json"
    if not p.exists():
        die(f"{p} がない")
    d = json.loads(p.read_text())
    return d.get("installed") or die("client_secret.json が「デスクトップ アプリ」の形ではない")


def post_form(url, data):
    req = urllib.request.Request(url, urllib.parse.urlencode(data).encode(), method="POST")
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        die(f"{url} が {e.code}: {e.read().decode(errors='replace')[:600]}")


def write_private(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    path.chmod(0o600)


def cmd_auth_start(_):
    c = client()
    verifier = secrets.token_urlsafe(64)
    challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b"=").decode()
    state = secrets.token_urlsafe(16)
    write_private(PENDING, json.dumps({"verifier": verifier, "state": state, "redirect": REDIRECT,
                                       "created": datetime.datetime.now().isoformat()}))
    url = AUTH_URI + "?" + urllib.parse.urlencode({
        "client_id": c["client_id"], "redirect_uri": REDIRECT, "response_type": "code",
        "scope": " ".join(SCOPES), "access_type": "offline", "prompt": "select_account consent",
        "state": state, "code_challenge": challenge, "code_challenge_method": "S256"})
    print("次の URL を、チャンネルのオーナーのアカウントで開いて許可する:\n\n" + url + "\n")
    print("手順:\n"
          "  1. チャンネルを持っているアカウントを選ぶ (複数のチャンネルがあれば Mokkosu Works を選ぶ)。\n"
          "  2. 「Google はこのアプリを確認していません」と出たら、「詳細」→「(アプリ名) に移動」と進む。\n"
          "  3. 権限の確認画面で、2 つとも (YouTube アナリティクスと YouTube アカウントの表示) チェックを付けて続行する。\n"
          "  4. 最後に「このサイトにアクセスできません」のエラー画面になるが、正常。\n"
          "     アドレス欄の URL (http://127.0.0.1:8791/?state=…&code=… で始まる) を全部コピーする。\n")
    print("そのあとで:  python3 yt_analytics.py auth-finish '<コピーした URL>'")


def cmd_auth_finish(a):
    if not PENDING.exists():
        die("先に auth-start を実行する")
    pend = json.loads(PENDING.read_text())
    q = urllib.parse.parse_qs(urllib.parse.urlparse(a.url).query)
    if "error" in q:
        die(f"許可されなかった: {q['error'][0]}")
    if q.get("state", [""])[0] != pend["state"] or "code" not in q:
        die("貼られた URL が、この auth-start のものではない (state が違う、または code がない)。URL 全体を貼る")
    c = client()
    tok = post_form(TOKEN_URI, {"client_id": c["client_id"], "client_secret": c.get("client_secret", ""),
                                "code": q["code"][0], "code_verifier": pend["verifier"],
                                "redirect_uri": pend["redirect"], "grant_type": "authorization_code"})
    if "refresh_token" not in tok:
        die("refresh_token が返ってこなかった。https://myaccount.google.com/permissions でこのアプリを外して、やり直す")
    granted = set(tok.get("scope", "").split())
    missing = [s for s in SCOPES if s not in granted]
    write_private(STATE / "token.json", json.dumps({"refresh_token": tok["refresh_token"],
                                                    "scope": sorted(granted),
                                                    "saved": datetime.datetime.now().isoformat()}))
    PENDING.unlink()
    print("保存した: state/token.json (権限 600)")
    print("許可された範囲:", ", ".join(s.rsplit("/", 1)[-1] for s in sorted(granted)))
    if missing:
        print("警告: 足りない権限がある ->", ", ".join(s.rsplit("/", 1)[-1] for s in missing),
              "\n  許可画面で、すべてのチェックを付けてやり直す。")


def access_token():
    c, tp = client(), STATE / "token.json"
    if not tp.exists():
        die("先に auth-start / auth-finish を実行する")
    rt = json.loads(tp.read_text())["refresh_token"]
    return post_form(TOKEN_URI, {"client_id": c["client_id"], "client_secret": c.get("client_secret", ""),
                                 "refresh_token": rt, "grant_type": "refresh_token"})["access_token"]


def api_get(url, params, tok):
    req = urllib.request.Request(url + "?" + urllib.parse.urlencode(params),
                                 headers={"Authorization": f"Bearer {tok}"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        return {"_error": e.code, "_body": e.read().decode(errors="replace")[:500]}


def cmd_check(_):
    tok = access_token()
    ch = api_get(DATA_API + "/channels", {"part": "snippet,statistics", "mine": "true"}, tok)
    if "_error" in ch:
        die(f"チャンネル情報が取れない: {ch}")
    item = (ch.get("items") or [None])[0]
    if not item:
        die("この許可のアカウントに、チャンネルが見つからない")
    print(f"チャンネル: {item['snippet']['title']}  (動画 {item['statistics'].get('videoCount')} 本)")

    end = datetime.date.today() - datetime.timedelta(days=3)
    start = end - datetime.timedelta(days=27)
    base = {"ids": "channel==MINE", "startDate": start.isoformat(), "endDate": end.isoformat()}
    print(f"\n[1] 期間 {start} 〜 {end} の動画別 (Shorts と通常動画を分ける)")
    r = api_get(ANALYTICS, {**base, "dimensions": "video,creatorContentType",
                            "metrics": "views,engagedViews,averageViewDuration,averageViewPercentage",
                            "sort": "-views", "maxResults": 5}, tok)
    show(r)
    print("\n[2] 全体の日別 (直近 3 日分)")
    r = api_get(ANALYTICS, {**base, "dimensions": "day", "metrics": "views,estimatedMinutesWatched,subscribersGained",
                            "sort": "-day", "maxResults": 3}, tok)
    show(r)
    vid = None
    r1 = api_get(ANALYTICS, {**base, "dimensions": "video", "metrics": "views", "sort": "-views", "maxResults": 1}, tok)
    if r1.get("rows"):
        vid = r1["rows"][0][0]
    print(f"\n[3] 視聴維持率の曲線 (動画 {vid})")
    if vid:
        r = api_get(ANALYTICS, {**base, "dimensions": "elapsedVideoTimeRatio",
                                "metrics": "audienceWatchRatio,relativeRetentionPerformance",
                                "filters": f"video=={vid}", "sort": "elapsedVideoTimeRatio"}, tok)
        show(r, limit=6)


def show(r, limit=5):
    if "_error" in r:
        print("  取れなかった:", r["_error"], r["_body"][:300])
        return
    cols = [h["name"] for h in r.get("columnHeaders", [])]
    rows = r.get("rows", [])
    print("  列:", cols, f"/ {len(rows)} 行")
    for row in rows[:limit]:
        print("  ", row)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("auth-start").set_defaults(fn=cmd_auth_start)
    f = sub.add_parser("auth-finish")
    f.add_argument("url")
    f.set_defaults(fn=cmd_auth_finish)
    sub.add_parser("check").set_defaults(fn=cmd_check)
    a = ap.parse_args()
    a.fn(a)


if __name__ == "__main__":
    main()
