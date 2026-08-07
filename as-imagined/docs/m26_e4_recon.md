# M26E4 recon — Summary/Stats screen: reference review, current state, route comparison, and scope

Written 2026-07-29. Recon only — no code written, no assets pulled this session.

M26E4 (was M26h): "a genuinely new screen with zero existing foundation — to be scoped
when reached, starting with its own Step 0 source investigation." This is that Step 0.
Same three-route evaluation as `docs/m26_e3_recon.md`: (A) direct source pulls, (B) the
Emerald UI Pack, (C) Godot-native.

Reference: pokeemerald-expansion v1.16.2, HEAD `74e40e03…`. Pack: `assets/Emerald UI
Pack 1.2/`.

---

## 0. TL;DR

1. **Zero-foundation confirmed** — no summary/stats/detail screen exists anywhere. The
   closest thing is the team builder's `RichTextLabel` result readout. The overlay
   architecture (item/switch screens), fonts, front sprites, and most display data are
   ready, though; E4 is also the third overlay consumer that triggers the planned
   extraction of the shared overlay helpers.
2. **The one real data gap is move descriptions: empty on all 717 moves** —
   `data/moves.json` has no description key and `gen_moves.py` never emits one. The
   move-detail panel needs them, so E4 starts with a small data-pipeline task. (Ability
   descriptions ARE populated; item descriptions are empty but E4 doesn't need them.)
3. Reference facts that shape the design (§1): the in-battle mode
   (`SUMMARY_MODE_LOCK_MOVES`) allows **all pages and Up/Down mon cycling** — it only
   locks move reordering; the screen **always shows stored stats, never battle-stage
   values** (`gBattleMons` is never read); nature-colored stats are ON by default in
   expansion; ~29% of the 4,886-line file is contest/egg/RPG freight a sim never needs.
4. **Route B (pack) wins again** (§4): 8 full-page backgrounds at exactly 2× canvas and
   a complete 1,443-line coordinate recipe (`001_Summary.rb`). Two pack gaps are covered
   by assets already in-project: **the pack ships no type icons at all** (recipe expects
   a sheet it doesn't include — project's reference-pulled 32×16 badges, zero consumers
   since M23.11, finally get their consumer) and its category sheet was already
   rejected by `gen_category_sprites.py` (reference-pulled 16×16 icons exist, also
   unconsumed).
5. Proposed shape: pack pages 1-4 (INFO / SKILLS / MOVES+detail / EVS-IVS), contest
   content dropped for good but the RPG freight (OT, met-location, caught ball, shiny,
   eggs, markings, nickname, characteristic) **deferred with reserved layout slots,
   each mapped to the M27+ milestone that produces its data** (§5) — the screen is
   built **battle-agnostic** because the roadmap's M27I already commits to "Summary
   built once and shared with M26E4." ~3-4 sessions (§6).

---

## 1. Reference review (`src/pokemon_summary_screen.c`, 4,886 lines)

### 1.1 Structure

Four pages — INFO, SKILLS, BATTLE_MOVES, CONTEST_MOVES (no ribbons page; ribbon count
is a one-line string on SKILLS). Four BG layers: text windows on BG0; two 512-wide
scrolling page layers that ping-pong (incoming page pre-loaded off-screen, scrolled in
at 32px/frame over 8 frames); INFO/portrait frame on BG3. Left third of the screen is a
persistent portrait column: dex no (shiny recolors the text; the portrait backdrop
palette-swaps — there is **no shiny star sprite**), nickname, species/level/gender,
status icon, markings, caught ball. Max 30 sprites, 19 task functions, 32 window
templates, a 25-state load machine.

### 1.2 Page contents (battle-relevant subset)

- **INFO**: OT/ID (RPG-only), ability name + description, trainer memo (nature flavor +
  met location — RPG-only except the nature name), TYPE/ + type icon sprites.
- **SKILLS**: held item; stat table (HP `cur/max`, Atk, Def left column; SpA, SpD, Spe
  right); **nature coloring of stats is ON by default** (`P_SUMMARY_SCREEN_NATURE_COLORS
  = TRUE`, up-stat red / down-stat blue, HP never colored, keyed off the *mint* nature —
  the sim has no mints, so plain nature applies); EXP points, NEXT LV. (=
  `table[level+1] − exp`), and a **64-tick tile-based EXP bar** (8 tiles, 9 tile
  variants). **There is no HP bar** — HP is text only. A config-gated IV/EV viewer
  (default OFF) cycles stats→IVs→EVs with letter grades.
- **BATTLE_MOVES**: 4 move rows (type icon + auto-fit name + PP `xx/yy` with **4-tier
  PP coloring** via the shared `text_pp` palette); on selection a sliding POWER/ACCURACY
  panel (3-digit right-aligned, `---` for status/never-miss), the **category icon**
  (`B_SHOW_CATEGORY_ICON` default TRUE), and the move description; blinking 10-sprite
  selection bar; a 5th CANCEL/new-move row exists only in the move-learn mode.
- **CONTEST_MOVES**: appeal/jam hearts — excluded wholesale (no contests).

### 1.3 Modes and the in-battle contract

In-battle entry is `CursorCb_Summary` → `ShowPokemonSummaryScreen(SUMMARY_MODE_LOCK_MOVES,
party, slot, max, CB2_ReturnToPartyMenuFromSummaryScreen)`. LOCK_MOVES **only** disables
move reordering (and relearn/rename prompts): all four pages stay reachable, and
Up/Down cycles party mons (eggs skipped off-INFO; range = own side). On close,
`gLastViewedMonIndex` is handed back so the party cursor follows the viewed mon, and
the party menu reopens **directly into the action submenu** — the E3 dependency edge.

**Data source: the party `struct Pokemon`, by value.** `gBattleMons` is never read: no
stat stages, no Transform/Mega values, no in-battle ability swaps. Current HP, status,
and PP are accurate because party mons stay synced. A Godot port reading
`mon.attack` etc. (nature/EV/IV-applied, stage-free) matches source behavior exactly.

### 1.4 What a sim never needs (~29% of the file)

Contest page + hearts + contest type anims (~200 lines), trainer memo/OT/met-location
(~155), move-replace/relearn select mode (~230), IV/EV viewer variant (~185), eggs
(~75), relearner prompt (~75), rename (~30), ribbons (~19), Pokérus (~14), markings
(~20), Factory/Tent/multi special cases (~60). Battle-relevant core ≈ 1,900-2,100
lines of C plus tables.

---

## 2. Current state (Godot side)

### 2.1 Foundation: none — but the scaffolding is ready

No summary/stats/detail screen or scene exists (verified). Ready to reuse: the
full-viewport **overlay pattern** (`item_select_screen.gd` / `switch_select_screen.gd`
— overlay-not-scene-swap because `BattleManager` lives inside the battle scene; E4 is
the flagged "third consumer" that justifies extracting the shared helpers), fonts
(`power green.ttf` message font + bitmap menu font with the ×4 integer-scale
invariant), `SpriteRegistry.get_front()` (64×128 two-frame sheets; note the M25a
finding that source's sprite X-flip applies **only** on the summary screen —
`sDontFlip` — so the front pic renders unflipped, exactly what `get_front()` gives),
the 386 party icons (E3-2 builds `get_icon()`; coordinate, don't duplicate), and
`TypeChart.type_name()`.

### 2.2 Display-data audit

Available now: unmodified battle stats (`mon.attack` etc. — nature/EV/IV applied,
stage-free: precisely source's display contract), level, gender + `gender_ratio`,
nature id (+ `_nature_stat_pair()` static for up/down coloring), ability
(`AbilityData.description` populated on 319 files), held item name, status, moves with
name/type/category/power/accuracy/PP + `current_pp`, IVs/EVs, types, dex number,
EXP fraction (`_exp_bar_fraction()` worked precedent; "to next" is a one-line
derivation off `PokemonRegistry.get_exp_for_level`).

Gaps:
| Gap | Severity | Resolution |
|---|---|---|
| **`MoveData.description` empty on all 717 moves** | Blocking for move detail | Extend `gen_moves.py` to emit reference descriptions; regenerate `.tres` |
| Nature names duplicated in 2 local arrays (team_builder, roster) | Minor | Consolidate into one shared table; E4 is the third consumer |
| No `exp_to_next` helper | Trivial | One-liner beside `_exp_bar_fraction` |
| No AbilityRegistry (ad-hoc `load()`s) | Cosmetic | Keep ad-hoc or add a thin registry |
| Nickname field exists but is never populated; no shiny/OT/met/caught-ball/ribbons/markings/Pokérus/characteristic | N/A | All excluded (§5); characteristic additionally needs a personality-ID concept the sim lacks |

---

## 3. The Emerald UI Pack Summary kit

45 PNGs + `001_Summary.rb` (1,443 lines — the complete assembly recipe with every
coordinate, like `004_Party.rb` was for E3).

- **8 page backgrounds, 512×384** (= exact 2× canvas): `bg_1` INFO, `bg_2` SKILLS,
  `bg_3` MOVES, **`bg_4` EVS/IVS (a pack extension page — dedicated, not a toggle)**,
  `bg_5` RIBBONS, plus `bg_egg`, `bg_movedetail` (swapped in while a move is
  selected), `bg_learnmove`.
- **Recipe coordinates** (512×384 space, ×2 for the project canvas): mon sprite at
  (114,156) center-origin with shiny glow overlay behind; shared chrome (page name,
  nickname/species, dex no, level, gender, held item, ball icon, status badge from
  the 44×112 `statuses.png`); SKILLS stat table two right-aligned columns at
  x=378/502, rows y=116/148/180, **nature up/down recoloring spelled out**; MOVES list
  at y=72 stride 38 with 4-tier PP colors; move detail = power/accuracy at (166,
  284/316), category icon at (138,348), description 5 lines at (222,240,w284); EXP
  bar = `overlay_exp` 132×6 at (252,364), width snapped to even pixels; 2-state
  move cursor sheet; pages clamp (no wrap), Up/Down cycles mons, L/R changes page.
- **Pack gaps, all covered in-project**: **no type-icon sheet at all** (recipe loads
  `Graphics/UI/types` — 64×28/row — which the pack simply doesn't ship; project's
  reference-pulled 32×16 badges render at 2× = 64×32, a disclosed 4px-tall deviation
  in a 28px slot, or letterboxed); **category sheet over-specified** (56px-wide sheet,
  66px-wide blit rect in the pack's own script — `gen_category_sprites.py` already
  rejected it and pulled the reference's clean 16×16 frames); no ribbons sheet or
  up/down arrow sprites (ribbons page dropped; arrows trivially replaced).

---

## 4. Route comparison

| Dimension | A: Direct source decode | B: Emerald UI Pack | C: Godot-native |
|---|---|---|---|
| Page art | 240-tile sheet + 4× 2048B page tilemaps; the page art lives in the **right screen-block** of 512-wide maps (a decode subtlety), plus pagination-dot tiles, sliding-window tilemaps, EXP-bar tile variants | 8 flat full-page PNGs | Invented panels |
| Layout data | Window templates in tiles + sprite px tables — usable but needs the same 3:2→4:3 re-anchoring E3's comparison flagged (240×160 does not divide the 1024×768 canvas) | **Complete px recipe at exactly 2× canvas** | Free |
| Dynamic mechanisms | Tile-written EXP bar, palette-swap shiny frame, sliding tilemap sub-windows, BG ping-pong scroll — each needs a Godot re-expression anyway | Recipe's mechanisms are already sprite/blit-shaped (Godot-friendly); EXP bar is a cropped TextureRect | Native |
| Type/category/status icons | All from reference — **already pulled in-project** (types 32×16, category 16×16, statuses) | Pack lacks types; category over-specified → use the reference pulls either way | same |
| Extra value | — | A dedicated EVS/IVS page (bg_4) source doesn't surface by default | — |
| Precedent/style | Superseded direction (M25h-4) | **M26B1/B2/B5 + E3's own recommendation — one coherent style across every M26 screen** | Contradicts M26's mandate |
| Est. asset/layout effort | ~2+ sessions | **~1 session** | ~0.5 session + permanent style debt |

**Recommendation: Route B** — pack backgrounds + recipe coordinates, reference-pulled
type/category/status icons (finally consuming the M23.11/C4/C5 asset pulls), source
semantics (stored stats, LOCK_MOVES contract, PP tiers, nature coloring, egg-free
cycling). Route A remains the documented fallback per piece; Route C rejected on the
same grounds as E3.

---

## 5. Scope

### In scope

1. **`SummaryScreen` overlay** (pack-styled, 4 pages: INFO / SKILLS / MOVES(+detail) /
   EVS-IVS), built **battle-agnostic**: constructed over a `BattleParty` + start index
   + a mode flag, no `BattleManager` coupling in the view — M27I's "built once and
   shared" contract. Entry today: E3's submenu SUMMARY action; return path re-opens
   that submenu with the cursor on the last-viewed mon (source contract).
2. **Pages**: shared chrome (front sprite unflipped, species/level/gender/dex, status
   badge, held-item name); INFO = types + ability + description + nature line
   (**disclosed sparse** — OT/ID/memo areas intentionally empty, no invented filler);
   SKILLS = stat table with nature up/down coloring (HP never colored) + EXP
   points / to-next / 132px bar; MOVES = 4 rows with type icons + PP tiers, selection
   → `bg_movedetail` + power/accuracy/category/description; EVS-IVS = the builder's
   values in pack layout.
3. **Behavior**: L/R page clamp, Up/Down mon cycling within the viewing side's party,
   ESC/B close, LOCK_MOVES semantics (no reordering — the sim has none anyway),
   stored-stats display (source-accurate; stage-modified values stay in the F3 debug
   overlay and E5's future matchup screen).
4. **Data enablers**: move-description extraction into `data/moves.json` + the 717
   `.tres`; shared nature-name table (replacing both local duplicates);
   `exp_to_next()` helper; `SpriteRegistry.get_icon()` if E3 hasn't landed it first.
5. Asset pull script (`gen_summary_screen_sprites.py`): bg_1..4 + bg_movedetail,
   cursor_move, overlay_exp, statuses source decision (pack 44×16 rows vs existing
   sheets — pick one for both E3 and E4), + smoke test.

### Not built now — split by kind (revised per Rob, 2026-07-29: the RPG freight is
### NOT disregarded — most of it returns with M27+ and the layout must reserve for it)

**Permanently out** (no future milestone produces this data):
contest page + appeal/jam hearts, contest type-icon frames, IV letter grades (values
shown instead), audio (M26 standing rule), item descriptions (not needed here).

**Deferred with reserved slots** — the pack layout's regions for these are left
EMPTY-BUT-RESERVED (never repurposed), each mapped to the milestone that will produce
its data, so re-activation is filling a slot, not redesigning a page:

| Deferred element | Pack region reserved | Returns with |
|---|---|---|
| OT name / ID | INFO (238,68) row | M27 (player identity — M27L save owns the trainer record) |
| Met location / date / memo | INFO memo block (238,130) | M27C/M27H (world + encounters) |
| Caught-ball icon | chrome (14,342) | M29 (catching records the ball; B7-4 supplies the 26 icon assets' battle twin) |
| Shiny (dex recolor + glow overlay) | chrome + (12,42) glow | M27/M29 (shiny generation; also unblocks the E3 exclusion) |
| Characteristic line | end of memo block | M29+ (needs a personality-ID concept at generation time) |
| Egg variant (`bg_egg`, page lock) | whole-page variant | M31 (breeding) |
| Markings | chrome (104,42) | M27I (PC storage is where marking-editing lives) |
| Ribbons page (`bg_5`) | page 5 slot | post-M27 if ever — lowest priority; keep the page-nav clamp at 4 until then |
| Nickname display | chrome name slot (falls back to species name today) | M29 (nickname prompt on catch) |
| Rename / relearn / move-replace modes | mode flags | M30 (relearn mechanics) — this screen gains a picker mode then |
| Pokérus | (52,348) dot | M35-era if ever |

Also not here: D-pad input (M26C8; the recipe's 2-column input model is recorded),
stage-modified stat display (E5's matchup overlay / F3 debug own battle-state views).

---

## 6. Phasing

| Phase | Content | Size |
|---|---|---|
| **E4-1** | Data enablers: move-description pipeline (gen script + regeneration + smoke test), shared nature names, exp helper; coordinate `get_icon()` with E3 | 1 session |
| **E4-2** | Asset pull + overlay skeleton: shared chrome, page backgrounds, page navigation, mon cycling, battle-agnostic API + E3 submenu integration | 1 session |
| **E4-3** | SKILLS + MOVES(+detail) dynamic content: stat table with nature coloring, EXP bar, move rows with type icons + PP tiers, detail panel with category icon + description | 1 session |
| **E4-4** | INFO + EVS-IVS pages, polish (cursor blink, page-change SE hook left silent), test suite | 0.5-1 session |

### Decisions needed (Rob)

1. **Route B confirmed?** (pack backgrounds + recipe, reference icons, source
   semantics)
2. **Include the EVS/IVS page** (recommended — sim-relevant, data present, pack ships
   the art) or hold to source's 3 battle pages?
3. **Move-description pipeline** — confirm extending `gen_moves.py` and regenerating
   all 717 move `.tres` files (touches a lot of files in one commit; data-only).
4. **Stored stats** (source-accurate, recommended) vs battle-modified values on
   SKILLS?
5. **INFO page sparseness** — keep source-shaped with the OT/memo regions
   empty-but-reserved per §5's deferral table (recommended — those slots are
   scheduled to fill as M27+ lands, so repurposing them now would mean undoing it
   later), or deviate from the pack layout to fill it today?
6. Status-badge source for E3+E4 jointly: pack `statuses.png` vs the existing
   reference sheets.

---

## 0e. All 6 decisions resolved (Rob, 2026-08-05)

Route B confirmed; EVS/IVS page included; move-description pipeline approved;
stored (not battle-modified) stats confirmed; INFO page stays source-shaped
with reserved-but-empty slots; status icons stay on the existing reference
sheets (no change for either E3 or E4). Every recommendation in §6.1-6.6
above was accepted as written — see `## 0f. E4-1 — SHIPPED` immediately below
for what actually landed.

---

## 0f. E4-1 — SHIPPED 2026-08-05

**Move descriptions** — the one blocking data gap. New `scripts/gen_move_
descriptions.py` bulk-extracts real move descriptions from `moves_info.h`'s
own `.description = COMPOUND_STRING(...)` field and patches them into
`gen_moves.py`'s own `MOVES` dict (idempotent; `python3 scripts/gen_moves
.py` regenerates the 717 `.tres` files afterward). New `MoveData.description`
schema slot (`gen_moves.py`'s `DEFAULTS`/`FIELD_ORDER` gained their first-
ever string-typed field, needing a small `render()` fix to quote/escape it —
every other field is bool/int/enum).

**Three real extraction bugs found and fixed before trusting the output**,
each confirmed via a direct before/after count check rather than assumed
correct on the first pass:

1. A first-draft regex assumed every description is one contiguous run of
   adjacent quoted C string literals. **37 of 717 real move descriptions
   are gated by inline `#if COND / #elif / #else / #endif` blocks**
   selecting between generation-dependent wordings (Disable's own 3-way
   turn-count text is the widest example) — the naive regex silently
   produced zero text for all 37. Fixed with a small preprocessor-
   conditional evaluator (`_eval_condition`), resolving every condition
   against this project's own REAL, already-established config defaults —
   not "whichever reads better": `MACRO >= GEN_N` → true (this project's
   standing "assume GEN_LATEST" convention, re-confirmed per-macro against
   `include/config/battle.h` rather than assumed uniform), `MACRO == TRUE`
   → resolved against the macro's own real default (`B_USE_FROSTBITE` is
   the one confirmed `FALSE`, matching `move_data.gd`'s own already-
   documented "no STATUS_FROSTBITE exists anywhere in this codebase"
   finding), and a project-specific 3-way symbolic macro
   (`B_PREFERRED_ICE_WEATHER`, defaulting to `B_ICE_WEATHER_BOTH`) for the
   Hail/Aurora-Veil/Chilly-Reception/Snowscape family, correctly resolving
   Hail's own description to "hailstorm" wording — matching `[D2 batch]`'s
   own already-decided Hail-only design, not a coincidence.
2. A second bug within that same 37: roughly two-thirds of them (Ice Beam is
   the worked example) duplicate the WHOLE statement's own closing paren
   inside EACH `#if`/`#else` branch rather than gating only the string
   content — a naive paren-counter finds the FIRST `)` (whichever branch
   happens to come first in the raw text) and truncates there, silently
   discarding every other branch — for Ice Beam under this project's own
   `B_USE_FROSTBITE=FALSE` default, discarding the one branch that was
   actually correct ("Blasts the foe with an icy" with no continuation).
   Fixed by abandoning paren-matching entirely in favor of a single
   preprocessor-aware pass over the WHOLE move struct (not just a span
   bounded around `.description`), stopping only at a genuine top-level
   field boundary (`.effect = `, etc.) once the `#if` stack is back to
   empty — correctly handles both the inline-gated shape (Disable) and the
   whole-statement-duplicated shape (Ice Beam, Hail) uniformly, including
   Tri Attack's own doubly-nested case (an outer whole-statement `#if`
   wrapping an inner Frostbite-only `#if`).
3. A third, narrower bug found via a full bulk scan (not anticipated up
   front): source's own fixed-width GBA line wrap sometimes splits mid-WORD
   at a real hyphen (Tackle's own `"a full-\nbody tackle."`) — collapsing
   every `\n` to a bare space left a stray space after the hyphen ("full-
   body" → "full- body"), confirmed across 7 real moves (Tackle, Bullet
   Punch, Karate Chop, Headbutt, Water/Fire Pledge, Freeze-Dry). Fixed by
   treating a hyphen immediately before an escaped newline as a wrap-
   continuation signal (no inserted space) rather than a word boundary.

Also handled: a bare `BINDING_TURNS` macro token embedded between two quoted
fragments on binding moves (Wrap/Bind/Fire Spin/etc.), resolved to its own
real "4 or 5" text (matching `[M18.5f]`'s own already-shipped binding-move
duration) rather than silently dropped; and Razor Wind's compound `||`
condition (`B_UPDATED_MOVE_DATA == GEN_3 || B_UPDATED_MOVE_DATA == GEN_1`),
the one non-single-condition case any of the 37 actually use.

New `scenes/battle/move_description_test.gd`/`.tscn`: 19/19 — full-roster
non-empty-description check (717/717), exact-value spot-checks (Tackle/
Pound/Disable/Hidden Power/Teleport/Razor Wind), and a discriminating
regression guard for each of the three bugs above (asserting the NEGATION —
e.g. Ice Beam's description must contain "freeze" and must NOT contain
"frostbite" — rather than merely asserting a plausible-looking positive
value), plus roster-wide sweeps for leftover `#if`/`COMPOUND_STRING`
artifacts and double-spaces.

**Nature-name table consolidated.** `team_builder_screen.gd` and
`roster_screen.gd` each carried a byte-identical local `_NATURE_NAMES`
array — E4 is the confirmed third consumer the gap was flagged against.
New `BattlePokemon.NATURE_NAMES` (a sibling constant right after the
existing `_nature_stat_pair()`) plus a static `BattlePokemon.nature_name(id)`
helper; both prior call sites now delegate to it, zero behavior change
(`m23_4_team_builder_test.gd` 44/44, `m23_5_team_persistence_test.gd` 52/52,
both unchanged).

**`exp_to_next()` helper added** — a sibling to the pre-existing
`_exp_bar_fraction()` in `battle_screen_shared.gd` (same real data path:
`species.national_dex_num` → `PokemonRegistry.get_species()` →
`growth_rate` → `PokemonRegistry.get_exp_for_level()`), returning the real
integer Exp-to-next-level count the SKILLS page prints verbatim
(`table[level+1] - exp`) rather than deriving it from the bar's own rounded
float fraction. Same disclosed fallback as its sibling: a hand-built fixture
mon with no real registry entry (dex 0) degrades to `0`, not a crash or a
fabricated value. 4 new tests added to `m26c1_databox_test.gd` (was 60,
now 64), mirroring that file's own existing `_exp_bar_fraction` test shapes.

**`SpriteRegistry.get_icon()` confirmed already shipped** by E3-2 — no
action needed, per this recon's own §2.1 note that E3 might land it first.

Two independent full regression sweeps: 211 files, GRAND TOTAL 31664 and
31665 (a 1-assertion difference, within this project's own documented
flaky-suite noise band — see CLAUDE.md's "Sweep-total interpretation"
section — not traced to anything this session touched), 0 real failures
either run.

**E4-2 (asset pull + overlay skeleton) is next.**

---

## 0g. E4-2 — SHIPPED 2026-08-05

**Step 0**: read `001_Summary.rb` in full (1,443 lines, the pack's own
Ruby assembly recipe) and confirmed via `find` that every real asset file
it references under `Graphics/UI/Summary/` exists on disk. Extracted the
exact native 512×384-space pixel coordinates needed for shared chrome and
every page's own content — recorded in full in this session's own
transcript; the subset actually consumed by E4-2's skeleton (mon-sprite
center, page-name/nickname/species/level/dex/gender/item-name positions)
is now recorded directly in `summary_screen.gd`'s own constant doc
comments rather than duplicated a third time here.

**Asset pull** — new `scripts/gen_summary_screen_sprites.py` (mirrors
`gen_party_screen_sprites.py`'s exact flat-copy shape): pulls `bg_1.png`
through `bg_4.png` (INFO/SKILLS/MOVES/EVS-IVS — `bg_5`/Ribbons deliberately
excluded per §0e decision 5's own 4-page scope), `bg_movedetail.png` (the
MOVES page's own move-detail overlay, E4-3's job to wire), `cursor_move
.png`, and `overlay_exp.png` (both E4-3 consumers) into
`assets/sprites/battle_ui/summary/`. Confirmed via direct PIL inspection
that the 4 page backgrounds + `bg_movedetail` are all 512×384 (2× this
project's own 1024×768 canvas, the same "some full-screen background
mockups are genuinely meant to be opaque, no transparency key needed"
finding already documented for the Party-screen pull) and that
`cursor_move.png`/`overlay_exp.png` carry the dimensions §3 already
recorded (292×64/132×6).

**New `scenes/battle/summary_screen.gd`/`.tscn` (`SummaryScreen`)** — a
genuine full-viewport CHILD overlay (matching `ItemSelectScreen`/
`SwitchSelectScreen`'s own established architecture; `BattleManager` is a
scene-tree child that must survive the round trip, so no scene swap).
Built battle-agnostic per M27I's "built once and shared" commitment —
constructed over a plain `BattleParty` + a start index, with `_parent_bs`
used only for its already screen-agnostic display/chrome helpers
(`_name_text`/`_level_text`/`_gender_glyph`/`_style_menu_button`/
`_strip_button_chrome`/`_wire_cursor_group`/`_font_menu`), so a future
non-battle Pokémon-storage context could reuse this screen unchanged.

Shipped this session: page background switching (bg_1-4, clamped — L/R-
equivalent page-nav buttons stop at page 1/4 rather than wrapping, matching
source's own real "pages clamp (no wrap)" behavior); shared chrome (mon
front sprite via `SpriteRegistry.get_front()`, page name label, nickname/
species name — both `_name_text()`, since this project has no nickname
system — level, dex number, gender glyph, held item name); mon cycling
(Up/Down-equivalent nav buttons, WRAPS at either end of the party — the one
real point of asymmetry with page nav, confirmed against source's own
`pbChangePokemon` looping index arithmetic). Per-page DYNAMIC content
(SKILLS' stat table/nature coloring/EXP bar, MOVES' rows + detail panel,
INFO's type icons/ability text, EVS-IVS' own column) is explicitly NOT
built here — each page currently shows only its own real background plus
the shared chrome above; that's E4-3/E4-4's job.

**Wired into E3-3's own disabled Summary stub** in `switch_select_screen
.gd`: pressing Summary now opens a real `SummaryScreen` overlay (hiding,
not destroying, the action submenu underneath — there's no re-entrant
state to preserve, but avoiding a second disable/re-enable pass of the
whole slot-button list keeps a single continuous "looking at my roster"
excursion from one screen state), guarded against stacking a duplicate the
same way `ItemSelectScreen`/`SwitchSelectScreen`'s own overlays already are.

**Real return-path contract implemented**, per §1.3's own citation
verbatim ("On close, `gLastViewedMonIndex` is handed back so the party
cursor follows the viewed mon, and the party menu reopens directly into
the action submenu"): `SummaryScreen.closed(last_viewed_slot)` reports
whichever party slot it was LAST showing — not necessarily the slot that
opened it, since Up/Down inside Summary may have moved to a different
party member entirely — and `switch_select_screen.gd`'s own
`_on_summary_screen_closed` tears down the old (hidden) submenu and opens
a fresh one for that slot. Verified via real screenshot: opened Summary on
the bench mon "Torrent," cycled to the active mon "Blaze," closed — the
reopened submenu correctly highlighted Blaze's own panel, not Torrent's.

**A real ESC-ordering hazard found and closed before it could ship**: with
Summary added as a child of `SwitchSelectScreen`, both nodes' own
`_unhandled_input` listen for ESC. `switch_select_screen.gd`'s own ESC
handler now short-circuits to a no-op for the entire window Summary is
open (checked via `_summary_screen != null and is_instance_valid(...)`),
regardless of which node Godot happens to dispatch the event to first —
without it, a hidden-but-still-alive `_action_submenu` could be torn down
by the switch screen's own handler on the same keypress that closes
Summary, racing the real `_on_summary_screen_closed` rebuild.

**A real, cheap legibility bug caught by the mandatory screenshot pass,
not by any test**: the first draft's chrome-text labels used a flat
near-black fill, which read as illegible against several of the real page
backgrounds' own varied (and sometimes dark) panel colors. Fixed to reuse
this project's own already-established white-text-plus-drop-shadow
convention (`SwitchSelectScreen`'s header, `ActionPanel`'s `StatusLabel`) —
legible against both light and dark art alike, rather than inventing a
third scheme. A second, smaller layout fix: the recipe's own doubled
Level/Gender Y-coordinates landed inside this project's own invented
bottom nav-button row (a real element source has no on-screen equivalent
of, since it's a raw D-pad screen with no buttons at all) — shifted up,
disclosed at the constant rather than silently adjusted.

**Disclosed, not fixed, this session**: the gender glyph (♂/♀) renders as
a "missing glyph" tofu box against the curated 76-glyph bitmap menu font —
confirmed via screenshot, and confirmed to be a PRE-EXISTING, shared
limitation (`SwitchSelectScreen`'s own row text calls the identical
`_gender_glyph()` through the identical font), not a regression introduced
by this session. Not investigated further here.

New `scenes/battle/summary_screen_test.gd`/`.tscn`: 62/62 — real pack-asset
dimensions; start-index clamping (both directions); per-page background/
name/chrome-text correctness across all 4 pages; the "None" vs. real-item-
name held-item cases; page-nav clamping at both ends (with button-disabled-
state checks); mon-cycling wraparound at both ends (with the single-member-
party disabled-and-no-op case); the `closed` signal reporting the
CURRENTLY-viewed mon after cycling away from the start index; ESC closing
the screen; chrome-stripped/real-font nav buttons; and a full
`SwitchSelectScreen`-wiring block (Summary no longer a disabled stub;
pressing it opens a real overlay and hides — not destroys — the submenu;
a second press is idempotent; closing reopens a fresh submenu targeting
the real last-viewed slot, confirmed via inspecting the reopened submenu's
own bound button callables; ESC is a genuine no-op on the switch screen's
own handler while Summary is open). `switch_select_screen_test.gd`'s own
stale `_test_summary_button_is_a_disabled_stub` was rewritten in place
(not left contradicting the shipped behavior) to
`_test_summary_button_now_opens_a_real_summary_screen`, matching this
project's own established "a genuine correctness fix legitimately
invalidates a stale test assumption" precedent (113/113 after the rewrite,
was 111/111 before).

Real, non-headless screenshot verification (8 screenshots via a disposable
scratch driver, deleted after use): the action submenu with Summary now a
real enabled button; all 4 pages in turn (INFO/SKILLS/MOVES/EVS-IVS, each
showing its own real background art correctly, shared chrome persisting
identically across every page); page-nav clamping confirmed visually (a
5th "next page" press past EVS-IVS produces no change, the button visibly
greyed); mon-cycling confirmed visually (chrome text updates from
"Torrent" to "Blaze," page stays put); and the reopened-submenu screenshot
confirming the real return-path contract end-to-end.

Two independent full regression sweeps: 213 files, GRAND TOTAL 31728 and
31729 (a 1-assertion difference, isolated via direct diff to the
already-documented pre-existing `m24c_test.tscn` flake — 27/28 vs. 28/28 —
not traced to anything this session touched), 0 real failures either run.

**Same-day follow-up: converted to real scene-tree-visible UI, per Rob's
own standing preference** (`feedback_scene_tree_visible_ui.md`: "author
fixed-content UI as real .tscn nodes"). Every fixed-position/fixed-content
element (Background, MonSprite, all 7 chrome Labels, all 5 nav Buttons) is
now a real node authored directly in `summary_screen.tscn` — real default
texture (the INFO background), a real baked font (`latin_normal_menu.fnt`,
referenced by uid, mirroring `health_group_panel_player.tscn`'s own
established precedent of baking a FontFile directly rather than fetching
it from a parent script at runtime), real placeholder text, and real
offsets Rob can now drag in the Godot editor to fine-tune — rather than
computed from constants and instantiated procedurally at runtime the way
this screen's own first draft did it. `summary_screen.gd` was correspondingly
cut down to a `_bind_nodes()` function (`$NodeName` lookups) plus a
`_wire_behavior()` function (button chrome-stripping/cursor-group wiring,
which genuinely IS runtime behavior needing `_parent_bs`, so it stays in
code) — the two `_make_label`/`_make_nav_button` procedural builders and
every position constant are gone.

**A real design decision, not an oversight**: node binding deliberately
uses plain `$NodeName` (`get_node()`) rather than `@onready var`. `@onready`
only resolves once a node's own branch actually enters the LIVE SceneTree
(`NOTIFICATION_READY`), and this screen is routinely instantiated and
driven directly in tests — several of which never `add_child()` the
enclosing `SwitchSelectScreen` overlay into a live tree at all, matching
this project's own established bare-instance test convention elsewhere.
`$NodeName` has no such liveness requirement: the child nodes already
exist in the local (possibly off-tree) hierarchy the instant
`PackedScene.instantiate()` returns, so binding via plain `get_node()`
inside `setup()` works unconditionally, with zero test-file changes
required for the conversion (confirmed: all 62 `summary_screen_test.gd`
tests and all 113 `switch_select_screen_test.gd` tests passed unchanged
against the new node-authored scene).

Re-verified via the exact same disposable-scratch-driver screenshot
sequence used for the original shipping pass — pixel-identical output to
the pre-conversion screenshots, confirming the refactor is behavior-
preserving. Two more full regression sweeps: 213 files, GRAND TOTAL 31729
both times, 0 real failures.

**E4-3 (SKILLS + MOVES dynamic content) is next.**

---

## 0h. E4-3 — SHIPPED 2026-08-05

**Step 0**: read `001_Summary.rb`'s own `drawPageTwo` (SKILLS,
lines ~630-673), `drawPageThree`/`drawSelectedMove` (MOVES + detail,
lines ~675-832) directly, rather than trusting the earlier recon prose
summary. Two real findings came out of this re-read, both disclosed
plainly rather than silently absorbed:

**A real correction to this doc's own §1.2**: that section's prose lists
"EXP points, NEXT LV." as SKILLS-page content. The real recipe
(`drawPageOne`, ~lines 451-473) draws EXP on the **INFO** page instead —
`drawPageTwo` never touches it at all. EXP-bar work is therefore E4-4's
job (INFO page), not a scope cut from this session; `summary_screen.gd`'s
own header doc comment states this explicitly so a future reader doesn't
"fix" the omission back into the wrong page.

**PP 4-tier coloring and nature/raised/lowered stat coloring** were
transliterated exactly from the recipe's own literal color arrays
(`ppBase`/`ppShadow` in `drawPageThree`/`drawSelectedMove`, both define
the identical array) rather than approximated — recorded as real `Color8`
constants directly in `summary_screen.gd` (`_PP_TIER_FG`/`_PP_TIER_SHADOW`,
`_COLOR_RAISED_*`/`_COLOR_LOWERED_*`/`_COLOR_NEUTRAL_*`), not duplicated a
third time here. HP is confirmed via source to NEVER receive raised/
lowered coloring (`nature_for_stats.stat_changes` never touches `:HP`) —
reproduced with an explicit, commented exclusion in the stat-coloring loop
rather than relying on `_nature_stat_pair()` never structurally returning
`STAT_HP` to keep the rule true by accident.

**Shipped this session**: `_refresh_skills_page()` — nature name (via the
already-shared `BattlePokemon.nature_name()`), ribbons (always "None" —
this project has no ribbon system, so the real count-based branch is
unreachable by construction, not a simplification), ability name +
description (real text when `mon.ability` is set, "—"/blank when null),
and the 6-stat value table with real nature-driven raised/lowered/neutral
coloring. `_refresh_moves_page()` — 4 real move rows (type badge via the
already-existing `_type_badge_texture()`, real move name, real PP at the
correct 4-tier color) with a real empty-slot placeholder ("-"/"--",
disabled row, tier-0 gray) for any of the mon's own unfilled move slots.
Move selection (`_on_move_row_pressed`) toggles a real detail panel
(power/accuracy sentinel text — "---" for a true status move, "???" for
this project's own established power=1 variable-power sentinel, else the
real number/percentage — plus the real category icon via the already-
existing `_category_icon_texture()` and the move's own real description),
with the background swapping to the real `bg_movedetail.png` only while a
move is actively selected on the MOVES page. Page change, mon change, and
leaving the MOVES page all correctly reset the selection back to none,
matching source's own "leaving MOVES/switching mons always drops back to
the plain list" behavior.

**The real bug found and fixed this session — a bitmap-font opaque-accent
color-modulation defect, not a logic bug in any of the above.** The
mandatory screenshot pass showed every new dynamically-colored SKILLS
label (Nature/Ribbons/stat values) rendering as a solid, illegible black
rectangle instead of colored text. Root-caused via a multi-step
investigation (progressively-zoomed PIL pixel cropping, an isolated
single-Label debug scene comparing a black-colored label against a
white-colored one under the identical font, a direct raw pixel dump of
the font atlas PNG, and finally reading `scripts/gen_battle_fonts.py`'s
own `COLOR_CONTEXTS`/`_recolor` logic) to: the `"latin_normal_menu"` font
context — every label on this screen, old and new alike, was using it —
bakes its "accent"/bulk-fill role as fully **opaque white** at generation
time (`(255,255,255,255)`), a deliberate, source-accurate choice for that
context's real original use case (menu-button text drawn on a matching-
color window panel, where the accent is meant to color-match the panel
and therefore never actually be seen as a separate box). A runtime
`font_color` override multiplies against these already-baked pixels: white
(this project's own pre-existing chrome-label color) is the multiplicative
identity, so it silently preserved the intended look and no one noticed;
**black zeroes both the foreground stroke and the opaque accent fill to
the identical value**, erasing all internal shape and producing exactly
the solid rectangle the screenshot showed.

**Confirmed NOT limited to the new SKILLS labels**: re-cropping an
EARLIER, already-shipped E4-2 chrome screenshot ("Torrent," the nickname
label, white-colored) at 4× nearest-neighbor zoom showed it had ALWAYS
been rendering with a visible solid white box behind the text — simply not
noticeable at normal zoom against the pack's own pale page backgrounds.
This was a real, pre-existing (if invisible) rendering defect affecting
every label on this screen since E4-2 shipped, not something E4-3
introduced.

**Fix**: a new `COLOR_CONTEXTS` entry in `scripts/gen_battle_fonts.py`,
`"latin_normal_colorable"` — foreground=shadow=**WHITE** (both act as the
multiplicative identity, so a runtime `font_color`/`font_shadow_color`
override produces exactly the requested color), accent/bulk-fill=fully
**TRANSPARENT** (`(0,0,0,0)`) — mirroring the already-established
precedent set by `"latin_small_healthbox"` and the two popup contexts, all
three of which already use a transparent accent for text overlaid on
varied/sprite art rather than one fixed-color panel. Regenerated via
`python3 scripts/gen_battle_fonts.py` (idempotent, all 6 font contexts
regenerate cleanly). Every label on `summary_screen.tscn` — every E4-2
chrome label AND every new E4-3 SKILLS/MOVES/detail label, plus all 5 nav
buttons — was repointed from `latin_normal_menu.fnt` to the new
`latin_normal_colorable.fnt`; the old font's own `ext_resource` was left
unreferenced-and-removed (nothing else on this screen still needs it).
Re-verified via the same disposable screenshot driver: Nature/Ribbons/
stat values, move names/PP (all 4 real tiers reachable through the
fixture), and the detail panel's power/accuracy/description all now
render as genuinely legible colored text with the real page art visible
behind them — no solid-color boxes anywhere.

New `scenes/battle/summary_screen_test.gd`/`.tscn` coverage (62→127): SKILLS
— real nature name, ribbons always "None," ability name/description
(including the null-ability dash case), all 6 stat values, raised-stat-red/
lowered-stat-blue coloring (via a real Adamant fixture), a neutral-nature
all-neutral-colored check, HP-never-colored (even with a nature whose pair
could theoretically include it), and SKILLS-only node visibility toggling.
MOVES — a real move row's full content (type icon/name/PP/tier-0 color), an
empty slot's placeholder content, `_pp_tier()`'s own boundary values (a
direct static-function check, not routed through the accuracy-roll-forcing
seam this codebase has none of for PP), row click-to-select and
click-again-to-deselect, the `bg_movedetail` background swap gated
correctly on selection, page-change and mon-change both resetting the
selection, and MOVES-only row visibility toggling. Detail panel — both
power sentinels ("---"/"???") plus a real value, both accuracy cases,
and the category icon + real description. All 127 pass clean.

Two independent full regression sweeps via the hardened absolute-path
`count_assertions.sh` invocation: 213 files, GRAND TOTAL 31794 and 31795
(a 1-assertion difference, isolated via direct diff to the
already-documented pre-existing `m24c_test.tscn` flake — 27/28 vs. 28/28 —
not traced to anything this session touched), 0 real failures either run.

Real, non-headless screenshot verification (5 screenshots via a disposable
scratch driver, deleted after use): the SKILLS page (nature/ribbons/all 6
stat values legible and correctly colored), the MOVES page (all 4 real
moves with type badges, names, and full-PP tier-0 PP text), a selected
move's detail panel (real power/accuracy/description text, background
swapped to `bg_movedetail`), a second move selected (confirming per-row
selection state), and deselection (confirming the background and detail
panel both correctly revert).

**Not built this session, per its own already-locked scope**: INFO page's
own dynamic content (types, ability text there, OT/memo reserved slots,
EXP bar — now confirmed to belong here, not SKILLS, per the correction
above) and the EVS-IVS page. Both remain E4-4's job.

**E4-4 (INFO + EVS-IVS pages, polish, full test suite) is next.**
