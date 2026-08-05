# M26E3 recon — Party/Switch screen: reference review, current state, route comparison, and scope

Written 2026-07-29. Recon only — no code written, no assets pulled this session.

M26E3 (was M26g) was "to be scoped when reached." This document is that scoping pass. It
also evaluates, per Rob's direction, three implementation routes: (A) direct pulls from
the GBA source, (B) the vendored Emerald UI Pack, (C) a Godot-native / alternate-asset
build — with a difficulty comparison and a recommendation.

Reference repo state: pokeemerald-expansion v1.16.2, HEAD `74e40e03…`, clean tree.
Pack state: `assets/Emerald UI Pack 1.2/` (vendored in-project).

---

## 0a. Decisions resolved (Rob, 2026-08-05)

All 5 decisions from §6 answered, matching M26E1/E2's own decisions-first
discipline:

1. **Route B (Emerald UI Pack) confirmed** — panel art, backgrounds, HP/
   glyph overlays, cancel/ball icons all pulled from the pack; mon icons +
   semantics stay reference-derived, as already planned.
2. **Show all six slots**, active and fainted included, with real
   legality-rejection messages for illegal picks — the source-accurate
   option, superseding the current filtered-list behavior. (Full legality-
   message wiring is E3-3's job; E3-1 renders all six slots with the
   correct static per-slot panel state — base/faint — as that specific
   sub-phase's own scope.)
3. **Submenu stubs SUMMARY now**, in both source variants — SHIFT/SUMMARY/
   CANCEL (voluntary) and SEND OUT/SUMMARY/CANCEL (forced) — giving M26E4
   a real hook once it ships. (E3-3's job.)
4. **HP zone thresholds: source's 50%/20%** — already what `_hp_bar_color()`
   implements (`frac > 0.5` / `frac > 0.2`), so this decision requires no
   code change, only confirms the existing function is the one this screen
   keeps using rather than switching to the pack's own slightly different
   ½/¼ zone-band art.
5. **Exclusions list confirmed as-is**: swap-reorder mode + its slide
   animation, eggs, Pokérus, mail, multi-battle layouts + R/L team cycling,
   item-use-from-party (that flow lives in the Bag screen, `[M26E1/E2]`),
   a shiny indicator (deferred — flag, don't build), fonts (M26D1's job),
   D-pad input (M26C8's job, model recorded in §3.2).

---

## 0b. E3-1 — SHIPPED 2026-08-05

Asset pull + static layout rebuild, both real formats, all six party slots
shown.

**`scripts/gen_party_screen_sprites.py`** pulls all 30 real files from
`Graphics/UI/Party/` into `assets/sprites/battle_ui/party/` — 7 states each
for `panel_round`/`panel_rect` (base/sel/faint/faint_sel/swap/swap_sel/
swap_sel2), `panel_blank`, the singles/doubles full-screen backgrounds, the
4-file HP kit, 3 glyph files, and 6 icon files. A plain flat copy — every
file already carries a real tRNS chunk PIL resolves via `.convert("RGBA")`,
confirmed per-file rather than assumed; `bg.PNG`/`bg_double.png`/`overlay_
hp.png` are the one genuine exception (no tRNS at all — correctly opaque,
not a gap). `statuses.png`/`shiny.png` deliberately NOT pulled (§0a
decision 5 and the recon's own §5 exclusions — this project already has an
equivalent, already-tested status-icon sheet, and the shiny indicator is
explicitly deferred).

**Real doubles coordinates measured directly**, since — unlike singles,
which `004_Party.rb` gives outright (`panel_round.png` at (18,62);
`panel_rect.png` at (222, 30/90/150/210/270), 60px pitch) — the doubles
layout logic lives in base Essentials, absent from this pack. A border-
color pixel scan of `bg_double.png` (same method applied to `bg.PNG` for
cross-check) found 2 round-panel row-runs at y≈64-157/188-281 and 4
rect-row runs at y≈52-275, all sharing singles' own x/width — a clean 60px
row pitch and a 124px round-panel-to-round-panel pitch (98px panel height
+ 26px gap), internally consistent with the singles measurement using the
identical method.

**`switch_select_screen.gd` rewritten** from the old single-flat-row list
(filtering active/fainted members out entirely) into the real format-
dependent shape: singles = 1 round active panel + 5 rect bench rows;
doubles = 2 round panels + 4 rect rows. **All six party slots are now
shown** (§0a decision 2) — active member(s) render in the round panel(s),
every other member gets a bench row in the correct real panel STATE
(`base` or `faint`), superseding the old filtered-list behavior entirely.

**Scope boundary, disclosed and deliberate**: this is E3-1's own "static
layout" scope, not the full E3 arc. The active round panel(s) and any
fainted bench row are pure VISUALS — no Button, not in the cursor group —
since clicking an illegal slot and getting source's own real rejection
message ("is already in battle!", "has no energy left to battle!") is
E3-3's job. Only a live, non-active, non-fainted bench mon is a real
clickable row, unchanged from this screen's pre-existing selectable-
candidate scope. Mon icons, the HP-tier animation cadence, the selection
bounce, the ball-open cursor marker, the real `overlay_hp_back`/`overlay_
hp` HP-bar compositing, and the panel `_sel` state swap on cursor movement
are ALL explicitly E3-2 ("Dynamics") scope per the recon's own phasing —
this screen keeps its existing plain-text name/level/HP display and the
existing "▶"-prefix cursor convention (M25h-1.3) rather than inventing
approximate pixel offsets for a composite this project doesn't have real
004_Party.rb text/HP-bar coordinates for yet. Status icon + held-item icon
(M25h-4 Part C) are kept UNCHANGED — both already real, already-tested,
purely static per-row displays, so carrying them over is continuity, not
new E3-2 work.

**Confirmed via direct code check, not assumed**: decision 4 (source's
50%/20% HP thresholds) needed no implementation — `_hp_bar_color()` already
uses exactly those thresholds (`frac > 0.5` / `frac > 0.2`), so this
decision only confirms the existing function stays in use rather than
switching to the pack's own slightly different ½/¼ zone-band art.

**A real bug found and fixed via the mandatory screenshot pass, not by any
automated test**: `_style_menu_button()`'s own font size
(`_MENU_BUTTON_FONT_SIZE`, 4× `_FONT_NORMAL_SIZE` = 60) is sized for SHORT
menu labels ("Fight"/"Cancel"/a move name) — applying it unmodified to a
full "Name♂ Lv50   HP 999/999"-shaped row string overflowed well past both
the rect panel's 576px width and the round panel's narrower 312px. Fixed
with a new `_ROW_FONT_SIZE := 30` (an exact 2× multiple of `_FONT_NORMAL_
SIZE`, preserving the standing "menu font size must be an exact integer
multiple" invariant), applied on top of `_style_menu_button`'s own call for
bench-row Buttons and directly for the round-panel/fainted-row Labels.
Re-verified via a second screenshot pass: no overflow in either format.

**Held-item icon note**: `_add_slot_overlays` (renamed from the old per-row
`_build_mon_row`'s inline logic, factored out so both the round panel and
bench rows share one implementation) repositions the status/held-item
icons to each slot's own top-right corner rather than the old fixed
fractional-anchor position, since slot widths now genuinely differ between
the round panel (312px) and rect rows (576px).

New/updated tests: `party_screen_sprite_smoke_test.gd`/`.tscn` (99/99) —
directory scan against the generator's own fixed 30-file list, real
per-file dimensions, and the opaque-vs-real-alpha transparency check for
all 3 genuinely-opaque files plus a real-alpha discriminator.
`switch_select_screen_test.gd` grown from 20 to 51 assertions: Test O
rewritten (the retired HP-tint `ColorRect` check replaced with a real
current/max HP-fraction text check), Test P rewritten (the old "active/
fainted excluded" assumption replaced with "all six slots shown, but only
live bench is clickable" — a real architecture-change-invalidates-a-stale-
assumption case, matching this project's own established precedent), Test
Q rewritten (checks the new pack assets this screen actually consumes,
not the retired M25h-4 decoded tilemap files), and 2 new tests (Section
U/V) confirming the format-dependent shape directly (singles: 5 bench
buttons + Cancel, `party_bg_singles.png`; doubles: 4 bench buttons +
Cancel, `party_bg_doubles.png`, exercised via a bare `BattleScreenShared`
with `_opp_panels` set to 2 entries to trigger `_is_doubles()`'s own real
derivation).

Real non-headless screenshot verification (singles + doubles, a disposable
scratch driver deleted after): both real backgrounds render correctly
behind the panel layout; blue "base" panel art for healthy mons, orange
"faint" panel art for the fainted one; status icons (poison/burn) and the
held-item icon visible in each row's own top-right corner; the "▶" cursor
correctly on the first clickable bench row in both formats; Cancel
correctly positioned below the bench list; all text fits within its own
panel after the font-size fix, with no overflow in either format.

Two full regression sweeps: 209 files, GRAND TOTAL 29635 both times
(byte-identical), 0 failures.

E3-2 (dynamics: mon icons, HP-tier cadence, selection bounce, ball/status/
item overlays, real HP-bar compositing, the `_sel` selection state
machine) and E3-3 (action submenu, legality messages, full-roster
rejection flow, forced/voluntary paths re-verified, test-suite rewrite)
remain open.

---

## 0. TL;DR

1. The reference party screen is an 8,620-line, 428-function system, but most of that is
   field-mode freight (items, mail, moves, daycare, contests). The in-battle slice —
   layout, slot states, icons, submenu, legality messages, forced-replacement — is a
   bounded fraction, and its semantics are ALREADY mostly ported (M25h-1.5/M25h-4 got the
   flow, cancel rules, status-row mapping, and HP-bar-equivalent right).
2. What's missing is visual and structural: the current screen is a flat generic-frame
   row list with **no active-mon panel, no doubles-vs-singles distinction, no mon icons,
   no ball markers, no selection/fainted panel states** — and it *hides* active/fainted
   mons instead of showing them with legality messages like source does.
3. **Route B (Emerald UI Pack) wins the comparison decisively** (§4): the pack ships
   every panel in all 7 interaction states as flat separate PNGs, full-screen singles AND
   doubles mockups at exactly 2× the project canvas, and — uniquely among all pack pulls
   so far — its own assembly recipe with complete coordinates (`004_Party.rb`), which
   M26B2's backgrounds never had. Route A would mean re-implementing a 6-palette-bank
   recolor state machine as pre-baked decode variants for art that is visibly inferior
   anyway; Route C would break M26's whole authenticity mandate for little effort saved.
4. Two corrections to the 2026-07-25 roadmap finding are now source-verified (§3.1): the
   singles top-left box is the **active mon's own large panel** (Essentials draws slot 0
   round-left, bench rect-right), NOT a submenu; the doubles "two stacked boxes = 2 field
   slots" guess was correct.
5. The project already has all 386 two-frame mon icons pulled (`gen_pokemon_sprites.py`,
   zero consumers) and the reference's HP-tier icon animation cadence is documented here
   (§2.4) — icons are nearly free.
6. Proposed phasing: E3-1 assets+static layout, E3-2 dynamic slot states + icons, E3-3
   submenu/messages/full-roster display — ~3-4 sessions total (§6). Summary action stubs
   until M26E4 exists; swap-reorder animation and eggs are excluded.

---

## 1. Reference review — the party screen as battle UI

Full detail lives in the agent survey this section condenses; citations are to
pokeemerald-expansion.

### 1.1 Layout

Three window layouts matter here (`src/data/party_menu.h:160-362`, coordinates in
8px tiles on a 240×160 canvas):

- **SINGLE**: slot 0 = large left panel (8,24, 80×56px); slots 1-5 = wide rows
  (96,y, 144×24px) at 24px pitch; message bar at (8,120, 224×32).
- **DOUBLE**: TWO large left panels (both active mons: (8,8) and (8,64)), only 4 wide
  rows. **A genuinely different shape, not a reflow** — the distinction the current
  screen lacks.
- **MULTI** variants exist (partner interleave, R/L team cycling) — out of scope; this
  project has no multi-trainer battles.

Panel interiors (`sPartyBoxInfoRects`): nickname, Lv (suppressed when a status icon
occupies the space), gender glyph, HP `xx/yy`, a 48px 2-row HP bar drawn as direct
pixel fills, and a description-text rect. Slot 0 vs bench have different internal
coordinate sets. CANCEL is a bottom-right button window + small pokéball sprite; the
persistent prompt ("Choose a POKéMON.") is its own message window.

### 1.2 Slot state machine

Each slot window owns a palette bank; state = rewriting 6 palette entries
(`LoadPartyBoxPalette`, `src/party_menu.c:2505-2580`). Dispatch order (first match
wins): empty → softboil-pending → switching → swap-pending → **fainted** →
partner-alt → **selected** → normal. Plus HP-bar green/yellow/red entries
(>50% / >20% / >0, `GetHPBarLevel`) and gender-color entries. The GBA needs palette
tricks for this; any Godot route just needs N pre-baked panel variants or tints.

### 1.3 Per-slot sprites (4 each)

- **Mon icon**: 32×64 sheet = two 32×32 frames per species; **frame rate is a function
  of HP fraction** — 5 anim tiers with delays 6/8/14/22/29 frames, the slowest tier
  repeating frame 0 (a dying icon stops flipping) (`src/pokemon_icon.c:48-92`).
  **Selection bounce**: the selected icon bobs y2 = −3/+1 synchronized to its own
  frame flips (`SpriteCB_BouncePartyMonIcon`); unselected icons sit offset −4px and
  just animate. There is **no cursor sprite at all** — "the cursor" is palette
  highlight + open pokéball + bouncing icon.
- **Pokéball backdrop**: 32×32, closed(0)/open(1) anims — open marks the cursor slot.
- **Status icon**: 32×8 frames in order PSN/PRZ/SLP/FRZ/BRN/PKRS/**FNT**/FRB; hidden
  for none/PKRS.
- **Held-item marker**: 8×8, item/mail frames.

### 1.4 In-battle flow (semantics — mostly already ported)

`PARTY_ACTION_*` cases: CHOOSE_MON (voluntary), SEND_OUT (forced, cancel plays failure
SE and does nothing), CANT_SWITCH (trapped), ABILITY_PREVENTS. Picking a mon opens the
**action submenu** bottom-right (grows upward): SHIFT/SUMMARY/CANCEL (voluntary) or
SEND OUT/SUMMARY/CANCEL (forced); Arena/egg edge cases collapse to SUMMARY-only.
`TrySwitchInPokemon` (`src/party_menu.c:7526-7593`) is the legality gauntlet, in order:
ally's mon → **"{mon} has no energy left to battle!"** → **"{mon} is already in
battle!"** → egg → partner-already-picked → "{mon}'s {ability} prevents switching!" →
"{mon} can't be switched out!". **Source SHOWS every slot — active and fainted included
— and rejects with messages**; it never filters the list. Doubles: both active mons
occupy the two large panels; picking either → "already in battle!".

### 1.5 Animations beyond icons

Screen fade in/out from black; HP drain/fill at 1 HP per frame on item use; the
swap-mode slide (party reorder — field feature); multi-partner slide-in. No affine
entrance.

### 1.6 Scale

`src/party_menu.c` 8,620 lines / 428 functions / 87 tasks / 27 cursor callbacks; max 8
windows + 26 sprites live. The battle-relevant slice: ~1 layout system, ~7 slot states,
4 sprites/slot, 1 submenu, 7 legality messages, 4 PARTY_ACTION cases.

---

## 2. Current-state review (Godot side)

`scenes/battle/switch_select_screen.gd` (394 lines; the `.tscn` is an 8-line stub —
everything is code-built). A full-viewport overlay on the live battle screen (scene-swap
would free `BattleManager`). What it does right, verified against source in M25h-1.5/h-4:
forced-replacement can't-cancel behavior (no Cancel button + inert ESC), the real header
string, status-icon row mapping mirroring `GetMonAilment`, the disclosed HP-bar
equivalent (a `ColorRect` tint over the measured fill rect of the decoded slot art),
held-item marker, and the M25a zero-candidate hardlock guard. 43-assertion test suite.

Structural/visual gaps vs reference:

| Reference | Current |
|---|---|
| Slot 0 large active panel + bench rows; doubles = 2 large panels + 4 rows | One flat row list, same in all formats; no active panel at all |
| All 6 slots shown; illegal picks rejected with messages | **Active and fainted mons filtered out of the list entirely** |
| Mon icon (HP-tier animated, selection bounce) + ball + status + item per slot | No icon, no ball; status + item only |
| 7 panel states (selected/fainted/swap/…) | None (fainted-dim helper exists but is uncalled — no fainted row can exist) |
| Action submenu (Shift/Summary/Cancel) | Direct pick, no submenu |
| Legality messages | None (illegal rows simply absent) |
| Full-screen party background | Dark ColorRect + generic decoded frame |

Assets on hand: M25h-4's decoded `party_frame.png` (240×192) + `party_slot_wide.png`
(144×24) + `party_status_icons.png` + `party_hold_icons.png`; **386 mon icons at
`assets/sprites/pokemon/icon/` (32×64, 2-frame) with zero consumers** (`sprite_registry.gd:19`
comments `get_icon()` "deliberately NOT built"); M26B5's pack-sourced ball icons.

Test debt if reworked: ≥5 of the 20 tests assert the current architecture (asset
dimensions, ColorRect HP bar, 32×64 status sheet, modulate-dim helper) and will need
rewriting — the expected pattern, per M25h-4's own precedent.

---

## 3. The Emerald UI Pack's party kit

### 3.1 Corrections to the 2026-07-25 finding (now verified from `004_Party.rb`)

- The singles top-left box is **the active (index 0) mon's own panel** —
  `panel_round.png` (156×98) at (18,62); bench = `panel_rect.png` (288×48) at
  (222, 30/90/150/210/270), 60px pitch. NOT a submenu.
- The doubles guess was right: `bg_double.png` has 2 round outlines (left column) + 4
  rect outlines — confirmed by pixel scan.

### 3.2 What the pack ships (complete, `Graphics/UI/Party/`, 24 PNGs + shared)

- **Panels in all 7 states each**: `panel_round*` and `panel_rect*` ×
  {base, sel, faint, faint_sel, swap, swap_sel, swap_sel2} — **the reference's palette
  state machine, pre-baked as flat files**. `panel_blank.png` (1×1 transparent) lets the
  bg's own empty-slot outline show through.
- **Full-screen mockups**: `bg.PNG` (singles) and `bg_double.png` (doubles), both
  512×384 = **exactly 2× the project's 1024×768 canvas** (the very reason M26A1 chose
  that resolution).
- **HP kit**: `overlay_hp.png` = 3 stacked 96×8 zone bands (green/yellow/red, indexed
  `hpzone*8`); `overlay_hp_back*.png` troughs (normal/faint/swap) with the "HP" label
  baked in. Ruby's fill rule: width = hp-fraction of bar width, min 1, **rounded to
  2px**; zone 1 at ≤½, zone 2 at ≤¼ (thresholds differ slightly from source's
  50%/20% — a disclosed pack-vs-source delta to pick one of).
- **Glyphs/chrome**: `overlay_lv`, `overlay_male/female`, `icon_ball(_sel)` slot
  markers, `icon_cancel(_sel)`, `icon_item/mail`; shared `statuses.png` (44×112, 7
  frames incl. FNT wide-frame) and `shiny.png` (14×16).
- **The assembly recipe**: `Plugins/Emerald UI Pack/004_Party.rb` (359 lines) — every
  element's coordinates, active-vs-bench offset tables, z-order, text colors
  (shadow (112,112,112), small font), the 2-column D-pad navigation model (recorded
  for M26C8), and the swap slide animation timing. **No prior pack pull had its
  coordinates; M26B2 had to approximate positions. E3 does not.**
- **Not in the pack**: mon icons and held-item item-art (Essentials-engine assets) —
  both already pulled in-project from the reference; fonts (none in pack — M26D1's
  Essentials-pack TTF question is unchanged); the doubles bg selection logic (lives in
  base Essentials; our pixel scan of `bg_double.png` supplies the doubles coordinates).

---

## 4. Route comparison — source pull vs Emerald UI Pack vs Godot-native

| Dimension | A: Direct source decode | B: Emerald UI Pack | C: Godot-native / alt. free assets |
|---|---|---|---|
| Panel art | Decode `bg.png` tiles through `slot_main.bin`/`slot_wide.bin` (already done for 2 pieces in M25h-4) | Flat copy, 14 panel files | StyleBoxFlat / nine-patch, invented |
| Slot states (7) | **Must re-implement the palette-bank recolor**: decode each state by rewriting 6 palette entries per `sPartyBox*PalIds` before rendering → gen-script pre-bakes ~7 variants per panel type; fiddly, error-prone | **Already pre-baked as separate files** — zero work beyond copying | Modulate tints; trivial but reads as programmer-art |
| Doubles layout | Window-template tables give tile coords (documented §1.1) — usable | `bg_double.png` + pixel-scanned outline coords — usable | Invented |
| Full-screen background | `bg.bin` tilemap decode (2048B, format already handled) | `bg.PNG`/`bg_double.png` flat | ColorRect/gradient |
| HP bar | 2-row pixel-fill + 3 palette pairs → re-bake as colors (current ColorRect approach already approximates this) | Zone-strip + trough overlays, flat files, Ruby fill rule | Godot ProgressBar |
| Mon icons | Reference icons **already pulled** (386 files) — identical for all routes | same | same |
| Coordinates | Tile-unit tables, need px conversion + scale mapping to 1024×768 (240×160 source is 3:2 — does not divide the 4:3 canvas evenly; every position needs re-anchoring, the exact re-fitting M26A1 chose the pack canvas to avoid) | **`004_Party.rb` gives px coordinates at exactly 2× canvas scale** | Free choice |
| Canvas fit | 240×160 → 4.8×/4.27× non-integer, or 4× letterboxed panel | 512×384 → clean 2× | native |
| Precedent | M25h-4 (superseded direction) | **M26B1/B2/B5: the established M26 direction** — roadmap explicitly frames E3 as "swapping decode-derived art for pack-sourced flat art" | none; contradicts M26's mandate |
| Style coherence | GBA-authentic but clashes with the pack-styled battle screens shipped by M26B1/B2 | Matches every M26 screen shipped so far | Third style, clashes with both |
| Est. asset/layout effort | ~2 sessions (state-baking + re-anchoring dominate) | **~0.5-1 session** (gen script + coordinates transcription) | ~0.5 session, then perpetual "looks wrong" debt |
| What it can't give | Nothing missing, just slower | Nothing needed is missing | Authenticity |

**Recommendation: Route B**, with two reference-sourced carve-outs that all routes share
anyway: (1) mon icons + the HP-tier animation cadence and selection bounce (§1.3 —
behavior from source, sprites already pulled); (2) all *semantics* — legality gauntlet
order, messages, forced-replacement rules, submenu structure — stay source-derived as
they already are. Route A is kept only as the documented fallback if a pack piece turns
out structurally unusable (none identified). Route C is rejected: it saves at most a
session and spends it forever in style debt against a milestone whose whole mandate is
replacing invented chrome with real art.

---

## 5. Scope

### In scope

1. **Layout rework**: full-screen party view (still an overlay for engine-lifetime
   reasons) — singles: round active panel + 5 rect bench rows; doubles: 2 round + 4
   rect; `bg`/`bg_double` full-screen backdrops; CANCEL plate; prompt bar.
2. **Show all six slots** (design change from the current filtered list): active and
   fainted mons render with their real panel states; illegal picks rejected with
   source's messages ("is already in battle!", "has no energy left to battle!",
   ability-trap and trapped variants — wire the two trap cases to the existing
   `is_trapped()` seam from M17f).
3. **Per-slot dynamics**: mon icon (2-frame, HP-tier cadence 6/8/14/22/29, selected
   bounce −3/+1 on frame flip), ball marker (sel/normal), status icon (reuse existing
   sheet or pack `statuses.png` — pick one, they encode the same rows), held-item
   marker, HP bar via pack overlays with zone thresholds (decision: pack ½/¼ vs source
   50%/20%), gender glyph, Lv glyph + level, name, HP text.
4. **Selection model**: panel `_sel` swap + ball-open + icon bounce as the cursor
   (source has no cursor sprite); mouse now, 2-column D-pad model recorded for M26C8.
5. **Action submenu**: SHIFT/SUMMARY/CANCEL (voluntary), SEND OUT/SUMMARY/CANCEL
   (forced) — SUMMARY present but stubbed/disabled until M26E4 builds the summary
   screen (dependency note: E4's return path re-opens this submenu, per source).
6. **Messages**: the legality set + "Do what with this Pokémon?" prompt swap.
7. Preserve: forced-replacement rules, zero-candidate hardlock guard, field_slot
   threading, `mon_chosen`/`cancelled` signal contract (unchanged consumers).
8. Test rework: rewrite the ~5 architecture-bound assertions; add state-matrix and
   legality-message coverage.

### Out of scope / excluded

Swap-reorder mode + its slide animation (field feature; sim party order is
battle-managed), eggs, Pokérus, mail, multi-battle layouts and R/L team cycling,
Softboiled/item-use-from-party (item flow lives in the bag screen), shiny indicator
(defer until the sim has a shiny concept — flag, don't build), fonts (M26D1 owns),
D-pad input (M26C8 owns, model recorded), audio (M26 standing rule).

---

## 6. Proposed phasing

| Phase | Content | Size |
|---|---|---|
| **E3-1** | `gen_party_screen_sprites.py` (pack pull: panels ×14, bg ×2, overlays, glyphs, cancel/ball icons; smoke test) + static layout rebuild at `004_Party.rb` coordinates ×2, singles + doubles shapes, all six slots rendered with correct static states | 1 session |
| **E3-2** | Dynamics: mon icons (first consumer of the 386-icon pull — build `SpriteRegistry.get_icon()`), HP-tier cadence + selection bounce, ball/status/item overlays, HP bar overlays, selection state machine | 1 session |
| **E3-3** | Action submenu + legality messages + full-roster rejection flow + forced/voluntary paths re-verified + test-suite rewrite | 1 session |
| (E3-4) | Optional polish: screen fade in/out, HP drain-on-heal hook (only if in-battle heal-from-party lands), deferred until M26G2's pacing pass otherwise | — |

### Decisions needed (Rob)

1. **Route B confirmed?** (pack art + source semantics + reference icons)
2. **Show-all-six-slots** with legality rejection (recommended, source-accurate) vs
   keeping the current filtered list.
3. **Submenu** with stubbed SUMMARY now (recommended — matches source, gives E4 its
   hook) vs direct-pick-until-E4.
4. HP zone thresholds: pack's ½/¼ or source's 50%/20% (recommend source's — it's what
   the in-battle HP bars already use via `_hp_bar_color`).
5. Confirm exclusions list (§5), notably swap-reorder and shiny.
