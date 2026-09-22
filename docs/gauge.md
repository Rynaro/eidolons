# Optional Gauge controller

Gauge is an opt-in compiled controller for typed local state and fixture execution. Native harnesses still own reasoning and editing. The current seam supports explicit legacy import and writer transfer; it does not provide full CLI parity, live harness reconstruction, or current-candidate acceptance. See the [V4-06 receipt](campaigns/gauge/receipts/V4-06.md) for the tested candidate and outstanding gates.

## Build and select the binary

Ordinary installation and commands do not require Go. Build Gauge explicitly with Go **1.27.1** and the locked module dependencies available:

```sh
make gauge-build
eidolons gauge --help

# A distributable directory containing the executable, BUILD.txt and licenses:
make gauge-package GAUGE_OUT=/absolute/path/to/gauge-package
export EIDOLONS_GAUGE_BIN=/absolute/path/to/gauge-package/eidolons-gauge
eidolons gauge --help
```

The shim selects `EIDOLONS_GAUGE_BIN` when set, otherwise `gauge/bin/eidolons-gauge` relative to the CLI source. A missing or non-executable binary is an error. Invocation never runs Go, downloads a toolchain, or falls back to legacy writes. The explicit build sets `GOTOOLCHAIN=local` and uses `CGO_ENABLED=0`, `-mod=readonly`, `-trimpath`, `-buildvcs=false`, and an empty build ID. Build-time dependencies may require an explicit preparation/download step; runtime does not.

| Compatibility | Supported behavior |
|---|---|
| Keep | Existing opt-out CLI commands and installation; legacy writes for unrelated roots and imports that have only been staged. Existing command dependencies still apply. |
| Shim | `eidolons gauge` forwards to the selected executable. Successful commands emit JSON on stdout; failures emit a diagnostic on stderr and exit 1. Help emits text. |
| Unsupported | Full legacy command parity, native/provider dispatch, real harness reconstruction, account-wide scheduling or authority, cross-device coordination, and current-candidate acceptance. |

## Create and exercise a fixture root

```sh
eidolons gauge init --project /absolute/project --root demo
eidolons gauge fixture --project /absolute/project --root demo \
  --event-id observation-1 --outcome pass
eidolons gauge status --project /absolute/project --root demo
eidolons gauge replace --project /absolute/project --root demo \
  --worker worker-2 --reconstruction fixture
eidolons gauge replace --project /absolute/project --root demo \
  --environment environment-2 --reconstruction fixture
```

`init` without `--root` initializes only the controller instance. With a new root, it also stages and promotes that fixture root. Root IDs use letters, numbers, dots, underscores and hyphens; `.` and `..` and the controller's reserved directory name are unavailable. Existing legacy history requires `import`.

Fixture outcomes are `pass`, `fail` or `cancelled`. Receipts record `model_calls: 0`, `evidence_grade: "fixture-only"`, `accepted: false`, and an explicit observed model, normally `unknown`. Repeating the same event ID and identical input/configuration returns the existing receipt; conflicting reuse fails. A passing fixture is not acceptance. `status` reports `current_acceptance: "unavailable"`.

Worker and environment replacement are independent. Worker replacement also allocates new invocation and context identities; durable root, policy, candidate, intent and evidence references remain linked. Reconstruction is restricted to controller-created fixture roots. Imported roots have unknown adapter provenance and cannot become reconstructable by supplying `--reconstruction fixture`, including older imports labeled as fixtures.

Every command accepts `--project` (default `.`) and `--lock-timeout` (default `5s`, positive and at most `300s`). `--root` is required except for `init`. Event options belong only to `fixture`; replacement options belong only to `replace`.

## Import and transfer writer authority

Stop producers at an appropriate boundary and preserve the legacy files before transferring a root:

```sh
eidolons gauge init --project /absolute/project
eidolons gauge import --project /absolute/project --root existing-run
eidolons gauge promote --project /absolute/project --root existing-run
eidolons gauge status --project /absolute/project --root existing-run
```

`import` validates and stages an exact frozen inventory. It preserves original event bytes and IDs and their lower evidence grades, validating the legacy jq canonical hash including its trailing LF. It does not reinterpret Go JSON serialization as that hash or upgrade self-attested history. Repeating an unchanged import is idempotent.

Staging leaves Bash authoritative and able to append. Any subsequent inventory change blocks promotion and conflicts with re-import; the frozen inventory is not silently replaced. There is no automatic reset command. Resolve the changed inventory explicitly before attempting transfer again. A staged root is not an active `gauge status` result.

Promotion acquires existing append ownership, checks the frozen inventory, publishes a persistent per-root claim and a pending run marker, commits matching authority and imported state, then finalizes the marker. The claim at `.eidolons/.ledger/.gauge-controller-v1/authority-<root>.json` survives loss of `.eidolons/.ledger/<root>/.writer-authority.json`. Either proof blocks Bash writes. Claims bind the shared store identity, root, generation and inventory; malformed, future, conflicting and nonregular proofs fail closed. Active inspection and mutations recheck the imported inventory.

After promotion, `eidolons ledger status --run-id existing-run --json` remains a historical legacy view, with `historical: true`, `source: "legacy-import"`, `current_authority: "gauge"`, and unavailable current acceptance. Run it from the project directory. Those original files remain historical evidence, not the current Go state. Removing the Gauge binary does not restore Bash write authority.

## Recover an interrupted transfer

[ACTION] The operator must establish that all writers and their publishing children are quiescent before manually resolving ambiguous `.append-lock` ownership. Preserve the DB, original journal, claim and marker, including pending files. A PID alone does not establish quiescence. `recover` never steals or removes an append lock:

```sh
eidolons gauge recover --project /absolute/project --root existing-run
eidolons gauge status --project /absolute/project --root existing-run
```

Recovery completes a recorded, matching transfer. It can restore a lost run marker from a matching persistent claim and DB state. Missing claims, old layouts without claims, orphan proofs, disagreements and changed history require explicit inspection; recovery does not synthesize authority from ambiguous state. Do not delete proofs to reopen legacy writes. There is no automatic rollback, database recreation, reset or legacy write fallback.

## Storage and support boundary

[DECISION] Use one shared bbolt **1.5.0** database per controller instance at `.eidolons/.ledger/.gauge-controller-v1/state.db`, with distinct typed root records. This is not a database per execution or an account-wide store. Occupied legacy paths are rejected. Short transactions atomically publish dependent typed updates inside this database; the filesystem marker and database do not form one transaction. Sync stays enabled, lock waits are bounded, and corruption, unsupported versions and missing migrations fail closed.

The contracts distinguish history, working-context references, reusable knowledge and authoritative policy. Profile/method, assignment, worker/invocation, context, authority, candidate, receipt, environment and root identities remain separate roles. A versioned execution manifest records requested and observed model, harness, adapter, methods, environment and policy references; unknown observations remain unknown.

The exercised boundary is cooperating processes on local Linux/macOS storage. Process-interruption tests do not establish power-loss durability, hostile-filesystem security, safety after removal of every authority proof, or support for network, cloud-synced, removable or Windows filesystems. No live provider/model qualification is claimed.

For development, `make gauge-test` runs the nine conformance anchors separately from ordinary CLI tests. The complete Go suite also includes repair regressions: from `gauge/`, run `GOTOOLCHAIN=local go test -mod=readonly -race -count=1 ./...`. Run `bash gauge/tests/package-repeat.sh` from the repository as a non-root user for the repeat-package regression. Go, Bats, jq and Python are test/build tools, not additions to the ordinary no-Gauge runtime.

## Provenance

IDG 1.8.1, usage reference, 2026-09-22. Sources: [CLI](../gauge/cmd/eidolons-gauge/main.go), [shim](../cli/src/gauge.sh), [build script](../scripts/gauge-build.sh), [controller](../gauge/internal/controller/controller.go), [authority protocol](../gauge/internal/controller/authority.go), [typed contracts](../gauge/internal/contract/types.go), [spec](../.spectra/changes/gauge-v4-06/spec.md), and the verified Vivi repair report identified in the [receipt](campaigns/gauge/receipts/V4-06.md#provenance). That handoff is Vivi → IDG, `PROPOSE`, message `8f84391a-5292-43b3-8c53-0c00aa93c682`, thread `10c848f8-d48b-4e45-babe-ee9616617f09`, outcome `verify_pass`. CHT: C:5/5 H:5/5 T:5/5 for documented usage and limits; candidate acceptance is tracked separately. CRYSTALIUM unavailable.
