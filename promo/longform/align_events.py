#!/usr/bin/env python3
"""映像で確認した出来事1つを基準に、ログを録画の秒へ換算する。

python3 promo/longform/align_events.py <録画フォルダ> --anchor-seq 0 --video-time 4.25
--video-time は推測せず、対応するラウンド開始などをコマで確認して指定する。
"""

import argparse
import json
from pathlib import Path


def align(folder, anchor_seq, video_time, session=None, note="", through_seq=None):
    events = [json.loads(line) for line in (folder / "events-raw.jsonl").read_text().splitlines() if line.strip()]
    sessions = {e["session"] for e in events}
    if session is None:
        if len(sessions) != 1:
            raise ValueError(f"sessionを1つ指定してください: {sorted(sessions)}")
        session = next(iter(sessions))
    events = [e for e in events if e["session"] == session]
    if through_seq is not None:
        events = [e for e in events if e["seq"] <= through_seq]
    if not events:
        raise ValueError("指定したsessionの出来事がありません")
    seqs = [e["seq"] for e in events]
    if seqs != list(range(seqs[0], seqs[-1] + 1)):
        raise ValueError("出来事に欠落・重複・順序の乱れがあります")
    if any(b["clock_s"] < a["clock_s"] for a, b in zip(events, events[1:])):
        raise ValueError("ゲームの時計が逆行しています")
    anchors = [e for e in events if e["seq"] == anchor_seq]
    if len(anchors) != 1:
        raise ValueError("基準にした出来事を特定できません")
    anchor = anchors[0]
    result = folder / "events.json"
    if result.exists():
        raise FileExistsError(f"既存の換算済みログがあります(改訂時はold/へ退避): {result}")
    metadata = json.loads((folder / "capture.json").read_text())
    if metadata.get("status") != "recorded_unaligned":
        raise ValueError("正常に録画できたテイクではありません")
    duration = float(metadata["probe"]["format"]["duration"])
    if not 0 <= video_time < duration:
        raise ValueError("基準の秒が映像の範囲外です")
    for event in events:
        event["video_s"] = video_time + event["clock_s"] - anchor["clock_s"]
    forbidden = [e["video_s"] for e in events if e["type"] == "round_started" and (
        metadata["mode"] == "endless" and e.get("number", 0) >= 10 or e.get("boss") is not None
    )]
    # 欠けたログより前だけを使う場合は、使用可能な映像もそこまでに制限する。
    log_end = events[-1]["video_s"] if through_seq is not None else duration
    safe_end = min([duration, log_end, *[max(0, t - .2) for t in forbidden]])
    payload = {"schema": 1, "capture": str(folder.resolve()), "video": "capture.mp4", "session": session,
               "duration": duration, "safe_end": safe_end,
               "alignment": {"anchor_seq": anchor_seq, "video_s": video_time,
                             "clock_s": anchor["clock_s"], "note": note, "through_seq": through_seq,
                             "method": "映像内の出来事とログを目視で照合。フレーム単位の差は試作で確認する。"},
               "events": events}
    result.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n")
    print(f"{len(events)}件。使用可能な終わり: {safe_end:.3f}秒。{result}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("folder", type=Path)
    parser.add_argument("--anchor-seq", required=True, type=int)
    parser.add_argument("--video-time", required=True, type=float)
    parser.add_argument("--session")
    parser.add_argument("--note", default="")
    parser.add_argument("--through-seq", type=int, help="明示的にここまでの連続したログだけを使い、映像もここまでに制限する")
    args = parser.parse_args()
    align(args.folder, args.anchor_seq, args.video_time, args.session, args.note, args.through_seq)
