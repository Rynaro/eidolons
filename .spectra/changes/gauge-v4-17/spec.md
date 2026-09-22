# V4-17 preparatory implementation contract

Canonical authority: plan c581308f055a0e252013bf09f2a7b2e1426ff811. Implement only after predecessor code, tests and distinct review satisfy the DAG. No live/provider dispatch is claimed by this package. All applicable canonical requirements below remain binding. The attached decision resolves bounded implementation choices; it cannot grant runtime provider authority or publication authority.

## V4-17 — Publish explicit Vivi candidate and context modes

**Default source owner:** `Rynaro/Vivi`. **Prerequisites:** `V4-15`, `V4-21`.

**Scope and decisions.** Amend fresh-context/human-apply assumptions only in named opt-in modes. Support proposal-only and authorized continuous candidate-workspace work. Preserve greenfield/publication boundaries unless separately revised. Continuing maker and clean checker context are different; neither retry strategy is predeclared the winner. Gauge does not grant publication authority. Sibling Vivi remains canonical until accepted V4-10 relocation.

| ID | EARS requirement | Planned verification |
|---|---|---|
| V4-17-R01 | WHEN candidate-workspace mode is selected with scoped authorization, Vivi SHALL edit only the authorized candidate workspace. | **V4-17-T01** |
| V4-17-R02 | WHERE proposal-only mode is selected, Vivi SHALL return a candidate proposal without applying it to the user tree. | **V4-17-T02** |
| V4-17-R03 | WHEN a coherent task uses continuity mode, Vivi SHALL retain relevant decisions and failure history across repair attempts. | **V4-17-T03** |
| V4-17-R04 | IF independent verification is required, THEN Vivi SHALL submit the candidate to the controller-managed verification boundary. | **V4-17-T04** |
| V4-17-R05 | IF a task exceeds Vivi's declared authority or greenfield scope, THEN Vivi SHALL return the applicable boundary rather than using method composition to evade it. | **V4-17-T05** |
| V4-17-R06 | WHEN a context strategy is selected, Vivi SHALL record the strategy version and its observed context-transition boundary. | **V4-17-T06** |

## Bounded decision

See [decision.md](decision.md). Schema-2 additive vivi_* namespaces. Named opt-in modes only (`proposal_only`, `candidate_workspace`). No V4-16/18/10/19/22.
