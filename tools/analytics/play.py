"""Google Play の取得 → 日次の行 (読み取り専用。標準ライブラリ + openssl)。

鍵は環境変数で渡す (Actions の secret): PLAY_SA_JSON (サービスアカウントの JSON 全体) / PLAY_BUCKET / PLAY_PACKAGES (カンマ区切り)。
  - Vitals (クラッシュ率・ANR 率): Play Developer Reporting API。利用者が少ないと、データが出ない。
  - バルクレポート (インストール・評価・クラッシュ・レビュー): Cloud Storage のバケットの月次 CSV。3〜7 日遅れ。
レビューの文面は読まない (件数と星だけを行にする)。
"""
import base64, csv, datetime, io, json, os, re, subprocess, tempfile, time
import urllib.error, urllib.parse, urllib.request

GCS = "https://storage.googleapis.com/storage/v1/b"
VITALS = "https://playdeveloperreporting.googleapis.com/v1beta1/apps/{p}/{m}"
SC_GCS = "https://www.googleapis.com/auth/devstorage.read_only"
SC_VITALS = "https://www.googleapis.com/auth/playdeveloperreporting"
REPORTS = [("stats/installs", "installs_{p}_{ym}_overview.csv"), ("stats/ratings", "ratings_{p}_{ym}_overview.csv"),
           ("stats/crashes", "crashes_{p}_{ym}_overview.csv"), ("reviews", "reviews_{p}_{ym}.csv")]
VITALS_SETS = (("crashRateMetricSet", ["crashRate", "userPerceivedCrashRate", "distinctUsers"]),
               ("anrRateMetricSet", ["anrRate", "userPerceivedAnrRate", "distinctUsers"]))


class ApiError(RuntimeError):
    pass


def b64u(b):
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


def make_jwt(sa, scope, now=None):
    now = int(now or time.time())
    head = b64u(json.dumps({"alg": "RS256", "typ": "JWT"}).encode())
    claim = b64u(json.dumps({"iss": sa["client_email"], "scope": scope, "aud": sa["token_uri"], "iat": now, "exp": now + 3000}).encode())
    data = f"{head}.{claim}".encode()
    with tempfile.NamedTemporaryFile("w", suffix=".pem") as f:  # 署名のあいだだけ、一時ファイルに置く
        os.chmod(f.name, 0o600)
        f.write(sa["private_key"])
        f.flush()
        r = subprocess.run(["openssl", "dgst", "-sha256", "-sign", f.name], input=data, capture_output=True)
    if r.returncode != 0:
        raise ApiError("openssl の署名に失敗")
    return f"{head}.{claim}.{b64u(r.stdout)}"


def access_token(scope, env=os.environ):
    if not env.get("PLAY_SA_JSON"):
        raise ApiError("PLAY_SA_JSON が未設定")
    sa = json.loads(env["PLAY_SA_JSON"])
    data = urllib.parse.urlencode({"grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer", "assertion": make_jwt(sa, scope)}).encode()
    try:
        with urllib.request.urlopen(urllib.request.Request(sa["token_uri"], data, method="POST"), timeout=60) as r:
            return json.load(r)["access_token"]
    except urllib.error.HTTPError as e:
        raise ApiError(f"トークンが取れない HTTP {e.code}") from None


def _call(url, tok, body=None, raw=False):
    req = urllib.request.Request(url, json.dumps(body).encode() if body else None, method="POST" if body else "GET",
                                 headers={"Authorization": "Bearer " + tok, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return r.read() if raw else json.load(r)
    except urllib.error.HTTPError as e:
        raise ApiError(f"{url.split('?')[0].rsplit('/', 2)[-2]}/{url.split('?')[0].rsplit('/', 1)[-1]} が HTTP {e.code}") from None


def slug(h):
    return re.sub(r"[^a-z0-9]+", "_", h.lower()).strip("_")


def num(x):
    try:
        v = float(str(x).replace(",", ""))
        return v if v == v else None
    except ValueError:
        return None


def decode_csv(b):
    """バルクレポートは UTF-16 (BOM つき)。UTF-8 にも対応する。"""
    for enc in ("utf-16", "utf-8-sig"):
        try:
            text = b.decode(enc)
            if "," in text.splitlines()[0]:
                return list(csv.DictReader(io.StringIO(text)))
        except (UnicodeError, IndexError):
            continue
    return []


def month_list(start, end):
    out, d = [], start.replace(day=1)
    while d <= end:
        out.append(f"{d.year}{d.month:02d}")
        d = (d.replace(day=28) + datetime.timedelta(days=4)).replace(day=1)
    return out


def _date_col(rows):
    return next((h for h in rows[0] if "date" in h.lower()), None) if rows else None


def bulk_rows(folder, pkg, csv_rows, start, end):
    """バルクレポートの CSV を、日次の行にする。数値の列は、そのまま指標にする (列名は slug にする)。レビューは件数と星の平均だけ。"""
    dc = _date_col(csv_rows)
    if not dc:
        return []
    inwin = [r for r in csv_rows if r.get(dc) and start.isoformat() <= r[dc][:10] <= end.isoformat()]
    out = []
    if folder == "reviews":
        star = next((h for h in (csv_rows[0] if csv_rows else {}) if "star" in h.lower()), None)
        by = {}
        for r in inwin:
            by.setdefault(r[dc][:10], []).append(num(r.get(star)) if star else None)
        for d, stars in by.items():
            out.append({"source": "play", "metric": "review_count", "entity": pkg, "date": d, "value": len(stars)})
            st = [s for s in stars if s is not None]
            if st:
                out.append({"source": "play", "metric": "review_star_avg", "entity": pkg, "date": d, "value": round(sum(st) / len(st), 4)})
        return out
    prefix = folder.split("/")[-1] + "_"
    for r in inwin:
        for h, v in r.items():
            if h == dc or "package" in h.lower() or v in (None, ""):
                continue
            n = num(v)
            if n is not None:
                out.append({"source": "play", "metric": prefix + slug(h), "entity": pkg, "date": r[dc][:10], "value": n})
    return out


def vitals_rows(ms, pkg, query_rows, entity=None):
    out = []
    for row in query_rows:
        t = row.get("startTime") or {}
        try:
            d = datetime.date(t["year"], t["month"], t["day"]).isoformat()
        except KeyError:
            continue
        ver = next((x.get("stringValue") for x in row.get("dimensions", []) if x.get("dimension") == "versionCode"), None)
        for m in row.get("metrics", []):
            v = (m.get("decimalValue") or {}).get("value")
            if v is not None:
                out.append({"source": "play", "metric": "vitals_" + slug(re.sub(r"(?<=[a-z])(?=[A-Z])", "_", m["metric"])), "entity": f"{pkg}#{ver}" if ver else pkg,
                            "date": d, "value": float(v)})
    return out


def _tz_date(d):
    return {"year": d.year, "month": d.month, "day": d.day, "timeZone": {"id": "America/Los_Angeles"}}


def collect_vitals(pkg, start, end):
    """Vitals を取る。どちらかの指標が取れなくても、取れたものは返す。(行, 取れなかった理由の一覧)"""
    tok = access_token(SC_VITALS)
    rows, notes = [], []
    for ms, metrics in VITALS_SETS:
        try:
            info = _call(VITALS.format(p=pkg, m=ms), tok)
            fr = [f for f in info.get("freshnessInfo", {}).get("freshnesses", []) if f["aggregationPeriod"] == "DAILY"]
            if not fr:
                notes.append(f"{ms}: DAILY の鮮度がない")
                continue
            e = fr[0]["latestEndTime"]
            last = datetime.date(e["year"], e["month"], e["day"])  # この日の手前まで
            s = max(start, last - datetime.timedelta(days=28))
            spec = {"aggregationPeriod": "DAILY", "startTime": _tz_date(s), "endTime": _tz_date(last)}
            for dims in (None, ["versionCode"]):
                body = {"timelineSpec": spec, "metrics": metrics, "pageSize": 1000, **({"dimensions": dims} if dims else {})}
                r = _call(VITALS.format(p=pkg, m=ms) + ":query", tok, body)
                rows += vitals_rows(ms, pkg, r.get("rows", []))
        except ApiError as ex:
            notes.append(f"{ms}: {ex}")
    return rows, notes


def collect_bulk(bucket, pkg, start, end):
    tok = access_token(SC_GCS)
    rows, notes = [], []
    for folder, pat in REPORTS:
        for ym in month_list(start, end):
            name = f"{folder}/" + pat.format(p=pkg, ym=ym)
            try:
                b = _call(f"{GCS}/{bucket}/o/{urllib.parse.quote(name, safe='')}?alt=media", tok, raw=True)
            except ApiError as ex:
                notes.append(f"{folder} {ym}: {ex}")
                continue
            rows += bulk_rows(folder, pkg, decode_csv(b), start, end)
    return rows, notes


def collect(start, end, env=os.environ):
    """(行, 取れなかった理由の一覧, 取れたか) を返す。取れなかった経路があっても止めない。"""
    pkgs = [p.strip() for p in env.get("PLAY_PACKAGES", "").split(",") if p.strip()]
    if not pkgs:
        raise ApiError("PLAY_PACKAGES が未設定")
    rows, notes = [], []
    for pkg in pkgs:
        try:
            r, n = collect_vitals(pkg, start, end)
            rows += r
            notes += n
        except ApiError as ex:
            notes.append(f"vitals: {ex}")
        if env.get("PLAY_BUCKET"):
            try:
                r, n = collect_bulk(env["PLAY_BUCKET"], pkg, start, end)
                rows += r
                notes += n
            except ApiError as ex:
                notes.append(f"bulk: {ex}")
        else:
            notes.append("PLAY_BUCKET が未設定")
    return rows, notes
