# Checker verdict — atlas-aci-autosync

- **Change:** `atlas-aci-autosync` (tier full) · **maker:** vivi · **checker:** vigil
- **Commit under review:** `5d79bf9` (PR #461, branch `feat/atlas-aci-autosync`) — every code read pinned via `git show 5d79bf9:`
- **Checker method:** adversarial verify against the code, not the maker's report. Ran the bats suite, `shellcheck -x -S error`, and live mutation tests on a scratch copy of the sources.

## VERDICT: GO-WITH-CONDITIONS

All 8 acceptance checks PASS (several proven by live mutation). maker != checker is satisfied. One MAJOR reasoned risk (F-1) touches the maintainer's stated non-negotiable ("never block a turn") and diverges from the precedent the spec itself cites — it is not an AC failure (no AC covers it), but given the release bar I do not issue a clean GO. Close F-1 or knowingly accept it as a documented residual before cutting v2.5.0.

## Per-AC results

| AC | Result | Evidence |
|----|--------|----------|
| AC-1 (no-op when atlas-aci absent) | PASS [VERIFIED] | bats AC-1 x2 green; gates `harness_hook.sh:205-206`. Malformed/absent `.mcp.json` -> `jq -e` fails -> `return 0`. |
| AC-2 (opt-out; absent => on) | PASS [VERIFIED] | bats AC-2 x3 green; MUTATION: replacing `has("enabled")` with the buggy `.enabled // "true"` makes `enabled:false` wrongly fire -> AC-2 goes RED. Confirms the deliberate idiom is load-bearing. `harness_hook.sh:211-216`. |
| AC-3 (exact argv: -d, --pull=never, exact digest, rw /repo, index --since) | PASS [VERIFIED] | Live argv is byte-exact contract. MUTATION 1 (drop `--pull=never`) and MUTATION 2 (hardcode a different digest) each turn the AC-3 assertion RED. `harness_hook.sh:223-250`. |
| AC-4 (dedup on running container) | PASS [VERIFIED] | bats AC-4 x2 green; `grep -qx` correctly rejects the `foo`/`foobar` substring collision (verified). Code double-anchors: `docker ps --filter name=^/<cname>$` AND `grep -qx`. `harness_hook.sh:238-240`. |
| AC-5 (never block / never non-zero / fail-open docker-absent) | PASS-with-caveat [VERIFIED for tested paths] | docker-absent -> exit 0, silent, normal SessionStart payload still emits; `-d` present in argv. CAVEAT: "never block" is only exercised on fail-fast paths; the wedged-daemon path is unguarded and untested — see F-1. `harness_hook.sh:219,244`. |
| AC-6 (both SessionStart and UserPromptSubmit) | PASS [VERIFIED] | bats AC-6 x3 green; single call site `harness_hook.sh:274-276` gated only on `event_name`, before all mode branches; PostToolUse does not fire. |
| AC-7 (bash 3.2 + shellcheck -x -S error clean) | PASS [VERIFIED] | `shellcheck -x -S error cli/src/harness_hook.sh` exit 0 (only a non-gating SC2034 warning). No `declare -A`/`readarray`/`mapfile`/`&>>`/`${var,,}`. |
| AC-8 (README on-by-default + opt-out) | PASS [VERIFIED] | README names `harness.atlas_sync.enabled: false` and "**on by default**"; both AC-8 greps match. |

## Findings

### MAJOR
- **F-1 [SUSPECT] No `timeout` guard on the synchronous docker calls** — `cli/src/harness_hook.sh:239` (`docker ps -a ...`, fully synchronous) and `:244` (`docker run --rm -d ...`) run with no time bound. The precedent the spec explicitly cites, `cli/src/memory.sh:164-171`, wraps its docker call in `timeout "${TIMEOUT}s"` (default 8s) with a bash-3.2 fallback. Against a daemon that is **up but unresponsive** (Docker Desktop hang, storage-driver stall, overload), `docker ps -a` can hang the synchronous prompt path with **no upper bound**, contradicting the spec's "bounded" claim and AC-5's "never block". The maker correctly closed the *foreground-pull* block vector with `--pull=never` (verified present) but not this one.
  - Mitigation that lowers, not removes, the risk: the spawn is `-d` (detached), so only container *creation* — not indexing — can block there; the dedup `docker ps -a` is the fully-synchronous exposure. The daemon-**down** case fails fast (~10-15 ms, connect-refused) and is not affected.
  - Not covered by any AC or test — the fake-docker shim always returns instantly, so the wedged-daemon path is entirely unexercised.
  - Suggested close (maintainer's call, I did not apply it): gate the two calls behind `command -v timeout` and wrap with a short bound (a few seconds), mirroring `memory.sh:164-171`.

### MINOR
- **F-2 [VERIFIED] Dedup test exercises only the `grep -qx` layer.** The fake docker `ps` handler echoes `FAKE_DOCKER_RUNNING_NAME` verbatim, ignoring the `--filter name=^/<cname>$` regex, so AC-4's "differently-named does not block" passes via `grep -qx`, not via docker's native anchoring. Both layers exist in the code and `grep -qx` is correct (verified), so the invariant holds; the docker-filter layer is a proxy in the test. `harness_hook.sh:239-240`; `harness.bats:2391-2393`.
- **F-3 [SUSPECT] Rapid-turn dedup race.** Two near-simultaneous invocations could both pass `docker ps -a` before either container registers. The daemon rejects the second `docker run --name <cname>` on the name conflict (`|| true` -> no-op) and atlas-aci's single-writer lock (AC-H-17) is the deeper backstop, so no two live indexers result — worst case a harmless rejected duplicate. In a single synchronous-hook session this race is not reachable anyway. Not a defect. `harness_hook.sh:239-250`.
- **F-4 [VERIFIED] Two `@sha256` tokens / multi-server.** The digest read is scoped to `.mcpServers["atlas-aci"].args` with `head -1`; a second mcp server's digest cannot leak, and multiple atlas-aci digests resolve deterministically to the first. `harness_hook.sh:223-224` (verified: `other-mcp` digest absent from spawn).
- **F-5 [VERIFIED] Slug with a space / shell metacharacter.** All uses are double-quoted, no `eval`; a space-containing slug yields exit 0 with no crash (verified). A docker-invalid name would be rejected by real docker -> `|| true` no-op. No injection vector. `harness_hook.sh:228-248`.
- **F-6 [VERIFIED] AC-1 "no stderr" clause holds by construction, not by assertion.** The AC-1 bats test asserts exit-0 + empty argv log but not empty output; the no-stderr guarantee comes from the call-site `>/dev/null 2>&1` and the outer `_main 2>/dev/null` (`harness_hook.sh:275,531`). Test-completeness note only.

### Observations (not findings)
- Autosync is gated behind `HOOK_HOST` non-empty (early `return 0` at `harness_hook.sh:265-267`, before the autosync call at :274). A misconfigured empty-`HOOK_HOST` invocation does not autosync; run.sh always sets it. Correct.
- `HOOK_EVENT_NAME` unset defaults to `UserPromptSubmit` (`:261`) -> autosync still fires. Robust.
- Nested-workspace bound: if a *different*, also-atlas-aci-wired project root is the hook's cwd, it reindexes that tree. Documented in the header (`:195-199`) and README, and gated by that tree having atlas-aci wired (it reads that tree's digest+slug). Disclosed known bound, not a bug.

## Scope / hygiene checks
- `git diff --stat origin/main 5d79bf9` touches exactly `README.md`, `cli/src/harness_hook.sh`, `cli/tests/harness.bats`, `roster/mcps.yaml` — no more.
- `schemas/eidolons.yaml.schema.json` is byte-identical to `origin/main` (the partial `.harness` block was reverted cleanly).
- `VERSION` and `CHANGELOG.md` untouched (maintainer owns the release).
- Full `cli/tests/harness.bats`: 139/139 pass, 0 failures (no regression from the new call site).

## ESL ruling
- **maker != checker:** SATISFIED. `maker: vivi`, `checker: vigil` are distinct identities (ESL C4). I did not author `5d79bf9`.
- **Ready to transition to `verified`?** Not yet, unconditionally. Every stated AC passes, so this is not a hard `verify_fail`; but F-1 is a turn-blocking path the maintainer's stated bar rejects. Recommended path: (a) close F-1 with a `timeout` wrapper (mirrors `memory.sh:164-171`) and transition to `verified`, OR (b) the maintainer knowingly accepts the wedged-daemon residual as documented and transitions to `verified`. I did not run `mcp__tonberry__transition` — the lifecycle decision on the condition is the maintainer's.

*VIGIL — checker on the ESL failure path. Verified against 5d79bf9, not against the maker's report.*

---

## Second pass — F-1 fix re-verified at `c848ed2` (the shipped commit)

Re-checked because the fix is a newer commit than the one I first verified; the checker of record must confirm what actually ships. All reads pinned via `git show c848ed2:`. `c848ed2` builds directly on `5d79bf9` (ancestor); working tree is byte-identical to `c848ed2` for all 4 files, so the bats run tests the shipped code.

**1. F-1 closed correctly — CONFIRMED [VERIFIED].** Both synchronous docker calls are wrapped in the reused `with_timeout` helper (`cli/src/lib.sh`, the bash-3.2-portable wrapper returning 124 on timeout), not a hand-rolled second idiom: `harness_hook.sh:262` (`docker ps -a` dedup) and `:269` (`docker run -d` spawn). Bound is `_atlas_sync_timeout="${EIDOLONS_ATLAS_SYNC_TIMEOUT_S:-1.5}"` (`:255`), env-overridable. Fail-open composition verified: on a timed-out dedup probe, `running` is empty → `grep -qx` no match → falls through to the (also-bounded) spawn — backstopped by `--name` uniqueness + atlas-aci's single-writer lock. Guard test `F-1: with_timeout is the ONLY timeout idiom` asserts `with_timeout` count ≥ 2 and no `GNU timeout` hand-roll.

**2. Wall-clock test bounds a real hang and models the real failure — CONFIRMED [VERIFIED by reproduction].** The shipped shim uses `exec sleep "$PS_SLEEP"` (single process, same PID, no descendant holding the capture pipe) — the correct model of a single-process docker CLI wedging on its own syscall, so `with_timeout`'s `kill -9 "$pid"` genuinely terminates it. The test asserts wall-clock (`elapsed < 6` against `FAKE_DOCKER_PS_SLEEP=8` + `EIDOLONS_ATLAS_SYNC_TIMEOUT_S=2`) and that the killed dedup falls through to a spawn. Reproduced the RED against the pre-fix `harness_hook.sh`:
  - FIXED (`c848ed2`, with_timeout): **elapsed = 2068 ms** → GREEN (bounded), spawn fired.
  - PRE-FIX (`5d79bf9`, raw `docker ps`): **elapsed = 8028 ms** (full sleep) → RED. The test does NOT pass against unbounded code — it is not a fake-is-wrong pass.

**3. No regression, scope intact — CONFIRMED [VERIFIED].** `shellcheck -x -S error` clean on both `cli/src/harness_hook.sh` and `cli/src/lib.sh` (exit 0). Full `cli/tests/harness.bats`: **141/141 pass, 0 fail** (139 prior + 2 new F-1 tests). `git diff --stat origin/main c848ed2` = only the 4 files. `schemas/eidolons.yaml.schema.json` byte-identical to `origin/main`. `VERSION` / `CHANGELOG.md` untouched.

**4. Nothing new introduced — CONFIRMED [VERIFIED].** The only code delta `5d79bf9`→`c848ed2` (comments aside) is three lines: the `_atlas_sync_timeout` var + wrapping the two existing docker calls in `with_timeout`. The docker argv is unchanged — AC-3 exact-argv test still green (`--pull=never`, rw `/repo`, digest-from-`.mcp.json`, `index --repo /repo --since auto`). No gate altered; the other 7 ACs re-run green (19/19 autosync tests pass).

### Revised verdict: GO — `c848ed2` is `verified`-ready
F-1 (the sole condition from the first pass) is closed the way it should be, and its regression test is real (reproduced RED against pre-fix). All 8 ACs pass on the shipped commit; scope, schema, and version are intact. **maker != checker is satisfied on `c848ed2`** (`maker: vivi`, `checker: vigil`, distinct; I did not author it). Clear to transition to `verified`.

*VIGIL — second-pass confirm on the shipped commit c848ed2.*
