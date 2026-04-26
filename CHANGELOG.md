# Changelog

All notable changes to the **Eidolons nexus** are documented here. The nexus versions independently from individual Eidolons and from EIIS.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning follows [Semantic Versioning](https://semver.org/).

---

## [Unreleased]

### Added
- **Release integrity and automation.** Adds roster release metadata schema
  (`versions.releases`), install-time commit/tree/checksum verification,
  `eidolons verify`, lockfile integrity fields, release/roster-intake GitHub
  Actions, and docs for the warn-now/strict-later supply-chain model.
- **`eidolons upgrade` (full implementation, replaces v1.0 stub).** Two surfaces on a single command: `eidolons upgrade --check` is a read-only diff (nexus head vs latest tag on `Rynaro/eidolons`; per-member `eidolons.lock` versions vs `roster/index.yaml` `versions.latest`); `eidolons upgrade` applies member upgrades within `eidolons.yaml` constraints. Bare invocation is project-scoped (members in cwd); `--system` upgrades the nexus only; `--project` is the explicit form of the default and pairs with `--check` to narrow the report; `--all` runs both phases (equivalent to `--system --project`). Also adds `--json`, `--yes`, `--non-interactive`, `--dry-run`, plus positional member arg / comma-separated list. Respects `^/~/=` SemVer constraints (pure-bash `semver_satisfies` helper, no external deps); a latest exceeding the constraint surfaces as `pinned-out` rather than auto-editing the manifest. Network failures during the nexus probe degrade gracefully (10-second timeout via new `with_timeout` helper). Idempotent on repeat runs: lockfile mtime is preserved when no resolved version changed. Spec: `docs/specs/eidolons-upgrade/`.
- **OpenAI Codex** as a first-class supported host (PR #21). `detect_hosts` recognises `.codex/` (precedence) and `AGENTS.md` co-ownership; `eidolons sync` wires both root `AGENTS.md` and per-Eidolon `.codex/agents/<name>.md` subagent files; `--no-shared-dispatch` is overridden-with-warn when `codex` is in the host list.

### Changed
- **`eiis_required` bumped from `1.0` to `1.1`** — the roster now requires EIIS v1.1 (Codex addendum). All six shipped Eidolons publish EIIS-1.1-conformant releases.
- **`cli/src/lib.sh` `eiis_check`** delegates to the external checker at [`Rynaro/eidolons-eiis`](https://github.com/Rynaro/eidolons-eiis) when reachable; falls back to the inline file-existence check when offline. The standalone checker (cached at `~/.eidolons/cache/eiis@<version>/`) provides the full §1–§4 contract enforcement; the inline path remains for air-gapped installs.
- **`.github/workflows/roster-health.yml`** clones `Rynaro/eidolons-eiis` and runs the external `conformance/check.sh` against each shipped Eidolon, replacing the previous five-file existence smoke.
- **Roster pin bumps** (all six shipped Eidolons publish EIIS-1.1 + Codex support):
  - ATLAS: `1.0.3` → `1.0.4`
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
