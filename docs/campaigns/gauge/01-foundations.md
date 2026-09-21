# Stage 1 — Evidence floor and a narrow Go seam

Fix the existing journal and receipt semantics, then reuse their fixtures at a narrow typed Go boundary. Do not implement future budget state twice.

Read [HANDOFF.md](HANDOFF.md) and [ARCHITECTURE.md](ARCHITECTURE.md). [plan.yaml](plan.yaml) owns package identities, dependencies and source routing. Each table below owns its EARS requirements; verification entries are planned cases, not executed results. Assign one package, and one named slice where applicable.

<a id="v4-04"></a>

## V4-04 — Repair journal ordering and preserve the legacy evidence floor

**Default source owner:** `Rynaro/eidolons`. **Prerequisites:** `V4-01`. Stage gates also apply.

**Starting points:** `cli/src/ledger.sh`, `cli/src/run.sh`, `schemas/`, `cli/tests/`. Resolve symbolic/new paths in the actual checkout; they are not claims those interfaces already exist.

**Scope and decisions.** Minimal current-kernel repair for G01. Serialize allocation and publication, validate predecessor linkage, and make read paths side-effect-free. Preserve a reusable conformance fixture suite for the Go implementation; do not build future budget transactions twice in Bash.

**Implementation sequence.** Reproduce numeric-order and concurrent-writer faults. Add a bounded ownership/append primitive and legacy reader checks. Freeze language-neutral input/output and failure fixtures for V4-06.

| ID | EARS requirement | Planned verification |
|---|---|---|
| V4-04-R01 | WHEN accepted events are appended to a run, the journal SHALL preserve a unique numeric order with valid predecessor linkage. | **V4-04-T01:** Append 120 events; independently recompute the full chain across 9/10 and 99/100 boundaries. |
| V4-04-R02 | WHEN concurrent writers submit distinct event identities, the journal SHALL retain every accepted identity exactly once. | **V4-04-T02:** Barrier-synchronized writers plus duplicate submissions; compare identity sets and payloads, not only counts. |
| V4-04-R03 | IF a writer is interrupted during append, THEN recovery SHALL classify incomplete state without losing published events. | **V4-04-T03:** Inject failure before publication, after publication, and while owning the lock; test stale-owner handling and bounded timeout. |
| V4-04-R04 | WHEN an unknown run is inspected, the journal reader SHALL leave the filesystem unchanged. | **V4-04-T04:** Snapshot before/after status on absent run; assert explicit unknown result and no new directory. |
| V4-04-R05 | IF event history is corrupt or unsupported, THEN the reader SHALL withhold a successful evidence projection. | **V4-04-T05:** Malformed JSON, broken chain, duplicate sequence, legacy-version and valid legacy controls; no silent discard. |

**Exit.** Map every requirement above to observed evidence or a named blocker. Read HANDOFF.md for mechanical, independent, CI and live-evidence distinctions. Unavailable mandatory evidence prevents acceptance; a fixture-only candidate can be ready for review without claiming live qualification.

**Stop and rollback.** Keep original events readable and never overwrite history during repair/import. Document supported filesystems and distinguish atomic rename from proven power-loss durability.

---

<a id="v4-05"></a>

## V4-05 — Current-candidate completion and generated evidence

**Default source owner:** `Rynaro/eidolons`. **Prerequisites:** `V4-04`. Stage gates also apply.

**Starting points:** `cli/src/ledger.sh`, `cli/src/check_change_specs.sh`, `schemas/`, `Makefile`, `.github/workflows/ci.yml`. Resolve symbolic/new paths in the actual checkout; they are not claims those interfaces already exist.

**Scope and decisions.** Correct G02/G03 semantics before Go migration. Distinguish authored claims, observed checks, and derived verdicts. Store volatile evidence once and render views. A legacy/manual checker label is not trusted invocation provenance; record its lower grade honestly. Actual protected execution arrives in V4-14.

**Implementation sequence.** Characterize pass/fail projection and candidate identity. Add conservative invalidation and explicit evidence grades. Generate summaries and exercise schema/reference/negative gates before review.

| ID | EARS requirement | Planned verification |
|---|---|---|
| V4-05-R01 | WHEN an applicable mandatory check fails after a previous pass, the completion projector SHALL report the candidate as not accepted. | **V4-05-T01:** Pass-fail-pass for the same mandatory check; unrelated historical failure and different-candidate controls. |
| V4-05-R02 | WHEN acceptance-relevant candidate inputs change, the completion projector SHALL invalidate dependent verification evidence. | **V4-05-T02:** Tracked and required untracked source, symlink/mode, criteria, and relevant environment/configuration mutations; conservative invalidation is acceptable initially. |
| V4-05-R03 | IF checker provenance is only a supplied label or maker identity is absent, THEN the projector SHALL withhold an independent-verification grade. | **V4-05-T03:** Same invocation renamed twice, absent maker, forged fields, and trusted fixture invocation with recorded context access. |
| V4-05-R04 | WHEN an evidence view is generated, the renderer SHALL derive volatile fields from the canonical observation record. | **V4-05-T04:** Injected clock/golden fixtures; change a result or hand-edit a view and verify regeneration/drift detection. |
| V4-05-R05 | IF a mandatory check is missing, stale, cancelled, or tied to another candidate, THEN the completion projector SHALL withhold acceptance. | **V4-05-T05:** Mixed receipts, missing evidence objects, empty check set, and cancelled runner; no prose claim overrides the result. |
| V4-05-R06 | WHEN a completion claim is rendered, the CLI SHALL distinguish artifact integrity, execution provenance, and acceptance status. | **V4-05-T06:** Assert independent typed fields; a matching hash or successful command alone cannot set all fields to verified. |

**Exit.** Map every requirement above to observed evidence or a named blocker. Read HANDOFF.md for mechanical, independent, CI and live-evidence distinctions. Unavailable mandatory evidence prevents acceptance; a fixture-only candidate can be ready for review without claiming live qualification.

**Stop and rollback.** Keep legacy records marked legacy/self-attested; never silently upgrade them. Exclude only declared evidence/build outputs from candidate hashing, not acceptance-affecting source/tests/docs.

---

<a id="v4-06"></a>

## V4-06 — Introduce a thin Go controller and typed execution contracts

**Default source owner:** `Rynaro/eidolons`. **Prerequisites:** `V4-04`, `V4-05`. Stage gates also apply.

**Starting points:** `cli/eidolons`, `cli/src/ledger.sh`, `schemas/`, `docs/architecture.md`, `Junction: internal/ (inspect actual tree)`. Resolve symbolic/new paths in the actual checkout; they are not claims those interfaces already exist.

**Scope and decisions.** Introduce a narrow opt-in Go command seam, not full CLI parity. Define separate profile, assignment, worker, context, authority, candidate, receipt, and root-task identities. Choose and document one transactional local storage implementation and supported filesystem/durability boundary; SQLite is a candidate, not assumed installed. Reuse verified Junction/tonberry/atomos code only after license and dependency review. Keep protocols modular; no single-page spec constraint.

**Implementation sequence.** Freeze typed interfaces and compatible version rules from existing fixtures. Implement a local vertical seam with injected clock/ID/adapter dependencies and a single authoritative writer. Run differential and recovery fixtures through legacy and Go paths.

| ID | EARS requirement | Planned verification |
|---|---|---|
| V4-06-R01 | WHEN a profile is loaded, the controller SHALL represent its identity separately from worker and context identities. | **V4-06-T01:** One worker with two methods and two workers with one profile; assert distinct identifiers and references. |
| V4-06-R02 | WHEN an opt-out consumer invokes an existing command, the CLI SHALL preserve its established behavior. | **V4-06-T02:** Supported command compatibility fixtures, stdout/stderr/exit codes, and no-Gauge install controls. |
| V4-06-R03 | IF controller state uses an unsupported version, THEN the controller SHALL reject managed execution without mutating that state. | **V4-06-T03:** Future schema, missing migration, and partially imported fixture with read-only diagnostic. |
| V4-06-R04 | WHEN legacy journal state is imported explicitly, the migration SHALL preserve event identity and original evidence grade. | **V4-06-T04:** Repeat import, interruption, rollback read, and one-writer tests against V4-04/V4-05 fixtures. |
| V4-06-R05 | WHEN an authoritative state mutation commits, the store SHALL publish its dependent state updates atomically within the declared storage boundary. | **V4-06-T05:** Fault injection, concurrent mutation and replay tests; document actual durability settings and network-filesystem exclusions. |
| V4-06-R06 | WHEN fixture execution completes through the Go seam, the controller SHALL emit observed results without invoking an LLM for bookkeeping. | **V4-06-T06:** Fake adapter with model-call counter; hash, status, retry count, and receipt generation create no model request. |

**Exit.** Map every requirement above to observed evidence or a named blocker. Read HANDOFF.md for mechanical, independent, CI and live-evidence distinctions. Unavailable mandatory evidence prevents acceptance; a fixture-only candidate can be ready for review without claiming live qualification.

**Stop and rollback.** Opt-out consumers stay on the shell path. Migration is explicit and resumable; no dual-write source of truth and no automatic upgrade of evidence trust.

---
