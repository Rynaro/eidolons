# verification-plan — crystalium#66

All ten criteria executed 2026-08-07 against `Rynaro/crystalium` at `d1691db` + this change.
Image `crystalium:dev` rebuilt from the modified Dockerfile before any run.

| AC | result | evidence |
|---|---|---|
| AC-401 compose runs as host user | **PASS** | `uid=1000 gid=1000 groups=1000` |
| AC-402 fresh volume writable | **PASS** | `/data` = `drwxrwxrwt`, `DATA WRITE OK` |
| AC-403 real stores open | **PASS** | `doctor`: `data_dir writable` OK, dense+graph arms active, "all P0 checks passed" |
| AC-404 uv survives non-root | **PASS** | exit 0 with `HOME=/tmp`; red-checked below |
| AC-405 writes host-deletable | **PASS** | `make check-ownership` exit **0** |
| AC-406 gate fails on defect | **PASS** | pre-fix compose, `make check-ownership` exit **2**, 22 undeletable paths |
| AC-407 published image unchanged | **PASS** | every added Dockerfile line is below `FROM base AS dev` |
| AC-408 no suite regression | **PASS** | `make test-ci` → 1097 passed, 4 skipped, 1 xfailed, exit 0 |
| AC-409 migration reclaims | **PASS** | real checkout 297 → **0** foreign-owned paths |
| AC-410 confound-free attribution | **PASS** | root 1095/6 vs host-user 1097/4 in ONE checkout; delta = the 2 doctor tests |
| AC-411 no traversal blind spot (REJECT-01) | **PASS** | 6/6 fixture cases match; c1 and c4 FAIL, c2/c3/c5/c6 PASS |
| AC-412 `.git` is audited (REJECT-02) | **PASS** | root-owned `.git/worktrees/ghost` now FAILs the gate; 0 foreign-owned in `.git` on the real checkout, so no over-fire |
| AC-413 hostile filenames (maker self-attack) | **PASS** | space and embedded-newline fixtures both FAIL with the path intact and the correct reason |

## REJECT-01 — checker kupo, 2026-08-07 — the gate had a silent blind spot

The checker was asked to attack the removability rule specifically, on the grounds that the
maker had written both the rule and the `.venv` exception that motivated it. It found a real
hole and the change was rejected rather than verified.

**The defect.** The rule flagged a path only when its OWN parent was unwritable. Correct for
a file; incomplete for a directory. A root-owned mode-0700 directory with content, sitting in
a host-owned parent, passed:

```
$ <old rule>   -> OK: every path the container wrote is deletable by uid 1000
$ rm -rf D     -> rm: cannot remove 'D': Permission denied      # D survives
```

Two compounding causes: the directory's own parent WAS writable so the rule cleared it, and
`find` could not descend into a 0700 directory so its children were never enumerated — the
traversal error going straight into the `2>/dev/null` the check itself installed. Reproduced
independently by the maker before accepting the finding.

This matters for this project specifically: mode-0700 directories are routine output of
`tempfile.mkdtemp`, `.ssh`, `.gnupg` and assorted caches, and root-owned residue of exactly
that shape is what #66 exists to catch.

**The fix.** Rule moved to `scripts/check-ownership.sh` and restated as the real removability
condition for both kinds — a path is STUCK unless its parent is writable AND, if it is a
directory, the host user can actually clear it (readable + traversable + writable, or
genuinely empty). An unreadable directory is STUCK by definition, since `ls` on it returns
nothing and would otherwise read as "empty" and pass — it fails closed. `find`'s stderr is
captured instead of discarded and any traversal failure is itself a finding.

**Stating the condition properly caught a second case the checker did not report:** c4, a
root-owned 0755 non-empty directory — readable and traversable, so `find` enumerates it fine,
but not writable, so its children cannot be unlinked. The old rule missed that too. Patching
only the reported symptom would have left it.

Validated by a 6-case fixture (AC-411) rather than by re-running the single counter-example,
so the fix is shown not to over-fire: the `.venv` mountpoint (c2) still passes **without an
exception entry**. `shellcheck -S style` clean; `make check-ownership` green on the real
checkout.

## Red-checks — each defect below was found by RUNNING, not by reading

1. **AC-404 / uv cache.** First non-root probe died with
   `Failed to initialize cache at /.cache/uv: Permission denied` before reaching Python. The
   entrypoint is `uv run --no-sync`, so uv touches `$HOME` on every start; as a non-root uid
   `HOME` is `/`. Measured that `HOME=/tmp` alone is sufficient — no separate `UV_CACHE_DIR`.
2. **AC-402 / named-volume ownership.** A volume mounted at a path the image does not
   pre-create is root-owned `drwxr-xr-x`; `touch` returned `Permission denied`. Fixed by
   `mkdir -p /data && chmod 1777 /data` in the dev stage, since Docker seeds a fresh volume
   from the image directory's mode.
3. **AC-405 / the gate's first form was wrong.** It gated on raw *ownership* and failed the
   green arm on `./.venv` — a root-owned mountpoint the Docker daemon creates regardless of
   `user:`. Measured that `rmdir .venv` succeeds without sudo (removal permission comes from
   the parent's write bit), so it is harmless. Rewritten to gate on **removability**, which is
   the property #66 actually claims. The tempting alternative — an exception list for `.venv` —
   is how a gate rots into a formality.
4. **`make fix-ownership` created the mess it was written to clean.** The first draft ran
   without `--entrypoint`, so `uv run --no-sync` executed and wrote a fresh `.venv` straight
   into the bind-mounted tree. Fixed with `--entrypoint sh`. It also used a plain `chown`,
   which follows symlinks — `.venv/bin/python` and `.venv/lib64` stayed root-owned until
   `chown -h`. Both found by running it against a real 297-path checkout.
5. **AC-410 / the first control was confounded.** Comparing the fixed real checkout against a
   pre-fix *fresh clone* showed a 4-test delta. Two were `test_roundtrip_handoff` skipping on
   "roster fixtures not mounted" — a property of the clone, not of the change. Re-measured with
   `--user 0:0` in the same directory: the true delta is 2.

## Not covered

- The published image's own `--user` story. That pin belongs in the nexus MCP templates
  (`roster/mcps.yaml`), not this repo, and cannot be regression-tested from here.
- ~~Hosts where `id -u` is not 1000.~~ **CLOSED — now measured.** The CI `ownership` job on
  PR #67 ran as **uid 1001** (GitHub runner) and passed: `scanning for paths the host user
  (uid 1001) cannot delete` → `OK`. The 1777 mode on `/data` is uid-agnostic in fact, not just
  by argument. Run 31221905779, job 93008092327.
- Podman / rootless Docker, where uid mapping differs entirely.

## REJECT-02 — checker kupo, 2026-08-07 — two findings, one fixed, one bounded

### Finding 2 — ACCEPTED AND FIXED: the audit excluded the motivating incident

The scan carried `-path ./.git -prune`. That excluded exactly the territory #66 exists to
protect: the motivating incident is `git worktree remove` deregistering a worktree and then
failing to delete it, and worktree metadata lives in `.git/worktrees/<name>/`.

```
$ <pruned rule>                    -> OK: every path ... is deletable   (exit 0)
$ rm -rf .git/worktrees/ghost      -> Permission denied; it survives
```

The sharper form of the finding: **the audit was narrower than its own remedy.**
`make fix-ownership` runs a bare `find /app -not -user … -exec chown -h …` with no `.git`
exclusion, so it reaches in and repairs damage `check-ownership` could not see. An audit that
reports green on damage its own remedy is standing by to fix is not an audit.

Prune removed. On the real checkout `.git` contributes 389 walked entries and **0**
foreign-owned paths, so the wider scope costs nothing and does not over-fire.

### Finding 1 — ACCEPTED AS REAL, deliberately NOT fixed: `chattr +i`

Immutable files defeat every rule here, which reasons purely over POSIX mode bits — and
defeat `make fix-ownership` too, since even a root container's `chown`/`rm` are refused
without an explicit `chattr -i`. The checker is right that this is strictly worse than the
mode-bit cases.

Not defended against, on **reachability** rather than convenience, and measured rather than
argued:

| probe | result |
|---|---|
| compose service (uid 1000, default caps) | `chattr: not found` — binary absent |
| root container, Docker default capability set | `Operation not permitted` |
| root container + explicit `--cap-add LINUX_IMMUTABLE` | succeeds |

`--cap-add LINUX_IMMUTABLE` appears nowhere in this repo, so no container this project runs
can produce the state. Detecting it would mean shelling out to `lsattr`, which does not exist
on macOS and has no cross-platform equivalent.

**Correction, from the checker's third pass.** An earlier draft of this justification also
claimed `lsattr` errors on overlayfs and tmpfs. The checker tested it: clean round-trip on
tmpfs, overlay2 AND btrfs — btrfs being what actually backs the real checkout. That claim was
asserted, not measured, and is withdrawn. It was never load-bearing: reachability is the
argument, and that half was independently verified and holds. Recorded as an explicit bounded limitation in the script header
and in `spec.yaml` known_gaps, so it is not rediscovered as a novel finding later.

### Axes now spent on this gate

Four, only one of them the maker's original design:

1. unreadable directory (mode 0700) — **checker**, REJECT-01
2. unwritable non-empty directory (mode 0755) — **maker**, from stating the rule properly
3. newline fragmentation in `find -print` — **maker** self-attack
4. `.git` prune scope — **checker**, REJECT-02

Every one of the four was found by RUNNING the gate against a constructed failing input, and
none by reading it. That is the campaign's own lesson applied to the campaign's own gate.
