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

    def test_unlogged_clip_requires_audio_note(self):
        from render_long import check_unlogged_clip
        video = self.folder / "title.mp4"
        video.write_bytes(b"")
        with self.assertRaisesRegex(ValueError, "audio_note"):
            check_unlogged_clip({"source": str(video), "start": 0, "duration": 3, "audio_note": " "})

    def test_single_source_project_becomes_one_clip_with_profile_tag(self):
        from render_long import clips_of
        project = {"profile": "akane", "source": "a.mp4", "events": "e.json", "source_start": 2, "duration": 45}
        self.assertEqual([(c["start"], c["duration"], c["tag"], c["logo"]) for c in clips_of(project)],
                         [(2.0, 45.0, "tags/akane_tag_endless.png", True)])

    GAPS = {"before_title": 1.5, "after_title": 1.0, "before_ending": 1.5, "card_min": 2.5}

    def test_long_silent_tail_is_trimmed(self):
        from assemble import trimmed_length
        # 最後の台詞が 7.9 秒で終わる 12 秒の場面は、台詞の後 1.2 秒(1.5 - 最低の読み始め 0.3)で切る。
        self.assertAlmostEqual(trimmed_length(12, 7.9, self.GAPS), 9.1)
        # もともと無音が短い場面は切らない。
        self.assertEqual(trimmed_length(10.4, 10.34, self.GAPS), 10.4)

    def test_card_fills_missing_gap_when_previous_scene_ends_on_a_line(self):
        from assemble import card_timing
        lead, length = card_timing(0.08, 1.67, 0.3, self.GAPS)
        self.assertAlmostEqual(0.08 + lead, 1.5)
        self.assertAlmostEqual(length - lead - 1.67 + 0.3, 1.0)

    def test_short_title_card_keeps_minimum_length(self):
        from assemble import card_timing
        lead, length = card_timing(1.2, 0.87, 0.3, self.GAPS)
        self.assertEqual(length, 2.5)
        self.assertAlmostEqual(lead - 0.3, (length - lead - 0.87) - 0.7)

    def test_ending_is_delayed_to_keep_gap(self):
        from assemble import ending_offset
        self.assertAlmostEqual(0.09 + 0.6 + ending_offset(0.09, 0.6, self.GAPS), 1.5)

    def test_thin_mouth_corner_is_inside_paste_area(self):
        # 閉じた口は細い線 (x=60〜140)。開いた口は右寄りの塊 (x=100〜140) だけで、線の左側は消えている。
        # 細い線の違いも範囲に入れないと、開いた口の絵の左に閉じた線が残る(2026-11-17 の不具合)。
        from PIL import Image, ImageDraw
        from bust import MOUTH_ZONE, patch
        skin, ink = (235, 200, 180, 255), (40, 30, 30, 255)

        def face():
            # 位置合わせの手がかりになる、目と顔の輪郭(本物の絵と同じく、閉じた絵と開いた絵で共通)
            im = Image.new("RGBA", (200, 200), skin)
            d = ImageDraw.Draw(im)
            d.ellipse((20, 20, 180, 190), outline=ink, width=4)
            d.ellipse((55, 60, 80, 95), fill=ink)
            d.ellipse((120, 60, 145, 95), fill=ink)
            return im
        closed, opened = face(), face()
        ImageDraw.Draw(closed).line((60, 120, 140, 120), fill=ink, width=2)
        ImageDraw.Draw(opened).ellipse((100, 108, 140, 136), fill=(200, 80, 80, 255), outline=ink, width=2)
        _, area = patch(closed, opened, MOUTH_ZONE)
        self.assertLessEqual(area[0], 60)
        self.assertGreaterEqual(area[2], 140)

    def test_bust_keeps_aspect_ratio(self):
        from PIL import Image
        from render_long import BUST_BOX, bust_size
        tall = bust_size(Image.new("RGBA", (356, 408)))
        self.assertEqual(tall.height, BUST_BOX[1])
        self.assertAlmostEqual(tall.width / tall.height, 356 / 408, places=2)

    def test_guest_must_be_another_known_member(self):
        from render_long import check_guest
        check_guest("wakana", "mitsuba")
        for guest in ("mitsuba", "nobody"):
            with self.assertRaisesRegex(ValueError, "メンバー"):
                check_guest(guest, "mitsuba")

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

    def test_caption_breaks_after_comma_instead_of_inside_a_word(self):
        from render_long import wrap

        class Font:  # 1 文字 = 幅 1
            def getlength(self, s):
                return len(s)

        self.assertEqual(wrap("ああああ、いいいいう", Font(), 8), ["ああああ、", "いいいいう"])
        # 前半にしか読点がなければ、これまでどおり幅いっぱいで折り返す。
        self.assertEqual(wrap("あ、いいいいいいいう", Font(), 8), ["あ、いいいいいい", "いう"])


if __name__ == "__main__":
    unittest.main()
