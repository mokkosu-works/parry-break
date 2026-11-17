import json, tempfile, unittest, pathlib, subprocess, sys

import extract


class ExtractTest(unittest.TestCase):
    def test_result_message(self):
        msgs = [{"type": "assistant", "message": {"role": "assistant", "content": [{"type": "text", "text": "考え中"}]}},
                {"type": "result", "subtype": "success", "result": '前置き {"status": "ok"} 後書き'}]
        self.assertIn('{"status": "ok"}', extract.last_text(msgs))

    def test_fallback_and_cli(self):
        msgs = [{"type": "assistant", "message": {"role": "assistant", "content": [{"type": "text", "text": '{"a": 1}'}]}}]
        with tempfile.TemporaryDirectory() as d:
            src, out = pathlib.Path(d, "e.json"), pathlib.Path(d, "a.json")
            src.write_text(json.dumps(msgs))
            subprocess.run([sys.executable, "extract.py", str(src), str(out)], check=True, capture_output=True)
            self.assertEqual(json.loads(out.read_text()), {"a": 1})
            src.write_text("broken")
            subprocess.run([sys.executable, "extract.py", str(src), str(out)], check=True, capture_output=True)
            self.assertEqual(out.read_text(), "")


if __name__ == "__main__":
    unittest.main()
