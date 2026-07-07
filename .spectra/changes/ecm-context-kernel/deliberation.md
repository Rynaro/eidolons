# FORGE Deliberation — ECM context kernel (change: `ecm-context-kernel`, tier=full)

> **Gates:** ESL `deliberated` transition for `ecm-context-kernel`.
> **Mode:** TRANCE G2 self-consistency (explicit user-token opt-in). D1–D4: N=3
> perspective-diverse, mutually-blind traces (personas: evidence-maximizing /
> pre-mortem / constraint-relaxation), structural-agreement judge-merge, 60%
> consensus floor. D5–D6: framed at Standard depth (Step-4 score 5/9 each —
> below the stakes bar; single-trace, ≥3 hypotheses, full stress tests).
> **Requester:** orchestrator → RAMZA (P1 implementation spec).
> **requires_checker: false** (checker-handoff scan run; see Provenance).

---

## Frame (frozen before fan-out)

**Decision types:** D1 TRADE-OFF · D2 FEASIBILITY/scope · D3 CONSTRAINT-SATISFACTION ·
D4 TRADE-OFF · D5 TRADE-OFF · D6 TRADE-OFF.

### Evidence inventory

| ID | Source | Reliability |
|----|--------|-------------|
| E1 | `docs/specs/ecm/spec.md` (v0.1 draft) | H — decision context, internally consistent |
| E2 | `docs/specs/ecm/policy.yaml` | H — machine-readable companion |
| E3 | `research/context-lifecycle-survey-2026-07.md` | H for S/A-tier findings (F1, F2, F4); M for B-tier (F5, F7) |
| E4 | `.spectra/changes/ecm-context-kernel/scout-harness-surface.md` (ATLAS) | H — path:line anchored, FINDING/GAP discipline |
| E5 | `.spectra/changes/ecm-context-kernel/evidence-host-facts.md` | H — verified against first-party docs 2026-07-06; C1 UNVERIFIED, C5/C6 PARTIAL as marked |
| E6 | CRYSTALIUM recall: ECM design episodic crystal (T1, unverified) | M — consistent with E1, no new facts |

### Shared constraint table

| ID | Constraint | Hard/Soft | Source |
|----|-----------|-----------|--------|
| CC1 | Mechanical gates only; never LLM-discretionary | Hard | E1 P0-2 |
| CC2 | Fail-open, advisory-first; never block on memory/telemetry failure | Hard | E1 P0-9; DOSSIER-HARNESS rule |
| CC3 | bash 3.2 + jq kernel; prompt path ≤ 300 ms | Hard | E1 P0-8; E2 limits |
| CC4 | Memory/meter/policy harness-injected, never model-requested | Hard | E3 F6 (A/B-tier, Mem0-vs-Letta) |
| CC5 | Anti-scope: no CRYSTALIUM re-declaration, no ECL performative extension | Hard | E1 P0-7 |
| CC6 | Sidecar-on-disk for meter/log/brief | Hard | E1 P0-3 |
| CC7 | C-4: per-prompt injected artifacts ≤ ~200 tokens | Hard (named invariant) | E1 §3.5 |
| CC8 | Zone bands 25-point coarse; ±10% estimate cannot mis-zone > 1 band | Design premise | E1 §3.1 |
| CC9 | Opt-in; schema additive | Hard | E1 P0-1 |
| CC10 | Subagents cannot spawn subagents; TRANCE fan-out ≤ 5 | Hard | orchestrator statement; roster |
| CC11 | Host compaction needs headroom to run | Hard (physical) | E5 context |

Confidence reporting: for D1–D4 the anchor is `structural_agreement` (per
self-consistency skill), bounded above by the 4-factor calibration where evidence
is thin — the reported number is `min(structural, 4-factor composite)`, factors shown.

---

## D1 (OQ-E1) — Meter estimation on hosts without token telemetry

**Question.** For Codex/Copilot/Cursor/OpenCode-tier hosts with no exact telemetry
(Claude Code is exempt — E5 C4 confirms `context_window.used_percentage`), does the
meter use (H1) a bytes/4 transcript heuristic, (H2) a tokenizer-in-container, or
(H3) host-tier-only metering (no meter on blind hosts)?

### Traces

- **T1 evidence-max → H1.** CC8 is designed for exactly this: ±10% cannot mis-zone
  more than one band, and every band boundary has a cheap response (P6 externalize
  is low-cost). E5 C7 confirms `transcript_path` on all hook payloads for the
  verified host; `wc -c` + jq is trivially inside CC3. H2 has no evidence of
  container availability on blind hosts and no correct tokenizer to install
  (Claude's is not public; a mismatched tokenizer is an expensive heuristic). H3
  abandons the spec's core value (E1 §1.2.3: no human backstop) precisely on the
  hosts most likely to rot silently (E3 F1).
- **T2 pre-mortem → H1.** Failure comparison: H1 fails *soft* (bytes/4
  underestimates on code/JSON-dense transcripts → late trigger → host emergency
  compact backstops; never worse than the T0 status quo). H2 fails *hard*
  (docker-less/air-gapped host → dead meter or blown 300 ms budget → hooks
  disabled; violates CC2+CC3). H3 fails *silent* (overnight Codex chain rots at
  60%, orchestrator contradicts itself — the exact E1 §1.2.3 scenario). Surfaced:
  bytes/4's error direction is systematically *late* (code averages ~3–3.5
  chars/token) — [ASSUMPTION], unmeasured on our transcripts.
- **T3 constraint-relax → H1.** Relaxing the 300 ms budget (the only relaxation
  that helps H2) is unacceptable — per-prompt, user-facing, DOSSIER-HARNESS-derived
  — and even relaxed, H2 only moves ±15% → ±10%, both inside the CC8 one-band
  tolerance. Surfaced: H1 must formally include H3's floor — where no transcript
  file exists, degrade to `zone: unknown` → `continue` (CC2).

### Merged verdict

**[VERDICT] H1 — bytes/4 transcript heuristic, spec'd as a three-rung estimation
ladder: host telemetry (exact) → transcript bytes/4 (where a transcript file
exists) → `zone: unknown` → continue (fail-open floor).** No tokenizer container,
ever, on the meter path. The P1 canary must pre-register a divisor-bias
measurement on real tool-heavy transcripts (bytes/4 vs bytes/3.5): the cost
asymmetry favors erring early (early externalize is cheap; late compaction risks
F2 loss), so if bias is confirmed, the correction is a divisor constant — never a
tokenizer.

- **structural_agreement:** 3/3 = 100% (PASS, well above 60% floor)
- **Confidence: 86%** (Evidence 80 — design tolerance H-anchored, but bytes/4
  accuracy itself unmeasured [GAP]; Logic 90; Constraints 90; Sensitivity 85)
- **Rejected — H2 tokenizer-in-container:** load-bearing counterargument: it
  converts a fail-open advisory system into one with a hard runtime dependency
  (CC2/CC3 violation) to buy accuracy the zone design doesn't need (CC8), using a
  tokenizer that is wrong for most hosts anyway.
- **Rejected — H3 host-tier-only:** load-bearing counterargument: the blind hosts
  are the entire reason ECM exists (E1 §1.2.3 + E3 F1); no meter there means no
  policy there, reducing ECM to a Claude Code feature.
- **[REVERSAL-CONDITION]** (convergent, T1+T2+T3): P1 canary shows ≥2-band
  mis-zoning on real transcripts → recalibrate divisor / per-host constant via ESL.
- **[REVERSAL-CONDITION]** (convergent, T2+T3): a blind host exposes no readable
  transcript file → that host degrades to rung 3 (`unknown`/continue); if this
  covers *most* blind hosts at P2, revisit whether a plugin-shim counter is worth
  spec'ing.
- **[GAP]** transcript-file availability verified only on Claude Code (E5 C7);
  Codex/Copilot/Cursor/OpenCode transcript access is `[VERIFY]` at P2.

---

## D2 (OQ-E2) — Does the optional `atomos` MCP exist in the roadmap at all?

**Question.** Is kernel-verbs+hooks the complete ECM implementation (H1: delete
atomos from the roadmap), does atomos stay a P3 conditional (H2), or is atomos
committed as the compose/verify executor per the tonberry precedent (H3)?

### Traces

- **T1 evidence-max → H2 (sharpened).** E3 F6 is the strongest single finding in
  the evidence set (A/B-tier + internally measured): anything on the
  trigger/meter/injection path must be harness-injected — an MCP is
  model-requested by definition, so atomos can never be a chokepoint. What
  remains *legal* for atomos is the tonberry-analog surface: compose/verify
  executor operations. Evidence that any host needs even that: none (E1 §8 P3 is
  explicitly `[VERIFY per-host]`). Evidence-max refuses both to build unproven
  surface (H3) and to delete an option whose deciding evidence (the P2 round-trip
  canary) hasn't been collected (H1).
- **T2 pre-mortem → H2.** H1-fails: a T2 host (Copilot-class, weak hook injection)
  proves unable to compose/ingest the handoff brief at P3 → roadmap re-open via
  ESL, weeks of delay — moderate. H3-fails: two implementation paths, models
  start "asking" atomos for policy, the Letta failure replays under our own flag
  — the worst outcome, a doctrinal self-contradiction. H2-fails: zombie roadmap
  item invites speculative building — cheap to mitigate with sharper spec text.
  Surfaced: deciding final existence *now* would pre-empt the spec's own
  decide-via plan ("FORGE deliberation at P2 exit"); the correct verdict shape is
  a conditional with a pre-registered kill criterion.
- **T3 constraint-relax → H2.** The only relaxation that favors H3 is treating
  "kernel path stays canonical" as soft for pattern-uniformity with tonberry.
  Unacceptable: F6 is measured evidence, not a preference. Surfaced: write the
  anti-scope fence *now* — the only legal atomos surface, if ever built, is
  compose/verify execution (brief composition assist, envelope verification);
  never metering, policy evaluation, triggering, or injection.

### Merged verdict

**[VERDICT] H2 — kernel-verbs+hooks are the complete and canonical v1.0
implementation; atomos remains a P3 conditional with its anti-scope fence written
into the spec now (compose/verify executor only — never meter/policy/trigger/
injection) and a pre-registered kill criterion: if all wired hosts pass the
handoff round-trip canary via kernel+hooks alone at P2 exit, atomos is deleted
from the roadmap.** P1 builds nothing atomos-related.

- **structural_agreement:** 3/3 = 100% (PASS)
- **Confidence: 90%** (Evidence 90 — F6 is A/B-tier measured; Logic 90;
  Constraints 95; Sensitivity 85)
- **Rejected — H1 delete now:** load-bearing counterargument: it decides ahead of
  the evidence the spec itself scheduled (P2-exit canary data), and re-opening a
  frozen sibling-spec roadmap costs an ESL cycle if a T2 host gap materializes.
- **Rejected — H3 commit now:** load-bearing counterargument: F6 — a
  model-requested memory/context surface is the *measured* failure mode
  (Letta/MemGPT class); committing to atomos builds the failure mode into the
  roadmap before any host proves a need.
- **[REVERSAL-CONDITION]** (convergent, T1+T2): all-hosts canary PASS via
  kernel+hooks at P2 exit → delete atomos (H1 fires then, mechanically).
- **[REVERSAL-CONDITION]** (convergent, T2+T3): a verified host gap in brief
  composition/ingestion → atomos green-lit, scope-fenced to compose/verify.

---

## D3 (OQ-E3) — Subagent sessions: meter and budget model

**Question.** Do subagent sessions get (H1) their own meter + a shared budget
ledger, (H2) fully inherited meter/budget state (no per-subagent metering), or
(H3) fully independent meter + budget?

### Traces

- **T1 evidence-max → H1.** Utilization is defined per physical window (E1 §3.1)
  and F1 rot applies to each window independently — a subagent at 10% inheriting
  the orchestrator's `red` is a category error, so any meter a subagent has must
  be its own. The budget ceiling (rule P1) is only meaningful over *campaign*
  spend: TRANCE fan-out ≤ 5 (CC10) can multiply spend ~5×, exactly when the
  ceiling matters. Only H1 satisfies both. Surfaced: fan-out-5 concurrency means
  the ledger must be an append-only JSONL and meter files session-keyed
  (`meter-<session_id>.json`) — a single mutable JSON corrupts under concurrent
  rewrites.
- **T2 pre-mortem → H1.** H2-fails: a Kupo "micro" task balloons (repeat-failure
  loop), rots its own window at 80%+, and returns confident garbage the
  orchestrator integrates — silent quality corruption, invisible in any ledger.
  H3-fails: five branches each under private budgets; the campaign ceiling is a
  lie; overnight cost blowout with no human backstop (E1 §1.2.3). H1-fails:
  *soft* — subagent hooks may not fire on some hosts, ledger under-counts,
  ceiling fires late; mitigated by fail-open (unmetered subagent → `unknown` →
  continue) and dispatch-count estimates. Surfaced: subagents **cannot execute
  `handoff_fresh` or `wrap_up`** (CC10 — no successor spawn); their policy table
  must remap both to "finish-and-return": externalize + return a brief-shaped
  summary to the orchestrator + stop.
- **T3 constraint-relax → H1.** Relaxing per-subagent hook overhead concerns is
  acceptable (subagent sessions are short; ≤300 ms per firing is bounded).
  Relaxing CC10 is not ours to relax (host-enforced). Surfaced: per-dispatch
  sub-allowances (orchestrator grants each branch ceiling/N) are a compatible
  P2+ refinement of the shared ledger — routing/RAMZA territory, not v1.0 ECM
  surface. Budget rule P1 evaluation stays orchestrator-only (the ledger is
  summed there); subagents never self-evaluate the ceiling.

### Merged verdict

**[VERDICT] H1 — own meter per subagent session (session-keyed
`meter-<session_id>.json`), shared campaign budget via an append-only
`.eidolons/.context/budget-ledger.jsonl`, with rule P1 (ceiling) evaluated only
in the orchestrator session.** Subagent policy tables remap `handoff_fresh` and
`wrap_up` to finish-and-return (externalize + summary to orchestrator + stop),
because subagents cannot spawn successors (CC10). Unmetered subagents (host
hooks absent) degrade to `unknown`/continue with dispatch-count ledger estimates.

- **structural_agreement:** 3/3 = 100% (PASS)
- **Confidence: 85%** (Evidence 80 — per-window rot is H-anchored, but whether
  hooks fire inside subagent sessions is unverified on any host [GAP]; Logic 90;
  Constraints 90; Sensitivity 80)
- **Rejected — H2 fully inherited:** load-bearing counterargument: zone is a
  property of a physical window; inherited state either compacts empty windows or
  (in its defensible no-subagent-metering form) leaves ballooning micro-tasks to
  rot invisibly — the F1 failure with no audit trail.
- **Rejected — H3 fully independent:** load-bearing counterargument: it makes the
  budget ceiling unenforceable exactly in the fan-out campaigns that dominate
  spend — the autonomous cost-blowout scenario the ceiling exists to stop.
- **[RISK]** (convergent, T1+T2): concurrent writes under fan-out-5 → append-only
  JSONL is mandatory; a mutable shared ledger file is a defect.
- **[CONSTRAINT]** (convergent, T2+T3): subagent operation-set restriction
  (no self-executed handoff_fresh/wrap_up) must appear in the spec's policy
  section, not be left to implementation.
- **[REVERSAL-CONDITION]** if P1 shows subagent sessions cannot fire hooks or
  expose spend on any host, subagent metering degrades to documentary and the
  ledger to orchestrator-side dispatch estimates — H1's floor, not a new model.
- **[GAP]** subagent hook firing and subagent token-count visibility are
  unverified per host — RAMZA must schedule this probe in P1.

---

## D4 (OQ-E4) — Handoff brief token budget (and the C-4 tension)

**Question.** Is the brief budget (H1) a 1,500-token hard cap enforced by the
composer, (H2) tiered by ESL change tier, or (H3) uncapped-with-advisory? And:
is the brief injected whole into the successor, or recalled-on-demand with only
a digest injected — resolving C-4 (~200-token per-prompt injection cap) vs 1,500.

### The C-4 tension, resolved first (all traces depend on it)

There is **no conflict — the two numbers govern different injection classes.**
C-4 bounds *per-prompt* artifacts in the volatile tail (meter digest, policy
verdict — every turn, cache-miss cost each time). The brief is injected **once**,
at successor SessionStart, through the existing memory pre-flight path
(E4 FINDING-015), whose output is already mechanically truncated to a ~1,500-byte
digest (E4 FINDING-014, `head -c 1500` ≈ ~375 tokens) — and E5 C2 confirms
SessionStart `additionalContext` has no documented size cap. The full brief lives
on disk (`.eidolons/.context/handoff-<ts>.md`) and in CRYSTALIUM, **recalled/read
on demand**. So: digest-injected, brief-on-demand. The 1,500-token figure governs
the *composition* of the brief artifact itself, not any per-prompt injection.

### Traces

- **T1 evidence-max → H3-refined.** The S-tier finding F2 (truncation drops
  instructions/identifiers first) weighs directly *against* hard truncation — a
  composer hard cap that truncates replicates, in our own artifact, the exact
  compaction failure ECM defends against. The injection-cost concern is already
  mechanically solved by the digest pipe (FINDING-014); the utilization concern is
  second-order (1,500 tokens ≈ 0.75% of a 200k window; even 5k ≈ 2.5%). Verdict:
  1,500 = advisory composition *target*; overflow → warn + policy-log the size;
  never truncate the artifact; the hard bound lives on the injected digest only.
- **T2 pre-mortem → H3-refined.** H1-fails: an emergency handoff at critical zone
  produces a 1,900-token brief; the hard cap either truncates the
  failed-approaches section (successor repeats a destructive failed approach — the
  §3.4 anti-goal) or blocks/retries at 95% utilization and the session dies before
  the brief lands (CC2 violation at the single most valuable moment). H2-fails:
  sessions not bound to an ESL change have no tier → composer stalls or defaults
  arbitrarily, and the emergency path gains an ESL-state read dependency.
  H3-pure-fails: a 25k-token brief bloats the store and a dutiful successor
  re-imports rotted prose — annoying but *soft*, and mitigated by digest-first +
  warn. Surfaced: order brief sections by survival priority (identifiers,
  failed approaches, next steps first) so even digest-only consumption gets the
  load-bearing content.
- **T3 constraint-relax → H3-refined.** Relaxing C-4 to inject the whole brief
  per-prompt is unacceptable (cache-miss cost every turn + rot re-import).
  Relaxing fail-open to allow compose-retry is unacceptable at critical zone.
  Surfaced: the defensible *tiering* dimension is trigger context, not ESL tier —
  the spec already says it (rule P2: emergency handoff "minimal manifest
  allowed" vs rule P1 graceful wrap-up targeting the full brief). Mechanical,
  observable, no ESL dependency.

### Merged verdict

**[VERDICT] H3-refined — 1,500 tokens is an advisory composition target, not a
hard cap: overflow warns and is recorded in the policy log; the artifact is never
truncated. The mechanically-hard bound sits on the *injected digest* (existing
pre-flight `head -c 1500` path); the full brief is recalled/read on demand.
Brief sections are ordered by survival priority (identifiers → failed approaches
→ next steps → narrative). Size tiering, where needed, keys on trigger context
(P2 emergency = minimal manifest; P1 wrap-up = full target), never on ESL change
tier.** Spec edit required: E2 `handoff_brief_max_tokens: 1500` comment and E1
OQ-E4 "hard-capped by the composer" → "advisory target; overflow warn+log;
digest injection hard-bounded".

- **structural_agreement:** 3/3 = 100% (PASS)
- **Confidence: 86%** (Evidence 85 — F2 is S-tier, digest pipe is code-anchored,
  but no measured brief sizes exist yet [GAP]; Logic 90; Constraints 90;
  Sensitivity 80 — sensitive to digest adequacy, see GAP below)
- **Rejected — H1 hard cap:** load-bearing counterargument: hard enforcement
  fails worst at the highest-value moment — emergency handoff — where it either
  truncates the exact F2-class content the brief exists to preserve or violates
  fail-open (CC2) with a compose-retry at 95% utilization.
- **Rejected — H2 ESL-tier tiering:** load-bearing counterargument: change tier
  is a property of a *change*, not a *session*; many sessions have no ESL change
  in flight, so the composer's input is undefined precisely when the mechanism
  must be mechanical (CC1) — and it imports an ESL read into the emergency path.
- **[REVERSAL-CONDITION]** (convergent, T1+T2): P1 canary shows briefs routinely
  ≫ target (e.g. >3–4k) with degraded successor recall quality or store bloat →
  escalate to a mechanically enforced compose-time cap via ESL revision.
- **[GAP]** the ~1,500-**byte** (~375-token) pre-flight digest may under-serve a
  handoff digest; whether the ingested crystal's `summary` field carries the
  survival-priority head of the brief is unverified — P1 canary must check
  digest adequacy, and RAMZA may parameterize the pre-flight truncation for
  `session_handoff` queries.

---

## D5 (scout GAP-004) — CRYSTALIUM targeting for `session_handoff` — Standard depth

**Question.** P1 canonical persist path for the handoff brief: (H1) `ingest` of
the ECL envelope, (H2) episodic `commit` with reserved `topic_key`, (H3) dual
path (ingest-when-envelope, commit-fallback)? And does `contains_tool_origin`
survive?

**Analysis.** The spec makes the envelope unconditional for briefs (E1 §3.4: the
artifact *pair* includes `ecl-envelope.json`), so H3's "when envelope exists"
condition is always-true for this artifact class and collapses into H1. The
ingest chokepoint is the substantive differentiator: per the tool contract,
ingest maps any artifact to crystal.v1 with the native payload preserved
verbatim, commits **through the chokepoint so MIN-trust is preserved**, and
tool-origin content is never laundered upward — i.e. `contains_tool_origin`
survives *and is enforced* structurally. Under `commit`, the flag survives only
by caller convention (placed in payload/provenance by hand) with no chokepoint
enforcement. The envelope's SHA-256 is also the natural anchor for the
round-trip canary's "verbatim-by-hash" check (E1 §3.4); `commit` would carry a
hash only informally. Recall side: both paths land episodic at T1
(`from.eidolon` = the active Eidolon; existence proof: this session's recall
returned a T1 episodic crystal), so the successor pre-flight's existing
`--layers semantic,episodic,procedural` (E4 FINDING-012) needs **no change** —
that closes GAP-004's layer question. `execution` stays excluded and must: plan
state travels via `plan_checkpoint`, which is TTL-bound (24 h) — another reason
the brief must never live only in the execution layer.

**[VERDICT] H1 — `crystalium_ingest` of the ECL envelope is the P1 canonical
path, with the file floor (`.eidolons/.context/handoff-<ts>.md`, written before
ingest) as the only degradation path. No commit-fallback branch.**
`contains_tool_origin` survives both paths, but only ingest enforces
non-laundering at the chokepoint — a second, independent reason for H1.

- **Confidence: 81%** (Evidence 85 — first-party tool contracts + spec text;
  Logic 85; Constraints 85; Sensitivity 70 — one identified sensitivity, below)
- **Rejected — H2 commit:** loses chokepoint MIN-trust enforcement and the
  integrity-hash canary anchor; the flag becomes a convention, not a guarantee.
- **Rejected — H3 dual path:** doubles the canary/verification matrix for zero
  availability gain — the file floor already covers crystalium-down, and
  fail-open (CC2) says skip-on-failure, not fall-back-and-retry.
- **[RISK][GAP]** Quarantine-vs-recall interaction: if ingest treats a
  `contains_tool_origin: true` brief as a tool-origin artifact and
  episodic-*quarantines* it, and quarantined records are excluded from default
  recall visibility, the handoff round-trip breaks **exactly when the session
  touched tool output — which is nearly always.** Evidence is silent on default
  recall visibility of quarantined records. **P1 round-trip canary MUST include
  a `contains_tool_origin: true` brief.** If it fails to surface, the remedy is
  a scoped recall flag for `session_handoff` records — not a switch to H2.
- **[REVERSAL-CONDITION]** the quarantine canary above failing with no viable
  recall-flag remedy → revisit with `commit` + explicit provenance as the
  fallback candidate.
- **[ASSUMPTION]** a one-shot out-of-MCP-session ingest invocation (analog of
  the existing recall docker path, E4 FINDING-011/012) is buildable at P1;
  memory.sh currently implements recall only — new plumbing either way, so it
  does not differentiate H1 vs H2.

---

## D6 (scout GAP-002 + host-facts C5) — Autocompact alignment on Claude Code — Standard depth

**Question.** What does `harness install` write to align Claude Code autocompact
with ECM: (H1) `compactThreshold` in `.claude/settings.json` via the existing
jq-merge, (H2) `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` env export (session-scoped, no
settings mutation), (H3) nothing (documentary only)? And is 75 the right value?

**Analysis.** A fact that reframes the decision: with PreCompact unverified
(E5 C1) and no kernel-invocable `/compact`, **the autocompact threshold is the
only mechanical implementation of rule P3 on Claude Code** — the host fires
compaction, then SessionStart(`compact`) (E5 C2) does pin re-inject + handoff
recall, and externalize-before-compact is already covered amber-zone-eager
(E5 correction #2: P5/P6 *are* the pre-compaction hook on hosts without one).
So H3 is not "no alignment", it is "no mechanical P3 at all" — host default 95%
emergency compaction, the F1/F2 failure the spec exists to prevent. H2 has a
mechanism hole: hooks run as children of the host process and cannot set the
parent's environment; with no `eidolons` wrapper process around `claude`, the
only way to make the env var live is an unmanaged shell-profile export —
machine-global, invisible to `doctor`, not project-scoped, not removable by
`eidolons remove`. E5 C5 itself recommends the settings field. H1 uses the
proven idempotent jq-merge canonical-compare idiom (E4 FINDING-007), is
project-scoped, doctor-auditable, and reversible — with one required nuance:
**don't-clobber semantics.** A scalar field carries no marker identity, so:
absent → write `75` and record `managed: true` in the lock's `context:` block;
present-and-different → leave it, warn, record `managed: false`. The env var's
documented precedence (it *overrides* the setting, E5 C5) preserves a free user
escape hatch.

**On 75.** Double-anchored: it is the ECM RED boundary (E2 `red: 0.75`) and the
top of Claude Code's own recommended aggressive band 60–75 (E3 F1). Headroom for
the summarization pass at 75% is 25% of the window (~50k tokens on 200k) —
ample (CC11 pass). The residual race (utilization jumps 70→85 inside one
tool-heavy turn, autocompact fires before any red-zone hook firing) is bounded
to ~one turn of unexternalized state by amber-eager P5/P6 — the designed
mitigation, not a new gap. Offsetting the threshold above RED (e.g. 80) to
widen the externalize window buys little against that bound and breaks the
clean, auditable "autocompact = RED boundary" invariant.

**[VERDICT] H1 — `harness install` writes `compactThreshold: 75` into
`.claude/settings.json` via the existing jq-merge canonical-compare idiom, with
don't-clobber semantics (absent → write + `managed: true` in lock;
present-and-different → leave + warn + `managed: false`). 75 = the RED
boundary. The env var is documented as the user-side override, never written by
the harness.**

- **Confidence: 80%** (Evidence 75 — C5 is PARTIAL: field semantics confirmed as
  "percentage 0–100" but exact key spelling/location and numeric default are
  undocumented [GAP]; Logic 85; Constraints 85; Sensitivity 75)
- **Rejected — H2 env export:** load-bearing counterargument: there is no
  process boundary the harness controls where a session-scoped export can take
  effect — a hook cannot mutate its parent's environment — so H2 degenerates
  into an unmanaged, machine-global profile edit, worse on every axis it was
  meant to win (scope, reversibility, no-mutation).
- **Rejected — H3 nothing:** load-bearing counterargument: on Claude Code the
  threshold IS rule P3's mechanization; without it, ECM's compact trigger is
  documentary and the host's 95% emergency floor governs — precisely E3 F1/F2.
- **[REVERSAL-CONDITION]** a documented PreCompact hook surface ships (E5 C1
  [WATCH]) → the kernel gains a true pre-compaction anchor; re-evaluate both the
  threshold's role and its value.
- **[REVERSAL-CONDITION]** P1 live verification shows `compactThreshold`
  semantics differ from "percentage 0–100 of window" (e.g. token count, or the
  key name differs) → adjust mechanism to match; the don't-clobber + lock-record
  design is invariant to the field's spelling.
- **[GAP]** exact settings key name/location and default value must be verified
  live at P1 before the jq-merge branch is written (C5 verdict is PARTIAL).

---

## Gate record

- **Logical soundness:** PASS. Fallacy scan per decision: no false dichotomies
  (≥3 genuine hypotheses each; D3's H2 was deliberately re-cast into its
  strongest form before evaluation); no appeal-to-authority (tonberry cited as
  functional analog, decided on F6's measured evidence); no circularity found
  walking each chain backward. D4's "H3-refined" is H3 with the hard bound
  relocated to the injection layer — recorded as a refinement, not a fourth
  hypothesis smuggled past the tally.
- **Evidence coverage:** PASS. Every load-bearing claim anchored E1–E6 with
  reliability tier; 6 [GAP] markers, 2 [RISK], 3 [ASSUMPTION]-class notes, 11
  [REVERSAL-CONDITION]s (5 convergent across ≥2 blind traces — high-trust per
  the self-consistency protocol).
- **Decision completeness:** PASS. All six verdicts actionable by RAMZA without
  follow-up; hard constraints CC1–CC11 each addressed where binding.
- **REFORGE:** not required.
- **Self-consistency accounting:** D1–D4 each N=3, personas 1–3
  (evidence-max / pre-mortem / constraint-relax), sequential-blind in-context
  form; one deterministic merge pass each; structural agreement 3/3 on all four
  — no [DISPUTED] emissions; zero traces discarded (none invented evidence).
  Dissent-shaped signal worth noting despite unanimity: D1-T2 flagged the
  systematic *late* bias of bytes/4; D5's quarantine-recall interaction is the
  single highest-risk unknown in the set.

## Checker-handoff record

Scanned all six recommended actions against the five-category irreversibility
trigger table (deploy/release; destructive migration/data deletion;
security-boundary change; external spend; public communication): **zero
matches** — the actions are spec-text edits, P1 implementation guidance, canary
requirements, and a consumer-project settings write that is marker-idiom
managed and reversible. **`requires_checker: false`** (recorded, per
orchestrator expectation).

---

## Consolidated verdict table (for RAMZA)

| # | Decision | Verdict | Conf. | Structural | Key obligation for P1 |
|---|----------|---------|-------|------------|----------------------|
| D1 | Meter on blind hosts | bytes/4 heuristic in a 3-rung ladder: host telemetry → transcript bytes/4 → `unknown`/continue. No tokenizer container. | 86% | 3/3 | Pre-register divisor-bias canary (4 vs 3.5) on tool-heavy transcripts; verify transcript access per host at P2 |
| D2 | atomos MCP | Kernel+hooks canonical & complete; atomos stays P3-conditional with anti-scope fence written now (compose/verify only, never meter/policy/trigger); kill criterion = all-hosts canary PASS at P2 exit | 90% | 3/3 | Spec-text edit: fence + kill criterion; P1 builds nothing atomos-related |
| D3 | Subagent meter/budget | Own meter per session (`meter-<session_id>.json`) + shared append-only `budget-ledger.jsonl`; ceiling (P1 rule) evaluated orchestrator-only; subagent `handoff_fresh`/`wrap_up` → finish-and-return | 85% | 3/3 | Append-only JSONL mandatory; spec the subagent operation-set restriction; probe subagent hook firing |
| D4 | Brief budget | 1,500 = advisory composition target (warn+log on overflow, never truncate); hard bound on injected digest only (existing pre-flight truncation); sections ordered by survival priority; tiering by trigger context (P2 minimal vs P1 full), never ESL tier. C-4 tension: resolved — different injection classes | 86% | 3/3 | Edit E1 OQ-E4 + E2 comment ("hard-capped" → advisory target); canary checks digest adequacy |
| D5 | session_handoff path | `ingest` of the ECL envelope is canonical; file floor is the only fallback; no commit branch. `contains_tool_origin` survives both but only ingest *enforces* it | 81% | n/a (std) | Round-trip canary MUST include a `contains_tool_origin: true` brief (quarantine-vs-recall risk); memory.sh layer set unchanged |
| D6 | Autocompact alignment | Write `compactThreshold: 75` (RED boundary) to `.claude/settings.json` via existing jq-merge, don't-clobber + lock-record; env var stays the user override, never harness-written | 80% | n/a (std) | Verify exact key semantics live (C5 PARTIAL) before writing the merge branch |

**Handoffs:** → RAMZA (P1 implementation spec — consume table above); → ATLAS
(P2 probes: per-host transcript access, subagent hook firing, live
`compactThreshold` semantics); no → human required (all confidences ≥ 80%, no
[DISPUTED], requires_checker=false).

## Provenance

- **Decision types:** 3× TRADE-OFF, 1× FEASIBILITY/scope, 1×
  CONSTRAINT-SATISFACTION, 1× TRADE-OFF (D5)
- **Deliberation depth:** D1–D4 Deep/G2 (N=3 self-consistency, explicit opt-in);
  D5–D6 Standard (2 passes each, single-trace)
- **Evidence sources:** 6 (5 H, 1 M)
- **Hypotheses evaluated:** 19 across six decisions (≥3 each)
- **Confidence anchor:** min(structural_agreement, 4-factor composite) for
  D1–D4; 4-factor composite for D5–D6 — factor breakdowns inline per decision
- **Gate result:** PASS (no REFORGE)
- **Markers:** 3 ASSUMPTION · 6 GAP · 2 RISK · 11 REVERSAL-CONDITION · 0 DISPUTED
- **ise.assertion_grade:** self-attested · **requires_checker:** false
- **Author:** FORGE (Reasoner, methodology 1.10.0) · 2026-07-06 ·
  change `ecm-context-kernel` · gates ESL `deliberated`
