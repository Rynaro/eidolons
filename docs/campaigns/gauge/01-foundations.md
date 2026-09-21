# Stage 1 — Evidence floor and a narrow Go seam

Complete stabilization first, repair journal/completion semantics, and reuse those fixtures at the typed Go boundary. Do not build future transactional budgets twice.

Read [HANDOFF.md](HANDOFF.md) and the relevant [ARCHITECTURE.md](ARCHITECTURE.md) boundaries. [plan.yaml](plan.yaml) owns dependencies and source routing; these tables own requirement text. [RESEARCH.md](RESEARCH.md) explains the evidence-to-design mapping without adding hidden obligations.

**Common exit for every package:** map every applicable Rxx to its planned Txx and actual observed evidence. Exercise relevant rejection paths and the intended gate. Mark unavailable required evidence blocked; mark optional cases not applicable only with their feature/scope condition recorded. Authored requirements, authored tests, executed fixtures, observed CI, and live-host qualification are distinct. A fixture-only candidate can be ready for review without a live-managed claim. See HANDOFF.md for receipts and acceptance.

---

<a id="v4-04"></a>

## V4-04 — Repair journal ordering and preserve the legacy evidence floor

**Default source owner:** `Rynaro/eidolons`. **Prerequisites:** `V4-01`, `V4-02`, `V4-03`.

**Starting points:** `cli/src/ledger.sh`, `cli/src/run.sh`, `schemas/`, `cli/tests/`. Locate actual paths in the pinned checkout; proposed interfaces are not claims of existing code.

**Scope and decisions.** Minimal current-kernel repair with reusable language-neutral fixtures. Serialize allocation/publication, validate predecessor linkage, and keep reads side-effect-free. Do not build future transactional budgets in Bash before porting them. Revision 3 makes the stabilization gate explicit in this dependency list.

**Implementation sequence.** Reproduce numeric-order/concurrent-writer faults; implement bounded append ownership and reader checks; freeze conformance and failure fixtures for V4-06.

| ID | EARS requirement | Planned verification |
|---|---|---|
| V4-04-R01 | WHEN accepted events are appended to a run, the journal SHALL preserve a unique numeric order with valid predecessor linkage. | **V4-04-T01:** Append 120 events and independently recompute the chain across 9/10 and 99/100. |
| V4-04-R02 | WHEN concurrent writers submit distinct event identities, the journal SHALL retain every accepted identity exactly once. | **V4-04-T02:** Barrier-synchronized writers and duplicate submissions; compare identity sets and payloads, not only counts. |
| V4-04-R03 | IF a writer is interrupted during append, THEN recovery SHALL classify incomplete state without losing published events. | **V4-04-T03:** Fail before/after publication and during lock ownership; verify stale-owner handling and bounded timeout. |
| V4-04-R04 | WHEN an unknown run is inspected, the journal reader SHALL leave the filesystem unchanged. | **V4-04-T04:** Snapshot absent-run inspection; explicit unknown result, no new directory or file. |
| V4-04-R05 | IF event history is corrupt or unsupported, THEN the reader SHALL withhold a successful evidence projection. | **V4-04-T05:** Malformed JSON, broken chain, duplicate sequence, unsupported version, and valid legacy control; no silent discard. |

**Exit.** Apply the common exit above and the package scope; missing required live evidence blocks its live claim, not disclosure of completed fixture work.

**Stop and rollback.** Keep original events readable. Distinguish atomic rename from proven power-loss durability and state the supported filesystems.

---

<a id="v4-05"></a>

## V4-05 — Current-candidate completion and generated evidence

**Default source owner:** `Rynaro/eidolons`. **Prerequisites:** `V4-04`.

**Starting points:** `cli/src/ledger.sh`, `cli/src/check_change_specs.sh`, `schemas/`, `Makefile`, `.github/workflows/ci.yml`. Locate actual paths in the pinned checkout; proposed interfaces are not claims of existing code.

**Scope and decisions.** Correct completion before migration. Separate authored claims, observations, and derived verdicts. Store volatile facts once and render views. Manual checker labels retain their lower trust grade. Protected execution arrives in V4-14. Protocol termination is not artifact acceptance.

**Implementation sequence.** Characterize pass/fail projection and candidate identity; add conservative invalidation and evidence grades; generate views; exercise wrong-candidate, missing, and stale evidence gates.

| ID | EARS requirement | Planned verification |
|---|---|---|
| V4-05-R01 | WHEN an applicable mandatory check fails after a previous pass, the completion projector SHALL report the candidate as not accepted. | **V4-05-T01:** Pass-fail-pass for one mandatory check; unrelated historical failure and different-candidate controls. |
| V4-05-R02 | WHEN acceptance-relevant candidate inputs change, the completion projector SHALL invalidate dependent verification evidence. | **V4-05-T02:** Tracked/required-untracked source, symlink/mode, criteria, and relevant environment/configuration mutations; conservative invalidation is valid initially. |
| V4-05-R03 | IF checker provenance is only a supplied label or maker identity is absent, THEN the projector SHALL withhold an independent-verification grade. | **V4-05-T03:** Renamed same invocation, absent maker, forged fields, and a trusted fixture invocation with recorded context access. |
| V4-05-R04 | WHEN an evidence view is generated, the renderer SHALL derive volatile fields from the canonical observation record. | **V4-05-T04:** Injected clock/golden fixture; change canonical outcome or hand-edit a view and detect regeneration drift. |
| V4-05-R05 | IF a mandatory check is missing, stale, cancelled, or tied to another candidate, THEN the completion projector SHALL withhold acceptance. | **V4-05-T05:** Mixed receipts, absent evidence objects, empty required set, and cancelled runner; prose cannot override the projection. |
| V4-05-R06 | WHEN a completion claim is rendered, the CLI SHALL distinguish artifact integrity, execution provenance, and acceptance status. | **V4-05-T06:** Typed independent fields; matching hashes or a successful command cannot set all grades to verified. |
| V4-05-R07 | WHEN a native or inter-agent task reports completion, the projector SHALL treat that event as execution termination rather than acceptance evidence. | **V4-05-T07:** Native success, A2A completed, and MCP tool success with absent/failed acceptance checks remain unaccepted; valid acceptance receipt is the positive control. |

**Exit.** Apply the common exit above and the package scope; missing required live evidence blocks its live claim, not disclosure of completed fixture work.

**Stop and rollback.** Do not silently upgrade legacy/self-attested evidence. Candidate exclusions cannot remove acceptance-affecting source, tests, or documentation.

---

<a id="v4-06"></a>

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
