extends Node2D

## [M27C C2] The overworld. One scene for the whole region, not one per map.
##
## Replaces `pallet_town.tscn`, which hardcoded a single map purely because
## M27A needed something to press F6 on. That scaffolding could not survive
## C4: once maps connect, several are live at once and the player crosses
## between them without a scene change, so "which map am I in" stops being a
## scene identity and becomes runtime state. It is deleted rather than
## extended, per docs/overworld_scope.md's own note.
##
## What moved and what did not: the movement, camera and elevation-reparent
## logic is carried over from that skeleton essentially unchanged — it was
## correct, and this is a restructure, not a rewrite. What changed is that
## every cell coordinate here is now GLOBAL (see MapManager) and every per-cell
## query goes through the manager rather than a directly-held MapData.
##
## Layer order inside each baked chunk, per §1.6 and source's own
## sElevationToPriority:
##     Ground / Objects / Entities_P2 / Overhangs / Entities_P1
## Priority-2 entities (elevation 0/1/3/5) draw below the overhang plane;
## priority-1 entities (elevation 4) draw above it.

const CELL := 16

## Which map the player starts in. An @export rather than a constant because
## this is exactly the thing that stopped being fixed at authoring time — C4
## changes it during play, and a warp (C5) changes it on arrival.
@export var start_map: String = "PalletTown_Frlg"

@onready var manager: MapManager = $MapManager

var _player: Node2D
var _camera: Camera2D
var _cell := Vector2i(0, 0)          # GLOBAL, not map-local
var _elev := 3
var _moving := false
var _facing := StepResolver.Dir.SOUTH
## ONE resolver, stepping in global cells across every loaded chunk.
##
## [M27C C4] Was a resolver per chunk, because StepResolver took a single
## MapData and could not span a seam. It now takes a cell SOURCE, and
## MapManager supplies one in global coordinates — so a step across a seam runs
## the identical rules as a step inside a map, including §1.7's two-sided
## directional check whose two tiles live in different MapDatas at a boundary.
var _resolver: StepResolver

## True from the moment a warp starts until the player is standing at the far
## end. Input and further warps are refused meanwhile, so a door cannot be
## re-entered mid-fade.
var _warping := false
var _fade: ColorRect

## [M27C C5] A FEEL value, not a ported constant. Source fades with
## `BeginNormalPaletteFade` at durations that vary per call site, and nothing
## depends on matching one — so this is chosen, and C5-4 owns tuning it.
##
## It only has to outlast the load it hides: Pallet plus neighbours measured
## ~112 ms threaded, comfortably inside one leg. If a large map ever exceeds it,
## hold the fade until the load reports done rather than raising this blindly.
const FADE_SECONDS := 0.25

## The camera is NOT a child of the player, deliberately.
##
## [M27C C4] It was, and crossing a seam produced a fast pan from the new
## chunk's top-left corner. Reparenting the player moves the camera with it, and
## a Camera2D carries its SMOOTHING state as a position that gets reinterpreted
## in the new parent's space — measured jumping to (192, -640), precisely Route
## 1's origin, while its actual global position was correct at (192, -16).
##
## Following the player from outside the chunk tree fixes it at the root rather
## than papering over it with reset_smoothing(), and removes a second hazard on
## the way: a chunk root is freed on unload, so anything parented into one is
## freed with it. The player has to live there for §1.6 draw order; the camera
## has no such reason.


func _ready() -> void:
	if not manager.load_chunk(start_map):
		push_error("overworld: %s is not baked — run map_baker.tscn" % start_map)
		return
	_resolver = manager.global_resolver()
	# Neighbours up front. Hysteresis-based loading as the player moves is the
	# remaining half of C4; loading the starting map's neighbours is what makes
	# a seam crossable at all, and is what the corridor is for.
	var added := manager.load_neighbours(start_map)
	_spawn_player()
	_add_camera()
	_add_fade()
	var d := manager.data_at(_cell)
	print("overworld: in %s at %s (%d chunk(s) live: %s)"
			% [manager.chunk_owning(_cell), _cell, manager.loaded_chunks().size(),
			", ".join(manager.loaded_chunks())])
	if not added.is_empty():
		for nb in added:
			print("  neighbour %-22s origin %s" % [nb, manager.origin_of(nb)])
	if d != null:
		print("  %s %dx%d, %d connection(s), %d loadable"
				% [d.map_name, d.width, d.height, d.connections.size(),
				d.loadable_connections().size()])


## First walkable cell of the starting chunk, in global coordinates.
##
## Deliberately searched rather than hardcoded: the start map is now a
## parameter, so a fixed spawn coordinate would be wrong for every map but one.
## A real spawn point is warp/heal-location data — C5 and beyond.
func _spawn_player() -> void:
	_cell = _first_walkable(start_map)
	_elev = manager.elevation_at(_cell)

	_player = Node2D.new()
	_player.name = "Player"
	var body := ColorRect.new()
	body.color = Color(1.0, 0.25, 0.25)
	body.size = Vector2(10, 14)
	body.position = Vector2(3, 1)
	_player.add_child(body)
	_reparent_for_elevation()
	# The chunk's LOCAL pixels, not the global cell's — the player is a child of
	# a chunk root that is itself offset by that chunk's origin.
	_player.position = manager.local_pixel_of(_cell)


## Moving between draw priorities moves the entity between containers. Driven
## by source's own table, so elevation 5 correctly returns to ground priority
## rather than staying "upper".
##
## Now looks the containers up per cell through the manager: at a seam the
## correct parent belongs to a DIFFERENT chunk, so a reference cached at spawn
## would quietly keep parenting the player into the map it started in.
func _reparent_for_elevation() -> void:
	if _player == null:
		return
	var strata := manager.strata_at(_cell)
	if strata.is_empty():
		return
	var target: Node = strata.get(manager.priority_at(_cell), strata.get(2))
	if target == null or _player.get_parent() == target:
		return
	if _player.get_parent() == null:
		target.add_child(_player)
	else:
		_player.reparent(target)


func _add_camera() -> void:
	if _player == null:
		return
	_camera = Camera2D.new()
	_camera.zoom = Vector2(3, 3)
	_camera.position_smoothing_enabled = true
	add_child(_camera)
	_camera.global_position = _player.global_position
	_camera.reset_smoothing()
	_camera.make_current()


## Grid-locked movement polls a HELD direction every frame rather than
## reacting to discrete input events. `_unhandled_input` fires once per key
## event, so holding a direction produced a single step (plus erratic OS key
## repeat) — correct per-step logic, unplayable feel.
func _process(_delta: float) -> void:
	if _player == null:
		return
	# Every frame, including mid-step: the tween is when following matters most.
	if _camera != null:
		_camera.global_position = _player.global_position
	if _moving or _warping:
		return
	var dir := _held_direction()
	if dir >= 0:
		_facing = dir
		_try_step(dir)


func _held_direction() -> int:
	if Input.is_action_pressed("ui_down"):
		return StepResolver.Dir.SOUTH
	if Input.is_action_pressed("ui_up"):
		return StepResolver.Dir.NORTH
	if Input.is_action_pressed("ui_left"):
		return StepResolver.Dir.WEST
	if Input.is_action_pressed("ui_right"):
		return StepResolver.Dir.EAST
	return -1


## Resolve a step in GLOBAL cells. Split out and public-shaped so stepping is
## testable without input, a tween or a camera.
func resolve_step(gcell: Vector2i, dir: int, elev: int) -> Dictionary:
	if _resolver == null:
		return {"outcome": StepResolver.Outcome.OUTSIDE_RANGE, "to": gcell}
	# No conversion left to do: the resolver already works in global cells, so a
	# step out of one chunk and into the next is just a step.
	return _resolver.resolve(gcell, dir, elev)


## A step is a request: resolve first, then tween. Logic position is truth;
## the tween is presentation only (§22's testing conventions).
func _try_step(dir: int) -> void:
	var r := resolve_step(_cell, dir, _elev)
	var outcome: int = r["outcome"]
	if outcome != StepResolver.Outcome.NONE and outcome != StepResolver.Outcome.LEDGE_JUMP:
		return
	var was_in := manager.chunk_owning(_cell)
	_cell = r["to"]
	_elev = manager.elevation_at(_cell)
	# [M27C C4] Load the new chunk's own neighbours on arrival, and unload
	# nothing. Rob's call, and the measurements support it: stitchable fan-out
	# is at most 4 (360 of 421 maps have none at all), so this tops out around 5
	# live chunks, and unloading buys little against the complexity of deciding
	# when. The reference offers no guidance either way — it keeps ONE map live
	# and swaps it wholesale on crossing (LoadMapFromCameraTransition), so this
	# is deliberate original design, not a port.
	var now_in := manager.chunk_owning(_cell)
	if now_in != "" and now_in != was_in:
		manager.request_neighbours(now_in)
	_reparent_for_elevation()
	_moving = true
	var t := create_tween()
	var dur := 0.16 if outcome == StepResolver.Outcome.NONE else 0.26
	t.tween_property(_player, "position", manager.local_pixel_of(_cell), dur)
	# [M27C C5] THE WARP CHECK LIVES HERE, on the completion of a real step, and
	# nowhere else. Source fires warps from `TryStartStepBasedScript` under
	# `input->tookStep`, and that is the entire reason arriving on a warp tile
	# needs no guard against bouncing straight back: arriving is not a step. A
	# per-frame "am I standing on a warp" poll would look equivalent and would
	# ping-pong the player between two doors forever.
	t.finished.connect(func() -> void:
		_moving = false
		if _warping:
			return
		var w := manager.warp_at(_cell)
		if w != null:
			_do_warp(w)
	)


## A full-screen black rect on its own CanvasLayer, so it covers the world
## regardless of where the camera is looking or what the chunk tree is doing.
func _add_fade() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_fade)


func _fade_to(alpha: float) -> void:
	if _fade == null:
		return
	var t := create_tween()
	t.tween_property(_fade, "color:a", alpha, FADE_SECONDS)
	await t.finished


## Take a warp. Fade out, drop the whole region, load the destination alone,
## put the player on the far side, fade back in.
##
## [M27C C5] The unload is the point. A warp is a hard boundary, so nothing
## survives it — which is why the destination can always be placed at (0, 0)
## and why the Camera2D smoothing reset that cost C4 a real bug at a 24-cell
## seam is invisible here: it happens behind a black screen at a moment we pick.
func _do_warp(w: Warp) -> void:
	var dest := MapConstants.map_name_for(w.dest_map)
	# A dead door — a real destination this project has simply not baked yet.
	# Refused before anything is torn down, so the player keeps standing where
	# they are rather than being stranded in an empty region.
	if dest == "" or not MapConstants.is_baked(w.dest_map):
		print("overworld: warp to %s is not baked — staying put" % w.dest_map)
		return

	_warping = true
	await _fade_to(1.0)

	# The player is parented INTO a chunk for draw order, and unload_all frees
	# chunk roots. Moving it out first is not tidying — it is the difference
	# between a warp and deleting the player.
	if _player != null and _player.get_parent() != null:
		_player.reparent(self)
	manager.unload_all()
	manager.load_chunk(dest, Vector2i.ZERO)

	var arrival := manager.warp_arrival(dest, w.dest_warp_id)
	if arrival.is_empty():
		# Resolvable map, unresolvable slot. Degrade to a walkable cell rather
		# than leaving the player on whatever (0,0) happens to be, and say so —
		# this means the data disagrees with itself.
		push_warning("overworld: %s has no warp %d — falling back to first walkable"
				% [dest, w.dest_warp_id])
		_cell = _first_walkable(dest)
	else:
		_cell = Vector2i(arrival["cell"])
	_elev = manager.elevation_at(_cell)

	_reparent_for_elevation()
	_player.position = manager.local_pixel_of(_cell)
	if _camera != null:
		_camera.global_position = _player.global_position
		_camera.reset_smoothing()
	# An interior has none; an outdoor destination needs its own back.
	manager.load_neighbours(dest)
	manager.refresh_skirts()

	await _fade_to(0.0)
	_warping = false


## First walkable cell of a loaded chunk, in global coordinates.
##
## Shared with spawning: both answer "somewhere valid in this map" with no
## better information, and having one implementation means a fallback arrival
## cannot drift from where a fresh start would put you.
func _first_walkable(map_name: String) -> Vector2i:
	var origin := manager.origin_of(map_name)
	var d := manager.data_at(origin)
	if d == null:
		return origin
	for y in range(d.height):
		for x in range(d.width):
			var g := origin + Vector2i(x, y)
			if manager.collision_at(g) == 0:
				return g
	return origin
