#!/usr/bin/env python3
"""Google Play のレポート (Cloud Storage のバルクレポート) を、読み取り専用で取得する。標準ライブラリ + openssl で動く。

  python3 play_fetch.py check              # つながるか、バケットに何があるかを確認する
  python3 play_fetch.py fetch              # 今月と先月の CSV を data/play_raw/<日付>/ に保存する

鍵 (play_sa.json) は state/ に置く (権限 600)。サービスアカウントは、Play Console で「読み取り専用」の権限だけを与えたもの。
設定 (play_config.json): {"bucket": "pubsite_prod_…", "packages": ["com.example.app"]}
バルクレポートは、3〜7 日遅れで月ごとの CSV (UTF-16) に入る。
"""
import base64, csv, datetime, io, json, pathlib, subprocess, sys, tempfile, time
import urllib.error, urllib.parse, urllib.request

BASE = pathlib.Path(__file__).resolve().parent
STATE = BASE / "state"
DATA = BASE / "data"
SCOPE = "https://www.googleapis.com/auth/devstorage.read_only"
GCS = "https://storage.googleapis.com/storage/v1/b"

# 取得するレポート: (フォルダ, ファイル名の型)。{p}=パッケージ名、{ym}=年月、{dim}=区分
REPORTS = [
    ("stats/installs", "installs_{p}_{ym}_overview.csv"),
    ("stats/ratings", "ratings_{p}_{ym}_overview.csv"),
    ("stats/crashes", "crashes_{p}_{ym}_overview.csv"),
    ("reviews", "reviews_{p}_{ym}.csv"),
]


def die(msg):
    sys.exit(f"エラー: {msg}")


def b64u(b):
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


def config():
    p = STATE / "play_config.json"
    if not p.exists():
        die(f"{p} がない")
    return json.loads(p.read_text())


def sign_rs256(private_key_pem, data: bytes) -> bytes:
    """openssl で RS256 の署名を作る。鍵は、権限 600 の一時ファイルに、署名のあいだだけ置く。"""
    with tempfile.NamedTemporaryFile("w", suffix=".pem") as f:
        f.write(private_key_pem)
        f.flush()
        r = subprocess.run(["openssl", "dgst", "-sha256", "-sign", f.name], input=data, capture_output=True)
    if r.returncode != 0:
        die("openssl の署名に失敗: " + r.stderr.decode(errors="replace")[:200])
    return r.stdout


def make_jwt(sa, scope, now=None):
    now = int(now or time.time())
    head = b64u(json.dumps({"alg": "RS256", "typ": "JWT"}).encode())
    claim = b64u(json.dumps({"iss": sa["client_email"], "scope": scope, "aud": sa["token_uri"],
                             "iat": now, "exp": now + 3000}).encode())
    signing_input = f"{head}.{claim}".encode()
    return f"{head}.{claim}.{b64u(sign_rs256(sa['private_key'], signing_input))}"


def access_token(scope=SCOPE):
    p = STATE / "play_sa.json"
    if not p.exists():
        die(f"{p} がない")
    sa = json.loads(p.read_text())
    data = urllib.parse.urlencode({"grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
                                   "assertion": make_jwt(sa, scope)}).encode()
    try:
        with urllib.request.urlopen(urllib.request.Request(sa["token_uri"], data, method="POST"), timeout=60) as r:
            return json.load(r)["access_token"]
    except urllib.error.HTTPError as e:
        die(f"トークンが取れない {e.code}: {e.read().decode(errors='replace')[:300]}")


def gcs_get(url, tok, raw=False):
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {tok}"})
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return r.read() if raw else json.load(r)
    except urllib.error.HTTPError as e:
        return {"_error": e.code, "_body": e.read().decode(errors="replace")[:300]}


def list_objects(bucket, prefix, tok):
    out, page = [], None
    while True:
        params = {"prefix": prefix, "maxResults": 1000}
        if page:
            params["pageToken"] = page
        r = gcs_get(f"{GCS}/{bucket}/o?" + urllib.parse.urlencode(params), tok)
        if "_error" in r:
            return r
        out += [i["name"] for i in r.get("items", [])]
        page = r.get("nextPageToken")
        if not page:
            return out


def download(bucket, name, tok):
    return gcs_get(f"{GCS}/{bucket}/o/{urllib.parse.quote(name, safe='')}?alt=media", tok, raw=True)


def decode_csv(b):
    """Play のバルクレポートは UTF-16 (BOM つき)。UTF-8 のものにも対応する。"""
    for enc in ("utf-16", "utf-8-sig"):
        try:
            text = b.decode(enc)
            if "," in text.splitlines()[0]:
                return list(csv.DictReader(io.StringIO(text)))
        except (UnicodeError, IndexError):
            continue
    return []


def months(n=2, today=None):
    d = today or datetime.date.today()
    out = []
    for _ in range(n):
        out.append(f"{d.year}{d.month:02d}")
        d = (d.replace(day=1) - datetime.timedelta(days=1))
    return out


def cmd_check(_):
    cfg, tok = config(), access_token()
    print("トークン: 取れた")
    for folder, _pat in REPORTS:
        names = list_objects(cfg["bucket"], folder + "/", tok)
        if isinstance(names, dict):
            print(f"[NG] {folder}/: {names['_error']} {names['_body'][:160]}")
        else:
            print(f"[OK] {folder}/: {len(names)} ファイル。直近: {names[-3:]}")


def cmd_fetch(_):
    cfg, tok = config(), access_token()
    day = datetime.date.today().isoformat()
    out = DATA / "play_raw" / day
    out.mkdir(parents=True, exist_ok=True)
    got = {}
    for p in cfg["packages"]:
        for folder, pat in REPORTS:
            for ym in months(2):
                name = f"{folder}/" + pat.format(p=p, ym=ym)
                b = download(cfg["bucket"], name, tok)
                if isinstance(b, dict):
                    got[name] = f"なし ({b['_error']})"
                    continue
                rows = decode_csv(b)
                (out / name.replace("/", "__")).write_text(json.dumps(rows, ensure_ascii=False))
                got[name] = f"{len(rows)} 行"
    for k, v in got.items():
        print(f"{k}: {v}")
    return day


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    {"check": cmd_check, "fetch": cmd_fetch}.get(cmd, lambda _: sys.exit(__doc__))(None)
