"""シートの等幅境界をまたぐ髪・手を保持して、6人分の輪郭を分離する。"""
import functools
import re
from PIL import Image, ImageDraw, ImageFilter


def components(image, threshold=32):
    width, height = image.size
    alpha = image.getchannel('A').point(lambda a: 255 if a >= threshold else 0).tobytes()
    parents, runs, previous = [], [], []

    def root(i):
        while parents[i] != i:
            parents[i] = parents[parents[i]]
            i = parents[i]
        return i

    for y in range(height):
        row, j = [], 0
        for match in re.finditer(b'\xff+', alpha[y * width:(y + 1) * width]):
            left, right = match.span()
            idx = len(parents)
            parents.append(idx)
            runs.append((y, left, right))
            row.append(idx)
            while j < len(previous) and runs[previous[j]][2] < left:
                j += 1
            k = j
            while k < len(previous) and runs[previous[k]][1] <= right:
                parents[root(idx)] = root(previous[k])
                k += 1
        previous = row
    groups = {}
    for i, run in enumerate(runs):
        groups.setdefault(root(i), []).append(run)
    result = []
    for rs in groups.values():
        box = (min(a for y, a, b in rs), min(y for y, a, b in rs),
               max(b for y, a, b in rs), max(y for y, a, b in rs) + 1)
        result.append((sum(b - a for y, a, b in rs), box, rs))
    return sorted(result, key=lambda c: c[0], reverse=True)


@functools.lru_cache(maxsize=12)
def isolate_sheet(path, modified_ns):
    with Image.open(path) as source:
        sheet = source.convert('RGBA')
    parts = components(sheet)
    bodies = sorted(parts[:6], key=lambda c: c[1][0] + c[1][2])
    if len(bodies) != 6 or min(c[0] for c in bodies) < 10000:
        raise ValueError('6つの独立した立ち絵を検出できません。素材を確認してください')
    assigned = [[body] for body in bodies]
    centers = [(b[1][0] + b[1][2]) / 2 for b in bodies]
    # 汗・感嘆符など本体から離れた表情マークも対応する人物に帰属させる。
    for part in parts[6:]:
        if part[0] < 20:
            continue
        center = (part[1][0] + part[1][2]) / 2
        i = min(range(6), key=lambda n: abs(centers[n] - center))
        if abs(centers[i] - center) < sheet.width / 6 * .7:
            assigned[i].append(part)
    sprites = []
    for parts_for_pose in assigned:
        mask = Image.new('L', sheet.size)
        draw = ImageDraw.Draw(mask)
        for area, box, rs in parts_for_pose:
            for y, left, right in rs:
                draw.line((left, y, right - 1, y), fill=255)
        # 元の半透明の輪郭を1px分残す。別の人物の本体はマスクに入れない。
        mask = mask.filter(ImageFilter.MaxFilter(3))
        isolated = Image.new('RGBA', sheet.size)
        isolated.paste(sheet, (0, 0), mask)
        sprites.append(isolated.crop(isolated.getbbox()))
    scale = min(346 / max(s.width for s in sprites), 700 / max(s.height for s in sprites))
    normalized = []
    for sprite in sprites:
        sprite = sprite.resize((round(sprite.width * scale), round(sprite.height * scale)), Image.Resampling.LANCZOS)
        cell = Image.new('RGBA', (362, 724))
        cell.alpha_composite(sprite, ((362 - sprite.width) // 2, 712 - sprite.height))
        normalized.append(cell)
    return tuple(normalized)
