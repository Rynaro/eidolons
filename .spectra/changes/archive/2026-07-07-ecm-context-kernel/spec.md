---
eidolon: RAMZA
kind: spec
version: 0.1.0
created_at: 2026-07-07T00:00:00Z
change_id: ecm-context-kernel
esl_status: deliberated
tier: full
maker: vivi
checker: kupo
---

# ECM P1 — Context-Lifecycle Kernel + Claude Code Hook Recipes

> Implementation spec (ESL `specify` hop) for **ECM P1**. Consumes the six FORGE
> verdicts D1–D6 (`deliberation.md`) as SETTLED constraints, the ATLAS scout
> surface (`scout-harness-surface.md`, FINDING/GAP anchored), and the verified
> host facts (`evidence-host-facts.md`). Design source: `docs/specs/ecm/spec.md`
> (v0.1, §9 verdicts) + `docs/specs/ecm/policy.yaml`.
>
> **Produced via RAMZA parallel-spec (TRANCE G3):** 4 perspective-diverse
> candidate decompositions scored through `ramza-score` (bias-hardened:
> identity-strip, order-rotate, length-normalize, deterministic-anchor on
> file-disjointness + scout-FINDING reuse), judge-merged into one. Winner
> "verb-family-parallel" 83/100 (solid); grafts from three losers recorded in
> §Rejected Alternatives.

## Scope

**In (P1):** the `eidolons context status|policy|externalize|handoff` verb
family (two-tier dispatch: `context.sh` + `context_<sub>.sh`); `meter.json`
writer with D1's 3-rung estimation ladder; policy evaluator over
`roster/context-policy.yaml` (promotes+trims `docs/specs/ecm/policy.yaml`);
`policy-log.jsonl` + `budget-ledger.jsonl` (D3 shape); `externalize` with the
`crystalium_ingest`-canonical path + file floor (D5); `handoff` composer (D4:
advisory 1500 target never truncate, ≤200-token digest); Claude Code harness
recipes (SessionStart matcher `compact` → pin re-inject + handoff digest;
UserPromptSubmit → meter/verdict inject ≤200 tokens; PostToolUse → sidecar
refresh, inject only on zone change; `compactThreshold: 75` jq-merge
don't-clobber per D6); `eidolons.lock` `context:` recording (awk idiom) +
`schemas/eidolons.lock.schema.json` coverage (GAP-003); `roster/pins.yaml`
default set; `cli/tests/context.bats`; handoff round-trip canary INCLUDING the
D5 quarantine-vs-recall regression.

**Out (P1):** other hosts (P2), external spec repo + atomos (P3), cortex
§Context-protocol prose (separate docs-only change). No PreCompact anchor
(evidence C1 UNVERIFIED — externalization is amber-zone-eager, not
pre-compaction-hooked).

**Deferred / anti-scope (unchanged from FORGE):** ECM never re-declares
CRYSTALIUM layers/tiers, never extends ECL's ten performatives, never
re-implements host compaction. `atomos` builds NOTHING at P1 (D2).

## Approach

**Merged decomposition (judge-merge of 4 candidates):** slice by verb-family
file-disjointness (winner backbone) so each `context_<sub>.sh` is an independent
Vivi worktrace; sequence the shared substrate (dispatcher + `lib_context.sh`)
first and the shared harness/lock files last (dependency-serial graft); elevate
the D5 quarantine-vs-recall canary to a first-class early track (canary-first
graft); phrase acceptance criteria around observable per-verb capability
(capability-sliced graft). Every verb reuses a proven nexus idiom verbatim:
`mcp.sh` two-tier dispatch, `run.sh` single-jq-heredoc-over-`yaml_to_json`,
`memory preflight --query` reuse, `harness_install.sh` jq-merge + awk-lock
idioms, `harness.bats`/`memory.bats` test conventions.

### Tracks (execution units; PARALLEL = file-disjoint, worktrace-safe)

| Track | Title | Files (drift-fenced) | Depends on | Parallel? |
|---|---|---|---|---|
| **T-A** | Dispatch scaffold + shared lib | `cli/eidolons` (`context)` case), `cli/src/context.sh`, `cli/src/lib_context.sh` | — | SEQUENCE FIRST (blocking substrate) |
| **T-G1** | Config promotion | `roster/context-policy.yaml`, `roster/pins.yaml`, `schemas/eidolons.lock.schema.json`, `schemas/eidolons.yaml.schema.json` | — | PARALLEL with T-A (no code dep) |
| **T-B** | `context status` — meter writer | `cli/src/context_status.sh` | T-A | **PARALLEL** |
| **T-C** | `context policy` — evaluator | `cli/src/context_policy.sh` | T-A, T-G1 | **PARALLEL** |
| **T-D** | `context externalize` — crystalium + floor | `cli/src/context_externalize.sh` | T-A | **PARALLEL** |
| **T-E** | `context handoff` — composer | `cli/src/context_handoff.sh` | T-A | **PARALLEL** |
| **T-F** | Harness recipes + lock recording | `cli/src/harness_install.sh`, `cli/src/harness_hook.sh`, `cli/src/run.sh` | T-B…T-E | SEQUENCE AFTER verbs (shared files) |
| **T-H** | Tests + canary (D5 ⚠) | `cli/tests/context.bats`, `cli/src/canary.sh`, `.github/workflows/ci.yml` | all | START EARLY vs frozen criteria; finalize last |

**Sequencing:** Phase 1 = {T-A, T-G1}. Phase 2 = {T-B, T-C, T-D, T-E}
concurrent worktraces. Phase 3 = T-F. Phase 4 = T-H (skeleton authored in
Phase 1 against these frozen criteria, filled as verbs land).

## Stories (per-file plan, path:line anchored from the scout)

### Story S-A — Dispatch scaffold + `lib_context.sh` (T-A)
- **`cli/eidolons`** — add a `context)` case that `exec bash "$CLI_SRC/context.sh" "$@"`,
  modeled on the `mcp)` case (cli/eidolons:262-297) and the `memory)` case
  (cli/eidolons:299-308). Peel the sub-token, delegate.
- **`cli/src/context.sh`** — two-tier sub-dispatcher mirroring `mcp.sh:47-79`:
  `case "$subcmd" in status) exec .../context_status.sh; policy) …; externalize) …;
  handoff) …; -h|--help) usage; *) die`. Header block copies the bash-3.2
  disclaimer verbatim (FINDING-005) + `set -euo pipefail` + `SELF_DIR`/`. lib.sh`
  (FINDING-004).
- **`cli/src/lib_context.sh`** — shared helper (precedent: `lib_memory_probe.sh`):
  `context_sidecar_dir()` → `mkdir -p .eidolons/.context` (FINDING-026, fail-soft
  variant for best-effort writes); `context_zone_of(util)` → green/amber/red/critical
  band map (coarse 25-pt bands, CC8); `context_meter_read/write`; signal extraction
  for the policy `$ctx`. All log via stderr (FINDING-029); stdout reserved for
  machine output. No `.gitignore` change needed — `.eidolons/.context/` is covered
  by the existing blanket rule (FINDING-027).
- Executor hint: Opus-tier goals+constraints; the shared lib is the single
  contract every verb imports — get its function signatures right first.

### Story S-B — `context status` meter writer (T-B) — AC-1, AC-6, AC-7
- **`cli/src/context_status.sh`** — D1 3-rung estimation ladder:
  (1) host telemetry where present (Claude Code statusline JSON
  `context_window.used_percentage`, evidence C4 → `estimate_source=host`, exact,
  no estimation); (2) transcript `bytes/4` heuristic where a `transcript_path`
  exists (C7, all hook payloads) — `wc -c` + jq, inside the 300 ms budget (CC3);
  (3) no transcript + no telemetry → `zone: unknown` → policy `continue`
  (fail-open floor, CC2). Writes the `meter.json` sidecar (spec §3.1 shape):
  `utilization`, `zone`, `estimate_source`, `tool_result_share_est`,
  `compaction_count`, `budget`, `updated_at`. Subagent sessions key the file
  `meter-<session_id>.json` (D3). Never blocks; failure → `zone: unknown`.
- Executor hint: the bytes/4 divisor is a NAMED constant (`ECM_BYTES_PER_TOKEN=4`)
  so the canary's divisor-bias measurement (D1) can flip it to 3.5 without a
  code hunt.

### Story S-C — `context policy` evaluator (T-C) — AC-2, AC-7, AC-13
- **`cli/src/context_policy.sh`** — copy `run.sh`'s shape (FINDING-016/017):
  `yaml_to_json roster/context-policy.yaml` once → ONE named jq heredoc
  (`read -r -d '' POLICY_JQ <<'JQ' … JQ`) reading `meter.json` as the `$ctx`
  argjson (analogous to `run.sh`'s `$CTX_JSON`, run.sh:163-169) → first-match-wins
  over rows P1–P7. No shell-side per-row branching — all conditionals inside jq.
  `--json` emits the verdict to stdout; every evaluation appends a signal-snapshot
  line to `.eidolons/.context/policy-log.jsonl`. Subagent policy tables remap
  `handoff_fresh`/`wrap_up` → `finish_and_return` (D3); the P1 budget-ceiling row
  is evaluated ONLY in the orchestrator session (D3). `zone: unknown` → P7 continue.
- **`roster/context-policy.yaml`** — promoted+trimmed from `docs/specs/ecm/policy.yaml`
  (drop the design-comment prose, keep `zones`/`limits`/`rules`/`operations`/
  `pins`/`audit`/`subagents`). This is the single source of truth the evaluator
  reads (T-G1 owns the file; T-C owns the reader).

### Story S-D — `context externalize` (T-D) — AC-3, AC-16, AC-14
- **`cli/src/context_externalize.sh`** — drives the D5 canonical persist chain:
  `crystalium_plan_checkpoint` → `crystalium_commit(episodic, identifier manifest:
  path:line anchors, symbols, decision IDs, failed-approach log, open vars)` →
  `crystalium_ingest(ecl_envelope)` when an envelope exists (canonical, D5 — no
  commit-fallback BRANCH for the handoff artifact; commit here is the identifier
  manifest, a distinct payload). Provenance carries `contains_tool_origin: true`
  whenever T3 content was in scope (Gap G3). **Degradation (AC-3):** crystalium
  absent → warn once, write file floor `.eidolons/.context/externalized-<ts>.json`,
  continue; 1.5 s timeout → skip, never block (CC2, memory_timeout_ms). Budget
  records append to `.eidolons/.context/budget-ledger.jsonl` (append-only JSONL,
  D3/AC-14 — concurrent fan-out-5 safe; a mutable shared file is a defect).
- Reuse `lib_memory_probe.sh`'s docker-transform pattern (FINDING-011/012) for the
  one-shot ingest invocation. [ASSUMPTION carried from D5] one-shot out-of-MCP
  ingest is buildable at P1 — `memory.sh` currently implements recall only; new
  plumbing either way.

### Story S-E — `context handoff` composer (T-E) — AC-4, AC-8, AC-16
- **`cli/src/context_handoff.sh`** — compose `.eidolons/.context/handoff-<ts>.md`
  (D4: 1500-token ADVISORY target — overflow warns + logs size to policy-log,
  NEVER truncates; sections ordered by survival priority: identifiers →
  failed-approaches → next-steps → narrative). Emit the `ecl-envelope.json`
  sidecar (performative `INFORM`, artifact type `ecm/handoff-brief@0.1`, SHA-256
  integrity, `thread_id` continuity — reuse the existing envelope schema, no new
  performative, CC5). Persist via `crystalium_ingest` with reserved
  `topic_key: session_handoff` (D5 canonical). The ≤200-token DIGEST is a distinct
  artifact injected once at successor SessionStart via `eidolons memory preflight
  --query "<session_handoff query>"` (FINDING-015 — reuse verbatim, no new docker
  plumbing); the full brief is recalled/read on demand, never per-prompt injected
  (D4 two-injection-classes resolution of the C-4 tension).
- Layer set unchanged: `memory.sh`'s `--layers semantic,episodic,procedural`
  (FINDING-012) already lands `session_handoff` at T1 episodic — no change (D5).

### Story S-F — Harness recipes + lock recording (T-F) — AC-5, AC-10, AC-11, AC-12
- **`cli/src/harness_hook.sh`** — extend the SessionStart payload (already
  post-compact-aware via matcher `compact`, FINDING-008) with a `## Context policy`
  block: pin re-inject + handoff digest (append to the existing string-composition
  at harness_hook.sh:147-184, bounded). Extend UserPromptSubmit (harness_hook.sh:194-267)
  with a meter-zone + policy-verdict line, hard-bounded ≤200 tokens (AC-12,
  cut-cNNN idiom already present at :270). PostToolUse: refresh the meter sidecar
  cheaply, inject additionalContext ONLY on zone transition (evidence C6).
- **`cli/src/run.sh`** — add a PostToolUse hook mode alongside `--session-start`
  (run.sh:87-93) and `--stdin` (run.sh:95-112); it refreshes `meter.json` and
  emits injection only when the zone changed. Fail-open wrapper (`_main 2>/dev/null || true`).
- **`cli/src/harness_install.sh`** — (a) register a PostToolUse shim via the
  existing jq-merge idiom (harness_install.sh:634-701 template) — SessionStart +
  UserPromptSubmit need NO new registration (matcher already covers `compact`,
  FINDING-008), only payload extension in harness_hook.sh; (b) write
  `compactThreshold: 75` to `.claude/settings.json` via the same jq-merge
  canonical-compare (FINDING-007) with **don't-clobber** (D6): absent → write +
  `managed: true`; present-and-different → leave + warn + `managed: false`
  (AC-10/AC-11); (c) record a `context:` block in `eidolons.lock` (ECM version,
  effective host tier, resolved thresholds, `compactthreshold_managed`) via the
  awk-strip-and-regenerate idiom keyed on `/^context:/` (FINDING-019/020, exact
  analog of the `harness:` block). Idempotent: second run byte-identical (AC-5).
- [GAP carried from D6] verify exact `compactThreshold` key spelling/semantics
  live before writing the merge branch (evidence C5 PARTIAL); the don't-clobber +
  lock-record design is invariant to the field's spelling.

### Story S-G — Config + schema (T-G1) — AC-15, AC-17
- **`roster/pins.yaml`** — the default pin set (spec §3.2): cortex routing digest,
  active refusal table, ESL enforcement mode, crystalium trust-tier map, active
  plan step + criteria SHA-256, session budget + compaction count. Consumers may
  append (`pins_extra`), never shrink. Pins never include T3-origin content.
- **`schemas/eidolons.lock.schema.json`** — add an optional `context:` property
  (GAP-003 RESOLVED: the lock schema's `required` is `[generated_at,
  eidolons_cli_version, members]` and `additionalProperties` is unset — the
  existing `harness:` key is already permitted only because additionalProps is
  open; adding `context:` as a declared optional property makes coverage explicit
  and keeps `make schema` green, AC-17).
- **`schemas/eidolons.yaml.schema.json`** — add the optional consumer `context:`
  block (spec §7: `enabled`, `thresholds`, `compaction_depth_cap`, `budget_tokens`,
  `pins_extra`). Absent block ⇒ ECM off (AC-15, opt-in, additive — same class as
  the existing `hosts:` block, FINDING-022).

### Story S-H — Tests + canary (T-H) — AC-1..AC-17 verification, AC-4, AC-9
- **`cli/tests/context.bats`** — follow `harness.bats`/`memory.bats` conventions
  (FINDING-030-034): `load helpers`; a LOCAL `seed_lock_with_context` helper
  (do NOT edit shared `helpers.bash`, FINDING-031); `# ─── P<N> / AC-<N> ───`
  block headers; fail-open shim test technique (harness.bats:16). One test per
  AC VERIFY line.
- **`cli/src/canary.sh`** — add a `--context-handoff` mode reusing the `--memory`
  round-trip machinery (canary.sh:548-640, capability-probe + docker-transform):
  write a `session_handoff` brief in "session N", recall by envelope SHA-256 in
  "session N+1" (AC-4). **MUST include the D5 ⚠ regression (AC-9):** a
  `contains_tool_origin: true` brief must still surface on default recall — if
  quarantine excludes it, the round-trip breaks whenever a session touched tool
  output (nearly always). Remedy on failure = a scoped recall flag for
  `session_handoff` records, NOT a switch to `commit` (D5 reversal-condition).
- **`.github/workflows/ci.yml`** — wire the `--context-handoff` canary next to the
  existing crystalium memory parity/canary check (ci.yml:60 region), smoke-gated
  like `live-eval.yml`'s plumbing canary.

## Acceptance Criteria

The frozen criteria set is `acceptance-criteria.md` (17 blocks, EARS-linted:
`ramza-ears-lint` → `ok: 17 criteria pass`). Summary map:

| AC | Track | Verdict lineage | VERIFY |
|---|---|---|---|
| AC-1 | T-B | meter + zone, exit 0, bash 3.2 | bats |
| AC-2 | T-C | policy determinism (P1–P7) | bats |
| AC-3 | T-D | file-floor when crystalium absent, never blocks | bats |
| AC-4 | T-H | handoff round-trip by SHA-256 (N→N+1) | canary |
| AC-5 | T-F | harness install idempotent byte-identical | bats |
| AC-6 | T-B | D1 rung-1 host telemetry preferred | bats |
| AC-7 | T-B/T-C | D1 rung-3 unknown→continue fail-open | bats |
| AC-8 | T-E | D4 advisory 1500 target, never truncate | bats |
| AC-9 | T-H | **D5 ⚠ quarantine-vs-recall (tool-origin)** | canary |
| AC-10 | T-F | D6 don't-clobber existing compactThreshold | bats |
| AC-11 | T-F | D6 write 75 + managed=true in lock | bats |
| AC-12 | T-F | C-4 injected artifact ≤200 tokens | bats |
| AC-13 | T-C | D3 subagent handoff_fresh→finish_and_return | bats |
| AC-14 | T-D | D3 budget-ledger append-only JSONL | bats |
| AC-15 | T-G1 | opt-in: absent context block ⇒ off | bats |
| AC-16 | T-E | D5 crystalium_ingest canonical, no commit branch | bats |
| AC-17 | T-G1 | GAP-003 lock schema covers context | bats |

## Test Plan

- **Structural:** `ramza-lint` (this spec) + `ramza-ears-lint acceptance-criteria.md`.
- **Kernel unit (bats):** `cli/tests/context.bats` per AC table; `make test-file
  F=cli/tests/context.bats`; determinism check runs `context policy` twice on a
  frozen `meter.json` fixture and diffs (AC-2).
- **Idempotency:** second `harness install` run diffed byte-for-byte (AC-5); the
  CI "Second install run is idempotent" job pattern applies.
- **Fail-open:** minimal shim → nonexistent path → assert exit 0 + empty stdout
  (harness.bats:16 technique), for the PostToolUse shim.
- **Round-trip canary (AC-4, AC-9):** `eidolons canary --context-handoff` in CI,
  MUST carry a `contains_tool_origin: true` brief.
- **Lint/schema:** `make lint` (shellcheck -x -S error on new `context*.sh`),
  `make schema` (jq empty schemas + yq eval) after the `context:` additions.

## Drift Fence (files Vivi may touch)

The declared execution scope (`ramza-drift --declare`). Anything changed outside
this list post-handoff is DRIFT:

```
cli/eidolons
cli/src/context.sh
cli/src/context_status.sh
cli/src/context_policy.sh
cli/src/context_externalize.sh
cli/src/context_handoff.sh
cli/src/lib_context.sh
cli/src/harness_install.sh
cli/src/harness_hook.sh
cli/src/run.sh
cli/src/canary.sh
roster/context-policy.yaml
roster/pins.yaml
schemas/eidolons.lock.schema.json
schemas/eidolons.yaml.schema.json
cli/tests/context.bats
.github/workflows/ci.yml
CHANGELOG.md
```

Explicitly OUT of fence (drift if touched): `cli/tests/helpers.bash` (use a LOCAL
seed helper, FINDING-031), `docs/specs/ecm/spec.md` (§9 settled; D2/D4 spec-text
edits are a separate docs change), `EIDOLONS.md`/cortex prose (P-out),
`.gitignore` (no change needed, FINDING-027), any `cli/src/mcp*.sh` or
`cli/src/memory.sh` (read as precedent, never edited).

## Rejected Alternatives (parallel-spec losers + per-dimension grafts)

- **canary-first (69, weak)** — build the D5 canary before the verbs. Rejected as
  the backbone: writing the canary against absent verbs churns it (correctness 7).
  **Grafted:** its risk insight (9) → T-H elevated to a first-class EARLY track and
  the D5 ⚠ gets a dedicated criterion (AC-9).
- **dependency-serial (69, weak)** — one serial chain, no worktraces. Rejected:
  ignores the mission's parallel-worktrace requirement (performance 5).
  **Grafted:** its simplicity (8) → the SHARED files (dispatcher, `lib_context.sh`,
  harness, lock, schema) are SEQUENCED (Phase 1 and 3), not parallelized.
- **capability-sliced (63, weak)** — slice by observable capability, cross-cutting
  files. Rejected: cross-cutting touches break worktrace disjointness (performance
  5, maintainability 6). **Grafted:** its cohesion (innovation 8) → acceptance
  criteria are phrased around observable per-verb capability.

Per-dimension provenance of the merge (`[DECISION]`): alignment/maintainability/
performance ← verb-family-parallel (9/9/9); correctness ← verb-family (8, ties
dependency-serial); simplicity ← dependency-serial graft (shared-file sequencing);
risk ← canary-first graft (early D5 track); innovation ← capability-sliced graft
(capability-framed criteria).

## Risks

| Risk | Sev | Mitigation | Lineage |
|---|---|---|---|
| D5 quarantine excludes tool-origin briefs from default recall → round-trip breaks nearly always | P0 | AC-9 canary MUST carry a `contains_tool_origin:true` brief; remedy = scoped recall flag, not `commit` | D5 ⚠ 81% |
| `compactThreshold` key spelling/semantics differ from "percentage 0–100" | P1 | verify live before writing the merge branch; don't-clobber design is spelling-invariant | D6 GAP 80% |
| bytes/4 systematically underestimates on code (errs late) | P1 | named `ECM_BYTES_PER_TOKEN` constant; canary pre-registers divisor-bias (4 vs 3.5); RED boundary compensates | D1 86% |
| One-shot out-of-MCP `ingest` not buildable at P1 (`memory.sh` is recall-only today) | P1 | reuse `lib_memory_probe.sh` docker transform; file floor is the guaranteed fallback | D5 ASSUMPTION |
| Subagent hooks may not fire on the host → ledger under-counts | P2 | fail-open: unmetered subagent → unknown→continue + dispatch-count estimate | D3 GAP |
| Shared-file collision on T-F (harness/run/install interlock) | P1 | T-F is a SINGLE sequenced track, never split into worktraces | merge design |

## Rollback

Opt-in and additive throughout (P0-1). Rollback = revert the drift-fenced files;
`.eidolons/.context/` is gitignored runtime state (delete freely). The
`context:` lock block and `.claude/settings.json compactThreshold` are removable
by re-running `harness install` after the revert (don't-clobber leaves a
user-set value untouched) or by `eidolons remove`. No migration, no destructive
op, no external spend — checker-handoff `requires_checker: false` (FORGE gate
record).

## Confidence & Gaps

Evaluator confidence and the frozen criteria SHA-256 are recorded in
`spec.yaml` + `plan-state.json`. RAMZA-side open items:
- **[GAP]** exact `compactThreshold` settings-key semantics (D6, evidence C5
  PARTIAL) — a P1 live-verify precondition, not a spec blocker.
- **[GAP]** one-shot out-of-MCP `crystalium_ingest` buildability (D5 ASSUMPTION);
  file floor bounds the downside.
- **[GAP]** subagent hook-firing/token-visibility per host (D3) — P1 probe;
  fail-open floor bounds it.
- No **[DISPUTED]** items — all six FORGE verdicts consumed as settled; the
  parallel-spec merge reached 3-of-4 differentiation with a clear 83-vs-69 winner.
