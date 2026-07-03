# Emerald Battle Engine Clone — Project Guide for Claude Code

## What this project is

A standalone recreation of Pokémon Emerald's turn-based battle system in
Godot 4.x, using GDScript, based on the **expanded/upgraded battle engine**
(DizzyEgg's battle engine upgrade, as found in `pokeemerald_expansion`) rather
than vanilla Gen III mechanics. This means modern conveniences and later-gen
mechanics are in scope and expected — Physical/Special split, newer abilities,
newer moves, etc. — not just what shipped in the original 2004 release.

This is a separate project from my other Godot project (a farming/action-RPG
hybrid). Do not assume any code, autoloads, or conventions from that project
carry over here unless I explicitly say so.

## Ground truth / reference

The authoritative source for "what should this do" is the
`pokeemerald_expansion` repository (DizzyEgg / ROM Hacking Hideout community),
NOT the Bulbapedia prose description and NOT vanilla `pret/pokeemerald` —
vanilla Emerald is missing the mechanics this project wants (Physical/Special
split, newer movepool, newer abilities), so it's not the right reference here.

- Primary reference repo: `pokeemerald_expansion` (battle engine upgrade
  branch / merged `master`)
- Located at: `reference/pokeemerald_expansion` (relative to project root)
  (clone this in if not present — see Setup below)
- Key files to consult when implementing a mechanic:
  - `src/battle_script_commands.c` — move/effect execution logic
  - `src/battle_util.c` — damage calc helpers, status application
  - `src/battle_ai_script_commands.c` and `src/battle_ai_main.c` — trainer AI
  - `src/data/moves_info.h` / similar — move data tables
  - `src/data/abilities.h` — ability definitions
  - `include/constants/battle_move_effects.h` — move effect IDs

When implementing any mechanic, the workflow is: **look at the source logic
first, then port the behavior to GDScript** — don't guess from memory of "how
Pokémon battles work," since even the expanded engine has specific numeric
constants and edge cases worth confirming against source rather than assuming.

If a mechanic's source location is unclear, search the repo structure before
implementing, or ask me to confirm before making something up.

## Tech stack

- **Engine:** Godot 4.x, Standard edition (GDScript, not C#/.NET)
- **Why GDScript:** consistency with my other Godot project, plus standard
  edition keeps Web export available if I ever want it
- **Data format:** Godot `Resource` (`.tres`) or plain `.json` for
  Pokémon/move/ability/item data — decide and lock this in during Milestone 1,
  don't mix formats later
- **No external plugins/addons** unless I approve one explicitly

## Architecture overview

```
scripts/
  data/           # Data resource classes (PokemonSpecies, MoveData, AbilityData, ItemData)
  battle/
    core/         # BattleState machine, BattlePokemon (runtime instance), turn order/priority resolver, damage calculator
    moves/        # Move effect implementations, tiered by complexity (see Build Order)
    abilities/    # Ability hook implementations
    ai/           # Trainer AI decision logic
  ui/             # Battle HUD, menus, text box controller
scenes/
  battle/         # Battle scene(s), UI scene(s)
data/
  pokemon/        # Per-species data files
  moves/          # Per-move data files
  abilities/      # Per-ability data files
  items/          # Per-item data files
reference/
  pokeemerald_expansion/  # Cloned source, read-only reference — never edit
docs/             # Design notes, decisions log, mechanic verification notes
```

### Core battle flow (state machine)

```
BATTLE_START
  → MOVE_SELECTION (both sides choose action: move / switch / item / run)
  → PRIORITY_RESOLUTION (determine action order: priority bracket > speed > random tiebreak)
  → ACTION_EXECUTION (loop per resolved action)
      → PRE_MOVE_CHECKS (sleep/freeze/paralysis/confusion checks, flinch)
      → MOVE_EXECUTION (accuracy check → effect application → damage calc → secondary effects)
      → FAINT_CHECK
  → END_OF_TURN (weather damage, status damage (burn/poison), held item effects, etc.)
  → FAINT_CHECK / SWITCH_PROMPT
  → BATTLE_END_CHECK (loop back to MOVE_SELECTION or end battle)
```

This skeleton should be built and tested with simple placeholder moves
(struggle-only or single tackle-like move) BEFORE any real move data is added.
Get the loop solid first.

## Build order (milestones — do not skip ahead)

1. **Data schema + state machine skeleton**
   Define `PokemonSpecies`, `MoveData`, `AbilityData`, `ItemData` resource
   classes. Build the `BattlePokemon` runtime class (species + current
   HP/stats/status/PP). Build the empty state machine above with one dummy
   move so two Pokémon can "battle" with no real mechanics yet — just to
   prove the loop works and a winner is declared.

2. **Damage formula + type chart**
   Implement the damage formula exactly as the expanded engine computes it
   (base power, attack/defense stat use via the Physical/Special split,
   STAB, type effectiveness, random factor, critical hits). Build the full
   18-type effectiveness chart (including Fairy). Verify against known
   damage calc examples from the source or community damage calculators
   that target this engine.

3. **Status conditions**
   Burn, poison, toxic, paralysis, sleep, freeze, confusion — implement each
   condition's application rules, turn-start/turn-end effects, and cure
   conditions, matching the expanded engine's specifics.

4. **Move effects — Tier 1 (simple damage)**
   Implement ~15–20 simple attacking moves with no secondary effect, across
   different types, to validate the damage/type system against real data.

5. **Move effects — Tier 2 (stat changes & status infliction)**
   Stat-modifying moves (Swords Dance, Growl, etc.) and status-inflicting
   moves (Thunder Wave, Toxic, etc.).

6. **Move effects — Tier 3 (multi-turn, recoil, drain, fixed damage)**
   Solar Beam / Dig / Fly style charge-and-release moves, recoil moves,
   drain moves (Giga Drain), fixed-damage moves (Seismic Toss, Dragon Rage).

7. **Move effects — Tier 4 (one-off / unique mechanics)**
   Counter, Destiny Bond, Metronome, Substitute, etc. — the long tail.

8. **Abilities**
   Tiered similarly: passive stat modifiers first, then switch-in effects,
   then complex interactions (weather-setting abilities, contact-based
   abilities like Static).

9. **Trainer AI**
   Port the expanded engine's actual rule-based decision logic from
   `battle_ai_script_commands.c` / `battle_ai_main.c`.

10. **UI / animation layer**
    Battle HUD, health bars, menu navigation, text box sequencing, basic move
    animations. Deliberately last — logic must be solid first so the UI has
    something correct to display.

    

Do not jump to UI or "make it look like the game" before the move/damage/
status core is working — visuals are the easiest part to get wrong-but-
convincing, which masks logic bugs.

## Build order — Phase 2 (post-core-engine expansion)

These milestones build on the complete M1–M10 core. Same rules: one milestone
at a time, verify against source, regression-sweep before moving on.

11. **Weather**
    Field-wide weather state (rain / sun / sandstorm / hail). End-of-turn tick
    following the same burn/poison trigger pattern established in M3. Damage
    modifiers in `DamageCalculator`: rain ×1.5 Water / ×0.5 Fire; sun the
    reverse; sand and hail deal end-of-turn chip to non-immune types. Un-stub
    the weather-setting abilities (`Drizzle`, `Drought`) left as placeholders in
    M8. Weather-aware AI scoring (explicitly deferred in M10's `decisions.md`).

12. **Held items**
    `ItemData` exists from M1 but is unpopulated. Build item mechanics before
    item AI: passive stat items (e.g. Choice Band); single-use consumables
    (berries triggered by HP thresholds, using the same trigger-shape as M8's
    contact abilities); choice-lock items (source already references
    `AI_DoesChoiceEffectBlockMove`, found during M10's source read).

13. **Item AI**
    Extend `TrainerAI` to consider held items in move scoring and switch
    decisions. Source: `battle_ai_items.c` (located but deferred during M10).
    This is a sequel to M10, not new architecture — requires M12 complete first.

14. **Doubles battle support**
    The largest item. Must not start until M11 and M12/M13 are stable and
    verified, since doubles must correctly interact with weather and items. Treat
    as three separate milestone passes with a full regression sweep after each —
    do not collapse into one combined effort.

    - **14a — State machine + turn order for 4 combatants:** spread/ally
      targeting changes core assumptions in `BattleManager`,
      `DamageCalculator`, and every move/ability that currently assumes a
      single attacker/defender pair. Fix the foundations here before touching
      move or AI logic.
    - **14b — Spread moves and ally-targeting effects:** move effects that hit
      multiple targets or interact with the ally slot.
    - **14c — Doubles AI:** source is `ChooseMoveOrAction_Doubles`,
      `AI_FLAG_DOUBLE_BATTLE`, `AI_DoubleBattle` / `AI_AttacksPartner` — all
      located but skipped during M10's source read.

## Working style / instructions for Claude Code

- Work one milestone at a time. Do not implement Tier 3 moves while Tier 1
  is still unverified.
- When implementing a move or ability, state which source file and function
  you're basing the behavior on.
- When a mechanic seems ambiguous or you're not fully certain of the engine's
  specific behavior, stop and ask rather than guessing — call out the
  ambiguity explicitly.
- Write unit-test-style verification scenes/scripts for damage calc and status
  logic as they're built (e.g. a debug scene that runs known move/stat
  combinations and prints expected vs. actual damage), since correctness here
  is the entire point of the project.
- Keep `docs/decisions.md` updated with any mechanic verified against source,
  especially when a constant or rule was ambiguous and required a judgment
  call — so we don't re-litigate it later.
- The scope is "what the expanded engine does," not "whatever I think would
  be cool." If you have an idea for a mechanic or balance change beyond what
  `pokeemerald_expansion` implements, flag it as an idea in `docs/` rather
  than just adding it.

### Testing convention: snapshot via signals, not post-battle state

  This bit M16c and M16d independently (see `docs/decisions.md`), so it's
  captured here as a permanent rule rather than something each milestone
  re-discovers.

  Any Pokémon whose only available move is a **repeatable** effect — a
  side-condition/hazard-setter that can legitimately be re-cast after its
  effect naturally expires or gets cleared, or a toggle like Trick Room — will
  keep re-triggering once the turn's action queue drains and auto-select
  falls back to `moves[0]`, for as many turns as the test battle runs. A test
  Pokémon with no other move WILL cast that move again.

  Consequence: any assertion about "what happened after one specific action"
  must **never** read state (`_side_conditions`, `trick_room_turns`,
  `attacker.stat_stages`, etc.) after `start_battle()` fully returns — by then
  the battle may have run many more turns than intended, re-triggering,
  re-expiring, or re-toggling the exact state under test. Instead, snapshot
  the state by connecting to the relevant signal (`screen_set`,
  `hazard_set`, `trick_room_set`, `move_executed`, etc.) and capturing the
  value at the precise moment the signal fires — guarded to the first
  matching occurrence if the signal could plausibly fire more than once
  during the battle.

  Applies to every future milestone that introduces persistent/toggleable
  battle state (side conditions, field conditions, per-Pokémon volatiles) —
  see `docs/decisions.md`'s `[M16c]`/`[M16d]` entries for worked examples of
  tests that broke this way and how they were fixed.

### Testing convention: lambda-captured scalars are snapshots, not references

  This has already caused real bugs in M16c, M16d, M16e, and M17a — treat it as
  a known, recurring risk from the first draft of any new test, not something
  to catch reactively after a false pass slips through.

  GDScript lambdas capture local variables **by value, at the moment the
  lambda is defined** — not by reference. If a test connects a signal to a
  lambda that reads a local scalar (`int`/`bool`/`float`/`String`), and the
  lambda body then assigns to that variable, the assignment mutates a private
  copy inside the closure. The outer variable the test later reads never
  changes.

  This is dangerous in exactly the same "silent until it isn't" way as the
  signal-snapshot pitfall above: the test still runs, still prints a result,
  and often still passes — a positive-case assertion checking "did this stay
  false" trivially passes even when the mechanism under test is completely
  disconnected, because the outer variable was never going to change anyway.
  The bug only surfaces when a negative-case or discriminator assertion needs
  the captured value to actually flip, which is exactly what happened in
  M17a's Rock Head recoil test: the positive case (no recoil should fire)
  passed for the wrong reason, and only the negative case (recoil SHOULD fire
  for a non-Rock-Head attacker) failed and exposed that the signal handler's
  mutation was never reaching the outer scope.

  Fix: wrap the value in a single-element `Array` and mutate/read index `0`.
  Arrays are captured by reference, so mutations inside the lambda are visible
  to code outside it that holds the same Array.

  ```gdscript
  # WRONG — outer `fired` never becomes true, no matter what the signal does.
  var fired := false
  bm.recoil_damage.connect(func(mon, amount): fired = true)
  bm.start_battle(atk, def)
  _chk("recoil fired", fired == true)   # false pass/fail regardless of behavior

  # RIGHT — Array wrapper is captured by reference.
  var fired := [false]
  bm.recoil_damage.connect(func(mon, amount): fired[0] = true)
  bm.start_battle(atk, def)
  _chk("recoil fired", fired[0] == true)
  ```

  Applies to every test that connects a signal to a lambda and expects the
  lambda to communicate a result back to the enclosing test function — see
  `docs/decisions.md`'s `[M17a]` entry for the worked example of a test that
  broke this way and how it was fixed.

### Testing convention: type immunity precedes ability logic

  This has already caused real bugs in M17b and M17c — treat it as a known,
  recurring risk from the first draft of any new test involving a damaging
  move, not something to catch reactively after a misleading pass or fail
  slips through.

  Type effectiveness is checked before any ability/item logic gets a chance to
  run (see `DamageCalculator.calculate`'s early-return on `effectiveness ==
  0.0`). If a test scenario picks an attacker/defender type pairing that is a
  flat 0× immunity — not just a resistance — for the move being used, the hit
  never connects, damage is always 0, and the ability or item under test never
  actually executes its logic. The scenario looks plausible (a Ghost-typed
  defender to test a Ghost-related damage modifier, a Ground-type move against
  a Flying-type/Levitate holder to test a stat interaction) but is untestable
  by construction.

  This is dangerous in exactly the same "silent until it isn't" way as the two
  conventions above: the test still runs, still produces a result, and can
  still pass or fail in a way that looks reasonable — an assertion comparing
  "modified damage" against "baseline damage" can trivially pass at `0 == 0`
  even though the mechanism under test never fired. The bug only surfaces when
  the assertion actually needs a nonzero difference to hold, which is exactly
  what happened in M17b's Purifying Salt test (a Normal-type defender used to
  measure Ghost-type damage halving — Normal-types are outright immune to
  Ghost-type moves, unrelated to Purifying Salt, so the measured damage was 0
  regardless of the ability) and M17c's Cursed Body integration test (a
  Ghost-type holder hit by a Normal-type move — the same flat immunity, this
  time blocking the hit-reactive dispatch from firing at all).

  Fix: before writing any test scenario involving a damaging move, explicitly
  check the attacker's move type against the defender's type(s) against this
  project's own `TypeChart` and confirm effectiveness is nonzero — don't rely
  on a type pairing "sounding" safe. Unless the mechanism under test is itself
  type-specific, default to a neutral (1×) matchup chosen to have no side
  effects on the mechanic being isolated — the same one-variable-at-a-time
  discipline already used throughout this project's test suites.

  Applies to every test that measures damage, a damage modifier, or a
  hit-reactive effect through an actual `DamageCalculator.calculate` call or a
  full battle — see `docs/decisions.md`'s `[M17b]` and `[M17c]` entries for the
  worked examples of tests that broke this way and how they were fixed.

## Setup

```bash
# From project root
git clone https://github.com/rh-hideout/pokeemerald-expansion reference/pokeemerald_expansion
```

This reference clone is for reading only — never modify it, never build it,
it exists purely to look up exact source logic.

## Current status

- M1 (data schema + state machine skeleton): **COMPLETE** — 2026-06-24
- M2 (damage formula + type chart): **COMPLETE** — 2026-06-24, 24/24 tests pass
- M3 (status conditions): **COMPLETE** — 2026-06-24, 75/75 tests pass
- M4 (Tier-1 move pipeline + freeze-thaw hooks): **COMPLETE** — 2026-06-25, 45/45 tests pass
- M5 (move effects — stat changes & status infliction): **COMPLETE** — 2026-06-25, 78/78 tests pass
- M6 (move effects — multi-turn, recoil, drain, fixed damage): **COMPLETE** — 2026-06-25, 62/62 tests pass
- M7 (move effects — Tier 4 one-off/unique): **COMPLETE** — 2026-06-26, 86/86 tests pass
- M8 (abilities): **COMPLETE** — 2026-06-26, 59/59 tests pass
- M9 (switching mechanics): **COMPLETE** — 2026-06-26, 64/64 tests pass
- M10 (Trainer AI): **COMPLETE** — 2026-06-26, 26/26 tests pass
- M11 (Weather): **COMPLETE** — 2026-06-27, 64/64 tests pass
- M12 (Held Items): **COMPLETE** — 2026-06-27, 60/60 tests pass
- M13 (Item AI): **COMPLETE** — 2026-06-27, 40/40 tests pass (includes M10's 26 + 14 new)
- M14a (Doubles — state machine + turn order for 4 combatants): **COMPLETE** — 2026-06-28, 25/25 tests pass
- M14b (Doubles — spread moves and ally-targeting effects): **COMPLETE** — 2026-06-28, 46/46 tests pass (40 M14a + 9 M14b + B8 fixture fix; all prior suites green)
- M14c (Doubles — AI): **COMPLETE** — 2026-06-28, 46/46 tests pass (C1–C3 added; all prior suites green)
- M15 Task 3 (PP system): **COMPLETE** — 2026-07-01, 26/26 pp_test assertions; all M1–M14 still green
- M15 Task 5 (two-turn moves): **COMPLETE** — 2026-07-01, 32/32 two_turn_test assertions; all M1–M15T3 still green
- M16a (Tier A move effects — RESTORE_HP / FOCUS_ENERGY / GROWTH / OHKO): **COMPLETE** — 2026-07-01, 52/52 m16a_test assertions; all 637 prior assertions still green (689 total)
- M16b (Tier B move effects — MINIMIZE / DEFENSE_CURL / Stomp minimizeDoubleDamage / ROLLOUT (Ice Ball) / MAGNITUDE): **COMPLETE** — 2026-07-02, 55/55 m16b_test assertions; all 857 prior assertions still green (912 total). Note: Stomp's canonical move ID is 23, not 31 (31 is Fury Attack) — corrected after checking `constants/moves.h`; see decisions.md.
- M16c (Tier C move effects — REFLECT / LIGHT_SCREEN / AURORA_VEIL / Brick Break screen-break): **COMPLETE** — 2026-07-02, 60/60 m16c_test assertions; all 912 prior assertions still green (972 total). Introduces `BattleManager._side_conditions[side]`, the first per-side (not per-Pokémon, not per-battle) state — designed for reuse by Trick Room / entry hazards in M16d.
- M16d (Tier D move effects — entry hazards SPIKES / TOXIC_SPIKES / STEALTH_ROCK / RAPID_SPIN / TRICK_ROOM): **COMPLETE** — 2026-07-02, 71/71 m16d_test assertions; all 972 prior assertions still green (1043 total). Hazards reuse `_side_conditions[side]` (new layer-count/bool keys); Trick Room adds `trick_room_turns` as a genuinely per-battle field and is the first mechanic to alter turn order itself (inverts only the speed tiebreak within a shared priority bracket). New `AbilityManager.is_grounded()` helper for Spikes/Toxic Spikes immunity (Stealth Rock deliberately does not use it).
- M16e (Tier E move effects — PURSUIT / PAIN_SPLIT / CONVERSION / CONVERSION_2 / PSYCH_UP / Baton Pass extension): **COMPLETE** — 2026-07-02, 53/53 m16e_test assertions; all 1043 prior assertions still green (1096 total). Pursuit is the first mechanic to reorder turn order for a specific pair of battlers (strikes before an opposing switch resolves) rather than a global rule; reuses M16b's `power_override` for its doubled-power case. Conversion 2 confirmed from source to use the TARGET's last-used-move type, not "last hit the user" (contradicts the move's own flavor text at GEN_LATEST config). Psych Up confirmed to also copy the Focus Energy crit-boost volatile, not just the 7 stat stages. Baton Pass gained the one passable field it was missing (`focus_energy`, added in M16a after M9's original Baton Pass work). **M16 (Tiers A–E) is now fully complete** — 291 new assertions across the 5 sub-milestones, 1096 total across all 19 numbered suites. See `docs/decisions.md`'s consolidated `[M16]` summary entry for the full tier breakdown and the reusable patterns introduced along the way.
- M16 Milestone-End Review (targeted audit, not a new milestone): **COMPLETE, no fixes required** — 2026-07-02. Audited three risk areas: Baton Pass passable-volatiles completeness (no gap — `focus_energy` was the only omission and it was already fixed in M16e; every other M16a–M16e field correctly excluded per source), Conversion 2's last-used-vs-last-hit-by test coverage (implementation was already correct; a genuine testing gap existed and was closed with a direct-conflict discriminator test), and Trick Room × Pursuit turn-order integrity (the two mechanisms are structurally disjoint in `_phase_priority_resolution`'s comparator — no conflict found; added permanent cross-tier coverage). One real but out-of-scope latent bug was discovered and flagged (not fixed): Conversion/Conversion 2's `species.types` mutation is never reset on ANY switch-out (not just Baton Pass), unlike source where the active-battler struct is fully repopulated per switch — see `docs/decisions.md`'s `[M16 Review]` Area 1 for the recommended fix. New `m16e_test` assertions (53→56) plus new `m16_review_test.gd`/`.tscn` (8 assertions); 1107 total across 22 numbered suites, all green.
- Follow-up fixes (three independent small fixes, not a milestone): **COMPLETE** — 2026-07-02. (1) Chilan Berry — wired the previously-unreachable `TYPE_NORMAL` bypass in the resist-berry damage modifier (M12 decisions.md gap I2). (2) Heavy Duty Boots — new `ItemManager.is_hazard_immune()`, wired into `_apply_switch_in_hazards` as one shared gate across Spikes/Toxic Spikes/Stealth Rock, respecting the Toxic-Spikes-Poison-absorb-still-applies nuance (closes the gap flagged in M16d's decisions.md). (3) Conversion/Conversion 2 type-reset bug — found during the M16 Review turned out to be misattributed to the wrong source function (`RESTORE_BATTLER_TYPE` is Mimicry-specific, not general); the actual mechanism is switch-IN repopulation (`CopyMonAbilityAndTypesToBattleMon`/`Cmd_switchindataupdate`), so the fix is a new `BattlePokemon.original_types` cache restored via `BattleManager._reset_mon_type` at the same 5 switch-in call sites M16d's hazards use — not at switch-out as originally guessed. `item_test` grew 63→77, `m16e_test` grew 56→58; 1123 total across 22 numbered suites, all green. Air Balloon (a consumed-on-hit mechanic, a different shape of problem) and the rest of the held-item roster remain deferred to the future M18 milestone — not bundled into this session.
- M17 Recon + Signature-Ability Sweep (scoping only, not a milestone): **COMPLETE** — 2026-07-02. `docs/m17_recon.md` covers the full 1-318 ability range (151 roster-relevant + 166 full-scope extension), classifies each into 6 mechanic buckets, proposes M17a-n tier sequencing, and (in its Section 13 addendum) flags 23 additional legendary/mythical/Ultra-Beast-exclusive abilities Rob hadn't yet excluded (Air Lock/Rayquaza, Victory Star/Victini, the Necrozma-Solgaleo-Lunala constellation, the Regi-trio pair, Beast Boost/all 11 Ultra Beasts, Toxic Chain/the Loyal Three, etc.) plus a reconsideration flag on the Primal weather trio. Two small data-pipeline fixes applied during this pass: 6 (not 2) ability IDs had symbolically-defined enum values causing missing `.tres` placeholder files, all now generated via the new `scripts/gen_ability_placeholders.py`. Read this doc (all of it, including the Addendum and Section 13) before starting any M17 sub-tier — it is the locked scoping source of truth, not re-derived per milestone.
- M17a (Tier A move effects — damage-pipeline modifiers): **COMPLETE** — 2026-07-02. 32 abilities (Overgrow/Blaze/Torrent/Swarm, Marvel Scale, Compound Eyes, Battle Armor/Shell Armor, Multiscale, Filter/Solid Rock/Tinted Lens, Adaptability, Rock Head, Sniper, Toxic Boost, Sand Force, No Guard, Guts, Hustle, Heatproof, Iron Barbs, Fur Coat, Tough Claws, Steelworker, Steely Spirit, Battery, Power Spot, Rocky Payload, Ice Scales, Defeatist, Flare Boost) — Section 11's proposal re-derived against Section 13's exclusions first (removed Shadow Shield/Prism Armor/Neuroforce/Full Metal Body/Transistor/Dragon's Maw, all legendary-exclusive). Source investigation found FOUR distinct pipeline hook points were needed, not the one function the recon's shallow pass assumed — extended `attack_modifier_uq412` and `defense_damage_modifier_uq412` (new `effectiveness` param), added `attacker_post_effectiveness_modifier_uq412` and `move_power_modifier_uq412` (new base-power pipeline stage, mirrors M14b's Helping Hand insertion point), plus `blocks_critical_hit`/`blocks_recoil`/`bypasses_accuracy_check`/`accuracy_modifier_percent`. New `BattleManager._get_ally()` doubles-partner helper (reuses M14a's existing combatant layout, not new infrastructure) for Battery/Power Spot/Steely Spirit's ally-aura boost. New `m17a_test.gd`/`.tscn`: 83/83 assertions; caught and fixed a real Marvel Scale direction bug (returned ×1.5 instead of the correct reciprocal ≈×0.667) and a recurring GDScript lambda-scalar-capture test bug. 1206 total assertions across 23 numbered suites, all green. M17b next.
- M17b (Tier B move effects — stat-stage-system interactions, no new infrastructure): **COMPLETE** — 2026-07-02. 32 abilities (Steadfast, Anger Point, Simple, Download, Clear Body, White Smoke, Keen Eye, Hyper Cutter, Moxie, Unaware, Contrary, Defiant, Weak Armor, Moody, Big Pecks, Justified, Rattled, Flower Veil, Sweet Veil, Gooey, Stamina, Water Compaction, Berserk, Tangling Hair, Competitive, Cotton Down, Steam Engine, Pastel Veil, Thermal Exchange, Anger Shell, Purifying Salt, Supersweet Syrup) — Section 11's Bucket B proposal re-derived against Section 13's exclusions; corrected two gaps in the task's own exclusion transcription (Beast Boost excluded as UB-exclusive; Moxie included since it reuses M14b's existing `_last_attacker` kill-attribution rather than needing new infra). Guard Dog and Opportunist deferred (both need genuinely new infrastructure — a forced-switch ability gate, and threading a check through ~33 `apply_stat_change` call sites, respectively). Confirmed three distinct mechanic shapes: magnitude modifiers (Simple/Contrary, in `AdjustStatStage`), change-blocking gates (Clear Body/White Smoke/Hyper Cutter/Big Pecks/Keen Eye/Flower Veil, in `CanAbilityPreventStatLoss`/`AbilityPreventsSpecificStatDrop`), and reactive triggers hooking EXISTING M8/M11/M14b/M16d infrastructure rather than the stat-change pipeline itself. New non-contact-gated `AbilityManager.try_hit_reactive_effects` corrects a real over-generalization in the M8-era `try_contact_effects` comment (contact ≠ a blanket rule for the whole `ABILITYEFFECT_MOVE_END` dispatch — only true for M8's specific ability subset). `try_switch_in`/`try_end_of_turn` both changed return type `int` → `Dictionary` (breaking change, fixed the one affected M8-era `ability_test.gd` call site). New `m17b_test.gd`/`.tscn`: 109/109 assertions, negative case for every ability; caught one real implementation bug (Moody's forced-value pool validation) plus two test-only bugs (Anger Point's clamped-delta expectation, Purifying Salt's Ghost-immune-Normal-defender mismeasurement). 1315 total assertions across 23 numbered suites, all green.
- M17c (Tier C move effects — switch-in/turn-end triggers, no new field-state infrastructure): **COMPLETE** — 2026-07-02. 22 abilities (Sand Stream, Snow Warning, Rain Dish, Ice Body, Dry Skin, Hydration, Shed Skin, Healer, Truant, Poison Point, Poison Touch, Effect Spore, Cursed Body, Toxic Debris, Flower Gift, Slush Rush, Cheek Pouch, Ripen, Hospitality, Anticipation, Forewarn, Frisk) — Section 11's Bucket C proposal re-derived against Section 13's exclusions; corrected a gap in the task's own transcription (Spicy Spray excluded as Scovillain-Mega-exclusive, falling under the pre-existing "no Mega Evolution" scope note) and confirmed Solar Power/Poison Heal are deferred to M17d and Harvest is out of scope (needs new "last consumed berry" infra) per the recon's own tier proposal, not the task's "expected shape" hint. Dry Skin's Water-move absorb+heal half deferred (needs Bucket-E immunity+heal infra, shared gap with unimplemented Volt Absorb/Water Absorb); its Fire-damage-taken and end-of-turn heal/damage halves are wired. Truant is the first PRE-MOVE canceler this project adds via an ability rather than a status (new `BattlePokemon.truant_loafing`, slotted into `StatusManager.pre_move_check` at its exact source position). Flower Gift needed a new `DamageCalculator.defender_ally` parameter (the DEFENDER's doubles partner, distinct from M17a's attacker-side `ally`) and drops its Cherrim-Sunshine-form gate, matching the same precedent already set for the Primal weather trio. `try_end_of_turn`/`try_contact_effects`/`try_hit_reactive_effects`/`attack_modifier_uq412`/`defense_damage_modifier_uq412`/`effective_speed` all gained new trailing parameters (additive, no breaking changes this time). New `m17c_test.gd`/`.tscn`: 79/79 assertions; caught one real implementation bug (Flower Gift's ally-share was unreachable behind an incorrect `defender.ability != null` gate) plus one test-only bug (Cursed Body integration test's Normal-vs-Ghost type immunity mismeasurement, same pitfall class as M17b's Purifying Salt bug). 1394 total assertions across 24 numbered suites, all green.
- M17d (Weather-setter completions + Primal trio + multi-part abilities deferred from M17c): **COMPLETE** — 2026-07-02. 5 abilities (Solar Power, Poison Heal, Primordial Sea, Desolate Land, Delta Stream) — Section 11's M17d proposal re-derived against the current exclusions; corrected a stale recon-prose pairing (Orichalcum Pulse excluded as Koraidon-exclusive per Rob's updated legendary-exclusivity standard, despite Section 11 originally grouping it here alongside Hadron Engine) and confirmed Dry Skin already shipped in M17c. Harvest deferred again (still no "last consumed berry" tracking anywhere in `ItemManager`/`BattlePokemon` — genuinely new infra this otherwise-pure-reuse tier doesn't need for its other 5 abilities; natural bundling partner is Cud Chew whenever that tracker gets built). Solar Power is two-part (Sp. Atk ×1.5 in sun via `attack_modifier_uq412`; maxHP/8 self-damage in sun via `try_end_of_turn`, sharing Dry Skin's `SOLAR_POWER_HP_DROP`-labeled result key). Poison Heal inverts the existing `StatusManager.end_of_turn_damage` to return a **negative** (heal) value instead of duplicating poison-tick logic — a flat maxHP/8 heal regardless of poison vs. toxic, though the toxic counter still increments. Primordial Sea/Desolate Land reuse the ordinary `WEATHER_RAIN`/`WEATHER_SUN` constants directly (no separate "Primal" weather value, no Primal-item gate, per Section 8.5's explicit recommendation). Delta Stream needed a genuinely new `DamageCalculator.WEATHER_STRONG_WINDS` constant plus its type-effectiveness side effect (weakens super-effective hits against Flying-type defenders, checked per-type-component) wired into BOTH of this project's independent type-effectiveness computations (`TypeChart.get_effectiveness`'s early immunity/ability-gate check, gained a new `weaken_flying_se` bool param, and the actual per-type UQ4.12 damage-multiplier block in `DamageCalculator.calculate`) since they aren't unified into one function the way source's is. New `m17d_test.gd`/`.tscn`: 30/30 assertions, passed clean on the first run — every damage-calc scenario checked against `TypeChart.TABLE` directly first, per CLAUDE.md's type-immunity-precedes-ability-logic convention. 1424 total assertions across 25 numbered suites, all green. **M17e (Terrain system) is void** — Rob's locked-in scope decision (confirmed before M17a began) excludes all 10 terrain-reliant abilities (Electric/Psychic/Misty/Grassy Surge, Surge Surfer, Grass Pelt, Quark Drive, Mimicry, Hadron Engine, Seed Sower), so the Terrain system Section 11 proposed for M17e will never be built for this project — the letter is skipped, not renumbered, to avoid touching the already-shipped M17a-d labels/citations for no benefit.
- M17f (Trapping check — new infrastructure — + Shadow Tag/Arena Trap/Magnet Pull): **COMPLETE** — 2026-07-02. First genuinely new-infrastructure tier since M14a — every M17a-d tier before it was pure reuse. Source: `battle_util.c :: IsAbilityPreventingEscape` (L4917-4941), called only from two selection-time sites in `battle_main.c` (the wild-battle Run menu, the party-switch-menu's `B_ACTION_SWITCH` case) — `CanBattlerEscape`, the separate function backing forced switches/faint-replacement/Baton Pass, literally has "no ability check" per its own source comment, confirming trapping is a selection-time-only gate. New `AbilityManager.is_trapped(mon, live_opponents) -> bool` encodes: a global Ghost-type exemption from all three abilities (`B_GHOSTS_ESCAPE >= GEN_6`, unconditional at this project's GEN_LATEST config); Shadow Tag's mirror-match exemption when both sides have it (`B_SHADOW_TAG_ESCAPE >= GEN_4`, also unconditional here); Arena Trap gating on `AbilityManager.is_grounded` (reused directly from M16d); Magnet Pull gating on Steel-type. New `BattleManager._get_live_opponents` mirrors `_apply_switch_in_abilities`'s existing live-opponent loop shape. Wired into `_phase_move_selection` immediately after a queued/AI-chosen switch sets `_chosen_switch_slots` — a blocked switch falls back to the mon's first move, the same fallback expression already used elsewhere in that function. Forced switches, faint replacement, and Baton Pass are confirmed unaffected by construction (none of those three call sites ever reads `_chosen_switch_slots` or calls `is_trapped` — not a special-cased exemption, just architecturally disjoint paths), and trapping only ever reads the OPPONENT's side, never the holder's own. Shed Shell (source's one item-based exemption) isn't modeled — this project has no Shed Shell item anywhere, confirmed via grep. New `m17f_test.gd`/`.tscn`: 28/28 assertions (ability data; 12 direct `is_trapped` unit tests covering every positive/negative/exemption case including a dual Ghost/Steel mon proving the Ghost exemption overrides Magnet Pull's type gate; full-battle integration for the block itself, Arena Trap's Flying exemption, Magnet Pull's Steel-only gate, Roar/Baton Pass/faint-replacement all bypassing trapping, and the holder's own side switching freely). Total assertions across all 27 numbered suites: **1476**, all green (a direct recount during this sweep found the actual suite count was already 27, not 26 as M17d's "25 prior suites" line implied — a stale count, not a regression; every suite passed clean). See `docs/decisions.md`'s `[M17f]` entry for full source citations and the Step 0 exclusion cross-check. **M17g (Ability-suppression plumbing — Mold Breaker/Neutralizing Gas — + free-riders) is next**, but Section 11's original member list needs re-verification before implementation: Turboblaze (163) and Teravolt (164), listed there as "free" once Mold Breaker's plumbing exists, are BOTH flagged legendary-exclusive in Section 13.1 (Reshiram/Kyurem-White, Zekrom/Kyurem-Black) and should almost certainly be excluded under Rob's legendary-exclusivity standard — the same correction pattern as Beast Boost (M17b) and Orichalcum Pulse (M17d). Mycelium Might (298), listed as only "partially" a free-rider, is NOT in Section 13's exclusion sweep and likely stays in scope, pending its own Step 0 check.

## Development workflow

Run a verification scene headless (from project root):

```bash
/home/rob/Godot_v4.3-stable_linux.x86_64 --headless --path . scenes/battle/SCENE.tscn
```

**Verification scenes:**
- `scenes/battle/battle_test.tscn` — M1 battle loop (Struggle to faint)
- `scenes/battle/damage_test.tscn` — M2 damage formula and type chart (24 tests)
- `scenes/battle/status_test.tscn` — M3 status conditions (75 tests)
- `scenes/battle/move_test.tscn` — M4 move registry, damage via loaded moves, freeze-thaw (45 tests)
- `scenes/battle/stat_test.tscn` — M5 stat stages, secondary effects, accuracy, flinch (78 tests)
- `scenes/battle/tier3_test.tscn` — M6 multi-turn, semi-inv, fixed damage, recoil, drain (62 tests)
- `scenes/battle/tier4_test.tscn` — M7 Substitute, Counter/Mirror Coat, Protect, Destiny Bond, Disable, Encore, Bide, Metronome (86 tests)
- `scenes/battle/ability_test.tscn` — M8 abilities: Huge Power/Pure Power, Levitate, Thick Fat, Intimidate, Drizzle/Drought stubs, Speed Boost, Static, Flame Body, Rough Skin, Synchronize (59 tests)
- `scenes/battle/switch_test.tscn` — M9 switching: BattleParty unit tests, voluntary switch, volatile clear, non-volatile persist, Intimidate on switch-in, Roar/Whirlwind forced switch, Baton Pass passable transfer, faint replacement, full-party-faint battle end (64 tests)
- `scenes/battle/ai_test.tscn` — M10 Trainer AI: type effectiveness scoring, KO preference, type immunity avoidance, wasted status avoidance, two-turn penalty, BASIC vs SMART tier, proactive switch (all-immune / has-bad-odds), faint replacement, full battle integration (26 tests)
- `scenes/battle/weather_test.tscn` — M11 Weather: Drizzle/Drought set weather, duration countdown, expiry, no-clear-on-switch, same-weather no-op, overwrite, rain/sun damage modifiers (discriminating composition test), sandstorm/hail chip immunity, modifier revert on expiry, AI weather-aware scoring (64 tests)
- `scenes/battle/item_test.tscn` — M12 Held Items: Choice Band/Scarf/Specs stat boosts, Life Orb damage + recoil, Sitrus Berry HP heal, Lum Berry status cure, Leftovers EOT heal, resist berry (Occa/Chilan), Utility Umbrella, choice-lock enforcement, Heavy Duty Boots hazard immunity (77 tests)
- `scenes/battle/ai_test.tscn` — M10+M13 Trainer AI: effectiveness scoring, KO preference, type immunity, status avoidance, two-turn penalty, BASIC/SMART tiers, switch decisions, faint replacement, full battle integration; M13 adds choice-lock, bad-lock switch, item-boost discrimination (40 tests)
- `scenes/battle/doubles_test.tscn` — M14a Doubles foundation: BattleParty active_indices API, 4-combatant setup, turn order by speed, full-side faint required to end battle, targeted moves hit correct slot, faint replacement (slot-specific), voluntary switch in doubles (25 tests)
- `scenes/battle/m16a_test.tscn` — M16a Tier A move effects: RESTORE_HP (Recover/Slack Off/Heal Order), FOCUS_ENERGY (crit stage +2), GROWTH (+1/+2 Atk+SpAtk, sun doubling), OHKO (Guillotine/Horn Drill/Fissure/Sheer Cold — level check, custom accuracy, type immunity, semi-inv bypass) (52 tests)
- `scenes/battle/m16b_test.tscn` — M16b Tier B move effects: MINIMIZE (+2 evasion, minimized flag gated on success), DEFENSE_CURL (+1 defense, defense_curled set unconditionally), Stomp minimizeDoubleDamage (exact ×2 post-roll modifier), ROLLOUT/Ice Ball (5-hit power doubling 30→60→120→240→480, Defense Curl doubling, interruption/miss resets), MAGNITUDE (weighted power table, power_override plumbing) (55 tests)
- `scenes/battle/m16c_test.tscn` — M16c Tier C move effects (screens): REFLECT/LIGHT_SCREEN (exact floor(dmg/2) per-category reduction, 5-turn duration, already-up no-refresh, doubles ⅔ reduction, switch persistence), AURORA_VEIL (hail gate, independent coexistence with Reflect/Light Screen, no double-stacking, reduces both categories), crit bypass, Brick Break (clears target's side pre-damage, own hit unaffected) (60 tests)
- `scenes/battle/m16d_test.tscn` — M16d Tier D move effects: SPIKES (opponent's-side 3-layer stacking, per-layer maxHP fraction, grounded/Levitate immunity, switch persistence), TOXIC_SPIKES (1-layer poison vs 2-layer toxic, Poison-type absorb, Steel-type immunity, ungrounded immunity), STEALTH_ROCK (type-effectiveness damage table, hits Flying-types unlike Spikes), RAPID_SPIN (clears one hazard in Spikes→Toxic Spikes→Stealth Rock order, fires even hitting a Substitute), TRICK_ROOM (exact speed-order reversal within a priority bracket, priority still overrides it, toggle-off, 5-turn expiry) (71 tests)
- `scenes/battle/m16e_test.tscn` — M16e Tier E move effects: PURSUIT (doubled power + turn-order interception striking the original switcher before its switch resolves, verified against direct `DamageCalculator` calls), PAIN_SPLIT (current-HP averaging both directions, floor rounding, Substitute block), CONVERSION (type from the literal first move slot, already-that-type failure), CONVERSION_2 (resist-type selection against the target's last USED move — not "last hit by" — exclusion-before-indexing, deterministic via `_force_conversion2_pick`, plus a direct-conflict discriminator against an earlier hit of a different type), PSYCH_UP (copies all 7 stat stages plus the Focus Energy volatile, overwrite semantics), Baton Pass (`focus_energy` now passes; `minimized`/`defense_curled`/`rollout_turns` still correctly excluded), type-reset-on-switch (a Conversion-mutated type reverts to the original species type after a voluntary switch-out and back in) (58 tests)
- `scenes/battle/m16_review_test.tscn` — M16 Milestone-End Review, Area 3: Trick Room × Pursuit turn-order integrity — Pursuit interception still fires correctly under Trick Room regardless of which side is naturally faster, doubled power and switch completion both still correct, and Trick Room's own speed-reversal is unaffected when a Pursuit-carrying Pokémon's target isn't switching (singles only — doubles combination explicitly flagged as untested in `docs/decisions.md`) (8 tests)
- `scenes/battle/m17a_test.tscn` — M17a Tier A move effects: 32 damage-pipeline-modifier abilities across attack-stat, defense-stat, post-type-effectiveness, and base-power hook points (Overgrow/Blaze/Torrent/Swarm, Marvel Scale, Compound Eyes, Battle Armor/Shell Armor, Multiscale, Filter/Solid Rock/Tinted Lens, Adaptability, Rock Head, Sniper, Toxic Boost, Sand Force, No Guard, Guts, Hustle, Heatproof, Iron Barbs, Fur Coat, Tough Claws, Steelworker, Steely Spirit, Battery, Power Spot, Rocky Payload, Ice Scales, Defeatist, Flare Boost), including the doubles-ally cases (Battery/Power Spot/Steely Spirit) and Guts' burn-halving exemption (83 tests)
- `scenes/battle/m17b_test.tscn` — M17b Tier B move effects: 32 stat-stage-system-interaction abilities across the three mechanic shapes — magnitude modifiers (Simple/Contrary), change-blocking gates (Clear Body/White Smoke/Hyper Cutter/Big Pecks/Keen Eye/Flower Veil), and reactive triggers (Defiant/Competitive, Weak Armor/Justified/Rattled/Anger Point/Berserk/Anger Shell/Steam Engine/Thermal Exchange/Cotton Down/Stamina/Water Compaction, Gooey/Tangling Hair, Steadfast, Download, Moody, Moxie, Sweet Veil/Pastel Veil/Purifying Salt status immunities, Supersweet Syrup's one-time gate), plus Unaware's 4 stage-ignoring touch-points, including full-battle integration tests (Growl+Defiant, Cotton Down, flinch+Steadfast, KO+Moxie) (109 tests)
- `scenes/battle/m17c_test.tscn` — M17c Tier C move effects: 22 switch-in/turn-end-trigger abilities — weather-setters (Sand Stream/Snow Warning), end-of-turn heal/cure (Rain Dish/Ice Body/Dry Skin/Hydration/Shed Skin/Healer), Truant's pre-move canceler + toggle cycle, contact status infliction (Poison Point/Poison Touch/Effect Spore's weighted roll), non-contact hit-reactive (Cursed Body/Toxic Debris) including full-battle integration, weather-conditional stat modifiers (Flower Gift incl. ally-share, Slush Rush), item-adjacent (Cheek Pouch/Ripen), Hospitality's switch-in ally heal, and the three cosmetic/no-op abilities (Anticipation/Forewarn/Frisk) (79 tests)
- `scenes/battle/m17d_test.tscn` — M17d weather-setter completions + Primal trio + multi-part abilities: Solar Power's two halves (Sp. Atk boost in sun + end-of-turn self-damage), Poison Heal's inversion of the poison/toxic end-of-turn tick (incl. the flat-not-counter-scaled heal and the still-incrementing toxic counter), Primordial Sea/Desolate Land's plain switch-in weather-setting with no item gate, and Delta Stream's Strong Winds weather plus its Flying-type-weakness-cancellation effect (mono-type and dual-type cases, plus negative cases for non-Flying defenders and sub-2.0x hits) (30 tests)

**Note:** if you add a new file with `class_name`, run an import pass before the test scenes
will see it:

```bash
/home/rob/Godot_v4.3-stable_linux.x86_64 --headless --path . --import
```
