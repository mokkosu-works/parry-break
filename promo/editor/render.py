#!/usr/bin/env python3
"""動画レイアウト編集ツールの描画と書き出し。

プロジェクト JSON (promo/editor/projects/*.json) を受け取り、
promo/build/character_promo.py (v12) と同じ手順で 24 秒の縦動画を作る。
character_promo.py は v12 を再現する記録として残し、ここでは書き換えずに処理を流用している。

使い方 (画面を使わずに書き出す):
    python3 promo/editor/render.py promo/editor/projects/character-promo.json
"""

import hashlib
import io
import json
import math
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import urllib.error
import urllib.parse
import urllib.request
import wave

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont

EDITOR = pathlib.Path(__file__).resolve().parent
ROOT = EDITOR.parents[1]
PROJECTS = EDITOR / "projects"
OUT_DIR = ROOT / "promo/build/out"

ENGINE = "http://127.0.0.1:50021"
# 話者と話し方は固定 (クレジットが「VOICEVOX:春歌ナナ」なので)。台詞と話し始めの時刻は、
# プロジェクトの voice.lines で変えられる。ないときは、下の v12 (character_promo.py) と同じ台詞を使う。
VOICE = {
    "speaker": 54,  # 春歌ナナ・ノーマル
    "speakerName": "春歌ナナ",
    "speedScale": 1.12,
    "intonationScale": 1.18,
    "lines": [(0.15, 3, "この弾、返せる？"),
              (3.2, 8, "当たる瞬間に、タップ！"),
              (11.2, 16, "白いブロックを壊すと……"),
              (16.0, 19, "まとめて、どーん！"),
              (19.3, 24, "パリィブレイク。ストアで検索！")],
}
MAX_VOICE_LINES = 12
MAX_VOICE_TEXT = 80
CREDIT_TEXT = "VOICEVOX:春歌ナナ"
GAME_VOLUME = 0.52
FPS = 30
CANVAS = (1080, 1920)
# 初版ではシーンの順序と長さを変えない (既存の 24 秒構成)
SCENES = [("intro", "冒頭", 3), ("parry", "パリィ", 8), ("collapse", "ブロック崩壊", 8), ("outro", "アウトロ", 5)]
SHEET_CELL = (362, 724)  # キャラクターシート 1 ポーズの大きさ
POSES = 6
BOB_HZ = 1.8

LAYER_TYPES = {"text": "テキスト", "image": "画像", "video": "ゲーム映像", "rect": "枠", "character": "キャラクター"}
EXT = {"image": {".png", ".jpg", ".jpeg"}, "video": {".mp4", ".mov", ".webm", ".mkv"}, "font": {".ttf", ".otf"}}
COLOR = re.compile(r"^#[0-9a-fA-F]{6}$")
NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$")


class ProjectError(Exception):
    """検証で見つかった問題の一覧を持つ。"""

    def __init__(self, problems):
        super().__init__("\n".join(p["message"] for p in problems))
        self.problems = problems


class ExportError(Exception):
    """書き出しの失敗。message は画面にそのまま出す。"""

    def __init__(self, message, hint=""):
        super().__init__(message)
        self.hint = hint


# ---------------------------------------------------------------- 素材のパス

def resolve(rel, kind=None):
    """プロジェクトの置き場所 (promo/editor/projects/) からの相対パスを実パスにする。

    リポジトリの外、絶対パス、.git の中、許していない拡張子は ValueError。
    """
    if not isinstance(rel, str) or not rel.strip():
        raise ValueError("素材のパスが空です")
    if rel.startswith(("/", "\\")) or re.match(r"^[A-Za-z]:", rel) or "\\" in rel or "\0" in rel:
        raise ValueError(f"素材は promo/editor/projects/ からの相対パスで書いてください: {rel}")
    path = pathlib.Path(os.path.normpath(PROJECTS / rel))
    real_root = os.path.realpath(ROOT)
    # 文字の上でも、シンボリックリンクをたどった先でも、リポジトリの中であること
    if (os.path.commonpath([str(ROOT), str(path)]) != str(ROOT)
            or os.path.commonpath([real_root, os.path.realpath(path)]) != real_root):
        raise ValueError(f"リポジトリの外を指しています: {rel}")
    if ".git" in path.relative_to(ROOT).parts:
        raise ValueError(f".git の中は使えません: {rel}")
    if kind and path.suffix.lower() not in EXT[kind]:
        names = {"image": "画像", "video": "動画", "font": "フォント"}
        raise ValueError(f"{names[kind]}の素材ではありません ({', '.join(sorted(EXT[kind]))} のどれか): {rel}")
    if not path.is_file():
        raise ValueError(f"素材が見つかりません: {rel} (リポジトリ内のファイルを選び直してください)")
    return path


def to_rel(path):
    return os.path.relpath(path, PROJECTS)


def list_assets():
    """画面の素材選びに出す、リポジトリ内の既存ファイル。"""
    groups = {
        "image": [ROOT / "promo/characters", ROOT / "app/branding/icons", ROOT / "promo/build/assets/badges"],
        "video": [ROOT / "promo/capture/raw"],
        "font": [ROOT / "promo/build/fonts", ROOT / "app/assets/fonts"],
    }
    result = {}
    for kind, dirs in groups.items():
        items = []
        for d in dirs:
            if not d.is_dir():
                continue
            for p in sorted(d.iterdir()):
                if p.is_file() and p.suffix.lower() in EXT[kind]:
                    item = {"src": to_rel(p), "label": str(p.relative_to(ROOT))}
                    if kind == "image":
                        try:
                            with Image.open(p) as im:
                                item["width"], item["height"] = im.size
                        except OSError:
                            continue
                    items.append(item)
        result[kind] = items
    return result


# ---------------------------------------------------------------- 動画の情報

_probe_cache = {}
_probe_lock = threading.Lock()


def probe(path):
    """動画の長さと大きさ。読めなければ ValueError。"""
    key = (str(path), path.stat().st_mtime_ns)
    with _probe_lock:
        if key in _probe_cache:
            return _probe_cache[key]
    try:
        out = subprocess.run(["ffprobe", "-v", "error", "-show_entries",
                              "format=duration:stream=codec_type,width,height", "-of", "json", str(path)],
                             capture_output=True, text=True, timeout=60)
    except FileNotFoundError:
        raise ValueError("ffprobe が見つかりません (ffmpeg を入れてください)")
    if out.returncode != 0:
        raise ValueError(f"動画を読めません: {to_rel(path)} ({out.stderr.strip()[-200:]})")
    data = json.loads(out.stdout or "{}")
    video = next((s for s in data.get("streams", []) if s.get("codec_type") == "video"), None)
    if not video:
        raise ValueError(f"動画を読めません (映像がありません): {to_rel(path)}")
    info = {"duration": float(data.get("format", {}).get("duration") or 0),
            "width": int(video["width"]), "height": int(video["height"]),
            "audio": any(s.get("codec_type") == "audio" for s in data.get("streams", []))}
    with _probe_lock:
        _probe_cache[key] = info
    return info


# ---------------------------------------------------------------- 検証

def _num(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def validate(project, check_files=True):
    """問題の一覧 [{"where", "message"}] を返す。空なら問題なし。"""
    problems = []

    def bad(where, message):
        problems.append({"where": where, "message": f"{where}: {message}" if where else message})

    if not isinstance(project, dict):
        return [{"where": "", "message": "プロジェクトの形が正しくありません (JSON のオブジェクトではありません)"}]
    if project.get("version") != 1:
        bad("プロジェクト", "version は 1 にしてください")
    name = project.get("name")
    if not isinstance(name, str) or not NAME.match(name):
        bad("プロジェクト", "名前は英数字、-、_ で 64 文字までにしてください")
    if project.get("canvas") != {"width": CANVAS[0], "height": CANVAS[1]}:
        bad("プロジェクト", "キャンバスは 1080×1920 のままにしてください")
    if "voice" in project:
        _validate_voice(bad, project["voice"])
    scenes = project.get("scenes")
    if not isinstance(scenes, list) or [s.get("id") if isinstance(s, dict) else None for s in scenes] != [s[0] for s in SCENES]:
        bad("プロジェクト", "シーンは 冒頭・パリィ・ブロック崩壊・アウトロ の 4 つをこの順に置いてください (初版では順序を変えられません)")
        return problems
    start = 0
    for scene, (sid, label, seconds) in zip(scenes, SCENES):
        where = f"シーン「{label}」"
        if scene.get("duration") != seconds:
            bad(where, f"長さは {seconds} 秒のままにしてください (初版では変えられません)")
        if scene.get("start", start) != start:
            bad(where, f"開始時刻は {start} 秒のままにしてください")
        start += seconds
        bg = scene.get("background")
        if not isinstance(bg, dict):
            bad(where, "背景 (background) がありません")
        else:
            _check_video_time(bad, f"{where}の背景", bg.get("src"), bg.get("time"), 0, check_files)
        layers = scene.get("layers")
        if not isinstance(layers, list):
            bad(where, "レイヤー (layers) がありません")
            continue
        ids = set()
        for layer in layers:
            if not isinstance(layer, dict):
                bad(where, "レイヤーの形が正しくありません")
                continue
            lw = f"{where}のレイヤー「{layer.get('name') or layer.get('id')}」"
            lid = layer.get("id")
            if not isinstance(lid, str) or not lid or len(lid) > 64:
                bad(lw, "id がありません")
            elif lid in ids:
                bad(lw, f"id「{lid}」が重複しています")
            ids.add(lid)
            _validate_layer(bad, lw, layer, seconds, check_files)
    return problems


def _check_video_time(bad, where, src, time, duration, check_files):
    if not _num(time) or time < 0:
        bad(where, "時刻は 0 以上の数にしてください")
        return None
    try:
        path = resolve(src, "video")
        if not check_files:
            return None
        info = probe(path)
    except ValueError as e:
        bad(where, str(e))
        return None
    if time + duration > info["duration"] + 0.01:
        bad(where, f"時刻 {time} 秒から {duration} 秒分が、動画の長さ {info['duration']:.1f} 秒を超えます")
    return info


def _validate_layer(bad, where, layer, seconds, check_files):
    kind = layer.get("type")
    if kind not in LAYER_TYPES:
        bad(where, f"種類「{kind}」は使えません ({', '.join(LAYER_TYPES)})")
        return
    if not isinstance(layer.get("visible", True), bool):
        bad(where, "表示は true か false にしてください")
    for key in ("x", "y"):
        if not _num(layer.get(key)) or abs(layer[key]) > 10000:
            bad(where, f"{key} は -10000〜10000 の数にしてください")
    if kind in ("image", "video", "rect"):
        for key in ("width", "height"):
            v = layer.get(key)
            if not _num(v) or v < 1 or v > 10000:
                bad(where, f"{'幅' if key == 'width' else '高さ'}は 1〜10000 の数にしてください (今: {v})")
    if kind == "text":
        if not isinstance(layer.get("text"), str) or not layer["text"].strip():
            bad(where, "文言が空です")
        elif len(layer["text"]) > 200:
            bad(where, "文言は 200 文字までにしてください")
        fs = layer.get("fontSize")
        if not _num(fs) or fs < 4 or fs > 600:
            bad(where, f"文字サイズは 4〜600 にしてください (今: {fs})")
        sw = layer.get("strokeWidth", 0)
        if not _num(sw) or sw < 0 or sw > 60:
            bad(where, "縁取りの太さは 0〜60 にしてください")
        for key in ("color", "strokeColor"):
            if not isinstance(layer.get(key), str) or not COLOR.match(layer[key]):
                bad(where, f"色は #rrggbb の形にしてください ({key})")
        if layer.get("align", "left") not in ("left", "center", "right"):
            bad(where, "行揃えは left / center / right のどれかにしてください")
        try:
            path = resolve(layer.get("font"), "font")
            if check_files:
                ImageFont.truetype(str(path), 10)
        except ValueError as e:
            bad(where, f"フォント: {e}")
        except OSError:
            bad(where, f"フォントを読めません: {layer.get('font')}")
    elif kind == "image":
        op = layer.get("opacity", 1)
        if not _num(op) or op < 0 or op > 1:
            bad(where, "透明度は 0〜1 にしてください")
        if layer.get("resample", "lanczos") not in ("lanczos", "bicubic"):
            bad(where, "resample は lanczos か bicubic にしてください")
        try:
            path = resolve(layer.get("src"), "image")
            if check_files:
                with Image.open(path) as im:
                    im.verify()
        except ValueError as e:
            bad(where, str(e))
        except OSError:
            bad(where, f"画像を読めません: {layer.get('src')}")
    elif kind == "rect":
        sw = layer.get("strokeWidth")
        if not _num(sw) or sw < 1 or sw > 200:
            bad(where, "枠の太さは 1〜200 にしてください")
        if not isinstance(layer.get("color"), str) or not COLOR.match(layer["color"]):
            bad(where, "色は #rrggbb の形にしてください")
    elif kind == "character":
        h = layer.get("height")
        if not _num(h) or h < 20 or h > 4000:
            bad(where, f"キャラクターの高さは 20〜4000 にしてください (今: {h})")
        pose = layer.get("pose")
        if not isinstance(pose, int) or isinstance(pose, bool) or pose not in range(POSES):
            bad(where, f"ポーズは 0〜{POSES - 1} にしてください")
        if not isinstance(layer.get("bob", True), bool):
            bad(where, "揺れは true か false にしてください")
        amp = layer.get("bobAmplitude", 4)
        if not _num(amp) or amp < 0 or amp > 200:
            bad(where, "揺れの振幅は 0〜200 にしてください")
        try:
            path = resolve(layer.get("src"), "image")
            if check_files:
                with Image.open(path) as im:
                    if im.size[0] < SHEET_CELL[0] * POSES or im.size[1] < SHEET_CELL[1]:
                        bad(where, f"キャラクターシートの大きさが足りません ({SHEET_CELL[0]}px × {POSES} ポーズ、高さ {SHEET_CELL[1]}px が要ります)")
        except ValueError as e:
            bad(where, str(e))
        except OSError:
            bad(where, f"画像を読めません: {layer.get('src')}")
    elif kind == "video":
        info = _check_video_time(bad, where, layer.get("src"), layer.get("start"), seconds, check_files)
        crop = layer.get("crop")
        if not isinstance(crop, dict) or not all(_num(crop.get(k)) for k in ("x", "y", "width", "height")):
            bad(where, "表示範囲 (crop) の x, y, width, height を数で書いてください")
        elif crop["x"] < 0 or crop["y"] < 0 or crop["width"] < 2 or crop["height"] < 2:
            bad(where, "表示範囲は x, y が 0 以上、幅と高さが 2 以上にしてください")
        elif info and (crop["x"] + crop["width"] > info["width"] or crop["y"] + crop["height"] > info["height"]):
            bad(where, f"表示範囲が元の動画 ({info['width']}×{info['height']}) からはみ出しています")
        if info and not info["audio"]:
            bad(where, "この動画には音声がありません (ゲームの音が要ります)")


def default_voice_lines():
    return [{"start": start, "text": text} for start, _end, text in VOICE["lines"]]


def voice_lines(project):
    """プロジェクトの台詞 ({"start", "text"} の並び)。voice がなければ既定 (v12 と同じ)。"""
    voice = project.get("voice")
    return voice["lines"] if isinstance(voice, dict) and isinstance(voice.get("lines"), list) else default_voice_lines()


def _validate_voice(bad, voice, total=None):
    """台詞の形だけを確かめる。読み上げの長さ (重なり) は VOICEVOX が要るので voice_timing で見る。"""
    total = sum(s[2] for s in SCENES) if total is None else total
    where = "音声"
    if not isinstance(voice, dict) or not isinstance(voice.get("lines"), list):
        bad(where, "voice は {\"lines\": [...]} の形にしてください")
        return
    lines = voice["lines"]
    if len(lines) > MAX_VOICE_LINES:
        bad(where, f"台詞は {MAX_VOICE_LINES} 個までにしてください")
    previous = None
    for i, line in enumerate(lines):
        w = f"台詞 {i + 1}"
        if not isinstance(line, dict):
            bad(w, "台詞の形が正しくありません")
            continue
        text, start = line.get("text"), line.get("start")
        if not isinstance(text, str) or not text.strip():
            bad(w, "台詞が空です (要らなければ、台詞ごと消してください)")
        elif len(text) > MAX_VOICE_TEXT or "\n" in text:
            bad(w, f"台詞は 1 行で {MAX_VOICE_TEXT} 文字までにしてください")
        if not _num(start) or start < 0 or start >= total:
            bad(w, f"話し始めは 0 以上 {total} 秒未満にしてください")
        elif previous is not None and start < previous:
            bad(w, "台詞は話し始めの早い順に並べてください")
        if _num(start):
            previous = start


def check(project, check_files=True):
    problems = validate(project, check_files)
    if problems:
        raise ProjectError(problems)


# ---------------------------------------------------------------- プロジェクトの読み書き

def project_path(name):
    if not isinstance(name, str) or not NAME.match(name):
        raise ValueError("プロジェクト名は英数字、-、_ で 64 文字までにしてください")
    return PROJECTS / f"{name}.json"


def load_project(name):
    path = project_path(name)
    if not path.is_file():
        raise FileNotFoundError(f"プロジェクトがありません: {path.relative_to(ROOT)}")
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def save_project(project):
    """検証してから保存する。問題があれば ProjectError で、ファイルは変えない。"""
    check(project)
    path = project_path(project["name"])
    PROJECTS.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(project, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.replace(tmp, path)
    return path


# ---------------------------------------------------------------- 描画 (プレビューと書き出しで共通)

def _font(layer):
    return ImageFont.truetype(str(resolve(layer["font"], "font")), round(layer["fontSize"]))


def _text_args(layer):
    return dict(font=_font(layer), fill=layer["color"], stroke_width=round(layer.get("strokeWidth", 0)),
                stroke_fill=layer["strokeColor"], align=layer.get("align", "left"))


def image_pixels(layer):
    """画像レイヤーの、置く大きさにした RGBA。v12 と同じく縮小は thumbnail を使う。"""
    resample = Image.Resampling.BICUBIC if layer.get("resample") == "bicubic" else Image.Resampling.LANCZOS
    size = (round(layer["width"]), round(layer["height"]))
    with Image.open(resolve(layer["src"], "image")) as original:
        source = original.convert("RGBA")
    out = source.copy()
    out.thumbnail(size, resample)
    if out.size != size:
        out = source.resize(size, resample)
    opacity = layer.get("opacity", 1)
    if opacity < 1:
        alpha = out.getchannel("A").point(lambda a: round(a * opacity))
        out.putalpha(alpha)
    return out


def character_pixels(layer):
    """v12 と同じ切り出しと縮小 (高さ h、幅 h // 2)。"""
    pose, height = layer["pose"], round(layer["height"])
    with Image.open(resolve(layer["src"], "image")) as sheet:
        sprite = sheet.convert("RGBA").crop((SHEET_CELL[0] * pose, 0, SHEET_CELL[0] * (pose + 1), SHEET_CELL[1]))
    return sprite.resize((height // 2, height), Image.Resampling.LANCZOS)


def _paste(im, pixels, x, y):
    if im.mode == "RGB":
        im.paste(pixels, (x, y), pixels)
    else:
        layer = Image.new("RGBA", im.size, (0, 0, 0, 0))
        layer.paste(pixels, (x, y))
        im.alpha_composite(layer)


def draw_static(im, layer):
    """動かないレイヤーを im (RGB の背景か、透過の RGBA) に直接描く。"""
    x, y = round(layer["x"]), round(layer["y"])
    kind = layer["type"]
    if kind == "text":
        ImageDraw.Draw(im).text((x, y), layer["text"], **_text_args(layer))
    elif kind == "rect":
        ImageDraw.Draw(im).rectangle((x, y, x + round(layer["width"]), y + round(layer["height"])),
                                     outline=layer["color"], width=round(layer["strokeWidth"]))
    elif kind == "image":
        _paste(im, image_pixels(layer), x, y)
    elif kind == "character":
        _paste(im, character_pixels(layer), x, y)
    else:
        raise ValueError(kind)


def layer_preview(layer):
    """プレビュー用に、書き出しと同じコードでレイヤーだけを透過 PNG に描く。

    返り値は (PNG のバイト列, 左上のずれ dx, dy)。画面ではレイヤーの (x + dx, y + dy) に置く。
    テキストの x, y は Pillow の xy (行の上端) のままなので、文字の実際の上端までのずれが dx, dy に入る。
    """
    kind = layer["type"]
    if kind == "text":
        args = _text_args(layer)
        probe_draw = ImageDraw.Draw(Image.new("RGBA", (1, 1)))
        left, top, right, bottom = probe_draw.textbbox((0, 0), layer["text"], font=args["font"],
                                                        stroke_width=args["stroke_width"], align=args["align"])
        im = Image.new("RGBA", (max(1, right - left), max(1, bottom - top)), (0, 0, 0, 0))
        ImageDraw.Draw(im).text((-left, -top), layer["text"], **args)
        dx, dy = left, top
    elif kind == "rect":
        w, h = round(layer["width"]), round(layer["height"])
        im = Image.new("RGBA", (w + 1, h + 1), (0, 0, 0, 0))
        ImageDraw.Draw(im).rectangle((0, 0, w, h), outline=layer["color"], width=round(layer["strokeWidth"]))
        dx = dy = 0
    elif kind == "image":
        im, dx, dy = image_pixels(layer), 0, 0
    elif kind == "character":
        im, dx, dy = character_pixels(layer), 0, 0
    else:
        raise ValueError("このレイヤーは画像にしません")
    buf = io.BytesIO()
    im.save(buf, "PNG")
    return buf.getvalue(), dx, dy


def frame_at(source, second, dest):
    _ffmpeg("-y", "-v", "error", "-ss", second, "-i", source, "-frames:v", "1", dest)


def background(frame_png):
    """v12 の base(): ゲームのフレームをぼかして暗くした背景 (RGB 1080×1920)。"""
    with Image.open(frame_png) as original:
        width = round(original.width * 1920 / original.height)
        enlarged = original.resize((width, 1920), Image.Resampling.BICUBIC)
        left = (width - 1080) // 2
        im = enlarged.crop((left, 0, left + 1080, 1920)).filter(ImageFilter.GaussianBlur(44))
    im = ImageEnhance.Brightness(im).enhance(0.52)
    return Image.blend(im, Image.new("RGB", im.size, "#29142e"), 0.32)


def background_preview(bg):
    """シーンの背景だけを JPEG で返す (プレビュー用)。"""
    src = resolve(bg["src"], "video")
    with tempfile.TemporaryDirectory() as t:
        frame = pathlib.Path(t) / "frame.png"
        frame_at(src, bg["time"], frame)
        im = background(frame)
    buf = io.BytesIO()
    im.save(buf, "JPEG", quality=90)
    return buf.getvalue()


# ---------------------------------------------------------------- 書き出し

def _ffmpeg(*args, tool="ffmpeg"):
    try:
        out = subprocess.run([tool, *[str(a) for a in args]], capture_output=True, text=True)
    except FileNotFoundError:
        raise ExportError(f"{tool} が見つかりません", "ffmpeg を入れてから、もう一度書き出してください")
    if out.returncode != 0:
        raise ExportError(f"{tool} が失敗しました: {out.stderr.strip()[-600:]}",
                          "素材の動画が壊れていないか、ディスクの空きがあるかを確かめてください")
    return out.stdout


def _engine(path, data=None, content_type=None, timeout=120):
    headers = {"Content-Type": content_type} if content_type else {}
    req = urllib.request.Request(ENGINE + path, data=data, headers=headers)
    with urllib.request.urlopen(req, timeout=timeout) as response:
        return response.read()


def voicevox_status():
    """VOICEVOX が動いていれば {"ok": True, "version"}、なければ理由と直し方。"""
    try:
        version = json.loads(_engine("/version", timeout=3))
        return {"ok": True, "version": version}
    except (urllib.error.URLError, OSError, ValueError) as e:
        return {"ok": False, "message": f"VOICEVOX ({ENGINE}) に接続できません: {getattr(e, 'reason', e)}",
                "hint": "VOICEVOX を起動して、エンジンが立ち上がってから、もう一度書き出してください"}


def next_output(name):
    """promo/build/out/{name}-eNNN.mp4 のうち、まだない番号。既存のファイルは使わない。"""
    pattern = re.compile(re.escape(name) + r"-e(\d{3,})\.mp4$")
    used = [int(m.group(1)) for p in OUT_DIR.glob(f"{name}-e*.mp4") if (m := pattern.match(p.name))]
    n = max(used, default=0) + 1
    while (OUT_DIR / f"{name}-e{n:03d}.mp4").exists():
        n += 1
    return OUT_DIR / f"{name}-e{n:03d}.mp4"


def _groups(layers):
    """見えるレイヤーを、下から順に「動かないものの塊」と「動画・キャラクター」に分ける。"""
    groups = []
    for layer in layers:
        if not layer.get("visible", True):
            continue
        if layer["type"] in ("video", "character"):
            groups.append(("dynamic", layer))
        elif groups and groups[-1][0] == "static":
            groups[-1][1].append(layer)
        else:
            groups.append(("static", [layer]))
    return groups


def _box(layer):
    """レイヤーの画面上の範囲 (left, top, right, bottom)。"""
    if layer["type"] == "text":
        args = _text_args(layer)
        l, t, r, b = ImageDraw.Draw(Image.new("RGBA", (1, 1))).textbbox(
            (layer["x"], layer["y"]), layer["text"], font=args["font"], stroke_width=args["stroke_width"], align=args["align"])
        return l, t, r, b
    if layer["type"] == "character":
        h = round(layer["height"])
        amp = layer.get("bobAmplitude", 4) if layer.get("bob", True) else 0
        return layer["x"], layer["y"] - amp, layer["x"] + h // 2, layer["y"] + h + amp
    return layer["x"], layer["y"], layer["x"] + layer["width"], layer["y"] + layer["height"]


def _scene_video(tmp, index, scene, progress):
    """1 シーンを mp4 にする。v12 の scene() と同じ ffmpeg の組み立て方。"""
    sid, seconds = scene["id"], scene["duration"]
    progress(f"シーン「{SCENES[index][1]}」の背景を描いています")
    frame = tmp / f"{sid}-frame.png"
    frame_at(resolve(scene["background"]["src"], "video"), scene["background"]["time"], frame)
    base = background(frame)
    groups = _groups(scene["layers"])
    inputs, filters, still = ["-loop", "1", "-i", tmp / f"{sid}.png"], [], base.convert("RGBA")
    current, n, audio, dynamic_boxes = "0:v", 1, None, []
    for gi, (kind, item) in enumerate(groups):
        if kind == "static" and gi == 0:
            for layer in item:
                draw_static(base, layer)
            still = base.convert("RGBA")
            continue
        if kind == "static":
            canvas = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
            for layer in item:
                draw_static(canvas, layer)
            still.alpha_composite(canvas)
            path = tmp / f"{sid}-over{gi}.png"
            canvas.save(path)
            inputs += ["-loop", "1", "-framerate", FPS, "-t", seconds, "-i", path]
            overlay = f"[{n}:v]"
            position = "0:0"
        elif item["type"] == "video":
            layer = item
            c = layer["crop"]
            inputs += ["-ss", layer["start"], "-t", seconds, "-i", resolve(layer["src"], "video")]
            filters.append(f"[{n}:v]crop={round(c['width'])}:{round(c['height'])}:{round(c['x'])}:{round(c['y'])},"
                           f"scale={round(layer['width'])}:{round(layer['height'])}:flags=neighbor[g{n}]")
            if audio is None:
                audio = f"[{n}:a]volume={GAME_VOLUME}[a]"
            overlay, position = f"[g{n}]", f"{round(layer['x'])}:{round(layer['y'])}"
            dynamic_boxes.append(_box(layer))
        else:
            layer = item
            sprite = tmp / f"{sid}-sprite{n}.png"
            character_pixels(layer).save(sprite)
            inputs += ["-loop", "1", "-framerate", FPS, "-t", seconds, "-i", sprite]
            y = round(layer["y"])
            amp = layer.get("bobAmplitude", 4)
            y_expr = f"'{y}+{amp:g}*sin(2*PI*t*{BOB_HZ})'" if layer.get("bob", True) and amp else str(y)
            overlay, position = f"[{n}:v]", f"{round(layer['x'])}:{y_expr}"
            dynamic_boxes.append(_box(layer))
        filters.append(f"[{current}]{overlay}overlay={position}:shortest=1[s{n}]")
        current, n = f"s{n}", n + 1
    base.save(tmp / f"{sid}.png")
    if current == "0:v":
        filters.append("[0:v]null[v]")
    else:
        filters[-1] = filters[-1].rsplit("[", 1)[0] + "[v]"  # 最後の重ね合わせの出力を [v] にする
    if audio is None:
        inputs += ["-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo"]
        audio_map = f"{n}:a"
    else:
        filters.append(audio)
        audio_map = "[a]"
    progress(f"シーン「{SCENES[index][1]}」を組み立てています")
    dest = tmp / f"{sid}.mp4"
    _ffmpeg("-y", "-v", "error", *inputs, "-filter_complex", ";".join(filters),
            "-map", "[v]", "-map", audio_map, "-t", seconds, "-r", FPS, "-c:v", "libx264", "-preset", "veryfast",
            "-crf", "19", "-pix_fmt", "yuv420p", "-c:a", "aac", "-ar", "48000", dest)
    return dest, still, dynamic_boxes


_voice_cache = {}
_voice_lock = threading.Lock()


def synthesize(text):
    """台詞 1 つを VOICEVOX で作る。(wav のバイト列, 秒)。同じ台詞は作り直さない。"""
    with _voice_lock:
        if text in _voice_cache:
            return _voice_cache[text]
    try:
        params = urllib.parse.urlencode({"text": text, "speaker": VOICE["speaker"]})
        query = json.loads(_engine(f"/audio_query?{params}", b""))
        query["speedScale"] = VOICE["speedScale"]
        query["intonationScale"] = VOICE["intonationScale"]
        wav = _engine(f"/synthesis?speaker={VOICE['speaker']}", json.dumps(query).encode(), "application/json")
        with wave.open(io.BytesIO(wav)) as w:
            seconds = w.getnframes() / w.getframerate()
    except (urllib.error.URLError, OSError, ValueError, wave.Error, EOFError) as e:
        raise ExportError(f"VOICEVOX で音声を作れませんでした: {getattr(e, 'reason', e)}",
                          "VOICEVOX が起動しているか、話者「春歌ナナ」(54) が使えるかを確かめてください")
    with _voice_lock:
        if len(_voice_cache) > 200:
            _voice_cache.clear()
        _voice_cache[text] = (wav, seconds)
    return wav, seconds


def voice_timing(lines, total, progress=lambda message: None):
    """台詞ごとの長さと終わりの時刻、重なりや尺からのはみ出し。VOICEVOX が要る。

    返すのは ([{"start", "text", "duration", "end"}], [問題の文])。
    """
    timed, problems = [], []
    for i, line in enumerate(lines):
        progress(f"VOICEVOX で台詞 {i + 1}/{len(lines)} を作っています")
        _wav, seconds = synthesize(line["text"])
        timed.append({"start": line["start"], "text": line["text"], "duration": seconds, "end": line["start"] + seconds})
    for i, line in enumerate(timed):
        if i + 1 < len(timed) and line["end"] > timed[i + 1]["start"]:
            over = line["end"] - timed[i + 1]["start"]
            problems.append(f"台詞 {i + 1}「{line['text']}」が、次の台詞に {over:.2f} 秒重なります "
                            f"({line['end']:.2f} 秒まで話し、次は {timed[i + 1]['start']} 秒から)")
        if line["end"] > total:
            problems.append(f"台詞 {i + 1}「{line['text']}」が、動画の終わり ({total} 秒) を "
                            f"{line['end'] - total:.2f} 秒はみ出します")
    return timed, problems


def _voices(tmp, lines, total, progress):
    timed, problems = voice_timing(lines, total, progress)
    if problems:
        raise ExportError("台詞が重なるか、尺からはみ出します: " + " / ".join(problems),
                          "台詞を短くするか、話し始めの時刻をずらしてください")
    voices = []
    for i, line in enumerate(timed):
        voice = tmp / f"voice{i}.wav"
        voice.write_bytes(synthesize(line["text"])[0])
        voices.append(voice)
    return voices


def verify(path, project, outro_still=None, outro_boxes=()):
    """書き出し後の確認: 映像と音声の尺、1080×1920、クレジット。"""
    total = sum(s["duration"] for s in project["scenes"])
    data = json.loads(_ffmpeg("-v", "error", "-show_entries", "stream=codec_type,width,height,duration",
                              "-of", "json", path, tool="ffprobe"))
    video = next((s for s in data["streams"] if s["codec_type"] == "video"), {})
    audio = next((s for s in data["streams"] if s["codec_type"] == "audio"), {})
    checks = []
    vd, ad = float(video.get("duration", 0)), float(audio.get("duration", 0)) if audio else 0
    checks.append({"name": "映像の尺", "ok": abs(vd - total) < 0.1, "detail": f"{vd:.2f} 秒 (目標 {total} 秒)"})
    checks.append({"name": "音声の尺", "ok": bool(audio) and abs(ad - total) < 0.1,
                   "detail": f"{ad:.2f} 秒" if audio else "音声がありません"})
    size = (video.get("width"), video.get("height"))
    checks.append({"name": "解像度", "ok": size == CANVAS, "detail": f"{size[0]}×{size[1]}"})
    outro = project["scenes"][-1]
    credits = [l for l in outro["layers"] if l.get("type") == "text" and CREDIT_TEXT in l.get("text", "")
               and l.get("visible", True)]
    if not credits:
        checks.append({"name": "クレジット", "ok": False,
                       "detail": f"アウトロに「{CREDIT_TEXT}」の見えるテキストがありません"})
    else:
        box = [round(v) for v in _box(credits[0])]
        inside = box[0] >= 0 and box[1] >= 0 and box[2] <= CANVAS[0] and box[3] <= CANVAS[1]
        detail = f"アウトロのレイヤー「{credits[0].get('name') or credits[0]['id']}」({box[0]}, {box[1]})"
        ok = inside
        if not inside:
            detail += " が画面の外にはみ出しています"
        elif outro_still is not None:
            covered = any(not (b[2] <= box[0] or b[0] >= box[2] or b[3] <= box[1] or b[1] >= box[3]) for b in outro_boxes)
            if covered:
                detail += "、動画かキャラクターと重なるため、画素の確認は省略"
            else:
                start = sum(s["duration"] for s in project["scenes"][:-1])
                with tempfile.TemporaryDirectory() as t:
                    frame = pathlib.Path(t) / "credit.png"
                    frame_at(path, start + outro["duration"] / 2, frame)
                    with Image.open(frame) as got:
                        got = got.convert("RGB").crop(box)
                    want = outro_still.convert("RGB").crop(box)
                diff = sum(abs(a - b) for a, b in zip(got.tobytes(), want.tobytes())) / max(1, len(got.tobytes()))
                ok = diff < 12
                detail += f"、書き出した映像の同じ場所と描画の差 {diff:.1f} (12 未満なら表示されている)"
        checks.append({"name": "クレジット", "ok": ok, "detail": detail})
    return {"duration": vd, "audioDuration": ad, "width": size[0], "height": size[1], "checks": checks}


def export(project, progress=lambda message, fraction=None: None):
    """プロジェクトから新しい動画を書き出す。既存のファイルは上書きしない。"""
    check(project)
    status = voicevox_status()
    if not status["ok"]:
        raise ExportError(status["message"], status["hint"])
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    total = sum(s["duration"] for s in project["scenes"])
    lines = voice_lines(project)
    steps = len(project["scenes"]) + len(lines) + 3
    done = [0]

    def step(message):
        progress(message, done[0] / steps)

    def advance():
        done[0] += 1

    with tempfile.TemporaryDirectory(prefix="promo-editor-") as t:
        tmp = pathlib.Path(t)
        parts = []
        outro_still, outro_boxes = None, []
        for i, scene in enumerate(project["scenes"]):
            dest, still, boxes = _scene_video(tmp, i, scene, step)
            parts.append(dest)
            outro_still, outro_boxes = still, boxes
            advance()
        step("シーンをつないでいます")
        listfile = tmp / "list.txt"
        listfile.write_text("".join(f"file '{p}'\n" for p in parts))
        joined = tmp / "joined.mp4"
        _ffmpeg("-y", "-v", "error", "-f", "concat", "-safe", "0", "-i", listfile, "-c", "copy", joined)
        advance()

        def voice_step(message):
            step(message)
            advance()
        voices = _voices(tmp, lines, total, voice_step)
        step("音声を重ねて仕上げています")
        inputs = ["-i", joined]
        filters, mix = [], ["[0:a]"]
        for i, voice in enumerate(voices):
            inputs += ["-i", voice]
            filters.append(f"[{i+1}:a]aresample=48000,volume=1.35,adelay={round(lines[i]['start']*1000)}:all=1[a{i}]")
            mix.append(f"[a{i}]")
        if voices:
            filters.append("".join(mix) + f"amix=inputs={len(mix)}:duration=first:normalize=0,alimiter=limit=0.95[aout]")
        else:
            filters.append("[0:a]alimiter=limit=0.95[aout]")
        final = tmp / "final.mp4"
        _ffmpeg("-n", "-v", "error", *inputs, "-filter_complex", ";".join(filters),
                "-map", "0:v", "-map", "[aout]", "-c:v", "copy", "-c:a", "aac", "-b:a", "192k",
                "-t", total, "-movflags", "+faststart", final)
        advance()
        step("書き出し先へ置いています")
        out = _place(final, project["name"])
        advance()
        step("書き出した動画を確かめています")
        result = verify(out, project, outro_still, outro_boxes)
    result["path"] = str(out.relative_to(ROOT)) if out.is_relative_to(ROOT) else str(out)
    progress("書き出しました", 1.0)
    return result


def _place(final, name):
    """出来た動画を promo/build/out/ の新しい名前に置く。既にある名前には絶対に置かない。"""
    for _ in range(1000):
        out = next_output(name)
        partial = out.with_name(f".{out.stem}.partial-{os.getpid()}-{threading.get_ident()}.mp4")
        try:
            shutil.copyfile(final, partial)
            try:
                os.link(partial, out)  # 既にあれば FileExistsError。上書きはしない
            except FileExistsError:
                continue
            return out
        finally:
            if partial.exists():
                partial.unlink()
    raise ExportError("書き出し先の名前を決められませんでした", "promo/build/out/ を確かめてください")


def main():
    if len(sys.argv) != 2:
        raise SystemExit("使い方: python3 promo/editor/render.py promo/editor/projects/<名前>.json")
    with open(sys.argv[1], encoding="utf-8") as f:
        project = json.load(f)
    try:
        result = export(project, lambda m, f=None: print(f"[{'--' if f is None else f'{f*100:3.0f}%'}] {m}", flush=True))
    except ProjectError as e:
        raise SystemExit("プロジェクトに問題があります:\n" + "\n".join(p["message"] for p in e.problems))
    except ExportError as e:
        raise SystemExit(f"書き出しに失敗しました: {e}\n{e.hint}")
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
