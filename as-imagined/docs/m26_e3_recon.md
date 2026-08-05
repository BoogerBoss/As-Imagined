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

## 0c. E3-2 "Dynamics" — SHIPPED 2026-08-05

**A real correction to this doc's own §1.3, found by this session's own Step 0 —
not silently absorbed.** §1.3 claimed the mon icon's 5-tier `sMonIconAnims[]`
speed array (`src/pokemon_icon.c:48-92`, delays 6/8/14/22/29 GBA frames,
confirmed real) is selected by HP fraction. It is not, for the party-menu/
in-battle icon context: a full search of every `StartSpriteAnim` call
touching a party-menu mon-icon sprite (`party_menu.c`) found none of them
ever choosing anything but tier 0 (the default `animNum`) — there is no
HP-fraction-driven tier-selection call anywhere in this reference tree for
this context. Every icon here therefore animates at the one real, confirmed
tier-0 cadence (6-frame delay, i.e. `6/60` seconds) rather than a fictitious
HP-tiered one. The recon's own §1.3 line is left as originally written per
this project's no-retroactive-edit convention; this section is the correction
record.

**Real per-species mon icons** — the 386-icon pull's first consumer.
New `SpriteRegistry.get_icon(dex, frame) -> Texture2D` mirrors `get_front()`'s
exact frame-slicing shape (a 32×64 2-frame vertical sheet, frame 0/1 sliced
via `AtlasTexture`); confirmed via direct pixel inspection that all 386 icon
files are uniformly 32×64 with no single-frame exception (unlike `get_front`'s
own Unown/Castform carve-out). Icons render at 2× (64×64 on-screen), centered
at the real `004_Party.rb` `refresh_pokemon_icon` offsets (active:
`self.x+20, self.y+38`; bench: `self.x+8, self.y+26`, both `CENTER`-anchored,
doubled), and animate via one shared `_process()` timer driving every icon in
lockstep — a deliberate simplification over source's independent per-sprite
`animDelayCounter`, behaviorally indistinguishable here since every icon
shares the identical real cadence.

**Selection bounce**, from `SpriteCB_BouncePartyMonIcon`/
`AnimateSelectedPartyIcon`: the currently-selected mon's icon bobs
`y2 = -3/+1` (doubled `-6/+2`) synced to the frame flip; every unselected icon
sits at a fixed `-4px` (doubled `-8px`) offset instead — reproduced as a
y-shift for the round/active panel's icon and an x-shift for bench icons,
matching the two real branches' own differing offset axis.

**The ball-icon cursor marker** — resolves the E3-1 recon's own flagged
discrepancy (§1.3's "32×32 closed/open" GBA-source citation vs. the
44×56 two-file pack pull). Confirmed directly against `004_Party.rb`'s
`refresh_ball_graphic`: the PACK's own real mechanism is a plain two-state
(`sel`/`desel`) `ChangelingSprite` swap, not an animated open/close cursor —
this project follows the pack's real mechanism (Route B, decision 1), not the
raw GBA source's different one. `party_ball_icon.png`/`party_ball_icon_sel.png`
swap on real cursor-driven selection (wired via each mon button's own
`mouse_entered`, alongside — not instead of — the existing `_wire_cursor_group`
"▶"-text mechanism), defaulting to slot 0 selected exactly like the shared
cursor group's own default.

**Real `overlay_hp_back`/`overlay_hp` HP-bar compositing** — a real trough
background (`party_hp_trough.png`/`_faint.png`, per-state) plus a
live-cropped zone-color fill (`party_hp_zones.png`, 3 stacked 8px
green/yellow/red bands, confirmed via direct pixel sample top-to-bottom)
replacing the plain-text-only HP display; the numeric "HP cur/max" text is
KEPT alongside it, matching source's own `draw_hp` (which draws both). Zone
selection uses this project's own already-decided 50%/20% thresholds (§0a
decision 4 — `_hp_bar_color`'s existing thresholds), not the pack's own
slightly different ½/¼ bands, applied to the *same* 3-band asset. Fill width
rounds to the nearest 2 native px, matching `004_Party.rb`'s own
`w = ((w / 2).round) * 2` rule exactly. Trough and fill positions were
confirmed, not guessed, via direct pixel inspection of `party_hp_trough.png`'s
own baked-in "HP" label glyph — the fill's real relative offset
(`(178,16)` bench / `(50,64)` active, from `draw_hp`'s own blit call) sits
cleanly inside the trough's own box, leaving exactly the gap the label
occupies.

**The panel `_sel` state swap** — bench row art now swaps
`panel_rect_base.png` → `panel_rect_sel.png` on real cursor-driven selection
(the active round panel is never selectable in this sub-phase's own scope, so
it never swaps). A new per-button `StyleBoxEmpty` with its own
`content_margin_left` (not the shared static empty-chrome style every other
menu button uses) shifts each row's text clear of the new icon/ball graphics,
which — per the real measured coordinates — sit partly to the LEFT of the
row's own bounding rect by design (matching source's own overlapping
icon+ball-over-row-edge composition, not a layout bug).

**Real, non-headless screenshot verification** (singles + doubles, both a
resting state and a live simulated hover via the real button `mouse_entered`
signal — not a direct internal-function call, so the shared "▶" text cursor,
the ball swap, and the panel `_sel` swap were all confirmed moving together
exactly as they will in real interactive play): icons render correctly
per-species in every slot (active and bench, legal or not); the HP-bar fill
composites correctly at all three zone colors (a 15%-HP mon showing a short
real red/pink fill, a 60%-HP mon full green, a 35%-HP mon yellow, a fainted
mon showing the real faint trough with no fill at all); the ball icon swaps
between its real desel (red/grey) and sel (orange/tan) art on hover; the
bench row's panel art swaps to its real orange-bordered `_sel` state on
hover; and — in doubles — hovering onto Cancel correctly clears every mon's
own visual selection (ball/panel both revert), a real code path this
session's own screenshot pass exercised incidentally.

New tests: `sprite_registry_test.gd` gained `_test_get_icon` (all 386
species' frame 0/1, the real "no dex-0 fallback icon exists" finding, an
invalid-dex negative case) — 5030/5030. `switch_select_screen_test.gd` grew
82 assertions (was 51): one icon entry tracked per slot shown; ball
sel/desel defaults and hover-driven swaps; panel `_sel` swap on hover;
Cancel-hover clearing all mon visual selection; HP-bar trough+fill presence
and correct zone selection (including a fainted row showing no fill); the
real tier-0 animation cadence advancing a live icon's frame over real
elapsed time; and the selection-bounce/fixed-unselected-shift pair, both
before and after a frame flip. One real test-authoring bug was caught and
fixed on the first run — a hardcoded HP literal (`current_hp = 30` against
an assumed `max_hp == 100`) landed in the wrong zone once the real HP
formula's actual `max_hp` (≈160 at level 50) was accounted for, the same
pitfall this file's own Test O already hit once before; fixed by computing
the target fraction from each mon's own real post-construction `max_hp`
rather than a hardcoded literal.

Two full regression sweeps: 210 files, GRAND TOTAL 31613 both times, 0
failures.

---

## 0d. E3-3 "Full roster + legality + submenu" — SHIPPED 2026-08-05

**Step 0, `party_menu.c`'s own `TrySwitchInPokemon` (L7526-7593), read in its
exact real order** — this is the legality gauntlet this sub-phase's own
rejection flow reproduces, not a summary re-derived from memory:

1. Multi-battle partner check (L7538-7543) — N/A, excluded (no multi-battle
   support, §0a decision 5).
2. `GetMonData(HP)==0` (L7544-7549) → `gText_PkmnHasNoEnergy` — "{mon} has no
   energy left to battle!".
3. Already active on this side, looped over battlers (L7550-7560) →
   `gText_PkmnAlreadyInBattle` — "{mon} is already in battle!".
4. Egg check (L7561-7565) — N/A, excluded (no egg concept).
5. `BattlersShareParty(...) && battlePartyId == prevSelectedPartySlot`
   (L7566-7572, doubles-only sibling-already-picked-this-round) →
   `gText_PkmnAlreadySelected` — "{mon} has already been selected.".
6. `gPartyMenu.action == PARTY_ACTION_ABILITY_PREVENTS` (L7573-7577) →
   `SetMonPreventsSwitchingString()`, which names the ABILITY HOLDER/trapper
   (not the trapped mon, not the picked replacement) via
   `gText_PkmnsXPreventsSwitching` (`battle_message.c:74`) — "{trapper} is
   preventing switching out with its {ability} Ability!".
7. `gPartyMenu.action == PARTY_ACTION_CANT_SWITCH` (L7578-7584) →
   `gText_PkmnCantSwitchOut`, naming the currently-ACTIVE (battling) mon, not
   the picked replacement — "{active mon} can't be switched out!".

**Critical real finding**: checks 6/7 are independent of which slot was
picked — they concern the ACTIVE/outgoing mon's own trapped state (ability or
move-based), matching source's own pre-set `gPartyMenu.action` flag set
before the menu even opens. Reproduced here as a single `_rejection_message`
function checked in this exact order against the picked slot, falling
through to the active mon's own trapped-state check only once every
picked-slot-specific reason clears.

**Trapper recovery** — `AbilityManager.is_trapped()` (`[M17f]`) is
deliberately NOT widened to return which ability trapped the mon (too many
existing call sites to risk). A new, small, DELIBERATELY DUPLICATED static
`_find_trapping_opponent()` mirrors just its own ability-loop tail (Shadow
Tag mirror-exemption, Arena Trap grounded-gate, Magnet Pull Steel-gate) to
recover the real trapper for message purposes only.

**Full-roster clickability, superseding E3-1's "only a live bench mon is
clickable" restriction** (§0a decision 2 already called for this; this is
where it lands): every one of the six slots — both active round panel(s) and
every bench row, fainted included — is now a real, clickable, cursor-
selectable `Button`. `_mon_visual_entries` (icon/ball/panel-`_sel` machinery
from E3-2) widened to match; `_build_active_panel`/`_build_bench_row` were
unified into one `_build_slot()` so active and bench rows share one real-art/
button/icon/HP-bar/overlay construction path instead of two divergent ones.

**Default cursor position — a real source finding, not carried over from
E3-1/E3-2**: `004_Party.rb`'s own `pbStartScene` sets `@activecmd = 0` and
selects `@sprites["pokemon0"]` — the ACTIVE mon's own slot, not the first
bench candidate. Reproduced by building the active panel(s) FIRST in the
button/cursor-group array, so cursor index 0 (the shared group's own default)
lands there, a deliberate change from E3-1/E3-2's "first legal bench mon"
default (which predated the active slot's own becoming selectable at all).

**Action submenu — §0a decision 3**: a legal pick opens a real
Shift/Summary/Cancel (voluntary) or Send Out/Summary/Cancel (forced)
submenu instead of immediately emitting `mon_chosen`. Summary is a real,
positioned, `disabled = true` button (the stub M26E4 will later wire up, not
an omitted feature); the submenu's own Cancel returns to the party list
without closing the whole screen (a separate, always-available step from the
screen's own top-level voluntary-only Cancel). The list's slot buttons +
top-level Cancel are disabled while the submenu is open. Pressing Shift/Send
Out closes the submenu and emits `mon_chosen(picked_slot)` — preserving
`battle_screen_shared.gd`'s own existing external contract byte-for-byte;
confirmed and unchanged this session, since every consumer of that signal
still only cares that it eventually fires with the right slot, not when.

**Cancel/ESC behavior, unchanged from E3-1/E3-2, re-verified**: a forced
replacement still has NO top-level Cancel button and ESC is a no-op at the
top level — but ESC now closes an open action submenu first (a new,
always-available step, matching the submenu's own Cancel button, regardless
of voluntary/forced), falling through to the existing top-level behavior only
once no submenu is open.

**`battle_screen_shared.gd` needed zero changes** — confirmed directly:
`_build_switch_buttons`/`_on_switch_screen_mon_chosen`/`_on_switch_pressed`
are all untouched, since every new legality/submenu mechanism lives entirely
inside `switch_select_screen.gd` and the external `mon_chosen(slot)`/
`cancelled()` signal contract is unchanged.

**Test-suite rewrite** — the whole file was rewritten (not patched) to match
the new architecture, since the old E3-1/E3-2-era suite's own button-count/
clickability/default-cursor assumptions were architecturally invalidated by
this session's changes: 82 → 111 assertions. New coverage: exact slot-button
counts in both formats (singles 6 = 1 active + 5 bench, doubles 6 = 2 active
+ 4 bench, both + Cancel); the default cursor landing on the active panel;
all 4 real rejection cases (fainted, already-active, doubles-sibling-already-
selected via a bare `BattleManager` with `_chosen_switch_slots` manually
preset — confirmed safe since `_get_live_opponents`/`_is_neutralizing_gas_
active` both degrade to empty/false against an empty `_combatants` array,
verified by direct source read before relying on it; ability-trapped via a
real end-to-end Shadow Tag battle; move/self-trapped via Ingrain); the full
submenu lifecycle (open-on-legal-pick, correct Shift/Send-Out label per
context, Summary's disabled stub, primary press emits `mon_chosen` and
closes, Cancel press closes without emitting anything and re-enables the
list); ESC's new submenu-first-then-fallback behavior in both directions;
message auto-revert via direct `_process` advancement; and every still-
relevant E3-1/E3-2 test (real pack asset dimensions including the new
`faint_sel` variants, status-icon mapping, held-item icon, the fainted-dim
helper, icon animation, HP-bar zones, ball/panel-`_sel` swap, selection
bounce) re-indexed for the new unified slot layout.

**Real, non-headless screenshot verification** (5 shots via a disposable
scratch driver, deleted after use): singles voluntary list (active Snorlax
selected by default, live Pikachu bench row, fainted Charizard bench row
with its own faint icon/trough, top-level Cancel); the action submenu opened
on a legal pick (Shift/Summary-disabled/Cancel, list disabled behind it); the
rejection message on a fainted-slot pick ("Charizard has no energy left to
battle!", no submenu, list still enabled); the forced-replacement submenu
variant (active panel shown fainted, no top-level Cancel, submenu reads
"Send Out"); and the doubles list (2 round active panels + 2 bench rows +
Cancel). One real test-mon-construction gotcha found and fixed before any
of this was verifiable: test mons need a real move (not zero moves), since a
moveless mon forces Struggle on both sides every turn and `start_battle_
with_parties()`'s own internal `advance()` call then auto-resolves the whole
battle to completion before the screen can ever be reached — not a
production bug, a scratch-driver fixture gap.

Two full regression sweeps: 210 files, GRAND TOTAL 31641 both times, 0
failures.

**M26E3 is now fully shipped — E3-1, E3-2, and E3-3 are all complete.**

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
