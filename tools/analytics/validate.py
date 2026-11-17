#!/usr/bin/env python3
"""Claude の分析 (analysis.json) を、決まった規則で検証して、引き渡し (handoff.json) を作る。

  python3 validate.py --facts facts.json --analysis analysis.json --root <データ用リポジトリ> --out handoff.json

Claude が書いたものは、そのままは信用しない。次を機械的に付け直す:
  - evidence_verified    : 根拠の数字が facts.json の中にあるか (計算式は、左辺の数字だけを見る)
  - needs_human_approval : 公開・投稿・リリース・削除などの語を含む提案は、必ず true
  - auto_executable      : 承認が不要 / 確からしさが中以上 / サンプル 5 以上 / 根拠が検証済み / gather でない、のすべてで true
分析が読めなくても、止めずに「提案なし」の引き渡しを作る (レポートと通知は、事実だけで出せる)。
"""
import argparse, datetime, json, pathlib, re, sys

import exp

MAX_PROPOSALS = 6
APPROVAL_WORDS = re.compile(r"公開|投稿|アップロード|リリース|審査|ストア|削除|課金|広告|価格|返信|告知|配信を")
TARGETS = {"video", "game", "data"}
KINDS = {"experiment", "fix", "gather"}
CONF = {"high", "medium", "low"}
STATUS = {"ok", "attention"}
OUTCOMES = {"improved", "no_change", "worse", "insufficient_data"}
VERDICTS = {"伸びた", "平均的", "伸びなかった", "公開直後"}


def clean(s, n):
    return re.sub(r"[\x00-\x08\x0b-\x1f\x7f]", " ", str(s)).strip()[:n]


def canon(n):
    """数字の表記をそろえる (1099 と 1099.0、1,099 を同じに扱う)。"""
    try:
        return format(float(n), ".10g")
    except ValueError:
        return n


def numbers(s):
    return [canon(x) for x in re.findall(r"\d+(?:\.\d+)?", str(s).replace(",", ""))]


def corpus(facts):
    return set(numbers(json.dumps(facts, ensure_ascii=False)))


def evidence_ok(value, tokens):
    left = value.split("=")[0] if "=" in value else value
    ns = numbers(left)
    return bool(ns) and all(n in tokens for n in ns)


def load_analysis(p):
    raw = pathlib.Path(p).read_text(encoding="utf-8").strip() if pathlib.Path(p).exists() else ""
    if not raw:
        return None, "分析のファイルがない、または空"
    raw = re.sub(r"^```(?:json)?\s*|\s*```$", "", raw)
    try:
        d = json.loads(raw)
    except json.JSONDecodeError as e:
        return None, f"JSON として読めない: {e}"
    return (d, None) if isinstance(d, dict) else (None, "最上位が辞書でない")


def clean_evidence(items):
    out = []
    for e in (items or [])[:6]:
        if isinstance(e, dict) and e.get("metric") and e.get("value") is not None:
            out.append({"metric": clean(e["metric"], 80), "value": clean(e["value"], 160)})
    return out


def validate_proposal(p, tokens):
    if not isinstance(p, dict):
        return None, "辞書でない"
    t, k, c = p.get("target"), p.get("kind"), p.get("confidence")
    if t not in TARGETS or k not in KINDS or c not in CONF:
        return None, f"target/kind/confidence が不正 ({t}, {k}, {c})"
    action = clean(p.get("action", ""), 200)
    if not action:
        return None, "action が空"
    ev = clean_evidence(p.get("evidence"))
    verified = bool(ev) and all(evidence_ok(e["value"], tokens) for e in ev)
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


def build(facts, analysis, err, experiments, day):
    tokens = corpus(facts)
    proposals, rejected, reviews, dq, highlights = [], [], [], list(facts.get("data_quality", [])), []
    insights, findings = [], []
    # 状態は、規則の要確認 (alerts) があれば必ず attention。Claude は ok → attention に上げられるが、下げられない
    status = "attention" if facts.get("alerts") else "ok"
    summary = ""
    if err:
        dq.append(f"分析を読めなかった: {err}")
    else:
        if analysis.get("status") == "attention":
            status = "attention"
        summary = clean(analysis.get("summary", ""), 400)
        highlights = [clean(h, 200) for h in (analysis.get("highlights") or [])[:6] if isinstance(h, str)]
        for p in (analysis.get("proposals") or [])[:MAX_PROPOSALS]:
            v, why = validate_proposal(p, tokens)
            if v:
                v["id"] = f"P-{day.replace('-', '')}-{len(proposals) + 1:02d}"
                proposals.append(v)
            else:
                rejected.append({"reason": why, "raw_action": clean(p.get("action", "") if isinstance(p, dict) else "", 120)})
        for x in (analysis.get("video_insights") or [])[:8]:
            if isinstance(x, dict) and x.get("comment"):
                ev = clean_evidence(x.get("evidence"))
                insights.append({"id": clean(x.get("id", ""), 40), "verdict": x.get("verdict") if x.get("verdict") in VERDICTS else "",
                                 "comment": clean(x["comment"], 200), "evidence": ev,
                                 "evidence_verified": bool(ev) and all(evidence_ok(e["value"], tokens) for e in ev)})
        for x in (analysis.get("content_findings") or [])[:5]:
            if isinstance(x, dict) and x.get("finding"):
                ev = clean_evidence(x.get("evidence"))
                try:
                    n = int(x.get("sample_size"))
                except (TypeError, ValueError):
                    n = 0
                findings.append({"finding": clean(x["finding"], 200), "hypothesis": clean(x.get("hypothesis", ""), 200),
                                 "next_test": clean(x.get("next_test", ""), 150), "sample_size": n, "evidence": ev,
                                 "evidence_verified": bool(ev) and all(evidence_ok(e["value"], tokens) for e in ev),
                                 "reference_only": n < 5})
        for r in (analysis.get("experiment_reviews") or [])[:20]:
            if isinstance(r, dict) and r.get("experiment_id") in experiments and r.get("outcome") in OUTCOMES:
                reviews.append({"experiment_id": r["experiment_id"], "outcome": r["outcome"], "note": clean(r.get("note", ""), 300),
                                "evidence": [clean(x, 160) for x in (r.get("evidence") or [])[:4]]})
        dq += [clean(x, 240) for x in (analysis.get("data_quality") or [])[:8] if isinstance(x, str)]
    return {"schema": 2, "date": day, "generated_at": datetime.datetime.now().isoformat(timespec="seconds"),
            "status": status, "summary": summary, "highlights": highlights, "alerts": facts.get("alerts", []),
            "data_quality": list(dict.fromkeys(dq)), "video_insights": insights, "content_findings": findings, "proposals": proposals, "experiment_reviews": reviews,
            "open_experiments": [e for e in experiments.values() if e["status"] == "open"], "rejected": rejected,
            "rules_for_consumers": "auto_executable が false のものは実行しない。needs_human_approval が true は人の承認が先。"
                                   "hypothesis は仮説で、事実は facts だけ。実行したら exp.py で記録する。"}


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--facts", required=True)
    ap.add_argument("--analysis", required=True)
    ap.add_argument("--root", required=True)
    ap.add_argument("--out", default="handoff.json")
    a = ap.parse_args(argv)
    facts = json.loads(pathlib.Path(a.facts).read_text(encoding="utf-8"))
    analysis, err = load_analysis(a.analysis)
    h = build(facts, analysis, err, exp.read_at(a.root), facts["date"])
    pathlib.Path(a.out).write_text(json.dumps(h, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"保存: {a.out} (状態 {h['status']}、提案 {len(h['proposals'])} 件、落とした {len(h['rejected'])} 件)")


if __name__ == "__main__":
    sys.exit(main())
