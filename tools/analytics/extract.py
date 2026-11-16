#!/usr/bin/env python3
"""claude-code-action の実行記録 (execution_file) から、最後の返答を取り出して、analysis.json に書く。

  python3 extract.py <execution_file> <out>

取り出せなくても、空のファイルを書いて正常終了する (validate.py が「分析を読めなかった」として、事実だけで続ける)。
ログには、返答の中身を出さない (公開リポジトリのため)。
"""
import json, pathlib, sys


def last_text(messages):
    for m in reversed(messages):
        if isinstance(m, dict) and m.get("type") == "result" and isinstance(m.get("result"), str) and m["result"].strip():
            return m["result"]
    for m in reversed(messages):  # result が無い形の記録にも対応する
        msg = m.get("message") if isinstance(m, dict) else None
        if isinstance(msg, dict) and msg.get("role") == "assistant":
            texts = [c.get("text", "") for c in msg.get("content", []) if isinstance(c, dict) and c.get("type") == "text"]
            if any(t.strip() for t in texts):
                return "\n".join(texts)
    return ""


def main():
    src, out = sys.argv[1], sys.argv[2]
    try:
        data = json.loads(pathlib.Path(src).read_text(encoding="utf-8"))
        text = last_text(data if isinstance(data, list) else [data])
    except Exception as e:
        print(f"実行記録を読めない: {type(e).__name__}")
        text = ""
    start, end = text.find("{"), text.rfind("}")
    body = text[start:end + 1] if start >= 0 and end > start else ""
    pathlib.Path(out).write_text(body, encoding="utf-8")
    print(f"取り出した: {len(body)} 文字")


if __name__ == "__main__":
    main()
