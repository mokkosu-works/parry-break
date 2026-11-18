#!/usr/bin/env python3
"""デイリーの連続日数 (STREAK) を撮るための、撮影専用 APK を作る (2026-11-18)。

python3 promo/capture/build_streak.py            # 昨日まで 4 日続けた記録で始まる (今日遊ぶと 5 日)
python3 promo/capture/build_streak.py --days 6

本物の連続日数は、毎日 1 回デイリーを遊ばないと積み上がらない。撮影のために何日も待たなくてよいように、
最初の起動のとき (デイリーの記録がまだないときだけ) 「昨日まで N 日続けた」記録を入れておく。
ほかは build_mitsuba.py の JUST 版と同じ (v1.6.0、広告オフ、自動プレイ、出来事ログ)。

- パッケージは com.watsuwo.parrybreak.promostreak。いつもの撮影用アプリ (.promo) とも、ストア版とも別に入る。
  どちらの記録も消さない。
- 映る連続日数は、実際に遊び続けた日数ではない。動画で使うときは、本人に伝えてから使う。
- リポジトリの app/ は変更しない。既存の出力は上書きしない。
"""

import argparse
import hashlib
import io
import json
from pathlib import Path
import subprocess
import tarfile
import tempfile

from build_mitsuba import ROOT, replace_once, run

PACKAGE = "com.watsuwo.parrybreak.promostreak"
JUST_FLAGS = ["--dart-define=PROMO_AUTOPLAY=true", "--dart-define=PROMO_EVENT_LOG=true",
              "--dart-define=PROMO_SIGMA=0.006", "--dart-define=PROMO_SPEED=1500",
              "--dart-define=PROMO_BIAS=0", "--dart-define=PROMO_LAG_COMP=true"]


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--days", type=int, default=4, help="昨日までの連続日数 (2 以上)")
    args = parser.parse_args()
    if args.days < 2:
        parser.error("--days は 2 以上")
    output = ROOT / "promo/capture/apk"
    output.mkdir(exist_ok=True)
    name = f"promo_v1.6.0_streak{args.days}_events_arm64.apk"
    manifest = output / f"streak{args.days}-v160-build.json"
    if (output / name).exists() or manifest.exists():
        raise SystemExit("出力が既にあります。上書きしません")
    revision = subprocess.check_output(["git", "rev-parse", "v1.6.0^{commit}"], cwd=ROOT, text=True).strip()
    work = Path(tempfile.mkdtemp(prefix="parry-streak-v160-"))
    print(f"撮影専用の作業場所: {work}", flush=True)
    archive = subprocess.check_output(["git", "archive", revision, "app"], cwd=ROOT)
    with tarfile.open(fileobj=io.BytesIO(archive)) as source:
        source.extractall(work, filter="data")
    app = work / "app"
    run("patch", "-p1", "-i", str(ROOT / "promo/capture/promo-build.patch"), cwd=work)
    replace_once(app / "android/app/build.gradle.kts",
                 'applicationId = "com.watsuwo.parrybreak"',
                 'applicationId = "com.watsuwo.parrybreak"\n        applicationIdSuffix = ".promostreak"')
    replace_once(app / "lib/services/ads.dart", "static const enabled = true;",
                 "static const enabled = false;")
    # 最初の起動で、デイリーの記録 (daily.v1) がなければ「昨日 (UTC の日付) まで N 日続けた」記録を入れる。
    replace_once(app / "lib/main.dart",
                 "    prefs = await SharedPreferences.getInstance();\n",
                 "    prefs = await SharedPreferences.getInstance();\n"
                 "    // 撮影専用: デイリーの連続日数を見せるため、記録がなければ昨日まで続けた記録を入れる。\n"
                 "    if (prefs.getString('daily.v1') == null) {\n"
                 "      final now = DateTime.now().toUtc();\n"
                 "      final today = DateTime.utc(now.year, now.month, now.day).millisecondsSinceEpoch ~/\n"
                 "          Duration.millisecondsPerDay;\n"
                 "      await prefs.setString('daily.v1',\n"
                 f"          '{{\"version\":1,\"lastDay\":${{today - 1}},\"lastScore\":0,\"bestScore\":0,\"streak\":{args.days}}}');\n"
                 "    }\n")
    run("dart", "format", "lib/main.dart", cwd=app)
    run("flutter", "pub", "get", cwd=app)
    run("flutter", "analyze", "--no-pub", cwd=app)
    run("flutter", "build", "apk", "--release", "--target-platform", "android-arm64", *JUST_FLAGS, cwd=app)
    data = (app / "build/app/outputs/flutter-apk/app-release.apk").read_bytes()
    with (output / name).open("xb") as destination:
        destination.write(data)
    record = {"revision": revision, "version": "1.6.0", "work_dir": str(work), "package": PACKAGE,
              "ads_enabled": False, "event_log": True, "seed_streak_days": args.days,
              "file": name, "sha256": hashlib.sha256(data).hexdigest(), "dart_defines": JUST_FLAGS}
    with manifest.open("x") as destination:
        destination.write(json.dumps(record, ensure_ascii=False, indent=2) + "\n")
    print(f"保存: {output / name}", flush=True)


if __name__ == "__main__":
    main()
