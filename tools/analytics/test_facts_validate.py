import csv, datetime, json, pathlib, tempfile, unittest

import facts, store, validate

D = datetime.date
TODAY = D(2026, 11, 16)  # w0 = 11-07〜11-13、w1 = 10-31〜11-06


def yt(metric, entity, date, value):
    return {"source": "youtube", "metric": metric, "entity": entity, "date": date, "value": value}


class FactsTest(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.TemporaryDirectory()
        self.root = self.d.name
        rows = []
        for day in range(7):
            d0 = (D(2026, 11, 7) + datetime.timedelta(days=day)).isoformat()
            d1 = (D(2026, 10, 31) + datetime.timedelta(days=day)).isoformat()
            rows += [yt("views", "channel", d0, 10), yt("views", "channel", d1, 40),
                     yt("views", "v1", d0, 10), yt("averageViewPercentage", "v1", d0, 50), yt("engagedViews", "v1", d0, 5),
                     yt("views", "v1", d1, 40), yt("averageViewPercentage", "v1", d1, 20)]
        store.upsert(self.root, rows)
        store.update_meta(self.root, "youtube_videos", {"v1": {"title": "T", "published_jst": "2026-10-30"}})
        store.upsert(self.root, [{"source": "play", "metric": "vitals_crash_rate", "entity": "pkg", "date": "2026-11-08", "value": 0.02},
                                 {"source": "play", "metric": "vitals_crash_rate", "entity": "pkg", "date": "2026-11-01", "value": 0.01},
                                 {"source": "play", "metric": "installs_daily_user_installs", "entity": "pkg", "date": "2026-11-08", "value": 3},
                                 {"source": "play", "metric": "installs_daily_user_installs", "entity": "pkg", "date": "2026-11-09", "value": 4}])
        store.record_status(self.root, "play", "2026-11-16", "ng", "bulk: HTTP 403")
        self.rec = pathlib.Path(self.root) / "videos.csv"
        with open(self.rec, "w", encoding="utf-8-sig", newline="") as f:
            w = csv.writer(f)
            w.writerow(["id", "パターン名", "冒頭の種類", "タイトル", "投稿日", "長さ(秒)"])
            w.writerow(["v001", "p1", "A", "T", "2026-10-30", "19"])

    def tearDown(self):
        self.d.cleanup()

    def test_build(self):
        f = facts.build(self.root, self.rec, TODAY)
        w = f["youtube"]["channel_weekly"]
        self.assertEqual((w[0]["views"], w[1]["views"], w[0]["views_wow_pct"]), (70, 280, -75.0))
        v = f["youtube"]["videos"][0]
        self.assertEqual((v["id"], v["pattern"], v["views_w0"], v["views_w1"], v["views_28d"]), ("v001", "p1", 70, 280, 350))
        # 28 日の平均視聴割合は再生数で重みづけ: (50*70 + 20*280) / 350 = 26
        self.assertEqual(v["avg_view_pct_28d"], 26.0)
        crash = f["play"]["packages"]["pkg"]["vitals_crash_rate"]
        self.assertEqual(crash["weekly"][:2], [0.02, 0.01])
        self.assertEqual(f["play"]["packages"]["pkg"]["installs_daily_user_installs"]["weekly"][0], 7)
        codes = {a["code"] for a in f["alerts"]}
        self.assertEqual(codes, {"views_halved", "play_fetch_ng", "vitals_crash_rate_up"})
        self.assertTrue(any("4 週" in x or "週分" in x for x in f["data_quality"]))
        json.dumps(f)  # JSON にできること

    def test_empty_store(self):
        f = facts.build(self.root + "/none", None, TODAY)
        self.assertEqual(f["youtube"]["videos"], [])
        self.assertEqual(f["alerts"], [])


class ValidateTest(unittest.TestCase):
    FACTS = {"date": "2026-11-16", "alerts": [], "data_quality": [], "youtube": {"views": 1099, "pct": 23.36}}

    def prop(self, **kw):
        p = {"target": "video", "kind": "experiment", "action": "冒頭を変えた版を作る", "confidence": "medium", "sample_size": 6,
             "evidence": [{"metric": "views", "value": "1,099"}], "success_metric": {"metric": "views", "direction": "up"}}
        p.update(kw)
        return p

    def test_auto_executable(self):
        h = validate.build(self.FACTS, {"proposals": [self.prop()]}, None, {}, "2026-11-16")
        p = h["proposals"][0]
        self.assertTrue(p["evidence_verified"] and p["auto_executable"] and not p["needs_human_approval"])
        self.assertEqual(p["id"], "P-20261116-01")

    def test_rules(self):
        cases = [self.prop(action="動画を公開する"), self.prop(confidence="low"), self.prop(sample_size=3),
                 self.prop(kind="gather"), self.prop(evidence=[{"metric": "v", "value": "9999"}])]
        h = validate.build(self.FACTS, {"proposals": cases}, None, {}, "2026-11-16")
        self.assertFalse(any(p["auto_executable"] for p in h["proposals"]))
        self.assertTrue(h["proposals"][0]["needs_human_approval"])
        self.assertFalse(h["proposals"][4]["evidence_verified"])

    def test_formula_checks_left_side_only(self):
        self.assertTrue(validate.evidence_ok("1099 / 23.36 = 47.05", validate.corpus(self.FACTS)))
        self.assertFalse(validate.evidence_ok("1099 / 7 = 157", validate.corpus(self.FACTS)))
        self.assertFalse(validate.evidence_ok("多い", validate.corpus(self.FACTS)))

    def test_status_cannot_be_lowered_by_claude(self):
        f = {**self.FACTS, "alerts": [{"code": "views_halved"}]}
        self.assertEqual(validate.build(f, {"status": "ok"}, None, {}, "d")["status"], "attention")
        self.assertEqual(validate.build(self.FACTS, {"status": "attention"}, None, {}, "d")["status"], "attention")

    def test_broken_analysis_still_builds(self):
        with tempfile.NamedTemporaryFile("w", suffix=".json") as t:
            t.write("```json\nnot json\n```")
            t.flush()
            a, err = validate.load_analysis(t.name)
        h = validate.build(self.FACTS, a, err, {}, "2026-11-16")
        self.assertEqual(h["proposals"], [])
        self.assertTrue(any("読めなかった" in x for x in h["data_quality"]))

    def test_invalid_proposal_rejected(self):
        h = validate.build(self.FACTS, {"proposals": [self.prop(target="ads"), "x"]}, None, {}, "d")
        self.assertEqual(len(h["rejected"]), 2)


if __name__ == "__main__":
    unittest.main()
