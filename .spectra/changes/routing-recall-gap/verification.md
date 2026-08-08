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

## Checker round 3 — **REJECT**

Round 2's kernel form predicate was the right mechanism and fixed everything it
was aimed at — and then failed in the same shape one level up. `$is_question`
was `ends with '?' OR opens with a modal`, evaluated over the whole prompt with
no check for an imperative. So:

```
can you implement the retry logic in the worker?   -> clarify   (vivi 0.30)
would you refactor the roster loader for clarity?  -> clarify
implement the retry logic. is that ok?             -> clarify
refactor the roster loader, ok?                    -> clarify
```

**Six of the eight measured failures are this suite's own tasks** — `N-019`,
`N-020`, `N-023`, `N-024`, `N-025`, `N-026` — with nothing changed but a
courtesy prefix and a question mark. The suite reported **69/69** throughout.
Apply the most common politeness transformation in English to the corpus and
the recall arm collapses; no guard covered it, because not one of `N-G11`–`N-G20`
put a `?` on an imperative.

Two secondary findings, both "a closed list with a tail" under absolute
invariant wording:

- `read_only_question` did not fire on a question containing none of its 11
  function words — `"what is our current code coverage?"` → `vivi`, from the
  checker's own corpus (5/5 constructed to that shape reached a writer).
- The repo-wide list missed `across the codebase` / `throughout the repo` /
  `globally` / `all files` / `codebase-wide`: **8/10** unbounded mutations
  still routed.

## Remediation round 3

`$is_question` now models **request vs question** instead of punctuation:

- **First sentence only.** A trailing tag cannot turn the imperative before it
  into a question. Split on `". "` so a filename keeps its dots.
- **Modal-request frame is not a question.** `can/could/would/will` + `you/we`,
  or a leading `please`.
- **Imperative head is not a question.** `"add retry logic to the fetch step?"`
  is an instruction wearing a question mark.
- **`do`/`have`/`had` need a pronoun subject** to count as openers, which is
  what separates `"have we ever had to migrate this config?"` (question) from
  `"have a look at the loader"` (imperative). Those words are deliberately
  absent from the imperative-head list, or they would win the AND-NOT and
  misclassify the question.

Both closed lists were widened, and both invariants reworded from "never" to
what is actually measured — absolute wording is what earned rounds 1 and 2.

Guards `N-G21`–`N-G29` pin the new axis: polite/modal requests and tag
questions must route; questions without common function words and the wider
repo-wide vocabulary must clarify.

**Not fixed, and it is a pre-existing gap rather than a regression:**
`"do the migration in cli/src/lib.sh"` still clarifies — `migration` is a noun
and the coder lexicon has `migrate`. Adding the noun was tried and reverted: it
broke `N-030` (`"draft an approach for the migration"`), which correctly routes
to the planner. Trading a correct route for a prompt that never worked is not
an improvement.

## Evidence after round 3

| AC | Result | Evidence |
|---|---|---|
| AC-1 | **PASS** | recall arm 100 % |
| AC-2 | **PASS** | 0 MISS |
| AC-3 | **PASS** | `public` 15/15 |
| AC-4 | **PASS (measured both directions)** | 9/9 polite/modal requests route · 6/6 tag-question imperatives route · 3/3 subordinate-clause imperatives route · 9/9 interrogatives clarify · 7/7 repo-wide clarify · 3/3 path-bounded route. Guards `N-G01`, `N-G06/07/10`, `N-G11`–`N-G29` |
| AC-5 | **PASS** | recall arm collapses to **8.2 %** vs `v2.17.0`; exit 0 / 1 / 2 verified |
| AC-6 | **PASS (corpus, both directions)** | 12/12 real work requests surface (incl. 6/6 courtesy-prefixed shapes); 39/40 conversational silent |
| AC-7 | **PASS** | `make lint` 0 · `make schema` 0 · budget 836/850 · bash 3.2 construct test green |
| AC-8 | **PASS** | full `bats cli/tests/` green, counted against the plan |

Suites: recall **77/77**, public **15/15**, self-test **96 tasks**.
Frozen `generalist-eidolon` fixtures: all 11 resolve to contracted routes.

Both kernel predicates were verified by mutation rather than by reading —
removing `requires_question_form` drops recall 69/69 → 41/69 and
`guard-clause` to 0/4; removing `skip_if_path` drops `guard-unbounded` to 3/5.
The guards depend on the mechanism they claim to guard.

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
