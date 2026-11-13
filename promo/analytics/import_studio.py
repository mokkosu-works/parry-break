#!/usr/bin/env python3
"""YouTube Studio の CSV (zip) から、promo/records/videos.csv の「再生数」を埋め、集計を promo/analytics/summary.md に書く。

  python3 promo/analytics/import_studio.py promo/analytics/exports/<書き出した zip>   # 予行 (何も書かない)
  python3 promo/analytics/import_studio.py promo/analytics/exports/<書き出した zip> --write

- zip の「表データ.csv」だけを使う。動画は、タイトルと公開日 (videos.csv の「投稿日」) で ID に結びつける。
- 公開日がない行 (予約中) は飛ばす。
- 「視聴を継続 (%)」の列があれば (指標を増やして書き出したとき)、それを「視聴率(視聴 vs スワイプ)」に書く。
  この数字は、見た人 (ユニークリーチ) が少ないうちはぶれる。ユニークリーチが 100 未満の動画は、集計では「データ不足」として除く。
- 再生数は上書きする (書き出した時点の値)。書き出した期間の終わりも summary.md に残す。
"""
import csv, datetime, io, pathlib, re, statistics, sys, zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
VIDEOS = ROOT / "promo/records/videos.csv"
SUMMARY = ROOT / "promo/analytics/summary.md"
PATTERN = {"fever-s47-r2": "FEVER (s47)", "just-s47-r2": "ジャスト (s47)", "just-s27-r2": "ジャスト落ち (s27)", "just-s33-r2": "崩れ落ち (s33)"}
HOOK = {"A": "A 惜しい失敗", "B": "B 見栄え", "C": "C 結果"}


def read_studio(zpath):
    with zipfile.ZipFile(zpath) as z:
        name = next((n for n in z.namelist() if n.endswith("表データ.csv")), None)
        if not name:
            sys.exit("zip に「表データ.csv」がない")
        text = z.read(name).decode("utf-8-sig")
    out = {}
    for r in csv.DictReader(io.StringIO(text)):
        if r["コンテンツ"] == "合計" or not r["動画公開時刻"].strip():
            continue
        d = datetime.datetime.strptime(r["動画公開時刻"].strip(), "%b %d, %Y").date().isoformat()
        out[(r["動画のタイトル"].strip(), d)] = r
    m = re.search(r"(\d{4}-\d{2}-\d{2})_(\d{4}-\d{2}-\d{2})", str(zpath))
    return out, (m.group(2) if m else "?")


def reach(r):
    try:
        return int(r["_s"].get("ユニークリーチ") or 0)
    except ValueError:
        return 0


def reliable(r):
    return reach(r) >= 100 and (r["_s"].get("視聴を継続 (%)") or "").strip() != ""


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if not args:
        sys.exit(__doc__)
    studio, upto = read_studio(args[0])
    with VIDEOS.open(encoding="utf-8-sig", newline="") as f:
        rd = csv.DictReader(f)
        cols, rows = rd.fieldnames, list(rd)
    hit, miss = [], []
    for r in rows:
        s = studio.get((r["タイトル"], r["投稿日"]))
        if s:
            r["再生数"] = s["視聴回数"]
            if (s.get("視聴を継続 (%)") or "").strip():
                r["視聴率(視聴 vs スワイプ)"] = s["視聴を継続 (%)"]
            r["_s"] = s
            hit.append(r)
        elif r["投稿日"] and r["投稿日"] <= upto:
            miss.append(r["id"])
    used = {(r["タイトル"], r["投稿日"]) for r in hit}
    unknown = [k for k in studio if k not in used]
    print(f"結びついた: {len(hit)} 本 / 公開済みなのに Studio にない: {miss or 'なし'} / videos.csv にない: {unknown or 'なし'}")

    today = datetime.date.fromisoformat(upto) if upto != "?" else datetime.date.today()
    lines = ["# アナリティクスのまとめ", "",
             f"YouTube Studio の書き出し (〜{upto}) から `import_studio.py` が作る。再生数は書き出した時点の値。",
             "「視聴を継続 %」は Studio の「視聴 vs スワイプ」にあたる数字 (指標を増やして書き出すと入る)。", "",
             "## 1 本ずつ", "", "| ID | 公開日 | パターン | 冒頭 | 再生数 | 視聴を継続 % | 平均視聴割合 % | ユニークリーチ | 経過日数 |", "| --- | --- | --- | --- | --- | --- | --- | --- | --- |"]
    hit.sort(key=lambda r: r["投稿日"])
    for r in hit:
        days = (today - datetime.date.fromisoformat(r["投稿日"])).days
        st = r["_s"]
        lines.append(f"| {r['id']} | {r['投稿日']} | {PATTERN.get(r['パターン名'], r['パターン名'])} | {HOOK[r['冒頭の種類']]} | {r['再生数']} | {st.get('視聴を継続 (%)') or '-'}{'' if reliable(r) else ' (不足)'} | {st.get('平均視聴割合 (%)') or '-'} | {st.get('ユニークリーチ') or '-'} | {days} |")

    def group(key, label):
        g = {}
        for r in hit:
            g.setdefault(key(r), []).append(int(r["再生数"]))
        stay = {}
        for r in hit:
            if reliable(r):
                stay.setdefault(key(r), []).append(float(r["_s"]["視聴を継続 (%)"]))
        out = ["", f"## {label}ごと", "", f"| {label} | 本数 | 再生数の合計 | 再生数の中央値 | 視聴を継続 % の平均 (データ十分な動画) |", "| --- | --- | --- | --- | --- |"]
        for k, v in sorted(g.items(), key=lambda kv: -sum(kv[1])):
            sv = stay.get(k)
            out.append(f"| {k} | {len(v)} | {sum(v)} | {statistics.median(v):g} | {f'{statistics.mean(sv):.1f} ({len(sv)} 本)' if sv else 'データ不足'} |")
        return out
    lines += group(lambda r: PATTERN.get(r["パターン名"], r["パターン名"]), "パターン")
    lines += group(lambda r: HOOK[r["冒頭の種類"]], "冒頭")
    lines += ["", "## 読むときの注意", "",
              f"- 公開から {min((today - datetime.date.fromisoformat(r['投稿日'])).days for r in hit)} 日〜{max((today - datetime.date.fromisoformat(r['投稿日'])).days for r in hit)} 日の動画が混ざる。ショートは公開日に再生が集まりやすいので、経過日数が違う動画を並べて比べすぎない。",
              "- 「視聴を継続 %」は、ユニークリーチが 100 未満の動画では当てにならないので、除いた。公開から日が浅い動画は、Studio の数字が後から増える。",
              "- 本数が 5〜10 本たまるまでは参考値。パターンと冒頭と公開日の順番が重なっていて、どれが効いたかは分けられない。"]
    if "--write" not in sys.argv:
        print("\n".join(lines))
        print("\n(予行: --write を付けると videos.csv と summary.md に書く)")
        return
    with VIDEOS.open("w", encoding="utf-8-sig", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols, extrasaction="ignore")
        w.writeheader()
        w.writerows(rows)
    SUMMARY.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("書いた:", VIDEOS.relative_to(ROOT), SUMMARY.relative_to(ROOT))


main()
