---
name: add-eidolon
description: Promote an Eidolon to the nexus roster or bump an existing Eidolon's version. Use when the user says "publish X", "introduce X in the roster", "add X to the roster", "X is now stable", "bump <eidolon> to vX.Y.Z", or when working on a roster/index.yaml entry. Covers the full workflow — upstream repo normalization (EIIS-1.0 install.sh, version strings, CHANGELOG), roster + preset edits, capability-class schema changes for new classes, CI matrix, documentation touchpoints (README, MANIFESTO, composition.md, CHANGELOG), and verification.
---

# add-eidolon — Promote an Eidolon to the Eidolons nexus roster

This skill codifies the pattern for two related operations:

1. **Promote a new Eidolon to `shipped`** (e.g. FORGE, VIGIL) — adds a roster entry, possibly extends the capability_class enum, updates docs, and activates the nightly EIIS conformance check.
2. **Bump an existing shipped Eidolon's version** (e.g. SPECTRA 4.2.7 → 4.2.8) — changes `versions.latest` / `versions.pins.stable` in the roster, adds a CHANGELOG entry, branch name `fix/roster-<eidolon>-<version>`.

The two flows share ~70% of their checklist. Where they diverge, each section is labeled **[NEW]** or **[BUMP]**.

---

## Invariants you must respect

These come from `CLAUDE.md` in the nexus repo and from tooling contracts — violating them breaks CI or consumer installs:

- **Roster entries drive CI.** The matrix in `.github/workflows/roster-health.yml` (line 69 area) hardcodes Eidolon names. A new member means editing *both* `roster/index.yaml` *and* the matrix. **[NEW]**
- **Install target is `./.eidolons/<member>/`** — dot-prefixed, hidden. Per-Eidolon `install.sh` should default to this.
- **Canonical repo casing matters.** `source.repo` must match GitHub's canonical casing (e.g. `Rynaro/APIVR-Delta`, not `rynaro/apivr-delta`). The clone works either way, but the manifest is used as an identity key.
- **Marker-bounded sections** (`<!-- eidolon:<name> start --> … <!-- eidolon:<name> end -->`) are how multiple Eidolons coexist in shared files — per-Eidolon installers use them; `eidolons remove` relies on them.
- **Bash 3.2 compatibility.** macOS ships bash 3.2. `install.sh` scripts must avoid bash 4+ features (no `declare -A`, no `${var,,}`, no `readarray/mapfile`, no `&>>`).
- **Idempotency.** `eidolons sync` must produce identical output on repeat runs unless the roster or manifest changed. Every `install.sh` must be safe to re-run.
- **No code execution from `eidolons.yaml`.** The pipeline is `yaml → jq query → bash exec` with no `eval`.
- **Direct pushes to nexus `main` are not the pattern.** Land everything through a PR.
- **All log output to stderr** when helpers echo the return value on stdout (see `cli/src/lib.sh` `say/ok/info/warn/die`).

---

## Flow 1: Promoting a new Eidolon to `shipped` [NEW]

### Phase 0 — Exploration (understand the Eidolon)

Before writing anything, establish these facts by reading the Eidolon's repo:

| Fact | Where to find it |
|------|------------------|
| Canonical name (lowercase slug) + display name | `AGENTS.md` frontmatter `name:` field |
| Methodology name, version, cycle, summary | `AGENTS.md` frontmatter + README/entry-point |
| Capability class | Inferred from role — see "Capability classes" table below |
| `source.repo` (canonical casing) | GitHub URL |
| Current version + tag | `git tag -l`; if no tags, you'll need to tag in Phase A |
| Handoff shape (pipeline vs lateral) | See "Lateral vs pipeline classification" below |
| Token budget | Entry = `wc -w agent.md` × 1.33 (or read from CHANGELOG); target = typical working-set measurement |
| Security posture | `reads_repo`, `reads_network`, `writes_repo`, `persists` — read from install.sh and methodology docs |

**Capability classes** (current enum — extend if genuinely new):
- `scout` — read-only exploration (ATLAS)
- `planner` — decision-ready specs (SPECTRA)
- `coder` — implementation (APIVR-Δ)
- `scriber` — documentation synthesis (IDG)
- `reasoner` — structured deliberation (FORGE)
- `debugger` — forensic root-cause attribution (VIGIL)

If you need a new class, add it to `schemas/roster-entry.schema.json` `capability_class.enum`. This is backward-compatible; existing roster entries still validate.

**Lateral vs pipeline classification:**
- **Pipeline members** (scout → planner → coder → scriber): have non-empty `upstream` and `downstream`. Lateral array can reference consultable specialists.
- **Lateral specialists** (reasoner, debugger): `upstream: []`, `downstream: []`, `lateral: [<all other members>]`. Called by any member; results flow anywhere. The nexus `methodology/composition.md` is authoritative — the Eidolon's own `AGENTS.md` may declare pipeline-style handoffs for its own view but the roster uses lateral-only to keep composition clean.
- When adding a new lateral specialist, update every other Eidolon's `lateral` array to include the new one (so `eidolons sync` surfaces the relationship).

### Phase A — Upstream Eidolon repo normalization

The Eidolon repo must satisfy EIIS-1.0 §3 for `eidolons sync` to work:

1. **Required files** (CI enforces): `AGENTS.md`, `CLAUDE.md`, `install.sh`, `agent.md`, `README.md`. If any are missing, add them in the Eidolon's own repo before touching the roster.

2. **`install.sh` must accept the EIIS-1.0 §3 flag set**. The nexus CLI (`cli/src/sync.sh:167`) invokes:
   ```bash
   bash "$clone_dir/install.sh" \
     --target "$target" \
     --hosts "$HOSTS_CSV" \
     [--shared-dispatch|--no-shared-dispatch] \
     [--non-interactive] \
     --force
   ```
   Plus expected: `--version` (prints version, exits 0), `--help` / `-h` (CI tests this), `--dry-run`, `--manifest-only`. See `../ATLAS/install.sh` for the reference shape; `../FORGE/install.sh` and `../VIGIL/install.sh` for adaptations that preserve Eidolon-specific flags (e.g. VIGIL's `--mode read-only|sandbox|write`).

3. **`install.manifest.json` emission**. The nexus CLI reads this to populate `eidolons.lock`. Required fields: `eidolon`, `version`, `methodology`, `installed_at`, `target`, `hosts_wired`, `files_written`, `token_budget`, `security`.

4. **Per-host dispatch files**. At minimum, when `claude-code` is in `HOSTS_CSV`, write `.claude/agents/<name>.md`. The nexus has a safety net (`cli/src/sync.sh:179`) that writes a stub if the installer doesn't, but installers should do this themselves.

5. **Shared-dispatch flag compatibility shim**. If the installer supports `--no-shared-dispatch` (grep for the string), the nexus reads user preference. Installers without the flag get a legacy-mode warning.

6. **Version synchronization**. If the Eidolon has version drift (release tag says vX.Y.Z but footers across methodology files still say vA.B.C), resolve it — update all `*Name vX.Y.Z*` footers across `AGENTS.md`, `README.md`, `CHANGELOG.md` document footer, host wirings, all templates, all skills, all evals. Do NOT rewrite historical CHANGELOG dated entries.

7. **CHANGELOG**. Keep-a-Changelog format. Close out `[Unreleased]` as a concrete version (e.g. `[1.0.1] — 2026-04-23`), add a fresh empty `[Unreleased]` section.

8. **Bash 3.2**. Run shellcheck: `shellcheck -x -S error install.sh`.

9. **Smoke test locally**:
   ```bash
   bash install.sh --version
   bash install.sh --help | head
   bash install.sh --dry-run --target /tmp/<name>-smoke --hosts all
   TMPDIR=$(mktemp -d); bash install.sh --target "$TMPDIR/x" --hosts claude-code --non-interactive --force
   cat "$TMPDIR/x/install.manifest.json" | python3 -m json.tool
   rm -rf "$TMPDIR"
   ```

10. **Commit, tag, push** (ask user first; this hits a shared remote):
    ```bash
    cd ../<EIDOLON>
    git checkout main
    git merge --no-ff <feature-branch> -m "chore(release): <description> for v<X.Y.Z>"
    git tag -a v<X.Y.Z> -m "<EIDOLON> v<X.Y.Z> — <description>"
    git push origin main && git push origin v<X.Y.Z>
    ```
    **Ordering constraint**: Eidolon repo must have the tag/main state *before* the nexus PR merges, so CI can clone and verify EIIS conformance. If the remote has moved during your work (someone merged your PR via GitHub UI), see "Reconciliation" below.

### Phase B — Nexus roster

Branch off origin/main with `feat/roster-<name>-shipped`:

```bash
cd <nexus>
git fetch origin && git checkout main && git merge --ff-only origin/main
git checkout -b feat/roster-<name>-shipped
```

**B.1** — If adding a new `capability_class`, extend the enum in `schemas/roster-entry.schema.json`.

**B.2** — Add entry to `roster/index.yaml` using this template. Pipeline members go after existing pipeline members; lateral specialists go after FORGE:

```yaml
  - name: <lowercase-slug>
    display_name: <DisplayName>
    capability_class: <enum-value>
    status: shipped
    methodology:
      name: <Name>
      version: "<major>.<minor>"
      cycle: "<phase arrow diagram>"
      summary: "<one sentence>"
    source:
      type: github
      repo: Rynaro/<CanonicalName>
      default_ref: main
    versions:
      latest: "<major>.<minor>.<patch>"
      pins:
        stable: "<major>.<minor>.<patch>"
    install:
      target_default: "./.eidolons/<name>"
      standalone: true
    handoffs:
      upstream: [<members>]   # lateral specialists: []
      downstream: [<members>] # lateral specialists: []
      lateral: [<members>]    # for pipeline members: [forge, vigil, ...]
    working_set_tokens:
      entry: <measured>
      target: <measured>
    security:
      reads_repo: <bool>
      reads_network: <bool>
      writes_repo: <bool>
      persists: [<paths>]
    references:
      - "research/papers/<paper>.md"   # optional
```

**B.3** — For new lateral specialists, add the new name to every other Eidolon's `lateral:` array.

**B.4** — Bump `updated_at:` at the top of `roster/index.yaml` to today's ISO-8601 UTC.

**B.5** — Update presets. At minimum add to `full`:
```yaml
  full:
    description: "Every shipped Eidolon — pipeline plus lateral specialists."
    members: [atlas, spectra, apivr, idg, forge, vigil, <new>]
```
If the new Eidolon suggests a named bundle, add a preset (e.g. `diagnostics: [apivr, vigil, forge]`).

**B.6** — **Release-integrity setup (v1.0+)**.

Every `status: shipped` Eidolon should declare release integrity metadata
under `versions.releases.<latest>`. Compatibility mode (`integrity.enforcement:
warn` at the top of `roster/index.yaml`) keeps unannotated entries non-fatal,
but a future registry bump will switch enforcement to `strict` — at which
point every shipped Eidolon must populate metadata or fail the
`shipped-status integrity metadata posture` step in `roster-health.yml`.

Authoring loop:

1. **Adopt the release workflow template.** Copy
   `.github/workflows/eidolon-release-template.yml` from the nexus into the
   upstream Eidolon repo as `.github/workflows/release.yml`. The template
   uses `workflow_call` so the upstream repo wraps it with a thin `on:
   workflow_dispatch` caller. The template emits a `release-manifest.json`
   with `commit`, `tree`, `archive_sha256`, optional `manifest_sha256`, and
   `provenance.github_attestation: true`.
2. **Run a release.** Trigger the wrapper workflow with the SemVer (no
   leading `v`). It tags, attests, and uploads `release-manifest.json` plus
   `SHA256SUMS` to the GitHub release.
3. **Run `Roster Intake` from the nexus.** From the nexus repo's Actions
   tab, dispatch `roster-intake.yml` with the Eidolon name + version. The
   workflow downloads the upstream `release-manifest.json`, verifies the
   SHA256SUMS file and the GitHub artifact attestation, edits
   `roster/index.yaml` (writing `versions.releases.<v>`), and opens a draft
   PR.
4. **Review + merge the intake PR.** The body is auto-generated; nothing to
   hand-author. Merging activates the new metadata.

After merge, every consumer running `eidolons sync` or `eidolons upgrade`
clones the exact tag, verifies `commit` + `tree` + `archive_sha256` against
the cloned repo, and writes `verification: "verified"` into
`eidolons.lock`. Consumers can re-check at any time with `eidolons verify`,
or surface the per-member status from `eidolons doctor`.

Hash semantics (see `docs/release-integrity.md` for full detail):

- `commit` / `tree`: Git object IDs. Tree is content-addressed and survives
  history rewrites that preserve tree contents.
- `archive_sha256`: SHA-256 of `git archive --format=tar HEAD`. Tree-wide
  drift detection.
- `manifest_sha256`: SHA-256 of the single file
  `./.eidolons/<name>/install.manifest.json` after install. File-scoped, so
  it survives legitimate host-wiring variation. Optional — many Eidolons
  leave it `null`.

### Phase C — CI matrix + documentation

**C.1** — `.github/workflows/roster-health.yml` line 69 area:
```yaml
matrix:
  eidolon: [atlas, spectra, apivr, idg, forge, <new>]
```

**C.2** — `README.md` roster table: add a row under the existing members.

**C.3** — `MANIFESTO.md` team table: add a row. If the new Eidolon is a lateral specialist, update the "canonical pipeline" phrase (MANIFESTO.md:33 currently: "ATLAS → SPECTRA → APIVR-Δ → IDG, with FORGE (reasoning) and VIGIL (forensic debugging) as lateral specialists").

**C.4** — `methodology/composition.md`:
  - Update the pipeline diagram (§ canonical pipeline) to show the new lateral specialist.
  - Add a row to the handoff contracts table (§ handoff contracts).
  - Update the consultation-pattern example if the Eidolon is lateral.
  - Add a row to "Common partial configurations" table.
  - Add the Eidolon to the shared-memory model list.

**C.5** — `CHANGELOG.md` (nexus) under `[Unreleased]` → `### Added`:
```
- <EIDOLON> added/promoted to `shipped` in the roster (v<X.Y.Z>). <One-line why.>
```

### Phase D — Verification

From the nexus root:

```bash
# Schema + structural
jq empty schemas/*.json
yq eval '.' roster/index.yaml > /tmp/roster.json  # yq v4 defaults to YAML; for JSON: yq -o=json
yq eval -o=json '.' roster/index.yaml > /tmp/roster.json
for name in $(jq -r '.eidolons[].name' /tmp/roster.json); do
  jq -e --arg n "$name" '.eidolons[] | select(.name == $n) |
    .methodology.name and .methodology.version and .methodology.cycle and
    .source.repo and .versions.latest and
    .handoffs.upstream and .handoffs.downstream' /tmp/roster.json > /dev/null \
    && echo "$name: ok" || echo "$name: MISSING"
done

# CLI smoke
EIDOLONS_NEXUS="$(pwd)" bash cli/eidolons list
EIDOLONS_NEXUS="$(pwd)" bash cli/eidolons roster show <name>

# Shellcheck + tests
find cli -name '*.sh' -type f -print0 | xargs -0 shellcheck -x -S error
shellcheck -x -S error cli/eidolons
bats cli/tests/

# Upstream (from the Eidolon repo)
cd ../<EIDOLON>
bash install.sh --help > /dev/null
bash install.sh --version
```

### Phase E — PR

Push the feature branch, open PR against nexus main:

```bash
git push -u origin feat/roster-<name>-shipped
gh pr create --title "feat(roster): publish <NAME> v<X.Y.Z> (<one-line role>)" --body "$(cat <<'EOF'
## Summary
- Promotes <NAME> from in_construction to shipped (or: adds <NAME> to the roster as shipped).
- Adds to the `full` preset [+ any new presets].
- [Schema change: new `<class>` capability_class — backward-compatible enum extension]
- [Lateral wiring: adds <name> to every other Eidolon's lateral array]

Handoffs are <lateral-only | pipeline> per composition.md.

Upstream <NAME> is tagged v<X.Y.Z> on main (Rynaro/<NAME>@<sha>). The roster-health matrix already includes <name> — this PR activates EIIS conformance + install.sh --help smoke against the upstream repo on every push and nightly.

## Test plan
- [x] jq empty schemas/*.json clean
- [x] yq parse ok; CI validate-roster loop all `ok`
- [x] eidolons list + roster show <name> render correctly
- [x] shellcheck clean, bats N/N passing
- [x] upstream install.sh --help / --version / --dry-run clean
- [ ] CI roster-health green post-merge

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## Flow 2: Bumping an existing shipped Eidolon's version [BUMP]

Branch: `fix/roster-<eidolon>-<version-dashes>` (example: `fix/roster-spectra-4-2-8`).

1. **Verify the upstream tag exists**: `gh release view v<X.Y.Z> --repo Rynaro/<NAME>` or `git ls-remote --tags git@github.com:Rynaro/<NAME>.git | grep <version>`.

2. **Edit `roster/index.yaml`** — only two/three lines change:
   ```yaml
   versions:
     latest: "<new-version>"
     pins:
       stable: "<new-version>"
   ```
   Also bump `methodology.version:` if the major.minor changed.
   Bump `updated_at:` at the top.

3. **(Preferred) Run `Roster Intake`** from the nexus Actions tab with the
   Eidolon name + version. It auto-edits `versions.latest`,
   `versions.pins.stable`, and `versions.releases.<new-version>` from the
   upstream `release-manifest.json` and opens a draft PR. Skip the manual
   roster edit when the upstream Eidolon ships signed releases via
   `eidolon-release-template.yml`.

4. **(Manual fallback)** If the upstream Eidolon hasn't adopted the release
   workflow, edit the roster as above. Compatibility-mode warnings will
   surface in `roster-health.yml` until release metadata is added — that's
   intentional, not a regression.

5. **CHANGELOG.md** (nexus) under `[Unreleased]` → `### Added` or `### Changed`:
   ```
   - <NAME> v<X.Y.Z> published in the roster. <One-line release summary if non-trivial.>
   ```

6. **Verification** — same commands as Phase D above.

7. **PR**: commit message `fix(roster): publish <NAME> v<X.Y.Z>`, PR title matches.

No other touchpoints. Schema doesn't change; docs (README/MANIFESTO/composition) don't change unless the version bump introduces new capabilities worth surfacing.

---

## Reconciliation: remote moved during your work

If you pushed to the upstream Eidolon repo and got `! [rejected] main -> main (fetch first)` because someone merged your PR via GitHub UI in parallel, **do not force-push**. Instead:

1. `git fetch origin`
2. Compare your local main against origin/main: `git log --oneline --left-right main...origin/main`. If origin has the same work via a different merge commit (e.g. PR merge via UI), your local merge commit is redundant.
3. Identify which of your commits aren't on origin: typically a `chore(release): bump …` or similar.
4. `git reset --hard origin/main` — **safe only if those commits are preserved on another branch** (like your feature branch). Verify first: `git log --oneline <feature-branch>`.
5. Delete the stale tag locally if it pointed into the discarded merge commit: `git tag -d v<X.Y.Z>`.
6. Cherry-pick the missing commit(s) onto the reset main: `git cherry-pick <sha>`.
7. Re-tag: `git tag -a v<X.Y.Z> -m "…"`.
8. Push main and tag.

This happened in PR #17 (FORGE v1.1.1) — see the git log for `eec2d6e` (UI merge of PR #1) followed by `ce66734` (cherry-picked version bump). Document any similar incident in the nexus CHANGELOG if it affects consumers.

---

## Anti-patterns (have burned us before)

- **Editing `main` directly in the nexus**. Always a feature branch + PR. Direct pushes violate the established pattern.
- **Loose capability_class values**. `capability_class` is an enum, not free text. Pick from the current list or extend the schema explicitly.
- **Forgetting the CI matrix**. CI is hardcoded per Eidolon name at `roster-health.yml` line 69. Adding an Eidolon without matrix update means no CI coverage.
- **Pipeline-style handoffs for lateral specialists**. FORGE's own `AGENTS.md` declares pipeline-style upstream/downstream because that's how FORGE sees its own role — but the nexus roster is authoritative for composition, and composition.md calls for lateral-only. Keep the roster lateral for reasoners/debuggers.
- **Not running shellcheck and bats before pushing**. The CI on Ubuntu + macOS (bash 3.2) catches what the dev box misses — but you can catch most of it locally first.
- **Rewriting historical CHANGELOG entries**. When closing `[Unreleased]` as a version, leave prior dated entries alone. Only move the heading down and add a fresh `[Unreleased]`.
- **Lowercase canonical repo names**. `Rynaro/APIVR-Delta` is canonical, not `Rynaro/apivr-delta`. `source.repo` is an identity key.

---

## Worked examples in git history

- **FORGE v1.1.1 (new shipped)** — PR #17 (`feat(roster): publish FORGE v1.1.1`). Full new-Eidolon flow: install.sh EIIS-1.0 rewrite, version drift resolution (footer sync G-12/G-13), `in_construction → shipped` promotion, `full` preset addition.
- **VIGIL v1.0.1 (new shipped)** — PR #TBD (`feat(roster): publish VIGIL v1.0.1`). New capability_class (`debugger`), lateral specialist wiring (touches every other Eidolon's `lateral` array), new `diagnostics` preset.
- **SPECTRA 4.2.7 → 4.2.8 (version bump)** — `fix/roster-spectra-4-2-8`. Minimal roster-only change.

Follow whichever worked example most closely matches your current task.
