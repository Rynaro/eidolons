# Succession Brief — SPECTRA → RAMZA

> SPECTRA v2 campaign · 2026-07-04 · Fable 5. Pattern: the APIVR-Δ → Vivi succession (succession-by-demotion, not removal).

## The name

**RAMZA** — named for Ramza Beoulve, the tactician of *Final Fantasy Tactics*: the one who actually planned and fought the war the official chronicle erased, vindicated only because the records survived (the Durai Papers). Personality match, per house convention (cf. Vivi: "methodical, precise, devastating"):

- **A tactician, not a scribe** — plans battles others execute; never swings the sword mid-council (read-only planning).
- **Truth against the official story** — the market's plan modes are blackboxed chronicles; RAMZA's plans are auditable records with tamper-evident hashes. The Durai Papers *are* the artifact discipline.
- **Weighs before committing** — hypothesis scoring, gates, rejected-alternatives carried forward.
- Part of the Final-Fantasy-named family (Vivi, Kupo, Tonberry, Crystalium, Junction, Gambit).

Names considered and passed over: **Libra** (scan/reveal semantics fit, but zodiac/crypto dilution and concept-not-character breaks the Vivi precedent), **Orran** (the chronicler himself — too obscure outside FFT), **Gambit** (already used in the family).

`Rynaro/Ramza` verified free (2026-07-04). Roster slug: `ramza`. Capability class: `planner` (reused enum — two members may share a class, Vivi precedent).

## Succession decisions (D1–D8)

- **D1 — Mechanize the gates.** The reason RAMZA exists. SPECTRA 4.11's cognitive cycle is enforced by prose the model promises to obey; the 2026 evidence (Cursor staff-admitted violations, ExitPlanMode consent fabrication, ICLR goal-drift) shows promises erode. Every arithmetic, grammar, freeze, transition, and identity check that CAN run as code DOES run as code (`bin/`, bash 3.2). The methodology remains the mind; the scripts become the spine.
- **D2 — Inherit the discipline spine.** Same cycle (S→P→E→C→T→R→A + DISCOVER/CLARIFY pre-phases + PERSIST/ADAPT), same read-only P0, same `.spectra/` output discipline, ECL 2.0 emission, EIIS 1.4 layout, CRYSTALIUM memory verbs — derived from `SPECTRA@v4.11.0` exactly as Vivi derived from `APIVR-Delta@v3.6.0`. Succession, not rewrite.
- **D3 — Right-size mechanically; ceremony is a failure mode.** "Never skip" dies. A right-sizing gate (observable signals only, ESL pattern) selects trivial/lite/full tiers; phases skip with recorded reasons; trivial tier has a hard verbosity budget. Evidence: forced phases measurably hurt (arXiv 2604.12147); ceremony kills adoption (Scott Logic 10×; GSD growth).
- **D4 — Freeze for tamper-evidence, amend as first-class.** Acceptance criteria SHA-256-frozen at Assemble exit (DR-12 inherited) with a hash-chained `ac-amend` protocol — the Brooker variable (spec mutability during implementation) answered: mutable, but never silently.
- **D5 — Drift is measured, not hoped against.** `drift-check` (declared scope vs actual diff) and plan-adherence reporting are RAMZA's flagship verbs — the capability no vendor and no MCP server ships. ESL's named-but-unimplemented `drift_check` gets its implementation.
- **D6 — Tier at boundaries, not phases.** Frontier-tier models hold plan/replan/verify/judge boundaries; executor tiers get denser scaffolds and low-ambiguity output contracts; escalation is deterministic data. Blanket planner/executor splits are refused (AkitaOnRails). Maker≠checker on plan critique is asserted mechanically.
- **D7 — Honest instruments.** No outcome claims until measured. Rubric weights and thresholds ship as calibratable instruments; every scored gate logs to disk so calibration data accrues; the parked `calibrate` verb lands here. Transparency includes being honest about what is heuristic.
- **D8 — Two planners, not bloat.** RAMZA takes the `planner` seat via the staged path; SPECTRA remains shipped as the conservative fallback (named-dispatch), exactly like APIVR-Δ behind Vivi. Handoff shape stays identical (`upstream: [atlas]`, `downstream: [vivi, apivr]`, lateral forge/vigil) so the pipeline is structurally unchanged.

## Staged rollout (Vivi playbook, adapted)

| Stage | Gate | Content |
|---|---|---|
| **0 — Scaffold** (this session) | repo exists, CI green | `Rynaro/Ramza` created: identity docs, methodology, `bin/` mechanization scripts + bats tests, schemas, install.sh (EIIS 1.4), hosts, skills, ECL 2.0 |
| **1 — Roster intake** (this session, PR) | nexus PR opened | `roster/index.yaml` entry `status: in_construction`, CI matrix row, campaign artifacts committed. No preset/routing changes yet |
| **2 — Measurement** | canary + adherence data | `eidolons canary ramza` DSL missions incl. plan-adherence + drift metrics; A/B vs SPECTRA 4.11 on the H-WIN instrument |
| **3a — v1.0.0 release** | attested release + integrity metadata | Follows `eidolon-release-template.yml`; **smoke-test that every listed skill/script is actually installed** (Vivi v1.0.0 lesson) |
| **3b — Default planner seat** | Stage 2 measurement wins | `routing.yaml`: `ramza default_for_class: planner`, `fallback: spectra`; presets recomposed; cortex reseated; SPECTRA demoted to named-dispatch |

## Committed-artifact discipline

The APIVR overhaul digest was lost because it lived only in a session. Everything in this campaign is committed under `.spectra/plans/spectra-v2/` in the nexus — including this brief.
