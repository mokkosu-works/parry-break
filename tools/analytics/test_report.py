import datetime, json, os, tempfile, unittest
from unittest import mock

import facts, report, store, validate

EVIL = '<script>alert(1)</script>"@everyone'


def sample():
    d = tempfile.TemporaryDirectory()
    rows = []
    for i in range(14):
        day = (datetime.date(2026, 10, 31) + datetime.timedelta(days=i)).isoformat()
        rows += [{"source": "youtube", "metric": "views", "entity": e, "date": day, "value": 30 if i < 7 else 10} for e in ("channel", "v1")]
        rows.append({"source": "play", "metric": "vitals_crash_rate", "entity": "pkg", "date": day, "value": 0.01})
    store.upsert(d.name, rows)
    store.update_meta(d.name, "youtube_videos", {"v1": {"title": EVIL, "published_jst": "2026-10-01"}})
    f = facts.build(d.name, None, datetime.date(2026, 11, 16))
    a = {"status": "ok", "summary": EVIL, "highlights": [EVIL],
         "proposals": [{"target": "video", "kind": "experiment", "action": "動画を投稿する " + EVIL, "confidence": "low",
                        "sample_size": 1, "evidence": [{"metric": "views", "value": "70"}]}]}
    h = validate.build(f, a, None, {}, f["date"])
    d.cleanup()
    return f, h


class ReportTest(unittest.TestCase):
    def setUp(self):
        self.f, self.h = sample()

    def test_html_escapes_everything_and_has_no_script(self):
        page = report.build_html(self.f, self.h)
        self.assertNotIn("<script>", page)
        self.assertIn("&lt;script&gt;", page)
        self.assertIn("Content-Security-Policy", page)
        self.assertNotIn("http://", page.replace("http-equiv", ""))
        self.assertNotIn("https://", page)  # 外部を読み込まない

    def test_embed_within_discord_limits(self):
        em = report.embed(self.f, self.h, "https://github.com/x/y/actions/runs/1")
        self.assertLessEqual(len(em["title"]), 256)
        self.assertLessEqual(len(em["description"]), 4096)
        self.assertLessEqual(len(em["fields"]), 25)
        for fl in em["fields"]:
            self.assertLessEqual(len(fl["value"]), 1024)
        total = len(em["title"]) + len(em["description"]) + sum(len(x["name"]) + len(x["value"]) for x in em["fields"]) + len(em["footer"]["text"])
        self.assertLessEqual(total, 6000)
        self.assertTrue(em["title"].startswith("🔔"))  # 再生数が半減しているので要確認
        self.assertIn("人の承認が要る 1 件", json.dumps(em, ensure_ascii=False))

    def test_send_disables_mentions_and_attaches_html(self):
        sent = {}

        class Resp:
            def read(self):
                return b"{}"

        def fake(req, timeout):
            sent["url"], sent["body"], sent["ctype"] = req.full_url, req.data, req.headers["Content-type"]
            return Resp()
        with mock.patch.dict(os.environ, {"DISCORD_WEBHOOK_URL": "https://discord.com/api/webhooks/1/abc"}), \
             mock.patch("urllib.request.urlopen", fake):
            report.send({"embeds": [report.embed(self.f, self.h)]}, [("r.html", b"<html></html>", "text/html")])
        self.assertTrue(sent["url"].endswith("?wait=true"))
        self.assertIn("multipart/form-data", sent["ctype"])
        self.assertIn(b'"allowed_mentions": {"parse": []}', sent["body"])
        self.assertIn(b'name="files[0]"; filename="r.html"', sent["body"])

    def test_webhook_unset_or_malformed_fails(self):
        for v in ("", "https://example.com/hook"):
            with mock.patch.dict(os.environ, {"DISCORD_WEBHOOK_URL": v}), self.assertRaises(SystemExit):
                report.send({"content": "x"})

    def test_empty_facts(self):
        d = tempfile.TemporaryDirectory()
        f = facts.build(d.name, None, datetime.date(2026, 11, 16))
        h = validate.build(f, None, "なし", {}, f["date"])
        self.assertIn("データはない", report.build_html(f, h))
        report.embed(f, h)
        d.cleanup()


if __name__ == "__main__":
    unittest.main()
