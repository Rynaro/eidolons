---
eidolon: spectra
version: "4.11.0"
kind: spec
status: ready-for-apivr
created_at: "2026-07-05T19:27:14Z"
thread_id: "019f33bf-ea11-71ec-984d-fb982b6b0201"
target_repos: ["app/monolith", "app/session-service"]
stories_count: 15
validation_gates_count: 6
confidence: 0.83
---

# SAML Single Sign-On Integration — Decision-Ready Specification

**Spec ID:** SPEC-2026-07-05-saml-sso
**Produced by:** SPECTRA v4.11.0 (Strategic Specification through Deliberate Reasoning)
**Status:** VALIDATE — deliver with flags, human review required before execution
**Confidence:** 83% (see §9)
**Complexity:** 12/12 — extended thinking applied, human-in-the-loop recommended (see §3)

---

## Executive Summary

This specification covers adding SAML 2.0 single sign-on (SSO) to an application
that currently authenticates users with email/password and maintains a session
model that other internal services depend on. It selects an architecture that
**adds a federated front door without touching the existing session model** —
every downstream service that trusts today's session continues to work
unmodified. It defines how a SAML identity gets linked to an existing
email/password account without opening an account-takeover path, enumerates
the security risks specific to SAML (with severity ratings and mitigations),
lays out a phased rollout with kill-switches and rollback triggers, and
documents one fully-reasoned rejected alternative (a fourth is documented as
well). Because this is a security-critical, cross-service change with several
real business/legal unknowns (which identity provider, whether just-in-time
account provisioning is legally acceptable, data-residency of IdP metadata),
the spec is delivered at **VALIDATE** confidence — decision-ready, but flagged
for a named set of human sign-offs before implementation starts (see §9,
"Open Flags for Human Review").

**Reader's map to the four things this document must answer:**

| Mission requirement | Section |
|---|---|
| Identity linking for existing accounts | §6.3 (Feature F-3) |
| Security risks with severity | §7 — Security Risk Register |
| Rollout strategy | §8 — Rollout Strategy |
| Acceptance criteria | §6 (per-story GIVEN/WHEN/THEN) and §6.6 (release-level) |
| Rejected alternative(s) | §5.4 — Rejected Alternatives |

---

## 1. DISCOVER — skipped (justified)

**Trigger check:** DISCOVER activates only when the *goal itself* is latent
(`IDEA`/`STRATEGIC` intent). The mission here is a `CHANGE`-type request with a
clear, already-stated goal ("add SAML SSO to an app with existing
email/password auth and a session model other services depend on") — the
ambiguity is in the *details*, not the objective. Per the DISCOVER/CLARIFY
boundary rule in `SPEC.md`, this routes straight to CLARIFY. Skip is justified
and logged per the Preflight Checklist.

---

## 2. CLARIFY

**Intent parse:**

- **WHO:** End users of an existing application who currently authenticate with
  email/password; specifically, users belonging to enterprise customer
  organizations that require federated identity via their own IdP (Okta, Azure
  AD / Entra ID, OneLogin, Ping, Google Workspace, etc.).
- **WHAT:** Add a SAML 2.0 Service Provider (SP) integration that authenticates
  users against a customer-controlled Identity Provider (IdP), and bridges a
  successful SAML assertion into the application's existing session model with
  no changes required in the services that consume that session.
- **WHY:** Enterprise buyers commonly gate SaaS purchases on SSO support
  (procurement/IT security requirement); without it, deals stall or churn risk
  rises for security-conscious accounts. This is a revenue-unlocking,
  trust-building capability, not a cosmetic feature.
- **CONSTRAINTS (stated in the mission):** (1) an existing email/password
  auth system must keep working, (2) a session model already exists and other
  services depend on it — that dependency is a hard backward-compatibility
  constraint, not a suggestion, (3) the spec must address identity linking,
  security risk with severity, rollout, acceptance criteria, and at least one
  rejected alternative.

**Gaps identified (per the mission's own instruction — handled as assumptions
in §3.4 rather than clarifying questions, since none are permitted here):**
which specific IdP(s) must be supported first, whether the application is
single-tenant or multi-tenant B2B SaaS, whether new users may be
auto-provisioned (JIT) or must be pre-existing, whether SAML Single Logout
(SLO) is required, and what the session model's concrete transport is (signed
token vs. server-side session record + opaque cookie).

**Structural context gathering:** This is a fresh SPECTRA installation with no
consumer-project source tree beyond Eidolons scaffolding, and no
`.spectra/setup/spectra-conventions.md` is present. Per `SPEC.md` CLARIFY step
4 and Pattern step 2, SPECTRA proceeds with **generic defaults** rather than
project-specific vocabulary. Generic placeholder names are used throughout
(e.g. "the App", "the session service") and called out as assumptions where
the choice materially affects the design.

**Cognitive load assessment:** High. In a real engineering org this would span
multiple sessions and multiple reviewers (backend auth owners, the
session/session-service owners, AppSec, legal/compliance, enterprise
sales/CS). This document compresses that into one pass, per the mission's
instruction to produce one complete artifact; §9 names exactly which decisions
still need a human before `in_progress` work starts.

**CLARIFY skip check:** Not skipped — genuine ambiguity existed and was
processed above.

---

## 3. S — SCOPE

### 3.1 Intent Classification

**Type:** `CHANGE` — this modifies an existing, live authentication system
with an existing session model that other services already depend on. Action:
delta analysis + impact assessment (not greenfield "REQUEST" generation).

**Delta / impact framing (the load-bearing invariant of this whole spec):**
the session model itself is **not** modified. SAML is added strictly as a new
*front door* — a new way to arrive at the exact same internal
`create_session(user)` call that email/password login already uses today. Every
downstream service that validates sessions keeps doing exactly what it does
today. If this invariant is not held, this is the single most expensive way
for this project to fail (see Risk R-5 in §7 and Failure Taxonomy note in
§7.6).

### 3.2 Complexity Scoring (4-dimension matrix, `templates/scoring.md`)

| Dimension | Score (1-3) | Justification |
|---|---|---|
| **Scope** | 3 (Multi-project) | Touches auth flow, tenant/admin configuration, identity linking, and introduces a new external trust boundary (customer IdPs) — even though downstream services are code-unchanged, they inherit new trust exposure by construction. |
| **Ambiguity** | 3 (Vague/conflicting) | IdP choice, tenancy model, JIT-provisioning policy, and SLO requirement are all unstated; the mission explicitly defers these to the spec. |
| **Dependencies** | 3 (Cross-domain) | Spans identity/auth subsystem, session subsystem, tenant/org admin surface, external IdP protocol integration, and observability. |
| **Risk** | 3 (Critical path) | Authentication is the textbook critical path; a defect here ranges from customer lockout to account takeover across the whole app. |
| **Total** | **12/12** | **Thinking budget: Extended (2×) — human collaboration recommended by the scoring table's own threshold.** |

**Handling the 10–12 "human collaboration recommended" threshold under a
no-clarifying-questions constraint:** The mission explicitly forbids pausing
for questions and directs that ambiguity be handled *within* the spec. SPECTRA
does not have a mechanism to silently downgrade a 12/12 score to look more
confident than it is. Instead, this is resolved the way `SPEC.md` intends when
human-in-the-loop isn't available mid-cycle: assumptions are logged with
risk-if-wrong (§3.4), the spec is fully assembled and made decision-ready
(this is the actual mission), and the Assemble confidence gate is allowed to
land honestly at **VALIDATE** rather than being forced to **AUTO_PROCEED**
(§9). This is the methodology working as designed, not a shortfall.

**TRANCE (parallel-spec) consideration:** This complexity score (12/12) plus
"multi-service architecture" and "high-rework-risk system design" are exactly
the stakes flags `skills/parallel-spec.md` names for TRANCE activation.
However, TRANCE is explicitly **cortex-gated** ("Activate ONLY when the cortex
authorizes TRANCE") and this installation has no nexus cortex
(`EIDOLONS.md`) present — it is a standalone SPECTRA install invoked directly.
Per the hard constraint "TRANCE-GATED — never the default," the absence of an
authorizing cortex means **the standard single-pass S→P→E→C→T→R→A cycle is
used**, not the parallel G3 mode. This is noted here for auditability rather
than silently defaulting one way or the other.

### 3.3 WHO / WHAT / WHY / CONSTRAINTS

Restated formally for the Scope artifact (see §2 for full parse):

- **WHO:** Existing application end users; specifically enterprise-tier
  customers whose IT policy requires federated SSO via their own IdP.
- **WHAT:** SAML 2.0 SP-initiated authentication, bridging into the existing
  session issuance path, plus identity linking for pre-existing accounts.
- **WHY:** Unblock/retain enterprise sales; meet customer security posture
  requirements.
- **CONSTRAINTS:** Session model is a hard invariant (no breaking changes for
  dependent services); existing email/password auth must continue to work
  during and after rollout; security posture must not regress.

### 3.4 Boundaries

| In Scope | Out of Scope | Deferred |
|---|---|---|
| SP-initiated SAML 2.0 login (Redirect binding for AuthnRequest, POST binding for Response) | SAML Single Logout (SLO) | SLO — revisit after GA if support tickets show real user confusion (§7 Risk R-9) |
| Per-tenant IdP connection configuration (metadata/cert/entity IDs) | SCIM-based automated user de/provisioning | SCIM provisioning — natural F-3 follow-on once JIT patterns are proven |
| Identity linking for existing accounts (email/password → SAML identity) | OpenID Connect (OIDC) support | OIDC — likely Phase 2 of the enterprise-identity theme, not this project |
| JIT provisioning for net-new SSO users (tenant-policy-gated) | Self-service tenant onboarding UI (admin uploads metadata via a form) | Self-service config UI — v1 ships with support-assisted/API-driven config |
| SSO-enforcement toggle per tenant domain, with a break-glass admin path | Native mobile app deep-link SAML flows | Mobile SAML — assumed web-browser redirect flow only for v1 (Assumption A-8) |
| Certificate rotation workflow + expiry alerting | Group/role attribute-based authorization changes | Attribute-based authZ — v1 trusts IdP attributes for identity only, not privilege (Risk R-8) |

### 3.5 Assumptions Log (resolving mission ambiguity without clarifying questions)

| # | Assumption | Risk if wrong |
|---|---|---|
| A-1 | The application is multi-tenant B2B SaaS: each customer organization ("tenant") may configure its own IdP connection. | If actually single-tenant/enterprise-only, tenant-scoping (§6.3, F-1) becomes unnecessary complexity — low risk, since a single-tenant app is a strict subset of the multi-tenant design (one tenant row). |
| A-2 | The existing session model is a server-side session record referenced by an opaque, HttpOnly session cookie, minted by a shared internal `create_session(user)` call that other services validate against (directly or via a shared session-service). | If instead it's a self-contained signed JWT validated independently by each service, the architecture is unchanged — SAML success still calls the same token-minting path (§6.3 S-6); only the low-level implementation detail of "mint" changes. Medium risk to estimate accuracy, low risk to architecture. |
| A-3 | Just-in-time (JIT) account provisioning for net-new SSO users is acceptable *by default*, but is a per-tenant policy toggle (tenants can require pre-provisioned accounts instead). | If JIT provisioning turns out to require legal/compliance sign-off not yet obtained (data processing, consent), ship with the toggle defaulted OFF until sign-off lands — this is why JIT is called out explicitly as an Open Flag in §9, not silently assumed safe. |
| A-4 | A "break-glass" non-SSO admin account/procedure either already exists or will be created alongside SSO enforcement (S-3), so enforcing SSO for a tenant domain can never fully lock out all admins. | If no such mechanism exists today, S-3 must ship *before* any tenant is allowed to enable SSO enforcement — sequenced as a hard blocking dependency in §6. |
| A-5 | Local email addresses are already verified (double opt-in or equivalent) before this project starts. | If unverified emails are allowed to exist today, identity-linking auto-match (§6.3, S-7) must additionally gate on "local email verified," which is already how S-7 is written — this assumption confirms rather than weakens the design, but is flagged since it's load-bearing for Risk R-3. |
| A-6 | Each tenant has exactly one active IdP connection at a time (no multi-IdP-per-tenant in v1). | If a tenant genuinely needs multiple IdPs (e.g. post-M&A), the `saml_connections` table (§6.3) already supports multiple rows per tenant_id at the schema level; only the tenant-discovery UX (S-2) would need extending — contained, not a re-architecture. |
| A-7 | The application's login surface is a browser-based web app (redirect-capable), not exclusively a native mobile client. | If mobile-only, SP-initiated redirect flows still work via an embedded web view / ASWebAuthenticationSession-style pattern; this is a UX/story-level change, not an architectural one. |
| A-8 | Attribute-based authorization (roles/groups asserted by the IdP) is explicitly NOT trusted for privilege in v1 — SAML governs authentication (who), not authorization (what they can do). | If a design partner requires IdP-driven role mapping at launch, this becomes a new F-4 story gated by its own security review (Risk R-8) — deliberately deferred, not silently built. |

### 3.6 Stakeholders (approval chain)

| Stakeholder | Role in this change |
|---|---|
| Backend/Auth platform team | Owns SP implementation, identity linking, session bridging (builder + reviewer) |
| Session/session-service owners | Must confirm the "no session-model changes" invariant holds (§3.1) — reviewer, veto power over F-2/F-3 |
| AppSec / Security review | Owns Security Risk Register sign-off (§7), especially XSW test suite (S-12) — blocking reviewer for GA |
| Legal / Compliance | Sign-off on JIT auto-provisioning (data handling) and IdP metadata storage/data residency — named Open Flag (§9) |
| Enterprise Sales / Customer Success | Identifies design-partner tenants for phased rollout (§8); communicates SSO-enforcement UX to customers |
| Support / Ops | Owns break-glass procedure (S-3) and cert-expiry runbook (S-11) |
| Downstream service owners (session consumers) | Informed, not blocking — the point of this design is that they require no changes; still notified per §8 rollout comms |

---

## 4. P — PATTERN

**Memory query (CRYSTALIUM):** `mcp__crystalium__*` tools are not present in
this session's tool surface. Per the graceful-skip contract in `agent.md` and
`skills/planning.md`, this is a **silent no-op**, not a failure — SPECTRA is
EIIS-standalone-conformant. No prior specs/reflections were available to fold
into context.

**Codebase query:** No consumer-project source tree exists in this
installation beyond Eidolons scaffolding, and no
`.spectra/setup/spectra-conventions.md` was found. Per `SPEC.md` Pattern step
2, generic defaults are used rather than fabricated repo hits.

**Reference patterns considered** (industry-standard SAML SP integration
patterns, used as the "pattern corpus" in place of an unavailable in-repo
history):

| ID | Pattern | Fit | Decision |
|---|---|---|---|
| P1 | SP-initiated SAML + centralized session-bridging (validate assertion at the edge, mint the *existing* internal session, never let the SAML library touch session state directly) | High — directly matches the mission's hard constraint that the session model is untouched | ADAPT — this is the skeleton for the selected hypothesis (§5) |
| P2 | Auth broker / dedicated SSO gateway (in-house or vendor) sitting in front of the app, translating SAML↔internal session | High — same family as P1, differs on build-vs-buy axis, explored as H2 in §5 | ADAPT |
| P3 (anti-pattern) | Hand-rolled XML parsing/signature validation without a vetted SAML library | N/A — cataloged as a **known failure pattern**, not adopted | AVOID — see Pattern step 5 below |

**Strategy selected:** **ADAPT** (60–84% band). SAML SP integration is one of
the most well-trodden patterns in SaaS engineering; there is no need to
`GENERATE` from a blank slate, but there is also no ≥85%-match in-repo
template to `USE_TEMPLATE` directly (no repo exists here). Adapting the
known-good P1/P2 pattern family as the skeleton, with the project's specific
identity-linking and session-bridging requirements layered on top, is the
correct strategy call.

**Catalog Failure Patterns (Pattern step 5 — anti-patterns to avoid, feeding
the Explore and Security sections below):**

1. **Hand-rolled SAML XML signature validation.** The recurring CVE class in
   SAML implementations is exactly this: writing custom XML canonicalization
   / signature-verification code instead of using an audited library. This is
   the primary reason H1 (in-house build) is scored lower than H2 in §5 and
   why Risk R-1 (XSW) exists as a named, Critical-severity item in §7.
2. **Trusting the IdP-asserted email as identity proof without a local
   confirmation step.** A well-known failure mode where any user who can get
   an IdP (or a misconfigured/compromised one) to assert `victim@company.com`
   can silently take over the existing local account. This directly shapes
   the identity-linking design in §6.3.
3. **Reusing a pre-authentication session identifier after login (session
   fixation).** Feeds Risk R-5 and Story S-6.

---

## 5. E — EXPLORE

### 5.1 Observations (5 distinct angles)

1. **Security surface** — SAML introduces XML-signature cryptography, a new
   external trust boundary (customer-controlled IdPs), and a novel
   account-linking decision point; this is the dominant risk axis for this
   project (see §7).
2. **Blast radius on dependents** — because other services depend on the
   session model, any design that *doesn't* strictly preserve today's session
   shape carries organization-wide risk, not just auth-team risk.
3. **Time-to-market vs. build effort** — enterprise deals are often blocked
   today on the absence of SSO; a faster, well-trodden path has real revenue
   value over a more "complete" but slower build.
4. **Long-term maintainability** — SAML libraries and certificate rotation
   are an ongoing maintenance surface (expiring certs, IdP-side changes);
   the chosen approach should minimize custom cryptographic code that the team
   must keep patched.
5. **Multi-tenancy / configuration complexity** — supporting many customer
   IdPs means the "pattern" isn't just the SAML protocol, it's a
   configuration-management problem (one wrong tenant-scoping bug can leak
   cross-tenant trust).

### 5.2 Hypotheses (4 genuinely distinct strategies — quick-score triage)

| # | Name | Perspective | Feasibility | Value | Risk Profile | Pattern Fit | Timebox Fit | Total /15 |
|---|---|---|---|---|---|---|---|---|
| H1 | In-house SAML SP via a vetted open-source library (e.g. a maintained `python3-saml`/`ruby-saml`/`passport-saml`-class library), full custom identity-linking logic | Conservative (low-risk, proven) | 2 | 3 | 2 | 3 | 2 | 12 |
| H2 | Third-party SSO abstraction layer (managed SAML/OIDC gateway service, e.g. WorkOS/Auth0/Okta-class "SSO-as-a-service") sitting at the edge, translating validated assertions into the existing session-issuance call | Pattern-leveraging (maximizes reuse of a widely-adopted integration shape; minimizes custom crypto) | 3 | 3 | 3 | 3 | 3 | 15 |
| H3 | Build a full in-house Identity Provider / broker supporting arbitrary protocols (SAML, OIDC, SCIM) as a new platform capability | Innovative | 1 | 2 | 1 | 1 | 1 | 6 |
| H4 | SSO-only for net-new accounts; no identity linking — existing users must create a separate SSO-only account | Risk-minimizing (technically simplest) | 3 | 1 | 3 | 2 | 3 | 12 |

**Diversity check:** at least one conservative (H1), one pattern-leveraging
(H2), one innovative (H3), plus a risk-minimizing counter-option (H4) — the
mandatory mix is satisfied. Scores are not within 5% of each other (H2 leads
by 3+ points over the next-best), so differentiation is sufficient; no
re-observation needed.

### 5.3 Full Rubric — Top 2 Expanded (H1 vs H2)

| Dimension | Weight | H1 (in-house) | H2 (SSO abstraction layer) |
|---|---|---|---|
| Alignment | 25% | 8 — solves the stated goal, but "identity linking" logic is fully bespoke and unreviewed | 9 — solves the stated goal; linking logic still bespoke (vendor doesn't own business identity decisions), but the protocol-correctness burden is offloaded |
| Correctness & Feasibility | 20% | 6 — correctness of XML signature validation now rests entirely on the team's library choice and configuration; XSW-class bugs are the dominant real-world failure mode for exactly this kind of code | 9 — assertion validation, XSW hardening, and canonicalization correctness are owned by a widely-used, independently audited component; team is responsible for the *edge* (fewer moving parts to get wrong) |
| Maintainability | 15% | 6 — cert rotation, IdP quirks (Okta vs Azure AD vs Ping all have real-world attribute/encoding differences), and library upgrades are all in-house ongoing burden | 8 — much of IdP-quirk handling and cert lifecycle is externalized; in-house surface is the linking/session-bridging logic, which is small and stable |
| Performance & Scalability | 15% | 7 — comparable, protocol overhead is the same either way | 7 — comparable; adds one network hop to the abstraction layer if hosted, negligible for a login-frequency operation |
| Simplicity | 10% | 6 — more code in-repo, more surface to reason about | 8 — smaller in-repo footprint; the "obvious way" given the failure-pattern history of SAML |
| Risk & Robustness | 10% | 5 — highest-risk axis for this whole project; hand-rolled crypto-adjacent code is the named anti-pattern in §4 | 9 — directly reduces the Critical-severity risks in §7 (R-1, R-2) by construction |
| Innovation | 5% | 5 — boring, proven | 6 — not novel, but well-executed "buy the risky part" is the right kind of unexciting |
| **Weighted total** | | **6.55 × 10 ≈ 65.5 → 66/100 (Weak-to-Solid boundary)** | **8.35 × 10 ≈ 83.5/100 (Solid, near-Elite)** |

**Selected: H2 — Third-party SSO abstraction layer at the edge, bridging into
the existing session model.**

**Rationale:** The dominant risk in this project is exactly the class of bug
(XML signature/XSW handling, replay, canonicalization) that a mature,
widely-deployed SSO abstraction already had to solve and battle-test. Building
that logic in-house (H1) does not create meaningful business differentiation
— customers care that SSO works and is secure, not whose code validates the
XML signature. H2 keeps the actual differentiating logic (identity linking
against the existing account model, tenant configuration, session bridging)
in-house, where it belongs, while outsourcing the highest-risk, lowest-value
component. This is a build-vs-buy trade-off, made explicitly and with
rationale, per Explore step 5.

**What's traded off:** vendor cost and a new operational dependency (an
outage or misbehavior in the SSO abstraction layer becomes a login-path
outage). This is mitigated by S-13 (kill switch — able to disable
SSO-required enforcement and fall back to password login per tenant) and is
explicitly named as a residual risk in §7 (R-6 operational note) and §9.

### 5.4 Rejected Alternatives

- **H1 — In-house SAML SP via a vetted library.** Rejected as the *primary*
  path because it concentrates the highest-severity risk class (XML signature
  / XSW handling) inside custom code with no differentiation upside; retained
  in this document as the **documented fallback** if a third-party vendor
  cannot be procured in time (e.g. procurement/legal delay) — in that case,
  re-run this Explore step's rubric with updated vendor-availability
  constraints rather than silently reverting.
- **H3 — Build a full in-house Identity Provider / broker.** Rejected: massive
  scope overrun relative to the stated need ("add SSO," not "become an
  identity platform"), long timeline, and no near-term ROI. This is a
  Premature Optimization failure pattern (§7.6) if selected now.
- **H4 — SSO-only new accounts, no identity linking.** Rejected: the mission
  explicitly requires identity linking for existing accounts, and H4 directly
  contradicts that requirement — it would force existing paying customers
  into a second, disconnected account with no history continuity, which is a
  Valuable-criterion (INVEST) failure from the business's own perspective, not
  just a technical shortcut. Documented here specifically because it is the
  cheapest-looking option and a stakeholder is likely to ask "why not this,"
  per Explore step 6 ("prevents re-exploration in replanning").

---

## 6. C — CONSTRUCT

**Hierarchy:**

```
THEME: Enterprise Identity Federation (unlock/retain enterprise accounts requiring SSO)
└── PROJECT P-1: SAML SSO Integration
    ├── FEATURE F-1: Tenant SAML Connection Management
    ├── FEATURE F-2: SP-Initiated SAML Authentication Flow
    ├── FEATURE F-3: Identity Linking & Provisioning
    ├── FEATURE F-4: Security Hardening & Abuse Prevention
    └── FEATURE F-5: Rollout, Observability & Rollback
```

All 15 stories below pass INVEST (Independent / Negotiable / Valuable /
Estimable / Small / Testable — `templates/scoring.md`); none exceed the 8-day
timebox ceiling, and none use story points.

### 6.1 Feature F-1 — Tenant SAML Connection Management

#### STORY S-1: Tenant SAML connection configuration

> 🔵 Foundational — everything else in F-2/F-3 depends on this existing.

**Description:** As a **tenant administrator**, I want **to register my
organization's IdP connection (metadata, signing certificate, entity IDs)**
so that **my organization's users can authenticate via our own identity
provider.**
**Timebox:** ≤3d
**Risk:** P1

**Action Plan:**
1. **Create:** `saml_connections` table — `id, tenant_id, idp_entity_id,
   idp_sso_url, idp_x509_cert, sp_entity_id, acs_url, name_id_format,
   attribute_mapping (json), sso_enforced (bool, default false),
   idp_initiated_allowed (bool, default false), status (draft|active|disabled),
   created_at, rotated_at`.
2. **Create:** an internal (support/API-driven, not self-service in v1 per
   §3.4) admin operation to create/update a tenant's connection from IdP
   metadata XML or manual field entry.
3. **Configure:** unique constraint on `(tenant_id, idp_entity_id)`.
4. **Test:** unit tests for metadata parsing and validation (reject malformed
   or missing required fields before `status` can become `active`).

**Acceptance Criteria:**
- [ ] GIVEN a well-formed IdP metadata document WHEN an admin submits it for a
  tenant THEN a `saml_connections` row is created with `status: draft` and all
  required fields populated.
- [ ] GIVEN a connection missing a signing certificate WHEN an admin attempts
  to set `status: active` THEN the operation is rejected with an actionable
  error.
- [ ] GIVEN two connections submitted for the same `(tenant_id, idp_entity_id)`
  THEN the second is rejected as a duplicate, not silently overwritten.

**Technical Context:**
- **Pattern:** P1/P2 (§4) — tenant-scoped configuration table.
- **Files:** `db/migrations/*_create_saml_connections.*`, tenant-admin API
  handler (generic path: `app/admin/saml_connections`).
- **Dependencies:** none (foundational).

**Agent Hints:**
- **Class:** builder
- **Context:** existing tenant/organization model, existing admin-API
  conventions.
- **Gates:** P1 checked; migration reversible; tests cover malformed metadata.

---

#### STORY S-2: Tenant discovery / SSO login routing

**Description:** As an **end user**, I want **the login page to route me to
my organization's IdP** so that **I don't have to remember a special URL or
manually pick my identity provider.**
**Timebox:** ≤2d
**Risk:** P1
**Dependencies:** S-1

**Action Plan:**
1. **Create:** tenant-discovery step on the login surface — accept either an
   email address (derive domain → look up an active `saml_connections` row
   whose tenant claims that domain) or a tenant-specific slug URL
   (`/sso/<tenant-slug>`).
2. **Extend:** existing login controller to branch into the SAML SP-initiated
   flow (S-4) when discovery resolves to an active connection.
3. **Test:** ambiguous/unregistered domains fall through to standard
   password login unchanged.

**Acceptance Criteria:**
- [ ] GIVEN an email domain mapped to an active SAML connection WHEN a user
  enters that email on the login page THEN they are redirected into the
  SP-initiated flow (S-4) rather than shown a password field.
- [ ] GIVEN an email domain with no SAML connection THEN the existing
  password login form is shown unchanged.
- [ ] GIVEN a tenant slug URL for a `draft` (not yet `active`) connection
  THEN the user sees a clear "SSO not yet enabled" message, not a broken flow.

**Technical Context:**
- **Pattern:** domain-based tenant discovery (standard multi-tenant SaaS
  pattern).
- **Files:** login controller/view, tenant lookup service.
- **Dependencies:** S-1.

**Agent Hints:**
- **Class:** builder
- **Context:** S-1's schema, existing login-page routing.
- **Gates:** P1 checked; regression test confirms non-SSO login path is
  untouched.

---

#### STORY S-3: SSO enforcement toggle + break-glass admin safeguard

> 🔴 Blocking dependency: no tenant may enable `sso_enforced` until this ships.

**Description:** As a **tenant administrator**, I want **to require SSO for
my organization's users (disabling password login for matching accounts)**
so that **my organization's security policy is actually enforced, not just
offered** — while as a **platform operator**, I want **a guaranteed
non-SSO admin recovery path** so that **an IdP outage or misconfiguration
can never fully lock every admin out of the application.**
**Timebox:** ≤2d
**Risk:** P0
**Dependencies:** S-1, S-2

**Action Plan:**
1. **Modify:** password-login handler to check `sso_enforced` for the
   account's domain **server-side, on every attempt** — not merely hide the
   UI option (directly closes Risk R-7, §7).
2. **Create/Confirm:** a break-glass admin account/procedure explicitly
   excluded from `sso_enforced` checks (per Assumption A-4); document the
   procedure for Support/Ops.
3. **Test:** password login is rejected server-side for an enforced domain
   even if the request bypasses the UI entirely (e.g. direct API call).

**Acceptance Criteria:**
- [ ] GIVEN a tenant with `sso_enforced: true` WHEN a matching-domain user
  submits valid password credentials directly to the auth API THEN the
  request is rejected with a redirect-to-SSO response, not authenticated.
- [ ] GIVEN the break-glass admin account WHEN it authenticates with a
  password THEN it succeeds regardless of any tenant's `sso_enforced` state.
- [ ] GIVEN a tenant enabling `sso_enforced` for the first time WHEN no
  break-glass procedure exists yet THEN the enable operation is blocked
  (hard dependency, not a soft warning).

**Technical Context:**
- **Pattern:** server-side authorization check, not client-side-only gating.
- **Files:** password auth handler, tenant policy service.
- **Dependencies:** S-1, S-2.

**Agent Hints:**
- **Class:** reasoner (security-sensitive branch logic)
- **Context:** Risk R-7 (§7); existing password-auth code path.
- **Gates:** P0 checked; explicit test for API-level bypass attempt.

### 6.2 Feature F-2 — SP-Initiated SAML Authentication Flow

#### STORY S-4: Generate signed AuthnRequest (Redirect binding)

**Description:** As the **application (SP)**, I want **to issue a signed SAML
AuthnRequest and redirect the user to their IdP** so that **authentication is
initiated correctly and can be matched to a response later.**
**Timebox:** ≤2d
**Risk:** P1
**Dependencies:** S-1, S-2

**Action Plan:**
1. **Create:** AuthnRequest generation via the chosen SSO abstraction (H2,
   §5.3) — HTTP-Redirect binding, includes a unique `ID`, `RelayState`
   carrying the tenant context.
2. **Create:** a server-side store (short TTL, e.g. 5–10 min) of issued
   request IDs, keyed for later `InResponseTo` validation (feeds S-5's replay
   defense).
3. **Test:** request ID uniqueness and TTL expiry.

**Acceptance Criteria:**
- [ ] GIVEN a user enters the SP-initiated flow WHEN the AuthnRequest is
  built THEN it is signed, includes a fresh unique ID, and that ID is
  recorded server-side before redirect.
- [ ] GIVEN a request ID older than the TTL WHEN a response references it
  THEN it is treated as invalid (see S-5).

**Technical Context:**
- **Pattern:** standard SP-initiated Redirect binding.
- **Files:** SAML SP integration module (edge layer per H2).
- **Dependencies:** S-1, S-2.

**Agent Hints:**
- **Class:** builder
- **Context:** chosen SSO abstraction's SDK/API docs.
- **Gates:** P1 checked; request-ID store has enforced TTL.

---

#### STORY S-5: ACS endpoint — validate SAMLResponse

> 🔴 Highest-risk story in this project — see Security Risk Register (§7),
> specifically R-1 and R-2.

**Description:** As the **application (SP)**, I want **to rigorously
validate every inbound SAMLResponse before trusting its contents** so that
**forged, replayed, or tampered assertions can never authenticate a user.**
**Timebox:** ≤5d
**Risk:** P0
**Dependencies:** S-4

**Action Plan:**
1. **Configure:** the chosen SSO abstraction's assertion-validation pipeline
   (signature verification against the tenant's stored `idp_x509_cert`,
   correct-element signature binding to defeat XSW, canonicalization).
2. **Validate:** `Issuer` matches the `idp_entity_id` configured for the
   tenant context carried in `RelayState`; `Audience` matches `sp_entity_id`;
   `Recipient` equals the exact ACS URL; `NotBefore`/`NotOnOrAfter` within a
   small clock-skew tolerance; `InResponseTo` matches an unexpired,
   **single-use** request ID from S-4's store (consumed atomically so a
   response cannot be replayed).
3. **Extract:** `NameID` + email/attributes per the tenant's
   `attribute_mapping`.
4. **Test:** an adversarial test suite covering XSW variants, replay
   (reused `InResponseTo`), expired assertions, and audience/recipient
   mismatch — feeds directly into S-12.

**Acceptance Criteria:**
- [ ] GIVEN a validly signed SAMLResponse referencing an unexpired,
  unconsumed request ID THEN it is accepted exactly once; a second
  submission of the identical response is rejected.
- [ ] GIVEN a SAMLResponse containing a wrapped/duplicated Assertion
  (XSW pattern) THEN it is rejected — the signature must be validated over
  the exact assertion element actually processed, not merely "a" signed
  element present anywhere in the document.
- [ ] GIVEN an assertion whose `Audience` does not match this SP's
  `sp_entity_id` THEN it is rejected.
- [ ] GIVEN an assertion signed by a certificate not matching the tenant's
  configured `idp_x509_cert` THEN it is rejected, even if the `Issuer`
  string matches.

**Technical Context:**
- **Pattern:** P1/P2 (§4); anti-pattern P3 explicitly avoided (§4).
- **Files:** ACS endpoint handler, assertion-validation config.
- **Dependencies:** S-4.

**Agent Hints:**
- **Class:** reasoner (security-critical validation logic) + reviewer
  (AppSec sign-off required before merge).
- **Context:** Security Risk Register §7 R-1/R-2; chosen library's
  documented XSW-hardening configuration.
- **Gates:** P0 checked; adversarial test suite (S-12 scope) passes; AppSec
  review required, not optional.

---

#### STORY S-6: Session bridging into the existing session model

> This is the story that directly protects the mission's named invariant:
> "a session model other services depend on."

**Description:** As the **application**, I want **a successful SAML
authentication to mint a session via the exact same internal path that
password login already uses** so that **every downstream service that
depends on the session model keeps working with zero changes.**
**Timebox:** ≤2d
**Risk:** P0
**Dependencies:** S-5

**Action Plan:**
1. **Extend:** on successful assertion validation (S-5), call the existing
   internal `create_session(user)` path unchanged — do not introduce a
   parallel/second session type for SSO users.
2. **Create:** a fresh session on every SAML login; explicitly discard/ignore
   any pre-authentication session identifier that existed before the SSO
   flow began (defeats session fixation — Risk R-5).
3. **Test:** a downstream-service contract test — confirm a session minted
   via SAML is indistinguishable in shape/validation from one minted via
   password login.

**Acceptance Criteria:**
- [ ] GIVEN a successful SAML authentication WHEN the session is issued
  THEN it is created via the same `create_session(user)` call path as
  password login, with no schema differences observable to downstream
  services.
- [ ] GIVEN a browser held a pre-authentication session/cookie value before
  starting the SSO flow WHEN authentication completes THEN a brand-new
  session identifier is issued; the old one is never reused or upgraded.
- [ ] GIVEN a downstream service validating a SAML-originated session THEN it
  passes validation with no code changes on the downstream side.

**Technical Context:**
- **Pattern:** "session bridging at the edge" — the core architectural
  decision from H2 (§5.3).
- **Files:** SAML SP integration module (post-validation hook),
  session-issuance service (call site only, no modification).
- **Dependencies:** S-5.

**Agent Hints:**
- **Class:** reasoner
- **Context:** existing `create_session` implementation; session-service
  owners must review this story specifically (§3.6).
- **Gates:** P0 checked; downstream contract test passes; session-service
  owner sign-off required.

### 6.3 Feature F-3 — Identity Linking & Provisioning

This is the section directly answering the mission's **"identity linking for
existing accounts"** requirement.

**Design summary:** On first successful SAML login for a given
`(tenant_id, idp_entity_id, NameID)` triple, the system resolves identity in
this order:

1. **Already linked** — an `sso_identities` row exists for this exact triple
   → log in as the linked user via S-6, no further action.
2. **Local account match, not yet linked** — a local account exists in the
   same tenant whose **verified** email matches the IdP-asserted email →
   require one-time **step-up confirmation** (the user must authenticate with
   their existing local password once, in the same session, before the link
   is created) rather than silently trusting the IdP's email claim. This is
   the direct mitigation for Risk R-3 (§7) and the anti-pattern named in §4.
3. **No local match, JIT allowed for this tenant** — auto-provision a new
   local account, `email_verified: true` (trust boundary: the IdP already
   cryptographically signed the assertion in S-5), and create the
   `sso_identities` link immediately. The new account has no local password
   set.
4. **No local match, JIT disallowed for this tenant** — deny login with an
   actionable message directing the user to their admin; no account is
   created.

**Schema:** `sso_identities`: `id, user_id (FK), tenant_id, idp_entity_id,
name_id, name_id_format, email_at_idp, linked_at, last_login_at`, with a
unique constraint on `(tenant_id, idp_entity_id, name_id)` and an index on
`user_id`.

#### STORY S-7: Existing-account linking with step-up confirmation

**Description:** As an **existing user**, I want **my SAML identity linked to
my existing account only after I've proven I control that account** so that
**an attacker who can get an IdP to assert my email address cannot silently
take over my account.**
**Timebox:** ≤3d
**Risk:** P0
**Dependencies:** S-6

**Action Plan:**
1. **Create:** the "candidate match found, not yet linked" branch — present
   the user a confirmation step requiring their existing local password.
2. **Create:** `sso_identities` row only after the step-up password check
   succeeds, within the same request/session context (not via an
   out-of-band emailed link, which reintroduces phishing surface).
3. **Test:** an email-collision attempt where the IdP asserts an email
   matching another user's account is blocked without the correct password.

**Acceptance Criteria:**
- [ ] GIVEN a local account exists with a verified email matching the
  IdP-asserted email, and is not yet linked, WHEN the SAML login completes
  THEN the user is prompted for their existing password before any
  `sso_identities` row is created.
- [ ] GIVEN the user enters the wrong password at the step-up prompt THEN no
  link is created and no session is issued for that local account.
- [ ] GIVEN the link is successfully created THEN subsequent SAML logins for
  the same `(tenant_id, idp_entity_id, NameID)` skip the step-up prompt
  (state 1 in the design summary above).

**Technical Context:**
- **Pattern:** step-up re-authentication before a trust-elevating action.
- **Files:** identity-resolution service, `sso_identities` migration.
- **Dependencies:** S-6.

**Agent Hints:**
- **Class:** reasoner (security-sensitive) + reviewer.
- **Context:** Risk R-3 (§7); anti-pattern #2 in §4.
- **Gates:** P0 checked; AppSec review required.

---

#### STORY S-8: JIT provisioning for net-new SSO users

**Description:** As a **new enterprise user with no existing account**, I
want **my first SAML login to create my account automatically (when my
tenant allows it)** so that **I don't need a separate manual sign-up step.**
**Timebox:** ≤3d
**Risk:** P1
**Dependencies:** S-6

**Action Plan:**
1. **Create:** per-tenant `jit_provisioning_allowed` policy flag (default
   per Assumption A-3 — flagged as an Open Flag in §9 pending legal
   sign-off).
2. **Create:** account auto-creation path: new user row +
   `sso_identities` link created atomically; `email_verified: true`.
3. **Test:** JIT-disallowed tenants correctly deny rather than
   auto-create.

**Acceptance Criteria:**
- [ ] GIVEN a tenant with `jit_provisioning_allowed: true` and no matching
  local account WHEN a new user authenticates via SAML THEN a new account
  is created and linked in the same transaction.
- [ ] GIVEN a tenant with `jit_provisioning_allowed: false` and no matching
  local account THEN login is denied with an actionable admin-contact
  message; no account is created.

**Technical Context:**
- **Pattern:** JIT provisioning, tenant-policy-gated (not global default).
- **Files:** identity-resolution service, tenant policy config.
- **Dependencies:** S-6.

**Agent Hints:**
- **Class:** builder
- **Context:** S-7's identity-resolution branch structure.
- **Gates:** P1 checked; legal sign-off recorded before default-enabling
  for any tenant (§9).

---

#### STORY S-9: Identity-linking conflict handling

**Description:** As the **system**, I want **well-defined behavior for edge
cases in identity resolution** so that **no ambiguous state ever silently
grants access to the wrong account.**
**Timebox:** ≤2d
**Risk:** P1
**Dependencies:** S-7, S-8

**Action Plan:**
1. **Create:** explicit handling for: (a) IdP-asserted email matches a local
   account already linked to a *different* SSO identity, (b) IdP-asserted
   email matches more than one local account (should be structurally
   impossible if emails are unique per tenant, but validate it), (c) case/
   normalization mismatches (e.g. `User@Co.com` vs `user@co.com`).
2. **Test:** each conflict case resolves to an explicit denial + actionable
   error, never a silent best-guess match.

**Acceptance Criteria:**
- [ ] GIVEN a local account already linked to a different `NameID` WHEN a
  second IdP identity asserts the same email THEN the login is denied with
  an "already linked to a different identity" error, not silently
  re-linked.
- [ ] GIVEN mixed-case email matching THEN comparison is
  normalized/case-insensitive consistently on both the local-lookup and
  uniqueness-constraint sides.

**Technical Context:**
- **Pattern:** defensive conflict handling — deny-by-default on ambiguity.
- **Files:** identity-resolution service.
- **Dependencies:** S-7, S-8.

**Agent Hints:**
- **Class:** reviewer (edge-case audit) + builder.
- **Context:** S-7/S-8 resolution logic.
- **Gates:** P1 checked; each conflict case has an explicit test.

### 6.4 Feature F-4 — Security Hardening & Abuse Prevention

#### STORY S-10: IdP-initiated flow support (optional, off by default)

**Description:** As a **tenant with an IdP that only supports IdP-initiated
login (e.g. via an IdP application dashboard tile)**, I want **an
IdP-initiated flow available on an opt-in basis** so that **my organization's
preferred login UX still works**, without exposing tenants who don't need it
to the extra risk.
**Timebox:** ≤2d
**Risk:** P1
**Dependencies:** S-5

**Action Plan:**
1. **Create:** per-tenant `idp_initiated_allowed` flag, default `false`.
2. **Create:** for allowed tenants, validate the unsolicited response's
   `Issuer`/tenant binding strictly (no `RelayState` from a prior AuthnRequest
   exists to correlate against, so tenant-scoping must be derived from the
   ACS URL/Issuer pairing alone) and apply a short "freshness" tolerance on
   `IssueInstant`.
3. **Test:** an unsolicited response for a tenant with the flag `false` is
   rejected outright.

**Acceptance Criteria:**
- [ ] GIVEN a tenant with `idp_initiated_allowed: false` WHEN an unsolicited
  SAMLResponse arrives at the ACS endpoint THEN it is rejected.
- [ ] GIVEN a tenant with the flag `true` WHEN a validly signed, fresh,
  correctly Issuer-scoped unsolicited response arrives THEN it succeeds via
  the same S-5/S-6 validation and bridging path.

**Technical Context:**
- **Pattern:** opt-in exception path, not a default.
- **Files:** ACS endpoint handler (extends S-5).
- **Dependencies:** S-5.

**Agent Hints:**
- **Class:** reasoner (security-sensitive) + reviewer.
- **Context:** Risk R-4 (§7).
- **Gates:** P1 checked; default-off verified by test.

---

#### STORY S-11: Certificate rotation workflow + expiry alerting

**Description:** As a **platform operator**, I want **advance warning of
expiring IdP certificates and a safe rotation procedure** so that **a
certificate expiry never becomes an unplanned authentication outage for a
tenant.**
**Timebox:** ≤2d
**Risk:** P1
**Dependencies:** S-1

**Action Plan:**
1. **Create:** scheduled check against `idp_x509_cert` expiry per active
   connection; alert at 30/14/3 days out.
2. **Create:** a dual-cert grace-window update path (old + new cert both
   accepted for a bounded overlap window during planned rotation) to avoid a
   hard cutover outage.
3. **Test:** expiry alert fires at the correct thresholds; dual-cert window
   correctly accepts either cert during overlap and neither after it closes.

**Acceptance Criteria:**
- [ ] GIVEN a connection's certificate expires in 30/14/3 days THEN an alert
  fires to platform operators (not silently discovered at the moment of
  outage).
- [ ] GIVEN a rotation in the dual-cert grace window THEN responses signed
  by either the old or new certificate validate successfully; after the
  window closes, only the new certificate validates.

**Technical Context:**
- **Pattern:** operational safety valve for a known SAML operational risk
  (Risk R-6).
- **Files:** scheduled job, `saml_connections.rotated_at`.
- **Dependencies:** S-1.

**Agent Hints:**
- **Class:** builder
- **Context:** existing scheduled-job/alerting infrastructure conventions.
- **Gates:** P1 checked; alert thresholds tested.

---

#### STORY S-12: Adversarial security review pass

> 🔴 Gating story — GA (§8 Phase 2+) is blocked until this passes.

**Description:** As the **organization**, I want **an explicit adversarial
security review, including an automated XSW-class test suite, run against
the full SAML flow** so that **the highest-severity risks in §7 are verified
closed, not just designed-around.**
**Timebox:** ≤3d
**Risk:** P0
**Dependencies:** S-5, S-7, S-10

**Action Plan:**
1. **Create/Run:** an automated adversarial test suite covering XML
   Signature Wrapping variants, replay, audience/recipient/timing violations,
   and unsolicited-response abuse (reuses and extends the test scaffolding
   from S-5/S-10).
2. **Test:** each item in the Security Risk Register (§7) has a
   corresponding pass/fail check, not just a narrative mitigation.
3. **Document:** results reviewed and signed off by AppSec (§3.6) before
   any tenant is enabled beyond the dogfood phase (§8 Phase 0).

**Acceptance Criteria:**
- [ ] GIVEN the full Security Risk Register (§7) THEN every Critical/High
  item has an automated, passing test, not solely a design-review
  assertion.
- [ ] GIVEN the adversarial suite THEN it is wired into CI so a future
  regression in assertion validation is caught before merge, not just at
  this one-time review.

**Technical Context:**
- **Pattern:** Test-phase Adversarial layer (§7 of this document,
  operationalized as code).
- **Files:** security test suite (new), CI pipeline config.
- **Dependencies:** S-5, S-7, S-10.

**Agent Hints:**
- **Class:** reviewer (quality-class) + reasoner.
- **Context:** §7 Security Risk Register in full.
- **Gates:** P0 checked; AppSec sign-off recorded; CI-wired, not one-shot.

### 6.5 Feature F-5 — Rollout, Observability & Rollback

#### STORY S-13: Feature-flag gating per tenant + kill switch

**Description:** As a **platform operator**, I want **SAML SSO gated behind
a per-tenant feature flag with a global kill switch** so that **rollout can
be staged and instantly reverted if something goes wrong.**
**Timebox:** ≤1d
**Risk:** P0
**Dependencies:** S-6

**Action Plan:**
1. **Create:** per-tenant flag gating whether the SAML login path is even
   reachable for that tenant.
2. **Create:** a global kill switch that, when tripped, forces all traffic
   back to password-only login regardless of per-tenant flags (does not
   affect already-linked accounts' ability to use password login if they
   have one — SSO-only/JIT accounts without a local password are the one
   group affected, documented in §8's rollback notes).
3. **Test:** kill switch verified to take effect without a deploy (runtime
   toggle).

**Acceptance Criteria:**
- [ ] GIVEN a tenant without the feature flag enabled THEN the SAML login
  path is unreachable for that tenant, even if S-1 configuration exists.
- [ ] GIVEN the global kill switch is tripped THEN no tenant's SAML flow
  succeeds, without requiring a code deploy to take effect.

**Technical Context:**
- **Pattern:** staged-rollout feature flagging.
- **Files:** feature-flag config, ACS endpoint entry check.
- **Dependencies:** S-6.

**Agent Hints:**
- **Class:** builder
- **Context:** existing feature-flag infrastructure conventions.
- **Gates:** P0 checked; kill switch tested as a runtime toggle.

---

#### STORY S-14: Auth funnel observability

**Description:** As a **platform operator**, I want **metrics on the SAML
login funnel (attempt, validation failure by reason, linking outcome,
fallback to password)** so that **rollout health is measurable, not
anecdotal.**
**Timebox:** ≤2d
**Risk:** P1
**Dependencies:** S-6, S-7, S-8

**Action Plan:**
1. **Create:** metrics/dashboards for: SAML attempt count, validation
  failure count by reason code (ties to S-5's rejection cases), linking
  outcome breakdown (auto-linked / step-up-confirmed / JIT-created / denied),
  fallback-to-password rate.
2. **Configure:** alert thresholds feeding the rollback triggers in §8.

**Acceptance Criteria:**
- [ ] GIVEN a SAMLResponse validation failure THEN it is recorded with a
  specific reason code (not a generic "failed") so that a spike in one
  failure class is distinguishable from another.
- [ ] GIVEN the dashboards THEN a design-partner tenant's rollout health can
  be assessed without querying raw logs.

**Technical Context:**
- **Pattern:** funnel observability for a phased rollout.
- **Files:** metrics emission at S-5/S-7/S-8 decision points.
- **Dependencies:** S-6, S-7, S-8.

**Agent Hints:**
- **Class:** builder
- **Context:** existing metrics/dashboard conventions.
- **Gates:** P1 checked; reason codes enumerated and tested.

---

#### STORY S-15: Staged rollout execution

**Description:** As the **project team**, I want **a defined,
gate-checked rollout sequence** so that **SSO reaches GA without an
uncontrolled blast radius at any step.**
**Timebox:** ≤3d
**Risk:** P0
**Dependencies:** S-3, S-12, S-13, S-14 (effectively all prior features)

**Action Plan:**
1. **Execute:** the phased rollout defined in full in §8.
2. **Configure:** phase-gate checks (metrics thresholds, sign-offs) before
   advancing each phase.
3. **Document:** a rollback runbook referencing S-13's kill switch.

**Acceptance Criteria:**
- [ ] GIVEN Phase 0 (dogfood) metrics THEN Phase 1 (design partners) does
  not begin until the exit criteria in §8 are met.
- [ ] GIVEN a rollback trigger fires (§8) THEN the documented runbook step
  (kill switch, S-13) is executed and verified within the stated time
  budget.

**Technical Context:**
- **Pattern:** phase-gated rollout with explicit rollback path.
- **Files:** rollout runbook (ops doc), phase-gate checklist.
- **Dependencies:** S-3, S-12, S-13, S-14.

**Agent Hints:**
- **Class:** orchestrator (coordination-class) — spans eng, security, and
  CS/sales stakeholders (§3.6).
- **Context:** §8 in full.
- **Gates:** P0 checked; each phase's exit criteria explicit and measured,
  not judgment-call-only.

### 6.6 Release-Level Acceptance Criteria (consolidated)

Beyond the per-story GIVEN/WHEN/THEN above, these are the criteria a
stakeholder should check against the feature *as a whole* before calling it
done:

- [ ] GIVEN a configured, active tenant SAML connection, WHEN an end user
  completes SP-initiated authentication, THEN a session is created that is
  byte-for-byte compatible in shape/validation with a password-login session
  — no downstream service requires a code change to accept it (§6.2 S-6).
- [ ] GIVEN an existing email/password user whose email matches an
  IdP-asserted identity, WHEN they first authenticate via SAML, THEN they are
  never linked without proving control of the existing account via step-up
  authentication (§6.3 S-7).
- [ ] GIVEN the Security Risk Register (§7), WHEN GA rollout (§8 Phase 2) is
  proposed, THEN every Critical- and High-severity item has a passing
  automated test (S-12), not a narrative-only mitigation.
- [ ] GIVEN a tenant enforcing SSO, WHEN any recovery path is needed, THEN the
  break-glass admin account (S-3) remains available regardless of IdP
  availability.
- [ ] GIVEN any point in the rollout (§8), WHEN a rollback trigger fires,
  THEN the kill switch (S-13) restores password-only login for all tenants
  without a code deploy.

**Note on EARS form:** `templates/acceptance-criteria.md` offers an optional,
additive EARS-form structure for `acceptance_checks[]`, gated on the consumer
project having adopted ESL (`ESL_VERSION` / `mcp__tonberry__*` present). Neither
is present in this installation, so this spec uses the plain GIVEN/WHEN/THEN
form throughout, per `skills/planning.md`'s explicit guidance — EARS is skipped
by design, not by oversight.

---

## 7. Security Risk Register

**Severity scale:** **Critical** = exploitable without special preconditions,
leads to authentication bypass or full account takeover · **High** =
exploitable with a limited precondition (e.g. requires a specific
misconfiguration or targeted timing), significant impact · **Medium** =
requires a meaningful precondition or has bounded/contained impact · **Low** =
defense-in-depth, operational, or availability-class concern rather than a
direct compromise path.

| ID | Risk | Severity | Description | Mitigation | Owning Story |
|---|---|---|---|---|---|
| R-1 | XML Signature Wrapping (XSW) | **Critical** | An attacker adds a forged/duplicated Assertion alongside a validly signed one; a naive validator checks "a signature exists" rather than "the signature covers the exact element being processed," letting the forged content through. | Use a vetted library with documented XSW hardening; validate signature binds to the specific Assertion ID processed; run an automated adversarial XSW test suite pre-launch and in CI. | S-5, S-12 |
| R-2 | SAMLResponse / Assertion replay | **High** | A captured valid response is resubmitted to authenticate again. | `InResponseTo` tracked server-side, single-use, short TTL, consumed atomically; `NotBefore`/`NotOnOrAfter` enforced with minimal clock-skew tolerance. | S-5 |
| R-3 | Email-claim account takeover ("email confusion") | **Critical** | An attacker who controls or compromises an IdP (or exploits a misconfigured one) asserts a victim's email address and is auto-linked to the victim's existing account. | Never auto-link on email match alone; require step-up re-authentication with the existing local credential before creating the link; tenant-scoped matching only (never cross-tenant). | S-7, S-9 |
| R-4 | IdP-initiated login CSRF / unsolicited-assertion abuse | **Medium** | Without a prior AuthnRequest to correlate against, IdP-initiated flows are more exposed to crafted or misdirected assertions. | Disabled by default per tenant; when enabled, strict Issuer/tenant-binding + freshness checks in place of `InResponseTo` correlation. | S-10 |
| R-5 | Session fixation across the auth boundary | **High** | Reusing a pre-authentication session identifier after SSO login could let an attacker who fixed that identifier inherit the authenticated session. | Always mint a brand-new session on SAML success via the same path as password login; never reuse or "upgrade" a pre-auth identifier. | S-6 |
| R-6 | Certificate/metadata staleness (spoofing or outage) | **Medium** | An expired or rotated-without-warning IdP certificate either breaks login (availability) or, if handled carelessly during rotation, creates a window where validation logic is inconsistent. | Expiry alerting at 30/14/3 days; dual-cert grace-window rotation procedure. | S-11 |
| R-7 | SSO-enforcement bypass ("downgrade" via password login) | **High** | If enforcement is only a UI-level hide-the-password-field behavior, an attacker (or confused user) can still authenticate with a password directly against the API on a domain that's supposed to require SSO. | Server-side enforcement check on every password-login attempt, not merely UI gating. | S-3 |
| R-8 | Over-trusting IdP-asserted attributes for authorization | **Medium** | If group/role attributes from the IdP were used to grant privilege, a misconfigured attribute mapping (or a compromised IdP) could silently escalate privilege. | Out of scope for v1 by design (§3.4): SAML governs authentication only; no automatic role/privilege mapping from IdP attributes. | Scope decision (§3.4), revisit as its own reviewed feature if needed |
| R-9 | Missing SAML Single Logout (SLO) | **Low** | Local logout only clears the internal session; the user's session at the IdP may remain active, so a subsequent login attempt may silently re-authenticate via SSO. | Accepted risk for v1 — documented as an explicit scope exclusion (§3.4), not a vulnerability that grants unauthorized access, purely a UX nuance. Revisit if support volume indicates real confusion. | Deferred (§3.4) |
| R-10 | Break-glass lockout | **Medium** | If SSO enforcement can be enabled with no non-SSO recovery path, an IdP outage or misconfiguration can lock out all admins simultaneously. | Break-glass admin account/procedure required to exist before `sso_enforced` can be enabled for any tenant (hard dependency, not advisory). | S-3 |

**Adversarial layer note (Test phase, §7 cross-reference):** every Critical
and High item above (R-1, R-2, R-3, R-5, R-7) has a corresponding automated
test requirement in S-5, S-7, S-9, or S-12 — this register is not a narrative
document sitting apart from the implementation plan; each row is traceable to
a story with a concrete, testable acceptance criterion.

---

## 8. Rollout Strategy

**Principle:** dual-run old and new authentication throughout; no phase
removes password login as a fallback option (except the deliberate, opt-in,
per-tenant `sso_enforced` case in S-3, which itself preserves a break-glass
path). Every phase has a measurable exit gate and an explicit rollback
trigger tied to S-13's kill switch.

| Phase | Scope | Entry Criteria | Exit Criteria (advance to next phase) | Rollback Trigger |
|---|---|---|---|---|
| **Phase 0 — Internal dogfood** | Internal test tenant only, feature-flagged (S-13) | F-1 through F-4 stories complete; S-12 adversarial suite passing | ≥2 weeks of internal usage with zero validation-integrity failures (R-1/R-2/R-3 classes); dashboards (S-14) live and readable | Any Critical/High-severity finding in S-12 → halt, fix, re-run suite before proceeding |
| **Phase 1 — Design-partner beta** | 2–3 named enterprise design-partner tenants (identified by Enterprise Sales/CS, §3.6), opt-in, feature-flagged per tenant | Phase 0 exit criteria met; design partners confirmed and IdP connections configured (S-1) | ≥4 weeks; SAML validation-failure rate for false rejections (legitimate users blocked) below an agreed operational threshold; at least one full identity-linking case (S-7) and one JIT case (S-8) observed and correct in production | Validation-failure spike, a single confirmed R-3-class near-miss, or a design-partner-reported lockout → trip kill switch (S-13), investigate before resuming |
| **Phase 2 — General availability (opt-in)** | All tenants may self-request SAML connection setup (support-assisted per §3.4, not self-service UI in v1) | Phase 1 exit criteria met; AppSec sign-off on S-12 results recorded (§3.6) | Adoption and health metrics (S-14) stable across a broader tenant set for an agreed observation window | Same triggers as Phase 1, evaluated at wider scale; any newly-discovered Critical/High risk not in §7's register → halt GA expansion, return to Explore/Refine for that specific gap |
| **Phase 3 — SSO enforcement available** | Tenants may opt into `sso_enforced` (S-3) | Phase 2 stable; S-3's break-glass procedure verified in a live drill (not just designed) | Enforcement in production for at least one design-partner tenant with no lockout incidents over an agreed window | Any break-glass failure or lockout report → immediately disable `sso_enforced` for the affected tenant (does not require the global kill switch — per-tenant reversible) |

**Cross-cutting rollout mechanics:**

- **Kill switch (S-13):** trips at any phase; restores password-only login
  globally without a deploy. The one caveat: SSO-only/JIT-provisioned
  accounts (§6.3, S-8) that never had a local password cannot log in via
  password until they complete a password-reset flow — this is a known,
  accepted, and communicated limitation of the fallback path, not a gap in
  the kill switch design.
- **Comms:** downstream/session-consuming service owners (§3.6) are notified
  before Phase 0, not because they need to act, but because the mission's
  invariant (§3.1) is a claim worth letting them independently verify.
- **Metrics-driven, not calendar-driven:** every phase transition above is
  gated on the stated exit criteria, not a fixed date — consistent with the
  Process Reward test layer (§9) principle that each step should
  demonstrably reduce risk before the next one starts.

---

## 9. T — TEST (6-Layer Verification)

| # | Layer | Assessment | Status |
|---|---|---|---|
| 1 | **Structural** | Hierarchy intact (Theme→Project→Feature→Story); all 15 stories independently deliverable in the Construct dependency graph; no orphaned tasks — every story maps to a Feature and every Feature to the one Project. | ✓ Pass |
| 2 | **Self-Consistency** | Three alternative decompositions were considered: (Alt A) organize by security-boundary bands (perimeter / broker / session / observability) instead of feature area; (Alt B) organize by user-journey stage (tenant setup → login → post-auth linking → admin ops); (Alt C) organize by owning team (platform-auth vs. security vs. session-service). All three alternative groupings converge on the same underlying set of ~15 atomic units of work — they differ in *grouping label*, not in *what work exists or which stories depend on which*. Estimated overlap ≈ 75%. | ✓ Pass — 75% ≥ 70% HIGH-confidence threshold |
| 3 | **Dependency** | All affected surfaces identified: auth/login controller, session-issuance call site (read-only reference, not modified), new tables (`saml_connections`, `sso_identities`), tenant-admin surface, CI pipeline (S-12), scheduled jobs (S-11), feature-flag config (S-13), metrics/dashboards (S-14). Migration paths defined for both new tables. File paths are given as generic placeholders (no real repo present, per §4) — **flagged**: must be validated against the actual project structure once one exists. | ✓ Pass, with one flagged caveat (generic paths — see Refine Cycle 1) |
| 4 | **Constraint** | NFRs addressed: security (§7, mapped per-story), backward compatibility (§3.1, S-6), timeboxes all ≤5d (S-5 is the longest at ≤5d, appropriately for the highest-risk story), no story exceeds the 8-day ceiling. Security/compliance implications explicitly addressed (§7); two compliance-adjacent items (JIT provisioning legal sign-off, IdP metadata data-residency) are correctly *not* silently assumed away — see §9's Open Flags below. | ✓ Pass |
| 5 | **Process Reward** | Ordering reduces risk progressively: F-1 (config) → F-2 (auth flow, gated by the highest-risk story S-5 early) → F-3 (linking, builds on a validated session bridge) → F-4 (hardening, closes remaining gaps before any real rollout) → F-5 (rollout itself, last). S-3's break-glass safeguard is explicitly sequenced *before* any tenant may enable enforcement — this is a deliberate ordering choice, not an oversight. | ✓ Pass |
| 6 | **Adversarial** | See the Failure Taxonomy pass immediately below. | ✓ Pass, with tracked gaps folded into Refine (below) and Open Flags (§9 Confidence section) |

**Failure Taxonomy checklist (Adversarial layer, `templates/scoring.md`):**

- **Under-specification** — would an executor need to ask questions? The
  identity-linking decision tree (§6.3) and security validation checklist
  (S-5) are concrete enough to implement without further clarification;
  remaining true unknowns (IdP vendor, legal sign-off) are explicitly named
  as Open Flags rather than silently left under-specified.
- **Over-specification** — are valid implementations blocked by rigid
  constraints? No; the design deliberately keeps the SSO-abstraction choice
  (H2) as "adopt a vetted third-party layer" rather than naming one specific
  vendor, leaving room for procurement/vendor-selection latitude.
- **Dependency blindness** — S-3 → S-1/S-2, S-6 → S-5, S-7/S-8 → S-6, S-12 →
  S-5/S-7/S-10, S-15 → nearly everything: dependency chain is explicit
  throughout §6, not implicit.
- **Assumption drift** — the eight assumptions in §3.5 are each paired with
  a stated risk-if-wrong and, where relevant, a story-level consequence
  (e.g. A-3 → S-8's default-off framing), so a wrong assumption has a
  defined blast radius rather than silently invalidating downstream stories.
- **Scope creep** — SLO, SCIM, OIDC, self-service config UI, and
  attribute-based authZ are explicitly named Out of Scope/Deferred (§3.4),
  not silently absorbed into the 15 stories above.
- **Premature optimization** — H3 (build a full custom IdP) was explicitly
  rejected as over-scoped for the stated need (§5.4); complexity is matched
  to the actual ask.
- **Stale context** — not directly applicable (no existing codebase state to
  go stale against in this installation); flagged instead as "generic paths
  must be validated against the real project structure" in layer 3 above.

**Gate result:** No fundamental issues; two **minor gaps** were carried into
Refine (Cycle 1) below, consistent with "1–2 minor gaps → Refine (1 cycle)."

---

## 10. R — REFINE

| Cycle | Diagnosis | Prescription | Applied |
|---|---|---|---|
| **1** | Test-phase Dependency layer flagged that file paths are generic placeholders (no real repo present); the initial draft also under-specified two things: (a) what stops an admin from enabling `sso_enforced` before a break-glass path exists, and (b) how a certificate rotation avoids a hard-cutover outage. | (a) Added the explicit hard-dependency block in S-3 ("enable operation is blocked" if no break-glass procedure exists); (b) added S-11's dual-cert grace-window mechanism. Both are now first-class acceptance criteria, not narrative asides. | Yes — reflected in the S-3 and S-11 text above. |
| **2** | Remaining confidence gap traced to genuinely external unknowns — which IdP vendor(s) must be supported (affects H2's specific integration effort), whether JIT auto-provisioning has legal/compliance sign-off (A-3), and IdP-metadata data-residency requirements — none of which can be resolved by additional internal reasoning or another drafting pass; they require a human decision. **Diminishing returns rule invoked**: a third refinement cycle would not close these gaps (expected mean-score improvement < 0.3 on the 1–5 scale) because the gaps are informational, not structural or editorial. | Rather than burn a third cycle rewriting already-solid content, the gaps are surfaced explicitly as **Open Flags for Human Review** in §9's Confidence Report, which is the correct methodology-prescribed outcome for a genuinely external unknown (Confidence 70–84% → VALIDATE: "deliver with flags, human reviews"). | Yes — halted per the diminishing-returns rule; not a 3rd cycle. |

**Refinement log (1–5 self-critique dimensions, target ≥4):**

| Dimension | Cycle 0 (pre-refine) | After Cycle 1 | After Cycle 2 |
|---|---|---|---|
| Clarity | 3 | 4 | 4 |
| Completeness | 3 | 4 | 4 |
| Actionability | 3 | 4 | 4 |
| Efficiency | 4 | 4 | 4 |
| Testability | 3 | 4 | 5 |

No dimension decreased between cycles (no oscillation detected). All
dimensions reached the ≥4 target by Cycle 1; Cycle 2's only change was a
tightening of acceptance-criteria phrasing (Testability 4→5), confirming the
diminishing-returns call was correct — the remaining gap genuinely lives in
external unknowns, not in the quality of this document.

**Important distinction:** Refine's 1–5 critique measures the *quality of
this document's writing and structure*; it is not the same measurement as
Assemble's confidence formula below, which measures *decision-certainty
against unresolved external unknowns*. A spec can legitimately score ≥4 on
every Refine dimension (this one does) while still landing at VALIDATE rather
than AUTO_PROCEED on the Assemble gate — that is not a contradiction, it is
two different questions being asked and answered honestly.

---

## 11. A — ASSEMBLE

### 9. Confidence Report

| Factor | Score (0–3) | Rationale |
|---|---|---|
| Pattern Match | 3/3 | SP-initiated SAML with edge-validated, session-bridged identity is an extremely well-established SaaS pattern (§4, §5.3). |
| Requirement Clarity | 2/3 | Core architecture and security requirements are unambiguous; however, IdP vendor choice, legal sign-off on JIT provisioning, and data-residency requirements remain genuinely unresolved (§3.5, §9 Open Flags). |
| Decomposition Stability | 2/3 | Self-consistency check (§9 layer 2) found ≈75% overlap across three alternative decompositions — solidly in the "HIGH confidence, decomposition stable" band, but short of a clean 3/3 given the real build-vs-buy branch point still open (H1 fallback, §5.4). |
| Constraint Compliance | 3/3 | All 6 verification layers passed (§9); every Critical/High security risk is mapped to a testable story (§7); no timebox exceeds the ceiling; hierarchy uses Project, not Epic. |

**Formula:** `(3 + 2 + 2 + 3) / 12 × 100 = 83%`

**Weighted Confidence: 83%**
**Decision: VALIDATE — deliver with flags, human review required before `in_progress` work begins.**

This is a deliberate, honest landing point, not a shortfall: §3.2 already
flagged this project at 12/12 complexity, the threshold at which the
methodology itself recommends human collaboration. VALIDATE is the correct
terminal state for "decision-ready but not yet rubber-stamped" — the spec is
complete and actionable; a small, named set of decisions needs a human
before execution starts.

**Open Flags for Human Review (the actual content of the "flags" in
VALIDATE):**

1. **IdP vendor scope** — which specific identity providers must be
   supported at launch (Okta, Azure AD/Entra ID, OneLogin, Ping, Google
   Workspace, others)? Affects H2's integration/testing surface, not the
   architecture.
2. **JIT provisioning legal sign-off (A-3)** — confirm whether
   auto-creating accounts from IdP-asserted attributes is acceptable under
   current data-handling/consent policy before defaulting it on for any
   tenant (S-8).
3. **IdP metadata / data-residency** — confirm where `saml_connections`
   data (including IdP certificates and metadata) may be stored relative to
   any regional data-residency commitments made to specific customers.
4. **Break-glass account status (A-4)** — confirm whether a non-SSO admin
   recovery path already exists today or must be newly created as part of
   S-3; this gates whether S-3 is "wire up an enforcement check" or
   "wire up an enforcement check *and* stand up a new recovery mechanism."
5. **SLO deferral (R-9)** — confirm Product/Support are comfortable
   shipping without SAML Single Logout at GA, given the documented UX
   nuance.

### Deliverables (this document, single-file per delivery constraint)

Per SPECTRA's Output Discipline, an Assemble delivery normally produces four
artifacts as separate files under `.spectra/` (Markdown spec, YAML agent
handoff, JSON state machine, and — because `ECL_VERSION` (2.0) is present in
this install root — a `.envelope.json` ECL sidecar). This delivery's harness
constrains output to a single file at an externally-specified path outside
`.spectra/`, so all four artifacts are embedded below as self-contained
sections of this one document rather than as sibling files. The Markdown
spec content is defined as everything from the document title (§ "SAML
Single Sign-On Integration — Decision-Ready Specification") through the end
of this Confidence Report — i.e., sections 0 through 11 up to this point —
and is the byte range over which the embedded ECL envelope's integrity digest
below is computed.

#### 11.1 Agent Handoff (YAML)

```yaml
metadata:
  spec_id: "SPEC-2026-07-05-saml-sso"
  confidence: 83
  complexity: 12
  spectra_version: "4.11.0"

projects:
  - id: "P-1"
    name: "SAML SSO Integration"
    features:
      - id: "F-1"
        name: "Tenant SAML Connection Management"
        stories:
          - id: "S-1"
            title: "Tenant SAML connection configuration"
            timebox: "≤3d"
            risk: "P1"
            action_plan:
              - verb: "Create"
                target: "saml_connections table + admin config operation"
              - verb: "Test"
                target: "metadata validation, duplicate-connection rejection"
            acceptance_criteria:
              - given: "well-formed IdP metadata submitted for a tenant"
                when: "admin submits it"
                then: "a draft saml_connections row is created with required fields populated"
            agent_hints:
              recommended_class: "builder"
              context_files: ["db/migrations/*_create_saml_connections.*", "app/admin/saml_connections"]
              validation_gates: { p1: "checked", coverage: "malformed-metadata cases tested" }
          - id: "S-2"
            title: "Tenant discovery / SSO login routing"
            timebox: "≤2d"
            risk: "P1"
            dependencies: ["S-1"]
            agent_hints:
              recommended_class: "builder"
              context_files: ["login controller", "tenant lookup service"]
          - id: "S-3"
            title: "SSO enforcement toggle + break-glass admin safeguard"
            timebox: "≤2d"
            risk: "P0"
            dependencies: ["S-1", "S-2"]
            agent_hints:
              recommended_class: "reasoner"
              context_files: ["password auth handler", "tenant policy service"]
      - id: "F-2"
        name: "SP-Initiated SAML Authentication Flow"
        stories:
          - id: "S-4"
            title: "Generate signed AuthnRequest (Redirect binding)"
            timebox: "≤2d"
            risk: "P1"
            dependencies: ["S-1", "S-2"]
          - id: "S-5"
            title: "ACS endpoint — validate SAMLResponse"
            timebox: "≤5d"
            risk: "P0"
            dependencies: ["S-4"]
            agent_hints:
              recommended_class: "reasoner"
              validation_gates: { p0: "checked", coverage: "adversarial XSW/replay/audience suite required" }
          - id: "S-6"
            title: "Session bridging into the existing session model"
            timebox: "≤2d"
            risk: "P0"
            dependencies: ["S-5"]
      - id: "F-3"
        name: "Identity Linking & Provisioning"
        stories:
          - id: "S-7"
            title: "Existing-account linking with step-up confirmation"
            timebox: "≤3d"
            risk: "P0"
            dependencies: ["S-6"]
          - id: "S-8"
            title: "JIT provisioning for net-new SSO users"
            timebox: "≤3d"
            risk: "P1"
            dependencies: ["S-6"]
          - id: "S-9"
            title: "Identity-linking conflict handling"
            timebox: "≤2d"
            risk: "P1"
            dependencies: ["S-7", "S-8"]
      - id: "F-4"
        name: "Security Hardening & Abuse Prevention"
        stories:
          - id: "S-10"
            title: "IdP-initiated flow support (optional, off by default)"
            timebox: "≤2d"
            risk: "P1"
            dependencies: ["S-5"]
          - id: "S-11"
            title: "Certificate rotation workflow + expiry alerting"
            timebox: "≤2d"
            risk: "P1"
            dependencies: ["S-1"]
          - id: "S-12"
            title: "Adversarial security review pass"
            timebox: "≤3d"
            risk: "P0"
            dependencies: ["S-5", "S-7", "S-10"]
      - id: "F-5"
        name: "Rollout, Observability & Rollback"
        stories:
          - id: "S-13"
            title: "Feature-flag gating per tenant + kill switch"
            timebox: "≤1d"
            risk: "P0"
            dependencies: ["S-6"]
          - id: "S-14"
            title: "Auth funnel observability"
            timebox: "≤2d"
            risk: "P1"
            dependencies: ["S-6", "S-7", "S-8"]
          - id: "S-15"
            title: "Staged rollout execution"
            timebox: "≤3d"
            risk: "P0"
            dependencies: ["S-3", "S-12", "S-13", "S-14"]

execution_plan:
  phases:
    - name: "Foundation (config + flow)"
      stories: ["S-1", "S-2", "S-3", "S-4", "S-5", "S-6"]
      agent_class: "reasoner"
    - name: "Identity linking"
      stories: ["S-7", "S-8", "S-9"]
      agent_class: "reasoner"
    - name: "Hardening"
      stories: ["S-10", "S-11", "S-12"]
      agent_class: "reviewer"
    - name: "Rollout"
      stories: ["S-13", "S-14", "S-15"]
      agent_class: "orchestrator"
```

#### 11.2 State Machine (JSON)

```json
{
  "session_id": "019f33bf-ea11-71ec-984d-fb982b6b0201",
  "spec_id": "SPEC-2026-07-05-saml-sso",
  "goal": "Add SAML SSO to an application with existing email/password auth and a session model other services depend on, covering identity linking, security risk, rollout, and acceptance criteria.",
  "spectra_version": "4.11.0",
  "steps": [
    { "id": 1, "story_id": "S-1", "title": "Tenant SAML connection configuration", "status": "pending", "dependencies": [], "files_affected": ["db/migrations/*_create_saml_connections.*", "app/admin/saml_connections"], "verification_command": "run S-1 unit tests: metadata validation + duplicate rejection", "estimated_timebox": "≤3d", "replanning_notes": null },
    { "id": 2, "story_id": "S-2", "title": "Tenant discovery / SSO login routing", "status": "pending", "dependencies": ["S-1"], "files_affected": ["login controller", "tenant lookup service"], "verification_command": "run S-2 routing tests", "estimated_timebox": "≤2d", "replanning_notes": null },
    { "id": 3, "story_id": "S-3", "title": "SSO enforcement + break-glass safeguard", "status": "pending", "dependencies": ["S-1", "S-2"], "files_affected": ["password auth handler", "tenant policy service"], "verification_command": "run S-3 server-side enforcement + break-glass tests", "estimated_timebox": "≤2d", "replanning_notes": null },
    { "id": 4, "story_id": "S-4", "title": "Generate signed AuthnRequest", "status": "pending", "dependencies": ["S-1", "S-2"], "files_affected": ["SAML SP integration module"], "verification_command": "run S-4 request-ID TTL tests", "estimated_timebox": "≤2d", "replanning_notes": null },
    { "id": 5, "story_id": "S-5", "title": "ACS endpoint — validate SAMLResponse", "status": "pending", "dependencies": ["S-4"], "files_affected": ["ACS endpoint handler"], "verification_command": "run adversarial XSW/replay/audience suite (feeds S-12)", "estimated_timebox": "≤5d", "replanning_notes": null },
    { "id": 6, "story_id": "S-6", "title": "Session bridging", "status": "pending", "dependencies": ["S-5"], "files_affected": ["SAML SP integration module", "session-issuance service (call site only)"], "verification_command": "run downstream-service session contract test", "estimated_timebox": "≤2d", "replanning_notes": null },
    { "id": 7, "story_id": "S-7", "title": "Existing-account linking with step-up confirmation", "status": "pending", "dependencies": ["S-6"], "files_affected": ["identity-resolution service"], "verification_command": "run email-collision + step-up tests", "estimated_timebox": "≤3d", "replanning_notes": null },
    { "id": 8, "story_id": "S-8", "title": "JIT provisioning", "status": "pending", "dependencies": ["S-6"], "files_affected": ["identity-resolution service", "tenant policy config"], "verification_command": "run JIT allowed/disallowed tests", "estimated_timebox": "≤3d", "replanning_notes": null },
    { "id": 9, "story_id": "S-9", "title": "Identity-linking conflict handling", "status": "pending", "dependencies": ["S-7", "S-8"], "files_affected": ["identity-resolution service"], "verification_command": "run conflict-case test matrix", "estimated_timebox": "≤2d", "replanning_notes": null },
    { "id": 10, "story_id": "S-10", "title": "IdP-initiated flow support", "status": "pending", "dependencies": ["S-5"], "files_affected": ["ACS endpoint handler"], "verification_command": "run default-off + opt-in unsolicited-response tests", "estimated_timebox": "≤2d", "replanning_notes": null },
    { "id": 11, "story_id": "S-11", "title": "Certificate rotation + expiry alerting", "status": "pending", "dependencies": ["S-1"], "files_affected": ["scheduled job", "saml_connections.rotated_at"], "verification_command": "run expiry-threshold + dual-cert-window tests", "estimated_timebox": "≤2d", "replanning_notes": null },
    { "id": 12, "story_id": "S-12", "title": "Adversarial security review pass", "status": "pending", "dependencies": ["S-5", "S-7", "S-10"], "files_affected": ["security test suite", "CI pipeline config"], "verification_command": "run full Security Risk Register test mapping (§7)", "estimated_timebox": "≤3d", "replanning_notes": null },
    { "id": 13, "story_id": "S-13", "title": "Feature-flag gating + kill switch", "status": "pending", "dependencies": ["S-6"], "files_affected": ["feature-flag config", "ACS endpoint entry check"], "verification_command": "run kill-switch runtime-toggle test", "estimated_timebox": "≤1d", "replanning_notes": null },
    { "id": 14, "story_id": "S-14", "title": "Auth funnel observability", "status": "pending", "dependencies": ["S-6", "S-7", "S-8"], "files_affected": ["metrics emission at S-5/S-7/S-8"], "verification_command": "verify reason-code coverage", "estimated_timebox": "≤2d", "replanning_notes": null },
    { "id": 15, "story_id": "S-15", "title": "Staged rollout execution", "status": "pending", "dependencies": ["S-3", "S-12", "S-13", "S-14"], "files_affected": ["rollout runbook", "phase-gate checklist"], "verification_command": "verify phase-gate exit criteria per §8", "estimated_timebox": "≤3d", "replanning_notes": null }
  ],
  "current_step": 0,
  "completed_steps": [],
  "replanning_history": [
    { "cycle": 1, "trigger": "Test-phase Dependency layer flagged missing break-glass hard-dependency and cert-rotation outage handling", "action": "patched S-3 and S-11" },
    { "cycle": 2, "trigger": "Confidence <85% traced to external unknowns (IdP vendor, legal sign-off, data residency)", "action": "diminishing-returns rule invoked; gaps surfaced as Open Flags rather than a 3rd rewrite cycle" }
  ]
}
```

#### 11.3 ECL Envelope (v2.0 sidecar, embedded)

```json
{
  "envelope_version": "2.0",
  "message_id": "019f33bf-ea11-7a07-9cb5-a3c46d6ebf09",
  "thread_id": "019f33bf-ea11-71ec-984d-fb982b6b0201",
  "parent_id": null,
  "from": { "eidolon": "spectra", "version": "4.11.0" },
  "to": { "eidolon": "apivr", "version": "n/a" },
  "performative": "PROPOSE",
  "edge_origin": "roster",
  "objective": "Propose implementation spec for SAML SSO integration (identity linking, security hardening, phased rollout) targeting the primary application and its session-dependent services.",
  "artifact": {
    "kind": "spec",
    "schema_version": "1.0",
    "path": "AB-H2-spectra-r1.out.md",
    "sha256": "ab9da259fe8d784eb98a563b06b49585ced39b015e19e0d97dea351a78c298e1",
    "size_bytes": 74814
  },
  "context_delta": {
    "token_budget": 6000,
    "tokens_used": 0,
    "input_handles": [],
    "summary": "Full SPECTRA-cycle specification for adding SAML SSO to an existing email/password app whose session model is depended on by other services. Selects a third-party SSO-abstraction architecture (H2) that bridges into the existing session-issuance path unchanged; specifies tenant-scoped identity linking with mandatory step-up confirmation to prevent email-claim account takeover; enumerates 10 security risks with severity and per-story mitigations; defines a 4-phase rollout with metrics-gated advancement and a kill switch; documents 3 rejected alternatives. Delivered at 83% confidence (VALIDATE) with 5 named Open Flags for human sign-off before execution."
  },
  "constraints": { "trust_level": "standard" },
  "ise": {
    "assertion_grade": "self-attested",
    "provenance": {
      "methodology_version": "spectra-4.11.0",
      "tool_surface": ["Read", "Grep", "Glob", "Bash"],
      "lateral_consults": []
    },
    "receiver_authorization": { "auto_route": true, "auto_merge": false, "auto_deploy": false }
  },
  "confidence": 0.83,
  "integrity": {
    "method": "sha256",
    "value": "ab9da259fe8d784eb98a563b06b49585ced39b015e19e0d97dea351a78c298e1"
  },
  "trace": {
    "ts": "2026-07-05T19:27:14Z",
    "host": "claude-code",
    "model": "claude-sonnet-5",
    "tier": "standard"
  },
  "x_spectra_comment": "Embedded per-delivery constraint (single-file output required by the invoking harness); see §11 preamble for the exact byte range the integrity digest covers, and DR-09 (self-attested, decision-ready not externally verified) for the ise.assertion_grade rationale."
}
```

**CRYSTALIUM ingest / session_end:** `mcp__crystalium__*` tools are not
present in this session (§4). Per the graceful-skip contract, the `ingest`
and `session_end` calls that would normally follow Assemble are silently
skipped — Assemble is still marked complete per `skills/planning.md`'s
explicit instruction that absent CRYSTALIUM never blocks completion.

**verify-incoming skill:** not applicable to this session — SPECTRA is
producing an outbound spec here, not consuming an inbound artefact with a
sibling `.envelope.json`, so the receiver-side integrity gate in
`skills/verify-incoming.md` has no trigger condition to check against.

---

## Methodology Compliance Checklist (Preflight, `SPEC.md`)

- [x] CLARIFY ran (§2)
- [x] `spectra-conventions.md` checked — absent, generic defaults used and documented (§2, §4)
- [x] Complexity scored (12/12), reasoning budget routed to Extended (§3.2)
- [x] 4 genuinely distinct hypotheses explored, diversity mix satisfied (§5.2)
- [x] All 15 stories pass INVEST
- [x] All timeboxes valid (≤5d max, no story points)
- [x] Hierarchy uses Project (not "Epic")
- [x] Acceptance criteria in GIVEN/WHEN/THEN throughout (§6, §6.6)
- [x] Agent hints with context files per story
- [x] Dual output: Markdown + structured data (YAML §11.1, JSON §11.2) — embedded per single-file delivery constraint, not as sibling files
- [x] Confidence score present with factor breakdown (§9/§11)
- [x] Plan delivered as a persisted artifact at the harness-specified path (not an ephemeral chat message)
- [x] No code produced — plans only
- [x] Rejected alternatives documented (§5.4 — three, mission required at least one)
- [x] ECL v2.0 envelope emitted (ECL_VERSION present in install root) — embedded per single-file constraint (§11.3)

*SPECTRA — Strategic Specification through Deliberate Reasoning*
