# M24 Recon — Trainer Data

Scoping/recon session only — **no implementation this session**. Follows the
project's standing "Step 0" discipline: every finding below is re-derived
directly from `pokeemerald_expansion` source, not assumed from memory of
"how Pokémon trainers work" or from symmetry with M15's own species/move
pipeline (trainers turned out to have a genuinely different shape in
several important ways — see below).

## 1. Source structure — re-derived, not assumed

### 1.1 `struct TrainerMon` (`include/data.h`) — one Pokémon in a trainer's party

```c
struct TrainerMon
{
    const u8 *nickname;
    const u8 *ev;               // NULL if unspecified (all-zero EVs)
    u32 iv;                     // packed via TRAINER_PARTY_IVS(hp,atk,def,speed,spatk,spdef)
    enum Move moves[MAX_MON_MOVES];   // FIXED moveset — NOT learnset-derived
    enum Species species;
    enum Item heldItem;
    enum Ability ability;       // a specific ability, not a slot index
    u8 lvl;
    enum PokeBall ball:8;       // cosmetic (which ball animation plays on send-out)
    u8 friendship;
    u8 nature:5;                // explicit, not randomly rolled
    bool8 gender:2;
    bool8 isShiny:1;
    enum Type teraType:5;       // Tera — already-excluded mechanic, see §6
    bool8 gigantamaxFactor:1;   // Dynamax/Gigantamax — already-excluded, see §6
    u8 shouldUseDynamax:1;
    u8 dynamaxLevel:4;
    u32 tags;                   // trainer-POOLS role tag (lead/ace/weather-setter/support) — see §1.5
};
```

**Confirmed, not assumed**: trainer mons have a **fixed moveset** (up to 4
explicit moves), **explicit nature/IVs/EVs** (no random rolling — this
project's own `BattlePokemon.from_species(sp, level, forced_nature,
forced_ivs, forced_friendship)` forcing-parameter API, built specifically
for this future need during M18.5h-1/h-2, is exactly the shape M24 needs to
consume), and an **explicit ability** (not a slot index the way a wild
encounter would resolve one). This is a genuinely different construction
path from every wild/random Pokémon this project has built so far — closer
to `TeamStorage.build_member(spec)`'s own saved-team-shape (M23.6) than to
`RandomTeamGenerator`.

### 1.2 `struct Trainer` (`include/data.h`) — one trainer

```c
struct Trainer
{
    u64 aiFlags;                 // see §2 — a 64-bit combinable bitmask, not a tier enum
    const struct TrainerMon *party;
    enum Item items[MAX_TRAINER_ITEMS];   // MAX_TRAINER_ITEMS=4 — battle-USE items (Potions/X items), NOT held items
    struct StartingStatuses startingStatus;  // field-wide starting weather/terrain/room — 0 uses in vanilla trainers.party, see §6
    u8 trainerClass;              // links to struct TrainerClass, see §1.3
    u16 encounterMusic:4;
    u16 multiTeamSize:1;          // MULTI_TEAM_SIZE_FULL/HALF — 2 uses in vanilla data, low priority
    u16 gender:1;
    u16 battleType:2;             // Singles/Doubles — 77 of 855 trainers are Doubles
    u16 mugshotColor:3;
    u16 partySize:3;
    enum TrainerPicID trainerPic; // see §1.4 — THE portrait key, NOT 1:1 with trainer identity
    u8 trainerName[TRAINER_NAME_LENGTH + 1];
    u8 poolSize;                  // trainer POOLS (procedural party generation) — see §1.5
    u8 poolRuleIndex;
    u8 poolPickIndex;
    u8 poolPruneIndex;
    u16 overrideTrainer;          // rematch/alt-version linkage — see §4
};
```

### 1.3 `struct TrainerClass` (`src/battle_main.c`, NOT the `.party` pipeline)

```c
struct TrainerClass { u8 name[13]; u8 money; u16 ball; };
const struct TrainerClass gTrainerClasses[TRAINER_CLASS_COUNT] = { ... };
```

**A real, non-obvious finding**: unlike individual trainers (defined in the
friendly `trainers.party` text format, see §1.6), the **116** trainer
*classes* are a plain hardcoded C designated-initializer array directly in
`battle_main.c` — no companion `.party`-style file exists for classes. Money
values observed range 1-50 (e.g. Swimmer=2, Hiker=10, Beauty/Lady/Rich
Boy=20-50); many entries (Team Aqua/Magma grunts, `PKMN_TRAINER`) omit money
entirely, which the money formula (§3) treats as 0 → falls back to 5. The
Python converter needs a **second, small parser** for this array specifically
(a regex over the designated-initializer block — the same class of
direct-C-source parsing this project's own `gen_weight_data.py` already
established as precedent, not a new technique).

### 1.4 Trainer *Pic* — the real portrait-ID answer, quantified not guessed

`trainers.party` has a `Pic:` field per trainer (e.g. `Pic: Leader Brawly`,
`Pic: Swimmer M`). Counted directly, not assumed:

- **855 total trainer entries**, but only **93 distinct `Pic` values** —
  massive reuse (e.g. `Swimmer M`=34 trainers, `Swimmer F`=30,
  `Cooltrainer F`=30, `Hiker`=23, all sharing one portrait).

**This directly answers the Phase 3 portrait blocker**: the ID scheme
Phase 3 needs to key against is the **~93-entry Pic identifier**, NOT the
855-entry individual trainer ID. `TrainerData.trainer_id` (unique, one per
`.party` entry) and `TrainerData.trainer_pic_id` (one of ~93, many trainers
share a value) must be two **separate** fields/registries — conflating them
would either force 855 duplicate portrait assets or silently break the
many-shares-one-Pic reality. Proposed: a small separate `TrainerPicRegistry`
(or just a `.tres`-per-pic-id catalog) distinct from `TrainerRegistry`
itself, mirroring how this project's own `SpriteRegistry` (Phase 4a) is
already a separate lookup from `PokemonRegistry`.

### 1.5 Trainer Pools — a real, substantial, likely-excludable system

`include/trainer_pools.h`: an **expansion-specific, opt-in, procedural**
party-generation system — a trainer with `poolSize > 0` doesn't use its
fixed `party` array directly; instead the game picks mons from a candidate
pool at battle-start time, honoring rules (`PoolRuleset`: species clause,
exclude-forms) and per-mon role tags (`PoolTags`: Lead/Ace/Weather-Setter/
Weather-Abuser/Support/3 generic tags) via configurable pick/prune
functions. This is a genuinely separate, nontrivial mechanic layered on top
of the base trainer-party concept — **flagged as a strong exclusion
candidate for M24's first pass**, not built by default (see §6, open
question 1).

### 1.6 `src/data/trainers.party` — the actual converter input format

**Not a raw C struct table** — a **human-readable, Pokémon-Showdown-export-
style text format**, compiled to real C tables at build time by a dedicated
tool (`tools/trainerproc`). Confirmed via direct inspection of a real entry:

```
=== TRAINER_BRAWLY_1 ===
Name: BRAWLY
Class: Leader
Pic: Leader Brawly
Gender: Male
Music: Male
Items: Super Potion / Super Potion
Double Battle: No
AI: Basic Trainer

Machop
Level: 16
IVs: 12 HP / 12 Atk / 12 Def / 12 SpA / 12 SpD / 12 Spe
- Karate Chop
- Low Kick
- Seismic Toss
- Bulk Up
```

This is genuinely good news for the converter (§5) — parsing this is much
closer to "parse a Showdown export block" (a format class this project has
zero precedent for, but which is well-documented and regular) than to
"parse arbitrary C macro-heavy struct initializers." **855** total
`=== TRAINER_XXXX ===` blocks in the file; IDs are assigned by `trainerproc`
in file order at build time (no complete hand-maintained enum exists to
reverse — `include/constants/trainers.h` only has **276** entries, a
smaller legacy/special-case subset, not the full 855) — the converter
should derive stable IDs the same way, by parsing header order directly,
not by trying to reconcile against that smaller header.

Held items: 144 of the many hundreds of individual Pokémon entries carry a
held item (`Mon Name @ Item`) — real and present, but a minority, not
universal.

## 2. AI-tier system — a much smaller practical scope than the flag count suggests

`include/constants/battle_ai.h` defines a genuine **64-bit combinable
bitmask** — **34 distinct named flags** (`AI_FLAG_CHECK_BAD_MOVE` through
`AI_FLAG_RANDOMIZE_PARTY_INDICES`, plus 4 more at bits 60-63 for
Dynamic-func/Roaming/Safari/First-Battle), each independently
togglable — genuinely not the 2-tier system this project's own M10-era
`TrainerAI` (`scripts/battle/ai/trainer_ai.gd`) currently models
(`enum Tier { BASIC, SMART }`, mapping to the two named bundles
`AI_FLAG_BASIC_TRAINER` (3 flags) and `AI_FLAG_SMART_TRAINER` (7+ flags)).

**The real, load-bearing finding**: counting actual usage across all 855
real trainers in `trainers.party` (not assumed from the flag *definitions*
alone) —

```
640  AI: Check Bad Move                                    (single flag, weaker than this project's own BASIC tier)
173  AI: Basic Trainer                                      (= this project's existing BASIC tier, exactly)
 13  AI: Check Bad Move / Try To Faint / Force Setup First Turn
  7  AI: Check Bad Move / Try To Faint
  5  AI: Basic Trainer / Risky
  1  AI: Basic Trainer / Force Setup First Turn
——
839  trainers with an AI: line (16 have none at all — likely inherit some project default)
```

**Only 6 distinct combinations are used across the entire real trainer
roster — and NONE of them include this project's own SMART tier or any of
the heavier flags** (OMNISCIENT, SMART_SWITCHING, PREDICT_MOVE, etc.).
Spot-checked the Elite Four/Champion specifically (the strongest
non-facility trainers in the game) expecting them to be the exception —
they are not: Sidney uses `Basic Trainer / Force Setup First Turn`, Steven
(Champion) uses plain `Basic Trainer`. Vanilla-based
`pokeemerald_expansion`'s own shipped trainer roster simply doesn't exercise
most of its own elaborate AI system — real difficulty in these battles
comes from party composition/levels/items, not AI sophistication.

**Practical implication**: this project's existing 2-tier `TrainerAI` is NOT
a dead end requiring a full 34-flag rebuild — it needs a small, well-scoped
extension (a `check_bad_move`-only sub-tier below BASIC, a `+Risky` and
`+Force Setup First Turn` modifier on top of either tier) to exactly cover
the 6 real combinations found, not a from-scratch bitmask AI engine. A full
bitmask model remains a legitimate FUTURE option if custom/non-vanilla
trainers are ever added, but isn't required to field the real 855-trainer
roster faithfully. Flagged as an explicit open question for Rob in §6
anyway, since it's a real design fork even at this smaller scope.

## 3. Money-yield formula — fully re-derived, not assumed

`src/battle_script_commands.c :: GetTrainerMoneyToGive`:

```c
trainerMoney = gTrainerClasses[trainerClass].money ?: 5;   // 0 (unset) falls back to 5
if (TWO_OPPONENTS)      moneyReward = 4 * lastMonLevel * moneyMultiplier * trainerMoney;
else if (IsDoubleBattle) moneyReward = 4 * lastMonLevel * moneyMultiplier * 2 * trainerMoney;
else                     moneyReward = 4 * lastMonLevel * moneyMultiplier * trainerMoney;
```

- `lastMonLevel` = the level of the trainer's **last** party member (not an
  average, not the highest).
- `moneyMultiplier` starts at 1 per battle (`battle_main.c`), doubled by the
  attacker holding **Amulet Coin** (`battle_hold_effects.c`) and separately
  doubled by a successful **Pay Day** use (`battle_script_commands.c`) —
  both already-implemented moves/items in this project (Pay Day shipped in
  `[M19a-gen1]`; Amulet Coin's own implementation status needs a quick
  confirm-not-assumed check before M24 implementation, not confirmed this
  session).
- A related but distinct mechanic, only worth flagging not scoping into
  M24: losing refunds half your money (Gen 3 rule, `B_WHITEOUT_MONEY`) — a
  battle-outcome/save-money concern, not trainer-data itself.

## 4. Rematch/postgame system — a real, save-state-heavy mechanic

`src/gym_leader_rematch.c` + `include/constants/rematches.h`: rematches are
modeled as **entirely separate trainer table entries** (e.g.
`TRAINER_BRAWLY_1`/`_2`/`_3` — confirmed 3 real entries exist for Brawly
alone in `trainers.party`), not a single trainer whose party dynamically
scales. Progression through them is tracked via:

- `gSaveBlock1Ptr->trainerRematches[]` — a **persistent, per-trainer-slot
  save-state array** (has this rematch trainer become available again?).
- `HasTrainerBeenFought(trainerId)` — a persistent "have I fought this exact
  trainer-table-entry" flag, gating which rematch tier is currently active.
- Gated behind `FLAG_SYS_GAME_CLEAR` (a postgame story flag) plus a 30%
  random roll on each relevant check (`UpdateGymLeaderRematch`, called
  periodically, not every step).
- `struct Trainer.overrideTrainer` — a distinct field, likely used for
  alternate-version trainer swaps (not fully traced this session — flagged,
  not resolved, see §6 open question 4).

**This is the single clearest "serialization-in-mind" trigger in all of
M24** (see §7) — rematch eligibility/progression is real, per-trainer,
must-survive-a-save-cycle state, not something derivable fresh from static
trainer data alone.

## 5. Proposed `TrainerData` resource shape

Following this project's `.tres`-per-ID convention (established post-M15
for moves/abilities/items, in preference to `PokemonRegistry`'s own older
bulk-JSON style — a trainer roster of 855 is the same order of magnitude as
the 934-move roster, so the newer, more actively-used convention is the
better fit):

```gdscript
class_name TrainerData
extends Resource

@export var trainer_id: int              # stable, 1 per trainers.party entry (855 total)
@export var trainer_name: String
@export var trainer_class_id: int        # -> TrainerClassData (name/money/ball), 116 total
@export var trainer_pic_id: int          # -> a SEPARATE ~93-entry portrait registry, see §1.4
@export var gender: int                  # BattlePokemon.GENDER_* reused, not a new enum
@export var is_doubles: bool
@export var ai_flags: int                # see §2 — small bitmask covering the 6 real combos, not all 34
@export var battle_items: Array[int]     # up to 4 — battle-USE items, distinct from party mons' held items
@export var money_multiplier_override: int = 0   # StartingStatuses / overrideTrainer-adjacent edge cases, see §6
@export var party: Array[TrainerPartyMon]  # see below

@export var rematch_group_id: int = -1   # -1 = not rematchable; else indexes into a rematch progression table
@export var rematch_tier: int = 0        # which entry in that trainer's own rematch sequence this IS (0 = base)
```

```gdscript
class_name TrainerPartyMon
extends Resource

@export var species_dex: int
@export var level: int
@export var nickname: String = ""
@export var move_ids: Array[int]         # fixed, up to 4 — NOT learnset-derived
@export var held_item_id: int = 0
@export var ability_id: int = 0          # explicit, not a slot index
@export var nature: int                  # BattlePokemon.NATURE_* reused
@export var ivs: Array[int]              # explicit 6 values, reuses forced_ivs shape from M18.5h-2
@export var evs: Array[int]              # explicit 6 values
@export var friendship: int = 0
@export var gender: int = -1             # -1 = use species default roll; explicit override otherwise
@export var is_shiny: bool = false
@export var ball_id: int = 0             # cosmetic only
```

**Deliberately excluded from this shape** (see §6): `teraType`,
`gigantamaxFactor`/`shouldUseDynamax`/`dynamaxLevel` (already-excluded
mechanics per this project's own long-standing Mega/Dynamax/Z-Move/Tera
scope decisions — the raw struct carries them, the schema shouldn't),
`tags`/pool fields (trainer Pools, §1.5), `startingStatus` (0 real uses in
`trainers.party`, matches the established "dormant field, don't build
unused infra" precedent from `exp_yield`/`gender_ratio` before their own
M20a/M18.5d fixes — NOT populated pending a real use case).

**Construction path**: `TrainerPartyMon` feeds directly into
`BattlePokemon.from_species(species, level, nature, ivs, friendship)` —
confirming this exact forcing-parameter API (built ahead of need during
M18.5h-1/h-2, explicitly "ready for M24" per that session's own closing
note) is sufficient with zero further `BattlePokemon` changes.

## 6. Scope decisions — resolved with Rob (same day as the recon)

All 6 questions below were originally raised as open, unresolved
exclusion/scope forks — resolved directly with Rob in a follow-up
discussion, recorded here so no future session re-derives or re-asks them.

1. **Trainer Pools (§1.5) — EXCLUDED from M24.** Re-confirmed at decision
   time (not just recommended): a direct grep of `trainers.party` found
   **zero** of the 855 real trainer entries use any pool field at all — the
   only "pool" text matches in the whole file are the move name
   "Whirlpool" (a false positive). `tools/trainerproc/main.c` does parse
   real `Pool Rules`/`Pool Pick Functions`/`Pool Prune`/`Copy Pool` fields
   from this exact file format, confirming the feature is genuinely
   available infrastructure — it's just that vanilla-based content never
   uses it (it's there for hack authors building their own custom
   procedural trainers). Building it now would be pure unused code with
   zero current consumer. Decision: excluded entirely for M24; revisit only
   if/when Rob wants to author custom procedural trainers of his own.
2. **AI-tier fidelity (§2) — NARROW extension, flagged for a future
   revisit.** `TrainerAI` gets extended just enough to cover the 6 real
   combinations found in §2 (a `Check Bad Move`-only sub-tier below BASIC,
   plus `+Risky`/`+Force Setup First Turn` modifiers) — not a full 34-flag
   bitmask engine, matching the recommendation (the real roster doesn't use
   anything heavier). **Explicitly flagged to revisit later**: Rob intends
   to reconsider AI sophistication as part of scope work starting around
   **M30 onward** — a more advanced AI build (closer to the real 34-flag
   system) is an anticipated FUTURE upgrade, not abandoned, just correctly
   sequenced after the base trainer roster is fielded. Whoever picks up
   that future AI work should start from §2's own 34-flag inventory
   directly rather than re-deriving it.
3. **Trainer scope breadth — core 855 only, rest flagged for future.** All
   855 `trainers.party` entries (gym leaders, Elite Four, rivals, generic
   trainers, gym-leader rematch entries as separate table rows) are in
   scope for M24. Explicitly DEFERRED, flagged for a future session's own
   recon rather than decided now: Trainer Tower/Trainer Hill/Battle
   Frontier-facility trainers (separate systems entirely, not part of
   `trainers.party`, not investigated this session at all), Secret Base
   trainers (`TRAINER_SECRET_BASE`'s own special-cased money-formula
   branch, §3), and the roaming-trainer/`AI_FLAG_SAFARI`/
   `AI_FLAG_FIRST_BATTLE` special cases.
4. **`overrideTrainer` field (§4) — investigate during M24 implementation,
   not a separate session.** Small, contained follow-up: trace its real
   source usage once M24a implementation actually starts, fold the finding
   directly into that sub-tier rather than spinning up a dedicated recon
   session for it.
5. **Rematch scope — ship base trainers only, defer rematch progression.**
   M24 covers the base (non-rematch) trainer roster only. The progressive
   rematch-tier system (§4) — genuinely dependent on persistent save-state
   `trainerRematches[]`/`HasTrainerBeenFought` tracking — gets its own
   dedicated future session once M33 (or an earlier interim save-state
   mechanism) actually exists to back those persistent flags, rather than
   building it now against a placeholder that would likely need rework.
6. **Held-item field (§1.1) — wire it now.** `TrainerPartyMon.held_item_id`
   feeds directly into the same `ItemManager` path a wild Pokémon's held
   item already uses — confirmed as the recommended default (very likely a
   zero-new-mechanism integration, since `ItemManager` already handles
   every held-item mechanic a wild Pokémon could carry) and locked in as
   the decision, not just landing the data field inert.

## 7. Serialization-in-mind notes (per this session's own standing
constraint — design for M33, don't build M33)

- **Rematch progression is the one genuinely unavoidable persistent-state
  concern** (§4): `trainerRematches[]`/`HasTrainerBeenFought` are real,
  per-trainer-slot save flags with no static-data equivalent. The proposed
  `rematch_group_id`/`rematch_tier` fields on `TrainerData` (§5) are
  static/read-only (which rematch SEQUENCE a trainer belongs to, and which
  step THIS specific `.tres` entry represents) — the actual "has been
  fought, is currently available" bits belong in a **separate**,
  not-yet-designed save-state structure keyed by `trainer_id`, deliberately
  NOT stored on `TrainerData` itself (a `.tres` Resource is static content,
  not a save slot — conflating the two would make every save-file schema
  change require touching the trainer-data pipeline). This mirrors this
  project's own already-established pattern of keeping `BattlePokemon`
  (runtime/mutable) separate from `PokemonSpecies` (static/shared) — the
  same static-vs-mutable split, just at the trainer-roster level.
- **Money already paid out** is NOT trainer-data at all (it's the player's
  own wallet, incremented once at battle end) — explicitly out of
  `TrainerData`'s own scope, flagged only so a future session doesn't
  accidentally bolt it on here.
- **Defeated-trainer flags for generic (non-rematchable) trainers**: even
  non-rematchable trainers need SOME "already beaten, don't re-fight on
  re-entering this map" flag in the real game — also save-state, also
  deliberately NOT part of `TrainerData` itself, for the same
  static-vs-mutable reason above. Flagged as a real M26/M33-adjacent need
  this recon surfaced, not a gap in this session's own scope.
- **Trainer ID stability across regenerations**: since `trainer_id` (§5) is
  assigned by the converter in `trainers.party`'s own file order, any
  future re-run of the converter after the source file changes (e.g. a new
  expansion version upstream) could silently renumber every trainer,
  silently invalidating every save file's own stored rematch/defeated
  flags. Recommend the converter emit IDs keyed by the literal
  `TRAINER_XXXX` name string (stable across re-generation) rather than by
  raw file-order integer, with the integer `trainer_id` derived
  deterministically FROM that stable name (e.g. a sorted-name index or a
  hash) — flagged as a design point to lock in during implementation, not
  resolved definitively this session.

## 8. Proposed Python converter (`scripts/gen_trainer_data.py`)

Mirrors the established `gen_moves.py`/`gen_abilities.py`/`gen_items.py`
shape (a Python dict → `DEFAULTS` → `FIELD_ORDER` → `render()` → `main()`
per-ID `.tres` emitter) with two genuinely new pieces neither of those
scripts needed:

1. **A real text-format parser** for `src/data/trainers.party` (855 blocks)
   — the `=== TRAINER_XXXX ===` / `Field: Value` / blank-line-separated
   Pokémon-block structure is regular enough for a straightforward
   line-oriented state-machine parser (not a general Showdown-format
   library dependency) — closer in spirit to this project's own
   `gen_move_status_table.py`-style source-scanning than to a hand-authored
   `MOVES = {...}` dict, since 855 entries is far past hand-transcription
   scale (unlike the 40-140-item batches every M18 item tier hand-wrote).
2. **A small designated-initializer parser** for `gTrainerClasses[]` in
   `battle_main.c` (116 entries, §1.3) — same class of direct-C-source
   regex parsing already established by `gen_weight_data.py`.

Both parsers write into the SAME two-track pattern every other M-tier data
pipeline uses: parsed Python data → `.tres` files under a new `data/
trainers/` (+ possibly `data/trainer_classes/`) directory → loaded via a
new `TrainerRegistry`/`TrainerClassRegistry` (`get_trainer(id)`/
`get_trainer_class(id)`, path-convention loaders mirroring `MoveRegistry`/
`ItemRegistry`, not `PokemonRegistry`'s bulk-JSON style — see §5's own
reasoning). A new `battle_ui_sprite_smoke_test.gd`-style directory-scan
smoke test (one assertion per emitted trainer, matching `move_smoke_test
.gd`'s own M19.5 precedent) is the natural first real verification once
implementation starts.

## 9. Proposed sequencing plan

Mirrors this project's own established multi-session-per-milestone
discipline (M20's core/a/b/c split, M23.11's phase split) — sub-tiers, not
one combined session, given the real scope found above:

Updated to reflect §6's resolved decisions — Trainer Pools and the full
rematch-progression system are now confirmed OUT of M24 entirely (not
deferred-pending-a-choice), and the AI-tier direction is locked in as the
narrow path:

- **M24a — Data pipeline**: `gen_trainer_data.py` (both parsers),
  `TrainerData`/`TrainerPartyMon`/`TrainerClassData` resource classes,
  `TrainerRegistry`/`TrainerClassRegistry`, the directory-scan smoke test.
  Core 855-trainer roster only (§6.3) — no Trainer Pools fields (§6.1,
  confirmed zero real usage), no Trainer Tower/Hill/Battle Frontier/Secret
  Base/roaming trainers (§6.3, deferred). Fold in a real trace of the
  `overrideTrainer` field (§6.4) as part of this sub-tier's own
  implementation, not a separate session. No battle-integration yet.
  **Low-to-medium risk** — mechanical parsing work, well-precedented
  pipeline shape, but 855+116 real entries is a large first-pass volume to
  get right.
- **M24b — Money + held items + battle-use items**: wire `GetTrainerMoney
  ToGive`'s formula (§3) into whatever end-of-battle hook this project's
  own battle-outcome handling uses; wire `battle_items`/party-mon held
  items into `ItemManager`'s existing mechanics NOW, not deferred (§6.6,
  locked in). **Low risk** — expected to be a clean reuse of existing
  `ItemManager` mechanics.
- **M24c — AI-tier extension**: extend `TrainerAI` with the NARROW
  6-combination extension only (§6.2, locked in) — a `Check Bad Move`-only
  sub-tier plus `+Risky`/`+Force Setup First Turn` modifiers. **Low risk.**
  **Flagged for a future revisit**: Rob intends to reconsider AI
  sophistication starting around M30 onward, once the base trainer roster
  is fielded — whoever picks that up should start from §2's own 34-flag
  inventory rather than re-deriving it.
- **Rematch/postgame system is OUT of M24 entirely** (§6.5, locked in) —
  not deferred-pending-a-decision, confirmed deferred. Gets its own
  dedicated future session once M33 (or an earlier interim save-state
  mechanism) exists to back `trainerRematches[]`/`HasTrainerBeenFought`'s
  persistent flags (§7).
- **Phase 3 (trainer portraits) unblocks after M24a alone** — it only needs
  the `TrainerPicRegistry`/ID scheme (§1.4), not money/AI, so it could
  reasonably run concurrently with or immediately after M24a rather than
  waiting for M24b/c.

No code written for M24 itself this session, per the task's own explicit
scope. §6 above now reflects the FINAL, resolved scope decisions — a
future M24 implementation session can proceed directly from this doc
without re-litigating any of the 6 forks.

## Appendix: test-fixing rollover (append at end of this session)

### `d4_bundle5_test.tscn` root cause and fix

Reproduced directly (not assumed RNG) by matching the exact sweep
invocation (`--autoplay` — a real, initially-overlooked difference from
plain isolated reruns, which never reproduced it in 70+ tries). With
`--autoplay` included, reproduced in ~1/15-1/40 runs. Root cause, confirmed
via a debug-instrumented scratch scene tracing every `move_executed` event:
`_test_charge`'s section (iv) snapshotted `atk3.charged` on "the next
`move_executed` event of any kind" after atk3's 3rd queued action (Thunder
Shock, which clears the flag), reasoning the clear would have already
committed. This is unreliable: once the 3-action queue drains, atk3
auto-repeats from its own `moves[0]` (Charge) — and Charge's own status-move
dispatch sets `charged = true` **before** emitting its own `move_executed`
(unlike the damaging-hit path Thunder Shock's clear lives in, which emits
`move_executed` first and clears after) — so "the next event" can itself
already reflect a re-corrupted value if it happens to be atk3's own Charge
re-cast rather than def3's reply. Fixed properly with a new, precise
`charge_cleared(mon)` signal (`battle_manager.gd`, mirroring the existing
`charge_set` signal exactly) emitted at the literal instant of the clear,
removing the ambiguity entirely. Confirmed stable across 80 consecutive
`--autoplay` reruns post-fix (0 failures) plus 3 full sweeps (all under the
same `--autoplay` invocation that originally reproduced it).

### Batch-fix: unpinned nature/IV fixture pattern (44 files)

Same fix as `m18_5g_test.gd`/`m19_rampage_test.gd`: pin
`BattlePokemon.NATURE_HARDY` + all-zero IVs on every unforced
`from_species(sp, level)` call. Applied mechanically via a small Python
script (regex-matched, not hand-edited per file) across all 44 remaining
files sharing the pattern. **3 files deliberately excluded, not fixed —
false positives, not bugs**: `m18_5d_test.gd` (tests gender-rolling
specifically; zero exact-value stat assertions anywhere in the file, so
nature/IV variance is harmless noise, not a real flake risk),
`m18_5h1_test.gd` (the Nature system's own origin test — its own E04
discriminator *requires* genuine unforced randomness to prove random
nature-rolling actually happens; pinning it would break the test's own
purpose), and `battle_test.gd` (the M1 narrative-only smoke test with no
formal pass/fail assertions at all — nothing for nature/IV variance to
break).

### Sweep results

One "before" sweep (per this session's own instruction, using last
session's recorded baseline rather than reconstructing) and two "after"
sweeps: **all three identical — 152 files, GRAND TOTAL 20198, zero
mismatched suites, byte-identical diff between the two after-runs.** No
suite's pass/fail behavior changed for any reason other than closing the
exposure (every count matches exactly; the only functional change anywhere
is `d4_bundle5_test.tscn`'s own now-fixed flake).

No commit made this session — per standing instruction, Rob commits.
