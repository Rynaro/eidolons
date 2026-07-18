# mcp-reap-command — `eidolons mcp reap`: stop stale MCP containers without killing the live session

**Tier:** full · **Maker:** vivi · **Checker:** kupo · **Target:** nexus (new `eidolons mcp reap` subcommand)

## Scope

**Intent class:** REQUEST (new CLI surface + a novel safety algorithm).

### Problem

`.mcp.json` runs 4 of 5 MCP servers as `docker run --rm -i` stdio containers
(`crystalium`, `tonberry`, `atlas-aci`, `atomos`; `junction` is a native binary — verified in
`/home/rynaro/workspace/oss/agents/eidolons/.mcp.json`). A `--rm -i` container lives exactly as
long as its `docker run` client keeps stdin open and is auto-removed **only** on a clean EOF.
Every Claude Code session — and every daemon-prewarmed `claude` spare — spawns a full set of
these containers, and abandoned sessions never close stdin cleanly, so their containers never
exit. Stale MCP containers accumulate (observed: 16 running across 5 live sessions + a 9h
unclaimed spare). This is **not** a crash-loop (`RestartPolicy=no`, `restarts=0`) and nothing is
a truly orphaned container in the common case — each is pinned by a **live** `docker run` client
belonging to a session the user no longer wants. There is no reaper today:
`eidolons mcp uninstall` only unwires `.mcp.json` and the nexus contains no `docker stop`
anywhere (verified — grep of `cli/src`).

### In scope

- A new `eidolons mcp reap` subcommand that lists and (on explicit confirm) stops **labeled**
  stale MCP containers.
- An **exact current-session protection guard** so the reaper never stops a container the running
  agent is using mid-task.
- `--dry-run` / preview default, `--yes`, `--all`, `--project`, `--older-than`, `--json`, `-h`.
- Graceful behaviour when docker is absent or the guard is indeterminate.
- An inline `fake-docker` + `fake-ps` bats harness (no real daemon, no real containers).

### Out of scope (Deferred)

- Reaping **unlabeled** containers. Reap identifies MCP containers **only** by the Docker label
  `eidolons.project=<slug>`. Legacy `atlas-aci` wiring that OMITS the label (a known coverage gap
  — the current template at `cli/templates/mcp/atlas-aci.mcp.json.tmpl` DOES set it, but older
  installs may not) is invisible to reap. This is the **safe** direction (an unlabeled container
  is never a candidate, so it is never wrongly stopped) but it means label-less legacy containers
  must be cleaned manually. Called out, not solved, in v1.
- Stopping the native `junction` binary or any non-docker server.
- Removing Docker **images** (that is `mcp uninstall`/image lifecycle territory).
- A background daemon / watch mode. `reap` is a one-shot verb.
- Cross-host process guards. The guard is Linux/`ps`-based; on hosts without a POSIX `ps` the
  guard degrades to **indeterminate** (protect-all), never to unsafe.

### Assumptions (risk-if-wrong)

1. **A1 — The current session's MCP `docker run` clients are direct children of the session's
   `claude` process** (PPID == the ancestor `claude` PID). *Verified live:* the four
   `docker run --rm -i --label eidolons.project=eidolons …` processes all have `PPID` equal to
   the session `claude` PID; no intermediate `node`/shell wrapper. *Risk if wrong:* the guard
   would enumerate the wrong client set → mitigated by the fail-safe (indeterminate ⇒ protect all).
2. **A2 — A `docker run` client synchronously creates exactly one container at start, so within a
   server signature the start-order of clients equals the creation-order of containers**, and this
   holds across `--rm` respawns (a respawn is a NEW client + a NEW container, both later). *Risk if
   wrong:* a mis-pairing → mitigated by the ambiguity-safe over-protect rule (§Approach step 6).
3. **A3 — `CLAUDECODE` is present in a Claude Code session's environment** (verified live). Used as
   the "am I inside a session, so the guard MUST be active" sanity signal.
4. **A4 — `docker stop` on a `--rm` container triggers auto-removal**, so the reaper needs no
   `docker rm`. *Risk if wrong (a non-`--rm` labeled container):* it is left stopped-but-present;
   acceptable, and re-runnable.

## Approach (selected hypothesis: **B — reap-all-except-current-session**)

Reap every labeled MCP container **except** the current session's own set, gated behind a
preview-by-default confirm flow and an exact session guard. This is the only option that matches
the actual pain (live-but-abandoned sessions); see §Rejected Alternatives for A (orphan-only,
a no-op) and C (count-based heuristic, unsafe).

### CLI surface

```
eidolons mcp reap [options]

Options:
  --dry-run            Preview the reap set; never invoke docker stop. Wins over --yes.
  -y, --yes            Actually stop the reap set. Without it (and without --dry-run),
                       reap PREVIEWS and stops nothing (safe default for a destructive op).
  --all                Consider labeled MCP containers across EVERY eidolons.project slug.
                       Mutually exclusive with --project. (Default: current project only.)
  --project <slug>     Restrict to containers labeled eidolons.project=<slug>.
                       Default: the current project slug (project_slug of cwd).
  --older-than <dur>   Only reap containers created more than <dur> ago (Ns|Nm|Nh|Nd).
                       Default: 0 (any age, still subject to the session guard).
  --json               Emit a machine-readable JSON object (schema eidolons/mcp-reap.v1)
                       on stdout; all human logs stay on stderr.
  -h, --help           Show help.

Exit codes:
  0  success — reaped, nothing-to-reap, docker absent, guard indeterminate, or any preview
  2  usage error (unknown flag, bad --older-than, --all combined with --project)
```

**Safety default = preview.** With neither `--yes` nor `--dry-run`, `reap` lists what it *would*
stop and stops nothing. `--dry-run` is an explicit forced-preview that overrides a stray `--yes`.
Only `--yes` (without `--dry-run`) executes `docker stop`. Rationale: this verb stops containers
belonging to *other live sessions*; the least-surprising, hardest-to-misfire default for a
destructive op is preview + explicit confirm. Exit-code posture follows the docker-touching family
(`mcp images` always exits 0; usage is 2): a cleanup verb returns 0 on every non-usage outcome,
including partial stop failures caused by a container that already self-removed (recorded in
`errors[]`, never fatal).

### Container identity

An "MCP container" is any container returned by:

```
docker ps --filter label=eidolons.project=<slug> \
  --format '{{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Label "eidolons.project"}}\t{{.CreatedAt}}'
```

Under `--all`, the same query without `label=…=<slug>` (bare `label=eidolons.project`) to span
every slug. Nothing without the label is ever a candidate.

### Current-session protection guard (the load-bearing invariant)

**Invariant: the current session's containers are NEVER passed to `docker stop`.** The guard is
process-anchored and exact; the `--rm` self-heal is noted only as a last-ditch net (a wrongly
stopped container re-spawns on the next MCP call), never relied upon — stopping mid-call can still
error an in-flight op.

The reaper takes ONE process snapshot (`ps -eo pid=,ppid=,etime=,args=`, or `-Ao …` for
BSD/macOS `ps`) and one `docker ps` snapshot, then:

1. **Resolve `CURRENT_CLAUDE_PID`.** Walk the parent chain from the reaper's self PID
   (`$$`, overridable by the test-only seam `EIDOLONS_REAP_SELF_PID` for the fake-ps harness),
   at most ~24 hops or until PID 1. Stop at the first ancestor whose `comm`/`args` is `claude`
   (or matches `$CLAUDE_CODE_EXECPATH` when set). Record its PID.
2. **Classify the guard state:**
   - `none` — `CLAUDECODE` unset (invoked from a plain shell / cron): there is no current session
     to protect. Proceed against all matching containers (still subject to `--yes`).
   - `indeterminate` — `CLAUDECODE` set but `CURRENT_CLAUDE_PID` unresolved, OR resolved but the
     session has **zero** `docker run` MCP clients while candidates exist: **fail safe — protect
     every candidate, stop nothing, warn, exit 0.**
   - `active` — `CLAUDECODE` set, `CURRENT_CLAUDE_PID` resolved, ≥1 current-session client found.
3. **Enumerate current-session clients (`CUR_CLIENTS`).** From the snapshot, select processes P
   where `ppid(P) == CURRENT_CLAUDE_PID` and `args(P)` matches a `docker … run …` invocation
   carrying `--label eidolons.project=`. For each, extract its **signature** = the image ref token
   (`ghcr.io/…@sha256:…`) and its start-order key (parsed `etime` seconds; larger = started earlier).
4. **Enumerate ALL host MCP clients** (same match, any PPID) so ranks can be computed across
   sessions; each carries its PPID + start-order key + signature.
5. **Rank-bijection per signature.** For each signature S:
   - Sort S's containers by `CreatedAt` (ISO/`docker inspect {{.Created}}` sorts lexically —
     no date math) ascending → `C0..Ck`.
   - Sort S's clients by start-order (earliest first) → `D0..Dk`.
   - Pair rank-wise `Ci ↔ Di` (A2). Container `Ci` is **PROTECTED** iff its paired client `Di`
     has `ppid == CURRENT_CLAUDE_PID` (equivalently `Di ∈ CUR_CLIENTS`).
6. **Ambiguity-safe over-protect.** If, within a signature, client-count ≠ container-count, or a
   start-order / `CreatedAt` tie makes a rank pairing span different owning sessions, protect
   **all** of that signature's containers that could plausibly map to a current-session client.
   Over-protection only spares an extra stale container (safe); it must never leave a
   current-session container reapable.

Only clock **order within one list** is ever compared, so `ps` vs `docker` clock skew is
irrelevant. The full PROTECTED set is the union across signatures.

### Reap set + mechanism

```
REAP = candidates − PROTECTED − { too-young by --older-than } − { project-mismatch }
```

- `--older-than <dur>`: `age = now(date +%s) − created_epoch`, where `created_epoch` comes from
  `docker inspect -f '{{.Created}}'` parsed by a small `_reap_iso_to_epoch` helper (GNU `date -d`
  → BSD `date -jf` → **unknown**). Unknown age FAILS the age filter (treated as too-young ⇒
  protected). `<dur>` parsed by `_reap_dur_to_seconds` (`Ns|Nm|Nh|Nd`); a malformed value is a
  usage error (exit 2). Absent `--older-than` ⇒ threshold 0 ⇒ every age passes.
- **Stop mechanism (`--yes`, not `--dry-run`):** `docker stop <id-or-name> …` for each container
  in REAP. `docker stop` sends SIGTERM to the server (PID 1 in the container); on exit `--rm`
  auto-removes it (A4) — no `docker rm` needed. The owning (other) session's `docker run` client
  gets EOF and that session self-heals on its next MCP call. A `docker stop` that errors because
  the container already vanished is recorded in `errors[]` and is non-fatal.
- **Idempotency:** after a successful reap the stopped containers are gone from `docker ps`, so a
  second run finds nothing in REAP and stops nothing (exit 0).
- **Docker absence:** if `atlas_aci_check_docker_cli` / `atlas_aci_check_docker_daemon` (reused
  from `cli/src/lib_mcp_atlas_aci.sh`, exactly as `mcp_images.sh` does) fail, print one info line
  to stderr, emit an empty result, exit 0. Never a failure.

### `--json` shape (schema `eidolons/mcp-reap.v1`)

```json
{
  "schema": "eidolons/mcp-reap.v1",
  "project": "eidolons",
  "docker_available": true,
  "executed": false,
  "guard": { "status": "active", "claude_pid": 2615391, "protected_count": 4 },
  "reap":      [ { "id": "…", "name": "…", "image": "…", "project": "eidolons",
                   "age_seconds": 34210, "stopped": false } ],
  "protected": [ { "id": "…", "name": "…", "image": "…", "project": "eidolons",
                   "age_seconds": 41 } ],
  "skipped":   [ { "id": "…", "name": "…", "reason": "too-young" } ],
  "errors":    [ { "id": "…", "message": "…" } ]
}
```

`executed` is `false` for preview/`--dry-run`, `true` under `--yes`; each `reap[]` entry's
`stopped` flips to `true` when its `docker stop` returns 0. `guard.status` ∈
`active | indeterminate | none`. `reason` ∈ `protected | too-young | project-mismatch | unlabeled`.

## Stories

- **S1 — Reap subcommand + dispatch.** New `cli/src/mcp_reap.sh` (sources `lib.sh`, `lib_mcp.sh`,
  `lib_mcp_atlas_aci.sh`); registered in `cli/src/mcp.sh` (case arm, usage block line, and the
  `Available subcommands:` error line). Arg parser, `-h/--help`, exit-code contract. **Executor
  tier:** mid; **output contract:** stderr logs via say/ok/info/warn/die, stdout reserved for
  `--json`. Timebox: ≤ 2d. Covers AC-001..002, AC-005..007, AC-010..011, AC-016..019.
- **S2 — Session guard.** The process-snapshot walk, `CURRENT_CLAUDE_PID` resolution, guard-state
  classification, rank-bijection, ambiguity-safe over-protect, `EIDOLONS_REAP_SELF_PID` seam.
  **Output contract:** a PROTECTED id/name set consumed by the reap-set computation. Timebox: ≤ 2d.
  Covers AC-003..004, AC-012..015, AC-020 (the core safety surface).
- **S3 — Filters + reaping.** `--older-than` (dur + iso parsers, unknown-age-safe), `--project`,
  `--all`, `docker stop` loop with non-fatal error capture, idempotency, `--json` assembly via
  `jq -n`. Timebox: ≤ 1d. Covers AC-008..009, AC-014, AC-020.
- **S4 — Harness + CHANGELOG.** Inline `fake-docker` + `fake-ps` bats harness in
  `cli/tests/mcp_reap.bats` (per-file convention — do NOT lift to `helpers.bash`; model on
  `cli/tests/mcp_images.bats` lines 24-90); `CHANGELOG.md` `[Unreleased] › Added`. Timebox: ≤ 2d.
  Covers every AC + AC-018 (shellcheck).

## Rejected Alternatives

- **A — Orphan-only** (score 70; alignment 3). Reap only containers whose owning `docker run`
  client PID is dead. Strictly safe but a **no-op in practice**: with `--rm -i`, a dead client
  means the container already exited and was auto-removed, so there is nothing to find. The real
  stale case (live-but-abandoned sessions) is exactly what this misses. Rejected: does not solve
  the problem.
- **C — Count-based oldest-surplus heuristic** (score 60, weak; risk 4). Per `(slug,image)`
  signature, keep N newest, reap the older surplus. **Unsafe:** the current session does not
  necessarily own the newest container of a signature (a prewarmed spare can hold a newer one), so
  "keep newest" can leave the live session's container reapable. Fails the non-negotiable safety
  invariant. Rejected.
- **Guard sub-variant — protect by signature match only** (protect every container of any
  signature the current session uses). Safe but **over-protects to a no-op** (it also spares other
  sessions' containers of the same server type — the same failure mode as A). The rank-bijection is
  the minimal mechanism that is both exact and useful. Rejected in favour of §Approach step 5,
  keeping signature-match only as the ambiguity fallback (step 6).

## Risks

- **P0 — Guard mis-classifies a current container as reapable.** The single unacceptable failure.
  Mitigations: exact rank-bijection (A2), ambiguity-safe over-protect (step 6), fail-safe
  indeterminate ⇒ protect-all (step 2), preview-by-default + explicit `--yes`. The core acceptance
  check (AC-003) asserts `docker stop` is *never* called with a protected name across every
  scenario.
- **P1 — `ps` portability.** `etime` parsing differs Linux/BSD; a host without POSIX `ps` yields no
  snapshot. Mitigation: unresolved `CURRENT_CLAUDE_PID` ⇒ indeterminate ⇒ protect-all. Never unsafe,
  at worst a no-op.
- **P1 — Label coverage gap.** Legacy label-less `atlas-aci` containers are invisible to reap
  (Deferred). Safe (never wrongly stopped) but incomplete; documented in `--help` and the
  CHANGELOG so operators know to clean those manually.
- **P2 — Timestamp-tie mis-pairing under a same-second concurrent spawn** (e.g. a spare racing a
  user session). Mitigation: over-protect on ambiguity (step 6) — spares an extra stale container,
  never kills a live one.

## Acceptance Criteria

Every criterion is mechanically checkable with the inline `fake-docker` + `fake-ps` harness
(no real daemon, no real containers). `fake-docker` logs every argv line to `$DOCKER_LOG`; the
suite asserts on the presence/absence of `stop <name>` lines. `fake-ps` emits a controlled process
table; the reaper is rooted at it via `EIDOLONS_REAP_SELF_PID`. Container `CreatedAt`/`Created`
and process `etime`/`ppid` are fixtured to construct exact scenarios.

### AC-001 (event-driven)
GIVEN the docker CLI is absent from PATH
WHEN `eidolons mcp reap --yes` runs
THEN no `docker stop` line is ever written to the docker log
VERIFY: bats `AC-001` — fake-docker removed from PATH; assert exit 0; assert `grep -c '^stop' $DOCKER_LOG` is 0.

### AC-002 (event-driven)
GIVEN the docker daemon is unreachable (`docker info` exits non-zero)
WHEN `eidolons mcp reap --yes` runs
THEN the command exits 0 having stopped nothing
VERIFY: bats `AC-002` — `FAKE_DOCKER_INFO_RESULT=fail`; assert exit 0; assert no `stop` line in log.

### AC-003 (unwanted-behavior)
GIVEN a fixtured session table where CURRENT_CLAUDE_PID owns one crystalium client paired (by rank) to container `cur-crystalium`
WHEN `eidolons mcp reap --yes` runs with other-session containers also present
THEN `docker stop` is never invoked with `cur-crystalium`
VERIFY: bats `AC-003` (core safety) — assert `$DOCKER_LOG` contains no line `stop cur-crystalium`; assert every protected name is absent from the stop lines.

### AC-004 (event-driven)
GIVEN a fixtured other-session container `old-crystalium` owned by a different claude PID
WHEN `eidolons mcp reap --yes` runs with the guard active
THEN `docker stop old-crystalium` is invoked exactly once
VERIFY: bats `AC-004` — assert `grep -c '^stop old-crystalium' $DOCKER_LOG` is 1.

### AC-005 (state-driven)
GIVEN reapable other-session containers exist and neither `--yes` nor `--dry-run` is passed
WHEN `eidolons mcp reap` runs
THEN no `docker stop` line is written to the docker log
VERIFY: bats `AC-005` — assert exit 0; assert no `stop` line; assert stdout/stderr lists the would-reap set.

### AC-006 (unwanted-behavior)
GIVEN reapable other-session containers exist
WHEN `eidolons mcp reap --dry-run --yes` runs
THEN no `docker stop` line is written to the docker log
VERIFY: bats `AC-006` — assert exit 0; assert no `stop` line (dry-run overrides --yes).

### AC-007 (event-driven)
GIVEN labeled containers exist under two slugs `eidolons` and `other`
WHEN `eidolons mcp reap --yes --project other` runs
THEN no container labeled `eidolons.project=eidolons` appears in a stop line
VERIFY: bats `AC-007` — assert stop lines reference only `other`-slug names.

### AC-008 (unwanted-behavior)
GIVEN an other-session container created 30s ago
WHEN `eidolons mcp reap --yes --older-than 10m` runs
THEN that container is not passed to `docker stop`
VERIFY: bats `AC-008` — assert its name is absent from stop lines; assert `--json` records it as `skipped` reason `too-young`.

### AC-009 (event-driven)
GIVEN an other-session container created 2h ago
WHEN `eidolons mcp reap --yes --older-than 10m` runs
THEN `docker stop` is invoked with that container
VERIFY: bats `AC-009` — assert its name appears in a stop line.

### AC-010 (event-driven)
GIVEN any reap invocation with `--json`
WHEN the command completes
THEN stdout parses as a JSON object whose `.schema` equals `eidolons/mcp-reap.v1`
VERIFY: bats `AC-010` — pipe stdout to `jq -e '.schema=="eidolons/mcp-reap.v1" and (.guard.status|type=="string") and (.reap|type=="array") and (.protected|type=="array")'`.

### AC-011 (state-driven)
GIVEN the only labeled containers belong to the current session
WHEN `eidolons mcp reap --yes` runs
THEN the command exits 0 having written no `stop` line
VERIFY: bats `AC-011` — assert exit 0; assert no `stop` line; assert `--json` `.reap` is `[]`.

### AC-012 (event-driven)
GIVEN a first reap removed all other-session containers so `docker ps` now returns only current-session containers
WHEN `eidolons mcp reap --yes` runs a second time
THEN no `docker stop` line is written on the second run
VERIFY: bats `AC-012` — repoint fake `docker ps` to the post-reap set; assert exit 0; assert no `stop` line.

### AC-013 (unwanted-behavior)
GIVEN `CLAUDECODE` is set but the process walk resolves no `claude` ancestor
WHEN `eidolons mcp reap --yes` runs with candidates present
THEN no `docker stop` line is written to the docker log
VERIFY: bats `AC-013` — fake-ps has no `claude` row; assert exit 0; assert no `stop` line; assert `--json` `.guard.status=="indeterminate"`.

### AC-014 (event-driven)
GIVEN labeled containers exist under slugs `eidolons` and `other`, none owned by the current session
WHEN `eidolons mcp reap --yes --all` runs
THEN `docker stop` is invoked with an `other`-slug container
VERIFY: bats `AC-014` — assert a stop line references the `other`-slug name.

### AC-015 (unwanted-behavior)
GIVEN a running container that carries no `eidolons.project` label
WHEN `eidolons mcp reap --yes --all` runs
THEN that container is never passed to `docker stop`
VERIFY: bats `AC-015` — the unlabeled container is absent from the label-filtered `docker ps`; assert its name never appears in a stop line.

### AC-016 (event-driven)
GIVEN an unknown flag `--bogus`
WHEN `eidolons mcp reap --bogus` runs
THEN the command exits 2
VERIFY: bats `AC-016` — assert status 2.

### AC-017 (event-driven)
GIVEN a malformed duration `--older-than 5x`
WHEN `eidolons mcp reap --older-than 5x` runs
THEN the command exits 2
VERIFY: bats `AC-017` — assert status 2.

### AC-018 (ubiquitous)
THEN the `cli/src/mcp_reap.sh` source is shellcheck-clean under the repo's error gate
VERIFY: `shellcheck -x -S error cli/src/mcp_reap.sh` exits 0 (mirrors `make lint`).

### AC-019 (event-driven)
GIVEN the `mcp` sub-dispatcher
WHEN `eidolons mcp reap --help` runs
THEN the command exits 0
VERIFY: bats `AC-019` — assert status 0; assert `mcp.sh` case arm + usage line + error-list line mention `reap` (grep the dispatcher).

### AC-020 (unwanted-behavior)
GIVEN a signature whose client-count and container-count disagree (a mid-respawn window) with a current-session client present
WHEN `eidolons mcp reap --yes` runs
THEN none of that signature's containers are passed to `docker stop`
VERIFY: bats `AC-020` — fixture a 1-client / 2-container signature owned partly by CURRENT_CLAUDE_PID; assert none of the signature's names appear in stop lines (over-protect).

## Confidence

See `spec.yaml` for the machine-readable `acceptance_checks` mirror and the files-touched list.
Confidence verdict is computed by `ramza-score --rubric confidence` and recorded in the plan
state (`.spectra/plans/mcp-reap-command.state.json`). The one gate this spec cannot self-satisfy
— the independent critic (maker≠checker) — is the downstream ESL verify by **kupo**; the
implementation maker is **vivi**.
