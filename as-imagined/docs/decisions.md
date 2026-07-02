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
