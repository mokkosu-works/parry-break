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
        for stage, x, chapters in [("1-1", "178", 0), ("1-2", "455", 0),
                                    ("1-4", "1009", 0), ("2-1", "178", 1)]:
            adb.reset_mock()
            capture_long.select_stage(stage)
            self.assertIn(call("shell", "input", "tap", x, "535"), adb.call_args_list)
            self.assertEqual(adb.call_args_list.count(
                call("shell", "input", "tap", "1368", "225")), chapters)
            self.assertEqual(adb.call_args_list[-1],
                             call("shell", "input", "tap", "2102", "927"))

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
