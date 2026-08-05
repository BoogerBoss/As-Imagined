# M28 Recon — Evolution

Step 0 scoping pass. No game code touched. Every claim below is cited against
`/home/rob/GodotAsImagined/reference/pokeemerald_expansion` (file:line) or
against this project's own current source — nothing here is from general
Pokémon-modding memory.

## TL;DR

- The reference engine's evolution model is **8 real trigger methods**
  (`EVO_*`) crossed with **39 real additional-condition qualifiers**
  (`IF_*`) — a `struct Evolution { method, param, targetSpecies, params }`
  table per species, `params` being a variable-length `EvolutionParam` array
  of `{condition, arg1, arg2, arg3}`.
- **Of those 39 real conditions, this project's own 386-entry
  `data/evolutions.json` uses exactly 9**: `IF_NOT_REGION`, `IF_HOLD_ITEM`,
  `IF_ATK_LT_DEF`, `IF_ATK_GT_DEF`, `IF_ATK_EQ_DEF`, `IF_TIME`,
  `IF_NOT_TIME`, `IF_MIN_BEAUTY`, `IF_MIN_FRIENDSHIP` — confirmed by a full
  programmatic scan of the file, not sampled. The other 30 conditions
  (nature, PID-modulo, contest stats other than Beauty, party-composition,
  map-based, move-known, weather, recoil/critical-hit/move-use counters,
  step-counters, bag-item-count, etc.) are **real, dozens-deep noise for
  this project's own roster** — they exist in the engine but nothing in
  this project's 386 species will ever ask for them. Real scope is 9
  conditions, not 39.
- **Trade evolution has a 100%-confirmed item-based substitute already in
  this project's own data.** Every one of the 13 `trade`-method entries in
  `evolutions.json` has a parallel `item`-method entry to the identical
  `target_dex`, and `ITEM_LINKING_CORD` is a real reference item (id 796,
  `include/constants/items.h:969`). **This means M28 can ship complete
  evolution mechanics with zero trade-system work of any kind** — the
  4 "pure trade" species (Kadabra/Machoke/Graveler/Haunter) each already
  have an `ITEM_LINKING_CORD` item alternative in the data; the 9
  item-plus-trade species (Poliwhirl/Slowpoke/Onix/Seadra/Scyther/
  Porygon/Feebas/Clamperl×2) use real named items (King's Rock, Metal
  Coat, Dragon Scale, Prism Scale, Deep Sea Tooth/Scale, Up-Grade).
- **Friendship is a real gap, confirmed, not assumed.** Nothing in this
  codebase increases or decreases `BattlePokemon.friendship` anywhere
  (confirmed by grep and by `docs/m18_5h_recon.md`'s own already-recorded
  exclusion of friendship-gain/Return-Frustration's power-scaling as a
  separate, deliberately-deferred concern). `IF_MIN_FRIENDSHIP` evolutions
  are checkable against the species' static starting value but can never
  become newly eligible through play.
- **Real source engine detail nobody had confirmed before this recon: real
  Pokémon DO learn new moves upon evolving**, via the identical
  `MonTryLearningNewMoveEvolution` function used after level-up
  (`src/pokemon.c:6360`) — it reads the level-up learnset at level==0 or
  level==currentLevel entries. This directly contradicts the task's own
  inherited assumption ("real games: no, moves are untouched by
  evolution") — **that assumption was wrong and is corrected here.**
- **HP follows the identical flat-additive-delta rule as level-up**,
  because evolution calls the exact same `CalculateMonStats` function
  level-up does (`src/pokemon.c:1372`) — confirmed by reading the one
  function, not assumed symmetric.
- **Multiple-eligible-evolution resolution at level-up is FIRST-MATCH-WINS
  by table order** — a deliberate, explicitly-commented departure from
  vanilla in this specific reference engine (`src/pokemon.c:4536`, comment
  at the `break` inside the loop). Not "vanilla continues checking," not
  "player chooses" — the first entry in the species' own evolution array
  that passes wins, full stop.
- **No in-game clock exists in this project, and the reference's real
  `GetTimeOfDay()` is backed by a persistent, save-state RTC/`localTimeOffset`
  clock (`src/rtc.c:331`), not wall-clock.** The `AnimTask_GetTimeOfDay`
  hit in `anim_behaviors.gd` is a coincidental namesake in an unrelated
  system (battle-animation VM) and has nothing to do with this. `IF_TIME`/
  `IF_NOT_TIME` evolutions have no real trigger mechanism to check against
  until a persistent in-game clock exists — a genuine open design question.
- **Evolution-scene assets already sit unused in `assets/Essentials_v19.1/`**
  (confirmed present on disk this session) — belongs to M27H, not M28.
- **A real, previously-undocumented gap: this project has NO Everstone
  item, and no held-item-based evolution-block mechanism of any kind.**
  Confirmed via grep of `scripts/gen_items.py` and `data/items/`.
- **A real, previously-undocumented gap: Shedinja (`EVO_SPLIT_FROM_EVO`) is
  not representable in this project's current `evolutions.json` schema at
  all.** Nincada (dex 290) has exactly one `level_up` entry, target Ninjask
  (291) — nothing generates a second, cloned Shedinja. Shedinja (dex 292)
  exists in this project's roster as a normally-obtainable species with
  currently zero path to acquire it.
- **No rerunnable Python generator exists for `data/evolutions.json`** —
  confirmed absent (same "hand-produced once" gap this project has hit
  for other bulk data files before). Real, separate finding; not the core
  of this recon.

---

## 1. Reference facts (with citations)

### 1.1 The full `EVO_*` method enum — 8 real methods

`include/constants/pokemon.h:322-330`:

```c
enum EvolutionMethods {
    EVO_NONE,                   // not a real evolution (regional-form clone generator)
    EVO_LEVEL,                  // reaches the specified level
    EVO_TRADE,                  // is traded
    EVO_ITEM,                   // specified item used on it
    EVO_SPLIT_FROM_EVO,         // a CLONE is generated and evolved when another evolution happens (Shedinja)
    EVO_SCRIPT_TRIGGER,         // player interacts with an overworld trigger
    EVO_LEVEL_BATTLE_ONLY,      // reaches the specified level, in battle only
    EVO_BATTLE_END,             // battle ends, doesn't need to level up
    EVO_SPIN                    // player spins in the overworld
};
```

8 real methods (`EVO_NONE` is a sentinel used only for regional-form
clone-blocking, never a real evolution path). **This project's
`evolutions.json` uses exactly 3 of the 8**: `level_up`→`EVO_LEVEL`,
`trade`→`EVO_TRADE`, `item`→`EVO_ITEM`. The other 5
(`EVO_SPLIT_FROM_EVO`/Shedinja, `EVO_SCRIPT_TRIGGER`/overworld
triggers, `EVO_LEVEL_BATTLE_ONLY`/Tandemaus, `EVO_BATTLE_END`,
`EVO_SPIN`) are real mechanisms in the engine with zero representation
in this project's roster data — either genuinely irrelevant (no
species in this project's 386 needs them for anything but Shedinja) or
a real gap (Shedinja, see §5).

### 1.2 Dispatch modes — `enum EvolutionMode` (`include/constants/pokemon.h:334-342`)

```c
enum EvolutionMode {
    EVO_MODE_NORMAL,             // level-up (and the overworld-item-check party-menu view)
    EVO_MODE_TRADE,
    EVO_MODE_ITEM_USE,
    EVO_MODE_ITEM_CHECK,         // Everstone still shown as "could evolve" in party menu
    EVO_MODE_BATTLE_SPECIAL,     // battle-end-triggered, no level requirement
    EVO_MODE_OVERWORLD_SPECIAL,  // overworld-spin-triggered
    EVO_MODE_SCRIPT_TRIGGER,
    EVO_MODE_BATTLE_ONLY,        // Tandemaus's own unique in-battle-only requirement
};
```

### 1.3 The full `IF_*` additional-condition enum — 39 real conditions

`include/constants/pokemon.h:272-319`, full list, by generation-of-origin
comment already in source:

Gen 2 (8): `IF_GENDER`, `IF_TIME`, `IF_NOT_TIME`, `IF_MIN_FRIENDSHIP`,
`IF_ATK_GT_DEF`, `IF_ATK_EQ_DEF`, `IF_ATK_LT_DEF`, `IF_HOLD_ITEM`.

Gen 3 (8): `IF_PID_UPPER_MODULO_10_GT/_EQ/_LT`, `IF_MIN_BEAUTY`,
`IF_MIN_COOLNESS`, `IF_MIN_SMARTNESS`, `IF_MIN_TOUGHNESS`,
`IF_MIN_CUTENESS`.

Gen 4 (4): `IF_SPECIES_IN_PARTY`, `IF_IN_MAP`, `IF_IN_MAPSEC`,
`IF_KNOWS_MOVE`.

Gen 5 (1): `IF_TRADE_PARTNER_SPECIES`.

Gen 6 (3): `IF_TYPE_IN_PARTY`, `IF_WEATHER`, `IF_KNOWS_MOVE_TYPE`.

Gen 8 (7): `IF_NATURE`, `IF_AMPED_NATURE`, `IF_LOW_KEY_NATURE`,
`IF_RECOIL_DAMAGE_GE`, `IF_CURRENT_DAMAGE_GE`, `IF_CRITICAL_HITS_GE`,
`IF_USED_MOVE_X_TIMES`.

Gen 9 (8): `IF_DEFEAT_X_WITH_ITEMS`, `IF_PID_MODULO_100_GT/_EQ/_LT`,
`IF_MIN_OVERWORLD_STEPS`, `IF_BAG_ITEM_COUNT`, `IF_REGION`,
`IF_NOT_REGION`.

8+8+4+1+3+7+8 = **39 total**, each implemented in
`DoesMonMeetAdditionalConditions` (`src/pokemon.c:4207-4739ish`, see §1.5).

### 1.4 `struct Evolution` / `struct EvolutionParam` — the real data shape

`include/pokemon.h:384-398`:

```c
struct EvolutionParam
{
    u16 condition;   // one of the 39 IF_* values, or CONDITIONS_END
    u16 arg1;
    u16 arg2;
    u16 arg3;
};

struct Evolution
{
    u16 method;                        // one of the 8 EVO_* values
    u16 param;                         // e.g. level for EVO_LEVEL, item id for EVO_ITEM
    enum Species targetSpecies;
    const struct EvolutionParam *params; // variable-length, ended by CONDITIONS_END
};
```

Per-species tables live in `src/data/pokemon/species_info.h`, each entry
built with the `EVOLUTION(...)` macro (`species_info.h:8`) —
`(const struct Evolution[]) { __VA_ARGS__, { EVOLUTIONS_END }, }`.

This project's own `data/evolutions.json` (`{species_name, evolutions:
[{method, condition, target_dex, conditions:[...]}]}`) is a faithful,
flattened translation of exactly this shape: `method`+`condition` is the
`EVO_*` half, `conditions` array is the `IF_*` qualifier list (arg values
folded away — this project's schema doesn't carry `arg1/2/3` numeric
values for the qualifier tags, only which tags apply; see §6 open
decision).

### 1.5 `DoesMonMeetAdditionalConditions` — how each `IF_*` actually reads

`src/pokemon.c:4207-4739ish`. Full body read directly (not summarized from
memory). Key mechanics relevant to this project's own 9 used tags:

- `IF_HOLD_ITEM` (`:4207+`): `heldItem == params[i].arg1` → sets
  `removeHoldItem = TRUE`, which is applied (item cleared from the mon)
  **only when `evoState == DO_EVO`**, i.e. only at the moment the
  evolution actually commits, not at a mere `CHECK_EVO` probe.
- `IF_MIN_FRIENDSHIP`: `friendship >= params[i].arg1` — a plain read of the
  mon's current friendship value, no mutation.
- `IF_ATK_GT_DEF`/`_EQ_DEF`/`_LT_DEF`: raw stat comparison, no stage
  modifiers, no held item, no ability — literally `attack`/`defense` as
  currently computed.
- `IF_TIME`/`IF_NOT_TIME`: `GetTimeOfDay() == params[i].arg1` — see §4 for
  what `GetTimeOfDay` actually is.
- `IF_MIN_BEAUTY`: reads `MON_DATA_BEAUTY`, a real per-mon contest stat
  field — confirmed this project's `BattlePokemon` has no such field
  (Beauty is a Contest-only stat this battle-engine project never modeled;
  a real open item, see §6).
- `IF_REGION`/`IF_NOT_REGION`: reads `GetCurrentRegion()` — an overworld
  concept (which region the player's current map belongs to) this project
  has zero infrastructure for yet (no map system exists until M27C).

**Item consumption at commit time**: right after each condition's own
`switch`, the function checks `if (evoState == DO_EVO)` and applies
`removeHoldItem`/`removeBagItem` — meaning the *check* pass and the
*commit* pass are literally the same function called twice with a
different `evoState`, and mutation only ever happens on the commit call.
This project's own architecture doesn't need to replicate the two-pass
shape verbatim, but the commit-time-only item consumption rule is real
and should be preserved: a probe ("could this species evolve at all," the
existing `CanEvolve`/Eviolite check) must never consume an item.

### 1.6 `GetEvolutionTargetSpecies` — the real dispatch function and its modes

`src/pokemon.c:4536-4739ish`. One function, `switch (mode)` over the 8
`EvolutionMode` values, each iterating the species' own `evolutions[]`
array in **table order**, checking the primary method match first, then
calling `DoesMonMeetAdditionalConditions` for the qualifier array. The
loop's own comment, verbatim (`:4536` region, inside every mode's loop):

> "All checks passed, so stop checking the rest of the evolutions. This is
> different from vanilla where the loop continues. If you have overlapping
> evolutions, put the ones you want to happen first on top of the list."

This is the single most load-bearing citation in this recon (see TL;DR
and §5, item 4). It directly answers "what happens when multiple
evolution branches could apply" — **first table-order match wins,
unconditionally, in this reference engine specifically** (an explicit,
intentional fork from vanilla pokeemerald's own "last match wins /
continues checking" behavior).

An **Everstone check runs before the mode switch at all**
(`HOLD_EFFECT_PREVENT_EVOLVE`): if the holder's held item has that hold
effect and the mode isn't `EVO_MODE_ITEM_CHECK` (party-menu preview), the
function returns `SPECIES_NONE` immediately — no evolution of any kind can
occur while holding an Everstone (with one Kadabra-specific exception
gated behind a config flag, `P_KADABRA_EVERSTONE < GEN_4`, irrelevant at
this project's `GEN_LATEST` config).

### 1.7 Real trigger/call sites (not assumed — enumerated directly)

| Call site | File:line | Mode | What triggers it |
|---|---|---|---|
| `TryEvolveMon`/party-menu after a level-up in battle | `src/pokemon.c:3799` | `EVO_MODE_ITEM_USE` at the item-use site; the level-up path itself is in `party_menu.c`/battle end-of-battle handling | Level-up crossing |
| `party_menu.c:5851` | `party_menu.c` | `EVO_MODE_NORMAL` | Ordinary level-up outside battle (Rare Candy, overworld leveling) |
| `party_menu.c:6041` | `party_menu.c` | `EVO_MODE_NORMAL` | A second normal-mode level-up-adjacent site |
| `party_menu.c:1183` | `party_menu.c` | `EVO_MODE_ITEM_CHECK` | Party-menu preview of "could this Everstone-holder evolve" |
| `src/trade.c:3875/3878/4380/4383/4426/4429` | `trade.c` | `EVO_MODE_TRADE` | A real trade completing (both link-trade and the in-game NPC trade path) |
| `src/scrcmd.c:3311/3318` | `scrcmd.c` | `EVO_MODE_SCRIPT_TRIGGER` | An overworld script event (Trade Evolution stones triggered via a map object, King's Rock rock-tap events, etc.) |
| `src/battle_main.c:5636/5644/5651` | `battle_main.c` | mode-parametrized | End-of-battle evolution check (level-up evolutions surfacing right after a win) |
| `src/pokemon.c:6416/6420` | `pokemon.c` | `EVO_MODE_OVERWORLD_SPECIAL` | The overworld-spin trigger (`EVO_SPIN`) |
| `src/chooseboxmon.c:121` | `chooseboxmon.c` | `EVO_MODE_SCRIPT_TRIGGER` | Choosing a boxed mon in a script-triggered context |

**Confirmed real trigger points, not assumed**: level-up (both in-battle
and overworld/Rare-Candy), item-use (from the party menu), trade
completion, and 3 distinct overworld-script mechanisms
(`EVO_SCRIPT_TRIGGER`/`EVO_SPIN`/`EVO_MODE_BATTLE_SPECIAL`). The task's
own suspicion ("there may be other trigger points too") is correct — there
are genuinely 4 real families of trigger, not one.

### 1.8 The actual species/stat/ability mutation sequence

`src/evolution_scene.c`, state `EVOSTATE_SET_MON_EVOLVED` (`:779-796`):

```c
SetMonData(mon, MON_DATA_SPECIES, (void *)(&gTasks[taskId].tPostEvoSpecies));
SetMonData(mon, MON_DATA_EVOLUTION_TRACKER, &zero);
CalculateMonStats(mon);
EvolutionRenameMon(mon, gTasks[taskId].tPreEvoSpecies, gTasks[taskId].tPostEvoSpecies);
GetSetPokedexFlag(SpeciesToNationalPokedexNum(gTasks[taskId].tPostEvoSpecies), FLAG_SET_SEEN);
GetSetPokedexFlag(SpeciesToNationalPokedexNum(gTasks[taskId].tPostEvoSpecies), FLAG_SET_CAUGHT);
IncrementGameStat(GAME_STAT_EVOLVED_POKEMON);
```

Immediately followed, at state `EVOSTATE_TRY_LEARN_MOVE`, by
`MonTryLearningNewMoveEvolution` (see §1.9). Note this whole state
machine lives in `evolution_scene.c` — **the reference engine does not
cleanly separate the mechanics mutation from the presentation state
machine**; the species/stat/rename mutation literally executes as one
step inside the visual scene's own script. This is worth flagging plainly
per the boundary note in the task brief: this recon's own scope (M28
mechanics only) can still extract the mutation logic cleanly, but a
future session building M27H's scene should know the reference itself
doesn't draw that line — it's this project's own architectural choice to
draw it, not a reflection of how source is organized.

**`CalculateMonStats` is the single shared function** for level-up (M20b,
already ported in this project) AND evolution (source, this recon) —
confirmed by reading the one function (`src/pokemon.c:1372-1421ish`),
not assumed symmetric:

```c
gBattleScripting.levelUpHP = newMaxHP - oldMaxHP;
if (gBattleScripting.levelUpHP == 0) gBattleScripting.levelUpHP = 1;
SetMonData(mon, MON_DATA_MAX_HP, &newMaxHP);
if (currentHP == 0 && oldMaxHP != 0) return;          // stays fainted at 0
if (newMaxHP > oldMaxHP) currentHP += newMaxHP - oldMaxHP;  // flat additive delta
if (currentHP > newMaxHP) currentHP = newMaxHP;             // clamp
SetMonData(mon, MON_DATA_HP, &currentHP);
```

This is **the exact same flat-additive-delta rule this project's own
M20b-era level-up code already implements** (per M20b's own CLAUDE.md
entry: "the real HP rule... is a flat ADDITIVE delta"). Confirmed
identical function, not merely a plausible-sounding assumption — evolution
follows the identical HP rule as level-up because it's literally the same
code path in source.

### 1.9 Move learning at evolution — a real correction to the task's own assumption

`src/pokemon.c:6360-6386`, `MonTryLearningNewMoveEvolution`:

```c
u16 MonTryLearningNewMoveEvolution(struct Pokemon *mon, bool8 firstMove)
{
    enum Species species = GetMonData(mon, MON_DATA_SPECIES);
    u8 level = GetMonData(mon, MON_DATA_LEVEL);
    const struct LevelUpMove *learnset = GetSpeciesLevelUpLearnset(species);
    if (firstMove) sLearningMoveTableID = 0;
    while (learnset[sLearningMoveTableID].move != LEVEL_UP_MOVE_END)
    {
        while ((learnset[sLearningMoveTableID].level == 0
             || learnset[sLearningMoveTableID].level == level) ...)
        {
            gMoveToLearn = learnset[sLearningMoveTableID].move;
            sLearningMoveTableID++;
            return GiveMoveToMon(mon, gMoveToLearn);
        }
        sLearningMoveTableID++;
    }
    return 0;
}
```

Called from `evolution_scene.c`'s `EVOSTATE_TRY_LEARN_MOVE` right after
the species swap, reading `MON_DATA_SPECIES` and `MON_DATA_LEVEL`
**fresh, off the already-mutated mon** — i.e. it queries the NEW species'
own learnset at the mon's current level, using the identical function and
identical level-0-is-a-wildcard rule the ordinary post-level-up move-learn
path uses (this project's own M20b `_try_learn_move_at_level`, already
evolution-safe per that milestone's own design note).

**This directly contradicts the task brief's own inherited assumption**
("real games: no, moves are untouched by evolution") — that premise is
**wrong**, and is corrected here per this project's own standing
discipline of surfacing a Step 0 finding that contradicts the task's
framing rather than quietly building around it. Real Pokémon absolutely
can, and frequently do, learn a new move the instant they evolve (the
classic example: a starter evolving mid-level-range and immediately
learning a move it "should" already know). The `level == 0` branch is
specifically for moves flagged as "learned upon evolving" in the species'
level-up table (as distinct from "learned upon reaching level N") — a real
data concept this project's own move-learnset JSON needs to be checked
against (see §6 open decision — does this project's learnset data
currently encode any level==0 entries at all?).

Existing moves are **never removed or altered** by this function — it
only ever calls `GiveMoveToMon` to add a new one into an open slot, or
(if all 4 slots are full) prompts the real player-choice replace-or-skip
flow this project has no UI for yet, mirroring M20b's own already-resolved
"replacement slot" design (`_force_move_replacement_slot` forcing seam,
already built and already evolution-agnostic — it doesn't care whether
the level-up trigger came from a level crossing or an evolution).

### 1.10 Nickname handling — the real rule, and how it maps onto this project's own field

`src/pokemon.c:4875-4881`, `EvolutionRenameMon`:

```c
void EvolutionRenameMon(struct Pokemon *mon, enum Species oldSpecies, enum Species newSpecies)
{
    u8 language;
    GetMonData(mon, MON_DATA_NICKNAME, gStringVar1);
    language = GetMonData(mon, MON_DATA_LANGUAGE, &language);
    if (language == GAME_LANGUAGE && !StringCompare(GetSpeciesName(oldSpecies), gStringVar1))
        SetMonData(mon, MON_DATA_NICKNAME, GetSpeciesName(newSpecies));
}
```

Rule: **if the current nickname exactly equals the OLD species' own
default display name** (i.e., the player never renamed it), auto-update
to the NEW species' default name. Otherwise, leave a genuinely custom
nickname untouched.

This project's own `BattlePokemon.nickname`/`display_name()` split
(`scripts/battle/core/battle_pokemon.gd:86-108`, built at M27K K-c) maps
onto this rule almost exactly for free: `from_species()` already seeds
`nickname` with the species' own `species_name` at construction time (per
the K-c doc comment, "the fallback never fires on anything the factory
made... `from_species` already seeds nickname with the species name"). So
an evolution mutation would check `mon.nickname == mon.species.species_name`
(i.e., "still the default") immediately BEFORE reassigning `.species`, and
if true, reassign `nickname` to the new species' `species_name` right
after — the identical check-then-update shape as source, using a field
this project already has. If the player set a genuinely custom nickname,
this check is false and the nickname is correctly left alone.

---

## 2. Time-of-day system — confirmed absent, and what the `AnimTask_GetTimeOfDay` red herring actually is

The task brief flagged a suspicion that `AnimTask_GetTimeOfDay`
(`scripts/battle/anim/anim_behaviors.gd:318,10554`) might be a
wall-clock-reading stand-in worth reusing. Confirmed via source
(`src/rtc.c:331-333`):

```c
enum TimeOfDay GetTimeOfDay(void)
{
    UpdateTimeOfDay();
    return gTimeOfDay;
}
```

`gTimeOfDay` is derived from `gLocalTime`, itself computed from a real
hardware RTC (or `OW_USE_FAKE_RTC`'s software equivalent) offset against
`gSaveBlock2Ptr->localTimeOffset` — a **persistent, save-state-anchored
in-game clock**, not the host machine's wall-clock time read live. This is
the identical mechanism `[M18.5h-1]`'s own recon already flagged for
Nature/friendship-adjacent systems: a genuine engine subsystem this
project has never built any equivalent of.

This project's own `AnimTask_GetTimeOfDay` (in the battle-ANIMATION VM,
`anim_behaviors.gd`) is an unrelated, coincidentally-named function
belonging to M36's move-animation port — it exists to drive a purely
cosmetic per-move visual effect (matching the reference's own
`AnimTask_GetTimeOfDay` used by weather/time-flavored move animations),
and has zero connection to evolution, to `GetTimeOfDay()` the save-clock
function, or to any persistent game-state concept. Confirmed by reading
both call sites directly, not assumed from the shared name.

**Real conclusion**: `IF_TIME`/`IF_NOT_TIME` evolutions have no real
backing clock system to check against in this project at all. Confirmed
by direct query of `evolutions.json`: the only 2 entries using either tag
are both on **Eevee (dex 133)** — `level_up`→Umbreon (197,
`IF_MIN_FRIENDSHIP`+`IF_NOT_TIME`) and `level_up`→Espeon (196,
`IF_MIN_FRIENDSHIP`+`IF_TIME`), each ALSO gated on friendship (itself a
separate, already-flagged gap, §5 item 4). This is squarely an open
design question for the project owner (see §6), not something this recon
can silently resolve either way.

---

## 3. Scope table — which `EVO_*`/`IF_*` values actually matter for this project's 386-species roster

| Category | Reference engine total | Used in this project's `evolutions.json` | Real scope for M28 |
|---|---|---|---|
| `EVO_*` methods | 8 real (+1 sentinel) | 3 (`EVO_LEVEL`, `EVO_TRADE`, `EVO_ITEM`) | Build all 3. `EVO_SPLIT_FROM_EVO` is a real gap (Shedinja, §5) — not currently representable, needs a schema decision. The other 4 (`EVO_SCRIPT_TRIGGER`/`EVO_LEVEL_BATTLE_ONLY`/`EVO_BATTLE_END`/`EVO_SPIN`) are genuinely irrelevant noise — zero species in this roster need them. |
| `IF_*` conditions | 39 real | 9 (`IF_NOT_REGION`, `IF_HOLD_ITEM`, `IF_ATK_LT_DEF`, `IF_ATK_GT_DEF`, `IF_ATK_EQ_DEF`, `IF_TIME`, `IF_NOT_TIME`, `IF_MIN_BEAUTY`, `IF_MIN_FRIENDSHIP`) | Build all 9. The other 30 are irrelevant noise for this roster — Gen 4/5/6/8/9-era conditions (nature-gated, PID-modulo, party-composition, map-based, weather-based, move-known, recoil/crit/move-use counters, step-counters, bag-item-count) never appear in this project's own 386-entry data. |
| Trigger-time infrastructure needed | 4 real families (level-up, item-use, trade, overworld-script) | Confirmed used in `evolutions.json`: level_up (needs a level-crossing dispatch — **already exists**, M20b), item (needs a "use item on party member" flow — **does not exist yet**, no bag/inventory UI in this project until M27I), trade (needs **zero** work — see TL;DR) | 2 of 4 real trigger families matter: level-up and item-use. Level-up dispatch already exists (M20b's `_check_level_up`). Item-use dispatch does not exist — a real, non-trivial M28-adjacent dependency on M27I (Bag/Item screen) landing first, OR a narrower "consume item directly on a party member" seam that doesn't wait for the full Bag UI. |
| Held-item block (Everstone) | Real, unconditional (`HOLD_EFFECT_PREVENT_EVOLVE`) | Confirmed **0 items in this project's roster carry this hold effect** — no Everstone exists at all | Real, disclosed gap — flagged in §5, not fixed here. |

**Bottom line**: the theoretically-huge 39-condition/8-method surface
collapses to **9 conditions × 3 methods** for this project's own data —
dozens of Gen 4-9-era conditions are correctly irrelevant, not a scope
this milestone needs to build toward "just in case."

---

## 4. Proposed phasing

| Phase | Scope | Depends on |
|---|---|---|
| **M28a — core mutation primitive** | Species/stat/ability/original_types swap (extending the existing Transform-precedent `_reset_mon_species`/`_reset_mon_stats`/`_reset_mon_ability` trio into a PERMANENT variant — new functions, not a reuse of the temporary ones, since permanence changes what's safe to assume per the task's own warning), the flat-additive HP-delta rule (already proven identical to M20b's level-up code), nickname auto-update (`nickname == old species_name` check), move-learning-at-evolution (reusing M20b's `_try_learn_move_at_level`/`_force_move_replacement_slot` machinery, now also driven by an evolution event rather than only a level crossing) | M20b (already shipped) |
| **M28b — level-up-triggered evolution dispatch** | Wire the 8-tag qualifier check (`IF_NOT_REGION` through `IF_MIN_FRIENDSHIP`, minus the ones needing infra this project doesn't have — see below) into the existing level-up dispatch (`_check_level_up`), first-match-wins over the species' own `evolutions.json` array order (matching source exactly) | M28a |
| **M28c — item-triggered evolution** | A narrow "use item X on party member Y, check+commit evolution" seam — does NOT need to wait for the full M27I Bag screen if a minimal party-member-plus-item-id API is built instead; can be exercised by tests/debug tooling before any UI exists | M28a; optionally ahead of M27I |
| **M28d — trade-evolution items** | Confirm the 13 real `ITEM_LINKING_CORD`-and-siblings entries dispatch through the SAME item-triggered path as M28c (they are, after all, plain `item`-method entries in the data) — **this phase may collapse entirely into M28c since it's the identical mechanism**, flagged as a likely no-op phase rather than real new work | M28c |
| **M28e — deferred/blocked conditions** | `IF_MIN_BEAUTY` (needs a Beauty contest-stat field this project has never modeled), `IF_TIME`/`IF_NOT_TIME` (needs a persistent in-game clock, §6 open decision), `IF_NOT_REGION` (needs a "current region" overworld concept — may already resolve once M27C's map system lands, needs re-checking then) | Contest-stat decision; clock decision; M27C |

Everstone/held-item evolution-block and Shedinja are both explicitly
**not phased above** — they're real gaps flagged for the project owner's
own decision in §6, not silently folded into a phase.

---

## 5. Real findings, flagged not fixed (per this project's own "flag, don't silently fix" standing rule)

1. **No rerunnable Python generator exists for `data/evolutions.json`.**
   Confirmed via search — same "hand-produced once, never kept as a
   re-runnable extractor" gap this project has hit before for other bulk
   JSON files (`gender_ratio`, `exp_yield`, etc., before their own
   `gen_*.py` fixes). A future M28 session regenerating or extending this
   file should build `scripts/gen_evolutions.py` rather than hand-editing
   the JSON, matching every other data file's own established convention.

2. **No Everstone / `HOLD_EFFECT_PREVENT_EVOLVE`-equivalent item exists
   anywhere in this project.** Confirmed by grepping `scripts/gen_items.py`
   and `data/items/` for "everstone" and for the hold-effect constant —
   zero hits. Without it, there is currently no way for a player to
   deliberately block an otherwise-eligible level-up evolution, which
   real games treat as a first-class, commonly-used mechanic.

3. **Shedinja (`EVO_SPLIT_FROM_EVO`) is not representable in this
   project's current `evolutions.json` schema.** Nincada (dex 290) has
   exactly one entry, `{"method": "level_up", "condition": 20,
   "target_dex": 291}` (→ Ninjask) — no clone-generation event exists
   anywhere in the data. Shedinja (dex 292) sits in this project's roster
   as an ordinarily-obtainable species with **zero current path to
   acquire it**, since the split-evolution mechanism that's supposed to
   produce it was never encoded.

4. **Friendship never increases or decreases anywhere in this codebase.**
   Confirmed by grep (no write site to `BattlePokemon.friendship` outside
   construction) and cross-referenced against `docs/m18_5h_recon.md`
   Section E, which already independently confirmed and deliberately
   deferred this exact gap ("no per-individual friendship field... a
   friendship-based STAT boost, distinct from Return/Frustration's
   move-power scaling"). `IF_MIN_FRIENDSHIP` evolutions are checkable
   against each species' static `base_friendship` starting value but can
   never organically become newly eligible during play under the current
   architecture.

5. **The reference engine does not architecturally separate the
   evolution-mechanics mutation from the evolution-scene presentation
   layer** — they live in the same state machine
   (`src/evolution_scene.c`'s `EVOSTATE_*` sequence). This project's own
   M27/M28 boundary (mechanics here, scene in M27H) is this project's own
   deliberate choice, not a reflection of how source organizes the code —
   flagged per the task's own explicit instruction to say so plainly
   rather than silently absorb the blurred boundary.

---

## 6. Open decisions for the project owner

Each phrased as a concrete either/or, with a recommendation — not a vague
"consider this."

1. **`IF_TIME`/`IF_NOT_TIME` evolutions**: (A) build a minimal persistent
   in-game clock now, just far enough to back these two conditions, or (B)
   leave time-gated evolutions permanently unreachable until a real
   in-game clock is built for its own reasons (likely alongside M27's
   overworld day/night-cycle work, if ever scoped) and treat this as an
   explicit, disclosed exclusion for now.
   **Recommendation: (B).** A whole persistent RTC-equivalent system is a
   large, cross-cutting piece of infrastructure to build solely to unlock
   what is likely a small handful of species in this roster — better
   scoped as its own milestone if/when the overworld's day/night cycle is
   ever decided, not smuggled into M28.

2. **Everstone / held-item evolution-block**: (A) add a real Everstone
   item now, gating the whole evolution dispatch behind
   `HOLD_EFFECT_PREVENT_EVOLVE` exactly as source does, or (B) ship M28
   without it and let every eligible evolution always fire.
   **Recommendation: (A).** This is cheap (one new item, one boolean
   check at the top of the dispatch function, mirroring source's own
   `GetEvolutionTargetSpecies` early-return) and its absence is a
   genuinely large behavioral gap for anyone used to real games — a
   player currently has no way to deliberately keep a Pokémon at its
   current stage.

3. **Shedinja/`EVO_SPLIT_FROM_EVO`**: (A) extend `evolutions.json`'s
   schema with a new method value (e.g. `"split_evolution"`) carrying the
   clone-target dex number, and build the clone-generation mechanic
   (append a new party/box slot on a Ninjask evolution, gated on party
   space and a Poké Ball being available, matching source's own
   `CreateShedinja` conditions), or (B) exclude Shedinja from this
   project's obtainable roster for now, flagged as a permanent or
   temporary exclusion.
   **Recommendation: (A), but sized as its own small sub-phase, not
   folded into the main level-up dispatch work.** It's a real, one-off,
   non-reusable mechanic (party-slot creation, Ball-consumption, a
   from-scratch Pokémon rather than a mutation of the evolving mon) that
   would otherwise silently leave a real, already-present species in this
   roster permanently unobtainable.

4. **Item-evolution trigger surface**: (A) build a minimal
   "use-item-on-party-member" API now, ahead of M27I's own real Bag/Item
   screen, so M28's item-evolution phase (M28c) isn't blocked on that
   milestone landing first, or (B) let M28c sit blocked until M27I ships.
   **Recommendation: (A).** The actual evolution-dispatch logic (M28a/b)
   doesn't care where the "use this item on this mon" call comes from —
   a narrow, UI-less seam (callable from tests/debug tooling, later wired
   to the real Bag screen when M27I lands) unblocks 9 of this project's
   13 item-method species and both `IF_HOLD_ITEM`-trade-substitute items
   without waiting on an unrelated milestone's own UI timeline.

5. **`IF_MIN_BEAUTY`**: (A) add a minimal Beauty contest-stat field now,
   just to back this one condition, or (B) exclude Beauty-gated
   evolutions (Feebas→Milotic, dex 349→350, the only user of this tag in
   this project's data) until a real Contest-stat system is ever built.
   **Recommendation: (B), with a disclosed exclusion.** This project has
   never modeled Contest stats at all (Cool/Beauty/Cute/Smart/Tough) —
   adding one field solely for a single evolution's gate, with no other
   consumer anywhere in the codebase, is scope creep in the wrong
   direction; better to exclude this one evolution path explicitly and
   revisit if Contests are ever scoped as their own feature.
