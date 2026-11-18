import unittest
from unittest.mock import patch, call

import capture_long


class CaptureChecks(unittest.TestCase):
    def test_wrong_stage_log_is_rejected(self):
        capture_long.check_event_modes([{"mode": "stage:2-1"}], "stage", "2-1")
        with self.assertRaisesRegex(RuntimeError, "一致しません"):
            capture_long.check_event_modes([{"mode": "stage:1-1"}], "stage", "2-1")

    @patch("capture_long.adb")
    def test_invalid_stage_is_rejected_before_device_access(self, adb):
        for arguments in [("stage", "test", "30", "--stage", "1-10"),
                          ("endless", "test", "30", "--stage", "1-1")]:
            with patch("sys.argv", ["capture_long.py", *arguments]), \
                    patch("sys.stderr"), self.assertRaises(SystemExit) as error:
                capture_long.main()
            self.assertEqual(error.exception.code, 2)
        adb.assert_not_called()

    @patch("capture_long.time.sleep")
    @patch("capture_long.adb")
    def test_mitsuba_stages(self, adb, sleep):
        for stage, x, chapters in [("1-1", "292", 0), ("1-2", "569", 0),
                                    ("1-4", "1123", 0), ("2-1", "292", 1)]:
            adb.reset_mock()
            capture_long.select_stage(stage)
            self.assertIn(call("shell", "input", "tap", x, "536"), adb.call_args_list)
            self.assertEqual(adb.call_args_list.count(
                call("shell", "input", "tap", "1482", "220")), chapters)
            self.assertEqual(adb.call_args_list[-1],
                             call("shell", "input", "tap", "2102", "927"))

    @patch("capture_long.time.sleep")
    @patch("capture_long.adb")
    def test_second_row_stages(self, adb, sleep):
        # 2 行目は 10〜6 が左から並ぶ。1-8 は左から 3 番目、1-7 は 4 番目。
        for stage, x in [("1-7", "1123"), ("1-8", "846")]:
            adb.reset_mock()
            capture_long.select_stage(stage)
            self.assertIn(call("shell", "input", "tap", x, "776"), adb.call_args_list)
        with self.assertRaises(ValueError):
            capture_long.stage_tap(10)

    @patch("capture_long.time.sleep")
    @patch("capture_long.adb")
    def test_difficulty_is_tapped_before_choosing_the_stage(self, adb, sleep):
        capture_long.select_stage("1-1", "hard")
        taps = [c for c in adb.call_args_list if c.args[:3] == ("shell", "input", "tap")]
        self.assertEqual(taps[1], call("shell", "input", "tap", "1934", "88"))
        adb.reset_mock()
        capture_long.select_stage("1-1")
        self.assertNotIn(call("shell", "input", "tap", "1934", "88"), adb.call_args_list)

    @patch("capture_long.adb")
    def test_difficulty_only_for_stage_mode(self, adb):
        for arguments in [("endless", "test", "30", "--difficulty", "hard"),
                          ("stage", "test", "30", "--difficulty", "extreme")]:
            with patch("sys.argv", ["capture_long.py", *arguments]), \
                    patch("sys.stderr"), self.assertRaises(SystemExit) as error:
                capture_long.main()
            self.assertEqual(error.exception.code, 2)
        adb.assert_not_called()

    @patch("capture_long.adb")
    def test_foreign_audio_is_rejected(self, adb):
        adb.return_value = "AudioPlaybackConfiguration u/pid:10123/42 state:started usage=USAGE_MEDIA "
        with self.assertRaisesRegex(RuntimeError, "ゲーム以外"):
            capture_long.check_audio_owner(10456)

    @patch("capture_long.adb")
    def test_sleeping_screen_is_rejected(self, adb):
        for state in ("Asleep", "Dozing"):
            adb.return_value = f"mWakefulness={state}"
            with self.assertRaisesRegex(RuntimeError, "画面が消えて"):
                capture_long.check_screen_awake()
        adb.return_value = "mWakefulness=Awake"
        capture_long.check_screen_awake()


if __name__ == "__main__":
    unittest.main()
