# REPO-PLAN — Rynaro/Ramza scaffold (Stage 0)

> SPECTRA v2 campaign · 2026-07-04 · Fable 5. Derived-from: `SPECTRA@v4.11.0`. Target: v0.1.0 scaffold → v1.0.0 after Stage 2.

## Repository layout

```
Ramza/
├── README.md                    # identity, the anti-blackbox pitch, mechanization table
├── DESIGN-RATIONALE.md          # D1–D8 succession decisions (evidence-mapped)
├── CHANGELOG.md
├── LICENSE                      # CC BY-SA 4.0 (docs) — scripts MIT? → keep CC BY-SA 4.0 whole-repo (SPECTRA precedent)
├── agent.md                     # ≤1000-token always-loaded card (install.sh budget-checked)
├── AGENTS.md / CLAUDE.md        # host stubs (marker-bounded on install)
├── EIIS_VERSION                 # 1.4
├── ECL_VERSION                  # 2.0
├── install.sh                   # EIIS 1.4, adapted from SPECTRA 4.11 (manifest, sweep, markers, token budget)
├── docs/methodology/
│   ├── SPEC.md                  # the corrected cycle: right-sizing gate → tiered S→P→E→C→T→R→A
│   ├── scoring.md               # rubrics AS INSTRUMENTS + "computed by bin/, never by the model"
│   └── tiers.md                 # trivial/lite/full — phases, layers, verbosity budgets per tier
├── bin/                         # THE DIFFERENTIATOR — bash 3.2, no deps beyond sh+awk+shasum/sha256sum
│   ├── ramza-gate               # phase state machine: validate/record transitions on .state.json; skips-with-reason
│   ├── ramza-rightsize          # observable signals in → tier out (trivial/lite/full), recorded
│   ├── ramza-score              # per-dimension scores JSON in → weighted totals + gate decision out; appends calibration log
│   ├── ramza-ears-lint          # EARS grammar + atomicity (no compound AND in THEN) + verify_method presence
│   ├── ramza-freeze             # SHA-256 freeze of acceptance-criteria block; ramza-freeze --amend = hash-chained amendment
│   ├── ramza-lint               # plan-body structural completeness vs plan schema (sections, frontmatter, story fields)
│   ├── ramza-drift              # frozen declared scope vs `git diff --name-only` range → uncovered-change report
│   └── ramza-verify-emit        # validates spec frontmatter + ECL envelope against schemas/ before handoff
├── schemas/
│   ├── plan-state.v1.json       # authoritative .state.json shape (phases, tier, gates, skips, amendments)
│   ├── spec-profile.v1.json     # inherited from SPECTRA
│   ├── ecl-envelope.v2.json     # inherited (+ v1 for back-compat window)
│   └── install.manifest.v1.json # inherited
├── skills/
│   ├── methodology.md           # cycle skill (tier-aware)
│   ├── discover.md              # ontology-checklist elicitation + coverage counter contract
│   ├── critic.md                # maker≠checker plan critique w/ mechanical debias steps
│   ├── parallel-spec.md         # TRANCE (inherited, critic-tool-backed)
│   ├── verify-incoming.md       # inherited
│   └── esl-hop.md               # inherited
├── templates/                   # planning-artifact, acceptance-criteria (EARS), spec.envelope, plan.json (§7.5)
├── hosts/                       # claude-code.md (incl. PreToolUse hook shim recipe), copilot.md, cursor.md, opencode.md (permission ruleset)
├── evals/canary-missions.md     # incl. adherence/drift canaries (DSL)
├── tests/*.bats                 # wiring + BEHAVIORAL tests for every bin/ script (not only grep-the-prose)
└── .github/workflows/{ci,release}.yml
```

## What is mechanized (bin/ contracts)

| Script | In | Out | Hard property |
|---|---|---|---|
| `ramza-rightsize` | signal flags (files-est, blast, novelty, stakes) | tier + record | deterministic; overrides recorded, never silent |
| `ramza-gate` | requested transition + state file | allow/deny + updated state | rejects out-of-order phases; skip requires `--reason` |
| `ramza-score` | dims JSON | weighted total, gate verdict | arithmetic never done by the model; calibration log appended |
| `ramza-ears-lint` | criteria file | violations list, exit code | closed EARS grammar; compound-assertion detection |
| `ramza-freeze` | criteria block | sha256 into state + envelope ext | `--amend` chains hashes; silent edit ⇒ later drift/verify fails |
| `ramza-lint` | plan.md + state | missing-section report | tier-aware required sections |
| `ramza-drift` | state (frozen scope) + git range | uncovered-changes report | the ESL `drift_check` implementation |
| `ramza-verify-emit` | spec + envelope | pass/fail vs schemas | nothing hands off unvalidated |

All scripts: bash 3.2, stderr logging, stdout = machine-readable result (nexus lib.sh convention). MCP surface deferred to Stage 2+ (scripts-first doctrine, G-G).

## Nexus intake (Stage 1, same PR as campaign artifacts)

- `roster/index.yaml`: `ramza` entry, `capability_class: planner`, `status: in_construction`, methodology 1.0 cycle `RS→S→P→E→C→T→R→A` (RS = right-size), handoffs mirroring spectra's shape (+ downstream vivi), `working_set_tokens` entry 900 target 3500, security read-only + persists `.spectra/`.
- `.github/workflows/roster-health.yml`: matrix += ramza (in_construction ⇒ EIIS conformance skipped).
- `CHANGELOG.md` + campaign artifacts under `.spectra/plans/spectra-v2/`.
- NOT in this PR: presets, routing.yaml, cortex reseating (Stage 3b, measurement-gated).

## Verification for this session (Stage 0 exit)

1. `shellcheck -x -S error` clean on install.sh + every `bin/*`.
2. bats: behavioral tests green for all bin/ scripts (happy + violation paths).
3. `bash install.sh` into a tmp consumer dir: idempotent second run; manifest lists every skill/script (Vivi lesson); token budget passes.
4. Nexus: `make schema` green with the ramza roster entry.
