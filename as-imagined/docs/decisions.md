# Mechanic Decisions Log

Running log of mechanics verified against the `pokeemerald_expansion` source,
plus any judgment calls made where the source was ambiguous or where a
mechanic's exact behavior needed to be confirmed rather than assumed.

Format per entry:

```
## [Mechanic name]
- Source: path/to/file.c, function_name()
- Behavior: short description of what was verified
- Notes: anything ambiguous, any judgment call made, date verified
```

---

## Project Scope (established pre-M15)

**Battle Engine:** All Emerald Expansion moves and abilities. No Z-moves, Mega Evolution, or Dynamax. Two-turn moves in scope. Unique/complex moves and abilities handled individually in dedicated milestones.

**Pokémon:** All 386 Gen III Pokémon. Castform forms included. No Deoxys forms. No Unown.

**Items:** All items through Gen V. Gen VI+ items picked and chosen as needed based on mechanic dependencies.

**Berries:** All berries through Gen V. Gen VI+ picked and chosen as needed.

**Battle formats:** Singles, doubles, and 2v2 multi-battle (two separate trainers per side). Link battles out of scope.

**Testing strategy:** Straight damaging moves implemented freely. One representative test per status-move category, rest implemented with same logic. Full citation audit for complex mechanics.

**Simulator:** Standalone scene architecture. Overworld calls into battle, gets control back after. Experience, leveling, catching, and flee handled at simulator layer not engine layer.

**End goal:** Fully playable Emerald-style game with overworld, trainer data, party building, and UI in Godot.

**Timeline:** ~1 year. Solo developer with Claude Code.

---

## [M1] Data format: .tres, one file per entry

- Source: project design decision (Milestone 1)
- Behavior: All PokemonSpecies, MoveData, AbilityData, ItemData stored as
  individual Godot `.tres` Resource files under `data/pokemon/`, `data/moves/`,
  `data/abilities/`, `data/items/`. Never mix with `.json`.
- Notes: `.tres` gives load-time type validation and lets one Resource directly
  reference another (e.g. species ability slot holds AbilityData ref, not an
  int lookup). `.json` would require a manual parse layer with no type safety.
  Decision locked at Milestone 1; do not mix formats later. 2026-06-24.

## [M1] Move category: stored per-move (Physical / Special / Status)

- Source: `include/move.h`, `struct MoveInfo`, field `enum DamageCategory category`
- Behavior: Each MoveData resource carries its own `category` field
  (0 = Physical, 1 = Special, 2 = Status). The damage formula uses this to
  select Attack vs. Sp. Attack and Defense vs. Sp. Defense. This is the
  Physical/Special split that distinguishes the expanded engine from Gen I/II.
- Notes: Vanilla Gen I/II determined category by move type; the expansion
  (and Gen IV+) moved it to a per-move field. The reference struct confirms
  the per-move approach. 2026-06-24.

## [M1] Ban flags: bitmask with named bit constants on MoveData

- Source: `include/move.h`, `struct MoveInfo`, ban flag bitfields
- Behavior: MoveData stores a single `ban_flags: int` field. Named constants
  (`MoveData.BAN_GRAVITY`, `BAN_METRONOME`, `BAN_MIMIC`, etc.) define each bit.
  Callers check `move.ban_flags & MoveData.BAN_X` to test a flag.
- Notes: The reference has ~13 separate bool bitfields. Collapsing to a single
  int bitmask avoids 13 exported bools cluttering the Godot editor inspector
  and matches how they're used (queried together during move legality checks).
  Individual-bool approach would be chosen if per-flag editor inspection were
  important; it isn't for this project. 2026-06-24.

## [M1] IVs and EVs: fields present on BattlePokemon, zeroed for Milestone 1

- Source: Standard Pokémon stat formula; see `src/pokemon.c` for expansion
  stat calculation context
- Behavior: `BattlePokemon` carries `ivs: Array[int]` and `evs: Array[int]`
  (both length 6, indices: hp/atk/def/sp_atk/sp_def/speed). Set to all-zeros
  in `BattlePokemon.from_species()` for Milestone 1. The stat formula reads
  from them already so switching to real values later requires no structural
  change — only the initialization values change.
- Notes: Shedinja's 1 HP exception (HP formula clamps to 1) not yet handled;
  add when implementing Shedinja specifically. 2026-06-24.

## [M1] State machine driver: signal / explicit-advance, not _process polling

- Source: project design decision (Milestone 1)
- Behavior: `BattleManager` exposes a single public `advance()` method.
  Auto-advancing phases call `advance()` themselves at the end of their handler.
  Phases that need external input (MOVE_SELECTION in future milestones) emit
  `action_needed` and return without calling `advance()`. External code (UI,
  AI, test runner) calls `advance()` after supplying the required inputs.
- Notes: This keeps the state machine frame-rate-independent and gives the UI
  layer natural pause points without polling. Do not add a `_process()` tick
  to BattleManager. 2026-06-24.

## [M1] Milestone 1 damage: flat PLACEHOLDER_DAMAGE constant, no formula

- Source: project design decision (Milestone 1)
- Behavior: `BattleManager.PLACEHOLDER_DAMAGE = 20`. MOVE_EXECUTION applies
  this flat value regardless of stats, type, or move power. No accuracy check.
  The real damage formula (including Physical/Special split, STAB, type chart,
  random factor, crits) is Milestone 2. The constant name makes the placeholder
  impossible to confuse with a real calculation.
- Notes: Remove entirely and replace with `DamageCalculator.calculate()` call
  in Milestone 2. 2026-06-24.

---

## [M2] Base damage formula

- Source: `src/battle_util.c` :: `CalculateBaseDamage` (L7215–7218)
- Behavior: `power * attack * (2 * level / 5 + 2) / defense / 50 + 2`
  All C integer division (truncates toward zero = floor for positive values).
  Left-to-right evaluation order. In GDScript: int `/` on ints matches directly.
- Notes: No overflow risk — max intermediate value (~500 * 2000 * 22) well within 64-bit int. 2026-06-24.

## [M2] Modifier application order (DoMoveDamageCalcVars + ApplyModifiersAfterDmgRoll)

- Source: `src/battle_util.c` L7577–7628
- Behavior (M2 scope, single-target 1v1, no weather/items/abilities):
  1. Resolve attack stat (Physical→Attack, Special→SpAttack)
  2. Resolve defense stat (Physical→Defense, Special→SpDefense)
  3. Apply stat stages to both (gStatStageRatios)
  4. If crit: clamp attacker's negative stages to 0; clamp defender's positive stages to 0
  5. `base_damage = power * attack * (2*level/5+2) / defense / 50 + 2`
  6. Crit modifier: `_uq412_half_down(base_damage, 6144)` if crit  (UQ_4_12(1.5) = 6144)
  7. Random roll: `dmg = base_damage * roll / 100`, roll = uniform {85..100}
  8. STAB: `_uq412_half_down(dmg, 6144)` if move type matches attacker's type
  9. Type effectiveness: accumulate modifiers in UQ4.12 space via `_uq412_multiply` (half-UP),
     then apply combined modifier once: `dmg = _uq412_half_down(dmg, combined_uq412)`
  10. Minimum: if dmg == 0 (not from immunity), set to 1
- Notes: Immunity (type modifier = 0.0) returns 0 before damage calculation starts.
  Crit ignoring stage drops/boosts confirmed in CalcAttackStat (L6781–6783) and
  CalcDefenseStat (L7068–7070). 2026-06-24.

## [M2] UQ4.12 fixed-point multiply: uq4_12_multiply_by_int_half_down

- Source: `include/fpmath.h` :: `uq4_12_multiply_by_int_half_down` (L70–73)
- Behavior: `(modifier * value + (UQ_4_12_ROUND - 1)) / 4096 = (modifier * value + 2047) / 4096`
  (C/GDScript integer division = truncate toward zero for positive values.)
  The source comment reads: *"Returns an integer, rounded to nearest (rounding down on n.5)"*.
  This is **round half-down** — NOT floor/truncation. The rounding rules are:
  - Fractional part < 0.5 → rounds DOWN (same as floor).
  - Fractional part = 0.5 (tie) → rounds DOWN (half-down, differs from half-up).
  - Fractional part > 0.5 → rounds UP (differs from floor!).
  For individual modifier values in our pipeline (0.5×, 1.0×, 1.5×, 2.0×), the product
  `modifier * value` never produces a fractional part > 0.5, so the result coincidentally
  equals `floori()` for those specific values. The equivalence breaks for a combined 0.25×
  modifier applied in a single call: e.g. value=7 → `(1024*7+2047)/4096 = 9215/4096 = 2`,
  while `floori(0.25*7) = floori(1.75) = 1`. Do **not** substitute `floori()` for this
  primitive in general; always use the integer formula.
- Notes: GDScript int division (`/`) truncates toward zero — matches C integer division for
  positive operands. Intermediate values (modifier * value) are within 64-bit int range for
  all plausible damage values. 2026-06-24.

## [M2] Critical hit multiplier: 1.5× (Gen 6+)

- Source: `src/battle_util.c` :: `GetCriticalModifier` (L7294–7298); `include/config/battle.h` line 6
- Behavior: `B_CRIT_MULTIPLIER = GEN_LATEST` → `>= GEN_6` → multiplier = 1.5× (not 2.0×)
  Applied before the random roll.
- Notes: If a future config change to GEN_LATEST changes this, update here and in DamageCalculator. 2026-06-24.

## [M2] Critical hit odds: Gen 7+ table

- Source: `src/battle_util.c` :: `sGen7CriticalHitOdds` (L7768), `CalcCritChanceStage` (L7820),
  `IsCriticalHit` (L7916); `include/config/battle.h` line 5
- Behavior: `B_CRIT_CHANCE = GEN_LATEST >= GEN_7` → odds {stage0: 1/24, stage1: 1/8, stage2: 1/2, stage3+: always}
  In M2 the only input is `move.critical_hit_stage`. Focus Energy, Dragon Cheer,
  Laser Focus, Super Luck, Battle Armor / Shell Armor — all M8+.
- Notes: 2026-06-24.

## [M2] Random roll: uniform integer {85..100}

- Source: `src/battle_util.c` L7600; `include/battle_util.h` L82–83
- Behavior: `DMG_ROLL_PERCENT_LO = 85`, `DMG_ROLL_PERCENT_HI = 100`.
  `roll = 100 - RandomUniform(0, 15)` → discrete uniform on {85, 86, ..., 100} (16 values).
  Applied as `dmg = dmg * roll / 100` (integer division).
- Notes: 2026-06-24.

## [M2] Stat stages: gStatStageRatios table

- Source: `src/pokemon.c` :: `gStatStageRatios` (L505–520)
- Behavior: Stage -6→+6 maps to ratios [10/40, 10/35, ..., 10/10 (neutral), ..., 40/10].
  Applied integer: `stat = base_stat * ratio[0] / ratio[1]`. In BattlePokemon our
  stat_stages stores -6..+6; DamageCalculator adds 6 to get the table index.
- Notes: 2026-06-24.

## [M2] STAB: 1.5× (no Adaptability in M2)

- Source: `src/battle_util.c` :: `GetSameTypeAttackBonusModifier` (L7239–7248)
- Behavior: If move.type matches any of attacker.species.types AND move.type != TYPE_MYSTERY,
  apply 1.5× via `_uq412_half_down(dmg, 6144)`. Adaptability (2.0×) not implemented until M8.
  Struggle (move.type would be TYPE_NONE) naturally doesn't STAB.
- Notes: 2026-06-24.

## [M2] Type effectiveness chart: GEN_LATEST config applied

- Source: `src/data/types_info.h` :: `gTypeEffectivenessTable` (L14–38); `include/config/battle.h` line 45
- Behavior: `B_UPDATED_TYPE_MATCHUPS = GEN_LATEST`. Five macro substitutions resolved:
  - STL_RS (Ghost/Dark → Steel): 1.0× (was 0.5× before Gen 6)
  - PSN_RS (Bug → Poison): 0.5× (was 2.0× in Gen 1)
  - BUG_RS (Poison → Bug): 1.0× (was 2.0× in Gen 1)
  - PSY_RS (Ghost → Psychic): 2.0× (was 0.0× in Gen 1)
  - FIR_RS (Ice → Fire): 0.5× (was 1.0× in Gen 1)
  Dual-type effectiveness is computed via `MulByTypeEffectiveness` (L8083):
  `*modifier = uq4_12_multiply(*modifier, mod)` — both type modifiers are **accumulated
  in UQ4.12 space** using `uq4_12_multiply` (half-UP rounding, `+2048`). The combined
  UQ4.12 modifier is then applied **once** to the integer damage via
  `uq4_12_multiply_by_int_half_down` (`_uq412_half_down`). GDScript: `TypeChart.get_uq412`
  returns the UQ4.12 value for one type pairing; `_uq412_multiply` combines them;
  `_uq412_half_down` applies the result once. For dual 0.5× (e.g. combined 0.25×):
  `_uq412_half_down(15, 1024) = 4` (rounds 3.75 up), while per-type would give 3 —
  the source gives 4; our implementation matches.
- Notes: TYPE_STELLAR (20) row/column all 1.0 (Tera mechanic not in scope). 2026-06-24.

---

## [M3] Burn: 1/16 HP end-of-turn; halves Physical attack damage

- Source: `src/battle_end_turn.c` :: `HandleEndTurnBurn` (L565–590)
- Source: `src/battle_util.c` :: `GetBurnOrFrostBiteModifier` (L7278–7292)
- Source: `include/config/battle.h` line 28 (`B_BURN_DAMAGE = GEN_LATEST`)
- Behavior:
  - End-of-turn: `maxHP / 16` (integer division), minimum 1. (`B_BURN_DAMAGE >= GEN_7` → 1/16, not 1/8 of Gen I–VI).
  - Attack halving: If the burned Pokémon uses a Physical move, the damage is halved via `_uq412_half_down(dmg, 2048)` applied **after** type effectiveness in `ApplyModifiersAfterDmgRoll`. Special moves are unaffected.
  - Type immunity: Fire-types cannot be burned (L5291–5294).
  - (Facade exception and Guts ability: not in M3 scope.)
- Notes: Burn halving is applied to the move's damage, not to the Attack stat directly. This matters because it occurs after the random roll (unlike the old Gen I–V interpretation). GDScript implementation in `DamageCalculator.calculate` at the burn-modifier step. 2026-06-24.

## [M3] Poison: 1/8 HP end-of-turn

- Source: `src/battle_end_turn.c` :: `HandleEndTurnPoison` (L517–563) — `else` branch (L554–558)
- Behavior: `maxHP / 8` (integer division), minimum 1 per turn.
- Type immunity: Poison-types and Steel-types cannot be poisoned (L5250–5252). No Corrosion ability in M3.
- Notes: 2026-06-24.

## [M3] Toxic (badly poisoned): escalating 1/16 per turn

- Source: `src/battle_end_turn.c` :: `HandleEndTurnPoison` (L545–553)
- Source: `include/constants/battle.h` :: `STATUS1_TOXIC_COUNTER` (L190–191)
- Behavior: Counter starts at 0 on application. Each end-of-turn:
  1. Counter increments (capped at 15).
  2. Damage = `(maxHP / 16) * counter`.
  - Turn 1: counter 0→1, damage = maxHP/16 × 1.
  - Turn 15+: counter stays at 15, damage = maxHP/16 × 15.
- Same type immunity as Poison (Poison/Steel immune).
- Switch-out counter reset: not yet implemented (requires switching mechanics, M5+).
- Notes: `STATUS1_TOXIC_TURN(num) = (num) << 8`; the counter occupies bits 8–11 of status1. In GDScript, tracked as `toxic_counter: int` on BattlePokemon. 2026-06-24.

## [M3] Paralysis: 25% full-para; Gen7+ 50% speed cut

- Source: `src/battle_move_resolution.c` :: `CancelerParalyzed` (L447–458)
- Source: `src/battle_main.c` L4712–4714 (speed calculation)
- Source: `include/config/battle.h` lines 7, 43
- Behavior:
  - Full-para: `!RandomPercentage(RNG_PARALYSIS, 75)` → 25% chance to fail to move. Implemented as `randi() % 4 == 0`.
  - Speed: `B_PARALYSIS_SPEED >= GEN_7` → `speed /= 2` (50% cut). (Pre-Gen7 was `/ 4 = 75% cut`.)
  - Type immunity: `B_PARALYZE_ELECTRIC >= GEN_6` = GEN_LATEST → Electric-types cannot be paralyzed (L5272–5274).
- Notes: Speed cut applies to the value used for turn-order priority resolution (`StatusManager.effective_speed`). The raw `BattlePokemon.speed` field is unchanged; the cut is applied on read. 2026-06-24.
- Known gap (S19): source gates the paralysis speed halving on `ability != ABILITY_QUICK_FEET`
  (battle_main.c L4712). This check is absent. Currently safe — Quick Feet (ability_id 7) is
  unimplemented. Revisit when Quick Feet is added.

## [M3] Sleep: 2–4 turn duration; wakes and moves same turn

- Source: `src/battle_script_commands.c` L2176–2177 (application)
- Source: `src/battle_move_resolution.c` :: `CancelerSleep` (~L120–169)
- Source: `include/config/battle.h` line 57 (`B_SLEEP_TURNS = GEN_LATEST`)
- Behavior:
  - Duration on application: `RandomUniform(2, 4)` inclusive (B_SLEEP_TURNS >= GEN_5 path). Pin via `force_sleep_turns` in tests.
  - Each pre-move check: decrement `sleep_turns` by 1. If still > 0 → can't move. If reaches 0 → wake, status cleared, **can use move that same turn**.
  - (Early Bird halves decrement — not in M3 scope.)
- Notes: No type immunity to sleep. Nightmare and Uproar interactions: M4+. 2026-06-24.

## [M3] Freeze: 20% thaw chance per turn; thawed mon moves that turn

- Source: `src/battle_move_resolution.c` :: `CancelerAsleepOrFrozen` (L172–186)
- Source: `include/config/battle.h` line 49 (`B_FROZEN_STATUS_FAIL = GEN_LATEST`), line 50 (`B_REFREEZE = GEN_LATEST`)
- Behavior:
  - Checked in `CancelerAsleepOrFrozen` as `else if` branch (after sleep). Condition: `STATUS1_FREEZE && !MoveThawsUser(cv->move)`. If the frozen Pokémon is using a `thawsUser` move, the entire freeze block is skipped — handled instead by `CancelerThaw` (position 22 in the dispatch table, M4+ scope).
  - If frozen (and move doesn't thaw): `RandomPercentage(RNG_FROZEN, 20)` = 20% thaw. Implemented as `randi() % 100 < 20`.
  - If thaws → status cleared, **can use move that same turn**.
  - If stays frozen → can't move.
- Type immunity: Ice-types cannot be frozen (L5342). Sun weather also prevents freeze (not in M3 scope).
- Notes: `!MoveThawsUser(cv->move)` guard at L172 is not yet wired into our StatusManager since no `thawsUser` moves exist until M4. The flag will need to be checked during M4 move execution. 2026-06-24.

## [M3] Freeze — user-thaw via `thawsUser` move flag (M4+ hook)

- Source: `include/move.h` L141 (`bool32 thawsUser:1`) and L455–457 (`MoveThawsUser`)
- Source: `src/battle_move_resolution.c` :: `CancelerAsleepOrFrozen` L172 (`!MoveThawsUser(cv->move)`) and `CancelerThaw` (L586–622)
- Source: `src/data/moves_info.h` — `thawsUser = TRUE` on: Flame Wheel, Sacred Fire, Flare Blitz, Scald, Fusion Flare, Steam Eruption, Burn Up, Sizzly Slide, Pyro Ball, Scorching Sands, Hydro Steam, Matcha Gotcha (12 moves)
- Behavior: When a frozen Pokémon uses a move with `thawsUser=TRUE`, the standard 20% thaw roll in `CancelerAsleepOrFrozen` is bypassed — the move executes. `CancelerThaw` (position 22) then fires: if still frozen AND the move doesn't have `MOVE_EFFECT_REMOVE_ARG_TYPE=TYPE_FIRE` for non-Fire-types, status is cleared and a defrost message plays.
- M3 status: not implementable — requires knowing which move is being used during MOVE_EXECUTION. Hook will be: in M4 move execution, before damage, check `move.thaws_user && attacker.status == STATUS_FREEZE` → clear freeze.
- Notes: The `MOVE_EFFECT_REMOVE_ARG_TYPE/TYPE_FIRE` edge-case at L594 means a move that specifically removes "your own Fire type" won't thaw a non-Fire frozen Pokémon — only relevant to Burn Up specifically; skip for M4. 2026-06-25.

## [M3] Freeze — target-thaw when hit by Fire-type damaging move (M4+ hook)

- Source: `src/battle_script_commands.c` :: `CanFireMoveThawTarget` (~L11041–11044): `B_HIT_THAW >= GEN_3 && moveType == TYPE_FIRE && GetMovePower(move) != 0`
- Source: `src/battle_script_commands.c` :: `CanMoveThawTarget` (L11031–11033): `B_HIT_THAW >= GEN_6 && !IsSheerForceAffected(move, abilityAtk) && MoveThawsUser(move)`
- Source: `src/battle_move_resolution.c` :: `MoveEndDefrost` (L3288–3329) — loops non-attacker battlers; condition: `STATUS1_ICY_ANY && IsBattlerTurnDamaged(battler, EXCLUDING_SUBSTITUTES) && IsBattlerAlive(battler)`; if `CanFireMoveThawTarget || CanBurnHitThaw` → call `DefrostBattler`; else if `CanMoveThawTarget` → call `DefrostBattler`
- Source: `include/config/battle.h` line 118 (`B_HIT_THAW = GEN_LATEST`)
- Behavior (GEN_LATEST = GEN_6+ path): Any Fire-type move with power > 0 that deals damage to a frozen target clears STATUS1_FREEZE after damage is dealt. `thawsUser` moves (Scald etc.) additionally thaw the target (Gen6+). The thaw is a post-damage move-end effect, not a pre-damage effect.
- M3 status: **not implementable now** — `MoveEndDefrost` requires `IsBattlerTurnDamaged`, which is move-execution state (did the hit connect and deal damage this turn?). Not tracked until M4.
- M4 hook: In MOVE_EXECUTION's post-damage step, after damage is applied to the target, check: `(move.type == TYPE_FIRE && move.power > 0) && target.status == STATUS_FREEZE` → clear freeze. Mirror the `MoveEndDefrost` loop. Add to the post-damage processing that M4 will build.
- Notes: `CanBurnHitThaw` (L10010) applies only to `B_HIT_THAW <= GEN_2` (burn-inflicting moves thaw) — irrelevant at GEN_LATEST. 2026-06-25.

## [M3] Confusion: 33% self-hit (Gen7+); 2–5 turn volatile duration

- Source: `src/battle_move_resolution.c` :: `CancelerConfused` (L389–430)
- Source: `include/config/battle.h` lines 8, 199 (`B_CONFUSION_SELF_DMG_CHANCE = GEN_LATEST`, `B_CONFUSION_TURNS = 5`)
- Source: `src/battle_script_commands.c` L2363 (application duration)
- Behavior:
  - Duration on application: `RandomUniform(2, B_CONFUSION_TURNS=5)` = 2–5 turns.
  - Each pre-move check: decrement `confusion_turns` by 1.
    - If still > 0: 33% chance self-hit (`B_CONFUSION_SELF_DMG_CHANCE >= GEN_7`). If self-hit → deal damage and skip move. If no self-hit → move executes.
    - If hits 0: snap out, **move executes that turn**.
  - Confusion is a volatile status — coexists with any major status (burn, para, etc.).
- Notes: Self-hit damage formula below. 2026-06-24.

## [M3] Confusion self-hit damage: base power 40, Physical, no roll

- Source: `src/battle_move_resolution.c` :: `CancelerConfused` (L402–413)
- Source: `src/data/moves_info.h` L38 (`MOVE_NONE.category = DAMAGE_CATEGORY_PHYSICAL`)
- Source: `src/battle_util.c` L7598–7607 (`randomFactor = FALSE` → returns before roll and `ApplyModifiersAfterDmgRoll`)
- Behavior: `DamageContext` with `battlerAtk==battlerDef`, `MOVE_NONE` (Physical), `TYPE_MYSTERY`, `isCrit=FALSE`, `randomFactor=FALSE`, `fixedBasePower=40`.
  - Because `randomFactor=FALSE` the function returns **before** `ApplyModifiersAfterDmgRoll`: no random roll, no STAB, no type effectiveness, **no burn halving**.
  - Formula: `40 * attack_staged * (2*level/5+2) / defense_staged / 50 + 2`
  - Stat stages applied normally; minimum damage = 1.
- Notes: This is the only place in M3 where Physical Attack/Defense is used for a non-move calculation. The formula is identical to the base damage formula but with fixed power=40, self-targeting, and no post-roll modifiers. 2026-06-24.

## [M3] One major status at a time

- Source: `src/battle_util.c` :: `CanSetNonVolatileStatus` (L5391)
- Behavior: If `gBattleMons[battlerDef].status1 & STATUS1_ANY` → fails (`BattleScript_ButItFailed`). A Pokémon can have at most one of: burn, freeze, paralysis, poison, toxic, sleep.
- Notes: Confusion is a volatile status (not in STATUS1_ANY) and CAN coexist with any major status. 2026-06-24.

## [M3] Pre-move check order: (sleep+freeze) → confusion → paralysis

- Source: `include/constants/battle_move_resolution.h` `enum CancelerState` (L22–46): `CANCELER_ASLEEP_OR_FROZEN` (pos 5) < `CANCELER_CONFUSED` (pos 15) < `CANCELER_PARALYZED` (pos 17)
- Source: `src/battle_move_resolution.c` dispatch table (L2399–2438): each enum value maps to its function; functions run in enum order
- Source: `src/battle_move_resolution.c` :: `CancelerAsleepOrFrozen` (L115–189) — sleep and freeze are handled in a **single combined** function: checks `STATUS1_SLEEP` first, then `else if STATUS1_FREEZE`. Since a Pokémon can only have one major status, checking them in a single function is equivalent to checking them sequentially.
- Behavior: The effective order for M3 conditions is: **(sleep or freeze) → confusion → paralysis**. Each canceler returns `CANCELER_RESULT_FAILURE` on block, causing the chain to abort — later cancelers don't run. A self-hitting-confused Pokémon that is also paralyzed: confusion fires first and returns early; the full-para roll is never evaluated.
- Intermediate cancelers between ASLEEP_OR_FROZEN and CONFUSED (power-points check, obedience, truant, focus-punch, flinch, disabled, volatile blocked, taunted, imprisoned) are M4+ scope and are not implemented in M3.
- `CANCELER_GHOST` (pos 16) sits between CONFUSED and PARALYZED — it's the Gen I Pokémon Tower ghost mechanic and is irrelevant to the modern engine.
- Notes: The M3 status_test.gd S11b and S12 tests pin the ordering. 2026-06-25.

---

## [M4] Move data format: one .tres per move, path-convention loading

- Source: project decision (Milestone 1 locked) — see `[M1] Data format: .tres, one file per entry`
- Behavior: Each move is stored at `res://data/moves/move_NNNN.tres` where NNNN is the move's
  canonical ID zero-padded to 4 digits, matching `include/constants/moves.h` in pokeemerald_expansion.
  `MoveRegistry.get_move(id)` constructs the path from the ID and calls `ResourceLoader.load()`.
  No dictionary or preload table. Adding a move = drop a correctly-named file, nothing else.
- Loader approach rationale: Convention-based beats a preloaded dictionary at scale.
  A dictionary of `preload()` calls embeds all resource paths at startup and requires a
  two-step add (file + dictionary entry). Convention-based is lazy (loads on demand, Godot
  caches), single-step to add, and the path is derivable from the move ID alone.
  Re-evaluate if lookup latency matters at full scale (~900 moves); if so, build a path
  cache from `DirAccess.get_files_at("res://data/moves/")` on first use.
- Validated at 20 files (Tier-1, Milestone 4). 2026-06-25.

## [M4] Tier-1 moves: 20 pure-damage moves, GEN_LATEST values

- Source: `src/data/moves_info.h` (power, type, category, accuracy, pp, flags per move)
- Source: `include/constants/moves.h` (canonical move IDs)
- Behavior: 20 moves with IDs and GEN_LATEST values:
  - Pure damage (EFFECT_HIT, no secondary): Pound(1), Karate Chop(2), Scratch(10),
    Wing Attack(17), Vine Whip(22), Tackle(33), Strength(70), Rock Throw(88),
    Quick Attack(98), Swift(129), Aerial Ace(332), Water Gun(55), Surf(57)
  - Damage with M5 secondaries (effect field present in data, not yet wired):
    Body Slam(34) 30% para, Ember(52) 10% burn, Flamethrower(53) 10% burn,
    Ice Beam(58) 10% freeze, Psybeam(60) 10% confusion, Thunder Shock(84) 10% para,
    Rock Slide(157) 30% flinch
  - Moves swapped out / not included: Earthquake (EFFECT_EARTHQUAKE, doubles-aware special
    behavior), Headbutt (flinch secondary), Iron Head (flinch secondary), Flash Cannon
    (SpDef drop secondary) — all M5+ effects.
  - Karate Chop: critical_hit_stage=1 (high-crit flag, source L79). Not a secondary effect
    — crits are already wired in DamageCalculator.
  - Quick Attack: priority=1 (confirmed in source L641).
  - Tackle: power=40 (B_UPDATED_MOVE_DATA >= GEN_7 path, source L893).
  - Vine Whip: power=45, pp=25 (B_UPDATED_MOVE_DATA >= GEN_6 path, source L614–615).
  - Surf: power=90 (B_UPDATED_MOVE_DATA >= GEN_6 path, source L1536).
  - Swift, Aerial Ace: accuracy=0 = always hits (source L3508, L9062).
- Notes: Move `description` field intentionally left empty for all Tier-1 moves; fill during
  UI milestone. `effect` field left at 0 (EFFECT_HIT); real secondary effects wired in M5. 2026-06-25.

## [M4] Freeze-thaw hooks: target-thaw and user-thaw now live

- Source: `src/battle_script_commands.c` :: `CanFireMoveThawTarget` (~L11041–11044)
- Source: `src/battle_move_resolution.c` :: `MoveEndDefrost` (L3288–3314)
- Source: `src/battle_move_resolution.c` :: `CancelerThaw` (L586–622); `!MoveThawsUser` guard at L172
- Behavior — two hooks in `BattleManager._phase_move_execution()`:
  1. **User-thaw** (fires before damage): `StatusManager.check_user_thaw(attacker, move)` —
     clears attacker's STATUS_FREEZE if `move.thaws_user=true`. Also wires the bypass in
     PRE_MOVE_CHECKS: a frozen Pokémon using a thawsUser move gets `force_freeze_thaw=true`
     passed to `pre_move_check` so the freeze block is skipped.
  2. **Target-thaw** (fires after damage): `StatusManager.check_target_thaw(defender, move, damage)` —
     clears defender's STATUS_FREEZE if `move.type==FIRE && move.power>0 && damage>0`.
     Both helpers live in `StatusManager` so move_test.gd can call them directly without
     going through the full BattleManager loop.
- Exercise status at Tier-1: target-thaw is exercised by Flamethrower (Tier-1 Fire move)
  hitting a frozen target — verified in move_test.gd T3a. User-thaw hook is wired but not
  exercised until Flame Wheel/Sacred Fire/Scald/etc. are added in a later milestone.
- Notes: `CanMoveThawTarget` (Gen6+ `thawsUser` moves also thaw the defender) is not yet
  wired; add when thawsUser moves are added (same point user-thaw becomes exercisable). 2026-06-25.

## [M1] PokemonSpecies.learnset: defined now, empty for Milestone 1

- Source: `include/pokemon.h`, `struct SpeciesInfo`, field `levelUpLearnset`
- Behavior: `PokemonSpecies` has `learnset: Array[Dictionary]` with entries
  `{"level": int, "move_id": int}`. Populated with real data in Milestone 4+.
  Milestone 1 test Pokémon have their moves assigned directly on `BattlePokemon`
  rather than derived from the learnset.
- Notes: 2026-06-24.

---

## [M5] Stat-stage system: gStatStageRatios integer path

- Source: `src/battle_util.c` :: `GetStatValue` / `gStatStageRatios` table (L825 approx.)
- Behavior: 13-entry table indexed by stage+6 (0=-6, 6=neutral, 12=+6). Applied as
  `stat = base * ratio[0] / ratio[1]` (integer division). Values:
  -6=[2,8], -5=[2,7], -4=[2,6], -3=[2,5], -2=[2,4], -1=[2,3], 0=[2,2],
  +1=[3,2], +2=[4,2], +3=[5,2], +4=[6,2], +5=[7,2], +6=[8,2].
  Stat stages flow into DamageCalculator via `_apply_stage()` (already in place from M2/M3).
  `StatusManager.apply_stat_change()` applies and clamps to [-6, +6]; returns 0 if already at limit.
- Notes: Accuracy/evasion stages (Sand Attack, etc.) enter the accuracy check path via
  ACCURACY_STAGE_RATIOS (separate table, see accuracy decision below), NOT the damage-stat
  multiplier path. Verified 2026-06-25.

## [M5] Accuracy check: gAccuracyStageRatios and check_accuracy()

- Source: `src/battle_script_commands.c` :: `Cmd_accuracycheck` (L1058); `gAccuracyStageRatios` (L825)
- Source: `src/battle_util.c` :: `GetTotalAccuracy` (L10241–10281)
- Behavior: All moves pass through `StatusManager.check_accuracy()` before effect application.
  Combined stage = attacker.STAGE_ACCURACY - defender.STAGE_EVASION, clamped to [-6,+6].
  `calc = moveAcc * ACCURACY_STAGE_RATIOS[stage+6][0] / ACCURACY_STAGE_RATIOS[stage+6][1]`
  (integer division). Roll succeeds if `randi() % 100 < calc`. `move.accuracy == 0` always hits.
  ACCURACY_STAGE_RATIOS: -6=[33,100], -5=[36,100], -4=[43,100], -3=[50,100],
  -2=[60,100], -1=[75,100], 0=[1,1], +1=[133,100], +2=[166,100], +3=[2,1],
  +4=[233,100], +5=[133,50], +6=[3,1].
  Weather, abilities, and held items are M8+ scope.
- Notes: Added to BattleManager._phase_move_execution() for ALL moves (status and damaging).
  Verified 2026-06-25.

## [M5] Secondary effects: Cmd_setadditionaleffects and SE_* constants

- Source: `src/battle_script_commands.c` :: `Cmd_setadditionaleffects` (L3506)
- Source: `src/data/moves_info.h` :: `additionalEffects` array per move
- Behavior: `StatusManager.try_secondary_effect(attacker, defender, move, force_secondary)`.
  If `secondary_chance == 0`, roll is skipped (effect is guaranteed — used for primary-effect
  status moves like Thunder Wave, Toxic, Confuse Ray). If `secondary_chance > 0`, roll
  `randi() % 100 < secondary_chance`. SE_FLINCH is special: `try_secondary_effect` returns
  true if roll passes but does NOT set `defender.flinched` — BattleManager does that after
  a turn-order check (flinch only effective if defender_idx > current_actor_index).
  Status/confusion effects route through existing `try_apply_status` / `try_apply_confusion`
  so type immunities and already-has-status guards are respected.
- SE_* constants (MoveData): NONE=0, BURN=1, FREEZE=2, PARALYSIS=3, SLEEP=4, TOXIC=5,
  CONFUSION=6, FLINCH=7. Verified 2026-06-25.

## [M5] Type immunity for status moves

- Source: `src/battle_util.c` :: `CanSetNonVolatileStatus` → `IsBattlerUnaffectedByMove` (L5276)
- Source: `data/battle_scripts_1.s` :: `BattleScript_EffectNonVolatileStatus` order:
  `trynonvolatilestatus` → `accuracycheck` → `setnonvolatilestatus`
- Behavior: For power==0 moves that target the opponent (`stat_change_self == false`):
  if `TypeChart.get_effectiveness(move.type, defender.species.types) == 0.0`, the move fails
  before the accuracy check (emits `move_missed(attacker, "immune")`). Examples:
  Thunder Wave (Electric) vs Ground-type: 0.0× → fails.
  Confuse Ray (Ghost) vs Normal-type: 0.0× → fails.
  Will-O-Wisp (Fire) vs Fire-type: 0.5× → does NOT fail here; `try_apply_status` blocks burn.
  Self-targeting stat changes (Swords Dance) skip this check.
- Notes: `move.type == TYPE_NONE` also skips this check (no type = no type immunity).
  Verified 2026-06-25.

## [M5] Flinch: volatile, cleared at turn start, ordered before confusion/paralysis

- Source: `src/battle_move_resolution.c` :: `CancelerFlinch` (L298–316)
- Source: `include/constants/battle_move_resolution.h` :: CANCELER_FLINCH=34, CANCELER_CONFUSED=39,
  CANCELER_PARALYZED=41 (flinch fires before confusion and paralysis in the canceler chain)
- Behavior: `BattlePokemon.flinched` is a volatile bool. Cleared in `_phase_priority_resolution`
  at the start of each turn. Set by `BattleManager._phase_move_execution()` when the SE_FLINCH
  roll passes AND `defender_idx > _current_actor_index` (defender hasn't acted yet this turn).
  `StatusManager.pre_move_check()` checks `mon.flinched` between the freeze check and the
  confusion check. If flinched: clears the flag, sets `result["flinched"]=true`, `can_move=false`.
- Notes: Flinch is silently wasted if the defender already acted this turn. Verified 2026-06-25.

## [M5] Move data: new M5 moves and wired secondaries

- Source: `src/data/moves_info.h` (GEN_LATEST); `include/constants/moves.h` (IDs)
- New stat-change moves: Swords Dance(14), Sand Attack(28), Tail Whip(39), Leer(43), Growl(45)
- New status moves: Sleep Powder(79), Thunder Wave(86), Toxic(92), Confuse Ray(109), Will-O-Wisp(261)
- New damaging move: Flame Wheel(172) — closes M4 user-thaw gap (thaws_user=true, 10% burn)
- Wired secondaries on existing Tier-1 moves: Body Slam(34)=30% para, Ember(52)=10% burn,
  Flamethrower(53)=10% burn, Ice Beam(58)=10% freeze, Psybeam(60)=10% confusion,
  Thunder Shock(84)=10% para, Rock Slide(157)=30% flinch.
- gen_moves.py redesigned to dict-based entries; now generates 31 .tres files.
  Verified 2026-06-25. move_test 43/43 still passes after regeneration.

## [M6] Two-turn charge/release state machine

- Source: `src/battle_move_resolution.c` :: `CancelerCharging` (L1737); `gLockedMoves`
- Decision: simplified from source's three-way system (`chargingTurn` in gProtectStructs,
  `multipleTurns` in gBattleMons.volatiles, `gLockedMoves` array) to a single
  `BattlePokemon.charging_move: MoveData` field. Non-null = locked to this move on turn 2.
  Produces the same observable behavior without replicating all internal machinery.
- State cleared on: turn 2 release (by BattleManager before accuracy check), or on faint
  (in `_phase_faint_check()`). Not cleared by sleep/paralysis/confusion — state persists
  through cancelers, matching source behavior (CancelerCharging fires AFTER sleep/para/confusion
  cancelers; if the Pokémon can't move, chargingTurn persists until the next turn).
- `semi_invulnerable: int` on BattlePokemon is set from `move.semi_inv_state` on charge turn;
  cleared with `charging_move` on release or faint. Source: `gBattleMons[].volatiles.semiInvulnerable`.

## [M6] Semi-invulnerable accuracy bypass

- Source: `battle_move_resolution.c` :: `CancelerAccuracyCheck` (L1993);
  `CanBreakThroughSemiInvulnerablityInternal` (battle_util.c L10464)
- Order: semi-inv check fires BEFORE accuracy roll AND before always-hit (acc==0) moves.
  Swift and Aerial Ace (acc=0) STILL miss against semi-invulnerable targets unless they have
  specific bypass flags. Source: `CanMoveSkipAccuracyCheck` only returns true for Toxic
  (always-hit-on-same-type), not for acc=0 moves in general.
- Our `check_accuracy()` places the semi-inv check AFTER `force_hit` override (test convenience)
  but BEFORE the `acc==0` return. This matches the source for all non-No-Guard scenarios.
- Bypass table: UNDERGROUND → `damages_underground` (Earthquake); ON_AIR → `damages_airborne`
  (Gust, Thunder etc — M8+; Earthquake does NOT hit airborne); UNDERWATER → `damages_underwater`
  (Surf). Source: per-state flag checks in `CanBreakThroughSemiInvulnerablityInternal`.
- Surf (57) updated with `damages_underwater=True`; Earthquake (89) added with `damages_underground=True`.

## [M6] Fixed damage and level damage: type immunity applies, modifiers do not

- Source: `battle_util.c` :: `DoMoveDamageCalc` (L7725–7727);
  `CalcTypeEffectivenessMultiplier` runs before `DoFixedDamageMoveCalc`
- Decision: type immunity (0.0×) blocks fixed/level damage moves (Dragon Rage vs Fairy = 0).
  Type effectiveness multipliers beyond 0 do NOT apply (Dragon Rage vs Steel still = 40).
  Critical hits, STAB, stat stages, and random roll are all skipped.
- Implementation: after the `effectiveness==0.0` early return in `DamageCalculator.calculate()`,
  insert `if fixed_damage > 0: return {damage: fixed_damage}` and
  `if level_damage: return {damage: attacker.level}`.

## [M6] Recoil and drain fractions — no artificial floor on result

- Recoil source: `battle_move_resolution.c` EFFECT_RECOIL case (L3371)
  `recoil = savedDmg * max(1, GetMoveRecoil(move)) / 100`
  The `max(1, ...)` applies to the PERCENTAGE (ensuring ≥1% is used), not to the result.
  So `3 * 25 / 100 = 0` — zero recoil is possible for tiny-damage hits. No floor.
- Drain source: `battle_move_resolution.c` EFFECT_ABSORB case (L2635)
  `heal = moveDamage * GetMoveAbsorbPercentage(move) / 100`
  Same pattern: `1 * 50 / 100 = 0`. No floor on heal either.
- Heal is capped at max_hp (`min(max_hp, current_hp + heal)`).

## [M6] New moves added (48 total .tres files)

- Tier-3 charge (no semi-inv): Razor Wind(13), Solar Beam(76), Sky Attack(143)
- Tier-3 semi-invulnerable: Fly(19) [ON_AIR], Dig(91) [UNDERGROUND]
- Tier-3 recoil: Take Down(36) 25%, Double-Edge(38) 33%, Brave Bird(413) 33%
- Tier-3 drain: Absorb(71), Mega Drain(72), Giga Drain(202), Drain Punch(409) — all 50%
- Tier-3 fixed: Dragon Rage(82)=40, Sonic Boom(49)=20
- Tier-3 level: Seismic Toss(69), Night Shade(101)
- Tier-3 bypass: Earthquake(89) [damages_underground]
- gen_moves.py now generates 48 .tres files. Verified 2026-06-25.
  tier3_test 62/62; all prior suites still pass.

---

## [M7] Substitute: HP cost, damage routing, block conditions

- Source: `battle_script_commands.c` :: `Cmd_setsubstitute` (L7807)
- Source: `battle_script_commands.c` :: `MoveDamageDataHpUpdate` (L1577) — `DoesSubstituteBlockMove`
- Behavior: Cost = `maxHP / 4`. Fails if `substitute_hp > 0` (already active) or `current_hp <= cost`
  (would faint creating it). On success: `current_hp -= cost`, `substitute_hp = cost`.
  Incoming damaging moves hit the substitute instead of the Pokémon unless `move.ignores_substitute`.
  Source for ignores_substitute: `ignoresSubstitute` flag in `struct MoveInfo`.
  Substitute absorbs damage; substitute_hp cannot go below 0 (clamp, then `substitute_broke` fires).
  Counter/Mirror Coat damage tracking, Bide accumulation, recoil, drain, and secondary effects are
  all suppressed when the move is absorbed by the substitute (source: they only apply on direct hits).
  Status moves targeting the opponent are blocked unless `ignores_substitute` (same flag).
- Notes: `substitute_hp` field on BattlePokemon. Cleared on faint. 2026-06-26.

## [M7] Counter / Mirror Coat: 2× reflected damage, priority −5, category-specific

- Source: `src/battle_util.c` (effect EFFECT_REFLECT_DAMAGE L7670)
- Source: `src/data/moves_info.h` MOVE_COUNTER — priority=−5, category=PHYSICAL
- Source: `src/data/moves_info.h` MOVE_MIRROR_COAT — priority=−5, category=SPECIAL
- Behavior: Counter returns `last_physical_damage * 2`; Mirror Coat returns `last_special_damage * 2`.
  Fails (`no_damage_to_counter`) if the respective damage tracker is 0 at time of use.
  `last_physical_damage` and `last_special_damage` are per-turn fields on BattlePokemon,
  cleared in `_phase_priority_resolution` (source: `gProtectStructs` is memset'd each turn).
  They are set when a direct hit (not through substitute) lands and `damage > 0`.
  The 2× damage routes through `_apply_fixed_dmg_to_target` (substitute check still applies).
- Notes: Category is the determining factor, not move type. Fighting Counter vs Special attacker: fails. 2026-06-26.

## [M7] Protect / Detect: consecutive-use formula Gen 5+

- Source: `battle_util.c` :: `CanUseMoveConsecutively` (L10862)
- Source: `include/config/battle.h` — `B_PROTECT_FAIL >= GEN_5` (GEN_LATEST path)
- Behavior: `is_protect` flag shared by Protect and Detect (same handler, same mechanic).
  Consecutive uses tracked by `protect_consecutive` on BattlePokemon. Denominator table:
  `{1, 3, 9, 27}` — first use always succeeds; nth consecutive use succeeds with probability `1/(3^n)`.
  `protect_active` is cleared at the start of each turn (PRIORITY_RESOLUTION) — it only blocks
  moves in the same turn it was activated.
  `protect_consecutive` resets to 0 on Protect failure; increments by 1 on success.
  Blocking check fires AFTER the semi-invulnerable check but BEFORE the accuracy check
  (source: `CancelerTargetFailure :: IsBattlerProtected` L2009).
  Moves with `ignores_protect=true` bypass the block (Feint etc. — M8+).
- Notes: `protect_consecutive` is NOT reset to 0 at turn start; it only resets on failure.
  This allows consecutive runs to count correctly across turns. 2026-06-26.

## [M7] Destiny Bond: flag cleared when user acts, trigger on faint

- Source: `battle_scripts_1.s` :: `BattleScript_EffectDestinyBond` — `setvolatile BS_ATTACKER, VOLATILE_DESTINY_BOND, 2`
- Source: `battle_move_resolution.c` :: `FAINT_BLOCK_TRY_DESTINY_BOND` (L2953)
- Behavior: Setting: `destiny_bond = true` on the BattlePokemon after using Destiny Bond.
  Expiry: cleared (`attacker.destiny_bond = false`) at the START of the user's next action, before
  any move logic. This means if the user is KO'd AFTER acting in a turn, the bond has already
  expired and does NOT trigger.
  Trigger: in faint check, if `had_destiny_bond` (captured before clearing on faint), the KO attacker
  also faints immediately. Both fainted signal emissions fire.
  Consecutive use fail (Gen 7+): in source, using DB when the flag is already non-zero fails.
  Our implementation always clears at action start, so a second DB use on the same turn as the first
  can't happen in 1v1; the consecutive-fail for multi-turn use is not yet wired (M8+ if needed).
- Notes: 2026-06-26.

## [M7] Disable: locks target's last move for 4 turns; bypass for charging moves

- Source: `battle_script_commands.c` :: `Cmd_disablelastusedattack` (L7898)
- Source: `include/config/battle.h` — `B_DISABLE_TIMER = 4` (Gen 5+)
- Behavior: Targets `last_move_used` on the defender. Fails if `last_move_used == null` or
  `disabled_move != null` (already disabled). Sets `disabled_move` and `disable_turns = 4`.
  Each end-of-turn: `disable_turns -= 1`; when it reaches 0, `disabled_move = null`.
  Using the disabled move causes `move_skipped("disabled")`.
  Disable `ignores_substitute=true` (source: `struct MoveInfo.ignoresSubstitute` on MOVE_DISABLE).
- Charging-move guard: a Pokémon locked into a two-turn charge cannot be stopped by Disable.
  CancelerCharging in the source overrides `gCurrentMove` before CancelerDisabled can evaluate it.
  In our implementation: disabled check includes `and attacker.charging_move == null` so locked
  Pokémon bypass the check on both the store turn and the release turn.
- Notes: 2026-06-26.

## [M7] Encore: locks target to last move for 3 turns

- Source: `battle_script_commands.c` :: `Cmd_trysetencore` (L7924)
- Source: `include/config/battle.h` — `B_ENCORE_TIMER = 4` (Gen 5+); minus 1 since target already acted
- Behavior: Fails if `last_move_used == null`, `encored_move != null` (already encored), or
  `last_move_used.ban_flags & BAN_ENCORE`. Sets `encored_move = last_move_used`, `encore_turns = 3`.
  Blocked by substitute (Encore is NOT in the `ignoresSubstitute` list).
  In `_phase_move_selection`, an encored Pokémon's chosen move is forced to `encored_move`.
  Each end-of-turn: `encore_turns -= 1`; when 0, `encored_move = null`.
- Notes: 2026-06-26.

## [M7] Bide: 2-turn accumulation, release 2× total, charged via charging_move

- Source: `battle_move_resolution.c` :: `CancelerBide` (L1106)
- Source: `src/data/moves_info.h` MOVE_BIDE — priority=+1
- Behavior: Turn 1 (setup): `bide_turns = 2`, `bide_damage = 0`, `charging_move = bide` (locks the move).
  Turn 2 (store): `bide_turns -= 1` (→1 > 0 → store turn), `bide_storing` emitted.
  Turn 3 (release): `bide_turns -= 1` (→0), `charging_move = null`, release fires.
  Release: `bide_dmg = bide_damage * 2`. If 0 → `move_effect_failed("bide_no_energy")`.
  Damage accumulation: direct hits to the Pokémon (not through substitute) add to `bide_damage`.
  Source: `gBideDmg[battler] += gBattleStruct->moveDamage[battler]` (L1634).
  Bide uses `charging_move` to lock the Pokémon to it across turns — same mechanism as two-turn
  charge moves. The `two_turn` block in BattleManager uses `not move.is_bide` guard so Bide's
  locking goes through the dedicated bide state machine block instead.
  The disabled-move guard (`attacker.charging_move == null`) also applies to Bide's lock,
  ensuring Disable cannot interrupt a Bide in progress (same source rationale as charging moves).
- Notes: 2026-06-26.

## [M7] Metronome: random move from non-banned pool

- Source: `battle_move_resolution.c` :: `GetMetronomeMove` (L4998)
- Source: `struct MoveInfo` — `metronomeBanned` flag (= `BAN_METRONOME` in our system)
- Behavior: Scans `res://data/moves/` for all `.tres` files; builds a pool of moves where
  `(ban_flags & BAN_METRONOME) == 0`. Picks one uniformly at random via `randi() % pool.size()`.
  The called move replaces the original move object for the remainder of the execution path —
  it routes through all normal effect handlers (damage, status, stat change, etc.).
  `move_called` signal fires with the chosen move before execution.
  If pool is empty (degenerate case): `move_effect_failed("metronome_no_moves")`.
  `last_move_used` is set to the ORIGINAL Metronome move (not the called move) — consistent with
  source where gLastMoves[] tracks the move slot used, not the called move.
  Wait: actually the code sets `attacker.last_move_used = move` AFTER the Metronome redirect,
  where `move` has been overwritten with the called move. This means last_move_used = called move.
  This is fine for M7; revisit if Encore/Disable interactions with Metronome-called moves matter.
- Notes: `BAN_METRONOME` flag set on: Counter, Protect, Detect, Destiny Bond, Disable, Encore, Bide,
  Metronome itself, Substitute, Mirror Coat — all moves in our Tier-4 set. 2026-06-26.

## [M7] New moves added (58 total .tres files)

- Tier-4: Disable(50), Counter(68), Bide(117), Metronome(118), Substitute(164),
  Protect(182), Destiny Bond(194), Detect(197), Encore(227), Mirror Coat(243)
- gen_moves.py updated to generate 58 .tres files.
- tier4_test 86/86; all prior suites still pass. 2026-06-26.

---

## [M8] Advance() iterative refactor (pre-M8)

- Source: N/A (internal engine architecture)
- Behavior: `BattleManager.advance()` was already iterative by M7 completion (the while-loop
  with `_is_advancing` guard and `MAX_PHASES_PER_ADVANCE = 4096` cap). No phase handler calls
  `advance()` directly — each sets `_phase` and returns; the while-loop drives the next phase.
  Confirmed all 7 prior suites passed without change. No standalone commit needed since the
  refactor was already in the M7 staged work.
- Notes: 2026-06-26.

## [M8] Ability dispatch architecture

- Source: `battle_util.c` :: `AbilityBattleEffects(enum AbilityEffect caseID, ...)` (L2919)
- Behavior: Implemented as a static class `AbilityManager` with named entry points per trigger
  type, mirroring the source's `ABILITYEFFECT_*` enum cases:
  - `attack_modifier_uq412(attacker, move)` → Huge Power / Pure Power (Physical ×2)
  - `defense_damage_modifier_uq412(defender, move)` → Thick Fat (Fire/Ice ×0.5)
  - `blocks_move_type(defender, move_type)` → Levitate (Ground immunity)
  - `try_switch_in(pokemon, opponent)` → Intimidate
  - `try_end_of_turn(pokemon)` → Speed Boost
  - `try_contact_effects(attacker, defender, move, damage)` → Static / Flame Body / Rough Skin
  - `try_synchronize(holder, attacker, applied_status)` → Synchronize
- Notes: Hooks are inserted at specific points in DamageCalculator and BattleManager to mirror
  the ordering in the source. 2026-06-26.

## [M8] Huge Power / Pure Power: attack modifier position in damage pipeline

- Source: `battle_util.c` :: `GetAttackStatModifier` (L6800); called after stat stages are applied,
  returns UQ_4_12(2.0) = 8192 for Huge Power/Pure Power + Physical moves.
- Behavior: Applied to `atk` via `_uq412_half_down(atk, 8192)` AFTER stat-stage clamping and
  BEFORE the base damage formula. Pure Power treated identically (same case in source).
- Notes: The damage formula's `+2` constant means final output damage is NOT exactly 2× the
  baseline — the ratio is ≈1.9×. Tests verify the modifier value (UQ4.12=8192) rather than
  a 2× damage ratio. 2026-06-26.

## [M8] Thick Fat: damage modifier position in damage pipeline

- Source: `battle_util.c` :: `GetDefenseStatModifier` (L6933–6941)
- Behavior: Applied to `dmg` AFTER type effectiveness and BEFORE the burn modifier. If the
  incoming move is TYPE_FIRE or TYPE_ICE, damage is multiplied by 0.5× (UQ4.12=2048).
  Inserted as a Thick Fat hook between the type-effectiveness block and burn block in
  DamageCalculator.calculate().
- Notes: 2026-06-26.

## [M8] Levitate: immunity check position in damage pipeline

- Source: `battle_util.c` :: `CalcTypeEffectivenessMultiplierInternal` — Levitate check at
  top of type lookup before any multiplier is applied.
- Behavior: Checked BEFORE the type-immunity chart in DamageCalculator. If
  `AbilityManager.blocks_move_type(defender, move.type)` returns true (Levitate + Ground),
  returns `{damage: 0, is_crit: false, effectiveness: 0.0}` immediately. This ensures Levitate
  takes precedence over type effectiveness (Ground is normally 1× vs Normal, so no conflict in
  current tests, but the ordering is correct for future type matchups).
- Notes: No gravity or mold breaker in M8 scope. 2026-06-26.

## [M8] Synchronize: reflected status and attacker reference

- Source: `battle_script_commands.c` :: `TrySynchronizeActivation` (L2130–2162)
- Behavior: Fires for BURN, PARALYSIS, POISON, TOXIC applied to the holder. Does NOT fire for
  SLEEP or FREEZE (verified against source's trigger list). Attempts to apply the same status
  back to the attacker via `StatusManager.try_apply_status`. Returns 0 if the back-application
  fails (attacker already has a status, or attacker is immune).
  `_try_synchronize` in BattleManager takes `(holder, attacker, applied_status)` — the "attacker"
  is the pokemon that inflicted the status (NOT a BattleManager combatant index).
- Notes: The signature passes the attacker directly rather than looking up by side index.
  Synchronize for contact-based status (Static/Flame Body) fires in the contact-effects path.
  2026-06-26.

## [M8] Static / Flame Body: 30% trigger chance

- Source: `battle_util.c` :: `AbilityBattleEffects(ABILITYEFFECT_MOVE_END, ...)` (L4091, L4114)
  `B_ABILITY_TRIGGER_CHANCE >= GEN_4` → 30% (not 1/3 ≈ 33.3%)
- Behavior: On contact moves, rolls `randi() % 100 < 30`. Static applies STATUS_PARALYSIS;
  Flame Body applies STATUS_BURN. Only fires if the target doesn't already have a status
  (checked via `StatusManager.try_apply_status` return value).
- Notes: The `force_contact_roll` parameter to `try_contact_effects` bypasses the RNG for
  deterministic testing. 2026-06-26.

## [M8] Rough Skin: damage = maxHP/8

- Source: `battle_util.c` L3965: `B_ROUGH_SKIN_DMG >= GEN_4` → `max_hp / 8` (not / 16)
- Behavior: On contact moves, deals `defender.max_hp / 8` damage to the attacker. Emitted via
  the existing `recoil_damage` signal in BattleManager. Applied as actual HP reduction.
- Notes: Gen-3 would use maxHP/16; we use GEN_4+ constant as this targets the expanded engine.
  2026-06-26.

## [M8→A7] Speed Boost: BattlerJustSwitchedIn gate

- Source: `battle_util.c` :: `AbilityBattleEffects(ABILITYEFFECT_ENDTURN, ...)` (L3605):
  `if (!BattlerJustSwitchedIn(battler))` guard before applying the +1 Speed.
- Source: `BattlerJustSwitchedIn` (battle_util.c L10982): returns true when `isFirstTurn == 2`.
  `isFirstTurn` is set to 2 at mid-battle switch-in (battle_main.c L3198/L3309) and decremented
  at turn-end cleanup (L5038).
- Behavior (A7, post-M9 fix): Mirrored via `BattlePokemon.switched_in_this_turn`. Set to true in
  `_do_voluntary_switch`, `_do_forced_switch_in`, and `_do_switch_in` (all mid-battle switch-in
  paths). Cleared at the start of each turn in `_phase_priority_resolution`. Speed Boost is gated
  on `not pokemon.switched_in_this_turn` in `AbilityManager.try_end_of_turn`.
- Notes: M8 stub ("always false, revisit with switching") replaced by correct implementation
  after M9 added switching. Verified by S3B.07–S3B.10 in ability_test. 2026-06-26 (stub),
  2026-06-30 (A7 fix).

## [M8→M11] Drizzle / Drought: un-stubbed in M11

- Source: `battle_util.c` :: `AbilityBattleEffects(ABILITYEFFECT_ON_SWITCHIN, ...)` —
  `ABILITY_DRIZZLE` (L3213) → `TryChangeBattleWeather(BATTLE_WEATHER_RAIN)`;
  `ABILITY_DROUGHT` (L3242) → `TryChangeBattleWeather(BATTLE_WEATHER_SUN)`.
- Behavior: In M11 the weather system is fully implemented. Drizzle and Drought now set field
  weather on switch-in. The call goes through `AbilityManager.get_switch_in_weather(mon)` (a
  query function returning WEATHER_RAIN or WEATHER_SUN), which BattleManager then passes to
  `try_set_weather()`. This split keeps AbilityManager stateless while BattleManager owns the
  weather field effect.
- Notes: 2026-06-26 (stub), un-stubbed 2026-06-27.

## [M8] Intimidate: switch-in order and opponent targeting

- Source: `battle_util.c` :: `AbilityBattleEffects(ABILITYEFFECT_ON_SWITCHIN, ...)` (L3310):
  `SetStatChange(all opponents, STAT_ATK, -1)`.
- Behavior: Called in `_phase_battle_start()` for each combatant against its opponent. Emits
  `stat_stage_changed(opponent, STAGE_ATK, -1)` and `ability_triggered(holder, "intimidate")`.
  In a 1v1 battle (M8 scope), this means at most one opponent is targeted.
  `BattlePokemon.apply_stat_stage_change` clamps to -6 and returns the actual delta applied.
- Notes: In doubles/multi battles, all opponents are targeted simultaneously; deferred to M9+.
  2026-06-26.

## [M14x] Intimidate in doubles: all live opponents targeted; Gen 8 immunity omitted

- **The bug:** `_phase_battle_start`, `_do_voluntary_switch`, `_do_forced_switch_in`, and
  `_do_switch_in` all called `_get_first_opponent` + `AbilityManager.try_switch_in` once,
  meaning only slot 0 of the opposing side received the Attack drop. In doubles both active
  opposing Pokémon should be affected.
- **Source:** `battle_util.c` `AbilityBattleEffects` Intimidate case (L3310–3323):
  ```c
  for (enum BattlerId i = 0; i < gBattlersCount; i++) {
      if (IsBattlerAlly(battler, i) || !IsBattlerAlive(i)) continue;
      SetStatChange(i, STAT_ATK, -1);
  }
  BattleScriptCall(BattleScript_IntimidateActivates);  // once per activation
  ```
  `IsBattlerAlly` = same side. `IsBattlerAlive` = hp>0 AND not in gAbsentBattlerFlags.
  `SetStatChange` is a queue-append (no immunity check). The immunity check lives in
  `IsIntimidateBlocked` called inside `TryStatChange` → `Cmd_trystatchanges`.
- **Fix:** Extracted `_apply_switch_in_abilities(new_mon, mon_side)` in `BattleManager`.
  Loop shape: iterate ALL `_combatants` and filter by side — directly mirrors source loop
  structure rather than iterating only the opposing half. `ability_triggered` fires ONCE per
  activation (matching source's single `BattleScriptCall`), not once per opponent targeted.
- **Gen 8 immunity intentionally omitted:** `IsIntimidateBlocked` in `battle_stat_change.c`
  blocks Inner Focus, Scrappy, Own Tempo, and Oblivious (when `B_UPDATED_INTIMIDATE >= GEN_8`)
  and redirects Guard Dog. None of those five abilities exist in this codebase yet. If any is
  added, port `IsIntimidateBlocked`'s immunity check into `AbilityManager.try_switch_in`
  (check `opponent.ability` before calling `StatusManager.apply_stat_change`). Substitute does
  NOT protect against Intimidate — confirmed: no Substitute skip anywhere in the source path.
  2026-06-30.

## [M8] Ability IDs: sourced from include/constants/abilities.h

- Source: `pokeemerald-expansion/include/constants/abilities.h`
- 12 M8 abilities verified: Drizzle=2, Speed Boost=3, Static=9, Levitate=26, Intimidate=22,
  Rough Skin=24, Synchronize=28, Huge Power=37, Thick Fat=47, Flame Body=49, Drought=70,
  Pure Power=74.
- Notes: gen_abilities.py generates ability_NNNN.tres files with ability_id matching these
  constants. 2026-06-26.

## [Bug fix] Turn-order tiebreak: sort_custom comparator must not call randi() live

- Source: `battle_manager.gd` :: `_phase_priority_resolution()` (L~160–184)
- **The bug:** The `sort_custom` comparator called `randi() % 2 == 0` directly as the
  tiebreak when priority and effective speed were both equal. `sort_custom` requires a
  comparator to return a consistent answer for the same pair within one sort call; calling
  `randi()` live means the same pair can compare differently on successive calls within a
  single sort, which Godot flags as "bad comparison function; sorting will be broken."
- **Why it went unnoticed:** Latent since M1. The Milestone 1 dummy battle (Dummy-A vs
  Dummy-B) was designed with different speeds specifically to avoid a tiebreak. The warning
  only surfaced in M8's `ability_test` fixture, which creates matched combatants with
  identical priority and speed (e.g., the Intimidate and Synchronize tests).
- **The fix:** Pre-roll one `randi()` value per combatant into a `Dictionary` once per
  turn, keyed by `BattlePokemon` object, before calling `sort_custom`. The comparator's
  tiebreak line reads `return tiebreak[a] > tiebreak[b]` against those pre-rolled values.
  This is deterministic within the sort call while still randomizing tie order turn-to-turn
  via a fresh seed each call to `_phase_priority_resolution`.
- **Rule going forward:** Never call `randi()` (or any non-deterministic function) directly
  inside a `sort_custom` comparator. If randomized tiebreaking is needed, pre-compute the
  random values before sorting.
- Notes: 2026-06-26.

---

## [M9] Switching — volatile clear / non-volatile persist on switch-out

- Source: `battle_main.c :: SwitchInClearSetData()` (L3117)
- Behavior: Everything listed as a volatile in `constants/battle.h :: VOLATILE_DEFINITIONS`
  is cleared on switch-out (confusion_turns, charging_move, substitute_hp, flinched,
  protect flags, etc.). `STATUS1` bits (burn, poison, paralysis, sleep, freeze, toxic
  counter) are **not touched** — they persist through switch-out and switch-in.
- Toxic counter specifically: stored in `STATUS1` bits 8–11 in source. `SwitchInClearSetData`
  does not touch these bits. The toxic counter therefore persists through any voluntary switch
  (GEN_LATEST behavior). Verified via S3.09.
- Notes: 2026-06-26.

## [M9] Switch action ordering — switches before moves

- Source: `battle_main.c` L4967–4990 (action loop, `gActionsByTurnOrder`)
- Behavior: Switch actions always resolve before all move actions in the same turn, regardless
  of speed. Switch order between two switching sides follows battler index (0 before 1).
- Implementation: `_phase_priority_resolution` sorts the turn order with a key of
  `(is_switch=0 → sorts first, priority, effective_speed, pre-rolled tiebreak)`. The
  `_chosen_switch_slots[side]` Array drives whether that side's action is a switch.
- Notes: 2026-06-26.

## [M9] Baton Pass — exact passable fields

- Source: `constants/battle.h :: VOLATILE_DEFINITIONS` V_BATON_PASSABLE flag (L210);
  `battle_main.c :: SwitchInClearSetData()` stat_stages guard (L3122), substituteHP
  explicit copy (L3185).
- Behavior: **Passed through** — stat_stages (all 7), confusion_turns (VOLATILE_CONFUSION
  is V_BATON_PASSABLE), substitute_hp. **Not passed** — charging_move, flinched, protect
  flags, last_move_used, and all other non-BP-flagged volatiles.
- Notes: confusion_turns passability cannot be trivially tested end-to-end because
  `StatusManager.pre_move_check` decrements the counter before the Baton Pass save occurs
  in MOVE_EXECUTION. The `baton_passed` signal captures the post-decrement value. Verified
  via source reference + S6.11 comment. substitute_hp and stat_stages verified via S6.09–12.
  2026-06-26.

## [M9] Roar / Whirlwind — forced-switch mechanics

- Source: `data/moves_info.h :: MOVE_ROAR` (L1234), `MOVE_WHIRLWIND` (L482);
  `battle_script_commands.c` L7421 (target selection).
- Behavior: Both are `EFFECT_ROAR`. Priority −6; accuracy 0 (never miss in GEN_LATEST);
  ignoresProtect; ignoresSubstitute; soundMove (Roar). Forces the defending side's active
  mon to be replaced by a random non-fainted non-active party member. If the defending side
  has no valid switch targets, the move fails with `move_effect_failed("no_switch_target")`.
  The forced-out mon undergoes full `_switch_out_clear` (all volatiles including
  confusion_turns and charging_move reset to 0 / null).
- Implementation: `_force_roar_rng` field on BattleManager (set to -1 for real battles,
  0 for tests) overrides the random slot selection for deterministic testing.
- Notes: 2026-06-26.

## [M9] Faint replacement flow — SWITCH_PROMPT before BATTLE_END_CHECK

- Source: `battle_main.c` L3671+ (faint handling loop)
- Behavior: When a mon faints mid-turn (during ACTION_EXECUTION), the engine routes to
  FAINT_CHECK → SWITCH_PROMPT (sends in replacement) → BATTLE_END_CHECK → MOVE_SELECTION
  (if still alive). Battle does NOT end immediately on a faint — replacements are sent in
  first. Only when `_parties[side].is_fully_fainted()` returns true does BATTLE_END_CHECK
  declare a winner.
- Notes: 2026-06-26.

## [M9] GDScript lambda capture — scalar types are copies, not references

- Source: GDScript 4.x language semantics (observed via debugging in M9 test suite)
- Behavior: Lambda closures in GDScript 4.x capture **value types** (int, float, bool,
  String) **by copy** at closure creation time. Assigning to the captured copy inside the
  lambda does NOT update the variable in the enclosing scope.
- Fix: wrap any scalar that must be updated by a signal lambda in a single-element Array:
  `var result := [-1]; signal.connect(func(w): result[0] = w)`. Arrays (and all Objects)
  are reference types and share state correctly across lambda boundaries.
- Rule going forward: Never write `var x := 0; fn.connect(func(v): x = v)` and then check
  `x` after the signal fires. Use `var x := [0]; fn.connect(func(v): x[0] = v)` instead.
- Notes: 2026-06-26.

## [M9] GDScript typed Array assignment from untyped Array literal

- Source: GDScript 4.x language semantics (observed via debugging in M9 BattleManager)
- Behavior: `var arr: Array[int] = [...]; arr = [0, 0, 0]` silently fails or produces
  incorrect behavior when the right-hand side is an untyped Array literal or a plain Array
  variable. The typed Array property is not updated as expected.
- Fix: always use a loop: `for i in range(arr.size()): arr[i] = 0`. Applied in
  `BattleManager._switch_out_clear` (stat_stages reset) and `_baton_pass_apply`
  (stat_stages copy from saved data).
- Rule going forward: Never assign a plain Array literal or untyped Array to a typed
  `Array[T]` field. Always iterate element-by-element.
- Notes: 2026-06-26.


---

## [M10] Trainer AI — rule-based, not search-based

- Confirmed: `pokeemerald_expansion` AI is flag-driven scoring, NOT minimax/deep search.
  Source: `ChooseMoveOrAction_Singles` (battle_ai_main.c L856) iterates AI_FLAG bits
  and runs one scoring pass per enabled flag; highest score wins, ties random.
- Implemented two tiers:
  - **BASIC** (`AI_FLAG_BASIC_TRAINER` = CHECK_BAD_MOVE | TRY_TO_FAINT | CHECK_VIABILITY):
    move scoring only, no proactive switches.
  - **SMART** (adds `AI_FLAG_SMART_SWITCHING`): adds ShouldSwitchIfAllMovesBad and
    ShouldSwitchIfHasBadOdds proactive switch evaluation.
- Notes: 2026-06-26.

## [M10] Trainer AI — score constants (source: include/battle_ai_main.h L21-41)

- AI_SCORE_DEFAULT = 100.
- FAST_KILL = +6 (KO + attacker faster or equal speed). SLOW_KILL = +4 (KO + slower).
- BEST_EFFECT = +4 (4× effective). DECENT_EFFECT = +2 (2× effective or useful status).
- Immune move: score - 20 (RETURN_SCORE_MINUS(20), AI_CheckBadMove L1294).
- Wasted status move (target already has status): score - 10 (AI_CheckBadMove L2933).
- Two-turn non-semi-inv when being OHKOd: score - 10 (AI_CheckBadMove L1254).
- Status move scoring: condition-specific, not flat (see F25 entry below).
- Notes: 2026-06-26.

## [M10] Trainer AI — switch thresholds (source: battle_ai_switch.c)

- `ShouldSwitchIfAllMovesBad` (L484): all damaging moves type-immune → 100% switch.
  SHOULD_SWITCH_ALL_MOVES_BAD_PERCENTAGE = 100. No flag gate within SMART tier.
- `ShouldSwitchIfHasBadOdds` (L367): being OHKOd + no super-effective move + HP ≥ 50%
  → 50% switch chance. SHOULD_SWITCH_HASBADODDS_PERCENTAGE = 50.
  `_force_switch_rng` on TrainerAI overrides to 0 (stay) or 1 (switch) for tests.
- BASIC tier: NO proactive switch logic. `AI_FLAG_SMART_SWITCHING` absent from
  `AI_FLAG_BASIC_TRAINER` (constants/battle_ai.h L46), so no ShouldSwitch* calls.
- Faint replacement: `GetSwitchinCandidate SWITCHIN_CONSIDER_MOST_SUITABLE` —
  pick party member with best type effectiveness against current opponent.
  Implemented in `TrainerAI.choose_replacement`.
- Notes: 2026-06-26.

## [M10] Trainer AI — deferred scope

- Doubles AI (`AI_FLAG_DOUBLE_BATTLE`): no doubles engine implemented yet.
- Item usage AI (`battle_ai_items.c`): no held items implemented.
- Weather-based scoring: deferred in M10, resolved in M11 — see [M11] AI weather scoring below.
- `AI_FLAG_PREDICT_SWITCH`, `AI_FLAG_OMNISCIENT`, and other advanced flag tier scoring:
  beyond basic/smart scope for this milestone.
- Notes: 2026-06-26.

## [M10] Integration seam — AI plugs in at _phase_move_selection

- `BattleManager.set_trainer_ai(side, ai)` marks a side as AI-controlled.
- In `_phase_move_selection`: AI fires after lock-in (charging/encore) and after
  test queues, but before the auto-select fallback. Same ordering constraint as
  test queue_move calls — tests can pre-queue actions that override AI.
- In `_get_replacement_slot`: AI `choose_replacement` fires after test
  `_replacement_queues` but before `get_first_non_fainted_not_active` fallback.
- Notes: 2026-06-26.

---

## [M11] Weather — field effect architecture

- Source: `gBattleWeather` (global bitmask) + `gBattleStruct->weatherDuration` in source.
  Simplified to `BattleManager.weather: int` (WEATHER_NONE/RAIN/SUN/SANDSTORM/HAIL) +
  `BattleManager.weather_duration: int`.
- Weather is a **field effect**: lives on BattleManager, not BattlePokemon. Persists through
  switches because `_switch_out_clear` only touches per-Pokémon fields.
  Source: `SwitchInClearSetData` (battle_main.c L3117) does not touch `gBattleWeather`.
- Duration = 5 turns by default (source: `TryChangeBattleWeather` L1996, no rock-item extension
  in M11 scope — items are M12).
- Notes: 2026-06-27.

## [M11] Weather damage modifier — composition order

- Source: `DoMoveDamageCalcVars` (battle_util.c L7577-7614); `GetWeatherDamageModifier` (L7251).
  Order: base_damage → [WEATHER] → crit → random roll → STAB → type effectiveness → ability.
- Constants: UQ_4_12(1.5)=6144, UQ_4_12(0.5)=2048. All applied via `_uq412_half_down`.
  SUN→Fire ×1.5, SUN→Water ×0.5; RAIN→Water ×1.5, RAIN→Fire ×0.5.
- Sandstorm and Hail: no damage modifier (chip damage only, separate EOT handler).
- Discriminating test (W8a/W9a): force_roll=85, base=14 → weather-before-roll gives 17,
  weather-after-roll gives 16. Used to catch composition order mistakes.
- Notes: 2026-06-27.

## [M11] End-of-turn handler order — weather before status

- Source: `sEndTurnEffectHandlers` (battle_end_turn.c L1545):
  `ENDTURN_WEATHER(2)` → `ENDTURN_WEATHER_DAMAGE(3)` → ... → `ENDTURN_POISON(12)` → `ENDTURN_BURN(13)`.
- Weather duration ticks (and may expire) BEFORE weather chip damage fires.
  Both fire BEFORE poison/burn status damage.
- Chip damage: `GetNonDynamaxMaxHP(battler) / 16` (integer division).
  Source: `HandleEndTurnWeatherDamage` (battle_end_turn.c L100-186).
- Notes: 2026-06-27.

## [M11] Sandstorm/Hail immunity — type-based only

- Source: `HandleEndTurnWeatherDamage` (battle_end_turn.c L148/L171).
  Sandstorm immune: any type is Rock(6), Ground(5), or Steel(9); also semi-invulnerable.
  Hail immune: any type is Ice(16); also semi-invulnerable.
  `IS_BATTLER_ANY_TYPE` (sandstorm) vs `IS_BATTLER_OF_TYPE` (hail) — sandstorm matches any
  of three types, hail matches exactly one. Both use the same macro family.
- Ability-based immunities (Sand Veil, Sand Force, Sand Rush, Overcoat, Magic Guard) deferred
  to M12 — not in scope while those abilities are absent.
- Notes: 2026-06-27.

## [M11] AI weather-aware scoring — architecture proof

- The M10 deferral ("weather-aware scoring") is closed by the M10 architecture paying off:
  `TrainerAI._score_move` calls `DamageCalculator.calculate(..., weather)`. Since calculate()
  now applies the weather modifier, the AI's damage estimate automatically reflects the field
  weather. No AI-specific weather logic was added.
- `choose_action(weather)` → `_score_move(weather)` → `DamageCalculator.calculate(..., weather)`.
  Weather propagates as a parameter; the AI sees the boosted/reduced estimate with zero
  TrainerAI code change.
- Test seams `_force_roll: int` and `_force_crit: Variant` added to TrainerAI to make the
  AI's damage estimate deterministic in tests (W13 suite).
- Verified by W13: under RAIN, Surf estimate = 85 > 70 HP → FAST_KILL (+6) chosen over Ember
  (estimate = 13). Under no weather, both estimates < 70 HP → tie, both score 100.
- Notes: 2026-06-27.
# Mechanic Decisions Log

Mechanic-specific decisions verified against `reference/pokeemerald_expansion` source.
Every claim here has a live source citation — nothing from memory.

---

## M11: Weather (2026-06-27)

### Weather damage modifiers
- Rain: Water ×1.5, Fire ×0.5. Sun: Fire ×1.5, Water ×0.5.
- Source: `GetWeatherDamageModifier` (battle_util.c L7251–7276).
- UQ4.12 values: 6144 (1.5×), 2048 (0.5×). Source: include/fpmath.h.

### Weather duration
- Default 5 turns. Rock items extend to 8.
- Source: `TryChangeBattleWeather` (battle_util.c L1993–1996).

### Utility Umbrella
- Strips rain/sun modifier for holder (attacker or defender).
- Source: `GetAttackerWeather` (L9281–9290) and `GetWeatherDamageModifier` (L7258).

### AI weather-aware scoring
- AI calls `DamageCalculator.calculate` with the current weather field. The damage
  calculator already applies weather modifiers, so the AI's KO detection reflects
  weather automatically — zero AI-specific weather logic needed.
- Source: M11 architecture decision — proven by discriminating test (rain boosts
  Water Gun past KO threshold vs sun where it falls short).

---

## M12: Held Items (2026-06-27)

### Damage composition order
Full pipeline (source: `CalculateBaseDamage` + `ApplyModifiersAfterDmgRoll`, battle_util.c):
1. Ability atk modifier (Huge Power / Pure Power) — `GetAttackStatModifier` L6800.
2. **Item atk modifier** (Choice Band/Specs) — `GetAttackStatModifier` L6989–6996. Applied to stat BEFORE base formula.
3. Base formula: `power * atk * (2*level/5+2) / def / 50 + 2` (integer left-to-right).
4. Weather modifier — `GetWeatherDamageModifier` L7251.
5. Crit — `GetCriticalModifier` L7294.
6. Random roll — `DoMoveDamageCalcVars` L7598 (85–100, applied as `dmg*roll/100`).
7. STAB — `GetSameTypeAttackBonusModifier` L7239.
8. Type effectiveness — `CalcTypeEffectivenessMultiplierInternal` L8134 (combined UQ4.12 apply).
9. Ability def modifier (Thick Fat) — `GetDefenseStatModifier` L6933.
10. Burn — `GetBurnOrFrostBiteModifier` L7278.
11. **Life Orb** — `GetAttackerItemsModifier` L7497 (post-roll, after STAB/type/burn).
12. **Resist Berry** — `GetDefenderItemsModifier` L7510 (after Life Orb).

### UQ4.12 constants
- Choice Band/Specs: 6144 (=1.5 × 4096). Source: `UQ_4_12(1.5)` in fpmath.h.
- Life Orb: 5324 (=floor(1.3 × 4096)). Source: `UQ_4_12_FLOORED(1.3)`.
- Resist berry: 2048 (=0.5 × 4096). Source: `UQ_4_12(0.5)`.

### Choice lock
- `choice_locked_move` set by BattleManager when a choice-item holder uses a move (first use only).
- Cleared on switch-out (`_switch_out_clear`). NOT cleared on faint (fainted mon has no future turns).
- Source: `SwitchInClearSetData` (battle_main.c L3117) clears `chosenMovePositions`.
- In `_phase_move_selection`: if locked, that move is returned directly without re-querying the AI.

### Berry triggers
- Resist berry: triggers on super-effective hit (≥2.0×) matching berry's type param.
  Source: `GetDefenderItemsModifier` L7510–7524. Consumed after damage.
  Known gap (I2): source has a second trigger branch — `moveType == TYPE_NORMAL` bypasses
  the ≥2.0× threshold entirely (Normal moves can never be super-effective, so the threshold
  check would always fail). This is what allows Chilan Berry (Normal-type resist berry,
  `hold_effect_param == TYPE_NORMAL`) to function. Currently unreachable: no Chilan Berry
  exists in the implemented item set (`hold_effect_param` is never TYPE_NORMAL). Revisit
  when Chilan Berry is added.
- Sitrus Berry: heals 25% max HP at MoveEnd when HP falls to ≤50% max.
  Source: `MoveEndHpThresholdItemsTarget` (battle_move_resolution.c).
- Lum Berry: cures any non-volatile status on infliction (secondary, primary, contact ability).
  Source: `TryCureAnyStatus` (battle_hold_effects.c L764).
- Leftovers: heals max_hp/16 at EOT (FIRST_EVENT_BLOCK_HEAL_ITEMS, position 19 in handler table).
  Source: `TryLeftovers` (battle_hold_effects.c L634–648).

### Utility Umbrella
- Blocks rain/sun modifier for the holder (attacker or defender).
- Source: `GetAttackerWeather` L9281 and `GetWeatherDamageModifier` L7258.

---

## M13: Item AI (2026-06-27)

### Items compose through DamageCalculator automatically
- `TrainerAI._score_move` calls `DamageCalculator.calculate(attacker, defender, move, ...)`.
- M12 threads `ItemManager.attack_modifier_uq412` (Choice Band/Specs) and
  `ItemManager.post_roll_modifier_uq412` (Life Orb) into the calculator pipeline.
- Result: the AI's KO detection and effectiveness scoring already reflect held items
  with zero changes to `TrainerAI` scoring code.
- Confirmed by discriminating test: Choice Band makes Tackle KO a Fire-type defender
  at current_hp=60 (damage 61≥60), while without Band Tackle only deals 42. The AI
  picks Tackle with Band (score 106 via FAST_KILL) and Water Gun without (score 102).

### Choice-lock: score-prefilter mechanism
- Source: `BattleAI_SetupAIData` (battle_ai_main.c L164–191).
  When `moveLimitations & (1<<moveIndex)`: `SET_SCORE(battler, moveIndex, 0)`.
  `BattleAI_DoAIProcessing` (L1053) skips scoring for moves with score==0.
  Only the locked move keeps its score; it is automatically chosen.
- Port: if `attacker.choice_locked_move != null`, return that move's index directly,
  bypassing all scoring. Equivalent outcome to the prefilter.
- Source of move limitation: `CheckMoveLimitations` (battle_util.c L1621):
  `MOVE_LIMITATION_CHOICE_ITEM` — if `IsHoldEffectChoice(holdEffect) && *choicedMove != MOVE_NONE && *choicedMove != move` → mark unusable.

### ShouldSwitchIfBadChoiceLock
- Source: `ShouldSwitchIfBadChoiceLock` (battle_ai_switch.c L1170–1213).
  Called from `ShouldSwitch` L1449 (after HasBadOdds, before AttackingStatsLowered).
  Singles branch (L1206–1209): if choice-item held AND
  (locked move is STATUS category OR locked move cannot affect target / type-immune)
  AND `RandomPercentage(RNG_AI_SWITCH_CHOICE_LOCKED, SHOULD_SWITCH_CHOICE_LOCKED_PERCENTAGE)`.
- `SHOULD_SWITCH_CHOICE_LOCKED_PERCENTAGE = 100` (config/ai.h L23).
  Always switches — no RNG seam needed.
- Port: if `attacker.choice_locked_move != null` AND (move.category == 2 OR type-immune),
  call `_best_switch_target` and return. Placed after HasBadOdds in `_should_switch`.

### battle_ai_items.c scope
- `battle_ai_items.c` covers **trainer bag consumables only** (Potions, Revives, X-items).
  Source: `ShouldUseItem()` (L28–196) iterates `gBattleHistory->trainerItems` (bag items),
  not `gBattleMons[battler].item` (held items). Completely unrelated to held-item AI.
- Held-item effects on AI behavior are handled implicitly through the damage pipeline
  (see "Items compose through DamageCalculator automatically" above).

### AI_FLAG_SMART_SWITCHING scope for BadChoiceLock
- `ShouldSwitchIfBadChoiceLock` is inside `ShouldSwitch`, which in source is only
  called when `AI_FLAG_SMART_SWITCHING` is set. Our implementation gates all of
  `_should_switch` behind `tier == Tier.SMART`, matching this behavior.

### Berry-triggered awareness: CONFIRMED ABSENT
- Checked `ShouldSwitch` (battle_ai_switch.c L1391–1455) in full.
  None of the switch checks examine the AI's own berry HP threshold or the opponent's
  held item for defensive consideration.
- Checked `AI_CheckBadMove` and `AI_CheckViability` in `battle_ai_main.c` — no logic
  for "avoid recoil move to stay above Sitrus threshold" or similar berry-aware scoring.
- Conclusion: berry-triggered awareness does not exist in this version of the source AI.
  Not implemented. If a future session asks "does the AI consider its own Sitrus Berry
  threshold?", the answer is: no, confirmed absent from `battle_ai_switch.c` and
  `battle_ai_main.c` scoring passes.

---

## M14a — Doubles foundation (state machine + turn order for 4 combatants)

### Combatant layout (side-grouped, not source-alternating)
- Source uses alternating layout: B_POSITION_PLAYER_LEFT=0, B_POSITION_OPPONENT_LEFT=1,
  B_POSITION_PLAYER_RIGHT=2, B_POSITION_OPPONENT_RIGHT=3 (battle.h).
- Our layout groups by side: [side0_slot0, side0_slot1, side1_slot0, side1_slot1].
  Formula: `side = combatant_idx // _active_per_side`, `field_slot = combatant_idx % _active_per_side`.
- Rationale: side-grouped is simpler for existing party/side indexing; the alternating
  source layout is an artifact of how the GBA battler IDs were assigned and does not
  carry semantic meaning in our implementation.

### BattleParty.active_indices
- Replaced `active_index: int` (single active slot) with `active_indices: Array[int]`
  (list of party slot indices currently on the field).
- Backward-compat property `active_index` wraps `active_indices[0]` via GDScript 4
  getter/setter; all M1–M13 test code using `party.active_index` unchanged.
- `get_active_at(field_slot)`, `num_active()` added for doubles access.
- `has_valid_switch_target`, `get_random_non_fainted_not_active`,
  `get_first_non_fainted_not_active` updated to exclude ALL active indices (not just [0]).

### _active_per_side, _actor_indices, _chosen_targets (BattleManager)
- `_active_per_side: int = 1` (singles) or 2 (doubles); governs all layout formulas.
- `_actor_indices: Dictionary` (BattlePokemon → combatant_idx 0..N-1); distinct from
  `_actor_sides` (BattlePokemon → side 0 or 1). Used for `_chosen_moves`/`_chosen_targets` indexing.
- `_chosen_targets: Array[int]` — per-combatant target combatant index. Defaults to
  `_default_target(i) = (1 - side) * _active_per_side` (first slot of opposing side).
  Overridden by `queue_move_targeted` "target" field.

### _get_first_opponent vs _get_opponent
- Old `_get_opponent(mon)` assumed exactly 2 combatants and returned the other one.
- New `_get_first_opponent(mon)` returns first active slot of opposing side.
- All 9 former call sites updated; actual move damage uses `_combatants[_chosen_targets[i]]` instead.

### Target redirection for fainted targets (M14a addition)
- In doubles, a target can faint earlier in the same turn (before the attacker's action).
  Added redirect at top of `_phase_move_execution`: if `defender.fainted`, find first
  non-fainted mon on the opposing side. If none found, skip the move silently.
- This is required for any doubles battle to complete; without it, live attackers keep
  targeting fainted slots and the battle never ends.
- Singles not affected: the only opponent slot has a replacement or the battle ends.

### ACTION_EXECUTION fainted-skip fix (M14a bug fix)
- Old code: skipped fainted actor by re-dispatching to ACTION_EXECUTION (same phase).
  In singles this was harmless because replacements prevented permanently fainted slots.
  In doubles with no bench replacement, the fainted slot stays in `_turn_order` every turn,
  causing the `_phase == phase_before → break` guard in `advance()` to halt the loop.
- Fix: replaced `if actor.fainted: re-dispatch ACTION_EXECUTION` with a while loop that
  skips fainted actors before entering the main dispatch path. ACTION_EXECUTION now always
  changes phase on exit.

### Destiny Bond in doubles (M14a simplification)
- `_get_first_opponent` is used for the DB killer lookup; only the first opposing slot is
  considered. Full doubles DB (potentially two KB targets) is M14b scope.

### _do_forced_switch_in M14b note
- Kept `(side, slot)` signature; uses `active_indices[0]` (primary slot only).
  In doubles, forced switches (Roar/Whirlwind) should ideally target the specific
  combatant that used Roar — this is M14b scope.

### TrainerAI active_index in doubles (M14c simplification)
- `trainer_ai.gd` reads `my_party.active_index` (lines 115, 310) via the backward-compat
  property — sees only slot 0 of the active pair. Full doubles AI awareness is M14c scope.

### Queue API for doubles
- `queue_move_targeted(combatant_idx, move_index, target_idx)` — explicit targeting.
- `queue_switch_for(combatant_idx, slot)` — switch for a specific field position.
- `queue_replacement_for(combatant_idx, slot)` — faint replacement for a specific slot.
- Legacy `queue_move(side, slot)` / `queue_switch(side, slot)` / `queue_replacement(side, slot)`
  remain for backward compat; they address combatant `side * _active_per_side` (slot 0 of side).

---

## [M14b] Spread move damage reduction

- Source: `battle_util.c` :: `GetTargetDamageModifier` (L7220–7229)
- Behavior: When a spread move (is_spread=true) is used and ≥2 live opposing targets
  exist, each hit is multiplied by 0.75 (UQ4.12 = 3072). Applied as the first modifier
  after CalculateBaseDamage, before weather/crit/roll. When only 1 live target exists
  at execution time, no reduction — the lone target takes full power.
- Notes: `live_target_count` is computed at move-execution time (not selection time).
  If one opponent faints mid-turn (from another combatant's action), the later spread
  hits the survivor at full power. This matches source behavior (GetMoveTargetCount
  counts non-absent battlers at the time the move fires).

## [M14b] Helping Hand base-power boost

- Source: `battle_util.c` :: `CalcMoveBasePowerAfterModifiers` (L6436–6437)
- Behavior: Helping Hand multiplies the receiver's next move's base power by 1.5
  (UQ4.12 = 6144). Applied to effective_power before the damage formula, NOT to the
  final damage. The boost flag is cleared at the start of each turn's priority
  resolution (TurnValuesCleanUp / memset gProtectStructs).
- Notes: STAB is applied AFTER the random roll (ApplyModifiersAfterDmgRoll L7617).
  The unboosted Normal-type damage range is 43–52 (with STAB, at level 50 in tests);
  HH-boosted range is 66–78. Threshold 60 discriminates cleanly with margins of 8/6.

## [M14b] Follow Me target redirect

- Source: `battle_move_resolution.c` :: `IsAffectedByFollowMe` (L799)
- Behavior: Follow Me redirects all incoming single-target moves toward the Follow Me
  user. Spread moves (is_spread=true) bypass Follow Me — they still hit all live
  opponents. AI and queued targets are overridden at execution time.
- Notes: Follow Me redirect stored in `_follow_me_targets[side]` (per-side index).
  Cleared at start of priority resolution alongside Helping Hand.

## [M14b] Destiny Bond killer tracking in doubles

- Source: `_last_attacker` dict, populated by `_do_damaging_hit` on every damaging hit.
- Behavior: When a Destiny Bond user faints, the killer is looked up from `_last_attacker`.
  In doubles, multiple combatants may hit the DB user in the same turn; `_last_attacker`
  records the most recent hit, correctly identifying the actual fatal attacker.
- Notes: `_get_first_opponent` fallback is only reached if `_last_attacker` has no entry
  for the fainted mon (e.g., damage-over-time faint at end-of-turn with no attacking hit).

## [M14b] _phase_faint_check — "all-time fainted" semantics bug (fixed)

- Source: project-internal state-machine semantics (no direct source analogue).
- Behavior: `_phase_faint_check` must only trigger `SWITCH_PROMPT` for mons that fainted
  THIS tick (`current_hp ≤ 0 and not fainted`), not for mons that fainted in prior turns
  (`fainted = true`). The old second scanning loop checked `if combatant.fainted:`, which
  re-triggered SWITCH_PROMPT on every subsequent tick in doubles no-bench scenarios,
  preventing later actors from ever executing.
- Fix: replaced second loop with `any_new_faint` flag tracked during the first loop.

## [M14c] Doubles AI scoring architecture

- Source: `battle_ai_main.c` :: `ChooseMoveOrAction_Doubles` (L918–1038)
- Behavior: For each candidate target slot (excluding self and fainted mons), run the full
  AI scoring pipeline with that slot as the nominal defender. Each (move, target) pair is
  scored independently — the AI does NOT score a move once and bolt a target onto it.
  After all targets are evaluated, pick the target with the highest best-move score.
  The chosen move is whichever move scored highest against that target.
- Notes: Implemented as `TrainerAI.choose_action_doubles` with per-slot outer loop.
  Returns {"type": "move", "index": int, "target": int}. The "target" is the combatant
  index used directly by BattleManager's `_chosen_targets[i]`.

## [M14c] Doubles AI spread move preference — no explicit bonus

- Source: `battle_ai_util.c` :: `AI_CalcDamage` (L887) → `CalculateMoveDamageVars` →
  `GetTargetDamageModifier` (`battle_util.c` L7220); `CalcBattlerAiMovesData` (L715)
- Behavior: The source does NOT add a flat bonus for spread moves. Instead,
  `AI_CalcDamage` calls `CalculateMoveDamageVars` which calls `GetTargetDamageModifier`,
  which applies the 0.75× reduction when `GetMoveTargetCount == 2`. This means
  `simulatedDmg[atk][def][moveIndex]` already stores per-target damage with the reduction
  baked in. `GetNoOfHitsToKOBattler` reads that pre-computed value and is therefore
  naturally target-count-aware. `ShouldUseSpreadDamageMove` (L3915) only applies to
  `TARGET_FOES_AND_ALLY` (moves that also hit the user's own partner) — it is irrelevant
  to `TARGET_BOTH` spread moves that target only opponents.
- Port: `_score_move_doubles` passes `is_spread_active=true` to `DamageCalculator.calculate`
  so our KO estimate applies the 0.75× reduction, exactly mirroring what the source bakes
  into `simulatedDmg`. No spread bonus constant is added. The existing FAST_KILL/SLOW_KILL
  scoring handles spread vs single-target correctly with zero special-casing.
- C1 fixture (post-correction): spread (power=90) deals 109 to a max_hp=70 target
  despite 0.75× → OHKO → score 106. Tackle (power=40) deals 66 < 70 → no OHKO → score 100.
  Spread wins on real KO advantage, not a phantom bonus.

## [M14c] AI_AttacksPartner — confirmed absent for trainer AI

- Source: `battle_ai_main.c` :: `AI_AttacksPartner` (L6045–6067); flag index 30
- Behavior: This function only fires when (a) `IsNaturalEnemy(attacker, ally)` is true
  (wild battle species-pair logic), or (b) `AI_FLAG_ATTACKS_PARTNER_FOCUSES_PARTNER`
  is set. Neither condition applies to trainer battles in this project.
- Port: `choose_action_doubles` never scores targeting the ally slot. Confirmed absent —
  no trainer doubles AI in pokeemerald_expansion deliberately targets its own partner.

## [M14c] Doubles AI partner coordination — confirmed absent

- Source: `battle_ai_main.c` :: `AI_DoubleBattle` (L3034) — partner move awareness
- Behavior: The source's AI_DoubleBattle does check `aiData->partnerMove` for specific
  interactions (e.g., penalize duplicate moves, respond to Helping Hand). These partner-
  state checks require knowing what the ally will do this turn (via `GetAllyChosenMove`).
- Port: Not implemented. `choose_action_doubles` scores each battler independently
  without reading the ally's chosen move for the current turn. Matches the scope of M14c:
  "does the AI factor in partner state?" — source does, but only for specific move effects
  (Helping Hand response, equivalent move deduplication). These are not in scope for the
  three targeted decisions (spread preference, target selection, AI_AttacksPartner check).
  Documented as confirmed-partial — the source HAS this logic but it is out of scope.

## AI_CompareDamagingMoves — bounded port (post-M14c audit fix)

- Source: `battle_ai_main.c` L3940–4112, called at L881 (singles) and L964 (doubles).
- Behavior: After the per-move scoring passes, the move requiring the **fewest hits to KO**
  the defender receives `BEST_DAMAGE_MOVE (+1)`. If multiple moves tie for fewest hits,
  all tied moves receive +1 equally. Implemented as `TrainerAI._apply_best_damage_move`,
  called from `choose_action` and from the per-opponent loop in `choose_action_doubles`.
- Why added: A post-M14c source audit found that the prior `_score_move` carried a
  fabricated effectiveness bonus (DECENT_EFFECT for 2×, BEST_EFFECT for 4×) with no
  source backing. After removing it, four tests (A1.02, A1.03, A15.01) relied on a real
  source mechanism — `AI_CompareDamagingMoves` — that simply hadn't been ported yet.
  A20 required a test redesign (see below).

**What is ported:**
The core rule: among all damaging moves with power > 0 and non-zero type effectiveness,
compute `ceil(defender.current_hp / estimated_damage)` for each. The move(s) with the
strictly lowest hit count receive BEST_DAMAGE_MOVE (+1). Immune moves (effectiveness 0)
and status moves (category 2) are excluded as in source.

**What is deliberately omitted:**

1. **Tiebreaker cascade** (source L3986–4091 when multiple moves share the fewest hit
   count): resist-berry avoidance, speed/priority for OHKOs, guaranteed-KO at min roll,
   two-turn preference, accuracy comparison, effect comparison. None of the current test
   scenarios exercise a tied hit-count, so this would be untested dead code. To add later
   if a test requires it — do not add speculatively.

2. **Spread-move carve-out** (source sets `noOfHits = -1` for `ShouldUseSpreadDamageMove`
   to exclude spread moves from the hit-count comparison, because their full-damage
   estimate ignores the 0.75× reduction): our port calls `DamageCalculator.calculate`
   with `is_spread=true` for spread moves, so the 0.75× is already baked into the
   estimated damage. The carve-out's purpose is moot here.

3. **Self-sacrifice exception** (source sets `noOfHits = maxHP` when the AI decided
   against self-sacrifice for that move): no Explosion/Selfdestruct in the current moveset.
   If self-sacrifice moves are added later, revisit.

4. **`ShouldCompareMove` filter**: replaced by existing null / power==0 guards.

## IncreasePoisonScore/BurnScore/ParalyzeScore/SleepScore — bounded port (F25 audit fix)

- Source: `battle_ai_util.c` L4791–4907 (four functions); called from `AI_CalcMoveEffectScore`
  in `battle_ai_main.c`.
- **Why added:** The prior implementation applied a flat `DECENT_EFFECT (+2)` to all four
  status types unconditionally when `defender.status == STATUS_NONE`. A post-M14c audit
  (F25) found this was a fabrication pattern — the source functions each have distinct
  conditions and bonus amounts, with the flat +2 being wrong for most cases.

**What is ported (per function):**

- **Common guard** (all four): If AI can already KO the defender this turn
  (`CanAIFaintTarget`), skip the bonus. Ported as `_can_attacker_ko_defender`.

- **IncreasePoisonScore (SE_TOXIC)**: base `+WEAK_EFFECT (+1)`. Additional
  `+DECENT_EFFECT (+2)` if `!HasDamagingMove(battlerDef)` (defender is helpless).
  Total: +1 common case; +3 when defender has no attacking moves.

- **IncreaseBurnScore (SE_BURN)**: 0 if defender is not a physical attacker (no physical
  moves AND `base_atk < base_spatk + 10`). `+DECENT_EFFECT (+2)` if defender has explicit
  physical moves. `+WEAK_EFFECT (+1)` if only the stat heuristic applies
  (`base_atk >= base_spatk + 10`) but no known physical moves.

- **IncreaseParalyzeScore (SE_PARALYSIS)**: `+GOOD_EFFECT (+3)` when paralysis flips turn
  order (`defSpeed >= atkSpeed && defSpeed/2 < atkSpeed`). `+DECENT_EFFECT (+2)` otherwise.

- **IncreaseSleepScore (SE_SLEEP)**: unconditional `+DECENT_EFFECT (+2)`.

**What is deliberately omitted:**

1. **Synergy bonuses** — Poison: Venoshock/Merciless/STALL+Protect combos. Burn:
   Hex/Smelling Salts power-boost. Paralysis: flinch-move setup, defender confusion/
   infatuation volatile. Sleep: Dream Eater/Nightmare bonus, Focus Punch exception to the
   KO guard. None of these moves/abilities are in current scope.

2. **Hold-item guards** — each function checks `HOLD_EFFECT_CURE_PSN/BRN/PAR/SLP` on the
   defender. Not tracked in this project.

3. **Burn: "best moves" filtering** — source calls `GetBestDmgMovesFromBattler` and checks
   if the *best* defender moves are physical; our port checks if *any* physical move exists.
   Simplification: over-awards `+DECENT_EFFECT` when a mon has a physical move but its best
   moves are all special. Documentably conservative — no test exercises this distinction.

4. **Freeze** — no `IncreaseFreeze` function exists in source (freeze is always a secondary
   on damaging moves, not a pure status move). `SE_FREEZE` removed from Pass 3 matching;
   retained in Pass 1's already-statused penalty check for completeness.

- Notes: The only test exercising status bonus scoring is A6 (Toxic vs Splash vs helpless
  Normal defender). Under new scoring: Splash=100, Toxic=103 (DECENT_EFFECT for no-damage
  defender + WEAK_EFFECT base). A6 passes; no test required redesign. 2026-06-29.

## ShouldSwitchIfHasBadOdds — typeMatchup > 2.0 branch not ported (F28/F30 known gap)

- Source: `ShouldSwitchIfHasBadOdds` (battle_ai_switch.c L367).
- The source contains two distinct switch-out conditions:
  1. **OHKO branch** (L387): AI would be KO'd by a single hit AND HP ≥ 50% → 50% switch.
  2. **Type-disadvantage branch** (L399): `typeMatchup > UQ_4_12(2.0)` — switch out even
     without an imminent OHKO when the offensive type matchup is sufficiently unfavourable,
     subject to the same HP and no-super-effective-move conditions.
- **What is ported:** The OHKO branch only. `_should_switch` triggers `ShouldSwitchIfHasBadOdds`
  via `_can_defender_ko_attacker`.
- **What is omitted:** The typeMatchup > 2.0 branch. Our implementation never switches out
  of a bad type matchup unless the AI is simultaneously threatened with a one-hit KO.
- **Why safe to leave:** All existing tests pass under OHKO-only logic. The gap means AI is
  slightly less willing to switch in cases of unfavourable matchup without an OHKO threat —
  a known conservative deviation, not a logic error. 2026-06-29.

## ShouldSwitchIfBadChoiceLock — missing IsHoldEffectChoice/IsBattlerItemEnabled precondition (F31)

- Source: `ShouldSwitchIfBadChoiceLock` (battle_ai_switch.c L1170), singles branch L1206–1209.
- The source singles branch guards the entire switch check with:
  `else if (IsHoldEffectChoice(ctx.holdEffects[ctx.battlerAtk]) && IsBattlerItemEnabled(switchContext->battler))`.
  This verifies that (a) the held item is a choice item and (b) the item is currently enabled
  (not disabled by Embargo, Klutz, or similar mechanics).
- **What is ported:** `if attacker.choice_locked_move != null` — the presence of a lock implies
  the item was active when the lock was set. No further item re-check is done.
- **Why the gap is not currently reachable as a bug:** `choice_locked_move` is set by
  `BattleManager` only when a choice-item holder uses a move. No implemented mechanic can
  remove or disable a held item mid-battle (no Knock Off, no Thief, no Embargo, no Klutz,
  no Corrosive Gas). Therefore `choice_locked_move != null` currently implies a choice item
  IS held and enabled with 100% reliability. If item-removal mechanics are ever added, the
  `IsHoldEffectChoice && IsBattlerItemEnabled` guard must be added at that point. 2026-06-29.

## GetSwitchinCandidate — type-effectiveness simplification (F15/F32)

- Source: `GetSwitchinCandidate` (battle_ai_switch.c L2004). The source selects a switch-in
  candidate by priority tier: trappers > revenge killers > slow revenge killers > fast
  threaters > slow threaters > type-advantage effective > type-advantage neutral > healing
  candidates > Baton Pass holders > generic 1v1 mons > damage dealers. Within each tier that
  uses `GetSwitchinCandidate`, the function returns either the **last** eligible party member
  in party order (default) or a **random** eligible member (under `AI_FLAG_RANDOMIZE_SWITCHIN`).
  There is no "SWITCHIN_CONSIDER_MOST_SUITABLE" enum — that name does not exist in the source.
- **What is implemented:** Both `choose_replacement` and `_best_switch_target` pick the party
  member whose damaging moves have the highest type effectiveness against the current opponent,
  falling back to the first non-fainted non-active slot if no type data is available.
- **Kept as-is.** This is a different, also-valid simplification: it prefers the mon with the
  best offensive typing rather than the last eligible mon in party order. It skips the
  multi-tier priority logic (trappers, revenge killers, etc.) that would require access to
  speed stats, predicted moves, and damage estimates for all bench members. The behaviour is
  correct enough to pass all existing AI tests and is a deliberate scope reduction. If a more
  faithful port of `GetSwitchinCandidate`'s priority tiers is wanted later, it would be a
  standalone improvement, not a bug fix. 2026-06-29.

## [M14c] B8 Destiny Bond fixture non-determinism (fixed)

- Source: test fixture correctness (not a mechanic issue).
- Behavior: The original B8 fixture used B1 base_atk=200 (stat=205), which gives a damage
  range of 55–66 against A0 (max_hp=61). OHKO probability = 7/16 ≈ 44%. The comment
  claimed "min=82>61" which was arithmetically wrong (omitted STAB application).
- Fix: raised B1's base_atk to 230 (stat=235). New range: 63–76. Guaranteed OHKO at all
  rolls. Verified: base=50, roll=85 → 42, STAB → 63 ≥ 61.

## [Audit] BattleManager._force_hit — accuracy seam added (Prompt 2 audit)

- Source: `StatusManager.check_accuracy()` (status_manager.gd); `BattleManager._phase_move_execution()`.
- Behavior: `StatusManager.check_accuracy` has always had a `force_hit: Variant = null`
  parameter (added during M5), but `BattleManager` called it with only 3 positional arguments,
  never passing a fourth. This meant no test in the project's history could force a guaranteed
  hit on a non-accuracy=0 move through a real BattleManager turn.
- Root cause found via: S4E.03 (`ability_triggered = synchronize`) failed intermittently
  (~1/9 runs). Thunder Wave has accuracy=90. When twave_attacker's first Thunder Wave missed
  and synch_holder's own Thunder Wave hit first, twave_attacker was already paralyzed by the
  time synch_holder received paralysis — Synchronize's reflect attempt (`try_apply_status`)
  returned false (already statused), `back=0`, and `ability_triggered` was never emitted.
  Both mons ended up paralyzed via direct application, not Synchronize, so S4E.01/02 passed
  while S4E.03 failed.
- Fix: Added `var _force_hit: Variant = null` to BattleManager (same block as `_force_roar_rng`);
  threaded it through to `StatusManager.check_accuracy(attacker, defender, move, _force_hit)`.
  S4E.01–05 rewritten as direct API calls (StatusManager + AbilityManager, no BattleManager —
  same pattern as the sleep tests that had already avoided this trap). S4E.06 added as the
  integration test using `bm._force_hit = true`.
- Going forward: any test that needs a guaranteed hit on a move with accuracy < 100 should
  set `bm._force_hit = true` rather than substituting an always-hit move as a workaround.

---

## [Audit] BattleManager._force_roll / _force_crit — damage determinism seams added

- Source: `DamageCalculator.calculate()` (damage_calculator.gd L60-86);
  `BattleManager._do_damaging_hit()`.
- Same root-cause class as `_force_hit` above: `DamageCalculator.calculate` has always had
  `force_roll: int = -1` and `force_crit: Variant = null` parameters, but `_do_damaging_hit`
  hardcoded `-1` and `null` at its call site, so no BattleManager-integration test could pin
  a damage roll or crit result — tests had to rely on a numeric range wide enough to absorb
  live RNG variance instead (e.g. B5's old "≤ 60" threshold spanning a 43-78 possible spread).
- Found while reviewing B5 (`_test_b5_helping_hand_clears`, doubles_test.gd) — its threshold
  check happened to still be correct, but the surrounding range comments couldn't be verified
  by arithmetic without pinning the roll, and crit RNG (~1/24 per hit, two hits checked) gave
  a non-trivial chance of spurious failure across repeated runs.
- **The two parameters do NOT share one sentinel convention** — confirmed by re-reading
  `damage_calculator.gd` fresh rather than assuming symmetry with `_force_hit`:
  - `force_roll: int` is **int-sentinel**: `-1` = real RNG, any value `>= DMG_ROLL_LO` (85)
    pins that exact roll (L216-217: `roll = force_roll if force_roll >= DMG_ROLL_LO else ...`).
    It cannot hold `null` (it's `int`-typed), so `BattleManager._force_roll` is declared
    `Variant = null` (matching `_force_hit`'s style) and converted at the call site:
    `_force_roll if _force_roll != null else -1`.
  - `force_crit: Variant` is **null-sentinel**, identical convention to `_force_hit`: `null` =
    real RNG, `true`/`false` force the result directly (L118). No conversion needed —
    `BattleManager._force_crit` passes straight through.
- Fix: added `var _force_roll: Variant = null` and `var _force_crit: Variant = null` to
  BattleManager (same declaration block as `_force_hit`/`_force_roar_rng`); threaded both
  into the `DamageCalculator.calculate` call in `_do_damaging_hit`.
- B5 updated to set `bm._force_roll = 100` and `bm._force_crit = false` before
  `start_battle_doubles`, replacing the old variable-roll range comments with exact
  hand-computed values at that pinned roll (A1.attack=105, B0.defense=55, Tackle
  power=40/Normal/Physical, STAB and 1.0× type eff apply): turn 1 (with Helping Hand,
  effective_power=60) = 78 damage exactly; turn 2 (without Helping Hand) = 52 damage
  exactly. New exact-value assertions (B5.02/B5.03) added alongside the original
  threshold assertion (B5.01).
- Going forward: any BattleManager-integration test needing deterministic damage should set
  `bm._force_roll` / `bm._force_crit` rather than relying on a wide-enough numeric range to
  absorb live RNG variance — the same lesson as `_force_hit`, now extended to damage rolls
  and crit results.

---

## [Audit] BattleManager integration test coverage — RNG determinism sweep

**Scope:** All `randi()`, `randi_range()`, and probability-based branches in
`battle_manager.gd`, `status_manager.gd`, and `trainer_ai.gd`.  
**Coverage criterion:** a `_force_X` property exists on `BattleManager` and is threaded
through to the RNG site — same pattern as `_force_hit`, `_force_roll`, `_force_crit`,
`_force_roar_rng`.  
**Result: zero FLAKY findings.** No test claims a "guaranteed" assertion that fails at
worst-case RNG values.

### Complete site table (18 sites, in file order)

| ID | File | Lines | Code | Classification |
|----|------|-------|------|----------------|
| BM-1 | battle_manager.gd | L449 | `tiebreak[mon] = randi()` (speed-tie tiebreak) | **UNCOVERED-SAFE** |
| BM-2 | battle_manager.gd | L690 / L1420 | `randi() % denom` (Protect consecutive success roll) | **UNCOVERED-SAFE** |
| BM-3 | battle_manager.gd | L716 | `check_accuracy(..., _force_hit)` | **COVERED** (`_force_hit`) |
| BM-4 | battle_manager.gd | L730 | `get_random_non_fainted_not_active(_force_roar_rng)` | **COVERED** (`_force_roar_rng`) |
| BM-5 | battle_manager.gd | L1014 | `try_secondary_effect(...)` — status-move path | **UNCOVERED-SAFE** |
| BM-6 | battle_manager.gd | L1472 | `pool[randi() % pool.size()]` (Metronome move selection) | **UNCOVERED-SAFE** |
| BM-7 | battle_manager.gd | L1566 | `try_secondary_effect(...)` — damaging-move path | **UNCOVERED-SAFE** |
| BM-8 | battle_manager.gd | L1521–1523 | `DamageCalculator.calculate(..., roll, _force_crit, ...)` | **COVERED** (`_force_roll`, `_force_crit`) |
| BM-9 | battle_manager.gd | L1580–1581 | `try_contact_effects(attacker, target, move, damage)` — Static / Flame Body 30% | **NOT EXERCISED through BM** |
| SM-1 | status_manager.gd | L76 | `randi_range(2, 4)` (sleep duration on infliction) | **NOT EXERCISED through BM** |
| SM-2 | status_manager.gd | L99 | `randi_range(2, 5)` (confusion duration on infliction) | **NOT EXERCISED through BM** |
| SM-3 | status_manager.gd | L204 | `randi() % 100 < 20` (20% freeze thaw) | **NOT EXERCISED through BM** |
| SM-4 | status_manager.gd | L239 | `randi() % 100 < 33` (33% confusion self-hit) | **UNCOVERED-SAFE** |
| SM-5 | status_manager.gd | L259 | `randi() % 4 == 0` (25% full paralysis) | **NOT EXERCISED through BM** |
| SM-6 | status_manager.gd | L370 | `randi() % 100 < calc` (accuracy roll) | **COVERED** (`_force_hit`) |
| SM-7 | status_manager.gd | L445 | `randi() % 100 < move.secondary_chance` (secondary effect roll) | **UNCOVERED-SAFE** |
| AI-1 | trainer_ai.gd | L639 | `randi() % best_indices.size()` (AI move tie-break) | **UNCOVERED-SAFE** |
| AI-2 | trainer_ai.gd | L649 | `(randi() % 100) < pct` (ShouldSwitchIfHasBadOdds 50%) | **NOT EXERCISED through BM** |

### COVERED sites (4)

SM-6 and BM-3 describe the same accuracy-check RNG path from two vantage points (BM call
site vs. StatusManager implementation); both are covered by the same seam.

| Site | Seam | Threading path |
|------|------|----------------|
| BM-3 (accuracy call site) | `_force_hit: Variant = null` on BM | `_force_hit` → `StatusManager.check_accuracy(attacker, defender, move, _force_hit)` |
| SM-6 (accuracy roll) | same as BM-3 | same mechanism; SM-6 is the implementation that BM-3 drives |
| BM-4 (Roar/Whirlwind target) | `_force_roar_rng: int = -1` on BM | `_force_roar_rng` → `BattleParty.get_random_non_fainted_not_active(_force_roar_rng)` |
| BM-8 (damage roll + crit) | `_force_roll: Variant = null` and `_force_crit: Variant = null` on BM | `_do_damaging_hit` converts `_force_roll` via `_force_roll if _force_roll != null else -1` and passes `_force_crit` directly to `DamageCalculator.calculate` |

### UNCOVERED-SAFE sites (8) — arithmetic summaries

- **BM-1** (speed-tie): All equal-speed BM integration tests (D1/D3/D5/D6, all spd=80) have
  order-independent assertions. D5 worst case: A0/A1 deal min 69 damage to B0.max_hp=61
  regardless of turn order — OHKO is guaranteed either way. (`base=40×260×22/85/50+2=55`,
  `roll=85→46`, `STAB→69≥61`.)
- **BM-2** (Protect first use): `consecutive=0` → `denom=1` → always succeeds deterministically.
  S4.01–S4.04 assert only "at least one Protect fired," which requires only the first use.
- **BM-5** (status-move secondary): All BM-integrated status moves use `secondary_chance=0`;
  `try_secondary_effect` short-circuits before the RNG roll — application is guaranteed.
- **BM-6** (Metronome selection): S9.02–S9.05 assert only "a valid non-banned move was
  selected" — satisfied by any member of the pool regardless of which is picked.
- **BM-7** (damaging-move secondary): Only BM integration test with `secondary_chance>0` is
  T4a (Flame Wheel, 10% burn). T4a's defender has HP=1 and faints from the main hit; the
  burn secondary does not affect any T4a assertion.
- **SM-4** (confusion self-hit 33%): S5 — opp1.max_hp=220; max confusion self-hit =
  `40×65×22/65/50+2 = 19` (no roll, no STAB, no type eff at confusion path). 19 << 220;
  opp1 cannot faint. Roar fires regardless of whether confusion self-hit occurs.
- **SM-7** (secondary effect roll): covered by same reasoning as BM-5 (all secondary-capable
  status moves in BM tests have `secondary_chance=0`) and BM-7 (T4a defender faints before
  secondary matters).
- **AI-1** (AI move tie-break): BM integration tests A12/A13 have either one move per AI
  (no tie possible) or two moves with different scores (no tie). The live-RNG tie path is
  unreachable. (`_force_tie_rng` exists on `TrainerAI` directly but is not threaded through BM.)

### NOT-EXERCISED-through-BM sites — 6 sites (named systemic gap)

These six RNG sites have force-override parameters at the `StatusManager` or `AbilityManager`
level, but those parameters are never passed from BattleManager's call sites, and no BM
integration test currently exercises these code paths through a full battle turn. They are not
FLAKY because they are unreached; they are coverage gaps.

**Named gap:** BM-level integration testing has no coverage of:
- sleep infliction via a secondary effect through a full turn (SM-1)
- confusion infliction via a secondary effect through a full turn (SM-2)
- Static / Flame Body contact-ability triggering through a full turn (BM-9)
- full-paralysis immobility (25% roll) through a full turn (SM-5)
- freeze-thaw randomness (20% roll) through a full turn (SM-3)
- AI switch probability (`ShouldSwitchIfHasBadOdds` 50% roll) in a real BM battle (AI-2)

This is a **deliberate known gap**, not an oversight. These paths are all exercised at the
direct-API level (StatusManager and AbilityManager called directly with pinned force params
in their respective test suites). BM-level integration coverage for these mechanics is
deferred to a future Prompt 9 integration suite rather than being shoehorned in individually.

| Site | Description | Force param location (not yet threaded to BM) |
|------|-------------|-----------------------------------------------|
| BM-9 | `try_contact_effects` call (L1580) passes only 4 args; 5th param `force_contact_roll` on `AbilityManager.try_contact_effects` never passed. Static/Flame Body 30% roll is always live in BM battles. | `AbilityManager.try_contact_effects` 5th param |
| SM-1 | Sleep duration `randi_range(2,4)`: no BM integration test inflicts sleep through a secondary or status move. | `StatusManager.try_apply_status` `force_sleep_turns` |
| SM-2 | Confusion duration `randi_range(2,5)`: same — no BM integration test inflicts confusion through a secondary. | `StatusManager.try_apply_confusion` `force_confusion_turns` |
| SM-3 | 20% freeze-thaw roll: the only BM integration test with a frozen attacker (T4a, Flame Wheel) uses `thaws_user=true`, which the `MoveThawsUser` gate in `pre_move_check` bypasses before the 20% roll is ever reached. | `StatusManager.pre_move_check` `force_freeze_thaw` |
| SM-5 | Full-paralysis 25% roll: no BM integration test has a paralyzed combatant where immobility is required for any assertion. | `StatusManager.pre_move_check` `force_full_para` |
| AI-2 | `ShouldSwitchIfHasBadOdds` 50% roll: BM integration tests use BASIC tier; SMART tier is required to reach `_roll_switch_decision`. | `TrainerAI._force_switch_rng` (on TrainerAI; not threaded to BM at all) |

### BM-9 — third instance of the incomplete-BM-seam pattern

BM-9 (`try_contact_effects`) is the **third confirmed instance** of the same root-cause
class documented in the two prior audit entries:

1. **`_force_hit`** (Prompt 2 audit): `StatusManager.check_accuracy` had `force_hit:
   Variant = null` since M5, but BM called it with 3 positional args — no test could pin
   an accuracy roll through a real BM turn. Fix: added `_force_hit` to BM and threaded it.
2. **`_force_roll` / `_force_crit`** (prior session): `DamageCalculator.calculate` had both
   params since M2, but `_do_damaging_hit` hardcoded `-1`/`null`. Fix: added `_force_roll`
   and `_force_crit` to BM and threaded them.
3. **BM-9** (this audit, not yet fixed): `AbilityManager.try_contact_effects` has
   `force_contact_roll: Variant = null` as its 5th parameter, but BM's call at L1580
   passes only 4 arguments.

Pattern: the lower-level function is correctly designed with a determinism seam; the gap is
always at the BM call site. When a BM-level integration test for contact abilities is added
(Prompt 9 scope), the fix follows the established template: add
`var _force_contact_roll: Variant = null` to BattleManager (same declaration block as
`_force_hit`/`_force_roll`/`_force_crit`) and pass it as the 5th argument at L1580–1581:
`AbilityManager.try_contact_effects(attacker, target, move, damage, _force_contact_roll)`.

---

## [Reference] DamageCalculator.calculate() — full modifier pipeline

Source: `as-imagined/scripts/battle/core/damage_calculator.gd` — read directly 2026-06-30.  
This section supersedes any informal ordering claims in milestone notes; those were written
before later milestones (M11/M12/M14b) inserted additional steps. Use this table as the
single source of truth for ordering questions.

### Critical design note — two UQ4.12 rounding conventions, not one

This pipeline uses **two different UQ4.12 rounding conventions** for two distinct purposes.

- **`_uq412_half_down(v, f)` — rounds ties DOWN** (`(v * f + 2047) / 4096`).  
  Used for every sequential application of a single modifier to the running integer `dmg`:
  weather, crit multiplier, roll, STAB, type effectiveness (apply step), Thick Fat, burn,
  Life Orb, Resist Berry, Helping Hand power boost, and ability/item atk boosts (steps 3–5).
  This is the helper for "integer × UQ4.12 modifier → integer result."

- **`_uq412_multiply(a, b)` — rounds ties UP** (`(a * b + 2048) >> 12`).  
  Used **only** to accumulate two UQ4.12 type-effectiveness values into one combined modifier,
  which is then applied once via `_uq412_half_down`. This is the helper for "UQ4.12 × UQ4.12
  → UQ4.12 result."

**Counterexample retracted — the original claim was incorrect arithmetic.** A previous
version of this section asserted `_uq412_half_down(2048, 2048) = 1023` while
`_uq412_multiply(2048, 2048) = 1024`, claiming the helpers diverge for a dual 0.5×
type-effectiveness scenario. That is wrong. Full arithmetic for both:

- `_uq412_multiply(2048, 2048)` = `(a*b + 2048) >> 12`:
  `2048×2048 = 4,194,304`; `4,194,304+2048 = 4,196,352`;
  `4,196,352>>12`: `4096×1024 = 4,194,304`, remainder `4,196,352−4,194,304 = 2,048 < 4,096`
  → quotient = **1024**.

- `_uq412_half_down(2048, 2048)` = `(v*f + 2047) / 4096`:
  `4,194,304+2047 = 4,196,351`;
  `4,196,351/4096`: `4096×1024 = 4,194,304`, remainder `4,196,351−4,194,304 = 2,047 < 4,096`
  → quotient = **1024**.

Both return **1024**. The rounding-tie case where the two helpers diverge requires the raw
product to have remainder exactly 2048 when divided by 4096. For `2048×2048 = 4,194,304`,
the remainder is 0 — there is no tie to break.

More generally: every standard type-effectiveness modifier is a power of 2 in UQ4.12 space
(`{0, 2048, 4096, 8192}`). The product of any two powers of 2 is itself a power of 2, hence
an exact multiple of 4096. So every pair of real type-effectiveness values produces a raw
product with remainder 0, and `_uq412_multiply` and `_uq412_half_down` are **numerically
identical** for every type-effectiveness accumulation that can occur in this codebase.

**Why the distinction still matters and the rule is still correct.** The choice of helper
matches the structural API boundary in the source's `fpmath.h`:
`uq4_12_multiply` (half-UP) is the documented UQ4.12 × UQ4.12 → UQ4.12 operation;
`uq4_12_multiply_by_int_half_down` (half-DOWN) is the documented integer × UQ4.12 → integer
operation. Using the wrong helper for accumulation is structurally incorrect even though it
produces the same numbers today. A hypothetical future modifier with a non-power-of-2 UQ4.12
value (e.g. a 0.6× or 0.8× modifier) would have a product with a non-zero remainder, and at
the exact halfway point the two helpers diverge. Matching the source's intent now prevents a
silent wrong answer if such a modifier is ever added.

**The rule: accumulating a UQ4.12 modifier against another UQ4.12 modifier →
`_uq412_multiply`; applying any modifier to the integer `dmg` value → `_uq412_half_down`.**

### Rounding helpers used inside calculate()

Four distinct rounding behaviors appear; which one is used matters for specific inputs.

| Helper | Formula | Behavior |
|---|---|---|
| `_uq412_half_down(v, f)` (line 311) | `(v * f + 2047) / 4096` | Integer result; rounds ties DOWN. Used for every `dmg` modifier at steps 3–16 below. |
| `_uq412_multiply(a, b)` (line 298) | `(a * b + 2048) >> 12` | UQ4.12 result; rounds ties UP. Used **only** to accumulate dual-type effectiveness (step 12). |
| `_apply_stage(base, stage)` (line 320) | `base * STAGE_RATIOS[stage+6][0] / STAGE_RATIOS[stage+6][1]` | GDScript `/` — truncates toward zero. Used at step 2. |
| Inline `/` (lines 175, 218) | GDScript integer division | Truncates toward zero. Used in base formula (step 6) and random roll (step 10). |

### Pre-conditions (short-circuit before any formula)

| Check | Lines | Result |
|---|---|---|
| Ability type immunity (`AbilityManager.blocks_move_type`) | 92–94 | Returns `{damage:0, effectiveness:0.0}` immediately |
| Type chart immunity (effectiveness == 0.0) | 98–102 | Returns `{damage:0, effectiveness:0.0}` immediately |
| Fixed-damage move (`move.fixed_damage > 0`) | 109–111 | Returns `{damage: fixed_damage}` — all modifiers below skipped |
| Level-damage move (`move.level_damage == true`) | 112–114 | Returns `{damage: attacker.level}` — all modifiers below skipped |

### Modifier pipeline — execution order

Steps 2–5 modify the intermediate `atk` or `effective_power` values fed into the base
formula; they are not applied to `dmg` directly. Steps 6–17 operate on `dmg`.

| Step | Modifier | Lines | Constant / formula | Rounding | Conditional? |
|---|---|---|---|---|---|
| 1 | Crit determination | 118 | Gen 7+ odds: stage 0 → 1/24, 1 → 1/8, 2 → 1/2, 3+ → always. `force_crit != null` bypasses RNG. | n/a (produces `is_crit` bool) | Always; RNG or forced |
| 2 | Stat stage → `atk` | 146 | `_apply_stage(atk_base, atk_stage)` = `base × STAGE_RATIOS[idx][0] / STAGE_RATIOS[idx][1]` | Truncation | Always; stage 0 is neutral (×10/10 = unchanged) |
| 2 | Stat stage → `def` | 147 | same formula for def_base/def_stage | Truncation | Always |
| 2a | Crit clamps attacker drops | 141–143 | `if atk_stage < 0: atk_stage = 0` (applied before `_apply_stage`) | n/a | `is_crit == true` |
| 2b | Crit clamps defender boosts | 144 | `if def_stage > 0: def_stage = 0` (applied before `_apply_stage`) | n/a | `is_crit == true` |
| 3 | Ability atk modifier (Huge Power / Pure Power) | 153–155 | `atk = _uq412_half_down(atk, mod)`, mod = 8192 (×2.0) | `_uq412_half_down` | mod ≠ 4096 (i.e. attacker has Huge Power or Pure Power for physical moves) |
| 4 | Item atk modifier (Choice Band / Specs) | 159–161 | `atk = _uq412_half_down(atk, mod)`, mod = 6144 (×1.5) | `_uq412_half_down` | Physical + Choice Band, or Special + Choice Specs; mod ≠ 4096 |
| 5 | Helping Hand power boost | 173–174 | `effective_power = _uq412_half_down(effective_power, 6144)` — UQ4.12(1.5) = 6144 | `_uq412_half_down` | `helping_hand == true` |
| **6** | **Base damage formula** | **175** | `effective_power × atk × (2 × level / 5 + 2) / def / 50 + 2` | Inline truncation, left-to-right; each `/` truncates independently | Always |
| 7 | Spread-move reduction | 185–186 | `_uq412_half_down(dmg, 3072)` — UQ4.12(0.75) = 3072 | `_uq412_half_down` | `is_spread == true` AND caller confirmed ≥ 2 live targets |
| 8 | Weather modifier | 197–204 | RAIN+Water or SUN+Fire: 6144 (×1.5); RAIN+Fire or SUN+Water: 2048 (×0.5). Applied via `_uq412_half_down`. | `_uq412_half_down` | weather ≠ NONE AND move type matches AND no Utility Umbrella on either battler |
| 9 | Critical hit multiplier | 209–210 | `_uq412_half_down(dmg, 6144)` — UQ4.12(1.5) = 6144 = `UQ412_1_5` | `_uq412_half_down` | `is_crit == true` |
| **10** | **Random roll** | **216–218** | `dmg × roll / 100`, roll ∈ [85, 100] uniform. `force_roll ≥ 85` pins it. | Inline truncation | Always |
| 11 | STAB | 226–227 | `_uq412_half_down(dmg, 6144)` — UQ4.12(1.5) = 6144 = `UQ412_1_5` | `_uq412_half_down` | move.type ∈ attacker.species.types AND move.type ≠ TYPE_MYSTERY |
| 12 | Type effectiveness | 239–249 | For dual-type defender: accumulate via `_uq412_multiply(type_mod, next_uq412)` (one call per additional type); then apply once via `_uq412_half_down(dmg, type_mod)`. For mono-type: only the `_uq412_half_down` apply step (no accumulation). Returns `{damage:0}` if combined mod == 0. | Accumulate: `_uq412_multiply` (half-UP); Apply: `_uq412_half_down` | move.type ≠ TYPE_MYSTERY |
| 13 | Thick Fat (defender ability) | 256–258 | `_uq412_half_down(dmg, mod)`, mod = 2048 (×0.5) | `_uq412_half_down` | defender has ABILITY_THICK_FAT AND move type is FIRE or ICE |
| 14 | Burn halving | 266–267 | `_uq412_half_down(dmg, 2048)` — UQ4.12(0.5) = 2048 | `_uq412_half_down` | attacker.status == STATUS_BURN AND move.category == 0 (Physical) |
| 15 | Life Orb (post-roll, attacker item) | 272–274 | `_uq412_half_down(dmg, 5324)` — UQ_4_12_FLOORED(1.3) = 5324 | `_uq412_half_down` | attacker holds Life Orb (HOLD_EFFECT_LIFE_ORB = 60) |
| 16 | Resist Berry (post-roll, defender item) | 280–283 | `_uq412_half_down(dmg, 2048)` — UQ412_RESIST_BERRY = 2048 (×0.5) | `_uq412_half_down` | defender holds matching resist berry AND effectiveness ≥ 2.0× |
| 17 | Minimum damage floor | 286–287 | `if dmg == 0: dmg = 1` | n/a | dmg == 0 after all modifiers |

**Key ordering facts to remember (each is non-obvious and has been tested with
discriminating expected values):**
- Weather (step 8) comes **before** crit (9) and roll (10).
- Roll (10) comes **before** STAB (11) and type effectiveness (12).
- Life Orb (15) comes **after** STAB (11), type effectiveness (12), Thick Fat (13), and burn (14).
- Resist Berry (16) comes **after** Life Orb (15).
- Choice Band/Specs (step 4) modifies `atk` before the formula, not `dmg` after it.

---

### Verification hand-traces — three existing discriminating tests

Each trace below applies every step in the table order. Pre-conditions that do not
trigger are listed with "→ skip". Computed with `_uq412_half_down(v, f) = (v×f+2047)/4096`
(GDScript integer division, truncates toward zero).

---

#### Trace 1 — damage_test.gd T6c: Ember roll=100 (expected 54)

**Setup:**
- Attacker: Charmander, type=[FIRE], base_spatk=60 → sp_atk=65, level=50. No held item. abilities=[].
- Defender: Bulbasaur, type=[GRASS, POISON], base_spdef=65 → sp_def=70. No held item. abilities=[].
- Move: Ember — type=FIRE, category=1 (Special), power=40, crit_stage=0.
- force_roll=100, force_crit=false, weather=WEATHER_NONE, is_spread=false.

**Pre-conditions:** blocks_move_type → skip. Fire vs [GRASS, POISON] = 2.0× ≠ 0.0 → proceed. No fixed/level damage → proceed.

| Step | Calculation | Result |
|---|---|---|
| 1 | force_crit=false → is_crit=false | — |
| 2 | Special: atk_base=65, atk_stage=0, def_base=70, def_stage=0. `_apply_stage(65,0)=65×10/10=65`. `_apply_stage(70,0)=70`. | atk=65, def=70 |
| 3 | No Huge Power (abilities=[]) → mod=4096 | → skip |
| 4 | No held item → mod=4096 | → skip |
| 5 | helping_hand=false → effective_power=40 | — |
| 6 | `40×65×(2×50/5+2)/70/50+2` = `40×65×22/70/50+2` = `2600×22/70/50+2` = `57200/70/50+2` = `817/50+2` = `16+2` = **18** | dmg=18 |
| 7 | is_spread=false | → skip |
| 8 | WEATHER_NONE → mod=4096 | → skip |
| 9 | is_crit=false | → skip |
| 10 | `18×100/100 = 18` | dmg=18 |
| 11 | FIRE ∈ [FIRE] → STAB. `(18×6144+2047)/4096 = (110592+2047)/4096 = 112639/4096 = 27` | dmg=27 |
| 12 | type_mod = get_uq412(FIRE, GRASS) = 8192 (2.0×). Second type POISON ≠ GRASS: `_uq412_multiply(8192, get_uq412(FIRE,POISON))` = `_uq412_multiply(8192, 4096)` = `(8192×4096+2048)>>12` = `(33554432+2048)>>12` = `33556480>>12` = 8192 (×2.0 unchanged). Apply: `(27×8192+2047)/4096 = (221184+2047)/4096 = 223231/4096 = 54` | dmg=54 |
| 13–16 | No Thick Fat, no burn, no Life Orb, no resist berry | → all skip |
| 17 | dmg=54 > 0 | — |

**Result: 54. Asserted value: 54. ✓ MATCH**

---

#### Trace 2 — weather_test.gd W8a.02: Water Gun under rain, roll=85 (expected 17)

**Setup:**
- Attacker: type=[NORMAL], base_spatk=50 → sp_atk=55, level=50. No item. No ability. No status.
- Defender: type=[NORMAL], base_spdef=70 → sp_def=75. No item. No ability.
- Move: Water Gun — type=WATER, category=1 (Special), power=40, crit_stage=0.
- force_roll=85, force_crit=false, weather=WEATHER_RAIN, is_spread=false, helping_hand=false.

**Pre-conditions:** blocks_move_type → no ability → skip. WATER vs [NORMAL] = 1.0× ≠ 0.0 → proceed. No fixed/level damage.

**Step 1 — crit:** force_crit=false → `is_crit=false`

**Step 2 — stat stages:** category=Special → atk_base=55, atk_stage=0, def_base=75, def_stage=0. is_crit=false → no clamp.
- `_apply_stage(55, 0)`: STAGE_RATIOS[6]=[10,10]; `55×10=550`; `550/10=55` → **atk=55**
- `_apply_stage(75, 0)`: `75×10=750`; `750/10=75` → **def=75**

**Step 3 — ability atk mod:** no ability → mod=4096 → skip. atk=55

**Step 4 — item atk mod:** no held item → mod=4096 → skip. atk=55

**Step 5 — Helping Hand:** false → effective_power=40

**Step 6 — base formula:** `40 × 55 × (2×50/5+2) / 75 / 50 + 2`
- `2×50=100`; `100/5=20`; `20+2=22`
- `40×55=2200`; `2200×22=48400`
- `48400/75`: `75×645=48375`; `48400−48375=25` → quotient **645**
- `645/50`: `50×12=600`; `645−600=45` → quotient **12**
- `12+2=14` → **dmg=14**

**Step 7 — spread:** is_spread=false → skip. dmg=14

**Step 8 — weather:** WEATHER_RAIN + move type WATER → mod=6144. Neither mon holds Utility Umbrella.
- `14×6144=86016`; `86016+2047=88063`
- `88063/4096`: `4096×21=86016`; `88063−86016=2047` → quotient **21** → **dmg=21**

**Step 9 — crit multiplier:** is_crit=false → skip. dmg=21

**Step 10 — roll:** force_roll=85
- `21×85=1785`; `1785/100`: `100×17=1700`; `1785−1700=85` → quotient **17** → **dmg=17**

**Step 11 — STAB:** WATER ∉ [NORMAL] → skip. dmg=17

**Step 12 — type effectiveness:** get_uq412(WATER, NORMAL)=4096 (×1.0). Mono-type → no `_uq412_multiply`.
- `17×4096=69632`; `69632+2047=71679`
- `71679/4096`: `4096×17=69632`; `71679−69632=2047` → quotient **17** → **dmg=17**

**Steps 13–16:** No Thick Fat, no burn, no Life Orb, no resist berry → all skip. dmg=17

**Step 17 — floor:** 17 > 0 → no change.

**Result: 17. Asserted value: 17. ✓ MATCH**

**Wrong-order check** (weather placed after roll instead of before):
- dmg=14 after step 6 (same).
- Roll at wrong position: `14×85=1190`; `1190/100`: `100×11=1100`; `1190−1100=90` → quotient **11**; dmg=11.
- Weather at wrong position: `11×6144=67584`; `67584+2047=69631`; `69631/4096`: `4096×16=65536`; `4096×17=69632`; `69631<69632` → quotient **16**.
- Wrong order gives **16 ≠ 17**. Test is genuinely discriminating.

---

#### Trace 3 — item_test.gd I4.02: Life Orb Psychic, roll=85 (expected 94)

**Setup:**
- Attacker: type=[PSYCHIC], base_spatk=100 → sp_atk=105, level=50. Holds Life Orb (HOLD_EFFECT=60). No ability. No status.
- Defender: type=[NORMAL], base_spdef=70 → sp_def=75. No item. No ability.
- Move: Psychic — type=PSYCHIC, category=1 (Special), power=90, crit_stage=0.
- force_roll=85, force_crit=false, weather=WEATHER_NONE, is_spread=false, helping_hand=false.

**Pre-conditions:** blocks_move_type → no ability → skip. PSYCHIC vs [NORMAL] = 1.0× ≠ 0.0 → proceed. No fixed/level damage.

**Step 1 — crit:** force_crit=false → `is_crit=false`

**Step 2 — stat stages:** category=Special → atk_base=105, atk_stage=0, def_base=75, def_stage=0. is_crit=false → no clamp.
- `_apply_stage(105, 0)`: STAGE_RATIOS[6]=[10,10]; `105×10=1050`; `1050/10=105` → **atk=105**
- `_apply_stage(75, 0)`: `75×10=750`; `750/10=75` → **def=75**

**Step 3 — ability atk mod:** no ability → mod=4096 → skip. atk=105

**Step 4 — item atk mod:** Life Orb is not Band/Specs → `attack_modifier_uq412` returns 4096 → skip. atk=105

**Step 5 — Helping Hand:** false → effective_power=90

**Step 6 — base formula:** `90 × 105 × (2×50/5+2) / 75 / 50 + 2`
- `2×50=100`; `100/5=20`; `20+2=22`
- `90×105=9450`
- `9450×22`: `9000×22=198000`; `450×22=9900`; `198000+9900=207900`
- `207900/75`: `75×2772=207900` exactly → quotient **2772**
- `2772/50`: `50×55=2750`; `2772−2750=22` → quotient **55**
- `55+2=57` → **dmg=57**

**Step 7 — spread:** is_spread=false → skip. dmg=57

**Step 8 — weather:** WEATHER_NONE → mod=4096 → skip. dmg=57

**Step 9 — crit multiplier:** is_crit=false → skip. dmg=57

**Step 10 — roll:** force_roll=85
- `57×85`: `50×85=4250`; `7×85=595`; `4250+595=4845`
- `4845/100`: `100×48=4800`; `4845−4800=45` → quotient **48** → **dmg=48**

**Step 11 — STAB:** PSYCHIC ∈ [PSYCHIC] → apply.
- `48×6144`: `40×6144=245760`; `8×6144=49152`; `245760+49152=294912`
- `294912+2047=296959`
- `296959/4096`: `4096×72=294912`; `296959−294912=2047` → quotient **72** → **dmg=72**

**Step 12 — type effectiveness:** get_uq412(PSYCHIC, NORMAL)=4096 (×1.0). Mono-type → no `_uq412_multiply`.
- `72×4096`: `70×4096=286720`; `2×4096=8192`; `286720+8192=294912`
- `294912+2047=296959`
- `296959/4096`: `4096×72=294912`; `296959−294912=2047` → quotient **72** → **dmg=72**

**Step 13 — Thick Fat:** no ability → skip. dmg=72

**Step 14 — burn:** no burn → skip. dmg=72

**Step 15 — Life Orb:** `post_roll_modifier_uq412` returns 5324. 5324 ≠ 4096 → apply.
- `72×5324`: `70×5324=372680`; `2×5324=10648`; `372680+10648=383328`
- `383328+2047=385375`
- `385375/4096`: `4096×90=368640`; `4096×4=16384`; `368640+16384=385024` (=94×4096); `4096×95=389120`; `385375−385024=351` → quotient **94** → **dmg=94**

**Step 16 — Resist Berry:** no item → skip. dmg=94

**Step 17 — floor:** 94 > 0 → no change.

**Result: 94. Asserted value: 94. ✓ MATCH**

---

## [M15] Data pipeline: convert_pokedata.py

- Source: `src/data/pokemon/species_info/gen_{1,2,3}_families.h`, `src/data/moves_info.h`,
  `src/data/pokemon/level_up_learnsets/gen_{1,2,3}.h`,
  `include/constants/{species,pokedex,abilities,moves,battle_move_effects,pokemon}.h`
- Behavior: `tools/convert_pokedata.py` emits three JSON files to `as-imagined/data/`:
  - `pokemon.json` — 386 entries (#1–#386), deduped by natDexNum (base form only).
    Fields: dex, name, base_{hp/atk/def/spa/spd/spe}, types[2], catch_rate,
    base_friendship, gender_ratio, egg_groups[2], ability1/ability2/ability_h,
    item_common/item_rare.
  - `moves.json` — 935 moves (all expansion moves). Fields: id, name, effect, effect_name,
    type, category, power, accuracy, pp, priority, target, makes_contact, punching_move,
    biting_move, sound_move, powder_move, dance_move, healing_move, ignores_protect,
    ignores_substitute, thaws_user, critical_hit_stage, always_critical_hit, damages_*,
    ban_flags, two_turn, semi_inv_state, recoil_percent, drain_percent, fixed_damage,
    level_damage, secondary_effect (SE_* value), secondary_chance, stat_change_{stat,amount},
    stat_change_self, is_spread, is_protect, is_baton_pass, is_roar, is_metronome, is_bide,
    is_disable, is_encore, creates_substitute, destiny_bond, counter, mirror_coat,
    is_helping_hand, is_follow_me.
  - `learnsets.json` — keyed by dex number string, value = [{level, move_id, move_name}].
- All config flags assumed = GEN_LATEST = 9 (matches expansion `include/config/battle.h`).
- STANDARD_FRIENDSHIP resolves to 50 (GEN_8+ path).
- Unown (#201) hardcoded: uses UNOWN_MISC_INFO macro not parseable by block extractor.
- Alternate Deoxys and Unown forms (SPECIES_ID > 386) naturally excluded by natDexNum filter.
- `moves.json` secondary_effect field maps MOVE_EFFECT_POISON → SE value 2 (same slot as
  FREEZE); loader must distinguish these by effect_name if needed.
- 2026-07-01.

**Wrong-order check** (Life Orb before roll, per I4.02 discriminating comment):
- dmg=57 after step 9 (same).
- Life Orb at wrong position (before roll): `57×5324`: `50×5324=266200`; `7×5324=37268`; `266200+37268=303468`; `303468+2047=305515`; `305515/4096`: `4096×74`: `4096×70=286720`; `4096×4=16384`; `286720+16384=303104`; `305515−303104=2411`; `4096×75=307200`; `305515<307200` → quotient **74**; dmg=74.
- Roll at wrong position (after Life Orb): `74×85`: `70×85=5950`; `4×85=340`; `5950+340=6290`; `6290/100`: `100×62=6200`; `6290−6200=90` → quotient **62**; dmg=62.
- STAB: `62×6144`: `60×6144=368640`; `2×6144=12288`; `368640+12288=380928`; `380928+2047=382975`; `382975/4096`: `4096×93`: `4096×90=368640`; `4096×3=12288`; `368640+12288=380928`; `382975−380928=2047`; `4096×94=385024`; `382975<385024` → quotient **93**; dmg=93.
- Type eff ×1.0: `93×4096=380928`; `380928+2047=382975`; `382975/4096=93` (identical to STAB computation) → dmg=93.
- Wrong order gives **93 ≠ 94**. Test is genuinely discriminating.

---

## [M15 Task 2] PokemonRegistry autoload singleton

- Source: project design decision (Milestone 15 Task 2)
- Behavior: `scripts/data/pokemon_registry.gd` is registered as the `PokemonRegistry`
  autoload in `project.godot`. On `_ready()` it loads all three JSON files produced by
  `tools/convert_pokedata.py` and builds integer-keyed lookup dicts. API:
  - `get_species(dex_number: int) -> Dictionary` — raw JSON dict for that dex entry
  - `get_move(move_id: int) -> Dictionary` — raw JSON dict for that move
  - `get_learnset(dex_number: int) -> Array` — list of `{level, move_id, move_name}` entries
  - `get_all_species() -> Array` — all 386 species entries (ordered by dex)
- Key implementation note: Godot 4.3 `JSON.parse_string()` returns ALL numeric JSON values
  as `float`, not `int`. Dict keys for dex/id lookups are cast with `int(entry["dex"])` and
  `int(entry["id"])` at load time so that `get_species(1)` (int argument) resolves correctly.
  The learnsets file keys are already strings; converted via `int(key)` during load.
- Autoload registration: `class_name PokemonRegistry` would conflict with the autoload global
  name in Godot 4 — the script omits `class_name` and is accessed globally as `PokemonRegistry`.
- Smoke test: eight `assert()` calls in `_ready()` confirm Bulbasaur (#1), Charizard (#6),
  Mewtwo (#150), Rayquaza (#384) all load with non-zero base_hp and a second non-zero stat.
  Prints: "PokemonRegistry: smoke test passed — N species, N moves, N learnsets loaded".
- No battle engine changes — data loading only. All M1–M14 test suites pass without change.
- 2026-07-01.

---

## [M15 Task 2b] PokemonRegistry — learnable moves

- Source: `reference/pokeemerald_expansion/src/data/pokemon/all_learnables.json` (TM/tutor teachable moves per species) and `special_movesets.json` (universalMoves + signatureTeachables).
- Behavior: `get_learnable_moves(dex_number: int) -> Array` returns a flat array of MOVE_X string constants combining species-specific teachable moves with the 10 `universalMoves` (deduped, universal appended at end). The two source JSON files are copied as-is to `data/all_learnables.json` and `data/special_movesets.json`.
- Name-to-key transform: species names in `pokemon.json` (Title Case, e.g. "Mr. Mime") are converted to `all_learnables.json` keys (SCREAMING_SNAKE_CASE, e.g. "MR_MIME") by: replace ♀→_F, ♂→_M, remove dots and apostrophes, replace spaces/hyphens with underscores, `.to_upper()`. Special case: "Deoxys" maps to "DEOXYS_NORMAL" (base form; file has no bare "DEOXYS" key).
- All 386 species map to valid keys in `all_learnables.json` after the transform.
- Smoke test addition: asserts `get_learnable_moves(1)` is non-empty and contains "MOVE_TACKLE". (MOVE_SURF was incorrectly listed in task spec — Bulbasaur does not have it in all_learnables.json.)
- All M1–M14 suites (579 tests) still pass. 2026-07-01.

---

## [M15 Task 3] PP System

- Source: `battle_move_resolution.c :: CancelerPPDeduction` (L972), enum position `CANCELER_PPDEDUCTION=51` — fires before `CANCELER_ACCURACY_CHECK=72`. PP costs even on a miss.
- Skip conditions (matching source L974–980): Struggle (`cv->move == MOVE_STRUGGLE`), charging release turn (`volatiles.multipleTurns` in source, equivalent to `attacker.charging_move != null` at entry to `_phase_move_execution` before the two-turn block clears it), Bide wait/release turns (also covered by `charging_move != null`).
- **Struggle:** `AreAllMovesUnusable` (battle_util.c L1652) with `MOVE_LIMITATION_PP` marks all moves unusable when all PP=0. `GetChosenMovePriority` (battle_main.c L4727–4728) returns `MOVE_STRUGGLE`. In our engine: `_is_forced_struggle()` checks `current_pp` at move selection time; `_struggle_move` is a permanent MoveData instance built in `BattleManager._ready()`.
- **Struggle properties** (source: `moves_info.h MOVE_STRUGGLE`): power=50, TYPE_MYSTERY (typeless — no STAB, no type effectiveness), Physical, makes_contact=true, accuracy=0 (always hits). PP never decremented.
- **Struggle recoil** (source: `MOVE_EFFECT_RECOIL_HP_25`, battle_script_commands.c L2534–2543): `recoil = maxHP / 4; if (recoil == 0) recoil = 1`. This is 25% of the user's **max HP**, NOT % of damage dealt (unlike normal recoil moves). Handled separately from `recoil_percent` path via `is_struggle` flag.
- **BattlePokemon API added**: `has_pp(move_index)` → bool, `use_pp(move_index)` → decrements by 1, no underflow.
- **MoveData field added**: `is_struggle: bool` — guards Struggle-specific PP skip and HP recoil.
- pp_test.gd: 26 assertions covering PP init, has_pp/use_pp, release-turn exemption, forced-Struggle detection, and full 1-PP-then-Struggle scenario with recoil. All 605 tests (M1–M15 Task 3) clean. 2026-07-01.

---

## [M16a] Tier A Move Effects — RESTORE_HP / FOCUS_ENERGY / GROWTH / OHKO

### EFFECT_RESTORE_HP (Recover / Slack Off / Heal Order)
- Source: `battle_script_commands.c :: Cmd_tryhealhalfhealth` (L7016)
  - `SetHealAmount(target, GetNonDynamaxMaxHP(target) / 2)`
  - Fails if `current_hp == max_hp` (already at full health).
- Behavior: heals `max(1, max_hp / 2)` HP; capped at `max_hp`. Emits `drain_heal` signal. Fails (emits `move_effect_failed("already_full_hp")`) when already at max HP.
- Move data: `is_restore_hp: bool` field added to MoveData. Moves: Recover(105) pp=5, Slack Off(303) pp=5, Heal Order(456) pp=10.
- PP values: Recover/Slack Off pp=5 with `B_UPDATED_MOVE_DATA >= GEN_9` (GEN_LATEST). Heal Order pp=10 (hardcoded). Confirmed from source.
- 2026-07-01.

### EFFECT_FOCUS_ENERGY (Focus Energy)
- Source: `battle_script_commands.c :: Cmd_setfocusenergy` (L7718) — sets `volatiles.focusEnergy = TRUE`. Fails if already set.
- Source: `battle_util.c :: CalcCritChanceStage` (L7836) — `critChance = (focusEnergy != 0 ? 2 : 0) + GetMoveCriticalHitStage(move) + ...`
- Behavior: volatile `focus_energy: bool` on BattlePokemon. When set, adds +2 to the effective crit stage in `DamageCalculator._roll_crit`. Cleared by `_clear_volatiles()` (faint and switch-out).
- Config used: `B_FOCUS_ENERGY_CRIT_RATIO >= GEN_3` → the +2 crit stage path (not Gen 1 inversion).
- Focus Energy (116): pp=30, accuracy=0, Normal/Status, ignores_protect=true.
- 2026-07-01.

### EFFECT_GROWTH (Growth)
- Source: `src/data/moves_info.h MOVE_GROWTH` (L2003–2026):
  - `B_UPDATED_MOVE_DATA >= GEN_5` → raises both ATK +1 AND SpATK +1 (GEN_LATEST applies).
  - `B_UPDATED_MOVE_DATA >= GEN_6` → pp=20 (GEN_LATEST applies; was 40 in Gen5).
- Source: `battle_stat_change.c :: AdjustStatStage` (L800): if `EFFECT_GROWTH` and weather == `B_WEATHER_SUN` → `stage = 2` (doubles the boost, so +2 to both in harsh sun).
- Behavior: +1 Atk AND +1 SpAtk normally; +2 each in WEATHER_SUN. Both stats changed simultaneously; each emits `stat_stage_changed`. Fails with `"stat_limit"` only if BOTH are already at +6.
- Growth (74): pp=20, accuracy=0, Normal/Status, ignores_protect=true.
- 2026-07-01.

### EFFECT_OHKO (Guillotine / Horn Drill / Fissure / Sheer Cold)
- Source: `battle_util.c :: DoesOHKOMoveMissTarget` (L10378)
  - Level check: fail if `def.level > atk.level`.
  - Custom accuracy: `odds = GetMoveAccuracy(move) + (atk.level - def.level)`, rolled against `randi() % 100`.
- Source: `battle_util.c` L7696: `case EFFECT_OHKO: dmg = gBattleMons[ctx->battlerDef].hp` — damage = defender's current HP (instant KO).
- Behavior: inserted BEFORE the normal accuracy check in `_phase_move_execution`. Type immunity (ability + type chart) checked first. Semi-invulnerable check inlined (Fissure has `damages_underground=true` to hit Dig users). Level fail emits `move_missed("ohko_failed")`. Accuracy fail emits `move_missed("accuracy")`. Hit: calls `_apply_fixed_dmg_to_target(attacker, defender, move, defender.current_hp)`.
- Move data: `is_ohko: bool` field added. Moves: Guillotine(12) Normal/Phys, Horn Drill(32) Normal/Phys, Fissure(90) Ground/Phys+damages_underground, Sheer Cold(329) Ice/Spec.
- All four OHKO moves: power=1 (placeholder), accuracy=30, pp=5 — confirmed from source.
- Sheer Cold Ice-type immunity (`B_SHEER_COLD_IMMUNITY >= GEN_7`) deferred to M16b.
- 2026-07-01.

---

## [M16b] Tier B Move Effects — MINIMIZE / DEFENSE_CURL / Stomp / ROLLOUT / MAGNITUDE

### Canonical ID correction: Stomp is move 23, not 31
- The task spec named move ID 31 for Stomp. Checked against
  `include/constants/moves.h` before implementing (per CLAUDE.md workflow): `MOVE_STOMP = 23`;
  ID 31 is actually `MOVE_FURY_ATTACK`. Used the correct ID (23) to avoid silently overwriting
  or misnaming the Fury Attack move slot. 2026-07-02.

### EFFECT_MINIMIZE (Minimize)
- Source: `src/data/moves_info.h MOVE_MINIMIZE` (L2895–2921): `.effect = EFFECT_MINIMIZE`,
  `.accuracy = 0`, `.pp = 10` (`B_UPDATED_MOVE_DATA >= GEN_6`), `.target = TARGET_USER`,
  `.ignoresProtect = TRUE`. `additionalEffects = {STAT_CHANGE_EFFECT_PLUS, .evasion = 2}`
  (`B_MINIMIZE_EVASION >= GEN_5` → GEN_LATEST config resolves to +2, not the pre-Gen5 +1).
- Source: `src/battle_stat_change.c :: SetAdditionalEffectsOnStatChange`, case
  `EFFECT_MINIMIZE` (L1000): `volatiles.minimize = TRUE` **only if**
  `MOVE_RESULT_STAT_CHANGED` — i.e. the evasion raise must have actually succeeded (not
  already capped at +6) for the `minimized` flag to be set. Contrast with Defense Curl below.
- Behavior: dedicated block in `_phase_move_execution` (self-targeting, before the generic
  substitute/type-immunity status-move path — same pattern as Growth/Focus Energy). Raises
  Evasion +2 via `StatusManager.apply_stat_change`; sets `attacker.minimized = true` only on
  success; emits `move_effect_failed("stat_limit")` on failure (matches the Growth precedent).
- `minimized: bool` added to BattlePokemon; cleared in `_clear_volatiles` (faint + switch-out,
  since `_switch_out_clear` calls `_clear_volatiles`).
- Minimize (107): Normal/Status, accuracy=0, pp=10, ignores_protect=true.
- 2026-07-02.

### EFFECT_DEFENSE_CURL (Defense Curl)
- Source: `src/data/moves_info.h MOVE_DEFENSE_CURL` (L3011–3039): `.effect =
  EFFECT_DEFENSE_CURL`, `.accuracy = 0`, `.pp = 40`, `.target = TARGET_USER`,
  `.ignoresProtect = TRUE`. `additionalEffects = {STAT_CHANGE_EFFECT_PLUS, .defense = 1}`.
- Source: `src/battle_stat_change.c :: SetAdditionalEffectsOnStatChange`, case
  `EFFECT_DEFENSE_CURL` (L997): `volatiles.defenseCurl = TRUE` **unconditionally** — no
  `MOVE_RESULT_STAT_CHANGED` guard, unlike Minimize. `defense_curled` is set even when the
  Defense raise itself fails (already at +6).
- Behavior: raises Defense +1; on failure emits `move_effect_failed("stat_limit")` (added
  for consistency with the rest of the codebase's stat-move failure signaling — the source's
  `additionalEffects` stat-change failure path already implies this message class); sets
  `attacker.defense_curled = true` unconditionally, even when the stat raise failed. Verified
  by m16b_test S3.03/S3.04 (defense_curled still true at +6 Defense, despite stat_limit fail).
- `defense_curled: bool` added to BattlePokemon; cleared in `_clear_volatiles`.
- Defense Curl (111): Normal/Status, accuracy=0, pp=40, ignores_protect=true.
- 2026-07-02.

### Stomp — `minimizeDoubleDamage` (×2.0 damage modifier vs minimized targets)
- Source: `include/move.h` L132: `bool32 minimizeDoubleDamage:1` (per-move flag, not
  restricted to Stomp — also Astonish, Extrasensory, Needle Arm, Body Slam, Flying Press,
  Steamroller, Dragon Rush, etc. in the full dataset; only Stomp is in scope for M16b).
- Source: `src/battle_util.c :: GetMinimizeModifier` (L7319–7323): `if
  (MoveIncreasesPowerToMinimizedTargets(move) && volatiles[battlerDef].minimize) return
  UQ_4_12(2.0);`. This function is one of several folded together in `GetOtherModifiers`
  (L7534–7562), which is applied as a single combined multiplier inside
  `ApplyModifiersAfterDmgRoll` (L7617–7628) — **after** the random roll, STAB, type
  effectiveness, and burn. **This is a standalone post-roll damage multiplier, not a
  doubling of the base-power input** — confirmed from source before implementing, per the
  task's explicit request to check this. A naive "double `move.power` before the formula"
  implementation would diverge from source on any hit where an earlier modifier (STAB, type
  effectiveness, burn) also applies, because those compound multiplicatively on the
  *already-doubled* value in the power-doubling approach but on the *original* value in the
  correct (post-roll-modifier) approach.
- Behavior: `move.double_power_on_minimized: bool` (mirrors `minimizeDoubleDamage`) checked
  in `DamageCalculator.calculate`, positioned after the burn modifier and before Life
  Orb/Resist Berry (matching source's ordering: burn → `GetOtherModifiers` → Life
  Orb/items). `dmg = _uq412_half_down(dmg, 8192)` where `UQ_4_12(2.0) = 8192`; since 8192 is
  an exact multiple of 4096, this always yields exactly `2 * dmg` with no rounding drift —
  verified in m16b_test S4.01 (exact equality, not an approximate/ratio check).
- Stomp (23): power=65, makes_contact=true, double_power_on_minimized=true, 30% flinch
  secondary (unchanged from its existing EFFECT_HIT shape — Stomp was not yet in the
  project's move set before M16b).
- 2026-07-02.

### EFFECT_ROLLOUT (Rollout / Ice Ball)
- Source: `src/battle_util.c :: CalcRolloutBasePower` (L6034–6042):
  `basePower = move.power; for (i = 0; i < volatiles.rolloutTimer; i++) basePower *= 2; if
  (volatiles.defenseCurl) basePower *= 2;`. `rolloutTimer` here is the **pre-hit** count
  (0 on a fresh start), so the sequence over 5 consecutive successful hits is
  30→60→120→240→480 (Rollout/Ice Ball both have `power=30`); Defense Curl doubles every
  step in the sequence (60→120→240→480→960), not just the first hit, since it's a flat ×2
  applied on top of the already-timer-scaled value each time.
- Source: `src/battle_move_resolution.c :: SetSameMoveTurnValues`, case `EFFECT_ROLLOUT`
  (L4899–4909): on a successful hit (`IsAnyTargetAffected() && !unableToUseMove &&
  gLastResultingMoves[attacker] == gCurrentMove` — this last clause is essentially always
  true for a landed hit since `gLastResultingMoves` is set to the current move earlier in
  the same move-end sequence, in `MOVEEND_UPDATE_LAST_MOVES`, which fires before
  `MOVEEND_CLEAR_BITS`/`SetSameMoveTurnValues`), `rolloutTimer` increments; if the
  incremented value would reach 5, it resets to 0 instead (fresh start on the *next* use).
  The `default:` branch of the same switch (L4915–4917, fired whenever **any other move**
  is used) unconditionally resets `rolloutTimer` to 0 — this is the actual mechanism behind
  "interruption resets the counter," not a same-move-as-last-turn comparison.
- Judgment call (scope simplification): the source additionally drives a forced
  auto-repeat via `gLockedMoves`/`volatiles.multipleTurns` (similar to Thrash/Petal Dance),
  meaning the game doesn't let the player choose a different move mid-streak. This project's
  action-queue test harness has no analogous "forced move" plumbing for non-two-turn moves,
  and the task scope only asked for the power-scaling counter and its resets (not the
  auto-repeat lock). Not implemented — Rollout/Ice Ball are freely reselectable each turn in
  this engine; using a different move simply resets the streak (matching the counter-reset
  behavior, just without preventing the choice in the first place).
- Miss handling: `IsAnyTargetAffected()` false (the hit missed) also resets `rolloutTimer`
  to 0 per the `EFFECT_ROLLOUT` case's `else` branch — implemented as an explicit reset in
  the accuracy-check-failure branch of `_phase_move_execution`, since the power calculation
  (needed regardless of hit/miss, as it doesn't depend on this hit's own outcome) happens
  before the accuracy check.
- Behavior: `attacker.rollout_turns: int` (pre-hit consecutive-count, 0–4) and
  `attacker.rollout_base_power: int` (the power computed for the current hit) added to
  BattlePokemon; both cleared in `_clear_volatiles`. Power computed in
  `_phase_move_execution` before the accuracy check and threaded into `_do_damaging_hit` via
  a new `power_override` parameter that also reaches `DamageCalculator.calculate`
  (`power_override >= 0` replaces `move.power` as the base-power input, mirroring source's
  `gBattleMovePower` being computed once via the per-effect switch in `CalcMoveBasePower`,
  before Helping Hand's multiplicative modifier is applied on top of it in
  `CalcMoveBasePowerAfterModifiers`). Reset-on-different-move is a single check
  (`if not move.is_rollout: attacker.rollout_turns = 0`) placed immediately before
  `attacker.last_move_used = move` is set — after all of the early-return special-move
  blocks (OHKO/Roar/Baton Pass/Protect/Bide/two-turn) but before Counter/Mirror Coat/the
  damaging-move dispatch, so it fires for any move that reaches that point in the pipeline.
- `is_rollout: bool` added to MoveData (shared by both Rollout and Ice Ball — same
  `EFFECT_ROLLOUT` handler in source, same power sequence, different type).
- Rollout (205): Rock/Phys, power=30, accuracy=90, pp=20, makes_contact=true.
- Ice Ball (301): Ice/Phys, power=30, accuracy=90, pp=20, makes_contact=true,
  ballistic_move not modeled (no Bullet Seed-style interaction in scope yet).
- 2026-07-02.

### EFFECT_MAGNITUDE (Magnitude)
- Source: `src/battle_move_resolution.c :: CalculateMagnitudeDamage` (L5196–5234):
  `magnitude = RandomUniform(0, 99)` then weighted bands: `[0,5)→10 (magnitude 4)`,
  `[5,15)→30 (5)`, `[15,35)→50 (6)`, `[35,65)→70 (7)`, `[65,85)→90 (8)`, `[85,95)→110 (9)`,
  `[95,100)→150 (10)` — i.e. power {10,30,50,70,90,110,150} with probability
  {5%,10%,20%,30%,20%,10%,5%} respectively (the displayed "Magnitude N" number 4–10 is
  cosmetic text, not modeled).
- Source: `src/battle_util.c` L6160–6161: `case EFFECT_MAGNITUDE: basePower =
  gBattleStruct->magnitudeBasePower;` — the roll happens once per move use and the result
  is reused for every spread target (not rerolled per target).
- Source: `src/data/moves_info.h MOVE_MAGNITUDE` (L6063–6084): `.power = 1` (placeholder,
  always overridden), `.type = TYPE_GROUND`, `.accuracy = 100`, `.pp = 30`, `.target =
  TARGET_FOES_AND_ALLY` (spread — `is_spread = true` in our data), `.damagesUnderground =
  TRUE` (hits Dig users, same as Earthquake).
- Behavior: `is_magnitude: bool` added to MoveData. `_force_magnitude_power: Variant = null`
  test seam added to BattleManager (same null-sentinel convention as `_force_hit`/
  `_force_roll`/`_force_crit`/`_force_contact_roll`). New private helper
  `_roll_magnitude_power()` rolls the weighted table (or returns the forced value); called
  once per move use in `_phase_move_execution`, before the accuracy check, threaded into
  `_do_damaging_hit` via the same `power_override` mechanism added for Rollout.
- Magnitude (222): Ground/Phys, power=1 (placeholder), accuracy=100, pp=30,
  damages_underground=true, is_spread=true.
- Known gap: this project's existing spread-move handling (`is_spread`) was not
  consistently set on prior moves with `TARGET_BOTH`/`TARGET_FOES_AND_ALLY` in source (e.g.
  Earthquake's `.tres` has no `is_spread` field despite the M14b decisions log stating it
  should). Not a M16b regression — pre-existing gap, out of scope here; Magnitude's own
  `is_spread=true` is set correctly per its own source citation above.
- 2026-07-02.

### Testing
- `m16b_test.gd`/`.tscn`: 55 assertions covering move-data spot checks, Minimize
  (evasion +2, `minimized` flag gated on success, stat-limit failure), Defense Curl
  (defense +1, `defense_curled` set unconditionally even on stat-limit failure), Stomp
  (exact ×2 damage vs minimized target, unaffected non-flagged moves), Rollout (full
  30→60→120→240→480→30 power sequence with pre-hit counter values, Defense Curl doubling,
  interruption-by-different-move reset, always-miss keeps counter at 0, `power_override`
  plumbing verified byte-for-byte against an equivalent baked-power move), Ice Ball (spot
  check, shares Rollout's logic), and Magnitude (`_force_magnitude_power` pass-through for
  all 7 table entries, unforced-roll membership check, `power_override` plumbing in both a
  direct `DamageCalculator.calculate` call and a real battle turn).
- All tests use `_force_hit`/`_force_roll`/`_force_crit`/`_force_magnitude_power` — no
  unforced RNG drives any assertion (one unforced call exists for `_force_magnitude_power =
  null`, but its assertion only checks table membership, which holds regardless of which
  value the RNG picks).
- Full regression: all prior suites (`battle_test` through `m16a_test`, plus `pp_test`,
  `two_turn_test`, `integration_test`) still pass with 0 failures. Total assertions across
  all numbered suites: 857 prior + 55 new = 912. (Several suites — `move_test`,
  `ability_test`, `item_test`, `doubles_test` — carry more assertions today than the counts
  recorded in their original milestone log entries; this reflects incremental test
  additions in later milestones, not a discrepancy introduced here.)
- 2026-07-02.

---

## [M16c] Tier C Move Effects — REFLECT / LIGHT_SCREEN / AURORA_VEIL / Brick Break

### Data shape: `_side_conditions[side]`, side-indexed (0/1), not battler- or field-slot-indexed
- First mechanic requiring genuinely per-side (not per-Pokémon, not per-battle) state.
  Confirmed the convention against existing per-side arrays before inventing a new one:
  `_follow_me_targets: Array[int] = [-1, -1]` (M14b) is already indexed by SIDE (always
  length 2), independent of `_active_per_side` (doubles just means 2 field slots share one
  side's Follow Me/screen state) — matches source's `gSideStatuses[side]` /
  `gSideTimers[side]` shape exactly (side-indexed, not per-battler).
- Implemented as `_side_conditions: Array = [{"reflect_turns": 0, "light_screen_turns": 0,
  "aurora_veil_turns": 0}, {...}]` — one dict per side, folding the presence bit
  (`gSideStatuses` bitmask) and the duration (`gSideTimers[side].xTimer`) into a single int
  per condition (0 = not active). This shape is intended to be reused for Trick Room
  (field-wide, not side-wide — would need its own top-level int, not an entry in this dict)
  and entry hazards (side-wide, WOULD fit as additional keys in this same per-side dict) in
  M16d, per the task's explicit forward-compat request.
- 2026-07-02.

### EFFECT_REFLECT / EFFECT_LIGHT_SCREEN
- Source: `src/battle_script_commands.c :: TrySetReflect` (L2088–2106) / `TrySetLightScreen`
  (L2109–2127): both fail (return `FALSE`, no refresh) if the respective
  `gSideStatuses[side]` bit is already set; otherwise set the bit and
  `gSideTimers[side].{reflectTimer,lightscreenTimer} = 5` (8 with Light Clay — **not
  modeled**; this project has no held-item duration-extension mechanic yet, noted as a
  follow-up rather than silently ignored).
- Source: `src/data/moves_info.h MOVE_REFLECT` (L3123–3147) / `MOVE_LIGHT_SCREEN`
  (L3071–3095): both `.accuracy = 0`, `.target = TARGET_USER` (self-targeting),
  `.ignoresProtect = TRUE`. Reflect pp=20, Light Screen pp=30.
- Behavior: dedicated self-targeting blocks in `_phase_move_execution`, same architectural
  pattern as Minimize/Defense Curl/Growth (M16b) — placed immediately after Defense Curl,
  before the generic substitute/type-immunity status-move path. Fail path emits
  `move_effect_failed(attacker, "already_reflect"/"already_light_screen")`.
- Verified via `m16c_test` S2.08/S2.09 that re-using Reflect while already active does
  **not** refresh the timer (matches `TrySetReflect`'s early-return-`FALSE` — no timer
  write on the failure path). Also verified (S2.06/S2.07) that once a screen's sole-move
  caster has nothing else to select, it gets legitimately **re-cast** after the timer
  naturally expires — this is correct real-game behavior (Reflect can be re-applied after
  wearing off), not a bug; the test windows are bounded to the first 5-turn cycle to avoid
  conflating a fresh recast with the original cast.
- 2026-07-02.

### EFFECT_AURORA_VEIL
- Source: `src/battle_move_resolution.c` (L1191–1193): fails outright
  (`BattleScript_ButItFailed`) unless `GetWeather() & B_WEATHER_ICY_ANY`
  (`B_WEATHER_HAIL | B_WEATHER_SNOW`, `include/constants/battle.h` L504) — checked as a
  pre-move canceler, i.e. **before** the move's own "already up" check runs. This project
  only models Hail (no separate Snow weather state — confirmed against M11's weather scope
  in CLAUDE.md, which lists rain/sun/sandstorm/hail as the only four), so the gate
  simplifies exactly to `weather == WEATHER_HAIL` with no loss of behavior.
- Source: `src/battle_script_commands.c :: BS_SetAuroraVeil` (L13439–13462): fails only if
  `SIDE_STATUS_AURORA_VEIL` is already set — it does **not** check Reflect or Light Screen.
  Confirmed: Aurora Veil, Reflect, and Light Screen are three **independent** bitmask flags
  (`SIDE_STATUS_REFLECT`, `SIDE_STATUS_LIGHTSCREEN`, `SIDE_STATUS_AURORA_VEIL`, distinct
  bits in `include/constants/battle.h` L403–405), not a single shared "screen slot" — all
  three can be simultaneously active on the same side. `auroraVeilTimer = 5` (8 with Light
  Clay — not modeled, same as Reflect/Light Screen).
- Stacking / no-double-reduction: confirmed via `GetScreensModifier` (below) that having
  multiple screens active simultaneously does **not** compound the damage reduction — it's
  a plain boolean OR over the three conditions, applying the single ×0.5/×0.667 factor once,
  not multiplied together (e.g. Reflect + Aurora Veil both up ≠ ×0.25). Verified in
  `m16c_test` S4.10/S4.11 (exact equality against the single-screen reduction, both via a
  direct `DamageCalculator.calculate` call and a live battle with both flags set).
- Behavior: hail check first, then "already up" check, matching source's cancel-before-effect
  ordering — both implemented inline in the `is_aurora_veil` block (this project has no
  general canceler-chain architecture matching every per-move source precondition; each
  move's failure conditions are checked inline in its own dedicated block, established
  precedent since M7).
- Aurora Veil (657): Ice/Status, accuracy=0, pp=20, ignores_protect=true.
- 2026-07-02.

### Damage pipeline placement: `GetScreensModifier`, same group as M16b's Minimize modifier
- Source: `src/battle_util.c :: GetScreensModifier` (L7347–7365):
  ```
  bool32 lightScreen = (sideStatus & SIDE_STATUS_LIGHTSCREEN) && IsBattleMoveSpecial(move);
  bool32 reflect = (sideStatus & SIDE_STATUS_REFLECT) && IsBattleMovePhysical(move);
  bool32 auroraVeil = sideStatus & SIDE_STATUS_AURORA_VEIL;   // no category gate
  if (ctx->isCrit || ctx->isSelfInflicted) return UQ_4_12(1.0);
  if (Infiltrator && not ally) return UQ_4_12(1.0);           // not modeled, see below
  if (reflect || lightScreen || auroraVeil)
      return IsDoubleBattle() ? UQ_4_12(0.667) : UQ_4_12(0.5);
  return UQ_4_12(1.0);
  ```
  This function is folded into `GetOtherModifiers` (L7534–7562) in the exact sequence
  `Minimize → Underground → Dive → Airborne → Screens → CollisionCourseElectroDrift`, which
  fires inside `ApplyModifiersAfterDmgRoll` — i.e. the **same modifier group** as M16b's
  Stomp/`GetMinimizeModifier`, confirmed by re-reading that function's neighbors rather than
  assuming the position from memory (per the task's explicit instruction to verify
  placement the way M16b did for Stomp).
- Reduction fraction — confirmed from source rather than assumed: singles `UQ_4_12(0.5) =
  2048`; doubles `UQ_4_12(0.667) = (uq4_12_t)(0.667 * 4096 + 0.5) = 2732` — matched to
  source's literal `0.667` decimal bit-for-bit (not recomputed as the mathematically "true"
  2/3). The doubles gate is `IsDoubleBattle()` alone — **no live-target-count check**,
  unlike the M14b spread-move 0.75× reduction (`GetTargetDamageModifier` requires ≥2 live
  targets); confirmed these are different mechanisms with different gating conditions.
- Crit bypass: `if (ctx->isCrit ...) return UQ_4_12(1.0);` fires first in source — crits
  ignore screens entirely, confirmed and implemented via an `and not is_crit` guard on the
  modifier application (`is_crit` is already resolved earlier in `DamageCalculator.calculate`
  by that point, either forced or rolled). Verified in `m16c_test` S5.02: a screened crit's
  damage matches an unscreened crit's damage exactly.
- Infiltrator ability bypass (`ABILITY_INFILTRATOR` ignores screens) — **not modeled**.
  Infiltrator is outside this project's implemented-ability scope (M8's list: Huge
  Power/Pure Power, Levitate, Thick Fat, Intimidate, Drizzle/Drought, Speed Boost, Static,
  Flame Body, Rough Skin, Synchronize — no Infiltrator). Noted as a known gap rather than
  silently skipped, same treatment as M16a's Sheer Cold Ice-immunity gap.
- Behavior: `DamageCalculator.calculate` gained two new optional params, `screen_active:
  bool = false` and `is_doubles: bool = false`. Resolution of *which* screen applies (by
  move category) happens in `BattleManager._do_damaging_hit` — a stateless static utility
  like `DamageCalculator` has no access to `_side_conditions`, so the caller pre-resolves
  the boolean and passes it in, mirroring the existing `power_override`/`helping_hand`
  pattern from M16a/M16b. `UQ412_SCREEN_SINGLES = 2048` / `UQ412_SCREEN_DOUBLES = 2732`
  added as named constants next to `UQ412_1_5`.
- 2026-07-02.

### Brick Break — `MOVE_EFFECT_BREAK_SCREEN`
- Grepped the reference repo for screen-removal moves per the task's explicit instruction
  (rather than silently skipping this scope item). Found `MOVE_EFFECT_BREAK_SCREEN` on
  Brick Break (`src/data/moves_info.h MOVE_BRICK_BREAK`, L7672–7697): `.effect = EFFECT_HIT`
  (a normal damaging move, not a dedicated top-level effect), power=75, Fighting, contact,
  `additionalEffects = {MOVE_EFFECT_BREAK_SCREEN, .preAttackEffect = TRUE}`. This is the
  only screen-removal move in the current move set (Defog/Court Change also interact with
  `SIDE_STATUS_SCREEN_ANY` in source but are far outside this project's implemented-move
  scope and out of place to add speculatively here) — implemented as part of this
  milestone per the task's scoping instruction.
- Source: `src/battle_script_commands.c` :: `MOVE_EFFECT_BREAK_SCREEN` case (L3308–3336):
  `B_BRICK_BREAK >= GEN_4` (config default is `GEN_LATEST`, confirmed in
  `include/config/battle.h` L108) → clears `GetBattlerSide(gBattlerTarget)` — the move's
  **actual target's** side, not hardcoded to "the opponent's side" (matters if Brick Break
  is used on an ally in doubles; this project's implementation uses whatever `defender` was
  resolved to, so it's already correct for that case without special-casing). Clears
  `SIDE_STATUS_SCREEN_ANY` (all three conditions at once) and only plays the
  break/animation if something was actually up.
- `preAttackEffect = TRUE` — the screen removal resolves **before** this hit's own damage
  calculation, so a screen Brick Break itself just broke does **not** reduce its own
  damage. Implemented at the very top of `BattleManager._do_damaging_hit` (before the
  `screen_active` resolution and the `DamageCalculator.calculate` call): if
  `move.breaks_screens` and any of the three side-condition timers on the target's side are
  nonzero, zero all three and emit `screens_broken(side)`; the subsequent `screen_active`
  computation reads the (now-cleared) `_side_conditions` dict, so it naturally sees nothing
  active for this hit. Verified in `m16c_test` S6.03/S6.04 (Brick Break's own damage against
  a pre-screened target matches an unscreened baseline exactly).
- `B_BRICK_BREAK >= GEN_5` additionally gates screen removal on the move actually having
  affected the target (not blocked by Protect/immunity) — **not separately implemented**,
  since Protect blocking in this engine already returns early before reaching the
  damaging-move dispatch (the code path that contains the screen-break logic), so a
  Protect-blocked Brick Break can never reach `_do_damaging_hit` in the first place; the
  Gen5+ behavior falls out of the existing control flow for free, without new code.
- `breaks_screens: bool` added to MoveData. Brick Break (280): Fighting/Phys, power=75,
  accuracy=100, pp=15, makes_contact=true.
- 2026-07-02.

### Switch-out / side-clear interaction
- Confirmed by construction, not by adding new code: `_side_conditions` is a `BattleManager`
  field, not a `BattlePokemon` field. `_clear_volatiles` and `_switch_out_clear` (both
  defined in `BattleManager`) operate exclusively on `BattlePokemon` instances passed to
  them — neither touches `_side_conditions` at all, so screens persist across the owning
  side's voluntary switches, forced switches (Roar/Whirlwind), and faint replacements
  automatically. Verified in `m16c_test` S2.12 (Reflect still active on side 0 immediately
  after a mid-battle voluntary switch, snapshotted via the `pokemon_switched_in` signal
  rather than checked after the whole battle completes — checking post-battle would
  observe arbitrarily-later state once the timer naturally expires on its own 5-turn
  clock, unrelated to the switch itself).
- 2026-07-02.

### Testing
- `m16c_test.gd`/`.tscn`: 60 assertions covering move-data spot checks (Light Screen,
  Reflect, Brick Break, Aurora Veil, plus `_side_conditions` default shape), Reflect
  (setup, exact floor(dmg/2) Physical reduction, Special immunity, 5-turn duration sequence
  with exact `screen_expired` firing point, already-up no-refresh, doubles ⅔ reduction
  exact-match against `UQ_4_12(0.667)`, switch persistence), Light Screen (setup, exact
  floor(dmg/2) Special reduction, Physical immunity), Aurora Veil (hail gate failure and
  success, already-up independent of Reflect/Light Screen, coexistence without blocking,
  reduces both categories, no double-stacking with Reflect both direct-call and live-battle),
  crit bypass (screened crit == unscreened crit, exact), and Brick Break (clears target's
  side, own damage unaffected by the screen it just broke, no-op when nothing is up, clears
  all three condition types at once).
- All tests use `_force_hit`/`_force_roll`/`_force_crit` plus directly-set `weather`/
  `_side_conditions` for setup — no unforced RNG drives any assertion.
- Test-writing note for future milestones: several sole-move-Pokémon test setups (a
  Pokémon whose only move is the status move under test) legitimately **re-cast** that move
  after its side condition naturally expires, since auto-select falls back to `moves[0]`
  every turn once the action queue is drained. Reading `_side_conditions` (or any per-side/
  per-battle state with its own independent timer) **after** `start_battle` fully returns
  is unreliable once the battle runs long enough for that natural recast-and-re-expire
  cycle to occur — several assertions in this suite initially failed this way and were
  fixed by snapshotting state via a signal callback at the specific moment being tested
  (`screen_set`, `pokemon_switched_in`, a bounded `phase_changed`-into-`SWITCH_PROMPT`
  counter) rather than after the whole battle. Apply the same snapshot-not-post-battle
  discipline to any future side-condition or field-condition test (Trick Room, hazards).
- Full regression: all prior suites (`battle_test` through `m16b_test`, plus `pp_test`,
  `two_turn_test`, `integration_test`) still pass with 0 failures. Total assertions across
  all numbered suites: 912 prior + 60 new = 972.
- 2026-07-02.

---

## [M16d] Tier D Move Effects — Entry Hazards (SPIKES / TOXIC_SPIKES / STEALTH_ROCK) / RAPID_SPIN / TRICK_ROOM

### Reused pattern: hazards live in the SAME `_side_conditions[side]` dict as M16c's screens
- Per the task's explicit instruction, hazards were added as new keys on the existing
  per-side dict rather than a new array/shape: `"spikes_layers": int (0-3)`,
  `"toxic_spikes_layers": int (0-2)`, `"stealth_rock": bool`. Unlike the M16c screens
  (which store turns-remaining), hazards have no natural duration in source — they persist
  until explicitly cleared (Rapid Spin) or the battle ends — so they're stored as plain
  layer counts / a bool instead of a countdown.
- Confirmed by construction (same reasoning as M16c's persistence note): `_clear_volatiles`
  / `_switch_out_clear` only ever touch `BattlePokemon` fields, never `_side_conditions`, so
  hazards persist across the owning side's switches automatically — no new code needed to
  guarantee this, verified in `m16d_test` S2.11/S2.12.
- New forward-compat note for a future milestone: this dict is now genuinely mixed-shape
  (durations AND layer counts AND booleans in one dict) — fine for now, but if a future
  hazard needs its own per-instance data (e.g. Toxic Spikes tracking *who* set it, or a
  hazard with its own separate duration), consider whether the flat-dict shape still fits
  before blindly adding another key.

### New per-battle pattern: `trick_room_turns`, NOT part of `_side_conditions`
- Trick Room is genuinely field-wide, not side-wide — confirmed from source
  (`.target = TARGET_FIELD`, and the mechanism reads `gFieldStatuses`/`gFieldTimers`, which
  are singular per-battle values, not per-side arrays like `gSideStatuses`/`gSideTimers`).
  Implemented as a plain top-level `BattleManager.trick_room_turns: int` field, mirroring
  the existing `weather`/`weather_duration` convention (also field-wide, also plain fields)
  rather than `_side_conditions` (which is specifically for side-wide state). Confirmed this
  distinction before implementing, per the task's explicit instruction not to conflate the
  two shapes.

### "Grounded" check: new `AbilityManager.is_grounded()`, reused for both hazards
- Source: `src/battle_util.c :: IsBattlerGrounded` (L5896) →
  `IsBattlerGroundedInverseCheck` (L5879) → `IsBattlerUngroundedByAbilityItemOrEffect`
  (L5866): a battler is ungrounded (immune to Spikes/Toxic Spikes) if it has the Levitate
  ability or is a Flying-type (checked in that order in source; order doesn't matter here
  since both are simple independent conditions).
- Checked this codebase's existing "grounded"-adjacent logic before writing anything new,
  per the task's explicit instruction: `AbilityManager.blocks_move_type` (M8) already
  encodes Levitate's Ground-type-move immunity, but that's a *move-type* immunity check
  (`move.type == TYPE_GROUND`), not a general grounded-status query — Spikes/Toxic Spikes
  aren't "Ground-type moves" being blocked, they're a switch-in trigger that needs to know
  the battler's grounded state independent of any specific move. No existing general
  "grounded" helper existed anywhere in the codebase, confirmed via search. Added
  `AbilityManager.is_grounded(mon) -> bool` as a new, narrower, reusable query (Levitate
  ability OR Flying-type → false; else true), called from `_apply_switch_in_hazards`.
- Known gaps (not modeled, noted rather than silently skipped): Air Balloon held item,
  Magnet Rise/Telekinesis volatiles (would additionally ungrounded), Iron Ball item /
  Gravity field status / Ingrain / Smack Down volatiles (would force-ground even a
  Flying-type or Levitate holder) — all outside this project's currently-implemented scope;
  none of the underlying mechanics (held-item-driven grounding, Gravity field, Ingrain,
  Smack Down) exist anywhere else in the codebase either, so this isn't a hazard-specific
  gap, it's a project-wide scope boundary.
- **Stealth Rock deliberately does NOT use `is_grounded`** — confirmed from source that
  `TryHazardsOnSwitchIn`'s `HAZARDS_STEALTH_ROCK` case only checks `IsBattlerAffectedByHazards`
  (alive + not Heavy Duty Boots, not modeled) and Magic Guard (not modeled, no such ability
  in this project), with **no** `IsBattlerGrounded` call at all — this is exactly why
  Flying-types and Levitate holders still take Stealth Rock damage. Verified in `m16d_test`
  S4.09/S4.10 (Flying-type takes maxHP/4 from Stealth Rock, same as any other 2x-weak type).

### EFFECT_SPIKES
- Source: `src/battle_script_commands.c :: Cmd_trysetspikes` (L8373–8390): targets
  `GetBattlerSide(BATTLE_OPPOSITE(gBattlerAttacker))` — the **opponent's** side, the
  opposite of Reflect/Light Screen/Aurora Veil (M16c) which target the caster's own side.
  Fails (no wrap-around) at `spikesAmount == 3`; else increments.
- Source: `src/battle_switch_in.c :: TryHazardsOnSwitchIn`, case `HAZARDS_SPIKES`
  (L306–315): `spikesDmg = maxHP / ((5 - spikesAmount) * 2)` — 1 layer → maxHP/8, 2 →
  maxHP/6, 3 → maxHP/4. **Max HP**, not current HP. Requires grounded
  (`IsBattlerGrounded`) and `IsBattlerAffectedByHazards` (alive + not Heavy Duty Boots).
- Behavior: dedicated block in `_phase_move_execution`, targeting `1 - attacker_side`
  (opposite of the screens' `attacker_side`). Switch-in damage computed in the new
  `_apply_switch_in_hazards` helper, called at every switch-in site (see below).
- Spikes (191): Ground/Status, accuracy=0, pp=20, ignores_protect=true.
- 2026-07-02.

### EFFECT_TOXIC_SPIKES
- Source: `src/battle_script_commands.c :: Cmd_settoxicspikes` (L9043–9059): targets the
  opponent's side; fails at `toxicSpikesAmount >= 2`; else increments.
- Source: `src/battle_switch_in.c :: TryHazardsOnSwitchIn`, case `HAZARDS_TOXIC_SPIKES`
  (L328–359), in order:
  1. **Not grounded** → no effect at all (`effect = FALSE`) — the grounded check gates
     *before* the Poison-type absorb check, so an ungrounded Poison-type would neither
     absorb nor be poisoned. Verified with a plain Flying-type in `m16d_test` S3.10/S3.11.
  2. **Grounded + Poison-type** → absorbs: clears `toxicSpikesAmount` to 0 and removes the
     hazard from the field entirely (`RemoveHazardFromField`). The absorbing Pokémon is
     *not* itself poisoned.
  3. **Grounded, not Poison-type, `CanBePoisoned`** → 1 layer inflicts regular poison
     (`STATUS1_POISON`); 2 layers inflicts badly-poisoned/toxic (`STATUS1_TOXIC_POISON`).
- `CanBePoisoned` reused rather than re-derived: this project's `StatusManager.try_apply_status`
  already encodes the Poison/Steel-type immunity and the one-major-status-at-a-time guard
  (established in M3, decisions.md `[M3] Poison`/`[M3] One major status at a time`), so
  calling `try_apply_status(mon, STATUS_POISON | STATUS_TOXIC)` directly from
  `_apply_switch_in_hazards` correctly makes a grounded Steel-type immune (verified
  `m16d_test` S3.07/S3.08) without duplicating that check.
- Toxic Spikes (390): Poison/Status, accuracy=0, pp=20, ignores_protect=true.
- 2026-07-02.

### EFFECT_STEALTH_ROCK
- Source: `src/battle_script_commands.c` :: `MOVE_EFFECT_STEALTH_ROCK` case (L2707–2712):
  targets the opponent's side; single application (no layer count) — fails outright if
  already up.
- Source: `src/battle_util.c :: GetStealthHazardDamageByTypesAndHP` (L8317–8353), called
  with `hazardType = TYPE_SIDE_HAZARD_POINTED_STONES = TYPE_ROCK`
  (`include/constants/battle.h` L430–434): combined Rock-type effectiveness against the
  switching-in Pokémon's typing (both types multiplied together, same UQ4.12 accumulation
  style as normal damage calc) maps to a table: 0×→0, 0.25×→maxHP/32, 0.5×→maxHP/16,
  1×→maxHP/8, 2×→maxHP/4, 4×→maxHP/2, each nonzero case floored to a minimum of 1.
- Behavior: `_stealth_rock_damage(effectiveness, max_hp)` helper implements the table
  directly (reusing `TypeChart.get_effectiveness(TYPE_ROCK, mon.species.types)` for the
  combined multiplier — no new type-effectiveness logic needed, this project's existing
  dual-type combination already produces exactly the {0, 0.25, 0.5, 1, 2, 4} set).
- Stealth Rock (446): Rock/Status, accuracy=0, pp=20, ignores_protect=true.
- 2026-07-02.

### EFFECT_RAPID_SPIN
- Source: `src/data/moves_info.h MOVE_RAPID_SPIN` (L6247–6277): `.power = 50`
  (`B_UPDATED_MOVE_DATA >= GEN_8`, GEN_LATEST config applies), Normal/Physical, contact,
  accuracy=100, pp=40 — a normal damaging move, unlike the three status-category
  hazard-setters above.
- Source: `src/battle_move_resolution.c`, case `EFFECT_RAPID_SPIN` (L3569–3574):
  `IsAnyTargetTurnDamaged(battlerAtk, INCLUDING_SUBSTITUTES)` gates the clear effect — it
  fires even when the hit landed on the *defender's* Substitute, not only on a direct hit.
  Implemented at the top of `_do_damaging_hit`, right after `damage` is computed and
  *before* the `went_to_sub` branch that routes damage to a Substitute — placing it after
  that branch would have missed the Substitute case entirely, since that branch `return`s
  early. Verified in `m16d_test` S5.09/S5.10 with the opponent deliberately faster so its
  Substitute is already up before Rapid Spin fires within the same turn (had the user been
  faster, the hazard would clear from turn 1's direct hit before a Substitute ever existed,
  failing to isolate the case being tested).
- Source: `src/battle_script_commands.c :: Cmd_rapidspinfree` (L8578–8612): checks, in
  order, wrapped (Bind/Wrap) → Leech Seed → hazards on the **user's own** side — and for
  hazards, loops the hazard-type list and **returns after clearing the first match**, i.e.
  Rapid Spin clears only ONE hazard type per use, not all of them at once. This project's
  implemented hazard-type order (Spikes → Toxic Spikes → Stealth Rock, mirroring source's
  `HAZARDS_SPIKES` → `HAZARDS_STICKY_WEB` → `HAZARDS_TOXIC_SPIKES` → `HAZARDS_STEALTH_ROCK`
  enum with the unimplemented Sticky Web skipped) is replicated with a plain if/elif chain
  checked once per use. Verified in `m16d_test` S5.03–S5.07 (only Spikes clears when all
  three are simultaneously up; Toxic Spikes and Stealth Rock remain untouched).
- Known gap (not modeled, noted rather than silently skipped): the wrapped/Bind-Wrap-clear
  and Leech-Seed-clear branches ahead of the hazard-clear in `Cmd_rapidspinfree` are not
  implemented — this project has no Bind/Wrap-style trapping moves or Leech Seed
  implemented anywhere yet, so only the hazard-clearing branch (the one actually reachable
  given this project's current move set) applies.
- Rapid Spin (229): Normal/Phys, power=50, accuracy=100, pp=40, makes_contact=true.
- 2026-07-02.

### EFFECT_TRICK_ROOM
- Source: `src/data/moves_info.h MOVE_TRICK_ROOM` (L11641–11661): `.target = TARGET_FIELD`,
  `.priority = -7` (even lower than Roar/Whirlwind's -6 — confirmed from the M9 decisions
  entry), `.ignoresProtect = TRUE`, `.pp = 5`.
- Source: `src/battle_script_commands.c :: HandleRoomMove` (L9116–9121): **toggles** rather
  than failing when already active — `if (gFieldStatuses & statusFlag) { clear it, timer=0
  } else { set it, timer=5 }`. This is a real behavioral difference from every M16c screen
  and the M16d hazard-setters (all of which *fail* on re-use rather than toggling) —
  confirmed from source before implementing rather than assuming Trick Room follows the
  same fail-on-repeat pattern as everything else in this milestone family. Verified in
  `m16d_test` S6.09–S6.11 (re-using Trick Room while active cancels it immediately, does
  *not* refresh to a fresh 5 turns).
- Source: `src/battle_main.c :: GetWhichBattlerFasterArgs` (L4775–4821): priority is
  compared **first** (`if (priority1 == priority2) { ...speed... } else if (priority1 <
  priority2) strikesFirst = -1; else strikesFirst = 1;`) — the priority branch runs and
  returns without ever consulting `STATUS_FIELD_TRICK_ROOM`. Only *within* a tied priority
  bracket does the speed comparison invert under Trick Room (`speedBattler1 < speedBattler2`
  normally means battler2 goes first; under Trick Room it means battler1 goes first —
  i.e. lower effective speed wins the tiebreak). Traced this project's existing turn-order
  code (`_phase_priority_resolution`'s `_turn_order.sort_custom` comparator,
  `battle_manager.gd`) before touching it, per the task's explicit instruction, since this
  is the first mechanic to alter turn order itself rather than just damage/stats: the
  existing comparator already checks `pa != pb` (priority) *before* falling through to the
  `sa != sb` (speed) comparison, so the fix is a single-line change — swap `sa > sb` for
  `sa < sb` when `trick_room_turns > 0`, inserted at that exact point, leaving the priority
  branch completely untouched. Verified in `m16d_test` S6.03–S6.08 (slower Pokémon acts
  first under Trick Room; without Trick Room the same matchup has the faster one act first,
  confirming the effect is really Trick Room's doing; a priority move from the naturally
  faster Pokémon still goes first even under Trick Room, confirming priority is unaffected).
- Behavior: `trick_room_turns: int` field on `BattleManager` (per-battle, not
  `_side_conditions` — see the dedicated pattern note above). Decremented in
  `_phase_end_of_turn`, same position as the M16c screen decrements. `trick_room_set` /
  `trick_room_ended` signals added; `trick_room_ended` fires for **both** the toggle-off
  and the natural 5-turn expiry (source doesn't distinguish the two causes structurally
  either — both paths clear the same field-status bit via the same code shape).
- Trick Room (433): Psychic/Status, accuracy=0, pp=5, priority=-7, ignores_protect=true.
- 2026-07-02.

### Switch-in hazard triggering: 5 call sites, hazards before abilities
- Confirmed from source before wiring anything: `src/battle_switch_in.c`'s
  `FIRST_EVENT_BLOCK_*` enum order is `HEALING_WISH → HAZARDS → GENERAL_ABILITIES →
  IMMUNITY_ABILITIES → ITEMS` — **hazards fire before switch-in abilities** (Intimidate,
  Drizzle/Drought, etc.), not after. New `_apply_switch_in_hazards(mon, side)` helper is
  called immediately before every existing `_apply_switch_in_abilities(mon, side)` call
  site, matching this order.
- Found **5** switch-in call sites, not the 3 explicitly named in the task (voluntary
  switch, forced switch, faint replacement) — grepped for every call to
  `_apply_switch_in_abilities` rather than trusting the task's enumeration, per this
  project's standing "search the repo structure before implementing" instruction:
  1. `_phase_battle_start` — the initial simultaneous send-out (not explicitly requested,
     but wired in for consistency with `_apply_switch_in_abilities` already being called
     there for Intimidate/weather-setters, and to support pre-set-hazard test scenarios).
  2. `_do_voluntary_switch` (explicitly requested).
  3. `_do_forced_switch_in` — Roar/Whirlwind (explicitly requested).
  4. `_do_switch_in` — faint replacement (explicitly requested).
  5. The inline Baton Pass switch-in block in `_phase_move_execution` — this one does
     **not** go through `_apply_switch_in_abilities` at all; it has its own hand-rolled
     `AbilityManager.try_switch_in` call (a pre-existing simplification from M9, checking
     only the immediate `defender` rather than looping all opposing combatants). Missing
     this site would have left Baton Pass as a hazard-free switch-in path, contradicting
     "every switch-in" — added `_apply_switch_in_hazards` there too, immediately before its
     existing ability call.
- A hazard-fainted switch-in is handled via the same generic mechanism as weather/status
  chip damage (`mon.fainted = true; pokemon_fainted.emit(mon)`), relying on the existing
  `FAINT_CHECK`/`SWITCH_PROMPT` machinery to prompt a replacement on the next pass through
  those phases — not given dedicated chain-replacement testing in this milestone (not
  required by the task's testing checklist), but doesn't crash or leave inconsistent state.
- 2026-07-02.

### Testing
- `m16d_test.gd`/`.tscn`: 71 assertions covering move-data spot checks (all 5 moves plus
  `_side_conditions`/`trick_room_turns` defaults), Spikes (opponent's-side targeting,
  3-layer stacking with maxed-out failure, exact per-layer damage fraction for all 3
  layers, Flying-type and Levitate-holder grounded immunity, persistence + damage across a
  mid-battle switch), Toxic Spikes (1-layer poison vs 2-layer toxic threshold, Poison-type
  absorb clearing the hazard without self-poisoning, Steel-type immunity without absorbing,
  ungrounded Flying-type total immunity, 2-layer cap), Stealth Rock (single-application cap,
  neutral/4×-weak/resistant exact damage fractions, hits a Flying-type switch-in unlike
  Spikes), Rapid Spin (clears exactly one hazard type in Spikes→Toxic Spikes→Stealth Rock
  order, no clear on a miss, clears even when the hit lands on the defender's Substitute),
  and Trick Room (activation, exact speed-order reversal with a faster-vs-slower control
  case, priority still overriding the reversal, toggle-off-not-refresh, natural 5-turn
  expiry sequence).
- Repeated the M16c-identified pitfall and its fix in three more places this milestone
  (Spikes/Toxic Spikes/Stealth Rock multi-hazard Rapid-Spin ordering, and Trick Room's
  toggle behavior): several Pokémon in this suite have only ONE repeatable move (Rapid
  Spin, Trick Room), and since Trick Room *toggles* while Spikes/etc. can be **re-cast**
  after their own effects clear, a long-running battle (bounded only by the phase cap or an
  eventual faint) will legitimately cycle through multiple activations/clears/toggles.
  Every assertion in this suite that depends on "what happened after exactly one specific
  action" snapshots via a signal callback guarded to the first matching occurrence, never
  by reading `_side_conditions`/`trick_room_turns` after the whole battle completes.
- All tests use `_force_hit`/`_force_roll`/`_force_crit` plus directly-set
  `_side_conditions`/`trick_room_turns`/`weather` for setup — no unforced RNG drives any
  assertion.
- Full regression: all prior suites (`battle_test` through `m16c_test`, plus `pp_test`,
  `two_turn_test`, `integration_test`) still pass with 0 failures. Total assertions across
  all numbered suites: 972 prior + 71 new = 1043.
- 2026-07-02.

---

## [M16e] Tier E Move Effects — PURSUIT / PAIN_SPLIT / CONVERSION / CONVERSION_2 / PSYCH_UP / Baton Pass extension

### Process: testing convention codified in CLAUDE.md
- Before writing any M16e code, added a permanent "Testing convention: snapshot via
  signals, not post-battle state" section to `CLAUDE.md` (under "Working style / instructions
  for Claude Code"), since the pitfall had now independently bitten M16c and M16d. Future
  milestone prompts can reference "see CLAUDE.md testing conventions" rather than
  re-discovering the rule. M16e's own tests followed the rule from the start — and still hit
  it twice during development (see Testing section below), confirming the rule is easy to
  violate even when you know about it; every future milestone introducing persistent/
  toggleable state should budget for this explicitly.

### Pursuit — doubled power + turn-order interception
- Source: `src/data/moves_info.h` `MOVE_PURSUIT` (L6223): `.effect = EFFECT_PURSUIT`,
  `.power = 40`, `.type = TYPE_DARK`, `.accuracy = 100`, `.pp = 20`, `.category =
  DAMAGE_CATEGORY_PHYSICAL`, `.makesContact = TRUE`.
- Power doubling — Source: `src/battle_util.c` L6180-6182: `case EFFECT_PURSUIT: if
  (gBattleStruct->battlerState[battlerDef].pursuitTarget) basePower *= 2;`. Reused the
  existing M16b `power_override` plumbing (`DamageCalculator.calculate`'s `power_override`
  param) rather than adding a new mechanism — same pattern as Rollout/Magnitude.
- Turn-order interception — Source: `src/battle_script_commands.c` ::
  `Cmd_jumpifnopursuitswitchdmg` (L8494), `src/battle_util.c` :: `SetTargetToNextPursuiter`
  (L9827), `IsPursuitTargetSet` (L9850). Confirmed the exact detection mechanism: the source
  fires this check right as a switch action is about to resolve, scanning LATER-in-turn-order
  battlers for a queued Pursuit move (`gChosenActionByBattler[battler] == B_ACTION_USE_MOVE
  && GetMoveEffect(...) == EFFECT_PURSUIT`) — it requires the target to have specifically
  chosen a SWITCH action (not just any move), confirmed via `gCurrentTurnActionNumber`-based
  lookahead into `gChosenActionByBattler`. `B_PURSUIT_TARGET >= GEN_4` (GEN_LATEST,
  `include/config/battle.h`) means ANY opposing Pursuit user intercepts, not only one that
  specifically targeted the switcher.
- This project's existing turn order (`_phase_priority_resolution`'s `_turn_order.sort_custom`)
  already sorts ALL switch actions before ALL move actions unconditionally (established in
  M9, reaffirmed in M16d's Trick Room work) — meaning Pursuit's "hit before the switch"
  behavior could NOT be modeled as a pure damage multiplier the way the task anticipated; it
  genuinely requires overriding the switches-always-first rule for the specific
  pursuer/switcher pair. Added two branches to the top of the comparator (before the existing
  switch-priority check) plus a new `_pursuit_targets_switcher(pursuer_idx, switcher_idx)`
  helper. Confirmed the power-doubling check (`_chosen_switch_slots[defender_idx] >= 0` at
  the moment Pursuit's damage is computed) stays valid because `_chosen_switch_slots` for the
  switcher is only cleared when THEIR OWN switch action executes — which, with the reordering,
  happens strictly after the intercepting Pursuit user's action.
- Deliberate simplification (documented, not fixed): source supports CHAINING multiple
  pursuers against the same switcher one at a time via `MoveEndPursuitNextAction`
  (`battle_move_resolution.c` L4321), re-evaluating `IsBattlerAlive` between each. This
  project instead lets every intercepting Pursuit user act (in normal speed order) before the
  switch resolves — identical outcome for the common 1-pursuer case; only diverges in the
  rare multi-pursuer doubles case (out of scope; no test coverage claims accuracy there).
- Verified: `m16e_test` S2.01–S2.07 — normal power matches the calculator's unmodified
  result; doubled power (when the target chose to switch) exactly matches
  `DamageCalculator.calculate(..., power_override=80)`, and is strictly greater than the
  normal case; the damage lands on the ORIGINAL outgoing Pokémon (not the incoming
  replacement, which is still at full HP at that exact moment); the queued switch still
  completes afterward if the target survives.
- 2026-07-02.

### Pain Split — current-HP averaging (not max HP)
- Source: `src/battle_script_commands.c` :: `Cmd_painsplitdmgcalc` (L7989-8006):
  `hpDiff = (gBattleMons[gBattlerAttacker].hp + GetNonDynamaxHP(gBattlerTarget)) / 2` — plain
  C integer division (floor for positive operands), confirmed CURRENT HP on both sides, not
  max HP.
- Rounding: floor, confirmed via `m16e_test` S3.05 with an odd sum (101+100 -> 100, not
  101 or a fractional value).
- Both directions verified independently (S3.01-3.04): user-higher-HP heals the target and
  damages the user down to the average; target-higher-HP is the mirror image. Both mons
  converge on the exact floored average in both cases.
- Cannot faint either side: `floor((a+b)/2) >= 1` whenever both operands are `>= 1` (and
  neither combatant can have `current_hp <= 0` while still eligible to act), so the "damage"
  branch of `PassiveDataHpUpdate` (`src/battle_script_commands.c` L1547-1562, the non-heal
  path) can never actually reduce a Pokémon to 0 via this move. Not explicitly asserted as a
  separate test (would require contriving a fractional-HP edge case that can't occur given
  integer HP), but relied upon by the implementation (`min(max_hp, hp_diff)` — see below).
- Blocked by the target's Substitute: Pain Split has no `ignoresSubstitute` flag in source
  (unlike Conversion 2 / Psych Up below), so the existing substitute-block pattern (mirroring
  Encore's inline check) applies. Verified `m16e_test` S3.07-3.08.
- Implementation note: `final_hp = min(own_max_hp, hp_diff)` reproduces source's
  `PassiveDataHpUpdate` in one line — the negative-delta (heal) branch clamps to maxHP; the
  positive-delta (damage) branch never needs clamping since `hp_diff < current_hp` implies
  `hp_diff < max_hp` already. Verified equivalent by construction, not just by testing.
- Pain Split (220): Normal/Status, accuracy=0, pp=20, power=0 (status category).
- 2026-07-02.

### Conversion — type <- literal first move slot
- Source: `src/battle_script_commands.c` :: `Cmd_tryconversiontypechange` (L7449-7482),
  `B_UPDATED_CONVERSION >= GEN_6` branch (GEN_LATEST, `include/config/battle.h` L72): scans
  `moves[0..3]` for the first entry that isn't `MOVE_NONE` and uses THAT move's type — no
  special-casing of Curse/Struggle/status-vs-damaging, confirmed by reading the loop directly
  (it breaks on the first non-empty slot, full stop). Verified via `m16e_test` S4.06-4.07: a
  status move (Growl, NORMAL) in slot 0 wins over a damaging move (Ember, FIRE) in slot 1.
- Fails if the user is already that type — `IS_BATTLER_OF_TYPE(gBattlerAttacker, moveType)`
  checked against the user's CURRENT types (both, if dual-typed) before the change, matching
  the task's question directly: yes, it can fail this way, and the check is against the full
  current typing, not just a single "primary type" slot.
- On success, `SET_BATTLER_TYPE` (`include/battle.h` L797) makes the user MONO-typed — a
  genuine replacement of both type slots, not "add a type." This project represents mono-type
  as `[type, TYPE_NONE]` (the existing `PokemonSpecies.types` convention, confirmed via
  `get_effectiveness`'s `TYPE_NONE` skip) rather than source's literal both-slots-equal
  representation — functionally equivalent, verified via existing type-effectiveness code
  paths rather than re-deriving them.
- Implementation gotcha: an `Array[int]` typed-property is NOT safely reassignable via
  `Array[int]([a, b])` constructor syntax in this GDScript 4.3 build in this position — it
  parses but throws `Cannot call on an expression` at load time. Added a small
  `_set_mon_type(mon, new_type)` helper using resize + index assignment instead, matching the
  established typed-Array-assignment safe pattern from M9 (`_baton_pass_apply`).
- Conversion (160): Normal/Status, accuracy=0, pp=30, ignores_protect=true.
- 2026-07-02.

### Conversion 2 — resist type <- the TARGET's last used move (not "last hit by")
- Source: `include/config/battle.h` L73 — `B_UPDATED_CONVERSION_2 = GEN_LATEST` (>= GEN_5):
  "changes the user's type to a type that resists the **last move used by the selected
  target**. Before, it would consider the last move being successfully hit by." This directly
  contradicts the task prompt's own example phrasing ("resists the type of the move that last
  hit them") — that description is the PRE-Gen5 legacy behavior, not what GEN_LATEST config
  implements. Confirmed by reading `Cmd_settypetorandomresistance`
  (`src/battle_script_commands.c` L8009-8077) directly rather than trusting the task's
  framing: the GEN_LATEST branch reads `gLastResultingMoves[gBattlerTarget]` /
  `gLastUsedMoveType[gBattlerTarget]` — the move's own TARGET_SELECTED target (an opponent in
  1v1; could in principle be an ally in doubles), not a "last hit the user" tracker.
- Reused this project's existing `last_move_used` field directly (per the task's explicit
  instruction to check for reusable "last move" infrastructure before adding a new tracker —
  Mirror Coat/Counter's `last_physical_damage`/`last_special_damage` trackers were the wrong
  fit since those are damage-received trackers, not move-identity trackers; `last_move_used`
  — already used by Disable/Encore — was the correct match).
- Fails if the target has no `last_move_used` yet, or that move's type is
  None/Mystery/Stellar. Verified `m16e_test` S5.03-5.04 (very first action of the battle, no
  prior move to reference).
- Selection among multiple valid resisting types is UNIFORM RANDOM, not "first found" —
  source rejection-samples `Random() % NUMBER_OF_MON_TYPES`, discarding both non-resisting
  types and types the user already has, until a valid pick is found or the candidate set is
  exhausted. Modeled the equivalent (and simpler) way: build the exclusion-filtered candidate
  list up front, then pick uniformly from it — same distribution, confirmed by construction.
  New `_force_conversion2_pick` test seam (index into the candidate list, sorted ascending by
  `TypeChart.TYPE_*` id) mirrors the existing `_force_magnitude_power`/`_force_roar_rng`
  null-sentinel convention. Verified the exclusion happens BEFORE indexing, not after:
  `m16e_test` S5.05-5.06 forces index 0 with the user already holding the would-be index-0
  candidate, and confirms the NEXT candidate is chosen instead.
- Discriminating test (S5.07-5.08): the target's last move was Growl (NORMAL, status,
  0 power) — dealt no damage to the user at all. Conversion 2 still succeeds and resists
  NORMAL, proving the implementation is genuinely "target's last used move," not "last move
  that hit the user" (which a 0-damage status move could never have satisfied).
- Ignores Protect and Substitute — both explicit flags in source
  (`.ignoresProtect = TRUE`, `.ignoresSubstitute = B_UPDATED_MOVE_FLAGS >= GEN_5` = GEN_LATEST
  = true) — set directly on the move data; no extra code needed since Protect-blocking and
  Substitute-blocking are both keyed off `move.ignores_protect`/`move.ignores_substitute` in
  the existing pipeline.
- Conversion 2 (176): Normal/Status, accuracy=0, pp=30, ignores_protect=true,
  ignores_substitute=true.
- 2026-07-02.

### Psych Up — copies stat stages AND the Focus Energy crit-boost volatile
- Source: `src/battle_script_commands.c` :: `Cmd_copyfoestats` (L8555-8575): copies all
  `NUM_BATTLE_STATS` (7) `statStages` unconditionally (full overwrite, not additive), THEN —
  gated on `GetConfig(B_PSYCH_UP_CRIT_RATIO) >= GEN_6` (`include/config/battle.h` L97 =
  GEN_LATEST) — ALSO copies `volatiles.focusEnergy` (plus `dragonCheer`/`bonusCritStages`,
  neither implemented in this project). Directly answers the task's explicit question: this
  is NOT strictly-the-7-numeric-stages; confirmed from source rather than assumed, and the
  Focus Energy copy is real GEN_LATEST behavior, not a legacy/pre-Gen6 footnote.
- Verified `m16e_test` S6.01-6.02 (full 7-stage copy including negative stages) and S6.04
  (overwrite semantics specifically — target has `focus_energy=false`, user starts `true`,
  ends `false`, ruling out an accidental boolean-OR implementation).
- Always hits (`accuracy=0`, already covered by the existing generic accuracy-check step
  that runs before status-move dispatch); ignores Protect and Substitute (both explicit flags
  in source) — same no-extra-code pattern as Conversion 2.
- Psych Up (244): Normal/Status, accuracy=0, pp=10, ignores_protect=true,
  ignores_substitute=true.
- 2026-07-02.

### Baton Pass — added the missing `focus_energy` passable
- Read the full existing M9 Baton Pass implementation before touching it, per the task's
  explicit instruction (`_baton_pass_save`/`_baton_pass_apply` in `battle_manager.gd`,
  and the M9 decisions.md entry "Baton Pass — exact passable fields"). Found that M9 already
  correctly implements the FULL passable set for every volatile that existed AT M9's time
  (`stat_stages`, `confusion_turns`, `substitute_hp`) — the task's framing ("this milestone
  extends it to actually pass stat stages and volatile statuses," implying nothing passed
  yet) did not match the current code; M9 was already fully correct for its era.
- The actual gap: `include/constants/battle.h`'s `VOLATILE_DEFINITIONS` macro (L209-266)
  marks `VOLATILE_FOCUS_ENERGY` as `V_BATON_PASSABLE` (L236) — but Focus Energy wasn't
  implemented in this project until M16a, seven milestones after M9's Baton Pass work, so it
  was never added to the passable set. Fixed by adding `focus_energy` to both
  `_baton_pass_save` and `_baton_pass_apply`, following the exact same shape as the existing
  three fields.
- Cross-checked EVERY OTHER volatile currently implemented in this project against the
  `VOLATILE_DEFINITIONS` table to confirm nothing else was missing: `minimized`,
  `defense_curled`, `destiny_bond`, `disabled_move`/`disable_turns`, `encored_move`/
  `encore_turns`, `protect_active`/`protect_consecutive`, `rollout_turns`,
  `choice_locked_move` — **none** of these appear in `V_BATON_PASSABLE`, so their absence
  from the passable set is correct, not an oversight. Verified the negative case explicitly
  (`m16e_test` S7.02): `minimized` does NOT baton pass.
- Confirmed `confusion_turns` genuinely DOES baton-pass in this specific source
  (`VOLATILE_CONFUSION` IS `V_BATON_PASSABLE`, L210) — this contradicts the task prompt's own
  example ("confusion typically does NOT pass"), but the task's instruction is to follow
  THIS repo's source, and M9 already implemented and tested this correctly (see M9's
  decisions.md entry) — not re-litigated or changed here, just confirmed still correct and
  noted explicitly since the task prompt's assumption pointed the other way.
- Confirmed this doesn't need to interact with the M16d switch-in hazard/ability pipeline in
  any new way: Baton Pass's own switch-in call site (`_apply_switch_in_hazards` then
  `AbilityManager.try_switch_in`, wired during M16d) already fires AFTER
  `_baton_pass_apply(incoming, saved)` in `_phase_move_execution` — passed-in volatiles are
  already in place on the incoming Pokémon before hazards/abilities evaluate it, matching
  source's `SwitchInClearSetData` (restores passables) running before
  `AbilityBattleEffects(ABILITYEFFECT_ON_SWITCHIN, ...)` and hazard application in the
  turn-order script. No code change needed here beyond the `focus_energy` field addition
  itself.
- Verified `m16e_test` S7.01 (focus_energy passes) and S7.02 (minimized still correctly
  doesn't).
- 2026-07-02.

### Testing
- `m16e_test.gd`/`.tscn`: 53 assertions covering move-data spot checks (all 5 new moves plus
  Baton Pass's pre-existing field), Pursuit (normal vs. doubled power via direct
  `DamageCalculator.calculate` comparison, turn-order interception hitting the original
  switcher rather than the replacement, the switch still completing afterward), Pain Split
  (both HP-averaging directions, floor rounding on an odd sum, Substitute block), Conversion
  (type from literal first move slot including a status-move slot 0, already-that-type
  failure), Conversion 2 (resist-type selection forced deterministic via
  `_force_conversion2_pick`, no-last-move failure, exclusion-before-indexing, and the
  discriminating "target's last move was a non-damaging status move" case), Psych Up (full
  7-stage copy including negatives, focus_energy copy, overwrite-not-OR semantics), and Baton
  Pass's `focus_energy` extension plus a `minimized`-still-excluded regression check.
- Hit the CLAUDE.md-documented "snapshot via signals" pitfall TWICE more during this
  milestone's own test development, despite writing the convention down first — both fixed
  before being reported as passing:
  1. The Pursuit replacement-damage check (`bench2.current_hp == bench2.max_hp`) originally
     read `bench2`'s HP after `start_battle()` fully returned; since both mons survive turn 1,
     the battle continues and `bench2` legitimately takes normal-power Pursuit damage on a
     LATER turn once it's the active target — fixed by snapshotting `bench2.current_hp`
     inside the same guarded `move_executed` callback that captures the Pursuit damage itself.
  2. The Conversion 2 "fails with no last move" test originally checked
     `changed2.is_empty()` after the full battle; since the user's only move is Conversion 2
     and the opponent's Tackle establishes `last_move_used` after turn 1, a LATER Conversion 2
     attempt legitimately succeeds — fixed by capturing a single combined
     "first event of either kind" array instead of two independently-accumulating arrays, so
     the assertion is unambiguously about the very first attempt only. Applied the same
     combined-first-event pattern to the Pain Split Substitute-block test pre-emptively
     before it could fail the same way (both mons there also only have one move each).
  3. Separately (not a signals-vs-post-battle issue, a plain test-setup bug): the Pain Split
     Substitute-block test initially set the target's `current_hp` below Substitute's own
     HP cost (`maxHP / 4`), causing Substitute itself to fail on turn 1 for an unrelated
     reason and confounding the result. A reminder that "keep every unrelated mechanic in a
     test at full HP unless the test is specifically about that mechanic" is worth defaulting
     to, not just the signals-vs-post-battle discipline.
- All tests use `_force_hit`/`_force_roll`/`_force_crit`/`_force_conversion2_pick` for
  determinism — no unforced RNG drives any assertion.
- Full regression: all prior suites (`battle_test` through `m16d_test`, plus `pp_test`,
  `two_turn_test`, `integration_test`) still pass with 0 failures. Total assertions across
  all numbered suites: 1043 prior + 53 new = 1096.
- 2026-07-02.

---

## [M16] Milestone complete — Tiers A through E, consolidated summary

All five M16 sub-milestones are now complete. Per-tier assertion counts (each suite's own
total, including that suite's move-data spot checks):

| Tier | Moves/mechanics | Suite | Assertions |
|------|------------------|-------|------------|
| M16a | RESTORE_HP (Recover/Slack Off/Heal Order), FOCUS_ENERGY, GROWTH, OHKO (Guillotine/Horn Drill/Fissure/Sheer Cold) | `m16a_test` | 52 |
| M16b | MINIMIZE, DEFENSE_CURL, Stomp `minimizeDoubleDamage`, ROLLOUT (+ Ice Ball), MAGNITUDE | `m16b_test` | 55 |
| M16c | REFLECT, LIGHT_SCREEN, AURORA_VEIL, Brick Break screen-break | `m16c_test` | 60 |
| M16d | SPIKES, TOXIC_SPIKES, STEALTH_ROCK, RAPID_SPIN, TRICK_ROOM | `m16d_test` | 71 |
| M16e | PURSUIT, PAIN_SPLIT, CONVERSION, CONVERSION_2, PSYCH_UP, Baton Pass extension | `m16e_test` | 53 |

M16 total new assertions: 52+55+60+71+53 = **291**. Combined with the 805 assertions from
M1–M15 (the last pre-M16 total), the full regression suite now stands at **1096 assertions
across 19 numbered scenes**, all green.

New reusable patterns introduced across M16, for reference by future milestones:
- `power_override` (M16b) — pass a computed base power into `DamageCalculator.calculate`,
  bypassing `move.power`; reused as-is by Pursuit (M16e) with no changes needed.
- `_side_conditions[side]` (M16c, extended M16d) — per-side (not per-Pokémon, not
  per-battle) state: screens (turns-remaining ints) and hazards (layer counts / bool).
- Per-battle top-level fields (`weather`/`weather_duration` from M11, `trick_room_turns`
  from M16d) — for genuinely field-wide state, kept structurally distinct from
  `_side_conditions`.
- `AbilityManager.is_grounded()` (M16d) — general-purpose grounded check, reused by nothing
  yet in M16e but available for future hazard/Gravity-adjacent work.
- `_force_*` test seams with a `null` = real-RNG / non-null = pinned-value convention,
  extended in M16e with `_force_conversion2_pick` — established as the standard way to make
  any randomized selection deterministic for tests, going back to `_force_roar_rng` (M9).
- Turn-order interception (M16e) — the first mechanic to reorder specific actions within a
  turn based on cross-battler conditions (not just a global rule like Trick Room's speed
  inversion). If a future move needs similar "jump the queue" behavior, look at
  `_pursuit_targets_switcher` and the two branches at the top of
  `_phase_priority_resolution`'s comparator as the template.
- "Read the source's actual GEN_LATEST-config behavior, not the move's flavor text or a
  plausible-sounding assumption" bit twice in M16e alone (Conversion 2's target-vs-hit-by
  distinction, Baton Pass's confusion-passes contradiction) — the single most load-bearing
  habit across all of M16, worth carrying into every future milestone unchanged.
- 2026-07-02.

---

## [M16 Review] Milestone-end targeted audit — three risk areas

A review pass over M16 (Tiers A–E), not a new milestone — verifying three specific risk
areas that the M16a–M16e entries above already flagged or touched, rather than re-deriving
mechanics from scratch. Per-area verdicts, stated plainly first:

- **Area 1 (Baton Pass passable-volatiles completeness): no gap found, coverage added.**
- **Area 2 (Conversion 2 last-used vs. last-hit-by test coverage): no code gap — the
  implementation was already correct; the TEST coverage was incomplete, now fixed.**
- **Area 3 (Trick Room × Pursuit turn-order integrity): no gap found, coverage added.**

### Area 1 — Baton Pass passable-volatiles completeness

- Re-read `include/constants/battle.h` :: `VOLATILE_DEFINITIONS` in full (not just the
  `V_BATON_PASSABLE`-flagged subset previously cited) to build a complete cross-reference.
  The macro list is accurate as previously cited in M9's decisions.md entry — no changes
  since.
- `Cmd_copyfoestats` (Psych Up, M16e) additionally copies `dragonCheer` and
  `bonusCritStages`. Checked whether either exists anywhere in this codebase's
  `BattlePokemon`: **neither is implemented** (only referenced in comments as
  "unimplemented here" — `move_data.gd` L568/576, `battle_manager.gd` L1521). No gap,
  because there's nothing to pass. Also noted: `bonusCritStages` itself is NOT
  `V_BATON_PASSABLE` in source anyway (only `focusEnergy` and `dragonCheer` are, among the
  three fields `Cmd_copyfoestats` touches) — so even if it existed, it wouldn't belong in
  the Baton Pass passable set; Psych Up's copy of it is a separate, move-specific mechanic,
  unrelated to the general Baton Pass macro.
- Full audit table — every `BattlePokemon` field added M16a–M16e, cross-referenced against
  `V_BATON_PASSABLE` and against `_baton_pass_save`/`_baton_pass_apply`:

  | Field | Added | `V_BATON_PASSABLE` per source? | Currently passed? |
  |---|---|---|---|
  | `focus_energy` | M16a | YES (`VOLATILE_FOCUS_ENERGY`, L236) | YES (fixed in M16e) |
  | `minimized` | M16b | NO (`VOLATILE_MINIMIZE`, no flag) | NO — correct |
  | `defense_curled` | M16b | NO (`VOLATILE_DEFENSE_CURL`, no flag) | NO — correct |
  | `rollout_turns` / `rollout_base_power` | M16b | N/A — no dedicated Rollout volatile carries the flag (closest analogues `VOLATILE_MULTIPLETURNS`/`VOLATILE_CHARGE_TIMER` also have no flag) | NO — correct |
  | `_side_conditions` (screens M16c, hazards M16d) | M16c/d | N/A — side-wide (`gSideStatuses`/`gSideTimers`), not a battler volatile at all; untouched by `SwitchInClearSetData` regardless of Baton Pass | N/A — correctly out of scope |
  | `trick_room_turns` | M16d | N/A — field-wide (`gFieldStatuses`), not a battler volatile | N/A — correctly out of scope |
  | `species.types` override (Conversion / Conversion 2) | M16e | N/A — not part of `VOLATILE_DEFINITIONS` at all (type is a direct `gBattleMons[].types` field, not a volatile bitfield) | See flagged issue below — not a Baton Pass gap specifically |

  Conclusion: `focus_energy` (already fixed in M16e) was the only implemented+passable
  volatile that was missing. Every other M16a–M16e field is correctly excluded, matching
  source exactly.
- **Flagged (not fixed, out of scope for this review — a different bug class from what Area
  1 asked about):** `_set_mon_type()` (M16e, `battle_manager.gd`) mutates
  `attacker.species.types` directly and **nothing anywhere resets it** — not
  `_clear_volatiles`, not `_switch_out_clear`, not on faint. In source, `gBattleMons[battler]`
  is a battler-indexed struct that gets fully repopulated from the incoming Pokémon's party
  data on every switch, so a Conversion-induced type change is implicitly discarded the
  moment that battler slot is repopulated — it isn't part of the persistent per-Pokémon
  state at all. In this project's architecture (one long-lived `BattlePokemon` object per
  party member, not a repopulated-per-slot struct), the type mutation instead sticks to that
  specific `BattlePokemon` object permanently, surviving even an ordinary voluntary
  switch-out and switch-back-in later in the same battle — which is NOT what source does.
  This is a real latent bug, but it's a "does any switch clear a Conversion type-change"
  question, not a "Baton Pass passable volatiles" question (Baton Pass correctly doesn't
  pass it either way, since it's not `V_BATON_PASSABLE`). Recommend a small follow-up task:
  reset `species.types` to the original species types in `_clear_volatiles` (or a new
  narrower helper), sourced from `RESTORE_BATTLER_TYPE` (`include/battle.h` L802-806).
- Regression coverage added (`m16e_test.gd` S7.02–S7.04): confirmed `minimized`,
  `defense_curled`, and `rollout_turns` all still correctly do NOT survive a Baton Pass, in
  the same battle, alongside the existing `focus_energy`-passes check (S7.01).
- 2026-07-02.

### Area 2 — Conversion 2's resistance-selection test coverage

- Read the existing Conversion 2 assertions (`m16e_test.gd` S5.01–S5.08 at review time).
  S5.07/S5.08 already proved the target's last move counts even when it dealt zero damage
  (Growl) — a necessary check, but not a full discriminator: it only rules out "requires a
  hit to count at all," not "falls back to a PRIOR hit's type when one exists and differs
  from the last-used move's type."
- Added a direct-conflict test (S5.09/S5.10): the target's move that actually HIT the user
  (Water Gun, WATER, turn 1) and the target's LATER last-used move (Growl, NORMAL, turn 2,
  no damage) resist to genuinely different pool-index-0 candidates (WATER id 12 vs. ROCK
  id 6 respectively) — not a coincidental match, deliberately chosen so a "last hit by"
  implementation and the correct "last used" implementation would produce visibly different
  results. Confirmed the result is ROCK (last-used/Growl), not WATER (last-hit/Water Gun).
- **This WAS a testing gap** (no existing assertion could have caught a hypothetical
  last-hit-by regression), but investigating the implementation
  (`_phase_move_execution`'s `move.is_conversion2` block, `battle_manager.gd`) confirmed
  there is no "last hit by" code path in this project at all for Conversion 2 — it reads
  `defender.last_move_used` directly and unconditionally, the same field Disable/Encore
  already use. There was no way for the old test suite to have been "accidentally passing
  despite a bug," because the only implemented code path is already correct by construction.
  Verdict: implementation was already correct; only the test coverage needed closing.
- Caught and fixed a real bug in the NEW test itself while writing it (documented here since
  it's exactly the CLAUDE.md-documented pitfall recurring yet again, this time during a
  review pass rather than a milestone): the first draft queued 3 turns for the user
  (tackle, tackle, conversion2) against only 2 queued turns for a FASTER opponent
  (water_gun, growl). By the user's 3rd turn, the opponent's queue had drained and
  auto-select re-used Water Gun (`moves[0]`) BEFORE the user's Conversion 2 executed that
  same turn — silently re-overwriting `last_move_used` back to Water Gun and defeating the
  discriminator (observed result: type_changed fired with WATER, looking exactly like a
  real bug, until traced to the test's own turn-timing). Fixed by trimming the user's queue
  to 2 turns so Conversion 2 lands immediately after Growl within the same turn the
  opponent's queue provides it, before any auto-select fallback can re-fire.
- 2026-07-02.

### Area 3 — Turn-order integrity: Trick Room × Pursuit interaction

- Read `_phase_priority_resolution`'s `sort_custom` comparator and `_pursuit_targets_switcher`
  side by side. `_pursuit_targets_switcher(pursuer_idx, switcher_idx)` consults only
  `_chosen_moves[pursuer_idx].is_pursuit`, `_chosen_switch_slots[switcher_idx]`, and side
  membership — it never reads `StatusManager.effective_speed`, `trick_room_turns`, or
  anything order-dependent. The two new interception branches sit at the TOP of the
  comparator, before the priority/speed/Trick-Room comparison block, and `return`
  immediately for any pair where exactly one side is switching and the other has Pursuit
  queued against it — meaning Trick Room's speed-inversion code is never even reached for
  that specific pair. For every OTHER pair (no switch involved, or both/neither switching),
  the two new branches are unconditionally false and control falls through to the
  pre-existing, unmodified priority/speed/Trick-Room logic. The two mechanisms are
  structurally disjoint by construction — there is no shared state or code path where one
  could corrupt the other.
- Traced source's equivalent: `SetTargetToNextPursuiter` (`battle_util.c` L9827) scans
  `gBattlerByTurnOrder[i]` for `i` from `gCurrentTurnActionNumber + 1` onward — this array is
  the ALREADY-RESOLVED turn order (computed once via `GetWhichBattlerFasterArgs`-based
  sorting earlier in the turn, which is where Trick Room's inversion actually happens).
  Pursuit's interception is a second, independent reordering pass layered on top of
  whatever the Trick-Room-aware base order already was — source doesn't special-case
  Trick Room inside the Pursuit-interception logic at all, because by the time it runs,
  Trick Room's effect is already baked into the order it's operating on. This project's
  single-pass comparator (interception branches short-circuiting before the Trick-Room-aware
  speed comparison) produces the same observable outcome via a different mechanism —
  verified equivalent by construction, not just by testing.
- New `scenes/battle/m16_review_test.gd`/`.tscn` (8 assertions, singles only):
  - S1.01–S1.02: under Trick Room, a Pursuit user SLOWER than its target still intercepts
    the switch (damage lands on the original switcher; the replacement is undamaged at that
    exact snapshot moment).
  - S1.03–S1.04: mirror case, a Pursuit user FASTER than its target — same result, proving
    the interception decision is genuinely speed-independent in both directions.
  - S1.05–S1.06: doubled power still exactly matches the calculator's `power_override=80`
    result under Trick Room, and the queued switch still completes afterward.
  - S2.01–S2.02: Trick Room's ordinary speed-reversal is UNCHANGED for a Pursuit-carrying
    Pokémon when its target ISN'T switching this turn (a slower Pursuit user still acts
    first under Trick Room, exactly like any other slower Pokémon, with a without-Trick-Room
    control case confirming the effect is really Trick Room's doing) — proving the
    interception branches don't leak into or suppress ordinary Trick-Room-governed
    comparisons when no switch is involved.
- **Explicitly flagged, not tested (per the task's own scope guard):** doubles ×
  Trick Room × Pursuit (a third or fourth combatant's ordering, multiple simultaneous
  switchers/pursuers) is untested — both the M16d Trick Room suite and the M16e Pursuit
  suite are singles-only, and this review didn't expand into doubles. If a future task needs
  this combination verified, start from `m16_review_test.gd`'s Section 1 as the template and
  extend to `start_battle_doubles`.
- 2026-07-02.

### Testing / Regression

- `m16e_test.gd`: 56/56 (was 53; +3 from Area 1's broadened S7 regression check and Area 2's
  S5.09/S5.10 discriminator).
- `m16_review_test.gd`/`.tscn` (new): 8/8.
- Full regression: all prior suites (`battle_test` through `m16e_test`) still pass with 0
  failures. Total assertions across all 21 numbered suites: 1096 prior + 3 (m16e additions)
  + 8 (m16_review_test) = **1107**.
- No production code changes resulted from this review — all three areas confirmed the
  existing M16 implementation correct; the only changes were test additions and one
  documented-but-deferred finding (the `species.types` switch-reset gap under Area 1).
- 2026-07-02.

---

## [Follow-up fixes] Chilan Berry, Heavy Duty Boots, Conversion type-reset-on-switch

Three independent, small, cited fixes — not a milestone. Each closes a gap explicitly
flagged in an earlier decisions.md entry (M12's item gap I2, M16d's Stealth Rock section,
and the `[M16 Review]` Area 1 finding).

### Item 1 — Chilan Berry (Normal-type resist berry)

- Source: `src/battle_util.c` :: `GetDefenderItemsModifier` (L7506-7524): `ctx->moveType ==
  GetBattlerHoldEffectParam(...) && (ctx->moveType == TYPE_NORMAL || ctx->
  typeEffectivenessModifier >= UQ_4_12(2.0))`. The `TYPE_NORMAL` branch bypasses the
  effectiveness gate entirely — necessary because Normal-type moves can never reach 2.0×
  (no type in `gTypeEffectivenessTable` is 2×-weak to Normal), so without this branch Chilan
  Berry (`hold_effect=RESIST_BERRY`, `param=TYPE_NORMAL`) could never trigger.
- Fix: `item_manager.gd :: defender_item_modifier_uq412` — changed the effectiveness gate
  from `if effectiveness < 2.0: return 4096` to `if move.type != TypeChart.TYPE_NORMAL and
  effectiveness < 2.0: return 4096`, evaluated AFTER the param-match check (order doesn't
  matter functionally, kept for readability). No other resist-berry logic touched.
- No canonical item ID was needed in code — this project has no persisted `data/items/*.tres`
  convention for items despite M1's original stated intent (confirmed: `data/items/`
  doesn't exist; M12's held-item work always constructed `ItemData` inline via
  `ItemManager.HOLD_EFFECT_*` constants + explicit `hold_effect_param`, both in tests and in
  the only production code path that reads items). Chilan Berry reuses the existing
  `HOLD_EFFECT_RESIST_BERRY` constant (`item_manager.gd`, value 80) with
  `hold_effect_param = TypeChart.TYPE_NORMAL` — no new constant required.
- **Adjacent finding, not fixed (out of scope):** `data/items.json` (M15's data pipeline)
  has `hold_effect_param: 0` for EVERY resist berry (Chilan, Occa, Wacan, Babiri, etc. all
  checked) instead of their actual resisted type — a pre-existing pipeline gap, invisible
  until now because `PokemonRegistry`'s item dict isn't wired into any BattlePokemon
  construction path yet (party-building is future scope, per the Project Scope note). Not
  fixed here since it's a JSON-pipeline-wide issue, not specific to Chilan Berry.
- Canonical ID confirmed: `ITEM_CHILAN_BERRY = 549` (`include/constants/items.h` L679) —
  not currently referenced anywhere in this codebase's GDScript (no ID-keyed item lookup
  exists yet), recorded here for when that lookup is eventually built.
- Tested: `item_test.gd` I11.01-I11.06 — halves damage from a Normal move at neutral (1×)
  effectiveness, `defender_item_consumed` fires correctly, does NOT trigger for a non-Normal
  move even when super-effective (param-mismatch still gates correctly), and fires in a
  full battle integration test.
- 2026-07-02.

### Item 2 — Heavy Duty Boots (entry hazard immunity)

- Source: `IsBattlerAffectedByHazards` (`battle_util.c` L9209-9228) — the single shared gate
  checked at every `TryHazardsOnSwitchIn` call site (`battle_switch_in.c` L306-378): full
  immunity (not a damage reduction) whenever `holdEffect == HOLD_EFFECT_HEAVY_DUTY_BOOTS`,
  for Spikes, Toxic Spikes, and Stealth Rock alike.
- Exact per-hazard gating order matters and differs subtly:
  - **Spikes / Stealth Rock**: boots gate is unconditional — blocks regardless of type or
    grounded status (Stealth Rock already ignores grounded per M16d; boots adds a second,
    independent unconditional block).
  - **Toxic Spikes**: source checks grounded FIRST, then `IS_BATTLER_OF_TYPE(POISON)`
    (absorb) SECOND, and only reaches the boots gate in the else-if branch AFTER both —
    meaning a grounded Poison-type still ABSORBS/clears Toxic Spikes regardless of Heavy
    Duty Boots (the absorb check doesn't even look at held item). The boots only block the
    "would be poisoned" outcome for a grounded NON-Poison-type.
- Fix: new `ItemManager.HOLD_EFFECT_HEAVY_DUTY_BOOTS = 119` constant (position confirmed by
  counting `include/constants/hold_effects.h`'s enum — same technique used to verify every
  other `HOLD_EFFECT_*` constant already in this file, e.g. `RESIST_BERRY=80` and
  `UTILITY_UMBRELLA=115` both independently re-verified this way as a sanity check) and a
  new `ItemManager.is_hazard_immune(mon) -> bool` helper. Wired into
  `BattleManager._apply_switch_in_hazards` as ONE shared `hazard_immune` bool computed once
  at the top of the function (matching source's single shared gate), applied to: the Spikes
  branch's `and` condition; the Toxic Spikes branch's "would be poisoned" `elif` condition
  ONLY (NOT the Poison-type-absorb branch, which stays ungated per the ordering above); and
  the Stealth Rock branch's `and` condition.
- Canonical ID confirmed: `ITEM_HEAVY_DUTY_BOOTS = 510` (`include/constants/items.h` L637) —
  same "no persisted item-data-file" note as Item 1 applies; recorded for future reference.
- Tested: `item_test.gd` I12.01-I12.09 — holder takes no Spikes/Toxic-Spikes-poison/Stealth-
  Rock damage or status; a non-holder in an identical setup IS still affected (confirms the
  check doesn't accidentally suppress hazards globally); a grounded Poison-type holding the
  boots still absorbs Toxic Spikes (confirms the absorb-before-boots-gate ordering).
- 2026-07-02.

### Item 3 — Conversion / Conversion 2 type-reset-on-switch bug

- Corrects a misattribution from the `[M16 Review]` Area 1 entry: that entry cited
  `RESTORE_BATTLER_TYPE` (`include/battle.h` L797-806) as the switch-reset mechanism, but
  tracing every call site of that macro (`src/battle_util.c` L1731, inside
  `TryToRevertMimicryAndFlags`) shows it's ONLY invoked for the Mimicry ABILITY's
  terrain-based type reversion — unrelated to Conversion or general switching.
- Actual source mechanism, found by tracing where `gBattleMons[battler].types[0] =
  GetSpeciesType(...)` is set: `CopyMonAbilityAndTypesToBattleMon` (`battle_util.c`
  L9365-9379) and `Cmd_switchindataupdate` (`battle_script_commands.c` L5030-5032) — both
  fire at SWITCH-IN (not switch-out), repopulating `gBattleMons[battler].types` fresh from
  `GetSpeciesType()` every time a Pokémon enters the field. Source's `gBattleMons[]` is a
  battler-position-indexed struct that gets fully repopulated from party data on every
  switch, so a Conversion-induced type change is implicitly discarded the moment that
  battler slot is repopulated — it was never truly "reset on switch-OUT," it simply ceases
  to be the active data the instant a different (or the same) Pokémon's fresh data is loaded
  in on switch-IN.
- Design decision: this project's `BattlePokemon` objects are long-lived (one per party
  member for the whole battle, never repopulated-per-slot), so the source mechanism doesn't
  translate directly. Added a `BattlePokemon.original_types: Array[int]` cache, captured
  once in `from_species()` before any mutation can occur (`p_species.types.duplicate()`),
  and a new `BattleManager._reset_mon_type(mon)` that restores `species.types` from that
  cache. Confirmed before choosing this approach that `species` itself is never reassigned
  after construction (only `.types` is mutated in place by the existing `_set_mon_type`), so
  caching the ORIGINAL array once at construction time — rather than trying to re-derive
  "natural" types from `species` after it's already been mutated — was the only viable
  option; a same-species-shared-Resource concern was also checked and ruled out (every
  `BattlePokemon` gets its own fresh `PokemonSpecies` instance, confirmed via both the test
  harness's `_make_mon` helpers and the JSON-based `PokemonRegistry`, which returns plain
  dicts rather than cached `Resource` objects).
- Call sites: wired `_reset_mon_type` into the same 5 switch-IN call sites M16d's hazards
  were wired into (`_phase_battle_start`, the inline Baton Pass switch-in block,
  `_do_voluntary_switch`, `_do_forced_switch_in`, `_do_switch_in`) — NOT into
  `_clear_volatiles`/`_switch_out_clear`, since the correct trigger per source is switch-IN,
  not switch-out. Also reordered each site so `_reset_mon_type` runs BEFORE the
  `pokemon_switched_in`/`baton_passed` signal emissions (previously the reset would have run
  after, meaning an observer snapshotting type from those signals would have seen the
  stale/mutated value) — a pure internal reordering with no behavioral change to hazards or
  abilities, which already ran after either ordering.
- No special handling needed for faint: a fainted Pokémon never re-enters the field, so
  there's no "restore type after faint" scenario — confirmed by construction, since
  `_reset_mon_type` is only called from switch-IN sites, never from the faint path.
- Tested: `m16e_test.gd` S8.01-S8.02 — Conversion changes the user's type; the user
  voluntarily switches out and back in later in the same battle; confirmed the type is back
  to the original species type, not the Conversion-mutated one.
- 2026-07-02.

### Testing / Regression

- `item_test.gd`: 77/77 (was 63; +14 across I11 Chilan Berry and I12 Heavy Duty Boots).
- `m16e_test.gd`: 58/58 (was 56; +2 from the new Section 8 type-reset test).
- Full regression: all other suites unchanged and still passing. Total assertions across
  all 22 numbered suites: 1107 prior + 14 + 2 = **1123**.
- No other code paths touched — each of the three fixes is independently scoped, as
  requested.
- 2026-07-02.

## [M17a] Tier A move effects — damage-pipeline modifiers, no new infrastructure

Scoping source: `docs/m17_recon.md` (the original recon pass, its Addendum Sections 7-12,
and the Signature-Ability Sweep Section 13). That report — not this entry — is where the
full ability roster, exclusion reasoning, and tier sequencing were derived; this entry
only records what M17a actually implemented and cites source per ability. Do not
re-derive the roster/exclusion reasoning here — read the recon doc.

### Step 0 — finalized ability list

Section 11's original M17a proposal named Shadow Shield/Prism Armor/Neuroforce/Full Metal
Body/Transistor/Dragon's Maw as "free" duplicate-code-path additions. Section 13 (written
after Section 11) found all six are legendary/mythical-exclusive in the actual
`pokeemerald_expansion` species data (Lunala, Necrozma ×2, Solgaleo, Regieleki, Regidrago)
and recommended excluding them — Rob accepted that recommendation, so this milestone
re-derived the list from scratch against the final exclusion set rather than trusting
Section 11's text. Final list, 32 abilities, canonical IDs re-verified against
`include/constants/abilities.h` directly (not trusted from the recon's tables):

Overgrow(65), Blaze(66), Torrent(67), Swarm(68), Marvel Scale(63), Compound Eyes(14),
Battle Armor(4), Shell Armor(75), Multiscale(136), Filter(111), Solid Rock(116), Tinted
Lens(110), Adaptability(91), Rock Head(69), Sniper(97), Toxic Boost(137), Sand Force(159),
No Guard(99), Guts(62), Hustle(55), Heatproof(85), Iron Barbs(160), Fur Coat(169), Tough
Claws(181), Steelworker(200), Steely Spirit(252), Battery(217), Power Spot(249), Rocky
Payload(276), Ice Scales(246), Defeatist(129), Flare Boost(138).

### Source-function reality check

The recon's shallow classification pass assumed most of these lived in the single
attacker-stat-modifier function (`GetAttackStatModifier`) the 12 M8 abilities already use.
Re-reading source for every ability before writing code found this project actually needs
**four** distinct hook points, not one:

1. **`GetAttackStatModifier`** (existing `AbilityManager.attack_modifier_uq412`,
   pre-formula ATK/SpA stat modifier): Overgrow/Blaze/Torrent/Swarm (L6821-6836, matching
   type + hp≤maxHP/3 → ×1.5, either category), Guts (L6868-6870, statused + physical →
   ×1.5), Hustle (L6860-6862, physical → ×1.5), Defeatist (L6812-6813, hp≤maxHP/2 → ×0.5),
   Rocky Payload (L6891-6893, Rock-type → ×1.5, unconditional).
2. **`GetDefenseStatModifier`** (usesDefStat-gated = physical-only, L7089-7104) and
   **`GetDefenderAbilitiesModifier`** (post-type-effectiveness, L7407-7444) and the
   base-power function's "target's abilities" block (L6607-6611) — three genuinely
   different source functions this project folds into ONE extended
   `defense_damage_modifier_uq412(defender, move, effectiveness)` (new `effectiveness`
   parameter added), matching the simplification precedent M8 already established for
   Thick Fat (a pre-formula stat modifier in source, applied here as a post-type-
   effectiveness final-damage multiplier): Marvel Scale (statused+physical → stat ×1.5,
   translated to the RECIPROCAL damage multiplier ≈0.667/2731, not 1.5/6144 — a bug
   caught by the test suite, see Bugs below), Fur Coat (physical → stat ×2.0 → damage
   ×0.5), Multiscale (max HP → ×0.5), Filter/Solid Rock (effectiveness≥2.0 → ×0.75),
   Ice Scales (special → ×0.5), Heatproof (Fire-type → ×0.5).
3. **`GetAttackerAbilitiesModifier`** (post-type-effectiveness, attacker-side,
   L7378-7397): new `AbilityManager.attacker_post_effectiveness_modifier_uq412` —
   Sniper (crit → ×1.5), Tinted Lens (effectiveness≤0.5 → ×2.0). (Neuroforce, the third
   case in this same source switch, is excluded per Section 13.)
4. **`CalcMoveBasePowerAfterModifiers`** (base-power modifier, same pipeline stage as
   M14b's Helping Hand, L6375-6656): new `AbilityManager.move_power_modifier_uq412` —
   Toxic Boost (L6469-6471, poisoned+physical → ×1.5), Flare Boost (L6465-6467,
   burned+special → ×1.5), Sand Force (L6486-6490, {Steel,Rock,Ground}+sandstorm →
   ×1.3), Tough Claws (L6510-6512, contact → ×1.3), Steelworker (L6526-6528, Steel-type
   → ×1.5), Steely Spirit self (L6558-6560, Steel-type → ×1.5) AND ally (L6595-6597,
   same condition, checked independently — see doubles infra below), Battery
   (L6588-6591, ally + special move → ×1.3, ally-only), Power Spot (L6592-6593, ally,
   unconditional → ×1.3, ally-only).

Plus four hooks outside the damage-calc pipeline entirely: Battle Armor/Shell Armor (new
`AbilityManager.blocks_critical_hit`, forces `is_crit = false` even against a forced crit
— `CalcCritChanceStage` L7848-7859), Adaptability (direct edit to the STAB multiplier in
`DamageCalculator.calculate`, ×2.0 instead of ×1.5 — `GetSameTypeAttackBonusModifier`
L7244/L7247), Rock Head (new `AbilityManager.blocks_recoil`, gates the existing recoil
block in `BattleManager` — `battle_move_resolution.c` L3373-3396, does NOT affect
Struggle recoil or Life Orb recoil), No Guard (new
`AbilityManager.bypasses_accuracy_check`, early-return in `StatusManager.check_accuracy`
before even the semi-invulnerable gate — battle_util.c L10182-10193), Compound
Eyes/Hustle (new `AbilityManager.accuracy_modifier_percent`, folded into
`check_accuracy`'s existing integer-percentage math — `GetTotalAccuracy` L10283-10295),
and Guts' burn-halving exemption (added to the existing burn check in
`DamageCalculator.calculate` — `GetBurnOrFrostBiteModifier` L7285).

### New doubles infrastructure: `BattleManager._get_ally`

Battery/Power Spot/Steely Spirit's ally-aura boost needed to know the attacker's doubles
partner, which M14a-c never exposed as a helper (only `_get_first_opponent` existed).
Added `_get_ally(mon)` mirroring `_get_first_opponent`'s exact shape (reads the existing
`_combatants`/`_active_per_side` layout M14a already built) — this is NOT new
infrastructure in the Section 10/11 sense (no new state, no new subsystem), just a
missing convenience accessor over data that was already fully built. `DamageCalculator
.calculate()` gained a new `ally: BattlePokemon = null` trailing parameter (defaults to
null in the one existing singles-context call path that doesn't pass it — none do,
since the sole call site in `_do_damaging_hit` now always resolves and passes
`_get_ally(attacker)`).

### Bugs caught by the test suite before merging

- **Marvel Scale direction bug**: initially returned 6144 (×1.5), which INCREASES damage
  taken — backwards. Source raises the DEFENSE STAT by ×1.5 (a stat that's inversely
  proportional to damage in the formula); since this project's simplification applies a
  single post-hoc multiplier to final damage rather than the stat itself, the correct
  value is the RECIPROCAL, 1/1.5 ≈ 0.667 (UQ4.12 = 2731) — same reciprocal relationship
  Fur Coat already established (stat ×2.0 → damage ×0.5). Caught by
  `m17a_test.gd` S3.02 asserting reduced (not increased) damage taken.
- **GDScript lambda scalar-capture gotcha, recurring** (see `CLAUDE.md`'s gotchas list):
  the first draft of the Rock Head recoil test captured a plain `bool`/`int` local
  variable inside a `recoil_damage.connect(func(...): ...)` lambda and mutated it inside
  the lambda — GDScript captures outer scalars BY VALUE, so the outer variable never
  actually changed, silently producing a false pass on the positive-case assertion (Rock
  Head "correctly" showed no recoil, but only because the mechanism could never register
  ANY recoil, Rock Head or not) while the negative case (which needed the value to
  become nonzero) failed honestly and exposed the bug. Fixed with the established
  Array-wrapper pattern (`[false]`/`[0]`, mutate `[0]`).
- **Test-only bug, Flare Boost's physical negative case**: initially compared a burned
  Flare Boost holder's physical-move damage against a fully-plain (unburned, no ability)
  baseline and expected equality — but burn's own physical-damage-halving (a separate,
  pre-existing M3 mechanic, unrelated to Flare Boost) also applies to the burned
  attacker, so the two were never going to be equal regardless of Flare Boost's
  correctness. Fixed by comparing against a burned-but-ability-less baseline instead,
  isolating just Flare Boost's contribution.

### Testing / Regression

- New `m17a_test.gd`/`.tscn`: 83/83 assertions across 11 sections (ability data
  spot-checks; attack-stat-modifier additions; defense-modifier additions; crit
  interactions; Tinted Lens; Adaptability; Rock Head; No Guard; Compound Eyes/Hustle
  accuracy; move-power-modifier additions including the doubles-ally cases; Guts'
  burn exemption).
- `.tres` data: all 32 abilities added to `scripts/gen_abilities.py` (matching its
  existing description/ai_rating convention) and regenerated via the script — the
  previously name-only placeholder files for these 32 IDs now carry real descriptions,
  same as the original 12 M8 abilities.
- Full regression: all 22 prior suites unchanged and still passing. Total assertions
  across all 23 numbered suites: 1123 prior + 83 = **1206**.
- 2026-07-02.

## [M17b] Tier B move effects — stat-stage-system interactions, no new infrastructure

Scoping source: `docs/m17_recon.md` (Section 11's Bucket B proposal, cross-checked
against Section 13's Signature-Ability Sweep exclusions). As with `[M17a]`, this entry
records what M17b actually implemented and cites source per ability — it does not
re-derive the roster/exclusion reasoning, which lives in the recon doc.

### Step 0 — finalized ability list

Section 11's Bucket B proposal was re-derived against the final exclusion set rather
than trusted as-is. Two corrections were made to the task's own transcription of that
exclusion set during this cross-check:

- **Beast Boost excluded** — the task's given exclusion list omitted it (transcribed
  only 22 of Section 13's actual 23 findings). Beast Boost shares its source dispatch
  case with Moxie/Chilling Neigh/Grim Neigh/As One ×2 (`battle_util.c` L4467-4472) but
  is Ultra-Beast-exclusive (all 11 holders are UBs, zero non-UB holders) — excluded on
  the same legendary/mythical/UB-exclusive grounds as the rest of Section 13.
- **Moxie included** — the recon's shallow pass had flagged Moxie as "not currently
  hooked anywhere," but this project's `_last_attacker` dict (built for M14b's Destiny
  Bond) plus the `pokemon_fainted` signal already provide everything Moxie needs (killer
  lookup available before the faint signal fires in `_phase_faint_check`). Reusing
  existing infrastructure, not adding new — included despite the task description's own
  "expected shape" list omitting it.
- Chilling Neigh, Grim Neigh, As One (Ice Rider), As One (Shadow Rider) — removed per
  Section 13 (Glastrier/Spectrier/Calyrex-exclusive); no "free rider" carryover, per the
  task's own instruction.
- Intrepid Sword / Dauntless Shield — confirmed excluded (Zacian/Zamazenta-exclusive per
  Section 13), consistent with the task's expectation.
- **Guard Dog and Opportunist deferred** (not in this tier, matching the task's own
  expected-shape omission — verified via source why, not just left out silently):
  - Guard Dog is genuinely two-part: the Intimidate-reversal half is cheap, but the
    other half (forced-switch/Red-Card immunity) needs a new ability-check gate in the
    Roar/Whirlwind code path that doesn't exist yet (shared gap with the also-unimplemented
    Suction Cups). Implementing only the cheap half would misrepresent the ability.
  - Opportunist's "mirror the opponent's stat raise" mechanism is embedded directly in
    source's central stat-change-application function (`battle_stat_change.c`
    L431-447). A faithful port would require threading an opposing-side check through
    every one of `StatusManager.apply_stat_change`'s ~33 call sites — too broad for a
    "no new infrastructure" tier.

Final list, 32 abilities, canonical IDs re-verified against
`include/constants/abilities.h` directly:

Steadfast(80), Anger Point(83), Simple(86), Download(88), Clear Body(29), White
Smoke(73), Keen Eye(51), Hyper Cutter(52), Moxie(153), Unaware(109), Contrary(126),
Defiant(128), Weak Armor(133), Moody(141), Big Pecks(145), Justified(154), Rattled(155),
Flower Veil(166), Sweet Veil(175), Gooey(183), Stamina(192), Water Compaction(195),
Berserk(201), Tangling Hair(221), Competitive(172), Cotton Down(238), Steam Engine(243),
Pastel Veil(257), Thermal Exchange(270), Anger Shell(271), Purifying Salt(272),
Supersweet Syrup(306).

### The three stat-interaction shapes

Per the task brief and confirmed against source, this bucket contains three genuinely
different mechanisms, not one:

**(1) Magnitude modifiers** — transform the raw stage delta before it's applied, inside
`StatusManager.apply_stat_change` (the single central function every stat-raising/
lowering move/ability/item in this codebase already goes through).
Source: `battle_stat_change.c :: AdjustStatStage` (L797-815).
- **Simple** (86): stage ×2.
- **Contrary** (126): stage ×-1.
New: `AbilityManager.adjust_stat_stage_amount(target, amount)`.

**(2) Change-blocking gates** — checked BEFORE a (already magnitude-adjusted) NEGATIVE
change is applied, also inside `apply_stat_change`.
Source: `battle_stat_change.c :: CanAbilityPreventStatLoss` (L823-831, Clear
Body/White Smoke/Full Metal Body — the third excluded, Solgaleo-exclusive) and
`AbilityPreventsSpecificStatDrop` (L836-850, Hyper Cutter/Big Pecks/Keen Eye/Minds
Eye/Illuminate — the last two out of scope) and `IsFlowerVeilBlocked` /
`StatChange_IsFlowerVeilProtected` (L601-634, Flower Veil).
- **Clear Body** (29) / **White Smoke** (73): block ALL stat reductions on the holder.
- **Hyper Cutter** (52): blocks Attack reduction only.
- **Big Pecks** (145): blocks Defense reduction only.
- **Keen Eye** (51): blocks Accuracy reduction only (also reused for Unaware's evasion
  touch-point below).
- **Flower Veil** (166): blocks ALL reductions on a Grass-type battler if the battler
  itself OR its doubles ally holds Flower Veil.
New: `AbilityManager.blocks_stat_decrease(target, stat_idx, ally)`.

**(3) Reactive triggers** — fire a NEW stat change in response to a hit, switch-in, or
end-of-turn tick, hooking into EXISTING M8/M11/M14b/M16d infrastructure rather than the
stat-change pipeline itself. Each is detailed per-ability below.

Additionally, **Unaware** (109) doesn't fit any of the three shapes above — it's a
stage-*ignoring* mechanic touching 4 separate call sites (2 in `DamageCalculator
.calculate`, 2 in `StatusManager.check_accuracy`), matching source's own split across
`battle_util.c` L6785 (attacker ATK/SpA stage), L7072 (defender DEF/SpDef stage), L10251
(evasion stage, shared with Keen Eye), L10256 (attacker's own accuracy stage). New:
`ignores_defender_def_stage` / `ignores_attacker_atk_stage` (damage calc) and
`ignores_defender_evasion_stage` / `ignores_attacker_accuracy_stage` (accuracy calc).

### Reactive triggers, per ability

- **Defiant** (128) / **Competitive** (172) — `battle_script_commands.c ::
  BS_TryDefiantRattled` (L13885-13905) + `battle_util.c ::
  ShouldDefiantCompetitiveActivate` (L1149-1168): a landed Attack/other-stat decrease
  from an opponent triggers Atk+2 (Defiant) or SpA+2 (Competitive). New:
  `AbilityManager.defiant_competitive_stat(target)`. **Known simplification**: rather
  than changing `apply_stat_change`'s return type to a Dictionary (which would touch
  ~33 call sites), this is wired explicitly at the two places it matters in this
  project — the generic move-stat-change handler in `battle_manager.gd`, and
  Intimidate's branch inside `try_switch_in`. Other indirect opponent-caused decreases
  (e.g. Cotton Down lowering an attacker's Speed) don't check Defiant/Competitive on
  that attacker; documented as a deliberate scope limit, not an oversight.
- **Rattled** (155) — genuinely dual-trigger, confirmed from source rather than assumed:
  (a) `battle_util.c` L3790-3801, the "being Intimidated" half — wired inside
  `try_switch_in`, gated specifically on Intimidate actually lowering Attack (not a
  generic "any Attack decrease" reactor, since Growl also lowers Attack in this project
  and must not trigger Rattled); (b) `battle_util.c` L3790-3801 (hit half) — Dark/Bug/
  Ghost-type hit landing on the holder → Speed+1, in the new non-contact-gated
  `try_hit_reactive_effects`.
- **Weak Armor** (133) — `battle_util.c` L3826-3841: physical hit landing → Def-1,
  Spe+2 (`B_WEAK_ARMOR_SPEED >= GEN_7`, this project's config).
- **Justified** (154) — `battle_util.c` L3772-3783: Dark-type hit landing → Atk+1.
- **Anger Point** (83) — `battle_util.c` L3911-3920: critical hit received → Atk set to
  absolute max. Source requests a raw +12 delta in its 0-12 internal scale; this
  project's normalized -6..+6 `apply_stat_change` correctly clamps the result, so from a
  neutral starting stage the reported `actual` delta is **+6, not +12** — a test
  expectation bug (not an implementation bug) caught while writing `m17b_test.gd`
  (see Bugs below).
- **Gooey** (183) / **Tangling Hair** (221) — `battle_util.c` L3923-3958 (shared case
  block): unconditional attacker Speed-1 on CONTACT (confirmed via source's inline
  `CanBattlerAvoidContactEffects` check — these genuinely require contact, unlike the
  rest of this reactive group). Added to the EXISTING contact-gated
  `try_contact_effects` (M8's function), not the new non-contact-gated one.
- **Stamina** (192) — `battle_util.c` L3814-3825: any damaging hit landing → Def+1.
- **Water Compaction** (195) — `battle_util.c` L3802-3813: Water-type hit landing →
  Def+2.
- **Berserk** (201) — `battle_util.c` L3732-3742: HP crossing from >50% to <=50% on
  THIS hit specifically (not merely "currently <=50%") → SpA+1.
- **Anger Shell** (271) — `battle_util.c` L3743-3766: same >50%→<=50% crossing check →
  Def-1, SpDef-1, Atk+1, SpA+1, Spe+1 (five independent stat changes, each
  independently gated on not already at its limit).
- **Steam Engine** (243) — `battle_util.c` L4169-4179: Fire/Water-type hit landing →
  Speed set to absolute max via a flat +6 raw delta (source: `SetStatChange(battler,
  STAT_SPEED, 6)` — a flat addition, not a set-to-max instruction like Anger Point, but
  numerically identical from any non-maxed starting stage since +6 always saturates the
  -6..+6 range).
- **Thermal Exchange** (270) — `battle_util.c` L4222-4231: Fire-type hit landing →
  Atk+1. Thermal Exchange's OTHER half (curing the holder's own burn, mirroring Water
  Veil/Water Bubble) is NOT wired — no in-battle path in this project can inflict burn
  on a Thermal-Exchange holder in a way distinguishable from simply not being burned;
  flagged as a known simplification, not silently dropped.
- **Cotton Down** (238) — `battle_util.c` L4155-4165: any damaging hit landing → Speed-1
  on ALL OTHER live battlers (field-wide), not just the attacker. The new
  `try_hit_reactive_effects` can only see the attacker/defender pair, so it reports a
  bool flag; `BattleManager` applies Speed-1 to the attacker AND the attacker's doubles
  ally (via `_get_ally`), matching source's "every battler except the holder" loop.
- All eleven of Justified/Rattled(hit-half)/Water Compaction/Stamina/Weak
  Armor/Anger Point/Berserk/Anger Shell/Steam Engine/Thermal Exchange/Cotton Down live in
  the new **`AbilityManager.try_hit_reactive_effects`**, deliberately separate from the
  existing contact-gated `try_contact_effects`. This split corrects a real
  over-generalization in the M8-era comment on `try_contact_effects`, which claimed
  contact = `makes_contact` as a blanket rule — true only for M8's specific ability
  subset (Rough Skin/Static/Flame Body), not for the whole `ABILITYEFFECT_MOVE_END`
  dispatch. Source (`battle_move_resolution.c` L2696) calls
  `AbilityBattleEffects(ABILITYEFFECT_MOVE_END, ...)` after EVERY damaging hit
  regardless of contact; individual cases self-gate on contact only where the real
  ability needs it (Gooey/Tangling Hair do; the eleven above do not).
- **Steadfast** (80) — `battle_move_resolution.c :: CancelerFlinch` (L303-307):
  flinching → the flinched Pokémon's own Speed+1. Wired inside the flinch branch of
  `battle_manager.gd`'s pre-move-check handling (`check["flinched"]`), not inside
  `AbilityManager` at all, since it's a reaction to the flinch-cancel path M7 already
  built rather than a hit/switch-in/end-of-turn tick.
- **Download** (88) — `battle_util.c` L3151-3163 + `GetDownloadStat` (L10957-10979):
  switch-in, sums BOTH live opposing battlers' stage-adjusted Defense vs Sp. Defense
  (not a per-opponent loop like Intimidate/Rattled/Pastel Veil/Supersweet Syrup) and
  raises the holder's Attack or Sp. Atk by 1 (ties go to Sp. Atk). New standalone
  `AbilityManager.download_stat(pokemon, opponents)` plus a `_staged_stat` helper
  mirroring `DamageCalculator.STAGE_RATIOS`, since this shape doesn't fit the
  `try_switch_in` per-opponent loop.
- **Moody** (141) — `battle_util.c` L3613-3635 (end-of-turn, `AbilityBattleEffects
  (ABILITYEFFECT_ENDTURN, ...)`): raises one random not-already-maxed stat (from all 7,
  including Accuracy/Evasion per `B_MOODY_ACC_EVASION >= GEN_8`, this project's
  GEN_LATEST config) by +2, then lowers a DIFFERENT random not-already-minned stat by -1
  (excluding whichever stat was just raised). New `AbilityManager._apply_moody`, called
  from an extended `try_end_of_turn` (now returns a Dictionary carrying both Speed
  Boost's and Moody's changes — see Bugs below for a real implementation bug caught
  here).
- **Moxie** (153) — `battle_util.c` L4467-4472 (shared dispatch case with the
  UB/legendary-exclusive abilities excluded above): Attack+1 for the Pokémon that just
  KO'd the opponent. New `AbilityManager.moxie_boost(killer)`, wired in
  `_phase_faint_check` right after `pokemon_fainted.emit()`, reusing M14b's existing
  `_last_attacker` dict (built for Destiny Bond) rather than building any new
  kill-attribution tracking.
- **Sweet Veil** (175) — `battle_util.c` L5322-5327: immune to Sleep specifically, self
  OR doubles ally. First-ever ABILITY-based status immunity in
  `StatusManager.try_apply_status` (every prior check there was purely type-based).
- **Pastel Veil** (257) — two-part, both wired: (a) `battle_util.c` L5254-5259, immune
  to Poison/Toxic, self OR doubles ally, in `try_apply_status`; (b) `battle_util.c`
  L3073-3081, cures the holder's OWN pre-existing poison/toxic on switch-in, in
  `try_switch_in`.
- **Purifying Salt** (272) — two-part, both wired (per the task's own flag that this
  ability is two-part): (a) `battle_util.c` L5359-5361 (same shape as Comatose): immune
  to ALL non-volatile statuses, self only (no ally-wide check in source), in
  `try_apply_status`; (b) `battle_util.c :: CalcMoveBasePowerAfterModifiers`, "target's
  abilities" block (L6941-6947): Ghost-type damage taken ×0.5. The damage half is the
  same shape as Heatproof (a target-ability post-type-effectiveness multiplier, just
  Ghost- instead of Fire-typed), so it's kept in the existing M17a-era
  `defense_damage_modifier_uq412` rather than split into a new function — this is a
  stat/defense-adjacent mechanic bundled into a stat-stage-tier milestone because the
  status-immunity half belongs here; noted rather than silently placed.
- **Supersweet Syrup** (306) — `battle_util.c` L3324-3336: switch-in, lowers ONE
  opponent's Evasion by 1, but **ONE-TIME-ONLY per Pokémon for the whole battle** (per
  source's per-party-member `supersweetSyrup` flag), not per switch-in. New persistent
  `BattlePokemon.supersweet_syrup_used: bool` field, deliberately NOT cleared by
  `_clear_volatiles`/`_switch_out_clear` (those only clear per-switch state; this is
  battle-lifetime state). New `AbilityManager.try_switch_in_evasion`.

### Doubles-ally awareness

Flower Veil / Sweet Veil / Pastel Veil all needed ally-awareness for their ally-wide
protection. Reused the exact `ally: BattlePokemon = null` trailing-parameter pattern
M17a already established for Battery/Power Spot/Steely Spirit (`BattleManager
._get_ally(mon)`), threaded into `StatusManager.apply_stat_change` and
`StatusManager.try_apply_status` — no new infrastructure, same accessor M17a built.

### Bugs caught by the test suite before merging

- **Anger Point test-expectation bug**: test initially asserted `anger_point_change ==
  12`. Root cause: source's raw +12 delta is in its own 0-12 internal stage scale; this
  project's `apply_stat_change` correctly clamps to -6..+6, so the real reported delta
  from a neutral stage is +6. Fixed the test assertion, not the implementation.
- **Moody force-value validation bug — a REAL implementation bug**: the test forced
  `force_moody_raise` and `force_moody_lower` to the SAME stat, expecting the lowered
  stat to fall back to something else (since Moody can never lower the stat it just
  raised). The first-draft `_apply_moody` used forced test values directly without
  validating them against the `valid_to_raise`/`valid_to_lower` pools, meaning a forced
  value could bypass game-rule validity entirely (a bug that would also affect real,
  unforced random rolls if a stat were simultaneously eligible for both, which it never
  legitimately is — the test caught the validation gap itself, not just a test-seam
  quirk). Fixed by only honoring the forced value when it's actually `in` the
  corresponding valid pool, otherwise falling back to random selection from that pool.
- **Purifying Salt test bug**: the first-draft test used a Normal-type defender to
  measure Ghost-type damage halving, but Normal-types are outright TYPE-IMMUNE to
  Ghost-type moves (a pre-existing, unrelated type-chart rule), so the test measured 0
  damage regardless of Purifying Salt's correctness. Fixed by switching the defender to
  an ordinary non-immune type (Water) so the ×0.5 modifier could actually be observed.

### Breaking changes to existing signatures

`AbilityManager.try_switch_in` and `AbilityManager.try_end_of_turn` both changed return
type from `int` to `Dictionary`, since each needed to report multiple simultaneous
outputs that didn't exist before this tier (Intimidate + Rattled + Pastel Veil +
Defiant/Competitive for `try_switch_in`; Speed Boost + Moody-raise + Moody-lower for
`try_end_of_turn`). This required updating every call site, including the pre-existing
M8-era `ability_test.gd`, which had two statically-typed `var x: int =
AbilityManager.try_end_of_turn(...)` assignments (Speed Boost's own cap-check tests)
that no longer type-checked after the signature change — a real regression caught by
the mandatory full-suite sweep (a Godot GDScript Parse Error, not a silent behavior
change), fixed by keying into the new Dictionary's `"speed_boost_change"` entry at both
call sites. `ability_test.gd` has no direct call to `try_switch_in`, so it needed no
equivalent fix for that signature change.

### Testing / Regression

- New `m17b_test.gd`/`.tscn`: 109/109 assertions across 14 sections (ability data
  spot-checks; Simple/Contrary; Unaware's 4 touch-points; change-blocking abilities;
  Defiant/Competitive incl. full-battle Growl integration; non-contact hit-reactive
  abilities incl. full-battle Cotton Down integration; contact-reactive Gooey/Tangling
  Hair incl. composition with Clear Body on the attacker; Steadfast full-battle flinch
  integration; Download; Moody; Moxie incl. full-battle KO integration; status
  immunities incl. Ghost-damage halving; Supersweet Syrup's one-time gate; Rattled's
  dual trigger). Every ability has a negative case confirming it does not
  trigger/apply when its condition isn't met, per the mandatory convention this tier
  carried forward from M17a's Rock Head lambda-capture lesson.
- `.tres` data: all 32 abilities added to `scripts/gen_abilities.py` (matching its
  existing description/ai_rating convention) and regenerated via the script.
- Full regression: all 22 prior suites (everything through `m17a_test`) plus the fixed
  `ability_test` all confirmed passing — 23 numbered suites, **1315 total assertions**,
  0 failures (verified manually in-terminal per this project's existing convention for
  Godot test execution).
- 2026-07-02.

## [M17c] Tier C move effects — switch-in/turn-end triggers, no new field-state infrastructure

Scoping source: `docs/m17_recon.md` (Section 11's Bucket C proposal, cross-checked
against Section 13's Signature-Ability Sweep exclusions, the same way `[M17a]`/`[M17b]`
did). This entry records what M17c actually implemented and cites source per ability —
it does not re-derive the roster/exclusion reasoning, which lives in the recon doc.

### Step 0 — finalized ability list

Section 11's Bucket C proposal was re-derived against the final exclusion set and
against what the earlier tiers actually shipped, rather than trusted as-is. Corrections
made during this cross-check:

- **Toxic Chain (305) excluded** — confirmed in the task's Section 13 exclusion list
  (Loyal Three legendary trio: Fezandipiti/Munkidori/Okidogi).
- **Spicy Spray (318) excluded** — NOT in the task's Section 13 transcription, but
  Section 13.3 source-verified it as Mega-exclusive-only (Scovillain-Mega, this hack's
  custom Mega addition, zero non-Mega holders), which falls under this project's
  pre-existing "no Mega Evolution" scope note — the same grounds Aerilate/Parental
  Bond/Piercing Drill are already excluded on. A real gap in the task's transcription,
  same shape as `[M17b]`'s Beast Boost catch.
- **Solar Power (94) and Poison Heal (90) deferred to M17d, not included here** —
  Section 11's own tier proposal explicitly routes these two to M17d ("Weather-setter
  completions + Primal trio + Poison Heal/Solar Power/Dry-Skin-style multi-part
  abilities"), bundled with the Primal weather trio specifically because they're
  multi-part (Solar Power spans the Bucket A damage pipeline AND Bucket C end-of-turn;
  Poison Heal needs to redirect the existing poison-damage function). Confirmed Solar
  Power's damage-half was NOT shipped in `[M17a]`'s actual 32-ability list before
  deferring — the task's own "expected shape" hint included these two in M17c, but the
  recon's explicit tier assignment was trusted over that hint per the task's own
  instruction.
- **Harvest (139) excluded from this tier** — also absent from Section 11's actual M17c
  list (verified directly, not assumed). It needs new "last consumed berry" tracking on
  `ItemManager` (recon infra flag #6), which conflicts with this tier's "no new
  field-state infrastructure" framing. Cheek Pouch/Ripen are fine because they reuse the
  EXISTING berry-consumption choke point; Harvest needs a genuinely new one.
- **Dry Skin (87) stays in** despite also touching the damage pipeline (Fire-type
  damage-taken increase) — Section 11 explicitly keeps it in M17c unlike Solar Power, so
  trusted as written.

Final list, 22 abilities, canonical IDs re-verified against
`include/constants/abilities.h` directly:

Effect Spore(27), Poison Point(38), Rain Dish(44), Sand Stream(45), Truant(54), Shed
Skin(61), Dry Skin(87), Hydration(93), Anticipation(107), Forewarn(108), Ice Body(115),
Snow Warning(117), Frisk(119), Flower Gift(122), Cursed Body(130), Healer(131), Poison
Touch(143), Cheek Pouch(167), Slush Rush(202), Ripen(247), Toxic Debris(295),
Hospitality(299).

### Source citations, per ability

**Weather-setters** (extend the existing `get_switch_in_weather`, same function
Drizzle/Drought already use):
- **Sand Stream** (45) — `battle_util.c` L3227-3239: switch-in → Sandstorm.
- **Snow Warning** (117) — `battle_util.c` L3256-3269: switch-in → Hail/Snow (gated on
  `B_SNOW_WARNING >= GEN_9`). Mapped to this project's single `WEATHER_HAIL` constant —
  this codebase never modeled a separate Gen-9 Snow value, so this is the correct
  mapping for the existing weather model, not a dropped distinction.

**End-of-turn heal/damage/cure** (extend `try_end_of_turn`, the same function
Speed Boost/Moody already use — new `weather`/`ally` params, new force-roll seams for
Shed Skin/Healer):
- **Rain Dish** (44) — `battle_util.c` L3557-3567: rain active, not at max HP → heal
  maxHP/16.
- **Ice Body** (115) — `battle_util.c` L3541-3549: hail active, not at max HP → heal
  maxHP/16.
- **Dry Skin** (87) — three-part, all three cited and two wired:
  1. `battle_util.c` L3553-3556 (rain heal, shares Rain Dish's branch with a /8 divisor
     instead of /16 — L3562) — WIRED.
  2. `battle_util.c` L2246/L6616 (Water-type move absorb+heal, same `AbsorbedBy
     DrainHpAbility` mechanism as Volt Absorb/Water Absorb) — **DEFERRED**. This needs
     the Bucket-E "immunity + heal" pipeline shape (an early-return-zero-damage-plus-heal
     check) that this project doesn't have for ANY ability yet, since Volt Absorb/Water
     Absorb themselves are still unimplemented (Bucket E, a later tier). Implementing it
     only for Dry Skin would mean building that shape from scratch for one ability in a
     "no new infrastructure" tier — deferred until Volt Absorb/Water Absorb are
     scheduled, at which point Dry Skin should reuse whatever shape they establish.
  3. `battle_util.c` L6616-6619 (Fire-type damage taken ×1.25, same post-type-
     effectiveness slot as Heatproof) — WIRED, in `defense_damage_modifier_uq412`.
  4. `battle_util.c` L3660-3667, shared `SOLAR_POWER_HP_DROP` label (sun → self-damage
     maxHP/8) — WIRED.
- **Hydration** (93) — `battle_util.c` L3568-3574: rain active, has any status → cure
  it (shares the `ABILITY_HEAL_MON_STATUS` label with Shed Skin).
- **Shed Skin** (61) — `battle_util.c` L3575-3600: has any status, 1/3 chance (GEN_LATEST
  config: the `== GEN_4` branch is false, so `RandomChance(1,3)` applies — a genuinely
  different threshold than Static/Poison Point's 30% `>= GEN_4` branch despite looking
  similar) → cure it.
- **Healer** (131) — `battle_util.c` L3669-3677: doubles-only, ally alive with any
  status, 30% chance → cure the ALLY's status (not the holder's own).

**Truant** (54) — a genuine pre-move canceler PLUS an end-of-turn toggle, two touch
points:
- `battle_move_resolution.c :: CancelerTruant` (L258-270): if `truantCounter` is set,
  the move fails outright ("loafing around"), before PP deduction or anything else.
  Wired into `StatusManager.pre_move_check`, positioned between Freeze and Flinch to
  match `CANCELER_TRUANT`'s actual position in source's canceler chain (after
  `CANCELER_ASLEEP_OR_FROZEN`, before `CANCELER_FLINCH`).
- `battle_util.c` L3646-3647 (end-of-turn `ABILITY_TRUANT` case): unconditionally
  toggles `truantCounter` (XOR) every end of turn, regardless of whether the holder
  moved. New `BattlePokemon.truant_loafing: bool` field — cleared by `_clear_volatiles`
  like an ordinary switch-scoped volatile (confirmed via
  `include/constants/battle.h` L307: `VOLATILE_TRUANT_COUNTER` has no
  `V_BATON_PASSABLE` flag, unlike Supersweet Syrup's deliberately-NOT-cleared
  `supersweet_syrup_used`).

**Contact status infliction** (extend `try_contact_effects`, same function
Static/Flame Body already use):
- **Poison Point** (38) — `battle_util.c` L4068-4090: 30% chance to poison the attacker
  on contact.
- **Poison Touch** (143) — separate switch-case entry, identical shape to Poison Point.
- **Effect Spore** (27) — `battle_util.c` L4024-4066: weighted 3-way roll out of 0-99 —
  9% poison / 10% paralysis / 11% sleep (a genuine GEN_5+ quirk, NOT an even 10/10/10
  split), plus `IsAffectedByPowderMove(attacker)` (L4032). This project has no general
  "powder move" immunity system, but the specific exemption that check encodes for THIS
  ability — Grass-type attackers — is a plain `TypeChart` check already available
  everywhere else in this codebase, so it's applied directly rather than skipped
  outright.

**Non-contact-gated hit-reactive** (extend `try_hit_reactive_effects`, the same
non-contact-gated function `[M17b]` introduced for Justified/Rattled/etc.):
- **Cursed Body** (130) — `battle_util.c` L3843-3858: any damaging hit landing (NOT
  contact-gated, unlike Mummy/Static/Flame Body in the same source switch), attacker not
  already disabled, move used isn't Struggle, 30% chance → disables the attacker's
  just-used move for 4 turns (`B_DISABLE_TIMER`, the same constant this project's
  Disable move already uses). Reports a bool flag only; `BattleManager` applies
  `disabled_move`/`disable_turns` directly at the call site, mirroring how the Disable
  MOVE itself is applied (no shared helper exists for "apply a disable" — not worth
  introducing one for this single extra caller).
- **Toxic Debris** (295) — `battle_util.c` L4246-4259: physical hit landing, attacker's
  side not already at 2 Toxic Spikes layers → sets one layer. Reuses M16d's EXISTING
  `_side_conditions[side]["toxic_spikes_layers"]` directly, confirmed as a pure reuse
  (no new hazard-adjacent subsystem) — the same state Spikes/Toxic Spikes/Stealth Rock
  already read and write.

**Weather-conditional stat modifiers**:
- **Flower Gift** (122) — two source functions, both from the existing M17a-era
  pipeline hooks, plus a scope decision:
  - `battle_util.c` L6855-6858 (self Attack ×1.5, sun + physical) — folded into
    `attack_modifier_uq412` (new `weather` param, one call site updated).
  - `battle_util.c` L7114-7148 (self OR ally Sp. Def ×1.5→reciprocal damage ×0.667, sun
    + special) — folded into `defense_damage_modifier_uq412` (new `weather` and `ally`
    params; `DamageCalculator.calculate` gained a new `defender_ally` trailing param,
    since Flower Gift's ally-share needs the DEFENDER's doubles partner, a different
    ally than the attacker-side `ally` param M17a already threaded through for
    Battery/Power Spot/Steely Spirit).
  - **Scope decision**: source gates the entire ability on
    `species == SPECIES_CHERRIM_SUNSHINE`, a battle-triggered form-change this project
    doesn't model (Section 8.4/Bucket D infra this project deliberately doesn't have).
    Dropped the species-form gate and kept the generic weather-conditional boost,
    matching the exact precedent Rob already established for the Primal weather trio
    (`[M17-recon]` Section 8.5: "implement as ordinary innate... dropping the
    must-be-the-specific-form gate entirely, consistent with Rob's stated intent to
    freely reassign any ability to any species").
- **Slush Rush** (202) — same weather-conditional speed-multiplier shape as the
  still-unimplemented Swift Swim/Chlorophyll/Sand Rush family (this is the first of
  that family this project implements): Speed ×2 in Hail. Folded into
  `StatusManager.effective_speed` (new `weather` param, two call sites in
  `_phase_priority_resolution` updated; the two `TrainerAI` call sites were left on the
  `WEATHER_NONE` default — a minor, pre-existing-shape simplification, same category as
  M11's "weather-aware AI scoring explicitly deferred").

**Item-adjacent**:
- **Cheek Pouch** (167) — `battle_script_commands.c :: TryCheekPouch` (L6175-6188):
  heals maxHP/3 whenever the holder eats ANY berry. Every item consumed via this
  project's existing `BattleManager._consume_item` choke point IS a berry today
  (Lum/Sitrus/resist berries — the only consumed-item mechanics this codebase has), so
  this reuses that single existing function directly rather than building a new "is
  this a berry" gate.
- **Ripen** (247) — `battle_util.c :: GetDefenderItemsModifier` (L7519): doubles the
  resist berry's damage reduction (0.25× instead of 0.5×). Direct extension of the
  existing `ItemManager.defender_item_modifier_uq412` (it already receives the full
  `BattlePokemon` and can read `.ability`), no new plumbing.
- **Hospitality** (299) — `battle_util.c` L4662-4674: switch-in, doubles-only, heals the
  ally maxHP/4 (not an opponent-directed effect like Intimidate/Rattled/Pastel
  Veil/Supersweet Syrup, nor a combined-opponents effect like Download — a third
  switch-in shape). New standalone `AbilityManager.try_switch_in_ally_heal(pokemon,
  ally)`, wired into `_apply_switch_in_abilities`. **Known gap, inherited from
  `[M17b]`**: the Baton Pass inline switch-in block (battle_manager.gd's separate
  single-opponent path) does not call this, matching the SAME pre-existing
  simplification `[M17b]` already accepted for Download in that same code path — not a
  new gap introduced here.

**Cosmetic / no-op** — Anticipation (107), Forewarn (108), Frisk (119): all three
source-verified (`battle_util.c` L3083-3150) to only decide WHICH message to display
on switch-in (a threat warning, the opponent's strongest move, or the opponent's held
item) — none of them touch any stat, status, or field state. In a non-visual,
text/state-driven engine, there is nothing to gate or apply. Per the task's own
instruction, these get ID-constant registration (`AbilityManager
.ABILITY_COSMETIC_INFO_ONLY`) plus their `.tres` entries, and no dedicated mechanical
function — building invented behavior for something source confirms has none would be
worse than a documented no-op.

### Breaking/additive changes to existing signatures

All additive (new trailing parameters with defaults), no existing call site broke:
- `AbilityManager.attack_modifier_uq412` — added `weather` (Flower Gift).
- `AbilityManager.defense_damage_modifier_uq412` — added `weather`, `ally` (Dry
  Skin, Flower Gift).
- `AbilityManager.try_end_of_turn` — added `weather`, `ally`,
  `force_shed_skin_roll`, `force_healer_roll` (Rain Dish/Ice Body/Dry
  Skin/Hydration/Shed Skin/Healer/Truant).
- `AbilityManager.try_contact_effects` — added `force_effect_spore_roll` (Effect Spore).
- `AbilityManager.try_hit_reactive_effects` — added `force_cursed_body_roll`
  (Cursed Body).
- `DamageCalculator.calculate` — added `defender_ally` (Flower Gift's ally-shared
  Sp. Def half).
- `StatusManager.effective_speed` — added `weather` (Slush Rush).
- `StatusManager.pre_move_check` — no new parameter, but a new `"loafing"` result key
  (Truant).

### Bugs caught before merging

- **Flower Gift ally-share bug (a real implementation bug)**: the first draft of
  `defense_damage_modifier_uq412` gated the entire Flower-Gift-ally check inside `if
  defender.ability != null`, meaning the ally-shares-the-boost case (where the DEFENDER
  itself holds no ability at all, only its ally does) was unreachable — the exact same
  shape of bug the Flower Veil/Sweet Veil/Pastel Veil ally checks in `[M17b]` had
  correctly avoided. Caught by `m17c_test.gd` S8.07 (ally holds Flower Gift, defender
  does not). Fixed by computing `flower_gift_holder`/`ally_flower_gift` independently,
  outside any `defender.ability != null` gate.
- **Test-only bug, Cursed Body integration**: the first draft used a Ghost-type holder
  for `m17c_test.gd`'s full-battle integration test with a Normal-type attacking move —
  Normal-type moves are outright type-immune (0×) against Ghost-type defenders (a
  pre-existing, unrelated type-chart rule), so the test measured zero damage and the
  hit-reactive dispatch never fired regardless of Cursed Body's correctness. Same
  pitfall class as `[M17b]`'s Purifying Salt test bug (Normal-vs-Ghost immunity).
  Fixed by giving the holder an ordinary non-immune type instead.

### Testing / Regression

- New `m17c_test.gd`/`.tscn`: 79/79 assertions across 12 sections (ability data
  spot-checks; weather-setters; end-of-turn heal/cure; Truant's canceler+toggle cycle;
  contact status infliction incl. Effect Spore's weighted roll and Grass-type immunity;
  Cursed Body incl. full-battle integration; Toxic Debris incl. full-battle
  integration; Flower Gift incl. the ally-share case; Slush Rush; Cheek Pouch/Ripen;
  Hospitality; the three cosmetic no-ops). Every ability with a real mechanical effect
  has a negative case; the cosmetic no-ops get a minimal registration + no-side-effect
  check instead, per the task's own instruction not to invent behavior source confirms
  doesn't exist.
- `.tres` data: all 22 abilities added to `scripts/gen_abilities.py` and regenerated —
  98 total `.tres` files now carry real descriptions (12 M8 + 32 M17a + 32 M17b + 22
  M17c).
- Full regression: all 23 prior suites unchanged and still passing. Total assertions
  across all 24 numbered suites: 1315 prior + 79 = **1394**.
- 2026-07-02.

## [M17d] Weather-setter completions + Primal trio + multi-part abilities deferred from M17c

Scoping source: `docs/m17_recon.md` (Section 11's M17d proposal), cross-checked against
`[M17c]`'s own deferral language for Solar Power/Poison Heal/Harvest, the same way every
prior M17 entry has cross-checked against the recon rather than re-deriving scope from
scratch.

### Step 0 — finalized ability list

Section 11's M17d proposal ("Weather-setter completions + Primal trio +
Poison Heal/Solar Power/Dry-Skin-style multi-part abilities") was re-derived against the
current exclusion set and against what `[M17c]` actually shipped:

- **Dry Skin confirmed already shipped in `[M17c]`** — not re-implemented here.
- **Orichalcum Pulse (288) excluded** — NOT present in Section 13.1's actual candidate
  table (verified directly), but Section 13.2 documents that Rob's updated
  legendary-exclusivity standard (thematic exclusivity disqualifies regardless of
  genericness) "flipped Protosynthesis/Orichalcum Pulse... from keep to exclude."
  Section 11's own prose mentions Orichalcum Pulse as thematically paired with Hadron
  Engine and assigns it to this tier — that assignment predates the later policy update
  and is stale; not included.
- **Harvest (139) deferred again, not included.** Checked `ItemManager` and
  `BattlePokemon` directly (not assumed): no "last consumed berry" tracking exists
  anywhere in this codebase yet. Every other candidate in this tier
  (Solar Power/Poison Heal/the Primal trio) is a pure extension of an already-existing
  function; Harvest is the only one needing genuinely new state. Rather than quietly
  building new `ItemManager` infrastructure into an otherwise-reuse-only tier, Harvest
  stays deferred — its natural bundling partner whenever that tracker does get built is
  Cud Chew (291), which the recon's infra flag #6 already flags as needing the identical
  mechanism.

Final list, 5 abilities, canonical IDs re-verified against
`include/constants/abilities.h`:

Poison Heal(90), Solar Power(94), Primordial Sea(189), Desolate Land(190), Delta
Stream(191).

### Source citations, per ability

- **Solar Power** (94) — genuinely two-part, both wired:
  1. `battle_util.c :: GetAttackStatModifier`, `ABILITY_SOLAR_POWER` case
     (L6809-6811): `IsBattleMoveSpecial(move)` AND sun active → Sp. Atk ×1.5. Folded
     into the EXISTING `attack_modifier_uq412` (the same function Huge Power/
     Overgrow/Guts/Flower Gift already live in), immediately after Flower Gift's
     entry — category-gated to special only, unlike Flower Gift's physical-only gate
     right above it.
  2. `battle_util.c`, end-of-turn `ABILITY_SOLAR_POWER` case (L3660-3667, the shared
     `SOLAR_POWER_HP_DROP` label Dry Skin's sun half also jumps to in source — this is
     the ability the label is actually named after): sun active → self-damage maxHP/8,
     unconditionally (no not-at-max-HP gate, unlike Rain Dish/Ice Body's heal
     branches). Folded into the EXISTING `try_end_of_turn`, reusing the same
     `"damage_amount"` result key Dry Skin's sun half already produces — no new key,
     no new BattleManager wiring needed beyond tagging the correct `ability_triggered`
     string (`"solar_power"` vs `"dry_skin"`, since both abilities now share that one
     result key).
- **Poison Heal** (90) — `battle_end_turn.c :: HandleEndTurnPoison`,
  `ABILITY_POISON_HEAL` case (L533-544): inverts the poison/toxic end-of-turn tick
  into a heal instead of damage. Two things confirmed from source and preserved
  faithfully:
  1. The heal is a FLAT maxHP/8 regardless of poison vs. toxic — NOT scaled by the
     toxic counter the way ordinary toxic damage is.
  2. The toxic counter still increments even though Poison Heal converts the tick into
     a heal (source keeps ticking `STATUS1_TOXIC_COUNTER` unconditionally).
  Implemented by extending the EXISTING `StatusManager.end_of_turn_damage` (the single
  function every burn/poison/toxic tick in this project already goes through, per the
  task's explicit instruction not to build a parallel poison-damage path) to return a
  **negative** value for the Poison Heal case — the one call site in
  `battle_manager.gd` branches on the sign (positive = damage, applied as before;
  negative = heal, newly wired to reuse the `ability_healed` signal M17c introduced).
- **Primordial Sea** (189) — `battle_util.c`, `ABILITY_PRIMORDIAL_SEA` case
  (L3400-3407): switch-in → sets Rain. **Desolate Land** (190) — `ABILITY_DESOLATE_LAND`
  case (L3391-3398): switch-in → sets Sun. Both folded into the EXISTING
  `get_switch_in_weather` (the same function Drizzle/Drought/Sand Stream/Snow Warning
  already use), reusing this project's ordinary `WEATHER_RAIN`/`WEATHER_SUN` constants
  directly rather than adding separate "Primal Rain"/"Primal Sun" values — per
  `docs/m17_recon.md` Section 8.5's explicit recommendation, dropping the
  "must-be-the-Primal-Reversion-form-of-a-specific-legendary" gate entirely, consistent
  with Rob's stated intent to freely reassign any ability to any species. This project
  has no Air-Lock-blocks-Primal-only or weather-move-resists-Primal-only
  special-casing that would ever need the ordinary and Primal versions to be
  distinguishable, so a plain reuse is the correct port, not a simplification.
  **Known simplification** (not requested by the task, flagged here proactively): real
  Primal weather persists indefinitely while the setter remains on the field and
  reverts immediately on switch-out, rather than decrementing on a fixed turn counter.
  This project's weather model has only ever had fixed-duration weather (5 turns, 8
  with a rock item) since M11 — implementing indefinite-while-present weather would be
  new infrastructure (tracking "is the setter still active" and reacting to its
  switch-out), out of scope for a tier otherwise made of pure reuse. Primordial
  Sea/Desolate Land use the same fixed-duration model as Drizzle/Drought here.
- **Delta Stream** (191) — `battle_util.c`, `ABILITY_DELTA_STREAM` case (L3409-3416):
  switch-in → sets a weather value this project never had before, Strong Winds. Two
  parts, both wired:
  1. New `DamageCalculator.WEATHER_STRONG_WINDS` constant (value 5), folded into
     `get_switch_in_weather` exactly like the other switch-in weather setters — an
     additive constant, not new infrastructure in the Section 10/11 sense.
  2. The type-effectiveness side effect — `battle_util.c ::
     MulByTypeEffectiveness` (L8069-8074): "weakens Super Effective moves against
     Flying-type Pokémon," checked PER DEFENDING TYPE COMPONENT (`defType ==
     TYPE_FLYING && mod >= 2.0 → mod = 1.0`), not on the combined multi-type product.
     Wired at BOTH of this project's two independent type-effectiveness computations,
     which had to be kept consistent by hand since they're not unified into one
     function the way source's single `CalcTypeEffectivenessMultiplierInternal` is:
     - The early `effectiveness` float in `DamageCalculator.calculate` (used for
       immunity checks and Filter/Solid Rock/Tinted Lens's threshold gates) —
       `TypeChart.get_effectiveness` gained a new `weaken_flying_se: bool` parameter
       (a plain bool, not a `WEATHER_*` constant, to avoid a cross-reference from the
       data-layer `TypeChart` script back to `DamageCalculator`; the one caller that
       needs it computes the bool itself from `weather == WEATHER_STRONG_WINDS`).
     - The actual per-type UQ4.12 damage multiplier block in `calculate()` (the
       `TypeChart.get_uq412` calls that produce the value actually applied to
       damage) — corrected inline, matching the same per-component granularity.
     Every other caller of `get_effectiveness`/`get_uq412` (AI heuristics, Stealth
     Rock/OHKO-move type checks) was left at the default (no Strong Winds awareness) —
     the same category of simplification as "weather-aware AI scoring explicitly
     deferred" since M11.

### Additive changes to existing signatures

All additive (new trailing parameters with defaults or a documented sign convention),
no existing call site broke:
- `StatusManager.end_of_turn_damage` — same signature, but now returns a signed `int`
  (negative = heal) instead of an always-non-negative damage amount. The one call site
  in `battle_manager.gd` was updated to branch on sign; every OTHER caller (there are
  none besides that single site) needed no change.
- `TypeChart.get_effectiveness` — added `weaken_flying_se: bool = false`.
- `DamageCalculator.WEATHER_STRONG_WINDS` — new constant, additive.

### Testing / Regression

Per CLAUDE.md's type-immunity-precedes-ability-logic convention (the third documented
testing pitfall, added this session), every damage-calc scenario in `m17d_test.gd` was
checked against `TypeChart.TABLE` directly before being used — Solar Power's damage-half
tests use a neutral Normal-vs-Normal matchup to isolate the ability from any type
interference, and Delta Stream's Flying-type-weakness tests use Electric/Rock-type moves
against Flying-type defenders, confirmed super-effective (2.0×/4.0×) from the table
first, never an immunity.

- New `m17d_test.gd`/`.tscn`: 30/30 assertions across 6 sections (ability data
  spot-checks; Solar Power's damage-pipeline half; Solar Power's end-of-turn
  self-damage half; Poison Heal incl. the flat-not-counter-scaled toxic heal and the
  counter-still-increments check; the Primal trio's weather-setting with an explicit
  no-item-required check; Delta Stream's weather-setting plus both the mono-type and
  dual-type Flying-weakness-cancellation cases, plus negative cases confirming
  non-Flying defenders and sub-2.0x hits against Flying are both left untouched).
- `.tres` data: all 5 abilities added to `scripts/gen_abilities.py` and regenerated —
  103 total `.tres` files (12 M8 + 32 M17a + 32 M17b + 22 M17c + 5 M17d).
- Full regression: all 24 prior suites unchanged and still passing (including
  `damage_test`, re-checked specifically since `TypeChart.get_effectiveness`'s
  signature changed). Total assertions across all 25 numbered suites:
  1394 prior + 30 = **1424**.
- 2026-07-02.

## [M17f] Trapping check (new infrastructure) — Shadow Tag / Arena Trap / Magnet Pull

Scoping source: `docs/m17_recon.md` Section 11's M17f proposal ("Trapping check (new
infra) + Shadow Tag/Arena Trap/Magnet Pull. Unchanged from the original recon's
3-ability group (infra flag #3). Small, standalone tier."). First genuinely
new-infrastructure tier since M14a — every M17a-d tier so far was pure reuse of
existing call sites.

### Step 0 — finalized ability list

Re-checked Shadow Tag (23), Arena Trap (71), and Magnet Pull (42) against Section 13's
full exclusion sweep (13.1 legendary/mythical/UB candidates, 13.2 Primal-trio
re-litigation, 13.3 Mega-exclusive-only, 13.4 ordinary-co-holder exceptions) — none of
the three appear anywhere in it. Canonical IDs re-verified directly against
`include/constants/abilities.h`: `ABILITY_SHADOW_TAG = 23`, `ABILITY_MAGNET_PULL = 42`,
`ABILITY_ARENA_TRAP = 71` — all match the recon exactly. Final list, unchanged from
Section 11's proposal: **Shadow Tag (23), Arena Trap (71), Magnet Pull (42)**.

### Source citation and mechanic

`battle_util.c :: IsAbilityPreventingEscape` (L4917-4941), called from two selection-time
sites in `battle_main.c`: the wild-battle "Run" menu option (L3993) and the
`B_ACTION_SWITCH` case in the party-switch-menu handler (L4230-4238) — both gate the
choice itself, before it's accepted as an action, never after. `CanBattlerEscape`
(L4943), the separate function backing forced switches/faint-replacement/Baton Pass, has
**no ability check at all** ("no ability check" is literally the function's own source
comment) — confirming trapping is architecturally a selection-time-only gate in
source, not a battle-wide "can this Pokémon ever leave" flag.

Per-ability conditions, all read directly off `IsAbilityPreventingEscape`:
- **Ghost-type exemption is global, not per-ability**: `GetConfig(B_GHOSTS_ESCAPE) >=
  GEN_6` exempts a Ghost-type battler from ALL THREE trapping abilities in one early
  return, before the per-ability loop even runs. This project runs GEN_LATEST
  throughout (matching every prior GEN_LATEST config citation in this file), so the
  exemption applies unconditionally here.
- **Shadow Tag** (23): traps unconditionally, UNLESS the trapped battler ALSO has Shadow
  Tag, which only exempts (mirror match — neither side traps the other) at
  `B_SHADOW_TAG_ESCAPE >= GEN_4` — also GEN_LATEST here, so the mirror exception always
  applies.
- **Arena Trap** (71): traps only a GROUNDED opponent. Reuses `AbilityManager.is_grounded`
  (built in M16d for hazards) directly — no new grounded-check logic needed.
- **Magnet Pull** (42): traps only a Steel-type opponent.
- **Shed Shell** (the one item-based exemption source has, `HOLD_EFFECT_SHED_SHELL`) is
  **not modeled**: confirmed via direct grep that this project's `ItemManager`/data has
  no Shed Shell item anywhere, so there is nothing to exempt. Noted here rather than
  silently omitted, matching this project's convention for flagging known gaps (e.g.
  M16d's Air Balloon/Magnet Rise omission from `is_grounded`).
- Checked whether any existing ability-suppression mechanism (Mold Breaker/Neutralizing
  Gas) needs to interact with trapping: confirmed via grep that neither exists anywhere
  in this codebase yet (both are still unbuilt, per infra flag #4 / the proposed M17g
  tier below) — no interaction code needed, nothing to gate against.

### New infrastructure

- `AbilityManager.is_trapped(mon: BattlePokemon, live_opponents: Array) -> bool` —
  encodes the Ghost exemption, the Shadow Tag mirror exception, and the Arena
  Trap/Magnet Pull per-type gates described above. Takes the same "live opponents"
  shape `_apply_switch_in_abilities` already gathers (non-fainted, opposing-side
  combatants), not a hidden global lookup, so it stays doubles-correct with zero extra
  plumbing.
- `BattleManager._get_live_opponents(mon) -> Array` — a small new accessor mirroring the
  loop shape already inside `_apply_switch_in_abilities`, extracted so
  `_phase_move_selection` can call it too.
- Wired into `_phase_move_selection`: immediately after a queued/AI-chosen switch sets
  `_chosen_switch_slots[i]` (matching source's selection-time gate, not an
  execution-time one), a call to `is_trapped` blocks it — the slot resets to `-1` and
  the mon falls back to its first move, reusing the exact fallback expression already
  used elsewhere in the same function for "nothing else picked an action."
- **Confirmed unaffected, by construction (different call paths, not a special-cased
  exemption)**: forced switches (Roar/Whirlwind → `_do_forced_switch_in`), faint
  replacement (`_phase_switch_prompt` → `_do_switch_in`), and Baton Pass (a move,
  executed via `_chosen_moves`, never touches `_chosen_switch_slots` at all) — none of
  these three call sites reads `_chosen_switch_slots` or calls `is_trapped`. This
  mirrors `CanBattlerEscape`'s "no ability check" in source exactly.
- Trapping only restricts the OPPONENT's switching; the ability holder's own side is
  read from a completely disjoint set (`_get_live_opponents` explicitly excludes the
  holder's own side), so nothing needed to be added to keep the holder itself free to
  switch normally.

### Testing / Regression

New `m17f_test.gd`/`.tscn`, 28/28 assertions across 9 sections: ability-data spot-checks;
12 direct `is_trapped` unit tests (positive traps for all three abilities; Arena Trap
negative on Flying-type and on a Levitate holder; Magnet Pull negative on non-Steel;
Ghost-type exemption against all three, including a dual Ghost/Steel mon against Magnet
Pull specifically to prove the global exemption overrides the per-type gate; the Shadow
Tag mirror-match exemption; a doubles-shape "trapped if ANY live opponent matches"
check); full-battle integration for Shadow Tag blocking a voluntary switch (with the
blocked mon's fallback move confirmed via `move_executed`, and a same-turn-vs-later-faint
ambiguity resolved by ordering `pokemon_fainted`/`pokemon_switched_in` events rather than
asserting "never switched in" outright); Arena Trap's Flying-type exemption and Magnet
Pull's Steel-only gate confirmed via full battles where the switch actually succeeds;
Roar bypassing trapping; Baton Pass bypassing trapping; faint replacement bypassing
trapping; and the holder's own side switching freely. Per CLAUDE.md's
type-immunity-precedes-ability-logic convention, every full-battle scenario uses
Normal-type Tackle between non-Ghost defenders — the one relevant immunity in this
tier's type set (Ghost/Normal) is confirmed absent from every scripted damage exchange;
Ghost-type mons appear only in the direct `is_trapped` unit tests, which never call
`DamageCalculator`.

- `.tres` data: all 3 abilities added to `scripts/gen_abilities.py` and regenerated —
  106 total `.tres` files (12 M8 + 32 M17a + 32 M17b + 22 M17c + 5 M17d + 3 M17f).
- Full regression: all prior suites unchanged and still passing. Total assertions across
  all 27 numbered suites: 1424 prior + 28 = **1452** (direct-count verification during
  this sweep totaled 1476 across the actual 27 `.tscn` files present, indicating the
  prior "25 suites" figure in `[M17d]`'s entry undercounted by one suite that already
  existed at that time — not a regression, just a stale count; every suite passed clean
  either way, 0 failures).
- 2026-07-02.

### Next tier

M17e (Terrain system) is **void** — see `CLAUDE.md`'s status section for the full
scope-decision rationale (all 10 terrain-reliant abilities excluded). Section 11's next
proposed tier, **M17g — ability-suppression plumbing (Mold Breaker/Neutralizing Gas) +
free-riders**, needs its own re-verification before implementation: Section 11's
original M17g prose lists Turboblaze (163) and Teravolt (164) as "free-riders" once
Mold Breaker's plumbing exists, but Section 13.1 later flags BOTH as legendary-exclusive
(Reshiram/Kyurem-White and Zekrom/Kyurem-Black respectively) — under Rob's
legendary-exclusivity standard, both should be excluded, the same correction pattern as
Beast Boost in `[M17b]` and Orichalcum Pulse in `[M17d]`. Mycelium Might (298) is listed
as only "partially" a free-rider in Section 11 (it also needs the separate turn-order
Stall-shape half) and is NOT in Section 13's exclusion sweep, so it likely stays in
scope pending its own Step 0 check when M17g is actually implemented. Not resolved
further here — this is a pointer for the next implementation prompt, not a new tier
proposal.

### Follow-up (2026-07-02): general Ghost-type trapping immunity — verified already correct, extensibility comment added

A follow-up task asked to re-verify the broader Gen 6+ rule that Ghost-types are immune
to ALL trapping (not just Shadow Tag's own `B_SHADOW_TAG_ESCAPE` mirror-match exception),
on the concern that M17f's original scope (which only asked about Shadow Tag's own
condition) might have missed it. Re-checked against source rather than assuming either
way:

- `battle_util.c :: IsAbilityPreventingEscape` (L4919) and `CanBattlerEscape` (L4947,
  the separate function behind move-based trapping volatiles — escapePrevention from
  Mean Look/Block/Spider Web, `wrapped` from Wrap/Fire Spin/Whirlpool/Sand
  Tomb/Clamp/Magma Storm/Infestation, `root` from Ingrain, `STATUS_FIELD_FAIRY_LOCK`)
  both independently gate on the exact same `GetConfig(B_GHOSTS_ESCAPE) >= GEN_6 &&
  IS_BATTLER_OF_TYPE(battler, TYPE_GHOST)` check — confirming the immunity is uniform
  across BOTH ability-based and move-based trapping sources in source, not an
  ability-specific carve-out layered onto Shadow Tag alone.
- No `B_UPDATED_SHADOW_TAG` config flag exists anywhere in this project's
  `pokeemerald_expansion` reference (`grep -rn "B_UPDATED_SHADOW_TAG"` — zero matches);
  the only two relevant flags are `B_GHOSTS_ESCAPE` (the general immunity) and
  `B_SHADOW_TAG_ESCAPE` (Shadow Tag's own separate mirror-match exception), both already
  documented above.
- **This project's `AbilityManager.is_trapped()` already implemented the general rule
  correctly** — the `TypeChart.TYPE_GHOST in mon.species.types: return false` check was
  already positioned as the FIRST line of the function, before the Shadow
  Tag/Arena Trap/Magnet Pull loop, exactly matching source's structure (a single gate
  covering all three, not threaded into each ability's own condition). No functional
  code change was needed — this follow-up confirmed, rather than fixed, a gap.
- **What WAS added**: an extensibility comment on `is_trapped()` (`ability_manager.gd`)
  documenting that any future move-based trapping (Mean Look/Block/Spider Web/Ingrain/
  the partial-trap moves) should route through this same function's Ghost gate rather
  than reimplementing the check per-move when those moves are eventually built — those
  moves are out of scope for M17 (abilities only) and no move-trapping infrastructure
  was added now, per the task's explicit instruction.
- New full-battle integration test, `m17f_test.gd` Section 3D: a Ghost-type opponent
  voluntarily switches away freely despite an active Shadow Tag holder (the strongest of
  the three trapping abilities, chosen specifically because it has no type/grounded
  condition of its own to confuse with the Ghost gate). This closes the gap between the
  original suite's unit-level Ghost checks (S2.07-S2.09, which already existed and
  already covered Shadow Tag/Arena Trap/Magnet Pull individually, including a dual
  Ghost/Steel mon proving the Ghost gate overrides Magnet Pull's own type condition) and
  an actual `_phase_move_selection` voluntary-switch flow. Per CLAUDE.md's
  type-immunity-precedes-ability-logic convention, this scenario sidesteps Ghost's
  immunity to Normal-type Tackle entirely rather than fighting around it: this project's
  switches-before-moves action ordering means the Ghost-type mon leaves the field on
  turn 1 before any Tackle would ever be thrown at it.
- `m17f_test.gd`/`.tscn`: 30/30 assertions (28 prior + 2 new). Full regression: all 27
  suites still green. Total assertions across all 27 suites: 1478 (1476 prior + 2).
- Roar/Whirlwind-style forced switches were re-confirmed unaffected by this follow-up —
  no change was made to `_do_forced_switch_in` or any call site outside `is_trapped()`
  itself, so Section 4's existing forced-switch-bypasses-trapping coverage still applies
  unchanged.

## [M17g] Ability-suppression plumbing (new infrastructure) — Mold Breaker / Neutralizing Gas

Scoping source: `docs/m17_recon.md` Section 11's M17g proposal ("Ability-suppression
plumbing (new infra) + everything gated on it. Mold Breaker, Neutralizing Gas (original
pair, flag #4) PLUS Turboblaze/Teravolt (same bypass array) and (partially) Mycelium
Might"). Second genuinely new-infrastructure tier in M17, after `[M17f]`'s trapping check.

### Step 0 — finalized ability list

Re-derived against Section 13's exclusion sweep before implementation, per this
project's established M17f→M17g cross-check discipline:

- **Turboblaze (163) / Teravolt (164) excluded** — Section 13.1 flags both as
  legendary-exclusive (Reshiram/Kyurem-White, Zekrom/Kyurem-Black respectively), the
  same correction pattern as Beast Boost in `[M17b]` and Orichalcum Pulse in `[M17d]`.
  Section 11's own prose already flagged this as needing re-verification before
  implementation (see `[M17f]`'s "Next tier" note) — confirmed here, not re-derived from
  scratch.
- **Mycelium Might (298) deferred, not included.** Source-verified as a genuine hybrid
  (`battle_util.c` L4813: `ability == ABILITY_MYCELIUM_MIGHT && IsBattleMoveStatus
  (gCurrentMove)` — grouped in the EXACT SAME bypass array as Mold Breaker/Turboblaze/
  Teravolt for its ability-ignore half, but its other half — own status moves always
  act last in their priority bracket — is the Stall turn-order shape, which this project
  hasn't built yet (Stall itself is unscheduled, tentatively M17n). Implementing only
  the ability-ignore half would misrepresent the ability, the same reasoning `[M17b]`
  used to defer Guard Dog's two-part mechanic. Natural home is whenever Stall gets
  scheduled.

Final list, canonical IDs re-verified against `include/constants/abilities.h` directly:
**Mold Breaker (104), Neutralizing Gas (256)**. Just 2 abilities — a pure infrastructure
tier, no "free rider" abilities actually shipped this time (unlike `[M17a]`'s Full Metal
Body carryover).

### Source citations — the two genuinely different suppression shapes

**Mold Breaker (104)** — attacker-scoped, move-scoped:
- `battle_util.c :: IsMoldBreakerTypeAbility` (L4805-4820): identifies Mold Breaker (and
  Turboblaze/Teravolt/conditionally Mycelium Might, all excluded/deferred above) as
  "ignore-target's-ability" abilities.
- `battle_util.c` L9799-9802: `gBattleStruct->moldBreakerActive` is set true only
  `if (gCurrentMove != MOVE_NONE)`, immediately before a specific move's effects are
  resolved, and explicitly reset false at switch-in cleanup (`battle_main.c`
  L3326-3327) — confirming the suppression window is scoped STRICTLY to processing one
  Pokémon's current move, not a persistent flag.
- `battle_util.c :: CanBreakThroughAbility` (L4822-4827): `battlerDef == battlerAtk` is
  an explicit early exclusion — Mold Breaker NEVER suppresses its own wielder's ability,
  only a DIFFERENT battler's (the move's target).
- Only suppresses abilities flagged `.breakable = TRUE` in `src/data/abilities.h` — a
  per-ability data flag, not a blanket "ignore everything" rule. Cross-checked this
  project's full implemented-ability roster (M8 through `[M17f]`) against that flag
  directly (not assumed): 26 abilities are both implemented AND breakable — Battle
  Armor, Shell Armor, Levitate, Thick Fat, Marvel Scale, Fur Coat, Multiscale, Filter,
  Solid Rock, Ice Scales, Heatproof, Dry Skin, Purifying Salt, Clear Body, White Smoke,
  Hyper Cutter, Big Pecks, Keen Eye, Flower Veil, Sweet Veil, Pastel Veil, Simple,
  Contrary, Unaware, Flower Gift, Thermal Exchange (`AbilityManager
  .MOLD_BREAKER_BREAKABLE`). Confirmed NOT breakable despite looking like plausible
  candidates: Shadow Tag/Arena Trap/Magnet Pull, No Guard, Guts, Adaptability, Rock
  Head, Sniper, Tinted Lens, Compound Eyes, and the full M17b/M17c reactive-trigger
  roster except Thermal Exchange (every other ability in `try_hit_reactive_effects`
  confirmed non-breakable, one by one, not batch-assumed).
- A genuinely interesting confirmed nuance: Dry Skin's Fire-type damage-INCREASE and
  Purifying Salt's Ghost-type damage-DECREASE are both breakable — Mold Breaker
  suppresses the ability entirely regardless of whether it currently helps or hurts the
  attacker, so a Mold-Breaker holder's Fire move against a Dry Skin holder does LESS
  damage than an ordinary attacker's would (the ×1.25 vulnerability is also suppressed),
  not more. Verified this is exactly source's behavior, not a project-side quirk.

**Neutralizing Gas (256)** — field-wide, holder-presence-scoped:
- `battle_util.c :: IsNeutralizingGasOnField` (L4794-4803): true if ANY live battler has
  the ability active — a simple presence check, not move-scoped at all.
- `battle_util.c :: GetBattlerAbilityInternal` (L4844-4878), the single chokepoint EVERY
  ability read in source goes through: suppresses every OTHER live battler's ability
  (never its own — `ability != ABILITY_NEUTRALIZING_GAS` is an explicit exemption) for
  as long as it's active, touching switch-in triggers, end-of-turn triggers, contact/
  hit-reactive triggers, stat-change-blocking, status immunities, damage-pipeline
  modifiers, accuracy modifiers — genuinely everything, confirmed by the fact that
  `GetBattlerAbilityInternal` is the ONE function every other ability-reading function in
  source calls through.
- `abilityCantBeSuppressed` exemption (`gAbilitiesInfo[...].cantBeSuppressed`,
  `battle_util.c` L4852-4864): a fixed per-ability flag exempting form-defining
  mechanics (Multitype, Zen Mode, Stance Change, Shields Down, Schooling, Disguise,
  Battle Bond, Power Construct, Comatose, RKS System, Gulp Missile, Ice Face, As One ×2,
  Zero to Hero, Commander, Tera Shift) from Neutralizing Gas specifically (though a
  `.breakable` ability in this set can still be Mold-Broken). Checked directly: NONE of
  these 16 are implemented anywhere in this project (all are battle-form-change/Mega/
  Tera/legendary-exclusive mechanics already out of scope) — so
  `AbilityManager.NEUTRALIZING_GAS_UNSUPPRESSABLE` is correctly left empty rather than
  populated with unimplemented IDs, with a comment for whoever eventually builds one of
  those mechanics.

### New infrastructure

- `AbilityManager.effective_ability_id(mon, ng_active=false, attacker=null) -> int` — the
  single suppression-aware chokepoint, mirroring `GetBattlerAbilityInternal` exactly:
  Neutralizing Gas suppression first (unless in the unsuppressable set or `mon` IS the
  NG holder), then Mold Breaker suppression (only if `attacker` is a different battler,
  currently effectively holding Mold Breaker itself — resolved via a one-level recursive
  call to `effective_ability_id(attacker, ng_active)`, so an NG-suppressed Mold-Breaker
  holder correctly can't bypass anything either — a real, source-faithful double-
  suppression interaction that falls out of the recursive design rather than needing a
  special case).
- `AbilityManager.is_neutralizing_gas_active(combatants) -> bool` / `BattleManager
  ._is_neutralizing_gas_active()` — checks ALL live combatants field-wide (both sides),
  unlike `[M17f]`'s `_get_live_opponents` (one side only), computed fresh at each call
  site (cheap: ≤4 combatants) rather than cached, so a Neutralizing Gas holder fainting
  or switching out mid-turn stops suppressing immediately.
- **Every existing ability-check call site in `ability_manager.gd`, `status_manager.gd`,
  and `damage_calculator.gd` was rewritten to route through `effective_ability_id`**
  instead of reading `mon.ability.ability_id` raw — confirmed via a full grep sweep
  before and after (zero raw `.ability ==`/`.ability.ability_id` reads remain outside
  the primitive itself). This touched ~30 `AbilityManager` functions, 6 `StatusManager`
  functions, and `DamageCalculator.calculate`'s inline Adaptability/Guts checks — exactly
  the scope the task anticipated ("this touches a lot of existing code — that's expected
  and correct for a project-wide suppression mechanic"). Every call site in
  `battle_manager.gd` was updated to compute and pass `ng_active` (via
  `_is_neutralizing_gas_active()`, once per relevant phase/function) and, where the call
  site represents an actual move being resolved against a target, the current
  `attacker` (for Mold Breaker).

### Source-verified correction: the is_trapped() interaction

The task's own brief assumed "Mold Breaker ignores trapping abilities for switching
purposes too, not just damage-blocking ones." Checked against source rather than
trusted, per this project's standing discipline (the same kind of check that caught
Turboblaze/Teravolt's exclusion in `[M17f]`'s own "next tier" note) — **the assumption
was wrong, in one direction and right in the other**:

- **Neutralizing Gas DOES suppress trapping** — confirmed: `IsAbilityPreventingEscape`
  (`battle_util.c` L4917-4941) reads every trapper's ability via `GetBattlerAbility
  (battlerDef)` (L4928), the SAME suppression-aware chokepoint Neutralizing Gas's
  field-wide check already routes through everywhere else. `AbilityManager.is_trapped`
  gained an `ng_active` parameter and now correctly lets a trapped Pokémon escape while
  Neutralizing Gas is active anywhere on the field (including on the escaping Pokémon's
  own side, matching source's field-wide, not per-side, suppression scope).
- **Mold Breaker does NOT suppress trapping.** `moldBreakerActive` is scoped strictly to
  the window of processing one specific move (see the Mold Breaker citations above);
  `IsAbilityPreventingEscape` is called ONLY from selection-time menu code (the
  wild-battle Run option, the party-switch-menu's `B_ACTION_SWITCH` case — `battle_main
  .c` L3993/L4230-4238), entirely outside any move-processing window. `is_trapped`
  therefore takes an `ng_active` parameter but deliberately NO `attacker` parameter —
  documented explicitly in its own doc comment so this doesn't get "fixed" into a bug
  later by someone assuming the task brief's original (incorrect) framing.

### Bugs / gaps found, not fixed (flagged per this project's established convention)

- **Ripen's doubled resist-berry reduction appears to be dead code in the actual damage
  pipeline**: `ItemManager.defender_item_modifier_uq412` correctly computes the
  Ripen-aware value, but `DamageCalculator.calculate`'s actual resist-berry application
  hardcodes `ItemManager.UQ412_RESIST_BERRY` directly rather than calling that function
  — meaning Ripen's ability-check branch is never reached by the real multiplier applied
  to damage. This predates M17g (from `[M17c]`'s original Ripen implementation) and is
  unrelated to ability suppression — flagged here only because the M17g sweep for
  "every ability-check call site" surfaced it, not fixed, since it's out of this tier's
  scope (same convention as `[M16 Review]`'s Conversion type-reset finding).

### Testing / Regression

- New `m17g_test.gd`/`.tscn`: 31/31 assertions across 9 sections — ability data
  spot-checks; `effective_ability_id` direct unit tests (10 assertions covering NG
  suppression, the NG-doesn't-suppress-itself exemption, Mold Breaker's attacker-scoping
  in both directions, and the NG-suppresses-Mold-Breaker-itself recursive interaction);
  `is_neutralizing_gas_active` direct unit tests (including a fainted-holder negative
  case); Mold Breaker bypassing a defending Levitate holder's Ground immunity via direct
  `DamageCalculator.calculate` calls (blocked vs. bypassed contrast); Mold Breaker NOT
  suppressing when its holder isn't the actual attacker of the hit in question; a
  full-battle Neutralizing-Gas-suppresses-Intimidate scenario; a full-battle
  Neutralizing-Gas-stops-suppressing-once-its-holder-switches-away scenario (sequenced
  across 2 turns so the Intimidate holder's own switch-in fires strictly after NG has
  already left); the `is_trapped()` interaction (both directions: NG suppresses
  trapping, Mold Breaker does not, each with a direct unit test AND a full-battle
  integration); and a negative control (an ordinary Pokémon's presence suppresses
  nothing, paired with a full-battle re-run of the Intimidate scenario WITHOUT
  Neutralizing Gas to prove the earlier "did not fire" assertions were a real
  discrimination, not a vacuously-passing negative case per CLAUDE.md's signal-snapshot
  and type-immunity-precedes-ability-logic conventions).
- `.tres` data: Mold Breaker (104) and Neutralizing Gas (256) added to
  `scripts/gen_abilities.py` and regenerated — 108 total `.tres` files (106 prior + 2).
- **Baseline discrepancy noted and resolved before implementation began**: the task's
  expected baseline (26 suites, 1444 assertions) and this file's own last-recorded figure
  (27 suites, 1478 assertions, from `[M17f]`'s follow-up) disagreed with a fresh,
  directly-measured recount (27 `.tscn` files, 26 reporting assertion counts + the
  narrative-only `battle_test`, totaling **1454**, 0 failures). Per this project's
  standing "stop and flag, don't assume" discipline, this was surfaced to Rob before any
  M17g code was written; Rob confirmed proceeding on the measured 1454 baseline. The
  actual root cause of the historical drift was not further investigated (out of scope
  for this tier), consistent with `[M17f]`'s own similar "stale count, not a regression"
  resolution.
- Full regression: all 27 prior suite files unchanged and still passing (verified via a
  fresh direct recount of every suite, not assumed from the prior total). Total
  assertions across all 28 `.tscn` files: 1454 prior + 31 = **1485**, 0 failures.
- 2026-07-03.

### Next tier

Section 11's next proposed tier, **M17h — Ability-copy/overwrite plumbing (new infra) +
Trace/Mummy/Receiver/Power of Alchemy/Wandering Spirit/Lingering Aroma**, was re-checked
against Section 13's full exclusion sweep before naming it here (the same discipline
`[M17f]`'s Step 0 applied to `[M17g]` itself) — none of these 6 IDs (36, 152, 222, 223,
254, 268) appear anywhere in Section 13.1-13.4. Unlike the M17f→M17g handoff, this
tier's member list needs NO correction; Section 11's original proposal stands as-is.

## [M17h] Ability-copy/overwrite plumbing (new infrastructure) — Trace / Mummy / Receiver / Power of Alchemy / Wandering Spirit / Lingering Aroma

Scoping source: `docs/m17_recon.md` Section 11's M17h proposal ("Ability-copy/overwrite
plumbing (new infra) + everything gated on it. Trace (re-scoped here — flagging that its
cost was previously understated in the original pass, since it's the same underlying
mechanism these need) + Mummy, Receiver, Power of Alchemy, Wandering Spirit, Lingering
Aroma. Design once, ship six abilities."). Third genuinely new-infrastructure tier in
M17, after `[M17f]`'s trapping check and `[M17g]`'s suppression plumbing.

### Step 0 — finalized ability list

Re-derived against Section 13's exclusion sweep before implementation, per this
project's established per-tier cross-check discipline: **Trace (36), Mummy (152),
Receiver (222), Power of Alchemy (223), Wandering Spirit (254), Lingering Aroma (268)**
— all six canonical IDs re-verified directly against `include/constants/abilities.h`;
none appear anywhere in Section 13.1-13.4, so — unlike the M17f→M17g handoff — no
correction was needed to Section 11's original list. Lingering Aroma's source ID is
defined symbolically (`ABILITY_LINGERING_AROMA = ABILITIES_COUNT_GEN8`, not a literal
number); independently recounted (`AS_ONE_SHADOW_RIDER = 267`, then the unassigned
`ABILITIES_COUNT_GEN8` lands on 268) to confirm it resolves to 268, matching this
project's pre-existing placeholder `.tres` from an earlier (pre-M17) data-pipeline fix.

### Two genuinely different directions, not one shared "copy" function

Per the task's own instruction not to force these into a single shape, each ability's
exact mechanic was traced from source before writing any code:

- **Trace (36)** — switch-in, copies an OPPONENT's ability onto the holder. Source:
  `battle_util.c` L2964-3000 (`ABILITYEFFECT_ON_SWITCHIN` case) +
  `battle_script_commands.c :: BS_SetTracedAbility` (L12553-12559, the shared script
  command that actually writes `gBattleMons[battler].ability`). Targeting rule
  (L2971-2988): the two OPPOSING field slots are filtered to alive + not-`cantBeTraced`;
  if BOTH remain eligible, a 50/50 random pick (`RandomPercentage(RNG_TRACE, 50)`); if
  only ONE is eligible, that one deterministically; if NEITHER, Trace does nothing this
  switch-in. This project's `live_opponents` (built the same way `[M17f]`'s
  `_get_live_opponents` already does) is positionally equivalent to source's
  target1/target2 pair, so the same filter-then-pick logic applies directly. No
  `traceActivated`-equivalent volatile flag was added — this project's switch-in
  ability dispatch already fires exactly once per switch-in event (unlike source's
  more generic multi-pass-safe dispatch), so the call-site architecture itself
  provides the "exactly once" guarantee that volatile exists for in source.
- **Receiver (222) / Power of Alchemy (223)** — ally-fainting-triggered (doubles-only),
  copies the FAINTED ALLY's ability onto the holder. Source: `battle_script_commands.c
  :: BS_TryActivateReceiver` (L12946-12968), dispatched from the shared
  `BattleScript_FaintBattler` script (`tryactivatereceiver BS_FAINTED`,
  `data/battle_scripts_1.s` L2739) that runs for every faint regardless of context —
  confirmed Power of Alchemy shares this EXACT SAME function
  (`receiverAbility == ABILITY_RECEIVER || receiverAbility == ABILITY_POWER_OF_ALCHEMY`,
  L12954), not a separate near-identical implementation. The doubles-only restriction
  falls out entirely from `receiverBattler = BATTLE_PARTNER(faintedBattler)` — in this
  project, `_get_ally` already returns null in singles, so this needed zero extra
  plumbing, matching `[M17c]`'s Hospitality precedent exactly.
- **Mummy (152) / Lingering Aroma (268)** — contact hit landing → overwrites the
  ATTACKER's ability with Mummy/Lingering Aroma itself (one-directional; the holder's
  OWN ability never changes). Source: `battle_util.c` L3859-3883 — confirmed Lingering
  Aroma is mechanically identical to Mummy, sharing the exact same switch-case block
  (`case ABILITY_LINGERING_AROMA: case ABILITY_MUMMY:`, L3859-3860), not just
  similarly-shaped.
- **Wandering Spirit (254)** — contact hit landing → BIDIRECTIONAL ability swap with
  the attacker (the opposite direction from Mummy's one-way overwrite — both sides
  reassigned, `battle_util.c` L3904-3905, confirmed directly rather than assumed from
  the superficial "also contact-triggered" resemblance to Mummy).

Trace/Receiver's copy-ONTO-self and Mummy/Wandering-Spirit's overwrite/swap-WITH-other
were kept as genuinely separate functions (`try_trace`, `try_receiver_copy`,
`try_mummy_overwrite`, `try_wandering_spirit_swap`) rather than forced into one shared
"copy" primitive — they have different triggers (switch-in vs. faint vs. contact),
different targets (opponent vs. fainted ally vs. attacker), and different
directionality (one-way copy vs. one-way overwrite vs. two-way swap). All four read
and write the RAW `.ability` field, never the suppression-aware `effective_ability_id`
accessor — confirmed from source, which reads/writes `gBattleMons[...].ability`
directly throughout this entire dispatch (e.g. `gBattleStruct->tracedAbility[battler]
= gLastUsedAbility = gBattleMons[chosenTarget].ability;`, L2996) — meaning a
currently-suppressed ability is still copied/overwritten/swapped faithfully; suppression
is purely a separate, later runtime check (see the cross-tier interaction section
below). The one exception: each function's check of whether the ACTING mon's own
ability currently equals Trace/Receiver-or-Power-of-Alchemy/Mummy-or-Lingering-Aroma/
Wandering-Spirit IS suppression-aware (via `effective_ability_id`, threaded with an
`ng_active` param) — matching source's own `GetBattlerAbility` read at the dispatch
layer for the acting battler specifically (e.g. `enum Ability receiverAbility =
GetBattlerAbility(receiverBattler);`, `BS_TryActivateReceiver` L12951).

### Exemption design: AbilityData fields, not hardcoded arrays (see `[M17g]`'s addendum)

Source models FOUR distinct "can this ability be read from / changed away from" flags
in `src/data/abilities.h` — `cantBeTraced`, `cantBeCopied`, `cantBeSwapped`,
`cantBeOverwritten` — genuinely different from each other and from `[M17g]`'s
`cantBeSuppressed` (Truant is `cantBeOverwritten` but NOT `cantBeSuppressed`; Flower
Gift is `cantBeCopied` but nothing else — confirmed by direct inspection, not assumed
to overlap), each checked at a different point:

- Trace's dispatch checks `cantBeTraced` on the TARGET's raw ability.
- Receiver/Power of Alchemy's dispatch checks `cantBeCopied` on the FAINTED ALLY's raw
  ability.
- Wandering Spirit's dispatch checks `cantBeSwapped` on the ATTACKER's CURRENT ability
  (the one about to be swapped away).
- **Mummy/Lingering Aroma's dispatch checks `cantBeSuppressed`, NOT `cantBeOverwritten`**
  — a source-verified correction worth stating explicitly, since the task's own framing
  assumed `cantBeOverwritten` would be the relevant flag. Directly quoted from source
  (`battle_util.c` L3868): `!gAbilitiesInfo[gBattleMons[gBattlerAttacker].ability]
  .cantBeSuppressed`, checked on the ATTACKER's CURRENT ability. `cantBeOverwritten` is
  actually consumed by Skill-Swap/Entrainment/Simple-Beam/Worry-Seed-style MOVES
  (`battle_script_commands.c` L10631, L13036), which this project doesn't have —
  confirmed via grep that `cantBeOverwritten` has no OTHER consumer in source that would
  apply to Mummy. This REUSES `AbilityData.cant_be_suppressed`, the exact same field
  `[M17g]`'s Neutralizing Gas exemption reads, rather than a separate flag.

Mid-session design correction (raised and resolved with Rob before implementation):
`AbilityData` (`scripts/data/ability_data.gd`) was found to already define
`cant_be_copied`/`cant_be_swapped`/`cant_be_traced`/`cant_be_suppressed`/
`cant_be_overwritten`/`breakable` as `@export` boolean fields, with comments already
citing these exact mechanics, and `gen_abilities.py` already had full rendering
support — all completely unused until this tier. Rather than add hardcoded
`CANT_BE_TRACED`/`CANT_BE_COPIED`/`CANT_BE_SWAPPED` arrays in `ability_manager.gd`
(which would create a THIRD parallel exemption mechanism alongside `[M17g]`'s two
existing arrays and this dormant, purpose-built data), Rob confirmed migrating
everything to the field-based design: `[M17g]`'s two arrays were retrofitted in the
same pass (see the addendum on `[M17g]`'s own entry above), and M17h's three new
exemption needs were built field-based from the start. One consolidated source of
truth per ability, set once in `gen_abilities.py`, eliminates the "two lists could
drift out of sync" risk entirely rather than just avoiding it for this tier's own new
lists.

Every `.tres` field was set from a direct, per-ability source check (not assumed from
field names) — restricted to abilities this project actually implements, mirroring
`MOLD_BREAKER_BREAKABLE`'s own original scoping precedent:
- `cant_be_traced = true`: Trace, Receiver, Power of Alchemy, Neutralizing Gas.
- `cant_be_copied = true`: Trace, Flower Gift, Receiver, Power of Alchemy,
  Neutralizing Gas.
- `cant_be_swapped = true`: Neutralizing Gas (only).
- `cant_be_overwritten = true`: Truant (only implemented ability with this flag in
  source) — set for data fidelity even though nothing in this project's code currently
  reads it (no Entrainment/Simple-Beam/Worry-Seed-style move exists yet); flagged
  rather than silently omitted, per this project's standing convention for known gaps.
- Mummy/Wandering Spirit/Lingering Aroma themselves carry NO `cant_be_*`/`breakable`
  flags in source (confirmed directly, not assumed) — their own exemption logic reads
  the OTHER battler's ability, never their own.
- `ABILITY_NONE`'s own flags (`cantBeTraced`/`cantBeSwapped`, but not `cantBeCopied`/
  `cantBeSuppressed`) aren't representable via an `AbilityData` resource in this
  project (there is no id-0 placeholder — "no ability" is `mon.ability == null`), so
  every function checks `== null` directly instead of reading a field off a sentinel.

### Cross-tier interaction: copy-time vs. suppression-time (verified, not assumed)

Confirmed from source (all four functions read/write RAW `.ability` fields — see
above) and tested explicitly: a traced/copied ability's ID is assigned at copy time
regardless of any active Neutralizing Gas suppression elsewhere on the field;
suppression is purely a separate, later runtime check applied every time
`effective_ability_id` is consulted. A Trace holder that copies Intimidate from an
opponent still shows `tracer.ability.ability_id == ABILITY_INTIMIDATE` even once a
Neutralizing Gas holder later joins the field — only `effective_ability_id(tracer,
ng_active=true)` reports it as suppressed (`ABILITY_NONE`), and reverts to reporting
`ABILITY_INTIMIDATE` correctly the moment `ng_active` goes false again. This is exactly
the kind of cross-tier interaction `[M16 Review]` established as worth checking
deliberately rather than assuming clean — confirmed clean here, with an explicit test.

### New infrastructure

- `AbilityManager.try_trace(pokemon, live_opponents, ng_active=false,
  force_pick_second=null) -> int` — Trace's switch-in copy, called once (not
  per-opponent) from `_apply_switch_in_abilities`, mirroring `[M17b]`'s `download_stat`
  shape exactly (Trace needs to see all live opponents at once, unlike the
  per-opponent Intimidate-style loop).
- `AbilityManager.try_receiver_copy(fainted, ally, ng_active=false) -> int` — wired into
  `_phase_faint_check` immediately after `[M17b]`'s existing Moxie handling, reusing the
  same `pokemon_fainted`-adjacent point and `_get_ally`.
- `AbilityManager.try_mummy_overwrite(defender, attacker, move, damage, ng_active=false)
  -> int` / `AbilityManager.try_wandering_spirit_swap(defender, attacker, move, damage,
  ng_active=false) -> bool` — both added as new branches inside the EXISTING
  `try_contact_effects` (the same contact-gated dispatch Static/Flame Body/Gooey/
  Tangling Hair already use), not a new function — Mummy/Wandering Spirit both target
  the attacker (or both battlers), the same "effect lands on whoever touched the
  holder" shape every other entry in that function already has.
- New `BattleManager.ability_changed(pokemon, new_ability_id)` signal, mirroring
  `[M16e]`'s `type_changed(pokemon, new_type)` shape exactly — used for Trace's copy,
  Mummy/Lingering Aroma's overwrite, both halves of Wandering Spirit's swap (emitted
  twice, once per mon), and Receiver/Power of Alchemy's copy.
- **Known gap, inherited, not new**: Trace is NOT wired into the separate Baton Pass
  inline switch-in block in `_phase_move_execution` — the same already-documented
  simplification `[M17b]` accepted for Download and `[M17c]` accepted for Hospitality
  in that exact code path.

### Testing / Regression

- New `m17h_test.gd`/`.tscn`: 64/64 assertions across 10 sections — ability data
  spot-checks (including the M17g-retrofit fields now readable directly off Mold
  Breaker/Levitate/Neutralizing Gas/Truant's own resources); Trace direct unit tests
  (single-opponent copy, `cant_be_traced` exemption via Neutralizing Gas, fainted/
  no-ability/no-opponent negative cases, doubles 50/50 via `force_pick_second`, doubles
  single-eligible-slot determinism); Mummy/Lingering Aroma direct unit tests (overwrite
  on contact, non-contact negative, already-holds-Mummy no-op, zero-damage negative,
  plus an explicit note on the `cant_be_suppressed` exemption having no real
  implemented case to test against yet); Wandering Spirit direct unit tests (bidirectional
  swap confirmed on BOTH sides, `cant_be_swapped` exemption via Neutralizing Gas,
  ability-less-attacker exemption, non-contact negative); Receiver/Power of Alchemy
  direct unit tests (copy on ally-faint, identical Power-of-Alchemy behavior, singles
  no-op, non-holder-ally no-op, `cant_be_copied` exemption, holder-itself-fainting
  no-op); full-battle integration for Trace (switch-in), Mummy (contact), Wandering
  Spirit (contact, bidirectional confirmed via two separate `ability_changed` events),
  and Receiver (doubles, ally-faint); the copy-time-vs-suppression-time cross-tier
  interaction (direct + field-wide `is_neutralizing_gas_active` variant).
- A caught test-authoring bug (not an implementation bug) during the doubles-targeting
  tests: the first draft passed `force_pick_second` into `try_trace`'s THIRD positional
  slot, which is actually `ng_active` — since `force_pick_second` was left at its `null`
  default, the test silently fell back to real RNG instead of testing determinism,
  passing or failing unpredictably run-to-run. Caught by re-running the suite multiple
  times in a row and noticing inconsistent results before it could slip through as a
  flaky-but-ignored test; fixed by passing both positional arguments explicitly.
- `.tres` data: Trace/Mummy/Receiver/Power of Alchemy/Wandering Spirit/Lingering Aroma
  added to `scripts/gen_abilities.py` with real descriptions/ai_ratings (sourced
  directly from `src/data/abilities.h`, e.g. Mummy/Lingering Aroma's "Spreads with
  contact.", Wandering Spirit's "Trade abilities on contact.") — all six previously
  existed only as empty placeholder `.tres` files from an earlier bulk-placeholder
  pass. Plus the M17g-retrofit field additions on 27 existing abilities (26
  `breakable`, Truant's `cant_be_overwritten`, Neutralizing Gas's 3 fields) — 114 total
  `.tres` files (108 prior + 6 new).
- Full regression: all 27 prior suite files unchanged and still passing, including
  `m17g_test` at an UNCHANGED 31/31 post-retrofit (confirming the AbilityData-field
  migration is a pure refactor, not a behavior change). Total assertions across all 29
  `.tscn` files: 1485 prior + 64 = **1549**, 0 failures.
- 2026-07-03.

### Next tier

Section 11's next proposed tier, **M17i — Switch-out trigger hook (new infra) +
Regenerator/Natural Cure**, was re-checked against Section 13's full exclusion sweep
before naming it here (the same discipline every prior tier's Step 0 has applied to
its own list) — neither Regenerator (144) nor Natural Cure (30) appears anywhere in
Section 13.1-13.4. Section 11 also floats optionally batching in HP-threshold
forced-self-switch (Wimp Out/Emergency Exit, infra flag #13) "only if Rob wants to
batch things that make a Pokémon leave the field automatically together... otherwise
split into its own M17i-2, since the two hooks are mechanically distinct" — not
resolved here, a decision for whoever scopes M17i's own Step 0.

### Addendum (2026-07-03, during [M17h]): exemption arrays retrofitted to AbilityData fields

While building M17h's own exemption needs (cant_be_traced/cant_be_copied/cant_be_swapped
for Trace/Receiver/Wandering Spirit), discovered that `AbilityData`
(`scripts/data/ability_data.gd`) already defines `cant_be_copied`/`cant_be_swapped`/
`cant_be_traced`/`cant_be_suppressed`/`cant_be_overwritten`/`breakable` as `@export`
boolean fields — complete with comments citing these exact mechanics (Trace, Wandering
Spirit, Neutralizing Gas, Mold Breaker) — and that `gen_abilities.py` already had full
rendering support for all six, entirely unused until now. Rather than add a THIRD
parallel exemption mechanism for M17h on top of this tier's own two hardcoded arrays
(`MOLD_BREAKER_BREAKABLE`, `NEUTRALIZING_GAS_UNSUPPRESSABLE`), both were retrofitted to
read `AbilityData.breakable`/`.cant_be_suppressed` directly off each ability's own
resource — a direct 1:1 data migration (the same 26 `breakable` abilities and the same
empty `cant_be_suppressed` set this entry already source-cited above, just moved onto
the `.tres` files themselves), not a re-derivation. Both hardcoded arrays were removed
from `ability_manager.gd` entirely once the field-based checks were confirmed to
produce identical behavior (this entry's own `m17g_test.gd` suite re-run clean, 31/31,
with no test changes needed — a pure refactor). See `docs/decisions.md`'s `[M17h]`
entry for the full reasoning and the three new exemption fields this same migration
covers.

## [M17i] Switch-out trigger hook (new infrastructure) — Regenerator / Natural Cure

Scoping source: `docs/m17_recon.md` Section 11's M17i proposal ("Switch-out trigger hook
(new infra) + Regenerator/Natural Cure. Unchanged from the original recon (flag #1)."),
cross-referenced against Section 6's infra flag #1 ("Switch-out ability trigger
hook — doesn't exist. Needed by Regenerator (144) and Natural Cure (30). Only switch-IN
hooks exist today... Design once, use for both abilities."). Fourth genuinely
new-infrastructure tier in M17, after `[M17f]`'s trapping check, `[M17g]`'s suppression
plumbing, and `[M17h]`'s copy/overwrite plumbing.

### Step 0 — finalized ability list

**Regenerator (144), Natural Cure (30)** — both canonical IDs re-verified directly
against `include/constants/abilities.h` (`ABILITY_NATURAL_CURE = 30`,
`ABILITY_REGENERATOR = 144`); neither appears anywhere in Section 13.1-13.4, so — like
`[M17h]` and unlike the `[M17f]`→`[M17g]` handoff — no correction was needed to Section
11's original two-ability list.

Section 11 floated a hedge worth resolving explicitly rather than carrying forward
unexamined: whether Regenerator/Natural Cure and Wimp Out/Emergency Exit's HP-threshold
forced-self-switch (infra flag #13) should be split into two tiers, since "one reacts to
a switch already occurring, the other actively initiates one." Tracing both mechanisms
from source confirms the split is correct and the hedge resolves cleanly: Regenerator
and Natural Cure are BOTH purely reactive (they fire only once a switch-out is already
underway — `Cmd_switchoutabilities` runs after `returntoball`, when the outgoing mon has
already been confirmed leaving), while Wimp Out/Emergency Exit would need a genuinely
different mechanism (an HP-threshold check that itself INITIATES a forced switch,
something no move/ability in this project currently does). No third bucket or partial
overlap was found — Wimp Out/Emergency Exit stay out of this tier entirely, deferred to
a separate M17i-2 (or later), matching Section 11's own conditional framing ("only if
Rob wants to batch... otherwise split").

### Source citations — both abilities share one dispatch function

Both fire from the exact same battle-script command, confirming the recon's "design
once, use for both" framing was correct down to the implementation level, not just the
proposal level:

- **`battle_script_commands.c :: Cmd_switchoutabilities`** (L9322-9372) — dispatched via
  `GetBattlerAbility(battler)` (L9339, the suppression-aware read), with a `switch`
  covering both abilities:
  - **Natural Cure** (L9341-9351): clears `gBattleMons[battler].status1` entirely
    (all non-volatile status conditions — burn/poison/toxic/paralysis/sleep/freeze —
    cured in one assignment, `status1 = 0`; also fires a since-unimplemented
    `TryDeactivateSleepClause` call this project has no equivalent for, since no sleep-
    clause mechanic exists anywhere in this codebase, confirmed via grep). Does NOT
    touch any volatile condition (confusion, etc.) — `status1` only, the same
    non-volatile/volatile boundary `[M9]`'s Baton Pass passable-fields distinction and
    every subsequent status-cure site in this project already respects.
  - **Regenerator** (L9352-9364): `regenerate = GetNonDynamaxMaxHP(battler) / 3;
    regenerate += gBattleMons[battler].hp; if (regenerate > maxHP) regenerate = maxHP;`
    — integer-division floor(maxHP/3) added to current HP, clamped at maxHP.
- **Seven call sites in `data/battle_scripts_1.s`** all reach `Cmd_switchoutabilities`,
  confirming the trigger point is "any mon leaving the field alive," not "voluntary
  switch" specifically:
  `BattleScript_MoveSwitchOpenPartyScreenReturnWithNoAnim` (mid-turn move-menu switch),
  `BattleScript_EffectBatonPass` (Baton Pass), `BattleScript_DoSwitchOut` (ordinary
  turn-action switch), `BattleScript_RoarSuccessRet` (**Roar/Whirlwind forced
  switch** — `switchoutabilities BS_TARGET`), `BattleScript_SwitchOutEffects` (Emergency
  Exit / Wimp Out self-switch, and Eject Button), `BattleScript_EjectPackActivates`
  (Eject Pack item). The one mon that never reaches any of these seven sites is a
  **fainted** mon — fainting runs its own separate faint-animation script path that
  never calls `returntoball`/`switchoutabilities` at all.

### The new switch-out trigger hook

`AbilityManager.try_switch_out(mon, ng_active=false) -> Dictionary` is the shared
primitive (mirroring `Cmd_switchoutabilities`'s single-dispatch-function shape exactly,
per the recon's "design once" instruction), returning `{"healed_amount", "cured_status"}`
so `BattleManager` can emit the correct pre-existing signals rather than mutating fields
itself blind. It reads through `effective_ability_id(mon, ng_active)` — the
suppression-aware chokepoint `[M17g]` established — matching source's
`GetBattlerAbility` dispatch exactly.

`BattleManager._apply_switch_out_abilities(mon)` wraps the primitive and is called from
**three** sites, one per source call-site category that actually applies to mechanics
this project implements:

1. **`_do_voluntary_switch`** — an ordinary turn-action switch (source:
   `BattleScript_DoSwitchOut`/`BattleScript_MoveSwitchOpenPartyScreenReturnWithNoAnim`).
2. **`_do_forced_switch_in`** — Roar/Whirlwind (source: `BattleScript_RoarSuccessRet`).
   **This is a source-verified correction worth stating explicitly**: the natural
   assumption (and this tier's own initial task framing) is that switch-out abilities
   fire "only on voluntary switches." Source's own battle script disproves this directly
   — `BattleScript_RoarSuccessRet` reaches `switchoutabilities BS_TARGET` the same as any
   other switch-out, meaning a Roar-forced-out Regenerator holder heals and a
   Roar-forced-out Natural Cure holder cures its status, exactly as if it had switched
   out voluntarily. The real gate confirmed from source is **"did this mon leave the
   field alive,"** not **"was the switch voluntary."** Verified directly via a
   full-battle test (Section 6 below: `bm._force_roar_rng = 0` for a deterministic
   target, confirming `ability_healed`/status-cure fire on the Roar-forced-out mon).
3. **The inline Baton Pass switch-out block** in `_phase_move_execution` (source:
   `BattleScript_EffectBatonPass`).

Deliberately **NOT** called from `_do_switch_in` (faint replacement) — a fainted mon
never reaches source's `returntoball`/`switchoutabilities` at all (a structurally
separate faint-animation script path), so this is a correct-by-construction omission,
not an oversight papered over by a guard clause. Verified explicitly (Section 5) rather
than assumed safe by coincidence: a Regenerator holder driven to 0 HP and replaced via
the ordinary faint-replacement flow never emits `ability_healed`.

Wimp Out/Emergency Exit's self-switch (`BattleScript_SwitchOutEffects`) and Eject
Button/Eject Pack (item-triggered forced switch) also reach `Cmd_switchoutabilities` in
source, but none of those four mechanics exist in this project yet (Wimp Out/Emergency
Exit per Step 0 above; Eject Button/Eject Pack are held items, out of this ability-tier's
scope) — `_apply_switch_out_abilities` will apply correctly the moment any of those call
sites gets built, with zero changes needed to the primitive itself.

**Ordering vs. `_switch_out_clear`**: called immediately BEFORE `_switch_out_clear` at
all three sites, matching source's ordering (`switchoutabilities` runs before the
outgoing mon's data is fully torn down). Confirmed this ordering doesn't actually matter
in THIS codebase, unlike source's more entangled C struct lifecycle: `_switch_out_clear`
only clears volatiles, `stat_stages`, `last_physical_damage`/`last_special_damage`,
`protect_consecutive`, `last_move_used`, and `choice_locked_move` — it never touches
`current_hp`, `status`, or `toxic_counter`, the three fields Regenerator/Natural Cure
actually read and mutate. Kept the before-clear ordering anyway for direct source
fidelity and future-proofing (if a later milestone ever makes `_switch_out_clear` touch
HP/status, the call order is already correct rather than needing to be re-derived).

### `is_trapped()` interaction

`[M17f]`'s `is_trapped()` gates only the SELECTION of a voluntary switch, at
`_phase_move_selection` — if a switch is blocked there, `_chosen_switch_slots` is reset
to `-1` and `_do_voluntary_switch` is never called at all this turn. Since
`_apply_switch_out_abilities` only exists inside `_do_voluntary_switch`/
`_do_forced_switch_in`/the Baton Pass block, a trapped mon's blocked switch
architecturally never reaches the new hook — not a special-cased exemption, the same
"disjoint by construction" shape `[M17f]` already established for forced
switches/faint-replacement/Baton Pass bypassing trapping itself. Verified directly
(Section 8): a Shadow-Tag-trapped Regenerator holder that attempts a queued voluntary
switch never emits `pokemon_switched_out` and never emits `ability_healed` — confirming
the switch never happened at all, rather than happening-but-being-silently-a-no-op.

### Suppression-mechanism interaction

Checked directly against `src/data/abilities.h` before writing any code, per the
`[M17h]`-established "verify from source, don't assume the flag" discipline: neither
Natural Cure (L234-239) nor Regenerator (L1083-1088) carries a `.cantBeSuppressed` flag
of its own. Both are dispatched via `GetBattlerAbility` in source (the suppression-aware
read, confirmed above), so both correctly route through `effective_ability_id` — meaning
Neutralizing Gas CAN suppress either ability at the switch-out moment, same as it
suppresses them everywhere else. Verified with a full-battle test (Section 9): a
Regenerator holder switching out while an opposing Neutralizing Gas holder is active on
the field does not heal at all.

### AbilityData field usage — dormant-field check, per the `[M17h]`-established discipline

Per the standing rule `[M17h]` established ("check `AbilityData` for an existing dormant
field FIRST before adding any new hardcoded array or new field"), checked whether either
ability needed a new or existing exemption flag populated before writing any code.
Neither does: both `cant_be_suppressed` fields correctly default to `false` (matching
source, confirmed above) via `gen_abilities.py`'s existing `DEFAULTS` dict — no new
`FIELD_ORDER`/`DEFAULTS` entries, no hardcoded array, and no retrofit were needed this
tier. The only `gen_abilities.py` change was adding the two new `ABILITIES` list entries
themselves (Natural Cure/Regenerator previously existed only as empty placeholder
`.tres` files with no description/ai_rating).

Natural Cure's implementation resets `toxic_counter` alongside `status`, reusing the
exact precedent `[M17c]`'s Hydration/Shed Skin/Healer already established (curing a
status that may have already been ticking for several turns), rather than the
Lum-Berry-style cure sites elsewhere in this file (curing a status the instant it's
inflicted, where `toxic_counter` is still guaranteed to be 0 regardless) — the correct
precedent to follow given Natural Cure can fire on a mon that's been badly poisoned for
an arbitrary number of turns before switching out.

### Testing / Regression

New `m17i_test.gd`/`.tscn`: 35/35 assertions across 9 sections — ability data
spot-checks (both abilities' full `cant_be_*`/`breakable` flag sets confirmed all-false,
matching source); `try_switch_out` direct unit tests for Regenerator (ordinary
floor(maxHP/3) heal, overheal-clamping at maxHP, non-holder no-op, Neutralizing-Gas
suppression no-op) and Natural Cure (status cure, toxic_counter reset, confusion/volatile
untouched, no-status clean no-op, non-holder no-op, Neutralizing-Gas suppression no-op);
full-battle integration for an ordinary voluntary switch (both abilities); faint
replacement confirmed NOT to trigger either ability; **Roar-forced switch confirmed TO
trigger both abilities** (the source-verified correction, tested for both Regenerator
and Natural Cure independently via `_force_roar_rng = 0`); Baton Pass confirmed to
trigger Regenerator; the `is_trapped()` interaction (blocked switch never reaches the
hook); and the Neutralizing Gas suppression interaction (full-battle, not just the
direct unit call). Test suite authored and run independently by Rob in his own
terminal, confirmed 35/35 passing.

Full regression (direct foreground bash sweep, standard `pkill`/`timeout` discipline):
all 29 prior suite files unchanged and still passing, plus the new `m17i_test` at
35/35. Total across all 30 `.tscn` files (`battle_test.tscn` remains narrative-only, no
pass/fail assertions, so 29 suites contribute to the assertion count): 1549 prior + 35 =
**1584**, 0 failures.

- 2026-07-03.

### Next tier

Section 11's next proposed tier, **M17j — Item-transfer primitive (new infra) +
Pickpocket/Sticky Hold/Magician/Symbiosis**, was re-checked against Section 13's full
exclusion sweep before naming it here (the same discipline every prior tier's Step 0 has
applied to its own list) — none of the four (Pickpocket 124, Sticky Hold 60, Magician
170, Symbiosis 180) appears anywhere in Section 13.1-13.4, so no correction is needed to
Section 11's original four-ability grouping. Symbiosis is doubles-only (passes the
holder's own item to an ally after the ally's item is consumed) and Sticky Hold is a
pure blocker (prevents item removal/theft) — both depend on the same shared
item-transfer/removal primitive flag #10 first identifies, not separate mechanisms, per
Section 11's own "design once, ship four abilities" framing.

### Addendum (2026-07-03, during [M17j] resume): a real flaky-test bug found and fixed in this entry's own suite, plus a targeted check of `switch_test.tscn`'s known flakiness

Before starting M17j, a fresh baseline sweep surfaced `m17i_test.tscn` at 34/35 (`FAIL:
S9.02`) instead of the 35/35 recorded above — re-running several times confirmed it was
genuinely intermittent, not a one-off fluke. Root cause: `S9.02` read
`switcher.current_hp` **after** `start_battle_with_parties()` fully returned, the exact
signal-snapshot-not-post-battle-state pitfall this project's own CLAUDE.md documents —
the battle runs to completion, and if the bench mon (a 1v1 fight against the opposing
Neutralizing Gas holder with no decisive stat edge) later lost, `switcher` got pulled
back in as faint-replacement and took further damage before the assertion ran, corrupting
the result on the unlucky runs. Fixed by snapshotting `current_hp` via the
`pokemon_switched_out` signal (an `Array`-wrapped capture, guarded to the first
occurrence) instead of reading it post-battle. Confirmed stable across 8 consecutive
reruns after the fix, and the fresh full-sweep baseline reflects it: **1584 total
assertions**, 0 failures.

Given the shape of that bug (bench mon's fate depending on RNG timing, corrupting a
post-battle field read), a targeted check of `switch_test.tscn`'s own long-standing,
never-root-caused flakiness (occasionally reporting 62/64 instead of 64/64, first
flagged around `[M17f]`) was worth a quick look before assuming it's unrelated. Result:
`switch_test.gd`'s Section 6 (Baton Pass) already explicitly guards against this exact
pitfall (its own comment: "Capture passable state at signal time — the substitute may be
hit and confusion may decrement later in the same turn, so we must snapshot here, not at
battle end" — `bp_confusion`/`bp_substitute` captured via the `baton_passed` signal).
Section 5A (Roar) reads `opp1.confusion_turns`/`opp1.charging_move` **after** the full
battle resolves, which superficially resembles the same risk (opp1 can indeed get pulled
back onto the field later via faint-replacement once opp2, its 1-HP bench-mate, dies) —
but tracing it through: neither field can actually be re-set to a nonzero/non-null value
by anything else in that test's move roster (only Tackle is used anywhere in the test;
nothing re-inflicts confusion or starts a two-turn move), so the post-battle read is
safe in practice despite the superficially risky shape. Confirmed via 6 consecutive
clean reruns (64/64 every time) in this same session. This specific pitfall is therefore
**checked and ruled out** as `switch_test.tscn`'s flakiness root cause — the actual cause
remains un-investigated and is out of scope for this quick check, exactly as it was left
after `[M17f]`.

## [M17j] Item-transfer primitive (new infrastructure) — Pickpocket / Sticky Hold / Magician / Symbiosis

Scoping source: `docs/m17_recon.md` Section 11's M17j proposal ("Item-transfer primitive
(new infra) + everything gated on it. Design the shared 'transfer/remove/give item'
primitive (flag #15) once, then ship Pickpocket, Sticky Hold, Magician, Symbiosis
together"). Fifth genuinely new-infrastructure tier in M17, after `[M17f]`'s trapping
check, `[M17g]`'s suppression plumbing, `[M17h]`'s copy/overwrite plumbing, and `[M17i]`'s
switch-out trigger hook.

### Step 0 — finalized ability list

**Pickpocket (124), Sticky Hold (60), Magician (170), Symbiosis (180)** — all four
canonical IDs re-verified directly against `include/constants/abilities.h`; none appear
anywhere in Section 13.1-13.4, so no correction was needed to Section 11's original
four-ability grouping. Pickpocket's ID is defined symbolically in source
(`ABILITY_PICKPOCKET = ABILITIES_COUNT_GEN4`, not a literal number) — independently
recounted (`ABILITY_AIR_LOCK = 76` → `ABILITIES_COUNT_GEN3` auto-increments to 77 →
`ABILITY_TANGLED_FEET = ABILITIES_COUNT_GEN3` restarts the Gen-4 literal sequence at 77 →
… → `ABILITY_BAD_DREAMS = 123` → the unassigned `ABILITIES_COUNT_GEN4` lands on 124) to
confirm it resolves to 124 — matching this project's pre-existing placeholder `.tres`,
which (unlike Lingering Aroma's `[M17h]`-era gap) was already present for all four IDs
this time, no new placeholder-generation pass needed.

### Four genuinely different shapes, not one uniform "steal" ability

Per this tier's own task framing (and confirmed by tracing each mechanic from source
before writing any code), these four abilities are NOT interchangeable:

- **Pickpocket (124)** — reactive, **defender-keyed**: on being hit by a contact move,
  the Pickpocket holder (which must itself hold no item) steals the ATTACKER's item.
  Source: `MoveEndPickpocket` (battle_move_resolution.c L3944-3984) — the holder must be
  a battler OTHER than the current attacker that was damaged by a contact move this turn.
  Dispatched from `try_contact_effects` (already defender-keyed, contact/damage/
  fainted-attacker-gated by that function's existing shared guards), matching Static/
  Flame Body/Poison Point's existing inline shape rather than a new top-level wrapper.
- **Magician (170)** — reactive, but genuinely **attacker-keyed**, the opposite direction
  from every existing entry in `try_contact_effects`/`try_hit_reactive_effects` (both of
  which are defender-keyed reactions to being hit): the Magician holder's OWN ability
  fires after ITS OWN hit lands, stealing the TARGET's item. Source: `battle_util.c`
  L4399-4465 (`ABILITYEFFECT_MOVE_END_FOES_FAINTED`, `ABILITY_MAGICIAN` case) — confirmed
  contact is NOT required (no `IsMoveMakingContact` check anywhere in this case, unlike
  Pickpocket). This is exactly why Magician needed a genuinely new top-level function
  (`AbilityManager.try_magician`) called directly from `BattleManager._do_damaging_hit`,
  rather than folded into either existing defender-keyed dispatch.
- **Sticky Hold (60)** — passive, and structurally a **blocker, not a trigger**: it never
  fires anything itself, it gates whether Pickpocket/Magician's steal is allowed to
  happen at all. Implemented as the ONE Sticky Hold check inside the shared
  `AbilityManager._try_steal_item` primitive (see below), not duplicated per-ability —
  exactly per this tier's own explicit design ask.
- **Symbiosis (180)** — passive, **doubles-only**, and a **voluntary give**, not a steal:
  when an ally's held item is removed by ANY means, the Symbiosis holder immediately
  hands its OWN item to that ally (if it has one to give and the ally is now itemless).
  Source: `TryTriggerSymbiosis`/`TrySymbiosis` (battle_util.c L9962-9990) +
  `BestowItem` (L9998-10011) — a genuinely different one-directional primitive from
  `StealTargetItem`, and Sticky Hold does NOT gate it (the giver is voluntarily handing
  its item away, not having it forcibly removed — whatever effect originally stripped the
  ally's item already had its own Sticky Hold check, if applicable, before Symbiosis is
  ever reached).

### The shared item-transfer primitive, and where Sticky Hold gates it

`AbilityManager._try_steal_item(stealer, victim, ng_active) -> bool` is the ONE place
Sticky Hold's block lives — reused by both Pickpocket's inline branch in
`try_contact_effects` and `try_magician`, per this tier's explicit design requirement
("that check lives in exactly one place rather than being duplicated"). Mirrors source's
`StealTargetItem` (battle_script_commands.c L2055-2087): confirmed this is a plain
one-directional move (`victim.held_item` → `stealer.held_item`, `victim.held_item = null`
after), never an actual two-way exchange, since both real call sites only ever fire when
the stealer already holds no item of its own (both Pickpocket's and Magician's own
preconditions). Sticky Hold's gate is checked via `effective_ability_id(victim,
ng_active)` — the suppression-aware read `[M17g]` established — matching source's own
suppression-aware checks at both call sites (Pickpocket: battle_move_resolution.c L3971;
Magician: battle_util.c L4454).

Symbiosis uses a SEPARATE, simpler one-directional "give" (mirrors `BestowItem`) inlined
directly in `try_symbiosis` rather than routing through `_try_steal_item` — deliberately,
since Sticky Hold must NOT gate a voluntary give (see above).

### Reuses existing `ItemManager`/`BattlePokemon` state — no parallel item-tracking mechanism

All three transfer functions read and mutate `BattlePokemon.held_item` directly — the
exact same field every existing M12/M16/M17c item mechanic already uses (Choice items,
berries, Life Orb, Leftovers, Cheek Pouch, Ripen, Heavy Duty Boots). No new item-tracking
field, no parallel "who holds what" registry — confirmed by reading `ItemManager` in full
before writing any code, per this tier's own explicit ask to trace the existing
representation first.

### `AbilityData` field check, per the `[M17h]`-established discipline

Checked `AbilityData` (`scripts/data/ability_data.gd`) in full before writing any code,
per the standing rule `[M17h]` established. No dormant field exists for "this ability's
item cannot be removed" — the six existing fields
(`cant_be_copied`/`swapped`/`traced`/`suppressed`/`overwritten`, `breakable`) are all
ability-copy/suppression concepts, genuinely unrelated to item-removal blocking. Sticky
Hold's block is therefore correctly a direct ability-ID check inside
`_try_steal_item`, not a data field — the same precedent `[M17f]`'s trapping check
already set (Shadow Tag/Arena Trap/Magnet Pull are also direct ID checks inside
`is_trapped()`, not `AbilityData` fields, since trapping is likewise a concept with no
matching dormant field).

One EXISTING field turned out to be directly relevant, though: source confirms Sticky
Hold itself carries `.breakable = TRUE` (`src/data/abilities.h` L459-465) — set on its
`.tres` for data fidelity (same precedent as Truant's `cant_be_overwritten` in `[M17h]`).
Traced through carefully whether this has any reachable consumer among these four
abilities' own dispatches: it does not. Mold-Breaker-bypasses-Sticky-Hold requires the
CURRENT move's attacker to itself hold Mold Breaker while a DIFFERENT battler holds
Sticky Hold — structurally impossible through Pickpocket's or Magician's own triggers,
since each occupies its own holder's single ability slot (a mon can't simultaneously BE
the Magician/Pickpocket holder AND a Mold Breaker holder). This flag would only become
reachable once a Knock-Off/Thief/Covet-style MOVE exists, whose user could hold Mold
Breaker while targeting a DIFFERENT, Sticky-Hold-holding mon — none of those moves exist
in this project's roster yet (confirmed via grep), so this is untested-but-implemented
(the `breakable` field is already correctly set and `effective_ability_id` already
supports the `attacker` parameter that a future move would need to pass), not a
silently-dropped check.

`CanStealItem`'s further exemptions (Mail, Enigma Berry, species-form-change items,
Z-Crystals, Paradox Booster Energy, Ogerpon masks — `battle_util.c` L8686-8708) and
`TrySymbiosis`'s further exclusions (already-recorded-stolen no-re-trigger, Eject
Button/Eject Pack, gem-boost consumption, berry-damage-reduction consumption) are NOT
modeled — none of Mail, Z-moves, Mega/form-change items, Paradox forms, Ogerpon, gems, or
Eject Button/Pack exist anywhere in this project, matching the established "known gap,
doesn't apply since the mechanic doesn't exist" convention rather than silently dropping
a real check.

### New infrastructure

- `AbilityManager._try_steal_item(stealer, victim, ng_active) -> bool` — the shared
  primitive described above.
- `AbilityManager.try_magician(attacker, target, damage, ng_active) -> bool` — new
  top-level, attacker-keyed function.
- `AbilityManager.try_symbiosis(mon, ally, ng_active) -> bool` — new top-level function;
  `ally == null` (singles) is the exact value `BattleManager._get_ally` already returns
  there, matching the zero-extra-plumbing precedent `[M17c]`'s Hospitality and `[M17h]`'s
  Receiver both established.
- Pickpocket added as a new branch inside the EXISTING `try_contact_effects` dispatch
  (defender-keyed, contact-gated) — a new `"pickpocket_stole"` result key.
- New `BattleManager.item_transferred(from_mon, to_mon, item)` signal, mirroring
  `[M17h]`'s `ability_changed`/`[M16e]`'s `type_changed` shape.
- New `BattleManager._try_symbiosis(mon)` wrapper, called from exactly ONE new site:
  inside `_consume_item` itself — the single existing choke point every item consumption
  in this project already routes through (every berry/Lum-Berry site calls
  `_consume_item`), so this one addition automatically covers every existing consumption
  path. Also called directly after Pickpocket's steal (checking the mon that just lost
  its item, i.e. the attacker) and after Magician's steal (checking the target) in
  `_do_damaging_hit`, since those two remove an item WITHOUT going through
  `_consume_item` (a transfer, not a one-use consumption).

### Testing / Regression

New `m17j_test.gd`/`.tscn`: 48/48 assertions across 9 sections — ability data
spot-checks (including Sticky Hold's `breakable=true`); Pickpocket direct unit tests
(steal on contact, no-op when holder already has an item, no-op non-contact, no-op zero
damage, no-op attacker-has-no-item, non-holder no-op); Magician direct unit tests
(steal on a non-contact damaging hit, no-op when holder already has an item, no-op zero
damage, no-op when target has no item, non-holder no-op, and a **type-immunity-precedes-
ability-logic** test using a real `DamageCalculator.calculate()` call — Ground-type
Earthquake vs. a Flying-type defender — confirming the 0-damage early return, not a
hand-set `damage=0` stand-in); Symbiosis direct unit tests (ordinary give, singles
no-op, no-item-to-give no-op, receiver-already-has-item no-op, non-Symbiosis-ally no-op);
full-battle integration for Pickpocket; **Sticky Hold blocking Pickpocket in a full
battle** (with the source-verified role correction — Sticky Hold on the ATTACKER being
stolen from, not "the defender" as a surface reading of the ability's role might suggest,
since Pickpocket's holder is always the one hit); full-battle Magician; a chained
full-battle doubles scenario where an opposing Magician holder steals a player mon's item,
which then triggers Symbiosis (held by that mon's ally) to hand over its own item —
exercising the real `_do_damaging_hit`-driven removal path rather than a synthetic
item-loss; and Neutralizing Gas suppression of all three trigger abilities.

Full regression (direct foreground bash sweep, standard `pkill`/`timeout` discipline,
plus the flaky-test fix and `switch_test.tscn` check documented in the addendum above):
all 30 prior suite files unchanged and still passing, plus the new `m17j_test` at
48/48 (stable across 6 consecutive reruns, including the doubles-targeted chained
scenario). Total across all 31 `.tscn` files (`battle_test.tscn` remains narrative-only):
1584 prior + 48 = **1632**, 0 failures.

- 2026-07-03.

### Next tier

Section 11's next proposed tier, **M17k — Priority-move-block check (new infra) +
Dazzling/Queenly Majesty/Armor Tail**, was re-checked against Section 13's full exclusion
sweep before naming it here (the same discipline every prior tier's Step 0 has applied
to its own list) — none of the three appears anywhere in Section 13.1-13.4, so no
correction is needed to Section 11's original three-ability grouping.

## [M17k] Priority-move-block check (new infrastructure) — Dazzling / Queenly Majesty / Armor Tail

Scoping source: `docs/m17_recon.md` Section 11's M17k proposal ("Priority-move-block
check (new infra) + Dazzling/Queenly Majesty/Armor Tail. New 3-ability tier (flag #14),
small and self-contained."). Sixth genuinely new-infrastructure tier in M17, after
`[M17f]`'s trapping check, `[M17g]`'s suppression plumbing, `[M17h]`'s copy/overwrite
plumbing, `[M17i]`'s switch-out trigger hook, and `[M17j]`'s item-transfer primitive.

### Step 0 — finalized ability list

**Queenly Majesty (214), Dazzling (219), Armor Tail (296)** — all three canonical IDs
verified directly (literal values, not symbolic) against
`include/constants/abilities.h`; none appear anywhere in Section 13.1-13.4, so no
correction was needed to Section 11's original three-ability grouping.

Confirmed from source, not assumed, that the three are genuinely identical in mechanic
(the task explicitly flagged this as worth verifying rather than taking for granted):
`IsDazzlingAbility` (battle_move_resolution.c L1499-1509) is the literal shared
dispatch — `case ABILITY_DAZZLING: case ABILITY_QUEENLY_MAJESTY: case ABILITY_ARMOR_TAIL:
return TRUE;` — all three route through the exact same `CancelerPriorityBlock` check
with no per-ability branching anywhere. The only difference is flavor/holder species,
matching the recon's framing precisely with no subtle real difference found this time
(unlike some prior "obviously identical" groupings this project has caught real
divergence in).

### The exact block mechanism

- **Execution-time gate (fails), not selection-time rejection.** Source:
  `CancelerPriorityBlock` (battle_move_resolution.c L1511-1548) is one of the
  "attacker canceler" functions dispatched from `DoAttackCanceler`'s
  `sMoveSuccessOrderCancelers` array (L2420-2448) — the move IS chosen normally by the
  attacker, and THEN fails at execution time (`gBattlescriptCurrInstr =
  BattleScript_PokemonCannotUseMove; return CANCELER_RESULT_FAILURE;`). This is the
  same shape as this project's existing "chosen, then fails" pattern (e.g. Roar's
  `no_switch_target`), not the `move_skipped`-style pre-move cancellation used for
  sleep/freeze/paralysis/Disable.
- **Ordering confirmed relative to M16d/M16e's priority/turn-order work.** `[M16d]`'s
  Trick Room and `[M16e]`'s Pursuit both touch *turn-order/speed-sorting* — this tier
  touches something structurally different: not WHEN a move executes relative to other
  actions, but whether a chosen move is allowed to execute AT ALL once its turn comes
  up. `sMoveSuccessOrderCancelers`'s fixed array order confirms `CANCELER_PRIORITY_BLOCK`
  (L2434) is dispatched strictly BEFORE `CANCELER_ACCURACY_CHECK` (L2447) — this
  project's `AbilityManager.blocks_priority_move` check is inserted at the exact
  equivalent point in `_phase_move_execution`, immediately before the existing
  `StatusManager.check_accuracy` call and after the Pursuit power-doubling block. No
  changes to `_phase_priority_resolution`'s `_turn_order.sort_custom` comparator were
  needed or made — priority-BRACKET sorting (`[M16d]`) and Pursuit's turn-order
  interception (`[M16e]`) are both completely unaffected by this tier.
- **Gated on `move.priority > 0` only.** Source: `if (priority <= 0 ...) return
  CANCELER_RESULT_SUCCESS;` — a priority-zero or negative-priority move is never
  blocked, confirmed via a dedicated Tackle (priority 0) test that still deals real
  damage against a Dazzling holder.
- **SIDE-WIDE, not holder-only — confirmed from source, matching the recon's own
  framing** ("blocks priority moves targeting the user OR AN ALLY"). Source's loop
  iterates every battler on the OPPOSING side of the attacker (skipping the attacker's
  own allies) and blocks the move if ANY of them holds one of the three abilities —
  it does not check whether that specific battler was the move's chosen target. This
  project models the same behavior by checking both `defender` (the move's actual
  target) and `defender_ally` (that target's doubles partner, via the existing
  `_get_ally` helper) rather than a full N-battler generic loop, since this project's
  doubles model is always exactly 2 combatants per side. Verified with a dedicated
  full-battle doubles test: the move's direct target holds no ability at all, but its
  ally holds Dazzling, and the priority move still fails.
- **Does NOT affect the holder's own priority moves.** The function is only ever
  consulted with the OPPOSING side's ability holder(s) as `defender`/`defender_ally` —
  an attacking Dazzling holder's own Quick Attack is never checked against itself.
  Verified with a dedicated test (a Dazzling-holding attacker's own priority move deals
  real damage against a plain, non-Dazzling-holding defender).
- **Field-targeting-move exclusion confirmed non-applicable, not modeled as new
  infrastructure.** Source excludes `moveTarget == TARGET_FIELD ||
  TARGET_OPPONENTS_FIELD` (field-wide moves like Trick Room/Spikes/Stealth Rock aren't
  "aimed at" a specific battler, so can't be blocked). This project has no generic
  move-target-type enum — checked directly whether any of its three field-targeting
  moves (`is_trick_room`/`is_spikes`/`is_stealth_rock`) has positive priority: Trick
  Room is -7, both hazards are 0 (unset, defaulting to 0) — none qualifies, so
  `move.priority > 0` alone already excludes all of them. A confirmed-non-applicable
  simplification, not an assumed one.
- **`breakable = TRUE` on all three, genuinely reachable here.** Source:
  `src/data/abilities.h` L1640-1645/L1677-1682/L2296-2301. Unlike Sticky Hold's
  non-applicable `breakable` flag in `[M17j]` (where the ability being bypassed and the
  potential Mold-Breaker holder could never be different battlers), here the attacker
  attempting the priority move and the Dazzling-family holder are ALWAYS different
  battlers — a completely ordinary, immediately reachable Mold-Breaker-bypass case.
  Threaded through via `effective_ability_id`'s existing `attacker` parameter; verified
  with a dedicated unit test (a Mold-Breaker-holding attacker bypasses Dazzling's
  block).

### `AbilityData` field check, per the `[M17h]`-established discipline

Checked `AbilityData` in full before writing any code. No dormant field applies —
priority-move-blocking is a genuinely new concept, unrelated to the six existing
ability-copy/suppression fields. Sticky-Hold-style, this is correctly a direct
ability-ID check (`_is_dazzling_family`) rather than a data field, the same precedent
`[M17f]`'s trapping check (`is_trapped`) and `[M17j]`'s Sticky Hold check
(`_try_steal_item`) both already established for concepts with no matching dormant
field.

### New infrastructure

- `AbilityManager._is_dazzling_family(id) -> bool` — mirrors source's
  `IsDazzlingAbility` directly.
- `AbilityManager.blocks_priority_move(defender, defender_ally, attacker, move,
  ng_active) -> bool` — the query function, checked at the confirmed execution-time
  trigger point.
- Wired into `BattleManager._phase_move_execution`, immediately before the existing
  accuracy check: on a block, emits `move_effect_failed(attacker, "priority_blocked")`
  and `ability_triggered(defender, "dazzling_family")`, then the same
  `move_executed(attacker, defender, move, 0)` /
  `attacker.last_move_used = move` / turn-advance shape already used by Roar's
  no-switch-target fail path.

### Testing / Regression

New `m17k_test.gd`/`.tscn`: 26/26 assertions across 7 sections — ability data
spot-checks (all three `breakable=true`); `blocks_priority_move` direct unit tests (each
of the three blocking Quick Attack individually, priority-zero non-block, non-holder
no-op, side-wide ally-holds-it-but-target-doesn't, a fainted ally does NOT extend
protection, Mold Breaker bypass, a null-attacker sanity check confirming no bypass
context means no bypass, Neutralizing Gas suppression); full-battle priority-move-blocked
(Quick Attack vs. a Dazzling holder); full-battle priority-zero-not-blocked (Tackle vs.
the same holder, real damage dealt); full-battle side-wide doubles (target has no
ability, its ally holds Dazzling, the priority move still fails); the holder's own
priority move unaffected (real damage dealt); and a negative control (an ordinary
Pokémon with no ability blocks nothing). Stable across 7 consecutive reruns.

Full regression (direct foreground bash sweep, standard `pkill`/`timeout` discipline):
baseline reconfirmed exactly at 31 `.tscn` files, 1632 total assertions, 0 failures —
no drift this time (unlike the M17i→M17j handoff). All 31 prior suite files unchanged
and still passing, plus the new `m17k_test` at 26/26. Total across all 32 `.tscn` files:
1632 prior + 26 = **1658**, 0 failures.

- 2026-07-03.

### Next tier

Section 11's next proposed tier, **M17l — Doubles-redirect-adjacent + doubles-aura
abilities not already scheduled**: Lightning Rod, Storm Drain, Telepathy, Friend Guard,
Propeller Tail, Stalwart (6 abilities, all touching the existing M14a doubles targeting
system) — re-checked against Section 13's full exclusion sweep before naming it here
(the same discipline every prior tier's Step 0 has applied) — none of the six appears
anywhere in Section 13.1-13.4, so no correction is needed to Section 11's original
six-ability grouping.

## [M17l] Doubles-redirect/aura abilities — Lightning Rod / Storm Drain / Friend Guard / Telepathy / Propeller Tail / Stalwart

Scoping source: `docs/m17_recon.md` Section 11's M17l proposal ("Doubles-redirect-adjacent
+ doubles-aura abilities not already scheduled. Lightning Rod/Storm Drain (original,
type-effectiveness + redirect), Telepathy, Friend Guard, Propeller Tail/Stalwart
(redirect-ignore pair). Moderate, all touch the existing M14a doubles targeting
system."). Unlike `[M17f]` through `[M17k]`, this tier's task explicitly asked to
VERIFY rather than assume "no new infrastructure needed" going in, given five
consecutive new-infra tiers preceded it — verified directly: no new infrastructure was
needed. Every mechanic reuses an existing pipeline hook (see "New infrastructure"
below).

### Step 0 — finalized ability list

**Lightning Rod (31), Storm Drain (114), Friend Guard (132), Telepathy (140), Propeller
Tail (239), Stalwart (242)** — all six canonical IDs verified directly (literal, not
symbolic) against `include/constants/abilities.h`; none appear anywhere in Section
13.1-13.4, so no correction was needed to Section 11's original six-ability grouping —
the first M17 sub-tier since `[M17d]` where Step 0 found nothing to correct at all.

### Two genuinely different mechanic shapes, plus a separate exemption/reduction pair

Per this tier's own task framing (don't force these into one pattern):

- **Lightning Rod (31) / Storm Drain (114) — redirect-TRIGGER, defender-side.** An
  Electric-type (Lightning Rod) or Water-type (Storm Drain) move gets: (1) redirected
  from its original target onto the ability holder, if the holder is that target's
  doubles partner and the original target doesn't already hold the matching ability
  itself; (2) fully absorbed (0 damage) plus a Sp. Atk +1 boost, whenever the holder IS
  hit (whether by direct targeting or by the redirect). Source: `CanAbilityAbsorbMove`
  (battle_util.c L2258-2265) dispatched via `AbsorbedByStatIncreaseAbility`
  (L2328-2340) for the absorb+boost half; `HandleMoveTargetRedirection`
  (battle_move_resolution.c L822-888) for the redirect half — confirmed these are two
  separate source functions, not one, even though they're the same ability. The
  absorb+boost half applies identically in singles (verified with a dedicated test) —
  redirect itself is simply moot there (only one possible target), not disabled by any
  special-case code.
- **Propeller Tail (239) / Stalwart (242) — redirect-BYPASS, attacker-side — the
  OPPOSITE direction.** The ATTACKER's own moves ignore ALL redirection (both Follow
  Me/Rage Powder AND Lightning Rod/Storm Drain-style ability redirect) when the
  attacker holds either. Source: `IsAffectedByFollowMe`'s own gate
  (battle_move_resolution.c L809-810) and `HandleMoveTargetRedirection`'s redirect-loop
  condition (L872-873) both exclude a Propeller-Tail/Stalwart-holding attacker
  identically. Confirmed from source — not assumed — that these two are genuinely
  mechanically identical (the task explicitly flagged this as worth verifying): both
  gates cite the exact same two ability checks side by side with no per-ability
  branching anywhere.
- **Telepathy (140) — a separate damage-EXEMPTION, unrelated to redirection.** Full
  immunity (0 damage) to a damaging move whose target is the holder's own ATTACKING
  ALLY (doubles only). Source: `battle_util.c` L8201-8206, checked via `battlerDef ==
  BATTLE_PARTNER(battlerAtk)` — **a source-verified correction worth flagging**: this
  is NOT gated on the move being a spread move specifically, despite the ability's own
  "prevents ally spread-move damage" flavor text and this tier's own task framing. In
  practice it's only ever reachable via a spread move (normal move selection never
  deliberately aims a damaging move at one's own ally), but the underlying check itself
  is broader than that — implemented and tested exactly as source has it (a
  single-target Tackle deliberately aimed at the holder's own ally, via
  `queue_move_targeted`, is blocked identically to how a spread move would be).
- **Friend Guard (132) — a separate damage-REDUCTION, unrelated to redirection.** ×0.75
  damage reduction for the DEFENDER when the DEFENDER'S ALLY holds Friend Guard (not
  the holder's own incoming damage — verified with a dedicated test showing the
  Friend-Guard-holder's own incoming damage is unreduced while its ally's is). Source:
  `GetDefenderPartnerAbilitiesModifier` (battle_util.c L7460-7478).

### Redirect precedence (this project already has Follow Me/Rage Powder — M14b)

Checked directly per this tier's task instruction rather than assuming: this project
already implements Follow Me/Rage Powder (`[M14b]`, `_follow_me_targets`). Source
confirms Follow Me/Rage Powder take precedence — `HandleMoveTargetRedirection` only
evaluates the Lightning Rod/Storm Drain ability-redirect branch when
`gSideTimers[side].followmeTimer == 0` (i.e. Follow Me didn't already redirect this
hit). This project's implementation follows the identical precedence:
`_phase_move_execution`'s existing Follow Me block now also gates on `not
AbilityManager.bypasses_redirection(attacker, ng_active)` (so Propeller Tail/Stalwart
bypass Follow Me too, matching source), and the new Lightning Rod/Storm Drain redirect
check is nested inside that same block, only evaluated `if not followed_this_hit`.

**Not modeled** (a known, narrower gap, explicitly flagged rather than silently
dropped): source's `B_REDIRECT_ABILITY_ALLIES >= GEN_4` quirk, which also lets
Lightning Rod/Storm Drain redirect a move used by the ATTACKER's OWN ally onto that
ally (not just redirect-onto-the-original-target's-ally, the case this project
implements). This project's established defender/defender_ally-pair convention (used
throughout M17a/c/l) models only the standard, overwhelmingly common scenario — an
opposing attacker's move aimed at one of two Pokémon on the DEFENDING side gets pulled
onto the other Pokémon on that same side — not a full N-battler search across both
sides. Would need a broader architecture change to model the attacker's-own-ally case,
out of this tier's scope.

### `AbilityData` field check, and the Mold-Breaker interaction found along the way

Checked `AbilityData` before writing any code, per the `[M17h]`-established discipline
— no dormant field applies (this tier's mechanics reuse the existing `breakable` field
directly, not a new one). Source-verified `breakable = TRUE` on Lightning Rod, Storm
Drain, Friend Guard, and Telepathy (`src/data/abilities.h`), and confirmed all four are
genuinely, immediately reachable Mold-Breaker-bypass cases (attacker and holder are
always different battlers) — wired through `effective_ability_id`'s existing `attacker`
parameter throughout, verified with dedicated unit tests for Lightning Rod's absorb
AND its redirect (a Mold-Breaker-holding attacker's move is neither absorbed nor
redirected — correctly reading `cv->abilities[]` as suppressed throughout the entire
redirect-resolution function, matching source's single shared `GetBattlerAbility`
chokepoint). Propeller Tail/Stalwart correctly carry NO `breakable` flag — they're the
ATTACKER's own ability being consulted, not a defensive check Mold Breaker has any
bearing on.

### New infrastructure

**None was needed** (verified, not assumed, per this tier's explicit task instruction).
Every mechanic hooks into an existing pipeline stage:
- `AbilityManager.absorbs_move_type`/`blocks_ally_damage` are new functions, but slot
  into `DamageCalculator.calculate`'s EXISTING early ability-immunity gate group
  (alongside `[M17g]`'s Levitate check) with zero new parameters.
- `AbilityManager.friend_guard_modifier_uq412` reuses the EXISTING `defender_ally`
  parameter `[M17c]`'s Flower Gift already established.
- Telepathy's `is_attacker_ally` check reuses the EXISTING `ally` parameter `[M17a]`'s
  Battery/Power Spot/Steely Spirit already established (`defender == ally` is exactly
  source's own check) — no new parameter threaded through at all.
- `AbilityManager.resolve_redirect_target`/`bypasses_redirection` slot into the
  EXISTING Follow Me/Rage Powder redirect block in `_phase_move_execution` (`[M14b]`),
  extending it rather than adding a parallel targeting-resolution path.
- The Sp. Atk +1 boost signal (`"absorbed_stat_boost"` result key) follows the
  established `result.get(key, default)` convention (`[M12]`'s
  `defender_item_consumed`) rather than requiring every `calculate()` return branch to
  carry the new key.

### Testing / Regression

New `m17l_test.gd`/`.tscn`: 45/45 assertions across 12 sections — ability data
spot-checks (breakable flags correct for all six); Lightning Rod/Storm Drain direct
unit tests (`absorbs_move_type` type-matching, `resolve_redirect_target`'s
already-absorbing-original-target/no-ally/fainted-ally/Mold-Breaker-bypass/
Neutralizing-Gas-suppression cases); Telepathy direct unit tests (blocks only when
`is_attacker_ally`, non-holder no-op, power-0 move never blocked); Friend Guard direct
unit tests (0.75x reduction, no-ally/wrong-ability/fainted-ally no-ops, the
attacker==defender confusion-shape guard); Propeller Tail/Stalwart direct unit tests;
full-battle doubles integration for Lightning Rod and Storm Drain (redirect + Sp. Atk
+1, verified via turn-1-specific event snapshots after catching a real signal-snapshot
test bug — see below); Lightning Rod's direct-hit absorb+boost confirmed working
identically in singles; Telepathy blocking an ally's attack but not an opponent's, in
the same full battle; Friend Guard reducing the ally's damage below what the holder
itself takes from an identical attacker, deterministically (0.75× max always undercuts
the 0.85× minimum random-roll floor for equal base stats); Propeller Tail bypassing
Lightning Rod's redirect in a full battle (the tier's key cross-ability interaction
test); and a negative control (an ordinary Pokémon redirects/exempts/reduces/bypasses
nothing). Stable across 8 consecutive reruns after the fix below.

**A real test-authoring bug was caught and fixed during this tier**, the same class of
issue `[M17j]`'s addendum documented for `switch_test.tscn`'s Roar section: two
negative assertions (`move_executed_events.any(...)` checking a defender was "never"
hit by a specific attacker) read `move_executed_events` accumulated across the ENTIRE
battle, not just the queued turn-1 action under test. Since each relevant attacker in
this tier's full-battle tests has only ONE move, once the ORIGINAL redirect target
eventually fainted in later turns, that same attacker's later auto-selected actions
legitimately (and correctly) targeted whichever opponent remained — including the
ability holder itself — producing a real, later, unrelated `move_executed` event that
made the "never" assertion fail intermittently. Caught on the very first test run (not
latent — `S11.02` failed immediately). Fixed by filtering to each attacker's FIRST
recorded event (`.filter(...)[0]`), which deterministically corresponds to the queued
turn-1 action, matching this project's signal-snapshot testing convention precisely.

Full regression (direct foreground bash sweep, standard `pkill`/`timeout` discipline):
baseline reconfirmed exactly at 32 files/1658 assertions before starting (no drift).
All 32 prior suite files unchanged and still passing, plus the new `m17l_test` at
45/45. Total assertions across all 33 `.tscn` files: 1658 prior + 45 = **1703**, 0
failures.

- 2026-07-03.

### Next tier

Section 11's next proposed tier, **M17m — Type-effectiveness-pipeline batch**, is
explicitly flagged by the recon itself as the highest-risk remaining tier in M17: Wonder
Guard (unchanged despite type effectiveness — recon's own "highest risk" flag), Scrappy,
Volt Absorb, Water Absorb, Sap Sipper, Flash Fire, Overcoat, Normalize (+ the
Refrigerate/Pixilate/Aerilate/Galvanize "-ate" family sharing its exact move-mutation
mechanism), Motor Drive, Well-Baked Body, Earth Eater, Mind's Eye — roughly 15
abilities, not yet re-verified against Section 13 (that re-verification is M17m's own
Step 0 job, not done here). Worth flagging now, discovered directly while implementing
this tier: **Volt Absorb, Water Absorb, Sap Sipper, Flash Fire, Motor Drive, and
Well-Baked Body all share the EXACT SAME source dispatch function**
(`CanAbilityAbsorbMove`, battle_util.c L2235-2340) that this tier's Lightning Rod/Storm
Drain already partially extended via `AbilityManager.absorbs_move_type` — M17m should
extend that existing function (or its underlying pattern) rather than build a parallel
one. Also worth flagging: Wonder Guard's own check (battle_util.c L8201, right next to
Telepathy's check this tier already implemented) lives in the exact same
early-immunity-gate function this tier's Telepathy check now occupies in
`DamageCalculator.calculate` — the hook point is already proven out, but Wonder Guard's
OWN logic (block every non-super-effective hit) is a substantially different and
higher-risk shape than anything implemented so far in M17, matching the recon's own
warning.
