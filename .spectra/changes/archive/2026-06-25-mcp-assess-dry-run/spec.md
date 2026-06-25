---
Title: eidolons mcp assess --dry-run
Version: 1.0.0
Date: 2026-06-25
Author: SPECTRA 4.9.1
tier: lite
Target: cli/src/mcp_assess.sh, cli/tests/mcp_assess.bats
---

# eidolons mcp assess `--dry-run` (LITE spec)

## Framing

`eidolons mcp assess <name>` runs the MCP's `assess` op, derives the ESL
enforcement mode (`advisory|block`), prints a machine-readable JSON result to
**stdout**, and RECORDS that enforcement into `eidolons.mcp.lock` via
`mcp_lock_set_enforcement`. The new `--dry-run` flag performs every step EXCEPT
the lock write: it computes and prints the exact same assessment JSON but leaves
the lock byte-for-byte unchanged. **Use case:** preview an escalation decision in
CI or a pre-commit check — see whether `assess` would flip a project to `block` —
without mutating the VCS-committed lock. Without `--dry-run`, behavior is
unchanged (still records).

## Scope / non-goals

- IN: a `--dry-run` boolean flag on `mcp assess`; skip the `mcp_lock_set_enforcement`
  call when set; identical stdout JSON in both modes; help/usage text.
- OUT: changes to the assess op, the JSON schema, graceful-skip paths (absent MCP /
  unavailable op / non-JSON / non-oci kind already no-op the lock write and remain
  exit 0), or any new top-level verb. `--dry-run` only gates the RECORD hop.

## Behavioral contract

- Flag parses in the existing `while` option loop alongside `--project-root`; order
  with other args is free. `--dry-run` takes no value.
- When set: all compute/parse/normalize steps run unchanged; the
  `mcp_lock_set_enforcement` branch is skipped; the same `jq -n '{name, enforcement,
  recommended_mode, tripped, assessed_at}'` object is emitted to stdout. A "(dry-run:
  lock not written)" note MAY go to stderr (logs only — must not pollute stdout JSON).
- Exit code 0 on a successful dry-run assessment (same as a recording run).

## Acceptance checks (EARS / GIVEN-WHEN-THEN)

**AC-1 — dry-run still prints the assessment JSON.**
GIVEN tonberry is installed (seeded lock) and `assess` returns `recommended_mode:block`,
WHEN `mcp_assess.sh tonberry --dry-run` runs,
THEN stdout is valid JSON whose `.enforcement == "block"` (and carries `name`,
`recommended_mode`, `tripped`, `assessed_at`), and exit status is 0.
- verify_method: bats `@test "DRY-RUN: prints assessment JSON to stdout (enforcement parseable)"` in
  `cli/tests/mcp_assess.bats` — `run bash …/mcp_assess.sh tonberry --dry-run`; assert
  `[ "$status" -eq 0 ]` and `printf '%s' "$output" | jq -e '.enforcement=="block"'`.
  Reuses existing `seed_tonberry_lock` + `stub_assess_json` helpers.

**AC-2 — dry-run leaves `eidolons.mcp.lock` byte-unchanged.**
GIVEN a seeded `eidolons.mcp.lock` with no `enforcement` field,
WHEN `mcp_assess.sh tonberry --dry-run` runs,
THEN the lock file's bytes are identical before and after (no `enforcement*` keys written).
- verify_method: bats `@test "DRY-RUN: leaves eidolons.mcp.lock byte-unchanged"` —
  capture `shasum eidolons.mcp.lock` (or `cp` + `cmp`) before/after the run; assert
  `cmp -s` matches AND `lock_field '.enforcement'` is empty.

**AC-3 — without `--dry-run`, enforcement is still recorded (no regression).**
GIVEN tonberry is installed and `assess` returns `recommended_mode:block`,
WHEN `mcp_assess.sh tonberry` runs (no flag),
THEN `eidolons.mcp.lock` records `enforcement: block` plus its producing signals.
- verify_method: the existing `@test "G-RECORD: tripped signals → enforcement:block …"`
  MUST stay GREEN unchanged (regression guard); `lock_field '.enforcement' == "block"`.

**AC-4 — `--dry-run` is documented in usage/help.**
GIVEN any invocation of help,
WHEN `eidolons mcp assess --help` (or `mcp_assess.sh --help`) runs,
THEN the Options block lists `--dry-run` with a one-line description and exits 0.
- verify_method: bats `@test "DRY-RUN: --dry-run is listed in assess usage/help"` —
  `run eidolons mcp assess --help`; assert `[ "$status" -eq 0 ]` and
  `[[ "$output" =~ "--dry-run" ]]`.

## Notes for the executor

- Single-file change in `cli/src/mcp_assess.sh` (+ flag, + skip branch, + usage line)
  plus 3 new bats tests; bash 3.2 (no `${var,,}`, no associative arrays).
- All log/note lines go to **stderr**; only the `jq -n` result reaches stdout — keep
  AC-1/AC-2 from being defeated by a stray `say`/`ok` on stdout.
