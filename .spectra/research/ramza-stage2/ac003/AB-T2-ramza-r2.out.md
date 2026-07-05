---
eidolon: ramza
kind: spec
version: 0.2.0
status: ready-for-apivr
created_at: 2026-07-05T13:16:31Z
plan: ac003-t2-r2
tier: full
thread_id: 019f326c-94ab-713b-a551-60819260c0a2
target_repos: ["primary-rails-monolith (name unresolved — no repository access this session; treat as the mature Rails app named in the mission brief)"]
stories_count: 5
validation_gates_count: 13
confidence: 0.795
---

# Recoverable soft-delete for the Account model

Theme: Data lifecycle & recoverability. Project: Account soft-delete. Feature:
recoverable (undo-able) deletion for `Account`, layered alongside — never on
top of — the existing hard-destroy path other teams already depend on.

## Intake note (DISCOVER/CLARIFY disposition)

Intent class is `CHANGE` on a known, well-bounded goal ("add recoverable
soft-delete to Account") — DISCOVER (goal-elicitation) is skipped per its own
boundary rule (goal is not latent). CLARIFY's normal ≤3-question round was not
run synchronously in this session (no human reviewer was available to answer
in-turn); rather than block, every question CLARIFY would have asked is carried
forward as an explicit, flagged Assumption below with its risk-if-wrong — this
plan is written to be corrected cheaply at review (Confidence verdict:
VALIDATE, see below), not to assert false certainty.

## Scope

Intent class: CHANGE
In: a new, opt-in recoverable-deletion path for `Account` (`deleted_at`
column + default-scope exclusion + `soft_delete!`/`restore!` methods), a
call-site impact assessment of the existing hard-`destroy` path, admin-tooling
visibility into trashed Accounts, and a bounded-retention hard-delete reaper
that reuses the existing `destroy` pipeline (and therefore its callbacks)
unchanged.
Out: soft-delete for any model other than `Account`; changing the behavior,
callback set, or association `dependent:` semantics of `Account#destroy` /
`#destroy!` themselves; a generic reusable "Discardable"-style library
extraction for other models (noted as a natural Deferred follow-up); GDPR/CCPA
erasure-request tooling beyond the retention-bounded reaper already in scope.
Deferred: extracting the soft-delete concern into a shared, model-agnostic
library once a second model needs the same treatment (premature to generalize
from n=1); a self-service "undo" UI surfaced to end users rather than
operators (admin-only in this iteration).

Assumptions (each carries the CLARIFY-round questions this plan could not ask
synchronously):
- No repository access was available this session, so the call-site inventory
  in Story 2 is a **procedure and taxonomy**, not a fabricated enumeration of
  real `path:line` citations — risk if wrong: the actual call-site count could
  be materially larger or smaller than the `--files-est 14` used at
  Right-Size, which would change the RS tier; Story 2's first task is to
  re-run Right-Size once the real count is known if it lands far from the
  estimate.
- `Account` has `dependent: :destroy` (or `:restrict_with_error`) associations
  and at least one `before_destroy`/`after_destroy` callback consumed by a
  different team (both stated in the mission brief) — risk if wrong: if no
  other team actually consumes a destroy callback, the strongest argument for
  Hypothesis 2 (decoupling from `destroy` entirely) weakens and Hypothesis 1
  (paranoia-style override) becomes more competitive; re-score Explore if this
  turns out false.
- A bounded retention window (default assumed: 30 days) before the reaper
  hard-deletes is acceptable to compliance/legal — risk if wrong: the actual
  required window (or a "keep forever unless explicitly purged" policy) changes
  Story 4's timebox and AC-011/AC-012's numeric assumptions; this is the single
  highest-value real CLARIFY question left open and is called out again in
  Risks.
- Existing admin tooling lists Accounts through a single admin controller/index
  (as implied by "existing admin tooling that lists records") rather than N
  independent listing surfaces — risk if wrong: Story 3's timebox (2d) would
  need to multiply by the number of independent listing surfaces found during
  Story 2's inventory.
- The consumer application uses Rails ActiveRecord defaults (a real DB-backed
  `deleted_at` column, not a NoSQL or event-sourced store) — risk if wrong:
  the entire schema-level approach (Hypotheses 1–3) would need re-evaluation
  against Hypothesis 4's data-model assumptions instead of rejecting it.

Complexity (`ramza-score --rubric complexity`): 11/12 → **human_loop** (scope 3,
ambiguity 2, dependencies 3, risk 3 — cross-team destroy-callback consumers,
an admin surface, and a retention/compliance policy question together push
every dimension to its top band except ambiguity, which is contained by this
plan's explicit assumption list). human_loop routes the *execution* of this
plan to human-in-the-loop review at each Story boundary, not to blanket
automation — consistent with the Confidence verdict below.

## Pattern

No CRYSTALIUM MCP tools were available this session (graceful skip per
`agent.md`); no prior RAMZA plan in `.spectra/plans/` addresses soft-delete or
Account-model lifecycle, so there is no in-repo precedent to match against.
Classified **<60% match → generate**, not adapt-from-template, but the
generated design deliberately leverages a well-known, named industry pattern
rather than inventing one: the "decoupled soft-delete, `destroy` untouched"
shape used by the `discard` gem (deliberately *not* the `paranoia`/
`acts_as_paranoid` shape, which overrides `destroy` itself — see Rejected
Alternatives).

**Anti-pattern surfaced (not from prior RAMZA history, but from the domain
itself and worth recording for future plans in this project):** overriding
`ActiveRecord::Base#destroy` to silently redirect to a soft-delete is a known
failure mode in exactly this situation — "destroy callbacks that other teams
rely on" is a direct signal that those teams' callbacks assume destroy-time
side effects (webhooks, downstream syncs, cascades) are genuinely permanent.
Silently rerouting `destroy` breaks that assumption without those teams'
knowledge. This anti-pattern is why Hypothesis 1 loses in Explore below.

## Approach

Selected: **Hypothesis 2 — a decoupled `soft_delete!`/`restore!` path that
never touches `Account#destroy`/`#destroy!`** (`ramza-score --rubric explore`
total 88 → elite; see Rejected Alternatives for the other three).

Add a `deleted_at:datetime` column (indexed, nullable) to `accounts` via a
migration, plus a small `SoftDeletable` concern included into `Account`
providing: a default scope excluding non-null `deleted_at` (with an explicit
`Account.with_deleted`/`.only_deleted` escape hatch for admin tooling), a
`soft_delete!` method that sets `deleted_at` and saves (idempotent — a no-op
if already set), and a `restore!` method that clears it. Neither method calls
`destroy`, `destroy!`, or any association's destroy cascade — the entire
existing destroy pipeline, its callbacks, and its `dependent:` semantics are
left byte-for-byte unchanged, so every other team's existing integration
continues to work exactly as it does today for any caller that still invokes
`destroy` directly. Recoverability is bounded: a scheduled reaper job
hard-deletes (via the ordinary, unmodified `destroy!` path, so its callbacks
still fire exactly once) any Account whose `deleted_at` is older than a
configured retention window. Admin tooling gains an explicit, feature-flagged
"Trashed" view built on `Account.only_deleted`, with a Restore action.

Because this approach does not change `destroy`'s behavior, the existing
call-site risk shifts from "will this migration break destroy callbacks"
(it cannot — destroy is untouched) to "which call sites *should* move to the
new recoverable path going forward" — a product/ownership decision, not a
correctness risk. Story 2 makes that decision auditable via a classified
inventory rather than leaving it implicit.

## Impact Assessment — existing Account destroy call sites

**Framing.** Because Hypothesis 2 leaves `Account#destroy`/`#destroy!`
completely unchanged, this is not a "will existing behavior break" assessment
— it structurally cannot break, since no code path invoking `destroy` is
touched by this plan (AC-005, AC-006). It is a "which of these callers
*should* move to the new recoverable path, and who needs to be told"
assessment. That reframing is itself the headline finding of this section.

No repository access was available in this planning session (see Scope
Assumptions), so what follows is the **taxonomy and procedure** Story 2
executes against the real codebase, plus the **candidate categories** implied
directly by the mission brief's own language — presented as hypotheses for
Story 2 to confirm, never as verified findings asserted without evidence.

**Disposition taxonomy** (mechanically gated by AC-007/AC-008):

| Disposition | Meaning | Candidate example (to confirm in Story 2) |
|---|---|---|
| migrate-to-soft-delete | Caller performs a user-facing or reversible "delete this account" action; should switch to `soft_delete!` | Self-service/admin "delete account" action reachable from a request path |
| retain-as-hard-delete | Caller performs genuinely permanent cleanup; no behavior change needed or wanted | Rake tasks / console one-offs used for data cleanup |
| needs-cross-team-consult | Owning team differs from the team running this migration, or the destroy callback has an external side effect (webhook, downstream sync, billing event) assuming permanence | The "destroy callbacks that other teams rely on" named in the mission brief — default disposition until a consult proves otherwise |

**Known blast-radius categories from the mission brief** (unconfirmed until
Story 2 runs against real code):

- **Dependent associations** — every `has_many`/`has_one … dependent: :destroy`
  (or `:restrict_with_error`) on or below `Account`. Under Hypothesis 2 these
  are structurally unaffected by `soft_delete!` (AC-006); the open impact
  question is only whether any of *their own* code independently calls
  `Account#destroy` directly — a Story-2 grep target, not an
  association-declaration concern.
- **Destroy callbacks other teams rely on** — `before_destroy`/`after_destroy`
  hooks on `Account` itself, unchanged by this plan (AC-005). The assessment's
  job is to find every caller that currently reaches those hooks and decide,
  per caller, whether it should keep doing so (retain-as-hard-delete /
  needs-cross-team-consult) or move to the new path (migrate-to-soft-delete).
- **Existing admin tooling that lists records** — the admin Accounts index.
  Confirmed in scope as Story 3; the impact question folded in here is
  whether that index has any implicit "soft-deleted rows are just gone"
  assumption baked into a query, controller filter, or view partial that
  Story 3 must not silently change (AC-010 pins pre-existing behavior when
  the feature flag is off).

Story 2 is the executable form of this section: it turns the taxonomy above
into a checked-in, disposition-complete inventory before Story 3/4 are allowed
to roll out to production (AC-007, AC-008).

## Stories

### Story 1: Add the recoverable soft-delete mechanism to Account

As a backend engineer, I want a `deleted_at`-backed `soft_delete!`/`restore!`
pair on `Account` that never touches the existing `destroy` pipeline, so that
records can be recoverably removed from normal views without altering the
callback contract other teams already depend on.

Timebox: 3d.
Risk tag: P1 (touches the core model and a migration on a mature table; no
behavior change to any existing caller if built correctly, which is exactly
what AC-005/AC-006 verify).
Executor hint: mid tier (Sonnet-class) — file-level action plan below, named
pattern (`discard`-style decoupled soft-delete), no need for line-level
step-scripting.

Action plan: add migration `db/migrate/*_add_deleted_at_to_accounts.rb`
(nullable `datetime`, indexed) → add `app/models/concerns/soft_deletable.rb`
(default scope, `with_deleted`, `only_deleted`, `soft_delete!`, `restore!`,
all guarded against double-application) → `include SoftDeletable` in
`app/models/account.rb` → add model specs proving `destroy`/`destroy!` are
byte-for-byte unchanged (AC-005) and that dependents are not cascaded on
soft-delete (AC-006).

### Story 2: Inventory and classify existing Account destroy call sites

As the team introducing this change, I want every existing call site that
invokes `Account#destroy`, `#destroy!`, or a dependent-association cascade
reaching `Account` enumerated and classified, so that other teams' reliance on
destroy callbacks is made visible and each call site gets a deliberate,
recorded disposition instead of an implicit one.

Timebox: 2d.
Risk tag: P0 (this *is* the impact assessment the whole plan depends on being
honest about; an incomplete inventory silently reintroduces the exact risk
this plan exists to manage).
Executor hint: economy tier (Haiku-class) — explicit steps and a
schema-validated output contract, because this task is mechanical breadth-
first search over the codebase, not judgment:

1. Grep the codebase for `\.destroy\b`, `\.destroy!\b`, and every association
   declared `dependent: :destroy` / `:destroy_async` on any model that
   `belongs_to`/`has_many` an `Account` (directly or transitively).
2. For each hit, record: file:line, calling context (controller action,
   background job, rake task, console/one-off script, admin bulk action,
   service object), and whether it is invoked in a request path, an async job,
   or an operator-triggered path.
3. Classify each row into exactly one disposition: **migrate-to-soft-delete**
   (user-facing "delete" actions that should become recoverable),
   **retain-as-hard-delete** (internal cleanup/test-data tooling that should
   keep destroying for real), or **needs-cross-team-consult** (any call site
   whose owning team is not the team running this migration, or whose destroy
   callback has an external side effect — webhook, downstream sync, billing
   event — that a soft-delete-first policy would change).
4. For every `needs-cross-team-consult` row, record the owning team and open
   a consult before Story 3/4 roll out (AC-007, AC-008).
5. Output: a checked-in inventory artifact (e.g.
   `docs/account-destroy-call-site-inventory.csv` or equivalent), one row per
   call site, disposition column never blank.

Known candidate call-site categories, from the mission brief's own signals
(illustrative — the actual enumeration is this Story's deliverable, not this
plan's, per the Pattern-phase honesty note above): admin bulk "delete account"
actions; account-closure request-path controllers; background jobs that
cascade-clean related records; the specific "destroy callbacks that other
teams rely on" named in the brief (candidate disposition:
needs-cross-team-consult by default until proven otherwise); rake
tasks/console one-offs used for data cleanup (candidate disposition:
retain-as-hard-delete).

### Story 3: Surface trashed Accounts in the existing admin tooling

As an admin operator, I want the existing Accounts admin index to show a
"Trashed" filter with a Restore action, so that a soft-deleted Account is
discoverable and recoverable rather than silently invisible.

Timebox: 2d.
Risk tag: P1 (a hidden-by-default filter is low risk to existing behavior;
the risk is scope creep into a full audit-log UI, explicitly out of scope).
Executor hint: mid tier (Sonnet-class) — file-level action plan, named
pattern (scope-driven index filter + row action), no explicit step-scripting.

Action plan: feature-flag `account_soft_delete` gates the whole surface (off
= pixel-identical to today, AC-010) → add a "Trashed" tab/filter to the
existing Accounts admin controller/index using `Account.only_deleted` → add a
per-row Restore action calling `restore!` → do not add bulk-restore or an
audit trail in this iteration (Deferred).

### Story 4: Bounded-retention hard-delete reaper

As a data-retention owner, I want soft-deleted Accounts past a configured
retention window to be actually destroyed via the existing `destroy!` path,
so that "recoverable" stays time-bounded rather than becoming permanent,
indefinite storage, while every team that already consumes a destroy callback
still sees it fire exactly once, at the moment of real deletion.

Timebox: 2d.
Risk tag: P0 (this is the compliance backstop; wrong retention math either
deletes recoverable data too early or never purges at all).
Executor hint: mid tier (Sonnet-class) — file-level action plan + the
retention-window constant made a named, documented config value (not a
magic number), because Legal/Compliance sign-off on the number itself is
explicitly flagged as open in Risks.

Action plan: add `app/jobs/purge_soft_deleted_accounts_job.rb` scheduled
daily → job selects `Account.only_deleted.where(deleted_at: ...cutoff)` →
calls the ordinary `destroy!` on each (never a raw SQL delete), so existing
callbacks fire unchanged → log a count per run for observability.

### Story 5: Migration guide and cross-team rollout communication

As a team member of a dependent team (owning a destroy callback or admin
tooling touching Account), I want a short migration guide explaining the new
`soft_delete!` path, the disposition taxonomy, and the retention window, so
that I can decide whether my call sites should move to it without having to
reverse-engineer the change from a diff.

Timebox: 1d.
Risk tag: P2 (documentation; no runtime behavior).
Executor hint: frontier tier (Opus/Fable-class) — goals and constraints only;
writing a clear migration guide is a judgment task, not a scaffolded one.

Action plan: publish `docs/soft-delete-migration-guide.md` covering the
disposition taxonomy (Story 2), the retention window default and how to
request a different one, and "how to migrate a call site from `destroy` to
`soft_delete!`" with a before/after example (AC-013).

## Acceptance Criteria

Full EARS-form block, 13 criteria, `ramza-ears-lint`-clean. By story: Story 1
→ AC-001–AC-003, AC-005, AC-006; Story 2 → AC-007, AC-008; Story 3 → AC-009,
AC-010; Story 4 → AC-004, AC-011, AC-012; Story 5 → AC-013.

### AC-001 (event-driven)
GIVEN an Account that is not currently soft-deleted
WHEN  `account.soft_delete!` is called
THEN  the record SHALL persist with `deleted_at` set to the current time and remain physically present in the `accounts` table
VERIFY: test: spec/models/account_spec.rb#soft_delete_sets_deleted_at_without_removing_row

### AC-002 (ubiquitous)
THEN  `Account.all` and every default-scoped Account query SHALL exclude records with a non-null `deleted_at`
VERIFY: test: spec/models/account_spec.rb#default_scope_excludes_soft_deleted

### AC-003 (unwanted-behavior)
GIVEN an Account that is already soft-deleted
WHEN  `account.soft_delete!` is called again
THEN  the call SHALL be a no-op returning false, never raising and never overwriting the original `deleted_at` timestamp
VERIFY: test: spec/models/account_spec.rb#soft_delete_is_idempotent

### AC-004 (event-driven)
GIVEN a soft-deleted Account within the retention window
WHEN  `account.restore!` is called
THEN  `deleted_at` SHALL be cleared and the record SHALL reappear in default-scoped queries
VERIFY: test: spec/models/account_spec.rb#restore_clears_deleted_at

### AC-005 (ubiquitous)
THEN  `Account#destroy` and `Account#destroy!` SHALL retain their pre-existing behavior — physical row deletion, existing `before_destroy`/`after_destroy` callbacks, and existing `dependent: :destroy`/`:restrict_with_error` association semantics — unchanged for any caller that still invokes them directly
VERIFY: test: spec/models/account_spec.rb#destroy_path_behavior_unchanged

### AC-006 (unwanted-behavior)
GIVEN an Account with dependent associations declared `dependent: :destroy`
WHEN  `account.soft_delete!` is called
THEN  the dependent associations SHALL NOT be destroyed or otherwise mutated as a side effect
VERIFY: test: spec/models/account_spec.rb#soft_delete_does_not_cascade_to_dependents

### AC-007 (ubiquitous)
THEN  every call site in the application that invokes `Account#destroy`, `Account#destroy!`, or a dependent-association destroy cascade reaching Account SHALL be enumerated in the call-site inventory artifact and classified into exactly one disposition: migrate-to-soft-delete, retain-as-hard-delete, or needs-cross-team-consult
VERIFY: gate: script: bin/inventory_account_destroy_call_sites.rb --check-classified (exit 0 only when zero rows have a blank disposition)

### AC-008 (state-driven)
WHILE the call-site inventory contains at least one entry with disposition needs-cross-team-consult and no recorded resolution
THEN   the deployment pipeline SHALL block promotion of the `account_soft_delete` feature flag to 100% production rollout
VERIFY: gate: CI check: release_checklist#soft_delete_consult_entries_resolved

### AC-009 (optional-feature)
GIVEN the `account_soft_delete` feature flag is enabled for an operator's admin role
THEN  the admin Accounts index SHALL expose a "Trashed" filter listing soft-deleted Accounts with a per-row Restore action
VERIFY: test: spec/requests/admin/accounts_spec.rb#trashed_filter_lists_soft_deleted_with_restore_action

### AC-010 (unwanted-behavior)
GIVEN the `account_soft_delete` feature flag is disabled
WHEN  an operator opens the admin Accounts index
THEN  the index SHALL render exactly as it did before this change, with no Trashed filter and no soft-deleted rows visible
VERIFY: test: spec/requests/admin/accounts_spec.rb#trashed_filter_hidden_when_flag_disabled

### AC-011 (event-driven)
GIVEN a soft-deleted Account whose `deleted_at` is older than the configured retention window
WHEN  the scheduled hard-delete reaper job runs
THEN  the reaper SHALL invoke `Account#destroy!` on that record exactly once, preserving all existing destroy callbacks for teams that consume them
VERIFY: test: spec/jobs/purge_soft_deleted_accounts_job_spec.rb#hard_deletes_expired_soft_deleted_accounts_via_destroy

### AC-012 (unwanted-behavior)
GIVEN a soft-deleted Account whose `deleted_at` is within the configured retention window
WHEN  the scheduled hard-delete reaper job runs
THEN  the reaper SHALL NOT call destroy on that record, never removing a recoverable Account before its retention window elapses
VERIFY: test: spec/jobs/purge_soft_deleted_accounts_job_spec.rb#never_purges_within_retention_window

### AC-013 (ubiquitous)
THEN  the soft-delete migration guide SHALL document the disposition taxonomy, the retention window default, and the recommended replacement call (`soft_delete!` instead of `destroy`) for teams migrating a call site
VERIFY: gate: doc lint: docs/soft-delete-migration-guide.md exists and contains sections "Disposition taxonomy", "Retention window", "Migrating a call site"

## Confidence

`ramza-score --rubric confidence`: 79.5% → **VALIDATE** (pattern_match 75,
requirement_clarity 80, decomposition_stability 78, constraint_compliance 85
— the decoupled-from-destroy approach fully honors the one hard constraint
that matters most (never break existing destroy callbacks), but pattern_match
and decomposition_stability are capped below "elite" confidence because the
real call-site count and the real retention-window policy are both unverified
against the actual codebase this session, per the Assumptions above). VALIDATE
means: a human reviews before this plan is executed — which is exactly what
the human_loop complexity routing already recommended; the two independent
gates agree.

## Rejected Alternatives

- **Hypothesis 1 — override `Account#destroy`/`#destroy!` to soft-delete
  in place (paranoia/`acts_as_paranoid`-style)** — `ramza-score --rubric
  explore` total 64.5 (weak): the single most pattern-recognizable "Rails
  soft-delete" shape, but it fails the plan's actual hard constraint —
  rerouting `destroy` means every existing `before_destroy`/`after_destroy`
  callback the other teams rely on now fires on a *reversible* soft-delete,
  contradicting whatever "permanent removal" side effect they were written to
  assume (a webhook, a downstream sync, a billing event). Lower alignment (7)
  and risk (5) scores reflect exactly this mismatch. Also carries an
  ecosystem risk: the reference gem for this shape (`paranoia`) is effectively
  unmaintained.
- **Hypothesis 3 — adopt the `discard` gem as a new dependency instead of a
  hand-rolled concern** — total 78.5 (solid, not elite): philosophically the
  *same* decoupled-from-destroy shape as the selected Hypothesis 2 (this is
  why its alignment/correctness/simplicity scores are close to the winner),
  but it trades a small amount of hand-rolled code for a new runtime
  dependency governing core data-integrity behavior (maintainability 7, risk
  7 — third-party upgrade/abandonment risk, and less direct control over the
  exact `with_deleted`/admin-scope API this project's admin tooling needs).
  Worth revisiting if a second model needs the same treatment and the
  calculus shifts toward "don't hand-roll this twice" (see Deferred).
- **Hypothesis 4 — move soft-deleted rows to a separate archive/tombstone
  table** — total 47.5 (weak): genuinely the most innovative option
  (innovation 8) but the lowest alignment (4) and simplicity (3) — moving a
  row out of `accounts` breaks every dependent association's foreign key
  lookup unless every one of them is rewritten to consult two tables, which
  is a strictly larger blast radius than the "dependent associations" concern
  this plan exists to de-risk, not a smaller one. Rejected outright, not
  merely deferred.

## Risks

| Risk | Tag | Mitigation |
|---|---|---|
| Retention-window default (30d assumed) is not actually Legal/Compliance-approved | P0 | Story 4 makes the window a named, documented config value; Confidence verdict VALIDATE forces a human check on this specific number before rollout |
| Story 2's inventory is incomplete (a destroy call site is missed) | P0 | AC-007/AC-008 make "zero unclassified rows" and "no unresolved cross-team-consult entries at rollout" mechanically gated, not a one-time manual sweep |
| Admin tooling has more than one independent Accounts listing surface (Assumption in Scope) | P1 | Story 3's timebox is flagged as contingent on Story 2's inventory surfacing the true surface count |
| A dependent-team callback silently assumes `Account.all`/`Account.find` will always include every row it previously did (i.e., breaks on the new default scope, not on destroy) | P1 | AC-002 makes the default-scope exclusion an explicit, tested contract; Story 5's migration guide calls this out as the one behavior change every team *does* need to know about, even though destroy itself is untouched |
| Refine cap or critic disagreement discovered after this plan is frozen | P2 | `ramza-freeze --amend --reason` is the recorded path for any post-freeze correction; no silent edits |

---

## RAMZA governance appendix (audit trail summary)

This specification was produced by walking the full RAMZA cycle mechanically
— every rubric score, tier decision, and gate below is a real `bin/ramza-*`
tool invocation, not self-reported arithmetic.

- **Right-Size:** `ramza-rightsize --files-est 14 --migration --public-api --stakes high` → score 6 → **tier: full**.
- **Scope complexity:** 11/12 → **human_loop**.
- **Explore (4 hypotheses scored):** H1 destroy-override 64.5 (weak) · **H2 decoupled soft-delete 88 (elite, selected)** · H3 discard-gem 78.5 (solid) · H4 archive table 47.5 (weak).
- **Test:** `ramza-lint` clean (full-tier sections present) · `ramza-ears-lint` clean (13/13 criteria).
- **Critic (maker≠checker, mandatory at full tier):** author `ramza-r2-author`, checker `ramza-r2-critic` · refine rubric 4.6/5 (min dim 4) → pass, no refine cycle needed.
- **Assemble confidence:** 79.5% → **VALIDATE** (human review recommended before execution).
- **Scope declared** (13 globs) for post-execution drift watch; **criteria frozen** — SHA-256 `8191ec786cf54f42418c5003680d377d0ef597bd71d6fc2a6c8d088b58e0ca31`.
- **Emission gate:** `ramza-verify-emit` → **passed** (frontmatter contract + ECL v2.0 envelope integrity match).
- **Adherence:** plan_phase 1.0 · plan_order 1.0 · composite 1.0 (clean phase walk, zero skips, zero refine cycles).
- **State/artifacts:** `.spectra/plans/ac003-t2-r2.state.json`, `.criteria.md`, `.envelope.json` (full audit trail; CRYSTALIUM MCP unavailable this session — ingest/session_end gracefully skipped per `agent.md`).

**Bottom line for the reviewer:** the mechanism itself (Story 1) is
low-risk and structurally cannot disturb existing destroy callbacks — that
is the entire point of the selected hypothesis. The two things that
genuinely need a human before rollout are (1) sign-off on the retention
window (Story 4, Risks P0) and (2) resolving every `needs-cross-team-consult`
row that Story 2's real inventory turns up (Risks P0, mechanically gated by
AC-007/AC-008). Both are why Confidence landed at VALIDATE rather than
AUTO_PROCEED, and why complexity routed to human_loop — the plan is decision
ready, not execution-ready without those two check-ins.
