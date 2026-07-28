extends Node2D

## [M27A/M27B] Walking skeleton — now running on BAKED artifacts.
##
## Before Change 1 this script built the TileSet and painted every cell at
## `_ready()`, which silently destroyed anything hand-painted in the editor.
## It now instantiates the baked scene produced by map_baker.gd and loads the
## MapData .tres beside it, so the scene is the artifact and this is only a
## player controller (docs/overworld_scope.md §1.9).
##
## Layer order inside the baked scene, per §1.6 and source's own
## sElevationToPriority:
##     Ground / Objects / Entities_P2 / Overhangs / Entities_P1
## Priority-2 entities (elevation 0/1/3/5) draw below the overhang plane;
## priority-1 entities (elevation 4) draw above it.

const CELL := 16
const MAP_SCENE := "res://scenes/maps/PalletTown_Frlg.tscn"
const MAP_DATA := "res://scenes/maps/PalletTown_Frlg_data.tres"

var map: MapData
var resolver: StepResolver

var _player: Node2D
var _cell := Vector2i(0, 0)
var _elev := 3
var _moving := false
var _facing := StepResolver.Dir.SOUTH
var _strata: Dictionary = {}


func _ready() -> void:
	map = load(MAP_DATA) as MapData
	if map == null:
		push_error("pallet_town: no baked data at %s — run map_baker.tscn" % MAP_DATA)
		return
	resolver = StepResolver.new(map)

	var baked: Node2D = (load(MAP_SCENE) as PackedScene).instantiate()
	add_child(baked)
	_strata = {
		2: baked.get_node_or_null("Entities_P2"),
		1: baked.get_node_or_null("Entities_P1"),
	}

	_spawn_player()
	_add_camera()
	print("pallet_town: %s %dx%d, %d cells (baked)"
			% [map.map_name, map.width, map.height, map.metatile.size()])


func _spawn_player() -> void:
	for y in range(map.height):
		for x in range(map.width):
			if map.collision_at(x, y) == 0:
				_cell = Vector2i(x, y)
				_elev = map.elevation_at(x, y)
				break
		if _cell != Vector2i.ZERO:
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


## The elevation-change reparent: moving between draw priorities moves the
## entity between containers. Driven by source's own table, so elevation 5
## correctly returns to ground priority rather than staying "upper".
func _reparent_for_elevation() -> void:
	var pri: int = map.priority_at(_cell.x, _cell.y)
	var target: Node = _strata.get(pri, _strata.get(2))
	if target == null or _player.get_parent() == target:
		return
	if _player.get_parent() == null:
		target.add_child(_player)
	else:
		_player.reparent(target)


func _add_camera() -> void:
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
	if _moving or map == null:
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


## A step is a request: resolve first, then tween. Logic position is truth;
## the tween is presentation only (§22's testing conventions).
func _try_step(dir: int) -> void:
	var r: Dictionary = resolver.resolve(_cell, dir, _elev)
	var outcome: int = r["outcome"]
	if outcome != StepResolver.Outcome.NONE and outcome != StepResolver.Outcome.LEDGE_JUMP:
		return
	_cell = r["to"]
	_elev = map.elevation_at(_cell.x, _cell.y)
	_reparent_for_elevation()
	_moving = true
	var t := create_tween()
	var dur := 0.16 if outcome == StepResolver.Outcome.NONE else 0.26
	t.tween_property(_player, "position", Vector2(_cell) * CELL, dur)
	t.finished.connect(func() -> void: _moving = false)
