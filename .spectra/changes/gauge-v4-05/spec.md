# V4-05 — Current-candidate completion and generated evidence

Authority: pinned plan c581308f055a0e252013bf09f2a7b2e1426ff811, docs/campaigns/gauge/01-foundations.md#v4-05 and ARCHITECTURE.md. Prerequisite V4-04 accepted source/CI/lifecycle evidence is bound at proposal. Only V4-05 is implemented in this change.

## Canonical package requirements

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


## Selected implementation contract

# V4-05 implementation mission (preparatory until V4-04 accepted)

Canonical authority: plan c581308f055a0e252013bf09f2a7b2e1426ff811 docs/campaigns/gauge/01-foundations.md V4-05 R01-R07/T01-T07 and ARCHITECTURE.md. Scout /private/tmp/gauge-v4-05-probe.log; FORGE /private/tmp/gauge-v4-05-decision.md. Implement only after root creates isolated worktree, lifecycle and explicit writer handoff. V4-04 candidate85a8541 on PR602 awaits hostedCI.

Selected design: keep V4-04 canonical history as authority; embed every acceptance decision input in typed captured observations, reference bulky supporting evidence with digests. No second acceptance database. Current candidate snapshot conservatively binds tracked/relevant required-untracked source/tests/docs, path kinds/modes/symlink identity, integration base, criteria, explicit relevant environment/configuration. No user-defined exclusions that can hide acceptance inputs. Explicit fixed feature-owned outputs only, outside candidate where possible. Unsupported external symlink or missing relevant input fails closed. Do not claim a mutable snapshot freezes/protects execution.

Require nonempty mandatory check IDs bound to full identity tuple. Latest applicable sequence wins, not last historical pass. Missing/stale/cancelled/wrongcandidate/missingobject or changedbytes withholds acceptance. Unrelated historical failures do not poison current applicable evidence. Legacy/manual checker labels, absent maker, supplied independent fields and generic forged checked events remain self-attested, never independently accepted. Preserve original event bytes and original declarations; correct their derived projection.

Keep artifact_integrity, execution_provenance and acceptance_status separate and typed. Native/A2A/MCP completion establishes termination only. A test-only pure evaluator harness supplies already-authenticated invocation/context provenance in memory for a positive control. Serialized fixture output copied through production cannot restore trusted provenance; no CLI/env/config trust switch. Protected execution remains14. Production cannot claim independent acceptance before a real qualified provenance source exists.

Generate JSON/text/Markdown views from canonical captured observations/projection inputs. Capture timestamps/invocation IDs once, not on rendering; exact regeneration detects hand edits. Candidate/evidence revalidation failures visible. Do not add unrelated TTL policy; if time-based freshness is added its evaluation clock must be explicit and frozen for deterministic saved views.

Test anchor file: cli/tests/completion_conformance.bats, titles V4-05 T01..T07. Tests must exercise production CLI negative paths AND pure evaluator legitimate positive control; cannot pass only because production always blocks. Freeze language-neutral candidate/observation/expected-projection fixtures for06 import. Update existing ledger expectations explicitly (old manual label accepted case changes by design) while retaining04 interruption/integrity/retry protections.

Implementation boundaries: brownfield ledger/projection enhancement, no Go06 early, no protectedrunner14, no new managed/model/API calls, no paidtrials. Reuse helpers where correct. If a small Python3 stdlib adjunct is needed for deterministic snapshots/typed pure projection, make the new command dependency explicit and fail with an actionable diagnostic; do not silently fall back to legacy success. Preserve existing routing's optional failure-suppressed instrumentation. Root handles docs/lifecycle/commits/PR after makerYIELD. Source/test writer single; distinctchecker after stablecandidate. No sourcechanges until explicitin_progresshandoff.

## Resolved interface boundaries

Use ledger candidate/typed complete/current status and explicitly historical captured-projection rendering, with a Python3 stdlib completion helper and one typed completion schema. Keep Bash/jq as journal writer and validator; ordinary open/record and optional run instrumentation do not gain Python dependency. Missing Python on completion paths fails with an actionable diagnostic, never legacy-success fallback. New capture requires Git; legacy non-Git events remain readable but unaccepted.

Selection key contains candidate, criteria, environment/configuration, integration base and check/oracle identity. Invocation identity is provenance, not grouping: a later failure from a fresh invocation must displace the prior pass. Unknown context access and absent maker withhold independent grade. No TTL policy.

Typed captures compare stable caller request and freshly recomputed tuple under append ownership before creating timestamp/invocation ID. Matching event-ID retry returns original captured bytes; differing request or tuple conflicts. Generic record cannot opt into volatile-field suppression.

Replace augment evidence raw-array rendering with a narrow canonical-history-reference shim before cache/product-leap initialization. A versioned reference identifies an existing validated journal capture. Empty or nonempty old arrays fail actionably, as do malformed/missing refs; canonical controls render identically and edited views drift. No rendering-clock run IDs or comparative verdict. Other augment verbs remain unchanged; include product_leap regression and document compatibility.

## Planned executable anchors

- V4-05-R01 → V4-05-T01: bats --filter "V4-05 T01" cli/tests/completion_conformance.bats. Bind actual observed evidence before verification.
- V4-05-R02 → V4-05-T02: bats --filter "V4-05 T02" cli/tests/completion_conformance.bats. Bind actual observed evidence before verification.
- V4-05-R03 → V4-05-T03: bats --filter "V4-05 T03" cli/tests/completion_conformance.bats. Bind actual observed evidence before verification.
- V4-05-R04 → V4-05-T04: bats --filter "V4-05 T04" cli/tests/completion_conformance.bats. Bind actual observed evidence before verification.
- V4-05-R05 → V4-05-T05: bats --filter "V4-05 T05" cli/tests/completion_conformance.bats. Bind actual observed evidence before verification.
- V4-05-R06 → V4-05-T06: bats --filter "V4-05 T06" cli/tests/completion_conformance.bats. Bind actual observed evidence before verification.
- V4-05-R07 → V4-05-T07: bats --filter "V4-05 T07" cli/tests/completion_conformance.bats. Bind actual observed evidence before verification.

Implementation base: d1b56bb06bc22a7aab1f6ec8a4a07cb8f68aa138. Prerequisite: V4-04 source accepted on PR602, hosted CI35679172221 and RosterHealth35679147636 all25checks passed; blocking lifecycle verification passed.
