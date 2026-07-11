# Attempt 4 — DISCARDED (billing outage, same failure mode as attempt 1)

**2026-07-11.** This was the FIRST attempt to measure a genuinely-loaded
remediation: Gilgamesh **v0.2.0** was tagged upstream, the roster pin bumped,
and the member **installed** via `eidolons sync` so the harness loads the
installer-generated `.claude/agents/gilgamesh.md` (carrying the v0.2.0
mission-report protocol: REQUIRED-LABELS enumeration, verbatim-label rule,
quoted-anchor rule, sandbox verify-routing ladder) plus the real methodology
at `./.eidolons/gilgamesh/`.

**What happened:** the account's monthly spend limit was exhausted mid-sweep.
Only cell #1 (arm1-01, run 1) executed before the wall — the remaining
**44/45 cells are `"You've hit your monthly spend limit"` provider-error
stubs**, not agent output. `arm1-results-contaminated.jsonl` records the
mechanical grade of that mixture and is **NOT a valid rate**.

**The one real data point (preserved here):** `run1/arm1-01.report.md` +
`run1/arm1-01.oracle.log` — the v0.2.0 agent produced a clean, correctly
formatted, **PASSING** report (quoted anchor resolved, all required labels
present). A single cell proves the format works end-to-end; it says nothing
about the rate.

**Disposition:** discarded pre-scoring, like attempt 1. The 44 stub files were
deleted (no audit value; PR #467 precedent); retained: this note, `meta.jsonl`
(exit/secs per cell — note secs≈8 stubs after cell 1), `HARNESS.txt`, and the
single passing cell.

**BLOCKER — human action required:** the eval sweep cannot run until the
monthly spend limit is raised (claude.ai/settings/usage) or resets. Every
`claude -p` invocation returns the limit error until then. Attempt "4-real"
(the first valid v0.2.0 measurement) is deferred to a session with headroom;
the runner is already pinned to `--model claude-sonnet-5` and the corpus,
oracle, grader v4, and installed member are all in place to resume immediately.
