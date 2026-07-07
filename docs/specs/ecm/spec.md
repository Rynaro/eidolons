# Spec: ECM — Eidolons Context Management (v0.1 draft)

> **Status:** Draft (design brief, decision-ready — pre-ESL `propose`)
> **Target:** new sibling spec to EIIS / ECL / ESL, plus nexus kernel verbs + hook recipes
> **Evidence base:** `research/context-lifecycle-survey-2026-07.md` (tri-cycle survey, S/A-tier anchored) + `DOSSIER-HARNESS-2026-06.md` (hook-surface matrix, inject-by-default verdict)
> **Companion machine-readable policy:** [`policy.yaml`](./policy.yaml)
> **Naming:** spec = **ECM** (dry acronym family: EIIS/ECL/ESL/ECM). Optional
> implementation MCP (P3) = **atomos** (swallows and transports — eviction +
> offload), tonberry-analog. Both names are swappable until the external repo is cut.

---

## 1. Overview

### 1.1 What we're building

**ECM governs the context economy of a running Eidolons session**: how the
session measures its context, when it externalizes state to memory, when and how
it compresses (compaction), when it abandons the window entirely (handoff-fresh),
and how all of that happens **autonomously — mechanically, without a human
present to notice degradation and intervene.**

It is the fourth sibling spec:

| Spec | Governs | One line |
|---|---|---|
| EIIS | install layout | how an Eidolon lands in a project |
| ECL | wire format | how Eidolons talk to each other |
| ESL | spec lifecycle | how changes move from proposal to archive |
| **ECM** | **context lifecycle** | **how a session stays small, cheap, and coherent over time** |

ECM is a thin contract over things that already exist: the deterministic kernel
(`eidolons run`), the hook adapters (`eidolons harness install`), CRYSTALIUM's
8-tool surface, ECL envelopes, and the hosts' own compaction machinery. It adds
**no LLM-discretionary behavior** — every trigger is a mechanical gate over
observable signals, in the same doctrine as ESL's right-sizing gate.

### 1.2 Why now

Three forces, all measured (survey F1–F8):

1. **Context rot is threshold-governed and starts at ~50% utilization** — long
   autonomous chains (TRANCE campaigns, sandbox loops, nightly canaries) degrade
   *silently* long before any host emergency compaction fires at 95%.
2. **Compaction is lossy in exactly the way that hurts us most** — identifiers
   (paths, symbols, criteria SHAs, plan state) and *instructions* (refusal
   tables, enforcement modes) are what lossy summarization drops (ACL 2026
   pitfall class). Our entire methodology is instructions and identifiers.
3. **Autonomous operation has no human backstop.** When a chain runs overnight,
   nobody is around to notice the orchestrator contradicting its own earlier
   decisions and `/clear` it. The decision to compact / handoff / wrap up must be
   a hook-fired mechanical policy, not a hope.

The mechanization substrate shipped in the harness campaign: hooks exist on all
five hosts, the kernel exists, memory pre-flight exists. ECM is the missing
policy layer on top.

### 1.3 Scope

- A **spec** (this document → external repo `Rynaro/eidolons-ecm` at v1.0):
  meter format, zone ladder, closed operation set, decision table, pin-set
  contract, externalize-before-compact contract, handoff-brief artifact,
  budget accounting, conformance rules.
- **Kernel verbs** (`cli/src/context*.sh`): `eidolons context status|policy|externalize|handoff`
  — pure bash 3.2 + jq, non-LLM, table-driven from `policy.yaml`.
- **Hook recipes** added to `eidolons harness install`: PreCompact-class →
  externalize + pin re-inject; SessionStart-class → handoff recall + pin inject;
  prompt/tool-boundary → meter refresh + policy verdict inject.
- **CRYSTALIUM conventions** (additive, no schema change at P1): a reserved
  `topic_key: session_handoff`, provenance flag `contains_tool_origin`,
  handoff-fresh = brief → `session_end` → successor pre-flight recall.
- **Cortex documentary floor**: a new always-loaded §"Context protocol" block in
  `EIDOLONS.md` (≤ 120 tokens of the ≤ 900 budget) + deep table
  `methodology/cortex/context-protocol.md`.

### 1.4 Non-goals (out of scope, permanently or for v1.0)

- **KV-cache compression, serving-stack work, provider internals.** Eidolons is
  host-mediated; PagedAttention/KVzip/LMCache-class machinery belongs to
  providers and serving stacks. ECM observes that literature only for its
  failure modes (pin set) and its caching contract (prefix stability). A
  deployment note for self-hosted junction loops is documentation, not spec.
- **Re-implementing compaction.** ECM *triggers and brackets* the host's own
  compaction (hook + `/compact` + API compaction); it never generates summaries
  itself in v1.0.
- **Extending ECL.** The performative set is closed at ten (ECL P0). The handoff
  brief travels as an existing performative (`INFORM`) with an ECM artifact type
  — never a new performative.
- **Re-declaring CRYSTALIUM.** ECM names *when* to externalize; crystalium owns
  layers, tiers, gates, consolidation. Anti-scope discipline identical to ESL's.
- **A learned/optimizing policy.** Survey Gap G1 (no formal cost model) is
  answered with a deterministic table, not an optimizer. Revisions to the table
  go through ESL like any spec change.
- **Blocking on context signals.** Advisory-first everywhere; the only hard stop
  is the budget ceiling's graceful wrap-up, and even that emits artifacts rather
  than killing the session.

---

## 2. OWNS / DEFERS (anti-scope table)

| Concern | ECM | Deferred to |
|---|---|---|
| Meter format, zone ladder, thresholds | **OWNS** | — |
| Closed operation set + decision table | **OWNS** | — |
| Pin-set contract + post-op verification | **OWNS** | — |
| Externalize-before-compact obligation | **OWNS** (the *when*) | CRYSTALIUM (the *where/how*: layers, tiers, gates) |
| Handoff-brief content schema | **OWNS** | ECL (envelope, integrity, transport), CRYSTALIUM (persistence) |
| Compaction execution | — | Host (PreCompact/`/compact`/API compaction) |
| Prefix-stability obligations on generated files | **OWNS** (names the invariant) | Nexus sync idempotency + marker invariants (already enforced) |
| Hook dialects, tier degradation | — | Harness kernel (`eidolons run --hook`, DOSSIER-HARNESS ladder) |
| Change lifecycle for ECM itself | — | ESL |
| Budget ceiling + wrap-up trigger | **OWNS** | — |

---

## 3. The five mechanisms

### 3.1 Meter — deterministic context telemetry

A sidecar artifact (ECL doctrine: **sidecar-on-disk, never in-context-only**)
at `.eidolons/.context/meter.json`, refreshed by the kernel at hook firings:

```json
{
  "ecm_version": "0.1",
  "session_id": "<host session id or kernel-derived>",
  "window_tokens": 200000,
  "used_tokens_est": 91400,
  "utilization": 0.457,
  "estimate_source": "host | transcript_heuristic",
  "zone": "green",
  "tool_result_share_est": 0.31,
  "compaction_count": 0,
  "externalize_age_turns": 4,
  "budget": { "ceiling_tokens": null, "spent_tokens_est": 91400 },
  "updated_at": "<iso8601>"
}
```

- **Estimation ladder:** host-provided counts where a host exposes them
  (statusline/hook payloads — T3 hosts); `bytes/4` transcript heuristic
  otherwise. Zone boundaries are coarse (25-point bands) precisely so a ±10%
  estimate cannot mis-zone by more than one band.
- **Zone ladder** (survey F1): `green < 0.50 ≤ amber < 0.75 ≤ red < 0.90 ≤ critical`.
- Meter computation is pure bash+jq, ≤ 300 ms, and **never blocks** — failure
  degrades to `zone: unknown`, which the policy maps to `continue` (advisory
  systems fail open; DOSSIER-HARNESS rule).

### 3.2 Pin set — what must survive every lossy operation

`pins.yaml` (nexus ships defaults; consumer projects may extend, never shrink,
the default set):

| Default pin | Why |
|---|---|
| Cortex routing digest | Routing dies silently without it (measured: DOSSIER-HARNESS §1) |
| Active Eidolon's refusal table | ACL 2026 pitfall class: lossy ops drop instructions first |
| ESL enforcement mode (tonberry `enforcement`) | Advisory-vs-block posture must not flip mid-session |
| Crystalium trust-tier map (T0/T1/T3) | Tier confusion after compaction = quarantine bypass |
| Active plan step + frozen criteria SHA-256 | RAMZA's criteria freeze is meaningless if the SHA doesn't survive |
| Session budget ceiling + compaction count | The policy's own inputs must survive the operations they trigger |

Mechanics: pins are re-injected via the post-compaction hook surface
(SessionStart `source=compact` class); a post-op **verification probe** greps the
injected artifact for pin markers and repairs by re-injection on miss. Advisory,
never blocking. Pins **never include T3-origin content** (Gap G3 posture).

### 3.3 Externalize-before-compact — the crystalium contract

Before any lossy operation (compact, handoff, clear), the kernel drives:

1. `crystalium_plan_checkpoint` — current plan state under the chain's `plan_id`
   (execution layer; idempotent per `(plan_id, step)`).
2. `crystalium_commit(layer=episodic)` — identifier manifest: `path:line`
   anchors, symbol names, decision IDs, failed-approach log, open variables.
3. `crystalium_ingest(ecl_envelope)` — when a hand-off envelope exists for the
   current chain step (primary persist path; provenance preserved).

Provenance carries `contains_tool_origin: true` whenever T3 content was in
session scope — the summary that survives compaction was generated *from* mixed
trust and must not launder it (Gap G3). Dream's corroboration gate already
guards promotion; ECM adds only the flag.

**Degradation:** crystalium absent → warn once, write the identifier manifest to
`.eidolons/.context/externalized-<ts>.json` as the file-only floor, continue.
Memory failures are never fatal (1.5 s timeout → skip; DOSSIER-HARNESS rule).

### 3.4 Handoff brief — session succession without a human

The fresh-start operation for autonomous chains. Artifact pair:

- `.eidolons/.context/handoff-<ts>.md` — structured brief: task state, decisions
  made (+ rationale one-liners), failed approaches (so the successor doesn't
  repeat them), open variables, exact identifiers (`path:line`), next steps,
  budget ledger.
- `ecl-envelope.json` sidecar — performative `INFORM`, artifact type
  `ecm/handoff-brief@0.1`, SHA-256 integrity, `thread_id` continuity.

Flow: externalize (§3.3) → compose brief → `crystalium_ingest` with reserved
`topic_key: session_handoff` → `crystalium_session_end` (Dream fires) →
successor session's memory pre-flight (`eidolons memory preflight`, already
hook-wired at SessionStart) recalls the latest `session_handoff` record and
injects it.

This closes survey Gap G2 with something **measurable**: a round-trip canary
(brief written in session N is recalled verbatim-by-hash in session N+1) that
can run in CI next to the existing crystalium memory canary.

### 3.5 Cache discipline — prefix stability as a named invariant

Provider caches key on exact prefix match; truncation-from-front halves hit
rates (survey F4). ECM names the obligations — most already hold in the nexus
and become *conformance points* rather than new work:

- **C-1** Stable-prefix ordering: cortex digest, agent files, tool definitions
  precede volatile content; per-prompt injections (meter digest, routing
  artifact) append at the end of the prompt-local region, never mutate the prefix.
- **C-2** Byte-stable generated sections: `sync` idempotency + marker-bounded
  blocks (existing invariants) are load-bearing for cache hits — a regenerated
  file with shuffled bytes is a full cache invalidation across every session in
  the project.
- **C-3** Never truncate-from-front. Reduction is host tool-result pruning,
  compaction, or handoff — all of which preserve the prefix.
- **C-4** Per-prompt injected artifacts ≤ ~200 tokens (bound the cache-miss cost
  of the volatile tail).

---

## 4. The decision table (autonomous policy)

Deterministic, table-driven (`policy.yaml`), evaluated by
`eidolons context policy --json` at hook firings. Observable signals only —
**never LLM-discretionary** (ESL right-sizing doctrine). First matching row wins.

| # | Condition (all conjuncts) | Operation |
|---|---|---|
| P1 | `budget.ceiling` set AND `spent ≥ ceiling` | **wrap-up**: externalize → handoff brief → stop gracefully |
| P2 | `zone = critical` | **handoff-fresh** (emergency externalize first; minimal manifest allowed) |
| P3 | `zone = red` AND `compaction_count < 2` | **externalize → compact** (host surface; pins re-injected post-op) |
| P4 | `zone = red` AND `compaction_count ≥ 2` | **handoff-fresh** (depth cap — survey F8/G4: no summary-of-summary beyond 2) |
| P5 | `zone = amber` AND `tool_result_share ≥ 0.40` | **prune tool results** (host-supported clearing) + externalize |
| P6 | `zone = amber` | **externalize** (checkpoint now, while cheap) + continue |
| P7 | `zone = green` or `unknown` | **continue** |

Lateral signals (evaluated by the orchestrator, not the kernel — they require
chain context): repeat-failure ≥ 3 on one step → the existing
`failed-attempt-recovery` chain (VIGIL) with a *fresh* context, not a compacted
one; independent subtask → subagent isolation (existing TRANCE/Kupo dispatch) —
ECM meters subagent economics but routing already owns the dispatch.

Every verdict is logged to `.eidolons/.context/policy-log.jsonl`
(signal snapshot + rule fired + operation taken) — the audit trail that a future
evidence-based revision of the table needs, and the honest answer to Gap G1:
we can't derive the optimal policy yet, so we make the current one deterministic,
auditable, and cheap to revise through ESL.

---

## 5. Host enforcement ladder

Same shape as DOSSIER-HARNESS §3; INJECT is the default posture, BLOCK never.

| Host | Tier | Surfaces | Notes |
|---|---|---|---|
| Claude Code | **T3** | SessionStart matcher `compact` → pin re-inject + handoff recall (fires immediately post-loss); UserPromptSubmit `additionalContext` → meter digest + policy verdict; PostToolUse → sidecar meter refresh (inject only on zone change); statusline JSON `context_window.used_percentage` → exact telemetry, no estimation; `compactThreshold`/`CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` set to the RED boundary | VERIFIED 2026-07-06 (`evidence-host-facts.md`): PreCompact NOT in documented hook set — externalization is amber-zone-eager (P5/P6) instead of pre-compaction-hooked [WATCH for a documented pre-compact surface] |
| Codex CLI | **T3** | UserPromptSubmit dual-mode inject; SessionStart inject | No PreCompact analog: policy fires at prompt boundary only [VERIFY] |
| Copilot | **T2** | hooks (exit-0-hardened) + instructions injection | Pending GAP-1 injection verdict from harness campaign |
| Cursor | **T2** | rules dual-write + tool-boundary hooks | No prompt-block ever (known bug) |
| OpenCode | **T1** | AGENTS.md documentary thresholds + plugin shim meter | — |
| any | **T0 floor** | Cortex §Context protocol prose | Status quo, never worse |

Effective tier recorded in `eidolons.lock` (additive field), reported by
`doctor --deep` next to the harness tier.

---

## 6. P0 — non-negotiable for v1.0

1. **Opt-in.** Projects without ECM remain conformant unchanged (family rule).
2. **Mechanical gates only.** Every trigger is a deterministic function of
   observable signals; no LLM-discretionary context decisions.
3. **Sidecar-on-disk** for meter, policy log, handoff brief — never in-context only.
4. **Pin set survives every lossy operation**; post-op verify + repair; advisory.
5. **Externalize-before-compact is mandatory when crystalium is installed**;
   file-floor + warn when absent. Never block on memory failure.
6. **Compaction depth cap = 2** per session; beyond it, handoff-fresh only.
7. **Anti-scope:** ECM never re-declares crystalium layers/tiers, never extends
   ECL's ten performatives, never re-implements host compaction, never touches
   serving-layer concerns.
8. **Bash 3.2-compatible** kernel verbs + conformance checker; stderr discipline;
   prompt-path ≤ 300 ms.
9. **Fail-open.** Telemetry or policy failure degrades to `continue` + warning;
   the only stop is the budget ceiling's *graceful* wrap-up.
10. **Every verdict is audited** (policy log with signal snapshot) — the table is
    revisable only through ESL with that evidence.

---

## 7. Consumer-project surface (additive)

`eidolons.yaml` gains an optional block (schema additive; absent = ECM off):

```yaml
context:
  enabled: true
  thresholds: { amber: 0.50, red: 0.75, critical: 0.90 }   # defaults; override down, not up past host limits
  compaction_depth_cap: 2
  budget_tokens: null            # session ceiling; null = no ceiling
  pins_extra: []                 # project pins appended to nexus defaults
```

`eidolons.lock` records: ECM version, effective host tier, resolved thresholds.

---

## 8. Roadmap

- **P0 (this change):** research ingest + this spec + `policy.yaml` + cortex
  documentary floor (§Context protocol, ≤ 120 tokens + deep table). ESL
  `propose` + FORGE deliberation on the two open decisions (§9).
- **P1 (kernel + T3):** `context status|policy|externalize|handoff` verbs;
  meter + policy log; Claude Code hook recipes in `harness install`;
  crystalium `topic_key: session_handoff` convention; handoff round-trip canary.
- **P2 (verification + Codex):** pin-set verification probe; `doctor --deep`
  context probes; Codex adapter; `eidolons.lock` + schema additions; bats suites.
- **P3 (externalization):** cut `Rynaro/eidolons-ecm` (spec + bash conformance
  checker, ESL-style); optional **atomos** MCP (compose/verify executor,
  tonberry-analog — only if hosts prove to need in-session composition; the
  kernel-verb path stays canonical per survey F6); T2/T1 hosts; CLAUDE.md +
  cortex §ECM shipped blocks.

## 9. Open questions — RESOLVED 2026-07-06

FORGE TRANCE G2 deliberation (`.spectra/changes/ecm-context-kernel/deliberation.md`;
D1–D4 at N=3 blind traces, 3/3 structural agreement; D5–D6 standard depth):

| ID | Verdict | Conf. |
|---|---|---|
| OQ-E1 (D1) | **3-rung estimation ladder**: host telemetry → transcript bytes/4 → unknown→continue. No tokenizer container, ever. Canary pre-registers the divisor-bias check (bytes/4 underestimates on code — errs *late*, so the red boundary compensates). | 86% |
| OQ-E2 (D2) | **Kernel+hooks is canonical and complete.** atomos stays P3-conditional behind an anti-scope fence written now — compose/verify only, never meter/policy/trigger — with a kill criterion: all-hosts canary PASS at P2 exit deletes it from the roadmap. | 90% |
| OQ-E3 (D3) | **Own meter per subagent session; one shared append-only `budget-ledger.jsonl`**; the ceiling is evaluated orchestrator-only. Subagent `handoff_fresh`/`wrap_up` verdicts remap to finish-and-return (subagents cannot spawn successors). | 85% |
| OQ-E4 (D4) | **1,500 tokens is an advisory composition target — the composer never truncates** (survey F2: truncation drops exactly what briefs exist to preserve). The *hard* bound applies only to the injected digest. C-4 tension resolved: two injection classes — per-prompt volatile tail (≤ 200) vs one-time SessionStart handoff digest; the full brief is recalled on demand, not injected. | 86% |
| GAP-004 (D5) | **`crystalium_ingest` of the ECL envelope is the canonical persist path** (no `commit` branch; file floor is the only fallback). `contains_tool_origin` survives both paths but only ingest *enforces* it. ⚠ P1 canary MUST cover the quarantine-vs-recall interaction: if flagged briefs are episodic-quarantined and default recall skips quarantined records, round-trip breaks whenever a session touched tool output. | 81% |
| GAP-002 (D6) | **`harness install` writes `compactThreshold: 75`** (RED boundary) into `.claude/settings.json` via the existing jq-merge — don't-clobber a user value, record in `eidolons.lock`. The env var stays a user-side override, never written by us. | 80% |
