# SPEC — ASCII Art Redesign, Refinement Delta (ATLAS / VIGIL / APIVR)

- **ID**: spec-ascii-art-redesign-002 (refinement of -001)
- **Status**: draft — decision-ready
- **Owner**: nexus maintainer (Rynaro)
- **Producer**: SPECTRA (S→P→E→C→T→R→A)
- **Downstream executor**: APIVR-Δ (recomposition only)
- **Scope**: 3 sigil files. Nothing else changes.
- **Inherits**: envelope (12×6), palette, mechanical gates G1..G9, editorial gates G10..G13 from spec-ascii-art-redesign-001.

---

## Why this refinement exists

The initial redesign shipped. User review flagged **three** of six sigils:

| Sigil | User complaint | Diagnostic (confirmed on read) |
|-------|----------------|--------------------------------|
| `atlas.txt` | "misaligned" | Wing diagonals use inconsistent per-row offsets (3-space, 2-space, 1-space, 0-space), producing a kinked/zigzag V rather than strict diagonals. |
| `vigil.txt` | "misaligned" + "looks like a coffin, gives bad impressions" | Rounded top + widening straight sides + closed base `╲__╱` is a casket silhouette. Trailing `.` only on the right reads as one-sided tears. Eye ◉ is off-axis (col 5) while brow `▔` sits at col 6. |
| `apivr.txt` | "looks massive" (reads as tower, not creature) | Rows 3–5 are a solid 7-wide block for 3 consecutive rows — a monolithic wall with no shoulder/torso/base separation. Head `▲` is a single-cell tick dominated by the block mass. |

Three sigils are untouched and serve as the **family-coherence reference**: `spectra.txt`, `forge.txt`, `idg.txt`. Any refinement must feel like a member of the same family as those three.

---

## Scope lock (what does NOT change)

- Envelope: **12 cols × 6 rows** per sigil. No exceptions.
- Palette: exactly as in spec-001 §character-palette. No double-line box chars inside sigils.
- Mechanical gates G1..G9 in `cli/tests/art-lint.sh`: unchanged.
- Loader constants (`UI_SIGIL_WIDTH=12`, `UI_SIGIL_HEIGHT=6`) and card math: unchanged.
- Banner (`art/banner.txt`): unchanged.
- Bats tests: unchanged except that `ui-preview.sh` output for these three cards should look visibly cleaner.
- `spectra.txt`, `forge.txt`, `idg.txt`: **not edited**. Do not touch.

Only three files change: `art/eidolons/atlas.txt`, `art/eidolons/vigil.txt`, `art/eidolons/apivr.txt`.

---

## Column convention (applies to all three refined sigils)

The envelope is 12 columns, indexed `1..12`. There is **no true single center column** in an even-width grid — the vertical axis of symmetry falls **between columns 6 and 7**. Define:

- **Axis** = the line between col 6 and col 7. Mirror pairs: (6,7), (5,8), (4,9), (3,10), (2,11), (1,12).
- A "centered" single-cell feature MUST occupy **col 6 or col 7**, and when the design has a vertical element spanning multiple rows, that element MUST stay in the same column across every row it appears in. Drifting between 6 and 7 across rows is a G3-class alignment failure (even if art-lint passes byte-width).
- When a focal glyph is pinned in prose below as "col 6", it means literally col 6. Not col 5, not col 7. If mirrored companion features exist, they pair at col 7 (their mirror partner).

---

## Delta briefs

### ATLAS — cartographer / scout — **REFINED**

**Motif redirect**: was a kinked V with a floating eye (reads as "broken wings"), now a **strict-diagonal soaring bird-of-prey silhouette** with a single focal eye or cardinal marker on the vertical axis. Picture Valefor from above in flight — two clean wings, small head, airy.

**Geometric construction rule** (strict; this is the fix for the alignment complaint):

- Wings are **strict diagonals**. Define a wing-row offset function: on the two wing rows, each successive row moves the diagonal glyph **exactly one column outward from the axis** (left wing) and **exactly one column outward** (right wing). No "3-space jump then 2-space jump" — monotonic +1 per row.
- The body column (any vertical stroke, head mark, or tail mark) MUST sit at col 6 OR col 7 and MUST NOT drift between rows.
- If wings use `╱` (right-leaning, for the left wing going up-and-out) and `╲` (left-leaning, for the right wing going up-and-out), each instance on row N MUST be exactly one cell further from the axis than the same-side instance on row N-1 (or N+1, depending on whether wings rise or droop). Pick a direction; hold it.
- A cardinal marker (compass star `✦ ✧` or a small cross) MAY sit above the body on the axis — if present, ONLY on one row, ONLY at col 6 or col 7.

**Focal feature**: a single body-column element (eye `◉`, dot `·`, or small head mark) pinned at **col 6**. At most one "halo" or "star" mark above it at col 6 or col 7 (one row only).

**Anti-pattern box** (any of these = reject):
- Wings with mixed per-row offsets (e.g. gap sequence 3→2→1 that skips or reverses).
- Horizontal elements (`─`, `▔`, `═`) inside the wing span — ATLAS should read as airborne/open, not boxed-in.
- A closed outline at the bottom (bird is in flight, not perched in a cage).
- Any frame-like enclosure of the body — the card already has a frame.
- Filled block mass (`█`, `▓`). ATLAS is light; that weight belongs to APIVR.

**FF-summon aesthetic references** (cue, not copy):
- **Valefor** (FFX): light wings, small head, graceful diagonals — primary reference.
- **Pandemona** (FFVIII): wind-swept openness, lots of negative space.
- **Carbuncle** (recurring): small intelligent non-threatening focal creature.

**Density target**: ≤ 30% non-space cells across the 72-cell envelope. Whitespace dominance is a feature.

---

### VIGIL — debugger / forensic guardian — **REFINED**

**Motif redirect**: was a closed coffin-outline with one-sided tears (reads as "mourning"/"casket"), now a **sharp sentinel-eye or open-hooded lens**, vertical and alert. Think Odin's pre-strike stillness, not Anima's shackled grief. The silhouette MUST NOT close at the bottom.

**Geometric construction rule**:

- **Base is open, not sealed.** No `╲__╱`, no `╰──╯`, no `╲══╱`, no `└──┘` at row 6. The bottom row may taper to a point, may show legs/stance glyphs, may be empty on the axis, or may frame a grounded stance — but it MUST NOT be a horizontal closure across the axis columns. Specifically: the axis cells (col 6 AND col 7) on row 6 MUST NOT both be filled with connecting horizontal strokes.
- **Focal eye pinned at col 6**, on the row where the silhouette is widest (typically row 2 or 3). The eye is the dominant feature; everything else is supporting.
- Any brow, lid, or accent mark associated with the eye MUST sit at col 6 directly above or below the eye. No more "eye at col 5, brow at col 6" drift.
- Hood/mantle, if present, uses light single-line glyphs (`╱ ╲ · ·`) and opens outward (like shoulders), not inward (like a casket wall narrowing).

**Focal feature**: the eye glyph (`◉`, `⊙`, `◎`, or `●`) at **col 6**. This is the defining feature of VIGIL; if a reviewer cannot find an eye, the sigil fails.

**Symmetry accent rule**: forensic-dust particles (`·`, `.`, `˙`) are permitted but MUST be either (a) present symmetrically on both sides of the axis, or (b) confined to a single row at the very top or very bottom of the envelope as a textured band. A **one-sided trailing column of dots is banned** — that is what produced the "tears" reading in the shipped version.

**Anti-pattern box** (any of these = reject):
- **Closed base** of any kind spanning the axis on row 6.
- Rounded top (`╭───╮`) combined with straight widening sides (`╱ ... ╲`) combined with a closed bottom — the coffin combo. Break at least one of those three to be safe; the cleanest fix is breaking the base.
- Asymmetric trailing dots, trails, streaks on only one side of the axis.
- Eye offset from col 6.
- More than one eye (two eyes reads as a generic face/skull, not a sentinel lens).
- Hood that narrows inward and fully encloses the eye on sides + top + bottom (that's Anima; VIGIL is NOT Anima).
- Double-line chars anywhere (palette rule, reiterated — but especially relevant here because `═` inside a hooded shape reinforces tomb iconography).

**FF-summon aesthetic references**:
- **Odin** (FFXVI specifically): vertical armored sentinel, sword as vertical axis — the "alert, about to strike" read. Primary reference.
- **Yojimbo** (FFX): silent watcher, poised.
- **Carbuncle's ruby** as a pure-eye motif abstracted from the body.

**Anti-reference (explicit)**: **Anima** (FFX). Hooded, shackled, contained-suffering. VIGIL is NOT this. If the draft starts to look like Anima, discard it.

**Density target**: 35–50% non-space cells. Denser than ATLAS (VIGIL is "focused"), but never walled-in.

---

### APIVR-Δ — coder / brownfield implementer — **REFINED**

**Motif redirect**: was a 3-row × 7-col solid block with a tiny triangle tick (reads as "tower/monolith"), now a **horned anvil-bearing creature with distinguishable head, shoulders, and planted base**. Titan's articulation, not Titan's mass alone. Ifrit's horns and planted stance.

**Geometric construction rule**:

- **No single solid-block region may span more than 2 consecutive rows** at width ≥ 5. If a wide filled band is needed, it must be broken by at least one row of differentiated silhouette (gaps, partial blocks `▀ ▄ ▌ ▐`, or transitions `▓ ▒`) so the eye can parse head → shoulders → torso → base as distinct zones.
- The silhouette MUST have at least **three distinguishable vertical zones**: (1) head/horns at top, (2) shoulders or arms wider than the head, (3) base/anvil-stance at bottom, differing in width or fill from the torso.
- **Strict vertical-mirror symmetry required** (see Symmetry rules §below). The anvil motif is grounded; asymmetry reads as off-balance.
- Widest row (shoulders or anvil base) is at least **2 cells wider** than the head row. This is how we avoid "tower" — the creature must flare.
- A Δ may appear as head-glyph, chestplate-glyph, or anvil-face-glyph, but it is an accent, not the whole creature. If a reviewer sees "a triangle" before they see "a creature", that's a fail.

**Focal feature**: the shoulder-line or anvil-line — whichever is the **widest row** — pinned symmetrically about the axis (cols 6–7 center, mirrored outward). Head element on the axis at col 6 OR col 7 (must be consistent with whichever shoulder-line arrangement was picked).

**Anti-pattern box** (any of these = reject):
- Three or more consecutive rows of identical width ≥ 5 filled with the same glyph (that's the monolith/tower failure from the shipped version).
- Head smaller than a 3-cell element while torso is 5+ cells (dominated head = "building with a flag on top", not a creature).
- No visible widening at any row — a uniform-width silhouette top-to-bottom is a column/tower by definition.
- Floating Δ with no creature body (was spec-001's call-out; still applies).
- Any silhouette that could be mistaken for a chess rook, a silo, an obelisk, or a filing cabinet.
- Overlap with FORGE's flame motif. APIVR is a **metal** forge; FORGE is a **mental** forge. Keep them visually distinct: APIVR is articulated mass, FORGE is scattered sparks.

**FF-summon aesthetic references**:
- **Titan** (FFXVI): stone giant, heavy but with clearly articulated head, shoulders, torso, legs — primary reference for "heavy but legible".
- **Ifrit** (FFXVI): horned, planted stance, asymmetric flame mane suggesting volume without solidity — secondary reference for "breaking up the mass".
- **FFXV Hammerhead garage** vibe: industrial, grounded, workshop-ish — for the anvil tone.

**Density target**: 50–70% non-space cells. Still the heaviest of the six, but with visible internal structure, not a wall.

---

## Symmetry rules (new subsection)

The original spec-001 specified symmetry for the banner but was silent for sigils. This refinement makes it explicit for the three flagged sigils. For the three untouched sigils (`spectra`, `forge`, `idg`), the shipped symmetry behavior is ratified as-is.

| Sigil | Symmetry rule | Rationale |
|-------|---------------|-----------|
| **ATLAS** | **Strict vertical-mirror symmetric**. Every non-space cell at column C has its mirror at column 13−C (since columns are 1-indexed 1..12; mirror pair = col C ↔ col 13−C). Exceptions: none. | Bird-of-prey silhouettes from overhead are bilaterally symmetric; any asymmetry reads as injured wing, which contradicts the "competent watcher" reading. |
| **VIGIL** | **Vertical-mirror symmetric preferred**. A single asymmetric accent is permitted ONLY IF it occupies a full row of textural particles (forensic dust band, top row or bottom row) OR is mirrored on both sides. A **one-sided trailing column** of any character is banned (this is what produced the "tears/mourning" read in the shipped version). | Sentinel figures read as centered and alert; one-sided trails read as grief or instability. |
| **APIVR-Δ** | **Strict vertical-mirror symmetric REQUIRED**. No exceptions. | Anvil-bearing creatures are planted and grounded; asymmetry reads as off-balance and contradicts the "substantial" reading the user wants preserved. |

**Implementer note**: an optional tenth mechanical gate `G1b` could automate strict mirror symmetry for these three files (reverse each row and compare cell-by-cell). This is **not required** for this cycle — editorial review is sufficient — but it is cheap to add if APIVR-Δ wants extra insurance. If added, gate it to these three files only; `spectra`/`forge`/`idg` were authored without this constraint and should not retroactively fail.

---

## Updated editorial gate G10 (for these three sigils only)

Spec-001's G10 asked: "Can a reviewer name the creature/motif within 2 seconds?" This refinement adds a **negative** check on top of the positive one: reviewers must ALSO confirm that none of the following **failure readings** surface within the same 2-second window.

**Failure-keyword list** (reviewer must actively check for these when evaluating the refined sigils):

| Sigil | Banned readings (if ANY reviewer says one of these, the sigil fails) |
|-------|----------------------------------------------------------------------|
| **ATLAS** | "broken wings", "zigzag", "kinked", "shattered", "glitch", "jagged V", "crooked" |
| **VIGIL** | "coffin", "casket", "tomb", "mourning", "tears", "crying", "grave", "sad mascot", "hooded prisoner", "funeral", "Anima-like" |
| **APIVR** | "tower", "monolith", "obelisk", "wall", "block", "rook", "silo", "filing cabinet", "massive" (the user's original word), "building" |

**G10 protocol for the refinement**:
1. Show the sigil alone (no label, no card context) to 3 reviewers for exactly 2 seconds each.
2. Ask: "What does this look like?"
3. Pass if: ≥ 2 reviewers name a reading consistent with the motif redirect AND **0 reviewers** use any word from the banned-readings list.
4. Fail if: any reviewer uses a banned reading keyword, OR fewer than 2 reviewers identify the intended motif.

This is stricter than spec-001's G10 because the failure modes are already known and empirically demonstrated on the shipped version — the refined assets must not regress into the same traps.

---

## Handoff note to APIVR-Δ

This is a **recomposition**, not a redo. Preserve everything except the three flagged files. Specifically:

- **Do not touch**: `art/banner.txt`, `art/eidolons/spectra.txt`, `art/eidolons/forge.txt`, `art/eidolons/idg.txt`, `cli/src/ui/art_loader.sh`, `cli/src/ui/card.sh`, `cli/tests/art-lint.sh`, `cli/tests/art-lint.bats`, `cli/tests/ui-preview.sh`, any loader constants, any card layout math.
- **Do touch**: `art/eidolons/atlas.txt`, `art/eidolons/vigil.txt`, `art/eidolons/apivr.txt` — full rewrite of content, same filenames, same 12×6 envelope, same palette, same bytes-vs-columns rules.
- **Slice ordering**: three independent Δ-slices, one per sigil. Suggested order: ATLAS (simplest — pure alignment discipline), APIVR (recomposition with three-zone structure), VIGIL (trickiest — motif redirect away from coffin). Land each as its own PR so G10 reviewer feedback on one doesn't block the other two.
- **Validation per slice**: run `bash cli/tests/art-lint.sh` (must pass all of G1..G9 unchanged) and `bash cli/tests/ui-preview.sh roster <name>` (visual smoke on a 80-col TTY).
- **Acceptance per slice**: score ≥ 80/100 on the spec-001 rubric AND pass this refinement's strengthened G10 (no failure keywords from the list above).
- **No scope creep**: if while authoring VIGIL you think the shipped SPECTRA sigil would also benefit from a tweak, file a separate follow-up. This cycle fixes only the three flagged files. The user did not complain about the other three and trust is earned by honoring scope.

**FORGE consult trigger** (unchanged from spec-001): invoke FORGE only if a motif collision emerges while drafting — e.g. APIVR's new head shape starts to resemble FORGE's spark cluster, or VIGIL's eye starts to resemble SPECTRA's crystal focal. Otherwise proceed without consult.

---

## Open questions

All three fixes can proceed without further user input. The user's complaints are specific, the diagnostics are confirmed on-read, and the motif redirects are grounded in the FF-summon aesthetic references the original spec already endorsed. No blocking OQs.

Non-blocking follow-ups (file as separate cycles if the user wants):

- **OQ-R1**: should mirror-symmetry become a mechanical gate (`G1b`) enforced by `art-lint.sh` for all future sigils? Recommendation: **defer**; adopt only if a third alignment regression lands. Editorial review caught this one fine.
- **OQ-R2**: should the `ui-preview.sh` harness grow a "3-reviewer G10 checklist" mode that prints just the sigil in isolation (no card, no label) to make editorial review faster? Recommendation: **nice-to-have**; not required for this cycle. Could be a small FORGE or IDG follow-up.

---

## Acceptance summary (refinement-specific)

Ship the refinement when:

1. Three files (`atlas.txt`, `vigil.txt`, `apivr.txt`) pass G1..G9 unchanged.
2. Three files score ≥ 80/100 on the spec-001 rubric.
3. Three files pass the strengthened G10 with the failure-keyword list (§updated G10).
4. Three files pass the symmetry rules (§symmetry rules).
5. `bats cli/tests/` is green (no regression).
6. The untouched three sigils and the banner are byte-identical to the shipped versions (verify with `git diff --stat` — should only show the three intended files changed).
