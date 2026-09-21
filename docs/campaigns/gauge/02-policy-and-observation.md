# Stage 2 — Persistent policy, qualification, and compiled packages

Separate preference, authority, economics and host eligibility. Freeze baseline/protocol; consolidate sources without silently changing workflow or retiring consumers.

Read [HANDOFF.md](HANDOFF.md) and [ARCHITECTURE.md](ARCHITECTURE.md). [plan.yaml](plan.yaml) owns package identities, dependencies and source routing. Each table below owns its EARS requirements; verification entries are planned cases, not executed results. Assign one package, and one named slice where applicable.

<a id="v4-07"></a>

## V4-07 — Persistent Gauge preferences and intersected ceilings

**Default source owner:** `Rynaro/eidolons`. **Prerequisites:** `V4-06`. Stage gates also apply.

**Starting points:** `cli/eidolons`, `cli/src/lib.sh`, `schemas/`, `roster/model-profiles.yaml`. Resolve symbolic/new paths in the actual checkout; they are not claims those interfaces already exist.

**Scope and decisions.** Implement nexus-owned persistent Conserve/Balanced/Accelerate preferences with explainable origin. Proposed gauge set/explain commands are new interfaces. User/project/run preference precedence does not apply to hard ceilings: intersect applicable trusted limits. Do not treat project-controlled files as operator authorization. No numeric quota preset is claimed calibrated.

**Implementation sequence.** Implement validation and idempotent configuration updates. Compile an immutable effective policy snapshot per run. Add explicit operator-amendment handling while preserving prior consumption.

| ID | EARS requirement | Planned verification |
|---|---|---|
| V4-07-R01 | WHEN effective Gauge policy is resolved, the controller SHALL report the origin and resolution of each field. | **V4-07-T01:** Conflicting trusted user/project/run preferences; deterministic normalized output and origin checks. |
| V4-07-R02 | WHEN independently applicable ceilings are resolved, the controller SHALL apply their intersection. | **V4-07-T02:** Task/project/account/window/concurrency conflicts and explicit lower run limits; no last-writer-wins limit expansion. |
| V4-07-R03 | IF untrusted content requests wider authority or higher ceilings, THEN the controller SHALL reject the requested escalation. | **V4-07-T03:** Model output, repository config, recalled note, and forged runtime setting; operator-authorized amendment is a separate positive control. |
| V4-07-R04 | WHEN a run starts, the controller SHALL bind it to an immutable effective-policy identity. | **V4-07-T04:** Change persistent preference during the run; existing snapshot/consumption persist and authorized amendments are linked, not rewritten. |
| V4-07-R05 | WHEN a preset changes for an otherwise identical task, the policy compiler SHALL preserve mandatory acceptance and authority requirements. | **V4-07-T05:** Compare Conserve/Balanced/Accelerate contracts; optional exploration changes but required checks and permissions do not. |
| V4-07-R06 | IF configuration is invalid or cannot be persisted safely, THEN the CLI SHALL retain the previous configuration. | **V4-07-T06:** Duplicate keys, unknown enum, negative/nonfinite limit, partial write, Unicode/spaced paths, and unrelated-setting controls. |

**Exit.** Map every requirement above to observed evidence or a named blocker. Read HANDOFF.md for mechanical, independent, CI and live-evidence distinctions. Unavailable mandatory evidence prevents acceptance; a fixture-only candidate can be ready for review without claiming live qualification.

**Stop and rollback.** No defaults switch or native-host setting takeover. Disabling preferences keeps limits, history, and outstanding exposure intact.

---

<a id="v4-08"></a>

## V4-08 — Root lineage and honest multidimensional observations

**Default source owner:** `Rynaro/eidolons`. **Prerequisites:** `V4-06`, `V4-07`. Stage gates also apply.

**Starting points:** `cli/src/telemetry.sh`, `cli/src/trace.sh`, `cli/src/lib_context.sh`, `schemas/`. Resolve symbolic/new paths in the actual checkout; they are not claims those interfaces already exist.

**Scope and decisions.** Normalize usage without conflating subscription allowance, tokens, context capacity, money, latency, or concurrency. Define cumulative/delta and correction semantics. Account aliases refer to legitimately shared allowance for the same operator, not credential pooling. Minimize local retention and redact secrets; do not store hidden reasoning or full transcripts.

**Implementation sequence.** Add source/freshness/units and lineage to observations. Reconcile duplicates, late data, and parent/child totals. Expose unknown states to policy without breaking unrelated advisory hooks.

| ID | EARS requirement | Planned verification |
|---|---|---|
| V4-08-R01 | WHEN a new task begins, the controller SHALL allocate an execution root distinct from its route digest. | **V4-08-T01:** Identical prompts/routes create different roots; resume retains its original root. |
| V4-08-R02 | WHEN a descendant, reviewer, retry, or successor is created, the controller SHALL bind its observations to the original task root. | **V4-08-T02:** Role switch, context reset, child escalation, and supported provider switch; no budget identity reset. |
| V4-08-R03 | WHEN a usage observation is recorded, the collector SHALL include its unit, source grade, observation time, and freshness state. | **V4-08-T03:** Observed, estimated, self-attested, unsupported, stale, and unknown fixtures; distinct fields for cache usage and allowance. |
| V4-08-R04 | WHEN duplicate, corrected, or cumulative usage arrives, reconciliation SHALL account for each underlying consumption event once. | **V4-08-T04:** Out-of-order callbacks, cumulative snapshots, parent/child overlap, late correction and independent expected totals. |
| V4-08-R05 | IF allowance, pricing, or actual model identity is unavailable, THEN the report SHALL present that dimension as unknown or unsupported. | **V4-08-T05:** Missing pricing, stale reset, unobserved assigned model, provider-specific buckets; no zero/unlimited substitution. |
| V4-08-R06 | WHEN observations are persisted, the collector SHALL omit credentials, hidden reasoning, and raw private payloads. | **V4-08-T06:** Secret canaries and retention/export tests; metadata remains useful without raw transcripts. |

**Exit.** Map every requirement above to observed evidence or a named blocker. Read HANDOFF.md for mechanical, independent, CI and live-evidence distinctions. Unavailable mandatory evidence prevents acceptance; a fixture-only candidate can be ready for review without claiming live qualification.

**Stop and rollback.** No quota scraping, automatic paid fallback, invented model identity, or cross-device synchronization claim.

---

<a id="v4-09"></a>

## V4-09 — Qualify host interfaces, billing eligibility, and baseline protocol

**Default source owner:** `Rynaro/eidolons`. **Prerequisites:** `V4-08`. Stage gates also apply.

**Starting points:** `cli/src/harness_hook.sh`, `roster/host-capabilities.json`, `evals/`, `.github/workflows/live-eval.yml`. Resolve symbolic/new paths in the actual checkout; they are not claims those interfaces already exist.

**Scope and decisions.** Check installed host/version/mode against official interfaces at implementation time. Codex App Server and native Claude integrations are candidates, not prequalified commitments. Technical capability and permitted authentication/billing mode are separate requirements. Freeze the original control baseline and trial definitions before optimizations; no paid probe without account/pool, allowed models, ceiling, and retention authorization.

**Implementation sequence.** Build fake-host probes for dispatch, context inheritance, permissions, usage, cancellation, and resume. Record live capability only from authorized actual execution. Freeze task strata, independent oracles, margins, sample/stopping rules, and model/harness/configuration identities for later comparisons.

| ID | EARS requirement | Planned verification |
|---|---|---|
| V4-09-R01 | WHEN a host capability is recorded, the adapter catalogue SHALL bind it to the tested host version, mode, evidence, and control granularity. | **V4-09-T01:** Session/turn/request/tool/process fixtures; syntax registration alone cannot establish execution or hard caps. |
| V4-09-R02 | IF a required capability or permitted billing mode is unverified, THEN managed preflight SHALL reject that configuration. | **V4-09-T02:** Missing cancellation, child observation, permission enforcement, or subscription eligibility; explicit supported API mode is separately identified. |
| V4-09-R03 | IF continuing work requires a different spending mode, THEN dispatch SHALL wait for explicit operator authorization of that mode. | **V4-09-T03:** Exhausted subscription with available API credential; verify zero API requests without a separate allowance. |
| V4-09-R04 | WHILE shadow observation is enabled, the observer SHALL leave actual execution decisions unchanged. | **V4-09-T04:** On/off route, prompts, tool settings and model request comparison; only observation artifacts differ. |
| V4-09-R05 | WHEN a comparative live trial is authorized, the evaluator SHALL use a previously frozen protocol and baseline manifest. | **V4-09-T05:** Protocol timestamp/digest precedes outcome inspection; include acceptance margins, stopping rules, holdout ownership, and original control revisions. |
| V4-09-R06 | IF a required live probe has not run, THEN capability reporting SHALL label the live criterion blocked. | **V4-09-T06:** No credentials/allowance fixture plus successful fake probe; no upgrade to live-qualified. |

**Exit.** Map every requirement above to observed evidence or a named blocker. Read HANDOFF.md for mechanical, independent, CI and live-evidence distinctions. Unavailable mandatory evidence prevents acceptance; a fixture-only candidate can be ready for review without claiming live qualification.

**Stop and rollback.** No terminal scraping as an assumed durable API, SDK entitlement assumption, or silent subscription-to-API switch. Fixture-only completion cannot establish a live managed claim.

---

<a id="v4-10"></a>

## V4-10 — Consolidate coupled sources and compile first-party packages

**Default source owner:** `Rynaro/eidolons`. **Prerequisites:** `V4-03`, `V4-06`, `V4-09`. Stage gates also apply.

**Starting points:** `roster/index.yaml`, `roster/mcps.yaml`, `roster/routing.yaml`, `schemas/`, `docs/architecture.md`. Resolve symbolic/new paths in the actual checkout; they are not claims those interfaces already exist.

**Scope and decisions.** Separate source-repository, release, deployment, process, and trust boundaries. Inventory all ten roster specialists, four contracts, Junction, tonberry, atomos, atlas-aci, CRYSTALIUM, evaluation tooling, and optional clients before choosing imports. Import only tightly coupled components with provenance/licenses and minimal canonical profile+skill sources. Keep the optional memory service independently deployable; external packages remain supported. Do not archive anything in this stage.

**Implementation sequence.** Execute the named inventory slice first. Then assign exactly one approved component import or compiler slice, retaining compatibility endpoints. Generate aggregate registry, host discovery, and command-reference views and compare their semantics with the control.

**Assignment slices:** `inventory`, `one-component-import`, `registry-and-discovery-compiler`. Select one; final package acceptance covers the required selected core slices. Explicitly deferred optional slices do not become required later without amendment.

| ID | EARS requirement | Planned verification |
|---|---|---|
| V4-10-R01 | WHEN a component import is proposed, the consolidation inventory SHALL identify its consumers, license, provenance, replacement path, and preserved runtime boundaries. | **V4-10-T01:** Check all active roster members and support repos against inventory; no omitted legacy agents or unexplained third-party rights. |
| V4-10-R02 | WHEN first-party package sources are compiled, the compiler SHALL emit deterministic schema-valid aggregates from the declared canonical inputs. | **V4-10-T02:** Repeat builds, reordered source enumeration, duplicate identifier/key, missing integrity reference, and unknown-tool fixtures. |
| V4-10-R03 | WHEN host discovery files are generated, the compiler SHALL preserve portable skill sources and host-specific identifier semantics. | **V4-10-T03:** Agent Skills source remains canonical; host wrappers, hyphenated MCP names, allowed tools, and user-owned sections round-trip. |
| V4-10-R04 | WHEN a legacy endpoint is served by an imported component, the compatibility layer SHALL preserve its declared protocol behavior. | **V4-10-T04:** Old/new consumer fixtures for ECL/EIIS/ESL/ECM and supported CLI/MCP endpoints; no claim of free A2A/ACP interoperability. |
| V4-10-R05 | WHILE components share a repository or binary, deployment SHALL preserve their independently configured privileges and optionality. | **V4-10-T05:** No-MCP/no-memory/headless core test; verifier/candidate/journal isolation and tool-surface equality tests. |
| V4-10-R06 | IF an import lacks consumer migration evidence, THEN the migration planner SHALL retain the original distribution path. | **V4-10-T06:** Unmigrated dependent and missing replacement-release fixtures; no archive operation in this package. |

**Exit.** Map every requirement above to observed evidence or a named blocker. Read HANDOFF.md for mechanical, independent, CI and live-evidence distinctions. Unavailable mandatory evidence prevents acceptance; a fixture-only candidate can be ready for review without claiming live qualification.

**Stop and rollback.** Preserve old repositories/tags/endpoints and user settings. Do not mechanically merge privileged MCP tools, delete .spectra/, or rewrite protocols for directory aesthetics.

---
