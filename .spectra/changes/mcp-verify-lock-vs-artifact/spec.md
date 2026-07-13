# mcp-verify-lock-vs-artifact

**Tier:** full (files_touched=6, rubric=6/12, tradeoff_present=true → route 0→1→2→3→4)
**Maker:** vivi **Checker:** kupo (C4 maker≠checker)
**Deliberation:** FORGE, confidence 0.86
**requires_checker: true** — this changes `mcp install`'s failure semantics. Installs that
today silently "succeed" will begin to fail. That is the point, and it is user-visible.

## Problem

The v2.10.0 CHANGELOG filed this as "nothing reconciles `eidolons.mcp.lock` against
`.mcp.json`" and promised an `eidolons mcp verify` follow-up. That framing was **too
generous**. Three findings, each reproduced live, escalate it:

### P1 — The lock-lie is still MANUFACTURABLE, in one command

```
$ printf '{ "mcpServers": ' > .mcp.json          # any invalid/failed-write state
$ eidolons mcp install crystalium
⚠ .mcp.json is not valid JSON — skipping crystalium server registration
$ echo $?
0                                                 # <- "success"
$ grep -A2 'name: crystalium' eidolons.mcp.lock
  - name: crystalium
    version: "1.8.0"                              # <- the lock records an install
```

`.mcp.json` is untouched. The install did not happen. **The lock says it did, and the
command exits 0.** Path: `_mcp_merge_into_json_file` (`lib_mcp.sh`) `warn`s and
`return 0`s on all three failure modes — template missing, target not valid JSON, jq
merge failed — and `mcp_driver_oci_image_install` then calls `mcp_lock_upsert`
**unconditionally**, building the entry from the *catalogue* rather than from the
artifact it just (didn't) write.

This is not a historical artifact. It is the factory that produced the atomos drift.

### P2 — The lie is SELF-SEALING: the normal repair verbs refuse to act

With a lock claiming crystalium is installed and a valid-but-empty `.mcp.json`:

| command | `.mcp.json` servers after |
|---|---|
| `eidolons mcp install crystalium` | **0** |
| `eidolons mcp sync` | **0** |
| `eidolons mcp upgrade crystalium` | **0** |
| `eidolons mcp install crystalium --force` | 1 |

All three no-op because each gates on the **lock** (`mcp_use.sh` / `mcp_sync.sh` version
no-ops; `lib_mcp.sh`'s already-wired digest early-exit). Once the lock is wrong, every
ordinary path reads it, believes it, and declines to act. The drift was not merely
undetected — it was **unfixable by the documented commands**.

### P3 — `mcp images`' DRIFT column is a TAUTOLOGY, not a wrong axis

```bash
_full_ref="${_image}@${_pinned}"                                   # ref BUILT FROM the pin
_repo_digest="$(docker image inspect ... "$_full_ref")"
_local_full="${_repo_digest##*@}"
if [ "$_local_full" = "$_pinned" ]; then _drift="no"; else _drift="yes"; fi
```

You cannot inspect `img@sha256:X` and be handed back `sha256:Y`. `LOCAL` **is** `PINNED`
by construction; `_drift="yes"` is unreachable. The only escapes are `unknown` (docker or
image absent). Confirmed live: with `.mcp.json` wired to atomos **0.1.0**, `mcp images`
printed **`DRIFT: no`**.

A column that is *actively reassuring* during the exact drift it names is worse than no
column. Same species as the fake-docker shim fixed in v2.10.0.

### Every existing check is green during the drift

| check | reports | reality |
|---|---|---|
| `mcp images` | `DRIFT: no` | wired digest is 0.1.0 |
| `mcp list` | `INSTALLED 0.2.0  UPDATE? no` | reads the **lock** — repeats the lie as truth |
| `doctor --deep` | `✓ atomos: healthy` · `✓ All installed MCPs at catalogue stable` · exit 0 | serving 0.1.0 |

**Mechanism, in one line: everything trusts the lock; nothing verifies the artifact.**

## The structural invariant (F5 — this, not `verify`, is the actual fix)

> **A lock entry is a RECEIPT, not an ORDER.** `installed_at` may only be stamped for
> `<name>` after **re-reading `<target>` and observing the exact identity the entry
> claims** (digest, or command path). If the artifact cannot be read back and confirmed,
> the install **fails**. It does not record.
>
> **Nothing may assert "installed" except the artifact itself. The installer is not
> permitted to be the witness to its own success.**

`verify` is only the **detector**; the invariant is the **cure**. Ship both — `verify` still
must exist to catch states created *before* it (hand-edits, bad merges, a lock written on
another machine and `git checkout`ed here).

## Decisions (FORGE)

- **F1 — Authority.** The lock is *intent*; `.mcp.json` is *effect*. `verify` reports both
  and lets the disagreement pattern name the culprit — the catalogue is an invertible
  digest↔version map, so a wired digest can be resolved back to a published version.
  **`verify` NEVER repairs.** A checker that can make its own subject pass is not a
  checker (this repo's own ESL makes maker≠checker a P0). The repair already exists
  (`mcp install <n>@<ver> --force`); `verify` **prints that command** and stops.
- **F2 — Exit codes. Non-zero on mismatch; `doctor` goes RED in the FAST checks.**
  Fail-open is a **hot-path** doctrine (ECM fires every prompt, autonomously). `verify` is
  explicitly invoked by a human or CI *waiting for an answer*; **a diagnostic that cannot
  say NO is a `printf`.** Importing fail-open here would rebuild the very defect we are
  fixing. Precedent: doctor's check 7b already hard-errors on a `.mcp.json`-vs-reality UID
  mismatch — serving an entirely different image version is strictly more severe. The
  check costs one `jq` read of a file doctor already opens: no docker, no network. Burying
  a free, high-value check behind `--deep` is how it never runs (cf. "the drift check that
  never ran").
- **F3 — Fix the lying column.** `mcp images` gains a **`WIRED`** column; **`DRIFT` is
  redefined to wired-vs-locked** (needs no docker). Compat cost is nil: the current field
  is a constant, and you cannot break a consumer of a constant in any way that matters.
  `--json` gains `wired_digest` + `drift_axis: "wired_vs_locked"`. `mcp images` stays
  exit 0 always — it is an inventory, not a gate; the teeth live in `verify`/`doctor`.
- **F4 — Scope: A, B, C, D in; E (`--probe`) opt-in.** Default `verify` **executes
  nothing, ever** — that property makes it safe against an untrusted checkout.

## Requirements

### The cure (install may no longer lie)
- **R1** — `_mcp_merge_into_json_file` SHALL return **non-zero** on each of its three
  failure paths (template missing / target not valid JSON / jq merge failed). It SHALL
  still not clobber the target — the fix is to **refuse to lie about it**, not to
  force-write. Leave `.mcp.json` alone, leave the lock alone, exit non-zero.
- **R2** — The oci-image install driver SHALL **read back** `.mcp.json` after the merge and
  require the observed wired digest to equal the digest it intended, **before**
  `mcp_lock_upsert`. On mismatch or unreadable target: **no lock write**, non-zero exit.
  (This is axis A run at install time, so the installer's gate and `verify` share one code
  path — if the read-back helper ever rots, installs break **loudly** instead of lying
  quietly.)
- **R3** — The binary install driver SHALL likewise confirm `.mcp.json`'s `command` equals
  the intended `target` before upsert.

### The detector
- **R4** — A new `eidolons mcp verify [<name>]` SHALL compare, per lock entry:
  the digest wired in `.mcp.json` vs `lock.integrity.value` (**the bug**).
- **R5** — It SHALL also validate the lock **on its own terms**: `lock.integrity.value` vs
  `roster/mcps.yaml` `releases[lock.version].digest`.
- **R6** — Orphans, **asymmetrically**: locked-but-not-wired with `.mcp.json` *absent* is
  the normal fresh-clone state → **INDETERMINATE**, never block. Wired-but-not-locked →
  WARN, and **only for catalogue-known servers** (a user's hand-added MCP is ignored
  entirely, never mentioned).
- **R7** — An unpinned (mutable-tag) wired ref SHALL WARN by default, BLOCK under
  `--strict`, and SHALL NEVER be scored as a pass — it is the state in which R4 becomes
  unverifiable.
- **R8** — `kind: binary` (`integrity.algo: none`) is **not exempt**: compare `.mcp.json`'s
  `command` to `lock.target` (version drift is visible in the `junction@<ver>` cache path),
  and require the target to exist and be executable.
- **R9** — `doctor` (**fast** path, not `--deep`) SHALL surface BLOCK findings in a new
  "MCP wiring integrity" section and **exit non-zero**. It SHALL NOT go red on
  INDETERMINATE. The existing "MCP catalogue drift" check (lock vs `pins.stable`) is a
  *different question* ("you could upgrade" vs "you are lying") and stays advisory.
- **R10** — `mcp images` `DRIFT` SHALL be wired-vs-locked and SHALL be computable with
  **docker absent**.
- **R11** — bash 3.2; `shellcheck -x -S error` clean; all logs to **stderr**, stdout
  reserved (`mcp verify --json 2>/dev/null | jq empty` must pass).

## CLI contract

```
eidolons mcp verify [<name>] [--json] [--strict] [--probe] [--project-root PATH]

Exit codes:
  0  verified (WARN findings may be present)
  1  >=1 BLOCK finding — the host is not serving what the lock claims
  2  usage error
  3  INDETERMINATE — could not verify (no .mcp.json, unreadable catalogue, no jq).
     NOT a pass. --strict promotes 3 -> 1; `|| [ $? -eq 3 ]` accepts it explicitly.
```

**Exit 3 is load-bearing.** If "no `.mcp.json`" returned **0**, `mcp verify` in CI on a
fresh clone would be **green while verifying nothing** — the original bug class reborn
inside its own fix. If it returned **1**, every clean checkout goes red, someone makes the
check advisory to shut it up, and we are back where we started one release poorer. It must
be *visibly* indeterminate, and print the literal word `INDETERMINATE` — never `OK`, never
`FAIL`.

## Check table

| ID | Compares | Kind | Severity |
|---|---|---|---|
| `V-OCI-WIRED-MISMATCH` | wired digest vs `lock.integrity.value` | oci | **BLOCK** |
| `V-OCI-WIRED-MALFORMED` | server entry has 0 or ≥2 distinct `@sha256:` | oci | **BLOCK** |
| `V-LOCK-INCOHERENT` | lock digest resolves to a *different published* version than `lock.version` | oci | **BLOCK** |
| `V-LOCK-UNPUBLISHED-DIGEST` | lock digest matches no published release | oci | WARN (`--build-locally` is supported) |
| `V-LOCK-PLACEHOLDER` | lock digest is the all-zeros placeholder | oci | **BLOCK** |
| `V-NOT-WIRED` | locked, `.mcp.json` absent | both | **INDET (→3)**; `--strict`: BLOCK |
| `V-PARTIALLY-WIRED` | locked, absent from `.mcp.json`, but other eidolons servers present | both | WARN (partial-write signature) |
| `V-UNLOCKED-SERVER` | catalogue-known server wired, no lock entry | both | WARN |
| `V-UNPINNED-TAG` | wired ref is a mutable tag | oci | WARN; `--strict`: BLOCK |
| `V-BIN-WIRED-MISMATCH` | `.mcp.json` `command` vs `lock.target` | binary | **BLOCK** |
| `V-BIN-TARGET-MISSING` | `lock.target` exists and is `-x` | binary | **BLOCK** |
| `V-PROBE-SURFACE` (`--probe`) | live `tools/list` vs catalogue `exposes_tools.list` | both | BLOCK when probed |

**Why B (`V-LOCK-INCOHERENT`) is not redundant with A:** a lock saying `version: 0.2.0`
while carrying 0.1.0's digest, with `.mcp.json` faithfully wiring that same 0.1.0 digest —
**A passes.** The artifact matches the lock perfectly. The lock is still provably corrupt.
B is the only axis that convicts the lock on its own terms.

**Why E (`--probe`) is opt-in, not default:** if A holds, same digest ⇒ same image ⇒ same
tools. The residue is real but narrow (the digest is not the *invocation*; and
`exposes_tools.list` is itself an unverified catalogue claim) — and that residue is a
**constant per digest**, so re-deriving it on every user machine forever is misplaced cost.
Its systematic form belongs in nexus CI at digest-bump time, where a wrong answer blocks a
bad roster entry *before it reaches a user*. Filed as a follow-up.

## Acceptance checks

**AC-0 — Run the whole AC suite against today's `main`, unfixed, and show the RED pattern.
An AC that is green on unfixed code is not an AC.**

**AC-0b — Two-sidedness is MANDATORY.** Every check must flip **GREEN when the seeded
defect is removed** and **RED when re-seeded**, nothing else changed. A one-sided AC ("it
fails on the bad fixture") is satisfiable by `exit 1`. This is exactly the property the
DRIFT column fails: **no input exists that makes it say `yes`.**

**Shared fixture (`FIXTURE-drift`)** — builds itself from the real catalogue (reads both
digests out of `roster/mcps.yaml`), so a future digest bump cannot rot it:
lock = atomos `0.2.0` + catalogue's 0.2.0 digest; `.mcp.json` wires the catalogue's **0.1.0** digest.

| AC | Assertion | Teeth |
|---|---|---|
| **AC-1** | `mcp verify` on FIXTURE-drift → exit **1**, names both digests + the remedy | Mutation: wired == locked → **0**; flip one hex char → **1**. Two-sided. |
| **AC-2** | `mcp images` on FIXTURE-drift prints `DRIFT: yes`; `--json .drift == "yes"` | RED today (prints `no`). Pair with clean fixture → `no`: proves not a constant **in either direction**. |
| **AC-2b** | Same, with **docker absent from `PATH`** → `drift` still `"yes"` | **The tautology killer.** Wired-vs-locked needs no docker, so this **cannot be passed by tuning the old comparison** — it mechanically proves the *axis* changed, not the sensitivity. |
| **AC-3** | Lock says `0.2.0` but carries 0.1.0's digest; `.mcp.json` wires that same 0.1.0 digest (**so A passes**) → exit **1**, `V-LOCK-INCOHERENT` | Kills the "just do A" shortcut: an A-only impl is **green on a provably corrupt lock**. |
| **AC-4** | junction: lock `0.4.0` / target `…junction@0.4.0/junction` (created, `chmod +x`); `.mcp.json` wires `…junction@0.2.0/junction` → exit **1** | Re-point → green. Then delete the target binary → red with a **different code** (`V-BIN-TARGET-MISSING`). Distinct codes required, else one `exit 1` masquerades as two checks. |
| **AC-5** | `eidolons doctor` (**fast**, no `--deep`) on FIXTURE-drift → **non-zero** | RED today (exits 0). Pair: clean fixture → doctor **0**. **And assert doctor still prints `✓ All installed MCPs at catalogue stable` on FIXTURE-drift** — different axis, still true. A test that passes by making Check 8 red is testing the wrong thing. |
| **AC-6** | Valid lock, **no `.mcp.json`** → `mcp verify` exits **exactly 3**, prints `INDETERMINATE`; `doctor` exits **0** | Assert the literal number (`-eq 3`), never `-ne 0`. |
| **AC-7** | Same fixture `--strict` → **exactly 1**. FIXTURE-drift `--strict` → 1. Clean `--strict` → 0. | Three exit codes from one flag; a constant fails ≥1. |
| **AC-8** | Clean lock+wiring **plus** a hand-added `mcpServers.my-own-thing` → exit **0**, output does **not contain** `my-own-thing` | Asserts an **absence**. Kills a naive orphan check that warns on every unknown server — the shape that gets the verb muted. |
| **AC-9** | `.mcp.json` wires `…/atomos:latest` → default exit **0** + WARN; `--strict` → **1** | Same fixture, opposite exit codes: a constant-exit impl fails one. |
| **AC-10** | `mcp verify --json 2>/dev/null \| jq empty` passes; the `V-OCI-WIRED-MISMATCH` finding is `severity: block`; `.summary.exit_code == 1` | Enforces the stdout/stderr P0 — RED against any impl that echoes a status line to stdout. |
| **AC-11** | **THE INVARIANT.** `.mcp.json` invalid JSON → `eidolons mcp install crystalium` must exit **non-zero** AND the lock must **NOT** gain a crystalium entry | **RED today: exits 0, writes nothing to `.mcp.json`, writes the lock entry anyway** (reproduced live). Teeth: repair the JSON → install exits 0 **and** the lock gains the entry. **A maker who ships `verify` without AC-11 has installed a smoke detector and left the gas on.** |
| **AC-12** | `shellcheck -x -S error` clean; new bats green on macOS **bash 3.2** | MUST |
| **AC-13** | `mcp verify --probe` exits **2** on a clean project (assert the literal 2), **still 2 with stderr discarded**, and emits **no verdict** first | Added after the first implementation accepted `--probe` as a no-op that merely info'd to **stderr** — which CI discards, so it would exit 0 on a clean project and read as "the tool surface was verified" when nothing was probed. That is this change's own disease, inside the verb that enforces the cure. Mutation-verified red against the accept-and-no-op draft. |
| **AC-14** | **THE R2 GATE.** A temp nexus whose atomos template hardcodes 0.1.0's digest instead of the `__IMAGE_DIGEST__` placeholder → installing `atomos@0.2.0` writes **valid** JSON (so R1 *cannot* fire) wiring the **wrong** image → install must exit non-zero and the lock must gain **no** entry. | **AC-11 does NOT pin R2.** Its fixture is invalid `.mcp.json`, which trips R1 and short-circuits *before* the read-back is reached. Proven: neutering `_mcp_oci_confirm_wired` to `return 0` — deleting the F5 invariant's core gate — leaves **every AC-11 green and the whole suite passing**. AC-14 is the only test that goes red. R1 catches "the merge failed"; **R2 catches "the merge succeeded but the artifact does not say what we intended"** — the general case, and the one F5 actually names. Two-sided partner: honest template → install succeeds and the lock records it. |

## Out of scope

- `--fix` / auto-repair. If ever added, the only acceptable form is `exec mcp install
  <n>@<locked-ver> --force`, echoing the command, behind an explicit flag, never default.
- Systematic `--probe` in nexus CI (catalogue `exposes_tools.list` vs the real image at
  digest-bump time). Correct and wanted — **separate change**, and it belongs in
  `roster-health`, not on user machines.
- `mcp_upgrade.sh` / `mcp_refresh.sh` were not read end-to-end. They likely share the
  write-from-intent shape; if so that **adds** to the AC-11 surface. The maker must check
  and report, not silently narrow.

## Reversal conditions

- **doctor-fast → `--deep`** if maintainers hold the fast path must never fail on a state
  the user did not create (`git checkout` of a foreign lock). Move it; do **not** soften it
  to advisory.
- **`drift` redefinition → a new field (`wiring_drift`)** if any real consumer of `mcp
  images --json .drift` is found. None exists today, and the field is a constant.
- **`--probe` → default** if it catches a second class of defect that A+B miss in the wild
  (the "digest is not the invocation" hole firing for real).
