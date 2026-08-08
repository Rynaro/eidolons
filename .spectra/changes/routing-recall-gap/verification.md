# Verification — `routing-recall-gap`

> ESL change `routing-recall-gap` · tier **full**
> Maker: `vivi` · Checker: `kupo` (maker ≠ checker, C4 — mechanically enforced)

## Checker round 1 — **REJECT**

An independent checker (distinct actor, clean context) was dispatched against
the shipped code at `ec92dce` and told explicitly what the maker was least sure
of. It rejected. Every finding below came from *running* the kernel and the
hook, not from reading this record.

| # | Severity | Finding | Status |
|---|---|---|---|
| F1 | **BLOCKER** | Read-only interrogatives routed to write-capable Eidolons: **3/24 → 15/24** over the checker's own corpus. `"which port does the server listen on?"` → `vivi`, and the hook then instructed the host to delegate to a coder. Culprits: bare `port`, `modify`, `update the`, `migrate`. | **FIXED** |
| F2 | **MAJOR** | `unbounded_scope` was an **unconditional veto**, not the "bare verb match" its note claimed (−0.4 killed even raw=3: 0.97 → 0.57). It suppressed bounded one-file work while bare `everywhere` routed through. Its "mirrors predicate S5" claim was false — S5 has a LIMITER rescue that Step 1 never implemented. | **FIXED / claim corrected** |
| F3 | **MAJOR** | The work-intent discriminator used **unanchored substring globs**: `*test*`→"la**test**", `*spec*`→"e**spec**ially", `*plan*`→"ex**plan**ation". Fired on 12/20 conversational prompts including `"how are you today?"`, and stayed **silent on 12/12** genuine work requests. The AC-6 negative test pinned the single string that happened to work. | **FIXED** |
| — | minor | `verify-recall-mutation.sh` default `HEAD~1` false-alarms from a later checkout; `spec.md`/`spec.yaml` were untracked; AC-6 cited the wrong test file. | **FIXED** |
| — | none | AC-1/2/3/5/7, `files_touched`, and the frozen Gilgamesh fixtures all verified green independently. | confirmed |

The checker's through-line: **the change asserted precision over a 5-task guard
set and never measured it** — the same tautology on the precision axis that the
change was written to remove on the recall axis. AC-5 proved the suite was
sensitive to lexicon *removal*; nothing in it was sensitive to lexicon
*addition*.

## Remediation round 1 — **also REJECTED**

The first remediation fixed the three findings *as reported* and introduced
three new defects of the same species. The checker's verdict on it is the most
useful sentence in this record: **"the fix tracks the published examples, not
the class."**

| # | New defect introduced by round 1 | Measured |
|---|---|---|
| 1 | `read_only_question` presence-matched anywhere, so ordinary imperatives carrying a subordinate `which` / `is the` / `what happens` were vetoed | **18/18** and (independently) **12/12** correct dispatches → `clarify` |
| 2 | `unbounded_scope` weakened to −0.25 let `localized_micro_task` (+0.15) carry repo-wide renames back to Kupo at 0.70 | **5/7** probes |
| 3 | The conversational deny-list was checked FIRST and won outright, so a courtesy prefix silenced real work: `"thanks! now bump the timeout to 30 seconds"` | **5/5** silent |

All three were invisible to a 59/59 suite, because the guards added in round 1
were the checker's own example prompts rather than the axis they belong to.

## Remediation round 2 — fixing the class

Two of the three needed a **kernel** change, which is why round 1 could not get
there with data alone.

- **`requires_question_form` (kernel).** `read_only_question` now applies only
  when the prompt IS a question — ends in `?`, or opens with an interrogative.
  Head position is what makes a question a question; a mid-sentence "is the" is
  not. This also dissolved the "new class" of openers (`did` / `have we` /
  `were` / `am I` / `isn't` / `how do I`) that a closed phrase list kept
  missing: form cannot be walked around by inventing another opener. The match
  list is now deliberately generic function words, since form does the gating.
- **`skip_if_path` (kernel) + a two-tier scope signal.** `unbounded_scope`
  (repo-wide: `entire codebase`, `everywhere`, `repo-wide`, …) is never
  rescued, at −0.4 so `localized_micro_task` cannot cancel it.
  `unbounded_scope_qualified` (`all call sites`, `every file`) is skipped when
  a PATH token is present. **This is the S5 limiter/path rescue that round 1
  declared impossible** — the honest-limit paragraph it added is now obsolete
  and removed, because the rescue exists.
- **Deny-list deleted; work intent decides and is checked first.** With the
  order inverted the deny-list was redundant (no acknowledgement it listed
  contains a work verb), so it is gone rather than kept as decoration.
  `wrong`/`error` dropped from the work list — common in chat, and genuine
  failure reports reach VIGIL through the kernel.
- **Guards now pin the AXIS**: `N-G11`–`N-G14` (imperative + subordinate
  interrogative clause → MUST route), `N-G15`–`N-G17` (question form via
  openers no phrase list contains), `N-G18`–`N-G20` (repo-wide vs
  path-bounded scope).

## Evidence after round 2

| AC | Result | Evidence |
|---|---|---|
| AC-1 | **PASS** | recall arm 100 % |
| AC-2 | **PASS** | 0 MISS |
| AC-3 | **PASS** | `public` 15/15 |
| AC-4 | **PASS (measured both directions)** | 10/11 checker interrogatives clarify; **14/14** subordinate-clause imperatives route; 5/5 repo-wide scope clarifies; 2/2 path-bounded routes. Guards `N-G01`, `N-G06/07/10`, `N-G11`–`N-G20` |
| AC-5 | **PASS** | recall arm collapses to **8.2 %** vs `v2.17.0`; exit 0 / 1 / 2 verified |
| AC-6 | **PASS (corpus, both directions)** | 12/12 conversational silent (incl. `nothing wrong with that`, `human error, no biggie`); 6/6 courtesy-prefixed work requests surface; `cli/tests/harness.bats` green |
| AC-7 | **PASS** | `make lint` 0 · `make schema` 0 · budget 836/850 · bash 3.2 construct test green |
| AC-8 | **PASS** | full `bats cli/tests/` green, counted against the plan |

Suites: recall **69/69**, public **15/15**, self-test **88 tasks**.
Frozen `generalist-eidolon` fixtures: all 11 resolve to contracted routes.

## Residual — disclosed

- **`"remind me what the migrate step does"`** still reaches a writer. It is
  interrogative in *intent* but imperative in *form*, so the form gate does not
  fire. Accepted: widening form detection to cover polite-imperative info
  requests risks the subordinate-clause regression all over again.
- **`"should we refactor this or leave it?"`** forms a `decide-then-implement`
  chain rather than a lone FORGE dispatch. `should we` is deliberately excluded
  from `read_only_question` — penalising the coder there would make that chain
  unreachable. FORGE runs first and may conclude "leave it".
- The discriminator remains a heuristic; it never selects an Eidolon and fails
  open in both directions. Ordinary non-technical chat containing a listed verb
  ("can you make it to standup?") costs one extra context line.

## What two rejection rounds actually taught

Round 1's gates were real and each was sensitive to exactly **one** direction of
failure: `AC-5` could see a lexicon getting *narrower* and was structurally
blind to one getting *wider*. Round 2's lesson is narrower and sharper: when a
checker hands you counterexamples, fixing the counterexamples is not fixing the
defect. Every round-1 fix passed the checker's own corpus and broke a class the
corpus did not contain. Two of the three could not be fixed in data at all —
the presence-matching signal table simply cannot express "is this a question",
and pretending otherwise is what produced 18/18 regressions behind a green
suite.
