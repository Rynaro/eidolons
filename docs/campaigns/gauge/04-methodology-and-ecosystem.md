# Stage 4 — Measured adoption, context economy, and consolidation

Extend the demonstrated path with versioned specialist methods, bounded information access, optional clients, and justified source consolidation. Follow package dependencies rather than numeric stage order.

Read [HANDOFF.md](HANDOFF.md) and the relevant [ARCHITECTURE.md](ARCHITECTURE.md) boundaries. [plan.yaml](plan.yaml) owns dependencies and source routing; these tables own requirement text. [RESEARCH.md](RESEARCH.md) explains the evidence-to-design mapping without adding hidden obligations.

**Common exit for every package:** map every applicable Rxx to its planned Txx and actual observed evidence. Exercise relevant rejection paths and the intended gate. Mark unavailable required evidence blocked; mark optional cases not applicable only with their feature/scope condition recorded. Authored requirements, authored tests, executed fixtures, observed CI, and live-host qualification are distinct. A fixture-only candidate can be ready for review without a live-managed claim. See HANDOFF.md for receipts and acceptance.

---

<a id="v4-10"></a>

## V4-10 — Consolidate coupled sources after the delivery experiment

**Default source owner:** `Rynaro/eidolons`. **Prerequisites:** `V4-03`, `V4-06`, `V4-15`, `V4-21`.

**Starting points:** `roster/index.yaml`, `roster/mcps.yaml`, `roster/routing.yaml`, `schemas/`, `docs/architecture.md`. Locate actual paths in the pinned checkout; proposed interfaces are not claims of existing code.

**Scope and decisions.** Moved out of the demonstrator critical path. Inventory all ten roster specialists, four contracts, Junction, tonberry, atomos, atlas-aci, CRYSTALIUM, evaluation tooling, and optional clients before imports. Separate repository/release/deployment/process/trust boundaries. Minimal test profiles for V4-13 require no wholesale migration. Review early results, including null or blocked findings; maintenance justification is not a performance claim. Import only coupled, licensed sources; preserve external packages, optional memory/UI, and consumer compatibility.

**Implementation sequence.** Inventory first; then one approved component import or compiler slice. Generate aggregate registry/discovery/reference views; compare structural-only semantics against a pinned control. Record canonical ownership and compatibility, not duplicate editable sources.

**Assignment slices:** `inventory`, `one-component-import`, `registry-and-discovery-compiler`. Assign one slice at a time; package acceptance covers its declared required slices. Optional deferral is explicit, not a silent pass.

| ID | EARS requirement | Planned verification |
|---|---|---|
| V4-10-R01 | WHEN a component import is proposed, the consolidation inventory SHALL identify its consumers, license, provenance, replacement path, and preserved runtime boundaries. | **V4-10-T01:** Cover every active roster/support component and third-party rights; missing consumer/provenance prevents import readiness. |
| V4-10-R02 | WHEN first-party package sources are compiled, the compiler SHALL emit deterministic schema-valid aggregates from the declared canonical inputs. | **V4-10-T02:** Repeat/reordered builds, duplicate IDs/keys, missing integrity reference, and unknown-tool fixtures. |
| V4-10-R03 | WHEN host discovery files are generated, the compiler SHALL preserve portable skill sources and host-specific identifier semantics. | **V4-10-T03:** Portable skill remains canonical; wrappers, hyphenated MCP names, allowed tools, and user-owned sections round-trip. |
| V4-10-R04 | WHEN a legacy endpoint is served by an imported component, the compatibility layer SHALL preserve its declared protocol behavior. | **V4-10-T04:** Exact producer/consumer fixtures for ECL/EIIS/ESL/ECM and supported CLI/MCP; do not assume A2A/ACP equivalence. |
| V4-10-R05 | WHILE components share a repository or binary, deployment SHALL preserve their independently configured privileges and optionality. | **V4-10-T05:** No-MCP/no-memory/headless core; candidate/checker/journal isolation and unchanged tool grants. |
| V4-10-R06 | IF an import lacks consumer migration evidence, THEN the migration planner SHALL retain the original distribution path. | **V4-10-T06:** Unmigrated dependent and missing replacement-release fixtures; no archive operation in this package. |
| V4-10-R07 | WHEN a consolidation decision is recorded, the inventory SHALL distinguish measured delivery effects from maintenance-only justification. | **V4-10-T07:** Reference the early comparison record; null, blocked, or inconclusive results cannot be relabeled as demonstrated performance gains. |

**Exit.** Apply the common exit above and the package scope; missing required live evidence blocks its live claim, not disclosure of completed fixture work.

**Stop and rollback.** Preserve old repositories/tags/endpoints and settings. No automatic .spectra/ deletion, archival, privileged-tool merger, or protocol rewrite for directory aesthetics.

---

<a id="v4-16"></a>

## V4-16 — Publish lean RAMZA methods without fabricated certainty

**Default source owner:** `Rynaro/Ramza`. **Prerequisites:** `V4-15`, `V4-21`.

**Starting points:** `SPEC.md`, `PERSONA.md`, `tiers.md`, `skills/`, `templates/` in the assigned RAMZA revision. Locate actual paths in the pinned checkout; proposed interfaces are not claims of existing code.

**Scope and decisions.** Explicitly amend RAMZA-lite while preserving full-tier protections. Remove mandatory invented alternatives/hierarchies for clear reversible work. Method use inside a maker is not an independent planner or critique. Keep outcome/scope/criteria/verifier/decision/risks; do not equate small diff with low risk. Use source relocation only after accepted V4-10 evidence; otherwise the sibling remains canonical.

**Implementation sequence.** Inventory existing controls; version the lite contract; test producer/consumer and standalone/full compatibility. Give each heuristic activation, review, and retirement conditions; compare with the V4-21 instrument before claiming benefit.

| ID | EARS requirement | Planned verification |
|---|---|---|
| V4-16-R01 | WHEN a clear conventional lite task is planned, the RAMZA method SHALL produce a minimal actionable contract without mandatory invented alternatives. | **V4-16-T01:** Assert outcome, exclusions, criteria, verifier, chosen approach, material risks; no forced option count. |
| V4-16-R02 | IF unresolved information changes required behavior or authority, THEN the RAMZA method SHALL expose that decision before marking its plan ready for implementation. | **V4-16-T02:** One-file security change, migration, and ambiguous product choice; file count does not set risk. |
| V4-16-R03 | WHEN the maker consumes an accepted planning decision, the method contract SHALL avoid requiring a duplicate search for already settled alternatives. | **V4-16-T03:** Producer/consumer carry decision and invalidation conditions; changed evidence reopens only the relevant choice. |
| V4-16-R04 | WHEN rubric scores are presented, the RAMZA output SHALL label uncalibrated scores as heuristics. | **V4-16-T04:** A score of 85 is neither an 85-percent probability nor independent verification. |
| V4-16-R05 | WHERE legacy or full planning mode is selected, the profile package SHALL preserve its declared controls. | **V4-16-T05:** Standalone/prior-version compatibility; changed charter requires a versioned amendment. |
| V4-16-R06 | WHEN a planning heuristic is published, the method contract SHALL record its activation conditions, supported configuration scope, and retirement trigger. | **V4-16-T06:** Irrelevant task avoids activation; model/harness change queues reevaluation instead of inheriting an unqualified benefit claim. |
| V4-16-R07 | IF a planning artifact contains an unsupported assumption affecting acceptance, THEN the method SHALL expose that assumption as unresolved rather than convert it into a user requirement. | **V4-16-T07:** Ambiguous behavior and missing acceptance example remain visible; explicit user-confirmed behavior is a positive control. |

**Exit.** Apply the common exit above and the package scope; missing required live evidence blocks its live claim, not disclosure of completed fixture work.

**Stop and rollback.** No default flip or probability inference from rubric arithmetic. Consequential behavior/authority uncertainty remains explicit.

---

<a id="v4-17"></a>

## V4-17 — Publish explicit Vivi candidate and context modes

**Default source owner:** `Rynaro/Vivi`. **Prerequisites:** `V4-15`, `V4-21`.

**Starting points:** `SPEC.md`, `PERSONA.md`, `skills/loop-native/SKILL.md`, `skills/failure-recovery/SKILL.md` in the assigned Vivi revision. Locate actual paths in the pinned checkout; proposed interfaces are not claims of existing code.

**Scope and decisions.** Amend fresh-context/human-apply assumptions only in named opt-in modes. Support proposal-only and authorized continuous candidate-workspace work. Preserve greenfield/publication boundaries unless separately revised. Continuing maker and clean checker context are different; neither retry strategy is predeclared the winner.

**Implementation sequence.** Version mode declarations; exercise adapter fixtures; carry inherited decisions/failures/root budget; compare continuity, compaction, and fresh-context control without erasing task obligations.

| ID | EARS requirement | Planned verification |
|---|---|---|
| V4-17-R01 | WHEN candidate-workspace mode is selected with scoped authorization, Vivi SHALL edit only the authorized candidate workspace. | **V4-17-T01:** Proposal-only control, user-tree escape, protected criteria, unrelated dirty work, and valid candidate edits. |
| V4-17-R02 | WHERE proposal-only mode is selected, Vivi SHALL return a candidate proposal without applying it to the user tree. | **V4-17-T02:** Standalone compatibility and parent-authorized application remain separate operations. |
| V4-17-R03 | WHEN a coherent task uses continuity mode, Vivi SHALL retain relevant decisions and failure history across repair attempts. | **V4-17-T03:** Warm/fresh fixtures; resets are recorded without resetting accounting. |
| V4-17-R04 | IF independent verification is required, THEN Vivi SHALL submit the candidate to the controller-managed verification boundary. | **V4-17-T04:** Maker rename/fork fails; separated recorded checker satisfies only the actually observed evidence grade. |
| V4-17-R05 | IF a task exceeds Vivi's declared authority or greenfield scope, THEN Vivi SHALL return the applicable boundary rather than using method composition to evade it. | **V4-17-T05:** Novel architecture, push/deploy, external spend, and expanded scope. |
| V4-17-R06 | WHEN a context strategy is selected, Vivi SHALL record the strategy version and its observed context-transition boundary. | **V4-17-T06:** Continue, native compaction, and fresh-worker fixtures; unsupported host compaction is unknown, not claimed as completed. |

**Exit.** Apply the common exit above and the package scope; missing required live evidence blocks its live claim, not disclosure of completed fixture work.

**Stop and rollback.** Gauge does not grant publication authority. Mode rollback preserves diff, failed approaches, and unresolved consumption.

---

<a id="v4-18"></a>

## V4-18 — Adopt need-based specialist execution across the roster

**Default source owner:** `Rynaro/eidolons`. **Prerequisites:** `V4-13`, `V4-16`, `V4-17`.

**Starting points:** `EIDOLONS.md`, `roster/routing.yaml`, `methodology/cortex/`, `roster/index.yaml`. Locate actual paths in the pinned checkout; proposed interfaces are not claims of existing code.

**Scope and decisions.** Adopt approved method/worker contracts in explicit profile slices. Preserve named expertise, aliases, purpose, charters, and ceilings for ATLAS, FORGE, VIGIL, IDG, Kupo, Gilgamesh, SPECTRA, and APIVR-Delta. This is not an unrelated global rename. Classify enforceable rules, heuristics, and rationale. Embedded methods cannot substitute silently for a specifically requested independent invocation. Adoption can use external packages without depending on consolidation.

**Implementation sequence.** Assign one profile; define activation and input/output/execution contract; test exact producer/consumer versions; integrate approved identities. Require an evidence record or explicit experimental label for contribution claims.

**Assignment slices:** `ATLAS`, `FORGE`, `VIGIL`, `IDG`, `Kupo`, `Gilgamesh`, `SPECTRA`, `APIVR-Delta`, `nexus-adoption`. Assign one slice at a time; package acceptance covers its declared required slices. Optional deferral is explicit, not a silent pass.

| ID | EARS requirement | Planned verification |
|---|---|---|
| V4-18-R01 | WHEN a task requires expertise but no separate execution boundary, routing SHALL permit an embedded method instead of a mandatory specialist worker. | **V4-18-T01:** Clear fix, targeted discovery, lite planning; preserve deliverables while reducing unnecessary workers. |
| V4-18-R02 | WHEN the user explicitly requests a separate specialist or independent review, routing SHALL preserve that execution requirement. | **V4-18-T02:** Named legacy specialist, separate ATLAS inspection, independent critique, required documentation, and read-only intent. |
| V4-18-R03 | IF a specialist contribution requires a distinct context, permission boundary, or independent track, THEN routing SHALL record that reason on its assignment. | **V4-18-T03:** FORGE/VIGIL consultation, isolated writer, and checker; no unexplained fan-out. |
| V4-18-R04 | WHEN a methodology control is revised, the profile registry SHALL retain its rule, heuristic, or rationale classification and replacement reference. | **V4-18-T04:** Control diff retains protected tests; option counts are heuristics; rationale is not falsely certified. |
| V4-18-R05 | WHEN a profile version is adopted, compatibility validation SHALL check the exact producer and consumer versions. | **V4-18-T05:** Contract/package matrix and discovery parity; no invented tags, changed performatives, or mandatory external-agent imports. |
| V4-18-R06 | WHEN a method advertises isolated execution, its package SHALL declare a bounded input/output contract compatible with that execution form. | **V4-18-T06:** Missing dependency/context input, oversized result, and inline-only skill reject isolation; bounded consultant succeeds. |
| V4-18-R07 | IF a specialist strategy lacks qualifying comparative evidence, THEN the registry SHALL label its performance benefit unproven. | **V4-18-T07:** Untested, no-win, and inconclusive configurations remain experimental or maintenance-justified, not advertised as measured improvements. |

**Exit.** Apply the common exit above and the package scope; missing required live evidence blocks its live claim, not disclosure of completed fixture work.

**Stop and rollback.** Retain opt-out/legacy selection. No silent refusal weakening, source archival, or naming change under a performance adjustment.

---

<a id="v4-19"></a>

## V4-19 — Context, optional memory, and bounded information access

**Default source owner:** `Rynaro/eidolons`. **Prerequisites:** `V4-15`, `V4-21`.

**Starting points:** `cli/src/harness_hook.sh`, `cli/src/lib_context.sh`, `roster/context-policy.yaml`, `roster/pins.yaml`. Locate actual paths in the pinned checkout; proposed interfaces are not claims of existing code.

**Scope and decisions.** Measure actual host-visible instructions, tool schemas, returned data, startup, retrieval, and rebuild costs before optimizing. External evidence is addressable data, not proof it was read. Reuse only dependency-valid evidence. CRYSTALIUM remains optional knowledge, never operational truth; Atomos remains compose/verify-only. No mandatory index, vector store, recursive agent framework, or new service. Keep permitted redacted evidence outside active context with usable references; do not retain hidden reasoning.

**Implementation sequence.** Instrument payload/coverage; implement bounded presentation and source navigation; validate memory scope/version/supersession; exercise cold/warm and no-service modes. Any optional indexed/recursive method gets its own authorized bounded experiment and source/licensing review.

**Assignment slices:** `core-context`, `one-justified-optional-adapter`. Assign one slice at a time; package acceptance covers its declared required slices. Optional deferral is explicit, not a silent pass.

| ID | EARS requirement | Planned verification |
|---|---|---|
| V4-19-R01 | WHEN evidence is reused, the context manager SHALL validate its declared source, criteria, and environment dependencies. | **V4-19-T01:** Relevant mutations/missing artifacts invalidate; unrelated control reuses only with a proven dependency relation. |
| V4-19-R02 | WHEN a tool result exceeds the presentation bound, the context manager SHALL return a localized excerpt with a usable reference to full permitted evidence. | **V4-19-T02:** Decisive assertion outside raw tail, redaction, deleted log, and bounded results; inaccessible reference is reported. |
| V4-19-R03 | WHEN context succession occurs, the controller SHALL retain mandatory pins and outstanding task obligations. | **V4-19-T03:** Cold/warm recovery includes failures, budget, checks, and authority without fabricating unseen history. |
| V4-19-R04 | IF optional memory is unavailable or untrusted, THEN the delivery path SHALL continue without treating memory as authoritative execution evidence. | **V4-19-T04:** No-MCP task, foreign/poisoned note, stale test claim, failed recall; no receipt promotion. |
| V4-19-R05 | WHEN programmatic or batched tool execution is used, the controller SHALL enforce the same operation permissions as individual calls. | **V4-19-T05:** Generic code wrapper attempts denied tool/network/filesystem operations; valid batches remain bounded at the qualified enforcement boundary. |
| V4-19-R06 | WHILE repeated context triggers describe unchanged state, the context manager SHALL avoid duplicate lifecycle work. | **V4-19-T06:** Repeated hooks and threshold oscillation; test configured debounce/hysteresis without asserting universal thresholds. |
| V4-19-R07 | WHEN context overhead is measured, the report SHALL distinguish actual host-visible payload from source-file size and estimated token counts. | **V4-19-T07:** Hidden wrappers, eager/deferred tool schemas, repeated skill descriptions, and unsupported visibility; estimates are labeled. |
| V4-19-R08 | WHERE reusable memory is enabled, the memory adapter SHALL bind each retained item to source provenance, project scope, applicability, and supersession or expiry metadata. | **V4-19-T08:** Cross-project leakage, changed revision, expired item, and deletion/supersession controls; valid scoped item remains retrievable without granting authority. |
| V4-19-R09 | IF retrieved memories conflict or their dependencies are invalid, THEN the context manager SHALL present the conflict or invalidity before using them as task guidance. | **V4-19-T09:** Old and new environment instructions, failed procedure recorded as success, and withdrawn item; no silent newest-text-wins authority. |
| V4-19-R10 | WHEN evidence navigation is observed, the recorder SHALL distinguish discovery, retrieval, and cited use without inferring unobserved model comprehension. | **V4-19-T10:** Reachable-but-unopened reference, truncated decisive fragment, opened evidence, and cited source; availability alone is not counted as use. |
| V4-19-R11 | WHERE indexed or recursive information access is enabled, accounting SHALL include its construction, refresh, retrieval, and descendant inference costs in the declared lifecycle view. | **V4-19-T11:** Cold build, warm reuse, stale refresh, recursive calls, and abandoned tasks; report amortization denominator and unknown costs. |
| V4-19-R12 | WHERE recursive information access is enabled, admission SHALL enforce the configured depth, fan-out, and resource bounds under the original task root. | **V4-19-T12:** Self-referential corpus, cycle, repeated query, and child failure hit configured bounds; no new root or unlimited search on recursion. |

**Exit.** Apply the common exit above and the package scope; missing required live evidence blocks its live claim, not disclosure of completed fixture work.

**Stop and rollback.** No unconditional recall or mandatory service. Optional indexing/recursion is off unless selected; data access remains subject to the same authority and resource limits.

---

<a id="v4-20"></a>

## V4-20 — Truthful CLI status and optional user interfaces

**Default source owner:** `Rynaro/eidolons`. **Prerequisites:** `V4-15`.

**Starting points:** `cli/eidolons`, `docs/cli-reference.md`; locate actual GAMBIT session/status adapter only for its selected slice. Locate actual paths in the pinned checkout; proposed interfaces are not claims of existing code.

**Scope and decisions.** Extend the minimal V4-15 controls, not delay their existence until full roster adoption. Expose the same versioned state to CLI/JSON and optional clients. Keep Final Fantasy names plus plain-language functions; disclose capability/usage gaps and real blockers. Private clients remain separate assignments and are not described publicly. No duplicated budget engine in the UI.

**Implementation sequence.** Generate views from canonical observations; test no-color/headless/keyboard operation; add optional client conformance only if selected. A terminal task state or green UI badge never replaces acceptance evidence.

**Assignment slices:** `core-cli`, `optional-GAMBIT`. Assign one slice at a time; package acceptance covers its declared required slices. Optional deferral is explicit, not a silent pass.

| ID | EARS requirement | Planned verification |
|---|---|---|
| V4-20-R01 | WHEN task status is requested, the interface SHALL report observed delivery and verification states separately. | **V4-20-T01:** Implemented/runnable/checks-passed/review-pending/released, cancelled/partial/blocked, and stale evidence snapshots. |
| V4-20-R02 | WHEN execution participation is displayed, the interface SHALL distinguish methods used, worker identities, and context-separation evidence. | **V4-20-T02:** One maker with many methods versus separate specialist/checker; no fictional team. |
| V4-20-R03 | IF provider quota or enforcement is unsupported or stale, THEN the interface SHALL display that limitation in plain text. | **V4-20-T03:** Unknown bucket, no invented percentage, advisory-only mode, and execution outside controller control. |
| V4-20-R04 | WHEN a user inspects policy or previews a change, the interface SHALL avoid dispatching model work. | **V4-20-T04:** Model-call counters and denied escalation; preview preserves outstanding reservations. |
| V4-20-R05 | WHERE an optional client is installed, the client SHALL consume the same policy/status contract as the CLI. | **V4-20-T05:** Consumer versions and no-GUI/no-color controls; unsupported contract gives a clear error. |
| V4-20-R06 | WHEN a user requests cancellation through a client, the interface SHALL distinguish request acknowledgement, confirmed stop, and accounting reconciliation. | **V4-20-T06:** Native process continues after acknowledgement and usage arrives late; no premature done/refund display. |
| V4-20-R07 | IF a client receives an unsupported contract version, THEN the client SHALL reject authority-bearing mutations while retaining an explicit compatibility diagnostic. | **V4-20-T07:** Future schema cannot be guessed into permission grants; supported read-only diagnostic does not dispatch. |

**Exit.** Apply the common exit above and the package scope; missing required live evidence blocks its live claim, not disclosure of completed fixture work.

**Stop and rollback.** Optional UI deferral does not block CLI or measurement. Status/preview is observational and cannot refill budgets or create live-evidence claims.
