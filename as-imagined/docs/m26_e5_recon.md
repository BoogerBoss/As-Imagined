# M26E5 recon — Matchup overlay: design brief, data audit, and scope

Written 2026-07-29. Recon only — no code written this session.

M26E5 (was M26i) was "the one M26 item deliberately left unscoped." **Rob supplied the
design brief on 2026-07-29 (§1), which resolves the open shape question** — it is an
in-battle pull-up overlay, and it is **explicitly a custom expansion screen**: the base
games rely on the player to track this information mentally, and the reference audit
(§2.4) confirms none of it is ever shown numerically in source outside the debug menu.
E5 also owns the absorbed **M26C4 (category icon)** and **M26C5 (type badge)** wire-ups
— both asset-ready with zero consumers; this is the screen that finally hosts them.

Reference: pokeemerald-expansion v1.16.2. Inspiration: the Pokémon Champions battle
overlay (recorded here for the first time in-repo; guidance, not spec, per Rob).

---

## 0. TL;DR

1. **The shape is decided** (Rob, 2026-07-29): a mid-battle pull-up overlay over the
   live battle screen. Player's active mon(s): name, HP, types, held item, ability,
   moves in full detail; opponent's active mon(s): name, types, stat stages only.
   Field strip: weather / Trick Room / Tailwind remaining turns. Stat stages shown as
   **exact multipliers ("2.0x"), not arrows**.
2. **The engine already has everything except read APIs.** Both exact ratio tables are
   already ported (`DamageCalculator.STAGE_RATIOS` = `gStatStageRatios` verbatim;
   `StatusManager.ACCURACY_STAGE_RATIOS` = the expansion's percent table). Every field
   counter exists (`weather_duration`, `trick_room_turns`,
   `_side_conditions[side]["tailwind_turns"/"reflect_turns"/…]`). The F3 debug overlay
   already reads all of them — including via the private-field precedent E5 should
   replace with thin public getters.
3. **Two soft dependencies**: move descriptions (empty on all 717 — E4-1's pipeline;
   the move panel ships without them and fills in when that lands) and the shared
   overlay-helper extraction (E5 is the 4th overlay consumer).
4. **No fog-of-war problem by design**: the engine hides nothing, but the brief shows
   the opponent only what a player legitimately tracks from watching the battle
   (name/types/stages). No reveal-tracking infrastructure needed.
5. ~2-3 sessions across 3 phases (§6). Decisions in §7 — the biggest are the open
   trigger (mouse-first button + which key), the field-strip breadth (Rob named
   weather/TR/tailwind; screens/hazards/Safeguard/Mist are the same read and arguably
   belong), and accuracy/evasion display form.

---

## 1. Design brief (normalized from Rob, 2026-07-29 — "general guidance, not word-for-word")

- **Pull-up overlay, mid-battle, without leaving the battle screen.**
- **Player's active Pokémon**: name, HP, type(s), held item, ability, moves, and
  per-stat buffs/debuffs.
- **Opponent's active Pokémon**: name, type(s), buffs/debuffs only.
- **Field**: remaining turns of weather, Trick Room, Tailwind.
- **A custom screen and an expansion** — surfacing battle data the base game expects
  the player to track mentally.
- From the Champions inspiration: exact stat-stage multipliers ("2.0x") rather than
  arrows, both sides; full move descriptions in-battle with explicit percent chances
  for secondary effects and flags like contact; types for both sides; live conditions
  on the active Pokémon; HP/item/ability/moves **only** for your own side.

## 2. Reference facts

### 2.1 Stat-stage multipliers (regular stats)

`gStatStageRatios` (`src/pokemon.c:505`): −6→0.25x, −5→0.286x, −4→0.333x, −3→0.40x,
−2→0.50x, −1→0.667x, 0→1.0x, +1→1.5x, +2→2.0x, +3→2.5x, +4→3.0x, +5→3.5x, +6→4.0x.
Integer pairs {num,den}; **already ported verbatim** as
`DamageCalculator.STAGE_RATIOS` (`damage_calculator.gd:38-53`), applied by
`_apply_stage()` (`:844`). Display rule: `stage → STAGE_RATIOS[stage+6]` rendered as
`%.2fx` (or the fraction). Crits/Unaware/ignore-flags zero stages in damage — the
overlay shows the raw stage multiplier, which is what the player is tracking.

### 2.2 Accuracy/evasion

The expansion uses a percent table (`gAccuracyStageRatios`,
`battle_script_commands.c:825`: 0.33/0.36/0.43/0.50/0.60/0.75/1.0/1.33/1.66/2.0/2.33/
2.66/3.0) indexed by the **combined** stage `acc − eva`, clamped ±6 — already ported
as `StatusManager.ACCURACY_STAGE_RATIOS` (`status_manager.gd:737-756`). There is no
per-mon accuracy multiplier in the mechanics; only the matchup difference is real.
Display options in §7.

### 2.3 Field counters (source semantics, for label accuracy)

Weather 5 turns (8 with rock, 0=primal/perpetual — this project models primal as
non-permanent, disclosed gap); Trick/Wonder/Magic Room 5; Tailwind 4 (Gen5+);
Reflect/Light Screen/Aurora Veil 8 with Light Clay else 5; Safeguard/Mist/Lucky Chant
5. Source never displays any of these numbers; they exist only as
`gBattleStruct->weatherDuration` / `gFieldTimers` / `gSideTimers`.

### 2.4 Info-visibility conventions (why this is an expansion)

Opponent stat stages are never shown numerically in normal play (only the debug menu
renders them); ability reveals happen via the ability popup, item reveals via
Frisk/Thief message text; timers are never displayed. The brief's opponent panel
(name/types/stages) matches what an attentive player already knows from messages and
animations — the overlay removes bookkeeping, not information asymmetry.

### 2.5 Move info data shapes

Source: `struct AdditionalEffect.chance` (0 = certain/primary), `makesContact` plus
the flag word (sound/punch/bite/pulse/ballistic/powder/dance/wind/slicing…),
2-line `description`. Engine (`move_data.gd`): `secondary_effect`/`secondary_chance`
(0 = guaranteed), `secondary_effect_2`/`_chance_2`, stat-change secondaries reuse
`secondary_chance` via `stat_change_stat/_amount/_self`, **`makes_contact`** plus the
same flag family, `priority`, `critical_hit_stage`, target constants (spread derived
from `TARGET_BOTH` etc.), recoil/drain percents. **`description` empty on all 717
moves** — E4-1's pipeline fills it.

## 3. Engine audit — available vs. needed

**Readable today** (all verified): `stat_stages[7]` per mon (indices ATK/DEF/SPATK/
SPDEF/SPEED/ACC/EVA); `weather`, `weather_duration`, `trick_room_turns` (public on
BattleManager); `_side_conditions[side]` dict (**private**) carrying
`tailwind_turns`, `reflect_turns`, `light_screen_turns`, `aurora_veil_turns`,
`safeguard_turns`, `mist_turns`, `spikes_layers`, `toxic_spikes_layers`,
`stealth_rock`, `sticky_web`; ability/held item/moves/PP as plain fields; actives via
`BattleParty.get_active_at(slot)` / `num_active()` for the doubles case.

**Gaps, all small:**
1. **No public read API for side conditions** — the F3 overlay reads
   `_bm._side_conditions[...]` directly (`battle_screen_shared.gd:3173`). E5 should
   add thin getters instead of a third private read: `get_side_condition_turns(side,
   name)` (+ optionally a `get_field_state()` snapshot dict). No new signals needed —
   the overlay reads state when opened/refreshed; `weather_continues` already pulses
   per turn if a live-update hook is wanted.
2. **No multiplier API** — trivial: render from `STAGE_RATIOS`. (Note the tables are
   underscore-static but already called cross-class; a tiny display helper avoids
   widening private surface.)
3. **Type-id → badge-filename mapping doesn't exist** (`fight.png` vs
   `TYPE_FIGHTING`) — the C5 wire-up builds it once, shared with any future consumer.
4. Move descriptions — E4-1 (soft dependency; panel degrades to name/type/category/
   PP/power/acc/chance/contact until then).

## 4. UI review — what E5 builds on

- **F3 debug overlay is the working precedent** for a full-screen toggle overlay:
  top-level Control drawn last, `Color(0,0,0,0.85)` backdrop, raw-keycode
  `_unhandled_input` toggle (no InputMap exists project-wide), and its field-state
  handlers already read every counter E5 needs. E5 is the *player-facing* sibling:
  curated, styled, current-state (the debug view is a historian; E5 is a dashboard).
- **Overlay pattern**: 4th consumer of the item/switch/(E4 summary) child-overlay
  architecture — do the planned shared-helper extraction here or in E4, whichever
  lands first.
- **C4/C5 assets**: category icons 16×16 RGBA (reference-pulled;
  the old `MoveInfoCategory` helper was deleted and gets re-created here), type
  badges 32×16 indexed (18 real types). Both zero-consumer; E5 is their owner per the
  2026-07-27 absorption.
- **Chrome**: `text_window/1.png` panel art + `_style_menu_button`/`_strip_button_chrome`
  + `_font_menu` conventions; `_hp_bar_color` thresholds for the HP readout;
  `_mon_label` "Your X"/"Foe X" naming.
- **Doubles**: overlay must handle up to 2 actives per side; sides share one
  `_side_conditions` entry (Tailwind/screens are per-side, correct as-is).

## 5. Scope

### In scope

1. **`MatchupOverlay`** child overlay on the live battle screen, mouse-first trigger
   (an always-visible small button/tab in the battle UI) plus a keyboard toggle;
   closes via the same button/ESC. Openable during the command phase at minimum
   (§7 decision on broader availability). Pack/window-art styled, F3-style dark
   backdrop, distinct from the debug overlay (which stays as-is).
2. **Player panel** (per active mon; two columns in doubles): name, HP `cur/max` +
   bar, type badges (C5 wire-up), held item name, ability name (+ its populated
   description), and the 4 moves — each row: name, type badge, category icon (C4
   wire-up), PP `cur/max`, power/accuracy, secondary-effect chance rendered as an
   explicit % ("100%" when `secondary_chance == 0` and an effect exists; "—" when
   none), contact flag, and the description line once E4-1 lands.
3. **Stat-stage table, both sides**: exact multipliers from `STAGE_RATIOS`
   ("2.0x"), stage count alongside ("+2"), up/down color convention shared with E4's
   nature coloring (red up / blue blue); Atk/Def/SpA/SpD/Spe + Acc/Eva (display form
   per §7).
4. **Opponent panel** (per active mon): name, type badges, stat-stage table only —
   no HP numbers, item, ability, or moves, per the brief (the on-stage HP bar remains
   visible anyway).
5. **Field strip**: weather name + turns remaining, Trick Room turns, Tailwind turns
   per side — plus (pending §7) screens/Safeguard/Mist turns and hazard layers, which
   are the same read and the same player-bookkeeping burden.
6. **Engine seams**: `get_side_condition_turns(side, name)` (+ optional snapshot
   getter), migrating the F3 overlay's private read to it; the type-badge mapping
   helper; a stage→multiplier display helper.
7. Tests: seam unit tests, multiplier rendering table test, overlay build/toggle
   tests, doubles layout test, smoke coverage for the newly-wired C4/C5 assets.

### Out of scope

Type-effectiveness calculator/comparison grid (a possible later E5 extension — the
original E5 sentence mentioned "type-matchup info"; Rob's brief supersedes with the
Champions-style state overlay; effectiveness hints can be a follow-up decision),
reveal-tracking/fog-of-war infrastructure, opponent held-item/ability display, the
debug overlay (unchanged), D-pad navigation (M26C8), audio, move descriptions
pipeline itself (E4-1 owns it).

## 6. Phasing

| Phase | Content | Size |
|---|---|---|
| **E5-1** | Engine getters + overlay skeleton + trigger button/key + field strip + type-badge mapping helper (C5 lands) | 1 session |
| **E5-2** | Player panel with full move rows (category icons — C4 lands) + stat-stage tables both sides + multiplier rendering | 1 session |
| **E5-3** | Doubles layout, opponent panel polish, description wiring (if E4-1 has landed), test suite, F3-read migration | 0.5-1 session |

Sequencing note: E5 has no hard dependency on E3/E4 — only the soft E4-1 description
dependency. It can land before or after them; if before, it should still do the
shared-overlay-helper extraction.

## 7. Decisions needed (Rob)

1. **Trigger**: which on-screen affordance (small "INFO" tab near the action region
   is the recommendation) and which key (TAB recommended; F3 is taken, no InputMap
   convention exists yet).
2. **Availability**: command phase only (simplest, recommended first cut) vs.
   any-time including mid-animation (needs a refresh-on-beat hook).
3. **Field strip breadth**: Rob's three (weather/TR/Tailwind) only, or also
   screens/Safeguard/Mist turns + hazard layers (recommended — same read, same
   mental-tracking burden; they were named in the engine's own side-condition set).
4. **Accuracy/evasion display**: (a) stages only ("+1/−2"), (b) per-mon multiplier
   from the accuracy table applied to the mon's own stage (labeled approximate,
   since mechanics only use the matchup difference), or (c) the live combined
   attacker-vs-target value. Recommend (a) for truthfulness, given (c) needs a
   selected target to be meaningful.
5. **Opponent HP**: confirm omitted (brief says name/type/stages only; the stage HP
   bar already shows it visually).
6. **Type-effectiveness hints** (your moves' effectiveness vs the current opponent):
   in-scope extension or explicitly deferred? (Deferred recommended for the first
   cut; the data — `TypeChart.get_effectiveness` — is trivially available later.)
