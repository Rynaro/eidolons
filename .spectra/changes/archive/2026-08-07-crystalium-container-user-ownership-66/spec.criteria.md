# spec.criteria — crystalium#66 container user / bind-mount ownership

Criteria of record. Every VERIFY below was executed; results in `verification-plan.md`.

### AC-401 (ubiquitous) — the compose service runs as the host user
THE SYSTEM SHALL report the invoking uid/gid, not 0/0, for any `docker compose run`.
**VERIFY:** `docker compose run --rm --entrypoint sh crystalium -c 'id'` reports
`uid=1000 gid=1000`. **PASS = uid is not 0.**

### AC-402 (event-driven) — a fresh named volume is writable by the container user
WHEN the dev data volume is created for the first time,
THE SYSTEM SHALL permit the non-root container user to write to it.
**VERIFY:** `docker volume rm -f crystalium_data_v2` then
`docker compose run --rm --entrypoint sh crystalium -c 'ls -ld /data; touch /data/probe'`.
**PASS = `/data` is `drwxrwxrwt` and the touch succeeds.**

### AC-403 (state-driven) — the real stores open as non-root
WHILE running as the host user, THE SYSTEM SHALL open SQLite, LanceDB and Kuzu.
**VERIFY:** `docker compose run --rm crystalium python -m crystalium doctor`.
**PASS = `data_dir writable` OK, dense arm active, graph arm active, "all P0 checks passed".**
This is the criterion that would have caught a naive `user:` pin against `/root`.

### AC-404 (unwanted-behavior) — uv must not die before reaching Python
IF the container runs as a non-root uid,
THEN THE SYSTEM SHALL NOT fail with `Failed to initialize cache at /.cache/uv`.
**VERIFY:** `docker compose run --rm crystalium python -c 'print(1)'` exits 0.
**PASS = exit 0.** Red-checked: with `HOME` unset the same command fails with exactly that
error, so this criterion is falsifiable.

### AC-405 (event-driven) — container writes into the bind mount are host-deletable
WHEN the container writes into the bind-mounted tree,
THE SYSTEM SHALL leave every written path deletable by the host user.
**VERIFY:** `make check-ownership` in a pristine clone with the fix applied.
**PASS = exit 0.**

### AC-406 (unwanted-behavior) — the gate must fail on the defect
IF the `user:` key is absent, THEN `make check-ownership` SHALL exit non-zero.
**VERIFY:** same target, pre-fix `docker-compose.yml`, pristine clone.
**PASS = non-zero exit naming the undeletable paths.**
This is the red-check. A gate that cannot fail on the defect it names is not a gate.

### AC-411 (unwanted-behavior) — the gate must not have a traversal blind spot — REJECT-01
IF a root-owned directory is not readable/traversable by the host user (e.g. mode 0700),
THEN `make check-ownership` SHALL report it as STUCK, even though its own parent is
writable and `find` cannot enumerate its children.

**Origin — checker REJECT-01 (kupo, 2026-08-07).** The first rule flagged a path only when
its own PARENT was unwritable. That is the correct unlink condition for a FILE, but for a
DIRECTORY it misses the case where the directory itself cannot be cleared. Measured
counter-example: a root-owned mode-0700 directory with content, in a host-owned parent —
the gate printed `OK: every path the container wrote is deletable` while `rm -rf D` failed
with `Permission denied` and `D` survived. `find` could not descend into `D`, and the error
went into the `2>/dev/null` the check itself installed, so its children were never even
enumerated. The maker wrote both the rule and the `.venv` exception that motivated it —
exactly the arrangement this project keeps finding defects in.

**VERIFY:** a 6-case fixture, each case a host-owned parent containing one root-owned
artefact created via `docker run -u 0:0`:

| case | fixture | required |
|---|---|---|
| c1 | root 0700 non-empty dir (the REJECT-01 counter-example) | **FAIL** |
| c2 | root-owned EMPTY dir (the `.venv` mountpoint) | **PASS** |
| c3 | root-owned file, host-owned parent | **PASS** |
| c4 | root 0755 non-empty dir (readable, not writable) | **FAIL** |
| c5 | root-owned symlink | **PASS** |
| c6 | everything host-owned | **PASS** |

**PASS = all six match.** c2 is the load-bearing one: it must stay green *without* an
exception entry, or the fix has merely traded a blind spot for a suppression list.

Note c4 — a root-owned 0755 non-empty directory — was ALSO missed by the original rule and
is not the case the checker reported; it surfaced from stating the removability condition
properly rather than patching the single reported symptom.

### AC-412 (unwanted-behavior) — the audit must cover `.git` — REJECT-02
IF root-owned residue exists under `.git/`, THEN `make check-ownership` SHALL report it.

**Origin — checker REJECT-02 (kupo, 2026-08-07).** The scan carried `-path ./.git -prune`,
excluding exactly the territory this change exists to protect: #66's motivating incident is
`git worktree remove` deregistering a worktree and then failing to delete it, and worktree
metadata lives in `.git/worktrees/<name>/`. The audit was also **narrower than its own
remedy** — `make fix-ownership` runs a bare `find /app -not -user …` with no `.git`
exclusion, so it repairs damage the audit could not see. An audit that reports green on
damage its own remedy is standing by to fix is not an audit.

**VERIFY:** create a root-owned mode-0700 `.git/worktrees/ghost/` in a real repo; run the
gate. **PASS = non-zero exit naming it.** Measured before the fix: gate exit 0 while
`rm -rf .git/worktrees/ghost` failed with `Permission denied`.
**No over-fire:** on the real checkout `.git` contributes **0** foreign-owned paths. (The
walked-entry count is checkout-state dependent and drifts — 389 for the maker, 401 for the
checker minutes apart. It is not a pass condition; the 0 is.)

### AC-413 (ubiquitous) — path handling must survive hostile filenames
THE SYSTEM SHALL report the correct path for any filename, including names containing
spaces or newlines.

**Origin — maker self-attack, before resubmitting REJECT-01.** The rule read `find -print`
line-by-line, so a filename containing a newline split into fragments that were then tested
as if they were paths. A root-owned undeletable directory named `$'ev\nil'` was reported as
`il/a` — a path that does not exist. It still exited non-zero, because `dirname il/a` is
`il`, which does not exist and so tests as non-writable: **right by accident, naming a
ghost.** Contrive the trailing fragment to land on a real writable directory and the same
split becomes a miss.

**VERIFY:** fixtures with a space in the name and with an embedded newline, both undeletable.
**PASS = non-zero exit, path reported intact, correct reason.** Fixed with `-print0` /
`read -r -d ''`; accumulator changed from a `\n`-joined string printed via `printf '%b'` to
an array, since paths can contain backslashes that `%b` would interpret.

## Explicit bounded limitation — NOT a criterion, recorded so it is not rediscovered

`chattr +i` immutable files defeat this gate, and defeat `make fix-ownership` too: even a
root container's `chown`/`rm` are refused without an explicit `chattr -i`. Raised as
REJECT-02's first finding and **accepted as real**.

Not defended against, on **reachability** rather than convenience. Measured: the compose
service has no `chattr` binary and runs as uid 1000; a root container with Docker's default
capability set gets `Operation not permitted`; only an explicit `--cap-add LINUX_IMMUTABLE`
— which appears nowhere in this repo — can set it. No container this project runs can
produce the state. Detection would require `lsattr`, which does not exist on macOS and has
no cross-platform equivalent. An earlier draft also claimed it errors on overlayfs and tmpfs;
the checker measured otherwise (clean on tmpfs, overlay2 and btrfs) and that claim is
withdrawn — it was asserted rather than measured. Reachability is the load-bearing argument.

### AC-407 (ubiquitous) — the published image is unchanged
THE SYSTEM SHALL leave the `base` stage's user, entrypoint and data-dir resolution untouched.
**VERIFY:** `git diff main -- Dockerfile` contains no edit above the `FROM base AS dev` line.
**PASS = every added line falls inside the dev stage.**
This is the criterion protecting every existing MCP consumer wiring.

### AC-408 (state-driven) — no suite regression
WHILE running as the host user, THE SYSTEM SHALL pass the full suite.
**VERIFY:** `make test-ci`. **PASS = exit 0, 0 FAILED/ERROR lines.**

### AC-409 (event-driven) — the migration reclaims a polluted checkout
WHEN `make fix-ownership` runs against a checkout carrying pre-change root-owned files,
THE SYSTEM SHALL reduce the foreign-owned count to 0.
**VERIFY:** run it against the real checkout (297 foreign-owned paths at start).
**PASS = "remaining foreign-owned paths: 0".**

### AC-410 (event-driven) — attribution of the skip-count change is confound-free
WHEN the suite counts are compared before and after,
THE SYSTEM SHALL be measured in ONE checkout varying ONLY the container user.
**VERIFY:** `docker compose run --user 0:0 ... pytest` vs the same command without the
override, both in the real checkout.
**PASS = the delta is exactly the two `doctor` tests.**
Added because the first comparison used a fresh clone and reported a delta of four; two were
roster-fixture artifacts of the clone, not of this change.
