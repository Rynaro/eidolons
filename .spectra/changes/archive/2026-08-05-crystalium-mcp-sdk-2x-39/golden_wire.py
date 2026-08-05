#!/usr/bin/env python3
"""WU-1a — capture the MCP wire baseline by driving the real stdio server.

This is the ONLY oracle the #39 SDK migration has: mcp 2.x changes how tools are
REGISTERED but must change nothing a client observes. So we record exactly what a
client sees at v1.11.0 and diff it after the migration.

Drives `python -m crystalium serve` over stdio with raw JSON-RPC:
  initialize -> notifications/initialized -> tools/list -> tools/call (ok + error)

Deliberately NOT normalised beyond volatile keys, because over-normalising is how
a wire regression slips through the migration's only gate.
"""
import json
import subprocess
import sys

VOLATILE_TOP = {"id"}


def rpc(pid, obj):
    pid.stdin.write(json.dumps(obj) + "\n")
    pid.stdin.flush()


def read_response(pid, want_id, limit=400):
    """Read lines until we see the response with want_id (skip notifications/logs)."""
    for _ in range(limit):
        line = pid.stdout.readline()
        if not line:
            return None
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            msg = json.loads(line)
        except Exception:
            continue
        if msg.get("id") == want_id:
            return msg
    return None


def main(out_path):
    proc = subprocess.Popen(
        [sys.executable, "-m", "crystalium", "serve"],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        text=True, bufsize=1,
    )
    captured = {}
    try:
        rpc(proc, {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
            "protocolVersion": "2025-06-18",
            "capabilities": {},
            "clientInfo": {"name": "golden-wire", "version": "1"},
        }})
        captured["initialize"] = read_response(proc, 1)

        rpc(proc, {"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}})

        rpc(proc, {"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}})
        captured["tools_list"] = read_response(proc, 2)

        # A real call that SUCCEEDS. `scope` and `query` are both required by the
        # advertised inputSchema — omitting scope yields SDK-level schema
        # validation (isError=true) rather than exercising the handler at all.
        # agent_class_visibility is a STRING on the Scope model, not a list —
        # a list yields a pydantic ValidationError returned as ordinary content.
        scope = {"project": "golden-wire", "agent_class_visibility": "all"}
        rpc(proc, {"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {
            "name": "crystalium.recall",
            "arguments": {"scope": scope, "query": "golden wire probe", "k": 1},
        }})
        captured["call_recall"] = read_response(proc, 3)

        # A successful WRITE too, so the migration oracle covers the commit path
        # (enforcement chokepoint + ECL sidecar), not just a read.
        rpc(proc, {"jsonrpc": "2.0", "id": 5, "method": "tools/call", "params": {
            "name": "crystalium.commit",
            "arguments": {
                "layer": "episodic",
                "payload": {"summary": "golden wire fixture record", "scope": scope},
                "provenance": {
                    "source": "environment",
                    "author_agent": "golden-wire",
                    "task_id": "gw-1",
                    "created_at": "2026-08-05T00:00:00Z",
                },
            },
        }})
        captured["call_commit"] = read_response(proc, 5)

        # SDK-level schema validation path (distinct from crystalium's own
        # UNKNOWN_TOOL path below — the two set isError differently today).
        rpc(proc, {"jsonrpc": "2.0", "id": 6, "method": "tools/call", "params": {
            "name": "crystalium.recall",
            "arguments": {"query": "missing scope on purpose"},
        }})
        captured["call_schema_violation"] = read_response(proc, 6)

        # The ERROR path — FORGE R4 hinges on its current shape (errors currently
        # come back as ordinary content, not isError).
        rpc(proc, {"jsonrpc": "2.0", "id": 4, "method": "tools/call", "params": {
            "name": "crystalium.definitely_not_a_tool",
            "arguments": {},
        }})
        captured["call_unknown_tool"] = read_response(proc, 4)
    finally:
        try:
            proc.stdin.close()
        except Exception:
            pass
        proc.terminate()
        try:
            proc.wait(timeout=15)
        except Exception:
            proc.kill()

    for k, v in captured.items():
        if v is None:
            print(f"FATAL: no response captured for {k}")
            sys.exit(1)

    json.dump(captured, open(out_path, "w"), indent=1, sort_keys=True)
    tools = captured["tools_list"]["result"]["tools"]
    print(f"captured {len(captured)} exchanges -> {out_path}")
    print(f"tools/list: {len(tools)} tools")
    print("names:", sorted(t["name"] for t in tools))
    si = captured["initialize"]["result"].get("serverInfo", {})
    print("serverInfo:", si)
    err = captured["call_unknown_tool"]["result"]
    print("error-path keys:", sorted(err.keys()), "| isError:", err.get("isError"))


if __name__ == "__main__":
    main(sys.argv[1])
