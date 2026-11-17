"""App Store の取得 → 日次の行 (App Store Connect API の Analytics Reports。読み取り。標準ライブラリ + openssl)。

鍵は環境変数で渡す (Actions の secret): ASC_ISSUER_ID / ASC_KEY_ID / ASC_KEY_P8 (.p8 の中身)。
アプリは ASC_BUNDLE_ID (バンドル ID) から引く。ASC_APP_ID (Apple ID の数字) があれば、そちらを使う。

Analytics Reports は「レポートの依頼」を 1 回作ると、Apple が毎日レポートを作る (最初は 1〜2 日後)。
  - 依頼を作れるのは Admin の鍵だけ。読むのは Sales / Finance の鍵でもできる。
  - 依頼がなければ、ここで作ろうとする (継続 ONGOING と、過去分 ONE_TIME_SNAPSHOT)。権限がなければ、作らずに理由を残す。
  - 継続の依頼は、しばらく読まれないと Apple が止める (stoppedDueToInactivity)。週次で読むので、ふつうは止まらない。
使うのは、利用者を特定しにくい Standard のレポートだけ。行は日付と種類ごとの合計にする。
"""
import base64, csv, datetime, gzip, io, json, os, re, subprocess, tempfile, time
import urllib.error, urllib.parse, urllib.request

API = "https://api.appstoreconnect.apple.com"
# (レポート名, 指標名の頭, 種類の列 (None は種類で分けない), 数える列)
REPORTS = [
    ("App Store Discovery and Engagement Standard", "engagement", "Event", "Counts"),
    ("App Downloads Standard", "downloads", "Download Type", "Counts"),
    ("App Store Installation and Deletion Standard", "install", "Event", "Counts"),
    ("App Sessions Standard", "sessions", None, "Sessions"),
    ("App Crashes", "crashes", None, "Crashes"),
]


class ApiError(RuntimeError):
    pass


def b64u(b):
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


def der_to_raw(der, n=32):
    """openssl が返す ECDSA の署名 (DER) を、JWT の形 (r と s を 32 バイトずつ) にする。"""
    if len(der) < 8 or der[0] != 0x30:
        raise ApiError("署名の形が不正")
    i = 3 if der[1] & 0x80 else 2  # 長さが 1 バイトを超える場合 (P-256 では出ないが念のため)
    out = b""
    for _ in range(2):
        if der[i] != 0x02:
            raise ApiError("署名の形が不正")
        ln = der[i + 1]
        v = der[i + 2:i + 2 + ln].lstrip(b"\x00")
        if len(v) > n:
            raise ApiError("署名の形が不正")
        out += v.rjust(n, b"\x00")
        i += 2 + ln
    return out


def make_jwt(issuer, key_id, p8, now=None):
    now = int(now or time.time())
    head = b64u(json.dumps({"alg": "ES256", "kid": key_id, "typ": "JWT"}).encode())
    claim = b64u(json.dumps({"iss": issuer, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"}).encode())
    data = f"{head}.{claim}".encode()
    with tempfile.NamedTemporaryFile("w", suffix=".p8") as f:  # 署名のあいだだけ、一時ファイルに置く
        os.chmod(f.name, 0o600)
        f.write(p8.strip() + "\n")
        f.flush()
        r = subprocess.run(["openssl", "dgst", "-sha256", "-sign", f.name], input=data, capture_output=True)
    if r.returncode != 0:
        raise ApiError("openssl の署名に失敗")
    return f"{head}.{claim}.{b64u(der_to_raw(r.stdout))}"


class Client:
    def __init__(self, env=os.environ, opener=None):
        miss = [k for k in ("ASC_ISSUER_ID", "ASC_KEY_ID", "ASC_KEY_P8") if not env.get(k)]
        if miss:
            raise ApiError(f"{', '.join(miss)} が未設定")
        self.env, self.opener = env, opener or urllib.request.urlopen
        self.tok, self.tok_at = None, 0

    def token(self):
        if not self.tok or time.time() - self.tok_at > 900:  # 20 分で切れるので、15 分で作り直す
            self.tok = make_jwt(self.env["ASC_ISSUER_ID"], self.env["ASC_KEY_ID"], self.env["ASC_KEY_P8"])
            self.tok_at = time.time()
        return self.tok

    def call(self, path, body=None):
        url = path if path.startswith("http") else API + path
        req = urllib.request.Request(url, json.dumps(body).encode() if body else None, method="POST" if body else "GET",
                                     headers={"Authorization": "Bearer " + self.token(), "Content-Type": "application/json"})
        try:
            with self.opener(req, timeout=120) as r:
                return json.load(r)
        except urllib.error.HTTPError as e:
            name = urllib.parse.urlparse(url).path.split("/v1/", 1)[-1].split("/")[0]
            raise ApiError(f"{name} が HTTP {e.code}") from None

    def pages(self, path):
        """links.next をたどって、data をすべて返す。"""
        out, nxt = [], path
        for _ in range(50):
            r = self.call(nxt)
            out += r.get("data", [])
            nxt = (r.get("links") or {}).get("next")
            if not nxt:
                break
        return out

    def download(self, url):
        """セグメントの URL は署名つき。認証のヘッダは付けない。"""
        try:
            with self.opener(urllib.request.Request(url), timeout=120) as r:
                return r.read()
        except urllib.error.HTTPError as e:
            raise ApiError(f"セグメントの取得が HTTP {e.code}") from None


def num(x):
    try:
        v = float(str(x).replace(",", ""))
        return v if v == v else None
    except ValueError:
        return None


def slug(h):
    return re.sub(r"[^a-z0-9]+", "_", str(h).lower()).strip("_")


def parse_segment(b):
    """gzip の TSV を、辞書の一覧にする。gzip でなければ、そのまま読む。"""
    try:
        b = gzip.decompress(b)
    except OSError:
        pass
    text = b.decode("utf-8-sig", errors="replace")
    return list(csv.DictReader(io.StringIO(text), delimiter="\t"))


def _col(rows, name):
    if not rows:
        return None
    want = name.lower()
    return next((h for h in rows[0] if h and h.strip().lower() == want), None)


def segment_totals(rows, prefix, kind_col, count_col, app_id, fallback_date):
    """{(日付, 指標): 合計}。種類の列ごとに分け、種類を足した合計 (<prefix>_total) も出す。"""
    dc, cc = _col(rows, "Date"), _col(rows, count_col)
    kc = _col(rows, kind_col) if kind_col else None
    ac = _col(rows, "App Apple Identifier")
    if not cc:
        return {}
    out = {}
    for r in rows:
        if ac and app_id and str(r.get(ac, "")).strip() not in ("", str(app_id)):
            continue
        v = num(r.get(cc))
        if v is None:
            continue
        d = (r.get(dc) or "")[:10] if dc else ""
        d = d if re.fullmatch(r"\d{4}-\d{2}-\d{2}", d) else fallback_date
        if not d:
            continue
        keys = [prefix if not kind_col else f"{prefix}_total"]
        if kc and slug(r.get(kc, "")):
            keys.append(f"{prefix}_{slug(r[kc])}")
        for k in keys:
            out[(d, k)] = out.get((d, k), 0) + v
    return out


def app_id(c, env=os.environ):
    if env.get("ASC_APP_ID"):
        return env["ASC_APP_ID"].strip()
    bundle = (env.get("ASC_BUNDLE_ID") or "").strip()
    if not bundle:
        raise ApiError("ASC_BUNDLE_ID と ASC_APP_ID が未設定")
    d = c.call("/v1/apps?" + urllib.parse.urlencode({"filter[bundleId]": bundle, "fields[apps]": "bundleId"})).get("data", [])
    d = [x for x in d if (x.get("attributes") or {}).get("bundleId") == bundle]
    if not d:
        raise ApiError("バンドル ID のアプリが見つからない")
    return d[0]["id"]


def ensure_requests(c, app):
    """使えるレポートの依頼を返す。なければ作ろうとする。(依頼の一覧, 失敗の一覧, お知らせの一覧)"""
    notes, info = [], []
    reqs = c.pages(f"/v1/apps/{app}/analyticsReportRequests?limit=200")
    live = lambda t: [r for r in reqs if (r.get("attributes") or {}).get("accessType") == t
                      and not (r.get("attributes") or {}).get("stoppedDueToInactivity")]
    for t in ("ONGOING", "ONE_TIME_SNAPSHOT"):
        if live(t):
            continue
        if t == "ONE_TIME_SNAPSHOT" and any((r.get("attributes") or {}).get("accessType") == t for r in reqs):
            continue  # 過去分は 1 回で足りる
        try:
            r = c.call("/v1/analyticsReportRequests", {"data": {
                "type": "analyticsReportRequests", "attributes": {"accessType": t},
                "relationships": {"app": {"data": {"type": "apps", "id": app}}}}})
            reqs.append(r["data"])
            info.append(f"{t} のレポートの依頼を作った (最初のレポートは 1〜2 日後)")
        except ApiError as e:
            if t == "ONGOING":
                notes.append(f"継続のレポートの依頼がなく、作れなかった ({e})。Admin の鍵で 1 回動かす必要がある")
    return [r for r in reqs if not (r.get("attributes") or {}).get("stoppedDueToInactivity")], notes, info


def collect(start, end, env=os.environ, client=None):
    """(行, 取れなかった理由の一覧, お知らせの一覧) を返す。取れなかった経路があっても止めない。
    依頼を作っただけでまだ数字がないときは、失敗にしない (お知らせに残す)。"""
    c = client or Client(env)
    app = app_id(c, env)
    reqs, notes, info = ensure_requests(c, app)
    lo, hi = start.isoformat(), datetime.date.today().isoformat()
    totals = {}  # (日付, 指標) → 値。同じ日のインスタンスが複数あれば、後のもので上書きする (足さない)
    for rq in sorted(reqs, key=lambda r: (r.get("attributes") or {}).get("accessType") == "ONGOING"):  # 継続を後に読み、優先する
        try:
            reports = c.pages(f"/v1/analyticsReportRequests/{rq['id']}/reports?limit=200")
        except ApiError as e:
            notes.append(f"レポートの一覧: {e}")
            continue
        for name, prefix, kind_col, count_col in REPORTS:
            rep = next((r for r in reports if (r.get("attributes") or {}).get("name") == name), None)
            if not rep:
                continue
            try:
                insts = c.pages(f"/v1/analyticsReports/{rep['id']}/instances?filter[granularity]=DAILY&limit=200")
            except ApiError as e:
                notes.append(f"{name}: {e}")
                continue
            for inst in insts:
                pd = ((inst.get("attributes") or {}).get("processingDate") or "")[:10]
                if pd and not (lo <= pd <= hi):
                    continue
                try:
                    segs = c.pages(f"/v1/analyticsReportInstances/{inst['id']}/segments")
                    part = {}
                    for s in segs:
                        u = (s.get("attributes") or {}).get("url")
                        if u:
                            for k, v in segment_totals(parse_segment(c.download(u)), prefix, kind_col, count_col, app, pd).items():
                                part[k] = part.get(k, 0) + v
                    totals.update(part)
                except ApiError as e:
                    notes.append(f"{name} {pd}: {e}")
    if not reqs:
        notes.append("使えるレポートの依頼がない")
    rows = [{"source": "appstore", "metric": m, "entity": str(app), "date": d, "value": v}
            for (d, m), v in sorted(totals.items()) if lo <= d <= end.isoformat()]
    return rows, notes, info
