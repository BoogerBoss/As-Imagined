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

## 5. Decisions

### 1. Player party for D5 — DECIDED (Rob, 2026-07-30)

**Debug party for the pre-alpha; widen to a real one as the slice grows into
the full alpha.** So D5 proves the seam without waiting on M27K's starter
choice, and starter choice lands later against a seam already known to work.

### 2. `OBJ_EVENT_GFX_VAR_*` — bigger than one NPC, and source supplies the answer

Not a one-off: **44 region-wide across all 8 slots** (VAR_0 ×13, VAR_1/2/3 ×9
each, VAR_4..7 ×1 each). One is in the corridor — Viridian City (21,6),
`ViridianCity_EventScript_Tut...`, the tutorial man.

`GetObjectEventGraphicsInfo` resolves them through
`VarGetObjectEventGraphicsId(id - OBJ_EVENT_GFX_VARS)`, i.e. a script variable
picks the sprite. **They cannot be pulled, only dispatched**, and the variable
that drives them is set by field scripts (M27G).

**Source already answers what to draw meanwhile.** The same function ends:

```c
if (graphicsId >= NUM_OBJ_EVENT_GFX)
    graphicsId = OBJ_EVENT_GFX_NINJA_BOY;
```

— an unresolvable id falls back to a real, visible sprite rather than nothing.
**Recommendation: adopt source's own fallback.** It is visible (so a hole is
obvious rather than silent), it needs no invented placeholder art, and when
M27G lands the VAR lookup slots in ahead of the fallback with nothing to undo.

### 3. Empty `movement_type` — not a defect, and it exposes a bigger finding

**9 region-wide**, and the make-up is the point: **6 are
`OBJ_EVENT_GFX_CUTTABLE_TREE_FRLG`** plus 3 humans (`COOLTRAINER_M` ×2,
`FAT_MAN_FRLG`). The corridor's one instance is a cuttable tree on Route 2.

A cuttable tree has no movement type because **it is not a character** — it is
scenery with a script. Source's absent value is `MOVEMENT_TYPE_NONE`, which
means "hold the initial facing and never move", so **treating empty as NONE is
source behaviour, not a workaround.** Recommendation: do that, and do not
surface it as a data defect.

⚠️ **The finding underneath is worth more than the decision.** HM obstacles are
**object events, not tiles** — region-wide: 97 `BREAKABLE_ROCK_FRLG`, 55
`CUTTABLE_TREE_FRLG`, 43 `PUSHABLE_BOULDER`, 15 `PUSHABLE_BOULDER_FRLG` — **210
entities** that exist to block movement until a field move clears them.

Two consequences. **D2 gets them for free**: they import as `npc` kind, so the
`npc`/`trainer`/`item` occupancy rule already blocks them, and a cuttable tree
will be solid the moment occupancy lands, with no obstacle-specific code.
And **M27E (field moves) is partly an entity problem**, not a terrain one —
worth knowing before that block is scoped.

### 4. Remembering a beaten trainer — the data is already imported, the store is not

Source is one flag per trainer: `HasTrainerBeenFought(id)` is
`FlagGet(TRAINER_FLAGS_START + trainerId)`, and winning calls `FlagSet` on the
same bit (`battle_setup.c:1287-1294`).

**This project has no flag or var store — but it already imports the data for
both.** Measured on the corridor: **31 of 132 object events carry a visibility
flag**, and **30 triggers reference 9 distinct VARs**
(`VAR_MAP_SCENE_PEWTER_CITY`, `VAR_MAP_SCENE_ROUTE22`, and so on). The
importer extracts them, the baker writes them, and nothing reads them.

So this is not really "should the slice persist anything". **One flag/var store
answers three separate needs at once:**

- D4/D5 — has this trainer been beaten
- D1/D3 — 31 corridor NPCs are currently drawn unconditionally when their own
  flag says some should be hidden
- M27G — field scripts are mostly flag and var manipulation; this is their
  substrate

**Recommendation: build it in D4, in memory, shaped for serialisation.** It is
small (a flag set and a var dictionary), it is needed three times over, and
M27L's job then becomes writing it to disk rather than designing it. The
alternative — an ad-hoc "defeated trainers" set for the slice — is the same
work done twice and thrown away once.

---

## 6. D1 scope addendum — pull the whole sprite set (Rob, 2026-07-30)

**Pull all object-event sprites, not just the 46 the corridor names.**

Measured: **449 PNGs totalling 0.5 MB**, covering **387 graphics ids** of which
only **26 are `_FRLG`-suffixed** — the other 361 are Hoenn/shared, which is
what "the Emerald sprites" means here. None of them are currently in this
project.

At half a megabyte the selective pull saves nothing and costs a second
session later. This project has already run that experiment: `[M26B3-1]`
pulled 93 trainer front pics, and the Kanto roster then forced a second pull of
62 more. The dangling-stem counter exists because of it.

Non-people directories come along for free and are wanted eventually anyway —
`berry_trees` (47), `misc` (63), `dolls`/`cushions` (51, secret-base
decorations), `pokemon_old` (63).

The generated `graphics_id -> (sheet, frame size, palette)` table should cover
all 387 ids for the same reason, so a map baked later never hits an id the
table does not know.


---

## 7. D1 — what else to lump in (Rob, 2026-07-30)

Surveyed the reference for flat, unpulled, plausibly-wanted art. Three groups.
**Total addition over the 449 object-event sprites: ~55 KB.**

### A. Not optional — the slice needs these

- **`field_effects/pics/emotion_exclamation.png`.** The "!" a trainer shows on
  spotting you. **D4 has no visual for its own trigger without it.**
- **`shadow_small/medium/large.png`.** `.shadowSize` is real per-sprite data on
  **all 393 graphics-info entries** (324 `SHADOW_SIZE_M`, 67 `S`, 1 `L`, 1
  `NONE`), so a shadow is part of the sprite record rather than decoration.
- **The player's overworld sprite** — currently a red `ColorRect`. Comes free:
  `people/brendan`, `may`, `leaf`, `red` are already inside D1's 449.

### B. Free, and wanted by blocks already on the roadmap

**All 66 field effects — 37 KB.** Beyond the three above:
`tall_grass` / `jump_tall_grass` / `long_grass` (rustle when walking through,
M27H), `cut_grass` / `surf_blob` / `rock_climb_*` / `ash` (M27E field moves),
**`shiny_sparkle`** (M27's own flagged shiny gap), `pokeball_glow`, `sparkle`,
`ripple`, `splash`, and the footprint/track sets.

Taking the lot avoids picking winners for blocks that are not scoped yet, at a
cost that rounds to nothing.

### C. Closes a known open gap — 25 trainer front pics, 18 KB

Source has 180, the project has 155. The missing 25 are `[M26B3-1]`'s
"no consumer in either roster" set (`champion_steven_frlg`, `collector_frlg`,
`expert_f_frlg`, …). Pulling them retires the dangling-stem counter for good
rather than leaving it armed for the next roster change.

### Nothing to do for battle-side Pokemon art

Already complete: **387 front, 387 back, 386 icons**, 162 items, 155 trainer
portraits, 11 back pics — 19 MB in `assets/sprites/`. *(Checked twice: a first
pass looked for `pokemon/icons` and reported a false gap. The directory is
`pokemon/icon`, and the 386 icons are there.)*

### ⚠️ One gotcha that applies to every file above

**None of them carry a tRNS chunk**, and palette index 0 is the transparency
key. A plain `shutil.copyfile` renders each one inside an opaque box — exactly
what happened to the ball sheets in `[M26B3-6a]`. The pull must tag index 0
transparent, as `gen_ball_sprites.py` and `gen_hit_effect_sprites.py` already
do. Index 0 is NOT a constant colour across these files, so tag the index
rather than colour-keying a value.
