# Arm-1 (capability-expansion) holdout — construction log

> ESL change `generalist-eidolon`, Track G (R-039/AC-G01). Gate author:
> `gate-author-sonnet-fresh` — identity distinct from the spec maker
> (ramza), the implementation maker (vivi), and the generalist-builder.
> This log records the non-cherry-pickable selection rule and the
> dual-proof routability check for all 15 missions in `arm1-holdout.jsonl`,
> per R-039's "selection rule the maker cannot cherry-pick."

## 1. The grid (fixed *before* any mission was written)

5 mission **archetypes** × 3 **difficulties** = 15 cells, filled exactly
once each. No cell was skipped or duplicated.

| Archetype | Domains mixed | easy | medium | hard |
|---|---|---|---|---|
| A — schema-enum consistency | schema + roster + docs/CHANGELOG | arm1-01 | arm1-02 | arm1-03 |
| B — CI-matrix / roster-health audit | CI workflow + roster config | arm1-04 | arm1-05 | arm1-06 |
| C — dispatch-predicate fixture/test coverage | tests + fixtures + scripts | arm1-07 | arm1-08 | arm1-09 |
| D — cortex token-budget | docs (EIDOLONS.md) + scripts + CI | arm1-10 | arm1-11 | arm1-12 |
| E — extractor lexicon / frozen-doc consistency | scripts + spec docs + cortex copy | arm1-13 | arm1-14 | arm1-15 |

**Fill rule:** for a given archetype, the *easy* cell asks for one fact +
one mechanical verification command over one file; *medium* asks for two
facts cross-checked across two files plus one verification; *hard* asks
for three-plus facts cross-checked across three files plus two
verifications, and always requires the agent to judge whether the sources
**agree or disagree** (sometimes they don't — arm1-03 is a deliberate
conflation trap, see below) rather than assuming agreement. Difficulty is
therefore defined **structurally** (number of sources × number of
verify-commands × whether a genuine judgment call is required), never by
a subjective "this looks hard" read — the anti-cherry-pick requirement
in R-039.

Every mission:
- targets `workspace: nexus-checkout` (this checkout, read-only);
- is completable with gilgamesh's real tool surface per
  `.claude/agents/gilgamesh.md` (Read/Grep/Glob + `Bash(make:*)`,
  `Bash(bats:*)`, `Bash(shellcheck:*)`, `Bash(shasum:*)`, `Bash(wc:*)` —
  no Write/Edit, no network);
- ends in a **PROPOSE**, never an apply (`PROPOSAL` + `PROPOSAL-TARGET`
  lines, explicitly "do not apply it" in the prompt text);
- carries a fixed labeled-line report contract (`ANSWER-*`, `VERIFY-*`,
  `EVIDENCE-*`, `PROPOSAL`, `PROPOSAL-TARGET`) so `evals/oracle-check.sh`
  can grade it with zero discretion (grep + exact match + `sed -n`
  spot-check on cited anchors).

## 2. Dual routability proof (per mission, re-verified at freeze time)

Two independent, mechanical checks, both required:

- **(a) Kernel Step-1** — `EIDOLONS_NEXUS=$(pwd) bash cli/eidolons run "<prompt>" --explain`
  must show **no specialist (atlas/spectra/ramza/apivr/vivi/idg/forge/vigil/kupo)
  scoring ≥ 0.6**. This is S6 from the reference extractor's declared
  preconditions, checked against the *real* routing kernel, not merely
  asserted.
- **(b) Reference extractor** — `bash scripts/dispatch-predicate-extractor.sh --verdict "<prompt>"`
  must print `actionable` (the frozen `S1∧S2∧S3∧S4∧S5` combinator, the
  same code path `cli/src/run.sh` calls in production — see
  `cli/src/run.sh:387-388`).

Re-run immediately before `FREEZE.sha256` (this repo has scripts under
active concurrent edit — `scripts/dispatch-predicate-extractor.sh` grew a
`--verdict` mode and `cli/tests/dispatch_predicate.bats` grew from 17 to 22
`@test` blocks during this construction window; none of that touched the
lexicons or the combinator itself, confirmed below, so no mission needed
re-work for it — see §4 on `arm1-07`'s volatile fact).

| id | difficulty | max specialist score (excl. gilgamesh) | extractor vector (S1..S5) | extractor verdict |
|---|---|---|---|---|
| arm1-01 | easy | 0.15 (kupo) | 1 1 1 1 1 | actionable |
| arm1-02 | medium | 0.15 (kupo) | 1 1 1 1 1 | actionable |
| arm1-03 | hard | 0.15 (kupo) | 1 1 1 1 1 | actionable |
| arm1-04 | easy | 0.15 (kupo) | 1 1 1 1 1 | actionable |
| arm1-05 | medium | 0.15 (kupo) | 1 1 1 1 1 | actionable |
| arm1-06 | hard | 0.15 (kupo) | 1 1 1 1 1 | actionable |
| arm1-07 | easy | 0.15 (kupo) | 1 1 1 1 1 | actionable |
| arm1-08 | medium | 0.15 (kupo) | 1 1 1 1 1 | actionable |
| arm1-09 | hard | 0.15 (kupo) | 1 1 1 1 1 | actionable |
| arm1-10 | easy | 0.15 (kupo) | 1 1 1 1 1 | actionable |
| arm1-11 | medium | 0.15 (kupo) | 1 1 1 1 1 | actionable |
| arm1-12 | hard | 0.15 (kupo) | 1 1 1 1 1 | actionable |
| arm1-13 | easy | 0.15 (kupo) | 1 1 1 1 1 | actionable |
| arm1-14 | medium | 0.5 (spectra, named-only) | 1 1 1 1 1 | actionable |
| arm1-15 | hard | 0.5 (spectra, named-only) | 1 1 1 1 1 | actionable |

All 15 clear both gates: max specialist score `< 0.6` (S6 holds; the
0.15 floor is the `localized_micro_task` signal boost that fires on words
like "fixture"/"single-line" appearing in the report-contract suffix —
harmless, well under τ; the 0.5 on arm1-14/15 is the `.spectra/`
path-token in the file path incidentally satisfying SPECTRA's named-bonus
word boundary — also harmless, well under τ) and the reference extractor
resolves `actionable` — exactly AC-C01's `S6=1 ∧ S7=1 ∧ (S1∧S2∧S3∧S4∧S5)`
gate, reproduced against the live kernel and the live extractor, not
hand-asserted.

## 3. Rejected-then-repaired draft variants (non-cherry-pickable trail)

Six of the fifteen cells needed a wording repair after the first draft
failed one of the two gates above. Per R-039, no cell was dropped or
swapped for an "easier" one — each failing draft's specific forbidden
lexeme is named here, and the fix is a minimal, same-intent wording
substitution (never a different task, never a different domain).

| id | first-draft defect | mechanical cause | fix |
|---|---|---|---|
| arm1-02 | "declared **across** the `eidolons:` entries" | `across` ∈ `GENERIC_SCOPE`; no `LIMITER` co-occurred → S5=0 → verdict `clarify` | reworded to "declared **among** the `eidolons:` entries" |
| arm1-06 | "the other two omit **by design**" | `design` is a live RAMZA/SPECTRA kernel trigger verb → ramza & spectra scored 0.8 (S6 violated) | reworded to "the other two **do not carry**" |
| arm1-06 | "confirm **all** three name sets agree" | `all` ∈ `GENERIC_SCOPE` → S5=0 → verdict `clarify` | reworded to "confirm **the** three name sets agree" |
| arm1-11 | "confirm the two numbers **match**" | `match` (singular) is not in `ACCEPTANCE_MARKERS` (only `matches`, plural, is) → S4=0 → verdict `clarify` | reworded to "confirm the two numbers are **equal**" (`equal` ∈ `ACCEPTANCE_MARKERS`) |
| arm1-12 | "determine whether **all** three are consistent" | `all` ∈ `GENERIC_SCOPE` → S5=0 → verdict `clarify` | reworded to "determine whether **each of the three** is consistent" |
| arm1-14 | "keep the script and the frozen **document** in lockstep" | `document` is a live IDG kernel trigger verb → idg scored 0.8 (S6 violated) | reworded to "the frozen **file**" |
| arm1-15 | "determine whether **all** sources agree" | `all` ∈ `GENERIC_SCOPE` → S5=0 → verdict `clarify` | reworded to "determine whether **the three** sources agree" |
| arm1-15 | "drift between the script and the frozen **document**" | same IDG trigger collision as arm1-14 | reworded to "the frozen **file**" |

Nine cells (arm1-01, 03, 04, 05, 07, 08, 09, 10, 13) passed both gates on
the first draft. No mission was discarded outright — every rejection led
to a same-cell repair, never a substitute mission from a different
archetype/difficulty combination, keeping the 5×3 grid intact as declared
in §1 before any prompt was written.

## 4. A volatile ground-truth fact (documented, not hidden)

`cli/tests/dispatch_predicate.bats`'s `@test` block count moved during
this construction session (17 → 19 → 22) as `--verdict`-mode coverage was
added upstream (`scripts/dispatch-predicate-extractor.sh` and its test
file are under active concurrent development in this checkout). Mission
`arm1-07` asks for this count; `ANSWER-test_count` in
`arm1-holdout.jsonl` is pinned to the value at the moment of
`FREEZE.sha256` (22), with the volatility noted in that record's
`ground_truth_notes`. All other numeric facts referenced by these 15
missions (schema enum length 9, roster-index/routing/roster-health name
counts 11/10/10, `fixtures.tsv` 17 data rows, `ACT_VERBS` 47,
`GENERIC_SCOPE` 18, EIDOLONS.md always-loaded proxy count 831/ceiling 850)
were re-verified immediately before freeze and are stable static
config/spec content, not live-edited during this session.

One additional correction made during construction, unrelated to
routability: the original `arm1-03` `oracle_cmd` used
`sed -n '25,36p' EIDOLONS.md | grep -c '^|'`, which counts the Markdown
table's header + separator rows along with the 10 data rows (12, not
10). Corrected to `sed -n '27,36p' EIDOLONS.md | grep -c '^|'` (= 10,
data rows only) before freeze — caught by re-running the oracle command
against the live file rather than trusting the first draft's range.

## 5. What "actionable-but-unroutable" means for this holdout

Every mission is a **read+analyze+verify+PROPOSE** audit against real
facts in this checkout — never a request to design, plan, deploy,
migrate, route, or spawn (gilgamesh's `refuse_verbs` per
`roster/routing.yaml`), and never a request any specialist's trigger
vocabulary already owns (verified per mission, §2). Each mixes at least
two of {code, config, CI, docs} so no single specialist's domain
dominates the corpus, per the task's cross-domain requirement — see the
"Domains mixed" column in §1.
