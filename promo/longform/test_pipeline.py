"""記録の欠落、時計の違い、ボス区間、存在しない反応を取り違えないための検証。"""

import json
from pathlib import Path
import tempfile
import unittest
import unittest.mock
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "capture"))
from capture_long import active_media_players

from align_events import align
from make_script import make


class PipelineTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name)
        self.metadata = {"status": "recorded_unaligned", "mode": "endless", "probe": {"format": {"duration": "60"}}}
        (self.folder / "capture.json").write_text(json.dumps(self.metadata))

    def save(self, events):
        (self.folder / "events-raw.jsonl").write_text("".join(json.dumps(e) + "\n" for e in events))

    def event(self, seq, clock, **fields):
        return {"session": "take1", "seq": seq, "clock_s": clock, "sim_s": 0,
                "type": "parry", "grade": "just", **fields}

    def read(self):
        return json.loads((self.folder / "events.json").read_text())

    def test_alignment_uses_clock_even_while_simulation_is_stopped(self):
        self.save([self.event(0, 10), self.event(1, 13)])
        align(self.folder, 0, 2)
        self.assertEqual([e["video_s"] for e in self.read()["events"]], [2, 5])

    def test_gap_rejected_and_explicit_prefix_limits_video(self):
        self.save([self.event(0, 10), self.event(1, 13), self.event(3, 18)])
        with self.assertRaisesRegex(ValueError, "欠落"):
            align(self.folder, 0, 2)
        align(self.folder, 0, 2, through_seq=1)
        self.assertEqual(self.read()["safe_end"], 5)

    def test_boss_frame_is_outside_usable_video(self):
        self.save([self.event(0, 10), self.event(1, 20, type="round_started", number=10, boss=1)])
        align(self.folder, 0, 2)
        self.assertAlmostEqual(self.read()["safe_end"], 11.8)

    def test_duplicate_and_backwards_clock_rejected(self):
        for events in ([self.event(0, 10), self.event(0, 11)], [self.event(0, 10), self.event(1, 9)]):
            self.save(events)
            with self.assertRaises(ValueError):
                align(self.folder, 0, 2)

    def test_missing_reaction_is_not_invented(self):
        plan = {"profile": "akane", "source_clock_start": 0, "duration": 10, "lines": [],
                "reactions": [{"type": "fever_start", "after": 2, "before": 4}]}
        events = {"alignment": {"video_s": 0, "clock_s": 0}, "safe_end": 60,
                  "events": [self.event(0, 3, video_s=3)]}
        with self.assertRaisesRegex(ValueError, "対象になる出来事がありません"):
            make(plan, events)

    def test_parried_item_reaction_skips_paddle_pickups(self):
        plan = {"profile": "mitsuba", "source_clock_start": 0, "duration": 10, "lines": [], "events": "e.json", "note": "",
                "reactions": [{"type": "item_taken", "parried": True, "after": 2, "before": 6}]}
        events = {"alignment": {"video_s": 0, "clock_s": 0}, "safe_end": 60, "capture": "/x", "video": "v.mp4",
                  "events": [self.event(0, 3, video_s=3, type="item_taken", parried=False),
                             self.event(1, 5, video_s=5, type="item_taken", parried=True)]}
        with unittest.mock.patch("make_script.ROOT", Path("/")):
            script = make(plan, events)
        self.assertEqual([l["event_seq"] for l in script["lines"]], [1])

    def test_reaction_without_lines_for_profile_rejected(self):
        plan = {"profile": "akane", "source_clock_start": 0, "duration": 10, "lines": [],
                "reactions": [{"type": "item_taken", "parried": True, "after": 2, "before": 6}]}
        events = {"alignment": {"video_s": 0, "clock_s": 0}, "safe_end": 60, "events": []}
        with self.assertRaisesRegex(ValueError, "台詞がありません"):
            make(plan, events)

    def test_audio_guard_ignores_paused_players_and_past_events(self):
        dump = "\n".join([
            "AudioPlaybackConfiguration u/pid:10547/123 state:started attr:usage=USAGE_MEDIA",
            "AudioPlaybackConfiguration u/pid:10276/456 state:paused attr:usage=USAGE_MEDIA",
            "AudioPlaybackConfiguration u/pid:1000/789 state:started attr:usage=USAGE_ASSISTANCE_SONIFICATION",
            "01:00:00 player 10276 event:started",
        ])
        self.assertEqual([p["uid"] for p in active_media_players(dump)], [10547])

    def test_audio_guard_detects_background_media_even_if_muted(self):
        dump = "AudioPlaybackConfiguration u/pid:10276/456 state:started attr:usage=USAGE_MEDIA mutedState:streamVolume"
        self.assertEqual([p["uid"] for p in active_media_players(dump)], [10276])


if __name__ == "__main__":
    unittest.main()
