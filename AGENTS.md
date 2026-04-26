# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## What this repo is

This is the **Eidolons nexus** — the registry and CLI orchestrator for a team of AI agents (ATLAS, SPECTRA, APIVR-Δ, IDG, FORGE). It is **not** itself an Eidolon. Each Eidolon lives in its own public repo (`Rynaro/ATLAS`, `Rynaro/SPECTRA`, etc.) and is independently installable, versioned, and self-contained. The nexus only coordinates: it publishes the roster, ships the `eidolons` CLI, and defines how members compose.

The four-layer model is load-bearing — changes stay inside a layer whenever possible (see `docs/architecture.md`):

1. **EIIS** (`Rynaro/eidolons-eiis`, external) — the install contract every Eidolon satisfies.
2. **Eidolon repos** (external) — each methodology + its own `install.sh`.
3. **This nexus** — roster, CLI, methodology, research.
4. **Consumer project** — `eidolons.yaml` + `eidolons.lock` + `.eidolons/<member>/`.

## Common commands

```bash
# Tests (bats)
bats cli/tests/                   # full suite
bats cli/tests/init.bats          # single file
bats cli/tests/init.bats -f "preset pipeline"   # single test by name pattern

# Lint
find cli -name '*.sh' -type f -print0 | xargs -0 shellcheck -x -S error
shellcheck -x -S error cli/eidolons

# Schema + roster structural checks (what CI runs)
jq empty schemas/*.json
yq eval '.' roster/index.yaml     # parse check

# Run the CLI against this checkout without global install
EIDOLONS_NEXUS="$(pwd)" bash cli/eidolons list
```

Bats tests set `EIDOLONS_NEXUS=$EIDOLONS_ROOT` (see `cli/tests/helpers.bash`) so the CLI resolves the roster from the checkout rather than `~/.eidolons/nexus`. When debugging a test interactively, export that same variable.

## CLI architecture

`cli/eidolons` is a thin dispatcher. It parses the first argument and `exec`s the matching script in `cli/src/` (e.g. `init` → `cli/src/init.sh`). If the first argument is **not** a built-in command, it's checked against `roster_list_names`; a match delegates to `cli/src/dispatch_eidolon.sh`, which looks for `./.eidolons/<name>/commands/<sub>.sh` in the consumer project (installed target) with the nexus cache (`~/.eidolons/cache/<name>@<ver>/commands/`) as fallback.

All subcommand scripts source `cli/src/lib.sh` for shared helpers. The important ones:

- `yaml_to_json <file>` — prefers `yq` (mikefarah Go or kislyuk Python variants are both handled), falls back to `python3 -c 'import yaml'`. `yq` is a hard runtime dependency auto-installed by `cli/install.sh`; the Python fallback exists only as a best-effort for dev boxes.
- `roster_get / roster_list_names / roster_preset_members / roster_presets` — all reads go through `roster/index.yaml`, the single source of truth for what members exist, where they live (`source.repo`), what versions resolve, and which presets bundle them.
- `detect_hosts` — sniffs cwd for `AGENTS.md`, `.Codex/`, `.github/`, `.cursor/`, `.opencode/` to decide which host environments to wire.
- `fetch_eidolon <name> <version>` — shallow git clones the Eidolon's repo into `~/.eidolons/cache/<name>@<version>/`. `install.sh` then runs from that cache.
- All log output (`say/ok/info/warn/die`) goes to **stderr** so functions whose stdout is captured (e.g. `fetch_eidolon` echoes the cache path) stay uncorrupted. Preserve this when adding helpers.

`cli/install.sh` is the curl-pipe bootstrap. It `git init + fetch + checkout FETCH_HEAD` (rather than `git clone --branch`) specifically so `EIDOLONS_REF` accepts commit SHAs as well as branches/tags — useful when CI pins to `github.sha`.

### Bash 3.2 compatibility

macOS ships bash 3.2 as the system shell, and users run the CLI through it. Avoid bash 4+ features in `cli/src/*.sh` and `cli/install.sh`: no associative arrays (`declare -A`), no `${var,,}`/`${var^^}` case conversion, no `readarray`/`mapfile`, no `&>>`. Commit `116df8f` and `6a5689a` fixed previous regressions here — a bash 3.2 fallback path is expected, not optional. The `cli-tests` CI job on `macos-latest` catches these.

## Key invariants when changing code

- **Idempotency.** `eidolons sync` must produce identical output on repeat runs unless the roster or manifest changed. Same for `install.sh`: the CI job "Second install run is idempotent" enforces this.
- **Marker-bounded sections.** Every per-Eidolon installer writes into shared files (root `AGENTS.md`, `AGENTS.md`, copilot instructions) inside `<!-- eidolon:<name> start --> … <!-- eidolon:<name> end -->` blocks. Multiple Eidolons coexist and `eidolons remove` relies on these markers.
- **No code execution from `eidolons.yaml`.** The pipeline is `yaml → jq query → bash exec` with no `eval`. Don't introduce dynamic evaluation of consumer-project config.
- **Per-Eidolon `install.sh` writes only to cwd.** The nexus CLI writes to `$EIDOLONS_HOME` and cwd; per-Eidolon installers get cwd only. See the table in `docs/architecture.md` §"Security model".
- **Roster entries drive CI.** The matrix in `.github/workflows/roster-health.yml` hardcodes the Eidolon names — adding a new member means updating both `roster/index.yaml` and the matrix. `in_construction` status skips the EIIS conformance check.
- **Install target is `./.eidolons/<member>/`** (dot-prefixed, hidden). This moved from a visible directory in commit `3540ca2`; don't regress to a top-level `eidolons/` target.
- **Canonical repo casing matters.** `source.repo` values in the roster must match GitHub's canonical casing (`Rynaro/APIVR-Delta`, not `rynaro/apivr-delta`) — the clone works either way but the manifest is used as an identity key downstream. Commit `67949f7` locked this in.

## Roster changes

`roster/index.yaml` is validated by both CI workflows. Every entry must have `methodology.{name,version,cycle}`, `source.repo`, `versions.latest`, and `handoffs.{upstream,downstream}`. `registry_version` at the top is for breaking schema changes to the file itself — bump it if you change the shape, not just the contents. Presets are name → member-list bundles consumed by `eidolons init --preset`.

When a shipped Eidolon publishes a new version, the path is: update the Eidolon's own repo + tag → bump `versions.latest` and `versions.pins.stable` here → merge → nightly `roster-health` catches any upstream regression.

This version-bump flow is the most frequent change in this repo — the majority of recent commits are `fix(roster): publish <EIDOLON> vX.Y.Z`. Follow the branch convention `fix/roster-<eidolon>-<version>` (e.g. `fix/roster-spectra-4-2-8`) and land it through a PR; direct pushes to `main` are not the pattern here. CHANGELOG.md gets a matching entry.

## Notes on scope

- Don't embed per-Eidolon methodology content in this repo. It belongs in the individual Eidolon repos.
- Don't add package-manager publishing (npm/pip/brew) — the `curl | bash` flow is a deliberate design choice (see `docs/architecture.md` §"Why not a package manager").
- `MANIFESTO.md` and `methodology/prime-directives.md` are the voice/design documents; update them when the project's principles actually shift, not for incidental changes.
