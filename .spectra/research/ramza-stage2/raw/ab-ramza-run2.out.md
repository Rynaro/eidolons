# RAMZA run: `--dry-run` flag for the deployment command

Mission: produce a decision-ready spec for adding a `--dry-run` flag to a
deployment command, with user stories, EARS validation/acceptance gates, and
at least one rejected alternative. Executed READ-ONLY from `/tmp/ramza-e2e`
per `agent.md`'s hard rules — no code, no edits outside `.spectra/`. All
gate/lint/freeze calls below are real invocations of the executables in
`/tmp/ramza-e2e/.eidolons/ramza/bin/`, not role-played scores. Plan slug:
`ab2-dryrun`. State file:
`/tmp/ramza-e2e/.spectra/plans/ab2-dryrun.state.json`.

## Narrative: the cycle as actually run

**RS — Right-size.**
```
$ ./.eidolons/ramza/bin/ramza-rightsize --files-est 5 --public-api --stakes med \
    --plan ab2-dryrun --state .spectra/plans/ab2-dryrun.state.json
state initialised: .spectra/plans/ab2-dryrun.state.json (tier: lite, score: 3)
lite
```
Inputs, honestly estimated for a single-command CLI flag with tests:
`files-est 5` (touches the flag parser, the executor boundary, the deploy
command's help text, and a new test file — 3–9 range, 1 point), `--public-api`
set (a CLI flag is part of the command's user-facing interface contract, +1),
`--stakes med` (the flag lives on a deployment command — operationally
important surface — even though the flag itself is additive/opt-in, +1). No
`--new-dep`, `--migration`, `--security`, or `--novel` — none apply. Score 3 →
**lite**, confirming the mission's own estimate. Mandatory phases for lite:
RS S P E C T A.

**S — Scope**, complexity via `ramza-score`:
```
$ echo '{"scope":1,"ambiguity":1,"dependencies":2,"risk":2}' | \
    ./.eidolons/ramza/bin/ramza-score --rubric complexity --state <state> --label dryrun-scope-complexity
{"rubric":"complexity","total":6,"dims":{"scope":1,"ambiguity":1,"dependencies":2,"risk":2},
 "verdict":"standard","label":"dryrun-scope-complexity"}
```
6/12 → standard routing. `dependencies` and `risk` scored 2 (not 1) because a
dry-run flag must thread cleanly through every existing side-effecting call
site in the deploy pipeline without missing one or causing behavior drift —
that is a real, non-trivial dependency surface even for a single flag.

**P — Pattern.** Searched this consumer project for prior dry-run/CLI-flag
precedent (`grep -ril "deploy"`, directory walk under `/tmp/ramza-e2e`): the
project tree contains no application source at all — only the eidolons/RAMZA
scaffold and `.spectra/`. No internal pattern to reuse exists. Recorded
honestly as an assumption/risk in the plan rather than fabricated; the
Approach instead follows established cross-tool convention for `--dry-run`
flags (`terraform plan`, `kubectl apply --dry-run`, `npm publish --dry-run`,
`git push --dry-run`).

**E — Explore**, three genuinely distinct hypotheses, each scored with
`ramza-score --rubric explore`:

| Hypothesis | alignment | correctness | maintainability | performance | simplicity | risk | innovation | **total** | verdict |
|---|---|---|---|---|---|---|---|---|---|
| H1 — in-line flag-guarded short-circuit (thread `dry_run` through the existing executor boundary) | 9 | 8 | 7 | 9 | 8 | 7 | 4 | **79.5** | solid |
| H2 — separate, duplicated preview/plan code path | 7 | 6 | 4 | 8 | 5 | 5 | 3 | **59** | weak |
| H3 — real execution redirected to a sandboxed staging target | 4 | 6 | 5 | 3 | 3 | 4 | 6 | **44** | weak |

Actual tool output for the winner:
```
{"rubric":"explore","total":79.5,"dims":{"alignment":9,"correctness":8,"maintainability":7,
 "performance":9,"simplicity":8,"risk":7,"innovation":4},"verdict":"solid",
 "label":"H1-flag-guarded-shortcircuit"}
```
H2 and H3 both landed `weak` (<70) — per `docs/methodology/scoring.md` that
verdict band means "rework or drop," and the tool correctly exited 1 on each
(that failure is the expected, intended outcome of scoring a hypothesis we go
on to reject, not a process error). H1 wins and becomes the Approach. H2 and
H3 are retained as rejected alternatives with their per-dimension rationale
(see plan artefact below) — this satisfies the "name at least one rejected
alternative" requirement with two, and neither is a strawman: H2 is a
legitimate reuse-vs-duplication trade-off, H3 is a real technique used by
some deploy tools (blue/green-style dry validation), rejected specifically on
alignment (it isn't actually "dry") and cost.

**C — Construct.** Three stories written (release engineer previewing a
deploy; release engineer trusting no side effect leaks through; on-call
engineer composing `--dry-run` with `--env`/`--version`/`--format json`),
each with a timebox, a P0–P2 risk tag, and a mid-tier executor hint
(file-level action plan, named pattern — appropriate density for a
Sonnet-class executor per `docs/methodology/tiers.md`'s executor-scaffold
table). Eight EARS-form acceptance criteria written to
`.spectra/plans/ab2-dryrun.criteria.md` covering all five closed forms
(event-driven ×4, unwanted-behavior ×2, ubiquitous ×1, optional-feature ×1,
state-driven ×1) — atomic, one `THEN` per block, no compound `AND`.

**T — Test.** Mechanical lints, run for real:
```
$ ./.eidolons/ramza/bin/ramza-ears-lint .spectra/plans/ab2-dryrun.criteria.md
ok: 8 criteria pass EARS lint

$ ./.eidolons/ramza/bin/ramza-lint --plan .spectra/plans/ab2-dryrun.plan.md --state <state>
ok: plan passes structural lint (tier: lite)

$ ./.eidolons/ramza/bin/ramza-ears-lint .spectra/plans/ab2-dryrun.plan.md   # re-run against the embedded copy
ok: 8 criteria pass EARS lint
```
Lite tier's additional verification layers beyond structural+criteria
("dependency, constraint" per `docs/methodology/tiers.md`) have no dedicated
`bin/ramza-*` tool — verified manually and recorded here: **dependency**
check confirms the plan introduces no new external dependency, consistent
with `rightsize`'s `new_dep: false` input; **constraint** check confirms the
plan does not violate any RAMZA P0 (read-only planning artefact only, no code
executed, additive/opt-in flag only, matches the Scope section's declared
Out-of-scope boundary of "changing the default deploy behavior in any way").
No refine cycles were needed (`refine_cycles: 0` in the state file) — the
plan cleared T on the first pass.

**A — Assemble.** Confidence scored for real:
```
$ echo '{"pattern_match":85,"requirement_clarity":90,"decomposition_stability":85,"constraint_compliance":90}' | \
    ./.eidolons/ramza/bin/ramza-score --rubric confidence --state <state> --label ab2-dryrun-confidence
{"rubric":"confidence","total":87.5,"verdict":"AUTO_PROCEED", ...}
```
87.5% → **AUTO_PROCEED** (≥85 band). Criteria frozen:
```
$ ./.eidolons/ramza/bin/ramza-freeze --state <state> --criteria .spectra/plans/ab2-dryrun.criteria.md
frozen: b91bbc110e96a6f100844457f9cba52ef3c977904f4c22b8b85759c9dd0882d2
```
Scope declared for downstream drift checking:
```
$ ./.eidolons/ramza/bin/ramza-drift --state <state> \
    --declare 'cli/deploy* lib/deploy/* spec/cli/deploy_dry_run_spec.rb docs/cli/deploy.md'
scope declared: 4 glob(s)
```
ECL v2.0 envelope sidecar emitted (`ECL_VERSION` file at the install root
reads `2.0`, so `templates/planning-artifact.md` mandates it) at
`.spectra/plans/ab2-dryrun.envelope.json` — `performative: PROPOSE`,
`from.eidolon: ramza` v0.2.0 → `to.eidolon: apivr`, integrity
`sha256:5c67afa7955780486a50c4b1d6fba71ab8ac03571c05d984c0b0173380435217`
(recomputed hash of the spec Markdown bytes), carrying the frozen criteria
hash as `x_ramza_acceptance_criteria`. Mandatory emission gate:
```
$ ./.eidolons/ramza/bin/ramza-verify-emit \
    --spec .spectra/plans/ab2-dryrun.plan.md --envelope .spectra/plans/ab2-dryrun.envelope.json
ok: emission gate passed (ab2-dryrun.plan.md + envelope)
```
Phase advanced to DONE and closed out with an adherence check:
```
$ ./.eidolons/ramza/bin/ramza-gate advance --to DONE --state <state>
OK: A -> DONE

$ ./.eidolons/ramza/bin/ramza-adherence --state <state>
{"plan_phase":1,"plan_order":1,"plan_fidelity":null,"composite":1, ...}
```
`plan_phase: 1` — every mandatory lite-tier phase (RS S P E C T A) was
entered, none silently skipped. `plan_order: 1` — zero refine cycles used, no
penalty. `plan_fidelity: null` — expected and correct: no execution has
happened yet against this plan, so there is no diff to check against the
declared scope; fidelity is only measurable after a downstream `ramza-drift
--range` run. Composite adherence: **1.0**.

No escalation triggers were hit: confidence landed AUTO_PROCEED (not <50),
zero refine cycles (not at the 3-cycle cap), and no unresolved `[GAP]` axes
— Pattern's "no internal precedent found" was resolved by grounding in
external convention rather than left open, so it is a documented assumption,
not a gap.

Audit trail: `/tmp/ramza-e2e/.spectra/plans/ab2-dryrun.state.json` (schema
`ramza/plan-state.v1`, phase `DONE`), criteria at
`/tmp/ramza-e2e/.spectra/plans/ab2-dryrun.criteria.md`, envelope at
`/tmp/ramza-e2e/.spectra/plans/ab2-dryrun.envelope.json`, calibration log
appended at `/tmp/ramza-e2e/.spectra/plans/ramza-calibration.jsonl`.

---

## Plan artefact (`.spectra/plans/ab2-dryrun.plan.md`)

```markdown
---
eidolon: ramza
kind: spec
version: "0.2.0"
status: decision-ready
created_at: "2026-07-05T02:10:38Z"
target_repos:
  - deploy-cli
stories_count: 3
validation_gates_count: 8
confidence: 0.875
---

# Plan: `--dry-run` flag for the deployment command

## Scope

Intent class: REQUEST
In: Add a `--dry-run` flag to the existing deployment command. When present,
the command runs its full validation and planning pipeline, prints every
action it would take, and exits without performing any side-effecting
operation (build push, artifact upload, service restart, notification, or
any network/file-system mutation).
Out: Building a brand-new "plan" subcommand distinct from `deploy`; adding a
sandboxed/staging execution mode; retrofitting dry-run onto commands other
than the deployment command; changing the default (non-flagged) deploy
behavior in any way.
Deferred: Machine-readable diff output beyond a flat planned-actions list
(e.g. a structured before/after state diff) — noted as a follow-on story if
`--format json` adoption shows demand for it.
Assumptions:
- The deployment command already funnels its side-effecting operations
  through a small, identifiable set of call sites (an "executor" boundary,
  however currently structured) — risk if wrong: `--dry-run` could miss an
  un-audited call site and perform a real action; mitigated by AC-006's
  requirement that every side-effect site be guarded, verified by a
  dedicated test.
- No internal prior art for a dry-run flag exists in this codebase (checked
  during Pattern search — this consumer project's tree currently contains no
  application source, only the eidolons/RAMZA scaffold and `.spectra/`
  plans). The design instead follows established cross-tool convention
  (`terraform plan`, `kubectl apply --dry-run`, `npm publish --dry-run`,
  `git push --dry-run`) — risk if wrong: local project conventions
  (flag naming, output format) may diverge once real deploy code exists;
  mitigated by keeping the flag name and semantics (`--dry-run`, additive,
  opt-in, no side effects) aligned with the wider ecosystem so a future
  implementer has a well-trodden target to conform to.
- The deployment command already supports `--env`, `--version`, and a
  `--format json` output mode — risk if wrong: AC-005 and AC-007 would need
  rescoping to whatever flags actually exist; low risk since these are
  described as illustrative composition checks, not load-bearing scope.

Complexity (`ramza-score --rubric complexity`): 6/12 → standard
(scope 1, ambiguity 1, dependencies 2, risk 2 — dependencies and risk are
elevated because dry-run must thread cleanly through every existing
side-effecting call site in the deploy pipeline without behavior drift).

## Approach

Selected: **H1 — in-line flag-guarded short-circuit** (Explore score 79.5,
verdict `solid`; full scoring below).

Thread a single `dry_run` boolean from the CLI flag parser into the existing
deploy pipeline's executor boundary. The pipeline runs unchanged through
config resolution, validation, and planning. At each point that would
normally perform a side-effecting action, the executor checks `dry_run`: if
true, it logs a `[DRY RUN]`-prefixed description of the action it would have
taken and returns a synthetic success result instead of performing the
action; if false, behavior is identical to today. This keeps one code path
for both real and dry-run execution (no duplicated logic to drift out of
sync), and reuses all existing validation so a dry run is a faithful preview
of what a real deploy would attempt.

Concretely:
1. Add `--dry-run` (boolean, default `false`) to the deploy command's flag
   parser.
2. Extend the executor abstraction (or introduce one, if none exists yet)
   with a single `dry_run` check at each side-effecting call site.
3. On dry run, accumulate each simulated action into an ordered list and
   print it (`[DRY RUN] would <action>`) once the pipeline finishes planning
   with no validation errors.
4. Preserve normal validation-failure behavior: a dry run that fails
   validation exits non-zero with the same error reporting as a real deploy,
   before any planned-actions list is printed.
5. Compose with existing flags (`--env`, `--version`, `--format json`)
   without special-casing them beyond the executor guard.

## Stories

### Story 1: Preview a deployment before committing to it

As a release engineer, I want to run the deployment command with `--dry-run`,
so that I can see exactly what a deploy would do before any real action is
taken.
Timebox: 2d.
Risk tag: P1.
Executor hint: mid tier — file-level action plan (flag parser, executor
boundary, output formatting), named pattern (H1 flag-guarded short-circuit).

### Story 2: Trust that no side effect leaks through

As a release engineer, I want every side-effecting call site in the deploy
pipeline to be provably guarded under `--dry-run`, so that I never
accidentally trigger a real build push, restart, or notification while only
intending to preview.
Timebox: 2d.
Risk tag: P0.
Executor hint: mid tier — file-level action plan enumerating every existing
side-effecting call site and the guard added at each; explicit test per
site.

### Story 3: Combine `--dry-run` with existing deploy flags

As an on-call engineer, I want `--dry-run` to compose cleanly with
`--env`, `--version`, and `--format json`, so that I can test my exact
intended invocation risk-free, in whatever output shape my tooling expects.
Timebox: 1d.
Risk tag: P2.
Executor hint: mid tier — file-level action plan for flag-composition
handling plus JSON-output branch.

## Acceptance Criteria

(Full EARS-form blocks below; frozen via `ramza-freeze` — see Confidence
section for the criteria SHA-256. Source file:
`.spectra/plans/ab2-dryrun.criteria.md`, lint-verified: `ok: 8 criteria pass
EARS lint`.)

### AC-001 (event-driven)
GIVEN a syntactically valid deploy configuration and a reachable target environment
WHEN  the deploy command is invoked with --dry-run
THEN  the system SHALL execute the full validation and planning pipeline without invoking any side-effecting call (build push, artifact upload, service restart, or notification)
VERIFY: test: spec/cli/deploy_dry_run_spec.rb#no_side_effects_invoked

### AC-002 (event-driven)
GIVEN the deploy command is invoked with --dry-run
WHEN  the planning pipeline finishes without validation errors
THEN  the system SHALL print an ordered, human-readable list of every action it would have performed, each line prefixed with "[DRY RUN]"
VERIFY: test: spec/cli/deploy_dry_run_spec.rb#prints_planned_actions

### AC-003 (unwanted-behavior)
GIVEN the deploy command is invoked with --dry-run and an invalid or unreachable target environment
WHEN  validation fails during the dry run
THEN  the system SHALL exit with a non-zero status code and print the validation error, never printing a planned-actions list
VERIFY: test: spec/cli/deploy_dry_run_spec.rb#nonzero_exit_on_invalid_config

### AC-004 (ubiquitous)
THEN  the system SHALL exit with status code 0 whenever a --dry-run invocation completes validation and planning without error
VERIFY: test: spec/cli/deploy_dry_run_spec.rb#zero_exit_on_clean_dry_run

### AC-005 (event-driven)
GIVEN the deploy command supports --env and --version options
WHEN  --dry-run is combined with --env and --version in the same invocation
THEN  the system SHALL apply the given --env and --version values to the simulated plan identically to how a real deploy would apply them
VERIFY: test: spec/cli/deploy_dry_run_spec.rb#composes_with_env_and_version_flags

### AC-006 (unwanted-behavior)
GIVEN the deploy command is invoked with --dry-run
WHEN  the underlying pipeline reaches a call site that would normally trigger a network request, file write, or external API call
THEN  the system SHALL substitute a no-op simulation at that call site instead of performing the real action
VERIFY: test: spec/cli/deploy_dry_run_spec.rb#every_side_effect_site_is_guarded

### AC-007 (optional-feature)
GIVEN the deployment command supports a machine-readable output mode (--format json)
WHEN  --dry-run is combined with --format json
THEN  the system SHALL emit the planned-actions list as a JSON array instead of human-readable text
VERIFY: test: spec/cli/deploy_dry_run_spec.rb#json_output_when_format_flag_present

### AC-008 (state-driven)
GIVEN the deploy command is running with --dry-run active
THEN  the system SHALL label its output (terminal banner, log lines, and any structured output) as a dry run for the entire execution, never rendering output that could be mistaken for a real deploy
VERIFY: test: spec/cli/deploy_dry_run_spec.rb#dry_run_labeling_present_throughout

## Confidence

`ramza-score --rubric confidence`: 87.5% → AUTO_PROCEED
(pattern_match 85, requirement_clarity 90, decomposition_stability 85,
constraint_compliance 90 — logged at 2026-07-05T02:10:38Z, label
`ab2-dryrun-confidence`; full record in
`.spectra/plans/ab2-dryrun.state.json` gates[]).

Criteria frozen: SHA-256 recorded via `ramza-freeze` against
`.spectra/plans/ab2-dryrun.criteria.md` (see state file `criteria_sha256`).

## Rejected Alternatives

- **H2 — separate duplicated plan/preview code path** —
  `ramza-score --rubric explore` total 59 (weak; dims: alignment 7,
  correctness 6, maintainability 4, performance 8, simplicity 5, risk 5,
  innovation 3). Rejected because a second, hand-maintained code path that
  reimplements the deploy pipeline's read-only steps will drift from the
  real path over time — the classic "staging logic diverges from prod
  logic" failure mode. It scores worse on maintainability and correctness
  than H1 specifically because nothing structurally forces the two paths to
  stay in sync; every future change to deploy behavior would need to be
  ported twice.
- **H3 — real execution redirected to a sandboxed staging target** —
  `ramza-score --rubric explore` total 44 (weak; dims: alignment 4,
  correctness 6, maintainability 5, performance 3, simplicity 3, risk 4,
  innovation 6). Rejected primarily on alignment: this performs a real
  deploy (side effects do occur, just against a different target), which
  contradicts the "dry" semantics users expect from `--dry-run` and requires
  a standing, environment-parity-maintained staging target to even be
  meaningful. It also loses heavily on performance and simplicity — an
  actual deploy is far slower than a simulated preview, and requires
  infrastructure this feature does not otherwise need.

## Risks

| Risk | Tag | Mitigation |
|---|---|---|
| A side-effecting call site in the deploy pipeline is missed by the executor guard, so `--dry-run` silently performs a real action | P0 | AC-006 requires an explicit guard-presence test per call site; Story 2 timeboxes an audit of every existing side-effecting call site before sign-off |
| Dry-run output drifts from what a real deploy would actually do (e.g. a planned action differs from the executed action) because validation/planning logic changes later without updating the dry-run description | P1 | Single code path (H1) means the same planning logic produces both the real action and its dry-run description — there is no second description to fall out of sync; still worth a periodic spot-check |
| No internal codebase pattern exists for dry-run flags (Pattern phase found none in this project), so naming/output-shape choices rely on external convention rather than in-repo precedent | P2 | Followed widely adopted conventions (`--dry-run`, `[DRY RUN]` prefix, non-zero exit on validation failure) so a future implementer has an unambiguous, well-documented target |
```

---

*Emitted by RAMZA v0.2.0. Spec sha256:
`5c67afa7955780486a50c4b1d6fba71ab8ac03571c05d984c0b0173380435217`. Criteria
sha256: `b91bbc110e96a6f100844457f9cba52ef3c977904f4c22b8b85759c9dd0882d2`.
Envelope: `.spectra/plans/ab2-dryrun.envelope.json` (performative PROPOSE,
ramza → apivr). Emission gate: PASS. Confidence: 87.5% AUTO_PROCEED.*
