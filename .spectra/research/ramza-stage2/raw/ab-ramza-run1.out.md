---
eidolon: ramza
kind: spec
version: 0.1.0
created_at: 2026-07-05T02:06:53Z
---

# RAMZA run — `ab1-dryrun` — Add `--dry-run` to the deploy command

Working dir: `/tmp/ramza-e2e` · State: `.spectra/plans/ab1-dryrun.state.json`
(schema `ramza/plan-state.v1`) · Tier: **lite** · Final phase: **DONE**.

This document is the decision-ready deliverable: narrative cycle log first
(every gate run for real, output quoted verbatim), then the full plan
artefact (also persisted at `.spectra/plans/ab1-dryrun.plan.md`, with its
frozen criteria sidecar at `.spectra/plans/ab1-dryrun.acceptance.md` and its
ECL envelope at `.spectra/plans/ab1-dryrun.envelope.json`).

## Cycle log — every gate, run and quoted

### RS — Right-Size

Signals for "add `--dry-run` to a single deploy command, with tests":
`--files-est 4` (flag registration + guard in the execution path + tests +
`--help`/docs — squarely 3–9), `--public-api` (a new CLI flag is new
user-facing surface on an existing command), `--stakes med` (deployment
tooling is production-adjacent even though the flag itself is a preview).
No `--new-dep`, `--migration`, `--security`, or `--novel` — none apply.

```
$ ./.eidolons/ramza/bin/ramza-rightsize --files-est 4 --public-api --stakes med \
    --plan ab1-dryrun --state .spectra/plans/ab1-dryrun.state.json
state initialised: .spectra/plans/ab1-dryrun.state.json (tier: lite, score: 3)
lite
```

Score 3 = files-est(1) + public-api(1) + stakes-med(1) → **lite** (2–4 band),
matching the task's own estimate. Mandatory phases for lite: `RS S P E C T A`.

### S — Scope

```
$ ./.eidolons/ramza/bin/ramza-gate advance --state .spectra/plans/ab1-dryrun.state.json --to S
OK: RS -> S
```

Complexity scored honestly for a deploy-command change, not a trivial
identifier rename: `scope 1` (one command, contained), `ambiguity 2`
(what exactly "no side effects" covers — network calls, state writes,
notifications — needs a few real decisions), `dependencies 2` (the guard has
to sit correctly relative to several internal call sites in the deploy
path), `risk 2` (a dry-run that's wrong gives false confidence in a
deployment tool, which is a real cost even though the feature itself is a
safety mechanism).

```
$ echo '{"scope":1,"ambiguity":2,"dependencies":2,"risk":2}' | \
    ./.eidolons/ramza/bin/ramza-score --rubric complexity \
    --state .spectra/plans/ab1-dryrun.state.json --label "dryrun-scope-complexity"
calibration log appended: .spectra/plans/ramza-calibration.jsonl
{
  "rubric": "complexity",
  "total": 7,
  "dims": { "scope": 1, "ambiguity": 2, "dependencies": 2, "risk": 2 },
  "verdict": "extended",
  "at": "2026-07-05T02:07:23Z",
  "label": "dryrun-scope-complexity"
}
```

7/12 → **extended** reasoning routing (7–9 band) — appropriate: more than a
rename, less than a human-in-the-loop change.

### P — Pattern

```
$ ./.eidolons/ramza/bin/ramza-gate advance --state .spectra/plans/ab1-dryrun.state.json --to P
OK: S -> P
```

Searched this consumer project (`/tmp/ramza-e2e`, excluding `.eidolons/` and
`.git/`) for any existing deploy command, CLI arg parser, or "plan object"
pattern to reuse: **none found** — the repo ships `eidolons.yaml`/`.lock`,
`.claude/`, and `.spectra/` only, no deploy implementation. Match tier:
**<60% → generate**, not template/adapt. This absence is carried forward
honestly into both the plan's Assumptions and the Confidence score's
`pattern_match` dimension (scored low, not inflated) rather than pretended
away.

### E — Explore

Four genuinely distinct hypotheses scored — one conservative (A), one
pattern-leveraging (B), one innovative (C), one deliberately-different
architecture kept as the "why not a subcommand" answer (D):

```
$ ./.eidolons/ramza/bin/ramza-gate advance --state .spectra/plans/ab1-dryrun.state.json --to E
OK: P -> E

$ echo '{"alignment":9,"correctness":8,"maintainability":8,"performance":9,"simplicity":9,"risk":8,"innovation":3}' | \
    ./.eidolons/ramza/bin/ramza-score --rubric explore --state .spectra/plans/ab1-dryrun.state.json --label "hyp-A-early-return-flag"
{
  "rubric": "explore", "total": 82.5,
  "dims": {"alignment":9,"correctness":8,"maintainability":8,"performance":9,"simplicity":9,"risk":8,"innovation":3},
  "verdict": "solid", "at": "2026-07-05T02:08:11Z", "label": "hyp-A-early-return-flag"
}

$ echo '{"alignment":8,"correctness":7,"maintainability":9,"performance":9,"simplicity":6,"risk":6,"innovation":5}' | \
    ./.eidolons/ramza/bin/ramza-score --rubric explore --state .spectra/plans/ab1-dryrun.state.json --label "hyp-B-reuse-plan-object"
{
  "rubric": "explore", "total": 75.5,
  "dims": {"alignment":8,"correctness":7,"maintainability":9,"performance":9,"simplicity":6,"risk":6,"innovation":5},
  "verdict": "solid", "at": "2026-07-05T02:08:11Z", "label": "hyp-B-reuse-plan-object"
}

$ echo '{"alignment":8,"correctness":9,"maintainability":6,"performance":6,"simplicity":4,"risk":5,"innovation":9}' | \
    ./.eidolons/ramza/bin/ramza-score --rubric explore --state .spectra/plans/ab1-dryrun.state.json --label "hyp-C-recording-adapter"
{
  "rubric": "explore", "total": 69.5,
  "dims": {"alignment":8,"correctness":9,"maintainability":6,"performance":6,"simplicity":4,"risk":5,"innovation":9},
  "verdict": "weak", "at": "2026-07-05T02:08:11Z", "label": "hyp-C-recording-adapter"
}

$ echo '{"alignment":5,"correctness":7,"maintainability":4,"performance":8,"simplicity":5,"risk":4,"innovation":4}' | \
    ./.eidolons/ramza/bin/ramza-score --rubric explore --state .spectra/plans/ab1-dryrun.state.json --label "hyp-D-separate-subcommand"
{
  "rubric": "explore", "total": 55.5,
  "dims": {"alignment":5,"correctness":7,"maintainability":4,"performance":8,"simplicity":5,"risk":4,"innovation":4},
  "verdict": "weak", "at": "2026-07-05T02:08:11Z", "label": "hyp-D-separate-subcommand"
}
```

Spread is 82.5 → 55.5 (well past the "all within 5%" re-observe trigger —
no re-observation needed). **A wins** (82.5, `solid`). B is `solid` too
(75.5) but rejected for *this* pass on an unconfirmed assumption. C and D
both landed `weak` (<70) — the tool's own verdict is the mechanical
rejection rationale, not a judgment call layered on after the fact. All four
carried into Rejected Alternatives below (B, C, D) with their exact
per-dimension scores.

### C — Construct

```
$ ./.eidolons/ramza/bin/ramza-gate advance --state .spectra/plans/ab1-dryrun.state.json --to C
OK: E -> C
```

Full output is the plan artefact below: 3 stories (timeboxes, risk tags,
executor hints) + 6 EARS acceptance criteria.

### T — Test

```
$ ./.eidolons/ramza/bin/ramza-gate advance --state .spectra/plans/ab1-dryrun.state.json --to T
OK: C -> T

$ ./.eidolons/ramza/bin/ramza-lint --plan .spectra/plans/ab1-dryrun.plan.md --state .spectra/plans/ab1-dryrun.state.json
ok: plan passes structural lint (tier: lite)

$ ./.eidolons/ramza/bin/ramza-ears-lint .spectra/plans/ab1-dryrun.acceptance.md
ok: 6 criteria pass EARS lint
```

Both structural (lite: Scope/Approach/Acceptance Criteria/Stories/Confidence)
and EARS-grammar lints are green, exit 0. Lite tier does not mandate an
independent critic (full tier does); none was fabricated — there is no
second identity in this single-agent session, and inventing one would
violate maker≠checker rather than satisfy it. No refine cycle was needed
(gates were clean on the first pass).

### A — Assemble

```
$ ./.eidolons/ramza/bin/ramza-gate advance --state .spectra/plans/ab1-dryrun.state.json --to A
OK: T -> A

$ echo '{"pattern_match":55,"requirement_clarity":90,"decomposition_stability":65,"constraint_compliance":95}' | \
    ./.eidolons/ramza/bin/ramza-score --rubric confidence --state .spectra/plans/ab1-dryrun.state.json --label "ab1-dryrun-assemble-confidence"
{
  "rubric": "confidence", "total": 76.25,
  "dims": {"pattern_match":55,"requirement_clarity":90,"decomposition_stability":65,"constraint_compliance":95},
  "verdict": "VALIDATE", "at": "2026-07-05T02:10:38Z", "label": "ab1-dryrun-assemble-confidence"
}

$ ./.eidolons/ramza/bin/ramza-drift --state .spectra/plans/ab1-dryrun.state.json \
    --declare 'cli/commands/deploy.* lib/deploy/* tests/deploy/* docs/cli-reference.md'
scope declared: 4 glob(s)

$ ./.eidolons/ramza/bin/ramza-freeze --state .spectra/plans/ab1-dryrun.state.json \
    --criteria .spectra/plans/ab1-dryrun.acceptance.md
frozen: 393a8ffda79ff5a1b556735ada8d856889f3397dcccae5bae871bdc0e5fb87d0

$ ./.eidolons/ramza/bin/ramza-verify-emit --spec .spectra/plans/ab1-dryrun.plan.md \
    --envelope .spectra/plans/ab1-dryrun.envelope.json
ok: emission gate passed (ab1-dryrun.plan.md + envelope)

$ ./.eidolons/ramza/bin/ramza-gate advance --state .spectra/plans/ab1-dryrun.state.json --to DONE
OK: A -> DONE
```

**76.25% → VALIDATE** (70–84 band), not AUTO_PROCEED — deliberately: the
`pattern_match` dimension is honestly scored 55 because Pattern (P) found no
real deploy-command code in this repo to confirm the assumed module layout
against. VALIDATE means a human reviews before an executor starts Story 1;
that's the correct verdict here, not an inflated one.

`ECL_VERSION` (`2.0`) is present at `.eidolons/ramza/ECL_VERSION`, so the ECL
envelope sidecar was emitted per `templates/planning-artifact.md` and
validated by `ramza-verify-emit` alongside the spec's frontmatter contract —
both green.

Final `ramza-gate status`:

```
{
  "plan": "ab1-dryrun",
  "tier": "lite",
  "phase": "DONE",
  "next": "DONE",
  "refine_cycles": 0,
  "skips": [],
  "criteria_frozen": true
}
```

## Preflight (self-check against `agent.md`)

- [x] RS ran; tier recorded (lite, score 3, no override needed)
- [x] Phase walk clean in state: `RS S P E C T A DONE` — no unexplained skips (`skips: []`)
- [x] Hypotheses scored via tool (4, lite requires 3); rejected alternatives documented with real scores
- [x] `ramza-lint` + `ramza-ears-lint` green
- [ ] Full tier critic — N/A, this is lite tier (not required; not fabricated)
- [x] Confidence computed via tool (76.25% → VALIDATE); verdict honored (spec explicitly flags human review needed, doesn't overclaim AUTO_PROCEED)
- [x] Scope declared (4 globs); criteria frozen (sha256 `393a8f…7d0`); `ramza-verify-emit` green
- [x] Every output path under `.spectra/` (`ab1-dryrun.plan.md`, `.acceptance.md`, `.envelope.json`, `.state.json`); no code produced — plans only

---

# Plan: Add `--dry-run` to the deploy command

*(Full text of `.spectra/plans/ab1-dryrun.plan.md`, frontmatter included — this is the artefact `ramza-verify-emit` validated above.)*

## Scope

Intent class: CHANGE

In: Add a `--dry-run` boolean flag to the project's existing `deploy` command.
When set, the command performs the same validation/target-resolution/planning
steps as a real deploy, prints a structured plan of every action it would take,
and returns before invoking any action that mutates the target environment.
Covers: flag registration, the no-mutation guard on the deploy execution path,
`--help` documentation, and test coverage for the new flag's behavior
(including interaction with other execution-triggering flags).

Out: No new subcommand (e.g. no `deploy plan`); no change to the real (non
dry-run) deploy behavior; no change to deploy authN/authZ; no rollback
tooling; no machine-readable (JSON) dry-run output in this iteration.

Deferred: JSON/machine-readable dry-run output for CI consumption — noted as
a plausible fast-follow in Risks, not required to close this spec.

Assumptions:
- The deploy command's exact module layout (arg parser, execution engine,
  test locations) was not confirmed against real project code — Pattern (P)
  search of this repo found no existing `deploy` implementation to inspect
  (this consumer project ships no deployment code today). Illustrative paths
  below (`tests/deploy/*`, etc.) stand in for the real ones.
  Risk if wrong: the executor's action plan (file-level steps) needs revision
  once real call sites are known; captured in Risks and reflected in the
  Confidence score below (`pattern_match` scored low for exactly this reason).
- The deploy command already performs some ordered
  validate → resolve-target → plan-actions → execute sequence before any
  mutating call, even if that sequence is not factored into a reusable
  object today. Risk if wrong: the guard described in Approach may need to
  move earlier if validation and execution are currently interleaved rather
  than staged.

Complexity (`ramza-score --rubric complexity`): 7/12 → extended (dims:
scope 1, ambiguity 2, dependencies 2, risk 2 — recorded in
`.spectra/plans/ab1-dryrun.state.json` gates[], label
`dryrun-scope-complexity`).

## Approach

Selected: **Hyp A — flag-guarded early return before the first mutating
call** (Explore score 82.5/100, verdict `solid` — highest of four scored
hypotheses; see Rejected Alternatives).

1. Register `--dry-run` (boolean, default `false`) on the `deploy` command's
   existing flag parser, alongside its other flags.
2. Thread the flag value through to the point in the deploy command's
   execution path immediately *before* the first side-effecting call
   (artifact upload / service restart / registry or DNS update / whatever the
   command's first mutating action is).
3. Leave every step before that point untouched: config load, target
   resolution, and pre-flight validation all run exactly as they do today —
   this is what gives dry-run and real-run identical failure behavior for
   AC-003.
4. At the guard point: if `--dry-run` is set, render the computed plan (the
   ordered list of actions the command was about to take) to stdout and
   return/exit before any mutating call executes. If not set, proceed as
   today.
5. `--dry-run` wins over any execution-triggering flag (`--yes`, `--force`,
   etc.) encountered in the same invocation — the guard checks `--dry-run`
   first, unconditionally, regardless of what else was passed (AC-004).
6. Add the flag to the command's `--help` text with a one-line, unambiguous
   no-mutation guarantee (AC-005).
7. Add tests asserting: plan is printed (AC-001), no mutating adapter call
   fires (AC-002), validation-failure exit code parity (AC-003), flag
   precedence (AC-004), help text (AC-005), and exit-code-zero-on-clean-plan
   (AC-006).

This is deliberately the *simplest* correct approach at this scope: no new
abstraction layer, no new subcommand, no dependency on an unconfirmed
internal "plan object" refactor. The follow-up in Risks names where Hyp B's
idea (extracting a reusable plan/execute split) would pay off later without
being a prerequisite now.

## Stories

### Story 1: Preview a deploy before running it for real

As a release engineer, I want to pass `--dry-run` to the deploy command, so
that I can see exactly what it would do to the target environment without
making any real change.

Timebox: 2d.
Risk tag: P1.
Executor hint: mid tier — file-level action plan given in Approach above;
follow the guard-placement pattern, no further scaffolding needed.

### Story 2: Gate CI on a dry-run before merge

As a CI pipeline maintainer, I want `deploy --dry-run` to fail the same way
a real deploy would on bad config, so that pre-merge checks catch
deployment-config errors without ever touching the target environment.

Timebox: 1d.
Risk tag: P1.
Executor hint: mid tier — reuse the existing validation code path unchanged
(see Approach step 3); add the parity test named in AC-003.

### Story 3: Trust that dry-run truly does nothing

As an on-call engineer, I want a hard guarantee that `--dry-run` never
performs a mutating action — even if I also pass `--force` — so that I can
run it safely at any time, including against production, without fear of
triggering a real deploy.

Timebox: 1d.
Risk tag: P0.
Executor hint: mid tier — implement the flag-precedence check in Approach
step 5 and the adapter-call assertion in AC-002/AC-004's tests; this story's
tests are the ones most worth a second reviewer's eyes given the P0 tag.

## Acceptance Criteria

### AC-001 (event-driven)
GIVEN a valid deploy target and a valid deploy configuration
WHEN  the deploy command is invoked with `--dry-run`
THEN  the command SHALL print a structured plan listing every action it would perform, in the same order it would execute them
VERIFY: test: tests/deploy/dry_run_spec#prints_plan_summary

### AC-002 (unwanted-behavior)
GIVEN a valid deploy target and a valid deploy configuration
WHEN  the deploy command is invoked with `--dry-run`
THEN  the command SHALL NOT invoke any deploy-adapter call that mutates the target environment
VERIFY: test: tests/deploy/dry_run_spec#no_mutating_calls_invoked

### AC-003 (unwanted-behavior)
GIVEN a deploy configuration that would fail pre-flight validation on a real deploy
WHEN  the deploy command is invoked with `--dry-run`
THEN  the command SHALL exit with the identical non-zero validation-failure exit code the real deploy would return
VERIFY: test: tests/deploy/dry_run_spec#surfaces_validation_failure_parity

### AC-004 (event-driven)
GIVEN the deploy command is invoked with both `--dry-run` and any execution-triggering flag such as `--yes` or `--force`
WHEN  the command finishes parsing its flags
THEN  the command SHALL treat `--dry-run` as authoritative and skip every mutating action regardless of the other flags present
VERIFY: test: tests/deploy/dry_run_spec#dry_run_overrides_force

### AC-005 (ubiquitous)
THEN the deploy command's `--help` output SHALL document `--dry-run` with a one-line description stating it performs no mutating action
VERIFY: test: tests/deploy/help_spec#documents_dry_run_flag

### AC-006 (optional-feature)
GIVEN the deploy command supports the `--dry-run` feature
THEN the command SHALL exit `0` whenever it produces a clean plan, reserving any non-zero code for a plan-computation or validation failure rather than for the mere absence of a real deploy
VERIFY: test: tests/deploy/dry_run_spec#exit_code_zero_on_clean_plan

*(Byte-identical to the frozen `.spectra/plans/ab1-dryrun.acceptance.md` —
`ramza-ears-lint` reports `ok: 6 criteria pass EARS lint` against that file;
`ramza-freeze` recorded its sha256 as
`393a8ffda79ff5a1b556735ada8d856889f3397dcccae5bae871bdc0e5fb87d0`.)*

## Confidence

`ramza-score --rubric confidence`: 76.25% → **VALIDATE** (human reviews)
— dims: pattern_match 55, requirement_clarity 90, decomposition_stability 65,
constraint_compliance 95 (recorded in state, label
`ab1-dryrun-assemble-confidence`). Scored VALIDATE rather than AUTO_PROCEED
specifically because `pattern_match` is honestly low: no real deploy-command
code exists in this repo to confirm the assumed module layout against
(see Scope → Assumptions). A human should confirm the actual call sites
before an executor starts Story 1.

## Rejected Alternatives

- **Hyp B — reuse an existing plan/execute separation** —
  `ramza-score --rubric explore` total 75.5 (`solid`, dims: alignment 8,
  correctness 7, maintainability 9, performance 9, simplicity 6, risk 6,
  innovation 5). Would be the *better* long-term shape (best
  maintainability score of the four), but it assumes the deploy command
  already factors its logic into a reusable plan object — an assumption
  Pattern (P) could not confirm in this repo. Not rejected on merit; deferred
  as a natural follow-up refactor once the guard from Hyp A is in place and
  the real internals are visible (see Risks).
- **Hyp C — swap the deploy adapter for a recording/no-op backend (DI)** —
  total 69.5 (`weak`, dims: alignment 8, correctness 9, maintainability 6,
  performance 6, simplicity 4, risk 5, innovation 9). Highest correctness
  and innovation of the four — it would exercise the exact same code path
  end-to-end — but scored `weak` overall: the new adapter-swap abstraction is
  disproportionate ceremony for a single lite-tier CLI flag, and the
  in-repo pattern to hang it on doesn't exist yet. Rejected for this scope;
  worth reconsidering only if the command grows enough adapters that a
  recording backend pays for itself elsewhere too.
- **Hyp D — a separate `deploy plan` subcommand instead of a flag** —
  total 55.5 (`weak`, dims: alignment 5, correctness 7, maintainability 4,
  performance 8, simplicity 5, risk 4, innovation 4). Rejected: lowest
  alignment score of the four (the ask was explicitly a flag on the
  existing command, not a parallel command), and lowest maintainability —
  a second command means the deploy logic can silently drift out of sync
  with its "plan" twin over time, which is exactly the class of bug a
  dry-run flag exists to prevent.

## Risks

| Risk | Tag | Mitigation |
|---|---|---|
| Assumed module layout (no real deploy code found in-repo) turns out wrong | P1 | Confidence scored VALIDATE, not AUTO_PROCEED, for this reason; human/executor confirms real call sites before Story 1 starts; re-run `ramza-drift` once real file paths are known and amend declared scope if they differ. |
| `--dry-run` silently ignored or mis-parsed when combined with other flags, causing an accidental real deploy | P0 | AC-004 + Story 3's explicit flag-precedence test matrix; treat any regression here as a P0 bug, not a style nit. |
| Dry-run code path silently diverges from the real path over time (two branches drift apart, dry-run stops being trustworthy) | P1 | Approach keeps validation/target-resolution shared and untouched (only branches at the last mutating-call guard); Hyp B's plan/execute extraction (Rejected Alternatives) is the natural follow-up once internals are confirmed, precisely to close this gap for good. |
| Deferred JSON output request arrives later and gets bolted on inconsistently | P2 | Out-of-scope note above; if requested, right-size it as its own RS pass rather than silently expanding this plan's frozen criteria. |

---

## Artefact inventory (all under `.spectra/`, `/tmp/ramza-e2e`)

- `.spectra/plans/ab1-dryrun.state.json` — audit trail (schema `ramza/plan-state.v1`), phase `DONE`, `criteria_frozen: true`.
- `.spectra/plans/ab1-dryrun.plan.md` — this Markdown spec (frontmatter: `eidolon: ramza`, `kind: spec`, `version: 0.1.0`, `created_at`).
- `.spectra/plans/ab1-dryrun.acceptance.md` — frozen EARS criteria (sha256 `393a8ffda79ff5a1b556735ada8d856889f3397dcccae5bae871bdc0e5fb87d0`).
- `.spectra/plans/ab1-dryrun.envelope.json` — ECL v2.0 envelope sidecar (`performative: PROPOSE`, `integrity.value` matches the spec's recomputed sha256 `f37f31aaf2e05eff5fe37a7452c19bc1c81e7f0d8b0141e074028c544e8083bf`), validated by `ramza-verify-emit`.
- `.spectra/plans/ramza-calibration.jsonl` — appended calibration entries for every `ramza-score` call above.

No `plan.json` (Junction dispatch plan) was emitted — this consumer project
carries no Junction harness config, so per `templates/planning-artifact.md`
that artefact is a graceful no-op, not an omission.
