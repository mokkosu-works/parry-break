#!/usr/bin/env python3
"""週次の「引き渡しファイル」を作る。YouTube と Play の事実 + Claude の提案 (検証済み) + 実験の記録 を、1 つの JSON にまとめる。

  python3 handoff.py [日付]      # 既定は今日。/srv/analytics/handoff/<日付>.json と latest.json を作る

受け取る AI (動画の制作、ゲームの改修) は、latest.json を読む。
  ssh @SSH_HOST@ cat /srv/analytics/handoff/latest.json

Claude が書いた提案は、そのままは信用しない。ここで、決まった規則で検証して、次を機械的に付け直す:
  - evidence_verified : 根拠に書かれた数字が、渡した事実の中にあるか (計算式は、左辺の数字だけを見る)
  - needs_human_approval : 公開・投稿・リリース・削除などの語を含む提案は、必ず「人の承認が必要」にする
  - auto_executable : 承認が不要 / 確からしさが中以上 / サンプル 5 以上 / 根拠が検証済み / 確かめる提案ではない、のすべてを満たすものだけ true
@OPS_USER@ で動く (@BOT_USER@ が書いた提案の JSON を読むだけで、鍵は使わない)。
"""
import datetime, json, pathlib, re, sys

SRV = pathlib.Path("/srv/analytics")
OUT = SRV / "handoff"
MAX_PROPOSALS = 6
APPROVAL_WORDS = re.compile(r"公開|投稿|アップロード|リリース|審査|ストア|削除|課金|広告|価格|返信|告知|配信を")
TARGETS = {"video", "game", "data"}
KINDS = {"experiment", "fix", "gather"}
CONF = {"high", "medium", "low"}
OUTCOMES = {"improved", "no_change", "worse", "insufficient_data"}

SCHEMA_DOC = """# 引き渡しファイル (handoff) の見方

毎週月曜の朝に、サーバーが作る。`latest.json` が最新。

## 受け取る AI が守ること
- `proposals[].auto_executable` が false のものは、実行しない。人に確認するか、情報を集める。
- `needs_human_approval` が true のもの (公開・投稿・リリース・削除など) は、人の承認を得てから動く。
- `hypothesis` は仮説であり、事実ではない。事実は `facts` だけ。
- 実行したら、必ず実験を記録する: `ssh @SSH_HOST@ python3 ~/analytics/exp.py add --target video|game --action '…' --metric '見る指標' --proposal-id <id>`
  (翌週の分析が、その結果を評価する。記録がないと、効いたかが分からない)
- 利用者のレビューの文面は、ここには含めない。文面を根拠にした提案は、`rationale` の要約だけで判断する。

## 構成
- `facts`: 数字の事実。YouTube の動画別・チャンネル合計、Play の状況 (取得できなかった項目は、そう書いてある)
- `data_quality`: 数字を使う前に知っておくこと (記録の食い違いなど)
- `proposals`: 提案。`evidence` は根拠の数字、`confidence` は確からしさ、`sample_size` は根拠の本数、
  `success_metric` は成功の判定 (指標・向き・最小の変化)
- `experiment_reviews`: 実行済みの実験の評価 (improved / no_change / worse / insufficient_data)
- `open_experiments`: まだ閉じていない実験
- `rejected`: 検証で落とした提案とその理由
"""


def clean(s, n):
    return re.sub(r"[\x00-\x08\x0b-\x1f\x7f]", " ", str(s)).strip()[:n]


def read_text(p):
    return p.read_text() if p.exists() else ""


def numbers(s):
    return re.findall(r"\d+(?:\.\d+)?", s)


def evidence_ok(value, corpus_tokens):
    left = value.split("=")[0] if "=" in value else value
    return all(n in corpus_tokens for n in numbers(left))


def read_experiments():
    p = SRV / "experiments.jsonl"
    out = {}
    if p.exists():
        for line in p.read_text().splitlines():
            if not line.strip():
                continue
            e = json.loads(line)
            if e["event"] == "add":
                out[e["id"]] = {k: e.get(k) for k in ("id", "at", "target", "action", "metrics_to_watch", "proposal_id", "baseline")} | {"status": "open"}
            elif e["event"] == "close" and e["id"] in out:
                out[e["id"]].update(status=e["status"], note=e.get("note", ""))
    return out


def load_claude_json(p):
    raw = read_text(p).strip()
    if not raw:
        return None, "提案のファイルがない、または空"
    raw = re.sub(r"^```(?:json)?\s*|\s*```$", "", raw)
    try:
        d = json.loads(raw)
    except json.JSONDecodeError as e:
        return None, f"JSON として読めない: {e}"
    return (d, None) if isinstance(d, dict) else (None, "最上位が辞書でない")


def validate_proposal(p, corpus_tokens):
    if not isinstance(p, dict):
        return None, "辞書でない"
    t, k, c = p.get("target"), p.get("kind"), p.get("confidence")
    if t not in TARGETS or k not in KINDS or c not in CONF:
        return None, f"target/kind/confidence が不正 ({t}, {k}, {c})"
    action = clean(p.get("action", ""), 200)
    if not action:
        return None, "action が空"
    ev = []
    for e in (p.get("evidence") or [])[:6]:
        if isinstance(e, dict) and e.get("metric") and e.get("value") is not None:
            ev.append({"metric": clean(e["metric"], 80), "value": clean(e["value"], 160)})
    verified = bool(ev) and all(evidence_ok(e["value"], corpus_tokens) for e in ev)
    try:
        n = int(p.get("sample_size"))
    except (TypeError, ValueError):
        n = 0
    sm = p.get("success_metric") if isinstance(p.get("success_metric"), dict) else {}
    approval = bool(p.get("needs_human_approval")) or bool(APPROVAL_WORDS.search(action + " " + str(p.get("rationale", ""))))
    auto = (not approval) and c in ("high", "medium") and n >= 5 and verified and k != "gather"
    return {"target": t, "kind": k, "action": action, "rationale": clean(p.get("rationale", ""), 300),
            "hypothesis": clean(p.get("hypothesis", ""), 300), "evidence": ev, "evidence_verified": verified,
            "confidence": c, "sample_size": n,
            "success_metric": {"metric": clean(sm.get("metric", ""), 80),
                               "direction": sm.get("direction") if sm.get("direction") in ("up", "down") else "",
                               "min_change": clean(sm.get("min_change", ""), 60)},
            "needs_human_approval": approval, "auto_executable": auto}, None


def main():
    day = sys.argv[1] if len(sys.argv) > 1 else datetime.date.today().isoformat()
    yt_md, yt_json = read_text(SRV / f"facts/{day}.md"), SRV / f"facts/{day}.json"
    pl_md, pl_status = read_text(SRV / f"facts/play-{day}.md"), read_text(SRV / "facts/play-status.txt").strip()
    corpus_tokens = set(numbers(yt_md + "\n" + pl_md))
    facts = {"week": None, "youtube": None, "play": {"status": pl_status or None, "summary_markdown": pl_md or None},
             "youtube_summary_markdown": yt_md or None}
    if yt_json.exists():
        fj = json.loads(yt_json.read_text())
        facts["week"] = fj.get("windows")
        facts["youtube"] = {"channel_this_week": fj.get("channel_w0"), "channel_prev_week": fj.get("channel_w1"), "videos": fj.get("videos")}
    # レビューの文面は、引き渡しに含めない (利用者の文章。指示が混ざりうる)
    if pl_md:
        facts["play"]["summary_markdown"] = "\n".join(l for l in pl_md.splitlines() if not l.startswith("  - 星"))

    claude, err = load_claude_json(SRV / f"reports/proposals-{day}.json")
    proposals, rejected, reviews, dq = [], [], [], []
    if err:
        dq.append(f"提案を作れなかった: {err}")
    else:
        for p in (claude.get("proposals") or [])[:MAX_PROPOSALS]:
            v, why = validate_proposal(p, corpus_tokens)
            if v:
                v["id"] = f"P-{day.replace('-', '')}-{len(proposals) + 1:02d}"
                proposals.append(v)
            else:
                rejected.append({"reason": why, "raw_action": clean(p.get("action", "") if isinstance(p, dict) else "", 120)})
        exps = read_experiments()
        for r in (claude.get("experiment_reviews") or [])[:20]:
            if isinstance(r, dict) and r.get("experiment_id") in exps and r.get("outcome") in OUTCOMES:
                reviews.append({"experiment_id": r["experiment_id"], "outcome": r["outcome"], "note": clean(r.get("note", ""), 300),
                                "evidence": [clean(x, 160) for x in (r.get("evidence") or [])[:4]]})
        dq += [clean(x, 240) for x in (claude.get("data_quality") or [])[:8]]
    # 機械的に拾えるデータの注意
    for line in yt_md.splitlines():
        if line.startswith("注意:"):
            dq.append(clean(line, 300))
    if pl_status and "NG" in pl_status:
        dq.append("Google Play: " + pl_status)
    exps = read_experiments()
    doc = {"schema": 1, "date": day, "generated_at": datetime.datetime.now().isoformat(timespec="seconds"),
           "facts": facts, "data_quality": dq, "proposals": proposals, "experiment_reviews": reviews,
           "open_experiments": [e for e in exps.values() if e["status"] == "open"], "rejected": rejected,
           "rules_for_consumers": "SCHEMA.md を読む。auto_executable が false のものは実行しない。needs_human_approval が true は人の承認が先。実行したら exp.py で記録する。"}
    OUT.mkdir(parents=True, exist_ok=True)
    text = json.dumps(doc, ensure_ascii=False, indent=1)
    (OUT / f"{day}.json").write_text(text)
    (OUT / "latest.json").write_text(text)
    (OUT / "SCHEMA.md").write_text(SCHEMA_DOC)
    for p in OUT.iterdir():
        p.chmod(0o644)
    print(f"保存: {OUT / (day + '.json')} (提案 {len(proposals)} 件、落とした {len(rejected)} 件、実験の評価 {len(reviews)} 件)")


if __name__ == "__main__":
    main()
