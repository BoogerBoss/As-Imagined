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
- M4 (Tier-1 move pipeline + freeze-thaw hooks): **COMPLETE** — 2026-06-25, 43/43 tests pass
- M5 (move effects — stat changes & status infliction): **COMPLETE** — 2026-06-25, 78/78 tests pass
- M6 (move effects — multi-turn, recoil, drain, fixed damage): **next**
- M6–M10: not started

## Development workflow

Run a verification scene headless (from project root):

```bash
/home/rob/Godot_v4.3-stable_linux.x86_64 --headless --path . scenes/battle/SCENE.tscn
```

**Verification scenes:**
- `scenes/battle/battle_test.tscn` — M1 battle loop (Struggle to faint)
- `scenes/battle/damage_test.tscn` — M2 damage formula and type chart (24 tests)
- `scenes/battle/status_test.tscn` — M3 status conditions (75 tests)
- `scenes/battle/move_test.tscn` — M4 move registry, damage via loaded moves, freeze-thaw (43 tests)
- `scenes/battle/stat_test.tscn` — M5 stat stages, secondary effects, accuracy, flinch (78 tests)

**Note:** if you add a new file with `class_name`, run an import pass before the test scenes
will see it:

```bash
/home/rob/Godot_v4.3-stable_linux.x86_64 --headless --path . --import
```
