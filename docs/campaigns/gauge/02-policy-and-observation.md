# Stage 2 — Policy, qualification, and early measurement

Separate economic preferences from authority. Deliver the comparison instrument before managed execution. Broad consolidation moved to V4-10 in Stage 4.

Read [HANDOFF.md](HANDOFF.md) and the relevant [ARCHITECTURE.md](ARCHITECTURE.md) boundaries. [plan.yaml](plan.yaml) owns dependencies and source routing; these tables own requirement text. [RESEARCH.md](RESEARCH.md) explains the evidence-to-design mapping without adding hidden obligations.

**Common exit for every package:** map every applicable Rxx to its planned Txx and actual observed evidence. Exercise relevant rejection paths and the intended gate. Mark unavailable required evidence blocked; mark optional cases not applicable only with their feature/scope condition recorded. Authored requirements, authored tests, executed fixtures, observed CI, and live-host qualification are distinct. A fixture-only candidate can be ready for review without a live-managed claim. See HANDOFF.md for receipts and acceptance.

---

<a id="v4-07"></a>

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

<a id="v4-08"></a>

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

<a id="v4-09"></a>

## V4-09 — Qualify one host and deliver the early comparison instrument

**Default source owner:** `Rynaro/eidolons`. **Prerequisites:** `V4-08`.

**Starting points:** `cli/src/harness_hook.sh`, `roster/host-capabilities.json`, `evals/`, `.github/workflows/live-eval.yml`. Locate actual paths in the pinned checkout; proposed interfaces are not claims of existing code.

**Scope and decisions.** Qualify a host/version/integration-mode/method/permission tuple, not a brand. Separate technical capability, support maturity, and permitted billing. Recheck official interfaces at assignment time; no API/product from the research is preselected. Build the minimal comparison instrument NOW: known-outcome fixture checks, native and original-v3 controls, run manifests, all-attempt metrics, and a frozen protocol. V4-12 adds managed execution; this package can probe native interfaces directly without depending on it.

**Implementation sequence.** Build fake-host probes and the known-outcome recorder; freeze task strata, evaluator ownership, environment controls, margins/sample/stopping rules, and explicit allowance; record authorized live probes separately. Establish code acceptance for the instrument even when live qualification is blocked. Later live admission still fails closed.

| ID | EARS requirement | Planned verification |
|---|---|---|
| V4-09-R01 | WHEN a host capability is recorded, the adapter catalogue SHALL bind it to the tested host version, mode, evidence, and control granularity. | **V4-09-T01:** Session/turn/request/tool/process fixtures; registration alone cannot establish execution or hard caps. |
| V4-09-R02 | IF a required capability or permitted billing mode is unverified, THEN managed preflight SHALL reject that configuration. | **V4-09-T02:** Missing cancellation, child visibility, enforcement, or billing eligibility; authorized API mode remains a distinct configuration. |
| V4-09-R03 | IF continuing work requires a different spending mode, THEN dispatch SHALL wait for explicit operator authorization of that mode. | **V4-09-T03:** Exhausted subscription with API credential available; zero API requests without separate allowance. |
| V4-09-R04 | WHILE shadow observation is enabled, the observer SHALL leave actual execution decisions unchanged. | **V4-09-T04:** On/off routes, prompts, tool/model settings identical; only observation artifacts differ. |
| V4-09-R05 | WHEN a comparative live trial is authorized, the evaluator SHALL use a previously frozen protocol and baseline manifest. | **V4-09-T05:** Protocol digest/time precedes outcome inspection; includes margins, stopping rules, holdout ownership, and original code control. |
| V4-09-R06 | IF a required live probe has not run, THEN capability reporting SHALL label the live criterion blocked. | **V4-09-T06:** Successful fake probe without credentials/allowance cannot acquire live-qualified status. |
| V4-09-R07 | WHEN the early comparison instrument processes a run, the recorder SHALL emit the same versioned outcome and resource record for native and Eidolons controls. | **V4-09-T07:** Known-outcome native/v3 fixtures, failed/cancelled tasks, and unknown-cost fixtures; schema and independent arithmetic agree before V4-11 starts. |
| V4-09-R08 | WHEN a host method is qualified, the catalogue SHALL record that method's effective execution boundary and support maturity. | **V4-09-T08:** Sandboxed method versus privileged sibling method; preview/experimental status visible; qualifying one never grants the other. |
| V4-09-R09 | IF a host, method, permission configuration, or integration version changes, THEN preflight SHALL invalidate the affected qualification before new dispatch. | **V4-09-T09:** Version and effective-permission drift with unchanged brand; unaffected pinned configuration remains qualified. |
| V4-09-R10 | WHEN comparison conditions are frozen, the protocol SHALL specify resource guarantees, dependency/cache state, task splits, and outcome definitions for each arm. | **V4-09-T10:** Deliberate CPU, memory, network, cache, timeout, or acceptance mismatch is detected or explicitly stratified, not silently pooled. |
| V4-09-R11 | IF an evaluation arm lacks its required implementation or qualified configuration, THEN the instrument SHALL mark that arm ineligible rather than fabricate a run. | **V4-09-T11:** Structural-only arm before V4-10 and managed arm before V4-15 remain pending; available native/v3 controls still run under authorization. |

**Exit.** Apply the common exit above and the package scope; missing required live evidence blocks its live claim, not disclosure of completed fixture work.

**Stop and rollback.** Preserve user work, canonical history, and unresolved exposure; disable the new path without restoring stale acceptance or wider authority.
