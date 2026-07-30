# M27D — Entities & NPCs: Step 0

Scoping pass, 2026-07-30. No code written. Measured against the 32-map
corridor and, where it matters, against all 421 maps.

This is the block that turns a walkable region into a game: 226 entities are
already placed across the corridor as typed data nodes, and **not one of them
does anything**.

---

## 1. What already exists

| | |
|---|---|
| Entities placed | 226 across 32 maps — 100 NPC, 22 trainer, 10 item ball, 64 sign, 30 trigger |
| Typed classes | `NPC` / `TrainerNPC` / `ItemBall` / `Warp` / `Trigger` / `Sign` over `OverworldEntity` |
| Trainer identity | all 22 `trainer_key`s resolve against `TrainerRegistry` |
| Sight geometry | ported and tested — `MapOverlay.trainer_sight_cells()` |
| Occupancy rule | derived and documented — `MapOverlay._sight_blocking_cells()` |
| Battle engine | complete (M1–M26), with a `BattleSetupContext.set_pending()` seam |

**The entity classes are pure data carriers.** Read them: `npc.gd` is 37
lines, of which the body is three `@export`s and a configuration warning.
There is no sprite, no movement, no occupancy, no interaction.

Two pieces of real work are already banked in the *editor* and want moving to
the runtime rather than rewriting:

- **The sight ray.** `trainer_sight_cells()` walks `StepResolver.resolve()`
  rather than reading the collision bit, so a sight line can never disagree
  with the movement rules it describes. It already handles directional
  impassability, elevation mismatch, ledges and object-event blockers.
- **The occupancy rule.** `_sight_blocking_cells()` records that only
  `npc`/`trainer`/`item` block, because `DoesObjectCollideWithObjectAt`
  consults the `object_events` array and nothing else — warps, triggers and
  signs occupy no collision slot, so a trainer sees straight over a doormat.
  That rule is exactly what movement needs, in the wrong module.

---

## 2. What is missing, measured

### 2.1 No overworld sprites exist at all

`assets/sprites/` has `battle_anims`, `battle_backgrounds`, `battle_effects`,
`battle_ui`, `items`, `pokemon`, `trainers` — and nothing for the overworld.
Source has **449 PNGs** under `graphics/object_events/pics/`.

The corridor needs **46 distinct `graphics_id` values**. The resolution chain
is four hops and worth writing down, because none of it is derivable from the
id by string transform:

```
OBJ_EVENT_GFX_LASS_FRLG
  -> object_event_graphics_info_pointers.h   gObjectEventGraphicsInfo_LassFrlg
  -> object_event_graphics_info.h            .width/.height/.paletteTag/.anims
  -> object_event_pic_tables.h               sPicTable_LassFrlg -> gObjectEventPic_LassFrlg
  -> object_event_graphics.h                 INCGFX_U16(".../people/lass_frlg.png", ...)
```

**Frame sizes in use across the corridor:** 16x32 (36 ids), 16x16 (8), 32x16
(1). All 449 source files are palette-mode, so the pull is a flat copy in the
shape of `gen_trainer_portraits.py` — with two exceptions found by checking
rather than assuming:

⚠️ **`OBJ_EVENT_GFX_WORKER_M`'s embedded palette does NOT match its tagged
`npc_white.pal`.** 44 of the corridor's 46 match; this one genuinely differs,
so a flat copy renders it in the wrong colours. Same shape as `[M23.11 Phase
5b]`'s Thunder, where tile data and palette lived in different files. **A pull
must resolve `.paletteTag` per sprite rather than trusting the PNG.**

⚠️ **`OBJ_EVENT_GFX_VAR_0` is not a sprite at all.** It is one of
`OBJ_EVENT_GFX_VAR_0..F`, resolved at runtime through
`VarGetObjectEventGraphicsId` — the NPC's appearance is chosen by a script
variable. It cannot be pulled, only dispatched, and it needs the field script
engine (M27G) to mean anything. One instance in the corridor.

### 2.2 Nothing models entity occupancy

`MapManager.collision_at()` is terrain-only, and `StepResolver` is built
against a cell source with four methods, none of which know an entity exists.
**You walk straight through every NPC in the corridor.**

This is the one change that touches the movement core rather than sitting
beside it, and it is why it wants its own sub-tier.

### 2.3 No movement, no interaction, no battle handoff

Nothing polls, nothing turns, nothing reacts to the player, and no path exists
from the overworld into `BattleManager`.

---

## 3. Findings that shape the work

### 3.1 The movement problem is far smaller than 89 types

Source defines 89 `MOVEMENT_TYPE_*`. **The corridor uses 11**, and they
collapse to **four real behaviours**:

| behaviour | types | entities | what it does |
|---|---|---|---|
| fixed facing | `FACE_DOWN/UP/LEFT/RIGHT` | **96** | set a direction, never move |
| look around | `LOOK_AROUND` | 14 | turn in place on a timer |
| wander | `WANDER_AROUND`, `WANDER_UP_AND_DOWN`, `WANDER_LEFT_AND_RIGHT` | 18 | random step within a range |
| alternate facing | `FACE_DOWN_AND_UP`, `FACE_LEFT_AND_RIGHT` | 3 | turn between two directions |

**73% of corridor entities do not move.** `event_object_movement.c` is 12,245
lines because it covers berry trees, cycling, surfing, cutscene actors and 78
types the corridor never names — sizing M27D against that file is sizing it
against the wrong problem.

One entity carries an **empty** `movement_type`. Worth a decision rather than
a default (see §5).

### 3.2 Trainer sight is half-built, and the built half is the fiddly half

The ray is done and tested. What is missing is everything after it fires:
freeze the player, walk the trainer to them, show the exclamation mark, run
the intro line, start the battle, and remember the outcome.

Corridor sight ranges are 1–5 (`{4:4, 3:8, 5:4, 2:4, 1:2}`), and **zero Kanto
trainers are `TRAINER_TYPE_SEE_ALL_DIRECTIONS`** — already measured in M27B —
so the single-direction model holds for all 22.

### 3.3 The battle seam exists on one side only

`BattleSetupContext.set_pending(player_party, opp_party, ..., trainer_id)` is
a static hand-off that `battle_screen.gd` already consumes in `_ready()`, and
`BattleManager.set_trainer_data()` is wired. So the overworld can *start* a
battle today.

What does not exist: **a way back.** The battle screen ends at
`battle_setup_screen.tscn` (Play Again / Run). There is no result object, no
"restore the overworld where you left it", and no "this trainer has been
beaten". There is also **no player party anywhere in the overworld** — no
party, no starter, no player identity of any kind.

This is the largest unproven seam in the codebase and the reason the vertical
slice is worth doing: the two halves of this project have never touched.

---

## 4. Proposed sub-tiers

Ordered so each one is playable when it lands, and so the riskiest change to
existing code (occupancy) happens early while the corridor is the only
consumer.

**D1 — Sprite pull and static rendering.** `gen_object_event_sprites.py` in
the shape of `gen_trainer_portraits.py`, plus a generated `graphics_id ->
(sheet, frame size, palette)` table since none of it is derivable by string
transform. Resolve `.paletteTag` per sprite; do not trust embedded palettes.
Render each entity at its own facing from `movement_type`. Ends with: the
corridor is populated and every NPC faces the right way.

**D2 — Occupancy.** Entities block movement, using the rule already derived in
`_sight_blocking_cells()` — `npc`/`trainer`/`item` only. Touches the cell
source `StepResolver` reads, so it is the one sub-tier that can break existing
movement; doing it second keeps the blast radius at 32 maps.

**D3 — Movement behaviours.** The four shapes above. Needs D2 first, or
wandering NPCs walk through each other and through the player.

**D4 — Trainer sight and approach.** Ray (done) -> freeze -> approach -> hand
off. Stops at the handoff.

**D5 — The battle seam.** Overworld -> battle -> back, with a result object
and a defeated-trainer flag. Needs a player party, which means either a debug
party or pulling M27K's starter choice forward — a decision, not a detail
(§5).

Signs, item balls and interaction deliberately sit outside D1–D5: they need
the field script engine (M27G) to do anything beyond "show fixed text", and
M27F owns dialogue.

---

## 5. Decisions for Rob

1. **Player party for D5** — a hardcoded debug party, or pull M27K's starter
   choice forward? Debug party is faster and throwaway; starter choice is real
   work that has to happen anyway and makes the slice a genuine alpha.

2. **`OBJ_EVENT_GFX_VAR_0`** — one corridor NPC whose sprite is script-chosen.
   Render a visible placeholder until M27G, or leave it invisible? A
   placeholder is honest; invisible is a silent hole.

3. **The empty `movement_type`** — one entity carries `""`. Treat as
   `FACE_DOWN` (source's own default), or surface it as a data defect?

4. **Scope of "defeated"** — D5 needs to remember a beaten trainer. That is
   the first persistent world state in the project, and M27L owns save/load.
   In-memory only for the slice, or does this force the save shape early?
