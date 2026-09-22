---
eidolon: vivi
version: 1.1.0
kind: vivi-completion-report
status: candidate-for-independent-review
created_at: 2026-09-22T04:16:33.106648+00:00
files_changed_count: 6
tests_run: 29
tests_passed: 29
---

# V4-06 bounded repair candidate

Fresh-context repair actor `vivi_v4_06_repair`; sole source/test/build writer. Base commit `13d383bafe68d5e8b5c045212761d8ec4af89046`, branch `codex/gauge-v4-06-controller`, checkout `/private/tmp/eidolons-gauge-v4-06`. CRYSTALIUM unavailable. No original maker conversation/history or broad reasoning logs were read. Input was the canonical contract, installed Vivi resources, localized independent findings/reproducer, source, and original tests. The reviewer-to-Vivi forwarding envelope was mechanically verified by root before source repair; keyed gate record is in `/private/tmp/v4-06-review-probes/.eidolons/.trace/10c848f8-d48b-4e45-babe-ee9616617f09.jsonl`, message `034cf555-a4d0-4c78-b9b3-277ef846328f`.

This is a repair candidate, not independent acceptance. No commit, push, lifecycle/documentation edit, model invocation, or live probe was performed. Native macOS and repository-wide checks remain with root.

## Changes

- **F001:** Promotion now publishes a persistent per-root authority claim in the existing shared controller directory before the pending run marker. Bash refuses writes when either proof exists. The claim is per root: unrelated legacy roots and staged/unpromoted imports retain ordinary writes. Go binds the claim, marker, store identity, root generation, and frozen inventory; malformed, future, conflicting, missing, and nonregular proof states fail closed. A missing run marker can be restored only through explicit recovery using a matching existing claim and DB state. An orphan proof cannot initialize or import a root. Active inspection/mutation and idempotent promotion/recovery revalidate exact historical inventory bytes, so restoring marker bytes cannot conceal divergence.
- **F002:** Imported adapter provenance is `unknown`. Reconstruction rejects legacy roots, including earlier fixture-labeled imported manifests, while genuine controller-created fixture roots still support worker and environment replacement.
- **F003:** Package-owned license outputs are refreshed with `install -m 0644`, so prior cache-inherited read-only modes cannot break a repeat package build. The test runs under UID 501, forces license outputs to 0444 between builds, and compares the resulting executable bytes.

Four production files changed: `cli/src/ledger.sh`, `gauge/internal/controller/authority.go`, `gauge/internal/controller/controller.go`, `scripts/gauge-build.sh`. Two new test files: `gauge/internal/controller/repair_test.go`, `gauge/tests/package-repeat.sh`. All original Go/Bats/Python test definitions are byte-identical. The pre-repair freeze also includes both new regression files; `protected-tests.json` and `protected-verification.json` cover 121 files.

## Process termination evidence

New tests use real independently controlled OS children. The parent kills and reaps the promoter before promotion, at the existing pending-publication barrier, after DB commit before final-marker publication, and after successful final publication. Pending/committed cases also run an independent competing promoter and Bash writer. Neither can steal ownership. Recovery first refuses the unresolved append lock; only after all children are reaped and the synchronous Bash writer has finished does the test explicitly remove the known lock and invoke recovery. Independent reopened state retains original event bytes, IDs, and grades. Idempotent promotion, post-recovery fixture execution, and ordinary unrelated/staged legacy writes provide positive controls. Existing store tests separately kill children before/after store commit. No production cut seam was added solely for test convenience.

These are local cooperating-writer and process-interruption guarantees. They do not establish hostile filesystem security, resistance to removal of all authority proofs, power-loss durability, remote filesystem correctness, or production/native reconstruction capability. Unexpected old layouts lacking the new persistent claim require explicit inspection rather than automatic authority synthesis.

## Validation and provenance

Runner: `eidolons-gauge-go-qualified:local`, supplied image manifest `sha256:d9b4537412ed447276fbf3a745c3c953f254d412e70da57b5888831a0d61c795`, actual Go 1.27.1 linux/arm64. Docker uses network none, read-only root and source, UID 501/GID 20, all capabilities dropped, no-new-privileges, executable tmpfs `/tmp`, explicit module/build caches `/private/tmp/gauge-go-modcache` and `/private/tmp/gauge-go-buildcache`, and `GOTOOLCHAIN=local`.

`phase-N.command`, `.log`, and `.exit` retain every invocation and complete output independently of the sandbox's overwritten full-log file. The initial launch had an invalid `--out-dir` option; `launch-invalid-option.log` preserves that excluded setup failure. Phase 1 was a Docker socket permission refusal; it is not red evidence. Phase 2 independently reproduces F002. Phases 3 and 5 reproduce all three actual defects on unchanged source, while phase 4 passes all 29 original Gauge/journal/completion/ledger/product anchors. New tests were frozen before any source repair.

The first repaired targeted run (phase 6), all 29 repaired original anchors (phase 7), and full Go race suite (phase 8) pass. Phases 9–11 and 14 diagnose a non-root Git safe-directory mount issue in standalone packaging; these are excluded infrastructure failures, not defect reds. Phase 15 configures only the ephemeral known `/src` safe directory, repeats packaging successfully, and passes seven claim probes. Those probes cover lost-marker explicit recovery and bad/future/conflicting/missing/symlink/directory claim refusal without DB mutation, each paired with unrelated and unpromoted legacy write controls. Detailed subprocess argv/stdout/stderr/exits are in `claim-probes-commands.jsonl`.

One log from the first loop (phase 13) was corrupted when the runner script was edited while a shell was still executing it. Although that loop reported passed, its green verdict is excluded as decisive pass^k evidence. All initial artifacts remain intact and the problem is disclosed. The repaired source was saved with SHA-256s under `final-source/`, only the four production files were restored to HEAD, and the same candidate was mechanically replayed through a fresh protected `--require-red --k 2 --max-attempts 2` loop with the stable runner. Its fix-hook only restores those exact hashed source bytes; it is a mechanical replay of an already-authored repair, not a new fresh-model repair. Frozen tests never changed. The replay uses the nine V4-06 anchors as regression; the intact phase-7 run separately supplies all predecessor/product anchors.

The decisive replay is `loop-replay.log` / `loop-replay.exit` and `sandbox-replay/`: final `passed`, `red_gate=verified-red`, `k=2`, `tamper_rejections=0`. Phases 17 and 19 reproduce all three defects on the restored base; phase 18 passes baseline anchors. Phases 20/22 pass all nine original anchors; phases 21/23 pass all frozen repair/process/package tests. `replay-source-verification.json` confirms exact source identity before/after replay. `candidate-hashes.json` hashes all tracked and untracked candidate files; `candidate-complete.diff` includes both added tests, unlike the substrate's tracked-only candidate diff. Final static/runtime checks are phase 24.

Repair authority is yielded for independent re-review. No source edits are pending.
