#!/usr/bin/env python3
"""Diff a freshly-captured MCP wire capture against the v1.11.0 golden baseline.

This is the ONLY oracle the #39 SDK migration has. mcp 2.x changes how tools are
REGISTERED; it must change nothing a client observes. So: capture the same
exchanges after the migration and diff.

EXCLUSIONS ARE THE RISK. FORGE's stated failure mode is a comparator that
normalises so much a real wire regression slips through. So every exclusion here
is enumerated, justified, and narrow — we drop specific volatile VALUES, never
whole objects, and never a key we merely find inconvenient.

Excluded, with reason:
  1. initialize.result.serverInfo.version
     Legitimately moves 1.11.0 -> 1.12.0. Also env-dependent in dev: __version__
     derives from installed package METADATA (baked in the image), not from the
     bind-mounted source, so a dev capture reports the image's version.
  2. call_commit -> the committed record's `id` (uuid4, fresh per run)
     and any `created_at`/timestamp-shaped value.
     Volatile by construction; their PRESENCE is still asserted.

Everything else — tool names, descriptions, inputSchema, capabilities,
protocolVersion, isError on every path, error payload text, record shapes — is
compared verbatim.

Usage: compare_wire.py <golden.json> <candidate.json>
Exit 0 = identical modulo the documented exclusions. Exit 1 = regression.
"""
import json
import sys

VOLATILE_RECORD_KEYS = {"id", "created_at", "committed_at", "timestamp"}


def normalise(capture):
    """Return a deep copy with the documented volatile values replaced by a
    sentinel. The KEY must still exist — we assert presence, drop only value."""
    c = json.loads(json.dumps(capture))  # deep copy

    si = c.get("initialize", {}).get("result", {}).get("serverInfo")
    if isinstance(si, dict) and "version" in si:
        si["version"] = "<EXCLUDED:serverInfo.version>"

    for name in ("call_commit",):
        blk = c.get(name, {}).get("result", {})
        for item in blk.get("content", []) or []:
            txt = item.get("text")
            if not isinstance(txt, str):
                continue
            try:
                payload = json.loads(txt)
            except Exception:
                continue  # not JSON -> compare verbatim
            if isinstance(payload, dict):
                for k in list(payload):
                    if k in VOLATILE_RECORD_KEYS:
                        payload[k] = f"<EXCLUDED:{k}>"
                item["text"] = json.dumps(payload, indent=2, sort_keys=True)
    return c


def walk(a, b, path=""):
    diffs = []
    if type(a) is not type(b):
        return [f"{path}: type {type(a).__name__} != {type(b).__name__}"]
    if isinstance(a, dict):
        for k in sorted(set(a) | set(b)):
            if k not in a:
                diffs.append(f"{path}.{k}: ADDED in candidate")
            elif k not in b:
                diffs.append(f"{path}.{k}: MISSING from candidate")
            else:
                diffs += walk(a[k], b[k], f"{path}.{k}")
    elif isinstance(a, list):
        if len(a) != len(b):
            diffs.append(f"{path}: length {len(a)} != {len(b)}")
        else:
            for i, (x, y) in enumerate(zip(a, b)):
                diffs += walk(x, y, f"{path}[{i}]")
    elif a != b:
        diffs.append(f"{path}: {a!r} != {b!r}")
    return diffs


def main(golden_path, cand_path):
    golden = normalise(json.load(open(golden_path)))
    cand = normalise(json.load(open(cand_path)))

    # Presence assertions the exclusions must not hide.
    for label, cap in (("golden", golden), ("candidate", cand)):
        si = cap.get("initialize", {}).get("result", {}).get("serverInfo", {})
        if "version" not in si or "name" not in si:
            sys.exit(f"FATAL: {label} serverInfo missing name/version entirely")
        n = len(cap.get("tools_list", {}).get("result", {}).get("tools", []))
        if n == 0:
            sys.exit(f"FATAL: {label} advertises zero tools")

    diffs = walk(golden, cand, "root")
    if diffs:
        print(f"WIRE REGRESSION — {len(diffs)} difference(s):")
        for d in diffs[:60]:
            print("  " + d)
        sys.exit(1)
    gt = len(golden["tools_list"]["result"]["tools"])
    print(f"WIRE IDENTICAL — {len(golden)} exchanges, {gt} tools, "
          f"modulo documented exclusions (serverInfo.version, volatile record ids)")
    sys.exit(0)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
