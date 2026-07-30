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
var _cell := Vector2i(0, 0)          # GLOBAL, not map-local
var _elev := 3
var _moving := false
var _facing := StepResolver.Dir.SOUTH
## One resolver per loaded chunk. StepResolver is built against a single
## MapData and works in that map's own local cells, so it cannot span a seam —
## crossing one is C4's problem, and caching per chunk is the shape that will
## still be right when it does.
var _resolvers: Dictionary = {}


func _ready() -> void:
	if not manager.load_chunk(start_map):
		push_error("overworld: %s is not baked — run map_baker.tscn" % start_map)
		return
	_spawn_player()
	_add_camera()
	var d := manager.data_at(_cell)
	print("overworld: in %s at %s (%d chunk(s) live)"
			% [manager.chunk_owning(_cell), _cell, manager.loaded_chunks().size()])
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
	var origin := manager.origin_of(start_map)
	var d := manager.data_at(origin)
	if d == null:
		return
	var found := false
	for y in range(d.height):
		for x in range(d.width):
			var g := origin + Vector2i(x, y)
			if manager.collision_at(g) == 0:
				_cell = g
				_elev = manager.elevation_at(g)
				found = true
				break
		if found:
			break

	_player = Node2D.new()
	_player.name = "Player"
	var body := ColorRect.new()
	body.color = Color(1.0, 0.25, 0.25)
	body.size = Vector2(10, 14)
	body.position = Vector2(3, 1)
	_player.add_child(body)
	_reparent_for_elevation()
	_player.position = Vector2(_cell) * CELL


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
	var cam := Camera2D.new()
	cam.zoom = Vector2(3, 3)
	cam.position_smoothing_enabled = true
	_player.add_child(cam)
	cam.make_current()


## Grid-locked movement polls a HELD direction every frame rather than
## reacting to discrete input events. `_unhandled_input` fires once per key
## event, so holding a direction produced a single step (plus erratic OS key
## repeat) — correct per-step logic, unplayable feel.
func _process(_delta: float) -> void:
	if _moving or _player == null:
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


## Resolve a step in GLOBAL cells by handing the owning chunk its own local
## ones and translating the answer back. Split out and public-shaped so the
## conversion is testable without input, a tween or a camera — with one chunk
## at origin (0,0) the translation is identity, and an identity conversion is
## indistinguishable from a missing one unless something exercises it offset.
func resolve_step(gcell: Vector2i, dir: int, elev: int) -> Dictionary:
	var map_name := manager.chunk_owning(gcell)
	if map_name == "":
		# OUTSIDE_RANGE, whose own definition is "off the map / no connection" —
		# precisely a cell no loaded chunk owns.
		return {"outcome": StepResolver.Outcome.OUTSIDE_RANGE, "to": gcell}
	if not _resolvers.has(map_name):
		_resolvers[map_name] = StepResolver.new(manager.data_at(gcell))
	var origin := manager.origin_of(map_name)
	var resolver: StepResolver = _resolvers[map_name]
	var r: Dictionary = resolver.resolve(gcell - origin, dir, elev)
	r["to"] = Vector2i(r["to"]) + origin
	return r


## A step is a request: resolve first, then tween. Logic position is truth;
## the tween is presentation only (§22's testing conventions).
func _try_step(dir: int) -> void:
	var r := resolve_step(_cell, dir, _elev)
	var outcome: int = r["outcome"]
	if outcome != StepResolver.Outcome.NONE and outcome != StepResolver.Outcome.LEDGE_JUMP:
		return
	_cell = r["to"]
	_elev = manager.elevation_at(_cell)
	_reparent_for_elevation()
	_moving = true
	var t := create_tween()
	var dur := 0.16 if outcome == StepResolver.Outcome.NONE else 0.26
	t.tween_property(_player, "position", Vector2(_cell) * CELL, dur)
	t.finished.connect(func() -> void: _moving = false)
