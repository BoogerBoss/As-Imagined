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
