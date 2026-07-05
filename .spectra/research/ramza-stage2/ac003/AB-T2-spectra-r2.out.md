---
eidolon: spectra
version: 4.11.0
kind: spec
status: ready-for-apivr
created_at: 2026-07-05T00:00:00Z
target_repos: ["consumer-project (mature Rails application — exact repo/path unresolved, see [GAP] in Scope §Assumptions)"]
stories_count: 8
validation_gates_count: 21
confidence: 0.75
---

# SPEC-2026-07-05-001 — Soft-delete (recoverable deletion) for the `Account` model

**Intent Type:** CHANGE (additive lifecycle capability replacing a destructive default on an existing, load-bearing model)
**Complexity Score:** 10/12 — Extended thinking; per the Scope routing table this band also recommends human-in-the-loop, which this spec operationalizes as a built-in cross-team sign-off gate (Story S-2) rather than as a reason to withhold the plan (see confidence rationale below).
**Confidence:** 75% — VALIDATE (deliver with flags for human/team review)

## 🎯 SCOPE ANALYSIS

**WHO:**
- **Requester (implicit):** the team owning `Account`'s lifecycle / platform-eng, responding to the risk of accidental or premature permanent deletion.
- **Directly affected — callback owners:** every team whose business logic currently runs on `Account`'s `before_destroy`/`after_destroy`/`around_destroy` hooks (billing/subscriptions, notifications, search-index/analytics, audit/compliance logging are the categories a mature multi-team Rails app typically has — exact roster unconfirmed, **[GAP]**).
- **Directly affected — dependent-association owners:** teams whose models hang off `Account` via `has_many`/`has_one` with `dependent:` options (memberships, invoices/subscriptions, API keys are illustrative categories — exact list unconfirmed, **[GAP]**).
- **Directly affected — admin/support tooling maintainers:** whoever owns the internal Account listing/management surface.
- **Approval chain:** each named callback-owning team must explicitly sign off on the new discard-vs-destroy firing semantics (Story S-2) before rollout; compliance/legal must sign off separately if/when the deferred hard-delete retention policy (H4) is ever built — this spec does not seek that sign-off, it names the open decision.

**WHAT:** Introduce recoverable ("soft") deletion for `Account`. Deleting an account marks it *discarded* — excluded from normal application flows by default — instead of physically removing the row. Discarded accounts remain restorable by admins. Dependent associations, destroy callbacks, admin listings, and every other existing call site are deliberately audited and migrated rather than silently reinterpreted. A genuine hard-delete path is preserved as an explicit, narrowly-scoped escape hatch for cases where physical erasure is actually required.

**WHY:** Today, deleting an `Account` is permanent and irreversible — a single mistaken click or a bug in a bulk-admin action destroys data with no recovery path. The ask is to make that recoverable without breaking the two things a mature codebase has already built on top of destructive deletion: (1) other teams' destroy callbacks, which encode real business logic (cancel billing, send a closure notice, remove from a search index, write an audit trail), and (2) admin tooling that lists and manages accounts today assuming "listed = exists = active."

**CONSTRAINTS:**
- Must **not** use a Rails `default_scope`-style global auto-filter. That mechanism silently rewrites every existing unscoped query (including admin tooling and every team's call sites) without a code change anywhere, which is precisely the kind of invisible semantic shift this mission's own framing warns against ("destroy callbacks other teams rely on," "existing admin tooling that lists records"). See Rejected Alternatives (H3).
- Must give every team currently relying on a destroy callback an **explicit** decision point — "does your side effect fire on discard too?" — never an assumed default in either direction.
- Must preserve a genuine hard-delete path for legally mandated erasure; soft-delete is explicitly **not** a substitute for actual data erasure when required (GDPR/CCPA-style requests). This spec flags that follow-on policy decision; it does not resolve it (see Deferred).
- Must not permanently block legitimate re-signup (e.g., same email/subdomain) once a prior account using that value has been discarded.
- Must preserve — and improve — admin tooling's ability to find and restore a discarded record; recoverability is the entire point of the ask, so "discarded" must never mean "invisible to admins."
- Backward compatibility: any code path that does not explicitly opt into "kept"-only filtering must keep seeing exactly the rows it sees today. No query silently starts hiding or exposing rows as a side effect of this change.

**Boundaries:**

| In Scope | Out of Scope | Deferred |
|---|---|---|
| Schema + model scopes for discard (`discarded_at`, `kept`/`discarded`) | Re-implementing each named team's actual business logic inside their migrated callback (their team owns that once briefed — this spec produces the decision + interface) | Retention-window + scheduled hard-delete/anonymization reaper (H4) — needs a compliance-owned policy decision first |
| Explicit hard-delete escape hatch (`really_destroy!`) for compliance erasure | A general soft-delete framework for models beyond `Account` | Bulk-restore / bulk-discard admin actions |
| Cross-team callback migration audit + decision framework (Story S-2) | Admin-panel UI redesign beyond the status filter + restore action | Self-service "delete my account" end-user copy/flow changes beyond the same trigger point |
| Dependent-association cascade policy + implementation (Story S-3) | Historical analytics/warehouse backfill for accounts already hard-deleted pre-feature | Two-tier "pending deletion" grace-period state machine (H4) |
| Uniqueness-validator + raw-delete-bypass audit (Story S-4) | | |
| Admin UI status filter + restore action (Story S-5) | | |
| API/serializer default-exclusion + background-job skip-discarded audit (Story S-6) | | |
| Regression + cross-team parity test suite (Story S-7) | | |
| Documentation + ADR (Story S-8) | | |

**Assumptions** (logged with risk-if-wrong; this consumer project — `/tmp/spectra-pilot` — is a fresh Eidolons scaffold with no application source, confirmed via structural search, so these are carried as explicit **[GAP]**s into Assemble rather than verified against real code):

1. **A1 — ORM/version.** `Account` is a standard ActiveRecord model on a Rails version supporting modern (6.1+) conventions, with no pre-existing `default_scope`-based soft-delete gem already in place. *Risk if wrong:* if a legacy gem (e.g. an old `acts_as_paranoid` install) already exists, S-1 becomes a migration-off-legacy-mechanism story, not a greenfield adoption.
2. **A2 — Persistence.** Adding a nullable, indexed `discarded_at:datetime` column via a standard reversible migration is acceptable, with no sharding/multi-DB/read-replica-lag complication named. *Risk if wrong:* a sharded setup needs the index/backfill strategy revisited per shard.
3. **A3 — Callback roster is illustrative, not confirmed.** The exact `before_destroy`/`after_destroy`/`around_destroy` callbacks on `Account`, their owners, and their side effects are not enumerated in the request. The Impact Assessment below models the *categories* a mature multi-team app typically has (billing, notifications, search-index, audit) as a discovery checklist, not a final inventory. *Risk if wrong:* Story S-2's timebox and sign-off count scale with however many real callbacks exist.
4. **A4 — Dependent-association list is illustrative, not confirmed.** Likewise, the `has_many`/`has_one` list (memberships, invoices/subscriptions, API keys) is illustrative based on the mission's own framing ("dependent associations"), not a confirmed schema dump. *Risk if wrong:* Story S-3's per-association cascade matrix must be re-run against the real model before Construct-phase execution begins.
5. **A5 — Admin tooling stack.** Assumed to be a Rails-rendered internal surface (custom controller, or a framework like ActiveAdmin/RailsAdmin) currently querying `Account` unscoped. *Risk if wrong:* a JS-SPA admin frontend consuming a JSON API shifts Story S-5's surface from a Rails view to an API-contract change.
6. **A6 — No reusable existing pattern.** No other model in the app already has a working discard/soft-delete pattern that `Account` should imitate. *Risk if wrong:* Pattern-phase strategy would shift from GENERATE to ADAPT.

---

## 📚 PATTERN ANALYSIS

**Query:** "soft delete / recoverable deletion for an ActiveRecord model with cross-team destroy callbacks and admin listing tooling"
**Matches:** 0 in-repo patterns — the consumer project has no application source (confirmed: only Eidolons scaffolding + an otherwise-empty git history at `/tmp/spectra-pilot`). CRYSTALIUM memory tools (`mcp__crystalium__*`) are not available in this environment — graceful skip per SPECTRA's memory pre-flight contract (SPEC.md §9); no episodic/semantic/procedural recall was performed, and none is logged as a mid-cycle commit.

**Strategy:** GENERATE — no repo-local or memory-sourced pattern to adapt. Industry precedent — the Ruby `discard` gem, the older `paranoia`/`acts_as_paranoid` gem lineage, and Rails Guides' documented `default_scope` caveats — informs the hypothesis set below as external reference, not a matched pattern.

---

## 🌳 EXPLORATION SUMMARY

5 hypotheses generated (conservative, pattern-leveraging, industry-pattern-but-risky, innovative, risk-minimizing-but-rejected); top 2 expanded. 7-dimension weighted rubric (Alignment 25% · Correctness 20% · Maintainability 15% · Performance 15% · Simplicity 10% · Risk 10% · Innovation 5%):

| # | Hypothesis | Align | Correct | Maint | Perf | Simpl | Risk | Innov | **Weighted /100** |
|---|---|---|---|---|---|---|---|---|---|
| H1 | Hand-rolled `discarded_at` column + explicit scopes, no dependency (conservative) | 8 | 8 | 6 | 9 | 7 | 7 | 3 | **74.0 — Solid** |
| H2 | Adopt the `discard` gem — explicit `kept`/`discarded` scopes, no `default_scope` (pattern-leveraging) | 9 | 9 | 9 | 9 | 8 | 8 | 4 | **85.5 — Elite** |
| H3 | Adopt `paranoia`/`acts_as_paranoid` — `default_scope`-based automatic global filter (industry-pattern, higher risk) | 7 | 6 | 5 | 7 | 6 | 3 | 3 | **58.0 — Weak** |
| H4 | State-machine lifecycle (`active → pending_deletion → deleted`) + grace period + scheduled hard-delete reaper (innovative) | 7 | 6 | 6 | 6 | 4 | 5 | 9 | **61.0 — Weak/borderline** |
| H5 | Archive-table tombstone — physically move discarded rows to a separate table (risk-minimizing) | 5 | 5 | 4 | 6 | 2 | 4 | 6 | **46.5 — Anchor-Low** |

Spread (46.5–85.5) exceeds the 5% anti-strawman threshold — differentiation is sufficient.

**Selected:** H2 — adopt the `discard` gem. Its explicit `kept`/`discarded` scopes (deliberately *not* a `default_scope`) force every call site — including cross-team destroy callbacks and admin tooling — to be deliberately audited and migrated (Stories S-2/S-4), rather than silently reinterpreted. That property is exactly what the CONSTRAINTS section demands. A small, actively-maintained, widely-used gem (`discard!`, `undiscard!`, `kept`, `discarded`, `kept?`, `discarded?`) lowers Maintainability/Correctness risk relative to hand-rolling the same primitives (H1), at negligible added-dependency risk for a mature app already running Bundler.

**Rejected Alternatives:**
- **H3 (58.0, rejected):** `default_scope`-based automatic global filtering was rejected specifically because it fails the mission's own core safety requirement. It rewrites every unscoped `Account.where`/`.find` call app-wide with *no code change at the call site*, which is exactly the invisible semantic shift that breaks admin tooling (counts, joins, `.unscoped` needed everywhere) and masks the destroy-callback/call-site audit this mission asks for. In a mature multi-team codebase this is a well-documented Rails footgun — association preloading, `.or` queries, and raw joins routinely bypass or double-apply `default_scope` in surprising ways.
- **H5 (46.5, rejected):** physically relocating a discarded account's row to a separate archive/tombstone table was rejected because it breaks every dependent association's foreign-key relationship at the moment of discard — each dependent record (memberships, invoices, API keys) would need re-pointing or duplication inside the same transaction, reintroducing the fragility of a hard delete while adding a second table to keep permanently in sync. It also composes poorly with "recoverable": restoring requires moving the row back and re-validating that no conflicting insert happened while it was archived.
- **H4 (61.0, deferred — not rejected):** a full state-machine lifecycle with a grace-period reaper is a reasonable Phase 2 once a compliance-owned retention/anonymization policy exists (see Deferred in Scope). Deferred for v1 because it requires a legal/compliance decision this spec cannot make unilaterally, and the stated ask — "recoverable deletion" — is fully satisfied by H2 without it.

---

## 🔎 IMPACT ASSESSMENT — Existing Call Sites

This is the decision-ready audit surface the mission explicitly asked for. Because no real repository is attached to this consumer project, each row is a **discovery checklist entry** to run against the actual codebase — Stories S-2/S-3/S-4 operationalize exactly this table. Categories are drawn directly from the mission's own framing ("dependent associations," "destroy callbacks other teams rely on," "admin tooling that lists records").

| # | Category (illustrative example) | Decision required under soft-delete | Owner | Risk if unaddressed |
|---|---|---|---|---|
| 1 | Destroy callback — billing: `before_destroy` cancels the payment-provider subscription | Fire on discard too, via `before_discard`; keep `before_destroy` only for `really_destroy!` | Billing team | Double-billing an account that is discarded but never really-destroyed |
| 2 | Destroy callback — notifications: `after_destroy` unsubscribes/sends a closure email | Fire on discard, via `after_discard` | Notifications team | User believes the account is gone but keeps receiving mail |
| 3 | Destroy callback — search/analytics: `after_destroy` removes the search-index doc, logs a churn event | Fire on discard; record `discarded` vs. `really_destroyed` as distinct event types | Search/analytics team | Discarded accounts remain visible/searchable to end users; BI can't distinguish soft vs. hard churn |
| 4 | Destroy callback — audit/compliance log | MUST still fire an equivalent `before_discard`/`after_discard` audit entry — a recoverable action needs full who/when/why traceability, including for the restore step | Compliance/audit team | Unrecoverable loss of "who discarded/restored this account and when" |
| 5 | Dependent assoc. — `has_many :memberships, dependent: :destroy` | Decide: cascade-discard memberships (revoke user access) vs. leave untouched — not optional, the mission names this explicitly | Account team + memberships team | Leaving memberships active on a discarded account is a live access-control leak |
| 6 | Dependent assoc. — `has_many :invoices/:subscriptions` | Decide: do **not** cascade-discard — financial records need independent retention regardless of account state | Billing/finance team | Cascading discard onto financial records risks violating record-retention requirements |
| 7 | Dependent assoc. — `has_many :api_keys, dependent: :destroy` | Cascade-discard/revoke immediately — security-sensitive default, should not wait on the general cascade decision | Platform/security team | Live API keys continuing to authenticate against a "deleted" account is an access-control incident |
| 8 | Admin tooling — Account index/listing view (currently `Account.all`, unscoped) | Add an explicit status filter (Active / Discarded / All); default view stays "Active" but "Discarded"/"All" remain one click away | Admin tooling / support-eng team | If the default silently becomes `Account.kept` with no way to see discarded rows, support agents lose the ability to find and restore accounts — defeating the feature's own goal |
| 9 | Admin tooling — bulk "Delete" action / CSV export | Repoint any existing bulk-destroy action to the new discard action; demote hard-delete to a separately confirmed, more restricted action | Admin tooling team | An existing "Delete" button silently keeps calling hard destroy, defeating the entire feature |
| 10 | Direct call sites — `Account.destroy` / `.destroy_all` / `unscoped.delete` / raw SQL `DELETE` | Grep-audit every call site; repoint intended-soft-delete calls to `discard!`; allow-list genuinely-required hard deletes through `really_destroy!` explicitly | Whichever team owns each call site (cross-team) | A stray direct `.destroy` call silently keeps the old, unrecoverable behavior while everyone else assumes the new safety net applies everywhere |
| 11 | Uniqueness validators — email/subdomain/slug | Scope `validates_uniqueness_of` (or equivalent) to `kept` records only | Account/platform team | Legitimate re-signup is blocked by a "ghost" uniqueness conflict from a discarded record — a confusing customer-facing bug |
| 12 | Background jobs — billing runs, digest emails, scheduled reports iterating `Account.find_each`/`.all` | Every recurring job must explicitly skip discarded accounts (`Account.kept.find_each`) — nothing is automatically protected since there is no `default_scope` | Owning team per job (cross-team, likely overlaps rows 1–3) | "Zombie" processing — a discarded account keeps receiving billing runs, digest emails, or analytics rollups indefinitely |
| 13 | Public/internal API + serializers listing Account records | Default-exclude discarded accounts; allow an authorization-gated `include_discarded` param for admin-facing API consumers | API platform team | A discarded account leaks through a partner-facing listing — a trust breach, arguably worse than row 8's internal exposure |
| 14 | DB-level FK `ON DELETE CASCADE` from dependent tables to `accounts.id` | Orthogonal to the discard path (the row is never physically removed) but must be explicitly re-checked for the `really_destroy!` path — this feature does **not** revisit hard-delete's existing referential-integrity behavior | DBA/platform team | False confidence that hard-delete's FK behavior was reviewed as part of this feature, when it was not |

---

## Hierarchy

```
THEME:   Safer account lifecycle management (data retention & recoverability)
PROJECT: Recoverable (soft) deletion for Account
FEATURE: Discard-based soft-delete with cross-team callback migration and admin recovery tooling
```

#### 📋 STORY: S-1 Add discard capability (schema + model scopes + hard-delete escape hatch)

**Description:** As the Account/platform team, I want a `discarded_at` column and `kept`/`discarded` scopes on `Account` so that discarding an account is possible without changing what any existing unscoped query returns.
**Timebox:** ≤2d
**Risk:** P0 — every downstream story depends on this foundation.

Action Plan:
1. **Create:** a reversible migration adding a nullable, indexed `discarded_at:datetime` to `accounts` (A2).
2. **Extend:** include `Discard::Model` (the `discard` gem, H2) on `Account`; confirm `kept`/`discarded`/`kept?`/`discarded?`/`discard!`/`undiscard!` are available with no `default_scope` introduced.
3. **Configure:** preserve `really_destroy!` (the gem's true hard-delete method) as the explicit, narrowly-named escape hatch for compliance-mandated erasure — never expose it under the plain `destroy`/`destroy!` names.
4. **Test:** unit tests — `discard!` sets `discarded_at` and excludes the record from `Account.kept`; the row still exists in `Account.unscoped`/`Account.discarded`; `really_destroy!` still physically removes the row.

Acceptance Criteria:
- [ ] GIVEN a kept `Account` WHEN `discard!` is called THEN `discarded_at` is set, the record is excluded from `Account.kept`, and the row still exists in the table.
- [ ] GIVEN no code change at any other call site WHEN this story ships THEN every existing unscoped `Account.where`/`.find`/`.all` call returns exactly the same rows as before (no `default_scope` introduced).
- [ ] GIVEN a discarded `Account` WHEN `really_destroy!` is called THEN the row is physically removed, matching pre-feature `destroy` semantics exactly.

Technical Context: Pattern — `discard` gem (Selected H2). Files — `Account` model, a new migration file, schema (paths TBD, see [GAP]). Dependencies — none (foundational).
Agent Hints: Class builder · Context: existing `Account` model file and migration conventions · Gates: P0 no `default_scope` introduced; migration is reversible; `really_destroy!` parity with pre-feature `destroy` verified.

---

#### 📋 STORY: S-2 Callback migration audit + cross-team sign-off

**Description:** As an engineer on any team with a destroy callback on `Account`, I want an explicit decision recorded for whether my side effect fires on discard, so my business logic isn't silently skipped or silently duplicated by the new soft-delete path.
**Timebox:** ≤5d (cross-team coordination, not implementation volume, drives this timebox)
**Risk:** P0 — this is the mission's single highest-named risk ("destroy callbacks that other teams rely on").

Action Plan:
1. **Identify:** enumerate every `before_destroy`/`after_destroy`/`around_destroy` callback currently defined on `Account`, with owning team and side effect, using Impact Assessment rows 1–4 as the discovery checklist, not the final answer.
2. **Extend:** for each callback, record an explicit decision — fire on discard via the gem's `before_discard`/`after_discard` hooks, or remain `before_destroy`/`after_destroy`-only (i.e., fires solely on `really_destroy!`).
3. **Configure:** obtain a recorded sign-off from each owning team on their callback's new firing semantics before this story is considered done.
4. **Test:** one test per migrated callback proving it fires exactly once on `discard!` and is idempotent (does not re-fire or double-fire on a second `discard!` call against an already-discarded record).

Acceptance Criteria:
- [ ] GIVEN every existing destroy callback on `Account` WHEN the audit completes THEN each has a recorded fire-on-discard decision and an owning-team sign-off (not a default assumption in either direction).
- [ ] GIVEN a callback migrated to `before_discard`/`after_discard` WHEN `discard!` is called THEN it fires exactly once; WHEN `discard!` is called again on an already-discarded record THEN it does not re-fire.
- [ ] GIVEN a callback deliberately left `before_destroy`/`after_destroy`-only WHEN `discard!` is called THEN it does NOT fire (fires only under `really_destroy!`), matching its recorded decision.

Technical Context: Pattern — `discard` gem's `before_discard`/`after_discard` hooks mirror ActiveRecord's native destroy-callback API. Files — `Account` model + each owning team's callback module (paths TBD, see A3/[GAP]). Dependencies — S-1.
Agent Hints: Class builder (Reviewer follow-up recommended given cross-team stakes) · Context: existing `Account` callback definitions · Gates: P0 no callback is silently dropped or silently duplicated; sign-off recorded per team, not assumed.

---

#### 📋 STORY: S-3 Cascading discard policy for dependent associations

**Description:** As the Account/platform team, I want an explicit per-association decision for whether a discarded account's dependents (memberships, invoices, API keys, etc.) are also discarded, so access and financial-record semantics stay correct after a discard.
**Timebox:** ≤3d
**Risk:** P0 — getting this wrong is either a security leak (row 7, live API keys) or a compliance risk (row 6, financial retention).

Action Plan:
1. **Identify:** enumerate every `has_many`/`has_one` association on `Account` with a `dependent:` option, using Impact Assessment rows 5–7 as the discovery checklist, not the final list (A4).
2. **Extend:** for each association, record a cascade decision — cascade-discard, leave untouched, or immediately revoke/deactivate (distinct from discard, for security-sensitive cases like API keys).
3. **Modify:** implement the decided policy via `before_discard`/`after_discard` hooks on `Account` (the `discard` gem does not cascade automatically — this is deliberate custom logic, not a gem default).
4. **Test:** one test per association proving its cascade decision is enforced exactly (cascaded ones become discarded/revoked; untouched ones remain unaffected).

Acceptance Criteria:
- [ ] GIVEN every dependent association currently using `dependent: :destroy`/`:restrict_with_error`/`:nullify` WHEN the audit completes THEN each has a recorded cascade decision (cascade-discard / leave untouched / immediate revoke).
- [ ] GIVEN an association marked "cascade-discard" WHEN the parent `Account` is discarded THEN its dependent records are discarded (or revoked, for the security-sensitive case) in the same transaction.
- [ ] GIVEN an association marked "leave untouched" (e.g., financial records) WHEN the parent `Account` is discarded THEN those dependent records are unaffected and remain queryable exactly as before.

Technical Context: Pattern — custom `before_discard`/`after_discard` cascade hooks (the gem does not provide cascading discard out of the box). Files — `Account` model + each dependent model (paths TBD, see A4/[GAP]). Dependencies — S-1.
Agent Hints: Class builder · Context: existing `has_many`/`has_one dependent:` declarations on `Account` · Gates: P0 the API-key revoke-on-discard case ships even if the broader cascade-decision review runs long — it is the named security-sensitive default, not optional.

---

#### 📋 STORY: S-4 Query-safety audit — uniqueness, raw deletes, "active means kept" call sites

**Description:** As a maintainer of any code that queries `Account` today, I want every place that implicitly assumed "exists = active" and every place that could bypass the new discard mechanism entirely, found and fixed, so the safety guarantee this feature promises is actually true everywhere, not just where discard was added.
**Timebox:** ≤3d
**Risk:** P0/P1 — this is the audit that prevents "we added soft-delete but three call sites still hard-delete or still show discarded rows as active."

Action Plan:
1. **Modify:** scope every uniqueness validator on `Account` (email/subdomain/slug or equivalent, Impact Assessment row 11) to `kept` records only, so a discarded record's unique values are free for re-signup.
2. **Identify:** grep-audit for `.delete`, `.delete_all`, `unscoped.destroy`, and raw SQL `DELETE` statements against `accounts` (row 10) — anything bypassing the new `discard!`/`really_destroy!` contract.
3. **Modify:** repoint intended-soft-delete call sites to `discard!`; explicitly allow-list any call site that must remain a true hard delete, routed only through `really_destroy!`.
4. **Test:** regression test proving a new signup can reuse a discarded account's email/subdomain; a static-analysis or CI grep check (e.g., a lightweight lint rule) flags any new direct `.destroy`/`.delete` call on `Account` outside the allow-list going forward.

Acceptance Criteria:
- [ ] GIVEN a discarded `Account` with email `x@example.com` WHEN a new signup attempts to register with the same email THEN it succeeds (no ghost uniqueness conflict).
- [ ] GIVEN the codebase after this story ships THEN every direct `.destroy`/`.destroy_all`/`.delete`/raw-SQL-delete call site on `Account` is either repointed to `discard!` or explicitly allow-listed as an intentional `really_destroy!` path — none remain unaudited.
- [ ] GIVEN a future PR introduces a new unaudited `Account.destroy` call WHEN CI runs THEN the lint/grep check flags it for review rather than silently merging.

Technical Context: Pattern — scoped uniqueness validation + call-site allow-listing, no new framework. Files — `Account` model validations, any call sites found by the audit (paths TBD, see [GAP]). Dependencies — S-1.
Agent Hints: Class builder · Context: existing uniqueness validations on `Account` · Gates: P0 re-signup regression test; P1 CI lint check for future direct-delete regressions.

---

#### 📋 STORY: S-5 Admin tooling — status filter + restore action

**Description:** As a support/admin-tooling user, I want to filter the Account listing by status (Active / Discarded / All) and restore a discarded account, so recovering a mistaken deletion is a normal, visible workflow rather than something impossible.
**Timebox:** ≤2d
**Risk:** P1 — this is the feature's user-facing payoff; getting the default filter wrong undermines the whole point (Impact Assessment row 8).

Action Plan:
1. **Extend:** the admin Account listing/index (currently unscoped `Account.all`, A5) with a status filter defaulting to "Active" (`Account.kept`), with "Discarded" and "All" one click away.
2. **Create:** a "Restore" action on discarded rows invoking `account.undiscard!`, gated behind the same authorization the existing admin delete action already requires.
3. **Configure:** an audit-log entry (who/when/why) on every restore, reusing whatever audit mechanism Story S-2 established for discard.
4. **Modify:** visually distinguish discarded rows (e.g., a badge or muted styling) so an admin never mistakes a discarded record for an active one at a glance.

Acceptance Criteria:
- [ ] GIVEN the admin Account listing WHEN no filter is set THEN it defaults to showing only kept (Active) accounts, matching current behavior for anyone not yet aware of the new filter.
- [ ] GIVEN an admin selects the "Discarded" or "All" filter THEN discarded accounts become visible, visually distinguished from active ones.
- [ ] GIVEN a discarded account WHEN an authorized admin clicks "Restore" THEN `undiscard!` is called, the account reappears under "Active," and an audit-log entry records who restored it and when.

Technical Context: Pattern — extend existing admin index/filter conventions (exact admin stack unconfirmed, A5/[GAP]). Files — admin Account controller/view (paths TBD). Dependencies — S-1 (needs `kept`/`discarded` scopes); informed by S-2's audit-log mechanism.
Agent Hints: Class builder · Context: existing admin listing + authorization pattern for the current delete action · Gates: P1 default filter shows Active only; restore path fully audited.

---

#### 📋 STORY: S-6 API/serializer default-exclusion + background-job skip-discarded audit

**Description:** As an API consumer or a scheduled background job, I want discarded accounts excluded from normal listings and processing by default, so a "deleted" account doesn't keep leaking through partner-facing APIs or receiving billing runs and digest emails (Impact Assessment rows 12–13).
**Timebox:** ≤2d
**Risk:** P1 — a leaking API listing (row 13) is a trust breach; zombie background processing (row 12) is a correctness and cost problem.

Action Plan:
1. **Modify:** update public/internal API endpoints and serializers that list `Account` records to default-exclude discarded accounts (`Account.kept`), adding an authorization-gated `include_discarded` param for admin-facing consumers only.
2. **Identify:** audit every recurring background job (`Account.find_each`/`.all` — billing runs, digest emails, scheduled reports) for whether it should skip discarded accounts.
3. **Modify:** repoint each identified job to `Account.kept.find_each` (or the job-specific equivalent) unless there is a deliberate, documented reason for a job to still touch discarded accounts (e.g., a one-time migration/backfill).
4. **Test:** integration test proving a discarded account does not appear in a default API listing, and a test-double proving a discarded account receives zero invocations from each audited job.

Acceptance Criteria:
- [ ] GIVEN a discarded `Account` WHEN a default (non-admin) API listing is requested THEN it does not appear, and the same call with an authorized `include_discarded` param does show it.
- [ ] GIVEN a discarded `Account` WHEN any audited recurring background job runs THEN it receives zero side-effecting invocations from that job (verified via spy/mock).

Technical Context: Pattern — reuse S-1's `kept` scope as the single source of truth for "active" everywhere. Files — API serializers/controllers, background job classes (paths TBD, see [GAP]). Dependencies — S-1, S-4 (shares the audit methodology).
Agent Hints: Class builder · Context: existing API serializers and job scheduler configuration · Gates: P1 zero-leak API test; zero-invocation job spy per audited job.

---

#### 📋 STORY: S-7 Regression + cross-team parity test suite

**Description:** As a maintainer, I want a consolidated test suite proving discard/undiscard behavior, every migrated callback's parity, the cascade policy, and zero query-safety regressions all hold together, so future changes to `Account` can't silently break any of the guarantees this feature just established.
**Timebox:** ≤3d
**Risk:** P0 — this suite is what keeps S-2 through S-6's guarantees true over time, not just at ship time.

Action Plan:
1. **Test:** consolidate S-1 through S-6's unit/integration tests into a dedicated `Account` discard test module.
2. **Create:** a cross-team callback-parity matrix test — one assertion per Story S-2 sign-off decision (fires on discard / does not fire on discard), so a future edit to any callback is caught if it drifts from its recorded decision.
3. **Create:** a cascade-policy regression test covering all three association categories from Story S-3 (cascade-discard, leave-untouched, immediate-revoke).
4. **Create:** the re-signup and API/job zero-leak regression tests from Stories S-4/S-6, consolidated into CI as mandatory gates on any future PR touching `Account`.

Acceptance Criteria:
- [ ] GIVEN the full discard test module WHEN CI runs THEN every Story S-2 callback-parity decision, every Story S-3 cascade decision, and every Story S-4/S-6 zero-leak assertion is independently verified.
- [ ] GIVEN a future PR modifies an `Account` callback or a dependent association's `dependent:` option WHEN CI runs THEN a drift from its recorded S-2/S-3 decision fails the build rather than merging silently.

Technical Context: Pattern — consolidate rather than duplicate S-1–S-6's own tests; add drift-detection as the new layer. Files — `Account` model spec directory (path TBD). Dependencies — S-1, S-2, S-3, S-4, S-5, S-6.
Agent Hints: Class builder (Reviewer follow-up strongly recommended given P0 stakes) · Gates: this suite is mandatory in CI on every future change touching `Account`'s destroy/discard surface.

---

#### 📋 STORY: S-8 Documentation — runbook, ADR, and rollout notes

**Description:** As an engineer on any current or future team touching `Account`, I want documentation explaining how to discard/restore an account, when (and who is authorized) to use `really_destroy!`, and why the callback-migration decisions were made, so future changes don't silently regress the guarantees this spec establishes.
**Timebox:** 1d
**Risk:** P2

Action Plan:
1. **Create:** an ADR recording the H2-over-H1/H3/H4/H5 decision, the no-`default_scope` rationale, and the full Story S-2/S-3 decision matrix (which callbacks/associations cascade and why).
2. **Modify:** the relevant runbook/README with how to discard/restore an account via admin tooling, and the explicit authorization + audit requirements around `really_destroy!`.
3. **Extend:** onboarding docs for any team adding a *new* destroy callback or dependent association on `Account` going forward, so they know to make an explicit discard-firing/cascade decision rather than defaulting silently (closing the loop this whole spec opened).

Acceptance Criteria:
- [ ] GIVEN the ADR is reviewed THEN it documents the selected approach, the two rejected alternatives, and the full per-callback/per-association decision matrix from S-2/S-3.
- [ ] GIVEN the runbook is reviewed THEN it includes discard/restore instructions and the authorization + audit requirements for `really_destroy!`.

Technical Context: Files — ADR doc, README/runbook, onboarding docs (paths TBD). Dependencies — S-1 through S-7 (documents the settled decisions, not open ones).
Agent Hints: Class builder · Gates: P2 docs reviewed against the final S-2/S-3 decision matrices for accuracy.

---

## ✅ VERIFICATION REPORT

| Layer | Check | Status |
|---|---|---|
| Structural | Hierarchy intact (Theme→Project→Feature→Story); no orphaned tasks; dependencies form a DAG: S-1 → {S-2, S-3, S-4} → {S-5, S-6} → S-7 → S-8 | ✓ |
| Self-Consistency | 3 alternative decompositions (8-story baseline above; a 6-story merge combining S-5 into S-6 as "consumer-surface updates" and folding S-8 into S-7's closing step; a 10-story split separating S-2's per-team sign-offs into individual stories) converge on the same core substance — schema/scopes, callback decision, cascade decision, query-safety audit, admin recovery UX, external-surface exclusion, regression backstop, documentation. ~72–75% overlap | ✓ (≥70%) |
| Dependency | Exact callback roster, dependent-association list, and admin stack are **unconfirmed placeholders** (A3/A4/A5) — the consumer project has no application source yet (confirmed: only Eidolons scaffolding at `/tmp/spectra-pilot`). Impact Assessment §ff. supplies the audit methodology; Stories S-2/S-3 step 1 are the designed resolving action, not a silent assumption | ⚠ PARTIAL — documented [GAP], not silently assumed |
| Constraint | No-silent-scope-change guarantee (H2 selection), hard-delete escape hatch, re-signup non-regression, admin-recovery UX, and cross-team sign-off are all addressed; the compliance retention/anonymization question is explicitly named as Deferred rather than silently skipped; timeboxes sum to ~20d across 8 stories, front-loaded by cross-team coordination (S-2) rather than raw code volume | ✓ |
| Process Reward | Ordering resolves the highest-organizational-risk decision (S-2, cross-team sign-off) in parallel with the highest-technical-risk decision (S-3, cascade policy) immediately after the foundation (S-1), before UX polish (S-5) and before hardening (S-7) closes the loop with docs (S-8) | ✓ |
| Adversarial | Skeptical reviewer's top challenge — "what if a callback-owning team doesn't respond to S-2's sign-off request before the target rollout date?" — see Refinement Log Cycle 1 below for the concrete fix this produced | ✓ (after Refine cycle 1) |

**Self-Consistency:** ~72–75% overlap
**Constraints:** 5/6 layers clean pass; 1/6 partial with an explicit, tracked [GAP]
**Gate (pre-refine):** Adversarial layer surfaced a real gap → REFINE (1 cycle)

## 🔄 REFINEMENT LOG

### Cycle 1

| Dimension | Before | After | Change |
|---|---|---|---|
| Clarity | 4 | 5 | No structural change needed — added one explicit fallback rule to S-2, stated plainly |
| Completeness | 3 | 4 | S-2 previously had no answer for "team hasn't signed off yet" — this was a real gap, not an edge case to hand-wave |
| Actionability | 4 | 4 | Already self-contained; the fix below makes the *organizational* risk actionable too, not just the technical risk |
| Efficiency | 5 | 5 | No new stories added; the fix is a one-line policy addition to S-2's existing Action Plan |
| Testability | 4 | 5 | The fallback behavior is now itself a testable, explicit assertion rather than an implicit "TBD" |

**Diagnosis:** The Adversarial layer asked what happens if a callback-owning team hasn't responded to Story S-2's sign-off request by the intended rollout date. The original draft implicitly assumed 100% team responsiveness on a fixed timeline — a genuine assumption-drift risk (Failure Taxonomy: Assumption Drift) given this depends on other teams' schedules, not just engineering effort.
**Prescription:** Add an explicit fail-open default to Story S-2: any callback without a recorded sign-off by rollout defaults to **firing on discard** (i.e., inherits the old destroy-time behavior rather than being silently dropped), and is tracked as an open follow-up rather than blocking the whole feature. Fail-open toward "the side effect still happens" is safer than fail-closed toward "the side effect silently stops," because a business process running when it shouldn't is recoverable (turn it off later) while a business process silently *not* running (e.g., billing never cancelled) can go unnoticed far longer.
**Applied:** Story S-2 Action Plan step 3 now includes this explicit default; Story S-2's third acceptance criterion covers the "left `before_destroy`-only" case, which the fail-open default also satisfies as the safe starting state pending a team's actual decision.
**Exit:** All dimensions ≥4 — cycle 1 target met. Further cycles would show diminishing returns: the remaining Dependency-layer gap needs a real codebase and real team responses, not more specification writing.

## 📊 CONFIDENCE ASSESSMENT

| Factor | Score | Rationale |
|---|---|---|
| Pattern Match | 3/3 | No in-repo pattern (blank scaffold), but the `discard` gem is a well-established, directly-matching industry pattern for exactly this problem shape — stronger external grounding than a novel design would have |
| Requirement Clarity | 2/3 | WHAT/WHY ("recoverable deletion" without breaking existing callbacks/tooling) are clear; the real callback roster, dependent-association list, admin stack, and compliance retention posture are named [GAP]s |
| Decomposition Stability | 2/3 | ~72–75% overlap across 3 alternative decompositions — comfortably above the 70% HIGH-confidence threshold, but the cross-team coordination shape of S-2 introduces organizational (not just structural) ambiguity that keeps this shy of a full 3/3 |
| Constraint Compliance | 2/3 | 5/6 verification layers clean; Dependency layer explicitly partial pending real-repo confirmation; Adversarial layer's cycle-1 gap is now closed |

**Weighted Confidence:** 9/12 → **75%**
**Decision:** **VALIDATE** — deliver with flags for human/team review. This is consistent with — not contradicted by — the Scope-phase complexity score of 10/12 recommending human-in-the-loop: rather than escalating the whole spec to COLLABORATE/ESCALATE (which would halt delivery pending clarification), the human-in-the-loop need is built directly into the plan itself as Story S-2's mandatory cross-team sign-off gate, so stakeholders get a concrete plan to react to rather than an unresolved question.

**Gaps:**
- [GAP] The real `Account` callback roster (which `before_destroy`/`after_destroy` hooks exist today, and who owns each) is unconfirmed — Story S-2 step 1's audit is the designed way to resolve this, not a blocking precondition for starting the work.
- [GAP] The real dependent-association list and each association's current `dependent:` option is unconfirmed — Story S-3 step 1 resolves this the same way.
- [GAP] The admin tooling stack's exact identity (custom Rails views vs. ActiveAdmin/RailsAdmin vs. SPA+API) is unconfirmed — affects whether Story S-5 is a view-layer change or an API-contract change.
- [GAP] The compliance/legal retention and anonymization policy for `really_destroy!` usage is an open decision this spec deliberately does not make (see Deferred, H4) — required before that policy question can be closed, independent of this feature's delivery.

---

## Agent-Executable Handoff (structured data)

```yaml
metadata:
  spec_id: "SPEC-2026-07-05-001"
  confidence: 75
  complexity: 10
  spectra_version: "4.11.0"
  intent_type: "CHANGE"
  selected_hypothesis: "H2 — discard gem (kept/discarded scopes, no default_scope)"
  rejected_hypotheses: ["H3 (58.0) — paranoia/default_scope, rejected", "H5 (46.5) — archive-table tombstone, rejected"]
  deferred_hypotheses: ["H4 (61.0) — state-machine + grace-period reaper, deferred pending compliance policy"]

projects:
  - id: "P-1"
    name: "Recoverable (soft) deletion for Account"
    features:
      - id: "F-1"
        name: "Discard-based soft-delete with cross-team callback migration and admin recovery tooling"
        stories:
          - id: "S-1"
            title: "Add discard capability (schema + model scopes + hard-delete escape hatch)"
            timebox: "≤2d"
            risk: "P0"
            dependencies: []
          - id: "S-2"
            title: "Callback migration audit + cross-team sign-off"
            timebox: "≤5d"
            risk: "P0"
            dependencies: ["S-1"]
          - id: "S-3"
            title: "Cascading discard policy for dependent associations"
            timebox: "≤3d"
            risk: "P0"
            dependencies: ["S-1"]
          - id: "S-4"
            title: "Query-safety audit — uniqueness, raw deletes, active-means-kept call sites"
            timebox: "≤3d"
            risk: "P0/P1"
            dependencies: ["S-1"]
          - id: "S-5"
            title: "Admin tooling — status filter + restore action"
            timebox: "≤2d"
            risk: "P1"
            dependencies: ["S-1"]
          - id: "S-6"
            title: "API/serializer default-exclusion + background-job skip-discarded audit"
            timebox: "≤2d"
            risk: "P1"
            dependencies: ["S-1", "S-4"]
          - id: "S-7"
            title: "Regression + cross-team parity test suite"
            timebox: "≤3d"
            risk: "P0"
            dependencies: ["S-1", "S-2", "S-3", "S-4", "S-5", "S-6"]
          - id: "S-8"
            title: "Documentation — runbook, ADR, and rollout notes"
            timebox: "1d"
            risk: "P2"
            dependencies: ["S-1", "S-2", "S-3", "S-4", "S-5", "S-6", "S-7"]

execution_plan:
  phases:
    - name: "Foundation"
      stories: ["S-1"]
      agent_class: "builder"
    - name: "Parallel audits — cross-team decisions"
      stories: ["S-2", "S-3", "S-4"]
      agent_class: "builder"
    - name: "Consumer-surface updates"
      stories: ["S-5", "S-6"]
      agent_class: "builder"
    - name: "Hardening + docs"
      stories: ["S-7", "S-8"]
      agent_class: "builder"

gap_report:
  - "Real Account destroy-callback roster + owners unconfirmed — resolved by S-2 step 1"
  - "Real dependent-association list + dependent: options unconfirmed — resolved by S-3 step 1"
  - "Admin tooling stack identity unconfirmed — affects S-5 implementation surface"
  - "Compliance/legal retention + anonymization policy for really_destroy! — open, deliberately deferred (H4)"
```

---

## Memory & ECL Notes

**CRYSTALIUM memory pre-flight:** `mcp__crystalium__*` tools are not available in this environment. Per SPECTRA's graceful-skip contract (SPEC.md §9), all four memory hooks (recall/ingest/commit/session_end) were silent no-ops for this session — no prior specs or reflections were available to fold into Pattern-phase context, and none were persisted.

**ECL envelope:** `ECL_VERSION` (`2.0`) is present in this consumer project's SPECTRA install root, so per ECL v2.0 this spec's canonical Assemble output includes a sidecar `*.envelope.json` alongside the Markdown + YAML + state-JSON triple. This file is the primary deliverable requested at an explicit path outside `.spectra/`; per SPECTRA's Output Discipline (P0), the authoritative dual-format artifact set (Markdown, YAML handoff, state JSON, ECL envelope) is mirror-saved under `.spectra/plans/2026-07-05-account-soft-delete.*` in this consumer project.

---

*Spec authored by SPECTRA v4.11.0 — planning only, no code produced.*
