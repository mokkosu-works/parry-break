#!/usr/bin/env python3
"""YouTube の refresh token を作って、Actions の secret (YT_REFRESH_TOKEN) に直接入れる。手元の Mac で 1 回だけ使う。

  python3 tools/analytics/youtube_auth.py [--repo mokkosu-works/parry-break] [--env analytics] [--print]

1. OAuth クライアント (種類「デスクトップ アプリ」) の ID とシークレットを聞く (画面には出ない)。
2. ブラウザで許可画面を開く。チャンネルのオーナーのアカウントで、2 つの権限 (読み取りだけ) を許可する。
3. 戻ってきた許可コードを、この PC の 127.0.0.1 で受け取り、refresh token に換える (PKCE)。
4. `gh secret set` で YT_CLIENT_ID / YT_CLIENT_SECRET / YT_REFRESH_TOKEN を入れる。値は画面にもファイルにも残さない。
   --print を付けたときだけ、secret に入れずに画面に出す (gh が使えないとき用)。

使う権限は yt-analytics.readonly と youtube.readonly だけ。動画の投稿や設定の変更はできない。
同意画面の公開ステータスが「テスト中」だと、7 日で許可が切れる。「本番環境」にしておく。
"""
import argparse, base64, getpass, hashlib, http.server, json, secrets, subprocess, sys, threading
import urllib.error, urllib.parse, urllib.request, webbrowser

SCOPES = ["https://www.googleapis.com/auth/yt-analytics.readonly", "https://www.googleapis.com/auth/youtube.readonly"]
AUTH_URI, TOKEN_URI = "https://accounts.google.com/o/oauth2/v2/auth", "https://oauth2.googleapis.com/token"
PORT = 8791


def wait_for_code(state, timeout=300):
    got = {}

    class H(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            if q.get("state", [""])[0] == state:
                got.update({k: v[0] for k, v in q.items()})
            ok = "code" in got
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write(("許可を受け取った。このタブは閉じてよい。" if ok else "許可を受け取れなかった。ターミナルを確認する。").encode())

        def log_message(self, *a):
            pass

    srv = http.server.HTTPServer(("127.0.0.1", PORT), H)
    srv.timeout = timeout
    t = threading.Thread(target=srv.handle_request)
    t.start()
    t.join(timeout + 5)
    srv.server_close()
    return got


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--repo", default="mokkosu-works/parry-break")
    ap.add_argument("--env", default="analytics")
    ap.add_argument("--print", action="store_true", help="secret に入れずに画面に出す")
    a = ap.parse_args()
    cid = input("OAuth クライアント ID: ").strip()
    csec = getpass.getpass("OAuth クライアント シークレット (画面には出ない): ").strip()
    if not cid or not csec:
        sys.exit("ID とシークレットが要る")
    verifier = secrets.token_urlsafe(64)
    challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b"=").decode()
    state, redirect = secrets.token_urlsafe(16), f"http://127.0.0.1:{PORT}"
    url = AUTH_URI + "?" + urllib.parse.urlencode({
        "client_id": cid, "redirect_uri": redirect, "response_type": "code", "scope": " ".join(SCOPES),
        "access_type": "offline", "prompt": "select_account consent", "state": state,
        "code_challenge": challenge, "code_challenge_method": "S256"})
    print("\nブラウザで許可画面を開く。チャンネルのオーナーのアカウントを選び、2 つの権限にチェックを付けて続行する。")
    print("「Google はこのアプリを確認していません」と出たら「詳細」→「(アプリ名) に移動」。")
    print(f"開かないときは、この URL を開く:\n{url}\n")
    webbrowser.open(url)
    got = wait_for_code(state)
    if "error" in got:
        sys.exit(f"許可されなかった: {got['error']}")
    if "code" not in got:
        sys.exit("5 分以内に許可を受け取れなかった。やり直す")
    data = urllib.parse.urlencode({"client_id": cid, "client_secret": csec, "code": got["code"], "code_verifier": verifier,
                                   "redirect_uri": redirect, "grant_type": "authorization_code"}).encode()
    try:
        with urllib.request.urlopen(urllib.request.Request(TOKEN_URI, data, method="POST"), timeout=60) as r:
            tok = json.load(r)
    except urllib.error.HTTPError as e:
        sys.exit(f"refresh token に換えられなかった: HTTP {e.code}")
    if "refresh_token" not in tok:
        sys.exit("refresh_token が返ってこなかった。https://myaccount.google.com/permissions でこのアプリを外して、やり直す")
    missing = [s.rsplit("/", 1)[-1] for s in SCOPES if s not in tok.get("scope", "").split()]
    if missing:
        sys.exit(f"足りない権限がある: {', '.join(missing)}。許可画面で、すべてにチェックを付けてやり直す")
    values = {"YT_CLIENT_ID": cid, "YT_CLIENT_SECRET": csec, "YT_REFRESH_TOKEN": tok["refresh_token"]}
    if a.print:
        for k, v in values.items():
            print(f"{k}={v}")
        return
    for k, v in values.items():
        r = subprocess.run(["gh", "secret", "set", k, "--env", a.env, "--repo", a.repo], input=v.encode(), capture_output=True)
        if r.returncode != 0:
            sys.exit(f"{k} を入れられなかった: {r.stderr.decode(errors='replace')[:200]}")
        print(f"入れた: {k} (environment {a.env})")


if __name__ == "__main__":
    main()
