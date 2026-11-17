#!/usr/bin/env python3
"""v1.6.0の別コピーから、ミツバ撮影用のログ付きAPKを2種類作る。"""

import hashlib
import io
import json
from pathlib import Path
import subprocess
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def run(*args, cwd):
    subprocess.run(args, cwd=cwd, check=True)


def replace_once(path, before, after):
    text = path.read_text()
    if text.count(before) != 1:
        raise RuntimeError(f"想定したv1.6.0の内容と異なります: {path}")
    path.write_text(text.replace(before, after, 1))


def main():
    output = ROOT / "promo/capture/apk"
    output.mkdir(exist_ok=True)
    names = {kind: f"promo_v1.6.0_mitsuba_{kind}_events_arm64.apk"
             for kind in ("just", "sloppy")}
    manifest = output / "mitsuba-v160-build.json"
    if manifest.exists() or any((output / name).exists() for name in names.values()):
        raise RuntimeError("出力が既にあります。上書きしません")
    revision = subprocess.check_output(
        ["git", "rev-parse", "v1.6.0^{commit}"], cwd=ROOT, text=True).strip()
    work = Path(tempfile.mkdtemp(prefix="parry-mitsuba-v160-"))
    print(f"撮影専用の作業場所: {work}", flush=True)
    archive = subprocess.check_output(["git", "archive", revision, "app"], cwd=ROOT)
    with tarfile.open(fileobj=io.BytesIO(archive)) as source:
        source.extractall(work, filter="data")
    app = work / "app"
    run("patch", "-p1", "-i", str(ROOT / "promo/capture/promo-build.patch"), cwd=work)
    replace_once(app / "android/app/build.gradle.kts",
                 'applicationId = "com.watsuwo.parrybreak"',
                 'applicationId = "com.watsuwo.parrybreak"\n        applicationIdSuffix = ".promo"')
    replace_once(app / "lib/services/ads.dart", "static const enabled = true;",
                 "static const enabled = false;")
    # 元のパッチの1.5.1向け互換性を保ち、v1.6.0の撮影コピーにだけ詳細を足す。
    controller = app / "lib/game/game_controller.dart"
    replace_once(controller, "      _ => <String, Object?>{'type': e.runtimeType.toString()},",
                 "      ItemTaken() => <String, Object?>{'type': 'item_taken', "
                 "'kind': e.kind.name, 'parried': e.parried, 'grade': e.grade?.name, "
                 "'points': e.points},\n"
                 "      _ => <String, Object?>{'type': e.runtimeType.toString()},")
    run("dart", "format", "lib/game/game_controller.dart", cwd=app)
    run("flutter", "pub", "get", cwd=app)
    run("flutter", "analyze", "--no-pub", cwd=app)
    common = ["--dart-define=PROMO_AUTOPLAY=true", "--dart-define=PROMO_EVENT_LOG=true"]
    record = {"revision": revision, "version": "1.6.0", "work_dir": str(work),
              "package": "com.watsuwo.parrybreak.promo", "ads_enabled": False,
              "event_log": True, "item_taken_details": True, "builds": {}}
    for kind, name in names.items():
        flags = common + (["--dart-define=PROMO_SIGMA=0.006", "--dart-define=PROMO_SPEED=1500",
                           "--dart-define=PROMO_BIAS=0", "--dart-define=PROMO_LAG_COMP=true"]
                          if kind == "just" else [])
        # release用にプラグイン登録を再生成する（解析時のintegration_test登録を残さない）。
        run("flutter", "build", "apk", "--release",
            "--target-platform", "android-arm64", *flags, cwd=app)
        data = (app / "build/app/outputs/flutter-apk/app-release.apk").read_bytes()
        with (output / name).open("xb") as destination:
            destination.write(data)
        record["builds"][kind] = {"file": name, "sha256": hashlib.sha256(data).hexdigest(),
                                  "dart_defines": flags}
        print(f"保存: {output / name}", flush=True)
    with manifest.open("x") as destination:
        destination.write(json.dumps(record, ensure_ascii=False, indent=2) + "\n")


if __name__ == "__main__":
    main()
