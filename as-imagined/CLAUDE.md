# Emerald Battle Engine Clone — Project Guide for Claude Code

## What this project is

A faithful, standalone recreation of Pokémon Emerald's (Gen III, Game Boy
Advance) turn-based battle system in Godot 4.x, using GDScript. This is NOT
a new battle system "inspired by" Pokémon — the goal is mechanical accuracy
to vanilla Emerald, era-correct down to specific quirks (no Physical/Special
split, Gen III critical hit rate, Gen III status mechanics, etc.).

This is a separate project from my other Godot project (a farming/action-RPG
hybrid). Do not assume any code, autoloads, or conventions from that project
carry over here unless I explicitly say so.

## Ground truth / reference

The authoritative source for "what should this do" is the `pokeemerald`
decompilation project (PRET community), NOT the Bulbapedia prose description,
NOT a remake's mechanics, and NOT any of the `_expansion` / `battle_engine_v2`
modded branches — those add later-generation mechanics (Physical/Special
split, Fairy type, newer abilities) which would break fidelity to vanilla
Emerald.

- Primary reference repo: `pret/pokeemerald` (vanilla decompilation)
- Located at: `/home/claude/emerald-battle-clone/reference/pokeemerald` (clone
  this in if not present — see Setup below)
- Key files to consult when implementing a mechanic:
  - `src/battle_script_commands.c` — move/effect execution logic
  - `src/battle_util.c` — damage calc helpers, status application
  - `src/battle_ai_script_commands.c` and `src/battle_ai_main.c` — trainer AI
  - `src/data/moves_info.h` / similar — move data tables
  - `src/data/abilities.h` — ability definitions
  - `include/constants/battle_move_effects.h` — move effect IDs

When implementing any mechanic, the workflow is: **look at the disassembly
logic first, then port the behavior to GDScript** — don't guess from memory
of "how Pokémon battles work," because Gen III has specific numeric constants
and edge cases that differ from later/earlier generations.

If a mechanic's source location is unclear, search the pokeemerald repo
structure before implementing, or ask me to confirm before making something up.

## Era-correct rules (do not "fix" these — they are intentional)

- **No Physical/Special split.** Move category (physical/special) is
  determined by TYPE, not by the move individually. Type → category mapping
  must match Gen III exactly (e.g. all Dark-type moves are physical in Gen III).
- **Critical hit rate base is 1/16**, before stage modifiers (high-crit moves,
  Focus Energy, etc.) — NOT the later-gen 1/24.
- **No Fairy type.** 17 types only (later games add Fairy as an 18th).
- **No abilities beyond Gen III's list.** Don't add Drizzle/Drought-era weather
  abilities if they weren't in Emerald, etc.
- **Confusion, paralysis, and freeze chances** must match Gen III values exactly
  (e.g. paralysis = 25% full-para chance, not later-gen 50%→25% adjustments... verify exact value against source, don't assume).
- **Damage formula constants** (random factor range 85–100%, STAB 1.5x, etc.)
  must match Gen III exactly.

Whenever in doubt about a numeric constant, treat it as a fact to verify
against the decompilation source, not something to recall from general
Pokémon knowledge — general knowledge tends to blend mechanics across
generations.

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
  pokeemerald/    # Cloned decompilation source, read-only reference — never edit
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
   Implement the Gen III damage formula exactly (base power, attack/defense
   stat use depending on category, STAB, type effectiveness, random factor,
   critical hits). Build the full 17-type effectiveness chart. Verify against
   known damage calc examples from the decompilation or community damage
   calculators that explicitly target Gen III.

3. **Status conditions**
   Burn, poison, toxic, paralysis, sleep, freeze, confusion — implement each
   condition's application rules, turn-start/turn-end effects, and cure
   conditions, matching Gen III specifics.

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
   Port Gen III's actual rule-based decision logic from
   `battle_ai_script_commands.c` / `battle_ai_main.c` — this is simpler than
   modern Pokémon AI and well documented in the decompilation.

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
- When implementing a move or ability, state which decompilation source file
  and function you're basing the behavior on.
- When a mechanic seems ambiguous or you're not fully certain of the Gen III
  -specific behavior (vs. a later-gen change), stop and ask rather than
  guessing — call out the ambiguity explicitly.
- Write unit-test-style verification scenes/scripts for damage calc and status
  logic as they're built (e.g. a debug scene that runs known move/stat
  combinations and prints expected vs. actual damage), since correctness here
  is the entire point of the project.
- Keep `docs/decisions.md` updated with any mechanic verified against source,
  especially when a constant or rule was ambiguous and required a judgment
  call — so we don't re-litigate it later.
- Don't add quality-of-life features, balance changes, or later-gen mechanics
  "because they're better" — flag them as ideas in `docs/` instead, fidelity
  to vanilla Emerald is the point of this project.

## Setup

```bash
# From project root
git clone https://github.com/pret/pokeemerald reference/pokeemerald
```

This reference clone is for reading only — never modify it, never build it,
it exists purely to look up exact source logic.

## Current status

Project scaffolded, no milestones started yet. Next step: Milestone 1
(data schema + state machine skeleton).
