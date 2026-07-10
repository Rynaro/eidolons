# atlas-aci-autosync — keep the atlas-aci code-graph fresh automatically

**Tier:** full · **Maker:** vivi · **Checker:** vigil

## Problem

atlas-aci's `serve` reads a pre-built, epoch-namespaced index (`.atlas/graph.<epoch>.db`)
over a **read-only** mount; it never re-indexes. The index is built once by ATLAS's
`commands/aci.sh wire` (a single `atlas-aci index` run) and then **goes stale until a human
remembers to re-run it**. A session in flight keeps answering `callers_of` / `search_symbol`
against a graph that no longer matches the working tree — silently wrong, which is the exact
failure atlas-aci v2.0.0 spent itself eliminating.

atlas-aci v2.0.0 ships `index --since <marker>` incremental re-indexing: it skips files whose
`(mtime_ns, size)` are unchanged since the last pass, so a refresh is cheap. Nothing in the
nexus fires it.

## Change

Add an **auto-sync** step to the nexus harness hook (`cli/src/harness_hook.sh`) that fires a
**detached, deduplicated, incremental** re-index on **SessionStart** and on **every
UserPromptSubmit**, so the graph converges on the working tree within ~one turn of any edit.
**On by default; opt-out only.**

### Decision (deliberated)

The cadence was chosen against the freshness-vs-latency trade: **per-turn background**, not
session-start-only (which leaves mid-session staleness — the stated pain) and not blocking
(which would violate the ECM ≤300 ms prompt-path budget). Safe to run concurrently with
`serve` because atlas-aci's `index` writes a temp file and **atomically renames under a
single-writer lock** (AC-H-17), and `serve` opens the DB `mode=ro`; the reader keeps a
consistent snapshot until it reopens. This is the same docker-in-hook shape the existing
`eidolons memory preflight` step already uses (bounded, fail-open) — not a new precedent.

### Behaviour

On each SessionStart and UserPromptSubmit, the hook runs the auto-sync step. It is a **silent
no-op** unless **all** hold:

1. atlas-aci is wired: `.mcpServers["atlas-aci"]` exists in `./.mcp.json`.
2. Not disabled: `eidolons.yaml` `.harness.atlas_sync.enabled` is not `false`. **Absent ⇒
   enabled** (opt-out, unlike ECM's opt-in). This is the only knob; setting it to `false`
   is how a user "asks" for it off.
3. `docker` is on `PATH`.

When all hold, it:

- **Reuses the exact pinned image ref** from `.mcp.json`'s atlas-aci `serve` args
  (`ghcr.io/rynaro/atlas-aci@sha256:…`). **This is load-bearing:** a different digest could
  produce a different-`SCHEMA_EPOCH` DB that `serve` then rejects with `INDEX_UNAVAILABLE`.
  The reindex must be the same version as the server reading it.
- **Dedups** by container name `atlas-aci-sync-<project-slug>`: if one is already running, skip
  (rapid turns must not stack containers; the single-writer lock is only a backstop).
- **Spawns detached** and returns immediately:
  ```
  docker run --rm -d --name atlas-aci-sync-<slug> --label eidolons.project=<slug> \
    -v "<project-root>:/repo" --cap-drop ALL --security-opt no-new-privileges \
    <pinned-image> index --repo /repo --since auto
  ```
  Note `/repo` is mounted **read-write** here (the reindex writes `.atlas/graph.<epoch>.db`),
  which is the deliberate inverse of the `:ro` serve mount — the DIR-2 split (serve reads,
  index writes) applied at runtime.
- **Fails open**: docker error, image-pull miss, or any failure degrades to a silent no-op —
  a stale graph is never worse than a broken session. The whole hook already runs under
  `_main 2>/dev/null || true`.

### Non-goals

- No blocking / synchronous reindex (would break the ≤300 ms prompt path).
- No file-watcher or continuous daemon (serve is read-only by design).
- No change to atlas-aci itself — this is nexus wiring only.
- No git hook — working-tree edits (uncommitted) are the point, and a commit hook would miss
  them; per-turn `--since` covers them.

## Files

- `cli/src/harness_hook.sh` — the `_atlas_autosync` step + its calls from both branches.
- `roster/mcps.yaml` — a doc note on the atlas-aci entry pointing at the opt-out knob (no
  behavioural field; the hook reads `.mcp.json`, not the roster).
- `README.md` — the harness section: auto-sync is on by default; disable with
  `harness.atlas_sync.enabled: false`.
- `cli/tests/harness.bats` — coverage (see acceptance).
- `schemas/*` — if `eidolons.yaml`'s `.harness` block has a schema, add `atlas_sync.enabled`.

## Acceptance

See `change.json`. Every gate is mechanically checkable with a fake `docker` shim: the hook
must (a) no-op when atlas-aci absent, (b) no-op when `.harness.atlas_sync.enabled: false`,
(c) fire with the **exact `.mcp.json` digest** and `-d` when enabled+wired, (d) skip when a
sync container is already "running", (e) never emit non-zero / never block, (f) stay bash 3.2
clean.
