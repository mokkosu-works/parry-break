import datetime, json, os, tempfile, unicodedata, unittest
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
        rows.append({"source": "appstore", "metric": "downloads_total", "entity": "111", "date": day, "value": 2})
        rows.append({"source": "appstore", "metric": "engagement_" + "x" * 20, "entity": "111", "date": day, "value": 1})
    store.upsert(d.name, rows)
    store.update_meta(d.name, "youtube_videos", {"v1": {"title": EVIL, "published_jst": "2026-10-01"}})
    f = facts.build(d.name, None, datetime.date(2026, 11, 15))
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
        ems = report.embeds(self.f, self.h, "https://github.com/x/y/actions/runs/1")
        self.assertLessEqual(len(ems), 10)
        self.assertEqual(ems[0]["title"][:1], "🔔")  # 再生数が半減しているので要確認
        total = 0
        for em in ems:
            self.assertLessEqual(len(em.get("title", "")), 256)
            self.assertLessEqual(len(em["description"]), 4096)
            total += len(em.get("title", "")) + len(em["description"]) + len(em.get("footer", {}).get("text", ""))
        self.assertLessEqual(total, 6000)
        d = "\n".join(em["description"] for em in ems)
        self.assertIn("🔔 要確認", d)
        self.assertIn("承認が要る: 1 件", d)
        self.assertIn("[実行ログ](https://github.com/x/y/actions/runs/1)", d)

    def test_embed_is_markdown_and_safe(self):
        ems = report.embeds(self.f, self.h)
        d = "\n".join(em["description"] for em in ems)
        self.assertEqual([em.get("title", "")[:1] for em in ems[1:4]], ["📺", "🤖", "🍎"])  # YouTube・Play・App Store の順
        self.assertIn("## 💡", d)
        self.assertNotIn("[", d.replace("[実行ログ]", ""))  # Claude や動画のタイトルからリンクを作らせない
        self.assertEqual(d.count("```") % 2, 0)  # コードブロックが閉じている

    def test_all_metrics_and_labels(self):
        ems = report.embeds(self.f, self.h)
        yt = ems[1]["description"]
        self.assertIn("再生数", yt)
        rows = report.metric_table({"views": {"value": None}}, {"views": {"weekly": [5], "wow_pct": 10.0}}, {"views": "再生数"})
        self.assertEqual(rows[0][1:3], ["-", "未着"])  # 対象日の数字が無いときは「未着」
        rows = report.metric_table({"installs_daily_user_uninstalls": {"value": 2, "vs_prev_day_pct": -50.0}}, {}, {})
        self.assertEqual(rows[0][2], "🟢 -50%")  # アンインストールは減るのが良い

    def test_table_aligns_wide_chars(self):
        t = report.table(["", "この日", "前日比"], [["再生数", "98", "🔴 -25%"], ["エンゲージ視聴", "1,234", "🟢 +3%"]])
        lines = [x for x in t.split("\n") if x and x != "```"]
        w = lambda x: sum(2 if unicodedata.east_asian_width(c) in "WF" else 1 for c in x)
        self.assertEqual(len({w(x) for x in lines[1:]}), 1)  # 本体の行は同じ桁数

    def test_mark(self):
        self.assertEqual(report.mark(-25.0), "🔴 -25%")
        self.assertEqual(report.mark(-25.0, good_up=False), "🟢 -25%")  # クラッシュ率は下がるのが良い
        self.assertEqual(report.mark(0.2), "±0%")
        self.assertEqual(report.mark(None), "-")

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
            report.send({"embeds": report.embeds(self.f, self.h)}, [("r.html", b"<html></html>", "text/html")])
        self.assertTrue(sent["url"].endswith("?wait=true"))
        self.assertIn("multipart/form-data", sent["ctype"])
        self.assertIn(b'"allowed_mentions": {"parse": []}', sent["body"])
        self.assertIn(b'name="files[0]"; filename="r.html"', sent["body"])

    def test_webhook_unset_or_malformed_fails(self):
        for v in ("", "https://example.com/hook"):
            with mock.patch.dict(os.environ, {"DISCORD_WEBHOOK_URL": v}), self.assertRaises(SystemExit):
                report.send({"content": "x"})

    def test_growth_chart_and_findings(self):
        d = tempfile.TemporaryDirectory()
        rows, meta = [], {}
        for k in range(8):  # 8 本 → 色は 5 本、残りは灰色
            vid = f"yt{k}"
            meta[vid] = {"title": f"t{k}", "published_jst": "2026-10-20"}
            for i in range(25):
                day = (datetime.date(2026, 10, 20) + datetime.timedelta(days=i)).isoformat()
                rows.append({"source": "youtube", "metric": "views", "entity": vid, "date": day, "value": (k + 1) * 3})
        for i in range(25):
            day = (datetime.date(2026, 10, 19) + datetime.timedelta(days=i)).isoformat()
            rows.append({"source": "youtube", "metric": "views", "entity": "channel", "date": day, "value": 100})
        store.upsert(d.name, rows)
        store.update_meta(d.name, "youtube_videos", meta)
        f = facts.build(d.name, None, datetime.date(2026, 11, 15))
        a = {"content_findings": [{"finding": EVIL, "hypothesis": "h", "sample_size": 8, "evidence": [{"metric": "v", "value": "21"}]}],
             "video_insights": [{"id": "yt7", "verdict": "伸びた", "comment": EVIL}]}
        h = validate.build(f, a, None, {}, f["date"])
        page = report.build_html(f, h)
        d.cleanup()
        self.assertEqual(page.count('class="ln s'), 5)
        self.assertEqual(page.count('class="bg"'), 3)
        self.assertIn("ほか 3 本", page)
        self.assertIn("投稿内容の分析", page)
        self.assertNotIn("<script>", page)
        em = json.dumps(report.embeds(f, h), ensure_ascii=False)
        self.assertIn("公開直後の伸びが大きい動画", em)
        self.assertIn("yt7 — 公開 3 日目で 72 回", em)  # 1 日 24 回 × 3 日

    def test_appstore_section(self):
        html = report.build_html(self.f, self.h)
        self.assertIn("<h2>App Store (直近 7 日)</h2>", html)
        self.assertIn("ダウンロード+更新の合計", html)  # 知っている指標は日本語の名前
        self.assertIn("engagement_" + "x" * 20, html)  # 知らない指標は、そのままの名前
        em = json.dumps(report.embeds(self.f, self.h), ensure_ascii=False)
        self.assertIn("🍎 App Store", em)
        self.assertIn("ダウンロード+更新の合計", em)
        self.assertIn("engagement_" + "x" * 20, em)  # 知らない指標も、そのままの名前で出す(全指標)

    def test_day_section(self):
        html = report.build_html(self.f, self.h)
        self.assertIn("2026-11-13 (金) の数字", html)  # 取得日 11-15 の 2 日前
        self.assertIn("前週の同じ曜日比", html)
        ems = report.embeds(self.f, self.h)
        self.assertIn("日次レポート 2026-11-13", ems[0]["title"])
        self.assertIn("対象日 11/13 (金)", ems[0]["description"])
        self.assertIn("再生数", ems[1]["description"])

    def test_empty_facts(self):
        d = tempfile.TemporaryDirectory()
        f = facts.build(d.name, None, datetime.date(2026, 11, 15))
        h = validate.build(f, None, "なし", {}, f["date"])
        self.assertIn("データはない", report.build_html(f, h))
        report.embeds(f, h)
        d.cleanup()


if __name__ == "__main__":
    unittest.main()
