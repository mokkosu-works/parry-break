#!/usr/bin/env python3
"""通常尺用のバストアップの表情を、Codex のシートから作る。

シートは 4 列 × 2 段で、上の段が口を閉じた顔、下の段が同じ表情で口を開けた顔。
画像生成では上下の絵 (髪の毛先・手・服) を完全には揃えられず、そのまま口パクに使うとちらつく。
そこで口を閉じた絵を土台にし、口を開けた顔は「土台 + 開いた絵の口のまわりだけ」で作る。
目パチ (まばたき) も同じく、目のまわりだけを貼る。

使い方:
    python3 promo/longform/bust.py akane

入力: promo/characters/bust/<名前>_bust_sheet{1,2,3}.png、<名前>_bust_blink.png
出力: promo/characters/bust/<名前>/<表情>_{closed,open}.png と normal_blink.png
      (どれも同じ大きさのキャンバスに、同じ位置で置く)
"""

import sys
from collections import deque
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
BUST = ROOT / "promo/characters/bust"

# シートの並び (左上から。各シート 4 表情)
NAMES = [["normal", "explain", "focus", "surprise"],
         ["frustrated", "success", "smug", "think"],
         ["shy", "steam", "shock", "fired"]]

# 口の位置を手で決める表情 (自動では口を見つけられないもの)。(名前, 表情): コマの中の (左, 上, 右, 下)。
# ミツバの think は、下の段 (口を開けた絵) の頭の傾きが違い、目のずれを口と取り違えた。口も探す範囲の外にある。
MOUTH_FORCE = {
    ("mitsuba", "think"): (262, 288, 306, 322),
    # focus は顔の位置がほかの表情と違い、ほかの表情から借りた位置では目まで入った。
    ("mitsuba", "focus"): (204, 272, 264, 310),
}

# 顔の中で、口と目を探す範囲 (コマの幅・高さに対する割合)
MOUTH_ZONE = (0.30, 0.45, 0.70, 0.75)
EYE_ZONE = (0.22, 0.30, 0.78, 0.60)


def largest_blob(im):
    """一番大きなまとまり以外 (背景に散ったゴミ) を透明にする。"""
    alpha = im.getchannel("A")
    w, h = im.size
    px = alpha.load()
    seen = bytearray(w * h)
    best = []
    for y in range(h):
        for x in range(w):
            if px[x, y] > 40 and not seen[y * w + x]:
                comp, q = [], deque([(x, y)])
                seen[y * w + x] = 1
                while q:
                    cx, cy = q.popleft()
                    comp.append((cx, cy))
                    for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                        if 0 <= nx < w and 0 <= ny < h and not seen[ny * w + nx] and px[nx, ny] > 40:
                            seen[ny * w + nx] = 1
                            q.append((nx, ny))
                if len(comp) > len(best):
                    best = comp
    keep = Image.new("L", im.size, 0)
    kp = keep.load()
    for x, y in best:
        kp[x, y] = 255
    keep = keep.filter(ImageFilter.MaxFilter(5))  # 縁の半透明は残す
    out = im.copy()
    out.putalpha(ImageChops.multiply(alpha, keep))
    return out


def blobs(im, min_px=20000):
    """シートの中のまとまり (キャラ 1 体ずつ) を、左から順に返す。小さなゴミは捨てる。"""
    small = im.getchannel("A").resize((im.width // 4, im.height // 4)).point(lambda v: 255 if v > 40 else 0)
    w, h = small.size
    px = small.load()
    seen = bytearray(w * h)
    found = []
    for y in range(h):
        for x in range(w):
            if px[x, y] and not seen[y * w + x]:
                xs, ys, n, q = [x, x], [y, y], 0, deque([(x, y)])
                seen[y * w + x] = 1
                while q:
                    cx, cy = q.popleft()
                    n += 1
                    xs = [min(xs[0], cx), max(xs[1], cx)]
                    ys = [min(ys[0], cy), max(ys[1], cy)]
                    for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                        if 0 <= nx < w and 0 <= ny < h and not seen[ny * w + nx] and px[nx, ny]:
                            seen[ny * w + nx] = 1
                            q.append((nx, ny))
                if n * 16 >= min_px:
                    found.append((xs[0] * 4, ys[0] * 4, xs[1] * 4 + 4, ys[1] * 4 + 4))
    return sorted(found)


def cells(sheet, cols=4, rows=2, margin=12):
    """シートからキャラを 1 体ずつ切り出す。上下の段で同じ大きさの枠にそろえる。"""
    im = Image.open(sheet).convert("RGBA")
    half = im.height // rows
    grid = []
    for r in range(rows):
        row = im.crop((0, r * half, im.width, (r + 1) * half))
        boxes = blobs(row)
        if len(boxes) != cols:
            raise SystemExit(f"{sheet.name}: {r + 1} 段目のキャラが {len(boxes)} 体に見えます ({cols} 体のはず)")
        grid.append([largest_blob(row.crop((max(0, b[0] - margin), max(0, b[1] - margin),
                                            min(row.width, b[2] + margin), min(row.height, b[3] + margin))))
                     for b in boxes])
    size = (max(c.width for row in grid for c in row), max(c.height for row in grid for c in row))
    def canvas(c):  # 透明を除いた範囲の左上を、そろえた枠の左上に置く
        bb = c.getchannel("A").getbbox()
        out = Image.new("RGBA", size, (0, 0, 0, 0))
        out.paste(c.crop(bb), (margin, margin))
        return out
    return [[canvas(c) for c in row] for row in grid]


def zone(size, z):
    w, h = size
    return (int(w * z[0]), int(h * z[1]), int(w * z[2]), int(h * z[3]))


def flat(im):
    """位置合わせ用の灰色 (透明は白)。"""
    bg = Image.new("RGBA", im.size, (255, 255, 255, 255))
    return Image.alpha_composite(bg, im).convert("L")


def align(base, other, box, reach=36):
    """box の中で other を少しずつずらし、base と最もよく重なるずれ (dx, dy) を返す。"""
    b = flat(base).crop(box)
    o = flat(other)
    best = None
    for dy in range(-reach, reach + 1, 3):
        for dx in range(-reach, reach + 1, 3):
            s = sum(ImageChops.difference(b, o.crop((box[0] - dx, box[1] - dy, box[2] - dx, box[3] - dy))).get_flattened_data())
            if best is None or s < best[0]:
                best = (s, dx, dy)
    _, bx, by = best
    for dy in range(by - 2, by + 3):  # 1 ピクセル単位で詰める
        for dx in range(bx - 2, bx + 3):
            s = sum(ImageChops.difference(b, o.crop((box[0] - dx, box[1] - dy, box[2] - dx, box[3] - dy))).get_flattened_data())
            if s < best[0]:
                best = (s, dx, dy)
    return best[1], best[2]


def shifted(im, dx, dy):
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    out.paste(im, (dx, dy))
    return out


def grow(raw, found, size, reach=(30, 8), level=25, steps=40):
    """found から、削らない違い(raw > level)をたどって、つながっている所まで範囲を広げる。
    広げるのは found のまわり (左右 reach[0]・上下 reach[1]) の窓の中だけ。"""
    l, t, r, b = found
    window = (max(0, l - reach[0]), max(0, t - reach[1]), min(size[0], r + reach[0]), min(size[1], b + reach[1]))
    loose = raw.point(lambda v: 255 if v > level else 0).filter(ImageFilter.MedianFilter(3))
    limit = Image.new("L", size, 0)
    ImageDraw.Draw(limit).rectangle(window, fill=255)
    loose = ImageChops.multiply(loose, limit)
    region = Image.new("L", size, 0)
    ImageDraw.Draw(region).rectangle(found, fill=255)
    for _ in range(steps):
        grown = ImageChops.lighter(region, ImageChops.multiply(region.filter(ImageFilter.MaxFilter(3)), loose))
        if grown.getbbox() == region.getbbox() and ImageChops.difference(grown, region).getbbox() is None:
            break
        region = grown
    return region.getbbox()


def leftover(base, moved, area, level=40, strip=12):
    """貼った範囲のすぐ外 (左右 strip px、口の高さ) に、まだ閉じた絵と開いた絵の違いが残っている画素の数。
    moved は patch() で位置を合わせた開いた絵。"""
    box = (0, 0) + base.size
    diff = ImageChops.difference(flat(base), flat(moved))
    diff = diff.point(lambda v: 255 if v > level else 0).filter(ImageFilter.MedianFilter(3))
    l, t, r, b = area
    counts = []
    for side in ((max(box[0], l - strip), t + 6, l, b - 6), (r, t + 6, min(box[2], r + strip), b - 6)):
        if side[2] <= side[0] or side[3] <= side[1]:
            counts.append(0)
            continue
        counts.append(sum(1 for v in diff.crop(side).get_flattened_data() if v))
    return counts


def mouth_sheet(rows, dest):
    """確認画像: 表情ごとに、口のまわりを拡大した「閉じた・開いた」を並べ、貼った範囲を赤い枠で示す。"""
    from PIL import ImageFont
    cell_w, cell_h, zoom, margin = 300, 260, 3, 40
    cols = 3
    sheet = Image.new("RGB", (cols * (cell_w * 2 + 20), ((len(rows) + cols - 1) // cols) * (cell_h + 40)), "white")
    font = ImageFont.truetype(str(ROOT / "promo/build/fonts/NotoSansCJK-Bold.ttc"), 22)
    for i, (expr, closed, opened, area) in enumerate(rows):
        x0, y0 = (i % cols) * (cell_w * 2 + 20), (i // cols) * (cell_h + 40)
        ImageDraw.Draw(sheet).text((x0 + 8, y0 + 6), expr, font=font, fill="black")
        if not area:
            continue
        cx, cy = (area[0] + area[2]) // 2, (area[1] + area[3]) // 2
        crop = (cx - cell_w // (2 * zoom) - margin // zoom, cy - cell_h // (2 * zoom),
                cx + cell_w // (2 * zoom) + margin // zoom, cy + cell_h // (2 * zoom))
        for j, im in enumerate((closed, opened)):
            bg = Image.new("RGBA", im.size, "white")
            part = Image.alpha_composite(bg, im).crop(crop).convert("RGB")
            part = part.resize((cell_w, cell_h), Image.Resampling.NEAREST)
            d = ImageDraw.Draw(part)
            sx, sy = cell_w / (crop[2] - crop[0]), cell_h / (crop[3] - crop[1])
            d.rectangle(((area[0] - crop[0]) * sx, (area[1] - crop[1]) * sy,
                         (area[2] - crop[0]) * sx, (area[3] - crop[1]) * sy), outline="red", width=2)
            sheet.paste(part, (x0 + j * (cell_w + 10), y0 + 36))
    sheet.save(dest)


def patch(base, other, z, pad=14, feather=6, max_size=None, force=None):
    """other の、base と違う所 (z の範囲の中だけ) を、位置を合わせて base に貼る。"""
    box = zone(base.size, z)
    face = zone(base.size, (0.2, 0.25, 0.8, 0.8))
    if force:
        # 口の位置が決まっているときは、口のまわりだけで位置を合わせ、口のまわりだけを見る
        # (頭の傾きが違う絵でも、口が合うように)。
        fl, ft, fr, fb = force
        face = (max(40, fl - 40), max(40, ft - 40), min(base.width - 40, fr + 40), min(base.height - 40, fb + 40))
        box = (max(0, fl - 20), max(0, ft - 10), min(base.width, fr + 20), min(base.height, fb + 10))
    dx, dy = align(base, other, face)
    moved = shifted(other, dx, dy)
    limit = Image.new("L", base.size, 0)
    ImageDraw.Draw(limit).rectangle(box, fill=255)
    raw = ImageChops.multiply(ImageChops.difference(flat(base), flat(moved)), limit)
    found = None
    # 細い線のずれ (髪の毛先など) は捨て、まとまった違い (口・目) だけを残す。小さな口は弱めの条件で拾う
    for level, erode in ((60, 5), (40, 3)):
        diff = raw.point(lambda v, lv=level: 255 if v > lv else 0)
        diff = diff.filter(ImageFilter.MinFilter(erode)).filter(ImageFilter.MaxFilter(9))
        found = diff.getbbox()
        if found:
            break
    if force:
        # 枠の中の、まとまった違い (口) だけに絞る。輪郭や髪の細い線は削って捨てる。見つからなければ枠のまま。
        solid = raw.point(lambda v: 255 if v > 40 else 0).filter(ImageFilter.MinFilter(3)).filter(ImageFilter.MaxFilter(5))
        inside = solid.crop(force).getbbox()
        found = (force[0] + inside[0], force[1] + inside[1], force[0] + inside[2], force[1] + inside[3]) if inside else force
    if not found:
        return base.copy(), None
    l, t, r, b = found
    if max_size and (r - l > max_size[0] or b - t > max_size[1]):
        return None, (l, t, r, b)  # 口以外の線のずれも拾った。呼び出し側で、同じシートの口の位置から決め直す
    # 上で違いを削ったときに、口の細い端(閉じた口の線の端・開いた口の角)も削られる。
    # 削らない違いのうち、見つけた範囲からつながっている所まで広げて、口の端まで貼る(2026-11-17)。
    # 位置を決めた表情は、口のまわりに輪郭などの線が近いので、広げる幅を小さくする。
    l, t, r, b = grow(raw, found, base.size, reach=(16, 4) if force else (30, 8))
    area = (max(0, l - pad), max(0, t - pad), min(base.width, r + pad), min(base.height, b + pad))
    mask = Image.new("L", base.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(area, radius=pad, fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(feather))
    out = base.copy()
    out.paste(moved, (0, 0), ImageChops.multiply(mask, moved.getchannel("A")))
    patch.moved = moved  # 確かめ (leftover) で、同じ位置合わせを使うため
    return out, area


def main(name):
    out_dir = BUST / name
    out_dir.mkdir(exist_ok=True)
    report, warnings, check_rows = [], [], []
    for i, row_names in enumerate(NAMES):
        grid = cells(BUST / f"{name}_bust_sheet{i + 1}.png")
        results, retry = {}, []
        for c, expr in enumerate(row_names):
            if (name, expr) in MOUTH_FORCE:
                mouth, area = patch(grid[0][c], grid[1][c], MOUTH_ZONE, force=MOUTH_FORCE[name, expr])
            else:
                mouth, area = patch(grid[0][c], grid[1][c], MOUTH_ZONE, max_size=(90, 70))
            if mouth is None:
                retry.append(c)
            else:
                results[c] = (mouth, area, getattr(patch, "moved", None))
        auto = {c: r for c, r in results.items() if (name, row_names[c]) not in MOUTH_FORCE}
        for c in retry:  # 同じシートのほかの表情の口の中心に、口の大きさの枠を置き直す
            centers = sorted(((a[0] + a[2]) // 2, (a[1] + a[3]) // 2) for _, a, _ in auto.values() if a)
            cx, cy = centers[len(centers) // 2]
            force = (cx - 35, cy - 25, cx + 35, cy + 25)
            mouth, area = patch(grid[0][c], grid[1][c], MOUTH_ZONE, force=force)
            results[c] = (mouth, area, patch.moved)
        for c, expr in enumerate(row_names):
            closed = grid[0][c]
            mouth, area, moved = results[c]
            closed.save(out_dir / f"{expr}_closed.png")
            mouth.save(out_dir / f"{expr}_open.png")
            how = " (位置をほかの表情から決めた)" if c in retry else " (位置を手で決めた)" if (name, expr) in MOUTH_FORCE else ""
            report.append(f"{expr}: 口の範囲 {area}{how}")
            check_rows.append((expr, closed, mouth, area))
            if area:
                left, right = leftover(closed, moved, area)
                if left > 20 or right > 20:
                    warnings.append(f"{expr}: 貼った範囲のすぐ外に違いが残っています (左 {left}・右 {right} 画素)。確認画像で見てください")
            if expr == "normal":
                blink_src = largest_blob(Image.open(BUST / f"{name}_bust_blink.png").convert("RGBA"))
                blink_src = fit_to(blink_src, closed)
                blink, area = patch(closed, blink_src, EYE_ZONE, pad=10)
                blink.save(out_dir / "normal_blink.png")
                report.append(f"normal: 目の範囲 {area}")
    print("\n".join(report))
    check = ROOT / f"promo/design/checks/{name}-bust-mouth-v02.png"
    mouth_sheet(check_rows, check)
    print(f"確認画像: {check.relative_to(ROOT)}")
    print("\n".join(warnings) if warnings else "範囲の外に違いが残る表情はありません")


def fit_to(src, base):
    """別に作った絵 (目パチ) を、base と同じ大きさ・位置になるように縮めて置く。"""
    sb, bb = src.getchannel("A").getbbox(), base.getchannel("A").getbbox()
    piece = src.crop(sb)
    scale = (bb[2] - bb[0]) / piece.width
    piece = piece.resize((round(piece.width * scale), round(piece.height * scale)), Image.LANCZOS)
    out = Image.new("RGBA", base.size, (0, 0, 0, 0))
    out.paste(piece, (bb[0], bb[1]))
    return out


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    main(sys.argv[1])
