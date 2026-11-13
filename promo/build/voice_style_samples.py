#!/usr/bin/env python3
"""キャラクター音声の比較用に、VOICEVOX の短いサンプルを2種類出力する。"""

import json
import pathlib
import urllib.parse
import urllib.request

OUT = pathlib.Path(__file__).resolve().parent / "out"
ENGINE = "http://127.0.0.1:50021"
TEXT = "この弾、返せる？"
STYLES = {
    "voice-low": (8, {"pitchScale": -0.08, "intonationScale": 0.9, "speedScale": 1.08}),
    "voice-bright": (8, {"pitchScale": 0.06, "intonationScale": 1.2, "speedScale": 1.13}),
    "voice-lively": (8, {"pitchScale": 0.10, "intonationScale": 1.35, "speedScale": 1.18}),
    "voice-haruka-nana": (54, {"intonationScale": 1.18, "speedScale": 1.12}),
    "voice-whitecul-happy": (24, {"intonationScale": 1.18, "speedScale": 1.10}),
}


def post(path, data, content_type=None):
    headers = {"Content-Type": content_type} if content_type else {}
    req = urllib.request.Request(ENGINE + path, data=data, headers=headers)
    with urllib.request.urlopen(req, timeout=120) as response:
        return response.read()


def main():
    OUT.mkdir(exist_ok=True)
    for name, (speaker, settings) in STYLES.items():
        params = urllib.parse.urlencode({"text": TEXT, "speaker": speaker})
        query = json.loads(post(f"/audio_query?{params}", b""))
        adjusted = dict(query, **settings)
        wav = post(f"/synthesis?speaker={speaker}", json.dumps(adjusted).encode(), "application/json")
        path = OUT / f"{name}.wav"
        path.write_bytes(wav)
        print(path)


if __name__ == "__main__":
    main()
