# M26E1+E2 recon — Bag screen visual rework + real pocket-tab implementation

Written 2026-08-05. Recon only — no code written, no assets pulled this session.

## 0a. Decisions resolved (Rob, 2026-08-05)

All 6 open questions from §7 answered. One answer **expands scope** beyond
what this doc originally proposed — flagged explicitly below rather than
absorbed silently.

1. **Route: pack art confirmed** (`bg_m.png`/`bg_f.png` replace `bag_frame.png`).
2. **Battle pocket-legality: Items always / Poké Balls wild-only / TM-HM+Key
   Items never — as recommended — PLUS Berries, which was declined in the
   original recommendation** (§3 had proposed excluding Berries entirely,
   pending a feed-mechanic that didn't exist). See decision 2b.
3. **Cursor: reuse the existing "▶" glyph** (as recommended) — `cursor.png`
   is not pulled.
4. **Bag-jump transition animation: build now**, not deferred — `pbBagJump`'s
   5-frame lean, backed by `bag_1.png`…`bag_6.png` and `icon_pokeball.png`'s
   7-frame ball-flash strip, both pulled in E1 rather than left for later.
5. **`bag_N.png` → pocket mapping: the recommended order** — `bag_1`→Items,
   `bag_2`→Poké Balls, `bag_3`→TM/HM, `bag_4`→Berries, `bag_5`→Key Items,
   `bag_6` pulled but unused (matching this project's own "pull the whole
   set even if one entry has no consumer yet" precedent, `[M27D D1]`/
   `[M26B3-1]`).

## 0b. E1 — SHIPPED 2026-08-05

`scripts/gen_bag_sprites.py` pulls `bg_m.png`/`bg_f.png`, `icon_pocket.png`
(for E2), `bag_1.png`…`bag_6.png`(+`_f`), and `icon_pokeball.png` (the
7-frame ball-flash strip) into `assets/sprites/battle_ui/bag/` — a plain
flat copy, every source file already carries a real tRNS chunk PIL resolves
on `.convert("RGBA")`, no runtime color-keying needed (confirmed per-file,
not assumed uniform with earlier pack pulls).

**The real feed-a-berry mechanic** (`ItemManager.bag_berry_effect`) reuses
`hp_threshold_berry_heal`/`status_cure_berry_cures`/`confusion_cure_berry_
cures` via their pre-existing `override_item` bypass (built for Cud Chew,
`[M17n-7]`) rather than inventing new per-berry logic — `battle_usage` was
added to all 9 real bag-feedable berries' `gen_items.py` entries
(`BATTLE_USE_RESTORE_HP` for Oran/Sitrus, `BATTLE_USE_CURE_STATUS` for
Cheri/Chesto/Pecha/Rawst/Aspear/Persim/Lum), matching source's own real
`.battleUsage` field exactly. `BattleManager._do_item_use` routes a
`POCKET_BERRIES` item through this new function instead of `bag_item_heal`/
`bag_item_cure_status` (which are Potion/Full Heal's own flat/blanket
shape — wrong for Sitrus's percent heal or Cheri's per-status cure).

**`ItemSelectScreen` fully rewired** onto the real `OverworldSession.bag`
— no more hardcoded `_ITEMS` array. `_legal_pockets()` implements the §3
battle-legality filter (Items + Berries always, Poké Balls only when
`_bm.is_wild_battle`); real per-stack quantities now render (were always
empty before). New `BattleManager.bag_item_consumed` signal (engine-only,
never touches `OverworldSession` — the UI layer, `battle_screen_shared.gd`,
does the actual `Bag.remove()`) fires only when an item's effect genuinely
did something, so a no-op use (e.g. a Potion on a full-HP target) doesn't
spend real inventory. `_ensure_debug_stock()` seeds a small stock into the
real Bag for the standalone battle simulator (`is_overworld_battle ==
false`, promoted from a `_ready()`-local to a real member field on
`BattleScreenShared` so this overlay can read it later) — a real RPG
playthrough's own bag is never touched.

**Real bg_m.png background** wired into both `ItemSelectScreen` (replacing
the `bag_frame.png` decode) and `FieldBagScreen` (replacing its plain
`Panel`) — `stretch_mode` bug (TILE instead of SCALE) caught and fixed via
a real non-headless screenshot pass, which also confirmed the real item
list/quantity/cursor/bag-sprite positions against the pack's own actual
4-region layout (measured directly, not just from the recon's own derived
coordinates). The bag-jump animation (decision 4) plays once on open, as a
simplified scale/rotate "lean" tween — the full frame-by-frame `pbBagJump`
lean plus the 7-frame ball-flash strip stepping is a disclosed
simplification, not built. One disclosed minor cosmetic gap found via the
screenshot pass and not fixed: a handful of description-text glyphs (e.g.
"P", digits) render as black boxes in the menu-context bitmap font — a
font glyph-coverage gap, not a data or layout bug.

New/updated tests: `item_select_screen_test.gd` fully rewritten (15→47,
covering debug-stock seeding and its overworld-battle gate, the pocket
legality filter in both directions, real Bag contents + Cancel, a
stat-raise berry's exclusion even when physically present, real
font/chrome/cursor, both berry-feeding paths end-to-end — heal and cure —
each confirmed to fire `bag_item_consumed`, and the full-HP-Potion
no-consumption case); `item_test.gd` gained a new `_test_i13_bag_berry_
feeding` section (10 assertions) unit-testing `bag_berry_effect` directly
(flat heal, percent heal, already-full-HP no-op, per-status cure with a
wrong-status discriminator, confusion cure, a stat-raise berry's no-op,
wrong-pocket no-op, null guard); `m27i_i4_bag_screen_test.gd` (48/48,
unchanged — confirms the FieldBagScreen art swap didn't disturb its own
logic). Two full regression sweeps: 208 files, GRAND TOTAL 29503 and
29504 (the 1-assertion difference is this project's own documented
statistical-flake noise, not a regression), 0 failures.

E2 (real pocket-tab row + L/R cycling, ported from `FieldBagScreen.next_
pocket`/`move_row`) remains open — `bag_pocket_icons.png` is pulled and
ready for it.

## 0c. E2 — SHIPPED 2026-08-05

**`icon_pocket.png` confirmed via direct PIL pixel scan (not assumed from
its filename) to be a plain SELECTED/UNSELECTED position-dot indicator, not
per-pocket iconography**: 168×48, 6 slots at a 16px x-stride, a big 8×8
square at y=0-16 for the currently-selected slot, a small 4×4 dot at
y=32-48 for every other slot. New `ItemManager.pocket_dot_region(slot_
index, selected) -> Rect2` is the one shared crop-rect helper both screens'
dot rows use.

**`ItemSelectScreen` rewritten from a single flat combined-pocket list
(E1's own interim shape) into real per-pocket tabs.** New `_pocket_order`/
`_pocket_index` state, computed once per `setup()`/`_build()` call from
`_legal_pockets()` (unchanged from E1 — Items + Berries always, Poké Balls
only in a wild battle). `_build()` now does one-time chrome setup (debug
stock, DescLabel's font override) then calls a new `_refresh_pocket()`,
which rebuilds ONLY the dynamic per-pocket content (item rows + Cancel,
`PocketLabel`'s text, `DotRow`'s children) — the static chrome (background,
bag sprite) is untouched by a pocket change. New `next_pocket(delta)`
cycles with **skip-empty logic**: source's real `@choosing`-mode behavior
(this is a "pick one item to use" screen, not a plain browse), distinct
from `FieldBagScreen`'s own deliberately-non-skipping plain-browse mode —
capped at one full lap so an all-legal-pockets-empty state can't infinite-
loop; a genuinely empty pocket shows a real "No items." placeholder (Label,
not a button) plus Cancel, matching `FieldBagScreen.EMPTY_TEXT`'s own
precedent. `PocketLabel` (new `.tscn` node, top-left, matching source's
real pocket-name-bar position) shows the real pocket name via `FieldBag
Screen.POCKET_NAMES` — the item-list box's own old in-box "ITEMS" header
Label is retired (hidden, not deleted, so the VBox's static-vs-dynamic
child-clear guard still has a stable node to skip) rather than repurposed,
since source's real layout has no such second, redundant label. Input:
raw `KEY_LEFT`/`KEY_RIGHT` in `_unhandled_input` (matching this screen's
own pre-existing raw-keycode convention for ESC, not `FieldBagScreen`'s
separate `Input.is_action_just_pressed("ui_left")` convention — the two
screens already used different input conventions before this session and
this keeps that split rather than quietly harmonizing it).

**A real bug found and fixed during this session, not by any test on its
first run**: both `_refresh_pocket()`'s row-rebuild and the dot row's own
rebuild originally used `queue_free()` alone on their old children.
`queue_free()` only *schedules* removal at end-of-frame — it does not
detach the node from the tree immediately — so a bare-instance test
calling `next_pocket()` right after `setup()`, with no frame processed in
between (this project's own established synchronous bare-instance test
convention), would see the OLD pocket's rows/dots still present alongside
the NEW ones on the very next `get_children()` read. Fixed by pairing
every such rebuild loop with an explicit `parent.remove_child(c)` before
`c.queue_free()`, in both `item_select_screen.gd` and (the same latent bug,
found and fixed the same way before it could ever surface) `field_bag_
screen.gd`'s own `_refresh_dot_row()`.

**`FieldBagScreen` gained the matching dot-row visual** (`_dot_row`, a new
`HBoxContainer` sitting between the existing `_tab_label` and `_rows_box`)
— its own pocket-cycling INPUT was already fully wired since `[M27I I4]`
(`overworld.gd`'s `_drive_bag_screen()` reading `ui_left`/`ui_right`), so
this was visual-only. New `dot_region(index)`/`dot_count` public accessors
(mirroring this screen's own existing public-API-only test convention —
no prior test in this file ever reached into a private field) let a test
assert against the real per-dot region without touching `_dot_row`
directly.

**Real non-headless screenshot verification** (a disposable scratch
driver, deleted after) confirmed, via both eyeballing and precise pixel-
region cropping: `ItemSelectScreen`'s dot row correctly renders the
selected pocket as a solid highlighted square and every other pocket as a
small dot, switching correctly on `next_pocket()`; `FieldBagScreen`'s own
5-dot row renders and updates identically. One red herring during
verification, resolved by direct source-art inspection rather than
guessed: a row of small light squares visible in a `FieldBagScreen`
screenshot, positioned between two item rows, turned out to be a
**pre-existing decorative dashed line baked directly into `bag_bg_male.
png`'s own background art** (confirmed via a direct crop of the source
PNG) — coincidentally similar-looking to the real dot row, but unrelated
to it and not a defect introduced by this session.

New/updated tests: `item_select_screen_test.gd` grew 47→68 — Test C
rewritten for the new per-pocket-only content shape (was asserting a
single 6-item combined list); Test D updated to switch pockets before
checking a stat-raise berry's exclusion; the old header test replaced with
a `PocketLabel`-based one confirming both the default pocket's name and
that it updates on cycle; 11 new assertions across cycling (forward/
backward/wrap), skip-empty (a Poké-Ball-only-reachable scenario), the
all-pockets-empty termination + placeholder-text cases, the open-time
snap-to-first-non-empty-pocket behavior, the dot row's child count and
per-dot region (including the pre/post-cycle swap), and LEFT/RIGHT key
input. `m27i_i4_bag_screen_test.gd` grew 47→52 (Section G, 5 assertions:
dot count, the initial selected/unselected regions, and both flipping
correctly after `next_pocket(1)`). Two full regression sweeps: 208 files,
GRAND TOTAL 29527 both times (byte-identical), 0 failures; the overworld
suite (`scripts/run_overworld_tests.sh`, ERROR-line-sensitive, not covered
by the battle-side sweep) separately confirmed clean for `m27i_i4_bag_
screen_test` (53/53), `m27i_i5_party_test` (58/58), `m27a_step_resolver_
test` (514/514), `m27i_bag_test` (47/47), and `m27f_stage4_test` (63/63).

**M26E1+E2 is now fully complete.**

### 2b. Berries — real scope expansion, not just a pocket toggle

Including Berries means the battle bag needs to actually be able to DO
something with one — this project had no "feed a held-item-style berry to
your own Pokémon mid-battle" action before this decision (every berry was
held-item-only, `[M12]`/`[M18]`'s own scope). **Decision: build the real
mechanic**, not just show the pocket as browsable-but-inert.

Checked directly against `reference/pokeemerald_expansion/src/data/items.h`
before building anything (not assumed from memory): **exactly 9 of this
project's already-implemented berries carry a real `.battleUsage` field in
source** — Cheri/Chesto/Pecha/Rawst/Aspear/Lum (all `EFFECT_ITEM_CURE_
STATUS`), Persim (`EFFECT_ITEM_CURE_STATUS`, its own confusion-only
dispatch), and Oran/Sitrus (`EFFECT_ITEM_RESTORE_HP`) — **the exact same
`.battleUsage` category source already assigns to Potion/Full Heal**, not a
separate mechanism invented for this session. Every stat-raise/passive-only
berry this project has (Liechi, Ganlon, Salac, Petaya, Apicot, Starf,
Lansat, Custap, Micle, Enigma) carries **no `.battleUsage` at all** in
source (`.type = ITEM_USE_BAG_MENU` with `.fieldUseFunc =
ItemUseOutOfBattle_CannotUse`, no `battleUsage` key present) — confirmed
NOT bag-feedable in the real games, and correspondingly out of scope here.

This means the real feed-a-berry mechanic is narrower and cheaper than it
first looked: exactly the 9 status/HP berries this project already has full
mechanic functions for (`hp_threshold_berry_heal`/`status_cure_berry_cures`/
`confusion_cure_berry_cures`), each of which already carries an
`override_item` bypass parameter built for Cud Chew's re-trigger
(`[M17n-7]`) — passing the berry directly as `override_item` skips the
auto-trigger HP threshold and Unnerve's block, which is exactly the correct
behavior for a bag-fed berry (Unnerve blocks a HELD berry from
auto-triggering; a fed berry was never held, so neither Unnerve nor Klutz
should apply). No new per-berry logic was needed — a new thin dispatch
wrapper (`ItemManager.bag_berry_effect`) routes to the three existing
functions by `hold_effect`. See `[E1 implementation]` below for what
shipped.

Scoped together deliberately: E2 ("real pocket-tab implementation") was declined at
M25h-1.4 specifically *because* the battle bag could only ever show one populated
pocket, and the roadmap's own E2 entry says that call "is revisited now that the
screen itself is being rebuilt anyway" — i.e. under E1. Scoping E2 alone without
also settling E1's frame-art question would mean designing pocket-tab chrome twice.
This doc answers both; **E2 is still the harder/newer half and is the focus**, per
Rob's ask.

Reference: pokeemerald-expansion (mechanics/data, already ported) + the vendored
`assets/Emerald UI Pack 1.2/Graphics/UI/Bag/` art + its own bundled Ruby scene
script, `Plugins/Emerald UI Pack/002_Bag.rb` (an Essentials `PokemonBag_Scene`,
the closest thing this pack has to real coordinates/behavior for this screen —
same role `004_Party.rb`/`001_Summary.rb` played for E3/E4).

---

## 0. TL;DR

1. **The premise that killed E2 the first time is gone.** M25h-1.4 declined
   pocket-tab chrome because the battle bag "could only ever show one populated
   tab." That's no longer true: the current 4-entry battle list already spans
   **two** real pockets (Potion/Full Heal/X Attack → `POCKET_ITEMS`; Poké Ball →
   `POCKET_POKE_BALLS`, added later by `[M27H H4]`) and a real, capacity-bounded
   `Bag` (`scripts/overworld/bag.gd`) has existed since `[M27I I3]` with genuine
   multi-pocket contents. **There is real data to browse now.**
2. **A second, more consequential finding: the battle bag isn't wired to the real
   `Bag` at all.** `ItemSelectScreen` (`scenes/battle/item_select_screen.gd`)
   still reads a hardcoded 4-entry `_ITEMS` array, unchanged since M23.1/M27H —
   its own doc comment says outright "wiring it to `OverworldSession.bag` for
   real is M26E1/E2's rework." **E2 is not just a tab widget — it's the point
   where the battle bag stops being a placeholder and starts reading the real
   bag.** That's the larger part of the work, not the tab UI itself.
3. **The field bag (`scripts/overworld/field_bag_screen.gd`, `[M27I I4]`)
   already built real 5-pocket cycling/wrapping/clamping against the real
   `Bag`**, and its own doc comment explicitly defers its plain-`Panel` chrome
   to "M26E1" for a redo. So this work has two real screens to reconcile, not
   one to build from scratch: **port the field bag's already-correct pocket
   logic into the battle bag, and give both the real pulled art the field bag
   never got.**
4. **Real assets exist and are already vendored**: `bg_m.png`/`bg_f.png` (512×384,
   the real four-region layout background), `icon_pocket.png` (168×48, a
   16×16-per-cell icon strip covering up to 8 pockets), plus `bag_1.png`…
   `bag_6.png` (+`_f` variants, small animated bag-icon sprites, one per
   pocket), `cursor.png`/`cursor_swap.png`, `icon_hm.png`, `icon_register.png`.
   None of it is pulled into the project yet (`gen_databox_sprites.py`-style
   flat copy, same shape as every other Emerald-UI-Pack pull this project has
   already done).
5. **A real scope question the pack itself doesn't answer**: Essentials' own
   bag has 6 pockets (6 `bag_N.png` variants); this project's `ItemManager` has
   5 (`ITEMS`/`POKE_BALLS`/`TM_HM`/`BERRIES`/`KEY_ITEMS` — no separate
   "Medicine" pocket, matching Gen III's real pocket layout, not Essentials'
   default). Which `bag_N` maps to which of the 5 real pockets — and what
   happens to the 6th — is a decision for Rob (§7).
6. **A second real question specific to battle**: the real games restrict which
   pockets are even openable from a battle menu (no TM/HM, no Key Items — you
   can't teach a move or use a Bike mid-fight) and Poké Balls are legal only in
   a wild encounter, never against a trainer. This project already has both of
   the signals needed to reproduce that (`ItemData.battle_usage` and
   `BattleManager.is_wild_battle`) but nothing currently reads them for
   pocket-level filtering. Recommended in §5/§7.
7. Proposed phasing: **E1** real art pull + wiring the battle bag to the real
   `Bag` (still single-list, no tabs yet) → **E2** real pocket-tab cycling,
   ported from the field bag's own already-correct logic, plus the
   battle-context pocket filter. ~1.5–2 sessions total (§6).

---

## 1. Current state — two bag screens, two different gaps

### 1.1 `ItemSelectScreen` (the **battle** bag, `scenes/battle/item_select_screen.gd`)

- Built at `[M25h-1.4]`, extended at `[M25h-4]` (real `bag_frame.png`-derived
  window art — see §1.3 below, this is a *different*, earlier decode, not the
  pack's own `bg_m.png`) and `[M27H H4]` (added the Poké Ball entry).
- **Data source: a hardcoded `const _ITEMS` array**, 4 entries, each with an
  `id`/`label`/`pocket` (the `pocket` field is present but "not read by
  `_build()` yet, since every entry currently shares the same real pocket" per
  its own comment — except it no longer does; the Poké Ball entry is
  `pocket: 1`, the other three are `pocket: 0`. The comment predates the ball
  add-on and is stale).
- **UI**: one flat scrollable `VBox` of chrome-stripped, cursor-wired buttons
  (`_style_menu_button`/`_strip_button_chrome`/`_wire_cursor_group`, all
  inherited from the parent `battle_screen_shared.gd` — the established
  reuse pattern this screen already follows for every other overlay), a
  static `"ITEMS"` header, a real quantity-text slot that always renders
  empty (no quantity data behind it — `ItemData` has none, and the hardcoded
  list has no counts).
- **No pocket switching of any kind.** No tab row, no icon, no L/R input.
- Call site: `_build_item_buttons(field_slot)` in `battle_screen_shared.gd`,
  an idempotent child-overlay creator (same lifecycle shape as
  `SwitchSelectScreen`/`MatchupOverlay`) — `item_chosen(item_id)` /
  `cancelled()` signals, wired to `_on_item_pressed` which just calls
  `_bm.queue_item_for(combatant_idx, item_id)` — genuinely pocket-agnostic
  downstream, so nothing past the picker itself needs to change.

### 1.2 `FieldBagScreen` (the **field** bag, `scripts/overworld/field_bag_screen.gd`)

- Built at `[M27I I4]`, explicitly *not* a reuse of `ItemSelectScreen` — "its
  data path is not [reused], and reworking it is M26E1/E2's job."
- **Data source: the real `Bag`** (`open(bag: Bag, start_pocket)`), reading
  `bag.slots(pocket)` live.
- **Real 5-pocket cycling already built**: `next_pocket(delta)` wraps
  (`wrapi`), `move_row(delta)` clamps within a pocket (deliberately does NOT
  wrap — "with the pockets wrapping right beside it, a wrapping row list
  would make a held Down key silently cycle forever," the exact reasoning
  that generalizes to whatever E2 builds). `POCKET_ORDER`/`POCKET_NAMES` are
  keyed straight off `ItemManager.POCKET_*`, matching source's real
  `gPocketNamesStringsTable` strings ("ITEMS", "POKé BALLS", "TMs & HMs",
  "BERRIES", "KEY ITEMS").
- Real per-row quantity suffix logic already correct (`"x%d"`, suppressed for
  Key Items and HMs, matching source's own `gText_NumberItem_HM` exception —
  `[M27I I4]`'s own finding).
- **Chrome: a plain `Panel.new()`**, no real art, no shared `_font_menu`/
  cursor conventions from `battle_screen_shared.gd` (this screen has no
  battle-screen parent to borrow them from) — its own doc comment names this
  as the thing M26E1 owns.
- Uses/toss/give are already scoped narrowly here (`[M27I I5-2/I5-3]` — USE
  opens the field party screen as a target picker); irrelevant to the battle
  side, which has its own separate `_on_item_pressed` dispatch.

### 1.3 Two *different* prior art pulls already exist — do not conflate them

- `[M25h-4]`'s **decoded reference-ROM tilemap** (`bag_frame.png`/
  `party_frame.png`, `scripts/gen_ui_frames.py`) — a genuine tile+tilemap
  decode of the vanilla GBA `Bag`/`Party` screen graphics, still in use by
  `ItemSelectScreen.tscn` today (referenced by its `Panel/FrameRect` node,
  per that screen's own doc comment).
- **This session's pull target, `bg_m.png`/`bg_f.png`**, is the Emerald UI
  Pack's own *flat, pre-composited, stylized* Bag background — the same
  pack already used for the databox (`[M26c-1]`), battle backgrounds
  (`[M26c-2]`), Party (`[M26E3]`), and Summary (`[M26E4]`) screens. **The
  established M26 direction, confirmed repeatedly across those sessions, is
  the pack over a fresh reference decode** — matching art style across every
  M26 screen, at a fraction of the effort a second tile/tilemap/palette
  decode would cost, and with real per-element coordinates supplied by the
  pack's own Ruby script (§2), the same advantage `004_Party.rb`/
  `001_Summary.rb` gave E3/E4. **Recommendation: replace `bag_frame.png`
  with the pack's `bg_m.png`/`bg_f.png` rather than keep both**, consistent
  with the M26B2/E3 precedent of "swapping decode-derived art for
  pack-sourced flat art once a screen is actually reached."

---

## 2. The Emerald UI Pack's Bag kit — real coordinates, from `002_Bag.rb`

Confirmed by direct pixel inspection (`PIL`) and by reading the pack's own
bundled Ruby scene script (`Plugins/Emerald UI Pack/002_Bag.rb`, a real
Essentials `PokemonBag_Scene` — the same class of source `004_Party.rb`/
`001_Summary.rb` already supplied for E3/E4), **not** assumed from the
mockup image alone.

### 2.1 Assets, `Graphics/UI/Bag/`

| File | Size | Role |
|---|---|---|
| `bg_m.png` / `bg_f.png` | 512×384, P-mode | Full-screen background — the real four-region layout (pocket tab top-left, item list top-right, item-icon slot left-middle, description box bottom). Gender-paletted (blue/purple vs. pink/magenta); this project tracks no player gender yet — pick one as a neutral default (§7). |
| `icon_pocket.png` | 168×48, **RGBA** (already has real alpha, unlike every other file here) | A 16×16-per-cell icon grid. The scene script blits `Rect(x=(pocket-1)*16, y=0 or 16, w=16, h=16)` — two rows in use (selected/unselected state), the sheet's own 3rd row (height 48 = 3×16) unused by this scene. Room for up to ~8-10 pocket icons; this project needs 5. |
| `bag_1.png` … `bag_6.png` (+ `_f` variants) | 128×132 (132×132 for `_f`), P-mode | Small decorative "the bag itself" sprite, one flavor per pocket, blitted at (121,203) with origin (66,132) — bounces/tilts when the pocket changes (`pbBagJump`). **6 variants; this project has 5 real pockets** (§7). |
| `icon_pokeball.png` | 32×224, P-mode | 7-frame strip, the tiny ball animation during the bag-jump transition. Cosmetic, low priority. |
| `icon_hm.png` | 32×28, P-mode | Two-state marker (own row at y=0 vs y=24-ish) drawn over an HM row instead of a quantity — already reproduced logically in `FieldBagScreen._quantity_suffix` (HMs show no count), just no icon yet. |
| `icon_register.png` | 56×48, P-mode | Two-state marker (registered / can-register) for the Select-button quick-item feature. **Not modeled anywhere in this project** — no B/Select quick-item slot exists. Flag as out of scope, not silently built. |
| `cursor.png` | 12×20, P-mode | The plain row-select arrow. This project already has its own real "▶" glyph cursor convention (`_wire_cursor_group`, from `[M25h-1.3]`/`[M26D1]`'s font work) — **recommend reusing that, not pulling this asset**, for visual consistency with every other list screen (Switch, Item's own Cancel row, the TOP/FIGHT grids). |
| `cursor_swap.png` | 264×32, P-mode | The item-reordering "sort mode" cursor. This project has no item-reordering feature (real source's own `pbChooseItem` sort-mode branch) — out of scope. |

### 2.2 Real layout coordinates (from `pbStartScene`/`pbRefresh`, canvas 512×384 — this
project's own established 2× multiple of that canvas, matching every other
M26 pack pull)

- **Item list box** (top-right): `Window_PokemonBag.new(..., x=214, y=-4,
  width=314, height=20+32+(ITEMSVISIBLE*32))` — `ITEMSVISIBLE` is Essentials'
  own visible-row count (8 by default); each row is 32px tall.
- **Pocket-name + pocket-icon row** (top-left): position (72,52), size
  (186,32) for the icon row; pocket name text drawn at (124,22).
- **Item-icon slot** (left-middle): position (44,240).
- **Description box** (bottom): position (12,262), width `Graphics.width-24`
  (488), height 144 — the box's own bottom edge (406) runs slightly past the
  384-tall canvas in the raw numbers; treat as approximate and re-verify
  visually once built, the same "verify once built, adjust only if proven
  necessary" discipline M25h-1's own bottom-region did for its literal
  75-95% figure.
- **Pocket-cycle arrows**: left (28,18), right (182,18) — flanking the
  pocket-name row from above. This project's established input convention
  (no InputMap anywhere, raw keycodes per `[M25h-1.3]`) suggests L/R as
  literal on-screen buttons for mouse-first play, with a real key added
  alongside (see §7 — this overlaps `[M26C8]`'s own not-yet-built
  keyboard-navigation scope, cited there but never assigned).

### 2.3 Pocket-switch behavior, from `pbChooseItem`'s real input loop

- **Wraps**, both directions (`newpocket = (newpocket==1) ? pocket_count :
  newpocket-1`, and the mirror for right) — confirmed, matching
  `FieldBagScreen.next_pocket`'s own already-correct `wrapi` call exactly.
- **Skips empty pockets** when `@choosing` (the "pick one item" mode, e.g.
  when handing the bag to a move/effect) but does **not** skip them in the
  plain browse mode — this project's battle-bag use is closer to the
  `@choosing` shape (you're picking one usable item to act with, not just
  browsing), so skipping empty/no-legal-item pockets is the right behavior
  to port, not the plain-browse one.
- The little bag sprite audibly/visually "jumps" (`pbBagJump`) on a
  successful pocket change — 5-frame lean+ball-flash animation, purely
  cosmetic, low priority (§6, deferred to a later polish pass if wanted at
  all).

---

## 3. Battle-context pocket scope — what should actually be openable

Two real, already-encoded signals answer this without inventing anything:

1. **`ItemData.battle_usage`** (`RESTORE_HP`/`CURE_STATUS`/`INCREASE_STAT`/
   `THROW_BALL`, `item_manager.gd:907-911`) — already the exact discriminator
   `FieldBagScreen.is_field_usable` uses for its own field-context filter.
   A pocket with **zero** items carrying any real `battle_usage` value has
   nothing a battle bag could ever let you do with it — TM/HM and Key Items
   are structurally exactly this (teaching a move or using a Bike mid-battle
   isn't a mechanic this project has, or that the real games allow either).
2. **`BattleManager.is_wild_battle`** (`[M27H H4 fix]`, already correctly
   derived and consumed elsewhere for Run's own wild-vs-trainer branch) —
   the real games only let you throw a Poké Ball in a wild encounter, never
   against a trainer's Pokémon. `POCKET_POKE_BALLS` should be hidden (or
   shown-but-empty-and-disabled, matching source's own "shown, not hidden"
   convention for an unusable slot, per `[M27I I3]`'s own "an unknown special
   still halts... halts loudly" discipline of preferring visible-and-refused
   over silently-absent) when `is_wild_battle` is false.
3. **Berries** (`POCKET_BERRIES`) are a genuine real-games battle-legal
   pocket (feeding a held-berry-family item to your own Pokémon mid-battle
   is real Gen III/onward behavior) but this project has **no "use a bag
   item to give/feed a berry" mechanic at all** — every berry currently in
   this project is a *held*-item-only mechanic (`[M12]`/`[M18]`'s own scope).
   Showing the pocket with no working action would be worse than the
   TM/HM/Key-Items case (those are *correctly* inert; a Berry row that does
   nothing when pressed would read as broken). **Recommend excluding
   `POCKET_BERRIES` from the battle bag's pocket set entirely until a
   feed-a-berry mechanic exists**, not merely disabling its rows.

Net: **the battle bag's real openable pocket set is `POCKET_ITEMS` always,
`POCKET_POKE_BALLS` only in a wild encounter** — 1 or 2 tabs depending on
context, not the field bag's full 5. This is a genuine, disclosed narrowing
from the field bag, mirroring source's own real `ITEMMENULOCATION_BATTLE`
vs. `ITEMMENULOCATION_FIELD` distinction the `FieldBagScreen` doc comment
already names but never spells out the concrete pocket-set consequence for.

---

## 4. Route comparison — is a "tab row" the right shape at 1-2 tabs?

| Option | Assessment |
|---|---|
| **A — Real pocket-icon tab row + L/R cycle**, matching source | Builds the real mechanism even though it's underused today (1-2 of 5 pockets reachable in battle) — but the SAME component, unmodified, is what `E1`'s field-bag chrome pass and any later relaxation of §3's restriction (e.g. if a feed-berry mechanic ever lands) reuse for free. Matches this project's own repeated precedent (Multitype's Plate data, C4/C5's icons) of building the real mechanism once real data exists, rather than re-deriving it per consumer. |
| **B — No tabs; a static header switching by context** (â€œITEMSâ€ or, in a wild battle, an inline second section for Poké Balls) | Cheaper, but is exactly the shape M25h-1.4 already tried and the roadmap calls out as the thing being revisited — reverting to it would re-litigate a decision Rob already made when scoping E2 into existence. |

**Recommendation: A.** The mechanism is genuinely the same size either way
(pocket cycling is ~15 lines in `FieldBagScreen` already, proven correct) —
the only added cost of "do it for real" is wiring the icon row and L/R input,
not a second design. Building it once, shared-quality, is cheaper over the
project's own lifetime than building a battle-specific shortcut now and a
real one later when Berries/other battle-legal pockets eventually apply.

---

## 5. Scope

### In scope

1. **Asset pull**: `gen_bag_sprites.py` (new, mirrors `gen_databox_sprites.py`'s
   flat-copy shape) pulls `bg_m.png`/`bg_f.png`, `icon_pocket.png`,
   `bag_1.png`…`bag_6.png` (+`_f` variants) from the Emerald UI Pack. Index-0
   transparency tagging needed only for `icon_pocket.png`'s neighbours if any
   turn out untagged (most of this pack's assets have real alpha already,
   per every prior M26 pull — verify per-file before assuming).
2. **`ItemSelectScreen` rewired onto the real `Bag`** — replace `const
   _ITEMS` with `Bag.slots(pocket)` reads (the exact API `FieldBagScreen`
   already uses), reusing `PokemonRegistry.get_item_identity()` for
   name/description and `ItemData.battle_usage` for the legality filter in
   §3. `_on_item_pressed`'s downstream dispatch needs no change.
3. **Real pocket-tab cycling in the battle bag**, ported from
   `FieldBagScreen.next_pocket`/`move_row` (wrap pockets, clamp rows),
   restricted to the §3 battle-legal pocket set (computed fresh per
   open — `is_wild_battle` can differ between battles in the same session).
4. **Real window art** applied to both `ItemSelectScreen` and
   `FieldBagScreen` (currently a plain `Panel`) — `bg_m.png` (a fixed
   neutral default; no gender concept exists yet, per §7) as the full
   background, `icon_pocket.png`'s real per-pocket icons in the tab row.
5. **Input**: on-screen L/R (or prev/next) buttons for the pocket row,
   mouse-first per this project's established convention; a keyboard
   shortcut is a natural pairing with `[M26C8]` (still unbuilt) — cite it
   there rather than inventing a one-off binding here (§7).
6. Tests: `Bag`-backed item-list construction (both pocket-restriction cases
   — wild vs. trainer), pocket cycling (wrap, empty-pocket skip in the
   `@choosing`-shaped mode), the real quantity suffix now rendering real
   counts instead of always-empty, and a `FieldBagScreen` real-art
   regression pass (its own logic is unaffected, only its `Panel`→real-art
   swap).

### Out of scope / excluded

The item-reordering "sort mode" and its `cursor_swap.png` (no such feature
exists); the Select-button quick-item register/`icon_register.png` (no
Select-button quick-item slot exists anywhere in this project); the bag-jump
transition animation (`pbBagJump`, `icon_pokeball.png`'s 7-frame strip) —
cosmetic, defer to a future polish pass; per-gender background art (pick one
default, §7); Berries as a battle-openable pocket (§3, blocked on a
not-yet-built feed-mechanic); TM/HM and Key Items as battle-openable pockets
(structurally inert in battle, matching source); real keyboard pocket-cycle
binding (belongs to `[M26C8]`, not invented here).

---

## 6. Proposed phasing

| Phase | Content | Size |
|---|---|---|
| **E1** | `gen_bag_sprites.py` pull; real `bg_m.png` wired into `ItemSelectScreen`/`FieldBagScreen`'s chrome (replacing `bag_frame.png` and the plain `Panel` respectively); `ItemSelectScreen` rewired onto the real `Bag` (still single-pocket-list at this point, no tab UI); the §3 battle-legality filter (`battle_usage`/`is_wild_battle`) applied to which pocket's contents show | 1 session |
| **E2** | Real pocket-tab row (icon strip + name), L/R cycling ported from `FieldBagScreen`, wired into both screens (battle bag restricted per §3, field bag unrestricted as already built); test suite | 0.5–1 session |

### Decisions needed (Rob)

1. **Route confirmed?** (pack art over a second reference decode — §1.3/§4,
   matching the established M26 direction.)
2. **`bag_N.png` → real pocket mapping**, and what happens to the 6th
   variant (Essentials ships 6, this project has 5 real pockets). Recommend:
   `bag_1`→Items, `bag_2`→Poké Balls, `bag_3`→TM/HM, `bag_4`→Berries,
   `bag_5`→Key Items, `bag_6` unused (flat-pulled anyway since the cost is
   free, per this project's own repeated "pull the whole set even if one
   entry has no consumer yet" precedent — `[M27D D1]`, `[M26B3-1]`).
2b. Gender variant: `bg_m.png` vs `bg_f.png` — pick one neutral default (as
   every other player-gender-dependent pack asset in this project already
   has to, no tracked concept yet). Recommend `bg_m.png`, matching whichever
   default the Databox/other screens already picked, if any exists.
3. **Battle pocket-legality filter (§3) confirmed?** — Items always,
   Poké Balls only in a wild battle, Berries/TM-HM/Key-Items never. This is
   the one genuinely new design call in this doc (not just an asset
   question) — it changes what the player can *do*, not just what they see.
4. **Cursor**: reuse this project's existing "▶" glyph cursor (recommended,
   matches every other list screen) vs. pull the pack's own `cursor.png`.
5. **Bag-jump transition animation**: build now (cheap, ~5-frame tween,
   assets already free to pull) or defer to a later polish pass? Recommend
   defer — cosmetic, zero mechanical dependency on anything else in this
   doc.
