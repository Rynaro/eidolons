# V4-06 repair re-review — three original findings resolved in tested scope

Checker `v4_06_review` (VIGIL), source read-only, 2026-09-22. Re-review used the frozen candidate based on commit `13d383bafe68d5e8b5c045212761d8ec4af89046`, four source/build file edits and two additive regression files. `candidate-status.txt` records the exact paths; `candidate-hashes.json` records the reviewed bytes; `freeze-verification.json` confirms no initially hashed files changed during this pass. Original tests remained unchanged. No maker conversation or broad reasoning was read. Root coordination concerning its separate native/CLI checks and pending follow-up is disclosed below. No source edits, real model calls, paid/live probes, or test network.

**Result:** F001–F003 are resolved in independently exercised cases. No further implementation failure was reproduced. Complete campaign acceptance remains pending the narrow promotion-barrier test follow-up, continuous package-repeat wiring, and root's independent integration/hosted-evidence accounting. This review does not claim hosted CI, native Go/macOS qualification, or full campaign completion.

## F001: missing marker / divergent legacy inventory

Repair source: `cli/src/ledger.sh` denies Bash writes when the persistent per-root controller claim exists, regardless of marker loss. `gauge/internal/controller/authority.go` requires matching claim/marker/DB identity for active access, checks legacy inventory on active operations, and can explicitly recover a matching claim without a run marker. Claim creation precedes pending-marker publication. Unrelated roots and staged imports receive no claim.

Independent external CLI probes (`independent.py`) passed twice, with complete argv/exit/stdout/stderr in `independent.log`:

- Promote valid legacy history, remove only the marker, and retry the original Bash append: refused. Go fixture mutation also refused.
- Explicit recovery restores matching active authority while preserving logical status and original legacy/marker/claim bytes. Exact marker restoration without recovery also returns unchanged history to a valid readable state.
- Delete, corrupt, future-version, mismatch or symlink the persistent claim while preserving the marker: Bash writes and Go status/promote/recover/fixture all refuse. The failing operations preserve database and authority/history file bytes. Restoring the original claim restores the positive control.
- Append a genuinely new, correctly sealed jq-canonical legacy event outside the controller: Go status/promote/recover/fixture all refuse; the failed operations do not rewrite the DB or legacy bytes. This is actual valid-chain inventory drift, beyond whitespace-only drift.
- Ordinary and merely staged legacy roots remain Bash-writable under the same shared controller DB; staging does not publish a claim, and promotion refuses after that staged inventory changes.

A separate nonroot fault probe (`claim-publication.py`) passed twice. A jq barrier holds a real promoter after inventory validation with its append lock owned. The parent changes only the run-directory mode to 0555. The persistent claim publishes in the still-writable controller directory; creating the pending run marker fails with permission denied. The DB bytes remain exactly equal to the staged pre-promotion DB, the claim exists and marker does not, and both Bash writes and Go managed inspection refuse. The parent waits for the process and synchronous child to exit, restores directory permissions, removes only the retained empty append lock, then explicitly recovers. Recovery and Go status succeed; Bash writes remain refused. Full command/error evidence is `claim-publication-commands.log`; summary `claim-publication.log`, exit 0. This is an observed filesystem write-failure boundary, **not** a process kill in the claim-only window.

No simultaneous destruction of all authority proofs or hostile-filesystem security guarantee is inferred; the contract explicitly concerns cooperating local writers. Missing/corrupt individual claims and markers were exercised.

## F002: unsupported reconstruction of imported history

Repair source: `controller.go` records imported adapter as `unknown` and independently rejects every `Legacy` root in `Replace`, including historical roots mislabeled `fixture@1`.

Independent probes passed twice:

- Fresh imported status reports adapter `unknown`.
- Worker and environment replacement of the imported root are refused without byte changes.
- A separate scratch Go helper opens the real store and deliberately restores the old imported `fixture@1` label through the typed transaction API. Both worker and environment reconstruction are still refused without byte changes. Helper source/build logs are in `helper/`, `helper-build.log` and `.exit`.
- Genuine fixture-root worker and environment replacements succeed in independently invoked CLI processes and retain root/generation/inventory/policy/intent/evidence/candidate links. The retained fixture receipt remains linked.

No requested adapter/model setting is treated as a newly observed historical identity.

## F003: repeat packaging

Repair source: `scripts/gauge-build.sh` uses `install -m 0644` for repository, toolchain and dependency licenses.

`gauge/tests/package-repeat.sh` executed successfully in the qualified container as UID501/GID20, with a script assertion that UID is nonzero. It packages, copies the first executable, forces existing license files to 0444, packages again into the same directory, compares executables byte-for-byte, and checks required license files. Both package commands and comparison passed (`nonroot-package.log`, exit0). A separate fresh package for the independent probes also passed (`package.log`, exit0). F003's original permission failure did not recur.

**Continuous coverage gap:** the new package-repeat script was not invoked by either `make gauge-test` or `.github/workflows/gauge.yml` in the frozen reviewed bytes. Root agreed to wire it into native Gauge CI as a narrow follow-up. That change is outside this accepted source snapshot and must be checked separately.

## Executed suite and actual process-interruption coverage

The qualified Linux/arm64 image ran as an ordinary user with network disabled, read-only root/source, dropped capabilities, no-new-privileges, executable /tmp tmpfs, dedicated writable caches and `GOTOOLCHAIN=local`. Main commands are in `run.sh`; all exits are adjacent `.exit` files.

- All nine named V4-06 anchors passed (`anchors.log`, exit0).
- Full `go test -mod=readonly -race -count=1 -v ./...` passed (`go-race.log`, exit0), including every additive repair test and existing store callback/process rollback and atomicity tests.
- Nonroot package-repeat passed, as above.
- Independent repaired-expectation probes passed twice (`independent-summary.log`, exit0).
- Independent claim-only publication write-failure/recovery probe passed twice, as above.

I read the new `repair_test.go` process-helper implementation and verified its execution log rather than accepting its test names as evidence. The parent starts a real OS child, waits for READY, sends Kill, waits/reaps it and checks recovery. At pending and committed barriers, an independent competing promoter and synchronous Bash writer refuse; after kill, status and recovery refuse unresolved ownership; only after explicit operator lock cleanup does recovery succeed. Imported bytes/IDs/grades remain unchanged. Logs record killed/reaped PIDs at all four cases.

Exact boundaries currently observed:

| Case | Actual position |
| --- | --- |
| before | Before the child calls Promote; no promotion work has begun. |
| pending | After pending marker publication, inside existing Cut callback while append ownership remains held. |
| committed | After DB activation commit, inside existing Cut callback while append ownership remains held. |
| published | After Promote returns successfully, including deferred append-lock release. |

Consequently, these do not prove process-kill behavior immediately after claim publication/before pending-marker publication, or after final-marker publication/before lock release. The independent permission-failure probe covers fail-closed recovery for the former persisted state but is not a substitute for the requested process-kill claim.

**Remaining exact-boundary evidence gate:** add narrow existing-Cut phases immediately after durable claim publication and after final marker publication before function return/deferred release; add independently killed/reaped child cases there. Re-run the affected tests and their controls, then record the precise observations. Root received this recommendation and will coordinate a fresh writer. No production environment-switch hooks or source patch were introduced by this checker.

## Invalid scratch assertion retained transparently

The first independent repaired probe incorrectly required byte-identical bbolt DB after successful explicit Recover. Recover legitimately commits an activation transaction even when logical root state is unchanged. That overly strict scratch assertion failed after successful recovery. The corrected oracle compares complete logical status plus exact legacy/claim/marker bytes; refused operations still require all state bytes unchanged. Original invalid-probe summary and commands are retained as `independent-overstrict-recovery.log` and `independent-overstrict-recovery-commands.log`; this is not reported as a candidate failure or hidden passing run.

## Coordination and limits

Root reported a separate native macOS full Go race pass and was running native packaging plus full legacy CLI regression. Those are root-owned evidence, not execution by this checker, and must be integrated by root. Public push/hosted CI remained blocked and is not inferred from local success. No process-kill test establishes power-loss durability, and no network/remote filesystem or live-production qualification is claimed.

The distinct initial artifact-only review remains preserved in the parent evidence directory. This follow-up necessarily knows its own prior findings and localized root coordination; it is not a statistically independent blind trial. Source remained frozen throughout this pass, as checked by SHA-256.

Handoff to root: original findings closed within the stated observations; hold final campaign acceptance for the exact-boundary test/CI wiring follow-up and integration evidence. Reviewer yields before additional writes. No repair patch or source change was authored by this reviewer.
