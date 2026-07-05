## DISCOVER — Elicitation Summary

**Incoming request:** "We need better observability for our platform."

**Why DISCOVER (not RS, not CLARIFY, not a plan):** Per `skills/discover.md`'s
boundary rule, DISCOVER fires when *the goal itself* is unknown or latent —
not merely when spec details are ambiguous. This request has no metric, no
named stakeholder, no defined "platform," and no stated scope: the objective
is latent, so the intent reads as `IDEA`/`STRATEGIC`, which routes to DISCOVER
before CLARIFY (SPEC.md "## Pre-phases"). Running `ramza-rightsize` or drafting
a Scope artifact now would silently invent a goal that was never given —
exactly the failure mode DISCOVER exists to prevent. This document is
elicitation only; it produces no plan and stops at the CLARIFY hand-off /
escalation.

### Checklist

- [ ] **Stakeholders:** [GAP] — the request names no requester, no affected
  team, and no approver. "Our platform" implies *some* internal engineering
  org, but which team is asking (SRE? a product squad? platform infra?), who
  is affected by the current observability gap (on-call engineers? support?
  leadership doing postmortems?), and who signs off on the eventual plan are
  all unidentified. Approval chain: [GAP].
- [ ] **Latent goal:** [GAP] — "better observability" is the surface ask, not
  the underlying job-to-be-done. The latent goal driving this request could
  plausibly be: faster incident detection / reduced MTTR, meeting an
  SLA-or-SLO commitment that's currently being missed, cost/capacity
  visibility, a compliance/audit requirement, or unblocking onboarding for a
  new service — none of these is confirmed by the request text, so the real
  outcome behind "we need better observability" remains [GAP].
- [ ] **Success metrics:** [GAP] — no target metric and no current baseline
  are given (e.g., "MTTR from 45min → 15min," "trace coverage from 20% →
  90%," "alert noise ratio," "dashboard/query adoption"). Without a stated
  success metric, downstream complexity scoring (`ramza-score --rubric
  complexity`) has nothing to calibrate against, and "better" cannot be
  falsified as done or not done.
- [ ] **Hard constraints:** [GAP] — budget, existing tooling investments
  (is there already an APM/logging vendor to extend vs. replace?),
  compliance regime, timeline, and even which "platform" (which service,
  stack, or environment) is in scope are all unspecified.
- [ ] **Non-goals:** [GAP] — nothing has been explicitly ruled out. Without
  stated non-goals, "observability" can silently expand to cover logging,
  metrics, tracing, alerting/on-call, SLO management, cost monitoring, and
  security auditing all at once — a classic scope-creep vector this axis
  exists to surface early.

### Open gaps

- [GAP] Stakeholders — requester, affected teams, and approver chain unknown.
- [GAP] Latent goal — the underlying outcome/job-to-be-done is not
  distinguished from the stated surface request.
- [GAP] Success metrics — no measurable target or baseline exists to define
  "better."
- [GAP] Hard constraints — budget, stack/platform identity, compliance,
  and deadline all unknown.
- [GAP] Non-goals — scope boundary undefined; risk of scope creep across
  every observability sub-domain (logs, metrics, traces, alerting, SLOs,
  cost, security).

### Coverage

coverage: 0/5 resolved, 5/5 unresolved [GAP] axes ≥ 2 ⇒ **ESCALATE to human**
(per `skills/discover.md`'s mechanical coverage contract: `unresolved_count
>= 2` ⇒ escalate rather than hand off to CLARIFY outright). This is a
mechanical count of `[GAP]` tokens on the five checklist lines above, not a
self-assessment.

### Hand-off

This elicitation is bounded to a single pass (per DISCOVER's "no unbounded
interview loop" constraint) and cannot resolve 5/5 latent axes from the
request text alone, so it escalates rather than silently proceeding. The
escalation doubles as the hand-off packet CLARIFY would need once the human
resolves enough gaps to bring `unresolved_count` to ≤1. The ≤3 questions
CLARIFY would ask, surfaced now so the human can answer them directly instead
of routing through another elicitation pass:

1. **Who is asking, and what outcome are they actually chasing?** — resolves
   Stakeholders + Latent goal in one shot (e.g., "SRE on-call wants faster
   incident triage" vs. "Platform team wants cost visibility for the board")
   and determines which "platform" is even in scope.
2. **What does "better" mean, measured how, against what current baseline?**
   — resolves Success metrics; without this, no complexity score or plan
   shape can be justified downstream.
3. **What's explicitly out of scope, and what constraints (budget, existing
   tooling, deadline, compliance) already bound the answer?** — resolves
   Hard constraints + Non-goals together, since a stated non-goal is often
   just the flip side of a stated constraint (e.g., "extend existing vendor,
   do not introduce a new one" is both).

No `ramza-rightsize` call, no Scope artifact, and no plan follow from this
document — DISCOVER's contract ends here, at the escalation/hand-off, per
`agent.md`'s "≥2 unresolved `[GAP]` axes in DISCOVER → escalate to the human
with the gap report."
