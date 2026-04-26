# Spec: `eidolons upgrade` and `eidolons upgrade --check`

> **Status:** Draft (SPECTRA-produced, decision-ready)
> **Cycle:** S → P → E → C → T → R → **A** (this artifact = `A`-stage spec)
> **Target:** Eidolons nexus CLI (`Rynaro/eidolons`), v1.1
> **Replaces:** the v1.0 stub at `cli/src/upgrade.sh` (currently prints workaround instructions and exits 1)
> **Companion machine-readable spec:** [`spec.yaml`](./spec.yaml)
>
> **Revision 2026-04-26:** §11 supersedes §4.1 and §4.3 on scope-flag UX. Sections 1–10 retain
> historical decisions for traceability but the **flag surface defined in §11.4 is authoritative**
> for implementation. APIVR consumes §11 first; if §11 contradicts an earlier section, §11 wins.

---

## 1. Overview

### 1.1 What we're building

Two surfaces on a single command:

| Invocation | Mode | Side effects |
|---|---|---|
| `eidolons upgrade --check` | read-only diff | none — prints what *could* change |
| `eidolons upgrade` | mutating | re-runs the appropriate fetch + install path |

`upgrade` answers two distinct questions, on two distinct artifacts:

1. **Is the nexus itself out of date?** (i.e. `~/.eidolons/nexus` HEAD vs. the latest published nexus tag on `Rynaro/eidolons`)
2. **Are the Eidolon members in *this* consumer project out of date?** (i.e. versions in `eidolons.lock` vs. the corresponding `versions.latest` in the nexus's `roster/index.yaml`)

These are coupled but not identical. The roster ships *with* the nexus, so member version metadata only refreshes when the nexus refreshes. That means a nexus upgrade is *typically a prerequisite* for discovering new member versions — but a user may still want to run member upgrades alone after they've manually pulled the nexus, and may want to upgrade the nexus alone in an environment with no consumer project.

### 1.2 Why now

Today, upgrading is a manual three-step ritual the user has to remember:
1. Re-run the curl-pipe installer (or `git pull` inside `~/.eidolons/nexus`).
2. Manually edit `eidolons.yaml` to bump version constraints.
3. `rm -rf ~/.eidolons/cache && eidolons sync`.

This is error-prone, undiscoverable, and asymmetric (the nexus updates are entirely out-of-band relative to the per-project state). `eidolons upgrade --check` is the missing observability primitive; `eidolons upgrade` is the missing action primitive.

### 1.3 Scope of the change

- Replace the v1.0 stub `cli/src/upgrade.sh` with a real implementation.
- No changes to `eidolons.yaml` or `eidolons.lock` schemas.
- No changes to per-Eidolon `install.sh` contracts (EIIS).
- No changes to `roster/index.yaml` shape.
- New helpers in `cli/src/lib.sh` only where they're reusable (network probes, version-comparison primitives).
- New bats suite at `cli/tests/upgrade.bats`.

### 1.4 Non-goals (out of scope)

- **Package-manager publishing** (npm/pip/brew). Forbidden by `CLAUDE.md` — `curl | bash` is deliberate.
- **Editing `eidolons.yaml` constraint operators** (e.g. rewriting `^1.0.0` to `^1.1.0`). The manifest declares user *intent*; upgrade respects that intent. If the user has pinned `^1.0.0`, we won't silently bump them to `2.0.0`. (See §4.4 Pin policy.)
- **Downgrading.** Not in this surface. If a user wants to roll back, they edit `eidolons.yaml` and `eidolons sync`.
- **Cross-project upgrades** (running `upgrade` outside cwd to upgrade a *different* project). Always cwd-scoped, like `sync` and `doctor`.
- **Auto-applying a nexus upgrade then auto-applying member upgrades in one shell invocation.** See §4.1 — we surface both, but the nexus self-upgrade is a re-exec boundary that must end the process cleanly. The user re-runs `eidolons upgrade` after the nexus is current.
- **EIIS version upgrades.** The EIIS install-contract version is resolved at `sync` time via `fetch_eiis` and is not user-facing as a pinned dependency. Out of scope here.

---

## 2. User stories (GIVEN / WHEN / THEN)

### Story U1 — Discover available upgrades, no project context

**As** a user managing the nexus globally on my workstation,
**I want** to know whether my nexus install is behind the published release,
**so that** I can decide whether to re-run the bootstrap.

- **GIVEN** I have the CLI installed at `~/.eidolons/nexus` on a stale commit
- **AND** I am in any directory (no `eidolons.yaml` required)
- **WHEN** I run `eidolons upgrade --check`
- **THEN** the command lists the current nexus commit/tag and the latest available tag from `Rynaro/eidolons`
- **AND** prints a one-line action hint pointing at the curl-pipe re-install command
- **AND** exits 0 (informational, not an error) regardless of whether the nexus is current
- **AND** does not modify any file on disk
- **AND** does not require a `eidolons.yaml`

### Story U2 — Discover available upgrades, with project context

**As** a developer working on a project with `eidolons.yaml`,
**I want** to know which members in this project have new versions available,
**so that** I can plan an upgrade window.

- **GIVEN** my project has `eidolons.yaml` and `eidolons.lock`
- **AND** at least one member's `eidolons.lock` version is older than the roster's `versions.latest`
- **WHEN** I run `eidolons upgrade --check`
- **THEN** the command prints both the nexus check (Story U1) AND a per-member table:
  - columns: `MEMBER`, `INSTALLED`, `LATEST`, `STATUS`
  - statuses: `up-to-date`, `upgrade available`, `pinned-out` (latest exceeds the user's `eidolons.yaml` constraint), `not-installed` (declared in manifest but no lock entry)
- **AND** exits 0
- **AND** does not modify any file
- **AND** prints an action hint per status (e.g. "Run `eidolons upgrade` to apply" for `upgrade available`)

### Story U3 — Apply member upgrades

**As** a developer ready to take member upgrades,
**I want** a single command that brings every member to the latest version permitted by my `eidolons.yaml` constraints,
**so that** I don't have to manually edit, clear caches, and re-sync.

- **GIVEN** my project has `eidolons.yaml`, `eidolons.lock`, and at least one member with `upgrade available` status
- **WHEN** I run `eidolons upgrade`
- **THEN** the command:
  1. Performs an internal `--check` first and shows the upgrade plan
  2. Asks for confirmation (interactive only — `--yes` skips, `--non-interactive` requires `--yes` or fails)
  3. For each member with `upgrade available`: invalidates `~/.eidolons/cache/<name>@<old-version>`, fetches `<name>@<latest>`, runs the per-Eidolon `install.sh` (same flow as `sync`)
  4. Re-writes `eidolons.lock` with the new resolved versions and commits
- **AND** exits 0 on full success
- **AND** is idempotent: running `eidolons upgrade` again immediately after produces "all members up-to-date" and exits 0 with no disk changes
- **AND** preserves `eidolons.yaml` exactly (no edits to constraints)

### Story U4 — Upgrade the nexus itself

**As** a user with a stale nexus,
**I want** to update the nexus from the CLI without remembering the curl-pipe URL,
**so that** I can pick up new roster entries and CLI features.

- **GIVEN** my nexus at `~/.eidolons/nexus` is behind the latest published tag
- **WHEN** I run `eidolons upgrade --system` (was `--nexus` pre-revision; see §11)
- **THEN** the command performs the equivalent of a `git fetch + reset --hard` to the latest tag in the nexus's git repo (the same primitive `cli/install.sh` already uses)
- **AND** prints a clear "nexus updated to vX.Y.Z" line
- **AND** exits 0
- **AND** prints a hint to re-run `eidolons upgrade --check` to see freshly visible member versions
- **AND** does *not* automatically chain member upgrades (the user re-runs `eidolons upgrade` themselves — see §4.1)

### Story U5 — Selective member upgrade

**As** a developer,
**I want** to upgrade exactly one member rather than the whole project,
**so that** I can stage upgrades cautiously.

- **GIVEN** multiple members have upgrades available
- **WHEN** I run `eidolons upgrade spectra` (positional arg matches a roster name)
- **THEN** only `spectra` is upgraded
- **AND** other members in `eidolons.lock` remain on their pinned versions
- **AND** the lockfile is rewritten preserving the other members' resolved entries verbatim

### Story U6 — Offline / network-degraded run

**As** a user on a flight or behind a proxy,
**I want** the command to fail gracefully with actionable text rather than hang or crash,
**so that** I know what's wrong.

- **GIVEN** network is unavailable (DNS failure, proxy block, or rate limit)
- **WHEN** I run `eidolons upgrade --check`
- **THEN** the command attempts the network probe with a hard 10-second timeout
- **AND** on failure prints `WARN: nexus upstream unreachable — showing local roster only`
- **AND** continues to render the *member* check using only on-disk data (lockfile vs. local `roster/index.yaml`)
- **AND** exits 0 (degraded but useful)
- **WHEN** I instead run `eidolons upgrade` (mutating) under the same conditions
- **THEN** any per-member fetch failure is non-fatal and the run continues to the next member (matches `sync.sh`'s `|| { warn ...; continue; }` pattern)
- **AND** the final exit code is 1 if any member upgrade failed, 0 if all succeeded or no upgrades were available

### Story U7 — JSON output for scripting

**As** a CI pipeline or scripted tool,
**I want** machine-readable output,
**so that** I can gate releases on "everything is current".

- **GIVEN** any project state
- **WHEN** I run `eidolons upgrade --check --json`
- **THEN** stdout contains a single JSON object conforming to the schema in §6.4 (one top-level object with `nexus`, `members`, `summary` keys)
- **AND** all human-readable banner/log output continues to go to stderr (matches `lib.sh` invariant)
- **AND** the JSON is parseable in one `jq .` invocation
- **AND** exit code reflects: 0 when fully up-to-date, 0 when upgrades are *available* (informational), 2 only on argument error, 1 only on hard failure (e.g. unparseable lockfile)

---

## 3. Boundary with existing commands

### 3.1 Relationship to `eidolons sync`

`sync` already does the install primitive. **`upgrade` is not a replacement for `sync`** — it's a *driver* of `sync`-like behavior gated on a version diff.

| | `sync` | `upgrade` |
|---|---|---|
| Reads `eidolons.yaml` | Yes | Yes |
| Reads `eidolons.lock` | Writes only | Reads to compute diff, writes after |
| Compares lock vs roster | No (uses manifest's constraint as-is, strips `^`/`~`/`=`) | Yes — this is its raison d'être |
| Invalidates cache | No | Yes (per-member, only for entries actually being upgraded) |
| Fetches new versions | Yes (whatever the constraint resolves to via `fetch_eidolon`) | Yes (the new resolved version) |
| Runs per-Eidolon `install.sh` | Always, for every manifest member | Only for members with `upgrade available` |
| Idempotent on repeat run | Yes (CI-enforced) | Yes (after first run, all members `up-to-date`, no `install.sh` runs) |
| Touches `~/.eidolons/nexus` | No | Yes, with `--system` (was `--nexus`; §11) |

**Implementation shortcut:** the per-member execution path inside `upgrade` is essentially `sync`'s per-member loop with a pre-filter. The implementation should extract the per-member install body from `sync.sh` into a shared function in `lib.sh` (provisional name: `install_member <name> <version> <hosts_csv> <effective_shared_dispatch>`) and call it from both. (See §7 implementation hints.)

### 3.2 Relationship to `eidolons doctor`

`doctor` answers "is what I have on disk healthy?". `upgrade --check` answers "is what I have on disk current?". Distinct axes; both can be green or red independently. No overlap in implementation.

### 3.3 Relationship to `cli/install.sh` (curl-pipe bootstrap)

`install.sh` is the *external* bootstrap (no nexus on disk yet). `upgrade --system` is the *internal* refresh (nexus already on disk; was `--nexus` pre-revision, see §11). They share the `git init + fetch + reset --hard FETCH_HEAD` primitive — `upgrade --system` should use that same primitive against `$NEXUS` rather than re-cloning. This is critical because:

- `git clone --branch` rejects raw SHAs; `init + fetch + checkout FETCH_HEAD` accepts everything (commit `116df8f` lineage).
- It avoids re-downloading the entire repo for a small delta.
- It mirrors the proven idempotent path that CI already exercises.

---

## 4. Detailed behavior (decision-by-decision)

> **Note:** §4.1 and §4.3 below are SUPERSEDED by §11. The text is preserved for traceability of
> the original reasoning. APIVR should treat §11.4 as the authoritative flag matrix.

Each subsection below resolves one of the 10 explicit decision points raised by the requester. The recommendation is the *adopted* behavior. Alternatives are listed for traceability.

### 4.1 Decision: Scope (nexus / members / both) — *SUPERSEDED by §11*

**Adopted (pre-revision):**
- **Bare `eidolons upgrade`** = upgrade members only. Project-scoped. Does nothing to the nexus. Requires `eidolons.yaml`.
- **`eidolons upgrade --nexus`** = upgrade the nexus only. No project required. Does nothing to members.
- **`eidolons upgrade --all`** = nexus first, then members, in one invocation. Implementation does the nexus self-update via `git fetch + reset --hard` (no re-exec necessary since the bash dispatcher's `exec` semantics already forward the rest of the command), then proceeds to the member loop using the *new* roster on disk.
- **`eidolons upgrade --check`** = inspects both surfaces (nexus + members) and prints a unified report. No flags needed. If no `eidolons.yaml`, the members section is omitted with a one-line note.

**Why bare = members-only:**
1. The dominant user mental model is "I'm working in a project, I want to upgrade the project's deps." Most package managers default this way (`bundle update`, `npm update`).
2. Nexus upgrades change behavior globally and may surface new members, new presets, schema changes — they deserve a deliberate flag.
3. Symmetry with `sync` (also project-scoped).

**Alternatives considered:**
- *Bare = both.* Rejected: makes the common case (member tweaks) carry a heavier blast radius than the user intended.
- *Require explicit `--members` flag.* Rejected: too verbose for the dominant case.

> **Post-revision:** the substantive call ("bare = project/members") is preserved. Only the
> *flag spelling* changes — `--nexus` becomes `--system` and gains an explicit `--project`
> counterpart for symmetry. See §11.

### 4.2 Decision: Version discovery

**Adopted:**

| Surface | Source of truth | Probe |
|---|---|---|
| Nexus latest | `git ls-remote --tags --refs https://github.com/Rynaro/eidolons` | Sort tags by `sort -V`, take the highest `vN.M.P` matching `^v[0-9]+\.[0-9]+\.[0-9]+$`. Compare to `git -C "$NEXUS" describe --tags --exact-match HEAD` (falls back to short SHA when not on a tag). |
| Member latest | Local `roster/index.yaml` `versions.latest` (after `--system` upgrade if requested) | No network. The roster *is* the registry; if you want fresher member info, upgrade the nexus first. This is documented behavior, not a bug. |
| Member installed | `eidolons.lock` `members[].version` | No network. |

**Rationale for not hitting GitHub releases API:**
- No auth handling, no rate-limit handling required.
- `git ls-remote` is the same primitive `lib.sh` already uses (`resolve_eiis_tag`) — zero new dependencies.
- Works behind a corporate git proxy without separate HTTPS/API config.
- No JSON parsing layer.

**Why not probe member upstreams directly via `git ls-remote` per-Eidolon:** doing so would (a) take O(N) network calls instead of one, (b) duplicate the registry's role, (c) bypass the human curation gate (a tag exists in `Rynaro/SPECTRA` but the nexus maintainer hasn't blessed it in the roster yet — that's a feature, not a bug). The roster-bump-after-upstream-tag flow described in `CLAUDE.md` §"Roster changes" is the canonical path; `upgrade` follows it.

### 4.3 Decision: Selectivity — *SUPERSEDED by §11*

**Adopted flag set (pre-revision):**

```
eidolons upgrade [TARGET]                  # default: all members
eidolons upgrade --nexus                   # nexus only
eidolons upgrade --all                     # nexus + members
eidolons upgrade <member>                  # single member (positional)
eidolons upgrade <m1>,<m2>                 # comma-separated list
eidolons upgrade --check [TARGET]          # read-only, same TARGET semantics
eidolons upgrade --json                    # JSON output (combinable with --check)
eidolons upgrade --yes / -y                # skip confirmation prompt
eidolons upgrade --non-interactive         # fail on prompt; requires --yes or --check
eidolons upgrade --dry-run                 # show what would happen, don't fetch/install
eidolons upgrade -h / --help
```

- `--nexus` and a positional `<member>` are mutually exclusive (the command refuses with exit 2).
- `--all` and a positional `<member>` are mutually exclusive (exit 2).
- Positional arg must match either a roster name OR a roster alias (the existing `roster_get` already handles aliases — reuse it).
- Unknown member name exits 2 with the same "Try: eidolons list" hint already used in `roster_get`.

> **Post-revision:** see §11.4 for the authoritative flag set. The positional/CSV/`--json`/`--yes`/
> `--non-interactive`/`--dry-run`/`--check`/`--all` semantics carry over unchanged. `--nexus` is
> renamed to `--system`; `--project` is introduced as the explicit symmetric form of "default".

### 4.4 Decision: Pin policy

**Adopted:** respect `eidolons.yaml` constraints by default; surface but do not auto-jump pin boundaries.

**Definitions:**
- `versions.latest` (roster) = the absolute latest the maintainer has blessed.
- `versions.pins.stable` (roster) = the latest *recommended* version. Today these are equal in every roster entry, but the schema allows them to diverge (e.g. `latest=4.3.0-rc1`, `stable=4.2.10`). `upgrade` uses `latest` because v1.0 of the roster keeps them equal in practice; if/when they diverge, an additional `--prerelease` flag is the future extension point. (Documented as future work, not in scope.)
- The user's `eidolons.yaml` member version is a constraint string: `^1.0.0`, `~1.0.0`, `=1.0.0`, or a bare `1.0.0`. `sync.sh` currently strips `^`/`~`/`=` and uses the bare version as a cache key only — it does *not* perform constraint resolution. We preserve this conservatism.

**Rules:**

| Constraint | Latest | Behavior |
|---|---|---|
| `^1.0.0` | `1.0.5` | upgrade → `1.0.5` (caret allows patch + minor within major) |
| `^1.0.0` | `1.2.0` | upgrade → `1.2.0` (caret allows minor) |
| `^1.0.0` | `2.0.0` | **`pinned-out`**: don't upgrade. Print: "spectra: 2.0.0 available but constraint `^1.0.0` excludes it. Edit `eidolons.yaml` to bump the constraint." Exit 0. |
| `~1.0.0` | `1.0.5` | upgrade → `1.0.5` (tilde allows patch only) |
| `~1.0.0` | `1.1.0` | **`pinned-out`** |
| `=1.0.0` or `1.0.0` | anything | **`pinned-out`** unless equal |

**Caret/tilde semantics** are the standard SemVer ones (npm/cargo style):
- `^X.Y.Z` allows `>=X.Y.Z, <(X+1).0.0` (or `<0.(Y+1).0` if `X==0`).
- `~X.Y.Z` allows `>=X.Y.Z, <X.(Y+1).0`.

Implementation detail: the comparison is bash-implementable in pure `sort -V` + `awk`. No external semver library. (See §7.)

**Why not auto-edit `eidolons.yaml`:** the manifest is a user-owned, version-controlled file. Silent rewrites violate the "no code execution from `eidolons.yaml`" spirit (CLAUDE.md). The `pinned-out` status is the *signal* that asks the user to perform the edit explicitly.

### 4.5 Decision: Network failure handling

**Adopted:**

| Phase | Failure mode | Behavior |
|---|---|---|
| `--check` nexus probe | DNS / timeout / non-zero exit | Hard 10-second timeout (`timeout 10 git ls-remote ...`). On failure: print `warn` to stderr, mark nexus row as `unknown (offline)`, continue. Exit 0. |
| `--check` member rows | n/a (purely local) | Always works — no network. |
| `upgrade --system` fetch | Any | Fail loudly. Exit 1. The nexus state is untouched (the `init + fetch + reset` flow is atomic on success; on fetch failure we never reach `reset`). |
| `upgrade <member>` fetch | Any | Per-member: warn + continue (same as `sync.sh:209`). Final exit code = 1 if any member failed, 0 otherwise. |

`timeout` is BSD/GNU-portable but the macOS `timeout` lives in coreutils only when Homebrew installed it. The portable trick used elsewhere in eidolons-flavor scripts: `( command & PID=$!; ( sleep 10 && kill -9 $PID 2>/dev/null ) & TIMER=$!; wait $PID; kill $TIMER 2>/dev/null )` — the helper goes in `lib.sh` as `with_timeout SECONDS CMD ARGS...`. Bash 3.2 compatible; no `wait -n`.

### 4.6 Decision: Output format

**Adopted:**

**Human (default), `--check`:**
```
▸ Checking upgrades for project at /path/to/project

  NEXUS
    current:  v1.0.0  (commit a1b2c3d)
    latest:   v1.1.0  (Rynaro/eidolons)
    status:   upgrade available
    action:   eidolons upgrade --system

  MEMBERS                                                       (from eidolons.lock)
    NAME      INSTALLED   LATEST    CONSTRAINT     STATUS
    spectra   4.2.8       4.2.10    ^4.2.0         upgrade available
    apivr     3.0.3       3.0.5     ^3.0.0         upgrade available
    atlas     —           1.0.5     ^1.0.0         not-installed
    idg       1.1.5       1.1.5     ^1.1.0         up-to-date

  SUMMARY
    1 nexus upgrade available
    2 member upgrades available
    1 member declared but not installed (run: eidolons sync)
    Run `eidolons upgrade` to apply member upgrades.
```

**Human, mutating `eidolons upgrade`:** prints the same plan, then asks `Proceed? [Y/n]` (interactive) or proceeds directly (`--yes` / `--non-interactive --yes`). Per-member install output mirrors `sync.sh`'s style.

**JSON (`--json`):** structure documented in §6.4. Banner/log lines stay on stderr; only the JSON object goes to stdout. This matches the existing `eidolons list --json` pattern.

### 4.7 Decision: Rollback / partial-failure recovery

**Adopted: fail-fast at the *member* boundary, no rollback.**

The atomic unit is one member's `install.sh` invocation. If member B fails after member A succeeded, A's installation stays applied and the lockfile records A's new version + B's old version. The summary at the end lists which members succeeded and which failed; the recovery instruction is "fix the underlying issue and re-run `eidolons upgrade <failed-member>`".

**Why no automatic rollback:**
- Rollback would require snapshotting `.eidolons/<name>/` and host-wiring files (`.claude/agents/<name>.md`, `.cursor/rules/<name>.mdc`, `AGENTS.md` marker block, etc.) before each install — a non-trivial state machine that has never existed in the codebase.
- The `sync.sh` `|| { warn ...; continue; }` pattern already establishes "best-effort, report at end" as the project convention.
- Per-Eidolon `install.sh` is supposed to be idempotent (EIIS contract); re-running fixes most transient failures.
- Reverting member B by checking out the old git tag and re-running its old `install.sh` requires us to have kept the old cache around — which we explicitly invalidate to force fresh fetches.

**Mitigation:** the summary output documents the recovery path. The lockfile records *exactly* what's on disk after the run, never a desired-but-failed state.

### 4.8 Decision: Bash 3.2 compatibility

Already a project invariant. Concrete forbidden constructs in this implementation:
- No `declare -A` (no associative arrays). Member-status tracking uses parallel indexed arrays or `name|status` newline-delimited strings.
- No `${var,,}` / `${var^^}`. Use `tr '[:upper:]' '[:lower:]'`.
- No `readarray` / `mapfile`. Use `while IFS= read -r line; do ... done <<< "$multi"` or process substitution.
- No `&>>`. Use `>> file 2>&1`.
- No `wait -n`. The `with_timeout` helper uses `kill -9` + `wait $PID`.

CI catches regressions on `macos-latest` (already in the matrix).

### 4.9 Decision: Idempotency

**Contract:** `eidolons upgrade` run twice with no roster change between runs MUST:
- On run 2, find every member already at `latest` (or `pinned-out`), print "all members up-to-date", skip every per-Eidolon `install.sh`, exit 0.
- Not re-write `eidolons.lock` if the resolved versions and commits match. (Re-writing identical content is acceptable but discouraged because the `generated_at` timestamp would change and create spurious VCS diffs. **Rule:** only rewrite the lockfile if at least one member's resolved version changed.)
- Not invalidate caches that wouldn't have been invalidated.

`upgrade --check` run twice produces byte-identical stdout (modulo terminal width) for the same network condition.

CI gate: a new bats test `upgrade: idempotency on second run` asserts stdout/stderr from a second invocation contains "all members up-to-date" and the lockfile mtime is unchanged.

### 4.10 Decision: Interaction with `sync`

Already covered in §3.1. The implementation extracts a shared `install_member` helper into `lib.sh`; both `sync.sh` and `upgrade.sh` call it. This is the only `lib.sh` change with cross-command impact and must be reviewed carefully — the existing sync test suite is the regression guard.

---

## 5. Validation gates

A change ships only when **every** gate below is green.

### 5.1 Lint

- [ ] `find cli -name '*.sh' -type f -print0 | xargs -0 shellcheck -x -S error` passes
- [ ] `shellcheck -x -S error cli/eidolons` passes
- [ ] No new shellcheck warnings introduced (run `-S warning` and diff against `main`)

### 5.2 Schema / structural

- [ ] `jq empty schemas/*.json` passes (no schema changes expected, but the gate stays)
- [ ] `yq eval '.' roster/index.yaml` parses (no roster changes expected)

### 5.3 Bats — `cli/tests/upgrade.bats` (new file)

Every test name in §6 must exist and pass on both `ubuntu-latest` and `macos-latest` runners.

### 5.4 Bats — existing suites must not regress

- [ ] `bats cli/tests/sync.bats` (if it exists; otherwise the sync paths exercised via `init.bats`) still passes — the `install_member` extraction is the risk surface.
- [ ] `bats cli/tests/init.bats` — same reason.
- [ ] `bats cli/tests/doctor.bats` (if exists) — no expected impact, regression check.
- [ ] Full `bats cli/tests/` clean.

### 5.5 Idempotency CI gate

- [ ] New CI step in `.github/workflows/ci.yml` (`cli-tests` job): after seeding a project and running `eidolons upgrade`, run it again and assert stdout contains `up-to-date` and the lockfile mtime did not advance. Modeled on the existing "Second install run is idempotent" step in `install-e2e`.

### 5.6 Bash 3.2 compatibility

- [ ] `cli-tests` job on `macos-latest` exercises every new code path. (Passes by default if the bats tests run on macOS — that's the project's standing 3.2 gate.)

### 5.7 Documentation

- [ ] `docs/cli-reference.md` updated with the new command surface.
- [ ] `cli/eidolons` `usage()` text updated to document `--check`, `--system`, `--project`, `--all`, `--json`, `--yes`, `--dry-run` (the bare entry already exists). (Note: §11 renamed `--nexus` → `--system` and added `--project`.)
- [ ] `CHANGELOG.md` entry for the v1.1 nexus release.
- [ ] No changes required to `docs/architecture.md` (the four-layer model is unchanged).

### 5.8 Manual smoke (release checklist, not CI)

- [ ] Run `eidolons upgrade --check` against this very repo's `eidolons.lock` and visually verify the diff.
- [ ] Run `eidolons upgrade --system` against a stale nexus checkout and verify the `git fetch + reset` lands on the latest tag.
- [ ] Run `eidolons upgrade` interactively and verify the confirmation prompt renders.
- [ ] Disconnect from network, run `eidolons upgrade --check`, verify the offline degradation path.

---

## 6. Test plan

> **Note:** §11.7 lists deltas (renames, additions, drops) APIVR must apply to this section.
> The numbered tables below remain the original test inventory for traceability.

All bats tests live in `cli/tests/upgrade.bats` (new file), using the existing `helpers.bash` fixtures and the `setup_fake_git` pattern from `init.bats` to keep `git ls-remote` and `git clone` from hitting the network.

### 6.1 Read-only path (`--check`)

| # | Test name | Setup | Assertion |
|---|---|---|---|
| T1 | `upgrade --check: no eidolons.yaml prints nexus-only report` | empty cwd | exit 0, output contains `NEXUS`, no `MEMBERS` table, no error |
| T2 | `upgrade --check: with manifest + lock, all current, prints up-to-date` | seed_manifest, seed_lock, set roster latest = lock version | exit 0, output contains `up-to-date` for every member, `0 member upgrades available` |
| T3 | `upgrade --check: detects member upgrade available` | manifest pins `^1.0.0`, lock has `1.0.0`, roster latest `1.0.5` | exit 0, output contains `upgrade available`, `1.0.0`, `1.0.5` |
| T4 | `upgrade --check: detects pinned-out member` | manifest pins `^1.0.0`, roster latest `2.0.0` | exit 0, output contains `pinned-out`, action hint mentions editing `eidolons.yaml` |
| T5 | `upgrade --check: detects not-installed member` | manifest declares atlas, lock has no atlas entry | exit 0, output row for atlas with `INSTALLED: —`, status `not-installed` |
| T6 | `upgrade --check: stale nexus produces upgrade-available row` | mock `git ls-remote` fake to return higher tag than `git -C $NEXUS describe` | exit 0, NEXUS section shows `upgrade available` and the curl-pipe action hint |
| T7 | `upgrade --check: --json emits valid object on stdout, banner on stderr` | seed_manifest + lock | `echo "$output" \| jq -e '.nexus and .members and .summary'` succeeds; stderr contains `▸` glyph |
| T8 | `upgrade --check: offline nexus probe degrades, doesn't fail` | shadow PATH with a fake `git` that fails on `ls-remote` | exit 0, stderr contains `unreachable`, members section still rendered |
| T9 | `upgrade --check: respects ^/~/= constraint operators` | parameterized: each operator with a known boundary case | each row's STATUS matches the truth table in §4.4 |
| T10 | `upgrade --check: idempotent (run twice, byte-identical stdout)` | seed manifest + lock | `out1 == out2` |
| T11 | `upgrade --check: --json output matches schema in spec.yaml` | seed manifest + lock | run + pipe through a schema check helper (jq + the JSON schema in spec.yaml `output_schemas.check_json`) |
| T12 | `upgrade --check: aliases resolve` | seed manifest with `idg`, then `eidolons upgrade --check scribe` | row for `idg` (the canonical name), warning about alias usage |

### 6.2 Mutating path (member upgrades)

| # | Test name | Setup | Assertion |
|---|---|---|---|
| T13 | `upgrade: --non-interactive --yes runs without prompting` | manifest, lock with stale member, fake-git that returns success on clone | exit 0, no read prompt invoked |
| T14 | `upgrade: --non-interactive without --yes fails fast` | same | exit 2, stderr "use --yes" or similar |
| T15 | `upgrade: re-runs install.sh only for upgrade-available members` | three members, two stale one current | install.sh invoked exactly twice |
| T16 | `upgrade: invalidates cache for upgraded members only` | pre-create cache dirs for old + current | only old version's cache dir removed; current member's cache untouched |
| T17 | `upgrade: writes new lockfile with new resolved versions` | fake clone returns commit SHA `deadbeef` | `eidolons.lock` contains `deadbeef` for upgraded members |
| T18 | `upgrade: lockfile mtime unchanged when no upgrades occur` | all current | `stat -c %Y eidolons.lock` (or BSD equivalent) unchanged after run |
| T19 | `upgrade <member>: positional arg upgrades only that member` | three stale members | only one install.sh invoked, lockfile preserves other two entries verbatim |
| T20 | `upgrade <m1>,<m2>: comma-separated list` | three stale | exactly two install.shs run |
| T21 | `upgrade unknown-member: exits 2 with hint` | none | exit 2, stderr "not found in roster" |
| T22 | `upgrade: per-member install failure continues, reports at end, exits 1` | fake-git fails clone on second member only | first member upgraded, second errored, exit 1, summary lists the failure |
| T23 | `upgrade: idempotent on repeat run` | run upgrade once on stale manifest, then run again | second run prints `up-to-date`, no install.sh runs, lockfile mtime stable |
| T24 | `upgrade: pinned-out member is skipped silently in mutating path` | constraint `^1.0.0`, latest `2.0.0` | exit 0, summary mentions pinned-out, no install.sh invoked for that member |
| T25 | `upgrade: --dry-run prints plan without fetching` | stale manifest | output contains `[dry-run]`, fake-git's clone never invoked |

### 6.3 Nexus path

| # | Test name | Setup | Assertion |
|---|---|---|---|
| T26 | `upgrade --system: stale nexus is fetched + reset` | mock `git -C $NEXUS rev-parse HEAD` to return old SHA, mock `git ls-remote` to return new tag | `git fetch` invoked once on `$NEXUS`, then `git reset --hard FETCH_HEAD`, exit 0 |
| T27 | `upgrade --system: current nexus is no-op` | nexus HEAD == latest tag | exit 0, output contains `up-to-date`, no `git fetch` invoked |
| T28 | `upgrade --system: fetch failure exits 1` | fake-git `fetch` returns 128 | exit 1, nexus state unchanged (no `reset` invoked) |
| T29 | `upgrade --system: with positional member name fails with mutex error` | `eidolons upgrade --system spectra` | exit 2, stderr "mutually exclusive" |
| T30 | `upgrade --all: nexus first then members` | both stale | order asserted via fake-git invocation log |
| T31 | `upgrade --all: aborts member phase if nexus fails` | nexus fetch fails | exit 1, no member install.sh runs |

### 6.4 JSON schema

The JSON object emitted by `--check --json` and `upgrade --json` (post-run summary) MUST validate against the schema documented in `spec.yaml` under `output_schemas.check_json`. T11 enforces this.

---

## 7. Implementation hints (file-level pointers, no code)

### 7.1 Files to add

- **`cli/src/upgrade.sh`** — replace the v1.0 stub. Sources `lib.sh` and `ui/prompt.sh` (for `ui_confirm`). Argument parser modeled on `sync.sh`. Top-level dispatch:
  1. Parse flags (`--check`, `--system`, `--project`, `--all`, `--json`, `--yes`, `--non-interactive`, `--dry-run`, positional member list)
  2. Validate flag mutex (§11.5)
  3. Branch: nexus check → member check → render report → (if mutating) prompt → (if confirmed) per-member loop → write lockfile
- **`cli/tests/upgrade.bats`** — every test from §6, with renames per §11.7.
- **`docs/specs/eidolons-upgrade/spec.md`** — this file.
- **`docs/specs/eidolons-upgrade/spec.yaml`** — machine-readable companion.

### 7.2 Files to edit

- **`cli/src/lib.sh`** — add the following helpers. Each goes in a labeled section block, matching the existing house style:
  - `with_timeout SECONDS CMD ARGS...` — Bash 3.2-portable timeout wrapper (§4.5).
  - `nexus_current_tag` — echoes the exact-match tag at `$NEXUS` HEAD, or short SHA on detached non-tag.
  - `nexus_latest_tag` — `git ls-remote` against `Rynaro/eidolons`, sort-V, tail -1; wrapped in `with_timeout 10`.
  - `nexus_self_update` — `git -C $NEXUS fetch + reset --hard FETCH_HEAD` against the resolved latest tag. Returns 0/1.
  - `semver_satisfies CONSTRAINT VERSION` — pure-bash predicate. Handles `^X.Y.Z`, `~X.Y.Z`, `=X.Y.Z`, bare `X.Y.Z`. Implementation: parse out the operator, then use `sort -V` with awk on a 2-line input to compare. No external semver lib.
  - `semver_lt A B` — boolean helper used by `semver_satisfies`.
  - `lock_member_version NAME` — reads `eidolons.lock` via `yaml_to_json`, returns the resolved version for the named member or empty string if absent.
  - `install_member NAME VERSION HOSTS_CSV EFFECTIVE_SHARED_DISPATCH NON_INTERACTIVE` — the body of the per-member install loop currently inline at `sync.sh:148-279`. Returns 0 on success, 1 on failure. `sync.sh` and `upgrade.sh` both call this. **Risk surface:** refactor must preserve byte-for-byte log output that the existing sync tests assert on. Strategy: extract first, get all existing tests green, only then add the upgrade-specific call sites.
- **`cli/eidolons`** — no change needed; the dispatcher already routes `upgrade` to `cli/src/upgrade.sh`.
- **`docs/cli-reference.md`** — add `upgrade` section (apply §11.6 deltas if revising an already-shipped reference).
- **`CHANGELOG.md`** — `v1.1` entry under "Added".
- **`.github/workflows/ci.yml`** — append the idempotency smoke step in the `cli-tests` job (or in `install-e2e` if seeding a project there is cleaner; recommend `cli-tests` for locality with the bats suite).

### 7.3 Existing helpers to reuse (do not reimplement)

- `yaml_to_json`, `roster_get`, `roster_list_names`, `fetch_eidolon`, `eiis_check`, `manifest_exists`, `manifest_members` — all from `lib.sh`.
- `say`, `ok`, `info`, `warn`, `die` — logging (stderr-only invariant).
- `ui_confirm`, `ui_section_out`, `ui_section` — UI primitives from `cli/src/ui/`.

### 7.4 Test fixtures to extend

Add a `seed_lock_with_versions` helper in `helpers.bash` that takes member-version pairs as args:
```
seed_lock_with_versions atlas=1.0.0 spectra=4.2.8 apivr=3.0.3
```
This keeps each upgrade test concise and lets the test author dial in stale-vs-current scenarios cleanly.

Add a `mock_remote_tags` helper that writes a fake-git wrapper which returns a controlled `git ls-remote --tags` output, so tests don't depend on the real network or on the actual `Rynaro/eidolons` tag set.

### 7.5 Order of implementation (risk-first)

1. **Extract `install_member` from `sync.sh` to `lib.sh`.** All existing tests must stay green. Land as a separate PR; this is the highest-risk change.
2. **Add `semver_satisfies` + tests** (pure unit-ish bats around the helper). Independent of upgrade.sh.
3. **Add `nexus_*` helpers + tests.**
4. **Implement `upgrade --check` (read-only path).** All §6.1 tests pass.
5. **Implement `upgrade --system`.** §6.3 tests pass.
6. **Implement mutating `upgrade` (members).** §6.2 tests pass.
7. **Implement `--all`.** Final §6.3 tests pass.
8. **Wire idempotency CI gate, update docs, CHANGELOG.**

This sequencing ensures every step is independently mergeable and revertible.

---

## 8. Open questions / human decisions required

**NO HUMAN DECISIONS REQUIRED.**

Every decision point raised in the request has a recommendation in §4 (with §11 superseding §4.1
and §4.3) with stated rationale and stated alternatives. The remaining unknowns (e.g. exact
stdout column widths, the precise wording of action-hint strings) are implementation-detail
polish that doesn't affect the design and can be tuned in code review without re-spec'ing.

The one *future* extension explicitly deferred (a `--prerelease` flag for when `versions.pins.stable` and `versions.latest` diverge in the roster) is documented in §4.4 as future work and explicitly out of scope for v1.1. The roster currently ships `stable == latest` for every entry, so this divergence does not exist yet.

---

## 9. Appendix

### 9.1 Glossary

- **Nexus** — `~/.eidolons/nexus`, the local clone of `Rynaro/eidolons`. Owned by the user globally.
- **Member** — an Eidolon installed in a consumer project (declared in `eidolons.yaml`, resolved in `eidolons.lock`, materialized at `./.eidolons/<name>/`).
- **Roster** — `roster/index.yaml` inside the nexus. The registry of every available Eidolon.
- **Constraint** — the version expression in `eidolons.yaml` (`^X.Y.Z` etc.).
- **Resolved version** — the concrete `X.Y.Z` recorded in `eidolons.lock` after a sync or upgrade.
- **System scope** *(§11)* — the user-global state: `~/.eidolons/nexus` plus the registry it carries.
- **Project scope** *(§11)* — the cwd-local state: `eidolons.yaml`, `eidolons.lock`, `./.eidolons/<name>/`.

### 9.2 Cross-references

- `CLAUDE.md` — project invariants, especially "Idempotency", "Bash 3.2 compatibility", "No code execution from `eidolons.yaml`".
- `docs/architecture.md` §"Security model" — write-permission boundaries (the upgrade command writes to `$EIDOLONS_HOME` *and* cwd; per-Eidolon `install.sh` continues to write only to cwd).
- `cli/install.sh:130-149` — the `git init + fetch + reset --hard FETCH_HEAD` primitive that `upgrade --system` reuses.
- `cli/src/sync.sh:148-279` — the per-member install loop being extracted into `install_member`.
- `cli/src/lib.sh:179-190` — the `resolve_eiis_tag` precedent for `git ls-remote`-based version discovery.

---

## 11. Revision: scope-flag UX refinement (2026-04-26)

> **Status:** Adopted. **Supersedes** §4.1 and §4.3 on flag spelling.
> **Trigger:** post-implementation user review of the just-shipped (uncommitted) `upgrade.sh` flag set.
> **Scope of revision:** flag *names* and one mutex rule. The substantive scope decisions
> (bare = project, `--check` covers both surfaces, `--all` exists for combined runs, idempotency,
> pin policy, etc.) are unchanged.

### 11.1 Decision

**Proposal A wins, with a correction to its proposed default.** The command stays a single
`eidolons upgrade` with `--system` and `--project` as explicit, symmetric scope flags. The
**default (bare) invocation remains project-scoped**, *not* `--system` as the original Proposal A
sketch suggested.

In one sentence: `eidolons upgrade` defaults to project scope (members in cwd); `--system`
operates on the nexus binary; `--project` is the explicit form of the default; `--all` is the
combined run.

### 11.2 Rationale

**Why Proposal A over Proposal B (split commands):**

1. **`--check` is genuinely cross-scope.** A user asking "what's stale on this machine?" wants
   *both* surfaces in one read. Splitting into `upgrade-system --check` and `upgrade-project
   --check` forces the user to run two commands or maintain a third "status" command — strictly
   worse UX. With Proposal A, `eidolons upgrade --check` (no scope flag) inspects both, and
   `--check --system` / `--check --project` narrow on demand.
2. **Discoverability.** A new user types `eidolons upgrade --help` and sees the entire surface
   — both scopes, both check modes, all flags — on one page. Proposal B requires them to know
   `upgrade-system` exists before they can ask for help on it. (`eidolons --help` would list it,
   but commands tend to be discovered through verb intuition: "I want to upgrade" → `upgrade`.)
3. **Mutex rules are simpler with one command.** `--system` + positional-member is one error
   message, not a "wrong command" error in `upgrade-project` plus a separate "wrong flag" error
   in `upgrade-system`.
4. **Bash 3.2 parsing complexity is identical** between A and B — both are flat case statements
   over flags. No advantage to either.
5. **Symmetry with the rest of the CLI.** `init`, `sync`, `add`, `remove`, `doctor` are all
   single verbs that scope themselves by context; `roster` and `list` are single verbs that
   take flags to narrow scope. Proposal A matches that pattern. Proposal B would be the only
   verb that ships in two flavors (e.g. `upgrade-system` / `upgrade-project`), which is jarring.

**Why bare = project, not bare = system (the user's original Proposal A sketch):**

1. **Frequency.** Roster bumps land in `Rynaro/eidolons` ~weekly (the most common commit type
   per CLAUDE.md "Roster changes" — *fix(roster): publish <EIDOLON> vX.Y.Z*). Members upgrade
   far more often than the nexus's own version, which churns on CLI feature work — much rarer.
   The default should serve the common case.
2. **Mental coherence.** Every other project-verb (`sync`, `add`, `remove`, `doctor`) defaults
   to cwd scope. A user who has internalized "Eidolons commands act on this project unless I
   tell them otherwise" will be surprised if `upgrade` alone defaults to system scope.
3. **Blast radius.** Nexus upgrades change the registry globally — they may surface new members,
   new presets, schema-affecting changes. They deserve a deliberate, named flag (`--system`),
   not a default. Members upgrades only affect the current project and are easy to revert by
   editing `eidolons.yaml` and re-running `sync`.
4. **Prior art in the spec.** §4.1's adopted decision was already "bare = members". §11
   preserves that call; it only renames the *flags* used to deviate from the default.

### 11.3 What changes vs. the as-shipped (uncommitted) code

| Aspect | As-shipped (current `upgrade.sh`) | Revised (§11) |
|---|---|---|
| Bare `eidolons upgrade` | members in cwd | **unchanged** — members in cwd |
| Nexus-only mutating run | `--nexus` | **`--system`** |
| Members-only mutating run | (implicit default) | (still implicit) **OR `--project` for explicit equivalence** |
| Combined run | `--all` | **`--all`** (unchanged) |
| `--check` no scope flag | nexus + members | **unchanged** |
| `--check --system` | n/a | new — narrows to nexus only |
| `--check --project` | n/a | new — narrows to members only |
| Mutex: nexus + member positional | `--nexus` + `<member>` → exit 2 | **`--system` + `<member>` → exit 2** |
| Mutex: project + member positional | n/a | **`--project` + `<member>` → exit 2** is **NOT** an error; positional implies project scope, so they're consistent. (See §11.5.) |
| Mutex: `--system` + `--project` | n/a | **NOT an error** — equivalent to `--all`. (See §11.5.) |

### 11.4 Authoritative flag matrix (replaces §4.3)

```
eidolons upgrade [TARGET] [OPTIONS]            # default: project scope (members in cwd)
eidolons upgrade --check [SCOPE] [TARGET]      # read-only across requested scope
eidolons upgrade --system [OPTIONS]            # nexus-only mutating run
eidolons upgrade --project [TARGET] [OPTIONS]  # explicit project-scope mutating run
eidolons upgrade --all [OPTIONS]               # nexus first, then members
eidolons upgrade <member>                      # single member (project scope, no flag needed)
eidolons upgrade <m1>,<m2>                     # comma-separated list (project scope)
```

| Flag | Type | Description | Combinable with | Conflicts with |
|---|---|---|---|---|
| `--check` | bool | Read-only mode. Without further flags, inspects both scopes. | `--system`, `--project`, `--json`, `[TARGET]` | `--yes`, `--dry-run` (no-op together) |
| `--system` | bool | Operate on the nexus at `~/.eidolons/nexus`. | `--check`, `--json` | `[TARGET]` (positional member) |
| `--project` | bool | Operate on cwd members. Equivalent to default when given alone; useful for explicit symmetry and for narrowing `--check`. | `--check`, `[TARGET]`, `--json`, `--yes`, `--dry-run`, `--non-interactive` | none |
| `--all` | bool | Nexus first (must succeed), then members. Equivalent to `--system --project` for mutating runs. | `--yes`, `--dry-run`, `--non-interactive` | `[TARGET]` |
| `[TARGET]` | string/CSV | Member name or comma-separated list. Implies project scope. | `--check`, `--project`, mutating flags | `--system`, `--all` |
| `--json` | bool | JSON output on stdout (banner stays on stderr). | `--check` | — |
| `--yes` / `-y` | bool | Skip the confirmation prompt. | mutating flags | `--check` (no-op) |
| `--non-interactive` | bool | Fail on any prompt. Mutating runs require `--yes`. | mutating flags | — |
| `--dry-run` | bool | Show plan without fetching or running per-Eidolon `install.sh`. | mutating flags | — |
| `-h`, `--help` | bool | Print usage. | — | all others |

### 11.5 Mutex / equivalence rules

1. `--system` + positional `<member>` → **exit 2**, message: "`--system` operates on the nexus
   only; member arguments belong to project scope. Drop one or use `--all`."
2. `--all` + positional `<member>` → **exit 2**, message: "`--all` upgrades every member;
   drop the positional argument or use `<member>` without `--all`."
3. `--system` + `--project` → **NOT an error**. Treated as equivalent to `--all`. The user
   gets what they asked for (both scopes); we don't punish them for typing it out long-form.
   Implementation note: detect this at parse time and set the internal `ALL=true` flag.
4. `--project` + positional `<member>` → **NOT an error**. `--project` is documentation /
   explicitness; the positional is more specific and stays authoritative.
5. `--check` ignores `--yes` / `--non-interactive` / `--dry-run` (no prompts to skip, no
   mutations to dry-run). It does **not** error on them — silently no-ops, matching how
   `eidolons sync` treats redundant flags.

### 11.6 Backwards compatibility for `--nexus` (decision)

`--nexus` and `--all` were added in the as-shipped (uncommitted) implementation but **never
released**. There is no published binary that documents `--nexus`. Therefore:

- **`--nexus`: drop entirely.** No alias, no deprecation warning. The flag never reached users;
  carrying alias debt for an unreleased name is pure overhead. The rename lands in the same PR
  as the original feature ship — users only ever see `--system`.
- **`--all`: keep unchanged.** It's a useful shorthand, semantically clear, and orthogonal to
  the `--system`/`--project` axis. No reason to drop it.

**If a user has scripted `eidolons upgrade --nexus` against a local checkout pre-merge:** the
command will exit 2 with "Unknown option: --nexus" and the standard help hint will list
`--system`. Acceptable migration cost given zero published surface area.

### 11.7 Test plan delta (rename / add / drop)

> APIVR: apply these literal renames to `cli/tests/upgrade.bats`. Test IDs (T1–T31) stay stable
> for traceability; only the test *names* and the asserted CLI strings change.

**Renames (existing tests, change name + assertions referencing `--nexus` to `--system`):**

| ID | Old test name | New test name |
|---|---|---|
| T26 | `upgrade --nexus: stale nexus is fetched + reset` | `upgrade --system: stale nexus is fetched + reset` |
| T27 | `upgrade --nexus: current nexus is no-op` | `upgrade --system: current nexus is no-op` |
| T28 | `upgrade --nexus: fetch failure exits 1` | `upgrade --system: fetch failure exits 1` |
| T29 | `upgrade --nexus: with positional member name fails with mutex error` | `upgrade --system: with positional member name fails with mutex error` |

For each renamed test, also replace the literal flag in the `run` invocation
(`eidolons upgrade --nexus ...` → `eidolons upgrade --system ...`).

**Additions (new tests required by §11; pick test IDs T32–T36):**

| ID | New test name | Setup | Assertion |
|---|---|---|---|
| T32 | `upgrade --project: explicit project scope behaves like bare upgrade` | manifest + lock with one stale member | exit 0, exactly one install.sh invoked, lockfile updated; output identical to bare `eidolons upgrade --non-interactive --yes` modulo banner phrasing |
| T33 | `upgrade --system --project: equivalent to --all` | both nexus and a member stale | exit 0, fetch on nexus invoked, then install on member; equivalent invocation log to a `--all` run |
| T34 | `upgrade --check --system: narrows report to nexus row only` | manifest + lock present | exit 0, output contains `NEXUS`, does NOT contain `MEMBERS` table |
| T35 | `upgrade --check --project: narrows report to members only` | manifest + lock; nexus stale | exit 0, output contains `MEMBERS`, does NOT contain `NEXUS` row |
| T36 | `upgrade --nexus: rejected as unknown flag (post-rename)` | none | exit 2, stderr contains `Unknown option: --nexus` (no alias accepted) |

**Drops:** none. Every existing test (T1–T31) survives the revision; only the four named in
the rename table need their literal text changed.

**Help-text test update:** the existing `upgrade -h: help prints usage` test continues to pass
unchanged in shape, but its expected substrings should be updated to assert presence of
`--system` and `--project` (and **absence** of `--nexus`) in the printed usage.

### 11.8 Code delta (exact list for APIVR)

**`cli/src/upgrade.sh`:**

1. Variable rename: `NEXUS_ONLY` → `SYSTEM_ONLY` throughout (3 declarations + ~6 uses).
2. Add new variable: `PROJECT_ONLY=false` (parallel to `SYSTEM_ONLY`).
3. Argparse case: replace `--nexus) NEXUS_ONLY=true; shift ;;` with `--system) SYSTEM_ONLY=true; shift ;;`.
4. Argparse case: add `--project) PROJECT_ONLY=true; shift ;;`.
5. Mutex block (currently lines 84–95): rename messages and add new rules per §11.5:
   - `--system` + positional → exit 2 (renamed from `--nexus`).
   - `--all` + positional → unchanged.
   - `--all` + `--system` → unchanged (still mutex; `--all` already implies system).
   - `--system` + `--project` → set `ALL=true` (degenerate equivalence; not an error).
   - `--project` + positional → no-op, fine.
6. Phase 0 dispatch (currently `if [[ "$NEXUS_ONLY" == true ]]`): rename predicate to `SYSTEM_ONLY`.
7. `--check` rendering: branch on `SYSTEM_ONLY` and `PROJECT_ONLY` to suppress the opposite
   section. Currently `--check` always renders both; add a narrow path:
   - if `SYSTEM_ONLY` && `CHECK`: render only the NEXUS block, skip the MEMBERS block.
   - if `PROJECT_ONLY` && `CHECK`: render only the MEMBERS block, skip the NEXUS block.
   - if neither: current behavior (both blocks).
8. Usage text (`usage()` heredoc): update to match the §11.4 matrix. Replace `--nexus` line
   with `--system`. Add `--project` line. Update example invocations.
9. The `action:` hint line in the human report (currently shows
   `eidolons upgrade --nexus`): replace with `eidolons upgrade --system`.

**`cli/tests/upgrade.bats`:**

1. Rename T26–T29 per §11.7 (test names + invocation strings).
2. Append T32–T36 per §11.7.
3. Update help-test assertions to check for `--system` and `--project`.

**`docs/cli-reference.md`:**

1. The upgrade synopsis block (currently lines 130–135): replace `--nexus` with `--system`,
   add `--project` line, keep `--all`.
2. The flag table (currently lines 137–146): replace the `--nexus` row with `--system`. Insert
   a new row for `--project` immediately above `--all`.
3. The "Network failure" note: change `--nexus` reference to `--system`.

**`cli/src/sync.sh` and other commands:** no changes. The rename is local to `upgrade`.

**`CHANGELOG.md`:** v1.1 entry should list the renamed/added flags as the public surface.
Do not document `--nexus` as ever having existed; it didn't ship.

### 11.9 Files-touched summary (revision-only delta)

```
edit:
  - cli/src/upgrade.sh         # variable + flag rename, --project flag, --check narrowing
  - cli/tests/upgrade.bats     # rename T26–T29, add T32–T36, update help-test
  - docs/cli-reference.md      # synopsis + flag table updates
  - docs/specs/eidolons-upgrade/spec.md   # this file (revision §11)
  - docs/specs/eidolons-upgrade/spec.yaml # flags schema, test_plan, decisions

unchanged from original spec scope:
  - cli/src/lib.sh             # helpers list unchanged
  - cli/src/sync.sh            # untouched
  - .github/workflows/ci.yml   # idempotency gate unchanged
  - schemas/, roster/index.yaml
```

### 11.10 Result

**NO HUMAN DECISIONS REQUIRED.** Every sub-question raised in the user's refinement request
has a concrete answer above with stated rationale. The chosen design preserves all substantive
decisions from the original spec (bare = project, `--all` for combined runs, fail-fast at
member boundary, idempotency contract, pin policy, JSON schema) and only refines the *scope-flag
spelling* on the surface most exposed to users.
