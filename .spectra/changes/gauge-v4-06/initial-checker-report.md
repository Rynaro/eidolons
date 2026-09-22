# V4-06 independent acceptance review — changes required

Mission VIGIL-20260922-V406. Distinct checker `v4_06_review`; read-only source authority. Initial input was the bounded mission, canonical specifications, candidate source/tests and installed VIGIL resources. No maker conversation/history was read. Later coordination disclosed localized findings to root and received notice that root committed the unchanged candidate and was preparing native macOS checks; that coordination is not independent corroboration. CRYSTALIUM unavailable. No real model calls, paid/live probes, or network inside tests. Scratch probes modified only their generated data/package output.

Acceptance is withheld for the frozen candidate. Three reproducible findings remain. Baseline green tests do not cover these cases. I yield source and repair authority to a different actor.

## Candidate and scope

Initially uncommitted candidate based on `50e8553423dd19620e75a5a0d98a7ba4a9418528`; root committed it during review as `13d383bafe68d5e8b5c045212761d8ec4af89046`. `candidate-hashes.json` records initial file SHA-256s; `freeze-verification.json` confirms every initially hashed file remained byte-identical. `candidate-identity.txt` records original status. Initial maker manifest was treated only as scope, never acceptance.

Read the V4-06 spec and accepted store decision, controller/store/contracts/legacy implementations, existing tests, Bash authority guard, command shim, packaging script and CI workflow. The installed VIGIL instructions require reproduction before attribution, competing hypotheses and counterfactual controls. This is a read-only review: no repair patch was applied, and source-causal conclusions below are high-confidence hypotheses supported by controls rather than claims of a verified code repair.

## [FINDING-001] P1 — Missing authority marker reopens legacy writes after promotion

**Observed twice, confidence H.** After a valid Bash append, controller init, explicit import and promotion, status reports an active Go root. Bash correctly refuses another append while `.writer-authority.json` exists. Delete only that marker in scratch state: Go fixture execution refuses, but the same valid Bash writer now succeeds. Restore the exact original marker: Bash refuses again, while Go status succeeds with one imported historical event although the legacy journal now contains two. Thus the active DB and historical files silently diverge, violating fail-closed handling of incomplete/disagreeing authority and the no-fallback-write contract.

Localization: `cli/src/ledger.sh:70-76` decides authority only from marker presence (apart from the reserved controller directory name). `gauge/internal/controller/authority.go:248-277` checks active marker/DB identities but does not detect the intervening legacy append after the marker is restored.

Minimal sequence: `ledger record --run-id legacy --type probe --event-id initial`; `gauge init`; `gauge import --root legacy`; `gauge promote --root legacy`; remove `.eidolons/.ledger/legacy/.writer-authority.json`; `ledger record --run-id legacy --type probe --event-id after-marker-loss`. The last command exits 0. Run in scratch only.

Evidence: `independent.py`, `independent.log` (full argv, cwd, exit, stdout, stderr for both runs), `independent-summary.log`. Counterfactual I-001 restores only the saved marker bytes and flips Bash append from permitted to refused. It also demonstrates that marker restoration alone hides the inventory disagreement from Go status. Competing hypotheses before intervention: marker absence opens the gate; promotion never transferred authority; wrong binary/invalid fixture prevents reaching the intended writer. Active Go status and present-marker refusal eliminate the latter two.

Recommended downstream outcome: make a missing per-run marker in an already-transferred root a recovery-required state for Bash as well, preserving opt-out behavior for genuinely legacy roots. Add a loss/restoration regression and ensure recovered authority cannot hide changed legacy bytes. No concrete implementation is prescribed or verified here.

## [FINDING-002] P2 — Imported unknown harness history is treated as reconstructable fixture state

**Observed twice, confidence H for behavior.** Import and promote an ordinary legacy journal. Status records `legacy:true`, `harness:native-unobserved`, unknown historical profile/method, but `adapter:fixture@1`. `gauge replace --root legacy --worker reconstructed-history --reconstruction fixture` exits 0 and changes worker, invocation and context. No historical adapter observation or reconstruction capability has been established. The explicit fixture flag supplies a requested mode, not evidence that this imported task was a supported fixture. This contradicts the requirement that unsupported reconstruction stay blocked.

Localization: `gauge/internal/controller/controller.go:76-85` leaves the default fixture adapter in imported roots; `:316-340` authorizes reconstruction using that label. Source dependency: constructor fixture default → stored imported manifest → `Replace` adapter predicate → rewritten execution identities.

Evidence: both runs and controls in `independent.py`, `independent.log`, `independent-summary.log`. Controls: a genuinely controller-created fixture root can replace successfully; replacement without reconstruction support is rejected. The comparison isolates inherited fixture labeling from an entirely missing reconstruction gate. No source intervention was permitted; a repaired imported-adapter gate remains unverified. Hypotheses considered before controls: inherited fixture label; flag overrides all adapter support; replacement ignores root type entirely. Source inspection and controls support the first as the causal hypothesis.

Recommended downstream outcome: preserve unknown imported adapter provenance and block reconstruction until a qualified adapter establishes capability, while retaining genuine fixture replacement. Preserve original legacy bytes and lower grades.

## [FINDING-003] P2 — Repeating the standard package target fails on copied dependency licenses

**Observed twice, confidence H.** Fresh `make gauge-package GAUGE_OUT=/evidence/package` exits 0 and includes required licenses. Its bbolt and x/sys license outputs have mode 0444, inherited from the read-only Go module cache. Repeating exactly the same target exits 2: `cp: cannot create regular file '/evidence/package/licenses/go.etcd.io_bbolt-LICENSE': Permission denied`. The default output path is stable, so normal repeat packaging is affected too. Failure occurs after rebuilding/replacing the executable, leaving a partially refreshed package.

Localization: `scripts/gauge-build.sh:25-30`, especially the plain `cp` into a previously copied non-writable destination.

Evidence: `package.log`/`.exit` (fresh success), `probe-build.log`/`.exit` (first repeat failure), `package-repeat-2.log`/`.exit` (second failure), `package-mode-control.log`/`.exit` (success). Counterfactual I-003 changes only generated license output permissions with `chmod u+w /evidence/package/licenses/*`; the same package target then succeeds. Source remains unchanged. Competing explanations considered: read-only source mount; incomplete module cache; copied license output permissions. Fresh success and permission-only flip eliminate the first two. The executable reproducibility control (`cmp` independent build output) passes separately.

Recommended downstream outcome: permit deterministic refresh of package-owned license outputs, and test the package target twice into its normal output directory. No repaired implementation is claimed.

## Execution evidence

Qualified image: `eidolons-gauge-go-qualified:local`, supplied manifest `sha256:d9b4537412ed447276fbf3a745c3c953f254d412e70da57b5888831a0d61c795`. Actual runtime `go1.27.1 linux/arm64`, Bats 1.11.1, jq 1.7 (`runtime.log`). Containers had no network, read-only source/root, dropped capabilities, no-new-privileges, executable tmpfs /tmp, dedicated writable module/build caches, `GOTOOLCHAIN=local`.

- All nine V4-06 named Bats anchors: exit 0 (`anchors.log`, `anchors.exit`). Each invokes matching race-enabled Go tests.
- Full `go test -mod=readonly -race -count=1 -v ./...`: exit 0 (`go-race.log`, `go-race.exit`). Includes callback rollback, schema refusal, bounded lock wait, independent DB reopen, and child-process termination before/after commit with exactly-once retry.
- All five V4-04 journal and nine V4-05 completion compatibility tests: pass in `compat.log` entries 1–14.
- Initial combined compatibility command exit 1 solely because nine install tests could not follow the worktree's host-absolute Git metadata path. This is an invalid installation runner setup, not a candidate failure. After mounting that Git metadata read-only, all nine install tests pass (`install-corrected.log`, exit 0).
- Installation with Go absent from PATH: positive `command -v go` absence check followed by end-to-end install test; exit 0 (`no-go-install.log`, `.exit`).
- Fresh package target and required license outputs: pass. Independently built executable compares byte-identical (`build-b.log`, `reproducible.exit` 0). Repeat packaging has FINDING-003.
- Native host Bash 3.2.57 authority guard control: pass (`bash32-authority.log`, exit 0), running `LEDGER_TEST_BASH=/bin/bash python3 .../gauge/tests/authority.py`. This is a Bash compatibility check, not native Go/macOS store qualification.
- Shellcheck unavailable in qualified container: exit 127 (`shellcheck.log`); no lint acceptance inferred here. Root independently reports lint but those results are outside this checker's execution.
- First Docker invocation redundantly passed `bash` to the image's Bash entrypoint and exited 126 (`docker.log`). Corrected `--entrypoint /bin/bash` run is the evidence above; the launch failure is not behavioral red.

## Evidence limits and unresolved gates

No hosted CI or native macOS Go execution observed by this checker. Root is obtaining native evidence separately; public CI remained pending according to coordination. Linux tests do not establish macOS behavior, power-loss durability, remote filesystem qualification or production/live provenance.

Source inspection confirms sync defaults (no NoSync), schema guards in Stage/Activate/Update, one shared DB, per-root append exclusion, copied decoded transaction state, exact jq canonicalization with LF, self-attested imported history, fixture-only receipts, unavailable current acceptance and no runtime Go auto-download/fallback shim. Those are source findings; green tests support only their enumerated exercised cases.

Existing promotion interruption tests use error-return cuts after pending publication and DB commit, releasing the lock cleanly. They do not independently process-kill a promoter before/after each final-marker publication boundary. Existing concurrent import/promotion controls mostly use goroutines; store kill tests use real children but do not constitute all requested independent-process authority handoff permutations. These remain qualification gaps in addition to the reproduced failures; do not claim the entire process-interruption matrix passed. Native Bash lock interruption tests did execute in Linux journal compatibility, but cannot substitute for Go promoter interruption evidence.

Intervention budget used: 3 conceptual scratch-state controls (marker restore, reconstruction controls, license mode correction), each with repeated deterministic reproduction where applicable; 0 source edits. No verified patch. Three ruled-out alternatives: failed promotion/wrong writer for FINDING-001; no reconstruction flag gate for FINDING-002; missing dependencies/read-only source for FINDING-003. Source commit attribution is to the frozen candidate commit above, with no maker-intent inference.

Handoff: root to a fresh repair actor (APIVR-Δ/Vivi), then distinct verification of changed files and the uncovered boundaries. Primary artifact `/private/tmp/v4-06-review-probes/review-report.md`; reproductions and logs beside it. No repair should be treated as accepted from this report.
