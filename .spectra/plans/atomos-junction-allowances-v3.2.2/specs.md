---
eidolon: spectra
version: "4.9.1"
kind: spec
status: in_progress
created_at: "2026-09-13T00:07:14Z"
target_repos: ["Rynaro/eidolons"]
stories_count: 11
validation_gates_count: 33
---

# Atomos, MCP allowances and Junction — follow-up specs

Baseline: `main` = `origin/main` = `v3.2.2^{commit}` = `c195bd25fc9a3fea80fbc98e67cc6ffb7846fc71`. v3.2.2 is already published. These are post-release changes, not release-blocking work on an unpublished version.

WHO: Eidolons maintainers and host orchestrators. WHAT: make Atomos usable through a defined context executor and make MCP capability reporting truthful; then close Junction dispatch gaps. WHY: installed servers can remain unused or unusable while receipts look healthy. CONSTRAINTS: preserve canonical instruction sources, class restrictions, user permissions, existing kernel continuity and Atomos's compose/verify boundary.

Method: ATLAS source/reproduction evidence → installed SPECTRA planning fallback (RAMZA absent locally). MCP memory/tools were unavailable; no live runtime success is claimed. [Investigation](investigation.md) records reproductions and limitations. [Structured specification](specs.json) carries the same requirements and acceptance gates. Prior broad audit remains historical; this bundle supersedes its Atomos/Junction/grant follow-ups for this baseline.

Priority is top-down; dependencies govern implementation order. P1 = broken configuration or capability enforcement; P2 = missing integration/contract; P3 = incorrect discovery metadata. Work on Atomos follows shared P1 prerequisites before Junction automation.

## Implementation status

The first P1 tranche is implemented in the working tree: OCI sync now compares the complete rendered registration, Claude allowance edits parse and validate YAML before atomic mutation, and wiring receipts are written only after a managed allowance is verified. Stale managed markers are repaired and narrowed grants are reconciled by removing only managed allowances. GRANT-02 onward, Atomos executor selection, and Junction dispatch remain pending the versioned host capability and execution contracts specified below.

| ID | Priority | Individual fix | Depends on |
|---|---|---|---|
| MCP-01 | P1 | Reconcile executable registrations across every selected host | — |
| GRANT-01 | P1 | Parse and validate agent tool fields before mutation | — |
| GRANT-02 | P1 | Project canonical capability policy into host adapters | GRANT-01 |
| GRANT-03 | P1 | Reconcile actual grants, exclusions and truthful receipts | GRANT-01, GRANT-02 |
| GRANT-04 | P2 | Separate tool exposure from host execution approval | GRANT-02, GRANT-03 |
| ATOMOS-01 | P2 | Define Atomos composition result and persistence handoff | MCP-01 |
| ATOMOS-02 | P2 | Select Atomos for eligible context operations without naming it in prompts | MCP-01, ATOMOS-01, GRANT-04 |
| ATOMOS-03 | P2 | Consume verification verdicts at receiver and post-compaction gates | ATOMOS-02 |
| JUNCTION-01 | P2 | Align tool declarations with the pinned Junction release | MCP-01 |
| JUNCTION-02 | P2 | Make eligible parent dispatch explicit and provider-aware | JUNCTION-01, GRANT-04 |
| JUNCTION-03 | P3 | Derive the harness marker from the selected project receipt | MCP-01 |

## MCP-01 — Reconcile executable registrations across every selected host

**P1; confirmed defect.** Atomos passes static verification and sync no-ops despite stale mount/UID; any server entry masks absent Codex registration. Junction can likewise retain a nonexistent binary path.

**Scope:** mcp_sync, mcp_verify, OCI/binary installation and host read-back; shared registration comparison.

**Required behavior:** Compare normalized expected command, argv, identity mounts, working directory, user and digest against each selected host. Recognize -u/--user and supported equivalent forms. Reconcile from selected local cache without unnecessary downloads. Keep diagnostics read-only; report per-host failures without a complete-success receipt. Static validity, process readiness and live tool availability must remain separate verdicts.

**Acceptance:**

1. Copied Atomos registration with a foreign mount or wrong --user fails static comparison; requested sync repairs it, and a second sync is byte-stable.
2. With Claude and Codex selected, valid .mcp.json plus missing/malformed Codex config cannot pass; foreign content is preserved on repair failure.
3. A stale Junction command with a valid version-matched local cache repairs without download; a missing cache reports the actual prerequisite.

**Evidence at baseline:** `cli/src/mcp_sync.sh:117-126,154-158`; `cli/src/lib_mcp.sh:172-183,1652-1658,1833-1871`; `.mcp.json:82-101`. **Dependencies:** none.

## GRANT-01 — Parse and validate agent tool fields before mutation

**P1; confirmed defect.** CSV concatenation changes tools: [Read, Grep] into invalid YAML; multi-line lists are also not handled as structured data.

**Scope:** Claude descriptor parser/writer and mcp_wiring regression fixtures.

**Required behavior:** Normalize supported scalar, inline-list and block-list representations while preserving non-owned fields/body and original tool membership. Reject ambiguous, duplicate or malformed frontmatter without replacing the file. Validate output before atomic replacement. Define empty-tool behavior per supported host/version: none is a legacy convention, not assumed universal host syntax; use a supported deny-all representation or refuse safely, never silently switch to inheritance.

**Acceptance:**

1. Scalar, inline-list and block-list fixtures remain parseable and retain built-ins after one MCP grant; repeat apply is byte-stable.
2. Malformed/duplicate tools fields produce a named failure with byte-identical original file.
3. Removing a managed grant preserves unrelated tools; explicit empty/none input either retains the host-supported no-tool restriction or refuses safely without changing bytes.

**Evidence at baseline:** `cli/src/lib_mcp_wiring.sh:219-234,293-304`. **Dependencies:** none.

## GRANT-02 — Project canonical capability policy into host adapters

**P1; confirmed defect; host projection design required.** EIIS v3 discovery adapters omit explicit capabilities; Claude inherits parent tools, so installing adapters can lose restrictions while missing the requested allowance lines.

**Scope:** Schema-validated host capability mapping, lib_eiis_v3 rendering, roster/ACI policy reconciliation, selected host adapters.

**Required behavior:** Use existing roster security plus ACI class boundaries as policy inputs; add a versioned host projection map rather than assuming an unverified package capability field. Generate host-native tool metadata alongside canonical instruction pointers. Effective MCP grants must not override class/operation restrictions; surface conflicts such as tool-less classes versus catalogue all-grants. Preserve required built-ins. Report unsupported host enforcement as advisory, never invent native fields. Define supported host/version contracts before claiming enforcement. Removing Edit/Write while allowing unrestricted Bash or write-capable MCP operations is not sufficient evidence of read-only enforcement.

**Acceptance:**

1. Render -> wire -> parse preserves a scout's read-only boundaries and a coder's required edit/test capabilities; granting memory never creates an MCP-only tools list.
2. Tool-less/class-policy conflict is explicitly reported and never silently widens authority; no duplicated persona or methodology content is introduced.
3. Each supported host has a versioned capability test; unsupported enforcement reports advisory. Claude reuse references an existing parent server instead of creating duplicate inline connections where appropriate.

**Evidence at baseline:** `cli/src/lib_eiis_v3.sh:6-15,66-83`; `cli/src/sync.sh:418-423,593-601`; `roster/index.yaml:254-258`; `roster/aci.yaml:31-65`. **Dependencies:** GRANT-01.

## GRANT-03 — Reconcile actual grants, exclusions and truthful receipts

**P1; confirmed defect.** A stale sentinel prevents repair; skipped/failed patch attempts can still enter the receipt. Exclusions suppress new additions but do not revoke previously managed grants.

**Scope:** MCP grant desired-state reconciliation and receipt/status schema.

**Required behavior:** Recompute desired versus observed tool access on every reconciliation; treat markers as ownership hints, not proof. Record applied, inherited, advisory, excluded, blocked or failed states with reason and host/agent identity. Remove only managed grants when policy/exclusions change. For inheritance, either enforce a host-native restriction or report exclusion as unenforced. Upgrade old receipts without treating their stamps as evidence. Capture ownership before adding grants: identical pre-existing user grants never become installer-owned. Uninstall cleans only managed grants and receipts.

**Acceptance:**

1. A descriptor with a Crystalium sentinel but no Crystalium access is repaired; deleting a glob after install is detected on the next check.
2. Apply -> exclude -> restore -> uninstall -> repeat preserves user-owned tools and reconciles managed grants/receipts idempotently. An identical pre-existing user grant survives exclusion/uninstall, with the exclusion reported as conflicting/unenforced.
3. Missing/read-only descriptor or writer failure yields failed/blocked state, not applied; partial host success remains distinguishable.

**Evidence at baseline:** `cli/src/lib_mcp_wiring.sh:209-212,599-618,753-763,944-947,1007-1029`. **Dependencies:** GRANT-01, GRANT-02.

## GRANT-04 — Separate tool exposure from host execution approval

**P2; contract gap; proposed opt-in behavior.** Catalogue grants affect exposure, not permissions.allow or project-server approval; present wording makes these independent states look equivalent.

**Scope:** Documented permission contract, diagnostic output and optional managed host approval projection.

**Required behavior:** Default approval behavior remains unchanged. Report registered/exposed/approval-required/denied independently. If automatic approvals are offered, require an explicit project policy selecting exact permitted operations, preserve user/admin denies and unrelated rules, and make unsupported hosts advisory. An allowance/exclusion never authorizes broader operations than the member policy. Atomos and Junction remain orchestrator-facing by default. Report approval as unknown/unverified when effective host, user or admin settings and runtime decisions are unavailable; project files alone do not establish effective approval.

**Acceptance:**

1. An exposed but unapproved tool reports approval-required rather than missing or ready-to-execute; a user/admin deny wins. Unobservable effective permission state reports unknown/unverified.
2. If the optional approval projection is implemented, opt-in writes only chosen managed rules and removes only those on uninstall; no global allow-all or prompt bypass is introduced.
3. No-policy projects keep identical approval settings, and documentation explains connection approval separately from tool permission.

**Evidence at baseline:** `cli/src/lib_mcp_wiring.sh:915-947`; `roster/mcps.yaml:105-106,465-466`; `https://code.claude.com/docs/en/permissions#mcp`; `https://code.claude.com/docs/en/mcp#project-scope`. **Dependencies:** GRANT-02, GRANT-03.

## ATOMOS-01 — Define Atomos composition result and persistence handoff

**P2; confirmed missing integration; proposed design.** Atomos is an alternate composer, but the kernel currently composes directly; calling Atomos alone would omit the kernel's persistence/ledger work.

**Scope:** Versioned internal request/result contract between Atomos-capable host adapter and existing context lifecycle code.

**Required behavior:** Define typed semantic inputs, caller identity, request ID, fixed timestamps and result hashes for compose_handoff and compose_externalize_manifest. Prefer write_sidecar=false so the kernel is the sole artifact writer. Validate schema/hash before adopting output; preserve envelope identity, thread and tool-origin provenance. Kernel keeps persistence, ledger and context triggers. Bound deadlines; reuse the same frozen request on kernel fallback. Track persistence receipt/idempotency so a retry does not double-ingest; if the backend cannot guarantee this, expose uncertainty rather than claiming exactly-once delivery.

**Acceptance:**

1. Pinned parity fixtures, including Unicode, multi-line content and tool-origin provenance, produce the same canonical bytes/SHA through Atomos and kernel paths.
2. Malformed result, SHA mismatch or timeout cannot adopt partial output; fallback uses identical frozen inputs and reports its reason.
3. Accepted output enters the existing persist/ledger path once per successful receipt; retry/ambiguous persistence is visible and does not silently duplicate durable writes.

**Evidence at baseline:** `roster/mcps.yaml:456-499`; `cli/src/context_handoff.sh:104-115`; `cli/src/context_externalize.sh:115-196`; `https://github.com/Rynaro/atomos/blob/v0.2.0/internal/server/server.go`; `https://github.com/Rynaro/atomos#parity-contract`. **Dependencies:** MCP-01.

## ATOMOS-02 — Select Atomos for eligible context operations without naming it in prompts

**P2; confirmed missing selection; proposed opt-in integration.** No executor selection path exists. Installation neither enables ECM nor tells the host when to choose Atomos; the current checkout has no project manifest and therefore fails the ECM opt-in gate.

**Scope:** Proposed context.executor setting (kernel|auto|atomos), schema, host request dispatcher, concise discovery guidance and usage receipt.

**Required behavior:** Keep absent setting=kernel for compatibility. With ECM enabled and executor=auto, deterministically select Atomos for its supported operations only when the current host has an implemented tool dispatcher, registration, permission and tool availability; otherwise run kernel with a named reason. executor=atomos must disclose unavailability rather than silently claim Atomos use, while retaining the safe kernel continuity path. Reuse the host's MCP connection; do not launch a new docker run per policy event. Install/status must explain ECM opt-in and executor selection. Record requested/selected backend, actual completion, duration and fallback; never attribute kernel output to Atomos. A prose hint alone is not an implemented dispatcher.

**Acceptance:**

1. An eligible operation on a supported host with ECM+auto invokes the actual Atomos tool without a prompt naming Atomos and consumes the ATOMOS-01 result contract.
2. Disabled ECM, absent Atomos, denied permission, unavailable dispatcher and unsupported operation each select the documented path with a distinct reason; explicit atomos selection does not falsely report success.
3. Repeated events reuse the host connection and deduplicate operation IDs; live smoke evidence is required before advertising support for a host.

**Evidence at baseline:** `cli/src/context.sh:54-55`; `cli/src/harness_hook.sh:113-128`; `schemas/eidolons.yaml.schema.json:108-134`; `methodology/cortex/context-protocol.md:20-32`; `docs/specs/ecm/decisions/atomos-go-no-go.md:17-45`. **Dependencies:** MCP-01, ATOMOS-01, GRANT-04.

## ATOMOS-03 — Consume verification verdicts at receiver and post-compaction gates

**P2; integration gap; advisory semantics confirmed.** Atomos returns advisory data: a successful MCP call does not mean integrity passed, and pin verification neither reinjects nor repairs context.

**Scope:** Host-owned consumption of verify_envelope and verify_pins, existing ECL enforcement and pin recovery integration.

**Required behavior:** Dispatch through ATOMOS-02 using canonical pin set and actual receiver/post-operation artifact. Interpret semantic verdict, missing pins and blocked flags separately from transport success. Existing kernel/host policy decides whether to block, recover or continue; Atomos gains no meter, policy, injection, compaction or persistence authority. Missing/empty pin set or unavailable post-op evidence is indeterminate, not success. Preserve the canonical verifier's block behavior on fallback.

**Acceptance:**

1. Tampered, inconsistent and missing payload cases never pass a blocking receiver solely because tools/call succeeded; canonical verdict matrix parity is checked.
2. A dropped required pin requests host-owned recovery and verifies again; absent evidence/empty expected pins never reports survival.
3. Unavailable Atomos uses the existing verifier with unchanged enforcement; telemetry distinguishes check, recovery, fallback and final outcome.

**Evidence at baseline:** `https://github.com/Rynaro/atomos/blob/v0.2.0/internal/verify/envelope.go`; `https://github.com/Rynaro/atomos/blob/v0.2.0/internal/verify/pins.go`; `methodology/cortex/context-protocol.md:81-93`; `cli/src/verify_envelope.sh`. **Dependencies:** ATOMOS-02.

## JUNCTION-01 — Align tool declarations with the pinned Junction release

**P2; confirmed source/catalogue mismatch; live binary check pending.** Catalogue plan_dispatch/reasoning_step declarations do not match the pinned release registry, which registers harness.plan_from_prompt, harness.run, harness.verify and harness.inject; plan_from_prompt is a permanent stub.

**Scope:** Versioned catalogue tool declarations, generated instructions and released-binary contract check.

**Required behavior:** Record canonical MCP names separately from host-normalized names. Match pinned tools/list, retain the permanent stub as non-executable metadata, and generate instructions only for real supported operations. Verify the pinned binary before claiming runtime parity; source comparison is current evidence.

**Acceptance:**

1. Release-pinned tools/list comparison detects an added, removed or renamed tool; canonical and host-normalized identifiers are separately tested.
2. Generated dispatch never calls plan_dispatch/reasoning_step or relies on plan_from_prompt for planning.
3. A catalogue/registry mismatch reports incompatible readiness and prevents unsupported dispatch.

**Evidence at baseline:** `roster/mcps.yaml:96-113`; `https://github.com/Rynaro/Junction/blob/v0.4.0/internal/mcp/tools.go`. **Dependencies:** MCP-01.

## JUNCTION-02 — Make eligible parent dispatch explicit and provider-aware

**P2; confirmed integration gap; proposed opt-in behavior.** Parent dispatch is prescribed in a deep document but no automatic execution bridge was found; installing the server does not configure reasoning/provider capability.

**Scope:** Opt-in parent execution adapter, validated plans, provider capability checks and result/verification receipts.

**Required behavior:** Construct and validate plans in the parent, check task eligibility, required isolation and provider/sampling support, then call discovered harness.run. Missing prerequisites produce a named fallback before execution. Preserve one-writer authority, scoped workspace access and ECL validation. Keep transport out of worker tool grants. Record requested model, reported/observed model and unknown states separately. Provider none is eligible only for a proven non-reasoning operation.

**Acceptance:**

1. Opted-in eligible chain dispatches without user naming Junction; ineligible tasks do not dispatch, and the permanent planning stub is never used.
2. Missing provider, unsupported sampling, incompatible tool surface or required Docker absence produces a specific fallback without starting implementation.
3. Result verification and model provenance are recorded; worker descriptors never gain orchestration powers as a utilization workaround.

**Evidence at baseline:** `methodology/cortex/handoff-graph.md:78-99`; `cli/src/lib_mcp_wiring.sh:711-718`; `https://github.com/Rynaro/Junction/blob/v0.4.0/internal/reasoning/provider.go`; `https://github.com/Rynaro/Junction/blob/v0.4.0/internal/reasoning/mcp_sampling.go`. **Dependencies:** JUNCTION-01, GRANT-04.

## JUNCTION-03 — Derive the harness marker from the selected project receipt

**P3; confirmed defect.** The first cache directory wins, so marker version 0.2.0 can disagree with a project locked to 0.4.0.

**Scope:** Junction discovery marker generation and status comparison.

**Required behavior:** Use the validated project-selected executable/version, never cache enumeration order. Missing selected executable reports not-ready without silently substituting another version; retain hook ownership and unrelated harness files.

**Acceptance:**

1. With 0.2.0 and 0.4.0 cached and 0.4.0 selected, marker and status resolve 0.4.0.
2. A missing selected executable reports not-ready without selecting 0.2.0 or deleting hooks.
3. Repeated reconciliation is byte-stable and no longer depends on cache directory order.

**Evidence at baseline:** `cli/src/sync.sh:1038-1042`; `.eidolons/harness/manifest.json:1`; `eidolons.mcp.lock:61`. **Dependencies:** MCP-01.

## Validation and implementation boundaries

The 33 acceptance gates above are specifications, not tests already passed. Source/fixture findings are high confidence; host execution and live provider behavior remain unverified. The executor setting, response contract and approval policy are proposed interfaces for review; they are not installed functionality.

Recommended delivery groups: (1) MCP-01 and GRANT-01, (2) GRANT-02/03/04, (3) ATOMOS-01/02/03, (4) JUNCTION-01/02/03. Each future implementation must retain separate read-only diagnostics, prove effective host behavior, and report unverified states honestly. Do not create one container per policy operation or substitute textual instructions for an executed integration.
