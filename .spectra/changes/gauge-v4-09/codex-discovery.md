# V4-09 preparatory discovery, NOT live qualification

Observed 2026-09-22 UTC: local /opt/homebrew/bin/codex reports codex-cli0.154.0. Only --version and exec --help ran; no prompt, authentication inspection, model call or billing change. Both help invocations warned that PATH aliases could not be created under the sandbox and returned success; no permission escalation was used to create aliases.

Installed help exposes exec --json, --sandbox read-only/workspace-write/danger-full-access, --ephemeral, --output-schema and resume. These are discovered interfaces, not tested execution, cancellation, child visibility, hard-cap or permission enforcement guarantees. Actual model, billing eligibility, allowance, and live method support remain unknown/blocked. No API fallback authorized.

OpenAI Docs skill read at /Users/henrique/.codex/skills/.system/openai-docs/SKILL.md. No official docs MCP available. Read local installed help as required by tool instruction, then fetched official non-interactive documentation (https://developers.openai.com/codex/noninteractive/ redirects to https://learn.chatgpt.com/docs/non-interactive-mode). It documents explicit sandbox selection and JSONL execution events, including termination and usage; final response schema is a formatting feature, not acceptance proof. These documents do not qualify this installed version or its effective local permissions. Do not persist reasoning/private payload items when adding observation support. Reference claim scope is interface documentation only; no live host probe has run.

V4-09 catalogue should record the exact0.154.0 / localCLI / execJSONL / explicitpermission tuple and blocked livecriteria, with fake probes separate. A privileged sibling method cannot inherit qualification from a sandboxed method. Recheck installed version and effective permissions at actual assignment time.

Original-v3 control identity confirmed from V4-01 receipt and main Git history: 752194ef5ceaa8cee1f5995fd0d374888696d8fc (v3.3.1). This is the pre-overhaul source control; do not substitute a post-stabilization commit or fabricate missing structural/managed arms. No comparative outcome was inspected in this preparation.
