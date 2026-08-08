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
## Built once and cached: `data/map_scripts.json` is 8.6 MB and measures
## **28 ms to read + 198 ms to parse for 17,159 labels**, which is fine once per
## editor session and would not be fine per validation call.
static var _label_index: Dictionary = {}
static var _label_index_built := false


## ⚠️ **FAILS OPEN, DELIBERATELY.** Returns an EMPTY dictionary if the corpus
## cannot be read, and the caller then warns about nothing. A validator that
## cannot see the corpus would otherwise flag every entity on every map at
## once — which is worse than no warning, because the real one would be
## invisible in the noise and the whole check would get ignored.
static func _script_labels() -> Dictionary:
	if _label_index_built:
		return _label_index
	_label_index_built = true
	var f := FileAccess.open("res://data/map_scripts.json", FileAccess.READ)
	if f == null:
		return _label_index
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		return _label_index
	for k in (parsed as Dictionary):
		_label_index[str(k)] = true
	# Authored scripts live in GDScript, not the corpus, and `EventRegistry` is
	# populated at RUNTIME by `ScriptDriver.setup` — so in the editor it is
	# empty unless something fills it. Filling it here is safe: `register_all`
	# is static, builds plain op arrays, and `register` keeps the first
	# registration rather than erroring on a repeat.
	if EventRegistry.labels().is_empty():
		AuthoredEvents.register_all()
	for name in EventRegistry.labels():
		_label_index[str(name)] = true
	return _label_index


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
	spr.position = Vector2((CELL - size.x) * 0.5, CELL - size.y)
	return spr


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
