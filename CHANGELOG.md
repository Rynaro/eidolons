# Changelog

All notable changes to the **Eidolons nexus** are documented here. The nexus versions independently from individual Eidolons and from EIIS.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning follows [Semantic Versioning](https://semver.org/).

---

## [Unreleased]

### Added
- **`eidolons release <eidolon> <version>` — one-touch maintainer command.**
  Collapses the `Release <EIDOLON>` + `Roster Intake` workflow_dispatch
  chain into a single command. Validates SemVer, gh auth scope per repo,
  workflow file existence, and version precedence (rejects equals/downgrade
  without `--force`). Polls upstream for the tag, dispatches Roster Intake,
  polls for the resulting PR, prints final URLs. Flags: `--check` (dry-run,
  no dispatch), `--resume` (skip Release dispatch when tag exists),
  `--force`, `--auto-merge`, `--yes`, `--non-interactive`,
  `--release-timeout=N` (default 600s), `--intake-timeout=N` (default 300s).
  Exit codes: 0 success, 1 generic, 2 usage/validation, 4 network/timeout,
  5 dispatch failure. Bash 3.2 safe.
- **`eidolons doctor` — Pending Upgrades section.** New information-only
  section between the registry-reachability probe and the summary. Lists
  members where the roster's `versions.pins.stable` is ahead of the
  installed lock entry (within constraint), and flags pinned-out members
  separately. Does not increment `ERRORS`. Offline-degrades silently.
- **Roster Intake auto-merge.** Routine version bumps now open as
  ready-for-review and engage `gh pr merge --auto --squash`; GitHub holds
  the merge until required status checks pass on `main`. First-shipped
  transitions (`status == in_construction`) and bumps against an empty
  `versions.releases` stay DRAFT for explicit human review. The
  release-integrity contract is preserved — auto-merge only auto-clicks
  the merge button after attestation verification has already succeeded.
  See `docs/release-integrity.md` § "Auto-merge of routine roster bumps".

### Changed
- `cli/src/lib.sh` exposes `collect_member_upgrade_rows` and
  `nexus_status_label` as public helpers. `cli/src/upgrade.sh` delegates
  to the lib helpers (no behaviour change). Enables `cli/src/doctor.sh`
  to render the new Pending Upgrades section without duplicating logic.

### Fixed
- `with_timeout` in `cli/src/lib.sh` no longer holds an inherited
  command-substitution pipe open after the polled function returns early
  — the timer subshell now redirects stdout/stderr to `/dev/null`.
  Without this, `$(with_timeout N _poll)` blocked until the timer fired
  regardless of the polled function returning early.
- fix(mcp): doctor probes .atlas/memex/ writability; lib_mcp_atlas_aci.sh exposes pinned-ref accessor; reuse-already-loaded image is now an ATLAS-side contract (PR #2 in Rynaro/ATLAS).

### Added (atlas roster)
- atlas v1.4.0 published in the roster with release integrity metadata.
- **Nexus CLI self-versioning + `eidolons upgrade self`.**
  - `VERSION` file at the nexus root (initial content `1.0.0`) is now the single
    source of truth for the nexus version. `cli/eidolons` reads it via an inline
    `_read_nexus_version()` helper (fallback: `git describe --tags --abbrev=0`, then
    `0.0.0-dev`). The hardcoded `EIDOLONS_VERSION="1.0.0"` constant is replaced.
  - `eidolons --version` (and `eidolons version`, `-v`, `--version`) now prints a
    multi-line enriched block: version, commit SHA, install ref, install date, nexus
    path. `--quiet` / `-q` flag restores the single-line grep-compat form.
  - `eidolons upgrade self` — atomic, integrity-verified, rollback-safe nexus
    self-upgrade. Clones the target ref into `~/.eidolons/nexus.new/`, verifies commit
    + tree + archive SHA-256 against `nexus.versions.releases.<v>` in
    `roster/index.yaml`, runs a smoke test, then renames atomically
    (`nexus → nexus.prev`, `nexus.new → nexus`). Exit codes: 0 ok/no-op, 4 network
    error, 5 integrity mismatch, 6 smoke test failed, 7 no `nexus.prev` for rollback.
    Flags: `--ref`, `--check`, `--rollback`, `--force`, `--non-interactive`.
  - `nexus:` block added to `roster/index.yaml` with `versions.releases.1.0.0`
    integrity metadata (placeholders filled by the release workflow).
  - `.github/workflows/release-nexus.yml` — release workflow that tags, builds the
    archive, computes SHA-256, updates the `nexus.versions.releases.<v>` block in
    `roster/index.yaml`, commits the updated roster, and creates a GitHub Release.
  - `roster-health.yml` gains a `nexus-integrity` job that validates the latest nexus
    release block and skips gracefully when placeholders are still present (bootstrap
    window).
  - `cli/install.sh` writes `VERSION` (from `git describe` when absent) and sidecars
    `.install_date`, `.install_ref`, `.install_commit` into the cloned nexus after
    every fresh install. The sidecars are gitignored.
  - 15 new bats tests in `cli/tests/upgrade_self.bats` covering no-op, upgrade,
    rollback, dirty-tree guard, downgrade warning, integrity failure, smoke-test
    failure, `--check`, and first-install sidecar presence.
  - Versioning bump rules documented in `docs/architecture.md` §"Nexus CLI bump rules"
    and reproduced in `CHANGELOG.md` §"Versioning notes".
  - `docs/cli-reference.md` gains a dedicated `## eidolons upgrade self` section with
    flags, safety properties, and exit codes.
  - README gains a `### Updating` subsection and updated `## Recently shipped` entry.

### Fixed
- `eidolons init` / `eidolons sync` now auto-recover from stale or corrupt
  `~/.eidolons/cache/` entries by re-cloning once before failing. The
  strict integrity contract is preserved: a re-clone that still mismatches
  the roster is fatal with an explicit "upstream-truth mismatch" message.
  Affects all six shipped Eidolons (atlas, spectra, apivr, idg, forge, vigil).
  Root cause was `fetch_eidolon` reusing a cached clone without re-verification
  or recovery, causing fatal `commit mismatch` errors when a force-moved
  upstream tag had updated the roster commit after the initial cache was
  populated. Also handles interrupted clones and corrupt `.git` directories.
  Cache mismatch recovery is bounded to one retry.
- `eidolons doctor` now includes a `Cache hygiene` section (read-only) that
  walks `eidolons.lock` members and compares each `~/.eidolons/cache/` entry
  against the roster's recorded commit, reporting stale or corrupt entries
  with an actionable next-step.

### Added
- spectra v4.2.11 published in the roster with release integrity metadata.
- **`EIDOLONS.md` routing cortex at the repo root** (`.spectra/plans/eidolons-cortex-spec.md` §11.1). Always-loaded ≤900-token descriptor table + 5-step dispatch protocol + 8 chain templates + 6 TRANCE activation gates + 10 cortex invariants, marker-bounded `<!-- eidolon:cortex start --> … <!-- eidolon:cortex end -->`. Closes the routing gap from `.spectra/research/eidolons-cortex-foundation.md` §5: free-form natural-language prompts arriving through Claude Code / Cursor / OpenCode / Codex now have a semantic dispatch path; `cli/eidolons` deterministic string-match (`cli/src/dispatch_eidolon.sh`) is unchanged. Architecture is hierarchical-supervisor with two-stage hybrid dispatch (descriptor soft-match → confidence gate + TRANCE escalation) per spec §4.4 — single-router, cascade-by-strength, and MoA-as-default were rejected with cited reasons.
- **Deep cortex tables under `methodology/cortex/`** (spec §4 progressive disclosure, P3). Loaded on demand by a host that needs them: `handoff-graph.md` (canonical hand-off graph as the union of `roster/index.yaml` and `methodology/composition.md` edges with `edge_origin` labels per spec §7.1, resolving the foundation §4 dispute), `trance-matrix.md` (per-Eidolon TRANCE form, granted capabilities, refusal gates R1–R5, cost ceilings C1–C6), `validation-gates.md` (all 14 GIVEN/WHEN/THEN gates V1–V14 the cortex must satisfy). The README in that directory documents the load-order contract.
- **`eidolons sync` mirrors the cortex into the consumer project at `./.eidolons/cortex/EIDOLONS.md`** plus the deep tables (`trance-matrix.md`, `handoff-graph.md`, `validation-gates.md`, `README.md`) so the on-consumer progressive-disclosure pattern resolves correctly (`cli/src/sync.sh`; spec §11.1). Idempotent, dry-run-aware, bash 3.2 safe. Per-Eidolon installers continue to write only to cwd; the cortex is a nexus-level concern (`docs/architecture.md` Security model row "Nexus CLI").
- **Marker-bounded cortex pointer block injected into root `AGENTS.md` / `CLAUDE.md` / `.github/copilot-instructions.md`** when `--shared-dispatch` is on (spec §11.1 inclusion requirement, I-C1). Pointer-only — keeps `EIDOLONS.md` the single source of truth, respects the ≤900-token I-C4 budget at the consumer surface, honours progressive disclosure (P3). Two new helpers in `cli/src/lib.sh` — `upsert_marker_block` and `remove_marker_block` — share the per-Eidolon installer's marker pattern and are reused for cortex teardown.
- **`eidolons remove` cortex cleanup** (`cli/src/remove.sh`): removes the cortex marker block from host docs and deletes `.eidolons/cortex/` on last-Eidolon removal; preserves the cortex when other Eidolons remain installed.
- **27 new bats tests in `cli/tests/cortex.bats`** covering mirror creation (file + deep tables), marker presence, idempotency on repeat sync, host-doc injection under shared-dispatch, no-injection under `--no-shared-dispatch`, capability-class language only (no vendor model names per `methodology/prime-directives.md:152-162`), presence of all V1–V14 gates in the deep table, and the removal-cleanup paths (last-Eidolon and others-remain). Suite stands at 225/225 pass.
- **Three-line "Cortex" section in `CLAUDE.md`** so codebase contributors find the artifact and the `eidolons sync` mirroring contract from the standard onboarding file.

### Changed
- **`cli/src/sync.sh`** gains a cortex-mirror step (idempotent; runs only when `EIDOLONS.md` exists at the nexus root). Behavior on consumer projects without `eidolons.yaml` is unchanged. The four design principles cited as load-bearing in the spec: routing-as-calibrated-classifier (RouteLLM ICLR 2025, dossier §2 #1), progressive disclosure of descriptors (Anthropic Skills, dossier §3.1), TRANCE = parallel fan-out + isolation + verifier wrapping rather than longer thinking (Anthropic multi-agent research-system + ACL 2025 "Revisiting o1", dossier §3.4 / §2 #18), and capability-class language only — never vendor model names — per D9.

### Fixed
- **GHCR-default pull + `--build-locally` escape hatch for `eidolons mcp atlas-aci pull`** (`.spectra/plans/atlas-aci-ghcr-distribution-2026-05-01/spec.md` T6–T8). `DEFAULT_IMAGE_DIGEST` is now the registry-prefixed form `ghcr.io/rynaro/atlas-aci@sha256:<digest>`; the happy path runs `docker pull` against ghcr.io; the three-alternatives fallback block is demoted to the GHCR-failure path and lists `--build-locally` as alternative #1. The `--build-locally` flag (with optional `--git-ref REF`) builds the image from the upstream git source and is a **non-removable escape hatch** for air-gap and network-restricted environments.
- **Container-runtime security hardening** (`--cap-drop=ALL`, `--security-opt=no-new-privileges`) on the atlas-aci canonical body generated by `eidolons mcp atlas-aci`. Trivy-scan-gated (HIGH/CRITICAL) at publish time; read-only repo mount and dedicated UID 10001 are set in the upstream Dockerfile.
- **ghcr.io registry reachability probe in `eidolons doctor`** (T10). A non-fatal Check 7 performs an anonymous-token HEAD against the ghcr.io v2 manifests endpoint for the pinned digest. On success: `pass: atlas-aci image reachable on ghcr.io`. On 404/network error: `warn: atlas-aci image not reachable (offline? or pinned digest yanked? — try 'eidolons mcp atlas-aci pull --build-locally')`. The probe is skipped silently when `.mcp.json` is absent or has no atlas-aci entry; `curl` absence degrades gracefully.
- **Bootstrap pre-flight refusal** (T-H2): `eidolons mcp atlas-aci` (scaffold) and `eidolons mcp atlas-aci pull` both abort with an actionable error message if `DEFAULT_IMAGE_DIGEST` is still the all-zeros placeholder, preventing misconfigured `.mcp.json` from reaching users before the first real ghcr.io release.
- **P0 invariant test** asserting `--build-locally` cannot be silently removed (`cli/tests/mcp_atlas_aci_pull.bats` — test name includes the literal string `P0 invariant` to surface any removal PR in diffs; `INVARIANT (P0)` comment in `cli/src/mcp_atlas_aci_pull.sh`).
- feat(mcp): pre-flight image check + 'eidolons mcp atlas-aci pull' subcommand; doctor surfaces MCP image health.
- **fix(roster): publish ATLAS v1.3.0 (1.2.2 → 1.3.0).** Bumps ATLAS roster pin to v1.3.0 — the registry-prefixed canonical body for `eidolons atlas aci --container` (replaces the broken bare `atlas-aci@sha256:...` form which Docker resolved to docker.io/library/atlas-aci → 404), plus container-runtime security hardening (`--cap-drop=ALL`, `--security-opt=no-new-privileges`) on all four MCP emit paths (`.mcp.json`, `.cursor/mcp.json`, `.codex/config.toml`, `.github/agents/*.agent.md` Copilot bodies, and the one-time `run_index_container` invocation). Implements §T11 of `.spectra/plans/atlas-aci-ghcr-distribution-2026-05-01/spec.md`. Companion changes already on main: PR #55 (nexus GHCR-default + `--build-locally` escape hatch + doctor probe) and `ATLAS#20` (canonical body). Release-integrity metadata captured from `gh release view v1.3.0 -R Rynaro/ATLAS` (commit `7d9f3acf`, tree `9c377eac`, archive sha256 `7e015397…`); attestation produced by the canonical `eidolon-release-template.yml`.
- **ATLAS subagent silently bypassed the atlas-aci MCP server and used native Read/Grep instead (ATLAS roster pin 1.2.1 → 1.2.2).** After the [1.2.1 fix](https://github.com/Rynaro/ATLAS/pull/15), Claude Code connected to the atlas-aci MCP server cleanly and the seven indexed-graph tools (`view_file`, `list_dir`, `search_text`, `search_symbol`, `graph_query`, `test_dry_run`, `memex_read`) became visible at the project level — but the ATLAS subagent's `tools:` allowlist on line 5 of `.claude/agents/atlas.md` only permitted `Read, Grep, Glob, Bash(rg:*), Bash(git log:*), Bash(git show:*)`. Claude Code refused to expose any `mcp__atlas-aci__*` tool to the subagent, and the agent silently fell back to native Read+Grep. The expensive index sat idle. Fixed in [ATLAS#16](https://github.com/Rynaro/ATLAS/pull/16) — `eidolons atlas aci install` now also rewrites the `tools:` line to add all seven `mcp__atlas-aci__*` entries; `eidolons atlas aci remove` restores the BASE list. Six new bats tests (SUB-1..SUB-6) pin the install→remove cycle. The body of the subagent file and the rest of the frontmatter are untouched, so any user-customised description / handoff settings are preserved. Cursor and Codex don't gate MCP tools per-subagent the same way Claude Code does, so this only touches the Claude Code surface.

### Fixed
- **Claude Code emitted `Missing environment variables: workspaceFolder` on every project load (ATLAS roster pin 1.2.0 → 1.2.1).** The atlas-aci entry written into `.mcp.json` (and the cursor / codex / copilot equivalents) embedded the literal `${workspaceFolder}` placeholder for `--repo`, `--memex-root`, and the docker `-v` bind mount paths. Cursor / VSCode expand the placeholder natively, but Claude Code parses `${VAR}` as an env-var reference and so warned on every project load; the docker mount then dereferenced the literal string and the MCP server failed to attach. Fixed in [ATLAS#15](https://github.com/Rynaro/ATLAS/pull/15) — all four host body generators (`container_json_fragment`, `json_server_fragment`, `_copilot_command_array`, `_codex_canonical_body_container`) now bake the absolute project path (`$PWD` at install time) directly. Three new regression tests (ABS-1/ABS-2/ABS-3) pin the post-install body shape so the placeholder cannot silently come back. Trade-off: `.mcp.json` bodies are now machine-specific — re-run `eidolons atlas aci install` after relocating; gitignore in team workflows where each developer's path differs.

### Added
- **Ecosystem-normalized milestone.** All six shipped Eidolons (ATLAS, SPECTRA, APIVR-Δ, IDG, FORGE, VIGIL) now publish attestation-backed releases via the canonical `eidolon-release-template.yml`, with `versions.releases.<v>` populated in `roster/index.yaml` and verified end-to-end by `eidolons verify`. `integrity.enforcement` flipped from `warn` to `strict` — any consumer install with a commit/tree/archive checksum mismatch now aborts with exit 1 instead of warning.
- vigil v1.0.3 published in the roster with release integrity metadata.
- spectra v4.2.10 published in the roster with release integrity metadata.
- idg v1.1.5 published in the roster with release integrity metadata.
- forge v1.2.1 published in the roster with release integrity metadata.
- apivr v3.0.5 published in the roster with release integrity metadata.
- atlas v1.2.2 published in the roster with release integrity metadata.
- **Release integrity and automation.** Adds roster release metadata schema (`versions.releases`), install-time commit/tree/checksum verification, `eidolons verify`, lockfile integrity fields, release/roster-intake GitHub Actions, and docs for the warn-now/strict-later supply-chain model.
- **`eidolons atlas aci index` first-class re-index subcommand (ATLAS roster pin 1.1.1 → 1.2.0).** Refreshing the atlas-aci code graph previously required either re-running `--install` (which short-circuits on `.atlas/manifest.yaml` and effectively no-ops) or invoking `docker run --rm -v "$PWD":/repo atlas-aci:<ver> index --repo /repo --langs ...` by hand. The latter was a discoverability cliff for both humans and LLMs interacting with the nexus — nothing in `eidolons atlas aci --help` surfaced it. ATLAS [v1.2.0](https://github.com/Rynaro/ATLAS/pull/14) adds a positional `index` action (and `--index` flag form) that auto-detects host vs container mode (preferring host when `atlas-aci` is on PATH; falling back to `docker images :atlas-aci:<ATLAS_VERSION>` then podman; exit 5 with an actionable hint when neither is available). The action bypasses the install-side `.atlas/manifest.yaml` gate (T24) via a new `force` parameter on `run_index`, does NOT rebuild the image, does NOT touch MCP configs or `.gitignore`, and exposes nine new bats cases (IDX-1..IDX-9) covering positional/flag forms, mode auto-detect, prereq-missing exit, gate bypass, dry-run, override semantics, and action conflict.

### Fixed
- **`eidolons atlas aci --container` produced a broken image (ATLAS roster pin 1.1.0 → 1.1.1).** The image built fine but `atlas-aci index` failed at runtime with `ModuleNotFoundError: No module named 'tree_sitter_language_pack'`. Root cause was upstream of ATLAS: the `Rynaro/atlas-aci` production Dockerfile re-resolved transitive deps from PyPI via bare `pip install /tmp/*.whl` and ignored `mcp-server/uv.lock`. When `tree-sitter-language-pack 1.6.3` shipped a restructured wheel (only a `_native/` subpackage; no top-level `tree_sitter_language_pack` module), every fresh `--container` build silently produced an image that crashed on first index. Fixed in [atlas-aci#1](https://github.com/Rynaro/atlas-aci/pull/1) — pyproject constraint `<1.6.3` plus a lock-respecting Dockerfile (`uv export --frozen --no-dev` → `requirements.txt`, then wheel install with `--no-deps`). [ATLAS#12](https://github.com/Rynaro/ATLAS/pull/12) bumped `ATLAS_ACI_PIN`/`ATLAS_ACI_REF` to the merge SHA and tagged `v1.1.1`. This roster bump pulls that release in for everyone running `eidolons upgrade`.

### Added
- **`eidolons atlas aci --container` (container-runtime mode).** ATLAS v1.1.0 adds a second install path for the atlas-aci MCP server: `--container` builds the image locally via Docker or Podman (no GHCR pull; deferred to F1). Runtime selection follows D1 (always-prompt): interactively prompts docker/podman unless `--runtime <docker|podman>` is supplied explicitly; `--non-interactive` without `--runtime` exits non-zero (exit 9). Image is pinned by local sha256 digest captured after build (D3), so re-running against an unchanged image is a no-op. New flags: `--container` (switch), `--runtime <docker|podman>` (enum). New exit codes: 7 (runtime not on PATH), 8 (image build failed), 9 (non-interactive without --runtime). Bumps ATLAS roster pin to 1.1.0 (superseded by 1.1.1 above).
- **`eidolons upgrade` (full implementation, replaces v1.0 stub).** Two surfaces on a single command: `eidolons upgrade --check` is a read-only diff (nexus head vs latest tag on `Rynaro/eidolons`; per-member `eidolons.lock` versions vs `roster/index.yaml` `versions.latest`); `eidolons upgrade` applies member upgrades within `eidolons.yaml` constraints. Bare invocation is project-scoped (members in cwd); `--system` upgrades the nexus only; `--project` is the explicit form of the default and pairs with `--check` to narrow the report; `--all` runs both phases (equivalent to `--system --project`). Also adds `--json`, `--yes`, `--non-interactive`, `--dry-run`, plus positional member arg / comma-separated list. Respects `^/~/=` SemVer constraints (pure-bash `semver_satisfies` helper, no external deps); a latest exceeding the constraint surfaces as `pinned-out` rather than auto-editing the manifest. Network failures during the nexus probe degrade gracefully (10-second timeout via new `with_timeout` helper). Idempotent on repeat runs: lockfile mtime is preserved when no resolved version changed. Spec: `docs/specs/eidolons-upgrade/`.
- **OpenAI Codex** as a first-class supported host (PR #21). `detect_hosts` recognises `.codex/` (precedence) and `AGENTS.md` co-ownership; `eidolons sync` wires both root `AGENTS.md` and per-Eidolon `.codex/agents/<name>.md` subagent files; `--no-shared-dispatch` is overridden-with-warn when `codex` is in the host list.
- **`eidolons atlas aci` Codex MCP wiring.** ATLAS v1.0.6's `commands/aci.sh` registers the atlas-aci stdio MCP server in `./.codex/config.toml` under `[mcp_servers.atlas-aci]` via POSIX `awk` line-bounded TOML rewrite. Idempotent (install→install byte-identical; install→remove→install closure). `docs/atlas-aci.md` updated with the Codex bullet in the host list, the TOML row in the idempotency contract, and the user-level `~/.codex/config.toml` scope-boundary note.

### Changed
- **`eiis_required` bumped from `1.0` to `1.1`** — the roster now requires EIIS v1.1 (Codex addendum). All six shipped Eidolons publish EIIS-1.1-conformant releases.
- **`cli/src/lib.sh` `eiis_check`** delegates to the external checker at [`Rynaro/eidolons-eiis`](https://github.com/Rynaro/eidolons-eiis) when reachable; falls back to the inline file-existence check when offline. The standalone checker (cached at `~/.eidolons/cache/eiis@<version>/`) provides the full §1–§4 contract enforcement; the inline path remains for air-gapped installs.
- **`.github/workflows/roster-health.yml`** clones `Rynaro/eidolons-eiis` and runs the external `conformance/check.sh` against each shipped Eidolon, replacing the previous five-file existence smoke.
- **Roster pin bumps** (all six shipped Eidolons publish EIIS-1.1 + Codex support):
  - ATLAS: `1.0.3` → `1.0.6` (latest bump adds Codex MCP host wiring in `commands/aci.sh`)
  - SPECTRA: `4.2.8` → `4.2.9`
  - APIVR-Δ: `3.0.3` → `3.0.4`
  - IDG: `1.1.3` → `1.1.4`
  - VIGIL: `1.0.1` → `1.0.2`
  - FORGE: `1.1.1` → `1.2.0` (also closes drift items D-1, D-3, D-4 from the EIIS bootstrap audit)

### Added (initial nexus, retained)
- Initial nexus scaffold: roster registry, CLI, methodology aggregation, research library, examples.
- `eidolons` CLI with `init`, `add`, `sync`, `list`, `doctor`, `roster` commands.
- Stubs for `remove`, `upgrade` (full implementation in v1.1).
- JSON Schemas for `eidolons.yaml`, `eidolons.lock`, roster entries.
- Prime directives aggregated from project working notes.
- Composition doc with canonical pipeline and handoff contracts.
- Research library with starter BibTeX + production-patterns doc.
- Examples: greenfield, brownfield-rails, solo-atlas.
- GitHub Actions nightly roster health check.
- FORGE promoted to `shipped` in the roster (v1.1.1). Adds the lateral Reasoner to the `full` preset; first stable release with EIIS-1.0 conformant `install.sh`.
- VIGIL added to the roster as shipped (v1.0.1) — forensic debugger for code failures resistant to normal repair. Introduces a new `debugger` capability class in the roster schema. Added to the `full` preset and to every other Eidolon's lateral handoffs. New `diagnostics` preset (apivr + vigil + forge) for debug-focused work.
- `.claude/skills/add-eidolon/SKILL.md` — codifies the pattern for promoting a new Eidolon to the roster or bumping a version. Captures exploration checklist, roster entry template, CI matrix + documentation touchpoints, and verification steps.

### Depends on
- `Rynaro/eidolons-eiis` (separate repo, EIIS v1.1 standard — bumped from v1.0 in this release).
- Individual Eidolon repos: atlas, spectra, apivr, idg, forge, vigil.

---

## [1.0.0] — TBD

Initial release target. Release criteria:

- All five Eidolon repos EIIS-1.0 conformant and reachable.
- Nightly `roster-health` workflow green for 7 consecutive days.
- `eidolons init` and `sync` exercised end-to-end in at least one greenfield and one brownfield project.
- `remove` and `upgrade` commands fully implemented.
- Research library populated with ≥10 paper summaries under `research/papers/`.

---

## Versioning notes

- **Nexus version** bumps when the CLI, roster schema, or composition contracts change.
- **Individual Eidolon versions** are independent — bumping APIVR-Δ doesn't bump the nexus.
- **EIIS version** is independent — EIIS can bump to 1.1 without forcing a nexus bump.

### Nexus bump rules (from `docs/architecture.md`)

| Bump | Triggers |
|------|---------|
| **MAJOR** | Removing or renaming a built-in CLI subcommand; breaking-change to `eidolons.yaml` or `eidolons.lock` schema; breaking-change to `roster/index.yaml` shape when consumed by the CLI; raising minimum bash / git / jq / yq version; dropping a supported host wiring. |
| **MINOR** | Adding a new built-in subcommand or top-level flag; adding a new optional roster field or schema; adding a new host wiring; new methodology cortex layer; new MCP scaffold. |
| **PATCH** | Bug fix; doc-only change; roster bump for a shipped Eidolon (the most frequent change); internal refactor; CI tweak. |
