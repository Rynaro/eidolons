---
eidolon: spectra
version: 4.11.0
kind: spec
status: ready-for-review
created_at: 2026-07-04T02:08:32Z
thread_id: 019f3008-d356-7578-b835-b386c4384835
target_repos:
  - "<unresolved — no deploy-command implementation found in /tmp/spectra-pilot (Eidolons scaffold only, no application source); see CLARIFY Gap-1>"
stories_count: 6
validation_gates_count: 18
evidence_anchors_count: 0
confidence: 0.75
---

# SPEC-2026-07-04-001 — `--dry-run` flag for the deployment command

**Mission:** Produce a decision-ready spec for adding a `--dry-run` flag to a deployment command, with user stories, validation/acceptance gates, and at least one rejected alternative.

**Methodology:** SPECTRA v4.11.0 — CLARIFY → Scope → Pattern → Explore → Construct → Test → Refine → Assemble
**Tier:** Standard (complexity 7/12 → extended-thinking budget; below the 10–12 TRANCE threshold, so this is a single-pass cycle, not parallel-spec/G3)
**Read-only invariant honored:** no code, no file edits to the target system were made in producing this spec.

---

## Memory pre-flight (mission intake)

Per `agent.md`, a `mcp__crystalium__recall` call was attempted before CLARIFY to surface prior specs/decisions/traps relevant to "dry-run flag" or "deployment command" work. **No `mcp__crystalium__*` tools are reachable in this environment** (not present in the available tool surface, no CRYSTALIUM install evidence in `/tmp/spectra-pilot`). Per the documented graceful-skip rule, this is a silent no-op, not a hard failure — SPECTRA is EIIS-standalone-conformant. Planning proceeds without prior-session memory; this is reflected as a Pattern-phase gap below, not fabricated as a false match.

---

## CLARIFY

**Trigger:** every new request. **Not skipped** — the mission names a generic "deployment command" with no target repository, existing CLI conventions, or plan/execute architecture supplied, which is genuine ambiguity, not merely missing polish.

**Parse Intent:**
- **WHO:** platform operators who run the deploy command by hand, and CI pipeline maintainers who want to gate merges/deploys on a pre-flight check.
- **WHAT:** a `--dry-run` flag on the existing deploy command that previews planned changes without producing any side effect.
- **WHY:** reduce the blast radius of deploy mistakes (wrong environment, stale config, unintended resource deletion) by letting operators and pipelines see the plan before it executes.
- **CONSTRAINTS:** must not weaken today's real-run behavior (opt-in, zero behavior change when the flag is absent); must be trustworthy — a preview that lies about what would happen is worse than no preview at all.

**Identify Gaps (Discovery mode was not warranted — the goal itself, "add a safe preview flag," is clear; only plan-shape details are ambiguous, which is exactly CLARIFY's remit, not DISCOVER's):**

| # | Gap | Resolution mode |
|---|-----|------------------|
| G1 | No target repository or CLI framework was supplied, and `/tmp/spectra-pilot` (this consumer project) contains only Eidolons scaffolding — no application source, no existing `deploy` command was found by search. `.spectra/setup/spectra-conventions.md` does not exist. | **[GAP] — cannot be closed interactively in this run** (single-shot deliverable, no live user turn available). Resolved via explicit, risk-tagged assumption below rather than fabricating a fake codebase match. |
| G2 | Unknown whether the target deploy command already separates "compute what would change" from "execute the change" (a plan/apply split), or is a single monolithic function. | **[ASSUMPTION]** — treat as unknown/monolithic (conservative default). This directly shapes the Explore-phase hypothesis selection below. |
| G3 | Unknown whether dry-run output needs to be machine-readable (CI-consumable) in v1, or human-readable console output is sufficient. | **[ASSUMPTION]** — included as an in-scope P1 story rather than P0, so it can be deferred at zero cost to the core feature if wrong. |

**Would-ask (≤3, numbered, <200 chars, per CLARIFY step 3 — recorded for the human reviewer since no live turn is available this run):**
1. Which repo/CLI does `deploy` live in, and does it already separate plan computation from execution?
2. Does dry-run need CI-parseable output (JSON/exit codes) in v1, or is console text enough for the first ship?
3. Should `--dry-run` cover only the top-level `deploy` command, or also `rollback`/`destroy` if they exist?

**Gather Structural Context:** grepped `/tmp/spectra-pilot` for `deploy`/`dry-run` — zero implementation hits (Eidolons scaffold files only). No `spectra-conventions.md` to load. Proceeding with generic, industry-standard CLI conventions (see Pattern phase) rather than fabricated project-specific paths; all file paths in Construct below are marked **[ASSUMED]** and must be re-anchored to the real target repo before implementation.

**Assess Cognitive Load:** single session sufficient; no multi-session flag needed.

**Skip?** No — see gaps above. CLARIFY is complete via documented assumptions, which is why confidence is gated to VALIDATE rather than AUTO_PROCEED at Assemble (see below).

---

## S — SCOPE

**Intent Type:** `CHANGE` (modify an existing command) — with `REQUEST`-like characteristics because the target command's current implementation is unknown to this session.

**Complexity Score (4-dimension matrix):**

| Dimension | Score (1–3) | Rationale |
|---|---|---|
| Scope | 1 | Single feature, single command surface |
| Ambiguity | 2 | Target repo/architecture unknown (G1/G2 above) |
| Dependencies | 2 | Touches CLI parsing, plan computation, every mutating call site, docs — 2–3 internal "systems" |
| Risk | 2 | User-facing safety feature; a *broken* dry-run that still mutates is a critical-path failure |

**Total: 7/12 → Extended thinking (2× budget).** Consistent with the mission's premise that this task warrants SPECTRA at all.

**Boundaries:**

| In Scope | Out of Scope | Deferred |
|---|---|---|
| `--dry-run` flag on the deploy command | Rollback/destroy command dry-run (G3 above) | Fast-follow once the shared guard wrapper (S-3) exists — same mechanism, new call sites |
| Human-readable planned-action preview | Full state-diff / drift detection against last-deployed state (H3, rejected) | Revisit only if operators report the preview isn't trustworthy enough on its own |
| Guarding every mutating call site behind the flag | Shadow/staging full execution (H4, rejected) | Not deferred — rejected outright, see Explore |
| Exit-code contract for CI gating | Interactive confirmation-prompt changes to the real-run path | Not deferred — unrelated surface |
| Optional `--output json` for CI consumption | Real-run JSON output (JSON is dry-run-only in this iteration) | Fast-follow if CI teams ask for it post-ship |

**Assumptions (risk-tagged):**

1. **[ASSUMPTION]** Target deploy command is monolithic (no existing plan/apply split). **Risk if wrong:** the conservative hypothesis (H1, selected below) is still valid but leaves value on the table — if the codebase already separates plan from apply, H2 (rejected below) becomes strictly better and Pattern should be re-run once the real repo is known.
2. **[ASSUMPTION]** "Side effect" includes infra API writes, config writes, notifications/webhooks, and DB writes; read-only calls (auth checks, resource lookups) are allowed to run under dry-run so the preview stays accurate. **Risk if wrong:** if the target stack has read calls with billable/rate-limited side effects (e.g. paid API lookups), S-3's guard boundary needs a narrower definition — flagged for human review at VALIDATE gate.
3. **[ASSUMPTION]** CI-consumable output (S-5) is valuable but not release-blocking. **Risk if wrong:** low — S-5 is P1 and independently deferrable with no impact on S-1–S-4.

**Stakeholders:** platform/infra operators (primary users), CI/pipeline maintainers (secondary users), the engineer implementing the change (reviews Construct output), whoever owns the deploy command's on-call runbook (reviews S-6).

---

## P — PATTERN

**Query memory:** unavailable this session (see Memory pre-flight) — **[GAP]**, not a false negative; no prior-failure catalog to surface.

**Query codebase:** zero matches in `/tmp/spectra-pilot` (see CLARIFY G1). Falling back to well-established external reference patterns for "preview before mutate" CLI flags, ranked by similarity to this ask (MMR: `similarity − 0.3 × redundancy`, top candidates shown):

| Pattern | Similarity | Why |
|---|---|---|
| `kubectl apply --dry-run=client\|server` | 82% | Two-mode preview; server mode validates against the live API without persisting — closest match to "read allowed, write blocked" |
| `terraform plan` | 78% | Canonical plan/apply separation; best exemplar for structured, itemized change preview |
| `aws cloudformation deploy --no-execute-changeset` | 74% | Changeset-preview pattern; close to the itemized-plan rendering this spec wants |
| `npm publish --dry-run` | 65% | Simple guard-only pattern: run everything except the final publish call |
| `git push --dry-run` | 60% | Simplest guard-only pattern; no structured plan object at all |

**No single pattern reaches the 85% USE_TEMPLATE threshold** (no direct in-repo match exists to apply verbatim). **Strategy: ADAPT (60–84% band)** — adopt the guard-before-mutate skeleton common to `npm`/`git`/`kubectl`, and borrow the itemized, ordered plan-rendering vocabulary from `terraform`/`cloudformation` for the preview's shape (S-2), without adopting terraform's full plan/apply architectural refactor (that refactor is H2, evaluated and rejected below as more surface than an MVP needs under the monolithic-codebase assumption).

**Catalog Failure Patterns:** none available (memory unreachable). Documented as a gap rather than skipped silently.

---

## E — EXPLORE

**Trigger:** before Construct. Not skipped. 4 genuinely distinct hypotheses generated (within the 3–5 range; conservative + pattern-leveraging + innovative + risk-minimizing, exceeding the minimum-diversity requirement).

**Observations (5 angles):** (1) blast-radius safety — a guard that's easy to prove complete beats a clever one that's easy to bypass by omission; (2) trust — the preview must never drift from what a real run would do; (3) CI integration — exit codes and machine-readable output matter to a second audience beyond the interactive operator; (4) refactor cost — how much of the existing deploy internals must change to add this; (5) speed — a "dry" run that's slow defeats its own purpose as a pre-flight check.

### Hypothesis scoring (7-dimension weighted rubric, 1–10 per dimension → weighted /100)

| # | Hypothesis | Align 25% | Correct 20% | Maintain 15% | Perf 15% | Simple 10% | Risk 10% | Innov 5% | **Total** |
|---|---|---|---|---|---|---|---|---|---|
| H1 | **Conservative** — guard wrapper short-circuits every mutating call; prints planned actions reusing existing computation, no architectural refactor | 9 | 8 | 8 | 9 | 10 | 9 | 3 | **84.5** |
| H2 | **Pattern-leveraging** — refactor deploy into explicit `plan()`/`apply()` (Terraform-style); dry-run renders the plan diff | 10 | 8 | 9 | 8 | 6 | 7 | 6 | **82.5** |
| H3 | **Innovative** — structured JSON report + drift detection vs. last-deployed state, CI exit-code semantics | 8 | 6 | 6 | 7 | 3 | 5 | 9 | **64.0** |
| H4 | **Risk-minimizing (shadow exec)** — dry-run fully executes against an isolated shadow/staging namespace for full-fidelity output | 6 | 7 | 5 | 4 | 2 | 6 | 7 | **54.0** |

Spread is 84.5→54.0 (30.5-point range) — **not** within the 5% "insufficient differentiation" band; the set is well-differentiated and no re-observation is needed. H1/H2 sit close (2 points apart) — both expanded below per the "expand top 2" rule.

### Expand top 2

**H1 — Guard wrapper (conservative).**
- *File impact:* small — one guard/wrapper utility + call-site updates at each mutation point + a preview renderer.
- *Dependency chain:* every existing mutating call must route through the wrapper; the highest-risk dependency is *completeness of enumeration* (a missed call site silently defeats the whole feature).
- *Edge cases:* nested/transitive side effects (a "helper" function that itself calls a mutating API), read-only calls that must still run (auth/lookups), partial-plan failures mid-computation.

**H2 — Plan/apply refactor (pattern-leveraging).**
- *File impact:* larger — deploy internals restructured into a `Plan` value object plus an `apply(plan)` executor; every call site touching current monolithic flow is disturbed.
- *Dependency chain:* correctness of the refactor is entangled with the *existing* real-run path, so a regression here risks breaking real deploys, not just the preview — a materially larger blast radius for an MVP whose ask is "add a flag," not "restructure the executor."
- *Edge cases:* same as H1 plus refactor-introduced regressions in the real-run path; better long-term diff quality (can show *before → after* state) but at meaningfully higher delivery risk under the "unknown, assumed-monolithic" codebase (G2).

### Selection

**Selected: H1 (Guard wrapper, conservative).** Under the G2 assumption (architecture unknown, treated as monolithic), H1 delivers the exact ask — a safe preview — without gambling the real-run path on an unscoped refactor. It also scores highest overall (84.5) and is the only hypothesis Simplicity-scores ≥9, which matters directly for Correctness-by-inspection of the one property that most matters here: *nothing mutates under `--dry-run`, ever.* H1 borrows H2's structured, itemized rendering vocabulary for its preview output (Pattern phase, ADAPT) without importing H2's refactor.

**Rejected alternatives (documented per E-phase step 6, prevents re-exploration in replanning):**

- **H2 (plan/apply refactor) — rejected for MVP, not permanently.** Higher alignment score but larger blast radius for a feature whose ask is additive, not architectural, under an unverified-monolithic codebase assumption. **Re-open trigger:** if a human confirms the real target repo already has a plan/apply split (CLARIFY G2 resolved in H2's favor), re-run Pattern — H2 would then likely win outright since the refactor cost disappears.
- **H3 (drift detection + JSON, innovative) — rejected for this spec, deferred.** Valuable for a CI-mature org but requires persisted last-deployed-state storage and diffing logic with real false-positive/negative risk (score 64, "Weak" band per `scoring.md`) — too much unscoped complexity for a first `--dry-run` ship. Its CI-friendly *spirit* is partially retained via S-5's lightweight JSON output, which is far cheaper than full drift detection.
- **H4 (shadow-environment execution) — rejected outright.** Executing in a shadow namespace is not actually a "dry" run — it costs infra/quota, can drift from the real environment (false confidence), and is an order of magnitude slower than a static/read-only preview, defeating the pre-flight-check purpose (Performance scored 4/10, Simplicity 2/10). No re-open trigger identified; this is a rejection on principle, not on missing information.

---

## C — CONSTRUCT

**Hierarchy:**

```
THEME    Deployment Safety & Operator Confidence
└─ PROJECT  P-1  Deploy Command Preview Capability
   └─ FEATURE F-1  `--dry-run` flag for the deploy command
      ├─ STORY S-1  Flag parsing & mode routing
      ├─ STORY S-2  Plan computation & human-readable preview renderer
      ├─ STORY S-3  Side-effect guard across all mutating call sites
      ├─ STORY S-4  Exit-code & validation-failure contract
      ├─ STORY S-5  Structured `--output json` mode (P1, CI-facing)
      └─ STORY S-6  Docs, `--help`, changelog, runbook
```

All 6 stories pass INVEST (Independent within necessary sequencing, Negotiable on exact wording, Valuable to a named actor, Estimable at the timeboxes below, Small ≤2d each, Testable via the GIVEN/WHEN/THEN sets below).

**Execution sequence (dependency-ordered):**

```
Phase 1:  S-1
Phase 2:  S-2  ‖  S-3      (parallel — distinct files, both depend only on S-1)
Phase 3:  S-4  ‖  S-5      (parallel — both consume S-2 + S-3 outputs)
Phase 4:  S-6
```

---

#### 📋 STORY: S-1 Flag parsing & mode routing

> 🔴 P0

**Description:** As a platform operator running the deploy CLI, I want a `--dry-run` flag recognized by the deploy command so that I can request a preview without triggering a real deployment.
**Timebox:** 1d
**Risk:** P0 (blocks release — every downstream story depends on this)

**Action Plan:**
1. **Extend:** deploy command's argument parser to accept `--dry-run` (boolean flag, no value).
2. **Modify:** command entrypoint to branch into a `dry_run: true` execution mode before any plan or mutation step begins.
3. **Test:** flag absent → behavior byte-for-byte identical to current release (regression guard); flag present + conflicting flag (e.g. a hypothetical `--force`) → explicit rejection, not silent override.

**Acceptance Criteria:**
- [ ] GIVEN the deploy command is invoked WHEN `--dry-run` is present THEN the command enters dry-run mode before any plan or execution step begins
- [ ] GIVEN `--dry-run` is combined with a flag that implies unconditional execution WHEN parsed THEN the CLI SHALL reject the combination with a clear error and non-zero exit, never silently ignore the conflict
- [ ] GIVEN no `--dry-run` flag WHEN the command runs THEN behavior is unchanged from the current release (backward compatibility)

**Technical Context:**
- **Pattern:** guard-before-mutate (ADAPT, Pattern phase)
- **Files:** `[ASSUMED — confirm against target repo]` `cli/commands/deploy.*` (entrypoint/arg parsing)
- **Dependencies:** none (foundation story)

**Agent Hints:**
- **Class:** Builder (speed-class implementation)
- **Context:** existing deploy command entrypoint, CLI arg-parsing conventions used elsewhere in the target repo
- **Gates:** P0 regression test (no-flag path unchanged) must pass before merge

---

#### 📋 STORY: S-2 Plan computation & human-readable preview renderer

> 🔴 P0

**Description:** As a platform operator, I want the dry run to print the concrete list of planned actions (create/update/delete, target resource) so that I can review exactly what would happen before committing.
**Timebox:** ≤2d
**Risk:** P0

**Action Plan:**
1. **Extend:** existing plan/change-computation logic (whatever currently decides what the deploy would do) to be callable without executing it.
2. **Create:** a preview renderer that prints an ordered, itemized list (verb + resource identifier) to stdout.
3. **Test:** zero-change case explicitly states "no changes" (never an ambiguous empty output); preview output is asserted to match the real executor's action list exactly (no drift — the single most important property of this story).

**Acceptance Criteria:**
- [ ] GIVEN dry-run mode is active WHEN the deploy command computes the deployment plan THEN it SHALL print a structured, ordered list of planned actions to stdout
- [ ] GIVEN the plan contains zero changes WHEN dry-run renders THEN it SHALL explicitly state "no changes" rather than an empty/ambiguous output
- [ ] GIVEN plan computation reuses the real executor's decision logic WHEN dry-run renders THEN the preview SHALL match exactly what a real run would attempt (test this with a shared fixture exercised by both the dry-run and real-run test suites)

**Technical Context:**
- **Pattern:** itemized plan rendering, borrowed from `terraform plan`/`cloudformation --no-execute-changeset` (Pattern phase, ADAPT — vocabulary only, not the full plan/apply refactor)
- **Files:** `[ASSUMED]` `lib/deploy/plan.*` (computation), `[ASSUMED]` `lib/deploy/output/renderer.*` (new)
- **Dependencies:** S-1

**Agent Hints:**
- **Class:** Builder
- **Context:** existing plan-computation function/module, any current logging conventions to match
- **Gates:** no-drift test (dry-run preview vs. real-run action list, same fixture) is P0 and must be green

---

#### 📋 STORY: S-3 Side-effect guard across all mutating call sites

> 🔴 P0 — highest-risk story in this spec

**Description:** As a platform operator, I want every side-effecting call in the deploy path (infra API writes, config writes, notifications/webhooks, DB writes) skipped under `--dry-run` so that no real change or side effect occurs no matter which code path executes.
**Timebox:** ≤2d
**Risk:** P0 (a guard that misses one call site means dry-run silently mutates — the single failure mode this whole feature exists to prevent)

**Action Plan:**
1. **Create:** a single shared "execute-or-preview" wrapper that every mutating call is routed through (not per-call-site `if dry_run` conditionals — see AC #3, this is deliberate: conditionals scattered per call site are exactly how a future call site gets added without the guard).
2. **Modify:** every existing mutating call site (infra API writes, config writes, notification/webhook dispatch, DB writes) to route through the wrapper.
3. **Test:** dry-run mode + every mutating call site → assert zero external calls made (mock/spy assertions on the outbound client, not just log-message assertions); read-only calls (auth/lookup) still execute and their results still flow into the plan.

**Acceptance Criteria:**
- [ ] GIVEN dry-run mode is active WHEN any mutating call site is reached THEN the call SHALL be skipped and logged as "would execute: [action]" rather than performed
- [ ] GIVEN dry-run mode is active WHEN a read-only call is required to compute the plan (auth/credential validation, resource-existence lookup, current-state fetch) THEN that call SHALL still execute normally — dry-run gates mutation, not read access (Scope Assumption #2)
- [ ] GIVEN a new deploy code path is added in the future WHEN it contains a mutating call THEN the guard SHALL be enforced via the shared wrapper, not a new per-call-site conditional, so omission cannot silently bypass the guard

**Technical Context:**
- **Pattern:** guard-before-mutate (ADAPT — `kubectl --dry-run`/`npm publish --dry-run` family)
- **Files:** `[ASSUMED]` `lib/deploy/executor.*` (all current mutating call sites), new shared wrapper module
- **Dependencies:** S-1

**Agent Hints:**
- **Class:** Reasoner + Explorer (an exhaustive call-site audit is the risk-critical step here — an ATLAS-equivalent scout pass to enumerate every existing mutating call before Builder wires the wrapper is strongly recommended)
- **Context:** full deploy execution module; anything that talks to an external API, filesystem, DB, or webhook endpoint
- **Gates:** P0 — 100% of currently known mutating call sites verified routed through the wrapper (mock-assertion coverage, not just code review)

---

#### 📋 STORY: S-4 Exit-code & validation-failure contract

> 🟡 P1

**Description:** As a CI pipeline maintainer, I want `--dry-run` to exit non-zero when the plan itself is invalid and exit zero when the plan is valid, so that dry-run can gate merge/deploy pipelines reliably without scraping log text.
**Timebox:** 1d
**Risk:** P1 (degrades CI usefulness if wrong, does not itself risk a real mutation)

**Action Plan:**
1. **Configure:** exit-code table below as the explicit, documented contract.
2. **Modify:** dry-run's plan-computation failure paths (bad config, auth failure, unresolvable dependency) to map to the non-zero code.
3. **Test:** both branches (valid plan / invalid plan) asserted by exit code in CI-style invocation tests, not just human-readable output.

**Exit-code contract:**

| Condition | Exit code |
|---|---|
| Dry-run plan computed successfully, changes found | 0 |
| Dry-run plan computed successfully, no changes found | 0 |
| Plan computation failed (invalid config, auth failure, unresolvable dependency) | non-zero (distinct code recommended, e.g. 2) |
| Flag-parsing error (S-1, e.g. conflicting flags) | non-zero (existing CLI arg-error code) |

**Acceptance Criteria:**
- [ ] GIVEN dry-run mode is active WHEN the plan computes successfully (regardless of whether changes are found) THEN the process SHALL exit 0
- [ ] GIVEN dry-run mode is active WHEN plan computation fails THEN the process SHALL exit non-zero with a diagnostic message identifying the failure
- [ ] GIVEN a CI pipeline invokes `--dry-run` as a merge gate WHEN the exit code is non-zero THEN the pipeline SHALL be able to block the merge without additional log parsing

**Technical Context:**
- **Pattern:** standard CLI exit-code conventions (0 = success, non-zero = failure)
- **Files:** `[ASSUMED]` `cli/commands/deploy.*` (exit path), `[ASSUMED]` `lib/deploy/plan.*` (failure surfacing)
- **Dependencies:** S-2, S-3

**Agent Hints:**
- **Class:** Builder
- **Context:** existing CLI error/exit-code conventions elsewhere in the repo, to stay consistent
- **Gates:** both exit-code branches covered by an invocation-level test (not unit-level only)

---

#### 📋 STORY: S-5 Structured `--output json` mode

> 🟡 P1 — independently deferrable

**Description:** As a CI pipeline maintainer, I want an optional `--output json` mode for dry-run so that pipeline tooling can parse the plan programmatically instead of scraping human-readable text.
**Timebox:** ≤2d
**Risk:** P1

**Action Plan:**
1. **Create:** JSON serialization of the plan object already computed in S-2 (actions array, summary counts, validity status, `schema_version` field).
2. **Extend:** CLI to accept `--output json`, valid only in combination with `--dry-run` in this iteration (real-run JSON output is explicitly out of scope, Scope table).
3. **Test:** JSON output round-trips against a fixed schema; `--output json` without `--dry-run` is rejected with a clear error.

**Acceptance Criteria:**
- [ ] GIVEN `--dry-run --output json` is passed WHEN the plan is computed THEN the CLI SHALL emit a single JSON document to stdout containing the plan's actions array, summary counts, and validity status
- [ ] GIVEN `--output json` is passed WITHOUT `--dry-run` THEN the CLI SHALL reject the combination (JSON output is dry-run-only this iteration)
- [ ] GIVEN the JSON schema changes in a future version WHEN emitted THEN it SHALL carry a `schema_version` field so CI consumers can detect breaking changes

**Technical Context:**
- **Pattern:** lightweight structured-output mode; deliberately far cheaper than H3's rejected drift-detection JSON (Explore phase)
- **Files:** `[ASSUMED]` `lib/deploy/output/renderer.*` (shared with S-2)
- **Dependencies:** S-2

**Agent Hints:**
- **Class:** Builder
- **Context:** S-2's plan object shape
- **Gates:** JSON schema validated in test; P2 lint/format clean

---

#### 📋 STORY: S-6 Docs, `--help`, changelog, runbook

> 🟢 P2

**Description:** As a new team member or on-call operator, I want `--dry-run` documented in `--help` output and the deployment runbook so that I can discover and trust the feature without reading source code.
**Timebox:** 1d
**Risk:** P2 (cosmetic/discoverability — does not block core functionality)

**Action Plan:**
1. **Modify:** `--help` text to list `--dry-run` and `--output json` with a one-line description and example invocation.
2. **Modify:** CHANGELOG with the new flags, the exit-code contract (S-4), and any behavior automation might depend on.
3. **Modify:** deployment runbook to recommend `--dry-run` as a standard pre-deploy step.

**Acceptance Criteria:**
- [ ] GIVEN a user runs `deploy --help` WHEN help text renders THEN `--dry-run` and `--output json` SHALL be listed with a description and example invocation
- [ ] GIVEN the feature ships WHEN the changelog is updated THEN it SHALL document the new flags and the exit-code contract from S-4
- [ ] GIVEN the deployment runbook exists WHEN this feature ships THEN it SHALL be updated to recommend `--dry-run` as a pre-deploy step

**Technical Context:**
- **Pattern:** n/a — documentation story
- **Files:** `[ASSUMED]` CLI help strings, `CHANGELOG.md`, `[ASSUMED]` `docs/runbooks/deploy.md`
- **Dependencies:** S-1, S-2, S-3, S-4, S-5 (documents final, shipped behavior)

**Agent Hints:**
- **Class:** Scriber (IDG-equivalent, per this project's wired Eidolons roster)
- **Context:** final flag behavior from S-1–S-5
- **Gates:** reviewed by whoever owns the runbook

---

## T — TEST (6-layer verification)

| # | Layer | Result |
|---|---|---|
| 1 | **Structural** | ✓ Hierarchy intact (Theme→Project→Feature→Story), no orphaned tasks, stories independent modulo the documented sequencing in Construct |
| 2 | **Self-Consistency** | ✓ See below — 3 alternative decompositions, ~78% overlap → HIGH confidence, stable |
| 3 | **Dependency** | ⚠ Partial — mutating call sites (S-3) and file paths cannot be enumerated against a real codebase (G1); flagged, not silently assumed complete. Migration path: none needed (additive flag, no data migration) |
| 4 | **Constraint** | ✓ Timeboxes realistic (all ≤2d); NFR "zero behavior change when flag absent" explicit in S-1 AC #3; security implication (auth calls must still run) explicit in S-3 AC #2 |
| 5 | **Process Reward** | ✓ Ordering (flag → compute/guard → contract → CI polish → docs) monotonically reduces risk: the highest-risk property (nothing mutates) is proven in Phase 2, before any CI/docs polish is added on top |
| 6 | **Adversarial** | ✓ See checklist below |

**Self-Consistency check (3 alternative decompositions):**

- **Decomposition A (this spec):** flag-parsing / plan-render / guard / exit-code / json-output / docs — 6 stories, grouped by feature slice.
- **Decomposition B:** "core dry-run gate" (merges S-1+S-3) / "plan preview" (S-2) / "CI contract" (merges S-4+S-5) / docs — 4 stories, same conceptual chunks regrouped by delivery bundle.
- **Decomposition C:** grouped by execution layer instead of feature — "CLI layer" / "deploy engine layer" / "CI tooling layer" / docs — same coverage, different axis.

All three surface the same underlying concepts (gate/guard, preview rendering, side-effect safety, CI contract, docs) — estimated **~78% story-content overlap** → **HIGH confidence, decomposition is stable.** Decomposition A was kept because P0/P1/P2 risk tags map more cleanly onto feature slices than onto delivery bundles or execution layers, which matters for the confidence-gating factors below.

**Adversarial checklist (Failure Taxonomy, `scoring.md`):**

| Failure mode | Checked | Finding |
|---|---|---|
| Under-specification | ✓ | S-3's read-vs-write boundary was under-specified in the first pass — fixed in Refine below |
| Over-specification | ✓ | No rigid constraint blocks a valid implementation; file paths marked `[ASSUMED]`, not mandated |
| Dependency blindness | ⚠ | Real call-site enumeration is unknown (G1) — mitigated by explicitly requiring an Explorer/ATLAS pass before Builder starts S-3, not by pretending the list is known |
| Assumption drift | — | No earlier-phase discovery yet invalidates a later step; re-open triggers documented for H2 if G2 resolves differently |
| Scope creep | ✓ | Boundary table enforced; drift detection (H3) and shadow-exec (H4) explicitly kept out |
| Premature optimization | ✓ | Complexity 7/12 did not trigger over-engineering; H4 (most "sophisticated") was rejected precisely for this reason |
| Stale context | n/a | No prior file reads to go stale; this is a fresh cycle |

**Gate:** Minor gaps only (Dependency layer ⚠, one adversarial ⚠, same root cause: unknown target repo) → **Refine (1 cycle).**

---

## R — REFINE

**Cycle 1 diagnosis:** Test surfaced two related gaps: (a) S-3's guard boundary didn't originally distinguish read-only calls (needed for an accurate plan) from mutating calls (must be blocked) — a real under-specification risk, since an over-eager guard could break the very plan computation it's supposed to preview; (b) S-4's exit-code contract wasn't originally expressed as an explicit table, leaving an implementing agent to guess at specific codes.

**Root cause:** both gaps trace back to treating "block everything under dry-run" as a single undifferentiated rule, rather than naming the read/write boundary and the success/failure boundary explicitly.

**Prescription (applied):** added the explicit read-only carve-out to S-3 AC #2, and added the exit-code table to S-4 (both already reflected in the Construct section above — this log records the diagnose→fix→re-verify pass that produced them).

| Dimension | Before | After | Change |
|---|---|---|---|
| Clarity | 4 | 4 | unchanged — no clarity issue found |
| Completeness | 3 | 4 | read-only/mutating boundary now explicit in S-3; exit codes now tabular in S-4 |
| Actionability | 3 | 4 | an implementing agent no longer has to infer the exit-code contract or guess at the read/write boundary |
| Efficiency | 4 | 4 | unchanged |
| Testability | 3 | 4 | both fixes are independently unit-testable assertions (mock-spy on outbound calls; exit-code assertions per branch) |

**Mean:** 3.4 → 4.0 (**+0.6**, above the 0.3 diminishing-returns floor — this cycle earned its keep). **No dimension decreased** — no oscillation. **Cycle 1 target (all ≥3) met and exceeded (all ≥4); stopping at 1 cycle** rather than continuing to a cycle whose marginal gain would likely fall under the diminishing-returns threshold.

**Re-verify:** re-ran the Structural/Constraint/Adversarial layers against the updated S-3/S-4 — no new gaps introduced, no prior pass invalidated.

---

## A — ASSEMBLE

### Confidence Assessment

| Factor | Score (/3) | Basis |
|---|---|---|
| Pattern Match | 2 | Strong external pattern family (kubectl/terraform/npm), but no in-repo template exists to apply directly (G1) |
| Requirement Clarity | 2 | Mission's feature ask is unambiguous; target-repo specifics are not (CLARIFY gaps) |
| Decomposition Stability | 3 | ~78% self-consistency overlap across 3 alternative decompositions — HIGH |
| Constraint Compliance | 2 | 6-layer Test passed with 2 flagged-but-mitigated gaps, both traced to the same root cause (unknown target repo), not to spec quality |

**Weighted Confidence:** (2+2+3+2)/12 × 100 = **75%**

**Decision: VALIDATE (70–84% band) — deliver with flags, human reviews.**

**What a human reviewer should specifically validate before this becomes AUTO_PROCEED-worthy:**
1. Confirm the real target repo and whether it already has a plan/apply split (CLARIFY G2) — this could flip the Explore selection from H1 toward H2.
2. Re-anchor every `[ASSUMED]` file path in Construct against the actual codebase (an Explorer/ATLAS pass is recommended specifically for S-3's call-site enumeration, given it's the highest-risk story in the spec).
3. Confirm whether CI-consumable output (S-5) is actually wanted for v1, or should be fully deferred (Scope Assumption #3).

### Deliverables produced (dual-format contract + ECL sidecar)

| Artifact | Path |
|---|---|
| Plan artifact (this file) | `/tmp/ramza-s2/ab-spectra-run1.out.md` (requested output path — explicit override, honored) |
| Authoritative mirror (Output Discipline rule 2) | `/tmp/spectra-pilot/.spectra/plans/2026-07-04-deploy-dry-run.md` |
| Agent handoff (YAML) | `/tmp/spectra-pilot/.spectra/plans/2026-07-04-deploy-dry-run.yaml` |
| State machine (JSON) | `/tmp/spectra-pilot/.spectra/plans/2026-07-04-deploy-dry-run.state.json` |
| ECL v2.0 envelope sidecar | `/tmp/spectra-pilot/.spectra/plans/2026-07-04-deploy-dry-run.envelope.json` (emitted because `ECL_VERSION=2.0` is present at `/tmp/spectra-pilot/.eidolons/spectra/ECL_VERSION`) |

Per Output Discipline rule 2: since the mission explicitly named a path outside `.spectra/`, that path was honored as the primary deliverable, and the authoritative copy was mirrored under `.spectra/plans/` regardless, together with the full Assemble deliverable set (YAML handoff, state JSON, ECL envelope) that a SPECTRA Assemble phase produces per `SPEC.md` and `skills/planning.md`.

### Agent Handoff (YAML)

```yaml
metadata:
  spec_id: "SPEC-2026-07-04-001"
  confidence: 75
  complexity: 7
  spectra_version: "4.11.0"
  thread_id: "019f3008-d356-7578-b835-b386c4384835"

projects:
  - id: "P-1"
    name: "Deploy Command Preview Capability"
    features:
      - id: "F-1"
        name: "--dry-run flag for the deploy command"
        stories:
          - id: "S-1"
            title: "Flag parsing & mode routing"
            timebox: "1d"
            risk: "P0"
            action_plan:
              - verb: "Extend"
                target: "deploy command argument parser: add --dry-run boolean flag"
              - verb: "Modify"
                target: "command entrypoint: branch into dry_run execution mode pre-plan"
              - verb: "Test"
                target: "no-flag regression path + conflicting-flag rejection"
            acceptance_criteria:
              - given: "the deploy command is invoked"
                when: "--dry-run is present"
                then: "the command enters dry-run mode before any plan or execution step begins"
              - given: "--dry-run is combined with a flag implying unconditional execution"
                when: "parsed"
                then: "the CLI rejects the combination with a clear error and non-zero exit"
              - given: "no --dry-run flag"
                when: "the command runs"
                then: "behavior is unchanged from the current release"
            agent_hints:
              recommended_class: "builder"
              context_files: ["cli/commands/deploy.* [ASSUMED]"]
              validation_gates:
                p0: "no-flag regression test green"
          - id: "S-2"
            title: "Plan computation & human-readable preview renderer"
            timebox: "<=2d"
            risk: "P0"
            dependencies: ["S-1"]
            action_plan:
              - verb: "Extend"
                target: "plan/change-computation logic to be callable without executing"
              - verb: "Create"
                target: "preview renderer: ordered itemized action list to stdout"
              - verb: "Test"
                target: "zero-change case + no-drift fixture shared with real-run tests"
            acceptance_criteria:
              - given: "dry-run mode is active"
                when: "the deploy command computes the deployment plan"
                then: "it prints a structured, ordered list of planned actions to stdout"
              - given: "the plan contains zero changes"
                when: "dry-run renders"
                then: "it explicitly states no changes rather than an empty output"
              - given: "plan computation reuses the real executor's decision logic"
                when: "dry-run renders"
                then: "the preview matches exactly what a real run would attempt"
            agent_hints:
              recommended_class: "builder"
              context_files: ["lib/deploy/plan.* [ASSUMED]", "lib/deploy/output/renderer.* [ASSUMED]"]
              validation_gates:
                p0: "no-drift test (dry-run preview == real-run action list on shared fixture)"
          - id: "S-3"
            title: "Side-effect guard across all mutating call sites"
            timebox: "<=2d"
            risk: "P0"
            dependencies: ["S-1"]
            action_plan:
              - verb: "Create"
                target: "shared execute-or-preview wrapper (no per-call-site conditionals)"
              - verb: "Modify"
                target: "every mutating call site to route through the wrapper"
              - verb: "Test"
                target: "mock/spy assertions: zero outbound mutating calls under dry-run; read-only calls still execute"
            acceptance_criteria:
              - given: "dry-run mode is active"
                when: "any mutating call site is reached"
                then: "the call is skipped and logged as would-execute rather than performed"
              - given: "dry-run mode is active"
                when: "a read-only call is required to compute the plan"
                then: "that call still executes normally"
              - given: "a new deploy code path is added in the future"
                when: "it contains a mutating call"
                then: "the guard is enforced via the shared wrapper, not a new per-call-site conditional"
            agent_hints:
              recommended_class: "reasoner"
              context_files: ["lib/deploy/executor.* [ASSUMED]"]
              validation_gates:
                p0: "100% of known mutating call sites verified routed through wrapper via mock-assertion coverage"
          - id: "S-4"
            title: "Exit-code & validation-failure contract"
            timebox: "1d"
            risk: "P1"
            dependencies: ["S-2", "S-3"]
            action_plan:
              - verb: "Configure"
                target: "exit-code table: 0 valid plan (changes or none), non-zero plan-computation failure, non-zero flag error"
              - verb: "Modify"
                target: "plan-computation failure paths to map to the non-zero code"
              - verb: "Test"
                target: "invocation-level exit-code assertions per branch"
            acceptance_criteria:
              - given: "dry-run mode is active"
                when: "the plan computes successfully"
                then: "the process exits 0 regardless of whether changes are found"
              - given: "dry-run mode is active"
                when: "plan computation fails"
                then: "the process exits non-zero with a diagnostic message"
              - given: "a CI pipeline invokes --dry-run as a merge gate"
                when: "the exit code is non-zero"
                then: "the pipeline blocks the merge without additional log parsing"
            agent_hints:
              recommended_class: "builder"
              context_files: ["cli/commands/deploy.* [ASSUMED]", "lib/deploy/plan.* [ASSUMED]"]
              validation_gates:
                p1: "both exit-code branches covered by invocation-level test"
          - id: "S-5"
            title: "Structured --output json mode"
            timebox: "<=2d"
            risk: "P1"
            dependencies: ["S-2"]
            action_plan:
              - verb: "Create"
                target: "JSON serialization of plan object: actions[], summary counts, validity, schema_version"
              - verb: "Extend"
                target: "CLI --output json flag, valid only with --dry-run this iteration"
              - verb: "Test"
                target: "JSON schema round-trip; rejection when --output json used without --dry-run"
            acceptance_criteria:
              - given: "--dry-run --output json is passed"
                when: "the plan is computed"
                then: "the CLI emits a single JSON document with actions array, summary counts, validity status"
              - given: "--output json is passed without --dry-run"
                then: "the CLI rejects the combination"
              - given: "the JSON schema changes in a future version"
                when: "emitted"
                then: "it carries a schema_version field"
            agent_hints:
              recommended_class: "builder"
              context_files: ["lib/deploy/output/renderer.* [ASSUMED]"]
              validation_gates:
                p1: "JSON schema validated in test"
          - id: "S-6"
            title: "Docs, --help, changelog, runbook"
            timebox: "1d"
            risk: "P2"
            dependencies: ["S-1", "S-2", "S-3", "S-4", "S-5"]
            action_plan:
              - verb: "Modify"
                target: "--help text: list --dry-run and --output json with example invocation"
              - verb: "Modify"
                target: "CHANGELOG: new flags + exit-code contract"
              - verb: "Modify"
                target: "deployment runbook: recommend --dry-run as pre-deploy step"
            acceptance_criteria:
              - given: "a user runs deploy --help"
                then: "--dry-run and --output json are listed with description and example"
              - given: "the feature ships"
                then: "the changelog documents the new flags and exit-code contract"
              - given: "the deployment runbook exists"
                then: "it is updated to recommend --dry-run as a pre-deploy step"
            agent_hints:
              recommended_class: "scriber"
              context_files: ["CHANGELOG.md", "docs/runbooks/deploy.md [ASSUMED]"]
              validation_gates:
                p2: "reviewed by runbook owner"

execution_plan:
  phases:
    - name: "Phase 1 — Foundation"
      stories: ["S-1"]
      agent_class: "builder"
    - name: "Phase 2 — Core safety (parallel)"
      stories: ["S-2", "S-3"]
      agent_class: "builder+reasoner"
    - name: "Phase 3 — CI contract (parallel)"
      stories: ["S-4", "S-5"]
      agent_class: "builder"
    - name: "Phase 4 — Docs"
      stories: ["S-6"]
      agent_class: "scriber"
```

### State Machine (JSON)

```json
{
  "session_id": "019f3008-d356-7fea-8493-d652cc262ff5",
  "spec_id": "SPEC-2026-07-04-001",
  "goal": "Add a --dry-run flag to the deployment command with a trustworthy preview and a complete side-effect guard.",
  "spectra_version": "4.11.0",
  "steps": [
    { "id": 1, "story_id": "S-1", "title": "Flag parsing & mode routing", "status": "pending", "dependencies": [], "files_affected": ["cli/commands/deploy.* [ASSUMED]"], "verification_command": "test: no-flag regression + conflicting-flag rejection", "estimated_timebox": "1d", "replanning_notes": null },
    { "id": 2, "story_id": "S-2", "title": "Plan computation & preview renderer", "status": "pending", "dependencies": [1], "files_affected": ["lib/deploy/plan.* [ASSUMED]", "lib/deploy/output/renderer.* [ASSUMED]"], "verification_command": "test: zero-change case + no-drift fixture", "estimated_timebox": "<=2d", "replanning_notes": null },
    { "id": 3, "story_id": "S-3", "title": "Side-effect guard across all mutating call sites", "status": "pending", "dependencies": [1], "files_affected": ["lib/deploy/executor.* [ASSUMED]"], "verification_command": "test: mock-spy zero-mutating-calls assertion", "estimated_timebox": "<=2d", "replanning_notes": null },
    { "id": 4, "story_id": "S-4", "title": "Exit-code & validation-failure contract", "status": "pending", "dependencies": [2, 3], "files_affected": ["cli/commands/deploy.* [ASSUMED]", "lib/deploy/plan.* [ASSUMED]"], "verification_command": "test: invocation-level exit-code assertions", "estimated_timebox": "1d", "replanning_notes": null },
    { "id": 5, "story_id": "S-5", "title": "Structured --output json mode", "status": "pending", "dependencies": [2], "files_affected": ["lib/deploy/output/renderer.* [ASSUMED]"], "verification_command": "test: JSON schema round-trip", "estimated_timebox": "<=2d", "replanning_notes": null },
    { "id": 6, "story_id": "S-6", "title": "Docs, --help, changelog, runbook", "status": "pending", "dependencies": [1, 2, 3, 4, 5], "files_affected": ["CHANGELOG.md", "docs/runbooks/deploy.md [ASSUMED]"], "verification_command": "manual: runbook owner review", "estimated_timebox": "1d", "replanning_notes": null }
  ],
  "current_step": 0,
  "completed_steps": [],
  "replanning_history": [
    {
      "cycle": 1,
      "phase": "Refine",
      "diagnosis": "S-3 guard boundary didn't distinguish read-only vs mutating calls; S-4 lacked an explicit exit-code table",
      "fix_applied": "added read-only carve-out to S-3 AC #2; added exit-code table to S-4",
      "mean_score_before": 3.4,
      "mean_score_after": 4.0,
      "oscillation_detected": false
    }
  ]
}
```

### CRYSTALIUM persistence

`mcp__crystalium__ingest` and `mcp__crystalium__session_end` were **not called** — no `mcp__crystalium__*` tools are reachable in this environment (see Memory pre-flight). Per `agent.md`/`skills/planning.md`, this is a documented graceful no-op, not a silent omission.

### Preflight Checklist

- [x] CLARIFY ran (not skipped — genuine ambiguity, resolved via risk-tagged assumptions, no live user turn available this run)
- [x] `spectra-conventions.md` checked — absent, generic defaults used and documented
- [x] Complexity scored (7/12), extended-thinking budget routed
- [x] 4 genuinely distinct hypotheses explored (conservative, pattern-leveraging, innovative, risk-minimizing)
- [x] All 6 stories pass INVEST
- [x] All timeboxes valid (1d/≤2d only, no story points)
- [x] Hierarchy uses Project (not "Epic")
- [x] Acceptance criteria in GIVEN/WHEN/THEN
- [x] Agent hints with context files per story
- [x] Dual output: Markdown (this file) + structured YAML/JSON (embedded above + mirrored as separate files)
- [x] Confidence score present with factor breakdown (75%, VALIDATE)
- [x] Plan saved as artifact at the requested path + mirrored under `.spectra/plans/`
- [x] Every mirrored/derived output path starts with `.spectra/`
- [x] No code produced — plans only
- [x] Rejected alternatives documented (H2, H3, H4 — three, exceeding the "at least one" requirement)

---

*SPECTRA v4.11.0 — Strategic Specification through Deliberate Reasoning*
