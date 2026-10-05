# Issue 640 — Host-scoped model and routing policy

Planner: SPECTRA (gpt-6-astra, medium). Maker: Vivi (gpt-6-sol).

For each wired managed host/member, resolve an applicable complete policy before generating adapters. Add host-specific profiles and explicit unmanaged opt-out. Preserve compatible legacy single-host configurations and automatic host-compatible defaults only when policy is absent. Reject invalid/incompatible explicit policies with actionable migration diagnostics.

Codex managed descriptors explicitly own model and reasoning effort. Profile data provides light/standard/deep model and effort values. Unnamed children receive conservative configurable model/effort defaults; inheritance must be explicit. Preserve user-owned TOML and surface conflicts. Optional concurrency settings use supported host configuration.

Per-host locks, model status, doctor, and harness status separate configured policy, surface presence, local smoke, runtime qualification, and observed model/effort. Unknown runtime evidence stays unknown.

Generate Codex event matcher groups containing command hooks. Preserve unrelated hooks. Execute SessionStart/UserPromptSubmit smoke probes against the real routing kernel without a model call. Distinguish missing CLI, malformed input, kernel failure and invalid/empty output. Respect fail-open, warn, fail-closed with bounded diagnostics and recognized blocking payloads. Local smoke is not live runtime qualification.

Acceptance checks: incident fixture fails before writing; explicit three-host profile fixture succeeds; expensive parent fixture leaves named and unnamed children pinned; unmanaged/conflict/idempotence/legacy migration tested; doctor catches model and effort drift; hook failure matrix and successful real-kernel smoke tested; full make check and independent review pass.

Release target: 4.4.1; VERSION and CHANGELOG PR, merge after CI, dispatch canonical workflow, verify release/tag/assets. Optional deep-tier concurrency is omitted without host enforcement. No token-accounting or live model observation claims.
