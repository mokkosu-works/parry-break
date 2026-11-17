#!/usr/bin/env python3
"""収集。YouTube・Google Play・App Store の日次の事実を、データ用リポジトリの store/ に upsert する。

  python3 collect.py run --root <データ用リポジトリの clone> [--days 14] [--sources youtube,play,appstore]
  python3 collect.py backfill --root <…> --since 2026-08-01 [--sources …]

毎回、直近 --days 日を取り直して上書きする (数字の確定の遅れを吸収)。1 つの source が失敗しても、ほかは保存して続ける。
失敗した source があれば、最後に終了コード 1 で終わる (ジョブが赤になり、通知に出る)。ログに数字は出さない (公開リポジトリのため。件数だけ)。
動画のメタ情報 (タイトル・公開日) は store/meta/youtube_videos.json に残す。
"""
import argparse, datetime, sys

import appstore, play, store, youtube

LAG = 2


def run_source(name, root, start, end, today):
    if name == "youtube":
        rows, meta = youtube.collect(start, end, today)
        store.update_meta(root, "youtube_videos", meta)
        return rows, [], []
    if name == "play":
        return (*play.collect(start, end), [])
    if name == "appstore":
        return appstore.collect(start, end)
    raise ValueError(f"source が不正: {name}")


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["run", "backfill"])
    ap.add_argument("--root", required=True)
    ap.add_argument("--days", type=int, default=14)
    ap.add_argument("--since")
    ap.add_argument("--sources", default="youtube,play,appstore")
    a = ap.parse_args(argv)
    today = datetime.date.today()
    end = today - datetime.timedelta(days=LAG)
    start = datetime.date.fromisoformat(a.since) if a.cmd == "backfill" and a.since else end - datetime.timedelta(days=a.days - 1)
    failed = 0
    for name in a.sources.split(","):
        try:
            rows, notes, info = run_source(name, a.root, start, end, today)
            new, upd = store.upsert(a.root, rows)
            # 行があれば ok (取れなかった経路は note に残す)。行がなく経路の失敗があれば ng、失敗もなければ no_data
            state = "ok" if rows else ("ng" if notes else "no_data")
            store.record_status(a.root, name, today.isoformat(), state, "; ".join(notes + info))
            print(f"{name}: {state} (行 {len(rows)}、新規 {new}、更新 {upd}、取れなかった経路 {len(notes)})")
            for n in notes + info:
                print(f"  - {n}")
            failed += state == "ng"
        except Exception as e:  # 1 つの source の失敗で、ほかを止めない。例外の本文は出さない (鍵や数字が入りうる)
            store.record_status(a.root, name, today.isoformat(), "ng", type(e).__name__)
            print(f"{name}: 失敗 ({type(e).__name__}: {str(e)[:120]})")
            failed += 1
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
