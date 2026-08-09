# M27M5b — the map creator tool

**Scoped 2026-08-09. Nothing built. Scope of record for the tool; the
already-shipped `MapAuthoring` primitives are recorded in CLAUDE.md's M27M
block.**

---

## 1. The gap, stated exactly

The authoring workflow is six steps. **Four of them are yours today and two are
not:**

| | step | state |
|---|---|---|
| 1 | create the blank map | ⚠️ **needs a hand-written GDScript driver** |
| 2 | open it, toggle the Overlay, select the overlay node | ✅ |
| 3 | paint art (Godot's tile palette → **Sync Painted Tiles**, or the METATILE brush) | ✅ |
| 4 | set collision/elevation off the review list | ✅ |
| 5 | **Save Map Data** | ✅ |
| 6 | connect it to an existing map | ⚠️ **needs a hand-written GDScript driver** |

Steps 1 and 6 are the whole of this tool. Everything else already works.

⚠️ **THIS IS A FRONT END, NOT NEW MECHANISM, AND THAT IS THE SIZING.**
`MapAuthoring` already has `create_map` / `fill_rect` / `fill_rect_quad` /
`add_connection` / `save_map`, all exercised by the real Xanadu Nursery build
and covered by section BA. `map_baker.build_map_scene` is extracted and shared.
`AuthoredMaps` already makes a new map addressable. The tool wires those
together and validates the inputs; it should not grow a single new primitive.

---

## 2. Step 0 measurements

Every number below was measured, not estimated. The command is named where it
is not obvious.

### 2.1 ⚠️ Only 16 of 60 tileset pairs can back a new map today

- **60** pairs exist region-wide (`assets/map_atlases/*_layer_types.json`)
- **22** have rendered atlas PNGs
- **16** have a built `TileSet` in `assets/map_tilesets/`

⚠️ **THIS IS NOT A DEFECT AND NOTHING IS MISSING — it is the vertical slice,
measured.** A `TileSet` is built when a map on that pair is BAKED, and the sets
match exactly:

| | |
|---|---|
| baked maps | 35 |
| pairs those 35 maps use | **16** |
| TileSets built | **16** |
| identical sets? | **yes** |

So "16 of 60" restates "only 35 of 421 maps are baked", which is M27's own
deliberate strategy. The 22-vs-16 gap is the other half: **6 pairs have
rendered atlases but no TileSet** — `saffron_city`, `seafoam_islands`,
`vermilion_city`, `indigo_plateau`, `sevii_islands_45`, `sevii_islands_67` —
which are M27B's curated `subset`, rendered for screenshot validation and never
baked.

**Cost to unlock a pair:** for those 6, bake any one map on it. For the other
44, render the atlas (`gen_map_import.py <a map on that pair>`), run a Godot
`--import` pass, then bake that map — which is the full-region import M27's own
strategy note already reclassifies as a **chore** rather than a milestone.

A map can only be authored on one of the 16 because `save_map` resolves its
`TileSet` through `map_baker._get_or_build_tileset`, which needs the atlas PNGs
on disk.

**This is the single most likely first failure a new user hits**, and it is
recoverable only if the tool says so precisely. The 16:

```
building_frlg__  generic_building_1 · generic_building_2 · lab · mart · museum
                 pewter_gym · pokemon_center · school · silph_co · viridian_gym
general_frlg__   celadon_city · digletts_cave · pallet_town · pewter_city
                 viridian_city · viridian_forest
```

### 2.2 A sensible fill IS derivable — for all 16

Taking the most common metatile that is walkable, plain (`MB_NORMAL`) and at
elevation 3, across every imported map using that pair:

| pair | fill | | pair | fill |
|---|---|---|---|---|
| `general_frlg__viridian_city` | **8** | | `building_frlg__pokemon_center` | **641** |
| `general_frlg__pewter_city` | **8** | | `building_frlg__generic_building_2` | **265** |
| `general_frlg__celadon_city` | **8** | | `building_frlg__silph_co` | **820** |
| `general_frlg__viridian_forest` | **9** | | `building_frlg__lab` | **129** |
| `general_frlg__pallet_town` | **662** | | *(all 16 resolve)* | |

**So the tool never has to ask for a metatile id to make a usable map**, which
is what keeps it usable before M27M6's picker exists.

### 2.3 ⚠️ A border wall is COSMETIC, not correctness — and is NOT cleanly derivable

Two findings that point the same way:

- **`MapManager` already answers unowned cells as solid** (M27C2's fail-safe),
  and the border-skirt renderer was removed, so off-map is void. A map with no
  wall is fully playable; it just shows black at the edge.
- **The wall is a guess.** Outdoor pairs share the `general_frlg` primary, so
  the top solid tiles really are the tree block (`20/21/28/29`) — but "the four
  most common solid metatiles" is **not the same thing as a coherent 2×2
  block**, and for the ten `building_frlg` pairs the top solid tile is `8` on
  nine of them, which is an interior wall segment rather than anything tileable.

Xanadu's own wall used `20/23/28/31`, a *different* tree quad from the measured
top four — both render correctly, which is precisely why an automatic choice
here cannot be trusted.

### 2.4 The connection hazards are real, and both bit this session

- **Reciprocal offsets must be equal and opposite**, and the reciprocal
  direction must be the opposite one. Either wrong stitches the maps at a slant
  that looks plausible until walked.
- ⚠️ **Overlap is silent and nondeterministic.** Xanadu at a naive offset would
  have overlapped Pewter City (which sits at `(-12, -40)` relative to Route 2),
  and `chunk_owning()` is first-match-wins over an **unordered** Dictionary — so
  an overlapping pair answers differently run to run. This was avoided by hand,
  by computing Pewter's rect on paper. A tool must do it.

### 2.5 ⚠️ An authored map CANNOT have wild encounters — IN SCOPE (Rob, 2026-08-09)

`data/land_encounters.json` is keyed by map name — **192 maps**, generated from
the reference — and an authored map is in none of them. So grass painted on
Xanadu produces no encounters, silently. **Rob's call: authored maps need
grass**, so this becomes tier C3 rather than a footnote.

**The shape to fill**, measured from `Route2_Frlg`'s own entry: a table is
`{encounter_rate: int, slots: [{dex, min, max} x15]}`, and the 15 slot
probabilities are GLOBAL (`slot_rates`, `[15,15,15,10,10,10,5,5,4,4,2,2,1,1,1]`
percent), not per map. So an authored table is one integer plus fifteen
species/level rows — small, and hand-authorable.

**The seam is small too.** `WildEncounters` is all-static and reads one JSON
through `table_for(map_name)`; the single call site
(`overworld.gd:1450`) already holds both `map_name` and the `MapManager` that
owns the map's `MapData`. So an optional `MapData` argument threaded through
`should_encounter`/`build_wild_party`, defaulting to null, changes nothing for
the 192 imported maps.

---

## 3. What the tool must actually do

**Create:** validate the name, refuse an existing one, resolve the pair (§2.1),
resolve or accept the fill (§2.2), build, mint the `uid`, save both artifacts,
and register the `MAP_AUTHORED_*` constant.

**Connect:** add the edge to both maps, compute the reciprocal, check for
overlap against every chunk reachable from the host, and save both `MapData`.

---

## 4. Decisions, with recommendations

### D1 — CLI, editor dialog, or both? **Recommend: BOTH, in one pass.**

⚠️ **REVISED 2026-08-09 after Rob asked why. The first version of this section
recommended "CLI now, dialog deferred" and it does not survive examination —
the reasoning is kept below because the way it was wrong is the useful part.**

It argued from the plugin's defect history: four shipped defects, therefore
keep new surface out of the plugin. **That over-generalises.** All four — the
editor clip-rect bug, click-to-select disabling itself, the save stall, the
undo defect — are in `_forward_canvas_gui_input` or save timing. The **Name
Usage dialog has had zero**. A modal with text fields is a different risk class
from viewport input forwarding, and the latter's record was used to argue
against the former.

**And the workflow argument cuts the other way**, which §1's own table already
said: creating a map is step 1 of 6 and the other five are editor-resident, so
a terminal round-trip lands at exactly the worst point.

So: the logic goes in `MapAuthoring` (it already does), a **thin CLI driver**
earns its place as the TEST surface — headless assertions need it, and batch
creation should stay consistent with `map_baker` and `check_bake_diff` — and
the **dialog is the USER surface**, shipped in the same pass. It is a presser
over the same two functions, so it is not a second implementation and carries
almost no logic. That is the same split `ScriptPreview`/`entity_inspector` and
`MapOverlay`/`plugin` already use.

### D2 — ⚠️ Who is allowed to write `authored_maps.gd`? **DECIDED (Rob, 2026-08-09): append-only, guarded.**

This is the sharpest question in the scope. That file is **deliberately
hand-owned** — its whole reason to exist is that `map_constants.gd` is generated
and would erase authored entries. A tool that rewrites it makes it
generated-ish, which is the property being protected.

Three options:

1. **Append-only, guarded** — ✅ **CHOSEN.** The tool appends one line, refuses
   if the constant already exists, and never touches or reorders an existing
   one. The file stays hand-editable and no generator ever owns it. ⚠️ The
   guard is the load-bearing half: an append that silently overwrote a
   duplicate would reintroduce exactly the erasure this file exists to prevent,
   just by a different hand.
2. **Print, don't write** — the tool emits the line for you to paste. Safest,
   and annoying exactly once per map.
3. **Split it** — a plain data list the tool owns, wrapped by a hand-owned
   accessor. Cleanest in theory, an extra file for one dictionary in practice.

### D3 — An unbuilt tileset pair: refuse or auto-render? **Recommend refuse, precisely.**

Auto-rendering means invoking the Python importer and a Godot `--import` pass
from inside a Godot tool — two process launches and a resource-cache reload
mid-run. Refusing with the exact command to run is honest and cheap. ⚠️ The
error must name **which** pairs are available, or §2.1 becomes a guessing game.

### D4 — Border wall? **DECIDED (Rob, 2026-08-09): the tool does not draw walls at all.**

Rob paints them. §2.3 already showed the wall is cosmetic (unowned cells answer
solid, so a wall-less map is fully playable) and that the 2x2 quad is a guess
the tool cannot make honestly on indoor pairs. So there is no `--border` flag
and no quad argument — the created map is a plain rectangle of the derived fill,
and walls are step 3 of the workflow like any other art.

⚠️ This also removes `fill_rect_quad` from the tool's surface. The function
stays on `MapAuthoring` (Xanadu used it and it is covered), but nothing in the
creator calls it.

### D4b — Where does an authored encounter table LIVE? **DECIDED (Rob, 2026-08-09): a JSON side file, like every other encounter table.**

`data/authored_encounters.json`, hand-owned, merged on a miss — the same
delegate-on-miss shape as `AuthoredMaps`/`MapConstants`.

⚠️ **THIS OVERRIDES A RECOMMENDATION FOR `MapData` FIELDS, AND ROB'S REASON IS
BETTER THAN THE RECOMMENDATION WAS.** This file's own data rule (CLAUDE.md,
"TWO LAYERS, deliberately") is *full dataset in JSON, implemented behaviour in
`.tres`* — and an encounter table is dataset, not behaviour. Every other
encounter table in the project is already JSON. The `MapData` proposal weighed
rename-safety and Inspector editability and simply did not weigh the standard
already in force, which is the stronger argument: a second storage shape for
one kind of data would be the drift this project keeps paying for, arriving as
a convenience.

**The one real objection survives and is cheap to answer.** A name-keyed side
table detaches silently if an authored map is renamed. So C3 ships a guard:
**every map name in `authored_encounters.json` must resolve to a real map**,
reported loudly if not. That converts the failure from "grass quietly stopped
working" into a named error, which was the whole of the objection.

### D5 — Overlap: warn or refuse? **Recommend refuse unless `--force`.**

§2.4. A silent nondeterministic bug is worth a hard stop, and `--force` keeps
the escape hatch for someone who knows better.

### D6 — Naming. **Recommend: refuse to overwrite; no suffix rule.**

Reference maps all end `_Frlg`; `XanaduNursery` does not, which reads as a
useful accident rather than a rule. Worth NOT making it a rule — the map name is
already namespaced by its constant, and forcing a suffix on authored content
would be inventing a convention with no consumer.

### D7 — Warps too? **Recommend no, connections only.**

A warp is a `Warp` **node in the scene**, not a `MapData` field, so it is a
different mechanism with a different failure mode (`warp_id` is positional and
addressed BY POSITION). Interiors reached by a door are a real want and deserve
their own pass.

---

## 5. Proposed split

- **C1 — create.** Name/pair/fill validation, build, uid, constant
  registration. Ends with a new map openable in the editor and paintable.
- **C2 — connect.** Reciprocal edge, offset sign, overlap check against the
  reachable graph. Ends with the new map walkable from its neighbour, once its
  own doorway is painted.
- **C3 — authored encounters.** The `MapData` fields, the delegate-on-miss
  lookup, and the optional `MapData` threaded to the two `WildEncounters` entry
  points. Independent of C1/C2 — it is a property of a map, not of creating
  one — and equally useful to a map created by hand.

Per D1 the **editor dialog ships inside C1/C2** rather than as a later tier: it
is a presser over the same functions, and deferring it would leave the one
editor-resident step of the workflow living in a terminal.

C1, C2 and C3 are independently useful and independently testable; C2 carries
the real invariants (reciprocity, overlap), so it is where the assertions
belong.

---

## 6. Deliberately NOT covered

- **The metatile/behaviour picker** — M27M6. This tool avoids needing it by
  deriving a fill, but choosing art still means either the tile palette or a
  numeric id.
- **New art** — M27M7.
- **Scripts, events and entities on an authored map** — an authored map has no
  `script_label`s and no compiled entry in `map_scripts.json`; authoring those
  is `field_script_source/` + `scripts/events/`, a separate road.
- **Warps / interiors** — D7.
- **Batch or procedural generation** — no consumer.

---

## 7. Open questions for Rob

1. ~~**D2** — may the tool write `authored_maps.gd`?~~ **ANSWERED: append-only,
   guarded.**
2. ~~**D1** — CLI only, or dialog too?~~ **ANSWERED: both, in one pass — the
   CLI as the test surface, the dialog as the user surface.**
3. ~~**D4** — is a cosmetic border worth a flag?~~ **ANSWERED: no — Rob paints
   walls, so the tool draws none.**
4. ~~**§2.5** — do authored maps need wild encounters?~~ **ANSWERED: yes —
   scoped as tier C3.**
5. ~~**D4b** — encounters on `MapData` or a side JSON?~~ **ANSWERED: JSON,
   matching every other encounter table and this project's own two-layer data
   rule.**

**Nothing open. The tool is fully scoped and ready to build.**
