import base64, datetime, gzip, json, pathlib, subprocess, tempfile, unittest

import appstore, store

D = datetime.date
TSV = ("Date\tApp Name\tApp Apple Identifier\tEvent\tCounts\n"
       "2026-11-10\tPB\t111\tImpression\t30\n"
       "2026-11-10\tPB\t111\tImpression\t5\n"
       "2026-11-10\tPB\t111\tPage view\t4\n"
       "2026-11-10\tOther\t999\tImpression\t100\n")


class JwtTest(unittest.TestCase):
    def test_es256_signature_verifies(self):
        with tempfile.TemporaryDirectory() as d:
            key, pub = f"{d}/k.p8", f"{d}/k.pub"
            subprocess.run(["openssl", "genpkey", "-algorithm", "EC", "-pkeyopt", "ec_paramgen_curve:P-256", "-out", key], check=True)  # .p8 と同じ PKCS#8
            subprocess.run(["openssl", "ec", "-in", key, "-pubout", "-out", pub], check=True, capture_output=True)
            p8 = pathlib.Path(key).read_text()
            t = appstore.make_jwt("iss", "KID", p8, now=1000)
            head, claim, sig = t.split(".")
            self.assertEqual(json.loads(base64.urlsafe_b64decode(head + "==")), {"alg": "ES256", "kid": "KID", "typ": "JWT"})
            self.assertEqual(json.loads(base64.urlsafe_b64decode(claim + "=="))["exp"], 2200)
            raw = base64.urlsafe_b64decode(sig + "==")
            self.assertEqual(len(raw), 64)
            # raw (r||s) を DER に戻して、openssl で検証する
            enc = lambda v: (lambda b: b"\x02" + bytes([len(b)]) + b)((b"\x00" + v.lstrip(b"\x00")) if v.lstrip(b"\x00")[0] & 0x80 else v.lstrip(b"\x00"))
            body = enc(raw[:32]) + enc(raw[32:])
            pathlib.Path(f"{d}/sig").write_bytes(b"\x30" + bytes([len(body)]) + body)
            r = subprocess.run(["openssl", "dgst", "-sha256", "-verify", pub, "-signature", f"{d}/sig"],
                               input=f"{head}.{claim}".encode(), capture_output=True)
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

    def test_missing_keys(self):
        with self.assertRaises(appstore.ApiError):
            appstore.Client(env={"ASC_ISSUER_ID": "x"})


class ParseTest(unittest.TestCase):
    def test_segment_totals(self):
        rows = appstore.parse_segment(gzip.compress(TSV.encode()))
        t = appstore.segment_totals(rows, "engagement", "Event", "Counts", "111", "2026-11-11")
        self.assertEqual(t, {("2026-11-10", "engagement_total"): 39, ("2026-11-10", "engagement_impression"): 35,
                             ("2026-11-10", "engagement_page_view"): 4})

    def test_no_kind_and_fallback_date(self):
        rows = appstore.parse_segment(b"App Apple Identifier\tSessions\n111\t3\n111\t2\n")
        self.assertEqual(appstore.segment_totals(rows, "sessions", None, "Sessions", "111", "2026-11-09"),
                         {("2026-11-09", "sessions"): 5})

    def test_missing_count_col(self):
        rows = appstore.parse_segment(b"Date\tFoo\n2026-11-10\t1\n")
        self.assertEqual(appstore.segment_totals(rows, "x", None, "Counts", "1", ""), {})


class FakeClient:
    """App Store Connect API の偽物。依頼がない状態から始め、POST の権限を切り替えられる。"""

    def __init__(self, can_create=True, requests=None):
        self.can_create, self.posts = can_create, []
        self.reqs = requests if requests is not None else []

    def call(self, path, body=None):
        if body:
            self.posts.append(body["data"]["attributes"]["accessType"])
            if not self.can_create:
                raise appstore.ApiError("analyticsReportRequests が HTTP 403")
            r = {"id": f"R{len(self.reqs)}", "attributes": {"accessType": body["data"]["attributes"]["accessType"]}}
            self.reqs.append(r)
            return {"data": r}
        if path.startswith("/v1/apps?"):
            return {"data": [{"id": "111", "attributes": {"bundleId": "com.example"}}]}
        raise AssertionError(path)

    def pages(self, path):
        if path.startswith("/v1/apps/111/analyticsReportRequests"):
            return list(self.reqs)
        if path.endswith("/reports?limit=200"):
            rid = path.split("/")[3]
            return [{"id": f"{rid}-eng", "attributes": {"name": "App Store Discovery and Engagement Standard"}}]
        if "/instances" in path:
            rid = path.split("/")[3]
            return [{"id": f"{rid}-i1", "attributes": {"processingDate": "2026-11-10"}},
                    {"id": f"{rid}-old", "attributes": {"processingDate": "2026-01-01"}}]
        if path.endswith("/segments"):
            iid = path.split("/")[3]
            return [{"attributes": {"url": f"https://seg/{iid}"}}]
        raise AssertionError(path)

    def download(self, url):
        if url.endswith("-old"):
            raise AssertionError("範囲外のインスタンスを読んだ")
        n = 1 if url.startswith("https://seg/R0") else 2  # 依頼ごとに数を変え、上書きの向きを確かめる
        return gzip.compress(f"Date\tApp Apple Identifier\tEvent\tCounts\n2026-11-10\t111\tImpression\t{n}\n".encode())


class CollectTest(unittest.TestCase):
    env = {"ASC_BUNDLE_ID": "com.example"}

    def test_creates_requests_and_reads(self):
        c = FakeClient()
        rows, notes, info = appstore.collect(D(2026, 11, 4), D(2026, 11, 14), env=self.env, client=c)
        self.assertEqual(c.posts, ["ONGOING", "ONE_TIME_SNAPSHOT"])
        self.assertTrue(any("依頼を作った" in n for n in info))
        self.assertEqual(notes, [])  # 作っただけなら失敗にしない
        imp = [r for r in rows if r["metric"] == "engagement_impression"]
        self.assertEqual(len(imp), 1)  # 2 つの依頼の同じ日は、足さずに 1 行
        self.assertEqual(imp[0]["value"], 1)  # 継続 (R0) を後に読み、優先する
        for r in rows:
            store.validate(r)

    def test_no_admin_key(self):
        c = FakeClient(can_create=False)
        rows, notes, info = appstore.collect(D(2026, 11, 4), D(2026, 11, 14), env=self.env, client=c)
        self.assertEqual(rows, [])
        self.assertTrue(any("Admin の鍵" in n for n in notes))

    def test_existing_requests_are_not_recreated(self):
        c = FakeClient(can_create=False, requests=[{"id": "R0", "attributes": {"accessType": "ONGOING"}},
                                                   {"id": "R1", "attributes": {"accessType": "ONE_TIME_SNAPSHOT", "stoppedDueToInactivity": True}}])
        rows, notes, info = appstore.collect(D(2026, 11, 4), D(2026, 11, 14), env=self.env, client=c)
        self.assertEqual(c.posts, [])
        self.assertEqual(notes, [])
        self.assertEqual(len(rows), 2)  # total と impression

    def test_rows_outside_window_dropped(self):
        c = FakeClient()
        rows, _, _ = appstore.collect(D(2026, 11, 11), D(2026, 11, 14), env=self.env, client=c)
        self.assertEqual(rows, [])


if __name__ == "__main__":
    unittest.main()
