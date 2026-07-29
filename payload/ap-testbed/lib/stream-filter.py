#!/usr/bin/env python3
"""Turn `claude -p --output-format stream-json --verbose` JSONL into readable
live-progress lines for the scan log / admin UI. Reads stdin, writes plain text.
"""
import sys, json, time


def w(s):
    sys.stdout.write(s + "\n")
    sys.stdout.flush()


for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        ev = json.loads(line)
    except Exception:
        continue
    t = ev.get("type")
    ts = time.strftime("%H:%M:%S")
    if t == "system" and ev.get("subtype") == "init":
        w("[%s] session start — model %s, %d tools" %
          (ts, ev.get("model", "?"), len(ev.get("tools", []))))
    elif t == "assistant":
        for c in ev.get("message", {}).get("content", []):
            if c.get("type") == "text" and c.get("text", "").strip():
                w("[%s] %s" % (ts, c["text"].strip()))
            elif c.get("type") == "tool_use":
                inp = c.get("input", {}) or {}
                hint = (inp.get("command") or inp.get("url") or inp.get("file_path")
                        or inp.get("description") or inp.get("pattern") or "")
                w("[%s] → %s: %s" % (ts, c.get("name", "tool"), str(hint)[:140]))
    elif t == "user":
        for c in ev.get("message", {}).get("content", []):
            if c.get("type") == "tool_result":
                out = c.get("content", "")
                if isinstance(out, list):
                    out = " ".join(x.get("text", "") for x in out if isinstance(x, dict))
                out = str(out).replace("\n", " ").strip()
                if out:
                    w("[%s]   ✓ %s" % (ts, out[:180]))
    elif t == "result":
        w("[%s] === %s — %s turns, %sms ===" %
          (ts, ev.get("subtype", "done"), ev.get("num_turns", "?"), ev.get("duration_ms", "?")))
