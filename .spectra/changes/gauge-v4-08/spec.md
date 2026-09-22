# V4-08 preparatory implementation contract

Canonical authority: plan c581308f055a0e252013bf09f2a7b2e1426ff811. Implement only after predecessor code, tests and distinct review satisfy the DAG. No implementation or live qualification is claimed by this preparation. All applicable canonical requirements below remain binding. The attached actual FORGE decision resolves bounded implementation choices; it cannot grant runtime authority.

## V4-08 — Root lineage and honest multidimensional observations

**Default source owner:** `Rynaro/eidolons`. **Prerequisites:** `V4-06`, `V4-07`.

**Starting points:** `cli/src/telemetry.sh`, `cli/src/trace.sh`, `cli/src/lib_context.sh`, `schemas/`. Locate actual paths in the pinned checkout; proposed interfaces are not claims of existing code.

**Scope and decisions.** Keep token/cache/context, currency, allowance, elapsed time, compute, concurrency, and human effort distinct. Define cumulative/delta/correction semantics and overlap rules. Capture actual host-visible payload where observable and mark estimates/unknown dimensions. Alias only legitimately shared pools belonging to the same operator. Do not persist credentials, hidden reasoning, or raw private transcripts.

**Implementation sequence.** Implement provenance/units/freshness and lineage; reconcile duplicate/late data; add causal event references and privacy-preserving inspection; expose incomplete coverage to admission and evaluation.

| ID | EARS requirement | Planned verification |
|---|---|---|
| V4-08-R01 | WHEN a new task begins, the controller SHALL allocate an execution root distinct from its route digest. | **V4-08-T01:** Identical prompts/routes create different roots; resume retains the original root. |
| V4-08-R02 | WHEN a descendant, reviewer, retry, or successor is created, the controller SHALL bind its observations to the original task root. | **V4-08-T02:** Role/context/provider switches and child escalation cannot reset budget identity. |
| V4-08-R03 | WHEN a usage observation is recorded, the collector SHALL include its unit, source grade, observation time, and freshness state. | **V4-08-T03:** Observed, estimated, self-attested, unsupported, stale, and unknown fixtures; cache and allowance fields stay distinct. |
| V4-08-R04 | WHEN duplicate, corrected, or cumulative usage arrives, reconciliation SHALL account for each underlying consumption event once. | **V4-08-T04:** Out-of-order callbacks, snapshots, parent/child overlap, and late correction against independently computed totals. |
| V4-08-R05 | IF allowance, pricing, or actual model identity is unavailable, THEN the report SHALL present that dimension as unknown or unsupported. | **V4-08-T05:** Missing pricing, stale reset, unobserved model, and provider buckets; no zero/unlimited substitution. |
| V4-08-R06 | WHEN observations are persisted, the collector SHALL omit credentials, hidden reasoning, and raw private payloads. | **V4-08-T06:** Secret canaries, retention, and export controls; useful metadata without raw transcripts. |
| V4-08-R07 | WHEN an execution event is recorded, the collector SHALL link it to its task, assignment, invocation, configuration, and applicable candidate or intent. | **V4-08-T07:** Follow dispatch-to-check-to-verdict lineage; missing parent and late events remain identifiable rather than inventing lineage. |
| V4-08-R08 | WHEN resource use is summarized, the collector SHALL report coverage separately for inference, context/tool transfer, environment work, elapsed time, and human interventions. | **V4-08-T08:** Hidden child usage, cached versus uncached input, setup time, and manual work; unavailable dimensions are not omitted from completeness reporting. |

**Exit.** Apply the common exit above and the package scope; missing required live evidence blocks its live claim, not disclosure of completed fixture work.

**Stop and rollback.** Preserve user work, canonical history, and unresolved exposure; disable the new path without restoring stale acceptance or wider authority.

---


## Bounded decision

# V4-08 observation contract — actual FORGE decision transcription

Actor forge_v4_06, two-pass reasoning from supplied exact R01–R08/T01–T08, pinned architecture c581308f055a0e252013bf09f2a7b2e1426ff811 and supplied baseline route digest as run identity. No source inspection/execution. Root transcribes verdict; CRYSTALIUM unavailable. Architectural confidence80%, not runtime reliability. Implementation waits for06/07.

Selected explicit consumption identities and coverage-based reconciliation over cumulative-only or event-only authority. Missing source identity/coverage remains partial/unknown, never manufactured from timestamps or maximum values. Preserve observations; derive reproducible totals only with qualified semantics.

Distinct root/route/task/assignment/invocation/configuration/policy/candidate/intent/causal-event/observation/stream/coverage identities. Stream = source+adapterversion+account/poolreference+dimension+unit+scope+counterepoch. Never implicitly merge epochs or units. Stable namespaced observation ID deduplicates identical bytes; conflicts reject. Correction has own unique ID and names replaced observation/revision; preserve both; forks/cycles reject; correction before target pending and contributes nothing. Missing causal parent remains identifiable, no latest-root guess or route-hash ancestry.

Delta identifies disjoint event/segment. Cumulative identifies explicit known baseline and prefix end cursor within epoch. Latest validated prefix covers its deltas; only proven disjoint suffix deltas add. Covered data retained for breakdown. Unknown baseline cannot mean zero; reset needs new explicit epoch; unexplained decrease inconsistent, not refund/clamp. Rule/version recorded. Unknown coverage yields incomplete/unknown combined total.

Parent scope is exclusive, inclusive with explicit descendant/work membership, or unknown. Deterministic disjoint accounting frontier counts inclusive parent once, retaining covered child breakdown. Partial overlap needs exact decomposition or incomplete state; hidden descendants remain coverage gap even when aggregate known.

Keep tokens including cached/uncached, context/tool transfer, currency, allowance/window, environment work, elapsed time, concurrency and human interventions separate. Unit, source grade, observation time, receipt time, freshness; grade differs from completeness. Requested model != observed model. Unknown price => unknown cost; observed tokens × estimated price => estimated cost. Stale reset never unlimited. Pool alias only independently authorized same-operator genuinely shared pool; labels/model proposals cannot authorize. Aliases don't erase windows or prove overlap.

Typed metadata allowlist, bounded validated IDs, no raw prompts/transcripts/reasoning/credential/body/envdump/toolargs/arbitrarydiagnostics or free-text escape hatch. Actual visible payload measured only where exposed; persist permitted counts/references, mark estimates, don't substitute file bytes. Same allowlist storage/errors/exports; secret detector supplementary. No private-payload fingerprint without need. Retention removes eligible detailed metadata but preserves necessary totals/lineage/exposure and marks lostcoverage, never resets consumption.

Independent fixtures: deltas cursor1..4=[3,4,5,2]; prefix through3=12, total14 any arrival order/duplicates. Replace suffix2 with1 =>13, duplicate correction still13. New prefix through4=13 remains13; late prefix2=7 addsnothing. Explicit disjoint newepoch zero-baseline2 =>15, otherwise unknown. Parentinclusive13 with child5=>13; parentexclusive8+child5=>13; unknown inclusion incomplete. Conflicting duplicate, correctionfork/unknown target, missingparent, crossroot retry, ambiguous epoch remain explicit. Pricing/model/reset/hiddenchild unknowns and canaries tested. Every summary includes inference/transfer/environment/elapsed/human coverage. Expected arithmetic comes from independent inventory, not implementation output.

run.sh: fresh UUID for each new task, route digest separate; explicit resume resolves existing durable root, unknownroot fails. Descendant/reviewer/retry/successor validated inheritance, process/context/provider/environment replacement never new budgetroot. No prompt equality/routefolder implicitresume. Legacy optional telemetry can remain optional but cannot substitute routehash for managedroot or claim complete coverage.

No admission-budget implementation, accuracy or live-host qualification claimed. Narrow unsupported adapters rather than guessing identities/coverage. Late correction to already-covered prefix requires explicit additional rule below before implementation.

Actual FORGE follow-up resolves late-prefix correction: invalidate previous reconciliation. If snapshot explicitly identifies covered observation versions and source contract proves additive coverage, derived replacement = snapshot - oldcoveredvalue + correctedvalue, once per correction identity. Otherwise currenttotal unknown/incomplete pending reconciliation; oldsnapshot historical only. Never add full correction, retain stale current total or assume a newer snapshot absorbed it. Replacement snapshot explicitly establishes incorporation. Fixture deltas3,4,5 snapshot12; replace4→2 =>10 with proven versions; duplicate still10; unproven versions currentunknown; replacement snapshot explicitly incorporating =>10 with no second adjustment.


## Common implementation controls

Extend the V4-06 Go seam and its single authoritative transaction store. Preserve opt-out CLI compatibility and existing fixtures. Use injected dependencies and deterministic independent arithmetic; no model calls for bookkeeping. Freeze named conformance anchors before implementation, retain actual failure and passing execution evidence, preserve protected tests during repairs, and use a distinct artifact-context checker. Keep fixture evidence separate from live host and security qualification. No new paid probes, release, deployment or merge approval is implied.


## Baseline integration inspection

Actual read-only ATLAS findings are in `/private/tmp/gauge-v4-08-integration-scout.md` (SHA-256 `eae7c6a250f1b2b2fe687e68e0ea80a463a47665f54374b3f8493e4eb81670e3`). Copy this artifact into the change at proposal. The original-main route digest, ordinal telemetry IDs, timestamp attribution, project slug and context handoff references do not establish managed execution identity or causal ancestry. Keep them as legacy source references where useful. Existing telemetry silently substitutes zero for missing usage and silently ignores conflicting duplicate IDs; externalization repeatedly records meter estimates without cumulative/delta identity. Do not reuse those semantics for Gauge consumption. Existing full-row exports are not the new metadata allowlist. Preserve opt-out behavior and the scout's named compatibility fixtures while extending the accepted Go store and lineage contracts.


## Publication and CI boundary

Automatic approval review blocked public publication of newly created V4-06 implementation source, including a retry after same-origin/public-repository and payload verification. No further publication attempt is permitted without explicit user approval. Continue authorized local implementation against independently reviewed, locally qualified fixture contracts. Record hosted CI as pending/blocked, never as passed or not applicable. Native macOS Go checks use a temporary official Go 1.27.1 toolchain whose archive SHA-256 is verified against go.dev; qualified Linux container checks remain separate. This permits local successor development, not a merge/release or a live qualification claim. Present completed local branches for publication approval after the authorized implementation work is concrete and reviewable.


## Frozen predecessor Go seam map

Actual ATLAS map `/private/tmp/gauge-v4-08-go-seams.md`, SHA-256 `c91582256bec0aca5ece791b274eea31698f974265a1481215e5f24cb5a96318`, inspects accepted V4-06 aa155c8. Copy into proposal and re-anchor schema/policy and mutation APIs against accepted V4-07 before implementation. Existing fixture receipts/current mutable binding and legacy raw status are not usage collectors, durable historical invocation identity or a private-data-safe managed export. New root-linked APIs retain append ownership and claim/inventory validation. Preserve historical legacy raw bytes while keeping new observation storage/export/error boundaries strictly typed.


## Provisional V4-07 API map

`/private/tmp/gauge-v4-08-policy-seams-provisional.md` is an actual ATLAS public API delta map from a frozen first-repaired V4-07 copy. SHA-256 `b8e4c1bb7b95fdbd8907e175368be8983b2a145b23849cad6a7d2bb54e75cc0e`. It is explicitly unaccepted: final serialization and numeric repairs plus final V4-07 review must be applied/re-anchored. Typed PolicyBinding distinguishes latest PolicyID from ActivePolicyID; no binding is invented by migration. New08 mutators retain controller append lock/active proof checks before store transactions. Policy amendment replay is not resource observation dedup or pool-alias authority.

---

## Implementation re-anchor (V4-07 → V4-08)

Accepted implementation base: `4b3e499293e65b3567b47eb14b220743d3ff0773` (V4-07 merged via #605).
Plan commit: `c581308f055a0e252013bf09f2a7b2e1426ff811`.

Re-anchored against current main (not the provisional V4-07 harness copy):

- Schema remains **2**. Observation/lineage use additive typed buckets under schema 2 with `meta.observation_receipt` (typed_version=1). No schema 2→3 bump.
- New stores call `initializeObservation` after `initializePolicy`. Pre-V4-08 schema-2 stores stay openable; `EnsureObservationNamespaces` / `observation-enable` / `task-start` create buckets explicitly.
- Root mutators retain V4-06 append lock + `active` claim/inventory checks and V4-07 policy immutability. Observation recording does not authorize policy amendments or spending.
- Public APIs: `StartTask`, `ResumeRoot`, `BindLineage`, `RecordUsage`, `CorrectUsage`, `SummarizeUsage`, `ExportUsage`, `RetainUsage`, `EnsureObservationNamespaces`.
- CLI: `observation-enable`, `task-start`, `task-resume`, `lineage-bind`, `usage-record`, `usage-correct`, `usage-summary`, `usage-export`, `usage-retain`.
- Pure reconciliation: `contract.Reconcile` / `ReconcileObservations` / `EstimateCost` with independent vector oracles in `reconcile_vectors_test.go`.
- Anchors: `TestV408T01`–`TestV408T08` via `gauge/tests/observation-anchors.sh`, wired into `make gauge-test`.

