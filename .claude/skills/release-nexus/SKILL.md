---
name: release-nexus
description: Cut a release of the Eidolons nexus itself. Use when the user says "cut a nexus release", "release the nexus", "ship v2.4.0", or after merging changes that should be published. Covers the semver call, the VERSION/CHANGELOG cut, dispatching release-nexus.yml, and the integrity-metadata PR — which never gets CI, so you must verify it by hand. Distinct from `add-eidolon` (Eidolons) and `bump-mcp` (MCP servers), which release *other* things into the roster.
---

# release-nexus — Cut a release of the Eidolons nexus

Three release skills exist and they release different things. `add-eidolon` publishes an **Eidolon** into `roster/index.yaml`. `bump-mcp` pins an **MCP server** in `roster/mcps.yaml`. This one releases **the nexus itself** — the CLI, the roster, the methodology.

## The shape

```
1. PR: bump VERSION + finalise CHANGELOG        -> merge to main
2. gh workflow run release-nexus.yml -f version=X.Y.Z
     validates VERSION == requested (refuses otherwise)
     creates the tag, builds the canonical archive
     opens a PR: "chore(roster): record nexus vX.Y.Z release integrity metadata"
     creates the GitHub Release
3. Verify that PR by hand (it gets NO CI), then merge
```

The commit titles are load-bearing conventions: `chore(release): cut nexus vX.Y.Z — <summary>` then `chore(roster): record nexus vX.Y.Z release integrity metadata`.

## Phase 0 — Pick the version, and justify it

The nexus versions independently of every Eidolon, of EIIS, and of the MCPs it pins.

- **Major** — a break in the nexus's *own* surface: CLI flags, `schemas/`, the four sibling contracts, or `catalogue_version`.
- **Minor** — a new capability (a skill, a CLI verb, a new MCP in the catalogue), or a consumer-visible behaviour change. *Precedent: 2.3.0 added the atomos MCP; 2.4.0 added the `bump-mcp` skill and majored the atlas-aci pin.*
- **Patch** — fixes and pin bumps that do not change what a consumer experiences. *Precedent: 2.3.1 rolled tonberry `0.5.0 → 0.5.2`, diagnostic-only, MCP surface unchanged.*

**A pinned MCP going major does not make the nexus major.** It does make it at least a minor: `eidolons mcp upgrade <name>` will hand a consumer breaking behaviour, and they deserve to see that in a version number. Say so explicitly in the CHANGELOG.

## Phase 1 — The cut

```bash
git checkout -b chore/release-X.Y.Z origin/main
echo "X.Y.Z" > VERSION
```

`CHANGELOG.md`: promote `## [Unreleased]` to `## [X.Y.Z] — YYYY-MM-DD — <one-line summary>`, leaving an empty `[Unreleased]` above it. Sections are Keep-a-Changelog (`### Added` / `### Changed` / `### Fixed` / `### Removed`).

**Audit the changelog against the actual diff, not against your memory of it.** Squash-merges hide things:

```bash
git log --oneline <last-tag>..main
git diff --name-only <last-tag>..main
```

In 2.4.0 the `bump-mcp` skill shipped inside a squashed PR and had **no changelog entry at all** — a released capability nobody announced. Every changed path should map to a changelog line or be deliberately silent.

Verify before pushing:

```bash
EIDOLONS_NEXUS="$(pwd)" bash cli/eidolons version   # must print the new version
make schema
bats cli/tests/version.bats cli/tests/art-lint.bats
bats cli/tests/                                     # sequential; `make test` needs GNU parallel
```

Stage **exact paths**. This repo's tree routinely carries uncommitted `.mcp.json` / `.gitignore` edits that are not yours.

## Phase 2 — Dispatch

`VERSION` must already be on `main`. The workflow reads the file and refuses if it disagrees with the requested version — this is a real gate, not a formality.

```bash
gh workflow run release-nexus.yml -f version=X.Y.Z
gh run list --workflow=release-nexus.yml --limit 1
```

On `workflow_dispatch` the workflow creates the tag itself. (A `push: tags` trigger also works and short-circuits tag creation.) It then builds `eidolons-X.Y.Z.tar.gz`, computes an integrity hash, writes the metadata block, opens a PR, and cuts the GitHub Release.

## Phase 3 — The integrity PR gets no CI. Verify it yourself.

The workflow opens `chore(roster): record nexus vX.Y.Z release integrity metadata` as `github-actions[bot]`. **Workflows do not run on PRs created with `GITHUB_TOKEN`** — GitHub's recursion guard. The run sits at `action_required` forever, `gh pr checks` returns nothing, and `gh api .../actions/runs/<id>/approve` fails with `403: This run is not from a fork pull request`.

So the one PR that carries the repository's integrity claim is the one PR nothing checks. Verify it by hand:

```bash
git checkout -B verify origin/chore/nexus-release-X.Y.Z
make schema
yq eval '.' roster/index.yaml > /dev/null
bats cli/tests/roster.bats cli/tests/version.bats cli/tests/upgrade_self.bats
```

Then **recompute all three integrity fields** from the tag:

```bash
git rev-parse "vX.Y.Z^{commit}"     # must equal the recorded `commit`
git rev-parse "vX.Y.Z^{tree}"       # must equal the recorded `tree`
git archive --format=tar --prefix="eidolons-X.Y.Z/" "vX.Y.Z" | sha256sum
```

### `archive_sha256` is the RAW tar, not the published `.tar.gz`

The release asset is gzipped; the recorded hash is over the **uncompressed** tar, because that is what the consumer recomputes. Hashing the downloaded `eidolons-X.Y.Z.tar.gz` produces a **false mismatch** and will make you think the release is broken. It isn't.

The prefix matters too — `git_archive_sha256` in `cli/src/lib.sh` documents why: *"The prefix changes every byte of the tar (every entry's path is prepended with it), so the consumer-side hash MUST use the same prefix or every comparison will be a false mismatch."*

The strongest check is to run the consumer's own helper against a real clone at the tag:

```bash
T=$(mktemp -d); git clone -q --no-local . "$T/nexus"; git -C "$T/nexus" checkout -q vX.Y.Z
source cli/src/lib.sh
git_archive_sha256 "$T/nexus" "eidolons-X.Y.Z/"     # must equal the recorded archive_sha256
```

If that matches, `eidolons verify` and `eidolons upgrade self` will succeed for every consumer under `integrity.enforcement: strict`. If it doesn't, **do not merge** — a wrong `archive_sha256` breaks every consumer's upgrade path.

## Phase 4 — ESL

The nexus runs ESL. A release cut right-sizes to `trivial` (VERSION + CHANGELOG, no spec required):

```bash
tb propose --change_id release-nexus-X-Y-Z --maker vivi --checker kupo --has_code false --project_root /workspace
tb right_size --change_id … --files_touched 2 --rubric_score 1 --tradeoff_present false --project_root /workspace
```

## Traps

- **`gh pr checks` returning empty is not "all green".** On the bot PR it means no checks exist. Read the run list, not the check list.
- **`archive_sha256` is the raw tar.** Hashing the release asset gives a false mismatch.
- **`VERSION` must land on `main` before dispatch.** The workflow validates it and exits 1.
- **Squash-merges hide changelog gaps.** Diff `<last-tag>..main` and account for every path.
- **`make test` needs GNU `parallel`.** Fall back to `bats cli/tests/` (~2m30s).
- **`doctor_deep.bats` `DD-7` fails on a clean tree** at time of writing. Check a red test against a clean tree before blaming the release.
- **A pinned MCP's major is not the nexus's major** — but it is at least a minor, and it belongs in the changelog's breaking section.
