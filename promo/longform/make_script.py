#!/usr/bin/env python3
"""解説・雑談の配置案に、記録された出来事から短い反応を割り当てる。

python3 promo/longform/make_script.py <配置案.json> --out <台本.json>
生成した台本は映像と照合し、声の長さはrender_long.py --prepare-onlyで確認する。
"""

import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
# characters/reactions.md の各キャラの欄から、短くて時機を限定しやすい候補を選ぶ。
# 鍵は「出来事の種類」に、反応の枠で指定した判定(:just など)とパリィ取得(:parried)を足したもの。
REACTIONS = {
    "akane": {
        "parry:just": [("よしっ、ジャスト！", "success"), ("ど真ん中！", "success")],
        "fever_start": [("来た、フィーバー！", "fired")],
        "collapse": [("うわ、ごっそり！", "surprise"), ("まとめて落ちた！", "success"), ("崩れた崩れた！", "surprise")],
    },
    # シズクは落ち着いた短い文で、「!」を使わない。
    "shizuku": {
        "parry:just": [("……今。ジャスト。悪くない。", "success")],
    },
    # モモカは見どころを褒める。絵コンテ v01 の台詞を先頭に。
    "momoka": {
        "collapse": [("見て見て! まとめて崩れた!", "surprise"), ("崩れた〜! きれい!", "success")],
    },
    "mitsuba": {
        "parry:just": [("えっ、いまの見た？ ジャスト！", "success"), ("ぴったりだと、ジャストになるんだね！", "success")],
        "fever_start": [("フィーバーだって！", "smug"), ("キラキラしてる！", "success")],
        "collapse": [("崩れた〜！", "success"), ("白いブロック、すごい！", "success")],
        "miss": [("あれ、早すぎた？", "surprise"), ("スカッ……！", "surprise")],
        "item_taken:parried": [("取れた！ 今のは、パリィ取り！", "success")],
        "round_cleared": [("クリア！ 次はどんなの？", "success"), ("やった〜！", "success")],
    },
}


def reaction_key(slot):
    key = slot["type"]
    if "grade" in slot:
        key += ":" + slot["grade"]
    if slot.get("parried"):
        key += ":parried"
    return key


def make(plan, aligned):
    if aligned.get("rejected"):
        raise ValueError("音声などの問題で不採用になったテイクです")
    if plan["profile"] not in REACTIONS:
        raise ValueError(f"反応集がないキャラです: {plan['profile']}")
    reactions = REACTIONS[plan["profile"]]
    for slot in plan["reactions"]:
        if reaction_key(slot) not in reactions:
            raise ValueError(f"この反応の台詞がありません: {reaction_key(slot)}")
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
            if "parried" in slot and event.get("parried") is not slot["parried"]:
                continue
            found.append(event)
        if not found:
            raise ValueError(f"反応の対象になる出来事がありません: {slot}")
        event = found[0]
        used.add(event["seq"])
        choices = reactions[reaction_key(slot)]
        previous = {l["text"] for l in lines[-2:]}
        choice = next((c for c in choices if c[0] not in previous), choices[0])
        lines.append({"start": round(event["video_s"] - start + .18, 3), "kind": "reaction",
                      "text": choice[0], "expression": choice[1], "event_seq": event["seq"],
                      "event_type": event["type"]})
    lines.sort(key=lambda l: l["start"])
    extra = {"insets": plan["insets"]} if "insets" in plan else {}
    return {**extra, "schema": 1, "profile": plan["profile"], "source": str(((ROOT / plan["events"]).parent / aligned["video"]).relative_to(ROOT)),
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
