# V4-04 mechanical current-candidate sandbox-loop verification replay

Result: **passed**, real sandbox driver exit 0; `red_gate=verified-red`, `attempts_run=2`, `max_attempts=2`, `k=2`, `tier=container`, `tamper_rejections=0`, `merged=false`, both accepted pass-k runs exit 0, `flaky=false`.

## Provenance

This is an additional verification replay of the already-authored, locally reviewed candidate commit `85a8541a6537e83f30ea1f32c9e5d2287360cd79`. Original Vivi implementation and red/green checks were manual; this artifact does not retroactively make them loop-native. No fresh repair, new coder invocation, paid call, future/gold patch, original repository mutation, or original repository commit occurred in this replay.

Scratch `/private/tmp/gauge-v4-04-loop-replay` was materialized with `git archive 1a4697e2101f5c588dcf3632c6823e7b73c86d58`, then overlaid with the immutable candidate's `cli/tests/journal_conformance.bats`, `cli/tests/journal_conformance.py`, and `cli/tests/fixtures/journal/` via `git archive 85a8541a6537e83f30ea1f32c9e5d2287360cd79 <paths>`. A standalone git repository was initialized in scratch only, with a baseline commit containing that tree, so the driver's `base=325139b114e9cb901a36deaba158c619c15119fb` refers to this scratch baseline, not the original project commit.

The actual unmodified `cli/src/sandbox.sh loop` driver ran from scratch. `run-loop.sh` records the exact driver command. `docker-via.sh` records the exact isolation command and accepts the driver's single intact verifier command string. `fix-hook.sh` records the only edit step: after attempt 1 failed the reproduction, validate feedback and failing test assertions, then copy the candidate's already-authored `ledger.sh` and `lib.sh` into scratch. Candidate bytes were read from the specified immutable Git commit, not a moving working tree.

## Execution and evidence

The driver performs its `--require-red` gate before its regular regression-first cycles. Actual Docker invocations were:

| Invocation | Phase | Result |
|---|---|---|
| 01 | Initial red gate: journal conformance | 5 failed, exit 1 |
| 02 | Attempt 1 regression | 37 passed, exit 0 |
| 03 | Attempt 1 reproduction | 5 failed, exit 1 |
| hook | Mechanical candidate source copy | only ledger.sh and lib.sh |
| 04 | Attempt 2, run 1 regression | 37 passed, exit 0 |
| 05 | Attempt 2, run 1 reproduction | 5 passed, exit 0 |
| 06 | Attempt 2, run 2 regression | 37 passed, exit 0 |
| 07 | Attempt 2, run 2 reproduction | 5 passed, exit 0 |

Every invocation retains `.command.txt`, `.log`, `.exit-code.txt`, `.started.txt`, and `.finished.txt`. `driver.stdout.log`, `driver.stderr.log`, and `driver.exit-code.txt` retain driver results. `loop/loop.json`, its substrate ECL envelope, `candidate.diff`, feedback, and red-gate logs are the actual substrate artifacts. The wrapper's per-invocation logs additionally preserve earlier phase output which the driver's `full-log.txt` overwrites.

The red result was a real test failure, not an invalid command: Bats executed all five tests and reported their failing assertions. A supplementary direct run of the unchanged Python ordering oracle with read-only baseline source overlays produced `AssertionError: ('ordered', 'predecessor', 11)` after recording 120 events. This is preserved in `baseline-failure-diagnostic.log` with exit 1. The supplementary diagnostic did not edit source or test files and was not a driver attempt.

Docker used the existing qualified image `eidolons-v4-03-qualified:local`, pinned by digest `sha256:d8aba23301c07272b428495c1ea7eb2e7f115a82f165f83e0c2fef88e2410732`, Bash 5.2.37, Bats 1.11.1, jq 1.7, Python 3.13.5. Every test container had `--network none`, `--read-only`, `--cap-drop ALL`, `--security-opt no-new-privileges`, a read-only `/repo` mount, and a writable container-local `/tmp` tmpfs. No Docker socket was mounted inside test containers. Runtime qualification is preserved in `runtime-qualification.log`.

## Integrity

All 227 tracked files under `cli/src` and `cli/tests` were byte-compared against the immutable candidate, with hashes in `candidate-file-hash-verification.json`. The complete 141-file test snapshot before and after is identical (`tests-before.json`, `tests-after.json`). Scratch `git diff --name-only` contains exactly `cli/src/ledger.sh` and `cli/src/lib.sh`. Explicit `--protect` included both anchor files and every journal fixture; the default test-tamper ratchet stayed enabled. No test bytes changed.

- `cli/src/ledger.sh`: `ddd0b85eaf90b81efe8c437df131b74ce2c8d9f379800e0a81734c7b75ef7fcd`
- `cli/src/lib.sh`: `d52429318f570a95e18335624166df1a0667f1f0e2d722d738e2594d6b7bf78c`
- `cli/tests/fixtures/journal/README.md`: `703ca889cf53748d22223afb9163d3214087301cd7f29e90edb0d334b98ca828`
- `cli/tests/fixtures/journal/canonical.json`: `99b5c50875d5e0be283db245a7143646001d54246397aa93b389897696f78b8d`
- `cli/tests/fixtures/journal/invalid.json`: `5eaa14b0cf70768be0ea261d258502db05d227ea518de774a7718695d8d35f4f`
- `cli/tests/fixtures/journal/legacy-complex.json`: `4910d6148cc0cf670b01d2a1b605ccf0fb836373d2d0e529396707e878176f62`
- `cli/tests/fixtures/journal/legacy.json`: `98ecc277b50031c9f305ca2c7d707c125a3bdba3f5ddfb87da5453e62f5aa285`
- `cli/tests/journal_conformance.bats`: `dca0227fb288520c2449882c62155b54fe212be3028b0e4df4e82e38b8a03929`
- `cli/tests/journal_conformance.py`: `6de7d9cb5846cd9f5222c889196ff4ff3375fdfdf0321572670e7ef1483bc2f6`

## Limits

This is bounded Linux/Bash 5 verification of an existing candidate, not evidence of a fresh feedback-guided implementation, broad statistical reliability, protected-runner security, adversarial holdout isolation, or power-loss durability. The host-side driver and mechanical hook are trusted orchestration; only verifier commands ran inside Docker. No external judge or sealed holdout was configured. CRYSTALIUM tools were unavailable and were skipped, without a fake memory receipt. The driver's tier inference alone does not establish isolation; the retained actual Docker command is the evidence of the configured boundary.
