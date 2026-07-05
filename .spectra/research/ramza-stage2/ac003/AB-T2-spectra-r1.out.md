---
eidolon: spectra
version: 4.11.0
kind: spec
status: ready-for-review
created_at: 2026-07-05T10:12:00Z
thread_id: 019f3268-da91-7285-999c-cd8cc412b3cb
target_repos:
  - "<unresolved — no Rails application source found in /tmp/spectra-pilot (Eidolons scaffold only); see CLARIFY Gap G1>"
stories_count: 7
validation_gates_count: 21
evidence_anchors_count: 0
confidence: 0.75
---

# SPEC-2026-07-05-001 — Soft-delete (recoverable deletion) for the `Account` model

**Mission:** Produce a decision-ready specification for adding soft-delete (recoverable deletion) to the `Account` model of a mature Rails application, where `Account` has dependent associations, destroy callbacks other teams rely on, and existing admin tooling that lists records. Deliverable includes user stories, acceptance criteria, an impact assessment of existing call sites, and at least one rejected alternative.

**Methodology:** SPECTRA v4.11.0 — CLARIFY → Scope → Pattern → Explore → Construct → Test → Refine → Assemble
**Tier:** Standard (complexity 9/12 → extended-thinking budget; below the 10–12 TRANCE/human-in-the-loop threshold by one point — flagged explicitly below as a near-miss, not a comfortable margin)
**Read-only invariant honored:** no code, no file edits, no mutations to any target system were made in producing this spec.

---

## Memory pre-flight (mission intake)

Per `agent.md`, an `mcp__crystalium__recall` call was attempted before CLARIFY to surface prior specs, decisions, or known traps relevant to "soft delete," "recoverable deletion," or "Account model" work. **No `mcp__crystalium__*` tools are reachable in this environment** (absent from the available tool surface; no CRYSTALIUM install evidence anywhere under `/tmp/spectra-pilot`). Per the documented graceful-skip rule this is a silent no-op, not a hard failure — SPECTRA is EIIS-standalone-conformant. Planning proceeds without prior-session memory; this is carried into the Pattern phase as a gap, never fabricated as a false match.

---

## CLARIFY

**Trigger:** every new request. **Not skipped** — the mission names a specific model (`Account`) with specific structural hazards (dependent associations, cross-team destroy callbacks, admin tooling) but supplies no target repository, no `Gemfile`, and no view into the actual association graph or callback registrations. That is genuine decision-shaping ambiguity, not cosmetic gap-filling.

**DISCOVER was not warranted.** The goal itself — "add recoverable deletion to `Account`" — is already well-GOALED (a known `CHANGE` to an existing model), so this session goes straight to CLARIFY rather than open-ended elicitation (see `SPEC.md` DISCOVER vs CLARIFY boundary).

**Parse Intent:**
- **WHO:** account owners/end users who benefit from mistake-recoverable deletion; admin/support/ops staff who action deletions and restores through the admin console; engineering teams whose `before_destroy`/`after_destroy` callbacks on `Account` (or its associations) currently fire on hard delete (billing/invoicing cancellation, notification/webhook dispatch, search-index removal are the canonical examples for a mature multi-team Rails app, used here as concrete stand-ins — real callback names must be confirmed against the actual model, see G1).
- **WHAT:** a soft-delete capability on `Account` — mark-as-deleted instead of row removal, excluded from default queries, restorable, with an explicit decision for how dependent associations and existing destroy callbacks behave under the new "discard" path versus the still-existing "destroy" path.
- **WHY:** reduce the blast radius and reversibility gap of account deletion (accidental deletion, support-actioned deletion, self-service account closure) without weakening the guarantees other teams already depend on when a *real*, permanent destroy happens.
- **CONSTRAINTS:** must not silently change the behavior of `Account#destroy` for teams that already rely on its callbacks (explicit mission constraint); must account for `dependent: :destroy` associations rather than leaving orphaned or inconsistently-visible child records; must keep the existing admin listing usable — it must not start silently showing (or silently hiding, without recourse) deleted accounts.

**Identify Gaps:**

| # | Gap | Resolution mode |
|---|-----|------------------|
| G1 | No target repository, `Gemfile`, or model source was supplied, and `/tmp/spectra-pilot` (this consumer project) contains only Eidolons scaffolding — no `app/`, no `Gemfile`, no `Account` model to read. `.spectra/setup/spectra-conventions.md` does not exist. | **[GAP] — cannot be closed interactively this run** (single-shot deliverable, no live user turn). Resolved via explicit, risk-tagged assumptions below, using idiomatic Rails conventions rather than fabricating a fake codebase match. |
| G2 | Whether `account.discard` should cascade to `has_many ..., dependent: :destroy` associations (soft-delete them too) or leave dependents active but reachable only through a now-hidden parent. | **[ASSUMPTION]** — resolved by Explore/Pattern selection (mirror the existing `dependent: :destroy` graph 1:1); mapped to Would-ask Q3 below. |
| G3 | Whether `Account`'s existing `before_destroy`/`after_destroy` callbacks (relied on by other teams) should also fire on `discard`, and whether existing `before_destroy` *guard* clauses (validations that can block a destroy, e.g. "cannot destroy while an active subscription exists") apply equally to `discard`. | **[ASSUMPTION]** — treated as two separate questions (guard parity vs. side-effect parity) because conflating them is exactly the kind of under-specification the Refine cycle below catches. Mapped to Would-ask Q1/Q2. |
| G4 | Retention/purge policy: how long a discarded `Account` is kept before an eventual hard purge, and who owns that policy (compliance/legal). | **[ASSUMPTION]** — out of scope this iteration (see Scope boundaries); no purge job is specified here. |
| G5 | Whether a discarded `Account`'s unique identifiers (email, subdomain/slug — whatever `Account` uniquely validates on) remain reserved (blocking re-registration) or are released once discarded. | **[ASSUMPTION]** — default to "remain reserved" (safer default, avoids identity confusion/collision), flagged for business/compliance review since it is a product decision, not a technical one. |

**Would-ask (≤3, numbered, <200 chars each, per CLARIFY step 3 — recorded for the human reviewer since no live turn is available this run):**
1. Should `Account`'s existing `before_destroy` guard clauses (e.g., blocking destroy with an active subscription) also block `discard`, or can accounts ineligible for hard-destroy still be soft-deleted?
2. Should any current `after_destroy` side-effect callbacks (billing cancellation notice, search de-index, cache purge) also fire on `discard`, or are they exclusively real-destroy behavior until an eventual purge?
3. Should `discard` cascade to dependent associations (soft-delete them too), or leave dependents active but inaccessible via the parent?

**Gather Structural Context:** grepped `/tmp/spectra-pilot` for `account`, `discard`, `paranoia`, `deleted_at`, `Gemfile` — zero implementation hits (Eidolons scaffold files only; confirmed via `find`). No `spectra-conventions.md` to load. Proceeding with well-established, idiomatic Rails soft-delete conventions (see Pattern phase) rather than fabricated project-specific paths; every file path named in Construct below is marked **[ASSUMED]** and must be re-anchored to the real target repo before implementation begins.

**Assess Cognitive Load:** single session sufficient for the specification itself; flag explicitly that *execution* (Construct → real code) is very likely a multi-session, multi-team effort given the cross-team callback dependency (S-3) and the call-site audit (S-4) — this is noted as an execution-planning concern, not a re-scoping of this spec.

**Skip?** No — see gaps above. CLARIFY is complete via documented assumptions and three recorded would-ask questions, which is exactly why Assemble below gates to VALIDATE rather than AUTO_PROCEED.

---

## S — SCOPE

**Intent Type:** `CHANGE` (modify how deletion behaves on an existing, live model) — with `REQUEST`-like characteristics because the target model's current association graph and callback registrations are unknown to this session.

**Complexity Score (4-dimension matrix):**

| Dimension | Score (1–3) | Rationale |
|---|---|---|
| Scope | 1 | Single feature — soft-delete capability for one model — even though it touches several sub-mechanisms (schema, scoping, cascade, admin UI) |
| Ambiguity | 2 | Cascade behavior and callback-firing semantics are genuinely undecided pending team sign-off (G2/G3) |
| Dependencies | 3 | Cross-domain by the mission's own description: the model layer, other teams' destroy-callback side effects (billing/notifications/search), the admin console, plus every codebase call site that queries, destroys, or associates with `Account` |
| Risk | 3 | Explicitly named as critical-path in the mission ("destroy callbacks that other teams rely on") — a wrong scoping choice risks silently breaking another team's feature or exposing/hiding data incorrectly in admin tooling |

**Total: 9/12 → Extended thinking (2× budget).** One point below the 10–12 human-in-the-loop band — see the confidence discussion in Assemble for why this margin is treated as thin rather than comfortable.

**Boundaries:**

| In Scope | Out of Scope | Deferred |
|----------|--------------|----------|
| `discard`/`undiscard` (soft-delete/restore) API on `Account`, distinct from `destroy` | Automated hard-purge job for discarded accounts (G4) | Fast-follow once retention policy (compliance-owned) is defined |
| Default-scope exclusion of discarded accounts + explicit `.with_discarded` escape hatch | Rewriting or removing `Account#destroy`'s existing behavior/callbacks | Not deferred — rejected outright; `destroy` stays exactly as-is (see S-3) |
| Cascade decision for `dependent: :destroy` associations (mirror 1:1, see Explore) | Extending soft-delete to other models beyond `Account` | Fast-follow, same mechanism, once this ships and is observed in production |
| Codebase-wide audit + remediation of read/query call sites affected by the new default scope | Redesigning the admin console's UI beyond a minimal filter/badge/restore affordance | Revisit if support/ops report the minimal UI is insufficient |
| Minimal admin-console support: hide-by-default, filter toggle, restore action | Cross-model rollout of the discard pattern | Deferred to a separate spec once this pattern is validated |
| Authorization boundary + audit trail for discard/undiscard/destroy actions | Automated release of reserved identifiers (email/slug) on discard (G5) | Revisit if product/compliance decides identifiers should be released |

**Assumptions (risk-tagged):**

1. **[ASSUMPTION]** `Account` has one or more `has_many ..., dependent: :destroy` associations, and one or more `before_destroy`/`after_destroy` callbacks that other teams rely on (both stated directly in the mission). **Risk if wrong:** if `Account` turns out to have no dependent associations or no cross-team callbacks at all, S-2 and S-3 collapse to trivial no-ops — low risk, this is a "spec was more cautious than necessary" direction, not a dangerous one.
2. **[ASSUMPTION]** Discard should mirror the *existing* `dependent: :destroy` association graph 1:1 for cascade purposes (resolves G2/Q3, selected in Explore below). **Risk if wrong:** if the real business intent is "discard should never cascade, dependents stay active," S-2 is rebuilt as a no-cascade story — moderate rework, contained to one story.
3. **[ASSUMPTION]** Existing `before_destroy` *guard* clauses apply equally to `discard` (business-rule parity); existing `after_destroy` *side-effect* callbacks do **not** automatically fire on `discard` and must be explicitly, individually opted back in per callback after business review (resolves G3/Q1+Q2). **Risk if wrong:** if a team expected their side-effect callback (e.g., billing cancellation notice) to fire on discard by default, its absence could cause a real business-process gap (e.g., a "discarded" account still gets billed) — tagged P0 in S-3 precisely because this is the highest-consequence assumption in the spec.
4. **[ASSUMPTION]** Discarded accounts' unique identifiers remain reserved by default (resolves G5). **Risk if wrong:** low — reversing this later (releasing identifiers) is an additive follow-up, not a breaking migration.
5. **[ASSUMPTION]** Retention/purge policy is out of scope for this iteration (resolves G4). **Risk if wrong:** low for this spec's own delivery; a real compliance deadline (e.g. a "right to erasure" SLA) could force purge into scope sooner than assumed — flagged for human review at the VALIDATE gate.

**Stakeholders:** account owners/end users (indirect beneficiaries of recoverability); admin/support/ops staff who action and review deletions (primary reviewers of S-5); engineering teams whose destroy callbacks currently fire on `Account#destroy` — billing/invoicing, notifications, search-indexing, or whichever teams actually own callbacks on the real model (primary reviewers of S-3, must sign off on Assumption #3 before Construct is trusted); the engineer(s) implementing (review Construct output); compliance/legal (approval chain for the deferred retention/purge policy, G4/G5).

---

## P — PATTERN

**Query memory:** unavailable this session (see Memory pre-flight) — **[GAP]**, not a false negative; no prior-failure catalog to surface for this feature area.

**Query codebase:** zero matches in `/tmp/spectra-pilot` (see CLARIFY G1) — no `Gemfile`, no model source to confirm whether a soft-delete gem is already present or preferred. Falling back to well-established Rails-ecosystem conventions for "recoverable deletion," ranked by similarity to this ask (MMR: `similarity − 0.3 × redundancy`, top candidates shown):

| Pattern | Similarity | Why |
|---|---|---|
| `discard` gem convention (`Discard::Model`: `discarded_at`, `.kept`/`.discarded` scopes, `discard!`/`undiscard!`, `before_discard`/`after_discard` hooks) | 84% | Closest possible fit: purpose-built for exactly "soft-delete without touching `destroy`'s semantics," which is the mission's explicit constraint |
| `paranoia` gem convention (overrides `destroy` itself via `default_scope`, monkeypatches deletion) | 76% | Solves recoverability but by *redefining* `destroy`'s meaning — directly at odds with the mission's "callbacks other teams rely on" constraint, since `destroy` callbacks would now fire on what is semantically a soft-delete |
| Hand-rolled `deleted_at:datetime` column + manual `default_scope` + manual restore method, no gem dependency | 70% | Same shape as `discard`, more code to own, zero new dependency — a legitimate no-gem variant of the same pattern family |
| Event-sourced/state-machine deletion lifecycle (general software pattern, not Rails-specific) | 55% | Solves the callback-coupling problem by replacing synchronous callbacks with async events entirely — bigger reframing than this ask requires |
| Archive-table-on-destroy / audit-copy pattern (general audit-log pattern) | 48% | Solves auditability, not recoverability-in-place; doesn't satisfy "admin tooling that lists records" needing to show/filter/restore |

**No pattern reaches the 85% USE_TEMPLATE threshold** (no in-repo template exists to apply verbatim — G1). **Strategy: ADAPT (60–84% band)** — adopt the `discard`-gem-shaped API (`discarded_at`, `kept`/`discarded` scopes, `discard!`/`undiscard!`, distinct `before_discard`/`after_discard` hooks) as the skeleton. Whether the real implementation takes the `discard` gem as a literal dependency or hand-rolls the equivalent API is an implementation-detail decision left to Construct/execution — this spec specifies the *behavior contract*, not the dependency choice, and explicitly rejects `paranoia`'s destroy-redefinition approach because it conflicts with the mission's core constraint (see Explore, H2 selection and rationale).

**Catalog Failure Patterns:** none available (memory unreachable this session) — documented as a gap rather than silently skipped.

---

## E — EXPLORE

**Trigger:** before Construct. Not skipped. 4 genuinely distinct hypotheses generated (within the 3–5 range; conservative + pattern-leveraging + innovative + risk-minimizing).

**Observations (5 angles):** (1) contract safety — the single most important property this spec must prove is that `Account#destroy` and its existing callbacks are **completely unchanged** for every other team; (2) omission risk — cascade and query-boundary correctness live or die on *exhaustively* enumerating associations and call sites, not on cleverness; (3) admin usability — "existing admin tooling that lists records" must keep working on day one, not just eventually; (4) reversibility — a "soft" delete that can't be cleanly and completely restored (including cascaded dependents) isn't actually solving the stated problem; (5) coordination cost — this feature's riskiest edges (S-3, callback semantics) are a cross-team negotiation, not a purely technical decision.

### Hypothesis scoring (7-dimension weighted rubric, 1–10 per dimension → weighted /100)

| # | Hypothesis | Align 25% | Correct 20% | Maintain 15% | Perf 15% | Simple 10% | Risk 10% | Innov 5% | **Total** |
|---|---|---|---|---|---|---|---|---|---|
| H1 | **Conservative** — hand-rolled `discarded_at` column + manual scopes/hooks; cascade decided per-association case-by-case during Construct, no automatic mirroring rule | 8 | 8 | 8 | 9 | 9 | 7 | 3 | **79.0** |
| H2 | **Pattern-leveraging** — `discard`-gem-shaped API; cascade mirrors the *existing* `dependent: :destroy` graph 1:1 via explicit `after_discard`/`after_undiscard` hooks, keeping `destroy` and its callbacks byte-for-byte unchanged | 9 | 8 | 9 | 8 | 8 | 8 | 5 | **82.5** |
| H3 | **Innovative** — replace `Account`'s synchronous destroy-callback contract with an event-sourced lifecycle (`status: active\|discarded\|purged` + domain events other teams subscribe to async instead of `before_destroy`/`after_destroy`) | 7 | 6 | 6 | 7 | 3 | 4 | 9 | **60.5** |
| H4 | **Risk-minimizing (archive-on-destroy)** — leave `destroy` fully as-is; add a parallel archive table that snapshots the account + dependents before every real destroy, for out-of-band recovery | 4 | 6 | 5 | 6 | 5 | 6 | 4 | **51.5** |

Spread is 82.5→51.5 (31-point range) — **not** within the 5% "insufficient differentiation" band; the set is well-differentiated and no re-observation is needed. H1/H2 sit 3.5 points apart — both expanded below per the "expand top 2" rule.

### Expand top 2

**H1 — Hand-rolled, manual cascade (conservative).**
- *File impact:* small-to-medium — one `deleted_at`/`discarded_at` column migration, model-level scope/method additions, per-association cascade decisions made by hand during Construct.
- *Dependency chain:* correctness depends entirely on the implementer manually enumerating every `dependent: :destroy` association and deciding cascade behavior for each — no automatic tie to the existing association metadata, so a missed association silently produces an inconsistent state (dependents orphaned-but-not-flagged).
- *Edge cases:* same association-enumeration risk as H2, but without H2's structural safeguard of deriving the cascade set programmatically from `reflect_on_all_associations` (or equivalent), making a future new `dependent: :destroy` association more likely to be forgotten from the cascade set.

**H2 — `discard`-shaped API, cascade mirrors `dependent: :destroy` 1:1 (pattern-leveraging).**
- *File impact:* comparable to H1 — model concern (mixin/module), migration, explicit cascade hook enumerating today's `dependent: :destroy` associations.
- *Dependency chain:* ties the cascade set directly to the *same declaration* (`dependent: :destroy`) that already defines hard-delete's blast radius, so the two lists (hard-delete cascade, soft-delete cascade) can be diffed/asserted equal in a test — turning "did we miss an association" into a mechanically checkable property instead of a manual-review property (directly strengthens S-2's testability and the Dependency-layer risk in Test below).
- *Edge cases:* same underlying risk as H1 (new associations must remember to declare cascade intent) but with a test-enforceable invariant available (`dependent: :destroy` associations count == cascade-hook association count), and a widely-recognized ecosystem vocabulary (`kept`/`discarded`/`discard!`/`undiscard!`) that future engineers on this "mature" codebase are likely to already recognize.

### Selection

**Selected: H2 (`discard`-shaped API, cascade mirrors `dependent: :destroy`).** It scores highest overall (82.5) and, critically, is the only hypothesis that turns the cascade-completeness risk — the single biggest way this feature could silently misbehave — into something mechanically testable rather than something a reviewer has to trust by inspection. It also keeps `destroy` and 100% of its existing callbacks completely untouched by construction (the mission's explicit, non-negotiable constraint), because `discard` is additive vocabulary living beside `destroy`, not a redefinition of it (unlike the rejected `paranoia`-style approach surfaced in Pattern).

**Rejected alternatives (documented per E-phase step 6, prevents re-exploration in replanning):**

- **H1 (hand-rolled, manual per-association cascade) — rejected for this spec, not permanently.** Second-highest score and a legitimate zero-new-dependency alternative. **Re-open trigger:** if the real codebase has a hard policy against new gem dependencies, H1 becomes the default fallback — its behavior contract (S-1 through S-7) is otherwise identical to H2; only the cascade-enumeration mechanism (manual vs. metadata-derived) changes.
- **H3 (event-sourced lifecycle, async decoupling) — rejected for this spec, deferred as a future direction.** Elegant longer-term answer to "other teams depend on synchronous callbacks," but it *reframes* the mission's constraint (preserve existing callback behavior) into a bigger ask (migrate other teams off synchronous callbacks entirely) — that is a multi-team migration project, not a soft-delete feature, and scored lowest on Simplicity (3) and Risk (4) accordingly. **Re-open trigger:** if a separate, explicitly-scoped initiative to decouple `Account`'s destroy-time side effects from synchronous callbacks is already planned, this spec's S-3 becomes a stepping stone toward it rather than a permanent design.
- **H4 (archive-on-destroy, no in-place soft-delete) — rejected outright.** It does not deliver "recoverable deletion" as the mission and the admin-tooling requirement describe it: the account is still fully removed from `accounts` and from every default relation the instant `destroy` runs, so admin tooling has nothing to list, filter, or restore in-place — recovery would mean re-inserting from an archive dump, a fundamentally different (and slower, riskier) operation than "undiscard." No re-open trigger identified; this is a rejection on fit, not on missing information.

---

## C — CONSTRUCT

**Hierarchy:**

```
THEME    Data Retention & Recoverability
└─ PROJECT  P-1  Account Soft-Delete Capability
   └─ FEATURE F-1  Recoverable deletion (discard/restore) for the Account model
      ├─ STORY S-1  Schema & model foundation (discard API, default scope)
      ├─ STORY S-2  Cascade behavior for dependent associations
      ├─ STORY S-3  Destroy-callback contract preservation & business-guard audit
      ├─ STORY S-4  Query-boundary enforcement & read-call-site audit
      ├─ STORY S-5  Admin console: filter, badge, restore
      ├─ STORY S-6  Authorization boundary & audit trail
      └─ STORY S-7  Docs, runbook, changelog
```

All 7 stories pass INVEST (Independent within the sequencing below, Negotiable on exact wording, Valuable to a named actor, Estimable at the timeboxes below, Small ≤5d each, Testable via the GIVEN/WHEN/THEN sets below).

**Execution sequence (dependency-ordered):**

```
Phase 1:  S-1
Phase 2:  S-2  ‖  S-3  ‖  S-4      (parallel — distinct concerns, all depend only on S-1)
Phase 3:  S-5  ‖  S-6              (parallel — both consume S-2/S-3/S-4 outputs)
Phase 4:  S-7
```

---

#### 📋 STORY: S-1 Schema & model foundation

> 🔴 P0

**Description:** As an engineer implementing this feature, I want `Account` to gain a `discarded_at` column and a `discard`/`undiscard` API distinct from `destroy` so that every downstream story has a stable foundation to build on.
**Timebox:** 1d
**Risk:** P0 (blocks release — every downstream story depends on this)

**Action Plan:**
1. **Migrate:** add `discarded_at:datetime` (nullable, indexed) to `accounts`. No existing column, index, or constraint is altered.
2. **Extend:** `Account` model with `discard!`/`undiscard!` methods and `kept`/`discarded` query scopes; make `kept` the implicit default for unscoped queries (default scope excludes discarded rows unless a caller explicitly opts into `.with_discarded`).
3. **Test:** existing `Account` creation/query/update specs pass unchanged (regression guard); a freshly created `Account` is `kept` (not discarded) by default.

**Acceptance Criteria:**
- [ ] GIVEN the soft-delete migration runs WHEN it completes THEN a `discarded_at:datetime` column (nullable, indexed) SHALL be added without altering any existing column or index
- [ ] GIVEN an `Account` with `discarded_at` set WHEN any default (unscoped-by-caller) query is run THEN that `Account` SHALL be excluded from the result set unless the caller explicitly requests discarded records via `.with_discarded`
- [ ] GIVEN a brand-new `Account` WHEN created THEN `discarded_at` SHALL default to `nil` (kept), with zero behavior change for any existing code that predates this feature

**Technical Context:**
- **Pattern:** `discard`-gem-shaped API (Pattern phase, ADAPT)
- **Files:** `[ASSUMED — confirm against target repo]` `app/models/account.rb`, `db/migrate/*_add_discarded_at_to_accounts.rb`
- **Dependencies:** none (foundation story)

**Agent Hints:**
- **Class:** Builder (speed-class implementation)
- **Context:** existing `Account` model file, any existing model concerns/mixins used elsewhere for consistency
- **Gates:** P0 regression test (existing Account spec suite green, unmodified) must pass before merge

---

#### 📋 STORY: S-2 Cascade behavior for dependent associations

> 🔴 P0 — second-highest-risk story in this spec

**Description:** As an engineer relying on `Account`'s existing `dependent: :destroy` associations, I want `discard` to cascade to those same associations so that a discarded account doesn't leave its dependents in an inconsistent, silently-orphaned state.
**Timebox:** ≤3d
**Risk:** P0 (an incomplete cascade is the primary way this feature can silently misbehave)

**Action Plan:**
1. **Audit:** enumerate every association on `Account` declared `dependent: :destroy` (programmatically, via `reflect_on_all_associations`, not by manual code reading alone — see Impact Assessment below).
2. **Create:** an `after_discard` hook that discards every association from that enumerated set, and a matching `after_undiscard` hook that restores only the dependents that were auto-discarded by this same cascade (dependents already independently discarded before the cascade remain discarded).
3. **Test:** a structural assertion that the cascade-hook association set is *identical* to the `dependent: :destroy` association set (this is H2's core testability win from Explore) — the test breaks the build if a future association adds `dependent: :destroy` without updating the cascade hook, or vice versa.

**Acceptance Criteria:**
- [ ] GIVEN `Account` has one or more `has_many ..., dependent: :destroy` associations WHEN `account.discard!` is called THEN every one of those associations SHALL also be discarded via an explicit, enumerated `after_discard` hook — never via the discard mechanism's own destroy machinery (there is none; `destroy` is untouched)
- [ ] GIVEN a dependent association is **not** declared `dependent: :destroy` (e.g., `dependent: :nullify` or no `dependent` option) WHEN the parent `Account` is discarded THEN that association SHALL be left untouched, and this exclusion SHALL be explicitly listed in the Impact Assessment table below — never silently omitted
- [ ] GIVEN an `Account` and its cascade-discarded dependents WHEN `account.undiscard!` is called THEN only the dependents auto-discarded by this same cascade SHALL be restored; dependents discarded independently before the cascade SHALL remain discarded

**Technical Context:**
- **Pattern:** cascade mirrors `dependent: :destroy` 1:1 (Explore, H2 selection rationale)
- **Files:** `[ASSUMED]` `app/models/account.rb` (association declarations + new hooks)
- **Dependencies:** S-1

**Agent Hints:**
- **Class:** Reasoner + Explorer (an exhaustive association audit is the risk-critical step — an ATLAS-equivalent scout pass to enumerate every `dependent: :destroy` declaration on `Account` before implementation is strongly recommended, mirroring S-4's call-site audit approach)
- **Context:** full `Account` model file and every model that `belongs_to :account` or is otherwise reachable from it
- **Gates:** P0 — structural test asserting cascade-hook association set == `dependent: :destroy` association set, not just code review

---

#### 📋 STORY: S-3 Destroy-callback contract preservation & business-guard audit

> 🔴 P0 — highest-risk story in this spec (mission's explicit constraint)

**Description:** As an engineer on a team whose feature depends on `Account`'s existing `before_destroy`/`after_destroy` callbacks, I want `destroy`'s behavior and callback contract to remain completely unchanged, and I want a deliberate, reviewed decision — not an accident — about which of those callbacks (if any) also apply to `discard`.
**Timebox:** ≤3d
**Risk:** P0 (getting this wrong either breaks another team's feature silently, or produces a "discard" that quietly reproduces destroy's side effects when it shouldn't)

**Action Plan:**
1. **Audit:** enumerate every `before_destroy`/`after_destroy` callback currently registered on `Account` (and on associations reachable via `dependent: :destroy`, since S-2 cascades to them), classifying each as either a **business-rule guard** (can block the operation, e.g. "cannot destroy with an active subscription") or a **side-effect** (fires a downstream action, e.g. billing cancellation notice, search de-index, cache purge).
2. **Decide + Configure:** per Scope Assumption #3 — guard clauses apply equally to `discard` by default (business-rule parity); side-effect callbacks do **not** automatically fire on `discard` and must be individually, explicitly opted back in per callback only after the owning team reviews and signs off. Record each decision by callback name.
3. **Test:** a callback-registration test proving `destroy`'s current callback list is byte-for-byte unchanged after this feature ships; a separate test proving `discard` fires only the explicitly-opted-in subset.

**Acceptance Criteria:**
- [ ] GIVEN `account.destroy` (the real, permanent path) is called THEN 100% of currently-registered `before_destroy`/`after_destroy` callbacks SHALL continue to fire exactly as before this feature ships, verified by an unchanged callback-registration test
- [ ] GIVEN a `before_destroy` guard clause currently blocks hard-destroy under a business condition WHEN `account.discard!` is called under the same condition THEN `discard!` SHALL enforce an equivalent guard by default, unless a named, reviewed business decision explicitly overrides it for that specific guard — no guard is silently dropped
- [ ] GIVEN `Account`'s existing `after_destroy` side-effect callbacks WHEN `account.discard!` is called THEN none of those callbacks SHALL fire unless the owning team has explicitly reviewed and opted that specific callback back in — the default is "discard is silent," never "discard accidentally reproduces destroy's side effects"

**Technical Context:**
- **Pattern:** additive hook set (`before_discard`/`after_discard`), never a redefinition of `before_destroy`/`after_destroy` (Explore — this is precisely why `paranoia`-style destroy-redefinition was rejected in Pattern)
- **Files:** `[ASSUMED]` `app/models/account.rb` and any concern modules mixed into it; `[ASSUMED]` cross-team callback owners' files (billing/notifications/search — names must be confirmed against the real model)
- **Dependencies:** S-1

**Agent Hints:**
- **Class:** Reasoner (cross-team coordination and audit) + Reviewer (each affected team should review its own callback's classification)
- **Context:** full `Account` callback registration list; whoever owns each dependent team's callback should review this story's decisions before merge, not just the implementer
- **Gates:** P0 — every registered callback has an explicit, recorded classification (guard vs. side-effect) and an explicit discard-behavior decision; zero callbacks left unclassified

---

#### 📋 STORY: S-4 Query-boundary enforcement & read-call-site audit

> 🔴 P0 — largest-scope story (call-site sprawl across a mature codebase)

**Description:** As an engineer maintaining any code that queries, iterates, or serializes `Account` records, I want every existing call site audited against the new default scope so that no code path starts silently seeing fewer (or, via an unsafe override, more) accounts than it correctly should.
**Timebox:** ≤5d
**Risk:** P0 (dependency-blindness here reproduces exactly the "build breaks after complete execution" failure mode — see Test's adversarial checklist)

**Action Plan:**
1. **Audit:** enumerate every `Account.find`/`Account.where`/`Account.all`/association-based lookup (`user.account`, etc.), every background job/rake task/console script that iterates accounts, and every API serializer or admin/report query that exposes account data.
2. **Classify:** each call site as either "correctly scoped by the new default" (no change needed) or "requires an explicit `.with_discarded`/`.discarded` override" (e.g., a compliance export that must include discarded accounts).
3. **Test:** for every call site requiring an override, add or update a test proving the override behaves as intended; for call sites left on the new default, add a regression test proving discarded accounts are now excluded where they previously would have appeared.

**Acceptance Criteria:**
- [ ] GIVEN the codebase-wide audit of `Account.find`, `Account.where`, `Account.all`, and association-based lookups WHEN each call site is classified THEN every call site SHALL be tagged as either "correctly scoped by default" or "requires explicit `.with_discarded` override," with zero call sites left unclassified
- [ ] GIVEN a background job, rake task, or console script currently iterates all accounts (e.g. `Account.find_each`) WHEN the default-scope change ships THEN each such job SHALL be explicitly reviewed and, where it must still process discarded rows (e.g., a compliance export), updated to opt in via `.with_discarded`
- [ ] GIVEN any API serializer or external-facing endpoint exposes `Account` records WHEN the default scope changes THEN discarded accounts SHALL NOT be exposed through any endpoint that did not explicitly opt in to `.with_discarded`

**Technical Context:**
- **Pattern:** exhaustive call-site audit (Test-phase Dependency layer, directly informs the Impact Assessment section below)
- **Files:** `[ASSUMED]` entire `app/`, `lib/tasks/`, `app/serializers/` or equivalent — this story's scope is "everywhere `Account` is queried," not a fixed file list
- **Dependencies:** S-1

**Agent Hints:**
- **Class:** Explorer (retrieval-class — a full-codebase grep/AST sweep for `Account` query call sites) handing off to Builder for remediation
- **Context:** codebase-wide search for `Account.` usage; existing background-job registry/scheduler config
- **Gates:** P0 — audit table (Impact Assessment) has zero "unclassified" rows before this story is marked done

---

#### 📋 STORY: S-5 Admin console: filter, badge, restore

> 🟡 P1

**Description:** As an admin/support operator using the existing admin console that lists `Account` records, I want discarded accounts hidden by default but reviewable and restorable through an explicit filter, so that my day-to-day workflow doesn't change but recovery is still possible.
**Timebox:** ≤3d
**Risk:** P1 (degrades operator experience if wrong; does not itself risk data loss since S-1–S-4 already guarantee recoverability at the model layer)

**Action Plan:**
1. **Modify:** the admin `Account` listing's underlying query to rely on the new default scope (S-1) — discarded accounts disappear from the default view with no code change needed beyond removing any explicit `Account.unscoped`/`.all` bypass, if present.
2. **Extend:** the listing with a "Show discarded" filter/toggle that queries `.discarded` explicitly, rendering a clear visual indicator (badge/row styling) distinguishing discarded from active accounts.
3. **Create:** a "Restore" action on discarded rows that calls `account.undiscard!` (cascading per S-2) and reflects the account back in the default listing immediately.

**Acceptance Criteria:**
- [ ] GIVEN the admin `Account` listing currently lists all accounts WHEN this feature ships THEN the default listing SHALL exclude discarded accounts, matching the new model-level default scope
- [ ] GIVEN an admin operator wants to review deleted accounts WHEN they toggle a "Show discarded" filter THEN the listing SHALL display discarded accounts with a clear visual indicator distinguishing them from active accounts
- [ ] GIVEN a discarded account is visible under the "Show discarded" filter WHEN the admin operator clicks "Restore" THEN the account (and its cascade-discarded dependents per S-2) SHALL be undiscarded and reappear in the default listing immediately

**Technical Context:**
- **Pattern:** minimal filter/badge/restore affordance (Scope boundary — full UI redesign explicitly out of scope)
- **Files:** `[ASSUMED]` `app/controllers/admin/accounts_controller.rb`, `app/views/admin/accounts/index.html.erb` (or equivalent admin-framework views if the console is built on ActiveAdmin/RailsAdmin/similar — confirm against real repo)
- **Dependencies:** S-2, S-3, S-4

**Agent Hints:**
- **Class:** Builder
- **Context:** existing admin console listing/filter conventions, whatever admin framework (custom, ActiveAdmin, RailsAdmin) is actually in use
- **Gates:** manual review by an admin/support-tooling owner; P1 UI regression test on the default (non-discarded) listing

---

#### 📋 STORY: S-6 Authorization boundary & audit trail

> 🟡 P1

**Description:** As a compliance/support stakeholder, I want every discard, undiscard, and destroy action on `Account` to be permission-gated exactly as destroy is today, and recorded in a queryable audit trail, so that "who deleted this account and when" is always answerable.
**Timebox:** ≤2d
**Risk:** P1 (an authorization gap here could let an unprivileged actor discard/undiscard accounts even though today's destroy path is already gated — a real, if secondary, risk)

**Action Plan:**
1. **Extend:** the existing authorization layer that gates `destroy` to also gate `discard!`/`undiscard!` with the same permission boundary (no new, looser permission tier is introduced for discard).
2. **Create:** an audit record (actor, action, timestamp, account id) persisted on every discard/undiscard/destroy action.
3. **Test:** authorization tests for an unprivileged actor attempting each of the three actions; audit-trail read test confirming a compliance/support query can answer "who did this and when" from persisted data alone.

**Acceptance Criteria:**
- [ ] GIVEN a user without admin/ops-tier permissions WHEN they attempt to call `discard!`, `undiscard!`, or `destroy` on an `Account` THEN the action SHALL be rejected by the existing authorization layer, unchanged in its permission boundary from today's `destroy` guard
- [ ] GIVEN any discard, undiscard, or destroy action succeeds WHEN it completes THEN an audit record (actor, action, timestamp, account id) SHALL be persisted, queryable by the admin audit trail
- [ ] GIVEN the audit trail exists WHEN a compliance or support request asks "who deleted this account and when" THEN the answer SHALL be answerable from persisted audit data without needing application logs

**Technical Context:**
- **Pattern:** reuse existing authorization/audit conventions, extended rather than replaced
- **Files:** `[ASSUMED]` existing authorization policy file for `Account` (Pundit policy / CanCanCan ability / equivalent), `[ASSUMED]` audit-log model or table if one already exists, else new minimal `AccountAuditEvent`
- **Dependencies:** S-1, S-3

**Agent Hints:**
- **Class:** Builder + Reviewer (security-sensitive; a second reviewer on the authorization diff is recommended)
- **Context:** existing authorization policy/ability definitions for `Account#destroy`
- **Gates:** P1 — authorization regression test (unprivileged rejection) and audit-trail read test both green

---

#### 📋 STORY: S-7 Docs, runbook, changelog

> 🟢 P2

**Description:** As a new team member or on-call/support engineer, I want the discard/restore API, its cascade contract, and its callback-preservation guarantee documented so that I can discover and trust the feature without reading every line of source.
**Timebox:** 1d
**Risk:** P2 (cosmetic/discoverability — does not block core functionality)

**Action Plan:**
1. **Modify:** in-repo model documentation (README section or model-level doc comment) describing the discard/restore API, the cascade contract (S-2), and the callback-preservation guarantee (S-3).
2. **Modify:** CHANGELOG noting the new default-scope behavior change as the single most call-site-impacting change in this release (per S-4's audit).
3. **Modify:** admin/support runbook with the discard/restore workflow and a named contact for the still-deferred hard-purge/retention policy (G4).

**Acceptance Criteria:**
- [ ] GIVEN the feature ships WHEN a developer reads the `Account` model's documentation THEN the discard/restore API and its cascade + callback-preservation contract (S-2, S-3) SHALL be documented in-repo
- [ ] GIVEN the feature ships WHEN the changelog is updated THEN it SHALL note the new default-scope behavior change as the single most call-site-impacting change in this release
- [ ] GIVEN the admin/support runbook exists WHEN this feature ships THEN it SHALL be updated with the discard/restore workflow and a named contact for the deferred retention/purge policy

**Technical Context:**
- **Pattern:** n/a — documentation story
- **Files:** `[ASSUMED]` model doc comment / `README.md`, `CHANGELOG.md`, `[ASSUMED]` `docs/runbooks/account-lifecycle.md`
- **Dependencies:** S-1, S-2, S-3, S-4, S-5, S-6 (documents final, shipped behavior)

**Agent Hints:**
- **Class:** Scriber (IDG-equivalent, per this project's wired Eidolons roster)
- **Context:** final behavior from S-1–S-6
- **Gates:** reviewed by runbook owner

---

## Impact Assessment — Existing Call Sites

Directly answering the mission's "impact assessment of existing call sites" requirement. Every row below is a *category* of call site this feature can affect; exact file:line citations are unavailable this session (no application source present, G1 — `evidence_anchors_count: 0` in this spec's frontmatter is accurate, not an oversight) and must be filled in by S-4's audit against the real codebase.

| # | Call-site category | Current behavior | Impact once this ships | Action required | Owning story |
|---|---|---|---|---|---|
| 1 | Direct queries: `Account.find`, `Account.where`, `Account.all` | Returns all rows, including any that would later be discarded | Discarded accounts silently excluded unless the caller opts in | Classify every call site; add `.with_discarded` where intentional inclusion is needed | S-4 |
| 2 | `account.destroy` / `account.destroy!` call sites | Permanently removes the row and fires all registered destroy callbacks | **Unchanged** — this is the explicit non-negotiable constraint | Confirm each such call site's intent: is "permanent removal" actually desired, or should it migrate to `discard!`? | S-3, S-4 |
| 3 | `has_many ..., dependent: :destroy` associations declared on `Account` or referencing it | Child rows are destroyed when the parent is destroyed | Two independent paths now exist: `destroy` still cascades-destroys exactly as today; `discard!` cascades-discards the same set (S-2) | Enumerate the association set once, reuse it for both the existing destroy cascade and the new discard cascade's test assertion | S-2 |
| 4 | `before_destroy`/`after_destroy` callbacks on `Account` (business guards + cross-team side effects) | Fire synchronously on every `destroy` | **Unchanged on `destroy`**; a curated, explicitly-reviewed subset applies to `discard!` (S-3 Assumption #3) | Per-callback classification and sign-off from the owning team | S-3 |
| 5 | Admin console listing, filters, and CSV/report exports of `Account` | Lists/exports all accounts | Discarded accounts drop out of default views/exports; some exports (e.g., compliance) may need explicit inclusion | Audit each admin/report query; add filter + restore UI | S-4, S-5 |
| 6 | Background jobs / rake tasks / console scripts iterating `Account.find_each` or similar | Processes every row | May start silently skipping discarded rows, which is correct for most jobs (e.g., billing runs) but wrong for others (e.g., a compliance data export) | Per-job review and explicit `.with_discarded` opt-in where required | S-4 |
| 7 | API serializers / external-facing endpoints exposing `Account` | Serializes whatever the underlying query returns | Must guarantee discarded accounts never leak through an endpoint that didn't explicitly opt in | Audit every serializer/endpoint touching `Account` | S-4 |
| 8 | Uniqueness validations on `Account` (email, subdomain/slug, or equivalent) | Enforced against all rows | Ambiguous unless decided: does a discarded account's identifier still block re-registration? | Default to "remains reserved" (Scope Assumption #4/G5); flagged for business/compliance review | S-1 (schema), Scope §G5 |
| 9 | Associations declared **without** `dependent: :destroy` (e.g. `dependent: :nullify`, or no option) | Independent of parent's destroy | **Not** cascaded by `discard!` under the H2 selection — must be explicitly documented, not silently forgotten | Document the exclusion list explicitly in S-2's deliverable | S-2 |

**Dependency-layer note (feeds Test §3 below):** rows 1, 2, 5, 6, 7 above cannot be reduced to a fixed file list without the real codebase (G1) — this is the same structural gap that keeps this spec's Dependency-layer Test result at ⚠ rather than ✓, and the same reason S-4 is scoped as an audit-and-remediate story (≤5d) rather than a fixed, enumerable checklist.

---

## T — TEST (6-layer verification)

| # | Layer | Result |
|---|---|---|
| 1 | **Structural** | ✓ Hierarchy intact (Theme→Project→Feature→Story), no orphaned tasks, stories independent modulo the documented sequencing in Construct |
| 2 | **Self-Consistency** | ✓ See below — 3 alternative decompositions, ~75% overlap → HIGH confidence, stable |
| 3 | **Dependency** | ⚠ Partial — call sites (S-4) and cascade/callback sets (S-2, S-3) cannot be enumerated against a real codebase (G1); flagged, not silently assumed complete. Migration path: additive-only (`discarded_at` column, nullable, no data migration needed — existing rows default to kept) |
| 4 | **Constraint** | ✓ Timeboxes realistic (all ≤5d); NFR "destroy and its callbacks are unchanged" explicit in S-3 AC1; security/compliance addressed in S-6 (authorization parity, audit trail) and Scope §G4/G5 (retention, identifier reservation) |
| 5 | **Process Reward** | ✓ Ordering (foundation → cascade/callback/query-audit in parallel → admin/auth polish → docs) proves the two highest-consequence properties — cascade completeness and callback non-interference — before any UI or documentation polish is layered on top |
| 6 | **Adversarial** | ✓ See checklist below |

**Self-Consistency check (3 alternative decompositions):**

- **Decomposition A (this spec):** schema-foundation / cascade / callback-preservation / query-audit / admin-console / auth-and-audit / docs — 7 stories, grouped by feature slice.
- **Decomposition B:** "core discard mechanics" (merges S-1+S-2+S-3) / "call-site remediation" (S-4) / "operator experience" (merges S-5+S-6) / docs — 4 stories, grouped by delivery bundle.
- **Decomposition C:** grouped by risk surface instead — "data-model risk" (S-1, S-2) / "cross-team contract risk" (S-3) / "read-path risk" (S-4) / "human-facing risk" (S-5, S-6) / docs — 5 stories, same coverage on a different axis.

All three surface the same underlying concepts (scoped schema foundation, cascade correctness, callback-contract preservation, call-site remediation, operator-facing UI, authorization/audit, docs) — estimated **~75% story-content overlap** → **HIGH confidence, decomposition is stable.** Decomposition A was kept because P0/P1/P2 risk tags map cleanly onto feature slices, and because S-3's cross-team sign-off requirement is clearer as its own story than folded into a larger "core mechanics" bundle (Decomposition B) where it could be under-weighted relative to its actual risk.

**Adversarial checklist (Failure Taxonomy, `scoring.md`):**

| Failure mode | Checked | Finding |
|---|---|---|
| Under-specification | ✓ | S-3's guard-clause-parity rule was originally an unconditional hard requirement with no override path — fixed in Refine below |
| Over-specification | ✓ | No rigid constraint blocks a valid implementation; file paths marked `[ASSUMED]`, gem-vs-hand-rolled choice left open (Pattern phase) |
| Dependency Blindness | ⚠ | Real association graph and call-site enumeration are unknown (G1) — mitigated by requiring an explicit Explorer/audit pass before S-2/S-4 implementation starts, not by pretending the lists are already known |
| Assumption Drift | — | No earlier-phase discovery yet invalidates a later step; re-open triggers documented for H1/H3 if G2/G3 resolve differently |
| Scope Creep | ✓ | Boundary table enforced; retention/purge (H-adjacent, G4), cross-model rollout, and admin UI redesign explicitly kept out |
| Premature Optimization | ✓ | Complexity 9/12 did not trigger over-engineering; H3 (most "sophisticated") was rejected precisely for over-reframing a scoped feature into a migration project |
| Stale Context | n/a | No prior file reads to go stale; this is a fresh cycle |

**Gate:** Minor gaps only (Dependency layer ⚠, one adversarial ⚠, same root cause: unknown target repo) → **Refine (1 cycle).**

---

## R — REFINE

**Cycle 1 diagnosis:** Test surfaced two related gaps: (a) S-3's guard-clause-parity rule was originally stated as an unconditional requirement ("guards apply to discard, period"), which is actually a form of over-specification risk in disguise — a real business might legitimately want a guard to behave differently for discard than for destroy (e.g., allowing a "pause" via discard on an account that couldn't be hard-destroyed), and an unconditional rule would block that without recourse; (b) S-2's handling of non-cascaded associations (those without `dependent: :destroy`) wasn't originally required to be *documented*, only implicitly excluded, risking a silent omission that looks identical to an oversight.

**Root cause:** both gaps trace back to treating "mirror existing behavior" as an absolute rule rather than a *default with an explicit, auditable override path* — the same failure shape in two different stories.

**Prescription (applied):** added the named-override clause to S-3 AC2 ("...unless a story-level decision explicitly overrides it, and any such override SHALL be logged as a named business decision, not an implementation accident") and added the explicit documentation requirement to S-2 AC2 and to the Impact Assessment table (row 9) — both already reflected in the Construct and Impact Assessment sections above; this log records the diagnose→fix→re-verify pass that produced them.

| Dimension | Before | After | Change |
|---|---|---|---|
| Clarity | 4 | 4 | unchanged — no clarity issue found |
| Completeness | 3 | 4 | guard-parity override path now explicit (S-3); non-cascaded-association documentation requirement now explicit (S-2, Impact Assessment row 9) |
| Actionability | 3 | 4 | an implementing agent no longer has to guess whether a guard override is permitted, or whether silently skipping a non-cascaded association is acceptable |
| Efficiency | 4 | 4 | unchanged |
| Testability | 3 | 4 | both fixes are independently checkable: override-or-not is now a binary, logged decision; documentation-of-exclusions is now a checkable deliverable, not an inference |

**Mean:** 3.4 → 4.0 (**+0.6**, above the 0.3 diminishing-returns floor — this cycle earned its keep). **No dimension decreased** — no oscillation. **Cycle 1 target (all ≥3) met and exceeded (all ≥4); stopping at 1 cycle** rather than continuing to a cycle whose marginal gain would likely fall under the diminishing-returns threshold.

**Re-verify:** re-ran the Structural/Constraint/Adversarial layers against the updated S-2/S-3 — no new gaps introduced, no prior pass invalidated.

---

## A — ASSEMBLE

### Confidence Assessment

| Factor | Score (/3) | Basis |
|---|---|---|
| Pattern Match | 2 | Strong external pattern family (`discard`/`paranoia` ecosystem convention), but no in-repo template exists to confirm gem availability or existing conventions (G1) |
| Requirement Clarity | 2 | The mission's structural hazards (dependent associations, cross-team callbacks, admin tooling) are named explicitly and unambiguously; the *specific* business decisions within them (cascade choice, callback-firing semantics, identifier reservation) remain genuinely undecided pending team sign-off (CLARIFY gaps) |
| Decomposition Stability | 3 | ~75% self-consistency overlap across 3 alternative decompositions — HIGH |
| Constraint Compliance | 2 | 6-layer Test passed with 2 flagged-but-mitigated gaps, both traced to the same root cause (unknown target repo), not to spec quality |

**Weighted Confidence:** (2+2+3+2)/12 × 100 = **75%**

**Decision: VALIDATE (70–84% band) — deliver with flags, human reviews.**

**What a human reviewer should specifically validate before this becomes AUTO_PROCEED-worthy:**
1. Confirm the real target repo, its `Gemfile` (is `discard` or `paranoia` already present or forbidden by policy?), and `Account`'s actual association/callback graph — this could shift the Pattern selection between H1 (hand-rolled) and H2 (gem-shaped), though the *behavior contract* in Construct is designed to survive that choice unchanged.
2. Resolve the three CLARIFY would-ask questions with the actual owning teams — guard-clause parity (Q1), side-effect-callback opt-in list (Q2), and cascade-to-dependents (Q3) — these are business decisions this single-shot session could not obtain live sign-off for, and S-3/S-2 are built around assumed answers, not confirmed ones.
3. Re-score complexity once the real association/callback/call-site counts are known. This spec landed at 9/12 — one point below the 10–12 human-in-the-loop band — specifically because the unknown-repo gap (G1) capped how precisely Dependencies/Risk could be scored. If the real `Account` model turns out to have a materially larger callback/association surface than assumed, re-score before trusting Construct as final; this is a thin margin, not a comfortable one.

### Deliverables produced (dual-format contract + ECL sidecar)

| Artifact | Path |
|---|---|
| Plan artifact (this file) | `/tmp/ramza-s2/ac003/AB-T2-spectra-r1.out.md` (requested output path — explicit override, honored) |
| Authoritative mirror (Output Discipline rule 2) | `/tmp/spectra-pilot/.spectra/plans/2026-07-05-account-soft-delete-ac003.md` |
| Agent handoff (YAML) | `/tmp/spectra-pilot/.spectra/plans/2026-07-05-account-soft-delete-ac003.yaml` |
| State machine (JSON) | `/tmp/spectra-pilot/.spectra/plans/2026-07-05-account-soft-delete-ac003.state.json` |
| ECL v2.0 envelope sidecar | `/tmp/spectra-pilot/.spectra/plans/2026-07-05-account-soft-delete-ac003.envelope.json` (emitted because `ECL_VERSION=2.0` is present at `/tmp/spectra-pilot/.eidolons/spectra/ECL_VERSION`) |

**Naming note:** the `-ac003` suffix (this task's run identifier) was appended to the mirror filename stem because a concurrent SPECTRA session already occupies the unqualified `.spectra/plans/2026-07-05-account-soft-delete.*` slot in this shared consumer-project sandbox (a different run producing its own independent Account soft-delete spec). Output Discipline requires mirroring under `.spectra/`; it does not require — and this session will not perform — clobbering another session's concurrently-written artifact to claim the unqualified name.

Per Output Discipline rule 2: since the mission explicitly named a path outside `.spectra/`, that path was honored as the primary deliverable, and the authoritative copy was mirrored under `.spectra/plans/` regardless, together with the full Assemble deliverable set (YAML handoff, state JSON, ECL envelope) that a SPECTRA Assemble phase produces per `SPEC.md` and `skills/planning.md`.

### Agent Handoff (YAML)

```yaml
metadata:
  spec_id: "SPEC-2026-07-05-001"
  confidence: 75
  complexity: 9
  spectra_version: "4.11.0"
  thread_id: "019f3268-da91-7285-999c-cd8cc412b3cb"

projects:
  - id: "P-1"
    name: "Account Soft-Delete Capability"
    features:
      - id: "F-1"
        name: "Recoverable deletion (discard/restore) for the Account model"
        stories:
          - id: "S-1"
            title: "Schema & model foundation"
            timebox: "1d"
            risk: "P0"
            action_plan:
              - verb: "Migrate"
                target: "accounts: add discarded_at:datetime, nullable, indexed"
              - verb: "Extend"
                target: "Account model: discard!/undiscard! API, kept/discarded scopes, kept as implicit default"
              - verb: "Test"
                target: "existing Account specs unchanged + new-record defaults to kept"
            acceptance_criteria:
              - given: "the soft-delete migration runs"
                then: "a discarded_at column is added without altering any existing column or index"
              - given: "an Account with discarded_at set"
                when: "any default query is run"
                then: "it is excluded unless the caller opts in via .with_discarded"
              - given: "a brand-new Account"
                when: "created"
                then: "discarded_at defaults to nil, zero behavior change for existing code"
            agent_hints:
              recommended_class: "builder"
              context_files: ["app/models/account.rb [ASSUMED]", "db/migrate/*_add_discarded_at_to_accounts.rb [ASSUMED]"]
              validation_gates:
                p0: "existing Account regression suite green, unmodified"
          - id: "S-2"
            title: "Cascade behavior for dependent associations"
            timebox: "<=3d"
            risk: "P0"
            dependencies: ["S-1"]
            action_plan:
              - verb: "Audit"
                target: "enumerate every dependent: :destroy association on Account programmatically"
              - verb: "Create"
                target: "after_discard/after_undiscard hooks cascading to that enumerated set"
              - verb: "Test"
                target: "structural assertion: cascade-hook set == dependent::destroy association set"
            acceptance_criteria:
              - given: "Account has dependent: :destroy associations"
                when: "account.discard! is called"
                then: "every one of those associations is also discarded via an explicit after_discard hook"
              - given: "a dependent association is not declared dependent: :destroy"
                when: "the parent Account is discarded"
                then: "it is left untouched and explicitly documented, never silently omitted"
              - given: "an Account and its cascade-discarded dependents"
                when: "account.undiscard! is called"
                then: "only the auto-discarded dependents are restored"
            agent_hints:
              recommended_class: "reasoner"
              context_files: ["app/models/account.rb [ASSUMED]"]
              validation_gates:
                p0: "structural test: cascade-hook association set == dependent::destroy association set"
          - id: "S-3"
            title: "Destroy-callback contract preservation & business-guard audit"
            timebox: "<=3d"
            risk: "P0"
            dependencies: ["S-1"]
            action_plan:
              - verb: "Audit"
                target: "enumerate before_destroy/after_destroy callbacks, classify guard vs side-effect"
              - verb: "Configure"
                target: "guards apply to discard by default (overridable, named); side effects opt-in only, per team review"
              - verb: "Test"
                target: "destroy's callback list unchanged; discard fires only explicitly opted-in subset"
            acceptance_criteria:
              - given: "account.destroy is called"
                then: "100% of currently-registered destroy callbacks continue to fire exactly as before"
              - given: "a before_destroy guard blocks hard-destroy under a condition"
                when: "account.discard! is called under the same condition"
                then: "discard! enforces an equivalent guard by default, unless a named reviewed override exists"
              - given: "Account's existing after_destroy side-effect callbacks"
                when: "account.discard! is called"
                then: "none fire unless the owning team explicitly opted that callback back in"
            agent_hints:
              recommended_class: "reasoner"
              context_files: ["app/models/account.rb [ASSUMED]"]
              validation_gates:
                p0: "every registered callback has an explicit guard/side-effect classification and discard-behavior decision"
          - id: "S-4"
            title: "Query-boundary enforcement & read-call-site audit"
            timebox: "<=5d"
            risk: "P0"
            dependencies: ["S-1"]
            action_plan:
              - verb: "Audit"
                target: "enumerate every Account query/iteration/serialization call site codebase-wide"
              - verb: "Classify"
                target: "each call site: correctly-scoped-by-default vs requires .with_discarded override"
              - verb: "Test"
                target: "override behavior for opted-in sites; regression exclusion for default sites"
            acceptance_criteria:
              - given: "the codebase-wide call-site audit"
                when: "each call site is classified"
                then: "every call site is tagged, zero left unclassified"
              - given: "a background job/rake task iterates all accounts"
                when: "the default-scope change ships"
                then: "it is reviewed and updated to opt in via .with_discarded if it must see discarded rows"
              - given: "any API serializer exposes Account records"
                when: "the default scope changes"
                then: "discarded accounts are never exposed without an explicit opt-in"
            agent_hints:
              recommended_class: "explorer"
              context_files: ["app/ [ASSUMED, codebase-wide]", "lib/tasks/ [ASSUMED]"]
              validation_gates:
                p0: "Impact Assessment table has zero unclassified rows"
          - id: "S-5"
            title: "Admin console: filter, badge, restore"
            timebox: "<=3d"
            risk: "P1"
            dependencies: ["S-2", "S-3", "S-4"]
            action_plan:
              - verb: "Modify"
                target: "admin Account listing query to rely on the new default scope"
              - verb: "Extend"
                target: "Show discarded filter/toggle with visual indicator"
              - verb: "Create"
                target: "Restore action calling account.undiscard!"
            acceptance_criteria:
              - given: "the admin Account listing"
                when: "this feature ships"
                then: "the default listing excludes discarded accounts"
              - given: "an admin operator toggles Show discarded"
                then: "discarded accounts display with a clear visual indicator"
              - given: "a discarded account under the filter"
                when: "Restore is clicked"
                then: "the account and its cascade-discarded dependents are undiscarded and reappear in the default listing"
            agent_hints:
              recommended_class: "builder"
              context_files: ["app/controllers/admin/accounts_controller.rb [ASSUMED]", "app/views/admin/accounts/index.html.erb [ASSUMED]"]
              validation_gates:
                p1: "manual review by admin/support-tooling owner + default-listing regression test"
          - id: "S-6"
            title: "Authorization boundary & audit trail"
            timebox: "<=2d"
            risk: "P1"
            dependencies: ["S-1", "S-3"]
            action_plan:
              - verb: "Extend"
                target: "existing destroy authorization to also gate discard!/undiscard! identically"
              - verb: "Create"
                target: "audit record (actor, action, timestamp, account id) on every discard/undiscard/destroy"
              - verb: "Test"
                target: "unprivileged-actor rejection + audit-trail read test"
            acceptance_criteria:
              - given: "a user without admin/ops-tier permissions"
                when: "they attempt discard!/undiscard!/destroy"
                then: "the action is rejected, permission boundary unchanged from today's destroy guard"
              - given: "any discard/undiscard/destroy action succeeds"
                then: "an audit record (actor, action, timestamp, account id) is persisted"
              - given: "the audit trail exists"
                when: "a compliance/support request asks who deleted this account and when"
                then: "it is answerable from persisted audit data alone"
            agent_hints:
              recommended_class: "builder"
              context_files: ["existing Account authorization policy [ASSUMED]"]
              validation_gates:
                p1: "authorization regression test + audit-trail read test both green"
          - id: "S-7"
            title: "Docs, runbook, changelog"
            timebox: "1d"
            risk: "P2"
            dependencies: ["S-1", "S-2", "S-3", "S-4", "S-5", "S-6"]
            action_plan:
              - verb: "Modify"
                target: "in-repo model docs: discard/restore API, cascade contract, callback-preservation guarantee"
              - verb: "Modify"
                target: "CHANGELOG: default-scope behavior change as most call-site-impacting change"
              - verb: "Modify"
                target: "admin/support runbook: discard/restore workflow + named contact for deferred purge policy"
            acceptance_criteria:
              - given: "the feature ships"
                when: "a developer reads Account's documentation"
                then: "the discard/restore API and its cascade + callback-preservation contract are documented"
              - given: "the feature ships"
                then: "the changelog documents the default-scope change as the most call-site-impacting change"
              - given: "the admin/support runbook exists"
                then: "it documents the discard/restore workflow and a contact for the deferred retention/purge policy"
            agent_hints:
              recommended_class: "scriber"
              context_files: ["CHANGELOG.md", "docs/runbooks/account-lifecycle.md [ASSUMED]"]
              validation_gates:
                p2: "reviewed by runbook owner"

execution_plan:
  phases:
    - name: "Phase 1 — Foundation"
      stories: ["S-1"]
      agent_class: "builder"
    - name: "Phase 2 — Core safety (parallel)"
      stories: ["S-2", "S-3", "S-4"]
      agent_class: "reasoner+explorer"
    - name: "Phase 3 — Operator experience (parallel)"
      stories: ["S-5", "S-6"]
      agent_class: "builder"
    - name: "Phase 4 — Docs"
      stories: ["S-7"]
      agent_class: "scriber"
```

### State Machine (JSON)

```json
{
  "session_id": "019f3268-da9b-782f-957e-c495fcfe1e9f",
  "spec_id": "SPEC-2026-07-05-001",
  "goal": "Add recoverable soft-delete (discard/restore) to the Account model while leaving destroy and its cross-team callbacks completely unchanged, cascading correctly to dependent associations, and keeping the admin console usable.",
  "spectra_version": "4.11.0",
  "steps": [
    { "id": 1, "story_id": "S-1", "title": "Schema & model foundation", "status": "pending", "dependencies": [], "files_affected": ["app/models/account.rb [ASSUMED]", "db/migrate/*_add_discarded_at_to_accounts.rb [ASSUMED]"], "verification_command": "test: existing Account regression suite + new-record kept-by-default", "estimated_timebox": "1d", "replanning_notes": null },
    { "id": 2, "story_id": "S-2", "title": "Cascade behavior for dependent associations", "status": "pending", "dependencies": [1], "files_affected": ["app/models/account.rb [ASSUMED]"], "verification_command": "test: cascade-hook association set == dependent::destroy association set", "estimated_timebox": "<=3d", "replanning_notes": null },
    { "id": 3, "story_id": "S-3", "title": "Destroy-callback contract preservation & business-guard audit", "status": "pending", "dependencies": [1], "files_affected": ["app/models/account.rb [ASSUMED]"], "verification_command": "test: destroy callback list unchanged + discard opt-in subset only", "estimated_timebox": "<=3d", "replanning_notes": null },
    { "id": 4, "story_id": "S-4", "title": "Query-boundary enforcement & read-call-site audit", "status": "pending", "dependencies": [1], "files_affected": ["app/ [ASSUMED, codebase-wide]", "lib/tasks/ [ASSUMED]"], "verification_command": "audit: Impact Assessment table fully classified, zero unclassified rows", "estimated_timebox": "<=5d", "replanning_notes": null },
    { "id": 5, "story_id": "S-5", "title": "Admin console: filter, badge, restore", "status": "pending", "dependencies": [2, 3, 4], "files_affected": ["app/controllers/admin/accounts_controller.rb [ASSUMED]", "app/views/admin/accounts/index.html.erb [ASSUMED]"], "verification_command": "test: default-listing regression + manual admin-owner review", "estimated_timebox": "<=3d", "replanning_notes": null },
    { "id": 6, "story_id": "S-6", "title": "Authorization boundary & audit trail", "status": "pending", "dependencies": [1, 3], "files_affected": ["existing Account authorization policy [ASSUMED]"], "verification_command": "test: unprivileged-actor rejection + audit-trail read test", "estimated_timebox": "<=2d", "replanning_notes": null },
    { "id": 7, "story_id": "S-7", "title": "Docs, runbook, changelog", "status": "pending", "dependencies": [1, 2, 3, 4, 5, 6], "files_affected": ["CHANGELOG.md", "docs/runbooks/account-lifecycle.md [ASSUMED]"], "verification_command": "manual: runbook owner review", "estimated_timebox": "1d", "replanning_notes": null }
  ],
  "current_step": 0,
  "completed_steps": [],
  "replanning_history": [
    {
      "cycle": 1,
      "phase": "Refine",
      "diagnosis": "S-3 guard-clause parity was an unconditional rule with no override path; S-2 didn't require documenting non-cascaded associations",
      "fix_applied": "added named-override clause to S-3 AC2; added explicit documentation requirement to S-2 AC2 and Impact Assessment row 9",
      "mean_score_before": 3.4,
      "mean_score_after": 4.0,
      "oscillation_detected": false
    }
  ]
}
```

### CRYSTALIUM persistence

`mcp__crystalium__ingest` and `mcp__crystalium__session_end` were **not called** — no `mcp__crystalium__*` tools are reachable in this environment (see Memory pre-flight). Per `agent.md`/`skills/planning.md`, this is a documented graceful no-op, not a silent omission.

### Preflight Checklist

- [x] CLARIFY ran (not skipped — genuine ambiguity, resolved via risk-tagged assumptions and 3 recorded would-ask questions, no live user turn available this run)
- [x] `spectra-conventions.md` checked — absent, generic (idiomatic Rails) defaults used and documented
- [x] Complexity scored (9/12), extended-thinking budget routed; near-miss of the 10-12 human-in-the-loop band explicitly flagged in Assemble
- [x] 4 genuinely distinct hypotheses explored (conservative, pattern-leveraging, innovative, risk-minimizing)
- [x] All 7 stories pass INVEST
- [x] All timeboxes valid (1d/≤2d/≤3d/≤5d only, no story points)
- [x] Hierarchy uses Project (not "Epic")
- [x] Acceptance criteria in GIVEN/WHEN/THEN (21 total across 7 stories)
- [x] Agent hints with context files per story
- [x] Dual output: Markdown (this file) + structured YAML/JSON (embedded above + mirrored as separate files)
- [x] Confidence score present with factor breakdown (75%, VALIDATE)
- [x] Plan saved as artifact at the requested path + mirrored under `.spectra/plans/`
- [x] Every mirrored/derived output path starts with `.spectra/`
- [x] No code produced — plans only
- [x] Rejected alternatives documented (H1, H3, H4 — three, exceeding the "at least one" requirement)
- [x] Impact assessment of existing call sites produced (9-row table, mapped to owning stories)

---

*SPECTRA v4.11.0 — Strategic Specification through Deliberate Reasoning*
