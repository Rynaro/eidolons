# Labeling Rubric — Arm-2 (no-over-capture) ground-truth owner

> For the **blind labeler only**. ESL change `generalist-eidolon`, Track G
> (R-041/R-052/AC-G03/AC-G04/AC-G07). Gate author: `gate-author-sonnet-fresh`
> — distinct from the spec maker (ramza), the implementation maker (vivi),
> and the generalist-builder (whoever authors `Rynaro/Gilgamesh`'s own
> methodology). **The gate author does not assign labels.** This document
> is the instrument a separate, independent labeler uses.

## What you receive

`arm2-for-labeling.jsonl` — the Arm-2 corpus, **order-shuffled** (sorted by
`sha256(id + prompt)`, so the shuffle order carries no information about
authoring stratum), reduced to exactly two fields per row: `{id, prompt}`.

You do **not** receive, and must not consult before labeling:
- kernel routing scores or `--explain` output for any prompt,
- the stratum a prompt was authored under (strongly-matched / near-threshold
  / paraphrase / p-class),
- `arm1-holdout.jsonl`, `arm1-construction-log.md`, or any other file in
  `.spectra/research/gilgamesh-gate/` besides this rubric and the shuffled
  prompt file,
- the eventual gilgamesh replay outcome (labels are frozen **before** replay
  — AC-G07).

## What you produce

For each row, assign exactly one `ground_truth_owner` from the closed set:

```
{ atlas, ramza, vivi, idg, forge, vigil, kupo, generalist-fallthrough, clarify }
```

Emit `arm2-labels.jsonl`: `{id, ground_truth_owner, labeler_id, labeled_at}`.
Do **not** add any other field (no confidence, no notes column merged into
the corpus file — keep the label file separate from the corpus, per R-052).

## Source of truth (quoted verbatim from `EIDOLONS.md` §"Roster Index")

| Name | Capability class | Trigger verbs | Refuses | Hands off to |
|------|-----------------|---------------|---------|--------------|
| **ATLAS** | scout | map, trace, find where, who calls, call graph, audit (read-only) | implement, fix, edit, write, commit | RAMZA, Vivi, IDG |
| **RAMZA** | planner (default) | spec, plan, decompose, clarify requirements, decision-ready | implement code, modify files | Vivi, IDG |
| **SPECTRA** | planner (opt-in) | named dispatch only | implement code, modify files | Vivi, IDG |
| **Vivi** | coder (default) | implement, build, fix, extend, wire up, make tests pass | design from scratch, novel architecture | IDG |
| **APIVR-Δ** | coder (opt-in) | named dispatch only | design from scratch, novel architecture | IDG |
| **IDG** | scriber | document, ADR, runbook, chronicle, synthesize | explore repo, find calls, retrieve | (terminal) |
| **FORGE** | reasoner | trade-off, which approach, ambiguous, deliberate | implement, retrieve, synthesize prose | (lateral) |
| **VIGIL** | debugger | root cause, flaky, heisenbug, regression after X | build new feature, plan from scratch | (lateral) |
| **Kupo** | executor | rename, import/path fix, lockfile bump, lint autofix, one-line edit, search-replace | design, plan, cross-cutting refactor | (orchestrator-dispatched) |
| **Gilgamesh** | generalist (fallback-only) | (none — Step-2(a) fallthrough only) | design, plan, deploy, migrate, route, spawn, underspecified | (orchestrator-dispatched; PROPOSEs upward) |

> SPECTRA and APIVR-Δ are **opt-in conservative peers** of RAMZA and Vivi
> respectively — same capability class (planner / coder), same public
> trigger/refuse columns, dispatched by name rather than by default. This
> rubric's owner enum does not distinguish them: **label planner-class asks
> `ramza` and coder-class asks `vivi`**, regardless of whether the prompt
> happens to name SPECTRA or APIVR-Δ explicitly (see Tie-break rule 1).

## One-line owner definitions

- **atlas** — read-only exploration: mapping, tracing, call-graph, "who
  calls", entrypoint listing, read-only audit. Never implements.
- **ramza** — planning/spec work: writing a spec, decomposing work,
  clarifying requirements, decision-ready scoping (covers SPECTRA-named
  asks of the same shape — see note above). Never implements code.
- **vivi** — coding work: implement, build, fix, extend, wire up, make
  tests pass (covers APIVR-Δ-named asks of the same shape). Never designs
  from scratch / greenfield.
- **idg** — documentation synthesis: document, ADR, runbook, chronicle,
  changelog narrative. Never explores/retrieves code itself.
- **forge** — trade-off deliberation: "which approach", "should we", X-or-Y,
  ambiguous decisions. Never implements or retrieves.
- **vigil** — forensic debugging: root cause, flaky/heisenbug, regression
  after a change, post-mortem. Never plans a new feature from scratch.
- **kupo** — narrow, localized micro-task execution: a single rename, a
  one-line import/path fix, a lockfile/version bump, lint autofix,
  search-replace confined to a small, named scope. Never a cross-cutting
  refactor or a design task.
- **generalist-fallthrough** — the prompt is concretely actionable (has a
  named target, a deliverable, and an acceptance condition) but does not
  match any specialist's trigger vocabulary above, and is not refused by
  every specialist for a *different* reason (e.g. it is not simply
  "deploy" or "route to another Eidolon"). This is Gilgamesh's Step-2(a)
  seat: the residual, bounded-authority PROPOSE-only worker.
- **clarify** — the prompt lacks a concrete deliverable, a named target, or
  bounded scope (e.g. "make the project better", "improve performance
  somewhere"), OR is genuinely ambiguous between two owners with no
  resolving signal below. This is Step-2(b): 1–3 clarifying questions, no
  dispatch.

## Tie-break rules

1. **Named-mention-only prompts** ("Ramza, any thoughts on this?") with no
   task content beyond the name: label by the **named specialist's owning
   class** (ramza/vivi/atlas/idg/forge/vigil/kupo per the table above,
   collapsing SPECTRA→ramza and APIVR-Δ→vivi) — a bare name still signals
   intended audience, which is the ground-truth question this rubric asks.
   Do not label these `clarify` merely because they carry no verb; only
   label `clarify` when the prompt names no one AND carries no actionable
   content (rule 5).
2. **Chain-spanning prompts** (trigger vocabulary from ≥2 classes
   co-occurs, e.g. "decide whether X or Y, then build it"): label by the
   **first SDLC-phase owner** in the implied sequence — decide-before-build
   → forge; scout-before-spec → atlas; plan-before-build → ramza. If the
   two halves are genuinely inseparable (neither can be labeled without the
   other), label `clarify`.
3. **Version/decimal/measurement tokens are never a named target.** A
   prompt whose only concrete-looking anchor is a bare version/decimal
   (`2.5.0`, `30.5s`) with no file, path, or identifier is `clarify` unless
   it also carries a real deliverable/acceptance pair, in which case
   evaluate normally (specialist first, `generalist-fallthrough` only if no
   specialist owns it).
4. **Non-English or emoji-only prompts** → `clarify`. The roster's public
   table is English-only; no specialist match can be made in good faith.
5. **Generic, pathless asks** ("make the project better", "improve
   performance somewhere") → `clarify`, never `generalist-fallthrough` —
   there is no bounded deliverable to hand anyone, specialist or not.
6. **Refused-by-everyone-but-still-actionable** asks (bounded, concrete,
   acceptance-carrying, but outside every specialist's trigger vocabulary)
   → `generalist-fallthrough`.
7. If two owner definitions both plausibly apply and none of rules 1–6
   resolves it, label `clarify` and flag the row for second-labeler
   adjudication (see below). Never resolve a genuine tie by intuition
   ("feels like a Vivi task") — that defeats the independence guard this
   rubric exists to provide.

## Independence guard (R-052 / AC-G07)

- The labeler's identity **MUST NOT** be `ramza` (spec maker), `vivi`
  (implementation maker), or `generalist-builder` (author of the
  Gilgamesh member methodology). It also must not be
  `gate-author-sonnet-fresh` (this document's author) — the gate author
  constructs the corpus and this rubric but does not label.
- Labels are assigned **before** any Arm-1/Arm-2 replay and are SHA-frozen
  alongside the corpus (`FREEZE.sha256`) — a label written or revised after
  seeing a replay outcome is void.
- **Disagreements are adjudicated by a second, independent blind labeler**
  (different identity from the first, same independence constraints,
  same rubric, same shuffled input, no access to the first labeler's
  output while labeling). If the two labels differ, a third read against
  this rubric's tie-break rules resolves it; an unresolved 1-1 split with
  no rule-based resolution is recorded as `clarify`.
- The labeler must not consult `git log`/`git blame` on
  `.spectra/changes/generalist-eidolon/` or this gate's construction
  artifacts before labeling — that would leak stratum and defeat blindness.

## Labeling procedure

1. Read `arm2-for-labeling.jsonl` top to bottom (shuffle order is
   intentional; do not re-sort by `id`).
2. For each `{id, prompt}`, apply the owner definitions, then the
   tie-break rules in order (1→7), stopping at the first that resolves.
3. Emit one line per row to `arm2-labels.jsonl`:
   `{"id": "...", "ground_truth_owner": "...", "labeler_id": "...", "labeled_at": "..."}`.
4. Do not annotate `arm2-corpus.jsonl` itself; the label file stays
   separate so the corpus + labels can be SHA-verified independently
   (R-052's "assigned blind before replay, SHA-frozen alongside the
   corpus" requirement).
