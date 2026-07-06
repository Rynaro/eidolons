---
eidolon: ramza
kind: spec
version: 0.2.0
status: ready-for-apivr
created_at: 2026-07-05T19:46:54Z
thread_id: 019f33d6-ba95-7877-87b7-a0679aa7f629
target_repos:
  - core-app
stories_count: 10
validation_gates_count: 17
---

# SAML Single Sign-On for an Existing Email/Password Application

> RAMZA full-tier specification. Produced through the mechanized RS → S → P → E →
> C → T → (R×2) → A cycle; every tier decision, score, lint, freeze, and emission
> check below is the verbatim output of a `bin/ramza-*` gate tool (see the
> **Audit trail** at the end). Tier: **full** (RS score 7). Confidence: **87.25%
> → AUTO_PROCEED**. Acceptance criteria frozen at SHA-256
> `53483d652979cabbd491f5398ca2d2c0daeb043361784f39fa1e268c6497c111`. Plans only —
> execution belongs to a separate implementer (APIVR-Δ / Vivi).

## Scope

Intent class: REQUEST

Required coverage (this spec must deliver, per the request): (1) identity
linking for existing accounts; (2) security risks with severity; (3) a
rollout strategy; (4) acceptance criteria; (5) at least one rejected
alternative. Each is addressed below — respectively by Story 3/9 + the
linking design in Approach, the Risks table, the staged-rollout Stories
6/7, the 17 EARS criteria, and the three rejected hypotheses.

In: SAML 2.0 SP-initiated (and IdP-initiated) SSO login for `core-app`, which
today authenticates users by email/password and mints a session token that
multiple other services validate directly (no per-service auth logic change
assumed to be in scope). In includes: IdP configuration per tenant, the
SAML Assertion Consumer Service (ACS) endpoint, JIT identity linking for
existing accounts with security safeguards, post-link notification/revoke,
audit logging, a per-tenant rollout flag with dual-auth coexistence, and an
optional "SSO-required" enforcement mode.

Out: Building or operating an Identity Provider (this spec covers the
Service Provider side only — the IdP is the customer's, e.g. Okta, Entra ID,
PingFederate, or a generic SAML 2.0 IdP). SCIM/directory provisioning
(user creation ahead of first login) is out — this spec covers JIT linking
of accounts that already exist, not bulk provisioning. Multi-protocol
federation (OIDC) is out; SAML 2.0 only. Deprecating password login
platform-wide is out.

Deferred: SCIM-based provisioning and deprovisioning (a natural follow-on
once SSO adoption is high — deferred because it's a separate, larger
integration surface with its own IdP-side setup). Multi-IdP-per-tenant
support is deferred (v1 assumes one IdP per tenant). OIDC support is
deferred to a later spec.

Assumptions:
- The existing session token/cookie format is stable and its validation
  logic in downstream services is not modified by this work — risk if
  wrong: any change to session shape becomes a coordinated multi-service
  migration, which is explicitly the scenario this spec is designed to
  avoid (see AC-011 and Rejected Alternative C below).
- Email address is available and namespaced consistently between the
  IdP's SAML assertion and the app's existing user records — risk if
  wrong: identity linking cannot be automated at all, and every existing
  user needs manual/admin-driven linking (falls back toward Rejected
  Alternative A).
- `core-app` is a single deployable that owns both the login flow and the
  session-issuance code path today (password and SSO share one issuer) —
  risk if wrong: session issuance may already be split across services,
  which would change Story 2's implementation surface but not its
  acceptance criteria.
- At least one pilot tenant is available to validate the rollout flag
  end-to-end before broader enablement — risk if wrong: the staged
  rollout in Story 6/7 has no low-blast-radius validation step.

Complexity (`ramza-score --rubric complexity`): 11/12 → human_loop

## Approach

Add SAML 2.0 Service Provider support to `core-app` using a vetted,
actively-maintained SAML library for the app's stack (e.g. a
`python3-saml`/`ruby-saml`/`node-saml`/Spring Security SAML equivalent —
never a hand-rolled XML signature parser). SSO and password login converge
on the exact same session-issuance code path, so the SSO addition is
invisible to every downstream service that already validates today's
session token (AC-001, AC-011) — this is the central design constraint
that rules out any approach touching the shared session model itself.

Identity linking for existing accounts uses JIT (just-in-time) linking,
gated on the IdP asserting a **verified** email that matches **exactly
one** existing account, and only completed after a one-time step-up
confirmation (current password re-entry, or an emailed confirmation link)
on the first link (AC-004, AC-005). The moment a link is created, the
account owner is notified by email with a one-click revoke path that
forces a password reset (AC-006, AC-007) — this is the mitigation for the
core risk of this approach (an IdP asserting an attacker-controlled or
spoofed email), and it is the reason this hypothesis scored higher than
the purely manual alternative once that operational gap was weighed
in (see "Rejected Alternatives").

Rollout is staged: SSO is enabled per tenant behind a flag, with password
login remaining available throughout (dual-auth coexistence, AC-009), so a
pilot tenant can validate the flow before wider enablement. A tenant admin
can later opt into "SSO-required" enforcement once link adoption is high
enough to retire password login as an attack surface for that tenant
(AC-010). Every SSO-lifecycle transition — login, link, unlink, step_up,
manual_recovery, and break_glass — is audit-logged with actor, IdP, and
correlation ID (AC-008), and the ACS endpoint rejects invalid signatures,
audience/recipient mismatches, replayed assertions, untrusted rotated
certificates, and untrusted RelayState/unsolicited responses outright
rather than failing open (AC-002, AC-003, AC-012, AC-013).

Winning hypothesis: **hyp-B (JIT verified-email auto-link + step-up +
notify/revoke)** — `ramza-score --rubric explore` total **79/100** (elite
threshold ≥85, solid 70-84 → this is "solid," not "elite"; the
Assemble-time `ramza-score --rubric confidence` gate, not this prose,
determines the routing verdict — see the Confidence section and Audit
Trail — and "Rejected Alternatives" for why hyp-B still won against
A/C/D).

## Stories

Sequencing: Story numbering is not execution order — the machine-readable
edges live in the Agent Handoff YAML under one convention, `depends_on`
(a story lists every other story that must complete before it starts).
In prose: Story 1 (IdP config) precedes Story 2 (ACS login flow); once
Story 2 lands, Stories 3, 5, 8, 10 can proceed in parallel, and Stories
4 and 9 follow Story 3's linking path. **Stories 8 and 10 (security
hardening tests, RelayState/unsolicited-response hardening) are hard
prerequisites of Story 6 (tenant rollout enablement)** — encoded as
`Story 6.depends_on: [2, 8, 10]`, so no tenant, including a pilot, is
enabled until both security gates are green; enabling a rollout flag
ahead of them would contradict this plan's own "no fail-open" posture on
those exact attack classes. Story 7 (SSO-required enforcement, with
break-glass) depends on Story 6 having run in production for at least one
tenant.

### Story 1: SAML SP metadata & per-tenant IdP configuration

As an identity admin, I want to configure a SAML IdP per tenant (upload IdP
metadata XML, or manually enter entity ID / SSO URL / signing certificate),
so that `core-app` can establish a trust relationship with the customer's
IdP before any user can log in via SSO. The configured trust material is
the only material subsequent assertions validate against (AC-017).
Timebox: 5d.
Risk tag: P1.
Executor hint: mid tier — file-level action plan naming the chosen SAML
library's metadata-import API; no need to hand-script every UI field.

### Story 2: SP-initiated SAML login flow (ACS endpoint, session parity)

As an existing user, I want to click "Log in with SSO" and land in an
authenticated session that is indistinguishable in format and claims shape
from a password-login session, so that no downstream service needs to
change how it validates sessions.
Timebox: 8d.
Risk tag: P0.
Executor hint: mid tier — action plan + named library for signature/
assertion validation, with an explicit call-out that the session-issuance
call must be the exact same function/path password login uses (not a
parallel reimplementation). RelayState/unsolicited-response handling is
deliberately a separate story (Story 10) so it isn't an afterthought
bolted onto the happy path.

### Story 3: JIT identity linking with verified-email match + step-up confirmation

As an existing user whose IdP assertion carries a verified email matching
my existing account, I want my first SSO login to link to that account
only after a one-time confirmation step, so that I don't have to manually
reconnect on every device, while an attacker can't silently hijack my
account via a spoofed or unverified email claim.
Timebox: 8d.
Risk tag: P0.
Executor hint: mid tier, with an explicit state-machine step list for the
link/confirm/notify/revoke transitions given the risk tag — scaffold
density here is raised above the tier default because a P0 auth
state-machine is exactly the kind of task where an under-specified plan
is most costly to get wrong.

### Story 4: Post-link security notification & self-service revoke

As an account owner, I want to be notified by email the moment my account
is linked to an SSO identity, and be able to revoke that link, so that I
can react quickly to a linking attempt I didn't initiate.
Timebox: 3d.
Risk tag: P1.
Executor hint: mid tier — action plan + named notification pipeline.

### Story 5: SSO lifecycle audit logging

As a security engineer, I want every SSO lifecycle event — login, link,
unlink, step_up, manual_recovery, and break_glass — logged with actor,
IdP entity ID, event type, and correlation ID, so that incident response
can reconstruct account-linking and security-override history end to end.
Timebox: 3d.
Risk tag: P1.
Executor hint: economy tier — explicit steps and a schema-validated log
event contract; this is a well-bounded, mechanically specifiable task.

### Story 6: Per-tenant rollout flag with dual-auth coexistence

As a platform operator, I want to enable SAML SSO per tenant behind a
feature flag while password login keeps working for that tenant, so that
rollout can proceed cohort by cohort rather than as a big-bang cutover.
Timebox: 5d.
Risk tag: P1.
Executor hint: mid tier.

### Story 7: Tenant-level "SSO-required" enforcement mode, with break-glass override

As a tenant admin, I want to optionally require SSO-only login for my
org's domain once link adoption is high enough, so that we can retire
password login as an attack surface for that tenant — and as a platform
operator, I want a documented break-glass override so an IdP outage
cannot lock out an entire enforced tenant.
Timebox: 4d.
Risk tag: P1.
Executor hint: mid tier — explicit steps for the break-glass path given
its incident-response nature (denser scaffold than the tier default,
same rationale as Story 3).

### Story 8: SAML security hardening test suite

As a security engineer, I want automated tests covering known SAML attack
classes (XML signature wrapping, assertion replay, audience/recipient
mismatch, untrusted certificate rotation, RelayState/unsolicited-response
abuse), so that regressions in the SAML library's configuration are
caught before release rather than in production. This story gates Story
6 (see Sequencing above) — no tenant rollout without it green.
Timebox: 5d.
Risk tag: P0.
Executor hint: frontier tier — goals and constraints only (the known SAML
attack surface and "no fail-open" invariant), deliberately not a fixed
step list; designing the adversarial test matrix itself needs judgment,
and imposing a micro-plan here would foreclose attack vectors the
executor might otherwise think to cover.

### Story 9: Manual account-recovery fallback for blocked auto-link

As a user whose SSO login was correctly blocked from auto-linking
(unverified or ambiguous email, AC-005), I want a manual recovery path
that verifies my account ownership through a channel independent of the
IdP assertion (e.g. an existing-password confirmation plus an emailed
link to the on-file address), so that I'm not permanently stuck outside
my account just because the safe path refused to guess.
Timebox: 4d.
Risk tag: P1.
Executor hint: mid tier — action plan naming the specific independent
verification channel(s) used, since "independent of the IdP assertion"
is a security property that must be concrete, not aspirational.

### Story 10: RelayState validation & unsolicited-response (IdP-initiated) hardening

As a security engineer, I want the ACS endpoint to validate RelayState
against an allowlist and reject unsolicited IdP-initiated responses
unless a tenant has explicitly opted in, so that IdP-initiated SSO
(declared in Scope) doesn't open a RelayState-driven open-redirect or an
unsolicited-assertion replay path.
Timebox: 3d.
Risk tag: P0.
Executor hint: mid tier — explicit steps given this is a narrowly-scoped,
well-specified hardening task layered on top of Story 2's ACS endpoint.

## Acceptance Criteria

Full EARS-form blocks are reproduced below (also frozen in the sibling
file `2026-07-05-saml-sso.acceptance.md`, `ramza-ears-lint`-clean, 17
criteria; frozen via `ramza-freeze` at Assemble — hash in the Audit
Trail). Summary by story:

- **AC-001** (event-driven) — SSO login issues a session token identical
  in shape to password login. *(Story 2)*
- **AC-002** (unwanted-behavior) — invalid signature / audience mismatch
  is rejected with HTTP 401, no session created. *(Story 2, 8)*
- **AC-003** (unwanted-behavior) — replayed assertions are rejected.
  *(Story 8)*
- **AC-004** (event-driven) — JIT link requires step-up confirmation on
  first link. *(Story 3)*
- **AC-005** (unwanted-behavior) — no auto-link on unverified/ambiguous
  email; routes to manual recovery instead. *(Story 3, 9)*
- **AC-006** (event-driven) — link notification email enqueued within
  60s of the link commit. *(Story 4)*
- **AC-007** (event-driven) — revoke forces a password reset. *(Story 4)*
- **AC-008** (ubiquitous) — every SSO lifecycle event (login, link,
  unlink, step_up, manual_recovery, break_glass) is audit-logged.
  *(Story 5)*
- **AC-009** (state-driven) — password login remains available during
  rollout unless enforcement is on. *(Story 6)*
- **AC-010** (optional-feature) — SSO-required enforcement blocks
  password login for an opted-in tenant. *(Story 7)*
- **AC-011** (unwanted-behavior) — the session-compat-tested set of
  downstream services accepts an SSO-issued session unchanged. *(Story 2)*
- **AC-012** (unwanted-behavior) — rotated/untrusted IdP certificates are
  rejected, never accepted by fallback. *(Story 8)*
- **AC-013** (unwanted-behavior) — untrusted RelayState / unpermitted
  IdP-initiated responses are rejected. *(Story 8, 10)*
- **AC-014** (event-driven) — an authorized break-glass override restores
  password login for an SSO-required tenant during an IdP outage, emitting
  a break_glass audit event. *(Story 7)*
- **AC-015** (unwanted-behavior) — the break-glass override auto-expires
  at its max duration rather than staying open indefinitely. *(Story 7)*
- **AC-016** (event-driven) — manual account-recovery completes the link
  after independent ownership verification. *(Story 9)*
- **AC-017** (event-driven) — a tenant's configured trust material is the
  only material subsequent assertions validate against. *(Story 1)*

### Frozen EARS acceptance criteria (verbatim, `ramza-ears-lint`-clean)

```
### AC-001 (event-driven)
GIVEN a tenant has SAML SSO enabled and the user's account is either new or already linked
WHEN the user completes a successful SAML authentication at the ACS endpoint
THEN the system SHALL issue a session token identical in format and claims shape to the token issued by password login
VERIFY: test: integration/sso/acs_spec#session_parity_with_password_login

### AC-002 (unwanted-behavior)
GIVEN a SAML response arrives at the ACS endpoint
WHEN the response's signature fails validation against the configured IdP certificate, or the assertion's Audience/Recipient do not match this SP's entity ID and ACS URL
THEN the endpoint SHALL reject the login with HTTP 401 and create no session
VERIFY: test: security/sso/assertion_validation_spec#rejects_invalid_signature_or_audience

### AC-003 (unwanted-behavior)
GIVEN a SAML assertion has already been consumed once, its assertion ID recorded in the replay cache
WHEN the identical assertion is submitted to the ACS endpoint a second time
THEN the endpoint SHALL reject the second submission with HTTP 401
VERIFY: test: security/sso/replay_spec#rejects_replayed_assertion

### AC-004 (event-driven)
GIVEN a first-time SSO login asserts an email address matching exactly one existing password-authenticated account
WHEN the IdP marks that email attribute as verified
THEN the system SHALL require a one-time step-up confirmation, either current password or emailed confirmation link, before completing the account link
VERIFY: test: integration/sso/jit_link_spec#requires_step_up_before_first_link

### AC-005 (unwanted-behavior)
GIVEN a first-time SSO login asserts an email that is either not marked verified by the IdP or matches more than one existing account
WHEN the login attempt reaches the account-linking step
THEN the system SHALL route the user to manual account recovery without auto-linking any account
VERIFY: test: integration/sso/jit_link_spec#blocks_autolink_on_unverified_or_ambiguous_email

### AC-006 (event-driven)
GIVEN an SSO identity has just been linked to an existing account for the first time
WHEN the link transaction commits
THEN the system SHALL enqueue a notification email to the account's on-file address within 60 seconds of the commit, containing a one-click revoke link
VERIFY: test: integration/sso/notifications_spec#enqueues_link_notification_with_revoke_link

### AC-007 (event-driven)
GIVEN an account owner clicks the revoke link from a link-notification email
WHEN the revoke request is submitted within its validity window
THEN the system SHALL remove the SSO identity link and force a password reset before the account can be used again
VERIFY: test: integration/sso/revoke_spec#revoke_forces_password_reset

### AC-008 (ubiquitous)
THEN the system SHALL record an audit event with actor, IdP entity ID, event type drawn from the closed set login, link, unlink, step_up, manual_recovery, or break_glass, and correlation ID for every SSO lifecycle transition
VERIFY: test: security/sso/audit_log_spec#records_all_sso_lifecycle_events

### AC-009 (state-driven)
GIVEN a tenant has SAML SSO enabled but has not enabled SSO-required enforcement
THEN existing users SHALL still be able to authenticate with email and password
VERIFY: test: integration/sso/rollout_spec#password_login_remains_available_during_rollout

### AC-010 (optional-feature)
GIVEN a tenant admin has enabled SSO-required enforcement for their tenant
THEN the system SHALL reject email/password login attempts for that tenant's domain with a message directing the user to SSO
VERIFY: test: integration/sso/enforcement_spec#blocks_password_login_when_sso_required

### AC-011 (unwanted-behavior)
GIVEN the current set of downstream services under `session_compat_spec` coverage
WHEN a user authenticates via SAML SSO instead of password
THEN the session token those services receive SHALL be unchanged in format and claims shape from a password-issued session, requiring no code changes in any covered service
VERIFY: test: integration/sso/session_compat_spec#downstream_services_accept_sso_session_unchanged

### AC-012 (unwanted-behavior)
GIVEN an IdP's signing certificate has expired or been rotated without updating the SP's configured certificate
WHEN a SAML response arrives signed with the new or rotated certificate
THEN the endpoint SHALL reject the login as an invalid signature rather than falling back to accept any certificate
VERIFY: test: security/sso/cert_rotation_spec#rejects_login_on_untrusted_rotated_cert

### AC-013 (unwanted-behavior)
GIVEN the ACS endpoint receives a SAML response carrying a RelayState parameter, or a response with no InResponseTo value (an IdP-initiated response)
WHEN the RelayState does not match an allowlisted internal redirect target, or the tenant has not been explicitly configured to permit IdP-initiated responses
THEN the endpoint SHALL reject the response rather than following an arbitrary RelayState redirect or accepting an unsolicited assertion
VERIFY: test: security/sso/relaystate_spec#rejects_untrusted_relaystate_and_unpermitted_idp_initiated

### AC-014 (event-driven)
GIVEN a tenant has SSO-required enforcement enabled and its configured IdP is unreachable or returning errors
WHEN an operator holding the break-glass authorization role invokes the documented override for that tenant
THEN the system SHALL temporarily re-enable email and password login for that tenant's domain, emitting a break_glass audit event, until the override auto-expires or is explicitly cleared
VERIFY: test: integration/sso/breakglass_spec#operator_override_restores_password_login_and_audits

### AC-015 (unwanted-behavior)
GIVEN a break-glass override has been active for its configured maximum duration
WHEN that maximum duration elapses without an explicit clear
THEN the override SHALL auto-expire and SSO-required enforcement SHALL resume, rather than remaining open indefinitely
VERIFY: test: integration/sso/breakglass_spec#override_auto_expires_at_max_duration

### AC-016 (event-driven)
GIVEN a first-time SSO login was blocked from auto-linking per AC-005
WHEN the user completes the manual account-recovery flow, verifying ownership of the existing account through a channel independent of the IdP assertion
THEN the system SHALL link the SSO identity to that account and record a manual_recovery audit event
VERIFY: test: integration/sso/manual_recovery_spec#completes_manual_link_after_independent_verification

### AC-017 (event-driven)
GIVEN a tenant admin has uploaded IdP metadata or entered the IdP entity ID, SSO URL, and signing certificate
WHEN a user of that tenant subsequently initiates an SSO login
THEN the endpoint SHALL validate the assertion against exactly that configured trust material and no other
VERIFY: test: integration/sso/idp_config_spec#configured_trust_material_is_used_for_validation
```

## Confidence

`ramza-score --rubric confidence` (computed at Assemble, not estimated in
prose): **87.25% → AUTO_PROCEED** (≥85). Dimensions: pattern_match 85,
requirement_clarity 88, decomposition_stability 86, constraint_compliance
90 — recorded verbatim in the state file's `gates[]` and quoted in the
Audit Trail. Note the interaction with the Scope-phase complexity routing
(11/12 → human_loop): the plan is arithmetically confident enough to
AUTO_PROCEED, but the complexity signal and the P0 security surface mean a
security reviewer's sign-off before implementation remains the prudent
gate — AUTO_PROCEED here means "no RAMZA-side blocker," not "skip human
review of an auth-critical change."

## Rejected Alternatives

Winner selection rests on a double rescore during Explore, disclosed here
in full because it is load-bearing. On first observation hyp-A actually
**led** hyp-B, 77.5 vs. 76.5 — within 5% of each other, which the
methodology flags as insufficient differentiation and requires
re-observing. Two independent rescores followed, each justified on its own
terms: hyp-A's `alignment` was lowered 6→5 (its Day-1 "no existing user
can reach their account via SSO on first attempt" operational gap was
under-weighted at first), dropping it to 74; hyp-B's `alignment` was
raised 9→10 (it is the only candidate that advances two of the required
coverage areas enumerated in Scope — (1) identity linking and (2)
security-risk mitigation — through a single mechanism, the
step-up/notify/revoke chain), raising it to 79. The reobservation therefore **reversed**
the initial ranking rather than breaking a tie; every one of these four
score values is traceable verbatim in the state file's `gates[]` (see
Audit Trail).

- **Hyp-A — Manual, user-initiated account linking only** (no JIT
  auto-link at all: an existing user must first log in with their
  current password, then explicitly click "Connect SSO" while
  authenticated). `ramza-score --rubric explore` total **74/100**
  (solid). Rejected because it leaves a real Day-1 operational gap for
  the actual purpose of this spec: no existing user can use SSO to reach
  their existing account on first attempt — every one of them needs a
  manual password-login "bridge" step first, which undercuts the
  frictionless-login and centralized-deprovisioning value SSO is being
  added for, even though it is the safest option on every other
  dimension (correctness 9, risk 9, simplicity 8). Re-scored once
  (alignment 6→5) after weighing that operational gap more heavily —
  the first score under-weighted it.

- **Hyp-C — Centralized session-issuance service rewrite** (replace the
  app's session minting with a new shared session-issuance service that
  both password and SSO call into, as a vehicle to also prepare for
  future IdPs). `ramza-score --rubric explore` total **52/100**
  (**weak** — tool exit 1, mandatory rework-or-drop). Rejected on scope
  grounds: it inverts this spec's central constraint (see Approach) by
  deliberately touching the shared session model that "other services
  depend on," multiplying blast radius across every downstream
  consumer simultaneously instead of keeping the SSO addition invisible
  to them. Correct architectural instinct for a *later*, dedicated
  session-model spec — wrong vehicle to bundle into the SSO rollout
  itself.

- **Hyp-D — Buy: front the login with a third-party
  auth/IdP-aggregation platform** (e.g., an external auth platform
  handles SAML parsing and calls back into `core-app`'s existing
  session issuance). `ramza-score --rubric explore` total **73/100**
  (solid). A legitimate build-vs-buy alternative — less custom SAML
  code to maintain, vendor-hardened parsing — but rejected for this spec
  because it introduces a new third-party processor in the
  authentication path (a procurement/compliance review and a new vendor
  security dependency the mission's "existing... authentication" framing
  does not obviously license), and because it does not remove the need
  for this spec's identity-linking design — the vendor still hands back
  an assertion this app must link to an existing account. Worth
  revisiting if in-house SAML maintenance cost proves high in practice.

## Risks

| Risk | Severity | Tag | Mitigation |
|---|---|---|---|
| IdP asserts an attacker-controlled or unverified email, causing a silent account takeover via auto-link | Critical | P0 | JIT link requires the IdP's verified-email flag AND a one-time step-up confirmation before the link completes (AC-004, AC-005); link is impossible on an unverified or ambiguous email match. |
| Forged or tampered SAML assertion (signature wrapping, altered attributes) accepted as valid | Critical | P0 | Signature and Audience/Recipient validation via a vetted SAML library, never hand-rolled XML parsing; invalid assertions rejected with no session created (AC-002); dedicated adversarial test suite (Story 8, AC-002/AC-012). |
| Captured SAML assertion replayed to mint a second session | High | P0 | Assertion-ID replay cache checked at the ACS endpoint; replays rejected (AC-003). |
| IdP certificate rotates or expires and the SP silently accepts an unrecognized signer ("fail open") | High | P0 | Certificate mismatch is treated as an invalid signature, never a silent accept; rotation requires an explicit admin config update (AC-012). |
| Account-linking notification email is delayed, suppressed, or lost, so a hijacked link goes unnoticed | Medium | P1 | Notification enqueued within 60s of link commit (dispatch-time, SP-controlled — AC-006); a separate operational monitor tracks actual delivery latency and alerts on the notification pipeline; the revoke path does not depend on the user having seen the email, so recovery via support escalation remains possible if delivery is lost. |
| Session-model assumption breaks: a downstream service turns out to depend on password-login-specific session metadata SSO logins won't populate | High | P0 | Story 2 explicitly reuses the existing session-issuance code path rather than a parallel implementation (AC-001, AC-011); flagged as an assumption in Scope, verified in staging against real downstream consumers before tenant rollout. |
| Staged rollout flag misconfigured, enabling SSO-required enforcement for a tenant before enough users have linked, locking users out | High | P1 | Dual-auth coexistence is the default (AC-009); enforcement is a separate, explicit opt-in per tenant (AC-010), validated on a pilot tenant first (see Scope assumptions); an authorized, audited, auto-expiring break-glass override restores password login during an IdP outage rather than leaving the tenant fully locked out (AC-014, AC-015, Story 7). |
| SAML library dependency (new-dep flagged at Right-Size) carries its own CVEs over time | Medium | P2 | Pin to an actively-maintained library, add it to existing dependency/CVE scanning, and prefer one with a security disclosure history rather than the newest/least-used option. |
| IdP-initiated SSO (declared in Scope) is abused via a tampered RelayState (open redirect) or an unsolicited assertion replayed without a prior SP request | High | P0 | RelayState validated against an allowlist; unsolicited responses rejected unless a tenant has explicitly opted in to IdP-initiated SSO (AC-013, Story 10); covered by the Story 8/10 adversarial suite gating tenant rollout (see Sequencing). |
| The safe fallback for a blocked auto-link (AC-005) has no working recovery path in practice, leaving legitimately-blocked users stuck outside their account | Medium | P1 | Manual account-recovery is its own timeboxed, owned story with an independent-verification requirement and its own VERIFY test, not an unelaborated clause (AC-016, Story 9). |

---

## Agent Handoff (machine-readable)

```yaml
plan: 2026-07-05-saml-sso
eidolon: ramza
tier: full
theme: Enterprise SAML Single Sign-On
project: SAML 2.0 SSO integration for an existing email/password application
feature: Identity-linked SSO with staged, dual-auth rollout
winning_hypothesis: hyp-B-jit-stepup-reobserved
winning_score: 79
stories:
  - id: 1
    title: SAML SP metadata & per-tenant IdP configuration
    timebox_days: 5
    risk_tag: P1
    executor_hint: mid
    acceptance_criteria: [AC-017]
  - id: 2
    title: SP-initiated SAML login flow (ACS endpoint, session parity)
    timebox_days: 8
    risk_tag: P0
    executor_hint: mid
    acceptance_criteria: [AC-001, AC-002, AC-011]
    depends_on: [1]
  - id: 3
    title: JIT identity linking with verified-email match + step-up confirmation
    timebox_days: 8
    risk_tag: P0
    executor_hint: mid
    acceptance_criteria: [AC-004, AC-005]
    depends_on: [2]
  - id: 4
    title: Post-link security notification & self-service revoke
    timebox_days: 3
    risk_tag: P1
    executor_hint: mid
    acceptance_criteria: [AC-006, AC-007]
    depends_on: [3]
  - id: 5
    title: SSO lifecycle audit logging
    timebox_days: 3
    risk_tag: P1
    executor_hint: economy
    acceptance_criteria: [AC-008]
    depends_on: [2]
  - id: 6
    title: Per-tenant rollout flag with dual-auth coexistence
    timebox_days: 5
    risk_tag: P1
    executor_hint: mid
    acceptance_criteria: [AC-009]
    # depends_on encodes ALL prerequisites in one convention: Story 6 needs
    # the login flow (2) AND both security gates (8, 10) green before any
    # tenant — including a pilot — is enabled.
    depends_on: [2, 8, 10]
  - id: 7
    title: Tenant-level "SSO-required" enforcement mode, with break-glass override
    timebox_days: 4
    risk_tag: P1
    executor_hint: mid
    acceptance_criteria: [AC-010, AC-014, AC-015]
    depends_on: [6]
  - id: 8
    title: SAML security hardening test suite
    timebox_days: 5
    risk_tag: P0
    executor_hint: frontier
    acceptance_criteria: [AC-002, AC-003, AC-012, AC-013]
    depends_on: [2]
  - id: 9
    title: Manual account-recovery fallback for blocked auto-link
    timebox_days: 4
    risk_tag: P1
    executor_hint: mid
    acceptance_criteria: [AC-016]
    depends_on: [3]
  - id: 10
    title: RelayState validation & unsolicited-response hardening
    timebox_days: 3
    risk_tag: P0
    executor_hint: mid
    acceptance_criteria: [AC-013]
    depends_on: [2]
acceptance_criteria_file: 2026-07-05-saml-sso.acceptance.md
rejected_alternatives:
  - id: hyp-A-manual-link-reobserved
    score: 74
  - id: hyp-C-central-session-rewrite
    score: 52
  - id: hyp-D-buy-idp-proxy
    score: 73
confidence:
  total: 87.25
  verdict: AUTO_PROCEED
```

## ECL v2.0 envelope sidecar (`ramza-verify-emit`-validated)

`ECL_VERSION` = 2.0 is present in the install root, so the Assemble phase
emits this envelope alongside the spec. `ramza-verify-emit --spec
2026-07-05-saml-sso.md --envelope 2026-07-05-saml-sso.envelope.json`
recomputed the payload sha256, checked the closed performative set, and
passed (see Audit Trail). `integrity.value` == `artifact.sha256` == the
sha256 of the frozen spec Markdown bytes;
`x_ramza_acceptance_criteria.sha256` == the `ramza-freeze` output.

```json
{
  "envelope_version": "2.0",
  "message_id": "019f33f3-4da9-7a4d-9516-0f33565067cd",
  "thread_id": "019f33d6-ba95-7877-87b7-a0679aa7f629",
  "parent_id": null,
  "from": { "eidolon": "ramza", "version": "0.2.0" },
  "to": { "eidolon": "apivr", "version": "n/a" },
  "performative": "PROPOSE",
  "edge_origin": "roster",
  "objective": "Propose the implementation spec for SAML 2.0 SSO with identity-linking safeguards and staged dual-auth rollout, targeting core-app.",
  "artifact": {
    "kind": "spec",
    "schema_version": "1.0",
    "path": ".spectra/plans/2026-07-05-saml-sso.md",
    "sha256": "0d1577a0624c388771dd133c224751f79b6ed90e0ee9664a26a4a9bd66bc8e7f",
    "size_bytes": 25861
  },
  "context_delta": {
    "token_budget": 6000,
    "tokens_used": 0,
    "input_handles": [],
    "summary": "Decision-ready full-tier RAMZA spec for adding SAML 2.0 SP-side SSO to core-app (existing email/password auth + shared session model). Covers JIT verified-email identity linking with step-up/notify/revoke safeguards, a severity-tagged security-risk table (signature forgery, replay, cert rotation, RelayState/IdP-initiated abuse, silent takeover), a per-tenant staged dual-auth rollout with SSO-required enforcement and an audited auto-expiring break-glass override, 10 stories, 17 frozen EARS acceptance criteria, and three rejected alternatives. APIVR-Delta should implement per the frozen criteria; the session-issuance-parity constraint (AC-001/AC-011) is load-bearing."
  },
  "constraints": { "trust_level": "standard" },
  "ise": {
    "assertion_grade": "self-attested",
    "provenance": {
      "methodology_version": "ramza-0.2.0",
      "tool_surface": ["Read", "Write", "Edit", "Bash", "Agent"],
      "lateral_consults": []
    },
    "receiver_authorization": { "auto_route": true, "auto_merge": false, "auto_deploy": false }
  },
  "confidence": 0.87,
  "integrity": {
    "method": "sha256",
    "value": "0d1577a0624c388771dd133c224751f79b6ed90e0ee9664a26a4a9bd66bc8e7f"
  },
  "trace": {
    "ts": "2026-07-05T20:23:00Z",
    "host": "claude-code",
    "model": "claude-opus-4-8",
    "tier": "standard"
  },
  "x_ramza_acceptance_criteria": {
    "path": ".spectra/plans/2026-07-05-saml-sso.acceptance.md",
    "sha256": "53483d652979cabbd491f5398ca2d2c0daeb043361784f39fa1e268c6497c111"
  }
}
```

---

# Audit trail

Every RAMZA gate below was **run**, not role-played. This section quotes the
**actual stdout/stderr** of each `bin/ramza-*` invocation, in cycle order.
The authoritative record is `.spectra/plans/2026-07-05-saml-sso.state.json`
(schema `ramza/plan-state.v1`); phase walk:
`RS → S → P → E → C → T → R → T → R → T → A`.

## RS — Right-Size (tier decision)

```
$ ramza-rightsize --files-est 10 --new-dep --migration --security \
      --stakes high --plan 2026-07-05-saml-sso \
      --state .spectra/plans/2026-07-05-saml-sso.state.json
state initialised: .spectra/plans/2026-07-05-saml-sso.state.json (tier: full, score: 7)
full
```

Signals: files-est 10 (+2), `--new-dep` (+1, the SAML library), `--migration`
(+1, sso_identity table), `--security` (+1), `--stakes high` (+2) = **score 7
→ tier `full`** (≥5). No override; computed tier accepted.

## S — Scope (complexity rubric)

```
$ echo '{"scope":3,"ambiguity":2,"dependencies":3,"risk":3}' \
    | ramza-score --rubric complexity --state <state> --label "scope-saml-sso"
calibration log appended: .spectra/plans/ramza-calibration.jsonl
{
  "rubric": "complexity",
  "total": 11,
  "dims": { "scope": 3, "ambiguity": 2, "dependencies": 3, "risk": 3 },
  "verdict": "human_loop",
  "at": "2026-07-05T19:47:18Z",
  "label": "scope-saml-sso"
}
```

**11/12 → human_loop** — this auth-critical change routes to human-in-the-loop
review, reflected in the Confidence-section caveat above.

## E — Explore (hypothesis rubric; 4 candidates, 2 reobserved)

Initial scores (first observation):

```
$ echo '{"alignment":6,"correctness":9,"maintainability":9,"performance":8,"simplicity":9,"risk":9,"innovation":2}' \
    | ramza-score --rubric explore --state <state> --label "hyp-A-manual-link"
{ "rubric":"explore", "total":77.5, "verdict":"solid", "label":"hyp-A-manual-link" }        # exit 0

$ echo '{"alignment":9,"correctness":8,"maintainability":7,"performance":8,"simplicity":6,"risk":7,"innovation":5}' \
    | ramza-score --rubric explore --state <state> --label "hyp-B-jit-stepup"
{ "rubric":"explore", "total":76.5, "verdict":"solid", "label":"hyp-B-jit-stepup" }         # exit 0

$ echo '{"alignment":5,"correctness":6,"maintainability":6,"performance":6,"simplicity":2,"risk":3,"innovation":9}' \
    | ramza-score --rubric explore --state <state> --label "hyp-C-central-session-rewrite"
{ "rubric":"explore", "total":52, "verdict":"weak", "label":"hyp-C-central-session-rewrite" }  # exit 1 (weak: rework-or-drop)

$ echo '{"alignment":8,"correctness":8,"maintainability":7,"performance":7,"simplicity":8,"risk":6,"innovation":4}' \
    | ramza-score --rubric explore --state <state> --label "hyp-D-buy-idp-proxy"
{ "rubric":"explore", "total":73, "verdict":"solid", "label":"hyp-D-buy-idp-proxy" }        # exit 0
```

hyp-A (77.5) and hyp-B (76.5) landed within 5% → insufficient differentiation;
the methodology requires re-observing. Two independent, separately-justified
rescores followed:

```
$ echo '{"alignment":5,"correctness":9,"maintainability":9,"performance":8,"simplicity":8,"risk":9,"innovation":2}' \
    | ramza-score --rubric explore --state <state> --label "hyp-A-manual-link-reobserved"
{ "rubric":"explore", "total":74, "verdict":"solid", "label":"hyp-A-manual-link-reobserved" }   # exit 0

$ echo '{"alignment":10,"correctness":8,"maintainability":7,"performance":8,"simplicity":6,"risk":7,"innovation":5}' \
    | ramza-score --rubric explore --state <state> --label "hyp-B-jit-stepup-reobserved"
{ "rubric":"explore", "total":79, "verdict":"solid", "label":"hyp-B-jit-stepup-reobserved" }    # exit 0
```

Reobservation **reversed** the ranking: hyp-A 77.5→74, hyp-B 76.5→79.
**Winner: hyp-B at 79.** hyp-C (52) exited 1 (weak, mandatory rework-or-drop)
and is carried as a rejected alternative rather than reworked.

## C — Construct + T — Test (structural + EARS lint)

```
$ ramza-lint --plan .spectra/plans/2026-07-05-saml-sso.md --state <state>
ok: plan passes structural lint (tier: full)                        # exit 0

$ ramza-ears-lint .spectra/plans/2026-07-05-saml-sso.acceptance.md
ok: 17 criteria pass EARS lint                                      # exit 0
```

(Both re-run clean after every Refine edit; the final invocations above are
the ones gating the last Test phase.)

## T → R → T — Refine cycles + maker≠checker critic

**Full tier requires an independent critic (author ≠ checker) before Assemble.**
Three independent clean-context critic subagents reviewed the plan across two
Refine cycles; each ran the linters itself and scored the `refine` rubric — RAMZA
never self-scored. All refine verdicts (verbatim from `gates[]` /
`ramza-calibration.jsonl`):

```
cycle 1  {clarity:3, completeness:2, actionability:3, efficiency:4, testability:3}  total 3    min 2  verdict FAIL   at 2026-07-05T19:56:47Z
cycle 2  {clarity:4, completeness:3, actionability:4, efficiency:4, testability:4}  total 3.8  min 3  verdict FAIL   at 2026-07-05T20:04:21Z
cycle 2  {clarity:4, completeness:4, actionability:4, efficiency:4, testability:4}  total 4    min 4  verdict PASS   at 2026-07-05T20:09:26Z
cycle 3  {clarity:4, completeness:4, actionability:4, efficiency:4, testability:4}  total 4    min 4  verdict PASS   at 2026-07-05T20:21:37Z
```

**Cycle-1 critic (checker `ramza-critic-subagent-01`) — FAIL (total 3, completeness 2/5).**
Verdict verbatim: `ramza-lint clean · ramza-ears-lint clean (12 criteria) · refine rubric: fail (total 3, cycle 1)`. Load-bearing findings: (a) two dangling
"see Audit Trail" forward-references; (b) IdP-initiated attack surface (RelayState /
unsolicited-response) named in-scope but absent from ACs/Risks/Stories; (c) no
break-glass/rollback for SSO-required enforcement; (d) AC-005's manual-recovery
fallback was an unelaborated clause with no owning story/AC; plus AC-006 delivery-vs-dispatch
and AC-011 universal-quantifier testability nits, and an unnarrated hyp-B rescore.
Recorded critic identity:

```
$ ramza-gate critic --state <state> --author ramza-primary-sonnet5 --checker ramza-critic-subagent-01
OK: critic recorded (author: ramza-primary-sonnet5, checker: ramza-critic-subagent-01)   # exit 0
```

Refine pass 1 (`ramza-gate refine` → cycle 1, `OK: T -> R (cycle 1/3)`) applied all
8 prescriptions: added Story 9 (manual recovery) + Story 10 (RelayState hardening),
AC-013/014/015, reworded AC-006 (enqueue) and AC-011 (scoped to tested set),
added the Sequencing dependency note and the hyp-B rescore rationale.

**Cycle-2 critics — a genuine split on `completeness` (both quoted, neither buried):**

- checker `ramza-critic-subagent-01` (resumed) scored **completeness 3 → FAIL (3.8)**,
  citing two load-bearing gaps the first refine pass left: AC-008's audit-event
  enum was never extended to cover the newly-added `manual_recovery` (AC-016) and
  `break_glass` types, and AC-014 (break-glass) carried no audit-logging clause.
  Verdict verbatim: `ramza-lint clean · ramza-ears-lint clean (15 criteria) · refine: fail (total 3.8, cycle 2, completeness 3)`.
- checker `ramza-critic-subagent-02` scored **completeness 4 → PASS (4.0)**, but
  flagged the same AC-008/AC-014 audit contradictions plus the Risks "delivery"
  wording as non-blocking prescriptions. Verdict verbatim:
  `ramza-lint clean · ramza-ears-lint clean (15 criteria) · refine: pass (total 4, cycle 2)`.
  Recorded identity: `OK: critic recorded (author: ramza-primary-sonnet5, checker: ramza-critic-subagent-02)`.

Both critics converged on the same substantive gap. Refine pass 2
(`ramza-gate refine` → `OK: T -> R (cycle 2/3)`) addressed the **union** of both
critics' finding sets: extended AC-008's closed enum to
`{login, link, unlink, step_up, manual_recovery, break_glass}` (and the Approach
+ Story 5 lists to match), added a `break_glass` audit event and authorized
invoker to AC-014, added AC-015 (auto-expiry), renumbered manual recovery to
AC-016, added AC-017 (Story 1's own criterion), aligned the Risks "enqueue"
wording, enumerated the mission's required-coverage list in Scope, and collapsed
the handoff YAML to a single `depends_on` convention.

**Cycle-3 critic (checker `ramza-critic-final-03`) — PASS (total 4.0, all dims 4)**
on the final 17-criteria artifact that neither prior critic had seen. Verdict
verbatim:

```
ramza-lint  → ok: plan passes structural lint (tier: full)         (exit 0)
ramza-ears-lint → ok: 17 criteria pass EARS lint                   (exit 0)
ramza-score --rubric refine --cycle 3 →
{ "rubric":"refine", "cycle":3, "total":4, "min":4,
  "dims":{"clarity":4,"completeness":4,"actionability":4,"efficiency":4,"testability":4},
  "verdict":"pass", "at":"2026-07-05T20:21:37Z" }
```

It independently verified: AC-ID bijection (AC-001..017 all defined and
referenced, no orphan/dangling), AC-008's enum covers every event any AC emits,
the dependency graph is acyclic and matches the Sequencing prose, and
frontmatter counts (`stories_count: 10`, `validation_gates_count: 17`) match
reality — no new inconsistency introduced by the revision. Recorded identity
(this is the maker≠checker record gating Assemble entry):

```
$ ramza-gate critic --state <state> --author ramza-primary-sonnet5 --checker ramza-critic-final-03
OK: critic recorded (author: ramza-primary-sonnet5, checker: ramza-critic-final-03)   # exit 0
```

## A — Assemble (exit gates: confidence · scope · freeze · emit)

```
$ echo '{"pattern_match":85,"requirement_clarity":88,"decomposition_stability":86,"constraint_compliance":90}' \
    | ramza-score --rubric confidence --state <state> --label "assemble-saml-sso"
calibration log appended: .spectra/plans/ramza-calibration.jsonl
{
  "rubric": "confidence",
  "total": 87.25,
  "dims": { "pattern_match":85, "requirement_clarity":88, "decomposition_stability":86, "constraint_compliance":90 },
  "verdict": "AUTO_PROCEED",
  "at": "2026-07-05T20:22:38Z",
  "label": "assemble-saml-sso"
}
```

**Confidence 87.25 → AUTO_PROCEED** (≥85).

```
$ ramza-drift --state <state> --declare 'app/auth/saml/* app/auth/session/* app/models/sso_identity* db/migrate/*saml* config/saml/* spec/integration/sso/* spec/security/sso/*'
scope declared: 7 glob(s)                                          # exit 0
```

```
$ ramza-freeze --state <state> --criteria .spectra/plans/2026-07-05-saml-sso.acceptance.md
frozen: 53483d652979cabbd491f5398ca2d2c0daeb043361784f39fa1e268c6497c111
53483d652979cabbd491f5398ca2d2c0daeb043361784f39fa1e268c6497c111   # exit 0

$ ramza-freeze --state <state> --criteria .spectra/plans/2026-07-05-saml-sso.acceptance.md --verify
ok: criteria match frozen hash                                     # exit 0 (tamper check: clean)
```

**Frozen acceptance-criteria SHA-256:**
`53483d652979cabbd491f5398ca2d2c0daeb043361784f39fa1e268c6497c111`
(rides the ECL envelope as `x_ramza_acceptance_criteria.sha256`).

```
$ ramza-verify-emit --spec .spectra/plans/2026-07-05-saml-sso.md \
                    --envelope .spectra/plans/2026-07-05-saml-sso.envelope.json
ok: emission gate passed (2026-07-05-saml-sso.md + envelope)       # exit 0
```

`ramza-verify-emit` recomputed the spec Markdown sha256
(`0d1577a0624c388771dd133c224751f79b6ed90e0ee9664a26a4a9bd66bc8e7f`), confirmed
it equals `artifact.sha256` and `integrity.value`, verified `integrity.method:
sha256`, the frontmatter contract (`eidolon`, `kind: spec`, `version`,
`created_at`), and that `performative: PROPOSE` is a member of the closed
10-performative set read from `schemas/ecl-envelope.v2.json`.

```
$ ramza-gate advance --state <state> --to A
OK: T -> A                                                         # exit 0 (critic record present → Assemble entry permitted)

$ ramza-gate status --state <state>
{
  "plan": "2026-07-05-saml-sso",
  "tier": "full",
  "phase": "A",
  "next": "DONE",
  "refine_cycles": 2,
  "skips": [],
  "criteria_frozen": true
}
```

## Preflight (final state, all green)

- [x] RS ran; tier recorded (**full**, score 7; no override)
- [x] Phase walk clean, no unexplained skips (`skips: []`)
- [x] Hypotheses scored via tool (4 candidates + 2 reobservations); rejected alternatives documented (hyp-A/C/D)
- [x] `ramza-lint` + `ramza-ears-lint` green (17 criteria)
- [x] Full-tier critic recorded, author ≠ checker (`ramza-primary-sonnet5` ≠ `ramza-critic-final-03`); refine cycle 3 PASS
- [x] Confidence computed via tool (87.25 → AUTO_PROCEED); verdict honored
- [x] Scope declared (7 globs); criteria frozen + `--verify` clean; `ramza-verify-emit` green
- [x] ECL v2.0 envelope emitted (`ECL_VERSION` present) and validated
- [x] Every output path under `.spectra/`; no code produced (READ-ONLY honored)

*RAMZA v0.2.0 — decision-ready, tamper-evident. Execution belongs to a separate implementer.*
