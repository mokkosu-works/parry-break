#!/usr/bin/env python3
"""動画レイアウト編集ツールのローカルサーバー (標準ライブラリ + Pillow)。

    python3 promo/editor/server.py            # http://127.0.0.1:8765/ を開く
    python3 promo/editor/server.py --port 9000

127.0.0.1 だけで待ち受ける。外へ送るものはない (通信先はローカルの VOICEVOX だけ)。
"""

import argparse
import collections
import hashlib
import json
import mimetypes
import os
import pathlib
import sys
import threading
import time
import traceback
import urllib.parse
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

sys.dont_write_bytecode = True  # promo/editor/ に __pycache__ を作らない
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import render  # noqa: E402

STATIC = render.EDITOR / "static"
MEDIA_TYPES = {".mp4": "video/mp4", ".mov": "video/quicktime", ".webm": "video/webm", ".mkv": "video/x-matroska",
               ".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg",
               ".ttf": "font/ttf", ".otf": "font/otf"}
MAX_BODY = 5 * 1024 * 1024


class Cache:
    """プレビュー画像の小さな LRU。"""

    def __init__(self, size=300):
        self.size, self.items, self.lock = size, collections.OrderedDict(), threading.Lock()

    def get(self, key, make):
        with self.lock:
            if key in self.items:
                self.items.move_to_end(key)
                return self.items[key]
        value = make()
        with self.lock:
            self.items[key] = value
            while len(self.items) > self.size:
                self.items.popitem(last=False)
        return value


previews = Cache()


class Exporter:
    """書き出しを 1 本ずつ別スレッドで動かし、進み具合を持つ。"""

    def __init__(self):
        self.lock = threading.Lock()
        self.job = None

    def status(self):
        with self.lock:
            return dict(self.job) if self.job else {"state": "idle"}

    def start(self, name):
        with self.lock:
            if self.job and self.job["state"] == "running":
                return None, "書き出し中です。終わるまで待ってください"
        project = render.load_project(name)
        render.check(project)
        voicevox = render.voicevox_status()
        if not voicevox["ok"]:
            return None, voicevox
        with self.lock:
            if self.job and self.job["state"] == "running":
                return None, "書き出し中です。終わるまで待ってください"
            self.job = {"id": int(time.time() * 1000), "state": "running", "project": name, "message": "始めています",
                        "fraction": 0.0, "log": [], "startedAt": time.time()}
            job_id = self.job["id"]
        threading.Thread(target=self._run, args=(job_id, project), daemon=True).start()
        return job_id, None

    def _update(self, job_id, **changes):
        with self.lock:
            if self.job and self.job["id"] == job_id:
                if "message" in changes:
                    self.job["log"] = (self.job["log"] + [changes["message"]])[-50:]
                self.job.update(changes)

    def _run(self, job_id, project):
        def progress(message, fraction=None):
            changes = {"message": message}
            if fraction is not None:
                changes["fraction"] = round(fraction, 3)
            self._update(job_id, **changes)
        try:
            result = render.export(project, progress)
            self._update(job_id, state="done", result=result, fraction=1.0, finishedAt=time.time())
        except render.ProjectError as e:
            self._update(job_id, state="failed", error="プロジェクトに問題があります", problems=e.problems,
                         hint="画面の「問題」の一覧を直して保存してから、もう一度書き出してください")
        except render.ExportError as e:
            self._update(job_id, state="failed", error=str(e), hint=e.hint)
        except Exception as e:  # 想定外でも画面に理由を出す
            traceback.print_exc()
            self._update(job_id, state="failed", error=f"想定外の失敗: {e!r}",
                         hint="サーバーの端末に出ている詳しい内容を確かめてください")


exporter = Exporter()


class Handler(BaseHTTPRequestHandler):
    server_version = "PromoEditor/1"

    # ------------------------------------------------------------ 共通
    def log_message(self, fmt, *args):
        if os.environ.get("PROMO_EDITOR_LOG"):
            super().log_message(fmt, *args)

    def _allowed_host(self):
        host = (self.headers.get("Host") or "").lower()
        port = self.server.server_address[1]
        return host in (f"127.0.0.1:{port}", f"localhost:{port}")

    def _send(self, status, body, content_type, extra=None):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def _json(self, data, status=200):
        self._send(status, json.dumps(data, ensure_ascii=False).encode(), "application/json; charset=utf-8")

    def _error(self, status, message, **more):
        self._json({"error": message, **more}, status)

    def _body(self):
        if not (self.headers.get("Content-Type") or "").startswith("application/json"):
            raise ValueError("Content-Type は application/json にしてください")
        origin = self.headers.get("Origin")
        port = self.server.server_address[1]
        if origin and origin not in (f"http://127.0.0.1:{port}", f"http://localhost:{port}"):
            raise PermissionError("ほかのサイトからの操作は受け付けません")
        length = int(self.headers.get("Content-Length") or 0)
        if length > MAX_BODY:
            raise ValueError("送られた内容が大きすぎます")
        try:
            return json.loads(self.rfile.read(length) or b"null")
        except json.JSONDecodeError as e:
            raise ValueError(f"JSON として読めません: {e}")

    def _dispatch(self, routes):
        if not self._allowed_host():
            return self._error(403, "127.0.0.1 か localhost で開いてください")
        url = urllib.parse.urlsplit(self.path)
        query = dict(urllib.parse.parse_qsl(url.query))
        handler = routes.get(url.path)
        try:
            if handler:
                return handler(query)
            if self.command in ("GET", "HEAD"):
                return self._static(url.path)
            return self._error(404, "ありません")
        except PermissionError as e:
            self._error(403, str(e))
        except render.ProjectError as e:
            self._error(400, "プロジェクトに問題があります", problems=e.problems)
        except FileNotFoundError as e:
            self._error(404, str(e))
        except ValueError as e:
            self._error(400, str(e))
        except (BrokenPipeError, ConnectionResetError):
            pass
        except render.ExportError as e:
            self._error(500, str(e), hint=e.hint)
        except Exception as e:
            traceback.print_exc()
            self._error(500, f"サーバーで想定外の失敗: {e!r}")

    def do_GET(self):
        self._dispatch({"/api/projects": self.projects, "/api/project": self.get_project,
                        "/api/assets": self.assets, "/api/info": self.info, "/api/voicevox": self.voicevox,
                        "/api/voice": self.voice_wav,
                        "/api/export/status": self.export_status, "/media": self.media})

    def do_HEAD(self):
        self.do_GET()

    def do_POST(self):
        self._dispatch({"/api/project": self.save_project, "/api/validate": self.validate,
                        "/api/preview/layer": self.preview_layer, "/api/preview/background": self.preview_background,
                        "/api/export": self.start_export, "/api/voice/check": self.voice_check})

    # ------------------------------------------------------------ 画面のファイル
    def _static(self, path):
        if path in ("/", ""):
            path = "/index.html"
        target = pathlib.Path(os.path.normpath(STATIC / path.lstrip("/")))
        if os.path.commonpath([str(STATIC), str(target)]) != str(STATIC) or not target.is_file():
            return self._error(404, "ありません")
        ctype = mimetypes.guess_type(target.name)[0] or "application/octet-stream"
        if ctype.startswith("text/") or ctype == "application/javascript":
            ctype += "; charset=utf-8"
        self._send(200, target.read_bytes(), ctype)

    # ------------------------------------------------------------ プロジェクト
    def projects(self, q):
        names = sorted(p.stem for p in render.PROJECTS.glob("*.json"))
        self._json({"projects": names})

    def get_project(self, q):
        name = q.get("name", "")
        self._json({"project": render.load_project(name),
                    "path": str(render.project_path(name).relative_to(render.ROOT))})

    def save_project(self, q):
        project = self._body()
        problems = render.validate(project)
        if problems:
            return self._error(400, "保存できません。問題を直してください", problems=problems)
        path = render.save_project(project)
        self._json({"ok": True, "path": str(path.relative_to(render.ROOT))})

    def validate(self, q):
        self._json({"problems": render.validate(self._body())})

    def assets(self, q):
        self._json(render.list_assets())

    def info(self, q):
        self._json({
            "canvas": {"width": render.CANVAS[0], "height": render.CANVAS[1]},
            "scenes": [{"id": i, "label": l, "duration": d} for i, l, d in render.SCENES],
            "safeArea": {"top": 130, "bottom": 480},
            "voice": {**render.VOICE, "lines": render.default_voice_lines(),
                      "maxLines": render.MAX_VOICE_LINES, "maxText": render.MAX_VOICE_TEXT},
            "gameVolume": render.GAME_VOLUME, "bobHz": render.BOB_HZ, "credit": render.CREDIT_TEXT,
            "sheetCell": render.SHEET_CELL, "poses": render.POSES,
            "outDir": str(render.OUT_DIR.relative_to(render.ROOT)),
        })

    # ------------------------------------------------------------ プレビュー
    def preview_layer(self, q):
        layer = self._body()
        if not isinstance(layer, dict):
            raise ValueError("レイヤーの形が正しくありません")
        problems = []
        render._validate_layer(lambda w, m: problems.append(m), "", layer, 0, check_files=False)
        if problems:
            return self._error(400, " / ".join(problems))
        key = hashlib.sha256(json.dumps(layer, sort_keys=True).encode()).hexdigest()
        png, dx, dy = previews.get(("layer", key), lambda: render.layer_preview(layer))
        self._send(200, png, "image/png", {"X-Dx": str(dx), "X-Dy": str(dy)})

    def preview_background(self, q):
        bg = self._body()
        if not isinstance(bg, dict) or not render._num(bg.get("time")) or bg["time"] < 0:
            raise ValueError("背景の時刻は 0 以上の数にしてください")
        path = render.resolve(bg.get("src"), "video")
        key = (str(path), path.stat().st_mtime_ns, float(bg["time"]))
        try:
            jpg = previews.get(("bg",) + key, lambda: render.background_preview(bg))
        except render.ExportError as e:
            raise ValueError(f"背景のフレームを取り出せません: {e}")
        self._send(200, jpg, "image/jpeg")

    # ------------------------------------------------------------ 素材 (Range 対応)
    def media(self, q):
        path = render.resolve(q.get("src", ""))
        ctype = MEDIA_TYPES.get(path.suffix.lower())
        if not ctype:
            return self._error(403, "この種類のファイルは出せません")
        size = path.stat().st_size
        start, end, status = 0, size - 1, 200
        header = self.headers.get("Range")
        if header:
            try:
                unit, spec = header.split("=", 1)
                if unit.strip() != "bytes" or "," in spec:
                    raise ValueError
                a, b = spec.strip().split("-", 1)
                if a:
                    start, end = int(a), (int(b) if b else size - 1)
                else:
                    start, end = max(0, size - int(b)), size - 1
                end = min(end, size - 1)
                if start > end or start >= size:
                    raise ValueError
                status = 206
            except ValueError:
                self.send_response(416)
                self.send_header("Content-Range", f"bytes */{size}")
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(end - start + 1))
        self.send_header("Cache-Control", "no-cache")
        if status == 206:
            self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.end_headers()
        if self.command == "HEAD":
            return
        with open(path, "rb") as f:
            f.seek(start)
            left = end - start + 1
            while left > 0:
                chunk = f.read(min(1 << 16, left))
                if not chunk:
                    break
                self.wfile.write(chunk)
                left -= len(chunk)

    # ------------------------------------------------------------ 書き出し
    def voicevox(self, q):
        self._json(render.voicevox_status())

    def _voice_lines(self, voice):
        problems = []
        total = sum(s[2] for s in render.SCENES)
        render._validate_voice(lambda w, m: problems.append(f"{w}: {m}"), voice, total)
        return total, problems

    def voice_check(self, q):
        """台詞ごとの読み上げの長さと、重なり。VOICEVOX が動いていなければ、その旨を返す。"""
        body = self._body()
        voice = {"lines": body.get("lines") if isinstance(body, dict) else None}
        total, problems = self._voice_lines(voice)
        if problems:
            return self._json({"ok": False, "problems": problems, "lines": []})
        status = render.voicevox_status()
        if not status["ok"]:
            return self._json({"ok": False, "offline": True, "problems": [], "lines": [],
                               "message": "VOICEVOX が動いていないので、台詞の長さを確かめられません"})
        timed, problems = render.voice_timing(voice["lines"], total)
        self._json({"ok": not problems, "problems": problems, "total": total,
                    "lines": [{"duration": round(t["duration"], 3), "end": round(t["end"], 3)} for t in timed]})

    def voice_wav(self, q):
        """台詞 1 つの読み上げ (試し聞きとプレビューの再生に使う)。"""
        _total, problems = self._voice_lines({"lines": [{"start": 0, "text": q.get("text")}]})
        if problems:
            return self._error(400, " / ".join(problems))
        wav, _seconds = render.synthesize(q["text"])
        self._send(200, wav, "audio/wav")

    def start_export(self, q):
        body = self._body()
        name = body.get("name") if isinstance(body, dict) else None
        job_id, problem = exporter.start(name)
        if problem:
            if isinstance(problem, dict):
                return self._error(409, problem["message"], hint=problem["hint"])
            return self._error(409, problem)
        self._json({"ok": True, "id": job_id})

    def export_status(self, q):
        self._json(exporter.status())


def main():
    parser = argparse.ArgumentParser(description="宣伝動画のレイアウト編集ツール")
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    server.daemon_threads = True
    print(f"動画レイアウト編集ツール: http://127.0.0.1:{args.port}/  (止めるときは Ctrl+C)", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
