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

## [M27D D1] Placeholder, matching the battle side's own `_PLAYER_BACK_PIC`.
## M27K owns a real player identity; until then the two halves at least agree.
const PLAYER_GRAPHICS_ID := "OBJ_EVENT_GFX_LEAF"

@onready var manager: MapManager = $MapManager

var _player: Node2D
var _camera: Camera2D
## GLOBAL, not map-local.
##
## [M27D D3 follow-up] A SETTER rather than a plain field, because the manager
## needs the player's cell to stop NPCs walking into it and two copies of one
## fact drift. They did: the first cut notified the manager from four call
## sites, a test helper set `_cell` directly without doing so, and the manager
## went on blocking the square the player had LEFT — a phantom body that broke
## two unrelated warp tests. Notifying from the setter makes the drift
## unrepresentable rather than something to remember at each new call site.
var _cell := Vector2i(0, 0):
	set(value):
		_cell = value
		if manager != null:
			manager.set_player_cell(value)
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

## [M27D D5] Position handed back by OverworldSession after a battle, consumed
## by _spawn_player. Empty on a normal boot.
var _resume: Dictionary = {}

## Seeded per run rather than global, so NPC wandering is reproducible when a
## test wants it to be and varied when nobody sets it.
var _rng := RandomNumberGenerator.new()
var _fade: ColorRect

## [M27C C5] A FEEL value, not a ported constant. Source fades with
## `BeginNormalPaletteFade` at durations that vary per call site, and nothing
## depends on matching one — so this is chosen, and C5-4 owns tuning it.
##
## It only has to outlast the load it hides: Pallet plus neighbours measured
## ~112 ms threaded, comfortably inside one leg. If a large map ever exceeds it,
## hold the fade until the load reports done rather than raising this blindly.
const FADE_SECONDS := 0.25

## [M27D D4/D5] Persistent flag/var state: beaten trainers, hidden entities,
## trigger gates.
##
## Reads through OverworldSession rather than owning its own — a battle is a
## `change_scene_to_file`, so an instance var here would be discarded every time
## one is fought, silently forgetting every trainer already beaten. D4 shipped
## it as an instance var because nothing swapped scenes yet; D5 is what makes
## that wrong.
var flags: FlagStore:
	get:
		return OverworldSession.flags

## True while an approach is playing, so a step landing mid-approach cannot
## start a second one.
var _in_approach := false

signal trainer_spotted(trainer: TrainerNPC)
signal trainer_approach_finished(trainer: TrainerNPC)
signal battle_starting(trainer: TrainerNPC)
signal battle_returned(result: BattleOutcome)

## Feel values, not ported constants. Source measures the approach in frames
## against a 60fps lock (`sTrainerSeeFuncList`'s own per-step waits); this
## project is not frame-locked, so these are seconds and are tuned by eye.
const EXCLAMATION_SECONDS := 0.5
const APPROACH_STEP_SECONDS := 0.18
const EXCLAMATION_TEXTURE := \
	"res://assets/sprites/overworld/field_effects/emotion_exclamation.png"

## Facing after being approached: source turns the player to the OPPOSITE of the
## trainer's own facing (`PlayerFaceApproachingTrainer`), which is the direction
## that looks back down the sight line.
const OPPOSITE_DIR := {
	StepResolver.Dir.SOUTH: StepResolver.Dir.NORTH,
	StepResolver.Dir.NORTH: StepResolver.Dir.SOUTH,
	StepResolver.Dir.WEST: StepResolver.Dir.EAST,
	StepResolver.Dir.EAST: StepResolver.Dir.WEST,
}

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
	# FIRST, before any chunk loads. Every pair TileSet is loaded once and held
	# for the process lifetime — measured at 16.4 ms per pair cold (23.6 ms on a
	# cold OS cache), otherwise paid on the first visit to each map whose pair
	# has not been built yet. That is the hitch Rob reported.
	#
	# Ahead of load_chunk deliberately: the start map's own pair would otherwise
	# be the one pair that still pays full price, and boot cost is easier to
	# reason about as one contiguous block than as one block plus a straggler.
	#
	# Synchronous. The work is RELOCATED to a moment where a pause is expected,
	# not reduced — no tile definitions, atlases or .tres content change.
	MapManager.preload_tilesets()

	# [M27D D5] Returning from a battle resumes where the player stood, rather
	# than respawning at start_map. Source's own return is the same idea —
	# CB2_ReturnToFieldContinueScriptPlayMapMusic puts you back on the tile you
	# were on, with the script continuing.
	var resume := OverworldSession.take_return()
	var boot_map: String = str(resume.get("map", "")) if not resume.is_empty() else start_map
	if boot_map == "":
		boot_map = start_map
	if not manager.load_chunk(boot_map):
		push_error("overworld: %s is not baked — run map_baker.tscn" % boot_map)
		return
	_resolver = manager.global_resolver()
	_resume = resume
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
	# [M27D D5] A pending return wins over a fresh spawn: the player stood
	# somewhere specific when the battle started and must come back to it.
	if not _resume.is_empty():
		_cell = Vector2i(_resume.get("cell", Vector2i.ZERO))
		_elev = int(_resume.get("elevation", 3))
		_facing = int(_resume.get("facing", StepResolver.Dir.SOUTH))
		_resume = {}
		_build_player_node()
		_apply_battle_result()
		return
	_cell = _first_walkable(start_map)
	_elev = manager.elevation_at(_cell)
	_build_player_node()


## The player node itself, split out so a battle RETURN reuses it rather than
## duplicating spawn logic that would then drift.
func _build_player_node() -> void:
	_player = Node2D.new()
	_player.name = "Player"
	# [M27D D1] Was a red ColorRect. Draws from the same sheets and the same
	# frame maths as every NPC, via OverworldEntity.make_sprite.
	#
	# Leaf is a PLACEHOLDER and deliberately matches the battle side's own
	# `_PLAYER_BACK_PIC` choice, so the two halves agree on who the player is
	# until M27K builds a real player identity. `red` sits beside her, already
	# pulled, if the male Kanto counterpart is wanted instead.
	var body: Node2D = OverworldEntity.make_sprite(PLAYER_GRAPHICS_ID, "SOUTH")
	if body == null:
		# Never leave the player invisible: a missing sheet should be obvious,
		# not a soft-lock where you cannot find yourself on the map.
		var fallback := ColorRect.new()
		fallback.color = Color(1.0, 0.25, 0.25)
		fallback.size = Vector2(10, 14)
		fallback.position = Vector2(3, 1)
		body = Node2D.new()
		body.add_child(fallback)
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
	# NPCs keep moving while the player is mid-step or mid-warp; freezing the
	# world during a fade is a scripted-cutscene behaviour, not idle movement.
	manager.tick_entities(_delta, _rng)
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
	# Arrow warps resolve BEFORE the step, on the tile already under the player.
	# Source checks them ahead of movement for the same reason, and it matters:
	# an interior exit faces the map's bottom wall, so waiting for a step that
	# can never succeed would make every building a dead end.
	if _try_arrow_warp(dir):
		return
	var r := resolve_step(_cell, dir, _elev)
	var outcome: int = r["outcome"]
	if outcome != StepResolver.Outcome.NONE and outcome != StepResolver.Outcome.LEDGE_JUMP:
		# A blocked step is not necessarily a bump — it is how you open a door.
		_try_door_warp(dir)
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
		# A DIRECTIONAL warp is not a step-on warp. Source's own step-on set
		# (`IsWarpMetatileBehavior`) excludes every arrow and stair behaviour —
		# they live in `TryArrowWarp`, which reads the tile you are already on.
		#
		# Firing them here made the museum stairs trigger a tile early: their
		# warp sits IN FRONT of the staircase art, reachable from the north and
		# south, so walking past one warped you. Held movement means nothing is
		# lost by waiting — arrive on the tile still holding the direction and
		# the next poll fires it.
		if w != null and w.arrow_dir < 0:
			_do_warp(w)
			return
		check_trainer_sight()
	)


## Does any trainer now see the player? If so, run the approach.
##
## [M27D D4] Fires on STEP COMPLETION, the same seam warps use, and for the same
## source reason: `CheckForTrainersWantingBattle` runs off the field-control
## step hook, not a per-frame poll. That is also what makes it safe — a trainer
## whose line the player is standing in is checked once per arrival, so it
## cannot re-trigger while the player stands still.
##
## Returns the trainer that gets the battle, or null. Public and awaitable so a
## test can drive it without input or a tween.
func check_trainer_sight() -> TrainerNPC:
	if _warping or _in_approach:
		return null
	var seen := manager.trainers_seeing_player()
	for entry in seen:
		var t := entry["trainer"] as TrainerNPC
		# Source checks the trainer's own flag inside CheckTrainer and simply
		# skips a beaten one — it does not stop scanning, so a second trainer
		# behind a beaten one still gets its battle.
		if flags.trainer_defeated(t.trainer_key):
			continue
		if not flags.entity_visible(t):
			continue
		await _run_trainer_approach(t, int(entry["dir"]), int(entry["distance"]))
		return t
	return null


## The approach: exclamation mark, walk up, both parties face each other.
##
## Ported from `sTrainerSeeFuncList` (`trainer_see.c`), which is a task-driven
## state machine — TRSEE_EXCLAMATION, TRSEE_EXCLAMATION_WAIT, TRSEE_MOVE_TO_PLAYER,
## TRSEE_PLAYER_FACE. Reproduced as a coroutine because this project has no task
## scheduler and the sequence is strictly linear.
##
## THE TRAINER STOPS ADJACENT, NOT ON THE PLAYER. Source hands
## `InitTrainerApproachTask` a range of `approachDistance - 1`
## (`trainer_see.c:CheckTrainer`), so a trainer three tiles away walks two. That
## off-by-one is load-bearing: walking the full distance would put the trainer
## on the player's own cell.
func _run_trainer_approach(t: TrainerNPC, dir: int, distance: int) -> void:
	_in_approach = true
	trainer_spotted.emit(t)
	await _show_exclamation(t)

	var step: Vector2i = StepResolver.STEP[dir]
	var map_name := _owning_map_of(t)
	# Walk distance-1 tiles toward the player, one cell at a time so occupancy
	# stays true the whole way.
	for _i in range(max(0, distance - 1)):
		manager.move_entity(map_name, t, t.cell + step)
		await get_tree().create_timer(APPROACH_STEP_SECONDS).timeout

	# Both face each other. Source sets the trainer's movement type so it stays
	# put afterwards, then turns the player to the OPPOSITE of the trainer's own
	# facing (`PlayerFaceApproachingTrainer`).
	t.set_facing(dir)
	_facing = OPPOSITE_DIR.get(dir, _facing)
	_in_approach = false
	trainer_approach_finished.emit(t)
	start_trainer_battle(t)


## [M27D D5] Hand control to the battle engine.
##
## THE SEAM THE WHOLE VERTICAL SLICE EXISTS TO PROVE. Everything before this is
## an overworld that has never once started a battle.
##
## `BattleSetupContext` is the existing injection point — `battle_screen_shared`
## already consumes it in `_ready()` and already calls `set_trainer_data(1, ...)`
## for the opponent, so nothing on the battle side changes. What is new is the
## overworld remembering where it was, because `change_scene_to_file` frees it.
func start_trainer_battle(t: TrainerNPC) -> void:
	if t == null or t.trainer_key == "":
		return
	var opp := OverworldParty.build_trainer_party(t.trainer_key)
	if opp == null:
		# Unresolvable roster entry. Refuse rather than starting a battle with
		# an empty party, which would end instantly and read as an engine bug.
		push_warning("overworld: %s has no resolvable party — battle not started"
				% t.trainer_key)
		return
	OverworldSession.save_position(manager.chunk_owning(_cell), _cell, _facing,
			_elev, t.trainer_key)
	BattleSetupContext.set_pending(
			OverworldParty.build_debug_player_party(), opp, false, "", t.trainer_key)
	battle_starting.emit(t)
	get_tree().change_scene_to_file("res://scenes/battle/battle_screen.tscn")


## [M27D D5] Apply what the battle decided, once, on return.
##
## Source does this in `CB2_EndTrainerBattle` (`battle_setup.c:1430`): on the
## non-defeat branch it returns to the field and calls `SetBattledTrainersFlags`;
## on defeat it white-outs unless the player still has live Pokémon. A DRAW
## counts as a defeat there — see BattleOutcome.
func _apply_battle_result() -> void:
	var r := OverworldSession.take_result()
	if r == null:
		return
	if r.should_set_defeated_flag():
		flags.set_trainer_defeated(r.trainer_key)
	# Whiteout is NOT modelled: it needs a respawn point (a registered Pokécentre)
	# that M27I/M27K own and this project has no concept of. A loss currently
	# returns you to where you stood, with the trainer still undefeated — so the
	# encounter is repeatable, which is the honest interim behaviour rather than
	# a fake penalty.
	battle_returned.emit(r)


func _owning_map_of(e: OverworldEntity) -> String:
	for map_name in manager.loaded_chunks():
		var r := manager.chunk_rect(map_name)
		if r.has_point(e.cell + manager.origin_of(map_name)):
			return map_name
	return ""


## The "!" over the trainer's head. Source plays FLDEFF_EXCLAMATION_MARK_ICON
## and waits for it to finish before any movement starts.
func _show_exclamation(t: TrainerNPC) -> void:
	var tex_path := EXCLAMATION_TEXTURE
	if not ResourceLoader.exists(tex_path):
		await get_tree().create_timer(EXCLAMATION_SECONDS).timeout
		return
	var s := Sprite2D.new()
	s.texture = load(tex_path)
	s.centered = false
	s.position = Vector2(0, -CELL)
	t.add_child(s)
	await get_tree().create_timer(EXCLAMATION_SECONDS).timeout
	s.queue_free()


## An arrow warp: stand ON the tile, press its direction.
##
## [M27C C5-4] The third geometry, and the one that leaves a building.
## `TryArrowWarp` reads the player's OWN position on a held direction, ahead of
## any movement, so it does not care whether the target is walkable — Oak's Lab
## exits south into the bottom wall, and every other interior is the same shape.
##
## Without this you could still leave, by stepping off the exit tile and back
## onto it through the step-on path. That is what Rob reported as awkward on the
## OUTDOOR side of a door, and it is the same awkwardness indoors.
##
## The direction is read from the warp rather than inferred, because inferring
## it is measurably wrong: see Warp.arrow_dir.
func _try_arrow_warp(dir: int) -> bool:
	if _warping:
		return false
	var w := manager.warp_at(_cell)
	if w == null or w.arrow_dir != dir:
		return false
	_do_warp(w)
	return true


## A door is WALKED INTO, never stepped onto — a second warp geometry entirely.
##
## [M27C C5-3] This was missed on the first cut, which wired only the step-on
## path and left every building in Kanto sealed. Source has two:
##
##   TryStartWarpEventScript  the player's OWN tile, after `tookStep`
##   TryDoorWarp              the tile IN FRONT, on a held direction
##
## The distinction is not stylistic, it is forced by the map data. MEASURED
## across all 421 maps: of 1294 warps, 1015 sit on walkable tiles and 279 on
## SOLID ones — 193 of those being MB_ANIMATED_DOOR. A door tile cannot be
## stood on, so a step-on check can never fire for one.
##
## The NORTH restriction is source's (`TryDoorWarp` returns immediately for any
## other direction) and is safe to port exactly rather than generalise: of the
## 193 doors, ALL 193 have exactly one walkable neighbour and it is always the
## tile to the south. Zero have none, zero have more than one. If M27M ever
## authors a side-entry door this is the line to revisit — it is a real rule
## about real data, not an assumption.
##
## Keyed on COLLISION rather than the door behaviour, consistent with C5's own
## decoupling: which geometry is even POSSIBLE is decided by whether the tile
## can be stood on, so a hand-placed warp on a wall becomes a door and one on a
## floor becomes a step-on warp, with nothing to remember to set. Disclosed
## divergence: this makes 5 solid non-door warps (4 MB_CAVE, 1 MB_OCEAN_WATER)
## live where source fires them from nothing. None is in the corridor, and
## presence-decides is the same call `triggers` already made.
func _try_door_warp(dir: int) -> void:
	if _warping or dir != StepResolver.Dir.NORTH:
		return
	var target: Vector2i = _cell + StepResolver.STEP[dir]
	# Only a tile that CANNOT be entered — anything walkable is the step-on
	# path's business, and firing here as well would double-trigger it.
	if manager.collision_at(target) == 0:
		return
	var w := manager.warp_at(target)
	if w != null:
		_do_warp(w)


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
	await _exit_arrival(arrival.get("warp"))
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


## Walk off the thing you just arrived on.
##
## [M27C C5-4] Source does this in two unrelated places, which is why the first
## cut only found one: `SetUpWarpExitTask` (`field_screen_effect.c`) picks an
## exit task by arrival-tile kind — a door gets `Task_ExitDoor`, which waits for
## the fade and issues a literal `MOVEMENT_ACTION_WALK_NORMAL_DOWN`, while a
## ladder or floor warp gets `Task_ExitNonDoor` and moves NOWHERE — and an
## escalator never reaches that dispatch at all, being ridden in by
## `Task_EscalatorWarpIn` (`field_effect.c`), which ends on `DIR_EAST`.
##
## So the direction is a property of the warp you land on, stamped at import
## (see Warp.exit_dir) rather than inferred here. Inferring it is what produced
## the escalator bug: the doorway rule below reads "solid arrival tile means
## step south", which is right for every door and says nothing at all about an
## escalator, whose tile is perfectly walkable.
##
## The solid-tile fallback is kept underneath as a safety net for hand-placed
## warps, which carry no stamp: being left on a solid tile is standing inside a
## wall, so stepping off is a correctness fix rather than presentation.
##
## Deliberately NOT routed through `_try_step`: this is scripted movement, not
## player input, so it must not fire a warp at the far end. Same principle as
## arriving not counting as a step.
func _exit_arrival(w: Variant) -> void:
	if _player == null:
		return
	var dir := -1
	var warp := w as Warp
	if warp != null and warp.exit_dir == Warp.EXIT_DIR_FACING:
		# Task_ExitNonAnimDoor: no fixed direction, just keep going the way you
		# were already walking.
		dir = _facing
	elif warp != null and warp.exit_dir >= 0:
		dir = warp.exit_dir
	elif manager.collision_at(_cell) != 0:
		dir = StepResolver.Dir.SOUTH
	if dir < 0:
		return
	var out: Vector2i = _cell + StepResolver.STEP[dir]
	# Nowhere to step is data this project should not invent a recovery for.
	# Leaving the player put is visible, which is the point.
	if not manager.in_bounds(out) or manager.collision_at(out) != 0:
		push_warning("overworld: arrival at %s cannot step out (dir %d)" % [_cell, dir])
		return
	_cell = out
	_elev = manager.elevation_at(_cell)
	_facing = dir
	_reparent_for_elevation()
	var t := create_tween()
	t.tween_property(_player, "position", manager.local_pixel_of(_cell), 0.16)
	await t.finished
