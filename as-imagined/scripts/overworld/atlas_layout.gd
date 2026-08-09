@tool
class_name AtlasLayout
extends RefCounted

## [M27M Part C] Where a metatile lives in the atlas — the ONE place that knows.
##
## ⚠️ **THIS EXISTS BECAUSE THE PROJECT ALREADY HAS TWO HAND-KEPT COPIES OF THE
## ROUTING RULE AND MUST NOT GROW A THIRD OF ANYTHING.**
## `docs/m27m_trimmed_tileset_recon.md` §5.4 records that `map_baker.ROUTING`
## and `map_manager.ROUTING` encode one rule in two shapes, and that
## `ATLAS_COLS = 32` is likewise duplicated. Part C changes the id→tile mapping
## itself, so a second copy of THAT would be the same mistake in a place where
## the failure is silent (see below). Both the baker and the manager call in
## here.
##
## ## What changed, and why
##
## Kanto uses **two** primary tilesets — `general_frlg` (outdoor) and
## `building_frlg` (indoor) — plus one small map-specific secondary each. The
## atlases used to be a flattened composite of both, so the primary's 640
## metatiles were re-rendered into every pair:
##
##   measured over the 20 rendered pairs — **81% of all atlas area was the
##   shared primary, stored 20 times over.** `building_frlg__generic_building_1`
##   was 21 rows: **20 primary, 1 secondary.**
##
## Split, the primary is stored once per primary tileset and the secondary once
## per pair.
##
## ⚠️ **EXCEPT THAT A PRIMARY IS NOT ALWAYS SHAREABLE, WHICH THIS DESIGN DID
## NOT PREDICT.** On hardware the two tilesets share ONE tile/palette address
## space, so a primary metatile may name tile index >= 640 or palette slot >= 7
## and pick up whatever the paired secondary loaded there. Measured: **0 of
## `general_frlg`'s 640 primary metatiles do this, and 56 of
## `building_frlg`'s do** — placed on 208 real cells region-wide, one per
## Pokemon Centre in the corridor. Those pairs therefore get their own
## `<pair>_primary_<plane>.png` and the baker prefers it over the shared name.
##
## The id -> (source, coords) rule below is UNAFFECTED — this changes only
## which FILE backs the primary source, never which source or coord an id
## resolves to, which is why it stays a pure function of the id.
##
## ## ⚠️ The failure mode is SILENT
##
## `docs/m27m_trimmed_tileset_recon.md` §3 measured it directly: `set_cell` with
## a coord whose tile was never created is **accepted**, stores faithfully, and
## **renders nothing** — no warning, no error, and nothing in this project ever
## asks for tile data. So a wrong source id or a wrong coord here does not
## crash; it produces invisible terrain. Every consumer must resolve through
## these two functions rather than re-deriving them.


## Atlas grid width, in tiles. Both halves use the same width.
const COLS := 32

## `NUM_METATILES_IN_PRIMARY_FRLG` (`include/fieldmap.h`). Ids below this belong
## to the shared primary tileset; ids at or above it belong to the pair's own
## secondary and are re-based by exactly this much.
##
## ⚠️ **THE FRLG SPLIT, NOT THE HOENN ONE** (512/512/6). Reading the Hoenn
## constant here would mis-route every id in 512..639 to the secondary atlas,
## where it would land on a coord that exists but holds different art — so the
## map would render, and render *wrong*, which is worse than not rendering.
const PRIMARY_METATILES := 640

## Source ids 0-2 are the primary's three planes, 3-5 the secondary's. Chosen so
## `plane` still indexes the low half unchanged, which keeps the primary's
## source ids byte-identical to the pre-split convention.
const SECONDARY_SOURCE_BASE := 3


## Which TileSet source holds `metatile_id` on `plane`.
static func source_id(plane: int, metatile_id: int) -> int:
	return plane + (0 if metatile_id < PRIMARY_METATILES else SECONDARY_SOURCE_BASE)


## Where `metatile_id` sits within whichever atlas holds it.
##
## ⚠️ Re-based for the secondary half. Passing a raw id straight through — the
## obvious mistake — indexes far past a secondary atlas that is only a few rows
## tall, and `set_cell` accepts it silently.
static func coords(metatile_id: int) -> Vector2i:
	var local := metatile_id
	if metatile_id >= PRIMARY_METATILES:
		local = metatile_id - PRIMARY_METATILES
	return Vector2i(local % COLS, int(local / COLS))


## True when this id lives in the shared primary rather than the pair's own art.
static func is_primary(metatile_id: int) -> bool:
	return metatile_id < PRIMARY_METATILES


## The INVERSE: which metatile a painted cell is showing. -1 when the pair does
## not describe one.
##
## [M27M4] Needed because hand-painting happens in Godot's own TileMap editor,
## which knows only about sources and atlas coords — so recovering "which
## metatile did the author just place" means undoing `source_id()` and
## `coords()` together. It lives here rather than in the overlay for the reason
## this whole class exists: a second, hand-kept copy of half the rule is how the
## two ends drift apart, and here the drift would be silent in BOTH directions
## (a paint recorded as the wrong metatile, or a correct paint ignored).
##
## ⚠️ The bound is not decoration. A primary source can only hold ids 0..639,
## because the primary atlas is exactly 20 rows — a coord below that row range
## is a cell the author painted from a source that cannot contain it, and
## answering with an id anyway would write a plausible wrong number into
## `MapData.metatile` and re-key the cell's behaviour off it.
static func metatile_id(source_id: int, atlas_coords: Vector2i) -> int:
	if source_id < 0 or source_id >= SECONDARY_SOURCE_BASE * 2:
		return -1
	if atlas_coords.x < 0 or atlas_coords.y < 0 or atlas_coords.x >= COLS:
		return -1
	var local := atlas_coords.y * COLS + atlas_coords.x
	if source_id < SECONDARY_SOURCE_BASE:
		return local if local < PRIMARY_METATILES else -1
	return PRIMARY_METATILES + local


## The primary tileset's name for a pair slug — `building_frlg__lab_frlg` ->
## `building_frlg`. The atlas filenames depend on this being exactly the
## generator's own `atlas_slug()` join, so the separator lives in one place.
const PAIR_SEPARATOR := "__"


static func primary_of(pair: String) -> String:
	var i := pair.find(PAIR_SEPARATOR)
	return pair if i < 0 else pair.substr(0, i)
