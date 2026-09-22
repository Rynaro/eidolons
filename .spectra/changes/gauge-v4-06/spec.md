# V4-06 implementation contract (preparatory)

Canonical plan c581308f055a0e252013bf09f2a7b2e1426ff811 supplies requirements below. Implementation waits for reviewed V4-05 source and its language-neutral fixtures. This artifact records design boundaries, not observed acceptance.

## Resolved scope

Introduce one opt-in Go controller seam, not full CLI parity or native reasoning. Use a dedicated Go module and typed packages under a narrow directory selected after inspecting the frozen V4-05 tree. Existing opt-out commands and installation remain usable without Go. Package a reproducible controller build and explicit binary selection; no automatic network/toolchain download at runtime. Pin Go/dependencies and add Linux/macOS build/test CI without replacing existing gates. Document keep/shim/unsupported compatibility.

Conditional store selection and evidence gates: copy the actual FORGE decision from /private/tmp/gauge-v4-06-decision.md. bbolt v1.5.0, sync enabled; local Linux/macOS only after tests. Read-only schema preflight, then version recheck in every mutation. Reject corruption/future/missing migration without recreating state. One transaction governs all dependent typed state; never hold it across external operations. Explicit bounded lock wait and copied values. Fault tests cover callback rollback, controlled process kill around commit, independently reopened state and concurrency. No power-loss claim.

Import must preserve original journal bytes, original identity and lower evidence grades. Validate the exact V4-04 legacy jq canonical hash including LF: do not reserialize with encoding/json and call it compatible. Preserve04/05 fixtures; compare typed projections with the frozen old implementation, include invalid fixtures. Explicit idempotent migration captures a frozen inventory. Legacy remains readable, but Bash writers must reject after promotion. Authority marker and DB cannot be one filesystem transaction: define staged/recoverable fail-closed handoff and prevent two importers or a Bash writer from splitting authority. Unexpected/incomplete states require explicit recovery and retain original files. No automatic fallback writes after Go ownership.

Four state families and separate root, assignment, profile+method, worker/invocation, context, authority, candidate, receipt and environment IDs. Define versioned configuration manifest: requested model differs from observed model, unknown remains unknown. Inject clock, ID allocation and fake adapter. Fixture bookkeeping must produce zero model calls. Replace process and environment independently while durable identity and references remain unchanged; unsupported reconstruction explicit.

No Junction import justified: /private/tmp/gauge-v4-06-junction-reuse.md documents actual Apache-2.0 source inspection. Do not import a framework or build managed dispatch/budget scheduling early.

## Tooling and validation

Host Go absent. Isolated official golang:1.27.1-bookworm@sha256:69a7b9788769bec032d238959b61854e9ae87f57be9029ec04e9885fabf99195 qualified as go1.27.1 linux/arm64. Shared caches /private/tmp/gauge-go-modcache and /private/tmp/gauge-go-buildcache; bbolt1.5.0 downloaded and license checked MIT. Dependency network fetch separate from network-disabled tests. Native macOS execution remains a required hosted CI check, not inferred from cross compilation.

Author named V4-06 T01–T09 executable anchors before code; genuine behavior red, protected actual sandbox execution, repeated green, explicit fault evidence, distinct fresh checker. Full Go race/test/build where supported, existing CLI regression and opt-out behavior. Do not substitute missing commands/dependencies for behavioral red evidence. Record limits honestly.

## V4-06 — Introduce a thin Go controller and typed execution contracts

**Default source owner:** `Rynaro/eidolons`. **Prerequisites:** `V4-04`, `V4-05`.

**Starting points:** `cli/eidolons`, `cli/src/ledger.sh`, `schemas/`, `docs/architecture.md`; inspect actual Junction `internal/` before any reuse. Locate actual paths in the pinned checkout; proposed interfaces are not claims of existing code.

**Scope and decisions.** Introduce an opt-in seam, not full CLI parity. Keep profile, assignment, worker, context, authority, candidate, receipt, environment, and root identities distinct. Select one local transactional store with tested packaging/durability limits; SQLite is a candidate, not an assumed dependency. Capture the small store decision here, not another campaign. Preserve history, active context, reusable memory, and authority as different state families. Native harnesses own reasoning/edit-test loops.

**Implementation sequence.** Freeze contracts and compatibility matrix from fixtures; select/store the durability decision; implement injected clock/ID/adapter dependencies and one authoritative writer; run differential recovery tests. No framework adoption or source import is required beyond a specifically justified, license-checked seam.

| ID | EARS requirement | Planned verification |
|---|---|---|
| V4-06-R01 | WHEN a profile is loaded, the controller SHALL represent its identity separately from worker and context identities. | **V4-06-T01:** One worker with two methods and two workers sharing one profile; verify distinct IDs and links. |
| V4-06-R02 | WHEN an opt-out consumer invokes an existing command, the CLI SHALL preserve its established behavior. | **V4-06-T02:** Supported command, exit/stdout/stderr, and no-Gauge installation fixtures. |
| V4-06-R03 | IF controller state uses an unsupported version, THEN the controller SHALL reject managed execution without mutating that state. | **V4-06-T03:** Future schema, missing migration, partial import; compare bytes after read-only diagnostics. |
| V4-06-R04 | WHEN legacy journal state is imported explicitly, the migration SHALL preserve event identity and original evidence grade. | **V4-06-T04:** Repeat/interrupted import, rollback reads, and single-writer tests against V4-04/V4-05 fixtures. |
| V4-06-R05 | WHEN an authoritative state mutation commits, the store SHALL publish its dependent state updates atomically within the declared storage boundary. | **V4-06-T05:** Fault injection, concurrent mutations, and replay; record durability settings and excluded filesystems. |
| V4-06-R06 | WHEN fixture execution completes through the Go seam, the controller SHALL emit observed results without invoking an LLM for bookkeeping. | **V4-06-T06:** Fake adapter call counter; hashing, status, retry counts, and receipt generation produce no model calls. |
| V4-06-R07 | WHEN controller state is persisted, the state contract SHALL distinguish durable history, working-context references, reusable knowledge, and authoritative policy records. | **V4-06-T07:** Round-trip typed fixtures; reject a recalled note supplied as a policy record and a context summary supplied as a receipt. |
| V4-06-R08 | WHEN a harness process or execution environment is replaced, the controller SHALL preserve the task's durable identity independently of that process or environment. | **V4-06-T08:** Replace each independently; task root, policy, candidate, intents, and evidence remain linked; unsupported reconstruction stays blocked. |
| V4-06-R09 | WHEN an execution configuration is bound to a task, the controller SHALL record a versioned manifest of its model, harness, adapter, methods, environment, and policy references. | **V4-06-T09:** Change each constituent separately and observe a new manifest identity; unknown observed model remains explicit rather than copied from requested settings. |

**Exit.** Apply the common exit above and the package scope; missing required live evidence blocks its live claim, not disclosure of completed fixture work.

**Stop and rollback.** Preserve user work, canonical history, and unresolved exposure; disable the new path without restoring stale acceptance or wider authority.

## Qualified combined local runner

Root built `eidolons-gauge-go-qualified:local` from the existing qualified CLI image plus the pinned official Go toolchain and Debian GCC/libc development packages. Image manifest digest: `sha256:d9b4537412ed447276fbf3a745c3c953f254d412e70da57b5888831a0d61c795`. Go 1.27.1, Bats 1.11.1, jq 1.7, PyYAML 6.0.2. Real `go test -race` passing control succeeded and deliberately failing assertion returned exactly exit 1; wrapper returned success only after checking both. Evidence: `/private/tmp/gauge-go-runtime-probe.log`, Dockerfile `/private/tmp/gauge-go-test.Dockerfile`, build log `/private/tmp/gauge-go-test-build.log`. This qualifies the runner, not candidate behavior.

Use `--network none --read-only --cap-drop ALL --security-opt no-new-privileges`, read-only source mount, writable dedicated build/module caches, and `--tmpfs /tmp:rw,exec,nosuid` with explicit working directory. Go test binaries require the executable container-local tmpfs; default tmpfs was noexec and correctly failed, so that earlier run is excluded. `GOTOOLCHAIN=local` prevents an implicit toolchain download. Set GOCACHE and GOMODCACHE to mounted caches. Host Go remains absent; macOS qualification still requires actual hosted execution.

## Accepted maker interface preparation

Actual continuing maker `vivi_v4_core` performed read-only preparation and acknowledged these boundaries; no V4-06 source exists yet. Module `gauge/`, module path `github.com/Rynaro/eidolons/gauge`, command `gauge/cmd/eidolons-gauge`, narrow internal contract/store/legacy/controller packages. Add a `gauge)` dispatcher and `cli/src/gauge.sh` that selects an explicit `EIDOLONS_GAUGE_BIN` or packaged binary. Missing binary is actionable; never implicitly invoke Go, download anything, or fall back to legacy writes. Existing install and opt-out commands remain unchanged except the mandatory authority guard in the journal writer. Add separate Makefile build/test/package targets and Linux/macOS Gauge CI. Include required dependency and toolchain license notices with distributable artifacts.

IMPORTANT: the maker initially proposed a DB per execution. Root corrected this before implementation and the maker explicitly acknowledged: use ONE shared controller-instance bbolt DB, with separate typed root/execution records. Per-run markers bind that shared DB identity and the frozen import inventory. A feature-owned shared location under `.eidolons/.ledger` may reuse the existing fixed candidate exclusion, but detect occupied legacy run-name/path collisions and never overwrite them. Atomicity applies within that controller instance; no cross-instance, account-wide or cross-device coverage claim. This preserves a transaction boundary for later independently applicable resource scopes without implementing their scheduler now.

Import stages a validated frozen inventory before transfer. Promotion takes existing append ownership, revalidates inventory, records a pending transfer, commits matching authority generation and imported state, then finalizes the marker. Pending/disagreeing states reject writes and require explicit recovery. Prove interruption boundaries, competing importers and a concurrent Bash writer. Never use PID-only lock stealing. All mutators, including Go mutations of newly created roots, must obey the single-authority invariant. Legacy files remain readable as explicitly historical imported evidence; never present them as current authoritative Go state. A missing Go binary cannot reopen Bash writes.

Go projection covers imported typed observations and existing pure projection fixtures. Do not introduce a second filesystem candidate engine or production trust source. Any unsupported current-candidate acceptance remains explicitly unavailable; imported self-attested history cannot be upgraded.

Executable anchors: `bats --print-output-on-failure --filter 'V4-06 T0N ' gauge/tests/conformance.bats`, for N=1..9, invoking matching `TestV406T0N` package tests with `go test -race -count=1`. Keep these outside ordinary CLI test discovery so no-Go installations retain compatibility. Full regression includes existing V4-04/V4-05 anchors. Initial meaningful red exercises a valid existing Bash append against staged/future authority markers; command-not-found or compilation failures do not prove that gate.

T01 identity links; T02 opt-out stdout/stderr/exit and missing-binary/no-Go installation, historical promoted reads; T03 future/corrupt/missing-migration/partial states with unchanged diagnostic bytes; T04 original bytes/IDs/grades, valid/invalid fixtures, repeat/conflict/interruption/recovery and shared-writer barriers; T05 atomic rollback, barrier concurrency, process kill around commit, independent reopen and exactly-once retry; T06 fake adapter and zero model bookkeeping calls; T07 four state families and substitution rejection; T08 independent process/environment replacement without resetting durable references; T09 each manifest constituent changes identity and unknown observed model remains unknown.

Build with `GOTOOLCHAIN=local`, `-mod=readonly`, `-trimpath`, `-buildvcs=false`. Record the actual filesystem/runtime boundaries exercised by store tests. Process interruption is not power-loss qualification.


Implementation base: 50e8553423dd19620e75a5a0d98a7ba4a9418528. Predecessor acceptance is recorded in the committed V4-04 and V4-05 receipts and their checker/CI/lifecycle artifacts.
