# SPEC — ASCII Art Redesign (Banner + Eidolon Sigils)

- **ID**: spec-ascii-art-redesign-001
- **Status**: draft — decision-ready
- **Owner**: nexus maintainer (Rynaro)
- **Producer**: SPECTRA (S→P→E→C→T→R→A)
- **Downstream executor**: APIVR-Δ (implementer) with optional FORGE consult on motif selection
- **Repo**: `Rynaro/eidolons` (nexus)
- **Surface**: `art/banner.txt`, `art/eidolons/<name>.txt`, secondary: `cli/src/ui/art_loader.sh`

---

## S — Situation

The nexus ships ASCII art in two tiers:

1. **`art/banner.txt`** — a 6-row block-letter rendering of the word "EIDOLONS" using `█╗╔╝╚═` glyphs. Emitted by `ui_banner()` (`cli/src/ui/panel.sh`) on top-of-CLI invocation (`eidolons --help`) when `EIDOLONS_FANCY=1`.
2. **`art/eidolons/<name>.txt`** — per-Eidolon sigils for `atlas`, `spectra`, `apivr`, `forge`, `idg`, `vigil`. Loaded by `ui_load_sigil()` (`cli/src/ui/art_loader.sh`) into a fixed **14 cols × 8 rows** rectangle and embedded in the left cell of the roster card (`cli/src/ui/card.sh`). The card itself is 66 cols wide with a `╔═╦═╗` double-line frame.

### Problems observed (user-reported + confirmed via reads)

| # | Issue | Evidence |
|---|-------|----------|
| P1 | Banner is lettering, not an emblem. User wants an iconic image-style logo. | `art/banner.txt` is typographic "EIDOLONS". |
| P2 | Sigils are too big. Each wraps itself in its own `╔══╗/╚══╝` frame, and the card already has a frame. Doubled borders waste cells and look noisy. | All six sigils use `╔════════╗ … ╚════════╝` on rows 1 and 7. |
| P3 | Sigils don't read as "eikons" (FF summon silhouettes). They feel like generic icons (triangle, crosshair, delta, spark cluster). | `art/eidolons/atlas.txt` is an upward triangle + eye; `spectra.txt` is a compass-like plus. No creature silhouette. |
| P4 | Width/alignment drift. Several files have rows of differing display widths within the same file, trailing spaces, and reliance on the loader to pad. | `art/eidolons/atlas.txt` row 6 (`║   ▲    ╚╗`) is 11 cols while row 1 (`  ╔════════╗`) is 12. `art/eidolons/forge.txt` row 2 (`║   ✦ ✧   ║`) has spacing that visually skews. |
| P5 | Double-line box-drawing inside sigils clashes visually with the card's double-line outer frame. | Card uses `╔═╦═╗` (double), sigils use `╔══╗` (double) — two frames of the same weight stack. |
| P6 | Sub-label text (`sentinel`, `planner`, `coder`, etc.) is baked into the art file on row 8. This is data, not art — the card already renders `capability_class` from the roster. Redundant and adds alignment burden. | All six files have a role word on row 8. |

### Constraints (from `CLAUDE.md` + code reads)

- **Art files are plain text**; bash 3.2 compat is irrelevant to the art itself. It **is** relevant if `art_loader.sh` changes.
- **Loader contract must not silently change**: `ui_load_sigil` pads to `UI_SIGIL_WIDTH=14 × UI_SIGIL_HEIGHT=8`. The card layout math in `card.sh` depends on these constants. Any dimension change requires a coordinated edit to `UI_SIGIL_WIDTH`, `UI_SIGIL_HEIGHT`, and `UI_CARD_WIDTH` (currently 66).
- **Plain mode exists**: `EIDOLONS_FANCY=0` skips the banner entirely (`ui_banner` early-returns) and the card degrades to a text dump (`_ui_card_plain`) — sigils are **not rendered** in plain mode. This means the art only needs to render correctly when fancy mode is on, which already guarantees a UTF-8 capable interactive TTY. **Decision implication**: we can use Unicode BMP box-drawing + block glyphs freely; we do **not** need an ASCII-only tier for the sigils themselves. (See Open Question OQ-1 for banner-only ASCII fallback.)
- **Output destination is stderr** for the banner. Log aggregators rarely see it. Terminal is the only render target.
- **Loader uses `${#line}` byte count** for padding. The current comment explicitly warns: "keep authoring constrained to the box-drawing / block / dingbat ranges." No CJK, no emoji, no combining marks, no wide-display chars. This is a hard rule for any new art.

---

## P — Plan

Deliver a redesigned asset set and a repeatable authoring/validation workflow:

1. **Shrink + simplify the sigil envelope.** Drop the inner frame entirely (the card provides one); reclaim those ~2 rows + 2 cols per sigil for silhouette density. Shrink from 14×8 to **12×6** (new `UI_SIGIL_WIDTH=12`, `UI_SIGIL_HEIGHT=6`) and re-adjust `UI_CARD_WIDTH` to keep stats column width the same or tighten the whole card.
2. **Re-motif each sigil** as an eikon silhouette — a single creature/sigil readable at a glance. Use FF summons as *aesthetic references*, not copies.
3. **Replace the banner** with a centered emblem composition (summoning sigil / crystal / aetheric glyph) that fits **60 cols × 9 rows** max, with the wordmark rendered by `ui_banner` *below* the art (keeps "eidolons v1.2.3 · tagline" line intact).
4. **Enforce alignment via CI.** Add `cli/tests/art-lint.sh` (bash, bats-compatible) that checks width uniformity, no trailing whitespace, no tabs, character-set whitelist, max-line-length, row count.
5. **Strip the role label** (`sentinel`, `planner`, etc.) from each sigil file. It's already rendered from `capability_class` in the card title line.

### Artifacts this spec produces (not code)

- `specs/ascii-art-redesign.md` (this file)
- `specs/ascii-art-redesign.yaml` (machine-readable counterpart — rubric, gates, stories, size table)

### Artifacts the implementer (APIVR-Δ) will produce

- New `art/banner.txt` (emblem, see banner brief §banner-brief)
- New `art/eidolons/{atlas,spectra,apivr,forge,idg,vigil}.txt` (6 sigils)
- Edit `cli/src/ui/art_loader.sh` — new constants
- Edit `cli/src/ui/card.sh` — adjust `UI_CARD_WIDTH`, re-derive paddings (math already parametric on `UI_SIGIL_WIDTH`)
- New `cli/tests/art-lint.sh` (validation gate script)
- New bats test(s) in `cli/tests/art-lint.bats` that call the lint script
- Updated `cli/tests/ui-preview.sh` snapshot or equivalent

---

## E — Evidence (grounding reads already performed)

- `art/banner.txt` (6 lines, block-letter "EIDOLONS")
- `art/eidolons/*.txt` (six files, 8 rows each, widths drift 10–12 cols)
- `cli/src/ui/art_loader.sh` — defines `UI_SIGIL_WIDTH=14`, `UI_SIGIL_HEIGHT=8`, pads via `${#line}`
- `cli/src/ui/card.sh` — `UI_CARD_WIDTH=66`, layout math `stats_w = UI_CARD_WIDTH - sigil_w - 7`, frame splits at `sigil_seg = UI_SIGIL_WIDTH + 2`
- `cli/src/ui/panel.sh` — `ui_banner` reads `$NEXUS/art/banner.txt`, colors each line with `UI_ACCENT`, fancy-mode only
- `cli/src/ui/theme.sh` — plain-mode (`EIDOLONS_FANCY=0`) skips banner; triggered by `EIDOLONS_PLAIN=1`, `NO_COLOR=*`, `CI=*`, or non-TTY stderr
- `cli/src/ui/glyphs.sh` — fancy mode uses `─│┌┐└┘═║╔╗╚╝╭╮╰╯▸✓·⚠✗•↑↓→`, plain mode replaces box chars with `+/-/|`
- `roster/index.yaml` — capability_class values: `scout, planner, coder, scriber, reasoner, debugger`
- `cli/tests/ui-preview.sh` — visual smoke harness, not CI; sets `FORCE_COLOR=1`

---

## C — Criteria (scoring rubric)

Each submitted asset is scored 0–5 per dimension. Total = weighted sum, threshold **≥ 80/100** to ship. Weights reflect user priority: iconicity + alignment matter more than terminal portability because plain mode skips the art entirely.

| # | Dimension | Weight | 0 | 3 (threshold) | 5 (excellent) |
|---|-----------|--------|---|---------------|---------------|
| R1 | **Iconic read** — does it register as a creature/emblem at a glance (< 2s)? | 25 | Abstract blob; unreadable | Recognizable silhouette in context | Instantly legible; has a "face" or dominant feature |
| R2 | **Motif fidelity** — does the design intent match the Eidolon's role (see §per-eidolon-briefs)? | 20 | Off-theme | Matches primary motif | Matches primary + one layered accent (e.g. cartographer bird with compass) |
| R3 | **Alignment invariants** — passes `art-lint.sh` with zero warnings. | 20 | Fails 2+ gates | Passes all gates | Passes all gates + every row is visually centered in its bounding box |
| R4 | **Size budget** — within the envelope in §size-budget. | 10 | Overflows | At budget | Uses 80–95% of budget (good density without cramming) |
| R5 | **Character palette discipline** — only glyphs from §character-palette. No wide-display chars, no combining marks. | 10 | Uses banned glyphs | Uses only palette | Uses only palette and avoids characters that render inconsistently across iTerm2/Terminal.app/GNOME Terminal |
| R6 | **Visual weight vs card frame** — sigil doesn't duplicate or clash with the outer `╔═╗` frame. | 10 | Has its own frame | Frameless silhouette | Frameless and uses a lighter weight than the card (single-line or pure block, never double-line) |
| R7 | **Theme-plain compatibility** — N/A for sigils (plain mode skips them). For the banner: degrades meaningfully or is silently skipped (current behavior acceptable). | 5 | Breaks plain mode rendering of neighboring output | Plain mode skips cleanly | Plain mode has a single-line textual fallback acknowledged in `ui_banner` |

**Scoring is per-asset** (banner scored once, each of 6 sigils scored once). The set ships when **all 7 assets clear the 80/100 threshold**; any below-threshold asset blocks the batch.

---

## T — Tests (validation gates)

Two gate tiers: **mechanical** (automatable, runs in CI) and **editorial** (human judgment).

### T1 — Mechanical gates (CI-enforceable)

Implementer adds `cli/tests/art-lint.sh` with the following checks. Each check is a separate function; the script exits non-zero on any failure.

| Gate | Rule | Command sketch |
|------|------|----------------|
| G1 | **Width uniformity per file**: every row in a sigil file has the same display width. | `awk '{ if (NR==1) w=length; else if (length!=w) exit 1 }' art/eidolons/*.txt` — note: `length` counts **bytes**, not display columns. For Unicode, use `awk '{ print }' | perl -CSD -nE 'say length'` or a python helper. See Implementation note below. |
| G2 | **No trailing whitespace**: no line ends with spaces or tabs. | `grep -nE ' +$' art/**/*.txt && exit 1` |
| G3 | **No tab characters**: tabs forbidden everywhere. | `grep -nP '\t' art/**/*.txt && exit 1` |
| G4 | **Max row count**: sigil files ≤ 6 rows, banner ≤ 9 rows. | `[ "$(wc -l < file)" -le 6 ]` |
| G5 | **Max column width**: sigil ≤ 12 display cols; banner ≤ 60 display cols. | width helper (see note) per row, max across file |
| G6 | **Character-set whitelist**: every codepoint must be in the palette (see §character-palette). | python3/perl codepoint scanner with a whitelisted-set check |
| G7 | **No trailing empty lines**: file ends with exactly one `\n` after the last non-empty row. | `[ "$(tail -c1 file | od -An -c)" = "  \n" ]` and `[ -z "$(tail -n1 file)" ] && exit 1` (no empty last line before EOF) |
| G8 | **File is UTF-8 valid**: decoding round-trips. | `iconv -f UTF-8 -t UTF-8 file >/dev/null` |
| G9 | **Loader contract**: `ui_load_sigil <name>` emits exactly `UI_SIGIL_HEIGHT` rows, each exactly `UI_SIGIL_WIDTH` display columns. | integration test in `cli/tests/art-lint.bats` sourcing `art_loader.sh` |

**Implementation note on display width.** `${#var}` in bash 3.2 counts **bytes**, not columns. All the art chars we whitelist are either ASCII (1 byte, 1 column) or Unicode BMP chars that encode to 3 bytes in UTF-8 but render as 1 column. A byte-count width check will therefore fail on any file with Unicode. The lint script MUST use a width helper that counts Unicode scalar values, not bytes. Recommended: a small python3 helper (python3 is already a fallback dependency of `yaml_to_json` per `CLAUDE.md`, so it's implicitly available in the dev environment; Linux CI images ship it).

```bash
# reference width helper — display columns per line, assuming palette chars are all narrow
art_line_width() {
  python3 -c 'import sys, unicodedata
for line in sys.stdin:
    line = line.rstrip("\n")
    w = sum(2 if unicodedata.east_asian_width(c) in ("W","F") else 1 for c in line)
    print(w)'
}
```

### T2 — Editorial gates (reviewer judgment, PR checklist)

| Gate | Question |
|------|----------|
| G10 | Can a reviewer name the creature/motif within 2 seconds of seeing the sigil, without being told which Eidolon it is? (Test with 3 reviewers; ≥ 2 must identify correctly.) |
| G11 | Does the banner feel like an emblem rather than a word? |
| G12 | Do all 6 sigils feel like members of the same visual family (consistent line weight, consistent silhouette density)? |
| G13 | Viewed inside `bash cli/tests/ui-preview.sh roster` on a 80-col terminal, does every card render cleanly with no visible drift? |

---

## R — Stories (GIVEN/WHEN/THEN)

### Story 1 — Top-of-CLI banner renders

```
GIVEN an interactive TTY with UTF-8 and 24-bit color
  AND EIDOLONS_FANCY=1 (default when stderr is a TTY)
  AND EIDOLONS_NEXUS points at the nexus checkout
WHEN the user runs `eidolons --help`
THEN stderr shows the emblem banner followed by `  v<version>  · personal team of AI agents`
  AND every banner row is ≤ 60 display columns
  AND the emblem fits within 9 rows
  AND the entire banner is colored with UI_ACCENT (amber)
  AND there is a single blank line above and below the banner block
```

### Story 2 — Roster listing renders card stack

```
GIVEN EIDOLONS_FANCY=1
WHEN the user runs `eidolons roster`
THEN each of the 6 shipped Eidolons renders a 66-col card (or the post-redesign adjusted width)
  AND the left cell of each card contains a 12×6 sigil with no inner frame
  AND the sigil does not duplicate, overlap, or touch the card's outer double-line frame
  AND no row has trailing whitespace (no spurious color escape sequences after content)
  AND the capability_class (scout/planner/coder/scriber/reasoner/debugger) appears only in the card title, not inside the sigil
```

### Story 3 — Single card renders

```
GIVEN EIDOLONS_FANCY=1
WHEN the user runs `eidolons roster atlas`
THEN one card renders with ATLAS's cartographer-eikon sigil in the left cell
  AND a reviewer unfamiliar with the roster can tell which Eidolon this is from the sigil alone (editorial gate G10)
```

### Story 4 — Plain mode skips art cleanly

```
GIVEN EIDOLONS_PLAIN=1  OR  NO_COLOR is set  OR  stderr is not a TTY
WHEN the user runs `eidolons --help`
THEN no banner is printed to stderr (early return in ui_banner)
  AND no ANSI escape, no partial banner, no "???" boxes
  AND `eidolons roster atlas` prints the legacy plain-mode key/value dump (no sigil)
  AND every existing bats test assertion on "Methodology:", "Cycle:", "Handoffs:" still passes
```

### Story 5 — Narrow terminal (80 cols)

```
GIVEN EIDOLONS_FANCY=1 and COLUMNS=80
WHEN `eidolons roster` runs
THEN the card (≤ 66 cols) fits with at least 14 cols of right margin
  AND the banner (≤ 60 cols) fits with margin
  AND `ui_divider` renders at min(COLUMNS, 78) without overflow
```

### Story 6 — Art lint gate blocks malformed contributions

```
GIVEN a PR adds or edits a file under art/
WHEN CI runs `bash cli/tests/art-lint.sh`
THEN the script exits 0 only if every file passes G1..G9
  AND a non-zero exit prints the offending file, line, and rule id
  AND bats test cli/tests/art-lint.bats invokes the same script for parity with the rest of the test suite
```

### Story 7 — Dimension change is atomic

```
GIVEN the implementer changes UI_SIGIL_WIDTH from 14 to 12 in art_loader.sh
WHEN they commit
THEN the same commit updates all 6 sigil files to the new width
  AND the same commit updates card.sh if UI_CARD_WIDTH changes
  AND `bats cli/tests/` passes
  AND `bash cli/tests/ui-preview.sh` produces visually aligned cards
```

---

## A — Artifacts (design briefs + reference tables)

### <a id="banner-brief"></a>Banner brief — `art/banner.txt`

**Goal**: evocative emblem, not lettering. One cohesive composition readable as a single image. The wordmark `eidolons` is still printed by `ui_banner` on the line below the art, so the art does NOT need to spell the name.

**Envelope**: **60 cols × 9 rows max**. Recommended target: **48 cols × 7 rows** (leaves whitespace breathing room; scales down well on narrow terminals).

**Symmetry**: vertical axis mirror REQUIRED. Horizontal asymmetry permitted (bottom can be heavier than top; a base/altar works).

**Motif options (ranked)**:

| Rank | Motif | Description | Why it fits |
|------|-------|-------------|-------------|
| 1 | **Summoning sigil inside a diamond/rhombus** | Central geometric seal with radial lines extending outward; concentric rings or inner glyph | Literally the "summon the eidolon" metaphor of the nexus; scales well to 48×7; pure box-drawing palette |
| 2 | **Crystal / prism** | Faceted gem shape, internal divisions, light rays | Ties to FF summon materia aesthetic; strong silhouette |
| 3 | **Oculus / eye within a laurel** | Central eye surrounded by stylized wings or branches | Riffs on "agent observing the codebase"; heavier, risks looking busy at 48×7 |
| 4 | **Archway / gate** | Portal with a glyph at the apex, pillars flanking | Evokes "gateway to the eidolons"; hardest to balance without looking architectural rather than mystical |

**Recommendation**: option 1 (summoning sigil). It's the most iconic, the most symmetrically tractable, and the closest visual cousin to the FF-summon aesthetic.

**Character weight**: use **block + single-line** (`█▓▒░─│╱╲╭╮╰╯◆◇`), avoid double-line (`═║╔`) — the card frame already owns double-line weight, and the banner shouldn't compete.

---

### <a id="per-eidolon-briefs"></a>Per-Eidolon design briefs

Each brief defines a **motif**, a **reading intent** (what the reviewer should see in under 2 seconds), and **FF-summon aesthetic references** (for vibe, not copying). Envelope for all: **12 cols × 6 rows**, no inner frame.

#### ATLAS — cartographer / scout

- **Motif**: winged silhouette over a spread map, OR a compass-rose creature with outstretched arms. Primary read: **a watcher charting territory**.
- **Silhouette density**: light. Lots of negative space. ATLAS is read-only, non-invasive — the art should feel airy.
- **Key features**: cardinal marker at center (a fine `+` or compass star), horizontal expanse, a hint of wings or sweep.
- **FF references**: *Valefor* (light wings, graceful), *Carbuncle* (small, intelligent, non-threatening), *Pandemona* (wind/breadth).
- **Forbidden**: aggressive silhouettes, weapons, anything that reads as "builder" or "destroyer".

#### SPECTRA — planner / spec-scribe / seer

- **Motif**: a seated oracle figure with a radiant third eye, OR a many-faceted prism projecting a grid/lattice. Primary read: **a seer translating vision into structure**.
- **Silhouette density**: medium. Should feel more structured than ATLAS; ATLAS expands outward, SPECTRA projects inward-to-outward.
- **Key features**: a vertical axis of symmetry with a focal point (eye, crystal, seal), ordered radiating lines suggesting decomposition/spec branching.
- **FF references**: *Alexander* (judgment/structure, but scaled way down — keep it mystical not architectural), *Bahamut's* calm pre-flight pose (authoritative poise), *Diabolos's* crescent framing (seer silhouette).
- **Forbidden**: chaotic lines, weapon iconography, anything that competes with ATLAS's symmetry.

#### APIVR-Δ — coder / brownfield implementer / forge-of-change

- **Motif**: a horned anvil-creature or a hammer-bearing silhouette, possibly with a delta/triangle glyph forming the head. Primary read: **an artisan striking metal**. The Δ is thematic but shouldn't be the whole piece — it can form a subtle body feature.
- **Silhouette density**: heavy. APIVR writes code; the sigil should feel the most substantial of the six.
- **Key features**: broad base (anvil or stance), vertical strike line, Δ integrated (e.g. as head or chestplate).
- **FF references**: *Ifrit* (horned, powerful, grounded stance), *Titan* (mass, base-heavy), *Hammerhead's* workshop vibe from FFXV.
- **Forbidden**: overusing Δ as a literal floating triangle with no creature around it (that was the previous design's failure — the triangle had no body).

#### FORGE — reasoner / lateral consultant / creative spark

- **Motif**: a flame-wreathed head or a multi-spark constellation pattern coalescing into a face. Primary read: **scattered sparks becoming a thought**.
- **Silhouette density**: light-to-medium, but MORE points of light than ATLAS. The eye should dart across multiple loci before resolving into a whole.
- **Key features**: multiple small sparks (`✦ ✧ · ◆`) arranged to imply a face or lit brain shape; a strong central anchor.
- **FF references**: *Phoenix* (flame silhouette), *Ifrit's* mane (without the body), *Tonberry's* lantern dot-of-light idea inverted (many lights → one insight).
- **Forbidden**: re-using APIVR's anvil/forge imagery. FORGE is a mental forge, not a metal one. Keep them visually distinct despite the name.

#### IDG — scriber / documentation synthesizer

- **Motif**: a scribe silhouette with a quill/stylus, OR a scroll/tome with visible pages and a binding seal. Primary read: **a writer preserving what the team did**.
- **Silhouette density**: medium, with visible horizontal line-texture (to suggest text without spelling it).
- **Key features**: rectangular body (scroll/book), internal horizontal strokes (`─ ─ ─` or `▬▬`), a small seal or mark.
- **FF references**: *Ramuh's* staff and tome stance, *Scholar* job art (FFXIV) for the tome silhouette, *Tonberry's* slow deliberate posture.
- **Forbidden**: anything too "office supply" — avoid making it look like a clipboard.

#### VIGIL — debugger / forensic guardian

- **Motif**: a watchful hooded figure with a magnifying lens, OR a sentinel eye with a faint aura. Primary read: **something watching very carefully**.
- **Silhouette density**: medium, with a strong focal eye or lens. Should feel alert but not aggressive.
- **Key features**: single dominant eye/lens (`◉ ⊙ ◎`), asymmetric hood or mantle suggesting stealth, faint particulate aura (`·`) suggesting forensic dust/evidence.
- **FF references**: *Anima* (hooded, contained power), *Yojimbo* (silent watcher stance), *Odin's* pre-strike patience (observation before action).
- **Forbidden**: current VIGIL art looks like a cartoon face with a trailing line — avoid anything that reads as "sad mascot". VIGIL is the forensic debugger; it should feel *sharp*.

---

### <a id="size-budget"></a>Size budget table

| Asset | Max cols | Max rows | Target cols | Target rows | Notes |
|-------|----------|----------|-------------|-------------|-------|
| Main banner (`art/banner.txt`) | 60 | 9 | 48 | 7 | Vertical symmetry required. Wordmark is rendered separately by `ui_banner`. |
| Eidolon sigil (`art/eidolons/*.txt`) | 12 | 6 | 12 | 6 | **Down from 14×8.** Drops the inner frame. Fills the full envelope (use edge-to-edge). |
| (Future) roster thumbnail | 6 | 3 | 6 | 3 | Reserved for a hypothetical compact list view. Not in scope for this spec. |

**Loader constant changes required** (to be applied in the same commit as new art):

```
# cli/src/ui/art_loader.sh
UI_SIGIL_WIDTH=12    # was 14
UI_SIGIL_HEIGHT=6    # was 8

# cli/src/ui/card.sh
UI_CARD_WIDTH=64     # was 66 — tighten by sigil delta; OR keep at 66 and widen stats column
```

Implementer decides whether to keep `UI_CARD_WIDTH=66` (stats column grows by 2) or drop to 64 (whole card tightens by 2). Recommended: **keep 66, let stats column breathe**.

---

### <a id="character-palette"></a>Character palette

The palette is a **single tier**, because plain mode skips the art entirely (`ui_banner` returns early; `_ui_card_plain` never reads the sigil). We can author freely in Unicode BMP as long as every character renders 1 display column on modern terminals (iTerm2, Terminal.app, Alacritty, Kitty, GNOME Terminal, Konsole, Windows Terminal, VSCode integrated terminal).

**Allowed**:

| Range | Chars | Use for |
|-------|-------|---------|
| ASCII printable | `! " # $ % & ' ( ) * + , - . / 0-9 : ; < = > ? @ A-Z [ \ ] ^ _ ` a-z { \| } ~` | body, accents |
| U+2500..U+257F box-drawing | `─ │ ┌ ┐ └ ┘ ├ ┤ ┬ ┴ ┼ ═ ║ ╔ ╗ ╚ ╝ ╠ ╣ ╦ ╩ ╬ ╭ ╮ ╰ ╯ ╱ ╲ ╳` | lines, frames (but **avoid double-line in sigils** — clashes with card) |
| U+2580..U+259F block elements | `▀ ▄ █ ▌ ▐ ░ ▒ ▓` | mass, silhouette fills |
| U+25A0..U+25FF geometric shapes | `■ □ ▪ ▫ ▬ ▲ △ ▼ ▽ ◆ ◇ ◉ ○ ● ◍ ◎ ⊙ ★ ☆` | focal features, eyes, sigil centers |
| U+2600..U+26FF misc symbols (safe subset) | `☼ ✦ ✧ ✴ ✵` | sparks, celestial marks |
| U+2190..U+21FF arrows (sparing) | `← → ↑ ↓ ↖ ↗ ↘ ↙` | directional hints only |

**Forbidden**:

- Any character with East-Asian Width = W or F (CJK, emoji, some dingbats). These render 2 columns in most terminals and break the fixed-width contract in `art_loader.sh`'s byte-based padding.
- Emoji (any U+1F000+).
- Combining marks (U+0300..U+036F) — they render as zero-width and corrupt byte-based padding.
- Variation selectors (U+FE00..U+FE0F, especially U+FE0F which turns adjacent chars into emoji presentation).
- Tabs (`\t`).
- Non-breaking spaces (U+00A0) — indistinguishable from regular spaces visually but count differently in some tools.

**Double-line box chars (`═ ║ ╔ ╗ ╚ ╝` etc.)**: **banned inside sigils**, because the outer card frame uses double-line and the two weights clash. Allowed in the banner (the banner has no surrounding frame).

---

## Open questions / decisions the user must make

| # | Question | Options | Recommendation |
|---|----------|---------|----------------|
| OQ-1 | Should the banner have a plain-text fallback (ASCII-only single line like `~ EIDOLONS ~`) for when `EIDOLONS_PLAIN=1` is set but the user still wants *some* brand mark? | (a) No — current behavior is correct: plain mode skips banner entirely. (b) Yes — emit a single-line ASCII fallback. | **(a) No.** `ui_banner` early-returns in plain mode for a reason — keeps output machine-parseable for pipes, CI, and `--help` testing. Don't change it. |
| OQ-2 | Keep `UI_CARD_WIDTH=66` or shrink to 64 when sigil shrinks? | (a) Keep 66, stats column grows. (b) Shrink to 64. | **(a) Keep 66.** Stats column was always cramped (the longest row is `Tokens       2000 / 4500` at ~26 chars and has no padding margin). Extra space improves readability. |
| OQ-3 | Remove the role-word row (`sentinel`, `planner`, etc.) from sigil files? | (a) Yes — card already renders `capability_class`. (b) No — keep as redundancy. | **(a) Yes, remove.** Redundant with `capability_class` in card title; it's a frequent source of alignment drift (row 8 is always shorter than rows 1–7). |
| OQ-4 | Do we ship an ASCII-only (no Unicode box chars) sigil tier for terminals that can't render UTF-8? | (a) No — plain mode skips sigils entirely. (b) Yes — build a parallel `art/eidolons-ascii/` tier. | **(a) No.** Fancy mode already requires a capable TTY; plain mode skips. Parallel tier doubles maintenance. |
| OQ-5 | Should the banner be the same emblem across the whole CLI, or rotate per Eidolon when dispatching (e.g. `eidolons atlas <cmd>` shows ATLAS's emblem)? | (a) Single fixed emblem. (b) Per-Eidolon emblems (reuse `art/eidolons/<name>.txt` scaled up). (c) Hybrid — banner is fixed, but dispatch subcommands print the member's sigil. | **(c) Hybrid, but out of scope for this spec.** File it as a follow-up. This spec delivers one banner + 6 sigils; dispatch integration is a separate story. |
| OQ-6 | Who authors the actual ASCII? | (a) User iteratively. (b) APIVR-Δ with FORGE consult on motif. (c) SPECTRA proposes drafts (not this spec — a subsequent cycle). | **(b) APIVR-Δ with FORGE consult.** FORGE is the reasoner for lateral/aesthetic calls; APIVR-Δ commits the asset. Each sigil is a small enough change to be a single APIVR-Δ Δ-slice. |
| OQ-7 | Does the art-lint script run on every PR via GitHub Actions, or only on PRs touching `art/`? | (a) Every PR. (b) Path-filtered on `art/**` and `cli/src/ui/art_loader.sh`. | **(b) Path-filtered.** Cheaper; the assets are static most of the time. Add a nightly run via `roster-health.yml` for insurance. |

---

## Handoff notes

- **To APIVR-Δ**: this spec's §per-eidolon-briefs, §size-budget, §character-palette, and T1 gates are the acceptance surface. Each sigil is one Δ-slice; the banner is one Δ-slice; the lint script + bats test is one Δ-slice; the loader/card constant update is one Δ-slice. Suggested ordering: lint script first (so you can validate each asset as you author), then loader/card constants, then sigils one-by-one, then banner last.
- **To FORGE**: consult requested only on motif collisions — if while authoring SPECTRA's sigil you find it visually indistinguishable from ATLAS's, call FORGE to reason about differentiation. Otherwise proceed.
- **To VIGIL**: no role in this cycle unless an asset lands and a user reports a rendering regression (e.g. a sigil breaks on Windows Terminal). VIGIL then does forensic attribution on which char/terminal combination failed.
- **To IDG**: after ship, IDG documents the authoring contract (palette, envelope, lint) under `docs/` or a new `docs/ui/art-authoring.md`.

---

## Acceptance summary

Ship when:

1. All 7 assets score ≥ 80/100 on the rubric (§criteria).
2. All 9 mechanical gates pass (§tests T1).
3. All 4 editorial gates pass on a 3-reviewer panel (§tests T2).
4. All 7 GIVEN/WHEN/THEN stories (§stories) pass manual verification via `bash cli/tests/ui-preview.sh`.
5. Existing `bats cli/tests/` suite is green (no regression in plain-mode text assertions).
6. Open questions OQ-1..OQ-4 are resolved (OQ-5..OQ-7 can defer).
