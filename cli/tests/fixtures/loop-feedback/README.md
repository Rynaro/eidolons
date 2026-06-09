# loop-feedback capture-live fixtures

**Verbatim, unedited real tool output** captured 2026-06-05 to anchor the Stage-1
localized-feedback parser (S1.4-parser) and lint-gate (S1.3) acceptance tests.
Do NOT hand-edit these files — the whole point is that the parser is tested against
reality, not a fabricated shape (the "fabricated fixtures pass 10/10 while every
assumption is wrong" failure mode). Re-capture, don't massage, if a runner changes.

| file | runner | what it exercises |
|------|--------|-------------------|
| `bats-fail.txt`      | `bats math.bats`        | TAP `not ok` + loci as **`(in test file math.bats, line 3)`** + the failing assertion line |
| `pytest-fail.txt`    | `pytest -q calc_test.py`| `calc_test.py:8: AssertionError` (colon loci) + `assert 10 == 15` expected/actual + `FAILED ...::test_name` |
| `shellcheck-fail.txt`| `shellcheck deploy.sh`  | loci as **`In deploy.sh line 4:`** + `SC2154` code |

## Load-bearing finding (drove the parser design)

Loci formats are **not uniform**: pytest uses `file.ext:NN` (colon), but bats uses
`(in test file <f>, line N)` and shellcheck uses `In <f> line N:`. The pre-existing
`sandbox.sh` loci regex (`[A-Za-z0-9_./-]+\.[A-Za-z0-9]+:[0-9]+`) matches ONLY the
colon form, so it silently misses bats + shellcheck loci. The deepened parser MUST
extract loci, the failing test name, and (where present) expected/actual from all
three shapes. Acceptance tests assert against these captured files, never synthetic ones.
