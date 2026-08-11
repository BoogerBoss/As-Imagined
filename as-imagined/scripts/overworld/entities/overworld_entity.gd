@tool
class_name OverworldEntity
extends Node2D

## [M27B/M27D] Base class for every placed map event.
##
## The four `map.json` event arrays become six node types over this base
## (docs/overworld_scope.md §32): object_events split three ways by their own
## fields into NPC / TrainerNPC / ItemBall, warp_events into Warp, coord_events
## into Trigger, bg_events into Sign.
##
## The PLACED INSTANCE is the source of truth for spawn data — position,
## elevation, which flag hides it, which script it runs. Identity that outlives
## a placement (a trainer's party, class, name) stays in its own registry and is
## referenced by key.

const CELL := 16

## Tile coordinate, not pixels. `position` is derived from it so a hand-placed
## entity in the editor still snaps to the grid the step resolver walks.
@export var cell: Vector2i = Vector2i.ZERO:
	set(value):
		cell = value
		position = Vector2(value) * CELL
		update_configuration_warnings()

## Per-CELL elevation, same 0–15 space as MapData. Drives draw priority via
## MetatileBehavior.ELEVATION_TO_PRIORITY, which is why entities live in two
## containers rather than one Y-sorted pile (§1.6).
@export var elevation: int = 3

## Visibility flag from the source event (e.g. FLAG_HIDE_VIRIDIAN_CITY_POTION).
## Empty means always present. Nothing consumes this until the flag store lands
## in M27G — carried now because it is placement data and would otherwise have
## to be re-imported later.
@export var visibility_flag: String = ""

## Label of the script this event runs, indexed out of the reference's own
## data/**/*.inc tree at import time, or authored under `scripts/events/`.
@export var script_label: String = ""


## Entity draw priority for this entity's own elevation. Lower draws on top.
func priority() -> int:
	if elevation < 0 or elevation > 15:
		return 2
	return MetatileBehavior.ELEVATION_TO_PRIORITY[elevation]


## [M27Q Q2] Every script label that exists, for the editor-side check below.
##
## ⚠️ **NOTHING VALIDATED `script_label` BEFORE THIS.** `elevation`,
## `movement_type` and `trainer_key` each had a warning; the one field that
## decides whether an NPC says anything at all had none. A typo was silent in
## the editor, silent at boot, and first surfaced as the VM halting
## `UNRESOLVED` when you walked up and pressed A.
##
## ⚠️ **[M27Q Q3] DELEGATES TO `ScriptPreview` RATHER THAN HOLDING ITS OWN
## INDEX.** Q2 built a private one here; Q3's panel needed the same corpus and
## briefly had a second. Two lazy caches of an 8.6 MB file is 226 ms paid twice
## and, far worse, two answers to "does this label exist" that could disagree
## — which is the shape of the bug that had just cost 80 trainers a flag.
## One index, one parse, one answer.
##
## Fails open exactly as `ScriptPreview` does: an unreadable corpus yields an
## empty index and the caller warns about nothing, because a validator that
## cannot see the corpus would otherwise condemn all 2,386 scripted entities
## at once and bury the real warning.
static func _script_labels() -> Dictionary:
	return ScriptPreview.ops_index()


func _get_configuration_warnings() -> PackedStringArray:
	var out := PackedStringArray()
	if elevation < 0 or elevation > 15:
		out.append("elevation %d is outside the 0-15 range the source uses." % elevation)
	if script_label != "":
		var known := _script_labels()
		if not known.is_empty() and not known.has(script_label):
			out.append(("script_label '%s' resolves to no script — neither the "
					+ "imported corpus nor scripts/events/ defines it. This "
					+ "entity will halt with UNRESOLVED when interacted with.")
					% script_label)
	return out


## The sprite sheet id this entity draws with, or "" for one that draws nothing.
##
## Overridden by NPC and ItemBall — the two node types that come from source's
## own `object_events` array and therefore carry a `graphics_id`. Warps,
## triggers and signs are positions, not actors, and have no sprite by design.
func sprite_graphics_id() -> String:
	return ""


## Which way this entity faces when the map loads.
##
## Overridden by NPC. Everything else faces SOUTH, which is source's own resting
## frame (ANIM_STD_FACE_SOUTH == 0) and the right answer for an inanimate object
## whose sheet has a single frame anyway.
func initial_facing() -> String:
	return "SOUTH"


## Build a facing sprite for a graphics id, or null if it cannot be drawn.
##
## Static so the PLAYER shares it — the player is not an OverworldEntity (it is
## spawned by the overworld controller, not placed on a map) but draws from the
## same sheets by the same rules, and two copies of the frame maths is two
## places to get the horizontal-strip layout wrong.
static func make_sprite(graphics_id: String, facing: String) -> Sprite2D:
	var path := ObjectEventGraphics.sheet_path(graphics_id)
	if path == "" or not ResourceLoader.exists(path):
		return null
	var sheet := load(path) as Texture2D
	if sheet == null:
		return null
	var size := ObjectEventGraphics.frame_size(graphics_id)
	var frame: int = int(ObjectEventGraphics.FACE_FRAME.get(facing, 0))

	var spr := Sprite2D.new()
	spr.name = "Sprite"
	spr.texture = sheet
	spr.region_enabled = true
	# Frames run ACROSS, not down: frame N is at x = N * w, y = 0. Measured
	# across all 385 resolved ids — 384 horizontal strips, 0 vertical. A
	# vertical read renders SOUTH correctly (frame 0 sits at the origin either
	# way) and falls off the image for all three other facings, so a screenshot
	# of a resting NPC proves nothing about it.
	spr.region_rect = Rect2(frame * size.x, 0, size.x, size.y)
	# EAST has no frame of its own — sAnim_FaceEast is FRAME(2, hFlip = TRUE),
	# so it is WEST mirrored.
	spr.flip_h = facing == "EAST" and ObjectEventGraphics.EAST_IS_MIRRORED_WEST
	# A person is 16x32 on a 16x16 tile, so the sprite stands UP out of its
	# cell with its feet on it rather than being centred in it.
	spr.centered = false
	spr.position = Vector2((CELL - size.x) * 0.5, CELL - size.y) \
			+ Vector2(DRAW_OFFSET.get(graphics_id, Vector2i.ZERO))
	return spr


## ⚠️ **[Bugfix, live-reported: "the town map in the rival's house is too far
## left"] A SOURCE-EXACTNESS FIX, NOT AN AUTHORED NUDGE — and an earlier draft
## of this comment claimed the opposite. Rob pushed back ("source definitely
## doesn't have a misalignment") and he was right; the retracted reasoning is
## recorded below because it is the kind that looks airtight.**
##
## What the retracted version said: source centres an object event's sprite on
## its cell (`sprite->x += 8` with `centerToCornerVecX = -(width >> 1)`,
## `event_object_movement.c:1881-1884`), so a 32-wide frame straddles half a tile
## either side — invisible for people sprites whose art fills the frame, but
## `OBJ_EVENT_GFX_TOWN_MAP` is declared 32x16 with its art in only the LEFT half,
## so the poster would land left of its tile in FRLG too.
##
## ⚠️ **EVERY STEP OF THAT IS TRUE OF THE BASE OAM, AND THE BASE OAM IS NOT WHAT
## DRAWS THIS SPRITE.** `AddSubspritesToOamBuffer` (`sprite.c:1768`) uses
## `sprite->x + subsprite->x` and never consults `centerToCornerVec` at all, and
## `UpdateObjectEventElevationAndPriority` assigns
## `subspriteTableNum = sElevationToSubspriteTableNum[elevation]` every frame —
## a table that is `1` or `2` for every elevation the game actually uses
## (`:10029`). Only index 0 is the empty entry that would fall through to the
## base OAM, and nothing reaches it. So the town map renders through
## `sOamTables_16x16`: a **16x16** subsprite at `.x = -8, .y = -8`, i.e.
## `oam.x = (cell_px + 8) - 8 = cell_px` — exactly one tile, perfectly aligned.
##
## ⚠️ **THE TILE DATA PROVES IT INDEPENDENTLY, which is what settles it beyond a
## reading of the sprite code.** Its INCGFX carries `-mwidth 2 -mheight 2`
## (`object_event_graphics.h:498`) — the tile stream is METATILE-ordered into
## 2x2 blocks, which is the layout a 16x16 OAM reads. A 32x16 OAM reading that
## same stream renders the poster's bottom half beside its top half, i.e.
## visibly garbled. The base OAM cannot be the drawing path.
##
## **This is therefore a real port gap, not a divergence: this project ignores
## `subspriteTables` entirely.** Measured across all 1,148 graphics infos,
## `TownMap` is the ONLY one whose subsprite shape differs from its declared
## width/height — so a general subsprite port would buy exactly this one sprite,
## and the offset below is the whole of it.
##
## `+8` puts the frame's column 0 at `cell_px`, which is where source's 16-wide
## window puts it. The right 16 columns are fully transparent, so drawing the
## whole 32-wide frame shifted is pixel-identical to source's narrower window.
## Y needs nothing: `CELL - size.y` already lands the frame at `cell_py`, which
## is where source's `.y = -8` subsprite lands too.
##
## Keyed per graphics id so this stays one row rather than a special case in the
## formula, and so the 384 sprites that need nothing pay nothing.
const DRAW_OFFSET := {
	"OBJ_EVENT_GFX_TOWN_MAP": Vector2i(8, 0),
}


## Build this entity's sprite, if it has one.
##
## [M27D D1] Created with NO `owner`. Godot only serialises children that have
## one, so a baked scene stays byte-identical whether or not it has been
## opened — which matters because `check_bake_diff` reads any divergence as a
## hand edit, and a sprite appearing in 32 scenes would look like 32 edited maps.
func _ready() -> void:
	var gid := sprite_graphics_id()
	if gid == "":
		return
	var spr := make_sprite(gid, initial_facing())
	if spr != null:
		add_child(spr)
