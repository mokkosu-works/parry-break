import json, pathlib, tempfile, unittest

import store


def row(metric="views", entity="v1", date="2026-11-10", value=1, source="youtube"):
    return {"source": source, "metric": metric, "entity": entity, "date": date, "value": value}


class StoreTest(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.TemporaryDirectory()
        self.root = self.d.name

    def tearDown(self):
        self.d.cleanup()

    def test_upsert_is_idempotent(self):
        self.assertEqual(store.upsert(self.root, [row(), row(entity="v2")]), (2, 0))
        before = (pathlib.Path(self.root) / "store/youtube/2026-11.jsonl").read_bytes()
        self.assertEqual(store.upsert(self.root, [row(), row(entity="v2")]), (0, 0))
        self.assertEqual((pathlib.Path(self.root) / "store/youtube/2026-11.jsonl").read_bytes(), before)

    def test_upsert_overwrites_changed_value(self):
        store.upsert(self.root, [row(value=1)])
        self.assertEqual(store.upsert(self.root, [row(value=5)]), (0, 1))
        self.assertEqual(store.load(self.root, "youtube")[0]["value"], 5)

    def test_splits_by_month_and_source(self):
        store.upsert(self.root, [row(date="2026-10-31"), row(date="2026-11-01"), row(source="play", entity="pkg")])
        r = pathlib.Path(self.root) / "store"
        self.assertTrue((r / "youtube/2026-10.jsonl").exists() and (r / "youtube/2026-11.jsonl").exists())
        self.assertTrue((r / "play/2026-11.jsonl").exists())

    def test_load_filters_and_sorts(self):
        store.upsert(self.root, [row(date="2026-11-12"), row(date="2026-11-10"), row(date="2026-10-01"), row(metric="likes")])
        got = store.load(self.root, "youtube", start="2026-11-01", end="2026-11-30", metric="views")
        self.assertEqual([r["date"] for r in got], ["2026-11-10", "2026-11-12"])

    def test_invalid_row_writes_nothing(self):
        for bad in (row(value="12"), row(value=float("nan")), row(value=True), row(date="2026-13-01"),
                    row(source="x"), row(entity=""), {"source": "youtube"}):
            with self.assertRaises(ValueError):
                store.upsert(self.root, [row(entity="ok"), bad])
        self.assertEqual(store.load(self.root, "youtube"), [])

    def test_corrupt_file_is_not_overwritten(self):
        store.upsert(self.root, [row()])
        p = pathlib.Path(self.root) / "store/youtube/2026-11.jsonl"
        p.write_text("{broken\n")
        with self.assertRaises(ValueError):
            store.upsert(self.root, [row(entity="v2")])
        self.assertEqual(p.read_text(), "{broken\n")

    def test_status_is_one_row_per_source_day(self):
        store.record_status(self.root, "play", "2026-11-16", "ng", "403")
        store.record_status(self.root, "play", "2026-11-16", "ok")
        lines = (pathlib.Path(self.root) / "store/status.jsonl").read_text().splitlines()
        self.assertEqual(len(lines), 1)
        self.assertEqual(json.loads(lines[0])["state"], "ok")
        with self.assertRaises(ValueError):
            store.record_status(self.root, "play", "2026-11-16", "maybe")


if __name__ == "__main__":
    unittest.main()
