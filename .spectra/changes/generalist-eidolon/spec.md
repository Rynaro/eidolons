---
eidolon: ramza
kind: spec
version: 1.2.0
created_at: 2026-07-11
change_id: generalist-eidolon
esl_version: "1.1"
tier: full
maker: ramza
checker: pending
revision: 3
---

# Spec — ESL change `generalist-eidolon` (rev 3, post-critique cycle 2)

Package the "general-purpose agent" seat into the Eidolons roster as a new,
measurement-gated `generalist` capability class + a new member (persona name
**TBD_NAME**, a maintainer decision), dispatched **only** as a strict
specialist-preferring fallthrough worker, per FORGE verdict **H-E** (77%).

**Rev 3** dispositions CRIT-013..CRIT-021 from critic cycle 2. The predicate now uses a
fully-specified **reference extractor** whose output is the frozen fixture table (machine-derived,
zero hand-set cells, CRIT-013); noun/version/blast-radius over-fire vectors are closed
(CRIT-014/015/016); Arm-2 owner-labels are independence-guarded (CRIT-017). See §Revision Log.

**Lineage.** Scout: `scout-report.md` (FINDING-001..019, GAP-001..003) +
`scout-addendum-ecl.md` (FINDING-020/021). Deliberation: `deliberation.md`
(H-E @ 77%, `requires_checker=true`). Critic: `critique.md` (REVISE, 5 MAJOR +
7 MINOR). Evidence: `gp-agent-research-digest.md`. RAMZA gates: `plan-state.json`.

This spec is READ-ONLY output. It NAMES required artifacts + their acceptance
shape; per nexus P0 (HC1) no per-member methodology prose is authored here.

---

## Scope

**Intent class:** CHANGE (roster/registry + cortex + external-repo coordination).

**In:**
- New `capability_class` enum value `generalist` (schema, in-repo).
- New roster member row TBD_NAME at `in_construction` (roster/routing/CI/agent, in-repo).
- Dispatch Protocol Step-2(a)/(b) mechanical split with a presence-based signal extractor.
- Cortex ≤900-token re-fit precondition + a mechanical, tokenizer-pinned token-budget CI check.
- The NAMED artifact set + acceptance shape of the member's own-repo methodology (external).
- The eidolons-ecl edge-contract set + composition.md regen implications (external + in-repo CI).
- The two-arm measurement gate (coverage-rate + no-over-capture on a labeled corpus) + maker≠checker.
- Rollout sequencing + the two-checker (RAMZA critic + ESL kupo) pre-flip topology.

**Out:**
- The member's methodology prose itself (HC1 — written later in `Rynaro/TBD_NAME`).
- Re-declaring any ECL performative / CRYSTALIUM layer / ESL schema (HC2/HC3 anti-scope).
- Literal override of a host's built-in general-purpose subagent type (GAP-002/[GAP-hostslot]);
  S-host is covered as a named fallthrough agent + exported methodology, not a host-type override.
- Naming TBD_NAME, the strategic go/no-go, the `shipped` flip (human-owned, `requires_checker`).

**Deferred:**
- Full frequency instrumentation of `clarification_request`. Per CRIT-007, REVERSAL-3
  (frequency-null) is **redefined to remain mechanically evaluable**: it fires when the Arm-1
  stratified coverage-rate falls below its floor (no separate instrument required to keep the
  pre-flip checklist evaluable). The authority justification for minting `in_construction` stays
  structural (missing write-capable-worker archetype), not frequency-based (HC11, OQ-6 concurred).
- Any second host-slot adapter beyond Claude Code until [GAP-hostslot] is resolved.

**Assumptions (risk-if-wrong):**
- A1: the always-loaded section can be re-fit ≤ 850-proxy tokens by de-labeling mislabeled deep
  tables — risk if wrong: HC9 budget-locked (REVERSAL-5), forces routing-only H-D.
- A2: the host's built-in general-purpose type is not user-overridable — risk if wrong: S-host
  could be covered more strongly; does not invalidate H-E.
- A3: composition.md is auto-generated + drift-gated (FINDING-021, GAP-001 closed).

**Complexity** (`ramza-score --rubric complexity`): **10/12 → human_loop** — consistent with
`requires_checker=true`.

---

## Approach

Selected rollout strategy: **H-B — staged, Kupo-precedent rollout** (`ramza-score --rubric explore`
= **82, solid**; see Rejected Alternatives). The *path* (H-E) was decided upstream by FORGE; RAMZA
owns the *sequencing* + the mechanical predicate/gate design.

### 1. Capability class (Track A)
Add `"generalist"` to `capability_class.enum` (`roster-entry.schema.json:11`), backward-compatible
(FINDING-004). `routing.schema.json` needs **no** change (open string + `classes.default` cover
future classes, FINDING-002).

### 2. Roster member row (Track B)
A `roster/index.yaml` row for TBD_NAME: `capability_class: generalist`, `status: in_construction`,
**no positive trigger verbs** (never enters Step-1). `refuse_verbs` tile the specialist space +
deploy/irreversible-without-checker + routing/spawning + underspecified. `handoffs.upstream:
[orchestrator]`, `handoffs.downstream: []` (worker-never-router), `lateral: [forge]`.
`security.writes_repo: false`; a capability/authority table governs in-mission acts; sandbox-first;
PROPOSE-only across the authority line. Model tier: **standard** (rationale in R-010).

### 3. Dispatch Step-2 mechanical predicate (Track C) — rev 3, reference extractor

The generalist is dispatched **only** in branch (a), **only** when no specialist scores ≥ τ (0.6).
Rev 3 specifies a **deterministic reference extractor** (frozen verbatim in `acceptance-criteria.md`
§The reference extractor) so a third party reproduces every signal with zero discretion (CRIT-013):

- **S1 act_verb** — `1` iff an `ACT_VERBS` lexeme (∉ `EXCLUDED_POLYSEMOUS`) appears in **imperative
  position** (previous token a clause-marker or first) and is not preceded by a `DET_BLOCKLIST`
  determiner — this kills noun-sense false-hits like "the recent patch"/"the update" (CRIT-014).
- **S2 deliverable** — `1` iff a `DELIVERABLE_NOUNS` lexeme or a `PATH_OR_ID` token is present.
- **S3 named_target** — `1` iff a `PATH_OR_ID` token is present, where `PATH_OR_ID` is tightened to
  require a path separator, a closed `FILE_EXT`, or a backtick-fenced identifier — excluding bare
  versions/decimals/units/abbreviations (`30.5s`, `2.5.0`, `e.g.`) (CRIT-015).
- **S4 acceptance** — `1` iff an `ACCEPTANCE_MARKERS` token or a numeric target is present.
- **S5 bounded** — if no `GENERIC_SCOPE` token → `1`; else `1` **only** when a `LIMITER`
  (`only/just/limited_to/...`) co-occurs with a `PATH_OR_ID`. A co-occurring path alone does NOT
  neutralize a generic scope (CRIT-016 — "entire codebase" + one path stays unbounded → clarify).
- **S6 no_specialist_ge_tau / S7 no_chain** — branch preconditions from the Step-1 scorer
  (S7=0 = ≥2 classes trigger-hit = a chain owns it).
- **Tie-break:** any signal indeterminate → `0` → `clarification_request`.
- **Scope:** predicate input is **English only**; non-English/emoji-only prompts yield S1=0 →
  clarify by design (CRIT-019).

**Predicate** (only when S6 ∧ S7 hold): `actionable = S1 ∧ S2 ∧ S3 ∧ S4 ∧ S5`.

**Seventeen normative fixtures** (P1..P11 adversarial + C1..C6 counter) are **machine-derived**: the
frozen S1..S5 columns equal the reference-extractor output verified by a self-check (CRIT-013;
R-054/AC-C11). All eleven P-fixtures — including the noun-trap P7, version P8, blast-radius P9,
Spanish P10, version P11 — route to `clarification_request` or a chain; only the fully-bounded,
named-target, acceptance-carrying C1/C3/C5/C6 dispatch the generalist. A deterministic (no-LLM)
extractor must reproduce every fixture vector exactly (CRIT-002; AC-C05/C06/C11).


### 4. Cortex budget precondition (Track D) — rev 2, tokenizer-pinned
Precondition, not a nicety (HC9; FINDING-019 at/over budget; I-C4 at EIDOLONS.md:147). Two moves:
(a) relocate mislabeled deep tables (Chain-Template detail, TRANCE prose) outside a new
machine-readable pair `<!-- always-loaded:start -->` / `<!-- always-loaded:end -->` into on-demand
`methodology/cortex/`; (b) add a bash-3.2 token-budget CI check (closes GAP-003) that counts
`ceil(char_count/4)` of the bytes **strictly between those two markers** and fails if the proxy-count
exceeds **850** — a conservative ceiling under the I-C4 900 to absorb heuristic error vs a real BPE
tokenizer (CRIT-005; AC-D02/D06). Two runs on the same bytes give the same count by construction.

### 5. Member's own-repo methodology — NAMED artifacts only (Track E)
`Rynaro/TBD_NAME`, EIIS-1.0. The nexus NAMES (prose lives there, HC1): TaskState schema (digest§3);
delegation contract `{objective, scope(paths,mode), deliverables, evidence_required, stop_conditions}`
(digest§5); capability-authority table default+escalation (digest§7); externalized verification
(digest§4); stopping policy `{continue, recover, escalate, terminate}` (digest§4); bounded loop
budget (digest§3); "deliberately boring worker" posture — no permanent memory, no deploy authority,
no cross-task policy, delegates by returning a typed request upward (HC8).

### 6. ECL edge contracts + composition regen (Track F) — rev 2, edge_origin pinned
Upstream `Rynaro/eidolons-ecl` PR (FINDING-020/021): one directed-edge YAML per edge + a `schema_ref`
under `schemas/per-eidolon/` per new artifact kind (`mission-contract`, `handoff-request`). Edge set:
`human→TBD_NAME`, `orchestrator→TBD_NAME` (inbound mission-contract); the **PROPOSE-upward**
hand-off-request edges `TBD_NAME→atlas`, `TBD_NAME→kupo`, `TBD_NAME→vigil`, `TBD_NAME→idg`,
`TBD_NAME→forge`; lateral `forge↔TBD_NAME`. Per CRIT-009, each outbound edge sets
`edge_origin: emitted-request` (PROPOSE-upward, not dispatch), which reconciles `downstream: []`
(R-007/AC-B05) with the five outbound contracts (R-050/AC-F05). All use only the closed 10
performatives (HC2). Then nexus `compose-gen` regen; `composition-drift.yml` must pass. See OQ-4.

### 7. Two-arm measurement gate (Track G) — rev 2, falsifiable
Both arms MUST pass before `in_construction → shipped`; **maker≠checker** on the gate (A14).

- **Arm 1 (capability-expansion) — CRIT-004 fix.** A **frozen, SHA-pinned** holdout **stratified**
  across easy/medium/hard mission difficulty, drawn from instrumented `clarification_request` traces
  + a frozen synthetic set (selection rule the maker cannot cherry-pick; maker≠checker on
  construction), size N ≥ K. Pass = verified-completion **RATE ≥ a precedent-pegged floor X%**
  (Kupo-KEEP / RAMZA-succession precedent), holding across **three independent runs** (pass³
  repetition discipline). The `>0` bar is removed. X is human-owned (OQ-1 family); the structure
  (rate + floor + strata + repetition) is pinned.
- **Arm 2 (no-over-capture, mandatory) — CRIT-003 fix.** The corpus is **not** the trivially-safe
  strongly-matched-only set. It includes: (i) strongly-matched specialist prompts (≥ τ) — hard MUST
  bar = **0** generalist fires; (ii) a **near-threshold band** (specialist top-score in `[τ−0.15, τ)`);
  (iii) **paraphrase-perturbed** specialist prompts; (iv) the P1..P6 class. Over-capture is defined
  as "generalist fired on a prompt whose **labeled ground-truth owner** is a specialist," adjudicated
  against a labeled key — not "fired when a specialist scored ≥ τ." The near-threshold subset carries
  an explicit measured **non-inferiority bound** (denominator = near-threshold prompts; numeric bound
  human-owned, OQ-1).

### 8. Rollout sequencing (Track H) — rev 2, two-checker topology
P1 (in-repo, additive) → P2 (cortex precondition) → P3 (external) → P4 (gate) → P5 (release). P2
MUST land at/before any always-loaded row growth (HC9). Per CRIT-012, **two distinct gates are
required before the flip**: the RAMZA maker≠checker critic gate (this pass) **and** the ESL
change-checker (kupo — `kupo-esl-hop` / `verify-incoming`, per `change.json`). The `shipped` flip is
then gated on the two-arm gate + human go/no-go + naming (`requires_checker=true`, cats 1 & 5). The
five reversal-conditions are pre-flip stop gates, each mechanically evaluable (CRIT-007).

---

## Requirements

Every requirement traces to a FINDING/GAP/verdict-clause/HC/digest/CRIT item in brackets.

**Track A — capability class**
- **R-001** [FINDING-001/004, A1] Add `"generalist"` to `capability_class.enum`, backward-compatible.
- **R-002** [FINDING-002] routing.schema.json stays open string; `classes.default` covers the class.

**Track B — roster member row**
- **R-003** [FINDING-003/005/013] TBD_NAME row: `generalist`, `in_construction`, full block.
- **R-004** [RISK-over-capture] NO positive trigger verbs (fallthrough-only).
- **R-005** [FINDING-006, HC8] `refuse_verbs` tile specialist space + deploy + routing/spawn + underspecified.
- **R-006** [scope-boundary, digest§5] `handoffs.upstream: [orchestrator]`; inbound typed mission-contract.
- **R-007** [HC8, FINDING-007] `handoffs.downstream: []`; delegation PROPOSEd upward, never dispatched.
- **R-008** [scope-boundary] `lateral: [forge]`.
- **R-009** [digest§7] `writes_repo: false`; capability/authority table (default+escalation); sandbox-first; PROPOSE-only.
- **R-010** [deliberation Step-2 change; cost + Arm-1-gated] `working_set_tokens` declared; model tier = **standard** — rationale: the residual-hardest missions are cost-sensitive and any capability shortfall is caught by Arm-1 (CRIT-011 trace fix; OQ-5 dispositioned).
- **R-011** [A7] Add TBD_NAME to the `full` preset.
- **R-012** [FINDING-015, A4] Add the resolved name to `roster-health.yml` matrix; `in_construction` skips EIIS conformance.
- **R-013** [A8] README roster table + MANIFESTO team table / pipeline phrase rows.
- **R-014** [A9] CHANGELOG unreleased entry.
- **R-015** [A13, FINDING-008, digest§7] `.claude/agents/<name>.md`: standard tier, scoped allowlist (no generic `Bash(*)`).

**Track C — dispatch predicate**
- **R-016** [FINDING-010, verdict] Replace Step-2 no-match branch with (a) actionable→generalist / (b) underspecified→`clarification_request`.
- **R-017** [I-C6 determinism; CRIT-006 drops I-C2] The (a)/(b) predicate is mechanical (presence-based over closed lexicons), never LLM-discretionary. I-C2 (dispatch-is-interpretive) is NOT cited.
- **R-018** [task§3, CRIT-001/013/014/015/016/018] Define S1..S5 as the reference-extractor rules over closed lexicons (imperative-position S1 with DET_BLOCKLIST noun guard; PATH_OR_ID tightened to exclude versions/decimals/abbreviations; S5 LIMITER-scoped bounding) + truth table + tie-break + a lexicon versioning policy (out-of-lexicon verb → S1=0 → clarify).
- **R-019** [RISK-over-capture, I-C6] Generalist never enters Step-1; never outranks a specialist ≥ τ; lives solely in branch (a).
- **R-020** [FINDING-010] Underspecified prompts still emit `clarification_request`.
- **R-048** [CRIT-008/016] S5 blast-radius guard: a `GENERIC_SCOPE` token forces `clarification_request` unless a `LIMITER` co-occurs with a `PATH_OR_ID`; a co-occurring path alone does not neutralize generic scope.
- **R-049** [CRIT-002/013] A deterministic (no-LLM) reference extractor reproduces the seventeen frozen fixture vectors exactly; the fixture table is machine-derived with zero hand-set cells.
- **R-052** [CRIT-017] Arm-2 owner-labels: independent labeler (≠ maker, ≠ generalist-builder), assigned blind before replay, SHA-frozen alongside the corpus, disagreements adjudicated by a second blind labeler.
- **R-053** [CRIT-019] Predicate input scoped to English; non-English/emoji-only prompts route to `clarification_request` by design.
- **R-054** [CRIT-013] A fixture-table derivability self-check: the frozen S1..S5 columns equal the reference-extractor output with zero hand-edited cells, verified before freeze.

**Track D — cortex budget**
- **R-021** [FINDING-019, GAP-003, HC9, REVERSAL-5] Re-fit the always-loaded region before the row ships.
- **R-022** [FINDING-019, task§4a] Bound the always-loaded region with `<!-- always-loaded:start/end -->`; relocate mislabeled deep tables outside it to `methodology/cortex/`.
- **R-023** [GAP-003, HC7, CRIT-005] Add a bash-3.2 token-budget CI check: `ceil(chars/4)` of the delimited region, fail if > 850.
- **R-024** [FINDING-019, A5] The new EIDOLONS.md row keeps the delimited region ≤ 850-proxy.

**Track E — member methodology (NAMED only)**
- **R-025** [A10, HC1, HC4] New external repo `Rynaro/TBD_NAME`, EIIS-1.0 conformant.
- **R-026** [digest§3] Structured TaskState schema.
- **R-027** [digest§5] Typed delegation contract `{objective, scope, deliverables, evidence_required, stop_conditions}`.
- **R-028** [digest§7] Capability-authority table (default+escalation).
- **R-029** [digest§4] Externalized verification; never self-report.
- **R-030** [digest§4, task§5] Stopping policy `{continue, recover, escalate, terminate}`.
- **R-031** [digest§3, task§5] Bounded loop budget (time/turns/tokens).
- **R-032** [digest ref-design, HC8] "Deliberately boring worker": no permanent memory, no deploy authority, no cross-task policy.
- **R-033** [HC1] The nexus MUST NOT contain member methodology prose.

**Track F — ECL contracts + composition**
- **R-034** [FINDING-020/021, A11] Upstream eidolons-ecl PR adds a directed-edge YAML per TBD_NAME edge.
- **R-035** [FINDING-020] Per new artifact kind, a `schema_ref` under `schemas/per-eidolon/`.
- **R-036** [FINDING-021, A6] Regenerate composition.md via `compose-gen`; never hand-edit.
- **R-037** [FINDING-021] nexus `composition-drift.yml` passes post-regen.
- **R-038** [HC2] Edge contracts use only the closed 10 performatives.
- **R-050** [CRIT-009] The five outbound edges set `edge_origin: emitted-request` (PROPOSE-upward), reconciling `downstream: []` with one-YAML-per-edge.

**Track G — measurement gate**
- **R-039** [verdict arm1, HC10, A14, CRIT-004] Arm 1: SHA-frozen stratified holdout drawn by a non-cherry-pickable rule.
- **R-040** [verdict arm1, CRIT-004] Arm 1 pass = verified-completion RATE ≥ precedent floor X%, holding across 3 runs (pass³).
- **R-041** [verdict arm2, CRIT-003] Arm 2 corpus includes strongly-matched + near-threshold `[τ−0.15, τ)` + paraphrase + P1..P11; over-capture vs an independently-labeled, blind-frozen ground-truth owner.
- **R-042** [task§7, RAMZA precedent, CRIT-003] Margins: hard MUST = 0 over-capture on the strongly-matched subset; measured non-inferiority bound on the near-threshold denominator (numeric — OQ-1, human).
- **R-051** [HC10, checker-handoff] Both arms pass before `shipped`; maker≠checker on the gate.

**Track H — rollout + checker**
- **R-043** [task§8, FINDING-013] Phase order P1→P5 (§Approach 8).
- **R-044** [HC9, REVERSAL-5] Cortex-trim precondition (P2) lands at/before the row growth.
- **R-045** [checker-handoff cats 1&5, CRIT-012] `requires_checker=true`: **two** pre-flip gates — the RAMZA maker≠checker critic AND the ESL change-checker (kupo) — plus human naming + go/no-go.
- **R-046** [checker-handoff, REVERSAL-1/2] The shipped flip is gated on the two-arm gate AND human go/no-go.
- **R-047** [verdict REVERSAL 1-5, CRIT-007] The five reversal-conditions are pre-flip stop gates, each mechanically evaluable (frequency-null ≡ Arm-1 coverage-rate below floor).

---

## Stories

### Story 1 — P1: in-repo `in_construction` foothold
As the maintainer, I want the enum + a fallthrough-only roster row + routing block + CI matrix +
agent file landed at `in_construction`. Timebox: 2d. Risk: P1. Executor hint: **mid** — +action plan;
mechanical, backward-compatible, marker-bounded. Covers R-001..R-015 (minus cortex row), R-019/R-020.
Output: `make schema` + `make test` green; no `shipped` claim.

### Story 2 — P2: cortex precondition (BLOCKING)
As the maintainer, I want the always-loaded region marker-bounded + re-fit ≤ 850-proxy + a
tokenizer-pinned token-budget CI. Timebox: 2d. Risk: **P0** (HC9). Executor hint: **frontier** —
cortex-prose judgment + a bash 3.2 CI script. Covers R-016..R-018, R-021..R-024, R-048/R-049.
Output: token-budget CI green; extractor-fixture test green.

### Story 3 — P3: external member repo + ECL edges
As the maintainer, I want `Rynaro/TBD_NAME` (EIIS-1.0) + eidolons-ecl edge contracts (edge_origin
pinned) + composition regen. Timebox: 6–8d. Risk: P1. Executor hint: **frontier** — goals+constraints
(a whole methodology). Covers R-025..R-038, R-050. Output: EIIS checker green; `composition-drift.yml`
green; ECL conformance green.

### Story 4 — P4: two-arm measurement gate
As the maintainer, I want the coverage-rate + no-over-capture arms run on a frozen labeled corpus with
an independent checker. Timebox: 4d. Risk: **P0**. Executor hint: **frontier**. Covers R-039..R-042,
R-051. Output: Arm-1 rate ≥ floor across 3 runs; Arm-2 0 over-capture on strongly-matched + within
bound on near-threshold; maker≠checker attested.

### Story 5 — P5: shipped flip + nexus release (HUMAN-GATED)
As the maintainer, I want naming + go/no-go + the `shipped` flip + version cut. Timebox: 1d. Risk:
**P0**. Executor hint: **human** — `requires_checker=true` (RAMZA critic + ESL kupo both required).
Covers R-043..R-047. Output: no `TBD_NAME` token remains; go/no-go recorded; integrity metadata rostered.

---

## Acceptance Criteria

The full, EARS-linted, self-contained criteria (**57 checks**, grouped by track, incl. the closed
lexicons + ten normative predicate fixtures) are frozen in `acceptance-criteria.md` (SHA-256 in
`plan-state.json`). Index:

| Track | Checks | Covers |
|---|---|---|
| A — schema | AC-A01, A02a, A02b, A03 | R-001, R-002 |
| B — roster row | AC-B01..B10 | R-003..R-015 |
| C — dispatch predicate | AC-C01..C12 | R-016..R-020, R-048, R-049, R-053, R-054 |
| D — cortex budget | AC-D01..D06 | R-021..R-024 |
| E — member methodology | AC-E01..E09 | R-025..R-033 |
| F — ECL + composition | AC-F01..F05 | R-034..R-038, R-050 |
| G — measurement gate | AC-G01..G07 | R-039..R-042, R-051, R-052 |
| H — rollout + checker | AC-H01..H04 | R-043..R-047 |

---

## Confidence

`ramza-score --rubric confidence`: recomputed post-refine (see `plan-state.json` gates[]). VALIDATE
band — act with monitoring; the two named GAPs (frequency, host-slot) + the numeric margin/naming are
routed to the gate/human, not resolved here.

---

## Rejected Alternatives

**Rollout-strategy hypotheses (RAMZA Explore):**
- **H-A — single mega-PR** (`explore` 39, weak): couples `in_construction` to `shipped`, defeats
  `requires_checker` staging, unreviewable, ungateable. Rejected.
- **H-C — external-repos-first** (`explore` 46, weak): nexus schema cannot validate the row without
  the enum; inverts add-eidolon `[NEW]` order. Rejected.
- **H-D — routing-only, defer the member** (`explore` 54, weak): re-litigates the decided verdict;
  branch (a) has no dispatch target; leaves S-host uncovered. Rejected.

**Path-level hypotheses** (H-A loose / H-B promote-Kupo / H-C widen-Vivi-ATLAS / H-D routing-only /
H-F defer) were rejected upstream by FORGE (`deliberation.md`, 1.90–3.80 vs H-E 4.25); not re-opened.

---

## Risks

| Risk | Tag | Mitigation |
|---|---|---|
| Over-capture — generalist steals specialist prompts (I-C6) | P0 | No positive triggers (R-004); never in Step-1 (R-019); Arm-2 labeled-owner corpus incl. near-threshold, MUST=0 on ≥τ (R-041/R-042) |
| Predicate discretion leak (the primary risk, OQ-7) | P0 | Presence-based signals over closed lexicons + tie-break-to-clarify (R-017/R-018/R-048); frozen fixtures + extractor determinism test (R-049/AC-C06) |
| Identity drift — dumping ground | P1 | Explicit refuse-set (R-005) + "boring worker" posture (R-032) |
| Coordinator conflation — spawning (HC8) | P0 | `downstream: []` + PROPOSE-upward, edge_origin pinned (R-007/R-050) |
| Cortex regression / unmeasurable gate | P0 | Marker-bounded region + `chars/4 ≤ 850` CI + BPE-tolerance fixture (R-023/AC-D02/AC-D06) |
| Forgeable ship gate | P0 | Arm-1 rate-floor + strata + pass³ (R-040); Arm-2 non-tautological corpus (R-041) |
| Premature ship | P0 | Two-checker topology (R-045) + human go/no-go (R-046) + evaluable reversal gates (R-047) |
| Naming leakage | P1 | AC-H02 grep gate blocks release on any residual `TBD_NAME` |

---

## Open Questions (for critic re-check / human)

- **OQ-1** [R-042] Numeric values: Arm-1 floor X% + holdout size N/K; Arm-2 near-threshold
  non-inferiority bound. The **denominators + measurement are now specified** (CRIT-003/004);
  only the numbers remain human-owned. *(human)*
- **OQ-2** [R-003] TBD_NAME persona name — maintainer decision (`requires_checker`). *(human)*
- **OQ-3** [GAP-002, REVERSAL-4] Host-GP-slot wiring feasible, or documentation-only? *(ATLAS/human)*
- **OQ-4** [R-034/R-050] Confirm the five outbound edges + their `edge_origin: emitted-request`. *(maintainer)*
- **OQ-5** [R-010] Dispositioned: model tier = **standard** (cost + Arm-1-caught). Flag if the critic
  wants deep for cross-class missions. *(critic)*
- **OQ-6** [REVERSAL-3] Dispositioned (concur w/ FORGE + critic): `in_construction` mint justified on
  structural authority grounds; REVERSAL-3 kept evaluable via Arm-1 coverage-rate. *(recorded)*
- **OQ-7** [R-017/R-018/R-049] Primary risk — addressed by presence-based signals + frozen fixtures +
  extractor-determinism test. Re-check whether the closed lexicons are complete enough. *(critic)*

---

## Revision Log (rev 1 → rev 2; CRIT dispositions)

| CRIT | Sev | Disposition |
|---|---|---|
| CRIT-001 | MAJOR | S1..S7 rewritten as presence rules over closed lexicons (ACT/INVESTIGATE/DELIVERABLE/GENERIC_SCOPE/ACCEPTANCE); "cleanly"→S7 mechanical (≥2 classes hit); indeterminate→clarify tie-break; P1 "Make the project better" → clarification. §Approach 3, R-017/R-018, criteria §Signals + fixtures. |
| CRIT-002 | MAJOR | New R-049 + AC-C05/AC-C06 test the prompt→vector **extractor** against ten frozen fixtures (exact match), not the combinator. |
| CRIT-003 | MAJOR | Arm-2 corpus redefined: strongly-matched (MUST=0) + near-threshold `[τ−0.15,τ)` + paraphrase + P1..P6; over-capture vs labeled ground-truth owner. R-041/R-042, AC-G03/AC-G04. |
| CRIT-004 | MAJOR | Arm-1 ">0" replaced by a stratified, SHA-frozen, non-cherry-pickable holdout + rate-floor X% across 3 runs (pass³). R-039/R-040, AC-G01/AC-G02. |
| CRIT-005 | MAJOR | Token-budget CI pinned: `ceil(chars/4)` of the `<!-- always-loaded:start/end -->` region, fail > 850; BPE-tolerance fixture. R-022/R-023, AC-D02/AC-D04/AC-D06. |
| CRIT-006 | MINOR | I-C2 dropped from R-017/AC-C05 rationale; grounded on I-C6 alone. |
| CRIT-007 | MINOR | REVERSAL-3 redefined as "Arm-1 coverage-rate below floor" so AC-H04 is mechanically evaluable; Scope §Deferred updated. |
| CRIT-008 | MINOR | S5 blast-radius guard (R-048/AC-C08): unbounded/repo-wide acts route to clarification, never to the `writes_repo:false` worker. |
| CRIT-009 | MINOR | R-050/AC-F05 pin `edge_origin: emitted-request` (PROPOSE-upward) on the five outbound edges, reconciling `downstream: []`. |
| CRIT-010 | MINOR | AC-A02 split into AC-A02a (superset) + AC-A02b (length==9) — compound-THEN removed. |
| CRIT-011 | MINOR | R-010 trace corrected to the deliberation Step-2 change; standard-tier rationale documented; OQ-5 dispositioned. |
| CRIT-012 | MINOR | Two-checker topology stated in §Approach 8 / R-045 (RAMZA critic + ESL kupo both required pre-flip). |
| CRIT-013 | MAJOR | Fixture table **machine-derived** by the reference extractor; self-check proves frozen S1..S5 == extractor output, zero hand-set cells (R-049/R-054, AC-C06/C11). |
| CRIT-014 | MAJOR | S1 imperative-position + DET_BLOCKLIST noun guard — ACT nouns ("the patch"/"the update") no longer set S1 (R-018, AC-C09; fixture P7). |
| CRIT-015 | MAJOR | PATH_OR_ID tightened (path-sep / closed FILE_EXT / fenced-id); versions/decimals/abbreviations excluded (R-018, AC-C10; fixtures P8/P11). |
| CRIT-016 | MAJOR | S5 requires a LIMITER co-occurring with a path to bound a generic scope; a bare co-path no longer neutralizes it (R-048, AC-C08; fixture P9). |
| CRIT-017 | MAJOR | Arm-2 owner-labels independence-guarded: labeler ≠ maker/≠ builder, blind, SHA-frozen pre-replay, second-blind adjudication (R-052, AC-G07). |
| CRIT-018 | MINOR | ACT_VERBS broadened (append/insert/enable/...); out-of-lexicon verb → S1=0 → clarify, with a lexicon versioning policy (R-018). |
| CRIT-019 | MINOR | Predicate scoped to English input; non-English/emoji-only → clarify by design (R-053, AC-C12; fixture P10). |
| CRIT-020 | MINOR | (tooling, out of scope) `ramza-gate advance --to A` is verdict-blind; recorded for the RAMZA tooling owner — the plan correctly held at T. |
| CRIT-021 | MINOR | (audit hygiene) the T→A→T revert survives as `corrections[]`; provenance (tool vs hand-edit) is explicit in plan-state. |

---

*RAMZA — spec (tier=full, rev 3). Critic: PENDING re-check (maker≠checker; do not self-approve).*
