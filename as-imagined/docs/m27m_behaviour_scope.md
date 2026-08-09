# M27M — tile behaviour: the default, and the brush

**Step 0 + scope, 2026-08-09. Nothing built.** Covers two tiers that were
scoped separately and turn out to be one design:

- **M27M1 (revised)** — a painted tile brings its own meaning. *The default.*
- **M27M6+ (widened)** — paint the meaning by hand. *The override.*

Rob's call, 2026-08-09: **build both.** They cost barely more together than
either alone, and each is the other's safety net.

---

## 0. The problem, stated once

A tile has a **look** and a **meaning**. Paint a grass tile today and you get a
picture of grass that is not grass — no encounters, because
`StepResolver` reads `MapData.behavior`, a per-CELL array nothing updates when
a tile is painted.

The importer wrote 230,619 per-cell notes and they are correct for every
imported map. They are useless for authoring, because a newly painted cell has
no note.

---

## 1. Step 0 findings

### 1.1 The seam is declared and inert

`map_baker.gd:698-700` declares custom data layer 0 as `"behavior"`, `TYPE_INT`.
Parsing a real baked TileSet: **zero tiles carry a value.** `grep` for
`get_custom_data` across `scripts/`, `scenes/`, `addons/` returns **nothing**.
Someone scaffolded this exact seam and stopped.

### 1.2 Behaviour is genuinely per-pair — measured

`Tileset.behavior(mid)` is `attrs[mid] & MASK` — a pure function of the metatile
id within a tileset pair. Verified across **all 421 map JSONs**: 11,031 distinct
`(atlas, metatile)` combinations, **zero conflicting behaviours, zero
conflicting layer types**. So one table per pair is sound.

### 1.3 ⚠️ The per-cell arrays CANNOT supply this, and that reshapes the tier

An atlas holds every metatile in the pair; only a fraction are ever placed.
Measured on `building_frlg__generic_building_1`:

| | |
|---|---|
| tiles in the atlas | **672** |
| metatile ids placed on ANY map using this pair | **207** |
| tiles with no behaviour anywhere in map data | **465** |

**Those 465 are exactly the tiles authoring reaches for.** So the data must come
from the tileset attributes, not from a projection of the per-cell arrays.

### 1.4 ⚠️ And half of M27M1 is already shipped, as a sidecar

`assets/map_atlases/<pair>_layer_types.json` already exists — one entry per
metatile id across `range(ts.count)`, written by the `setmetatile` work for
*precisely this reason*: *"a live script can name any metatile in the pair's
atlas, including ones no imported cell currently uses."* `MapManager.
_layer_type_for(pair, mid)` reads it with a lazy static cache. Tested at
`m27_setmetatile_test` 20/20.

**So M27M1's stated scope ("behaviour + layer type onto the tile") is half done
and done the other way.** Only behaviour is missing.

### 1.5 The editor already shows behaviour and already paints two things

`MapOverlay.Mode.BEHAVIOR` is the DEFAULT view mode — colour-coded with a
legend. `EditMode` is `{NONE, COLLISION, ELEVATION, AUTHOR}`, so collision and
elevation are already paintable with undo, a review backlog, a dirty banner and
a Save affordance (`[M27B Change 2]`).

`MapData` exposes four mutators (`set_attr_explicit`, `set_collision`,
`set_elevation`, `author_cell_with_defaults`) and `behavior` is a plain
`PackedInt32Array` — so a `set_behavior` is a fifth of the same shape.

`attr_explicit` is a `PackedByteArray` bitfield using **2 of 8 bits**
(`COLLISION_EXPLICIT`, `ELEVATION_EXPLICIT`). A third flag fits with no format
change.

---

## 2. Why BOTH, rather than either

**The default alone** means you can never disagree with the tile. A patch of
grass that should not spawn encounters, or a decorative ledge nobody hops, would
be unexpressible.

⚠️ **The brush alone is worse, and this is the load-bearing argument.** Without
a default, every cell of every new map starts as `MB_NORMAL`, so *forgetting* to
paint a cell yields a square that **looks like grass and silently is not**. That
is the exact failure this project has paid for repeatedly — the invisible-until-
played kind. With a default, forgetting means the value is probably right AND
the cell is flagged for review either way.

Measured cost of brush-only: the corridor holds **1,223 `MB_TALL_GRASS` cells**.
A new route is plausibly 300-600 grass cells, hand-painted twice — once for the
picture, once for the meaning.

**Together they are the pattern already built for collision and elevation:**
offer a default, mark it as a guess, surface it in `review_cells()`. This would
be that machinery's third customer, not a new invention.

---

## 3. Part A — the default (M27M1, revised)

### Deliverable

`assets/map_atlases/<pair>_behaviors.json` — a flat array, one entry per
metatile id across `range(ts.count)`, emitted from the same `ts.behavior(mid)`
the atlas PNGs are already built from. **One source of truth, not a second
hand-kept copy of the rule.**

Plus `MapManager.behavior_for(pair, metatile_id) -> int`, mirroring
`_layer_type_for` exactly, including the lazy static cache and the `-1` return
for an unregenerated checkout or an out-of-range id.

### ⚠️ Why a sidecar and not the declared custom-data layer

| | tile custom data | sidecar JSON |
|---|---|---|
| tracked size | a tile line is `0:0/0 = 0` (11 bytes); +2 custom values ≈ +52/tile × 2,016 tiles = **~128 KB per pair**, ~5.5× growth → **~7.7 MB region-wide** | 664 ints ≈ **4 KB per pair** → **~240 KB region-wide** |
| boot cost | grows every TileSet build; `[M27D perf]`'s preload already pays 285-294 ms for 14 pairs | lazy; one `Dictionary` lookup |
| data shape | ⚠️ **three copies of one fact** — a metatile routes to 1-2 planes, so you would set all 3 source tiles at the same coords | one entry per metatile id |
| precedent | none — nothing reads custom data anywhere | proven and tested for layer type |

The custom-data route's one real advantage — reading a painted cell without
knowing its pair — **does not apply**: `MapData.atlas` is always in hand, so the
pair is never unknown. And `M27M6`'s own note already records that route's
weakness (*"Godot's custom data layers are plain typed ints with no enum
hint"*).

**Disposition of the inert layer:** recommend deleting the declaration in the
same pass, so nothing looks half-built. ⚠️ It churns 14 tracked `.tres` (60 at
full import) for a cosmetic gain — flag it and let Rob choose. Leaving it costs
nothing but a comment.

### Where the default is consumed

**Not here.** Part A ships a lookup with no caller; `M27M4` is what reads it
when it detects a painted id and writes the result into `MapData.behavior`.
Shipping it alone is still worth it — it closes a real data gap and is
independently testable — but it changes nothing observable on its own, and the
tier note should say so plainly rather than implying the brush works after it.

### Testing

The roster guard is the valuable one, matching `m27i_item_identity_test`'s
E.02/E.03 shape: **for every pair, every metatile id in the atlas resolves to a
behaviour, and it equals the value the per-cell arrays already carry wherever
that id is actually placed.** That cross-check is what proves the sidecar and
the imported cells cannot disagree — 11,031 real comparisons available.

---

## 4. Part B — the behaviour OVERRIDE (absorbs M27M6)

⚠️ **RE-SCOPED 2026-08-09, Rob's call: *"I don't need the picker if I have the
sync button and then later have a behavior overwrite ability."*** Two changes
to what follows, and the section is kept because its mechanism is unchanged —
only its PURPOSE and its urgency moved.

**No metatile picker will be built.** Godot's own tile palette is already a
visual picker, and `Sync Painted Tiles` (M27M4) makes what you paint with it
real. M27M6 therefore keeps only its narrow half — a named dropdown for
choosing a BEHAVIOUR — and merges here, because a dropdown with nothing to
paint into and a brush that takes raw ints are each useless alone.

**And this is an OVERRIDE, not an authoring path.** Behaviour follows the
metatile automatically and is correct by construction for every Kanto tile, so
this is the escape hatch for when the derived answer is wrong — and the only
way to tag behaviour at all on M27M7's new art, which has no sidecar entry.
Smaller than "the behaviour brush" sounds, and the reason it now sits after
`pokemart`.


### Deliverable

1. `EditMode.BEHAVIOR` alongside `COLLISION`/`ELEVATION`, with a
   `paint_behavior` value, routed through the existing `apply_edit`.
2. `MapData.set_behavior(x, y, value)` — a fifth mutator of the same shape.
3. `AttrFlag.BEHAVIOR_EXPLICIT`, the third bit of eight.
4. The picker — the only genuinely new UI.

### ⚠️ The default for behaviour comes from the TILE, not the neighbour

`author_cell_with_defaults` seeds collision and elevation from
`_nearest_neighbour`, because those are properties of the POSITION (measured:
52.0% / 52.1% placement variance). **Behaviour is a property of the TILE** (0%
variance, §1.2), so seeding it from a neighbour would be wrong in exactly the
cases authoring cares about — painting one grass tile into a path would inherit
`MB_NORMAL` from the path beside it.

So `author_cell_with_defaults` needs a behaviour branch that reads
`behavior_for(atlas, metatile[i])` instead. **This is the one place the two
parts genuinely interlock**, and is why Part A should land first.

### The picker, sized from real data

83 distinct behaviours region-wide, 45 in the corridor — but the distribution is
extremely skewed:

| rank | id | name | cells | cumulative |
|---|---|---|---|---|
| 1 | 0 | `MB_NORMAL` | 143,605 | 62.3% |
| 2 | 8 | `MB_CAVE` | 32,292 | 76.3% |
| 3 | 21 | `MB_OCEAN_WATER` | 31,501 | 89.9% |
| 4 | 2 | `MB_TALL_GRASS` | 5,303 | 92.2% |
| 5 | 44 | `MB_FAST_WATER` | 2,831 | 93.5% |
| 6 | 50 | `MB_IMPASSABLE_NORTH` | 2,125 | 94.4% |
| 7 | 200 | `MB_CYCLING_ROAD_PULL_DOWN` | 2,041 | 95.3% |
| 8 | 33 | `MB_SAND` | 1,491 | 95.9% |
| 9-12 | 12 / 59 / 45 / 23 | mountain top, jump-south ledge, cycling water, shallow water | | **97.5%** |

**In the corridor it is starker still**: `MB_NORMAL` 88.8%, `MB_TALL_GRASS`
7.0%, `MB_JUMP_SOUTH` 1.6% — three values cover **97.4%** of everything.

So the picker is **a short favourites list over a long tail**, not a 240-entry
menu: ~12 named entries, plus the full list behind it.
`MetatileBehavior.NAME_BY_ID` is already generated from source and is exactly
the table it needs.

⚠️ **The names are the point.** Painting a raw `59` is unreviewable; painting
`MB_JUMP_SOUTH` is self-documenting, and the review backlog becomes readable.

### Ledges deserve their own affordance

`MB_JUMP_*` is eight behaviours and Kanto uses **three** (S/W/E — measured at
`[M27B]`). They are also the behaviour whose direction is easiest to get wrong
and hardest to spot, since a wrong-facing ledge simply refuses. Worth grouping
in the picker rather than leaving in the tail.

---

## 4b. Part C — atlas deduplication *(Rob's observation, 2026-08-09)*

> *"The tilesets only use 1 shared indoor/outdoor main tileset for each map plus
> one city specific smaller tileset. Is this represented in our atlases?"*

**The model is exactly right, and the answer is: represented in the NAME, not in
the STORAGE.**

### What is actually on disk

An atlas is named `<primary>__<secondary>`, so the pairing is visible — but the
PNG is a **flattened composite of both**, re-rendered per pair. Measured across
the 20 pairs the corridor has rendered:

| | |
|---|---|
| distinct **primaries** | **2** — `general_frlg` (outdoor), `building_frlg` (indoor) |
| distinct **secondaries** | **20**, one per map/city |
| primary size | **640 metatiles = 20 rows of 32**, in *every* atlas |
| secondary size | **2-8 rows** (94 rows across all 20) |

⚠️ **So 81% of all atlas area is the shared primary, stored 20 times over.**
`building_frlg__generic_building_1` is 21 rows: **20 primary, 1 secondary.**

Corridor totals: **1.28 MB of atlas PNG across 20 pairs / 3 planes**, of which
400 of 494 rows are duplicated primary.

### What deduplicating would save

Split each atlas into a shared primary texture plus a per-pair secondary:

| | cells (all planes) | |
|---|---|---|
| today | 47,424 | 20 pairs × their own full atlas |
| deduped | 12,864 | 2 primaries + 20 secondaries |
| | **3.7× fewer** | ~1.28 MB → ~0.35 MB |

Projected region-wide (60 pairs, secondary rows scaled): **~4.6×**. ⚠️ That is a
projection — only 20 pairs are rendered today, so the other 40 secondaries are
unmeasured.

**The bigger win is memory, not disk.** Today 20 (eventually 60) copies of the
same primary texture are resident once `preload_tilesets()` runs. Deduped, there
are two.

### What it costs

**The change surface is genuinely small** — `source_id == plane` is relied on in
exactly **two production call sites**, `map_baker.gd:134` and
`map_manager.gd:887`, both `set_cell(cell, plane, coords)`. Deduping makes it
six sources (3 planes × primary/secondary) and the mapping becomes
`mid < 640 ? primary : secondary`, with `coords` re-based by 640 for the
secondary half.

⚠️ **But it invalidates every baked scene.** `tile_map_data` stores a source id
per cell, so re-basing source ids means **re-baking all 32 maps** (1.2 MB of
scenes today).

### ⚠️ Which is precisely why this is a NOW-or-never decision

Re-baking is free today and expensive later, and the reason is already recorded
in this project: `_scene_divergence` and `check_bake_diff` exist because a
`--force` re-bake silently overwrites hand-authored content. **Verified this
session: `check_bake_diff --all` reports 32 of 32 reproducible** — so a re-bake
right now loses literally nothing.

The moment Part B ships and Rob paints a real map, that stops being true, and
this reduction goes from "machine time" to "machine time plus a merge nobody
wants". **The same argument the M27 strategy note already makes for doing the
full 421-map import late applies here in reverse: do the format change early.**

### How it relates to M27M-T (the trimmed TileSet)

They are **complementary, not alternatives**, and it is worth not conflating
them:

| | what it removes | measured win |
|---|---|---|
| **M27M-T** (trim) | tile DEFINITIONS never placed anywhere — 11,036 real against 132,480 `create_tile()` calls | **8.9× TileSet load** (1.71 ms vs 15.25 ms on a real twin) |
| **Part C** (dedupe) | duplicated primary PIXELS and textures | **3.7× atlas bytes**, 60 resident textures → 2 |

⚠️ **Dedupe does NOT reduce tile-definition count** — tiles are per-TileSet, so
each pair still calls `create_tile` for the primary's cells even when the
texture is shared. That is M27M-T's job, and `[M27D perf]` already measured why
it matters more: *"PNG decode is not the dominant term — tile construction
is."* So **M27M-T is the load-time win and Part C is the size/memory win.**

### ⚠️ Correction: this option was already evaluated and REJECTED

`docs/m27m_trimmed_tileset_recon.md` §2 (2026-07-30) considered the
primary/secondary split and turned it down: *"worth 6.8x on paper, but needs a
re-key of `source_id`, a re-bake of all 421 maps, and a new atlas layout.
Trimming is worth 4.0x with no re-bake at all."*

**Part C was re-proposed today without reading that recon first** — a Step 0
miss, recorded rather than quietly dropped. Two things have changed since and
both favour Part C:

- **"A re-bake of all 421 maps" describes a world that does not exist.** Only
  **32** are baked and all 32 are reproducible (verified 2026-08-09), so the
  headline objection costs a fraction of what it assumed.
- The recon's own figure is **6.8x**, better than the 3.7-4.6x measured here.

The recon's real advantage over Part C stands and should not be forgotten:
**trimming needs no re-bake at all**, because M27M2 made the TileSet an
`ext_resource`.

**Rob's call, 2026-08-09: Part C is IN. Trimming (M27M-T) is revisited at the
END of M27 work** — which also resolves the §5.3 authoring conflict cleanly,
since by then the authoring shape will be settled rather than speculative.

### ⚠️ BUILT 2026-08-09 — and the headline assumption above turned out to be
### FALSE for one of the two primaries

Part C shipped, but **"the primary is stored once per primary tileset" is only
true of `general_frlg`.** Found by a pixel proof, not by the coverage check —
and it would never have been found by reasoning, because the wrong version
*renders*.

**The mechanism.** On hardware the primary and secondary tilesets are loaded
into ONE tile/palette address space, so a primary metatile is free to name tile
index ≥ 640 or palette slot ≥ 7 and pick up whatever the *currently paired*
secondary put there. That is a deliberate idiom — it is how a shared building
tileset defines a fixture whose art is themed per building. Rendered to a FILE,
such a metatile has no single answer: it genuinely differs per pair.

**Measured across all 421 converted Kanto maps:**

| primary | borrowing metatiles | placed on |
|---|---|---|
| `general_frlg` | **0** of 640 | — (fully shareable) |
| `building_frlg` | **56** of 640 | **208 cells** (0.36% of its maps) |

⚠️ **"BORROWS" IS NOT "RENDERS WRONG", and the first write-up of this conflated
them.** Screenshot verification forced three narrowings, each measured:

1. A borrowing metatile only renders wrong where it **differs from the pair that
   won the race** to write the shared file — alphabetically
   `building_frlg__generic_building_1_frlg`.
2. Across the corridor's 10 building pairs that is **6 cells**, not 208.
3. Of those, a difference confined to a plane that a fully-opaque upper plane
   **overdraws** is invisible on screen.

Metatile **98** in the four Pokémon Centres is exactly case 3 — 254 differing
Ground pixels, **all 254 overdrawn by an opaque Objects plane**. So the Centres
were never visibly wrong, and the earlier claim that they were is **retracted**.

**The real visible corridor impact is Silph Co 1F, cells (30,0) and (30,1),
metatiles 617/625** — differing in Objects *and* Overhangs, with 178 and 78
pixels respectively NOT overdrawn. Pre-fix they render **solid black**;
post-fix they are the notice board beside the stairwell. Confirmed by
screenshot, not by inference.

**Resolution: share only where it is actually shareable.** The generator asks
`Tileset.primary_borrows_from_secondary()`; a borrowing pair writes its own
`<pair>_primary_<plane>.png` and the baker prefers that name over the shared
one. `AtlasLayout` is untouched — this changes which FILE backs the primary
source, never which source or coord an id resolves to, so it stays a pure
function of the id.

**The cost is most of the predicted win**, and the earlier 3.7× figure should
be read as measured under a false assumption:

| | atlas cells | atlas bytes |
|---|---|---|
| before Part C | 47,424 | 1.22 MB |
| predicted (shared primaries) | 12,864 | 0.36 MB — **3.7×** |
| **actual (9 per-pair primaries)** | **28,224** | **0.63 MB — 1.9×** |

`general_frlg` — the outdoor tileset backing 173,560 of the region's 230,619
cells — still dedupes fully across its 11 pairs. `building_frlg`'s 9 do not.

⚠️ **Two proofs ship with this, and each catches what the other cannot.** The
coverage check (suite section **AX**) walks every painted cell of every baked
map and asserts the tile it points at exists — it catches a wrong source or a
wrong coord, and it caught an injected un-rebased coord on 628 cells. It did
**not** catch the borrowing bug, because a wrongly-shared primary points at a
tile that exists and simply holds another building's art. Only the pixel proof
— rendering the un-split composite the old way and comparing halves — found
that. **A "renders and renders wrong" failure needs a pixel comparison; a
"renders nothing" failure needs a coverage walk.**

### Recommendation

**Worth doing, and worth doing before Part B** — but it is a *storage format*
change with no behavioural payoff, so it should be its own tier with its own
re-bake and its own `check_bake_diff` pass, not folded into the behaviour work.

Sequencing: **Part A → Part C → M27M4 → Part B**, putting both format changes
(the sidecar and the atlas split) ahead of the first hand-authored map.

⚠️ **If it is not done before real authoring starts, recommend dropping it
permanently** rather than paying a merge for a 1 MB saving. Half-doing it later
is the worst outcome.

---

## 5. Order, and why

1. **Part A** — the sidecar. Independently testable, no UI.
2. **Part C** — the atlas split, while a re-bake is still free (32 of 32
   reproducible today). A storage change with no behavioural payoff, so it wants
   its own tier and its own `check_bake_diff` pass.
3. **M27M4** — detection + write-back, which is what makes a painted tile mean
   something. (Already scoped: two setters and a comparison; the editing
   apparatus exists.)
4. **Part B** — the brush, so you can disagree with the default.

⚠️ **Part B before Part A is the one order to avoid**: the brush would ship with
no default behind it, which is the silent-failure mode §2 exists to prevent, and
`author_cell_with_defaults` would need writing twice.

---

## 6. Open questions

0. **Is Part C in at all?** It is ~1 MB and 58 fewer resident textures for a
   full re-bake and a source-id convention change. Cheap now, not worth doing
   later — so the real question is in-before-authoring or dropped.
1. **Delete the inert `behavior` custom-data layer, or leave it?** Deleting is
   tidier and churns 14 tracked `.tres` (60 at full import).
2. **Does the brush paint a RANGE or one cell?** Collision and elevation are
   single-cell today. Grass is painted in fields, so a rectangle or
   flood-fill may matter more here than it did there — but it is also the kind
   of thing better judged after using the single-cell version once.
3. **Should painting a tile auto-seed behaviour immediately (M27M4), or only on
   an explicit "seed defaults" pass?** Auto is the friendlier default and is
   what §2 assumes; a manual pass is more predictable. Recommend auto, with the
   review backlog as the safety net it already is.
