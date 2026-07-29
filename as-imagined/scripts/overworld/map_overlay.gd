@tool
class_name MapOverlay
extends Node2D

## [M27B Change 2] The behaviour/elevation x-ray — read half.
##
## §20's validation surface, and the primary way to check importer output
## (including the §1.4 elevation mapping). Everything drawn here comes from
## `StepResolver.cell_info()`; this node re-derives nothing.
##
## **Original design.** The reference has no per-cell attribute visualiser at
## all — its overworld debug menu offers only "Warp to map warp…" and "Toggle
## Collision OFF", and the real authoring tool is porymap, external. So there is
## no source layout to port and this is judged by eye, not by fidelity.
##
## **Its own scene, never baked into a map.** Instanced conditionally, which
## keeps every shipping-gate option a one-liner and lets it survive M27C's
## retirement of pallet_town.tscn untouched. `@tool` controls editor execution
## and has nothing to do with export contents — the debug gate is the
## instancing condition (`OS.is_debug_build()`), not the annotation.
##
## Write support is Step D and is EDITOR-ONLY by design. Runtime F3 cycling is
## Step E and stays read-only.

## Vocabulary sized from measurement, not taste: 83 behaviours occur across the
## 421 imported maps, but these 12 cover **97.46%** of all cells. The remaining
## 71 share one "other" colour rather than inventing 71 more.
const BEHAVIOR_COLORS := {
	0: Color(0.30, 0.34, 0.40, 0.30),    # MB_NORMAL — 62.3%, deliberately faint
	8: Color(0.45, 0.35, 0.25, 0.45),    # MB_CAVE
	21: Color(0.15, 0.35, 0.75, 0.45),   # MB_OCEAN_WATER
	2: Color(0.20, 0.65, 0.25, 0.45),    # MB_TALL_GRASS
	44: Color(0.20, 0.55, 0.85, 0.50),   # MB_FAST_WATER
	50: Color(0.75, 0.20, 0.20, 0.45),   # MB_IMPASSABLE_NORTH
	200: Color(0.70, 0.45, 0.15, 0.45),  # MB_CYCLING_ROAD_PULL_DOWN
	33: Color(0.85, 0.78, 0.45, 0.45),   # MB_SAND
	12: Color(0.55, 0.50, 0.45, 0.45),   # MB_MOUNTAIN_TOP
	59: Color(0.90, 0.65, 0.15, 0.55),   # MB_JUMP_SOUTH
	45: Color(0.35, 0.60, 0.80, 0.45),   # MB_CYCLING_ROAD_WATER
	23: Color(0.40, 0.70, 0.85, 0.45),   # MB_SHALLOW_WATER
}
const OTHER_COLOR := Color(0.55, 0.30, 0.60, 0.45)

## §20's "bright magenta for untagged tiles". Measured: zero imported cells are
## untagged, so this can only ever mark a hand-painted cell whose behaviour was
## never set — or an importer regression.
const UNTAGGED_COLOR := Color(1.0, 0.0, 1.0, 0.85)

const COLLISION_COLOR := Color(0.85, 0.10, 0.10, 0.35)
const LEDGE_COLOR := Color(1.0, 0.85, 0.20, 0.95)
const REVIEW_COLOR := Color(1.0, 0.55, 0.0, 1.0)
const GRID_COLOR := Color(0, 0, 0, 0.15)
const TEXT_COLOR := Color(1, 1, 1, 0.85)

const CELL := 16

enum Mode { OFF, BEHAVIOR, MOVEMENT, PROVENANCE }

@export var map_data: MapData:
	set(value):
		map_data = value
		_resolver = StepResolver.new(value) if value != null else null
		queue_redraw()

@export var mode: Mode = Mode.BEHAVIOR:
	set(value):
		mode = value
		queue_redraw()

## Drawing every cell of Viridian Forest (3,726) each frame is wasted work, so
## the draw is clipped to what is actually on screen. Left settable so a test
## can pin a region without a live camera.
@export var visible_rect_override := Rect2i()

var _resolver: StepResolver = null
var _font: Font = null


func _ready() -> void:
	_font = ThemeDB.fallback_font
	queue_redraw()


## Editor-side entry point: the node is instanced first and map_data assigned
## afterwards, so redraw on any property notification rather than relying on
## _ready() having seen a map.
func _notification(what: int) -> void:
	if what == NOTIFICATION_EDITOR_POST_SAVE or what == NOTIFICATION_ENTER_TREE:
		queue_redraw()


## Cells intersecting the viewport, clamped to the map. Falls back to the whole
## map only when there is no camera and no override — acceptable for a 24x20
## test map, and never hit in normal editor/runtime use.
func _visible_cells() -> Rect2i:
	if map_data == null:
		return Rect2i()
	var full := Rect2i(0, 0, map_data.width, map_data.height)
	if visible_rect_override.size != Vector2i.ZERO:
		return visible_rect_override.intersection(full)
	# In the EDITOR, draw the whole map. get_viewport_transform() does not track
	# the 2D editor camera for a node in the edited scene, so clipping there
	# produced an empty rect and the overlay rendered nothing at all -- which is
	# exactly how this first shipped. The clip exists for the runtime case where
	# a moving camera redraws constantly; in-editor the redraw only fires when a
	# property changes, so even Viridian Forest's 3,726 cells cost nothing.
	if Engine.is_editor_hint():
		return full
	var vp := get_viewport()
	if vp == null:
		return full
	var xf := get_viewport_transform() * get_global_transform()
	var view := xf.affine_inverse() * Rect2(Vector2.ZERO, vp.get_visible_rect().size)
	var r := Rect2i(
		Vector2i((view.position / CELL).floor()) - Vector2i.ONE,
		Vector2i((view.size / CELL).ceil()) + Vector2i.ONE * 2)
	var clipped := r.intersection(full)
	# A degenerate clip means the transform lied; better to draw everything than
	# to silently draw nothing, which reads as "the overlay is broken".
	return full if clipped.size.x <= 0 or clipped.size.y <= 0 else clipped


func _draw() -> void:
	if map_data == null or _resolver == null or mode == Mode.OFF:
		return
	var area := _visible_cells()
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var info := _resolver.cell_info(Vector2i(x, y))
			if not info["in_bounds"]:
				continue
			_draw_cell(info)


func _draw_cell(info: Dictionary) -> void:
	var cell: Vector2i = info["cell"]
	var at := Vector2(cell) * CELL
	var box := Rect2(at, Vector2(CELL, CELL))

	match mode:
		Mode.BEHAVIOR:
			draw_rect(box, UNTAGGED_COLOR if info["untagged"]
					else BEHAVIOR_COLORS.get(info["behavior"], OTHER_COLOR))
			if info["ledge_dir"] != -1:
				_draw_ledge_arrow(at, info["ledge_dir"])
		Mode.MOVEMENT:
			if info["collision"] != 0:
				draw_rect(box, COLLISION_COLOR)
			_draw_blocked_edges(at, info)
			if info["ledge_dir"] != -1:
				_draw_ledge_arrow(at, info["ledge_dir"])
			# Elevation letter. Only 5 values occur in Kanto (0/1/3/4/5), and 0
			# means "unconstrained here" rather than a floor, so it is dimmed
			# rather than shouted — it is 56% of the region.
			var e: int = info["elevation"]
			var col := TEXT_COLOR
			if info["elevation_wildcard"]:
				col = Color(TEXT_COLOR.r, TEXT_COLOR.g, TEXT_COLOR.b, 0.35)
			_draw_letter(at, str(e), col)
		Mode.PROVENANCE:
			if info["provenance"] == MapData.Provenance.AUTHORED:
				draw_rect(box, Color(0.2, 0.6, 1.0, 0.30))
			# The 13%: a painted cell whose movement rules are still a guess.
			if info["needs_review"]:
				draw_rect(box, REVIEW_COLOR, false, 2.0)
				_draw_letter(at, "?", REVIEW_COLOR)
			else:
				var marks := ""
				if not info["collision_explicit"]:
					marks += "c"
				if not info["elevation_explicit"]:
					marks += "e"
				if marks != "":
					_draw_letter(at, marks, REVIEW_COLOR)
	draw_rect(box, GRID_COLOR, false, 1.0)


## Edges a step is refused through, drawn on the side it applies to. This is the
## two-sided rule made visible: a tile can be leavable one way and un-enterable
## the other, which is invisible in the rendered map and easy to get wrong.
func _draw_blocked_edges(at: Vector2, info: Dictionary) -> void:
	var c := Color(1.0, 0.25, 0.25, 0.9)
	for dir in info["exits_blocked"]:
		match dir:
			StepResolver.Dir.NORTH:
				draw_line(at, at + Vector2(CELL, 0), c, 2.0)
			StepResolver.Dir.SOUTH:
				draw_line(at + Vector2(0, CELL), at + Vector2(CELL, CELL), c, 2.0)
			StepResolver.Dir.WEST:
				draw_line(at, at + Vector2(0, CELL), c, 2.0)
			StepResolver.Dir.EAST:
				draw_line(at + Vector2(CELL, 0), at + Vector2(CELL, CELL), c, 2.0)


## Only S/W/E occur in Kanto — MB_JUMP_NORTH and all four diagonals are defined
## in source but never placed, so no arrow is drawn for them (they would render
## correctly if a hand-painted map ever used one).
func _draw_ledge_arrow(at: Vector2, dir: int) -> void:
	var c := at + Vector2(CELL, CELL) * 0.5
	var tip := c
	match dir:
		StepResolver.Dir.SOUTH: tip = c + Vector2(0, 5)
		StepResolver.Dir.NORTH: tip = c + Vector2(0, -5)
		StepResolver.Dir.WEST: tip = c + Vector2(-5, 0)
		StepResolver.Dir.EAST: tip = c + Vector2(5, 0)
	var perp := Vector2(tip.y - c.y, c.x - tip.x) * 0.6
	draw_polygon([tip, c - (tip - c) * 0.3 + perp, c - (tip - c) * 0.3 - perp],
			[LEDGE_COLOR, LEDGE_COLOR, LEDGE_COLOR])


func _draw_letter(at: Vector2, s: String, col: Color) -> void:
	if _font == null:
		_font = ThemeDB.fallback_font
	draw_string(_font, at + Vector2(3, CELL - 4), s,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9, col)


## Cycles the read-only modes. Step E wires this to F3; kept here so the
## mode set has one owner.
func next_mode() -> void:
	mode = ((mode + 1) % Mode.size()) as Mode
