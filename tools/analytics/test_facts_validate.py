import csv, datetime, json, pathlib, tempfile, unittest

import facts, store, validate

D = datetime.date
TODAY = D(2026, 11, 15)  # w0 = 11-07〜11-13、w1 = 10-31〜11-06


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
        store.record_status(self.root, "play", "2026-11-15", "ng", "bulk: HTTP 403")
        store.upsert(self.root, [{"source": "appstore", "metric": m, "entity": "111", "date": d, "value": v}
                                 for m, d, v in (("downloads_total", "2026-11-08", 2), ("downloads_total", "2026-11-09", 3),
                                                 ("downloads_total", "2026-11-01", 1), ("engagement_impression", "2026-11-09", 40))])
        self.promo = pathlib.Path(self.root) / "promo"
        (self.promo / "records").mkdir(parents=True)
        (self.promo / "build/specs").mkdir(parents=True)
        with open(self.promo / "records/videos.csv", "w", encoding="utf-8-sig", newline="") as f:
            w = csv.writer(f)
            w.writerow(["id", "パターン名", "冒頭の種類", "タイトル", "投稿日", "長さ(秒)"])
            w.writerow(["v001", "p1", "A", "T", "2026-10-30", "19"])
        (self.promo / "build/specs/spec.p1.json").write_text(json.dumps(
            {"hooks": {"A": {"caption": "あと1ミリ"}}, "body": {"caption": "弾け"}, "hashtags": ["#x"]}, ensure_ascii=False))

    def tearDown(self):
        self.d.cleanup()

    def test_build(self):
        f = facts.build(self.root, self.promo, TODAY)
        w = f["youtube"]["channel_weekly"]
        self.assertEqual((w[0]["views"], w[1]["views"], w[0]["views_wow_pct"]), (70, 280, -75.0))
        v = f["youtube"]["videos"][0]
        self.assertEqual((v["id"], v["pattern"], v["views_w0"], v["views_w1"], v["views_28d"]), ("v001", "p1", 70, 280, 350))
        # 28 日の平均視聴割合は再生数で重みづけ: (50*70 + 20*280) / 350 = 26
        self.assertEqual(v["avg_view_pct_28d"], 26.0)
        crash = f["play"]["packages"]["pkg"]["vitals_crash_rate"]
        self.assertEqual(crash["weekly"][:2], [0.02, 0.01])
        self.assertEqual(f["play"]["packages"]["pkg"]["installs_daily_user_installs"]["weekly"][0], 7)
        dl = f["appstore"]["apps"]["111"]["downloads_total"]
        self.assertEqual((dl["mode"], dl["weekly"][:2], dl["wow_pct"]), ("sum", [5, 1], 400.0))  # total でも合計
        codes = {a["code"] for a in f["alerts"]}
        self.assertEqual(codes, {"views_halved", "play_fetch_ng", "vitals_crash_rate_up"})
        self.assertTrue(any("4 週" in x or "週分" in x for x in f["data_quality"]))
        c = v["content"]
        self.assertEqual((c["kind"], c["hook_label"], c["hook_caption"], c["body_caption"], c["weekday"]),
                         ("プレイ動画", "惜しい失敗", "あと1ミリ", "弾け", "金"))
        g = v["growth"]
        # 公開 10-30、データは 10-31 から → 公開日からのデータが無いので、伸びの累計は出さない
        self.assertFalse(g["covered_from_publish"])
        self.assertIsNone(g["views_d7"])
        self.assertTrue(any("backfill" in x for x in f["data_quality"]))
        json.dumps(f)  # JSON にできること

    def test_day_facts(self):
        f = facts.build(self.root, self.promo, TODAY)
        dy = f["day"]
        self.assertEqual((dy["date"], dy["weekday"]), ("2026-11-13", "金"))  # 取得日の 2 日前
        v = dy["youtube_channel"]["views"]
        # 11-07〜13 は 1 日 10 回、10-31〜11-06 は 1 日 40 回。前 7 日 (11-06〜12) の平均は (40 + 10*6) / 7
        self.assertEqual((v["value"], v["prev_day"], v["same_weekday_last_week"], v["vs_last_week_pct"], v["prior7_mean"]),
                         (10, 10, 40, -75.0, 14.3))
        self.assertTrue(dy["available"]["youtube"])
        self.assertEqual(dy["youtube_top_videos"][0]["id"], "v001")
        self.assertFalse(dy["available"]["play"])  # Play は 11-13 のデータがない
        self.assertTrue(any("対象日" in x and "play" in x for x in f["data_quality"]))

    def test_growth_by_days_since_publish(self):
        store.update_meta(self.root, "youtube_videos", {"v1": {"title": "T", "published_jst": "2026-10-31"}})
        (self.promo / "records/youtube_uploads.csv").write_text("id,動画ID,公開の範囲,公開予約,アップロード日時\nv001,v1,public,,\n", encoding="utf-8")
        f = facts.build(self.root, self.promo, TODAY)
        g = f["youtube"]["videos"][0]["growth"]
        # 10-31 公開、10-31〜11-06 は 1 日 40 回、11-07〜11-13 は 1 日 10 回。as_of = 11-13 → 14 日目
        self.assertEqual((g["age_days"], g["views_d1"], g["views_d3"], g["views_d7"], g["views_d14"], g["views_d28"]),
                         (14, 40, 120, 280, 350, None))
        self.assertEqual((g["views_total"], g["peak_day"], len(g["curve"])), (350, 1, 14))
        self.assertEqual(g["state"], "ゆるやか")  # 今週 70 / 累計 350 = 0.2
        self.assertEqual(g["d7_vs_median"], 1.0)
        self.assertEqual(f["youtube"]["groups"]["hook"][0]["d3_median"], 120)

    def test_growth_state(self):
        st = facts.growth_state
        self.assertEqual(st({"age_days": 5, "views_total": 10}, 5), "公開直後")
        self.assertEqual(st({"age_days": 20, "views_total": 100}, 40), "伸び続けている")
        self.assertEqual(st({"age_days": 20, "views_total": 100}, 5), "落ち着いた")
        self.assertEqual(st({"age_days": 20, "views_total": None}, 5), "不明")

    def test_match_by_youtube_id_first(self):
        with open(self.promo / "records/youtube_uploads.csv", "w", encoding="utf-8-sig", newline="") as f:
            w = csv.writer(f)
            w.writerow(["id", "動画ID", "公開の範囲", "公開予約", "アップロード日時"])
            w.writerow(["v001", "v1", "private", "2026-10-30T19:00:00+09:00", ""])
        store.update_meta(self.root, "youtube_videos", {"v1": {"title": "タイトルを変えた", "published_jst": "2026-10-30"}})
        v = facts.build(self.root, self.promo, TODAY)["youtube"]["videos"][0]
        self.assertEqual((v["id"], v["content"]["publish_hour"]), ("v001", 19))

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

    def test_insights_and_findings(self):
        a = {"video_insights": [{"id": "v005a", "verdict": "伸びた", "comment": "冒頭が強い", "evidence": [{"metric": "views", "value": "1099"}]},
                                {"id": "x", "verdict": "すごい", "comment": "c", "evidence": [{"metric": "v", "value": "5555"}]},
                                {"id": "y"}],
             "content_findings": [{"finding": "疑問形の冒頭が伸びた", "hypothesis": "h", "sample_size": 3,
                                   "evidence": [{"metric": "pct", "value": "23.36"}], "next_test": "t"}]}
        h = validate.build(self.FACTS, a, None, {}, "d")
        self.assertEqual(len(h["video_insights"]), 2)
        self.assertTrue(h["video_insights"][0]["evidence_verified"])
        self.assertEqual(h["video_insights"][1]["verdict"], "")  # 決まった値以外は消す
        self.assertFalse(h["video_insights"][1]["evidence_verified"])
        f = h["content_findings"][0]
        self.assertTrue(f["evidence_verified"] and f["reference_only"])

    def test_invalid_proposal_rejected(self):
        h = validate.build(self.FACTS, {"proposals": [self.prop(target="ads"), "x"]}, None, {}, "d")
        self.assertEqual(len(h["rejected"]), 2)


if __name__ == "__main__":
    unittest.main()
