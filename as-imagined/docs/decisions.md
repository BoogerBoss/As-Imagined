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

- Source: `src/battle_script_commands.c` :: `CanFireMoveThawTarget` (L11036–11038): `B_HIT_THAW >= GEN_3 && moveType == TYPE_FIRE && GetMovePower(move) != 0`
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

- Source: `src/battle_script_commands.c` :: `CanFireMoveThawTarget` (L11036–11038)
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

## [M8] Speed Boost: BattlerJustSwitchedIn treatment

- Source: `battle_util.c` :: `AbilityBattleEffects(ABILITYEFFECT_ENDTURN, ...)` (L3605):
  `if (!BattlerJustSwitchedIn(battler))` guard before applying the +1 Speed.
- Behavior: Since M8 has no mid-battle switching, `BattlerJustSwitchedIn` is treated as always
  false (never true). Speed Boost fires every end-of-turn without restriction. If switching is
  added later, this guard must be revisited.
- Notes: 2026-06-26.

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
- Status move on fresh target: +2 (IncreasePoisonScore/etc in AI_CalcMoveEffectScore).
- Notes: 2026-06-26.

## [M10] Trainer AI — switch thresholds (source: battle_ai_switch.c)

- `ShouldSwitchIfAllMovesBad` (L481): all damaging moves type-immune → 100% switch.
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
