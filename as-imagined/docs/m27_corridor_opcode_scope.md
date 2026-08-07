# Corridor op code / special scope — 2026-08-07

Scope of record for "implement every op code and special the current 32-map
corridor actually needs" — Rob's own chosen boundary (not the whole Kanto
region, not the reference engine's Hoenn/multiplayer content). Supersedes
nothing; this is new, narrowly-scoped work sitting on top of `[M27F]`'s
opcode-coverage sessions and `[M27G]`'s specials recon.

## Method

Two full audits, both scoped to scripts truly owned by the 32 baked map
scenes (`scenes/maps/*.tscn`), not the whole reference corpus:

1. **Op codes**: parsed each of the 32 maps' own `scripts.inc` directly under
   `field_script_source/data/maps/<Map>/` for label boundaries (924 labels,
   546 with real op lists), then diffed every op name against
   `ScriptVM.step()`'s dispatcher.
2. **Specials**: BFS from those 546 labels, following every `goto`/`call`/
   `goto_if_*`/`case` target (including into shared/common scripts outside
   the 32 maps' own directories) to find every `special`/`specialvar` truly
   reachable from corridor content — 686 labels reached, 39 distinct
   special-function names.

## Result 1: specials — already effectively closed, no action needed

Of the 39 reachable special-function names: **17 are already implemented**
(via `FieldSpecials` or direct `ScriptVM.step()` dispatch), **18 are
permanently-excluded multiplayer/Mystery-Gift content** (Cable Club, Union
Room, Record Corner — the only corridor callers of these are themselves
Cable-Club-gated scripts), and the remaining **4 are blocked on systems
outside this scope, not on opcode work**:

- `GetFrlgPokedexCount` / `SetUnlockedPokedexFlags` / `EnableNationalPokedex`
  / `HasAllMons` / `GetProfOaksRatingMessage` — all **M33** (Pokédex).
- `ChooseMonForMoveTutor` — **M30** (move relearner/tutor mechanics).
- `SaveGame` — every real corridor caller of `Common_EventScript_SaveGame`
  is Cable-Club-gated; the actual save system (`SaveManager`) already
  exists and needs no new work until a non-multiplayer caller exists.
- `GetLeadMonFriendship` / `DaisyMassageServices` — blocked on a friendship
  system this project has never built (already flagged in
  `docs/m18_5h_recon.md`; not this scope's to open).

**No specials work is proposed here.** Everything actionable in this
category belongs to milestones that already own it.

## Result 2: op codes — 6 found, 1 closed by verification, 5 real, tiered by size

### Closed, no work needed: `map_script`

The raw `*_MapScripts` table header (25 uses — one per map). Verified
directly: every corridor map's table entries resolve exactly to the
`<map>_On{Transition,Frame,Warp,Load,Resume}` labels `overworld.gd` already
calls by name-convention (`_map_script_prefix(map_name) + "_OnFrame"`, etc.)
— the only non-matching targets are shared `CableClub_On*` hooks, which are
multiplayer-only and irrelevant. The table itself is correctly never parsed;
convention-based dispatch already covers 100% of what it would tell us.
**Verified, not a gap. No action.**

### Tier 0 — trivial (minutes): `fadeoutbgm`

1 use (`PewterCity_PokemonCenter_1F_EventScript_Jigglypuff`, the singing
Jigglypuff easter egg). This project has zero audio playback anywhere
(scoped separately as `M36-S`); every other `play*`/`fade*` audio opcode is
already a documented no-op (`playfanfare`/`waitfanfare`/`playse`/`playbgm`/
`fadedefaultbgm`, `script_vm.gd` line ~477). Add `fadeoutbgm` to that same
no-op group. No design decision, no new state.

### Tier 1 — small, bounded (a session each)

**`setmetatile`** — 2 uses, one script
(`ViridianCity_Mart_EventScript_HideQuestionnaire`), swapping two counter
tiles to hide a decorative prop after some scene event. This project bakes
map tiles into the `.tscn` at import time (`[M27M]`'s own "the scene
becomes the source of truth" decision) — there is currently no primitive
for mutating a live cell's metatile at runtime. Needs one new `MapManager`
method (`set_metatile(gcell, id)`-shaped) that writes directly into the
owning chunk's `TileMapLayer`, routed the same layer-type way `[M27C]`'s
border skirt already routes (a metatile can land on Ground/Objects/
Overhangs). Small, single real consumer, but is genuinely new
infrastructure, not a one-liner.

**`copyobjectxytoperm`** — 1 use (`PalletTown_EventScript_SignLady`,
Pallet Town's "look, a shooting star" NPC that steps aside once and should
stay stepped-aside). Source uses this to bake a moved NPC's new coordinates
into its own permanent template so it doesn't reset on map reload. This
project already treats a placed `NPC` node's live `cell` as the sole source
of truth (no separate template/instance split) — so within a single play
session this "just works" with no code at all. The only real question is
**save/reload persistence**: does a saved game need to remember the sign
lady moved? `[M27L]`'s save payload currently has no concept of "moved NPC
overrides" at all. Recommend: ship as a documented no-op for now (matching
this project's own precedent for small disclosed simplifications), and
open a real "persist moved/hidden NPC state" line item only if/when M27L's
save shape is revisited — inventing a one-off mechanism for a single NPC
would be the wrong scope for what is really a general save-completeness
question.

### Tier 2 — a real new UI primitive (medium)

**`multichoicegrid`** — 1 use today (`ViridianCity_School_EventScript_
ChooseBlackboardTopic` — pick a status-condition topic to read about: 5
real options + Exit, `switch`/`case` already implemented and ready to
consume the result). This project has no general VM-driven multi-item
choice widget yet — only the narrow `multichoice ... MULTI_YESNO` case
(`[M27F Stage 4]`) and purpose-built screens (Bag, Party). Scope: a small
`MultichoiceGrid` field widget — cursor movement over N named entries
arranged `per_row` wide, confirm writes the chosen index to `VAR_RESULT`
(mirroring `answer_party_choice`'s shape), B/cancel writes `MULTI_B_
PRESSED` (127, already a `_literal` constant). One real consumer today,
but this is the first general list-choice primitive built rather than a
one-off screen — worth building properly since any future NPC dialogue
menu will want the identical shape.

### Tier 3 — the real subsystem (largest, a multi-step build)

**`pokemart`** — 2 uses, both real, already-baked Mart clerks
(`PewterCity_Mart_EventScript_Clerk`, `ViridianCity_Mart_EventScript_
Clerk`). CLAUDE.md's own M27I entry already named this as consciously
deferred ("shops are nearly absent in the corridor... genuinely
deferrable") — this is that deferral coming due, not a fresh discovery.

Everything the shop needs elsewhere already exists: `Wallet` (`[M27I
I3b]`), `Bag`'s all-or-nothing add with capacity refusal (`[M27I I3]`), and
real per-item `price` data (`ItemData.price`, populated for all 816 items
since M15/M18). What's missing is the shop mechanism itself:

1. **Data**: `PewterCity_Mart_Items`/`ViridianCity_Mart_Items` compile to a
   degenerate op stub today — `gen_map_scripts.py` doesn't parse `.2byte
   ITEM_*` data tables as data, only as (mis-shaped) ops. Needs a small
   extractor (same shape as `gen_heal_locations.py`/`gen_wild_encounters.
   py`) pulling each mart's real `ITEM_NONE`-terminated stock list — bounded
   data, 2 corridor marts today (Pewter: 8 items, Viridian: 4 items).
2. **VM plumbing**: a new `Pause.WAIT_MART` (same shape as `WAIT_PARTY_
   CHOICE`) — `pokemart` pauses, the driver opens the shop screen, a result
   resumes the script.
3. **The Buy screen**: a new field screen (plain-`Panel` chrome, matching
   Bag/Party's own disclosed placeholder-chrome precedent — M26E1/E2 owns
   the real visual rework for all of these together) — item list with
   price, a quantity stepper, wallet-affordability check, `Bag.add`'s
   existing all-or-nothing contract handling a full bag.
4. **Sell**: real Poké Marts also offer SELL (walks the player's own bag,
   not mart-specific data) — needs deciding whether this ships now or is
   its own follow-up; recommend building it in the same pass since it's
   the same screen shape reading `Bag` instead of a stock list, not a
   second subsystem.

This is comparable in size to the Bag screen (`[M27I I4]`) or Party screen
(`[M27I I5-2]`) builds already shipped — a real multi-step item, not a
same-session add.

## Proposed build order

1. `fadeoutbgm` (trivial, bundle with anything else)
2. `copyobjectxytoperm` as a documented no-op (trivial, closes a real gap
   with zero new mechanism)
3. `setmetatile` (small, new but bounded `MapManager` primitive)
4. `multichoicegrid` (medium, new general-purpose widget — reusable beyond
   its one current consumer)
5. `pokemart` (largest — its own multi-step build, sequenced last since
   it's the only one that doesn't fit in a single session)

No specials work is proposed — that side is done for this scope.

## ⚠️ Companion scope, written the same day — read both

`docs/m27g_scope.md` (M27G G4–G9) was written 2026-08-07, the same day as
this document, for overlapping ground, **without either knowing about the
other**. Neither supersedes the other; they measure genuinely different
things and the distinction is load-bearing:

- **This document audits what HALTS.** Its method diffs op names against
  `ScriptVM.step()`'s dispatcher, so it finds opcodes the VM has no case for.
  That is content work, and the list above is the whole of it for the
  corridor.
- ⚠️ **It is structurally blind to opcodes that are IN the dispatcher and do
  nothing.** `fadescreen` (+2 siblings), `dofieldeffect`/`waitfieldeffect`,
  `showmonpic`/`hidemonpic`, `opendoor`/`closedoor`/`waitdooranim`,
  `showmoneybox`/`showcoinsbox` and their families all return `true` and are
  silent. They are dispatched, they count as covered, and a script executing
  one gets nothing. `m27g_scope.md` §3.1 audits that category; **no amount of
  the work listed above reaches it.**

`m27g_scope.md` also corrects three figures this document's own method
measured better, and defers to it accordingly — see its §2.4. In particular
`setmetatile` is **2 corridor uses**, not the 1,406 corpus-wide figure in
circulation.

**Proposed interleave** (`m27g_scope.md` §8 decision 6): architecture first,
content second, with `setmetatile` free to run in parallel because it touches
`MapManager` rather than the script engine —

> G4 (extract `ScriptDriver`) → G5 (`native` opcode) → {Tiers 0–1 above,
> `setmetatile`} → G6 (`EventScript`) → G7 → `multichoicegrid` → G8/G9 →
> `pokemart` (M27I)

⚠️ **`multichoicegrid` is deliberately sequenced after G5** — it carries a
result and fits the `WAIT_PARTY_CHOICE` pause shape, but it is also exactly
the kind of thing the `native` hatch exists to absorb. Whether it is the last
bespoke `Pause` or the first absorbed one is a real fork, and `m27g_scope.md`
§8 decision 7 defers it until G5 exists so it can be decided from real code
rather than on paper.
