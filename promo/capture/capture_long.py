#!/usr/bin/env python3
"""scrcpy録画と撮影ビルドの出来事ログを保存。既存テイクは上書きしない。"""

import argparse
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import threading
import time

ROOT = Path(__file__).resolve().parents[2]
PREFIX = "PARRY_PROMO_EVENT "


def adb(*args):
    return subprocess.check_output(["adb", *args], text=True, stderr=subprocess.STDOUT).strip()


def active_media_players(dump):
    """現在の再生状態だけを見る。過去のイベントログのstartedは対象にしない。"""
    players = []
    for line in dump.splitlines():
        if "AudioPlaybackConfiguration " not in line or "state:started " not in line:
            continue
        if "usage=USAGE_ASSISTANCE_SONIFICATION" in line:
            continue
        match = re.search(r"u/pid:(\d+)/(\d+)", line)
        if match:
            players.append({"uid": int(match[1]), "pid": int(match[2]), "description": line.strip()})
    return players


def check_audio_owner(expected_uid):
    players = active_media_players(adb("shell", "dumpsys", "audio"))
    foreign = [p for p in players if p["uid"] != expected_uid]
    if foreign:
        raise RuntimeError("ゲーム以外の音声再生を検知しました。録画は採用しません: "
                           + ", ".join(f"uid={p['uid']} pid={p['pid']}" for p in foreign))
    return players


def stop(proc, sig=signal.SIGINT):
    if proc is None or proc.poll() is not None:
        return
    proc.send_signal(sig)
    try:
        proc.wait(timeout=12)
    except subprocess.TimeoutExpired:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("mode", choices=["endless", "daily", "practice", "stage"])
    p.add_argument("take")
    p.add_argument("seconds", nargs="?", type=int, default=120)
    args = p.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9_-]{1,60}", args.take) or not 15 <= args.seconds <= 600:
        p.error("テイクは英数字・_-の60文字まで、録画秒数は15〜600")
    pkg = os.environ.get("PROMO_PKG", "com.watsuwo.parrybreak.promo")
    if pkg != "com.watsuwo.parrybreak.promo":
        p.error("この道具は撮影用 com.watsuwo.parrybreak.promo だけを操作します")
    dest = ROOT / "promo/capture/raw" / f"long-{args.mode}-{args.take}"
    dest.mkdir(parents=True, exist_ok=False)
    video, logcat, metadata = dest / "capture.mp4", dest / "logcat.txt", dest / "capture.json"
    info = {"schema": 1, "mode": args.mode, "package": pkg, "video": str(video.relative_to(ROOT)),
            "requested_seconds": args.seconds, "alignment": "未調整。映像と出来事を照合してから台詞を割り当てる。"}
    recorder = logger = None
    worker = None
    events = []
    stop_reason = []
    try:
        if adb("get-state") != "device":
            raise RuntimeError("端末が1台だけつながっていることを確認してください")
        power = adb("shell", "dumpsys", "power")
        if re.search(r"mWakefulness=(?:Asleep|Dozing)", power):
            raise RuntimeError("端末の画面が消えています。本人に画面の点灯とロック解除を依頼してください")
        size = adb("shell", "wm", "size")
        sizes = re.findall(r"(?:Physical|Override) size:\s*(\d+x\d+)", size)
        if not sizes or sizes[-1] not in ("2400x1080", "1080x2400"):
            raise RuntimeError(f"想定外の画面サイズ: {size}")
        if not adb("shell", "pm", "path", pkg).startswith("package:"):
            raise RuntimeError("撮影用アプリがありません")
        current_user = adb("shell", "am", "get-current-user")
        if not current_user.isdigit():
            raise RuntimeError("端末の使用中のユーザーを特定できません")
        package_info = adb("shell", "cmd", "package", "list", "packages", "--user", current_user, "-U", pkg)
        owner = re.search(rf"package:{re.escape(pkg)} uid:(\d+)(?:\s|$)", package_info)
        if not owner:
            raise RuntimeError("撮影用アプリのUIDを特定できません")
        audio_uid = int(owner[1])
        # playbackは別アプリの音も取り込む。開始前と録画中に再生元を確認する。
        info["audio_guard"] = {"expected_uid": audio_uid, "interval_seconds": 1, "checks": 0}
        check_audio_owner(audio_uid)
        info["device"] = adb("get-serialno")
        info["screen_size"] = sizes[-1]
        adb("shell", "am", "force-stop", pkg)
        adb("shell", "monkey", "-p", pkg, "-c", "android.intent.category.LAUNCHER", "1")
        time.sleep(6)
        pid = adb("shell", "pidof", pkg)
        if not pid.isdigit():
            raise RuntimeError("撮影用アプリのプロセスを特定できません")
        info["pid"] = int(pid)
        logger = subprocess.Popen(["adb", "logcat", f"--pid={pid}", "-v", "epoch", "-T", "1"],
                                  stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)

        def read_log():
            with logcat.open("w") as out:
                for line in logger.stdout:
                    out.write(line)
                    out.flush()
                    if PREFIX not in line:
                        continue
                    try:
                        event = json.loads(line.split(PREFIX, 1)[1])
                    except (json.JSONDecodeError, ValueError):
                        continue
                    events.append(event)
                    if args.mode == "endless" and (
                        event.get("type") == "round_cleared" and event.get("round", 0) >= 9
                        or event.get("type") == "round_started" and event.get("number", 0) >= 10
                    ):
                        stop_reason.append("R9クリア、またはR10開始を検知。編集ではR10開始前に制限する。")

        worker = threading.Thread(target=read_log, daemon=True)
        worker.start()
        info["host_recorder_started_s"] = time.time()
        with (dest / "scrcpy.log").open("w") as recorder_log:
            recorder = subprocess.Popen(["scrcpy", "--no-playback", "--no-control", "--audio-source=playback",
                                         "--video-bit-rate=16M", "--max-fps=60", f"--record={video}",
                                         "--record-format=mp4"], stdout=recorder_log, stderr=subprocess.STDOUT)
            time.sleep(4)
            if recorder.poll() is not None:
                raise RuntimeError("scrcpyが録画を開始できませんでした。scrcpy.logを確認してください")
            info["audio_guard"]["initial_players"] = check_audio_owner(audio_uid)
            info["audio_guard"]["checks"] += 1
            info["host_mode_tap_before_s"] = time.time()
            if args.mode == "endless":
                adb("shell", "input", "tap", "1740", "392")
            elif args.mode == "daily":
                adb("shell", "input", "tap", "430", "870")
            elif args.mode == "practice":
                adb("shell", "input", "tap", "470", "976")
            else:
                adb("shell", "input", "tap", "1720", "506")
                time.sleep(2.5)
                # ステージの章は保存状態に依存するため、左キーで第1章へ戻す。
                adb("shell", "input", "keyevent", *(["KEYCODE_DPAD_LEFT"] * 30))
                time.sleep(1)
                adb("shell", "input", "tap", "291", "535")
                time.sleep(2)
                adb("shell", "input", "tap", "2102", "927")
            info["host_mode_tap_after_s"] = time.time()
            started = time.monotonic()
            next_audio_check = started
            while time.monotonic() - started < args.seconds:
                if recorder.poll() is not None or logger.poll() is not None:
                    raise RuntimeError("録画か出来事ログの記録が途中で終了しました")
                if stop_reason:
                    break
                if time.monotonic() >= next_audio_check:
                    check_audio_owner(audio_uid)
                    info["audio_guard"]["checks"] += 1
                    next_audio_check = time.monotonic() + 1
                if not events and time.monotonic() - started > 15:
                    raise RuntimeError("出来事ログが来ません。PROMO_EVENT_LOG=trueのAPKか、タイトル画面の状態を確認してください")
                time.sleep(.1)
            info["stop_reason"] = stop_reason[0] if stop_reason else "指定した録画秒数"
            info["audio_guard"]["final_players"] = check_audio_owner(audio_uid)
            stop(recorder)
        if not video.exists() or video.stat().st_size == 0 or not events:
            raise RuntimeError("映像か出来事ログが空です")
        probe = json.loads(subprocess.check_output(["ffprobe", "-v", "error", "-show_streams", "-show_format", "-of", "json", str(video)]))
        if not any(s.get("codec_type") == "audio" for s in probe["streams"]):
            raise RuntimeError("ゲームの音声が録画されていません")
        info["probe"] = probe
        info["status"] = "recorded_unaligned"
        print(f"録画とログ: {dest.relative_to(ROOT)}", flush=True)
    except BaseException as error:
        info["status"] = "failed"
        info["error"] = str(error)
        raise
    finally:
        stop(recorder)
        stop(logger, signal.SIGTERM)
        if worker:
            worker.join(timeout=3)
        if logger and logger.stdout:
            logger.stdout.close()
        info["event_count"] = len(events)
        metadata.write_text(json.dumps(info, ensure_ascii=False, indent=2) + "\n")
        (dest / "events-raw.jsonl").write_text("".join(json.dumps(e, ensure_ascii=False) + "\n" for e in events))
        if "device" in info:
            adb("shell", "am", "force-stop", pkg)


if __name__ == "__main__":
    main()
