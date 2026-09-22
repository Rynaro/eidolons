# V4-09 preparatory implementation contract

Canonical authority: plan c581308f055a0e252013bf09f2a7b2e1426ff811. Implement only after predecessor code, tests and distinct review satisfy the DAG. No implementation or live qualification is claimed by this preparation. All applicable canonical requirements below remain binding. The attached actual FORGE decision resolves bounded implementation choices; it cannot grant runtime authority.

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


## Bounded decision

# V4-09 instrument decision — actual FORGE transcription

Actor forge_v4_06, two-pass reasoning from supplied exact11requirements, local codex-cli0.154.0 help-only discovery and original-v3 commit752194ef5ceaa8cee1f5995fd0d374888696d8fc. No live invocation/paidprobe authorization. Root transcribes emitted verdict. No runtime qualification; architectural confidence84% only.

Select fixture-first instrument plus fail-closed live admission over catalogue/validator-only (insufficient recorder proof) or livequalificationnow (unauthorized and insufficient boundaries). Challenge fakecapability labels, supplied freezetimestamps and invented scientific parameters. Missing protectedauthorization, usablehostinterface or trustworthy ordering leaves livecriterion blocked while fixturecode can be reviewready.

Catalogue tuple binds host+installedversion+integration/protocolversion+mode+method+effectivepermissions+executionboundary+granularity+maturity+evidence+permittedbilling. Helpflags discoveryonly: no cancellation/children/enforcement/billing proof. Preflight requires current evidence for each required capability plus authorizedbilling. Credentialpresence not allowance; exhaustedsubscription neverAPI switch. Drift invalidates affected tuple; sandboxed method never qualifies privileged sibling. Native/original-v3 livearms eligible only authorized+qualified; structural before10 and managed before15 remain ineligible. Eligibility records, not fabricatedattempts.

Versioned protocol freezes arms+exactbaselines+taskstrata/splits+evaluator/holdoutownership+outcome/acceptancedefinitions+resourcecoverage+CPU/memory/network/dependencies/cache/timeouts+exclusions/stratification+margins/sampleallocation/stopping/statisticalrules+mode/allowance+operatorauthref. Canonicalhash includes immutable referenced manifests. Atomic freeze stores identity and append-only controller ordering BEFORE outcomes/dispatch admitted. Updates newprotocol/trialidentity; supplied timestamp insufficient. Reject beforefreeze/wrongprotocol/changedmanifests. Local controller ordering cannot prove humans never saw externaloutcomes; live prospectivefreeze needs qualified access/evaluatorboundary, otherwise unverified. Fixture protocol explicitly synthetic and tests mechanics only. Live scientific fields and allowance need genuine07authorizer; approved:true/nonemptyJSON not approval. No invented effectsize/samples/margins.

One shared native/v3 recorder schema: trial/protocol/arm/task/attempt IDs, invocation/config/environmentrefs, terminalexecutionstate separatelyacceptance+evidence, resources/coverage, timestamps/exclusion/censoring. Failed/cancelled/abandoned attempts remain denominator and totals; retries keep taskroot. Known/estimated/unknown costs distinct, don't dropunknownattempts.

Shadow consumescopies/events, leaves routeinputs/prompts/model/toolsettings/executiondecisions identical. Observerfailure cannot reroute or changebilling. No zerotimingoverheadclaim.

Independent fixtures: attempts costs2,3,1,4 total10 with2distinctacceptedtasks =>5peracceptedtask; repeatedacceptancenotification doesn'tinflatecount. Costs2,1,3 zeroaccepted =>total6 ratio undefined. Costs2,unknown,3 =>knownsubtotal5; completetotal/ratio unknown. Equivalent synthetic native/v3 records sharearithmetic, never called livebaselineexecutions. Reject prefreeze/forgedtime/changedmanifest/wrongprotocol; validstoredfreeze positive. CPU/memory/network/cache/dependency/timeout mismatch rejects or predeclaredstratification, not silentpooling. Fakehost can'tlivequalify; API credential withoutallowance yieldszeroAPItransportcalls. Unavailablearms nofakeattempt. Shadow on/offrequest equality with only observationsdifferent.

Code acceptance: schemas, fakeadapters, isolatedstore, arithmetic/rejection/shadowfixtures. Explicitly proveblockedpathsneverrealtransport. Report instrumentcode/fixturemechanics separately from livehostblocked/liveprotocolauthabsent/comparativenotrun/performanceunmeasured. No paidcall/defaultpromotion implied.


## Common implementation controls

Extend the V4-06 Go seam and its single authoritative transaction store. Preserve opt-out CLI compatibility and existing fixtures. Use injected dependencies and deterministic independent arithmetic; no model calls for bookkeeping. Freeze named conformance anchors before implementation, retain actual failure and passing execution evidence, preserve protected tests during repairs, and use a distinct artifact-context checker. Keep fixture evidence separate from live host and security qualification. No new paid probes, release, deployment or merge approval is implied.


## Baseline integration inspection

Actual read-only ATLAS map: `/private/tmp/gauge-v4-09-integration-scout.md`, SHA-256 `04af687cb3a973a2b57d40ac44556d2d706d075890a0f01fd53c7fe5bef56384`. Copy into the change at proposal together with `/private/tmp/gauge-v4-09-codex-discovery.md`. Existing host catalogue/readiness establishes configuration and registration, not execution qualification. Existing H-WIN matrix arms share a sandbox-loop evaluator; neither is an unmodified native or pinned original-v3 control. Its aggregate scorecards omit attempt details and frozen protocol/environment identity. Harness hooks change instructions and cannot be reused unchanged for shadow observation. Reuse synthetic tasks, fake streams, isolated result stores and failure controls where applicable, without treating them as live evidence. Preserve opt-out behavior; do not repair or invoke the unrelated live workflow merely to qualify the new fixture instrument.


## Publication and CI boundary

Automatic approval review blocked public publication of newly created V4-06 implementation source, including a retry after same-origin/public-repository and payload verification. No further publication attempt is permitted without explicit user approval. Continue authorized local implementation against independently reviewed, locally qualified fixture contracts. Record hosted CI as pending/blocked, never as passed or not applicable. Native macOS Go checks use a temporary official Go 1.27.1 toolchain whose archive SHA-256 is verified against go.dev; qualified Linux container checks remain separate. This permits local successor development, not a merge/release or a live qualification claim. Present completed local branches for publication approval after the authorized implementation work is concrete and reviewable.
