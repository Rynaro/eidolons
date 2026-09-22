---
eidolon: vivi
version: 1.1.0
kind: vivi-completion-report
status: ready-for-independent-review
created_at: "2026-09-22T04:34:58.858418+00:00"
thread_id: 10c848f8-d48b-4e45-babe-ee9616617f09
files_changed_count: 3
tests_run: 61
tests_passed: 61
---

# V4-06 bounded publication-window follow-up

Fresh-context Vivi `vivi_v4_06_faults` completed only the dispatched callback/test/CI scope in `/private/tmp/eidolons-gauge-v4-06`. No original maker history was read. Installed Vivi resources, current spec, existing source/tests, and the verified forwarding report were read. Inbound blocking verdict and keyed trace matched message `2f926c98-de8b-4372-8890-4d8e5b259fbf` and payload SHA `ec2b034aa85a1cb7bf7091e5e6c59216839216d3f576d5577fd460f19993b139`. CRYSTALIUM was unavailable. No docs, lifecycle, commit, push, or unrelated production edits were made.

## Exact changes and boundaries

- `gauge/internal/controller/authority.go`: call existing optional Options.Cut with `claim-published` immediately after successful durable atomic claim publication, and `marker-published` after successful final active-marker publication. Both run inside append ownership, before deferred release. Existing pending/committed callbacks and before/published whole-call helper boundaries are unchanged. No CLI/environment fault switch.
- `gauge/internal/controller/publication_cuts_test.go`: separate readable gofmt test `TestV406T04_PublicationWindows`, matching the existing T04 anchor regex. Uses existing real process helper, each requested callback acknowledged by READY only when its exact mode matches. Parent independently verifies the persisted claim, absent/active marker, held owner file, and staged/active DB root at the barrier. Competing real promoter and Bash writer refuse. Parent kills and reaps the child, verifies status/promote/recover refuse the unresolved lock, and only removes the lock after all children and synchronous competitors are known complete. Explicit recovery, idempotent recovery/promotion retry, preserved original journal bytes/imported IDs/grades/root identity, and positive fixture mutation all pass. Final Bash writes remain denied.
- `.github/workflows/gauge.yml`: native package step invokes `bash gauge/tests/package-repeat.sh` once, inherited by both Linux and macOS matrix jobs. Existing package script remains byte-identical.

All 163 pre-existing test/fixture files captured in `existing-tests-before.json` are unchanged, including conformance_test.go, repair_test.go and package-repeat.sh. New test contents were frozen before source edits and were not altered after executable red. Runner `docker-run.sh` remained byte-identical throughout every test execution. SHA checks are in `frozen-tests-runner.sha256`, `source-freeze.json`, and `final-freeze-verification.json`; `follow-up-only.diff` excludes earlier makers' changes.

## Honest red and green accounting

The new callbacks were initially absent. Actual red-gate assertions failed in both subtests with `exact ... callback not reached ... missing publication fault-injection coverage`, exit 1. This is proof of missing fault-injection coverage, **not a new production behavior defect**. `coverage-red-loop.json` records `red_gate=verified-red`; this intentionally single-attempt, no-fix-hook red-only loop ends capped, exit 3. No automated repair dispatch occurred. Source edits followed the retained localized assertions. Green verification is a separate real protected sandbox loop, not a fabricated continuation.

One earlier red attempt was correctly rejected as vacuous: the draft name `publication_windows_test.go` was interpreted by Go as a Windows-specific filename, so Linux ran no tests and returned zero. `red-loop.json` records `vacuous-reproduction` and exit 3. The new file was renamed byte-identically to `publication_cuts_test.go`, refrozen, and rerun before production changes. This discarded run is retained and not counted as evidence. Initial formatter-launch attempts also hit Docker socket permission and the image's existing Bash-entrypoint argument mismatch; those were runner setup failures, not behavioral red. The runner was finalized before any test execution.

`green-loop.json` is `final=passed`, k=2, one attempt, both passk runs exit 0, zero tamper rejections. It protects `gauge/**/*_test.go` and `gauge/tests/*`. Regression ran first on each pass:

```
cd gauge && go test -mod=readonly -race -count=1 -v ./...
```

Then each reproduction/acceptance pass ran:

```
bats --print-output-on-failure gauge/tests/conformance.bats && bash gauge/tests/package-repeat.sh
```

Full logs are `execution.5NOxEF` and `execution.WT6Ejf` (20 top-level Go tests passed each; the helper-only entry point intentionally skips direct invocation). They include exact callback kill/reap PIDs, all existing process boundaries, and repaired regressions. Anchor/package logs are `execution.2Ea09S` and `execution.LlEDhm` (all nine anchors pass each; nonroot package refresh with read-only prior license files and byte-identical executable succeeds each). Bats T04 invokes the new test as part of its existing regex. `execution-index.json` retains every command, output path and actual exit, including excluded and red runs. Each log has adjacent `.command` and `.exit` files, so both green runs remain available despite the sandbox's own full-log overwrite behavior.

Workflow parsing verified matrix OS names, the exact single invocation in the native package step, no sudo invocation, GOPROXY=off, and ordering after race tests. gofmt cleanliness and package Bash syntax passed in the same isolated run, `structure.log`, exit 0. Frontmatter counts the final validation groups: 40 top-level Go passes + 18 Bats anchor passes + 2 repeated-package checks + 1 structure/format/syntax check = 61, not unique test cases or every subtest. Failed/excluded exploratory runs are disclosed above and excluded from these final green counts.

## Runtime and limits

All counted execution used qualified local image `eidolons-gauge-go-qualified:local`, network none, read-only root/source, dropped capabilities, no-new-privileges, executable /tmp tmpfs, UID501/GID20, GOTOOLCHAIN=local, GOPROXY=off, and dedicated `/private/tmp/gauge-go-modcache` and `/private/tmp/gauge-go-buildcache`. No dependency fetch during tests. Observed Linux process kill/recovery is not power-loss or remote-filesystem qualification. No hosted CI or native macOS execution is claimed here; root owns final native qualification and exact-diff re-review. Existing CLI files were unchanged by this follow-up, so their previously completed full suite was not redundantly rerun.

Source is frozen and write authority is yielded. Root should re-review the three-file follow-up against the listed hashes. No independent checker verdict is claimed by this maker.
