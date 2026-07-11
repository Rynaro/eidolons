# Attempt 2 re-graded under grader v4 (transparency record)

Grader v4 adds fix #4 (mission-verbatim folded labels accepted) on top of
v3's three fixes. Re-grading attempt 2's static reports under v4:

  run1: 10/15 = 66.7%   run2: 8/15 = 53.3%   run3: 8/15 = 53.3%

Still FAIL vs the frozen 80% pass-cubed floor. Conclusion: the grader
fixes alone do NOT rescue Gilgamesh v0.1.0 — its residual failures are
genuine (required lines absent entirely, verify steps abandoned when the
direct route was blocked, unresolvable anchors). Attempt 3 therefore
isolates the v0.1.1 methodology remediation as the variable under test.
For the gate checker (AC-G05): all four grader fixes are documented
in-file in evals/oracle-check.sh and are uniformly never-stricter; the
checker has authority to reject any of them and force a re-grade.

## Attribution correction (2026-07-11, post-attestation)

Mechanical evidence (file mtime 07:46 vs remediation commit 13:50): the
local harness surface `.claude/agents/gilgamesh.md` was NEVER edited by
the v0.1.1 remediation — the remediation reached only the member repo,
which the headless harness does not load. Attempt 3 therefore measured
the same unremediated agent definition as attempt 2; its "v0.1.1" label
in arm1-verdict.json is wrong as an attribution of the OPERATIVE surface
(the roster/upstream version was 0.1.1; the loaded agent text was the
P1 stub). Both FAIL verdicts stand as measurements of what actually ran.
Consequence: no remediation has been genuinely tested yet; attempt 4 is
the first real test, and must run against an INSTALLED member
(./.eidolons/gilgamesh/ present) so the methodology the roster certifies
is the methodology the agent loads.
