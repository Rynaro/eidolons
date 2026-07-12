---
document_type: change-narrative
subject: ESL lifecycle DOGFOOD—native baseline (GAP-B) for mcp-assess --dry-run
date: 2026-06-25
scope: nexus lifecycle validation
---

# Retrospective: ESL Dogfood Run (mcp-assess --dry-run)

## Verdict

**The structure earned its keep, but operational friction offset the value.** Right-sizing delivered proportionate scope (lite, not full); SPECTRA's spec caught a real load-bearing subtlety (stdout JSON-only discipline); maker≠checker isolation mechanically enforced. But three default-false flags (`--has_code`, `--write_manifest` on transition/right-size/drift-check) created high operational friction — operators must remember to flip non-obvious state. This is the **first native ESL + tonberry baseline** and reveals that the tooling prioritizes evaluation over guidance; a larger trial needs either aggressive defaults or forced-choice prompts to validate whether this class of friction scales.

## The Trace

| Phase | Owner | Input | Output | Notes |
|-------|-------|-------|--------|-------|
| propose | tonberry (CLI) | flag addition spec (2 files, ~5 CLI opts) | `change.json` status=proposed | Automated, deterministic |
| right_size | tonberry (CLI) → signals | 2 files / 12 = 5 (low signal) | lite route (0→2→3→4) | Correct proportioning; no tradeoff layers |
| specify | SPECTRA | lite route | 1-page spec.md (AC-1..AC-4) | **Surfaced: stdout must stay JSON-only** |
| in_progress → implement | Vivi | spec.md + acceptance | `cli/src/mcp_assess.sh` + 3 bats tests | Honored stdout discipline; 17/17 own-smoke; no self-verify |
| verified | Kupo (cross-check) | Vivi's artifact + envelope | PASS: 17/17 AC-1..AC-4 confirmed | Genuinely independent checker |
| verify (tonberry) | tonberry (CLI, --mode block) | Kupo envelope C4 cross-check | exit 0, 6/6 gates | maker≠checker authentically enforced (kupo≠vivi) |
| drift_check | Kupo (checker) | Kupo envelope + manifest | drift_checked=true, no mismatches | Consistent state |
| archived | tonberry (CLI) | all above | `archive/2026-06-25-mcp-assess-dry-run/` snapshot | Durable trace |
| escalation_assess | tonberry (CLI) | project context | advisory (1 change, N<10, L<50k, R<0.4) | Proportionate gate |

## Findings — Friction Candidates

1. **`transition` defaults `has_code=false`** — a CODE change silently skips the code states (`in_progress`, `implement`) unless the operator passes `--has_code true`. Easy to forget; a code change could be misrouted without audible error. [ACTION]: Either default to true for changes touching code paths, or force a choice prompt.

2. **`transition` / `right_size` / `drift_check` default `write_manifest=false`** — all three evaluate state but do NOT persist unless `--write_manifest true` is passed; by contrast, `compose_manifest` persists by default. Asymmetry creates a hidden trap: operators must know which verbs persist. [ACTION] : Document explicitly or unify the default.

3. **`archive` copies rather than moves** — original `.spectra/changes/<id>/` folder remains (status=archived) alongside `archive/<date>-<id>/` snapshot. SPEC §9 language ("snapshot moves") suggests intent to orphan the original. [DECISION] : If orphaning is desired, implement move instead of copy; if retention is desired, clarify the spec language.

4. **Bats `run` stderr-merge validated AC-1** — the test harness correctly enforced stdout-only by capturing stdout separately (`2>/dev/null`). This test discipline caught the maker during development—Vivi had to honor the constraint or tests broke. Concrete validation, not ceremony.

## What Earned Its Keep

- **Right-sizing worked**: lite route correctly sized for a small flag change — proportionate scope prevented over-specification.
- **Spec caught a real subtlety**: SPECTRA flagged stdout JSON-only discipline before implementation; Vivi then built it into the acceptance design.
- **Maker≠checker enforced mechanically**: Kupo verified Vivi's work as an independent checker; tonberry's C4 gate cross-checked the envelope identity (kupo≠vivi), not just the decision.
- **Durable trace**: change.json + spec + envelope + archive snapshot provide an auditable record for future retrospectives.

## GAP-B Status — Native Baseline Findings

This is the **first native ESL lifecycle use** against real code; the tooling was designed around Forge/SPECTRA editorial workflows. Extrapolating one run is premature, but:

- **Operational friction (3 findings above) is a leading signal.** Larger trials (10–50 changes) need to validate whether the friction is noise (easily solved) or systemic (unify defaults vs. force choice). Current ergonomics favor expert operators; consumer usability is untested.
- **The evaluation layer (right_size, verify, drift_check) is solid.** Proportionality, conformance checks, and maker≠checker isolation all functioned as designed.
- **Specification is reliable**: lite specs catch real subtleties (stdout discipline) without over-engineering.
- **Guidance layer (transition prompts, template selection) is absent.** Operators must know to pass `--has_code` and `--write_manifest` flags; there is no interactive choice or autocorrect. A 10-run trial with new operators would surface whether this is acceptable friction.

**Required for larger trial**: (1) operator cohort with varied expertise (not all ES experts), (2) change categories across all route types (lite, standard, full), (3) tally of flag misses and self-corrections.

## Provenance

| Source | Role | Finding |
|--------|------|---------|
| tonberry v0.3.1 (CLI) | trace orchestration | proposal, right_size, verify, archive all deterministic and correctly routed |
| SPECTRA v4.2.0 (spec synthesis) | specification | AC-1..AC-4 spec; caught stdout JSON-only constraint |
| Vivi v1.0.0 (implementation) | maker | honored stdout discipline in code; 17/17 tests pass; did not self-verify |
| Kupo v1.0.0 (verification) | cross-check | 17/17 AC-1..AC-4 passed; C4 envelope identity confirmed independent |
| mcp_assess.sh diff | artifact | 2 files, ~5 new options, negligible risk profile (lite classification correct) |

**ECL envelope status**: Kupo→tonberry verify envelope present, C4 gate cross-checked, maker≠checker enforced.

**Document type**: change-narrative (ESL lifecycle chronicle).

**Confidence**: High (trace is complete and auditable). Open: impact of findings 1–2 in 10+ run cohort.

---

*Scribe (IDG v1.8.1) — Provenance-first chronicle of ESL native baseline*
