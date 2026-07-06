---
eidolon: ramza
version: 0.2.0
kind: spec
status: ready-for-apivr
created_at: 2026-07-05T19:49:00Z
thread_id: 018f6b1e-9c3a-7c2a-9a3e-2f0b6a5d7e11
target_repos:
  - main-app
stories_count: 5
validation_gates_count: 21
confidence: 0.775
decisions_resolved_at: 2026-07-05T20:20:00Z
---

# SAML Single Sign-On for an App with Existing Email/Password Auth

## Scope

Intent class: CHANGE

In: Add SAML 2.0 SSO as an additional authentication method to an application that
already has email/password auth and a session model other services depend on.
Covers: SP-initiated login, identity linking for existing accounts, session
issuance compatibility, security controls, rollout/kill-switch strategy, and
acceptance criteria.

Out: IdP-initiated login is rejected by default (AC-004) — can be enabled per
organization in a later phase, not this spec. SAML Single Logout (SLO) at the
IdP. SCIM/automated user provisioning or deprovisioning. Multiple concurrent
IdPs per organization. Enforcing SSO-only (disabling password login) for a
linked account — the design leaves the *capability* to add that switch later
(AC-013's "unless SSO-only enforcement is enabled" is a forward-compatible
hook) but does not ship the enforcement UI/flow in this phase.

Deferred: Brand-new account auto-provisioning via SAML for users with no
existing local account (just-in-time provisioning) — risk if wrong: silently
trusting an IdP assertion to create a full account without human/admin
review broadens the trust boundary further than "linking" does; deferred
until the linking flow has run in production and its failure modes are
understood. Concretely, AC-009 (failed ownership verification) and AC-020
(zero-match) both route to the *existing manual signup flow*, never to an
auto-created account — this is a deliberate seam so that JIT provisioning
can be added later as its own reviewed change, not an oversight. SSO-only
enforcement per account/org — risk if wrong: locking users out if the IdP
has an outage, before the kill-switch and monitoring have a production
track record (Story 4).

Assumptions:
- The application has exactly one session model/token format shared by
  multiple downstream services ("other services depend on it" per the
  mission) — risk if wrong: if session consumers are more heterogeneous than
  assumed, AC-014/AC-015's "no schema change" guarantee needs re-verification
  per consumer, not just centrally.
- Local accounts have a verified email address available for NameID/email
  matching — risk if wrong: without a verified-email precondition, matching
  degrades to an unverified claim and the linking flow (Story 2) cannot rely
  on email as a matching key; would need a different matching strategy
  (manual admin-assisted linking only).
- Exactly one IdP per organization for this phase — risk if wrong: the
  config model (one metadata blob per org) would need to become a list,
  changing Story 1's configuration surface.
- "Existing accounts" means accounts already authenticated at least once via
  password — risk if wrong: if invited-but-never-logged-in accounts also need
  linking, AC-007's "existing, verified local account" precondition needs a
  second matching path for not-yet-activated accounts.

Complexity (`ramza-score --rubric complexity`): 11/12 → human_loop (scope=3,
ambiguity=2, dependencies=3, risk=3 — the ambiguity component reflects that
no concrete target codebase/session-token schema was supplied; the
dependencies and risk components reflect the mission's own framing that
"other services depend on" the session model and that this is a security
change. `human_loop` routing is the correct signal here, not a defect: see
Confidence below).

CLARIFY: skipped. The mission statement is a REQUEST/CHANGE with the goal,
required coverage (identity linking, security risks with severity, rollout,
acceptance criteria, ≥1 rejected alternative), and constraints (existing
password auth, shared session model) already explicit — no unresolved axis
changes this plan's shape enough to justify a clarification round before
Scope.

## Pattern

No CRYSTALIUM MCP tools are available in this environment (checked at
activation) and no application codebase is present in this project to query
for prior session/auth-integration patterns — this is a standalone spec with
a generic target ("main-app"), not a scan of a real repository. Per the
Pattern phase's match bands (≥85% template, 60–84% adapt, <60% generate),
this is a **generate** case: the design below is built from well-established,
externally documented SAML SP patterns (SP-initiated redirect binding,
signature/audience/replay validation, "shadow account" identity linking with
explicit user confirmation) rather than from an internal template. No prior
RAMZA/SPECTRA plans were available to surface as anti-patterns for this repo.

## Approach

**Theme:** Federated authentication. **Project:** SAML SSO enablement.
**Feature:** SP-initiated SAML login with confirmed identity linking.

Selected approach (winning hypothesis from Explore, hyp-A, `ramza-score
--rubric explore` total **81.5/100 → solid**): implement SAML as an
**additional, parallel** login path that terminates at the app's existing,
**unmodified** session-issuance code — the same code path, token format, and
validation logic used today for password logins (AC-014). A SAML login that
matches an existing verified local account by NameID/email does **not**
auto-link; it requires an explicit confirmation step where the user proves
they control the local account (active session or password re-entry) before
the identity is linked (AC-007, AC-008, AC-010). This keeps the SSO feature
additive and reversible: the shared session model that other services depend
on is never touched, so there is no coordinated multi-service migration, and
the kill switch (Story 4) can disable new SAML logins without touching
password auth or existing sessions at all.

Three other hypotheses were explored and rejected — see **Rejected
Alternatives**.

## Stories

### Story 1: SP-initiated SAML login with security-hardened assertion validation

As a user in an organization with SAML SSO configured, I want to sign in via
my organization's IdP, so that I don't need a separate app password.
Timebox: 5d.
Risk tag: P0.
Executor hint: mid tier — file-level action plan (new SAML request/ACS
handler module, wired to the existing session-issuance function; named
pattern: "SP-initiated redirect binding + POST binding ACS", per the SAML 2.0
core spec), no line-level scripting. Flagged for higher-scrutiny/mandatory
security review before merge: this story owns the Critical-severity
"assertion tampering / signature-wrapping" and "replay" risks (see Risks),
so its review rigor should exceed a typical mid-tier story even though the
executor tier label is the same as Story 2/3.

### Story 2: Identity linking for existing accounts

As an existing email/password user, I want my SSO login linked to my current
account only after I've proven it's mine, so that no one else can take over
my account via SSO.
Timebox: 4d.
Risk tag: P0.
Executor hint: mid tier — file-level action plan (new federated-identity
mapping table: `idp_issuer + name_id -> local_account_id`, unique
constraint on the pair; link-confirmation UI flow), named pattern:
"shadow-account linking with proof-of-ownership".

### Story 3: Session-issuance compatibility guarantee

As a downstream service owner, I want SAML-authenticated sessions to be
indistinguishable in shape from password-authenticated sessions, so that I
don't have to change anything to keep working.
Timebox: 2d.
Risk tag: P0.
Executor hint: mid tier — contract/characterization tests asserting
byte-for-byte token-schema parity between the two auth methods, plus one new
internal-only metadata field (`auth_method`) that is not serialized into the
token payload consumed by other services.

### Story 4: Staged rollout, feature flag, and kill switch

As an operator, I want to enable SAML SSO per organization gradually and be
able to shut it off instantly if something goes wrong, so that a SAML defect
can't become an outage or a security incident.
Timebox: 3d.
Risk tag: P1.
Executor hint: mid tier — action plan: per-org feature flag, global kill
switch, error-rate alert wired to on-call, staged rollout runbook (see
Rollout Strategy).

### Story 5: Logout parity

As a SAML-linked user, I want logout to work the same way it does today, so
that ending my session behaves predictably.
Timebox: 1d.
Risk tag: P2.
Executor hint: economy tier — reuse the existing logout route as-is, no new
logic; explicitly no new SLO (Single Logout) protocol work in this phase
(see Scope: Out). Near-zero ambiguity relative to Story 1, so it does not
need the file-level scaffold a mid-tier story gets.

**Story ordering:** Story 1 (SAML/ACS handler) must land before Stories 2
and 3 begin — both depend on a working assertion-validation pipeline to
link against or contract-test. Story 4 (flag, kill switch, alerting) can be
scaffolded in parallel with Story 1. Story 5 has no dependency and can run
any time. The 15-day story-timebox sum is therefore not a flat critical
path: with Story 1 (5d) gating Stories 2+3 (which can then run partly in
parallel with each other), the realistic critical path is closer to
5d + max(4d, 2d) = 9d for Stories 1-3, plus Story 4/5 absorbed in parallel.

## Acceptance Criteria

`ramza-ears-lint`-clean EARS-form blocks (also maintained as the frozen
sibling file `.spectra/plans/2026-07-05-saml-sso.acceptance.md` — that file
is the one passed to `ramza-freeze`; the content below is identical to it at
freeze time).

### AC-001 (event-driven)
GIVEN a user's organization has SAML SSO enabled
WHEN  the user completes authentication at the IdP and the app receives a valid SAML response
THEN  the app SHALL establish an authenticated session via the existing session-issuance path within 2s of assertion receipt
VERIFY: test: e2e/saml_login_spec#establishes_session_on_valid_assertion

### AC-002 (unwanted-behavior)
GIVEN a SAML response is received at the Assertion Consumer Service (ACS) endpoint
WHEN  the assertion's XML signature or audience restriction fails validation
THEN  the app SHALL reject the login and SHALL issue no session
VERIFY: test: spec/saml/assertion_validation_spec#rejects_invalid_signature_or_audience

### AC-003 (unwanted-behavior)
GIVEN a SAML assertion is received
WHEN  the assertion's NotBefore/NotOnOrAfter window has elapsed (beyond a 60s clock-skew allowance)
THEN  the app SHALL reject the assertion as expired
VERIFY: test: spec/saml/assertion_validation_spec#rejects_expired_assertion

### AC-004 (unwanted-behavior)
GIVEN the app only supports SP-initiated login by default
WHEN  a SAML response's InResponseTo does not match an outstanding SP-initiated AuthnRequest ID
THEN  the app SHALL reject the response as unsolicited
VERIFY: test: spec/saml/assertion_validation_spec#rejects_unsolicited_response

### AC-005 (event-driven)
GIVEN a SAML assertion has already been consumed once
WHEN  the same assertion ID is presented again
THEN  the app SHALL reject the second presentation as a replay
VERIFY: test: spec/saml/replay_protection_spec#rejects_replayed_assertion_id

### AC-006 (event-driven)
GIVEN a SAML authentication attempt is in progress
WHEN  the app rejects the attempt for any reason (signature, audience, expiry, unsolicited, or replay)
THEN  the app SHALL record a correlation ID and a machine-readable rejection reason to the audit log
VERIFY: test: spec/saml/audit_logging_spec#logs_rejection_with_correlation_id

### AC-007 (event-driven)
GIVEN a SAML assertion's NameID/email matches exactly one existing, verified local account
WHEN  the app evaluates the match for identity linking
THEN  the app SHALL present an explicit link-confirmation step requiring proof the user controls that local account
VERIFY: test: e2e/account_linking_spec#requires_confirmation_before_link

### AC-008 (unwanted-behavior)
GIVEN a SAML assertion matches an existing local account by email
WHEN  the app cannot verify the user controls that account (no active local session and no successful re-authentication)
THEN  the app SHALL NOT create an identity link to that account
VERIFY: test: spec/account_linking_spec#refuses_link_without_ownership_proof

### AC-009 (event-driven)
GIVEN link-confirmation ownership verification has failed
WHEN  the app finishes processing the failed verification
THEN  the app SHALL route the user to the existing manual account-signup flow instead of linking, not to any just-in-time auto-provisioning path
VERIFY: test: e2e/account_linking_spec#routes_to_signup_on_verification_failure

### AC-010 (event-driven)
GIVEN a user has proven ownership of the matched local account
WHEN  the user confirms the link
THEN  the app SHALL record the federated identity (IdP issuer + NameID) against that existing account
VERIFY: test: spec/account_linking_spec#persists_link_on_confirmation

### AC-011 (event-driven)
GIVEN a SAML NameID is already linked to a local account
WHEN  that same NameID authenticates again
THEN  the app SHALL resolve the login to the same linked account without re-confirmation
VERIFY: test: spec/account_linking_spec#resolves_repeat_login_without_reconfirmation

### AC-012 (unwanted-behavior)
GIVEN a SAML NameID is already linked to local account A
WHEN  a link attempt arrives that would associate the same NameID with a different local account B
THEN  the app SHALL reject the new link attempt as a conflict
VERIFY: test: spec/account_linking_spec#rejects_duplicate_link_conflict

### AC-013 (state-driven)
GIVEN an account has an active SAML identity link and its organization has not enabled SSO-only enforcement
THEN  the app SHALL continue to accept that account's existing email/password sign-in
VERIFY: test: spec/account_linking_spec#password_login_remains_available_by_default

### AC-014 (ubiquitous)
THEN  the app SHALL issue sessions for SAML-authenticated users through the same session-issuance path and token format used for password logins
VERIFY: test: spec/session/cross_service_compat_spec#saml_and_password_sessions_share_issuance_path

### AC-015 (ubiquitous)
THEN  the app SHALL record the authentication method as auth-service-internal session metadata without adding new fields to the token schema consumed by downstream services
VERIFY: test: spec/session/auth_method_metadata_spec#records_method_without_changing_token_schema

### AC-016 (optional-feature)
GIVEN the `saml_sso` feature flag is enabled for an organization
THEN  the app SHALL expose a "Sign in with SSO" entry point for that organization's users
VERIFY: test: spec/rollout/feature_flag_spec#exposes_entry_point_when_flagged

### AC-017 (event-driven)
GIVEN the `saml_sso` kill switch is currently enabled
WHEN  an operator disables the kill switch
THEN  the app SHALL stop issuing new SAML-based sessions within 60s, leaving existing password-based sessions unaffected
VERIFY: test: spec/rollout/kill_switch_spec#stops_new_saml_sessions_on_disable

### AC-018 (event-driven)
GIVEN an organization has SAML SSO enabled
WHEN  SAML login errors exceed 5% of attempts for that organization over a 15-minute window
THEN  the monitoring system SHALL page the on-call rotation
VERIFY: gate: alert rule alerts/saml_error_rate.yml + runbook runbooks/saml-sso.md

### AC-019 (event-driven)
GIVEN a SAML-linked user has an active local session
WHEN  the user logs out of the app
THEN  the app SHALL terminate the local session via the existing logout path
VERIFY: test: e2e/saml_login_spec#logout_terminates_local_session_only

### AC-020 (event-driven)
GIVEN a SAML assertion's NameID/email matches zero existing local accounts
WHEN  the app evaluates the match for identity linking
THEN  the app SHALL route the user to the existing manual account-signup flow
VERIFY: test: e2e/account_linking_spec#routes_to_signup_on_zero_match

### AC-021 (unwanted-behavior)
GIVEN a SAML assertion's NameID/email matches more than one existing local account
WHEN  the app evaluates the match for identity linking
THEN  the app SHALL reject automatic linking and require admin-assisted review
VERIFY: test: spec/account_linking_spec#requires_admin_review_on_ambiguous_match

## Rollout Strategy

**Phase 0 — Dogfood (internal org only), ~1 week.** `saml_sso` flag on for the
internal/staff organization only. Dual-auth: password login stays fully
available side-by-side with SSO for every user (no SSO-only enforcement
exists in this phase at all — see Scope: Out). Alert rule (AC-018) and kill
switch (AC-017) live before any external org is flagged on.

**Phase 1 — Design-partner pilot, 1–3 orgs, ~2 weeks.** Enable per-org via
the feature flag (AC-016) for a small number of opt-in customers. Require a
minimum soak period (both auth methods observed working, error rate under
the AC-018 threshold) before Phase 2. Support/runbook on-call briefed.

**Phase 2 — General availability (opt-in per org).** Org admins can enable
`saml_sso` themselves once IdP metadata is configured and validated. Kill
switch remains a global, instant, one-flag rollback the whole way through —
because SAML sessions ride the unmodified session-issuance path (AC-014),
disabling the flag stops *new* SAML logins without touching any existing
session, password login, or other service.

**Rollback:** flip `saml_sso` off (org-level or the global kill switch). No
data migration to undo: the identity-link mapping table (Story 2) is
additive and inert with the flag off — leaving linked rows in place is safe
and reversible (they simply stop being consulted); operators may optionally
purge them per data-retention policy, but nothing requires it for rollback
to be safe. This is a direct consequence of the Approach's core decision
(session model untouched) and is the reason hyp-A was selected over hyp-B
(see Rejected Alternatives).

**Explicitly deferred to a later phase (see Scope):** SSO-only enforcement
per org/account, just-in-time new-account auto-provisioning, multi-IdP per
org, SLO.

## Confidence

`ramza-score --rubric confidence`: 77.5% → **VALIDATE** (pattern_match=70,
requirement_clarity=75, decomposition_stability=80, constraint_compliance=85).

This is an honest, not a gamed, outcome: `pattern_match` and
`requirement_clarity` are held down specifically because no real target
codebase, session-token schema, or IdP inventory was supplied to this
planning session (Pattern phase found nothing to query — see Pattern
section) — the spec is necessarily generic at those two points
(`target_repos: [main-app]` is a placeholder). `decomposition_stability` and
`constraint_compliance` score higher because the story/AC breakdown is
internally stable and the core constraint driving the whole Approach — never
touch the shared session model — is respected throughout (AC-014, AC-015).
VALIDATE means a human (security review + the team that owns the real
session/auth code) should confirm the placeholder assumptions in Scope
against the actual system before this spec is executed — consistent with
Complexity's `human_loop` routing above. Running additional Refine cycles
would not raise `pattern_match`/`requirement_clarity` further, because the
gap is an external-information gap (no real repo given), not a prose-quality
gap; looping would be ceremony for its own sake (P0 constraint: "Ceremony is
a failure mode").

## Rejected Alternatives

- **hyp-B — Session model extended with federated-identity claims,
  provider-agnostic session issuance** — `ramza-score --rubric explore`
  total **63.5/100 (weak)** (alignment 7, correctness 7, maintainability 7,
  performance 7, simplicity 4, risk 4, innovation 6). Rejected because it
  directly modifies the shared session model the mission says other services
  already depend on — the `simplicity` and `risk` dimensions are the low
  points precisely because every downstream consumer would need coordinated
  changes/re-validation, which is the exact blast radius hyp-A was chosen to
  avoid.

- **hyp-C — External auth broker (e.g., a Keycloak/Auth0-style service)
  fronting all authentication, password included** — total **54/100 (weak)**
  (alignment 5, correctness 6, maintainability 7, performance 6, simplicity 3,
  risk 3, innovation 8). Rejected as over-scoped for the ask: the mission is
  to add SAML to an existing app, not re-architect all authentication through
  a new stateful broker; cutting *existing* password users over to a new
  broker is a much larger, riskier migration than the mission calls for, and
  `simplicity`/`risk` reflect that mismatch.

- **hyp-D — Auto-link matched accounts by verified email with no explicit
  confirmation step** — total **61/100 (weak)** (alignment 6, correctness 4,
  maintainability 8, performance 9, simplicity 9, risk 2, innovation 3).
  Rejected specifically on the `risk` dimension (lowest of all four
  hypotheses' risk scores): silent auto-linking on email match is a known
  account-takeover vector (email reassignment/collision at the IdP or in the
  local system) and directly contradicts the mission's explicit ask to name
  security risks with severity rather than accept one by default. Kept as a
  named alternative because it is the only genuinely faster/simpler option
  and a future admin-opt-in "trusted domain auto-link" mode could reconsider
  it under tighter preconditions.

## Risks

| Risk | Severity | Tag | Mitigation |
|---|---|---|---|
| Account takeover via identity linking without proof of ownership | Critical | P0 | Explicit link-confirmation requiring active session or password re-entry (AC-007, AC-008); reject on unverifiable ownership (AC-008); no silent auto-link (rejected as hyp-D) |
| Assertion tampering / signature-wrapping style forgery | Critical | P0 | Validate signature over the full assertion using a vetted SAML library, enforce audience restriction and issuer allowlist (AC-002) |
| Assertion replay | High | P1 | Track consumed assertion IDs, reject repeats (AC-005); bounded validity window with ≤60s clock skew (AC-003) |
| Session-model regression breaking dependent services | Critical | P0 | SAML issues sessions via the unmodified existing path/token format (AC-014, AC-015); cross-service contract tests in CI; staged rollout with an instant, flag-only kill switch (Story 4) |
| IdP outage locking users out of an org that adopted SSO | Medium | P2 | Password login remains available by default while SSO-only enforcement is unimplemented/off (AC-013); status-page + support runbook |
| Silent config drift (wrong ACS URL, expired IdP signing cert) breaking login for an org | Medium | P2 | Validate IdP metadata at configuration time; certificate-expiry alerting ahead of expiry |
| NameID reassignment at the IdP (e.g., email/UPN recycled to a new employee) causing a mislinked account | High | P1 | Prefer an immutable IdP-issued persistent NameID format over email where the IdP supports it; periodic reconciliation report; admin review gate before removing/re-pointing an existing link |
| Duplicate-link race/conflict when two flows attempt to link the same NameID concurrently | Medium | P2 | Unique constraint on (idp_issuer, name_id) at the data layer; reject the losing attempt as a conflict (AC-012), not a silent overwrite |

## Machine-Readable Summary

```yaml
schema: ramza/spec-summary.v1
plan: 2026-07-05-saml-sso
tier: full
intent_class: CHANGE
theme: Federated authentication
project: SAML SSO enablement
selected_hypothesis: hyp-A
selected_hypothesis_score: 81.5
rejected_hypotheses:
  - {label: hyp-B, score: 63.5, verdict: weak}
  - {label: hyp-C, score: 54, verdict: weak}
  - {label: hyp-D, score: 61, verdict: weak}
stories:
  - {id: 1, title: "SP-initiated SAML login", timebox: 5d, risk_tag: P0, executor_tier: mid, scrutiny: high, criteria: [AC-001, AC-002, AC-003, AC-004, AC-005, AC-006]}
  - {id: 2, title: "Identity linking for existing accounts", timebox: 4d, risk_tag: P0, executor_tier: mid, criteria: [AC-007, AC-008, AC-009, AC-010, AC-011, AC-012, AC-013, AC-020, AC-021]}
  - {id: 3, title: "Session-issuance compatibility guarantee", timebox: 2d, risk_tag: P0, executor_tier: mid, criteria: [AC-014, AC-015]}
  - {id: 4, title: "Staged rollout, feature flag, kill switch", timebox: 3d, risk_tag: P1, executor_tier: mid, criteria: [AC-016, AC-017, AC-018]}
  - {id: 5, title: "Logout parity", timebox: 1d, risk_tag: P2, executor_tier: economy, criteria: [AC-019]}
story_dependencies:
  - {story: 1, blocks: [2, 3]}
  - {story: 4, parallel_with: [1]}
  - {story: 5, parallel_with: [1, 2, 3, 4]}
critical_path_days: 9
complexity: {total: 11, verdict: human_loop}
confidence: {total: 77.5, verdict: VALIDATE}
refine: {cycle: 1, verdict: pass, total: 4, min: 4, critic_author: ramza-sonnet5-maker, critic_checker: ramza-sonnet5-critic}
declared_scope:
  - "src/auth/saml/*"
  - "src/auth/linking/*"
  - "src/session/metadata/*"
  - "config/saml/*"
  - "db/migrate/*identity_link*"
  - "alerts/saml_error_rate.yml"
  - "runbooks/saml-sso.md"
```

---

# Audit trail

This section quotes the **actual stdout/stderr** of every `bin/ramza-*` gate
tool invocation run during this planning session, in chronological order.
Plan slug: `2026-07-05-saml-sso`. State file:
`.spectra/plans/2026-07-05-saml-sso.state.json` (schema `ramza/plan-state.v1`).
All output paths live under `.spectra/`, per RAMZA's P0 constraint; nothing
under `.eidolons/` was modified.

## 1. RS — Right-size (tier decision)

Command:
```
bash .eidolons/ramza/bin/ramza-rightsize --files-est 12 --new-dep --public-api --migration --security --stakes high \
  --plan 2026-07-05-saml-sso --state .spectra/plans/2026-07-05-saml-sso.state.json
```
Actual stdout/stderr:
```
state initialised: .spectra/plans/2026-07-05-saml-sso.state.json (tier: full, score: 8)
full
```
Signals used and why: `--files-est 12` (≥10 → 2 pts: SAML request/ACS handler,
identity-link table + migration, session metadata field, feature flag, kill
switch, alert rule, runbook, multiple test suites); `--new-dep` (a SAML
library is a new dependency); `--public-api` (new SSO login/ACS routes are
externally reachable); `--migration` (identity-linking storage); `--security`
(explicit); `--stakes high` (auth + a session model other services depend
on). `--novel` was deliberately **not** set — SP-initiated SAML SSO with
confirmed account linking is a well-documented, standard integration
pattern, not a novel technique. Score 8 ≥ 5 → **full** tier.

## 2. Gate walk (RS → S → P → E → C → T → R → T → A → DONE)

```
$ bash .eidolons/ramza/bin/ramza-gate status --state .spectra/plans/2026-07-05-saml-sso.state.json
{
  "plan": "2026-07-05-saml-sso",
  "tier": "full",
  "phase": "RS",
  "next": "S",
  "refine_cycles": 0,
  "skips": [],
  "criteria_frozen": false
}

$ bash .eidolons/ramza/bin/ramza-gate advance --state <state> --to S
OK: RS -> S

$ bash .eidolons/ramza/bin/ramza-gate advance --state <state> --to P
OK: S -> P

$ bash .eidolons/ramza/bin/ramza-gate advance --state <state> --to E
OK: P -> E

$ bash .eidolons/ramza/bin/ramza-gate advance --state <state> --to C
OK: E -> C

$ bash .eidolons/ramza/bin/ramza-gate advance --state <state> --to T
OK: C -> T

$ bash .eidolons/ramza/bin/ramza-gate critic --state <state> --author ramza-sonnet5-maker --checker ramza-sonnet5-critic
OK: critic recorded (author: ramza-sonnet5-maker, checker: ramza-sonnet5-critic)

$ bash .eidolons/ramza/bin/ramza-gate refine --state <state>
OK: T -> R (cycle 1/3)

$ bash .eidolons/ramza/bin/ramza-gate advance --state <state> --to T
OK: R -> T

$ bash .eidolons/ramza/bin/ramza-gate advance --state <state> --to A
OK: T -> A

$ bash .eidolons/ramza/bin/ramza-gate advance --state <state> --to DONE
OK: A -> DONE

$ bash .eidolons/ramza/bin/ramza-gate status --state <state>
{
  "plan": "2026-07-05-saml-sso",
  "tier": "full",
  "phase": "DONE",
  "next": "DONE",
  "refine_cycles": 1,
  "skips": [],
  "criteria_frozen": true
}
```
No skips were recorded — every tier-mandatory phase for `full`
(RS S P E C T A, plus the critic record before A) was actually entered in
order; `ramza-gate advance --to A` would have DENIED without the critic
record (mechanically enforced, not a convention).

## 3. S — Scope: complexity score

```
$ echo '{"scope":3,"ambiguity":2,"dependencies":3,"risk":3}' | bash .eidolons/ramza/bin/ramza-score --rubric complexity --state <state>
calibration log appended: .spectra/plans/ramza-calibration.jsonl
{
  "rubric": "complexity",
  "total": 11,
  "dims": { "scope": 3, "ambiguity": 2, "dependencies": 3, "risk": 3 },
  "verdict": "human_loop",
  "at": "2026-07-05T19:49:00Z"
}
```

## 4. E — Explore: 4 hypotheses scored

```
$ echo '{"alignment":9,"correctness":9,"maintainability":8,"performance":8,"simplicity":7,"risk":8,"innovation":4}' \
  | bash .eidolons/ramza/bin/ramza-score --rubric explore --state <state> --label "hyp-A-sp-initiated-confirm-link"
{
  "rubric": "explore", "total": 81.5,
  "dims": {"alignment":9,"correctness":9,"maintainability":8,"performance":8,"simplicity":7,"risk":8,"innovation":4},
  "verdict": "solid", "at": "2026-07-05T19:49:55Z", "label": "hyp-A-sp-initiated-confirm-link"
}
exit=0

$ echo '{"alignment":7,"correctness":7,"maintainability":7,"performance":7,"simplicity":4,"risk":4,"innovation":6}' \
  | bash .eidolons/ramza/bin/ramza-score --rubric explore --state <state> --label "hyp-B-session-model-extension"
{
  "rubric": "explore", "total": 63.5,
  "dims": {"alignment":7,"correctness":7,"maintainability":7,"performance":7,"simplicity":4,"risk":4,"innovation":6},
  "verdict": "weak", "at": "2026-07-05T19:49:55Z", "label": "hyp-B-session-model-extension"
}
exit=1

$ echo '{"alignment":5,"correctness":6,"maintainability":7,"performance":6,"simplicity":3,"risk":3,"innovation":8}' \
  | bash .eidolons/ramza/bin/ramza-score --rubric explore --state <state> --label "hyp-C-external-auth-broker"
{
  "rubric": "explore", "total": 54,
  "dims": {"alignment":5,"correctness":6,"maintainability":7,"performance":6,"simplicity":3,"risk":3,"innovation":8},
  "verdict": "weak", "at": "2026-07-05T19:49:55Z", "label": "hyp-C-external-auth-broker"
}
exit=1

$ echo '{"alignment":6,"correctness":4,"maintainability":8,"performance":9,"simplicity":9,"risk":2,"innovation":3}' \
  | bash .eidolons/ramza/bin/ramza-score --rubric explore --state <state> --label "hyp-D-autolink-no-confirm"
{
  "rubric": "explore", "total": 61,
  "dims": {"alignment":6,"correctness":4,"maintainability":8,"performance":9,"simplicity":9,"risk":2,"innovation":3},
  "verdict": "weak", "at": "2026-07-05T19:49:55Z", "label": "hyp-D-autolink-no-confirm"
}
exit=1
```
`ramza-score` exits 1 on a `weak` verdict by design (documented in the tool's
own usage text) — the three rejected hypotheses each score `weak` for
distinct, real reasons (see "Rejected Alternatives" above), which is exactly
what makes them usable as rejected alternatives rather than strawmen; hyp-A
is clearly separated from the rest (81.5 vs. a 54–63.5 band), so no
"insufficient differentiation" re-observe was triggered.

## 5. T — Test: structural + EARS lint (first pass, pre-refine)

```
$ bash .eidolons/ramza/bin/ramza-lint --plan .spectra/plans/2026-07-05-saml-sso.md --state <state>
ok: plan passes structural lint (tier: full)
exit=0

$ bash .eidolons/ramza/bin/ramza-ears-lint .spectra/plans/2026-07-05-saml-sso.md
ok: 19 criteria pass EARS lint
exit=0

$ bash .eidolons/ramza/bin/ramza-ears-lint .spectra/plans/2026-07-05-saml-sso.acceptance.md
ok: 19 criteria pass EARS lint
exit=0
```

## 6. T — Independent critic (maker≠checker)

A single clean-context subagent was spawned via the Agent tool (no
prior-conversation context, no author identity, no chat reasoning — only the
three permitted artifacts: the plan `.md`, the acceptance-criteria `.md`, and
the state `.json`) to critique the draft per `.eidolons/ramza/skills/critic.md`.
Its full returned report, verbatim, including the tool output it independently
reproduced:

```
## Critique — 2026-07-05-saml-sso

**Verdict:** ramza-lint clean · ramza-ears-lint clean · refine rubric: pass (total 4, cycle 1)

**Findings**
- clarity (4/5): AC-009's "route the user to new-account provisioning instead of linking" is left undefined against the Scope: Out/Deferred section, which explicitly excludes "Brand-new account auto-provisioning via SAML for users with no existing local account (just-in-time provisioning)." As written, AC-009 could be read either as redirecting to the existing manual signup form (in scope) or as auto-creating an account from the SAML assertion (explicitly deferred) — the plan never reconciles the two.
- completeness (4/5): Story 2/AC-007 only specify behavior when a SAML NameID/email "matches exactly one existing, verified local account." There is no acceptance criterion for the zero-match case (a first-time SSO user with no existing local account at all) or the ambiguous multiple-match case — both are plausible real-world outcomes of email-based matching that the mission's "identity linking for existing accounts" requirement implicitly needs covered, and neither has a VERIFY anchor.
- actionability (4/5): Story 5's executor hint ("mid tier — file-level action plan... no line-level scripting") is identical in tier to Story 1's, despite Story 5 being explicit reuse of an existing route with 1-day timebox and P2 tag, while Story 1 is P0 cryptographic assertion validation (signature, audience, replay, unsolicited-response rejection). The uniform "mid tier" label doesn't differentiate a near-zero-ambiguity story from a security-critical one, understating the review rigor Story 1 likely needs relative to its stated tier.
- efficiency (4/5): The five stories sum to a 15-day timebox, but the plan never states execution order or dependencies, even though Story 2 (linking) and Story 3 (session-issuance contract tests) clearly build on Story 1's new SAML/ACS handler. Whether the 15 days is a serial critical path or parallelizable across engineers is left unstated, which affects rollout-schedule accuracy in Story 4/Rollout Strategy.
- testability (4/5): 18 of 19 ACs carry concrete, measurable VERIFY anchors (e.g., 2s session-establishment window in AC-001, 60s clock-skew in AC-003, 5% error-rate/15-min window in AC-018, 60s kill-switch in AC-017) and the ears-lint tool confirms all 19 are structurally clean EARS blocks. The one gap is a consequence of the completeness finding above: because no AC names the zero-match/ambiguous-match identity-linking case, there is no VERIFY line to exercise it, leaving that behavior unverifiable as currently scoped.

**Prescriptions**
1. AC-009 / Scope: Deferred — Add a clause to AC-009 (or a new AC-009a) that explicitly names the target of "new-account provisioning" as the existing manual signup flow, and add one sentence to Scope cross-referencing that AC-009 does not invoke JIT auto-provisioning, closing the apparent contradiction with the Deferred section.
2. Story 2 / AC-007 — Add two new EARS criteria: one for "NameID/email matches zero existing accounts" (define the routing target, likely the same manual-provisioning path as AC-009) and one for "NameID/email matches more than one local account" (define reject-and-require-admin-review or similar), each with its own VERIFY test anchor.
3. Story 5 executor hint — Re-tier Story 5's hint down (e.g., "low tier — reuse existing route, no new logic") to match its actual near-zero ambiguity, and add an explicit note to Story 1's hint flagging it as higher-scrutiny/security-review-required given its P0 tag and the Critical-severity "assertion tampering / signature-wrapping" risk it owns, so the two "mid tier" stories aren't handed to an executor with equal implied rigor.
4. Rollout Strategy / Stories section — Add a one-line dependency/ordering note (e.g., "Story 1 must land before Stories 2 and 3 begin; Story 4's flag can be scaffolded in parallel") so the 15-day sum isn't mistaken for a stated critical path.
5. AC-007/AC-009 (follow-on to #1 and #2) — Once the zero-match and multi-match criteria exist, add their VERIFY test names to the Machine-Readable Summary's Story 2 `criteria` list so the new ACs are tracked the same way AC-007–013 are today.

---

**Verbatim tool output**

`ramza-lint`:
ok: plan passes structural lint (tier: full)
EXIT_CODE_LINT=0

`ramza-ears-lint`:
ok: 19 criteria pass EARS lint
EXIT_CODE_EARS=0

`ramza-score --rubric refine --cycle 1`:
calibration log appended: .spectra/plans/ramza-calibration.jsonl
{
  "rubric": "refine", "cycle": 1, "total": 4, "min": 4,
  "dims": {"clarity":4,"completeness":4,"actionability":4,"efficiency":4,"testability":4},
  "verdict": "pass", "at": "2026-07-05T19:58:50Z"
}
EXIT_CODE_SCORE=0

Note on process: per the protocol, I did not run `ramza-gate critic` (identity
recording is the author's job) and made no edits to the plan or criteria
files — this session was read-only against the three permitted artifacts only.
```

**How the critic's verdict was addressed** (author, after receiving the above):
`ramza-gate critic --author ramza-sonnet5-maker --checker ramza-sonnet5-critic`
was recorded (§2 above), then `ramza-gate refine` entered cycle 1 (T→R). All
five prescriptions were applied to both `2026-07-05-saml-sso.md` and
`2026-07-05-saml-sso.acceptance.md`:
1. AC-009's THEN line now reads "...route the user to the existing manual
   account-signup flow instead of linking, not to any just-in-time
   auto-provisioning path"; Scope: Deferred now cross-references AC-009/AC-020.
2. Added **AC-020** (zero-match → route to manual signup) and **AC-021**
   (multi-match → reject + require admin review).
3. Story 1's executor hint now carries an explicit higher-scrutiny/mandatory
   security-review flag; Story 5's executor hint was re-tiered to **economy**
   (not "low" — RAMZA's closed executor-tier set is frontier/mid/economy per
   `templates/tiers.md`, so "economy" is the correctly named tier for
   near-zero-ambiguity reuse work).
4. Added a "Story ordering" paragraph under Stories stating Story 1 gates
   Stories 2/3, Story 4 can run in parallel, and a critical-path estimate
   (9d, not the flat 15d sum).
5. The Machine-Readable Summary's Story 2 `criteria` list now includes
   `AC-020, AC-021`; `validation_gates_count` in the frontmatter was updated
   19 → 21.

## 7. T — Structural + EARS lint (second pass, post-refine)

```
$ bash .eidolons/ramza/bin/ramza-lint --plan .spectra/plans/2026-07-05-saml-sso.md --state <state>
ok: plan passes structural lint (tier: full)
exit=0

$ bash .eidolons/ramza/bin/ramza-ears-lint .spectra/plans/2026-07-05-saml-sso.md
ok: 21 criteria pass EARS lint
exit=0

$ bash .eidolons/ramza/bin/ramza-ears-lint .spectra/plans/2026-07-05-saml-sso.acceptance.md
ok: 21 criteria pass EARS lint
exit=0
```
(The plan's embedded Acceptance Criteria section and the sibling
`.acceptance.md` file were also diffed byte-for-byte after the edits — the
only difference was one trailing blank line from the extraction method used
to compare them, i.e. the AC block content itself is identical, which is why
`ramza-freeze` below could later freeze the sibling file as the criteria of
record without drift from what's shown in the plan body.)

## 8. A — Assemble: confidence, drift declaration, freeze, emission gate

```
$ echo '{"pattern_match":70,"requirement_clarity":75,"decomposition_stability":80,"constraint_compliance":85}' \
  | bash .eidolons/ramza/bin/ramza-score --rubric confidence --state <state>
calibration log appended: .spectra/plans/ramza-calibration.jsonl
{
  "rubric": "confidence",
  "total": 77.5,
  "dims": {"pattern_match":70,"requirement_clarity":75,"decomposition_stability":80,"constraint_compliance":85},
  "verdict": "VALIDATE",
  "at": "2026-07-05T20:01:46Z"
}

$ bash .eidolons/ramza/bin/ramza-drift --state <state> \
  --declare 'src/auth/saml/* src/auth/linking/* src/session/metadata/* config/saml/* db/migrate/*identity_link* alerts/saml_error_rate.yml runbooks/saml-sso.md'
scope declared: 7 glob(s)

$ bash .eidolons/ramza/bin/ramza-freeze --state <state> --criteria .spectra/plans/2026-07-05-saml-sso.acceptance.md
frozen: 5dc6fd2723425a76a77354c06889284835a138a8af1b98ffdf88d5e754c066bc
```
Acceptance-criteria SHA-256 (frozen, tamper-evident):
`5dc6fd2723425a76a77354c06889284835a138a8af1b98ffdf88d5e754c066bc`.

Tamper-evidence re-check (`--verify`, run after freeze to confirm the frozen
hash still matches the on-disk criteria file):
```
$ bash .eidolons/ramza/bin/ramza-freeze --state <state> --criteria .spectra/plans/2026-07-05-saml-sso.acceptance.md --verify
ok: criteria match frozen hash
exit=0
```

ECL v2.0 envelope (`ECL_VERSION` = 2.0 is present in the install root, so
emission includes the sidecar per the methodology's ECL emission gate) was
written to `.spectra/plans/2026-07-05-saml-sso.envelope.json`:
`performative: PROPOSE`, `from.eidolon: ramza` (v0.2.0, matching the actually
installed version per `install.manifest.json`, not the template's example
0.1.0), `to.eidolon: apivr`, `edge_origin: roster`, `artifact.sha256` /
`integrity.value` both set to the spec payload's real SHA-256
(`45cacff272ed86efedf2d6a293b19c56199e1983c20994cf6d34e0b705a1139a`,
25140 bytes), `ise.assertion_grade: self-attested`,
`ise.receiver_authorization: {auto_route: true, auto_merge: false,
auto_deploy: false}`, and `x_ramza_acceptance_criteria.sha256` carrying the
exact `ramza-freeze` hash above.

Emission gate — the mandatory Assemble exit check:
```
$ bash .eidolons/ramza/bin/ramza-verify-emit --spec .spectra/plans/2026-07-05-saml-sso.md --envelope .spectra/plans/2026-07-05-saml-sso.envelope.json
ok: emission gate passed (2026-07-05-saml-sso.md + envelope)
exit=0
```

## 9. Final state

```
$ bash .eidolons/ramza/bin/ramza-gate status --state .spectra/plans/2026-07-05-saml-sso.state.json
{
  "plan": "2026-07-05-saml-sso",
  "tier": "full",
  "phase": "DONE",
  "next": "DONE",
  "refine_cycles": 1,
  "skips": [],
  "criteria_frozen": true
}
```
`skips: []` — every tier-mandatory phase (RS S P E C T A for full tier) was
actually entered in order, none was skipped. `refine_cycles: 1` — one
critic-driven refine pass was run and consumed (well under the cap of 3).
`criteria_frozen: true` — the EARS acceptance criteria are hash-frozen and
verified un-tampered as of this audit.

**CRYSTALIUM:** no `mcp__crystalium__*` tools were available in this
environment (checked via tool search before Assemble) — per RAMZA's graceful
degradation clause, the `ingest`/`session_end` calls were skipped silently;
this is not a failure, RAMZA is EIIS-standalone-conformant without CRYSTALIUM.

**Deliverables written (all under `.spectra/`, none under `.eidolons/`):**
- `.spectra/plans/2026-07-05-saml-sso.md` — the Markdown spec (this document's spec body)
- `.spectra/plans/2026-07-05-saml-sso.acceptance.md` — the frozen EARS acceptance-criteria sibling file
- `.spectra/plans/2026-07-05-saml-sso.state.json` — the full plan-state audit trail
- `.spectra/plans/2026-07-05-saml-sso.envelope.json` — the ECL v2.0 envelope sidecar
- `.spectra/plans/ramza-calibration.jsonl` — the appended calibration log (every `ramza-score` call)

No `plan.json` (Junction §7.5 dispatch plan) was emitted — the project has no
Junction harness present, and the planning-artifact template marks that file
as conditional ("when the consumer project runs Junction; a graceful no-op
otherwise").
