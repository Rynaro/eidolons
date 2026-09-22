# V4-06 final bounded checker verdict

**Accepted within the tested local controller/fixture scope.** Original findings F001–F003 are resolved, and the final exact-publication process-kill and continuous package-repeat coverage gaps are closed. No unresolved implementation finding remains from this review. This is not hosted-CI, publication, live-model, remote-filesystem or power-loss qualification.

Checker: VIGIL actor `v4_06_review`, 2026-09-22, read-only source authority. This final pass reviewed only the bounded three-file follow-up and carried forward the independently exercised original repairs from `/private/tmp/v4-06-review-probes/final/review-report.md`. It did not re-review unrelated work. No repository writes, real model calls, paid/live probes or network inside tests occurred.

## Frozen candidate and independence

The candidate is `/private/tmp/eidolons-gauge-v4-06`, based on commit `13d383bafe68d5e8b5c045212761d8ec4af89046` plus the previously reviewed repairs and the final follow-up. `source-verification.json` independently matches all three supplied final follow-up SHA-256s and verifies that all 163 previously captured test/fixture files remain byte-identical. `candidate-hashes.json` records the complete files inspected at this final boundary. Compared with the prior reviewed implementation, only existing `.github/workflows/gauge.yml` and `gauge/internal/controller/authority.go` changed; the new `publication_cuts_test.go` is additive.

Reviewed follow-up hashes:

- `gauge/internal/controller/authority.go`: `774f377b3c456f7e87c48ac19a2c86222ce2a94a3ccf3f86d7d078b797cdb436`
- `gauge/internal/controller/publication_cuts_test.go`: `bd313815535bf75944d722950ef6363b2b0e6dd95e796565a0c0598b32924286`
- `.github/workflows/gauge.yml`: `16148218f320e373537b28a88371145e9fd79f0edba8d303f320e5f6dbe11ccf`

The review began as a distinct artifact-only checker. Later passes necessarily know this checker's own findings and localized root coordination. The bounded follow-up completion report/diff/hash manifest were read as candidate artifacts, not acceptance evidence; no maker conversation or broad reasoning was read. Root's separate native/full-regression work is not presented as this checker's execution.

## Earlier findings remain resolved

The prior independent repair pass established the following, twice where documented, and the final follow-up does not change those implementation paths except optional test callbacks:

- **F001:** A durable per-root claim prevents Bash fallback after marker loss. Individual missing/corrupt/future/mismatched/symlinked claims fail closed. Go detects actual correctly sealed legacy inventory drift. Explicit recovery preserves typed durable identity and historical bytes. Unrelated and staged legacy histories retain Bash behavior. An independently induced nonroot claim-only publication write failure also recovered explicitly after quiescence.
- **F002:** Fresh imported adapter identity is unknown; imported roots cannot reconstruct even if an old manifest is deliberately relabeled fixture@1. Genuine fixture worker/environment replacements succeed through separate CLI processes without losing durable links.
- **F003:** Repeated ordinary-user packaging, including pre-existing 0444 licenses, succeeds and produces byte-identical executables with required notices.

The prior pass independently ran all nine anchors and the full race suite successfully. Its complete reproductions, controls, rejected overstrict scratch assertion and corrected oracle remain disclosed in `../final/review-report.md`, `../final/independent.py`, adjacent logs, and `../final/claim-publication.py`. Initial review evidence remains in the parent directory; it is not erased or converted into claimed green history.

## Exact publication boundaries now proved by execution

Source inspection places `Cut("claim-published")` at `authority.go:349-352`, immediately after successful durable atomic claim publication and before any pending run-marker publication. `Cut("marker-published")` at `:384-385` runs after successful final active-marker publication. Both execute inside `promoteLocked` while `Promote` still owns its append lock; release is deferred in `Promote` at `:395`. There is no new CLI or environment fault switch.

I read the test and existing process helper, then independently ran:

```
cd /src/gauge
go test -mod=readonly -race -count=2 -v ./internal/controller -run '^TestV406T04_PublicationWindows$'
```

**Exit 0.** Both phases passed twice. `windows.log` records exact child PIDs 129/192 and 253/315 reached, killed and reaped. The test asserts actual state before the kill rather than trusting labels:

- claim-published: persistent pending claim exists, run marker absent, root still staged, append owner file held;
- marker-published: active run marker and active root exist, durable identity preserved, append owner file still held;
- an independent competing promoter and synchronous Bash writer refuse at both windows, preserving typed state and original legacy bytes;
- after the promoter is killed and reaped, status/promote/recover reject unresolved ownership and preserve the owner bytes and store state;
- only after all children/competitors have completed does explicit operator lock cleanup occur;
- claim-only ordinary promotion still refuses, explicit recovery succeeds, recovery/promotion retries are idempotent in logical state, imported bytes/IDs/grades remain preserved, a positive fixture mutation succeeds, and Bash writes remain denied.

The prior pending/committed real-process kill cases and before/after whole-call controls remain unchanged. Together these cover the declared publication/commit interruption boundary matrix without pretending the whole-call controls occur immediately next to file writes. The earlier nonroot write-failure probe remains separate evidence, not mislabeled as process termination.

## T04 integration and continuous package coverage

Independently executed in the same isolated runner:

- `bats --print-output-on-failure --filter 'V4-06 T04 ' gauge/tests/conformance.bats`: exit0 (`t04.log`). The additive publication test matches the existing TestV406T04 anchor, so normal conformance runs execute it.
- `bash gauge/tests/package-repeat.sh`: exit0 (`package-repeat.log`). Runs as UID501/GID20, with script checking nonroot execution; two packages into the same directory, forced read-only existing licenses, byte-identical executable comparison and required notices all pass.
- Independent YAML structure assertions: exit0 (`ci-wiring.log`). Workflow line81 invokes package-repeat exactly once in the native package step, after race/conformance testing, without sudo, under GOPROXY=off, inherited by both ubuntu-latest and macos-latest matrix jobs.

The workflow source is wired correctly; no hosted run was observed or claimed. Full current native Go testing is root-owned and must be accounted for separately. This focused rerun was proportionate to the exact additive callbacks/test/CI change; the full suite was already independently green for the original repairs.

## Runner and evidence

Qualified `eidolons-gauge-go-qualified:local` image, supplied manifest `sha256:d9b4537412ed447276fbf3a745c3c953f254d412e70da57b5888831a0d61c795`; Go1.27.1 Linux/arm64, Bats1.11.1, jq1.7. Run used UID501/GID20, network none, read-only root and source, all capabilities dropped, no-new-privileges, executable /tmp tmpfs, dedicated writable caches, GOTOOLCHAIN=local and GOPROXY=off.

Exact inner commands and YAML assertions: `run.sh`. Full outputs and exits: `windows.log`/`.exit`, `t04.log`/`.exit`, `package-repeat.log`/`.exit`, `ci-wiring.log`/`.exit`. Container launch output: `docker.log`. Hash verification: `source-verification.json`; complete reviewed manifest: `candidate-hashes.json`.

No hosted CI or public publication has occurred according to root coordination. Local process interruption does not establish power-loss durability. No account-wide, cross-device, hostile-filesystem, network filesystem, production execution-provenance or live harness acceptance is inferred.

**Handoff:** root may integrate this scoped checker acceptance with its native, CLI, documentation and lifecycle evidence. Public deployment/CI status must remain explicitly pending until actually observed. Source write authority is yielded; this checker made no repair changes.
