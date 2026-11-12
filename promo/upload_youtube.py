#!/usr/bin/env python3
"""records/videos.csv の動画を YouTube にアップロードする (標準ライブラリだけで動く)。

  python3 promo/upload_youtube.py auth                       # 初回だけ: ブラウザで許可して token を保存
  python3 promo/upload_youtube.py auth-start                 # 離れたオーナーに許可してもらう: URL を作る
  python3 promo/upload_youtube.py auth-finish '<届いた URL>'   # ……届いた URL でトークンを保存する
  python3 promo/upload_youtube.py upload v002b               # 予行 (何も送らず、送る内容を表示する)
  python3 promo/upload_youtube.py upload v002b --yes         # 限定公開 (unlisted) でアップロード
  python3 promo/upload_youtube.py upload v002b --yes --publish-at 2026-11-08T19:00:00+09:00   # 予約公開
  python3 promo/upload_youtube.py upload v002b --yes --privacy public                        # すぐ公開

安全のための決めごと:
- --yes がなければ、何も送らない (予行)。
- 公開の範囲の既定は unlisted。public にするには --privacy public を明示する。
- csv の「投稿日」が入っている行は、二重投稿を避けるため送らない。
- 認証の鍵 (client_secret.json と token.json) は ~/.config/parry-break/youtube/ に置く。リポジトリには入れない。

事前の準備 (一度だけ):
1. https://console.cloud.google.com/ でプロジェクトを作り、「YouTube Data API v3」を有効にする。
2. 「OAuth 同意画面」を設定する。ユーザーの種類は「外部」。公開ステータスが「テスト中」のままだと、
   リフレッシュトークンが 7 日で切れる (動画アップロードの権限は基本スコープではないため)。
   自分だけが使うなら「本番環境に公開」にしておく (「未確認のアプリ」の警告が出るが、自分のチャンネルには使える)。
   「テスト中」で使う場合は、テストユーザーに自分のアカウントを入れ、7 日ごとに auth をやり直す。
3. 「認証情報」で OAuth クライアント ID を作る。種類は「デスクトップ アプリ」。JSON をダウンロードして
   ~/.config/parry-break/youtube/client_secret.json に置く。
4. `python3 promo/upload_youtube.py auth` を実行し、投稿先のチャンネルの Google アカウントで許可する。
"""
import argparse, base64, csv, datetime, hashlib, http.server, json, os, pathlib, re, secrets, sys
import threading, urllib.error, urllib.parse, urllib.request, webbrowser

ROOT = pathlib.Path(__file__).resolve().parent.parent
CONF = pathlib.Path(os.environ.get("PARRY_YT_DIR", "~/.config/parry-break/youtube")).expanduser()
SCOPE = "https://www.googleapis.com/auth/youtube.upload"
AUTH_URI, TOKEN_URI = "https://accounts.google.com/o/oauth2/v2/auth", "https://oauth2.googleapis.com/token"
UPLOAD_URI = "https://www.googleapis.com/upload/youtube/v3/videos"
CSV_PATH = ROOT / "records/videos.csv"
LOG_PATH = ROOT / "records/youtube_uploads.csv"


def die(msg):
    sys.exit(f"エラー: {msg}")


# ---------------------------------------------------------------- 認証
def client():
    p = CONF / "client_secret.json"
    if not p.exists():
        die(f"{p} がない。Google Cloud Console で「デスクトップ アプリ」の OAuth クライアントを作り、JSON をここへ置く")
    d = json.loads(p.read_text())
    return d.get("installed") or d.get("web") or die("client_secret.json の形が違う")


def post_form(url, data):
    req = urllib.request.Request(url, urllib.parse.urlencode(data).encode(), method="POST")
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        die(f"{url} が {e.code}: {e.read().decode(errors='replace')}")


def cmd_auth(_):
    c = client()
    verifier = secrets.token_urlsafe(64)
    challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b"=").decode()
    state = secrets.token_urlsafe(16)
    got = {}

    class H(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            got.update({k: v[0] for k, v in q.items()})
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.end_headers()
            self.wfile.write("許可を受け取った。このタブは閉じてよい。".encode())

        def log_message(self, *a):
            pass

    srv = http.server.HTTPServer(("127.0.0.1", 0), H)
    redirect = f"http://127.0.0.1:{srv.server_port}"
    url = AUTH_URI + "?" + urllib.parse.urlencode({
        "client_id": c["client_id"], "redirect_uri": redirect, "response_type": "code", "scope": SCOPE,
        "access_type": "offline", "prompt": "select_account consent", "state": state,
        "code_challenge": challenge, "code_challenge_method": "S256"})
    print("次の URL をブラウザで開いて、YouTube チャンネルのアカウントで許可する:\n\n" + url + "\n")
    webbrowser.open(url)
    t = threading.Thread(target=srv.handle_request)
    t.start()
    t.join(timeout=300)
    if got.get("state") != state or "code" not in got:
        die(f"許可を受け取れなかった: {got}")
    tok = post_form(TOKEN_URI, {"client_id": c["client_id"], "client_secret": c.get("client_secret", ""),
                                "code": got["code"], "code_verifier": verifier, "redirect_uri": redirect,
                                "grant_type": "authorization_code"})
    save_token(tok)


def save_token(tok):
    if "refresh_token" not in tok:
        die("refresh_token が返ってこなかった。https://myaccount.google.com/permissions でこのアプリを外して、やり直す")
    CONF.mkdir(parents=True, exist_ok=True)
    tp = CONF / "token.json"
    tp.write_text(json.dumps({"refresh_token": tok["refresh_token"], "saved": datetime.datetime.now().isoformat()}))
    tp.chmod(0o600)
    print(f"保存した: {tp}")


# 離れた場所にいるチャンネルのオーナーに、リンクを開いて許可だけしてもらう 2 段階の認証。
# 1) auth-start で URL を作り、オーナーに送る。2) オーナーが許可すると、ブラウザが 127.0.0.1 の
# 「アクセスできません」の画面になる。そのアドレス欄の URL をもらい、3) auth-finish に貼る。
# トークンはこの PC にだけできる。オーナーが送る URL の許可コードは、1 回限りで、手元の秘密の値 (PKCE) がないと使えない。
REMOTE_REDIRECT = "http://127.0.0.1:8765"
PENDING = CONF / "pending_auth.json"


def cmd_auth_start(_):
    c = client()
    verifier = secrets.token_urlsafe(64)
    challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b"=").decode()
    state = secrets.token_urlsafe(16)
    CONF.mkdir(parents=True, exist_ok=True)
    PENDING.write_text(json.dumps({"verifier": verifier, "state": state, "redirect": REMOTE_REDIRECT,
                                   "created": datetime.datetime.now().isoformat()}))
    PENDING.chmod(0o600)
    url = AUTH_URI + "?" + urllib.parse.urlencode({
        "client_id": c["client_id"], "redirect_uri": REMOTE_REDIRECT, "response_type": "code", "scope": SCOPE,
        "access_type": "offline", "prompt": "select_account consent", "state": state,
        "code_challenge": challenge, "code_challenge_method": "S256"})
    print("次の URL を、チャンネルのオーナーに送る (オーナーの Google アカウントで開いてもらう):\n\n" + url + "\n")
    print("オーナーへの伝言:\n"
          "  1. この URL を、ふだんのブラウザで開く。\n"
          "  2. チャンネルを管理しているアカウントを選ぶ (複数のチャンネルがあれば Mokkosu Works を選ぶ)。\n"
          "  3. 「Google はこのアプリを確認していません」と出たら、「詳細」→「移動」と進む。\n"
          "  4. 「YouTube への動画のアップロード」の権限を許可する。\n"
          "  5. 最後に「このサイトにアクセスできません」のエラー画面になるが、正常。\n"
          "     アドレス欄の URL (http://127.0.0.1:8765/?state=…&code=… で始まる) を全部コピーして送る。\n")
    print("URL が届いたら:  python3 promo/upload_youtube.py auth-finish '<届いた URL>'")


def cmd_auth_finish(a):
    if not PENDING.exists():
        die("先に auth-start を実行する (待機中の認証がない)")
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
    save_token(tok)
    PENDING.unlink()


def access_token():
    c, tp = client(), CONF / "token.json"
    if not tp.exists():
        die("先に `upload_youtube.py auth` を実行する")
    rt = json.loads(tp.read_text())["refresh_token"]
    tok = post_form(TOKEN_URI, {"client_id": c["client_id"], "client_secret": c.get("client_secret", ""),
                                "refresh_token": rt, "grant_type": "refresh_token"})
    return tok["access_token"]


# ---------------------------------------------------------------- 投稿内容
def read_rows():
    if not CSV_PATH.exists():
        die(f"{CSV_PATH} がない")
    with CSV_PATH.open(encoding="utf-8-sig", newline="") as f:
        r = csv.DictReader(f)
        return r.fieldnames, list(r)


def parse_post(rid):
    """posts/{id}.txt の「=== YouTube ===」の [タイトル] と [説明文] を読む。"""
    p = ROOT / f"posts/{rid}.txt"
    if not p.exists():
        die(f"{p} がない")
    text = p.read_text(encoding="utf-8")
    m = re.search(r"=== YouTube ===\n(.*?)(?:\n=== |\Z)", text, re.S)
    if not m:
        die(f"{p} に「=== YouTube ===」がない")
    sec = m.group(1)
    t = re.search(r"\[タイトル\]\n(.*?)\n\n\[説明文\]\n(.*)", sec, re.S)
    if not t:
        die(f"{p} の [タイトル] / [説明文] が読めない")
    return t.group(1).strip(), t.group(2).strip()


def build_body(title, desc, privacy, publish_at, shorts_tag):
    if shorts_tag and "#shorts" not in desc.lower():
        desc += "\n#Shorts"
    tags = [h[1:] for h in re.findall(r"#\S+", desc)][:15]
    status = {"privacyStatus": privacy, "selfDeclaredMadeForKids": False}
    if publish_at:
        status.update(privacyStatus="private", publishAt=publish_at)
    return {"snippet": {"title": title, "description": desc, "tags": tags, "categoryId": "20",
                        "defaultLanguage": "ja"}, "status": status}


# ---------------------------------------------------------------- アップロード
def cmd_upload(a):
    fields, rows = read_rows()
    row = next((r for r in rows if r["id"] == a.id), None)
    if not row:
        die(f"{a.id} は {CSV_PATH} にない")
    if row["投稿日"].strip():
        die(f"{a.id} は投稿日 ({row['投稿日']}) が入っている。二重投稿を避けるため送らない")
    video = ROOT / row["ファイルパス"]
    if not video.exists():
        die(f"{video} がない")
    title, desc = parse_post(a.id)
    if len(title) > 100:
        die(f"タイトルが {len(title)} 文字 (上限 100)")
    if a.publish_at:
        try:
            when = datetime.datetime.fromisoformat(a.publish_at)
        except ValueError:
            die("--publish-at は 2026-11-08T19:00:00+09:00 のように、タイムゾーンつきで書く")
        if when.tzinfo is None:
            die("--publish-at にはタイムゾーン (+09:00 など) が要る")
        if when <= datetime.datetime.now(when.tzinfo) + datetime.timedelta(minutes=15):
            die("--publish-at は、いまから 15 分以上先にする")
        a.publish_at = when.isoformat()
    body = build_body(title, desc, a.privacy, a.publish_at, not a.no_shorts_tag)
    if len(body["snippet"]["description"]) > 5000:
        die("説明文が 5000 文字を超えている")
    size = video.stat().st_size

    print(f"動画: {video.relative_to(ROOT)} ({size / 1e6:.1f} MB)")
    print(f"タイトル: {body['snippet']['title']}")
    print(f"公開の範囲: {body['status']['privacyStatus']}" + (f" → {a.publish_at} に公開" if a.publish_at else ""))
    print("説明文:\n" + "\n".join("  " + l for l in body["snippet"]["description"].splitlines()))
    if not a.yes:
        print("\n予行です。何も送っていません。送るには --yes を付ける。")
        return
    if body["status"]["privacyStatus"] == "public" and not a.publish_at:
        print("\n注意: すぐに公開されます。")

    tok = access_token()
    init = urllib.request.Request(
        UPLOAD_URI + "?uploadType=resumable&part=snippet,status", json.dumps(body).encode(), method="POST",
        headers={"Authorization": f"Bearer {tok}", "Content-Type": "application/json; charset=UTF-8",
                 "X-Upload-Content-Length": str(size), "X-Upload-Content-Type": "video/mp4"})
    try:
        with urllib.request.urlopen(init, timeout=60) as r:
            loc = r.headers["Location"]
    except urllib.error.HTTPError as e:
        die(f"開始に失敗 {e.code}: {e.read().decode(errors='replace')}")
    put = urllib.request.Request(loc, video.read_bytes(), method="PUT",
                                 headers={"Content-Length": str(size), "Content-Type": "video/mp4"})
    try:
        with urllib.request.urlopen(put, timeout=600) as r:
            res = json.load(r)
    except urllib.error.HTTPError as e:
        die(f"アップロードに失敗 {e.code}: {e.read().decode(errors='replace')}")
    vid = res["id"]
    print(f"\nアップロードした: https://www.youtube.com/shorts/{vid}  (動画 ID {vid})")

    # 記録 (csv の投稿日・媒体、と動画 ID の対応)
    day = (datetime.datetime.fromisoformat(a.publish_at).date() if a.publish_at else datetime.date.today())
    row["投稿日"], row["媒体"] = day.isoformat(), "YouTube Shorts"
    with CSV_PATH.open("w", encoding="utf-8-sig", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        w.writerows(rows)
    new = not LOG_PATH.exists()
    with LOG_PATH.open("a", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        if new:
            w.writerow(["id", "動画ID", "公開の範囲", "公開予約", "アップロード日時"])
        w.writerow([a.id, vid, body["status"]["privacyStatus"], a.publish_at or "",
                    datetime.datetime.now().isoformat(timespec="seconds")])
    print("records/videos.csv の投稿日と媒体を更新した。")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("auth").set_defaults(fn=cmd_auth)
    sub.add_parser("auth-start", help="離れたオーナーに許可してもらう: 1) URL を作る").set_defaults(fn=cmd_auth_start)
    f = sub.add_parser("auth-finish", help="離れたオーナーに許可してもらう: 2) 届いた URL でトークンを保存する")
    f.add_argument("url")
    f.set_defaults(fn=cmd_auth_finish)
    u = sub.add_parser("upload")
    u.add_argument("id")
    u.add_argument("--yes", action="store_true", help="実際に送る (なければ予行)")
    u.add_argument("--privacy", choices=["private", "unlisted", "public"], default="unlisted")
    u.add_argument("--publish-at", help="予約公開の日時 (例 2026-11-08T19:00:00+09:00)。private で上げて、その時刻に公開する")
    u.add_argument("--no-shorts-tag", action="store_true", help="説明文に #Shorts を足さない")
    u.set_defaults(fn=cmd_upload)
    a = ap.parse_args()
    a.fn(a)


main()
