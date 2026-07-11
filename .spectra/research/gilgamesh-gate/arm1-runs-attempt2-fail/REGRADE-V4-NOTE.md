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
