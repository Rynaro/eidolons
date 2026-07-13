# fix-ecm-meter-race-atlas-sync

**Tier:** full (files_touched=6, rubric=7/12, tradeoff_present=true → route 0→1→2→3→4)
**Maker:** vivi **Checker:** kupo (C4 maker≠checker)
**Spec of record:** `docs/specs/ecm/spec.md`

## Problem

Three independent defects, all of the same species: a silent, fail-open no-op that no
gate could observe. Each was found by *exercising* the system, not by reading it.

### D1 — the ECM meter was permanently wedged (context management entirely dead)

`.eidolons/.context/meter.json` was corrupt: a complete JSON object followed by the
orphaned tail of a longer previous write.

Cause is a **concurrent non-atomic write**. Two writers feed the meter:
- `cli/src/statusline.sh` (§"Feed the ECM meter"), fired by `.claude/settings.json`
  with `refreshInterval: 2` — **every two seconds**;
- `cli/src/harness_hook.sh`, fired on SessionStart and every UserPromptSubmit.

The write at `context_status.sh:201` is a plain `printf … > "$METER_PATH"` — no
temp-and-rename, no lock. The two writers emit **different-length** JSON (the statusline
passes `--session-id`, so its object is longer than a hook write with `session_id: null`),
so a short write landing over a long one leaves the long one's tail behind.

Reproduced: **9 of 40** concurrent write-pairs corrupt the file.

The corruption is **self-perpetuating**. The inherit-prior-meter reads
(`context_status.sh:121-123`) are `$(jq … 2>/dev/null || echo 0)`. On a corrupt file jq
prints the value **and** exits 5, so the shell captures *both* jq's output and the
fallback — yielding `compaction_count="0\n0"`. That is two JSON documents where
`--argjson` demands one, so the compose fails, `METER_JSON=""`, and the kernel bails
*before* the write. The kernel can therefore never overwrite the file that is breaking it.

Observable effect: `zone` pinned to `unknown` → policy pinned to `P7 → continue`. Every
zone-triggered operation (externalize / prune / compact / handoff-fresh / wrap-up) was
unreachable from 2026-07-12 until now. Fail-open (`exit 0`, warn→stderr, hooks discard
stderr) is why it ran silently.

The zone ladder and decision table themselves are **correct** — verified in isolation
(green→P7 continue, amber→P6 externalize, red→P3 compact, critical→P2 handoff_fresh).
Only the meter feeding them was broken. Do not "fix" the policy table.

### D2 — atlas-aci auto-sync: index never built, and permanently self-disabling

`_atlas_autosync()` (`harness_hook.sh:207-266`) has two stacked bugs:

1. **No `--user`.** The image runs as user `atlas`; host `.atlas/` is `1000:1000` mode
   `755` → `PermissionError: [Errno 13] … '/repo/.atlas/.index.lock'`. The index never
   builds; every `search_symbol` / `graph_query` returns `INDEX_UNAVAILABLE`.
2. **The dedup gate uses `docker ps -a`,** which matches **non-running** containers.
   Orphans in state `Created` are minted when `with_timeout`'s `kill -9` (`lib.sh:633`)
   lands on `docker run -d` mid-create — `--rm` only reaps containers that actually
   STARTED. Two such orphans were found live; they made the gate match unconditionally,
   so the reindex was **permanently skipped forever**.

The archived spec (`.spectra/changes/archive/2026-07-10-atlas-aci-autosync/spec.md:52`)
says *"if one is already **running**, skip"* — the `-a` was always drift from intent.

### D3 — atomos pinned to 0.1.0 while the lockfile claims 0.2.0

`.mcp.json` pins `sha256:ff2449e9…` (0.1.0). `eidolons.mcp.lock` records version `0.2.0`,
digest `sha256:b3f67b4e…`, `target: ".mcp.json"`, `installed_at: 2026-07-12T14:40:00Z`.
The lock records an install that never landed, and nothing reconciles lock against
artifact. Confirmed independently: the served tool surface has 3 tools;
`compose_externalize_manifest` (the 4th, shipped in 0.2.0) is absent.

## Decision (FORGE, confidence 0.86) — D2 dedup strategy

**Strategy D: spawn-first, reconcile-on-collision, `docker rm` (never `-f`).**

Delete the `docker ps` probe. `docker run --name` **is** the dedup gate — the only
*atomic* test-and-set Docker exposes (the daemon serialises name allocation at create
time). Do not check-then-act; act, and read the failure. Then use plain `docker rm` —
**never `rm -f`** — as the disambiguator: the daemon refuses to remove a *running*
container, so that one exit code separates "legitimate in-flight reindex, leave alone"
(C5) from "wedged orphan, reap" (C4) with no state parsing and no staleness clock.

Rejected: (A) running-only `ps` + unconditional `rm -f` → 3 docker calls in the common
case, and `-f` re-arms a check-then-act race that can SIGKILL a healthy indexer.
(B) `ps -a` + `{{.State}}` + `rm -f` → strictly dominated; same stale-read window.
(C) label-filter + random names → orphans accumulate forever (violates C4 self-healing)
and `status=running` cannot see a peer's mid-create container, so two indexers race.

**Timeout split:** reconcile keeps the 1.5 s hot-path bound; the **spawn gets 3 s**,
because 1.5 s sits *inside* the normal container-create latency distribution on a cold
daemon — it is the orphan factory. Deleting the probe buys back the budget, so worst-case
stall is unchanged (3.0 s) while the common case **halves** from 2 docker calls to 1.

## Requirements (EARS)

- **R1** — WHEN `context status` writes the meter, the system SHALL write it atomically
  (temp file in the same directory + `mv`), such that no reader or concurrent writer can
  observe a partially-written file.
- **R2** — WHEN `context status` reads a prior meter that is not valid JSON, the system
  SHALL treat it as absent (inherit defaults) and overwrite it, rather than failing to
  compose. A corrupt meter SHALL self-heal on the next write.
- **R3** — WHEN the atlas auto-sync spawns the reindex container, the system SHALL pass
  `--user "$(id -u):$(id -g)"` so the container can write `.atlas/`.
- **R4** — WHEN a *non-running* container already holds the sync name, the system SHALL
  remove it and spawn (self-heal, no human intervention).
- **R5** — WHEN a *running* container already holds the sync name, the system SHALL NOT
  remove or kill it, and SHALL create no new container.
- **R6** — WHEN no namesake exists, the system SHALL issue exactly **one** docker
  invocation (the spawn).
- **R7** — The reconcile SHALL NOT use `docker rm -f`.
- **R8** — `.mcp.json` SHALL pin atomos at the digest the lockfile records for the
  catalogue's `pins.stable` (0.2.0, `sha256:b3f67b4e…`), serving 4 tools.
- **R9** — All changed shell SHALL remain bash 3.2 compatible and fail-open on the hot path.

## Acceptance checks

| # | Check | Red-before |
|---|---|---|
| AC-1 | 40 concurrent `context status` write-pairs of differing length → **0** corrupt meters (`jq empty` passes every time) | currently 9/40 corrupt |
| AC-2 | A corrupt `meter.json` seeded on disk → next `context status` **overwrites it** and emits a valid meter with the correct zone | currently wedged forever |
| AC-3 | Common case (no namesake) → exactly **one** docker invocation | currently 2 (`ps -a` + `run`) |
| AC-4 | `Created` namesake → exactly one `rm`, then a successful spawn (self-heal in one turn) | currently skipped forever |
| AC-5 | `running` namesake → `rm` issued and **refused**; **zero** containers created; the running container survives | n/a |
| AC-6 | The reap command line never contains `-f` (literal grep) | n/a |
| AC-7 | The spawn command line contains `--user` | currently absent → EACCES |
| AC-8 | `.mcp.json` atomos digest == lockfile atomos digest (lock/artifact reconciliation) | currently mismatched |
| AC-9 | `make lint` (shellcheck -S error) clean; bash-3.2 source grep clean | must stay green |

## Test-gate replacement (mandatory — the current gate is complicit)

`setup_fake_docker_autosync` (`cli/tests/harness.bats:2587`) is **state-blind**: its
`docker ps` echoes `FAKE_DOCKER_RUNNING_NAME` regardless of `-a`, filters, or state, and
its `docker run` **always exits 0** — it can never simulate a name collision, and it has
no `rm` case. `docker ps` and `docker ps -a` are indistinguishable to it. That is why the
`-a` bug shipped green, and a fix landed against this shim would ship green too.

The replacement shim MUST model the daemon's **name registry + container state**
(`FAKE_DOCKER_EXISTING_NAME` + `FAKE_DOCKER_EXISTING_STATE`), with `run` returning a
non-zero conflict rc on a name collision and `rm` refusing when state is `running`.

**Every AC above must be demonstrated RED against the pre-fix code before it counts as a
gate.** A test that passes on both the broken and fixed code is not a gate.

## Out of scope

- The `running`-forever indexer (deadlocked index) is not reaped. Correct owner is a
  lease/deadline **inside atlas-aci**, not a kill-timer in the hot-path hook.
- The never-killed backgrounded spawn (fully orphan-proof create) — needs a
  hook-grandchild-survival experiment on Claude Code *and* Codex first. The 3 s bound is
  the cheap 80%.
- Lock-vs-artifact reconciliation as a general `eidolons mcp` verb (D3 is fixed for
  atomos here; the systemic gap is filed separately).

## Reversal conditions

- Measured container-create latency routinely exceeds 3 s → move to the backgrounded
  never-killed spawn.
- A `running` sync container is observed hanging indefinitely → add a lease inside
  atlas-aci (not a hook-side kill timer).
- podman/colima becomes supported and its `rm` does not refuse running containers → the
  reconcile needs an explicit state check and the safety argument must be re-derived.
