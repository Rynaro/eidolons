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
