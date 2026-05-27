---
name: test-scoping
description: Pick the minimal bats test scope for a code change in the eidolons nexus before running tests. Maps changed paths (cli/src/*.sh, roster/, schemas/, methodology/, docs/, .github/) to the bats files that actually exercise them, and falls back to `make test` (full suite, ~41s) only when the change touches shared infrastructure (lib.sh, helpers.bash, the dispatcher, cli/src/ui/*, or anything ambiguous). Use when the user asks to run tests, when finishing an APIVR-Δ V-phase, or anytime you would otherwise reflexively run all 649 tests.
when_to_use: Before running any bats command. Triggered when the user says "run tests", "verify this", "make sure tests pass", or when finishing an edit and considering verification.
---

# test-scoping — minimal-bats-scope routing for the eidolons nexus

The full bats suite is 649 tests across 44 files (~41s parallel, ~2m30s sequential). For most edits, **3–60 tests in 1–4 files** cover the change. This skill is the routing protocol: classify each changed file, union the resulting test sets, and run that subset. Only expand to the full suite when a change crosses a tripwire.

If you are unsure, prefer **`make test`** — it is fast enough (41s) that a precise-but-wrong scope is worse than an over-broad-but-right one.

---

## Decision flow

For a working tree with N modified files:

```
1. Get the changed-file list.
   git diff --name-only HEAD                     # uncommitted
   git diff --name-only main...HEAD              # branch vs main
   git diff --name-only --cached                 # staged only

2. For each file, classify it (see table below) and emit its test bucket:
   - one or more bats files, OR
   - "FULL SUITE" (a tripwire), OR
   - "NO TESTS" (docs/comments/CI yaml)

3. If any file is FULL SUITE → run `make test` and stop.
   If every file is NO TESTS → skip bats; run `make schema` if any
       .json/.yaml/workflow file changed.
   Otherwise → union the bats files and run them as a list (see commands).

4. When the change adds new code paths not covered by an existing bats file,
   the test you wrote alongside it goes in the list too. If you added a new
   bats file, run it AND the file that covers the source you touched.
```

---

## Tripwires → full suite (`make test`)

The change touches code that is sourced/dispatched by everything. Don't try to scope:

| Path | Reason |
|---|---|
| `cli/src/lib.sh` | Sourced by every subcommand. |
| `cli/tests/helpers.bash` | Loaded by every `.bats` file. |
| `cli/eidolons` | The dispatcher — argument parsing affects every command. |
| `cli/src/ui/*.sh` | Output formatting is asserted on by many tests (`init`, `sync`, `doctor`, `ui`). |
| `Makefile` (test target) | Changes the runner itself. |
| Anything you can't confidently classify | The 41-second tax is cheaper than a missed regression. |

A second class of tripwire **does not** demand the full suite but does demand a wide group — see "Shared libs" below.

---

## Source → test mapping

### Direct 1:1 (most common)

| `cli/src/…` | `cli/tests/…` |
|---|---|
| `add.sh` | `add.bats` |
| `canary.sh` | `canary.bats` |
| `harness.sh` | `harness.bats` |
| `init.sh` | `init.bats` |
| `list.sh` | `list.bats` |
| `migrate-stamp.sh` | `migrate-stamp.bats` |
| `release.sh` | `release.bats` |
| `remove.sh` | `remove.bats` |
| `roster.sh` | `roster.bats` |
| `upgrade.sh` | `upgrade.bats` |
| `upgrade_self.sh` | `upgrade_self.bats` + `backfill_roster_ref.bats` + `gitignore_sidecar.bats` (sidecar-heal paths) |
| `verify.sh` | `verify.bats` |
| `verify_release.sh` | `verify_release.bats` |
| `doctor.sh` | `doctor.bats` + `doctor_deep.bats` |
| `dispatch_eidolon.sh` | `dispatch_eidolon.bats` + `dispatch_pointer_flatness.bats` |
| `sync.sh` | `sync.bats` + `cortex.bats` + `cache_freshness.bats` + `cache_hygiene.bats` |

### MCP family

| `cli/src/…` | `cli/tests/…` |
|---|---|
| `mcp.sh` (the dispatcher) | `mcp_back_compat.bats` + the touched subcommand's `mcp_<sub>.bats` |
| `mcp_install.sh` | `mcp_install.bats` + `mcp_back_compat.bats` |
| `mcp_uninstall.sh` | `mcp_uninstall.bats` |
| `mcp_sync.sh` | `mcp_sync.bats` |
| `mcp_refresh.sh` | `mcp_refresh.bats` |
| `mcp_upgrade.sh` | `mcp_upgrade.bats` |
| `mcp_list.sh` | `mcp_list.bats` |
| `mcp_show.sh` | `mcp_show.bats` |
| `mcp_health.sh` | `mcp_health.bats` |
| `mcp_run.sh` | (no direct test; covered via `mcp_health.bats`) |
| `mcp_atlas_aci.sh` | `mcp_atlas_aci.bats` + `atlas_aci_dispatch.bats` |
| `mcp_atlas_aci_pull.sh` | `mcp_atlas_aci_pull.bats` |

### Shared libs (run the group)

| Touched file | Run all of |
|---|---|
| `cli/src/lib_mcp.sh` | every `cli/tests/mcp_*.bats` + `sync.bats` |
| `cli/src/lib_mcp_wiring.sh` | `mcp_wiring.bats` + `mcp_install.bats` + `mcp_uninstall.bats` + `mcp_sync.bats` + `mcp_refresh.bats` + `sync.bats` |
| `cli/src/lib_mcp_atlas_aci.sh` | `mcp_atlas_aci.bats` + `mcp_atlas_aci_pull.bats` + `atlas_aci_dispatch.bats` |
| `cli/src/lib_eidolons_md.sh` | `sync.bats` + `cortex.bats` + `dispatch_pointer_flatness.bats` |
| `cli/src/lib_host_prune.sh` | `sync.bats` |

### Data + config

| Changed | Run |
|---|---|
| `roster/index.yaml` — version bump only (`versions.latest` / `pins.stable`) | `roster.bats` + `verify.bats` + `verify_release.bats` + `list.bats` |
| `roster/index.yaml` — structural change (new fields, enum, integrity block) | **FULL SUITE** |
| `roster/mcps.yaml` | every `cli/tests/mcp_*.bats` |
| `schemas/*.json` | **FULL SUITE** (validators run across init/sync/verify/doctor) |
| `eidolons.yaml` / `eidolons.lock` / `eidolons.mcp.lock` at repo root | usually a consumer-side fixture, not test input — **NO TESTS**; run `make schema` if you want a sanity pass |
| `methodology/cortex/*` or `EIDOLONS.md` | `cortex.bats` |
| `cli/install.sh` | `install.bats` |
| `bin/ecl-io-shim` | `ecl_io_shim.bats` |
| `art/` or `cli/src/ui/art_loader.sh` | `art-lint.bats` + `ui.bats` |

### No-test-impact paths

| Changed | Action |
|---|---|
| `README.md`, `MANIFESTO.md`, `CHANGELOG.md`, `docs/**` | **NO TESTS**. (Exception: if the doc is `methodology/cortex/*` or `EIDOLONS.md`, see above.) |
| `.github/workflows/*.yml` | **NO TESTS**, but run `make schema` (which executes `yq eval` to catch YAML parse traps — see the workflow-block-scalar lesson in memory). |
| `.claude/**`, `.spectra/**`, `.junction/**` | **NO TESTS**. These are tooling state, not nexus code. |
| `VERSION` (release bumps) | typically paired with a roster change — scope to whichever roster path applies above. |

---

## Commands

```bash
# Scoped — one file
make test-file F=cli/tests/init.bats

# Scoped — one test by name pattern inside one file
make test-file F=cli/tests/init.bats P="preset pipeline"

# Scoped — multiple files (bats accepts a list; --jobs parallelises across them)
bats --jobs 8 --no-parallelize-within-files \
  cli/tests/sync.bats cli/tests/cortex.bats cli/tests/cache_freshness.bats

# Full suite (tripwire, or "I don't know")
make test                   # JOBS=8 default, ~41s
make test JOBS=4            # mirrors CI

# Non-bats sanity that complements scoped runs
make schema                 # roster + schema JSON structural check
make lint                   # shellcheck cli/**/*.sh
```

`make test-file` and the raw `bats <files>` form both honor parallelism; you do not need a per-test budget heuristic — let bats run them in parallel and read the timing.

---

## Worked examples

### Example 1 — version bump (`fix/roster-spectra-4-2-9`)

Diff: `roster/index.yaml` (only `versions.latest` and `versions.pins.stable` for spectra), `CHANGELOG.md`.

- `roster/index.yaml` (version-bump only) → `roster.bats` + `verify.bats` + `verify_release.bats` + `list.bats`
- `CHANGELOG.md` → NO TESTS

Run:
```bash
bats --jobs 4 --no-parallelize-within-files \
  cli/tests/roster.bats cli/tests/verify.bats \
  cli/tests/verify_release.bats cli/tests/list.bats
make schema
```

### Example 2 — fix in `cli/src/sync.sh` only

Diff: `cli/src/sync.sh`, `cli/tests/sync.bats` (added a regression test).

- `sync.sh` → `sync.bats` + `cortex.bats` + `cache_freshness.bats` + `cache_hygiene.bats`

Run:
```bash
bats --jobs 4 --no-parallelize-within-files \
  cli/tests/sync.bats cli/tests/cortex.bats \
  cli/tests/cache_freshness.bats cli/tests/cache_hygiene.bats
```

### Example 3 — touched `cli/src/lib_mcp_wiring.sh`

Shared lib → expand to the wiring group:
```bash
bats --jobs 8 --no-parallelize-within-files \
  cli/tests/mcp_wiring.bats cli/tests/mcp_install.bats \
  cli/tests/mcp_uninstall.bats cli/tests/mcp_sync.bats \
  cli/tests/mcp_refresh.bats cli/tests/sync.bats
```

### Example 4 — `cli/src/lib.sh` change (today's yaml_to_json cache, e.g.)

Tripwire → **full suite**:
```bash
make test
```

### Example 5 — workflow edit only

Diff: `.github/workflows/ci.yml`.

- NO TESTS in bats.
- Run `make schema` to exercise the `yq eval` check that catches block-scalar parse traps before they hit CI.

```bash
make schema
```

### Example 6 — pure docs change

Diff: `README.md`, `docs/architecture.md`.

- NO TESTS. Skip bats entirely. The CI doc-lint job (if any) will handle prose.

---

## Safety rules

1. **When in doubt, run `make test`.** 41s parallel is cheap; a missed regression caught only on CI costs minutes plus a force-push.
2. **Any change to `cli/src/lib.sh`, `cli/tests/helpers.bash`, `cli/eidolons`, `cli/src/ui/*`, or `schemas/*.json` is always full suite.** No exceptions.
3. **If you wrote a new bats file, run it alongside the file the source change implicates** — your new file is not in any mapping above yet.
4. **After a scoped run passes, do not skip `make lint` and `make schema` if you touched shell or YAML.** Those catch a class of failures bats doesn't (shellcheck, yq block-scalar traps).
5. **Do not invent test names.** If the mapping table doesn't list the touched file, run `make test`; do not guess.
6. **Verify the scoped list actually ran what you expected.** `bats` prints the file list at the top; a typo silently runs zero tests and exits 0.
