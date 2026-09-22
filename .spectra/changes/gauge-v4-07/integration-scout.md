# V4-07 Go integration scout — frozen V4-06 seam

Source inspected exclusively with `git show` at commit `13d383bafe68d5e8b5c045212761d8ec4af89046` in `/private/tmp/eidolons-gauge-v4-06`. No mutable source files inspected. Requirement authority: `/private/tmp/gauge-v4-07-spec-draft.md`. Static preparation only: no code execution, source edits, model/live/network calls, or V4-06 acceptance claim. CRYSTALIUM unavailable. All code anchors below refer to that commit; H indicates direct source evidence.

**Mandatory recheck:** the parent reports current V4-06 repair adds per-root authority claims and revalidates imported inventory. The frozen signatures below are not an approved implementation target. Reinspect every public mutator and controller authority path at the accepted predecessor commit before V4-07 implementation.

## Shared store and transaction surface

- `controller.Service` selects exactly one project/controller-instance DB at `.eidolons/.ledger/.gauge-controller-v1/state.db`; it is not per root or account-wide. `gauge/internal/controller/authority.go:17–39`; CLI scope text `gauge/cmd/eidolons-gauge/main.go:25–30`. H. Preserve this boundary; no new per-run preference DB or authoritative sidecar.
- `store.Inspect(path, timeout) (Snapshot,error)` opens read-only; `store.Open(path,timeout) (*Store,error)` first inspects, then rechecks guard after writable open. `gauge/internal/store/store.go:131–170`. Timeout is positive and at most 300s (`:40–44`); missing/unsupported schema is rejected (`:47–71`). H.
- `Store.Update(id,generation,func(*Tx) error) error` wraps one bbolt transaction, obtains the root inside it, and requires active phase plus matching generation (`store.go:320–333`). This is the existing dependent-state atomicity seam, subject to the accepted authority-claim repair. It is root-scoped, not a generic controller-preference transaction API. H.
- `Tx.Root() contract.Root` returns a detached copy (`:336–340`). `Tx.SetRoot(root)` refuses changes to ID/generation/inventory/phase, but otherwise persists the supplied root (`:342–350`). Reading the current predecessor/revision inside the transaction matters: supplying a previously captured full root can overwrite unrelated newer fields. No explicit expected-policy-revision CAS exists. H.
- `Tx.Put(contract.Record)` stores a record in a family/root bucket, permits identical replay, rejects changed content for an existing ID (`:353–375`). It can provide immutable policy-history storage, but compares raw body representation via `reflect.DeepEqual`; semantically equal JSON with different bytes is not automatically normalized. H.
- `Tx.Once(id,payload) (fresh bool,error)` stores a SHA-256 payload digest in the same transaction; identical replay returns false, changed payload conflicts (`:378–400`). Callback failure rolls it back with dependent writes. Identity is scoped to the current root's operations bucket, not globally consumed across roots, and it does not return the previous result. H.

## V4-07 mapping and missing typed contracts

| V4-07 need | Available seam | Constraint/gap |
|---|---|---|
| Atomic preferences | Existing bbolt store and transaction model | No controller/user/project preference records, revision field, CAS or non-root preference-update API. Bucket list is fixed at `store.go:19–20`; public Update requires an active root. Preference updates must not fabricate an execution root or imply authorization. |
| Immutable effective policy | `Record{Family:"policy",Kind:"policy",Body:...}` plus `Tx.Put` | `Record.Validate` checks only family/kind and valid JSON (`contract/types.go:91–103`), not provenance, grant source, ceilings, strategy rules or closed schema. |
| Active policy binding | `Root.PolicyRefs`, `Root.Manifest.PolicyRefs` | Both are untyped string slices (`types.go:38–47,71–82`), with no explicit active policy ID, predecessor or activation state. Their meaning and consistency must become explicit; a string reference alone is no proof of authority. |
| Amendment replay | `Once` + immutable `Put` + root update in one transaction | The existing Tx API has no record getter or prior-result lookup; Snapshot omits operations (`store.go:23–28,179–230`). Exact replay after active-policy advancement needs durable result retrieval, not a fresh mutation. Wrong-root and predecessor checks are not supplied by Once itself. |
| Strategy contract | Typed contract package and policy family | No strategy registry/version/subset, parameter schema or permitted-effects validator exists in inspected contracts. Do not substitute arbitrary JSON or executable Adapter code for the supplied strategy contract. |
| Preserve durable state | Root references and immutable families | Root has Binding, Manifest, PolicyRefs, Intents, Evidence (`types.go:71–82`); it has no typed consumption/exposure state yet. Existing references must survive preferences/amendments; future dimensions must not be reset or invented. |

All table claims H, anchored to committed code. They identify extension points, not a replacement authority design.

## Authority, validation and deterministic identity

- `Root.Generation` and `Binding.Authority` are generated as controller writer-ownership identity (`controller/controller.go:76–85`). Marker checks compare store/root/generation/inventory and active phase (`controller/authority.go:233–270`). These establish legacy→Gauge writer ownership, not the V4-07 designated trusted field authorizer. The existing `promote` command must never be read as granting policy permissions/billing.
- Controller mutation examples acquire root append ownership, check `active`, then open the shared store (`controller.go:238–245,292–312,325–354`). No authenticated policy-authorizer interface exists in `Options`; it contains timeout, injected clock/IDs, fixture Adapter and test Cut (`:33–40`). H. Follow the draft's inspection-only/unqualified default; do not add labels, environment switches or file location as grant evidence.
- `decodeFile` rejects unknown fields/trailing objects, but performs no duplicate-key token traversal (`authority.go:70–91`). It is insufficient for V4-07's duplicate-at-every-depth rule. `Record.Validate` accepts any valid JSON body; enum/version/range/finite checks need the V4-07 typed validation boundary. H.
- `Manifest.Identity()` validates selected fields and hashes `json.Marshal(m)`; `Digest` hashes bytes (`contract/types.go:49–65`). This is a reusable deterministic byte-hash primitive, not a complete canonical policy identity contract: set ordering, source classifications and display-timestamp exclusion are not handled for policies. H.
- `atomicJSON` uses same-directory temporary file, file sync, rename and directory sync (`authority.go:94–125`). It is a private filesystem-publication helper, not the canonical preference transaction. An error after rename can mean the target already changed; it cannot promise DB/file cross-resource rollback or previous-file retention on every error. H.
- CLI currently supports init/import/promote/recover/status/fixture/replace and requires roots except init (`cmd/eidolons-gauge/main.go:16–27,39–70`). No preference/compiler/amendment surface exists. Bash shim forwards arguments to the optional compiled binary and has no legacy write fallback (`cli/src/gauge.sh:1–10`). H.

## Reusable tests and required follow-up

→ APIVR-Δ: Reuse injected Clock/IDs/Adapter from `controller.Options`, existing immutable record/replay/transaction primitives, and the accepted replacement APIs only after authority-claim repair is reviewed. Keep provider/model calls outside transactions; the fixture example does so explicitly (`controller.go:273–297`). No runtime security qualification follows from these mechanisms.

→ VIGIL/checker: Preserve the existing unsupported/missing store refusal tests (`gauge/internal/store/store_test.go:29–46`), dependent history+policy rollback/concurrency/bounded lock/replay cases (`:49–70`), and process-kill before/after commit plus identical retry (`:73–90`). These test definitions were inspected, not executed here.

→ VIGIL/checker: Reuse deterministic fixture/retry/model-call assertions (`gauge/internal/controller/conformance_test.go:108–115`) and replacement preservation of root, policy, intent, evidence and candidate references (`:118–127`). Add V4-07 tests for preference revision conflicts, duplicate input, prior-result amendment replay after advancement, wrong-root authorization reuse, canonical patch/predecessor mismatch, strategy rejection, unrelated-state retention and pending activation. Existing fixture success is not a trusted operator authorizer.

→ ATLAS/orchestrator: After V4-06 acceptance, re-anchor `Store.Stage/Activate/Update`, `Tx.SetRoot/Put/Once`, controller InitRoot/Import/Promote/Recover/ExecuteFixture/Replace, and read/export authority validation. Confirm accepted claim construction cannot be bypassed by the new preference/policy entry points, and that imported inventory is rechecked where required. Preserve one authoritative shared DB and the existing local process-interruption scope; no power-loss/network-filesystem qualification is inferred.
