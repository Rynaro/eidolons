# FORGE decision

Accept v4.4.1 remediation: reject explicit incompatible policies, auto-select host-compatible policy only when absent, retain fail-open compatibility with observable diagnostics and explicit stronger policies.

Rejected silent global fallback because it changes user intent; rejected default blocking for all hooks because compatibility and host enforcement are separate. Require malformed-policy rejection, complete model/effort ownership, truthful opt-out, distinguish warn/fail-open, and no fake runtime qualification. Confidence 78%; design approval is not implementation verification. Official host blocking semantics were supplied separately by orchestrator from https://learn.chatgpt.com/docs/hooks .
