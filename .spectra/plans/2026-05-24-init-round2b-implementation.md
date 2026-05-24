# PR-R2B Implementation Report

**Spec:** SPEC-2026-05-24-INIT-ROUND2B  
**Branch:** chore/cli-hygiene-bundle-v1.6.1  
**Date:** 2026-05-24  
**Status:** complete — all 6 blocks implemented, all validation gates passed

---

## Blocks implemented

### R2B-1 — export EIDOLONS_VERSION
- `cli/eidolons` line 45: added `export EIDOLONS_VERSION` after the assignment.
- Effect: `init.sh`, `sync.sh`, and `upgrade.sh` `${EIDOLONS_VERSION:-1.0.0}` consumers now read the real value.
- Verified: fresh init stamps `v1.6.1` in both `eidolons.yaml` and `eidolons.lock`.

### R2B-2 — Doctor Check 12 (version-stamp drift)
- Added Check 12 to `cli/src/doctor.sh` after Check 11 (AGENTS.md drift).
- Reads `eidolons.lock`'s `eidolons_cli_version` first; falls back to `eidolons.yaml` header comment when lock absent.
- Warn-only; exit code unaffected. Remedy text points to `eidolons migrate-stamp`.

### R2B-3 — chmod 0644 after mv
- `cli/src/lib.sh::upsert_marker_block`: rewritten branch + created branch.
- `cli/src/lib.sh::remove_marker_block`: after `mv "$tmp" "$dst"`.
- `cli/src/lib_eidolons_md.sh::compose_eidolons_md`: after `mv "$_clean_tmp" "$src"`.
- `cli/src/sync.sh`: LOCK_TMP path + install.manifest.json rewrite.
- `cli/src/upgrade.sh`: install.manifest.json rewrite + LOCK_TMP path.

### R2B-4 — Roster ECL bump
- `roster/index.yaml`: all 6 shipped Eidolons bumped from `"1.0"` to `"2.0"`.
- Verified: `grep envelope_version roster/index.yaml | sort -u` returns single line `"2.0"`.

### R2B-5 — eidolons migrate-stamp
- New `cli/src/migrate-stamp.sh`: rewrites `eidolons.yaml` line 2 + `eidolons.lock` `eidolons_cli_version`.
- Idempotent; `--dry-run` flag; no git operations; chmod 0644 after writes.
- Wired in `cli/eidolons` dispatcher + usage help.

### R2B-6 — Empty .github/ cosmetic prune
- `cli/src/lib_host_prune.sh::host_prune_path_patterns`: `find "$target" -type d -empty -delete 2>/dev/null || true` appended after the pattern loop.

---

## Validation gates

| Gate | Description | Result |
|------|-------------|--------|
| 1 | Full bats suite (460 tests) | PASS |
| 2 | shellcheck -x -S error all modified files | PASS |
| 3 | Fresh init: eidolons.yaml stamps v1.6.1; lock stamps v1.6.1 | PASS |
| 4 | File modes: eidolons.lock=644, CLAUDE.md=644 | PASS |
| 5 | Stale-stamped project: doctor Check 12 warns with migrate-stamp remedy | PASS |
| 6 | migrate-stamp rewrites stamps; second run is no-op | PASS |
| 7 | `grep envelope_version roster/index.yaml | sort -u` → single line "2.0" | PASS |
| 8 | yq eval roster/index.yaml + jq empty schemas/*.json → exit 0 | PASS |

---

## Deviations from spec

- VERSION bumped from 1.5.0 to 1.6.1 in this PR (R2A merged without bumping VERSION; necessary so version-stamp tests pass against the actual current install).
- `upgrade.sh` mv sites also patched (R2B-3 audit found 2 additional sites in upgrade.sh not listed in spec; added for completeness; spec said "cross-reference all mv-from-tmp sites via grep").
- Doctor Check 12 `else` branch (no manifest, no lock) is technically unreachable since Check 1 exits early on missing manifest; test adjusted to reflect reality per spec rationale.
