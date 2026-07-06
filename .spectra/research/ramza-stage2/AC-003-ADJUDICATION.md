# AC-003 Adjudication — Planner A/B, ramza@0.2.0 vs spectra@4.11.0

> 2026-07-05 · Fable-5 campaign, Opus-4.8 coordination. Completes the run left
> incomplete by session-2 spend limits. Adjudicated **strictly** against the
> frozen protocol in `AC-003-PREREGISTRATION.md` (nexus commit f09f54f, the
> pre-registration timestamp). Every number below is mechanical (grep-based
> `eidolons eval quality grade`, zero LLM judge). Full 24-cell matrix, raw
> artifacts, and per-pair grade JSON in `ac003/` (see `ac003/matrix.csv`).

## Verdict: **AC-003 PASS**

RAMZA is **non-inferior** to SPECTRA on the planner-seat contract-conformance
suite, with holdout consistency intact. The Stage-3b seat-flip proceeds.

## The full matrix (k=2 per cell, 24 runs)

| Task | SPECTRA pass² | RAMZA pass² | MUST fails | words: spectra mean / ramza mean |
|---|---|---|---|---|
| AB-T1 webhook subsystem      | PASS | PASS | 0 | 10,560 / 5,104 |
| AB-T2 soft-delete brownfield | PASS | PASS | 0 | 8,165 / 4,624 |
| AB-T3 double-charge fix      | PASS | PASS | 0 | 9,535 / 3,852 |
| AB-T4 underspecified dashboard | PASS | PASS | 0 | 7,999 / 4,632 |
| **AB-H1** API deprecation *(holdout)* | PASS | PASS | 0 | 10,599 / 6,174 |
| **AB-H2** SAML SSO *(holdout)*        | PASS | PASS | 0 | 12,528 / 5,970 |

- **spectra tasks pass²: 6/6** (public 4/4, holdout 2/2)
- **ramza   tasks pass²: 6/6** (public 4/4, holdout 2/2)
- **MUST-item failures across all 24 runs: 0**

## Decision rule, applied exactly as frozen

1. **Non-inferiority** — `ramza_pass2 (6) >= spectra_pass2 (6) − 1 = 5` → **MET.**
   (Superiority is *not* claimed at this sample size, per the pre-registration.)
2. **Holdout consistency** — neither arm's holdout result diverges in direction
   from its public-task result by more than one task. Both arms are perfect on
   public and holdout alike → **CONSISTENT.** No overfitting signal.
3. **No partial credit** — the rule was withheld in session 2 (9/24 cells, holdout
   unrun) exactly because partial data cannot be adjudicated. It is applied here
   only now that all 24 cells exist.

→ Non-inferiority met **AND** holdout consistent → **AC-003 PASS.**

## Secondary metrics (descriptive, NOT gated)

- **Ceremony:** mean **5,059 words/artifact for RAMZA vs 9,897 for SPECTRA — 51%**
  of the verbosity across the full 24-cell matrix, on identical missions graded by
  identical rubrics. (Session-2's "~40%" was the terser T1–T3 public subset; the
  holistic full-suite figure is 51%. Reported without embellishment.)
- **Audit-trail density:** every RAMZA artifact carries a machine-verifiable audit
  trail — tier decision, rubric scores with weak hypotheses rejected on the record,
  EARS-lint result, SHA-256 criteria freeze + `--verify`, verify-emit, and
  maker≠checker critic identities. SPECTRA artifacts self-report their cycle.
- **Right-sizing behaved:** RAMZA sized to task rather than blanket-scaffolding —
  the same mission scored `lite` in one run and `full` in another (AB-T4), and
  T3 came in `lite` while T1/T2/H1/H2 went `full`. Ceremony tracked complexity.

## The finding that outweighs the numbers: the critic cascade caught a real defect, live

On **AB-H2 (SAML SSO), run r1**, RAMZA's own maker≠checker loop caught and closed a
genuine defect *before* the plan could be called done — the second such catch in
this campaign, and the cleanest:

- Right-sized `full`; the executor spawned a clean-context critic (distinct
  author/checker identities recorded via `ramza-gate critic`).
- **Cycle-2 refine scored `completeness 3/5`, below the ≥4 bar → FAIL.** The
  concrete defect: this refine pass had *added* Story 7 (break-glass override) and
  AC-015 (manual account recovery), which promise `break_glass_override` and
  `manual_recovery` audit events — but **AC-008's audit-event enumeration was never
  extended to cover them.** For a mechanism whose purpose is temporarily lowering a
  tenant's security posture, un-audited invocation is a real observability gap.
  This is exactly the criteria-desync class RAMZA's freeze/lint gates exist to catch.
- The executor extended AC-008 (the terms now appear throughout the final artifact),
  re-scored **cycle-2 completeness → 4 (PASS)**, and an **independent cycle-3 critic
  (`ramza-critic-final-03` ≠ author) returned PASS**. Only then did it Assemble.

The external A/B rubric would *not* have flagged this — it doesn't check audit-event
completeness. RAMZA's internal gate is **stricter than the measurement**, which is a
point in its favor, not a measurement problem. The methodology demonstrably works.

## Process honesty notes

- **Blindness held:** executors received mission text only (verified: zero rubric
  strings in any mission file). Same executor model (Sonnet 5) both arms. Fresh
  context per run; no cross-pollination.
- **Infrastructure re-runs:** the 3 session-2 ramza T1–T3 infra failures were
  re-run once (pre-registration allows this for infra, not content, failures) and
  labeled r1. All other cells are first-run.
- **Critic→author routing gap, again:** critics still cannot address their parent
  executor directly (they resolve the agent *type* name, not a thread id) — the
  coordinator relayed one verdict. This is the same infrastructure finding as
  session 2; the production fix belongs to Junction routing, not to prompts. It
  did not affect any grade (grades are mechanical on the final artifact).
- **CRYSTALIUM absent** in the sandbox; memory ingest/session_end gracefully
  skipped by both arms per their degradation clauses.

## Consequence

AC-001 (calibration), AC-002 (7/7 canaries), and **AC-003 (this)** are all closed
green. Stage-2 measurement is complete. RAMZA is cleared to leave `in_construction`:
Stage 3a (v1.0.0 attested release) and Stage 3b (default planner-seat flip, SPECTRA
retained as the conservative opt-in fallback) proceed with these numbers quoted as-is.
