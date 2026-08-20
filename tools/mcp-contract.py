#!/usr/bin/env python3
"""mcp-contract.py — verify every MCP tool an agent or skill declares still exists.

The stack has been bitten by this twice. The virustotal server renamed its tools
(analyze_domain -> get_domain_report) and nine agents kept declaring the old names
for days; engagement-start still declares wstg-pentest's start_engagement, which the
server does not expose at all. Neither was caught by anything: mcp-doctor diagnoses a
BROKEN SERVER, and stack-drift compares FILES. A reference to a tool that no longer
exists is a third thing, and it fails silently at the worst moment — mid-engagement,
inside an agent, on a call that simply errors.

This asks each server for its real tool list over stdio JSON-RPC (the same handshake
Claude Code performs, so the answer is authoritative) and diffs it against what the
repo's agents and skills declare.

Read-only. Spawns each server briefly and kills it; never writes.

Exit 1 if any declared tool does not exist. Servers that fail to answer are a
WARNING, never a failure — an MCP that needs a laptop-side app (caido) is legitimately
absent, and treating that as a broken contract would make the job untrustworthy.

Usage: tools/mcp-contract.py [--quiet] [--server NAME]
"""
import json, os, re, subprocess, sys, threading, glob, collections

ROOT = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
CLAUDE_JSON = os.path.expanduser("~/.claude.json")
TIMEOUT = int(os.environ.get("MCP_PROBE_TIMEOUT", "75"))
# Servers provided by the claude.ai account rather than ~/.claude.json. They cannot
# be spawned locally, so their tool lists are not checkable from here.
MANAGED_PREFIX = "claude_ai_"


def probe(cfg):
    """Return the server's tool names, or None if it did not answer in time."""
    try:
        p = subprocess.Popen(
            [cfg["command"]] + cfg.get("args", []),
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            text=True, env={**os.environ, **(cfg.get("env") or {})})
    except Exception:
        return None
    out = {}

    def send(o):
        p.stdin.write(json.dumps(o) + "\n")
        p.stdin.flush()

    def read():
        for line in p.stdout:
            try:
                m = json.loads(line)
            except Exception:
                continue
            if m.get("id") == 2:
                out["t"] = [t["name"] for t in m.get("result", {}).get("tools", [])]
                return
    try:
        send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
            "protocolVersion": "2024-11-05", "capabilities": {},
            "clientInfo": {"name": "mcp-contract", "version": "1"}}})
        send({"jsonrpc": "2.0", "method": "notifications/initialized"})
        send({"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}})
    except Exception:
        p.kill()
        return None
    t = threading.Thread(target=read, daemon=True)
    t.start()
    t.join(TIMEOUT)
    p.kill()
    return out.get("t")


def references():
    """server -> {tool -> {source files}}, from the REPO copies (what a rebuild installs)."""
    refs = collections.defaultdict(lambda: collections.defaultdict(set))
    srcs = glob.glob(os.path.join(ROOT, "payload/agents/*.md")) + \
        glob.glob(os.path.join(ROOT, "payload/skills/*/SKILL.md"))
    for f in srcs:
        label = os.path.relpath(f, os.path.join(ROOT, "payload"))
        try:
            body = open(f, encoding="utf-8").read()
        except Exception:
            continue
        for srv, tool in re.findall(r"mcp__([A-Za-z0-9_-]+)__([A-Za-z0-9_]+)", body):
            refs[srv][tool].add(label)
    return refs


def main():
    quiet = "--quiet" in sys.argv
    only = None
    if "--server" in sys.argv:
        only = sys.argv[sys.argv.index("--server") + 1]

    try:
        servers = json.load(open(CLAUDE_JSON))["mcpServers"]
    except Exception as e:
        print(f"[ALERT] cannot read {CLAUDE_JSON}: {e}")
        return 1

    refs = references()
    bad = warned = ok = 0
    total_refs = sum(len(v) for v in refs.values())
    print(f"=== mcp-contract: {total_refs} tool reference(s) across "
          f"{len(refs)} server(s) in {os.path.relpath(ROOT, os.path.expanduser('~'))}/payload ===\n")

    for srv in sorted(refs):
        if only and srv != only:
            continue
        declared = refs[srv]
        if srv.startswith(MANAGED_PREFIX):
            if not quiet:
                print(f"[skip]  {srv}: account-managed connector, not spawnable locally "
                      f"({len(declared)} refs unchecked)")
            continue
        if srv not in servers:
            print(f"[ALERT] {srv}: referenced by {len(declared)} tool(s) but NOT CONFIGURED "
                  f"in ~/.claude.json")
            for t in sorted(declared):
                print(f"          {t}  <- {', '.join(sorted(declared[t]))}")
            bad += len(declared)
            continue
        live = probe(servers[srv])
        if live is None:
            print(f"[warn]  {srv}: no tools/list within {TIMEOUT}s — not checked "
                  f"(server down or needs an external app)")
            warned += 1
            continue
        missing = sorted(set(declared) - set(live))
        if missing:
            print(f"[ALERT] {srv}: {len(missing)} declared tool(s) DO NOT EXIST "
                  f"(server exposes {len(live)})")
            for t in missing:
                print(f"          {t}  <- {', '.join(sorted(declared[t]))}")
            bad += len(missing)
        else:
            ok += 1
            if not quiet:
                print(f"[ok]    {srv}: all {len(declared)} declared tools exist "
                      f"({len(live)} exposed)")

    print(f"\n=== {bad} dead reference(s), {warned} server(s) unchecked, {ok} clean ===")
    if bad:
        print("    fix the agent/skill in payload/, then: tools/stack-apply.sh --host all --apply")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
