# SPECTRA Planning Session — `--dry-run` flag for the deployment command

**Agent:** SPECTRA v4.11.0 (planning-specialist, READ-ONLY — specification only)
**Consumer project:** `/tmp/spectra-pilot`
**Session date:** 2026-07-04
**Mirrored artifacts:** `.spectra/plans/2026-07-04-dry-run-deploy-flag.{md,yaml,state.json}` + `.md.envelope.json` (ECL v2.0, `ECL_VERSION` present in install root) — mirrored per Output Discipline rule 2 because this response's primary destination (`/tmp/ramza-s2/ab-spectra-run2.out.md`) is an explicit path override outside `.spectra/`.

## Memory pre-flight

Checked for `mcp__crystalium__*` tool availability before CLARIFY, per `agent.md` "Memory pre-flight". Not installed in this environment → graceful skip, no recall/ingest/commit calls made. SPECTRA is EIIS-standalone-conformant and proceeds without CRYSTALIUM.

Checked for `.spectra/setup/spectra-conventions.md` (project vocabulary override). Not present → generic defaults used throughout, documented explicitly wherever a real file path or framework name would otherwise be needed.

## CLARIFY

**Not skipped** — the goal ("add a `--dry-run` flag to a deployment command") is clear, but this consumer project (`/tmp/spectra-pilot`) is a fresh Eidolons scaffold with no application source, deploy script, or CI config checked in yet (confirmed by structural search: only `.eidolons/`, `.claude/`, `eidolons.yaml/lock`, and an empty git history exist). That means several plan-shape details cannot be resolved by reading code and are logged as assumptions with risk-if-wrong rather than blocking on a human round-trip (per the mission's auto-mode guidance to make the reasonable call and flag it, rather than halt).

**WHO / WHAT / WHY / CONSTRAINTS** — see Scope §below.

**≤3 clarifying questions** (answered provisionally via logged assumptions so the spec stays decision-ready; a human reviewer should confirm before Construct-phase execution):
1. Does the deploy command already separate into validate → plan → execute stages, or is it monolithic? → **Assumed:** stage-separated (A1).
2. Is the deploy command a CLI invocation (human/CI) or a long-running service? → **Assumed:** CLI (A2).
3. What should `--dry-run` + `--force` do together? → **Resolved in-spec:** `--force` becomes a no-op with a warning under `--dry-run` (S-1, AC-3) — never silently escalated to a real deploy.

---

## 🎯 SCOPE ANALYSIS

**Intent Type:** CHANGE (additive capability on an existing command)
**Complexity Score:** 8/12 (Scope 1 + Ambiguity 2 + Dependencies 2 + Risk 3) — **Extended thinking** (2x budget)
**Thinking Budget:** Extended

**WHO:** Release engineers and on-call responders running manual deploys; CI pipelines invoking the deploy command non-interactively; release managers reviewing what a deploy will do before approving it.

**WHAT:** Add a `--dry-run` boolean flag to the existing deployment command. When set, the command runs its full validation and planning logic unchanged, prints a clear preview of every action it would take, and exits with the same success/failure exit-code contract as a real run — but performs zero state-changing actions against the deploy target.

**WHY:** Reduce the risk of unintended production changes; give engineers a trustworthy way to preview a deploy before committing to it; let CI gate a release on "does this plan look right" as a distinct, cheap, fast step; shorten incident response by letting an on-call engineer verify a fix would deploy correctly before running it for real.

**CONSTRAINTS:**
- Must not perform any side-effecting action (no artifact push, no remote apply/restart, no config write, no notification side effects).
- Must reuse the existing validate/plan code path for parity — no separate, divergent "simulated" implementation that can silently go stale relative to real deploys.
- Must preserve the existing exit-code contract so CI can gate on dry-run failures exactly as it gates on real-run failures.
- Must compose with existing flags (`--env`, `--target`, `--verbose`, `--force`) without surprising interactions.
- Output must be unambiguous that no change was applied — no risk of a user mistaking dry-run output for a completed deploy.
- Omitting the flag must leave current behavior byte-for-byte unchanged (backward compatible).

**Boundaries:**

| In Scope | Out of Scope | Deferred |
|---|---|---|
| `--dry-run` flag parsing and wiring | Adding dry-run to other commands (rollback, status, etc.) | Two-tier `--dry-run=client\|server` with target-side what-if APIs (H2) |
| Gating every side-effecting call behind the flag | Changing the underlying deploy engine/orchestrator | Persisted plan artifact + `--apply=<plan-file>` workflow (H3) |
| Preview/summary output rendering | Sandboxed real-execution simulation (H4) | — |
| Exit-code parity for CI gating | | |
| Parity + zero-side-effect regression tests | | |
| Docs: help text, runbook, CI example | | |

**Assumptions** (logged with risk-if-wrong; cannot be verified against real code in this blank scaffold, carried as open items into Assemble):

1. **A1 — Stage separation.** The deploy command already has (or cleanly separates into) validate → plan → execute stages, so a dry-run can hook in immediately before "execute." *Risk if wrong:* a monolithic command needs refactoring first, growing S-2's timebox beyond ≤3d.
2. **A2 — CLI invocation model.** The deploy command runs as a CLI process (human- or CI-invoked), not as a long-running daemon/API. *Risk if wrong:* dry-run becomes a request parameter, not an arg-parser concern, and S-4 (CI gating) needs re-design.
3. **A3 — Exit-code contract.** 0 = success, non-zero = failure is the existing contract. *Risk if wrong:* S-4's acceptance criteria need to target whatever the real contract is.
4. **A4 — Read access unchanged.** Dry-run still needs read-level access to current state (to diff against) — no new elevated permission is introduced, only write/mutate calls are skipped. *Risk if wrong:* dry-run may need a distinct, narrower credential scope than assumed.

**Stakeholders:** Requester — release engineering. Reviewers/approval chain — whoever owns the deploy command (likely platform/DevOps) plus a security-minded reviewer for S-2 given its P0 safety stakes. Affected — any CI pipeline currently invoking the deploy command (must remain backward compatible).

---

## 📚 PATTERN ANALYSIS

**Query:** "add dry-run / no-op / preview flag to deploy command"
**Matches:** 0 in-repo patterns — the consumer project has no application code yet (confirmed via structural search: only Eidolons install scaffolding and an empty git history at `/tmp/spectra-pilot`). CRYSTALIUM memory tools are unavailable in this environment, so no episodic/semantic recall either — graceful skip per the memory pre-flight contract.

**Strategy:** **GENERATE** — no repo-local or memory-sourced patterns to adapt. Industry precedent (`kubectl --dry-run`, `terraform plan`) informs the hypothesis set below as external reference only, not as a matched pattern (hence no similarity % table — there is nothing local to score against).

---

## 🌳 EXPLORATION SUMMARY

**Hypotheses:** 4 generated (conservative, industry-pattern, innovative, risk-minimizing), top 2 expanded. Scored on the 7-dimension weighted rubric: Alignment 25% · Correctness 20% · Maintainability 15% · Performance 15% · Simplicity 10% · Risk 10% · Innovation 5%.

| # | Hypothesis | Align | Correct | Maint | Perf | Simpl | Risk | Innov | **Weighted /100** |
|---|---|---|---|---|---|---|---|---|---|
| H1 | Flag-gated no-op at the execution boundary (conservative) | 9 | 9 | 8 | 9 | 10 | 8 | 3 | **85.5 — Elite** |
| H2 | Two-tier `client`/`server` dry-run, kubectl/terraform-style (industry-pattern) | 8 | 7 | 6 | 7 | 5 | 6 | 7 | **68.0 — Weak/borderline** |
| H3 | Structured plan artifact + `--plan-out` for later `--apply` (innovative) | 7 | 6 | 5 | 7 | 3 | 5 | 9 | **60.0 — Weak** |
| H4 | Real execution against an ephemeral sandbox clone (risk-minimizing) | 4 | 6 | 3 | 2 | 1 | 4 | 6 | **37.5 — Anchor-Low** |

Spread exceeds the 5% anti-strawman threshold — differentiation is sufficient; no re-observation needed.

**Selected:** **H1 — Flag-gated no-op execution stage.** The deploy command runs through its existing validate + plan stages completely unchanged; a single guard at the point where side-effecting calls happen short-circuits to a logged "would-do" statement instead of executing. Same code path up to the mutation boundary guarantees dry-run/real-run parity by construction — exactly the property WHY depends on ("a preview I can trust").

**Rejected Alternatives:**
- **H2 (68.0) — two-tier client/server dry-run.** Deferred, not abandoned: layering `--dry-run=server` on top of H1 is reasonable Phase 2 work once/if the deploy target exposes a native what-if API. Rejected for v1 because target-capability detection and inconsistent-support UX add real complexity for a first cut the ask didn't request.
- **H3 (60.0) — structured plan artifact + later apply.** Rejected: introduces a versioned plan-artifact schema and a plan-vs-actual staleness problem (state can drift between "plan" and a later "apply"). That's scope creep relative to "add a dry-run flag"; revisit only if a genuine plan/apply workflow is separately requested.
- **H4 (37.5) — sandboxed real execution.** Rejected: provisioning and tearing down a real sandboxed environment per dry-run defeats the core value proposition (fast, cheap, zero-risk preview) with cost, latency, and new infra-permission surface disproportionate to the ask.

---

## Hierarchy

```
THEME:   Safer, more predictable deployments
PROJECT: Deployment Command Safety Enhancements
FEATURE: `--dry-run` flag for the deploy command
```

#### 📋 STORY: S-1 CLI flag registration

**Description:** As a release engineer, I want to pass `--dry-run` to the deploy command so that I can signal I want a preview instead of a real deployment.
**Timebox:** 1d
**Risk:** 🟡 P1

Action Plan:
1. **Extend:** the deploy command's argument parser to accept `--dry-run` (bool, default `false`) alongside `--env`/`--target`/`--verbose`.
2. **Configure:** thread the parsed flag into the command's execution context (e.g. `context.dry_run: bool`) so downstream stages can read it.
3. **Validate:** define the `--force` interaction (AC-3 below) rather than leaving it unspecified.
4. **Test:** unit tests for flag parsing — present, absent, combined with other flags.

Acceptance Criteria:
- [ ] GIVEN the deploy command is invoked WHEN `--dry-run` is passed THEN the execution context records `dry_run=true` and no error is raised.
- [ ] GIVEN the deploy command is invoked WHEN `--dry-run` is omitted THEN `dry_run` defaults to `false` and behavior is unchanged.
- [ ] GIVEN `--dry-run` and `--force` are both passed WHEN the command starts THEN a warning prints that `--force` has no effect in dry-run mode, and execution proceeds as a dry run (force is never silently escalated into a real deploy).

Technical Context:
- **Pattern:** extend existing flag parser (exact framework TBD — see A1/A2)
- **Files:** deploy command entrypoint (path TBD — [GAP], see Dependency layer below)
- **Dependencies:** none (foundational)

Agent Hints:
- **Class:** builder
- **Context:** existing `--env`/`--target` parsing code
- **Gates:** P0 flag parses correctly; unit coverage of default/explicit/combined cases

---

#### 📋 STORY: S-2 Gate every side-effecting action behind the flag

**Description:** As a release engineer, I want the deploy command to skip all state-changing actions when `--dry-run` is set so that I can preview a deploy with zero risk of mutating production.
**Timebox:** ≤3d
**Risk:** 🔴 P0 — this is the core safety guarantee of the entire feature.

Action Plan:
1. **Identify:** audit the execution stage and enumerate every side-effecting call (artifact push, remote apply/restart, config write, notification/webhook, migration execution, etc.) — this audit is itself a deliverable, not an implicit step, and is the designed way to resolve assumption A1.
2. **Extend:** wrap each identified call site with a check on `context.dry_run`; when true, log the action that would have been taken (verb, target, key parameters) instead of performing it.
3. **Modify:** leave validate/plan stages unconditional and untouched — dry-run must exercise the exact same validation/planning code as a real run, never a parallel simulated implementation.
4. **Test:** one test per identified call site proving it is NOT invoked when `dry_run=true` (mock/spy, zero invocations).

Acceptance Criteria:
- [ ] GIVEN `--dry-run` is set WHEN the command runs to completion THEN zero network calls or filesystem writes that mutate the deploy target occur (verified via mock/spy with zero invocations).
- [ ] GIVEN `--dry-run` is set WHEN a side-effecting call site is reached THEN a log line records the action that would have executed instead of executing it.
- [ ] GIVEN `--dry-run` is NOT set WHEN the command runs THEN behavior is identical to the pre-feature implementation (regression-tested).

Technical Context:
- **Pattern:** single code path with a mutation-boundary guard (Selected H1)
- **Files:** deploy executor/orchestrator module (path TBD — [GAP])
- **Dependencies:** S-1

Agent Hints:
- **Class:** builder
- **Context:** existing deploy executor and its side-effecting call sites
- **Gates:** P0 audit completeness (every side-effecting site enumerated, not just the obvious one); both branches covered by tests

---

#### 📋 STORY: S-3 Dry-run output — unambiguous simulation banner + action summary

**Description:** As a release engineer, I want dry-run output to clearly show what would happen and to look visibly distinct from real-deploy output so that I never mistake a preview for a completed deployment.
**Timebox:** ≤2d
**Risk:** 🟡 P1

Action Plan:
1. **Create:** a summary renderer listing planned actions grouped by target/resource (create/update/delete/no-op), sourced from the plan stage's existing data.
2. **Extend:** prepend/append a prominent banner (e.g. `>>> DRY RUN — no changes were applied <<<`) at both the start and end of output.
3. **Configure:** honor the existing `--verbose` flag for summary detail level rather than inventing a new verbosity system.
4. **Test:** snapshot/golden-output tests for the summary format; assert the banner appears at both start and end.

Acceptance Criteria:
- [ ] GIVEN `--dry-run` is set WHEN the command completes THEN output includes a banner stating no changes were applied, at both start and end.
- [ ] GIVEN `--dry-run` is set WHEN the plan stage identifies N planned actions THEN the summary lists all N, grouped by operation type.
- [ ] GIVEN `--dry-run` and `--verbose` are both set WHEN the command runs THEN the summary includes per-action detail rather than counts only.

Technical Context:
- **Pattern:** reuse S-2's plan data as the rendering source (no new data model)
- **Files:** output/reporting module (path TBD)
- **Dependencies:** S-2

Agent Hints:
- **Class:** builder
- **Context:** existing `--verbose` formatting code
- **Gates:** P1 banner presence tested; verbose/non-verbose paths covered

---

#### 📋 STORY: S-4 Exit-code parity for CI gating

**Description:** As a CI pipeline, I want the deploy command to exit non-zero under `--dry-run` when validation/planning fails, using the same exit-code contract as a real run, so a dry-run gate step can block a release on a bad plan.
**Timebox:** 1d
**Risk:** 🔴 P0 — if dry-run always exits 0, CI cannot gate on it, defeating the primary CI use case named in WHY.

Action Plan:
1. **Modify:** confirm the existing exit-code logic in validate/plan stages is untouched and applies identically regardless of `dry_run`.
2. **Test:** integration test — `--dry-run` against an invalid config exits with the same non-zero code/message as the equivalent real-run failure.
3. **Test:** integration test — `--dry-run` against a valid config exits 0.

Acceptance Criteria:
- [ ] GIVEN an invalid configuration WHEN `--dry-run` is set THEN the command exits with the same non-zero code as the equivalent real-run failure.
- [ ] GIVEN a valid configuration WHEN `--dry-run` is set and the plan succeeds THEN the command exits 0.
- [ ] GIVEN a valid configuration WHEN `--dry-run` is NOT set THEN exit-code behavior is unchanged from the pre-feature baseline.

Technical Context:
- **Pattern:** reuse existing exit-code contract, no new codes
- **Files:** command entrypoint/error handling
- **Dependencies:** S-2

Agent Hints:
- **Class:** builder
- **Context:** existing exit-code tests for real-run failures
- **Gates:** P0 CI-gating correctness

---

#### 📋 STORY: S-5 Parity + regression test suite

**Description:** As a maintainer, I want automated tests proving dry-run and real-run share the same validation/planning logic and that dry-run never mutates state, so future changes to the deploy command can't silently break the safety guarantee.
**Timebox:** ≤2d
**Risk:** 🔴 P0 — this suite is what keeps S-2/S-4's guarantee true over time, not just at ship time.

Action Plan:
1. **Test:** consolidate S-1–S-4's unit tests into a dedicated dry-run test module.
2. **Create:** an integration test running the same deploy scenario twice (with and without `--dry-run`, against a disposable/mock target) asserting the plan/validation portion of output is identical between runs.
3. **Create:** a "zero side effects" regression test — a spy on the deploy-target client that fails the test if ANY mutating method is invoked while `dry_run=true`, across success, validation-failure, and partial-target-failure scenarios.

Acceptance Criteria:
- [ ] GIVEN the same deploy inputs WHEN run once with `--dry-run` and once without THEN the plan/validation portion of output is identical.
- [ ] GIVEN `--dry-run` is set WHEN the full test suite runs THEN the mutating-method spy records zero invocations across all covered scenarios.

Technical Context:
- **Pattern:** existing test framework for the deploy command (framework TBD)
- **Files:** deploy command test directory
- **Dependencies:** S-1, S-2, S-3, S-4

Agent Hints:
- **Class:** builder (reviewer follow-up recommended given P0 stakes)
- **Context:** existing deploy command test suite structure
- **Gates:** zero-side-effect regression test is mandatory in CI on every future change touching the deploy command

---

#### 📋 STORY: S-6 Documentation — help text, runbook, CI usage example

**Description:** As a release engineer or CI author, I want documentation showing how and when to use `--dry-run` so I can adopt it correctly without reading source.
**Timebox:** 1d
**Risk:** 🔵 P2

Action Plan:
1. **Extend:** `--help` text with the new flag, its default, and its `--force` interaction.
2. **Modify:** the deployment runbook/README to recommend `--dry-run` before high-risk deploys.
3. **Create:** a CI pipeline example gating a release on `deploy --dry-run`'s exit code before the real `deploy` step.

Acceptance Criteria:
- [ ] GIVEN a user runs `deploy --help` WHEN output is inspected THEN `--dry-run` is documented with default value and `--force` interaction.
- [ ] GIVEN the runbook is reviewed THEN it includes a recommended-usage note and one CI example gating on `--dry-run`'s exit code.

Technical Context:
- **Files:** README/runbook + CLI help strings
- **Dependencies:** S-1, S-2, S-3, S-4

Agent Hints:
- **Class:** builder
- **Gates:** P2 docs reviewed against S-1..S-4 acceptance criteria

---

## ✅ VERIFICATION REPORT

| Layer | Check | Status |
|---|---|---|
| Structural | Hierarchy intact (Theme→Project→Feature→Story), no orphaned tasks, dependencies form a DAG (S-1 → S-2 → {S-3, S-4} → S-5/S-6) | ✓ |
| Self-Consistency | 3 alternative decompositions (6-story baseline; a 5-story variant merging S-3 into S-2; a 7-story variant splitting S-5 into unit/integration) converge on the same core substance — parse flag, gate side effects, render banner, preserve exit codes, prove parity, document. ~75–80% overlap | ✓ (≥70%) |
| Dependency | File paths and exact framework are **placeholders** — the consumer project has no application source yet (confirmed: only Eidolons scaffolding + empty git history at `/tmp/spectra-pilot`). Call-site enumeration is deliberately deferred to S-2 step 1 | ⚠ PARTIAL — documented [GAP], not silently assumed |
| Constraint | No-mutation guarantee, exit-code parity, backward compatibility, CI-gating all addressed; timeboxes sum to ~10d across 6 stories (realistic for a scoped CLI feature); no new compliance surface introduced (A4) | ✓ |
| Process Reward | Ordering front-loads the P0 safety stories (S-2, S-4) before UX polish (S-3), then hardens them (S-5) before documenting finished behavior (S-6) | ✓ |
| Adversarial | Skeptical reviewer's top challenge — "how do you guarantee EVERY side-effecting call is gated?" — answered by S-2's explicit audit step + S-5's spy-based regression backstop (structural, not review-only) | ✓ |

**Self-Consistency:** ~75–80% overlap
**Constraints:** 5/6 layers clean pass; 1/6 partial with an explicit, tracked [GAP]
**Gate:** Minor gap → **REFINE (1 cycle)**

**Adversarial checklist against the Failure Taxonomy:**
- Under-specification — mitigated: GIVEN/WHEN/THEN throughout.
- Over-specification — none: action plans stay framework-agnostic.
- Dependency blindness — explicitly flagged in the Dependency layer above, not hidden.
- Assumption drift — A1's risk-if-wrong is directly resolved by S-2 step 1 (audit), which would trigger a Patch-level replan if the assumption is wrong.
- Scope creep — bounded: H2/H3/H4 explicitly named as Out of Scope/Deferred.
- Premature optimization — none: H1 (simplest viable option) was selected over more elaborate alternatives.
- Stale context — N/A, first-pass spec.

## 🔄 REFINEMENT LOG

### Cycle 1

| Dimension | Before | After | Change |
|---|---|---|---|
| Clarity | 5 | 5 | No change needed — stories already concrete, jargon-free |
| Completeness | 3 | 4 | Converted the unresolved file-path unknown from an implicit assumption into an explicit [GAP] + confidence-tier decision; confirmed `--force` interaction is a named acceptance criterion (S-1 AC-3), not an open question |
| Actionability | 3 | 4 | S-2 step 1 (audit/enumerate side-effecting calls) is framed as the resolving action for A1 — an agent can start today without waiting on a human to confirm file paths first |
| Efficiency | 5 | 5 | H1 remains the minimal-footprint solution; no waste introduced |
| Testability | 5 | 5 | GIVEN/WHEN/THEN throughout; S-5 adds a structural (not just reviewed) safety backstop |

**Diagnosis:** Dependency layer flagged that file paths/framework are unverifiable because this consumer project has no real deploy-command implementation yet.
**Prescription:** Name the gap explicitly, route it to VALIDATE-tier confidence (human confirms the real entrypoint before Construct-phase execution begins) rather than either hiding it or blocking the whole spec on it.
**Exit:** All dimensions ≥4 — cycle 1 target met (and cycle 2's target incidentally already met too); further cycles would show diminishing returns since the remaining gap needs a real codebase, not more writing. No oscillation detected (no dimension decreased).

## 📊 CONFIDENCE ASSESSMENT

| Factor | Score |
|---|---|
| Pattern Match | 2/3 — no in-repo pattern (blank scaffold), but a well-established external precedent (`kubectl`/`terraform` dry-run) grounds the design |
| Requirement Clarity | 2/3 — WHAT/WHY are clear; exact target-system shape (single vs multi-environment) is a named [GAP] |
| Decomposition Stability | 3/3 — ≥70% overlap across 3 alternative decompositions |
| Constraint Compliance | 2/3 — 5/6 verification layers clean; Dependency layer partial with a tracked gap |

**Weighted Confidence:** 9/12 → **75%**
**Decision:** **VALIDATE** — deliver with flags for human review.

**Gaps:**
- [GAP] Real deploy-command entrypoint/file structure is unknown — confirm before Construct-phase execution starts (S-2 step 1's audit is the designed way to resolve this).
- [GAP] Single vs. multi-target/environment fan-out for the deploy command is unconfirmed — affects whether S-3's per-target grouping is a loop or trivial.

---

## Agent Handoff (YAML)

```yaml
metadata:
  spec_id: "SPEC-2026-07-04-001"
  confidence: 75
  complexity: 8
  spectra_version: "4.11.0"

projects:
  - id: "P-1"
    name: "Deployment Command Safety Enhancements"
    features:
      - id: "F-1"
        name: "--dry-run flag for the deploy command"
        stories:
          - id: "S-1"
            title: "CLI flag registration"
            timebox: "1d"
            risk: "P1"
            action_plan:
              - verb: "Extend"
                target: "deploy command argument parser to accept --dry-run (bool, default false)"
              - verb: "Configure"
                target: "thread dry_run into execution context"
              - verb: "Validate"
                target: "--force interaction policy under --dry-run"
              - verb: "Test"
                target: "flag parsing: default / explicit / combined with other flags"
            acceptance_criteria:
              - given: "the deploy command is invoked"
                when: "--dry-run is passed"
                then: "execution context records dry_run=true, no error raised"
              - given: "the deploy command is invoked"
                when: "--dry-run is omitted"
                then: "dry_run defaults to false, behavior unchanged"
              - given: "--dry-run and --force are both passed"
                when: "the command starts"
                then: "a warning prints that --force has no effect; execution proceeds as a dry run, never escalates to a real deploy"
            agent_hints:
              recommended_class: "builder"
              context_files: ["<deploy-command-entrypoint> (path TBD, see [GAP])"]
              validation_gates:
                p0: "flag parses correctly"
                coverage: "default + explicit + combined-flag cases"
            dependencies: []

          - id: "S-2"
            title: "Gate every side-effecting action behind the flag"
            timebox: "≤3d"
            risk: "P0"
            action_plan:
              - verb: "Identify"
                target: "audit + enumerate every side-effecting call site in the execution stage"
              - verb: "Extend"
                target: "guard each call site on context.dry_run; log would-do action instead of executing"
              - verb: "Modify"
                target: "keep validate/plan stages unconditional and unchanged"
              - verb: "Test"
                target: "one zero-invocation test per identified call site"
            acceptance_criteria:
              - given: "--dry-run is set"
                when: "the command runs to completion"
                then: "zero mutating network calls or filesystem writes occur (mock/spy verified)"
              - given: "--dry-run is set"
                when: "a side-effecting call site is reached"
                then: "a log line records the action that would have executed"
              - given: "--dry-run is NOT set"
                when: "the command runs"
                then: "behavior is identical to the pre-feature implementation"
            agent_hints:
              recommended_class: "builder"
              context_files: ["deploy executor/orchestrator module (path TBD, see [GAP])"]
              validation_gates:
                p0: "audit completeness — every side-effecting site enumerated"
                coverage: "both dry-run and real-run branches"
            dependencies: ["S-1"]

          - id: "S-3"
            title: "Dry-run output — unambiguous simulation banner + action summary"
            timebox: "≤2d"
            risk: "P1"
            action_plan:
              - verb: "Create"
                target: "summary renderer grouped by target/resource (create/update/delete/no-op)"
              - verb: "Extend"
                target: "prominent start+end banner: no changes were applied"
              - verb: "Configure"
                target: "honor existing --verbose flag for detail level"
              - verb: "Test"
                target: "snapshot tests for summary format + banner presence"
            acceptance_criteria:
              - given: "--dry-run is set"
                when: "the command completes"
                then: "output includes a no-changes-applied banner at both start and end"
              - given: "--dry-run is set"
                when: "the plan stage identifies N planned actions"
                then: "the summary lists all N, grouped by operation type"
              - given: "--dry-run and --verbose are both set"
                when: "the command runs"
                then: "the summary includes per-action detail, not counts only"
            agent_hints:
              recommended_class: "builder"
              context_files: ["existing --verbose output formatting code"]
              validation_gates:
                p1: "banner presence tested"
                coverage: "verbose + non-verbose paths"
            dependencies: ["S-2"]

          - id: "S-4"
            title: "Exit-code parity for CI gating"
            timebox: "1d"
            risk: "P0"
            action_plan:
              - verb: "Modify"
                target: "confirm exit-code logic in validate/plan stages is dry_run-agnostic"
              - verb: "Test"
                target: "integration: invalid config + --dry-run exits same non-zero code as real-run failure"
              - verb: "Test"
                target: "integration: valid config + --dry-run exits 0"
            acceptance_criteria:
              - given: "an invalid configuration"
                when: "--dry-run is set"
                then: "the command exits with the same non-zero code as the equivalent real-run failure"
              - given: "a valid configuration"
                when: "--dry-run is set and the plan succeeds"
                then: "the command exits 0"
              - given: "a valid configuration"
                when: "--dry-run is NOT set"
                then: "exit-code behavior is unchanged from the pre-feature baseline"
            agent_hints:
              recommended_class: "builder"
              context_files: ["existing exit-code tests for real-run failures"]
              validation_gates:
                p0: "CI-gating correctness — no false-positive 0 on a bad dry-run plan"
                coverage: "success + failure paths"
            dependencies: ["S-2"]

          - id: "S-5"
            title: "Parity + regression test suite"
            timebox: "≤2d"
            risk: "P0"
            action_plan:
              - verb: "Test"
                target: "consolidate S-1..S-4 unit tests into a dedicated dry-run test module"
              - verb: "Create"
                target: "integration test: same scenario dry-run vs real-run, assert plan output identical"
              - verb: "Create"
                target: "zero-side-effects regression test via mutating-method spy"
            acceptance_criteria:
              - given: "the same deploy inputs"
                when: "run once with --dry-run and once without"
                then: "the plan/validation portion of output is identical"
              - given: "--dry-run is set"
                when: "the full test suite runs"
                then: "the mutating-method spy records zero invocations across success, validation-failure, and partial-target-failure scenarios"
            agent_hints:
              recommended_class: "builder"
              context_files: ["existing deploy command test suite structure"]
              validation_gates:
                p0: "zero-side-effect regression test mandatory in CI on every future change to the deploy command"
            dependencies: ["S-1", "S-2", "S-3", "S-4"]

          - id: "S-6"
            title: "Documentation — help text, runbook, CI usage example"
            timebox: "1d"
            risk: "P2"
            action_plan:
              - verb: "Extend"
                target: "--help text with the new flag, default, and --force interaction"
              - verb: "Modify"
                target: "deployment runbook/README recommended-usage section"
              - verb: "Create"
                target: "CI pipeline example gating on deploy --dry-run's exit code"
            acceptance_criteria:
              - given: "a user runs deploy --help"
                when: "output is inspected"
                then: "--dry-run is documented with default value and --force interaction"
              - given: "the deployment runbook"
                when: "reviewed"
                then: "it includes a recommended-usage note and one CI example gating on --dry-run's exit code"
            agent_hints:
              recommended_class: "builder"
              context_files: ["existing help-text conventions"]
              validation_gates:
                p2: "docs reviewed against S-1..S-4 acceptance criteria"
            dependencies: ["S-1", "S-2", "S-3", "S-4"]

execution_plan:
  phases:
    - name: "Foundation — flag + safety gate"
      stories: ["S-1", "S-2"]
      agent_class: "builder"
    - name: "UX + CI integration"
      stories: ["S-3", "S-4"]
      agent_class: "builder"
    - name: "Hardening + docs"
      stories: ["S-5", "S-6"]
      agent_class: "builder"
```

## State Machine (JSON)

```json
{
  "session_id": "spectra-2026-07-04-dry-run-deploy-flag",
  "spec_id": "SPEC-2026-07-04-001",
  "goal": "Add a --dry-run flag to the deployment command: preview planned actions, guarantee zero side effects, preserve exit-code parity for CI gating.",
  "spectra_version": "4.11.0",
  "steps": [
    { "id": 1, "story_id": "S-1", "title": "CLI flag registration", "status": "pending", "dependencies": [], "files_affected": ["<deploy-command-entrypoint> (path TBD, see [GAP])"], "verification_command": "unit tests: flag parsing (default/explicit/combined)", "estimated_timebox": "1d", "replanning_notes": null },
    { "id": 2, "story_id": "S-2", "title": "Gate every side-effecting action behind the flag", "status": "pending", "dependencies": ["S-1"], "files_affected": ["deploy executor/orchestrator module (path TBD, see [GAP])"], "verification_command": "unit tests: zero-invocation spy per side-effecting call site", "estimated_timebox": "≤3d", "replanning_notes": null },
    { "id": 3, "story_id": "S-3", "title": "Dry-run output — simulation banner + action summary", "status": "pending", "dependencies": ["S-2"], "files_affected": ["output/reporting module (path TBD)"], "verification_command": "snapshot tests: banner presence + summary grouping", "estimated_timebox": "≤2d", "replanning_notes": null },
    { "id": 4, "story_id": "S-4", "title": "Exit-code parity for CI gating", "status": "pending", "dependencies": ["S-2"], "files_affected": ["deploy command entrypoint / error-handling module"], "verification_command": "integration tests: exit code parity (success + failure)", "estimated_timebox": "1d", "replanning_notes": null },
    { "id": 5, "story_id": "S-5", "title": "Parity + regression test suite", "status": "pending", "dependencies": ["S-1", "S-2", "S-3", "S-4"], "files_affected": ["deploy command test directory"], "verification_command": "integration test: dry-run vs real-run plan-output diff == empty; zero-side-effect spy", "estimated_timebox": "≤2d", "replanning_notes": null },
    { "id": 6, "story_id": "S-6", "title": "Documentation — help text, runbook, CI usage example", "status": "pending", "dependencies": ["S-1", "S-2", "S-3", "S-4"], "files_affected": ["README/runbook", "CLI help strings"], "verification_command": "manual review: --help output + runbook section present", "estimated_timebox": "1d", "replanning_notes": null }
  ],
  "current_step": 0,
  "completed_steps": [],
  "replanning_history": [
    {
      "cycle": 1,
      "trigger": "Dependency verification layer (Test phase) flagged file paths/framework as unresolved — consumer project has no application source yet",
      "action": "Converted the unknown into an explicit [GAP] + VALIDATE-tier confidence decision rather than blocking; S-2 step 1 (audit) is the designed resolving action",
      "result": "Refine cycle 1 exit: all 5 self-critique dimensions >= 4"
    }
  ]
}
```

## ECL Envelope (v2.0 sidecar — `ECL_VERSION` present in install root)

```json
{
  "envelope_version": "2.0",
  "message_id": "019f300c-2e7e-78a2-9f32-0d2edfff9d42",
  "thread_id": "019f300c-2e7e-72c0-bd07-142f00941446",
  "parent_id": null,
  "from": { "eidolon": "spectra", "version": "4.11.0" },
  "to": { "eidolon": "apivr", "version": "n/a" },
  "performative": "PROPOSE",
  "edge_origin": "roster",
  "objective": "Propose implementation spec for a --dry-run flag on the deployment command, targeting the consumer project's deploy CLI.",
  "artifact": {
    "kind": "spec",
    "schema_version": "1.0",
    "path": ".spectra/plans/2026-07-04-dry-run-deploy-flag.md",
    "sha256": "2a09e5661bb46524de77c06e1f67e2338ec887e2e61377079387fb3db180a3ea",
    "size_bytes": 21071
  },
  "context_delta": {
    "token_budget": 6000,
    "tokens_used": 0,
    "input_handles": [],
    "summary": "Spec adds a --dry-run flag to the deployment command via a flag-gated no-op execution stage (H1, selected over a two-tier client/server dry-run, a persisted plan-artifact workflow, and sandboxed real execution). 6 stories cover flag parsing, gating every side-effecting call, preview output, exit-code parity for CI gating, a parity/zero-side-effect regression suite, and docs. Confidence 75% (VALIDATE) — the one open gap is that this consumer project has no application source yet, so exact file paths/framework are placeholders pending confirmation of the real deploy command's location."
  },
  "constraints": { "trust_level": "standard" },
  "ise": {
    "assertion_grade": "self-attested",
    "provenance": { "methodology_version": "spectra-4.11.0", "tool_surface": ["Read", "Grep", "Glob", "Bash"], "lateral_consults": [] },
    "receiver_authorization": { "auto_route": true, "auto_merge": false, "auto_deploy": false }
  },
  "confidence": 0.75,
  "integrity": { "method": "sha256", "value": "2a09e5661bb46524de77c06e1f67e2338ec887e2e61377079387fb3db180a3ea" },
  "trace": { "ts": "2026-07-04T00:00:00Z", "host": "claude-code", "model": "claude-sonnet-5", "tier": "standard" }
}
```

*Note: the `sha256`/`integrity.value` above is the digest of the mirrored artifact `.spectra/plans/2026-07-04-dry-run-deploy-flag.md` (the canonical spec payload), not of this combined response file — per ECL, the integrity anchor is always the Markdown spec's own bytes at emit time, computed once against the artifact of record.*

---

## Preflight Checklist

- [x] CLARIFY ran (not skipped — see rationale above)
- [x] `spectra-conventions.md` checked — absent, generic defaults used and documented
- [x] Complexity scored (8/12), reasoning budget routed to Extended
- [x] 4 genuinely distinct hypotheses explored (conservative, industry-pattern, innovative, risk-minimizing)
- [x] All 6 stories pass INVEST
- [x] All timeboxes valid (1d/≤2d/≤3d, none >8d, no story points)
- [x] Hierarchy uses Project (not "Epic")
- [x] Acceptance criteria in GIVEN/WHEN/THEN throughout
- [x] Agent hints with context files per story
- [x] Dual output: Markdown + YAML + state JSON + ECL envelope
- [x] Confidence score present with factor breakdown (75%, VALIDATE)
- [x] Plan saved as artifact under `.spectra/plans/` (mirrored, per Output Discipline rule 2)
- [x] No code produced (plans only)
- [x] Rejected alternatives documented (H2, H3, H4 — with rationale)

*SPECTRA v4.11.0 — Strategic Specification through Deliberate Reasoning. Planning only, no code produced.*
