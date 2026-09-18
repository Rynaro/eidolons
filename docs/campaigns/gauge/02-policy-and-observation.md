# Phase 2 — Persistent policy and truthful observation

Entry: Phase 1 accepted. Exit: G04–G06 accepted. No live routing, model default, retry policy, or permission changes occur in this phase. Read [HANDOFF.md](HANDOFF.md); [plan.yaml](plan.yaml) owns dependencies.

## G04 — Persistent Gauge configuration and explainable resolution

**Primary repository:** Rynaro/eidolons. Start with `cli/eidolons`, configuration helpers in `cli/src/lib.sh`, `schemas/`, `roster/model-profiles.yaml`, and existing model/configuration commands and tests.

Implement a validated nexus-owned `gauge:` configuration block and user preferences under the existing Eidolons user configuration root. Proposed commands are `eidolons gauge set <conserve|balanced|accelerate> --user|--project` and `eidolons gauge explain --host <host> --json`; these are design targets, not commands that exist at campaign baseline. Reuse existing parsing/configuration conventions and preserve unrelated keys/comments where the existing writer supports that guarantee.

Preference precedence is user default → trusted project preference → explicit run override. Limits and permissions do not use last-writer-wins: compute the intersection of independently applicable operator/project/run ceilings, keeping each scope distinct. The model and untrusted repository content cannot raise operator ceilings, grant authority, or authorize paid overages. Root and child policy snapshots record origin and digest. Mid-run preference changes apply to future decisions; explicit limit increases require operator authorization and do not erase prior consumption. A stricter new limit must stop new work when appropriate without destroying current work.

Define candidate preset behavior, not arbitrary model IDs or guaranteed savings: Conserve minimizes speculative coordination; Balanced spends on consequential uncertainty; Accelerate permits justified critical-path parallelism. Quality and authority requirements are the same for the same risk class. Numeric budgets come from an explicit operator/project policy; do not canonize the earlier illustrative 45-minute/24-call example as a calibrated default.

| Acceptance | Required verification |
|---|---|
| G04-A1: Preference precedence and intersected ceilings are deterministic and explained per field. | Table-driven conflicting configuration fixtures, equivalent input ordering, and repeated explain output. |
| G04-A2: Untrusted inputs cannot raise ceilings or permissions. | Repository override, model-authored config, memory-origin instruction, and run override escalation attempts. |
| G04-A3: Invalid/duplicate keys, invalid numbers, unknown enums, and incompatible versions do not silently resolve. | Parser/schema negative fixtures; explicit diagnostics before persistence/dispatch. |
| G04-A4: User/project writes are idempotent and preserve unrelated settings. | Repeat set operations, existing host/user config, Unicode/spaced paths, and unwritable config cases. |
| G04-A5: Opt-out behavior and a running task's policy identity remain stable. | No `gauge:` project fixture plus a changed preference during a run; no runtime effect in this phase. |

**Stop/rollback:** ship configuration/explanation only. Do not call a model, select another host, invent a provider conversion, or claim managed execution. Disable the block without deleting user configuration or historical policy snapshots.

## G05 — Root-run identities and multidimensional usage observations

**Primary repository:** Rynaro/eidolons. Start with `cli/src/run.sh`, `cli/src/telemetry.sh`, `cli/src/trace.sh`, `cli/src/ledger.sh`, `cli/src/lib_context.sh`, and existing telemetry/context schemas and fixtures. Depends on G04.

Generate a unique root execution ID for each actual task attempt; keep route digest as a distinct deterministic description. Record parent/child, native session, request/turn, host/model, policy, project, account-pool alias, and allowance-window identities as available. Never persist credentials as IDs. A resume inherits its original root; a genuinely new task gets a new root even when the prompt/route is identical.

Normalize independent dimensions: context occupancy, observed input/output/cache usage, estimated money, provider-reported allowance/reset information, elapsed time, and local limits. Preserve original host fields and units. Record source/observation grade, observed-at time, freshness, and unknown/unsupported states. Define cumulative-versus-delta semantics, event deduplication, corrections, and delayed-arrival handling. Avoid double charging parent totals plus their child details. Price estimates cite a versioned pricing source; do not confuse them with subscription consumption.

Bind observations to G01's journal and G02/G03 evidence. Collector failures must not crash unrelated existing hooks; they must become an explicit observability state the future managed controller can refuse to rely on. Default retention is local, bounded, and redacted. Raw prompts, hidden reasoning, full tool output, secrets, and private provider account details are not necessary telemetry.

| Acceptance | Required verification |
|---|---|
| G05-A1: Identical routes can have distinct execution roots; descendants and resumes do not reset the root. | Two new runs, child dispatch, session resume, provider switch, and checkpoint succession fixtures. |
| G05-A2: Duplicate, out-of-order, cumulative, corrected, and delayed events reconcile once. | Cross-check normalized totals against independent expected values, including parent/child overlap. |
| G05-A3: Unknown quota/pricing/model identity never becomes zero or an invented value. | Missing fields, stale observations, unavailable model assignment, cache-only usage, and reset-boundary fixtures. |
| G05-A4: Reports never blend unlike units or evidence grades. | Assert separate typed fields and source splits in JSON and human summaries. |
| G05-A5: Failed collection is visible but preserves hook safety and privacy. | Corrupt transcript, denied access, secret-like input, and collector interruption; inspect stored records and existing hook exit behavior. |

**Stop/rollback:** no account scraping, automatic provider switching, reservations, or billing claims. Retain old report compatibility or publish an explicit schema migration. Unknown observations remain recoverable records.

## G06 — Host capability probes, shadow observations, and frozen trial protocol

**Primary repository:** Rynaro/eidolons. Start with host adapters, `cli/src/harness_hook.sh`, readiness/canary implementation, and live-evaluation fixtures. Depends on G05.

Define capabilities per installed host/version/mode, not one unconditional host label: agent dispatch; requested versus observed model; reasoning-effort control; input/output usage; provider allowance visibility; cancellation; per-request limits; tool/permission enforcement; child observation; and resume/context succession. Distinguish advisory, monitored, and managed, with a capability-specific reason when a requirement cannot be met. Registration/syntax success is not proof that a real model session executed the hooks.

Use deterministic/fake-host probes first. Verify current native interfaces against official host documentation before coding an adapter; archive the documentation date and the installed version actually tested. Probe Claude Code and Codex candidates without hardcoding a preference from their names. G08 selects the first qualified host using observed capabilities and existing integration reuse. A managed capability that needs a paid live check remains unverified until an explicit operator allowance exists.

Run shadow policy evaluation only: record what Gauge would propose and its reason, but do not modify actual route, models, prompts, or retries. Minimize observer overhead and measure it. Preserve the G03 original control configuration. Before optimization trials, freeze a protocol with task strata, acceptance/oracle definitions, intervention labels, unit-specific spending limits, runtime/config controls, held-out task ownership, trial counts or stopping rules, analysis methods, numerical non-inferiority/material-benefit margins, and safety stop rules. Parameters must be approved before observing comparative outcomes; do not derive a success bar from results.

| Acceptance | Required verification |
|---|---|
| G06-A1: Unsupported/unknown capabilities prevent a managed label. | Version/mode fixtures with missing cancellation, child accounting, model controls, or only registration checks. |
| G06-A2: Shadow mode has no execution side effects. | Compare routes/tool decisions and emitted host configuration with shadow mode on/off; only observation artifacts differ. |
| G06-A3: Strict requirements never silently degrade. | Request unavailable managed controls; return a preflight explanation without model execution. |
| G06-A4: Baseline and prospective protocol are frozen before a live comparison. | Check immutable refs/digests, version manifest, preregistered margins/stopping rules, and holdout access restrictions. |
| G06-A5: Capability and observer-overhead claims match actual tests. | Fake-host conformance plus separately labeled authorized live evidence; missing live access is a scoped blocked check, not a pass. |

**Stop/rollback:** no behavior/default changes. Disable observation without deleting evidence. Phase 2 may finish fixture-backed surfaces while live capability proof remains explicitly blocked; Phase 3 cannot claim a qualified live managed path until that proof is supplied.
