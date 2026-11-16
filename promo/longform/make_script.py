#!/usr/bin/env python3
"""解説・雑談の配置案に、記録された出来事から短い反応を割り当てる。

python3 promo/longform/make_script.py <配置案.json> --out <台本.json>
生成した台本は映像と照合し、声の長さはrender_long.py --prepare-onlyで確認する。
"""

import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
# characters/reactions.md のアカネ欄から、短くて時機を限定しやすい候補を選ぶ。
REACTIONS = {
    "parry:just": [("よしっ、ジャスト！", "success"), ("ど真ん中！", "success")],
    "fever_start": [("来た、フィーバー！", "fired")],
    "collapse": [("まとめて落ちた！", "success"), ("崩れた崩れた！", "surprise")],
}


def make(plan, aligned):
    if aligned.get("rejected"):
        raise ValueError("音声などの問題で不採用になったテイクです")
    if plan["profile"] != "akane":
        raise ValueError("いまの反応集はアカネのみ")
    anchor = aligned["alignment"]
    start = anchor["video_s"] - anchor["clock_s"] + plan["source_clock_start"]
    if start < 0 or start + plan["duration"] > aligned["safe_end"]:
        raise ValueError("指定した区間が録画の範囲外です")
    lines = [dict(line) for line in plan["lines"]]
    used = set()
    for slot in plan["reactions"]:
        found = []
        for event in aligned["events"]:
            t = event["video_s"] - start
            if event["seq"] in used or event["type"] != slot["type"] or not slot["after"] <= t <= slot["before"]:
                continue
            if "grade" in slot and event.get("grade") != slot["grade"]:
                continue
            found.append(event)
        if not found:
            raise ValueError(f"反応の対象になる出来事がありません: {slot}")
        event = found[0]
        used.add(event["seq"])
        key = event["type"] + (":" + slot["grade"] if "grade" in slot else "")
        choices = REACTIONS[key]
        previous = {l["text"] for l in lines[-2:]}
        choice = next((c for c in choices if c[0] not in previous), choices[0])
        lines.append({"start": round(event["video_s"] - start + .18, 3), "kind": "reaction",
                      "text": choice[0], "expression": choice[1], "event_seq": event["seq"],
                      "event_type": event["type"]})
    lines.sort(key=lambda l: l["start"])
    return {"schema": 1, "profile": plan["profile"], "source": str((Path(aligned["capture"]) / aligned["video"]).relative_to(ROOT)),
            "events": plan["events"], "source_start": start, "duration": plan["duration"],
            "note": plan["note"], "lines": lines}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("plan", type=Path)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    if args.out.exists():
        raise SystemExit("台本が既にあります(上書きしません)")
    plan = json.loads(args.plan.read_text())
    aligned = json.loads((ROOT / plan["events"]).read_text())
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(make(plan, aligned), ensure_ascii=False, indent=2) + "\n")
    print(args.out)
