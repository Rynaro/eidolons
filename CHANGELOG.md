# Changelog

All notable changes to the **Eidolons nexus** are documented here. The nexus versions independently from individual Eidolons and from EIIS.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning follows [Semantic Versioning](https://semver.org/).

---

## [Unreleased]

### Fixed
- **ATLAS subagent silently bypassed the atlas-aci MCP server and used native Read/Grep instead (ATLAS roster pin 1.2.1 → 1.2.2).** After the [1.2.1 fix](https://github.com/Rynaro/ATLAS/pull/15), Claude Code connected to the atlas-aci MCP server cleanly and the seven indexed-graph tools (`view_file`, `list_dir`, `search_text`, `search_symbol`, `graph_query`, `test_dry_run`, `memex_read`) became visible at the project level — but the ATLAS subagent's `tools:` allowlist on line 5 of `.claude/agents/atlas.md` only permitted `Read, Grep, Glob, Bash(rg:*), Bash(git log:*), Bash(git show:*)`. Claude Code refused to expose any `mcp__atlas-aci__*` tool to the subagent, and the agent silently fell back to native Read+Grep. The expensive index sat idle. Fixed in [ATLAS#16](https://github.com/Rynaro/ATLAS/pull/16) — `eidolons atlas aci install` now also rewrites the `tools:` line to add all seven `mcp__atlas-aci__*` entries; `eidolons atlas aci remove` restores the BASE list. Six new bats tests (SUB-1..SUB-6) pin the install→remove cycle. The body of the subagent file and the rest of the frontmatter are untouched, so any user-customised description / handoff settings are preserved. Cursor and Codex don't gate MCP tools per-subagent the same way Claude Code does, so this only touches the Claude Code surface.

### Fixed
- **Claude Code emitted `Missing environment variables: workspaceFolder` on every project load (ATLAS roster pin 1.2.0 → 1.2.1).** The atlas-aci entry written into `.mcp.json` (and the cursor / codex / copilot equivalents) embedded the literal `${workspaceFolder}` placeholder for `--repo`, `--memex-root`, and the docker `-v` bind mount paths. Cursor / VSCode expand the placeholder natively, but Claude Code parses `${VAR}` as an env-var reference and so warned on every project load; the docker mount then dereferenced the literal string and the MCP server failed to attach. Fixed in [ATLAS#15](https://github.com/Rynaro/ATLAS/pull/15) — all four host body generators (`container_json_fragment`, `json_server_fragment`, `_copilot_command_array`, `_codex_canonical_body_container`) now bake the absolute project path (`$PWD` at install time) directly. Three new regression tests (ABS-1/ABS-2/ABS-3) pin the post-install body shape so the placeholder cannot silently come back. Trade-off: `.mcp.json` bodies are now machine-specific — re-run `eidolons atlas aci install` after relocating; gitignore in team workflows where each developer's path differs.

### Added
- spectra v4.2.10 published in the roster with release integrity metadata.
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

A breaking change to `eidolons.yaml` or `eidolons.lock` schemas requires a **major** nexus bump with a migration guide in this file.
