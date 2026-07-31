# M27M — Trimmed TileSet recon

**Status:** recon only. Nothing implemented. Rev 1, 2026-07-30.

Scope: stop calling `create_tile()` for every cell of every atlas and create
only the tiles maps actually place. This is the M27M sub-tier that closes the
first-visit hitch Rob reported during M27D, and it interacts directly with
M27M1 (custom data layers), M27M2 (shared per-pair TileSets, shipped) and
M27M3/M7 (authoring and new art).

Every number below was measured this session against the real artifacts.
Nothing here is extrapolated from a sample unless it says so.

---

## 1. How it works today

`map_baker._build_tileset(atlas)` builds one `TileSet` per tileset PAIR:

```gdscript
for sid in range(3):                       # sid == plane (Ground/Objects/Overhangs)
    srcatlas.texture = load("<atlas>_<plane>.png")
    for y in range(tex.height / 16):
        for x in range(tex.width / 16):
            srcatlas.create_tile(Vector2i(x, y))     # EVERY cell, unconditionally
    ts.add_source(srcatlas, sid)
```

Measured geometry (`general_frlg__pallet_town_frlg`, and uniform across pairs):

| | |
|---|---|
| atlas texture | 512 x 368 px |
| grid | 32 x 23 = **736 tiles per plane** |
| three planes | **2208 `create_tile()` calls per pair** |
| 60 pairs region-wide | **132,480 calls** |

A metatile id resolves to a fixed atlas coordinate, in two places:

```gdscript
var coords := Vector2i(mid % ATLAS_COLS, int(mid / ATLAS_COLS))   # ATLAS_COLS = 32
layers[plane].set_cell(cell, plane, coords)                        # source_id == plane
```

**The coordinate is derived from the id and nothing else.** That is the single
most important structural fact for this work: trimming removes tiles but never
moves one, so no cell reference anywhere has to change.

---

## 2. Is trimming real, and what does it buy

Built a genuinely trimmed twin of the Pallet Town pair by `remove_tile()`-ing
every coord no map places, then timed both against each other with the atlas
textures already warm (so this measures tile construction, not PNG decode):

| | tiles | load | file |
|---|---|---|---|
| full | 2208 | **15.25 ms** | 25 KB |
| trimmed | 501 | **1.71 ms** | 6 KB |
| | 4.4x fewer | **8.9x faster** | 4.2x smaller |

The time gain (8.9x) is larger than the tile-count gain (4.4x) because the
resource file shrinks too — less to parse as well as less to construct.

Region-wide, summing each pair's own distinct usage:

| | |
|---|---|
| tile definitions needed | **11,036** |
| x3 planes | **33,108 calls** vs 132,480 today — **4.0x** |
| the 14 corridor pairs | 1,506 defs = 4,518 calls, **~31 ms for all fourteen** |

That last line is the decision-maker. **Building every tileset the 32-map
corridor uses would cost about as much as ONE cold tileset costs today**
(~15-30 ms). Warming the whole region is ~225 ms, once, at boot.

### Why this beats the alternatives already on the table

- **Primary/secondary split** (source's own architecture) is worth 6.8x on
  paper, but needs a re-key of `source_id`, a re-bake of all 421 maps, and a
  new atlas layout. Trimming is worth 4.0x with no re-bake at all (§4).
- **Preloading per gate zone** relocates cost rather than removing it, and the
  measured corridor cost after trimming (31 ms) is small enough that zone
  bookkeeping stops being worth writing.
- **Binary `.res` tilesets** were tested and rejected: 4% faster, 2.6x LARGER.
  The cost is tile construction, not text parsing — no format change touches it.

---

## 3. THE FAILURE MODE IS SILENT

Measured directly. Given a `TileSet` where coord (5,5) was never created:

```
layer.set_cell(Vector2i(0,0), 0, Vector2i(5,5))
  source_id read back : 0          <- accepted
  coords    read back : (5, 5)     <- stored faithfully
  get_cell_tile_data  : null       <- renders NOTHING
```

`set_cell` does not reject the call, does not warn, and does not clear the
cell. The cell is stored, and simply draws nothing. An error surfaces only if
something later asks for tile data — which nothing in this project does
(confirmed: no `get_tile_data`/`get_tiles_count`/`has_tile` call site exists
outside the test suite).

**So an over-aggressive trim produces invisible terrain with no diagnostic.**
This is the same class of defect as C3's half-blank border skirt and D1's
vertical-strip sprite read: internally consistent, screenshot-only detectable.
Every hazard in §5 is a way of arriving at exactly this failure.

Consequence for the build: the trim step must be able to *prove* its own
coverage, not just produce a smaller file. See §7.

---

## 4. What trimming does NOT touch

Checked rather than assumed:

- **Baked scenes need no re-bake.** M27M2 made the TileSet an `ext_resource`
  (`[ext_resource type="TileSet" path="res://assets/map_tilesets/....tres"]`),
  so a scene references it by path. Trimming rewrites the `.tres` only; all 32
  baked scenes are untouched and stay byte-identical.
- **`check_bake_diff.py` is unaffected** — it compares scenes, not tilesets.
- **The overlay editor is unaffected** — `map_overlay.gd` has zero TileSet
  references; every mode reads `MapData`, not tiles.
- **The atlas PNGs are unchanged.** All the art stays on disk exactly as now;
  only the tile *definitions* shrink. This is what makes the operation
  reversible (§6).
- **No consumer iterates tiles**, so a sparse source breaks nothing.
- **M27M1 (behavior custom data) gets cheaper, not harder** — only used tiles
  need a behavior value written.

---

## 5. Hazards, in descending sharpness

### 5.1 The trim set must be region-wide, not per-bake

`_get_or_build_tileset` builds a pair's TileSet the first time any map needing
it is baked, then reuses the saved file forever. If the trim set came from the
map being baked, then:

> bake Pallet Town alone -> tileset trimmed to Pallet's 98 metatiles -> later
> bake Route 1 (same pair, 50 metatiles, some of them different) -> Route 1's
> extra ids were never created -> **Route 1 renders with holes, silently.**

**Rule: compute the trim set per PAIR from all 421 imported `assets/maps/*.json`,
never from the map currently being baked.** The import data is complete
regardless of what is baked, so this removes the ordering hazard entirely
rather than managing it.

This also means the trim step is not really part of the bake — it is its own
pass over the import corpus. See §7.

### 5.2 Border metatiles are used and are NOT in the map body

The skirt (`map_manager._paint_skirt`) paints `MapData.border` through the
identical coord math, into layers sharing the same TileSet. A trim computed
from `metatile[]` alone would blank those cells.

Measured: **5 border ids across the region appear in no map body**, in 5 pairs
(`island_harbor`, `underground_path`, `trainer_tower`, `tanoby_ruins`,
`power_plant`). One tile each — small, real, and exactly the kind of
single-cell omission that reads as a rendering glitch rather than a build bug.

**Rule: used set = `metatile[] | border[]` per pair.**

### 5.3 The authoring conflict — the genuine one

`_build_tileset` creates every tile *on purpose*: it is what lets Godot's own
tilemap editor paint any metatile in the pair (recorded in M27M's own scoping
note). Trimming breaks that, and it is circular:

> a tile that is not placed anywhere is not created -> it cannot be painted ->
> so it can never become placed.

This is a hard conflict with M27M3/M27M5/M27M7, not a detail. Options in §6.

### 5.4 Two hand-kept copies of the routing rule

`map_baker.ROUTING` and `map_manager.ROUTING` encode the same layer-type ->
plane mapping in **different shapes**:

```gdscript
# map_baker.gd:34            # map_manager.gd:76
0: [[0, 1], [1, 2]]          0: [1, 2]
1: [[0, 0], [1, 1]]          1: [0, 1]
2: [[0, 0], [1, 2]]          2: [0, 2]
```

Semantically identical (the baker's `pair[1]` is the manager's element), but
this is the same two-implementations-of-one-rule shape that produced the
`check_bake_diff` false positive. `ATLAS_COLS = 32` is likewise duplicated.
A trim pass becomes a THIRD consumer of this rule and should not add a fourth
copy — fold it into one shared place while here.

### 5.5 Per-plane trimming is available but should not be taken first

Each metatile routes to exactly 2 of the 3 planes, so keeping its coord in all
three (as the probe above did: 167 ids -> 501 tiles) leaves ~33% on the table;
a per-`(id, plane)` trim would land near 334. CLAUDE.md's own measurement says
layer type varies by placement **0%**, so it is safe in principle.

Recommend NOT doing this in the first pass. It doubles the state the trim set
must carry, makes the coverage proof harder, and the whole-coord trim already
gets 8.9x. Revisit only if boot time ever actually matters.

---

## 6. Design: trim is a reversible transform, not a second artifact

The obvious response to §5.3 is two files per pair (a full authoring one and a
trimmed runtime one). That is worse than it looks: the scene references one
path, so shipping the other means either a swap step or a second path, and the
two drift.

The better framing, and the one this recon recommends:

> **The atlas PNG is the invariant. `expand` and `trim` are two idempotent
> operations on ONE `.tres`.**
>
> - `expand(pair)` -> `create_tile` for every atlas cell (today's behaviour)
> - `trim(pair, used)` -> `remove_tile` for every coord not in `used`
>
> Both were exercised this session and both work. The file at
> `assets/map_tilesets/<pair>.tres` is simply in one state or the other.

That makes the authoring story a workflow rather than an architecture:

1. Author wants to paint new tiles in a pair -> run `expand` on that pair
2. Paint freely; the map now places ids that were previously unused
3. Re-run the trim pass; the newly-placed ids are in the import/scene data, so
   they survive the trim automatically

Only step 1 is manual, only for the pair being edited, and only while editing.

**A key asymmetry that makes this safe:** `expand` can never break anything
(it only adds tiles), while `trim` can (it removes them). So the failure
direction is always "shipped a bigger file than needed", never "shipped a
broken map" — provided the trim's own coverage check (§7) runs.

---

## 7. Proposed sub-tiers

**M27M-T1 — the trim pass, plus its coverage proof.** A `@tool` script (or a
`map_baker` mode) that, for each of the 60 pairs, unions `metatile[] | border[]`
across all 421 imported JSONs, then rewrites the pair's `.tres` keeping only
those coords. **It must also verify**: for every baked scene, every
`(source_id, atlas_coords)` present in its `tile_map_data` still resolves to a
real tile after the trim. That check is the whole defence against §3, and it
is cheap — the scenes are on disk and `has_tile()` answers directly.

Ship the coverage check in the same change as the trim, never after. A trim
without it is a silent-failure generator.

**M27M-T2 — `expand`, and the ordering guard.** The inverse operation, plus a
guard in `_get_or_build_tileset` so a bake can never silently consume a trimmed
tileset that predates a newly-imported map. Cheapest correct guard: record the
trim's source corpus size/hash in the TileSet's own metadata and refuse (or
auto-re-trim) on mismatch.

**M27M-T3 — fold the duplicated rule.** One `ROUTING`/`ATLAS_COLS`, consumed by
baker, manager and trim. Do this while all three are open, not later.

**Deliberately out of scope:** per-plane trimming (§5.5), the primary/secondary
split, and any change to the atlas PNGs.

---

## 8. Decisions for Rob

1. **Where does the trim run?** A separate `scripts/`-style pass over the
   import corpus (recommended — matches §5.1's rule and keeps the baker simple),
   or a `--trim` mode on `map_baker`?
2. **Does the repo store trimmed or expanded tilesets?** Recommend **trimmed**,
   since that is what ships and what makes the 8.9x real; `expand` is a local,
   temporary authoring state that gets trimmed back before commit.
3. **When?** This is independent of D4/D5 and does not block the slice. It
   could equally land now (the hitch is real and Rob has felt it) or after the
   slice with the rest of M27M.

---

## 9. Verification plan when this is built

- **The coverage proof is the primary test**, not an afterthought: every
  `(source_id, coords)` in every baked scene resolves post-trim.
- A deliberate **break test**: remove one genuinely-used id from the trim set
  and confirm the coverage check fails and names it. Per this project's own
  standing discipline, a check that has never been shown to fail is not
  evidence.
- **Border coverage specifically**, using one of the 5 pairs from §5.2 as the
  fixture — a body-only trim must fail there.
- **A real screenshot**, because §3's failure mode is invisible to every
  assertion that does not think to ask. C3's skirt bug passed a 2432-of-2432
  cell count while rendering every other row blank.
- Re-run `check_bake_diff --all` to confirm 32/32 still reproducible (expected
  unaffected per §4, so this is a guard, not a hope).
