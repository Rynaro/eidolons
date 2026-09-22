# Optional Gauge controller

Gauge is an opt-in compiled controller for typed local state and fixture execution. Native harnesses still own reasoning and editing. The current seam supports explicit legacy import, writer transfer, persistent local preferences, policy inspection, root lineage, honest usage observations, a fixture-first host qualification / early comparison instrument, fixture-local atomic reservations with verification/recovery headroom, one fixture-qualified native adapter with durable dispatch and cancellation, and assignment compilation without mandatory agent chains; it does not provide full CLI parity, live harness reconstruction, live host qualification, or current-candidate acceptance. See the [V4-06 receipt](campaigns/gauge/receipts/V4-06.md), [V4-07 receipt](campaigns/gauge/receipts/V4-07.md), [V4-08 receipt](campaigns/gauge/receipts/V4-08.md), [V4-09 receipt](campaigns/gauge/receipts/V4-09.md), [V4-11 receipt](campaigns/gauge/receipts/V4-11.md), [V4-12 receipt](campaigns/gauge/receipts/V4-12.md) and [V4-13 receipt](campaigns/gauge/receipts/V4-13.md) for tested scope and outstanding gates.

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
| Unsupported | Full legacy command parity, live/provider dispatch, real harness reconstruction, account-wide scheduling or authority, cross-device coordination, and current-candidate acceptance. |

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

Every command accepts `--project` (default `.`) and `--lock-timeout` (default `5s`, positive and at most `300s`). The fixture/import/authority commands above require `--root` except for `init`; the rootless V4-07 commands below do not. Event options belong only to `fixture`; replacement options belong only to `replace`.

## V4-07 preferences and migration

V4-07 has independent local fixture acceptance, including preserved empty restrictions, distinct request identities and rejection of negative underflow. The [receipt](campaigns/gauge/receipts/V4-07.md#independent-findings-and-final-local-verification) records repairs and validation. Hosted CI remains blocked pending publication approval; production authorization remains unqualified.

V4-07 stores two logical preference layers, `user` and `project`, inside this project's controller DB. “User” is a provenance label local to that controller; it is not an OS identity, home setting, account-wide default or multi-user isolation boundary. Another controller DB has independent settings. Preferences require an initialized store but no execution root:

```sh
eidolons gauge init --project "/absolute/ação project"
eidolons gauge preferences --project "/absolute/ação project"
```

New stores use database schema 2. An existing V4-06 schema-1 store requires an explicit migration before ordinary V4-07 commands can open it:

```sh
eidolons gauge migrate --project "/absolute/ação project"
eidolons gauge preferences --project "/absolute/ação project"
```

[ACTION] Before migration, preserve the controller DB and legacy files and resolve interrupted writer transfers using the predecessor's recovery procedure. Migration validates existing roots, inventories and authority proofs under their locks. It creates typed namespaces, a migration receipt and schema 2 in one database transaction, preserving controller identity, history, replay state and filesystem proofs. The `.gauge-controller-v1` directory and version-1 layout/claim formats retain their names and versions; they are distinct from the DB schema.

The new binary refuses unmigrated schema 1 with `migration_required`; the real V4-06 binary refuses schema 2. There is no downgrade or schema-number reset. `migrate` accepts only the supported predecessor, so repeating it on schema 2 fails. Missing migration metadata, missing namespaces and unknown versions fail closed. Migration does not convert old generic policy JSON into grants or create V4-07 root bindings.

To replace a preference layer, save a JSON file such as `/absolute/preferences.json`:

```json
{"schema_version":1,"preset":"Conserve","restrictions":[{"denied":["write"]}]}
```

Read the current layer's `revision`, then submit it as a compare-and-swap check:

```sh
eidolons gauge preferences-set --project "/absolute/ação project" \
  --layer user --expected-revision 0 --input /absolute/preferences.json
```

Revision `0` is the initial value. Successful replacement increments that layer's revision; a stale revision fails, preserving the current document. Re-read and reconcile before retrying. This replaces the whole named layer, not a partial merge. Duplicate JSON keys at any depth, unknown fields/versions/presets, negative or nonfinite limits, and unsafe persistence failures leave the previous preferences intact. The returned document includes controller, layer, revision, digest and normalized values. The other layer and unrelated state remain unchanged.

Preset precedence is built-in `Balanced` < `user` < `project` < explicit run input. Valid presets are `Conserve`, `Balanced` and `Accelerate`. Preference precedence does not confer authority: restrictions accumulate/intersect, and a preference cannot supply a missing permission, billing grant or hard bound.

## Compile and inspect policy

```sh
eidolons gauge policy-compile --project "/absolute/ação project"
```

Compilation reads both persistent layers together and returns an unbound inspection result with an identity and field provenance: source classes/references/digests, resolution rules and contributing values. It does not persist a policy, bind a root or activate execution. Without `--input`, mandatory inspection placeholders are checks `acceptance`/`regression`, criteria `unavailable` and grade `unqualified`.

For an explicit run preference, save `/absolute/policy-patch.json`:

```json
{
  "run": {"schema_version":1,"preset":"Balanced"},
  "restrictions": [{"ceilings":[{
    "resource":"tokens","unit":"token","pool":"example",
    "interval":"run","scope":"task","limit":1000
  }]}],
  "required": {
    "checks":["acceptance","regression"],
    "criteria":"unavailable","grade":"unqualified"
  }
}
```

```sh
eidolons gauge policy-compile --project "/absolute/ação project" \
  --input /absolute/policy-patch.json
```

The example limit is an inspection input, not a calibrated budget or grant. Ceiling minima combine only matching resource/unit/pool/interval/scope dimensions; task, project, account, window and concurrency scopes remain separately applicable. These scope labels do not implement account-wide enforcement. Unknown hard bounds remain explicit and block authorized admission. Allowed sets can only narrow designated grants; denies accumulate. Presets change optional strategy choices while preserving the supplied mandatory acceptance contract and authority requirements.

Production activation remains **`authorizer_boundary_unqualified`**. No file, environment variable, CLI source label, authorization-looking ID, writer generation or DB ownership grants policy authority. The only trusted-authorizer positive controls are in-memory test fixtures. There is no production provisioning or activation flag in this seam.

The typed commands below require `--root` and currently expose storage/inspection contracts, not a way around that boundary:

| Command | Inputs and behavior |
|---|---|
| `policy-bind` | `--authorization-id ID [--input JSON]`; initial predecessor must be empty. A fresh production binding fails with `authorizer_boundary_unqualified`. |
| `policy-amend` | `--authorization-id ID --predecessor POLICY_ID [--input JSON]`; fresh production amendment has the same refusal. An ID is not a credential. |
| `policy-show` | `--policy-id ID`; reads an existing immutable typed policy for the root. A compiled-only ID has no stored record. |
| `policy-binding` | Reads the root's typed binding; newly initialized/migrated roots have no V4-07 binding. |
| `amendment-show` | `--authorization-id ID`; retrieves an existing original amendment result. |
| `strategy-select` | `--policy-id ID --input JSON`; validates a data-only selection against an existing stored policy. It does not execute a strategy. |

In the fixture-tested amendment contract, policy snapshots and results are immutable. Preference updates affect future compilation, never an old snapshot. Authorization consumption is keyed across the controller DB by authorizer and authorization ID, bound to the root and canonical request. Exact historical retry returns its original result after later amendments without reactivating it; conflicting reuse or stale predecessors fail. A pending restriction does not revoke an active worker. Criteria changes require separate lifecycle handling and evidence invalidation.

Strategy input has the closed shape `{"schema_version":1,"strategy":"focused@1","parameters":{"breadth":1},"reason":"limited optional exploration"}`. The pinned registry offers `focused@1` (breadth 1), `balanced@1` (1–2) and `exploratory@1` (1–3), restricted further by the immutable policy's preset subset. These are illustrative rules, not calibrated cost/quality promises. Selection reports the chosen entry, alternatives, rule, parameters and observable reason. Unknown entries, out-of-range parameters, executable code, protected-policy edits and acceptance changes are rejected.

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

V4-07 adds `bash gauge/tests/policy-anchors.sh`, which checks discovery of T01–T08 and runs the policy Go tests. Its separate external oracle, `gauge/tests/policy.py`, requires a qualified frozen V4-06 checkout mounted at `/predecessor`; it builds the actual older binary for migration/refusal checks. New policy rollback cuts are callback fault tests; they do not add process-kill or power-loss qualification for preference/amendment transactions.

V4-08 adds `bash gauge/tests/observation-anchors.sh` for T01–T08 lineage and usage-observation anchors. Independent arithmetic oracles for reconciliation live in `gauge/internal/contract/reconcile_vectors_test.go` (ported from the review-probe vectors). Observation recording does not grant policy or spending authority. Hosted CI remains blocked pending publication approval; no live-host qualification is claimed.

V4-09 adds `bash gauge/tests/instrument-anchors.sh` for T01–T11 host-qualification and early comparison instrument anchors. Independent arithmetic vectors K/Z/U/W live in `gauge/internal/contract/instrument_vectors_test.go`. Catalogue/preflight never grants live admission; fake adapters prove blocked paths never hit transport (including API). Structural before V4-10 and managed before V4-15 remain ineligible.

V4-11 adds `bash gauge/tests/reservation-anchors.sh` for T01–T08 atomic reservation anchors (plus concurrency stress). Admission is fixture-local only: known ceiling intersection, protected verification/recovery headroom, uncertain exposure retention, and accounting-fault rejection. No provider dispatch and no exact external billing claims.

V4-12 adds `bash gauge/tests/dispatch-anchors.sh` for T01–T09 durable native-adapter anchors. Exactly one fixture-qualified host/version/mode is exercised via a fake adapter; live qualification stays blocked. Commit reservation+intent before send; reconcile before redispatch; cancellation stays nonterminal until confirmed stop.

## V4-08 root lineage and observations

New stores initialize typed observation namespaces under schema 2 (`usage_observations`, `usage_corrections`, `lineage_edges`, `coverage_reports`) with an `observation_receipt`. Existing schema-2 controllers without those buckets remain openable; call `observation-enable` before first managed observation use (also implied by `task-start`).

```sh
eidolons gauge init --project "/absolute/ação project"
eidolons gauge observation-enable --project "/absolute/ação project"
eidolons gauge task-start --project "/absolute/ação project" --route-digest "sha256:route"
eidolons gauge task-resume --project "/absolute/ação project" --root <uuid-from-task-start>
```

`task-start` allocates a fresh UUID execution root distinct from the route digest. Identical routes create different roots. `task-resume` resolves an existing root only; an unknown ID fails without creating a root. Descendant/reviewer/retry/successor edges bind to the original root via `lineage-bind`. Worker/environment replacement never allocates a new budget root.

Record allowlisted usage JSON (unit, source grade, observation/receipt times, freshness; no credentials, transcripts, reasoning, tool-arg dumps):

```sh
eidolons gauge usage-record --project "/absolute/ação project" --root <uuid> --input /absolute/obs.json
eidolons gauge usage-correct --project "/absolute/ação project" --root <uuid> --input /absolute/corr.json
eidolons gauge usage-summary --project "/absolute/ação project" --root <uuid> --input /absolute/stream.json
eidolons gauge usage-export --project "/absolute/ação project" --root <uuid>
eidolons gauge usage-retain --project "/absolute/ação project" --root <uuid>
```

Reconciliation accounts for each consumption identity once (deltas, prefixes, corrections, epochs, parent/child overlap). Missing pricing, model identity or coverage stays unknown/incomplete — never zero or unlimited. Summaries always report inference, transfer, environment, elapsed and human coverage categories. `usage-export` is allowlisted managed inspection; legacy raw bytes are not forwarded. `usage-retain` drops eligible detail while preserving totals, lineage and exposure markers.

## V4-09 host qualification and early comparison instrument

New stores initialize typed instrument namespaces under schema 2 (`capability_catalogue`, `protocol_freezes`, `attempt_records`, `eligibility_records`, `shadow_observations`, `instrument_ordering`) with an `instrument_receipt`. Existing schema-2 controllers without those buckets remain openable; call `instrument-enable` before first managed instrument use.

```sh
eidolons gauge init --project "/absolute/ação project"
eidolons gauge instrument-enable --project "/absolute/ação project"
eidolons gauge catalogue --project "/absolute/ação project" --input /absolute/tuple.json
eidolons gauge preflight --project "/absolute/ação project" --tuple <id>
eidolons gauge freeze --project "/absolute/ação project" --input /absolute/protocol.json
eidolons gauge record --project "/absolute/ação project" --input /absolute/attempt.json
eidolons gauge shadow --project "/absolute/ação project" --input /absolute/shadow.json
eidolons gauge report --project "/absolute/ação project" --protocol <id>
eidolons gauge eligibility --project "/absolute/ação project" --input /absolute/elig.json
```

Catalogue tuples bind host/version/integration/mode/method/permissions/boundary/granularity/maturity/evidence/billing — not a brand. Help/registration is discovery only. Preflight fails closed when required capabilities or authorized billing are missing; credentials are not allowance; exhausted subscription never switches to API. Protocol freeze must precede dispatch/outcome in controller ordering. Live criterion stays blocked without protected authorization and a real live probe. Native and original-v3 (`752194ef5ceaa8cee1f5995fd0d374888696d8fc`) share one recorder schema; structural/managed arms stay ineligible until V4-10/V4-15.

## V4-11 atomic reservations

New stores initialize typed reservation namespaces under schema 2 (`reservations`, `scope_balances`, `reservation_events`) with a `reservation_receipt`. Existing schema-2 controllers without those buckets remain openable; call `reservation-enable` before first managed reservation use.

```sh
eidolons gauge init --project "/absolute/ação project" --root demo
eidolons gauge reservation-enable --project "/absolute/ação project"
eidolons gauge reservation-admit --project "/absolute/ação project" --root demo --input /absolute/admit.json
eidolons gauge reservation-status --project "/absolute/ação project" --root demo
eidolons gauge reservation-amend --project "/absolute/ação project" --root demo --input /absolute/amend.json
eidolons gauge reservation-reconcile --project "/absolute/ação project" --root demo --input /absolute/reconcile.json
```

Admission intersects known local ceilings (task/project/account/window/concurrency) under the active policy identity — it never invents grants. Verification/recovery headroom is excluded from optional implementation. Uncertain post-dispatch exposure is retained until explicit reconcile/release-with-proof. Provider window reset does not refill task budget. Authoritative accounting unavailability rejects managed admit. No provider/network call runs inside a store transaction; V4-12 owns durable native dispatch.

## V4-12 durable native dispatch

New stores initialize typed dispatch namespaces under schema 2 (`dispatch_intents`, `dispatch_events`, `dispatch_acks`, `dispatch_ops`) with a `dispatch_receipt`. Existing schema-2 controllers without those buckets remain openable; call `dispatch-enable` before first managed dispatch use.

```sh
eidolons gauge init --project "/absolute/ação project" --root demo
eidolons gauge dispatch-enable --project "/absolute/ação project"
eidolons gauge admit-dispatch --project "/absolute/ação project" --root demo --input /absolute/dispatch.json
eidolons gauge dispatch-status --project "/absolute/ação project" --root demo
eidolons gauge dispatch-cancel --project "/absolute/ação project" --root demo --input /absolute/cancel.json
eidolons gauge dispatch-reconcile --project "/absolute/ação project" --root demo --input /absolute/reconcile.json
eidolons gauge dispatch-events --project "/absolute/ação project" --root demo --intent <intent-id>
```

Managed dispatch admits a V4-11 reservation, commits durable intent, then invokes the single fixture-qualified fake native adapter (`exec-sandbox-readonly`). Live qualification remains blocked. Transport-terminal events are not acceptance. Cancellation requested ≠ confirmed stopped ≠ final reconciliation. Uncertain sends stay pending reconcile; checkpoint replay is not an exactly-once guarantee.

## V4-13 assignment compiler

New stores initialize typed compiler namespaces under schema 2 (`compiled_plans`, `method_bindings`, `assignment_splits`, `consultant_receipts`) with a `compiler_receipt`. Existing schema-2 controllers without those buckets remain openable; call `compiler-enable` before first managed compile use.

```sh
eidolons gauge init --project "/absolute/ação project" --root demo
eidolons gauge compiler-enable --project "/absolute/ação project"
eidolons gauge compile --project "/absolute/ação project" --root demo --input /absolute/compile.json
eidolons gauge compiler-status --project "/absolute/ação project" --root demo
eidolons gauge consult-validate --project "/absolute/ação project" --root demo --input /absolute/consult.json
eidolons gauge compiler-rebind --project "/absolute/ação project" --root demo --input /absolute/rebind.json
eidolons gauge compiler-evidence --project "/absolute/ação project" --root demo --input /absolute/evidence.json
eidolons gauge compiler-writers --project "/absolute/ação project" --root demo --input /absolute/writers.json
```

Compatible methods stay in the continuing maker; separate workers require a recorded boundary reason. Effective authority is the intersection of operator/task/assignment/specialist/host layers — role cards and model messages cannot widen a child grant. Skills bind versioned I/O contracts; consultant results must pass a bounded output check before maker use. Concurrent writers need isolated workspaces plus an integration owner. Selection reasons are inspectable and fallible; no V4-14 acceptance freeze is claimed.

## Provenance

IDG 1.8.1, usage reference, 2026-09-22. Sources: [CLI](../gauge/cmd/eidolons-gauge/main.go), [shim](../cli/src/gauge.sh), [build script](../scripts/gauge-build.sh), [controller](../gauge/internal/controller/controller.go), [authority protocol](../gauge/internal/controller/authority.go), [typed contracts](../gauge/internal/contract/types.go), [spec](../.spectra/changes/gauge-v4-06/spec.md), and the verified Vivi repair report identified in the [receipt](campaigns/gauge/receipts/V4-06.md#provenance). That handoff is Vivi → IDG, `PROPOSE`, message `8f84391a-5292-43b3-8c53-0c00aa93c682`, thread `10c848f8-d48b-4e45-babe-ee9616617f09`, outcome `verify_pass`. CHT: C:5/5 H:5/5 T:5/5 for documented usage and limits; candidate acceptance is tracked separately. CRYSTALIUM unavailable.

V4-07 additions use the [policy CLI](../gauge/cmd/eidolons-gauge/policy.go), [policy contract](../gauge/internal/contract/policy.go), [typed store](../gauge/internal/store/policy.go), [controller wrappers](../gauge/internal/controller/policy.go), and [spec/decisions](../.spectra/changes/gauge-v4-07/spec.md). Incoming Vivi → IDG `PROPOSE`, message `4a0633b1-4576-4f04-8069-54763f689daa`, thread `7fa26ce4-5020-4b35-be77-3b81ee9323ac`, passed the blocking SHA-256 gate; full lineage is in the [V4-07 receipt](campaigns/gauge/receipts/V4-07.md#provenance). CHT: C:5/5 H:5/5 T:5/5 for the usage reference; final independent local review and formatting reconciliation are recorded in the receipt; hosted CI remains blocked.

V4-08 additions use the [observation CLI](../gauge/cmd/eidolons-gauge/observation.go), [observation contract](../gauge/internal/contract/observation.go), [reconcile](../gauge/internal/contract/reconcile.go), [store](../gauge/internal/store/observation.go), [controller](../gauge/internal/controller/observation.go), and [spec/decision](../.spectra/changes/gauge-v4-08/spec.md). Local fixture anchors are recorded in the [V4-08 receipt](campaigns/gauge/receipts/V4-08.md). Hosted CI and independent review remain pending; no live qualification.

V4-09 additions use the [instrument CLI](../gauge/cmd/eidolons-gauge/instrument.go), [capability](../gauge/internal/contract/capability.go) / [protocol](../gauge/internal/contract/protocol.go) / [recorder](../gauge/internal/contract/recorder.go) contracts, [store](../gauge/internal/store/instrument.go), [controller](../gauge/internal/controller/instrument.go), and [spec/decision](../.spectra/changes/gauge-v4-09/spec.md). Local fixture anchors are recorded in the [V4-09 receipt](campaigns/gauge/receipts/V4-09.md). Live qualification intentionally blocked; hosted CI pending publication.

V4-11 additions use the [reservation CLI](../gauge/cmd/eidolons-gauge/reservation.go), [reservation contract](../gauge/internal/contract/reservation.go), [store](../gauge/internal/store/reservation.go), [controller](../gauge/internal/controller/reservation.go), and [spec/decision](../.spectra/changes/gauge-v4-11/spec.md). Local fixture anchors are recorded in the [V4-11 receipt](campaigns/gauge/receipts/V4-11.md). No provider dispatch; hosted CI pending publication.

V4-12 additions use the [dispatch CLI](../gauge/cmd/eidolons-gauge/dispatch.go), [dispatch contract](../gauge/internal/contract/dispatch.go), [store](../gauge/internal/store/dispatch.go), [NativeAdapter](../gauge/internal/controller/native_adapter.go), [controller](../gauge/internal/controller/dispatch.go), and [spec/decision](../.spectra/changes/gauge-v4-12/spec.md). Local fixture anchors are recorded in the [V4-12 receipt](campaigns/gauge/receipts/V4-12.md). Live qualification blocked; hosted CI pending publication.

V4-13 additions use the [compiler CLI](../gauge/cmd/eidolons-gauge/compiler.go), [compiler contract](../gauge/internal/contract/compiler.go), [store](../gauge/internal/store/compiler.go), [controller](../gauge/internal/controller/compiler.go), and [spec/decision](../.spectra/changes/gauge-v4-13/spec.md). Local fixture anchors are recorded in the [V4-13 receipt](campaigns/gauge/receipts/V4-13.md). No mandatory agent chains; no V4-14+; hosted CI pending publication.
