# V4-07 preparatory implementation contract

Canonical authority: plan c581308f055a0e252013bf09f2a7b2e1426ff811. Implement only after predecessor code, tests and distinct review satisfy the DAG. No implementation or live qualification is claimed by this preparation. All applicable canonical requirements below remain binding. The attached actual FORGE decision resolves bounded implementation choices; it cannot grant runtime authority.

## V4-07 — Persistent Gauge preferences and intersected ceilings

**Default source owner:** `Rynaro/eidolons`. **Prerequisites:** `V4-06`.

**Starting points:** `cli/eidolons`, `cli/src/lib.sh`, `schemas/`, `roster/model-profiles.yaml`. Locate actual paths in the pinned checkout; proposed interfaces are not claims of existing code.

**Scope and decisions.** Provide persistent Conserve/Balanced/Accelerate preferences with field provenance. Preference precedence does not determine authority: hard ceilings intersect. Each authority-bearing field has a trusted authorizer; other sources can restrict but cannot grant it. No preset numbers are considered calibrated. Controlled runtime adaptation selects only approved strategies within the immutable effective contract.

**Implementation sequence.** Validate and atomically persist configuration; compile per-run snapshots; distinguish preference change from explicit authority amendment; register versioned admissible strategy rules and fail-closed validation.

| ID | EARS requirement | Planned verification |
|---|---|---|
| V4-07-R01 | WHEN effective Gauge policy is resolved, the controller SHALL report the origin and resolution of each field. | **V4-07-T01:** Conflicting user/project/run preferences; deterministic normalized output with source classification. |
| V4-07-R02 | WHEN independently applicable ceilings are resolved, the controller SHALL apply their intersection. | **V4-07-T02:** Task/project/account/window/concurrency conflicts; lower run limits cannot become last-writer limit expansion. |
| V4-07-R03 | IF untrusted content requests wider authority or higher ceilings, THEN the controller SHALL reject the requested escalation. | **V4-07-T03:** Model output, repository config, recalled note, and forged setting; separately authorized operator amendment as control. |
| V4-07-R04 | WHEN a run starts, the controller SHALL bind it to an immutable effective-policy identity. | **V4-07-T04:** Change persisted preferences mid-run; old snapshot/consumption persist and authorized amendments form a new linked version. |
| V4-07-R05 | WHEN a preset changes for an otherwise identical task, the policy compiler SHALL preserve mandatory acceptance and authority requirements. | **V4-07-T05:** Compare three preset contracts; optional exploration changes, required checks/permissions do not. |
| V4-07-R06 | IF configuration is invalid or cannot be persisted safely, THEN the CLI SHALL retain the previous configuration. | **V4-07-T06:** Duplicate keys, unknown enum, negative/nonfinite limits, interrupted write, Unicode/spaced paths, and unrelated settings. |
| V4-07-R07 | WHEN an authority-bearing field is resolved, the policy compiler SHALL accept grants only from that field's designated trusted authorization source. | **V4-07-T07:** Restriction-only source adds a deny but cannot populate a missing grant; missing authorizer rejects; composed lower privileges succeed. |
| V4-07-R08 | IF a proposed strategy change alters protected policy, acceptance criteria, or executable controller code, THEN runtime adaptation SHALL reject that change. | **V4-07-T08:** Retrieved playbook and model proposal attempt protected edits; choosing a registered strategy inside the frozen envelope succeeds. |

**Exit.** Apply the common exit above and the package scope; missing required live evidence blocks its live claim, not disclosure of completed fixture work.

**Stop and rollback.** Preserve user work, canonical history, and unresolved exposure; disable the new path without restoring stale acceptance or wider authority.

---


## Bounded decision

# V4-07 policy contract — FORGE decision transcription

Actual actor forge_v4_06 read pinned V4-07 requirements and ARCHITECTURE.md at c581308f055a0e252013bf09f2a7b2e1426ff811, installed FORGE resources and accepted06 store decision. Two passes compared protected operator registry, signed documents and inspection-only compiler. Conditional registry contract plus fail-closed inspection-only default selected; no live protected operator boundary has been qualified. Root transcribes the emitted decision; FORGE made no file mutations. CRYSTALIUM unavailable. Implementation waits for06.

Preferences: deterministic built-in < persistent user < project < explicit run precedence, closed versioned fields. Each effective field reports value/category, all source references/digests, loader-assigned source classification, winner or intersection and rejected/overridden contributions. Display timestamps excluded from semantic identity.

Authority: fixed trusted field-to-authorizer map; no repository modification. Designated valid scoped authorizer supplies grant, then every applicable restriction intersects. Missing required grant/authorizer rejects. Restriction cannot supply grant. Allowed sets intersect, denies accumulate. Numeric minimum only within same resource/unit/pool/interval; distinct task/project/account/window/concurrency scopes all remain applicable. Unknown hard bounds explicit and block admission. Repository/model/recalled/tool grants explicitly rejected, regardless of supplied source label.

CLI may update preferences, compile/inspect snapshots, bind a run to genuinely authorized policy, and apply a pre-authorized amendment ID. No --source operator, authorized flag, grant-file, username, secret-looking token or env override can authenticate authority. Pinned operator registry must be provisioned outside model-controlled channel with actually established boundary. Same-UID writable directory is not one. Ordinary production may inspect and restrict but activation remains authorizer_boundary_unqualified until protected composition exists. Legitimate authenticated in-memory fixture authorizer is a positive test control only; serialized markers cannot create it. No signing system/daemon needed for07; future protected channel can implement this contract.

Amendment binds version+uniqueauthorizationID+root+expected predecessorpolicyID+canonicalpatchdigest+designatedauthorizer/scope+validity. One bbolt transaction validates, consumes/records authID, appends immutable linked snapshot and updates active ref. Identical retry returns same result; conflicting reuse/wrongroot/predecessor/patch rejects. Preserve root/consumption/unresolvedexposure/history. Preferences affect future compilations, never existing snapshot. Criteria changes need separate lifecycle and invalidate evidence, not implicit07 amendment. Restricted snapshot does not revoke an active worker; pending activation until qualified quiescence/new restricted invocation with effects reconciled.

Conserve/Balanced/Accelerate change optional priorities/approved strategies only; mandatory checks, criteria, grade, permission, billing and ceilings unchanged. No invented calibrated numbers.

Validate entire proposed Gauge config before transactional mutation; duplicate keys at every depth, enum/version/negative/nonfinite invalid. Preserve unrelated settings. Atomic canonical preferences in06 store, expected revision or transactional merge prevents lostupdates. File import/export failures cannot partially commit canonical state. Interruption/persistencefailure retain previous data; Unicode/spacedpaths via structured handling.

Strategies: versioned registry, IDs, bounded parameter schemas, declared permittedeffects, pinned registry/subset per snapshot. Proposals can only select allowed entry/params; cannot register executable logic, controllercode, acceptance/authority changes. Retrievedplaybook remains proposal. Record selected/alternatives/rule/observable reason, no hidden reasoning.

Required anchors T01–T08 as canonical plan plus boundary controls. T01 deterministic provenance; T02 allscopesintersection; T03/T07 forgedgrantrejection+genuinefixturecontrol; T04 immutableold snapshot+linkedatomicamendment+exposure+replayconflicts; T05presetinvariants; T06duplicates/nonfinite/unknown/concurrent/failure/interrupt/unrelated/Unicode; T08protectededits/unregisteredfail+registeredpositive. No fixture may become live-qualified from CLIlabel/location.

Two-pass scores (architectural judgment only): conditionalregistry4.20, signatures3.50, inspectiononly3.90/5. Narrow0.30margin, explicitly conditional; confidence77% (not measured reliability). Principalrisk same-UID writable operatorstate mistaken for auth. Reverse to signed records if protected cross-host/offline transportneeded; remaininspectiononly withoutqualifiedprovisioning. No implementation or livegrant established.


## Common implementation controls

Extend the V4-06 Go seam and its single authoritative transaction store. Preserve opt-out CLI compatibility and existing fixtures. Use injected dependencies and deterministic independent arithmetic; no model calls for bookkeeping. Freeze named conformance anchors before implementation, retain actual failure and passing execution evidence, preserve protected tests during repairs, and use a distinct artifact-context checker. Keep fixture evidence separate from live host and security qualification. No new paid probes, release, deployment or merge approval is implied.

## Baseline integration inspection

Actual read-only ATLAS findings are in `/private/tmp/gauge-v4-07-integration-scout.md`. Copy into this change's artifacts at proposal. Existing model/YAML/ECM helpers have fail-open or nontransactional semantics and must not be reused as Gauge policy authority or canonical persistence. Preserve current model profile, calibration, pins, project lock and host descriptors when changing Gauge preferences. Reuse their isolated compatibility fixtures and strict duplicate-detection semantics only. Inspect accepted V4-06 store APIs before selecting implementation entry points.


## Publication and CI boundary

Automatic approval review blocked public publication of newly created V4-06 implementation source, including a retry after same-origin/public-repository and payload verification. No further publication attempt is permitted without explicit user approval. Continue authorized local implementation against independently reviewed, locally qualified fixture contracts. Record hosted CI as pending/blocked, never as passed or not applicable. Native macOS Go checks use a temporary official Go 1.27.1 toolchain whose archive SHA-256 is verified against go.dev; qualified Linux container checks remain separate. This permits local successor development, not a merge/release or a live qualification claim. Present completed local branches for publication approval after the authorized implementation work is concrete and reviewable.


## Frozen Go seam scout

Additional actual ATLAS map: `/private/tmp/gauge-v4-07-go-integration-scout.md`, SHA-256 `c0c0189291f0e6d8eb93e9ad2d60b2657ffb5acc5c10601257da975662c0ee6b`. It inspects pre-repair commit13d383b only. Copy into proposal as historical preparation and re-anchor against the accepted V4-06 repair before implementation. Existing root transactions support immutable writes and replay markers, but preference revisions, non-root settings, typed policy, prior amendment-result retrieval and strategy contracts are absent. Writer generation is not policy authorization. New policy entry points must honor the accepted authority-claim and inventory checks; no generic raw store mutation may bypass them.


## Persistence and migration binding decision

[VERDICT] Persist both user and project preferences **inside the selected controller-instance DB**, with explicit controller-local semantics. Introduce the typed V4-07 storage through an **explicit migration to the next base store schema version**. Keep production activation `authorizer_boundary_unqualified`; neither migration nor storage ownership supplies policy authority.

Decision type: constraint satisfaction. Two passes completed; no source changes, browsing, model calls, or mutable V4-06 inspection. CRYSTALIUM unavailable.

**Evidence:** E1—V4-07 draft and fixed prior decision (H: requirement authority). E2—frozen Go scout at `13d383b` (H for that commit; current accepted APIs remain a gap).

### Persistence contract

- Preserve precedence: built-in < user < project < explicit run.
- Define **user** as “user-preference layer stored for this controller instance/project.” It is a logical provenance layer, not an authenticated identity, account-wide setting, cross-project preference, or multi-user isolation boundary. CLI help and inspection output must state this.
- Store user and project layers as separate typed preference documents with independent monotonically increasing revisions. The controller identity, layer, revision and canonical digest identify every persisted contribution.
- Built-ins remain versioned compiled defaults. Explicit run overrides are compilation inputs captured in the immutable snapshot; they do not rewrite either persistent layer.
- Preference writes require an existing initialized controller store, but **no execution root**. Initialization may create an empty controller store without roots. Never fabricate a run merely to satisfy `Store.Update`.
- Provide typed operations equivalent to `ReadPreferences(layer)` and `UpdatePreferences(layer, expectedRevision, validatedReplacement)`. Read both layers in one transaction for compilation. Validate the complete replacement and update the document plus revision atomically.
- Explicit import may copy preference values into a named local layer after validation/CAS. It does not preserve a file-supplied trust label. Export is a separate operation; export failure cannot claim the canonical DB update rolled back. No implicit home discovery or writes.
- Unrelated configuration and existing controller records remain untouched. Another project DB has independent preferences, even for the same OS user.

### Schema and API contract

Use **base schema N→N+1**, where N is the accepted V4-06 version; if N is 1, the new version is 2. Inside it, use closed versioned preference, policy, binding and amendment-result records.

Provide an explicit migration command/path separate from ordinary inspection/opening:

1. Validate the exact supported predecessor, required inventory and structural invariants under the accepted store locking discipline.
2. In one bbolt transaction, create the typed namespaces and migration receipt and update the base version. Preserve all existing roots, ownership claims, manifests, legacy policy records, replay markers and other history.
3. Ordinary V4-07 opening of N reports `migration_required`; absent migration metadata, unknown versions and incomplete/corrupt layouts fail closed. Never “repair” these by creating missing buckets.
4. The older V4-06 binary must reject N+1 through its existing future-schema guard. No downgrade or schema-number reset is supported.

Legacy generic policy JSON remains readable historical data. **Migration must not convert it into typed grants or active policy bindings.** Existing roots begin with no V4-07 binding; their old references remain preserved. New typed binding records explicitly name root, policy ID, predecessor and activation status.

Add narrow typed read APIs for policies, bindings and amendment results, and a narrow transactional amendment operation. Avoid exposing a general mutation callback as the preference API.

Within the amendment transaction, retain the accepted root-claim/inventory checks, validate designated-authorizer evidence and request binding, check the expected predecessor, append the immutable snapshot, consume authorization, store its result and update the binding together. Writer generation is only the ownership check.

Index consumed authorization by **designated authorizer identity + authorization ID across the controller DB**, with root and canonical request digest in the stored record. Exact retries retrieve the original result after later amendments; different root, patch or original predecessor conflicts. Check exact replay before comparing against today’s active predecessor. Returning a historical result neither reactivates that policy nor grants new authority.

### Two-pass comparison

| Option | Assessment |
|---|---|
| **Local layers + explicit N→N+1 migration** | Selected. Preserves existing data and excludes unaware old writers. Requires migration tests. |
| Local layers + feature-versioned buckets under unchanged base schema | Smaller change, but E2 gives no evidence old writers enforce a required-feature manifest. They could ignore new invariants. Rejected under current evidence. |
| Local layers + N+1 for newly initialized stores only; defer migration | Small, safe initial implementation, but existing V4-06 stores cannot use persistent07. Plausible staged fallback, not sufficient to complete integration. |

Pass one compared compatibility and implementation size. Pass two tested inversion, boundary failures, interrupted migration, mixed binary versions, cross-root replay and dependencies. The selected option survives these cases with explicit guard and transaction tests. The feature-only alternative depends on backward enforcement not established by E2; the fresh-store alternative depends on permission to leave existing stores unsupported.

### Required acceptance tests

- Two controller DBs remain isolated; user/project precedence and provenance are deterministic; no home writes or synthetic roots.
- CAS conflicts, invalid documents and interrupted preference transactions retain the previous revision and unrelated state.
- Real predecessor-store fixture migrates with history preserved; migration interruption yields a complete old or new state.
- Both binaries reject unsupported future schemas; new ordinary opens reject unmigrated N; missing migration receipts, missing required namespaces and unknown typed versions reject.
- Generic legacy policy JSON, forged typed JSON, source labels and writer generations cannot supply grants.
- Typed policy/result retrieval works after reopen; exact amendment replay after advancement returns the original result; conflicting and cross-root reuse reject; transaction failure rolls back result, consumption and binding together.
- Existing root ownership/imported-inventory protections remain effective through every new mutator. Fixture authorizer positive controls stay fixture-only.

[GAP] Accepted06 signatures and migration invariants must be re-anchored before implementation. [RISK] Calling the local layer merely “user settings” could imply global persistence; explicit scope labels are required.

[REVERSAL-CONDITION] Choose a feature-only schema only if the accepted older writer already rejects unknown required features before every mutation. Revisit persistence if actual cross-project user defaults become a requirement; this verdict deliberately does not provide them.

Confidence: **82%** architectural judgment, not measured reliability (evidence 78, logic 90, constraints 90, sensitivity 70). Gate: conditional pass. → ATLAS for accepted-seam re-anchoring; → implementation and independent checker for the contracts/tests above.

---

Transcription provenance: Actual actor `/root/forge_v4_07_binding` emitted the decision above after reading `EIDOLONS.md`, installed `.eidolons/forge/` resources, `/private/tmp/gauge-v4-07-spec-draft.md`, and `/private/tmp/gauge-v4-07-go-integration-scout.md`. The scout's frozen evidence is commit `13d383bafe68d5e8b5c045212761d8ec4af89046`; the draft records canonical requirement authority `c581308f055a0e252013bf09f2a7b2e1426ff811`. The actor did not independently inspect V4-06 source. This file transcribes the complete emitted decision verbatim, followed by this requested provenance addendum. It is the sole file written on the parent’s explicit transcription instruction; no repository changes or new reasoning were performed.
