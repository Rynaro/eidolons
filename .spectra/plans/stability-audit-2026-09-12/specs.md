---
eidolon: spectra
version: "4.9.1"
kind: spec
status: proposed-no-implementation-authorized
created_at: "2026-09-12T20:53:16Z"
target_repos: [Rynaro/eidolons]
stories_count: 15
validation_gates_count: 15
---

# Eidolons stability: 15 individual fix specs

Investigated checkout **3.2.1 / fd02811**, 12 September 2026. ATLAS scouts supplied evidence; SPECTRA reviewed scope and acceptance. These are proposals, not implemented fixes. P0 = potential user-data loss; P1 = release-blocking correctness/integration; P2 = reliability, economy, or requested augmentation. Order within each priority is the proposed work order.

Evidence labels: **reproduced** = isolated fixture; **confirmed** = source/configuration evidence; **unverified** = needs live host evidence; **augmentation** = deliberate behavior change. Runtime success is not inferred from generated files.

## S01 · P0 · Preserve valid Codex TOML and user configuration

**Evidence — reproduced.** Shell substitution removes table-ending newlines; concatenation produces `args = ["first"][mcp_servers.second]`. The closing marker lands inline, so the next rewrite cannot recognize it and deletes following user configuration. Environment objects use JSON `:` instead of TOML `=`. Sources: [lib_mcp.sh:985–1061](../../../cli/src/lib_mcp.sh).

**Fix boundary.** One TOML-aware, transactional writer for install/refresh/sync/uninstall. Preserve unowned content; serialize strings/env correctly; delimit managed regions on separate lines; reject ambiguous existing corruption without truncating it. Validate the staged file before replacement and retain a recoverable prior version.

**Acceptance.** Real TOML parsing passes for 1/2/5 MCPs, env/escaping, no final newline, and repeated operations. A user table below the managed region survives byte-for-byte; malformed/missing markers leave the original intact. **Depends:** none.

## S02 · P1 · Generate discoverable Codex agents

**Evidence — confirmed.** Both writers emit `instructions`: [lib_eiis_v3.sh:76–84](../../../cli/src/lib_eiis_v3.sh), [sync.sh:454–467](../../../cli/src/sync.sh). Codex requires `developer_instructions` alongside `name` and `description`; other supported configuration can supply model, sandbox and MCP settings. [Official agent schema](https://learn.chatgpt.com/docs/agent-configuration/subagents).

**Fix boundary.** Correct both writers and migrate owned legacy descriptors. Use escaped TOML values, valid canonical paths and role-appropriate settings. Validate against a declared supported Codex version; preserve user-owned customization.

**Acceptance.** Fresh install and upgrade discover and invoke the intended custom agent; its canonical persona/refusals load. Missing required fields, broken references and unsupported configuration fail validation. Check the generated descriptor, not a hand-written fixture. **Depends:** S01 writer infrastructure where shared.

## S03 · P1 · Enforce MCP grants on the actual host surface

**Evidence — confirmed.** Codex grants target `.codex/agents/*.md` and a YAML `tools:` mutator, while installs emit `.toml`: [lib_mcp_wiring.sh:391–443,771–774](../../../cli/src/lib_mcp_wiring.sh). Tests still fabricate legacy Markdown: [mcp_wiring.bats:158–174,727–750](../../../cli/tests/mcp_wiring.bats). Codex can inherit parent MCP configuration, so this proves failed grant/exclusion enforcement, **not** universal tool absence.

**Fix boundary.** Map catalogue grants to supported per-host capability controls. Record granted, inherited, excluded or unsupported explicitly; never report an unenforced restriction as applied. Preserve Junction/ATOMOS transport-only semantics.

**Acceptance.** Install actual generated agents, attach MCPs, and inspect/invoke permitted tools. Denied/excluded agents cannot invoke them when enforcement is claimed; inheritance is tested. Re-sync and uninstall reconcile exposure. **Depends:** S01–S02.

## S04 · P1 · Honor model selection and report what actually ran

**Evidence — reproduced/confirmed.** A Codex model pin resolves but wiring skips it when the profile remains default Anthropic. Sync skips all wiring without a nonempty `models` block and suppresses failures: [lib_model_resolve.sh:184–198,265–270](../../../cli/src/lib_model_resolve.sh), [lib_model_wiring.sh:378–434,480–503](../../../cli/src/lib_model_wiring.sh), [sync.sh:700–702](../../../cli/src/sync.sh). The lock records a resolved value even if wiring skipped or preserved another value. Routing emits tiers, not proof of execution: [run.sh:1–10,385–386](../../../cli/src/run.sh).

**Fix boundary.** Resolve a compatible profile per host; honor explicit pins independently of unrelated default-profile gating. Make inheritance/fallback an explicit policy. Keep desired, written and observed model/effort separate; propagate the selected model at dispatch. Surface unsupported hosts or rejected models; preserve deliberate user overrides while reporting divergence.

**Acceptance.** Default, pin, calibration, mixed-host, preserved-override and unavailable-model cases give accurate outcomes. A cheap-model worker under an expensive parent uses the requested model where the host supports selection; unsupported/unknown observation is explicit. Record token usage when available. **Depends:** S02.

## S05 · P1 · Diagnose and verify MCP startup

**Evidence — confirmed; live failure attribution unverified.** This checkout binds CRYSTALIUM to `/home/rynaro/...`, absent on this machine: [.mcp.json:18–23](../../../.mcp.json). Health checks CLI/daemon/image rather than MCP initialization: [lib_mcp.sh:1704–1771](../../../cli/src/lib_mcp.sh). Docker access was unavailable to this audit; that is an environment limitation, not a proven project daemon failure.

**Fix boundary.** Validate executable, configuration, bind sources, permissions and image before a bounded initialize/tools-list handshake. Distinguish unavailable daemon, invalid config, missing mount, server crash and timeout. Re-render machine-local paths from canonical settings on relocation; do not distribute developer-specific absolute paths as reusable configuration.

**Acceptance.** Each failure identifies the failing stage and exits/statuses consistently. A real isolated CRYSTALIUM startup handshakes successfully, emits no protocol noise and cleans up; moved-project/home fixtures regenerate valid mounts. **Depends:** S01, S07.

## S06 · P1 · Apply installation to the requested project only

**Evidence — confirmed.** OCI install accepts `--project-root`, but grant wiring uses CWD; Junction's binary install does not receive the target root: [mcp_install.sh:101–135](../../../cli/src/mcp_install.sh), [lib_mcp.sh:1907–1912,1963–1968](../../../cli/src/lib_mcp.sh).

**Fix boundary.** Resolve one project root and carry it through installation, server config, grants, hooks, lock and subsequent reconciliation. Report affected paths before mutation; fail on an invalid target.

**Acceptance.** From project A, installing each MCP into B changes only B's project artifacts. Test spaces, relative/absolute paths and both driver kinds. Refresh/uninstall use the same root contract. **Depends:** S01, S03.

## S07 · P1 · Make MCP sync repair drift and report truthfully

**Evidence — confirmed.** Same-version no-op checks only lock/runtime receipt, leaving deleted/broken host config unrepaired. `changed` increments in a pipeline subshell, so the final summary reports zero: [mcp_sync.sh:74–129](../../../cli/src/mcp_sync.sh), [lib_mcp.sh:170–183](../../../cli/src/lib_mcp.sh). Plain `eidolons sync` intentionally differs from `eidolons mcp sync`.

**Fix boundary.** Reconcile desired MCP state against actual server config, descriptors, grants and receipts. Track created/repaired/unchanged/failed outcomes in the parent process. Make plain sync's MCP exclusion visible and provide an explicit combined-sync option; preserve existing command semantics by default.

**Acceptance.** Removing or corrupting each owned artifact at an unchanged version is repaired or produces an actionable conflict. A second sync has no changes; counts and exit status match actual effects. **Depends:** S01–S03, S06, S08.

## S08 · P1 · Respect declared MCP version constraints

**Evidence — confirmed.** `^` and `~` constraints select catalogue stable without checking compatibility: [mcp_sync.sh:79–99](../../../cli/src/mcp_sync.sh).

**Fix boundary.** Resolve supported constraints against available releases and the existing lock under an explicit update policy. Never cross an incompatible range silently; fail clearly on an unsatisfied or unsupported expression.

**Acceptance.** Exact, caret, tilde, zero-major and prerelease fixtures select only compatible versions. A newer incompatible stable release causes no accidental upgrade; unsatisfiable constraints leave installed state unchanged. **Depends:** none.

## S09 · P1 · Install every referenced routing resource

**Evidence — confirmed.** Root cortex links use `methodology/cortex/`, but sync copies seven fixed files to `.eidolons/cortex`; it omits chain templates, dispatch predicate and context protocol: [sync.sh:717–754](../../../cli/src/sync.sh), [EIDOLONS.md:51–89,161](../../../EIDOLONS.md).

**Fix boundary.** Package a complete declared resource closure and render references to canonical installed paths. Validate recursive local references inside the installed package, without requiring the nexus source checkout.

**Acceptance.** In an empty consumer, all routing/deep-table references resolve under `.eidolons`; scout→planner and context-policy instructions can be followed. Removing a referenced resource fails package validation; repeated sync is stable. **Depends:** none.

## S10 · P2 · Bound MCP lifecycle and container cost

**Evidence — confirmed architecture; reported leak unverified.** CRYSTALIUM uses `docker run --rm -i` per client with no shared-service boundary: [crystalium template:3–26](../../../cli/templates/mcp/crystalium.mcp.json.tmpl). Preflight can create another transient process: [memory.sh:318–402](../../../cli/src/memory.sh). Four clients can legitimately produce four containers; live client ownership was not observable here.

**Fix boundary.** Add ownership/session labels, client/process accounting, resource budgets and disconnect cleanup first. For reducing one-project duplication, specify a managed broker with an atomic start lock and reference-counted clients; enable shared backing only where server isolation semantics support it. Never attach unrelated clients directly to one raw stdio stream or reap active sessions to meet a count target.

**Acceptance.** Four simultaneous clients have attributable, bounded resources; shared mode starts one backing instance per isolation/configuration identity and routes replies correctly. Killing one client leaves others working; last disconnect cleans up; different projects remain isolated. Preflight transients are bounded and measured. **Depends:** S05.

## S11 · P2 · Make Junction selection deterministic

**Evidence — confirmed contract gap.** Junction is intentionally transport-only and excluded from member allowlists: [roster/mcps.yaml:96–113](../../../roster/mcps.yaml), [lib_mcp_wiring.sh:708–715](../../../cli/src/lib_mcp_wiring.sh). Orchestration is assigned to the host in prose: [handoff-graph.md:77–99](../../../methodology/cortex/handoff-graph.md); no automatic invocation bridge was found in the audited integration paths.

**Fix boundary.** Add host-dispatch capability negotiation and an explicit routing rule for tasks needing Junction execution/transport. Invoke it from the orchestrator, with a bounded fallback and traceable selection reason. Do not force trivial or read-only tasks through it.

**Acceptance.** A qualifying prompt without the word “Junction” uses the configured transport; nonqualifying tasks skip it with a reason. Unavailable transport yields a declared fallback/failure and never a hidden authority expansion. **Depends:** S03–S04, S05.

## S12 · P2 · Activate ATOMOS only for its defined context work

**Evidence — confirmed design gap.** ATOMOS has transport wiring and no member grants: [roster/mcps.yaml:456–477](../../../roster/mcps.yaml). Its contract limits it to compose/verify; kernel metering, policy and triggers remain canonical: [context-protocol.md:190–198](../../../methodology/cortex/context-protocol.md). No automatic selection path was found.

**Fix boundary.** Add a capability-gated executor choice for brief composition and verification. Trigger it at relevant lifecycle transitions; retain the kernel fallback. Start it on demand where supported; otherwise disclose host startup behavior and disable unused registration by default.

**Acceptance.** A qualifying context transition invokes ATOMOS and verifies the resulting pins/envelope. Ordinary prompts avoid it; absence/failure uses the kernel path without recursive retries or repeated startup. **Depends:** S05, S09.

## S13 · P2 · Make AGENTS.md the shared instruction authority

**Evidence — augmentation.** Root `AGENTS.md` and `CLAUDE.md` are separate real files today. Doctor explicitly rejects shared-dispatch symlinks: [doctor.sh:198–209](../../../cli/src/doctor.sh). The current design already centralizes routing in EIDOLONS and vendor pointers in [lib_eidolons_md.sh:51–59,105–144](../../../cli/src/lib_eidolons_md.sh); this proposal changes that adapter contract.

**Fix boundary.** Consolidate shared project instructions into AGENTS.md, retaining EIDOLONS as the routing module and `.eidolons` as canonical package storage. Install `CLAUDE.md → AGENTS.md` and equivalent relative links for compatible plain-Markdown vendor entrypoints. Preserve and reconcile existing vendor-specific guidance before migration; structured formats need thin native adapters, not invalid symlinks. Update doctor, sync and removal ownership together.

**Acceptance.** Each compatible vendor reads identical shared instructions; paths resolve after project moves and Git checkout. Migration preserves existing guidance and offers recovery; symlink-unavailable platforms use a declared pointer fallback, never silently duplicated authority. **Depends:** S09.

## S14 · P2 · Complete canonical hook attachment and verification

**Evidence — partly implemented.** Hook shims already live at `.eidolons/harness/hooks`: [harness_install.sh:26,811–849](../../../cli/src/harness_install.sh). Registrations live in host-native JSON; `harness check` only checks Claude/Codex registration paths: [harness_check.sh:20–49](../../../cli/src/harness_check.sh).

**Fix boundary.** Keep all owned hook executable content/resources under `.eidolons`; attach by relative symlink where a host loads hook files, or a native registration referencing the canonical command where it requires JSON. Extend installation receipts and checks to every declared host/event. Preserve unrelated user hooks.

**Acceptance.** Each supported hook is reachable, executable and fires exactly once for its declared event. Missing registration, broken link and duplicate registration are detected across hosts, including Copilot. Sync/removal preserves user hooks; unsupported events are reported explicitly. **Depends:** S06, S13 migration compatibility.

## S15 · P2 · Budget the context actually loaded

**Evidence — confirmed accounting gap.** The budget check covers only 3,342 marker-bounded characters (836 proxy tokens); whole EIDOLONS is 13,048 bytes, roughly 3.3k tokens by the same rough proxy. Host pointers request reading the whole file: [scripts/token-budget-check.sh](../../../scripts/token-budget-check.sh), [sync.sh:770–776](../../../cli/src/sync.sh). This is not a marker-budget invariant violation; markers do not make a host omit text.

**Fix boundary.** Make the physical entry document small and load deep resources by phase. Measure unique instruction bytes/tokens, tool schemas, handoff payloads, duplicated context and observed usage per dispatched role/model. Prefer fresh bounded scout contexts and compact evidence handoffs; mark unavailable host telemetry as unknown.

**Acceptance.** A representative multi-agent task demonstrates what each host actually injects and stays within a declared budget, including vendor adapters. Compare baseline/candidate cost and task quality; no fabricated token savings or silent loss of pinned constraints. **Depends:** S04, S09, S13–S14.

## Release sequence and augments

**Release gate:** S01 first; complete S02–S09 before claiming a stable compatibility release. S10–S15 are separately reviewable follow-ups; prioritize S10 next if live ownership measurements confirm leaked or excessive processes. No broad reinstall/upgrade before S01 protects existing configuration.

- **A01 · Generated-consumer acceptance matrix.** Test fresh install → startup → custom-agent dispatch → permitted/denied tool use → model observation → sync → upgrade → uninstall in disposable consumers for each supported host/version. Pass only on host behavior, not grep matches. Cover package resource closure and canonical adapter links. Makes the existing fixture blind spots a release gate.
- **A02 · One diagnostic receipt.** Expose declared/installed/registered/healthy/used MCP states, owner/client count, actual hook events, and desired/written/observed model plus token telemetry. Redact secrets. An issue report should explain “unused,” “inherited,” “unsupported” and “unknown” without requiring transcript archaeology.
- **A03 · Reproducible dogfood consumer.** Keep a declared test manifest/lock and run the release candidate against it; require installed roles/resources to match that declaration. This checkout has no root consumer manifest/lock and lacks installed RAMZA, so that absence is a coverage gap, not proof of a broken install. Generate routing/usage documentation from explicit catalogue participation metadata to avoid infrastructure-versus-agent ambiguity.

## Validation performed and remaining evidence

- All **56 tests passed** across `eiis_v3.bats`, `eiis_v3_effectiveness.bats`, `model_resolve.bats`, `model_wiring.bats`. They do not establish real host discovery, permission enforcement or model execution.
- Isolated calls to the existing TOML merger reproduced multi-server parse failure, invalid env syntax, and deletion of a following user profile on the next rewrite. Model helpers reproduced a resolved Codex pin being skipped by profile gating and the absent-models-block bypass. No implementation was changed.
- CRYSTALIUM/Junction/ATOMOS/ATLAS-ACI tools were not exposed in this session. Docker client ownership, startup logs, actual billed model and complete host-injected context remain unverified. Reproduction must use disposable consumers and bounded integration checks; no live containers were started/stopped by this audit.
- Three ATLAS branches requested `gpt-5.6-terra` with fresh contexts; the SPECTRA critique requested the roster's deep model, `gpt-5.6-sol`. These are tool-requested settings, not independently measured billing evidence. The missing installed RAMZA prompted an explicit SPECTRA fallback.

Implementation remains a separate, unstarted phase. The JSON companion contains the same work-item IDs, dependencies and acceptance targets for later dispatch.
