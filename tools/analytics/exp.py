#!/usr/bin/env python3
"""実験の記録 (追記だけの JSON Lines)。作業した AI や人が「何を、いつ実行したか」を残し、以降の日次の分析が結果を評価する。

  python3 exp.py add --target video|game --action '実行したこと' --metric '見る指標' [--metric ...] [--proposal-id ID] [--baseline '実行前の数字']
  python3 exp.py close --id E-20261116-01 --status done|abandoned --note '結果や理由'
  python3 exp.py list [--open]

  共通: --root <データ用リポジトリ (mokkosu-works/analytics) の clone>。既定は環境変数 ANALYTICS_DATA、なければ ../analytics

保存先: <root>/store/experiments.jsonl。書いたら、データ用リポジトリで commit して push する (日次の分析が読む)。
"""
import argparse, datetime, json, os, pathlib, re, sys

PATH = None


def set_root(root):
    global PATH
    PATH = pathlib.Path(root) / "store" / "experiments.jsonl"


def read_at(root):
    set_root(root)
    return read()


def clean(s, n):
    return re.sub(r"[\x00-\x08\x0b-\x1f\x7f]", " ", str(s)).strip()[:n]


def read():
    out = {}
    if PATH.exists():
        for line in PATH.read_text().splitlines():
            if not line.strip():
                continue
            e = json.loads(line)
            if e["event"] == "add":
                out[e["id"]] = {**e, "status": "open"}
            elif e["event"] == "close" and e["id"] in out:
                out[e["id"]].update(status=e["status"], closed=e["at"], note=e.get("note", ""))
    return out


def append(e):
    PATH.parent.mkdir(parents=True, exist_ok=True)
    with PATH.open("a") as f:
        f.write(json.dumps(e, ensure_ascii=False) + "\n")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--root", default=os.environ.get("ANALYTICS_DATA", "../analytics"))
    sub = ap.add_subparsers(dest="cmd", required=True)
    a = sub.add_parser("add")
    a.add_argument("--target", choices=["video", "game", "data"], required=True)
    a.add_argument("--action", required=True)
    a.add_argument("--metric", action="append", required=True)
    a.add_argument("--proposal-id", default="")
    a.add_argument("--baseline", default="")
    c = sub.add_parser("close")
    c.add_argument("--id", required=True)
    c.add_argument("--status", choices=["done", "abandoned"], required=True)
    c.add_argument("--note", default="")
    l = sub.add_parser("list")
    l.add_argument("--open", action="store_true")
    args = ap.parse_args()
    if not (pathlib.Path(args.root) / ".git").exists():
        sys.exit(f"{args.root} がデータ用リポジトリの clone ではない (--root か ANALYTICS_DATA で指定する)")
    set_root(args.root)
    now = datetime.datetime.now().isoformat(timespec="seconds")
    if args.cmd == "add":
        day = datetime.date.today().strftime("%Y%m%d")
        n = sum(1 for e in read() if e.startswith(f"E-{day}")) + 1
        e = {"event": "add", "id": f"E-{day}-{n:02d}", "at": now, "target": args.target,
             "action": clean(args.action, 300), "metrics_to_watch": [clean(m, 80) for m in args.metric][:6],
             "proposal_id": clean(args.proposal_id, 40), "baseline": clean(args.baseline, 300)}
        append(e)
        print("記録した:", e["id"])
    elif args.cmd == "close":
        if args.id not in read():
            sys.exit("その ID の実験がない")
        append({"event": "close", "id": args.id, "at": now, "status": args.status, "note": clean(args.note, 300)})
        print("閉じた:", args.id)
    else:
        for e in read().values():
            if args.open and e["status"] != "open":
                continue
            print(f"{e['id']} [{e['status']}] ({e['target']}) {e['action']} / 見る指標: {', '.join(e['metrics_to_watch'])}"
                  + (f" / 実行前: {e['baseline']}" if e.get("baseline") else "")
                  + (f" / 結果: {e.get('note')}" if e.get("note") else ""))


if __name__ == "__main__":
    main()
