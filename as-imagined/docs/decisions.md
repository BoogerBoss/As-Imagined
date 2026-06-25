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

- Source: `src/battle_move_resolution.c` L172–186
- Behavior:
  - Each pre-move check: `RandomPercentage(RNG_FROZEN, 20)` = 20% thaw. Implemented as `randi() % 100 < 20`.
  - If thaws → status cleared, **can use move that same turn**.
  - If stays frozen → can't move.
  - Moves that thaw (`MoveThawsUser`) skip the freeze check — not in M3 scope (Flame Wheel, Sacred Fire, etc. are M4+ move effects).
- Type immunity: Ice-types cannot be frozen (L5342). Sun weather also prevents freeze but weather is not in M3 scope.
- Notes: 2026-06-24.

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

## [M3] Pre-move check order: sleep → freeze → confusion → paralysis

- Source: `src/battle_move_resolution.c` canceler dispatch table (verified order: `CancelerSleep` before `CancelerFrozen` before `CancelerConfused` before `CancelerParalyzed`)
- Behavior: Checked in that order. Each canceler either fails early (returns CANCELER_RESULT_FAILURE) or passes through. A confusion self-hit returns before the paralysis check — so a confused+paralyzed Pokémon that would self-hit does so without triggering the full-para roll.
- Notes: Flinch, taunt, disable, choice lock, etc. are later in the chain (M4+). 2026-06-24.

## [M1] PokemonSpecies.learnset: defined now, empty for Milestone 1

- Source: `include/pokemon.h`, `struct SpeciesInfo`, field `levelUpLearnset`
- Behavior: `PokemonSpecies` has `learnset: Array[Dictionary]` with entries
  `{"level": int, "move_id": int}`. Populated with real data in Milestone 4+.
  Milestone 1 test Pokémon have their moves assigned directly on `BattlePokemon`
  rather than derived from the learnset.
- Notes: 2026-06-24.
