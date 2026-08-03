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

## Where in `start_map` to spawn, in that map's own LOCAL cells.
##
## `(-1, -1)` means "pick one", which falls back to `_first_walkable` — a
## row-major scan, so it lands on whatever the map's top-left-most walkable tile
## happens to be. Fine for a smoke test, arbitrary for play: in Pewter City it
## puts you on the north edge, 52 tiles from the nearest trainer.
##
## Set explicitly for a real starting point. A cell that is out of bounds or
## solid falls back rather than dropping the player inside scenery.
@export var start_cell: Vector2i = Vector2i(-1, -1)

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

## [M27F Stage 3b] The player's walk-cycle clock, and the cadence of the step
## currently in flight. Same WalkAnim every NPC holds — the player is not an
## OverworldEntity, but it draws from the same sheets by the same rules, and a
## second frame implementation is a second place to get the strip layout wrong.
var _player_anim := WalkAnim.new()
var _step_ticks := 0
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

## [M27D D5] The battle overlay's CanvasLayer while a battle is running, else
## null. The overworld is not freed during a battle — it is paused underneath.
var _battle_layer: CanvasLayer = null
var _battle_screen: Control = null

## [M27O O3] Highest level in the party that went into the current battle.
var _battle_party_level := 1
var _in_battle := false

## [M27O O2] Set when a battle-return spawn decided a whiteout is owed but the
## fade and camera did not exist yet. Performed at the end of `_ready`.
var _pending_whiteout := false

## [M27F] The field script interpreter and its message box. `_vm` is null when
## no script is running — that is the "is the player in control" test.
var _vm: ScriptVM = null
var _box: MessageBox = null
## [M27F Stage 4] The yes/no prompt, built alongside the message box.
var _yes_no: YesNoBox = null
var _script_source: ScriptVM.ScriptSource = null

signal script_started(label: String)
signal script_finished(label: String, pause: String, diagnostic: String)

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

## [M27O O3] `sWhiteOutBadgeMoney` (`battle_script_commands.c:315`), indexed by
## how many badges the player holds — nine entries for 0 through 8.
const WHITEOUT_BADGE_MONEY := [8, 16, 24, 36, 48, 64, 80, 100, 120]

## `gBadgeFlags` (`event_data.c:39`), in order.
const BADGE_FLAGS := [
	"FLAG_BADGE01_GET", "FLAG_BADGE02_GET", "FLAG_BADGE03_GET", "FLAG_BADGE04_GET",
	"FLAG_BADGE05_GET", "FLAG_BADGE06_GET", "FLAG_BADGE07_GET", "FLAG_BADGE08_GET",
]

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

## A feel value, not a ported constant. Source measures the exclamation in
## frames against a 60fps lock (`sTrainerSeeFuncList`'s own wait); this project
## is not frame-locked, so this is seconds and is tuned by eye.
##
## [M27F Stage 3c] Its sibling `APPROACH_STEP_SECONDS` (0.18) is RETIRED, not
## merely unused: the approach now walks through the MovementRunner, so its
## cadence comes from the walk itself. That is strictly more accurate than the
## invented value — source hands the approaching object
## `GetWalkNormalMovementAction` (`trainer_see.c`), a NORMAL walk, which is
## 16 frames a tile rather than 0.18s.
const EXCLAMATION_SECONDS := 0.5
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
	_setup_scripting()
	# [M27D D5] The battle scene the same way, for the same reason: reported
	# from play as "the first trainer takes a while, the rest are near
	# instant" — that is the scene and its textures being cold exactly once.
	OverworldSession.preload_battle_scenes()

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
	if _pending_whiteout:
		_pending_whiteout = false
		_do_whiteout()
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
		# ⚠️ Cannot white out HERE. This runs before `_add_camera`/`_add_fade`,
		# so the overlay it fades and the camera it re-centres do not exist yet.
		# Recorded and performed at the end of `_ready` instead.
		_pending_whiteout = _apply_battle_result()
		return
	# [M27O O1] A session that has never had `setrespawn` run needs somewhere to
	# wake up. Resolved from the START MAP rather than hardcoded, so moving
	# `start_map` for a playtest moves the respawn with it instead of stranding
	# the session back in Pallet. M27K's new-game flow replaces this.
	if OverworldSession.respawn.current == "":
		OverworldSession.respawn.default_for(start_map)
	_cell = _resolve_start_cell()
	_elev = manager.elevation_at(_cell)
	_build_player_node()


## The cell to spawn on: `start_cell` if it is set AND actually standable,
## otherwise the map's first walkable tile.
##
## Validated rather than trusted, because the failure is silent and nasty — an
## unwalkable start_cell would drop the player inside scenery, where the step
## resolver refuses every direction and the only way out is a warp they cannot
## reach. Falling back is always recoverable; being stuck is not.
func _resolve_start_cell() -> Vector2i:
	if start_cell.x < 0 or start_cell.y < 0:
		return _first_walkable(start_map)
	var origin := manager.origin_of(start_map)
	var g := origin + start_cell
	if manager.chunk_owning(g) == start_map and manager.collision_at(g) == 0:
		return g
	push_warning("start_cell %s is not standable in %s — falling back."
			% [str(start_cell), start_map])
	return _first_walkable(start_map)


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
	# [M27D D5] A battle is a scripted takeover: the world underneath freezes.
	# This is the one case where NPCs must NOT keep wandering — unlike a warp
	# fade, where they deliberately do.
	if _in_battle:
		return
	# [M27F Stage 3] Ordering is load-bearing. In-flight motion keeps advancing
	# while a script runs — that IS what a cutscene is — so this sits ABOVE the
	# `_vm` return, while `tick_entities` (which DECIDES on new wandering moves)
	# sits below it and stays frozen.
	manager.tick_movement(_delta)
	# [M27F] A running script owns input and freezes the world, the same way a
	# battle does. `lock`/`lockall` are VM no-ops precisely because THIS is where
	# locking actually lives — the VM has no business knowing about input.
	# [M27O O4] A message box with no script behind it. The poison notice is the
	# only one today, and freezing the world for it is the faithful shape rather
	# than a shortcut — source runs it as a real script and
	# `EventScript_FieldPoison` opens with `lockall`. This project simply has no
	# VM to park it on, so the same lock is expressed by returning here.
	if _vm == null and _box != null and _box.is_open \
			and (_yes_no == null or not _yes_no.is_open):
		# `advance` skips the typewriter on the first press (source lets you
		# skip) and closes itself once past the last page, so this is the whole
		# interaction — the same shape as the VM's own WAIT_BUTTON branch.
		if Input.is_action_just_pressed("ui_accept"):
			_box.advance()
		return
	if _vm != null:
		_drive_script()
		return
	# NPCs keep moving while the player is mid-step or mid-warp; freezing the
	# world during a fade is a scripted-cutscene behaviour, not idle movement.
	manager.tick_entities(_delta, _rng)
	# [M27F Stage 3b] The player's own walk cycle, for the INPUT path. Scripted
	# movement is driven by the runner instead (see `_start_player_movement`).
	#
	# ⚠️ Resting is gated on the direction being RELEASED, not merely on the
	# tween having finished. Between two steps of a held walk there is one frame
	# where `_moving` is already false and the next `_try_step` has not run yet;
	# resting there would reset the cycle every tile and the player would lead
	# with the same foot every step — the hop this whole mechanism exists to
	# avoid. Holding the key pauses the cycle for that frame instead, which is
	# invisible, and releasing it settles properly.
	if _moving:
		_step_player(_facing, _step_ticks, _delta)
	elif _held_direction() < 0:
		_face_player(_facing)
	# [M27D D4 fix] Input is LOCKED during an approach. Source calls
	# LockPlayerFieldControls() the moment a trainer notices you
	# (`CheckForTrainersWantingBattle`), and without it you can walk away while
	# the "!" is still over their head — reported from play.
	if _moving or _warping or _in_approach:
		return
	# [M27F] A press of A, before movement: interacting with the tile you face
	# must not also step into it.
	if Input.is_action_just_pressed("ui_accept") and try_interact():
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
	# [M27F Stage 3b] The player's ordinary step is a tween, NOT a MovementRunner
	# script — the two paths are separate and the walk cycle has to be driven on
	# both. `_process` advances it while `_moving`; this records the cadence.
	_step_ticks = _player_step_ticks(dur)
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
		# [M27O O4] Poison ticks LAST, and the order is source's own:
		# `ProcessPlayerFieldInput` runs `CheckForTrainersWantingBattle` at its
		# very top, before it even tests `input->tookStep` — so a trainer who
		# just spotted you takes precedence over the step's own scripts, which
		# is where poison lives (`TryStartStepBasedScript` ->
		# `TryStartStepCountScript`). Gating on `_in_approach` rather than the
		# return value because `check_trainer_sight` is a coroutine; it sets the
		# flag synchronously before its first await, so this reads true already.
		if not _in_approach and not _in_battle:
			_poison_step()
	)


## One step's worth of field poison.
##
## ⚠️ **TWO SOURCE GATES ARE ABSENT BECAUSE NOTHING HERE CAN TRIP THEM YET, NOT
## BECAUSE THEY WERE DROPPED.** `UpdatePoisonStepCounter` skips
## `MAP_TYPE_SECRET_BASE` maps (this project has no secret bases and no map-type
## concept), and its caller skips the step entirely while
## `PLAYER_AVATAR_FLAG_FORCED_MOVE` is set or the tile is a forced-movement one
## — ice, currents, spin tiles — which is **M27E**'s territory and unbuilt. When
## forced movement lands, this call needs that guard; recorded here so it is
## found rather than rediscovered.
func _poison_step() -> void:
	if not FieldPoison.advance_counter(flags):
		return
	var party := OverworldSession.party
	if party == null:
		return
	if FieldPoison.tick(party) != FieldPoison.RESULT_AT_ONE_HP:
		# Ordinary ticks are SILENT. Source returns FALSE for both FLDPSN_NONE
		# and FLDPSN_PSN, so no script runs and no message prints — only the
		# screen flash, which this project has no equivalent for. Damage still
		# happened; the player just is not told about it.
		return
	var pages := PackedStringArray()
	for mon: BattlePokemon in FieldPoison.cure_at_one_hp(party):
		# [M27I I2] Through the real buffer/expansion path rather than a format
		# string, because the message IS `{STR_VAR_1}`-shaped in source and the
		# nickname genuinely goes through `StringGet_Nickname` into gStringVar1.
		var buffers := TextBuffers.new()
		buffers.set_slot(0, mon.species.species_name if mon.species != null else "")
		pages.append(buffers.expand(FieldPoison.MESSAGE))
	if pages.is_empty():
		return
	if _box != null:
		_box.open(pages)


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


## [M27I I2] The pending pages with every `{...}` marker expanded.
##
## ⚠️ Expansion happens HERE — at the moment the box opens — and not when the
## `message` opcode runs. Source expands at print time too
## (`StringExpandPlaceholders` is called by the print path, not the load path),
## and it matters: a script that buffers, prints, re-buffers and prints again
## must show two different values. Expanding at execution would freeze the
## first one, which is most of the corpus, since `STR_VAR_1` is rewritten 176
## times and read 1369.
func _expanded_pages() -> PackedStringArray:
	if _vm == null:
		return PackedStringArray()
	var out := PackedStringArray()
	for page in _vm.pending_pages:
		out.append(_vm.buffers.expand(str(page)))
	return out


## Wait for one entity's movement script to finish.
##
## Bounded rather than open-ended: a runner that never clears — an unimplemented
## action, a freed node — would otherwise hang the approach forever with input
## still locked, which is unrecoverable for the player. The cap is generous
## (twice the walk's own wall-clock cost plus a second) so it can only ever fire
## on a genuine fault, never on slow frames.
func _await_movement(e: OverworldEntity, tiles: int) -> void:
	var budget := (float(tiles) * MovementRunner.FRAMES_NORMAL * MovementRunner.FRAME) * 2.0 + 1.0
	var waited := 0.0
	while manager.movement().is_busy(e) and waited < budget:
		waited += get_process_delta_time()
		await get_tree().process_frame


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

	var map_name := _owning_map_of(t)
	# [M27F Stage 3c] Walk distance-1 tiles through the MovementRunner.
	#
	# ⚠️ This was the LAST place still calling `move_entity` directly, and it is
	# why an approaching trainer kept teleporting after Stage 3 fixed wandering:
	# `move_entity` assigns `cell`, whose setter snaps `position`, so the sprite
	# jumped a whole tile per timer tick with no interpolation and — after
	# Stage 3b — no walk cycle either. Stage 3's own note said "two consumers";
	# there were three. D4 built this path before the runner existed.
	#
	# Occupancy is unchanged: the runner commits the cell at each action's START,
	# so D3's "two entities cannot claim one tile in a frame" invariant holds
	# exactly as it did with the direct call.
	manager.start_entity_movement(map_name, t, manager.walk_ops(dir, distance - 1))
	await _await_movement(t, distance - 1)

	# Both face each other. Source sets the trainer's movement type so it stays
	# put afterwards, then turns the player to the OPPOSITE of the trainer's own
	# facing (`PlayerFaceApproachingTrainer`).
	t.set_facing(dir)
	_facing = OPPOSITE_DIR.get(dir, _facing)
	_in_approach = false
	trainer_approach_finished.emit(t)

	# [M27F Stage 2] Hand off to the trainer's own SCRIPT, not straight to the
	# battle. Source does the same — the approach ends by running the trainer's
	# script (`EventScript_StartTrainerApproach` falls through to it), and that
	# script's own `trainerbattle_single` is what carries the intro speech and
	# names the post-battle script.
	#
	# ⚠️ Going straight to start_trainer_battle() SKIPPED BOTH. Every route
	# trainer in the corridor battled in total silence and never ran their
	# post-battle branch, so `goto_if_defeated` never fired for any of them —
	# and the gap was invisible because the battle itself worked fine.
	if _run_trainer_script(t):
		return
	# No usable script: battle anyway, rather than leaving the player locked in
	# front of a trainer who noticed them and then did nothing.
	start_trainer_battle(t)


## True if the trainer had a runnable script and it started.
func _run_trainer_script(t: TrainerNPC) -> bool:
	if t == null or t.script_label in ["", "0x0", "0"]:
		return false
	return run_script(t.script_label, t)


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
	if t != null:
		_begin_battle(t.trainer_key, t)


## [M27F Stage 2] Start a battle from a trainer KEY, with no placed node.
##
## This is the seam `trainerbattle_single` needs: a script names a trainer, and
## there may be no TrainerNPC involved at all (a gym leader you walked up to and
## talked to is still an NPC, but the script is what decides to battle).
func start_script_battle(trainer_key: String) -> bool:
	return _begin_battle(trainer_key, null)


## Returns false WITHOUT having set `_in_battle` if the battle cannot start, so
## a caller polling every frame does not retry forever.
func _begin_battle(trainer_key: String, t: TrainerNPC) -> bool:
	if trainer_key == "":
		return false
	var opp := OverworldParty.build_trainer_party(trainer_key)
	if opp == null:
		# Unresolvable roster entry. Refuse rather than starting a battle with
		# an empty party, which would end instantly and read as an engine bug.
		push_warning("overworld: %s has no resolvable party — battle not started"
				% trainer_key)
		return false

	# The overworld STAYS ALIVE underneath. No position to save, no chunk to
	# rebuild, no 66-100 ms reload on the way back — the map, the loaded chunks
	# and the player are all still exactly where they were.
	OverworldSession.pending_trainer_key = trainer_key
	# [M27O O4] The SAME party every time now, not a fresh one — see
	# OverworldSession.party. HP and status carry in as well as out, which is
	# the whole reason field poison can exist.
	var player_party := OverworldSession.player_party()
	# ⚠️ A fainted lead would start the battle with a dead active slot. Source
	# never has to think about this (`HealPlayerParty` on whiteout guarantees a
	# live party), but a poisoned, battle-worn party reaches here by paths a
	# rebuilt-every-time one could not.
	for i in range(player_party.members.size()):
		if not player_party.members[i].fainted:
			player_party.active_indices = [i]
			break
	# [M27O O3] Captured here because the payout scales by it. Still captured
	# per battle rather than read later: levelling mid-battle is real, and the
	# figure source uses is the one at the moment the reward is computed.
	_battle_party_level = 1
	for m in player_party.members:
		_battle_party_level = maxi(_battle_party_level, int(m.level))
	# Source clears the poison counter at every battle entry
	# (`battle_setup.c:262, 298, 986`), so a partial step does not carry across.
	FieldPoison.clear_counter(flags)
	BattleSetupContext.set_pending(player_party, opp, false, "", trainer_key)

	var packed := OverworldSession.battle_scene(BattleSetupContext.is_doubles)
	if packed == null:
		push_error("overworld: battle screen scene missing")
		return false

	_in_battle = true
	battle_starting.emit(t)
	_mount_battle_overlay(packed)
	return true


func _mount_battle_overlay(packed: PackedScene) -> void:
	var screen: Control = packed.instantiate() as Control
	# The battle screen's root is a Control; the overworld is a Node2D. A
	# CanvasLayer is what puts it in SCREEN space above the world rather than
	# somewhere in world coordinates behind the tilemap.
	_battle_layer = CanvasLayer.new()
	_battle_layer.layer = 100
	_battle_layer.add_child(screen)
	_battle_screen = screen
	screen.overlay_mode = true
	screen.battle_finished.connect(_on_battle_overlay_finished)
	# Fade out, mount, fade in. Reported from play as being "instantly dumped"
	# between field and battle. NOT the real transition — source picks one of
	# several (Mugshot for gym leaders, `GetTrainerBattleTransition`), and that
	# is M27H's job. This is the minimum that makes the cut deliberate.
	await _fade_to(1.0)
	add_child(_battle_layer)
	await _fade_to(0.0)


## The overlay reports its own outcome rather than swapping scenes back.
func _on_battle_overlay_finished(outcome: int) -> void:
	var prize := 0
	if _battle_screen != null and is_instance_valid(_battle_screen) \
			and _battle_screen.has_method("prize_money"):
		prize = int(_battle_screen.prize_money())
	# [M27O O4] Strip the battle-only state BEFORE the screen is freed — the
	# BattleManager that owns the clearing logic dies with it. HP, status and
	# faints deliberately survive; that is the point of a persistent party.
	if _battle_screen != null and is_instance_valid(_battle_screen) \
			and _battle_screen.has_method("restore_party"):
		_battle_screen.restore_party(OverworldSession.party)
	OverworldSession.set_result(BattleOutcome.make(
			outcome, OverworldSession.pending_trainer_key, prize, _battle_party_level))
	await _fade_to(1.0)
	if _battle_layer != null and is_instance_valid(_battle_layer):
		_battle_layer.queue_free()
	_battle_layer = null
	_battle_screen = null
	# ⚠️ APPLY THE RESULT BEFORE CLEARING `_in_battle`, and never after a fade.
	# `_in_battle` is the guard that stops `_process` reaching `_drive_script`,
	# and a script that started this battle is still parked on WAIT_BATTLE until
	# the result resumes it. Clearing the guard first leaves a multi-frame window
	# (the whole fade-in) in which the driver sees that same WAIT_BATTLE and
	# starts a SECOND battle. Found by live-driving Brock: the beaten flag was
	# set, the badge was not, and the overlay was back on screen.
	# [M27D D5] The guard still holds while the result is applied — clearing it
	# first left a window in which `_drive_script` saw the still-parked
	# WAIT_BATTLE and started a SECOND battle.
	var whiteout := _apply_battle_result()
	_in_battle = false
	await _fade_to(0.0)
	if whiteout:
		await _do_whiteout()


## [M27D D5] Apply what the battle decided, once, on return.
##
## Source does this in `CB2_EndTrainerBattle` (`battle_setup.c:1430`): on the
## non-defeat branch it returns to the field and calls `SetBattledTrainersFlags`;
## on defeat it white-outs unless the player still has live Pokémon. A DRAW
## counts as a defeat there — see BattleOutcome.
func _apply_battle_result() -> bool:
	var r := OverworldSession.take_result()
	if r == null:
		return false
	if r.should_set_defeated_flag():
		flags.set_trainer_defeated(r.trainer_key)

	# [M27O O3] Money. Source does BOTH halves in one place
	# (`Cmd_getmoneyreward`) — the win prize and the loss payout — so they are
	# applied together here rather than split across the win and whiteout paths.
	if r.outcome == BattleOutcome.WON:
		OverworldSession.wallet.earn(r.prize_money)
	elif r.player_defeated():
		OverworldSession.wallet.spend(whiteout_payout(r.highest_party_level))

	# [M27O O2] A defeat whites out. The flag above is deliberately NOT set on
	# this path — source only calls `SetBattledTrainersFlags` on its non-defeat
	# branch, which is what makes losing cost something.
	#
	# ⚠️ THE PARKED SCRIPT MUST NOT RESUME. `CB2_WhiteOut` calls
	# `ScriptContext_Init()`, which wipes the script state outright — the
	# trainer's post-battle branch does not run after you black out. Resuming it
	# would hand out the reward for a fight you lost.
	if r.player_defeated():
		# ⚠️ Source's gate is `IsPlayerDefeated && NoAliveMonsForPlayer()`, not
		# defeat alone. That second half is currently UNREACHABLE-BUT-EQUIVALENT
		# here: with no persistent party, every battle starts at full health, so
		# a defeat means the party was wiped in that battle and "no alive mons"
		# is true by construction. It becomes a real distinction the moment a
		# party survives between battles — M27K/M27L — and belongs here.
		_abandon_script()
		battle_returned.emit(r)
		return true

	# [M27F Stage 2] A script that started this battle is parked on WAIT_BATTLE.
	# Resumed AFTER the flag is set, so its post-battle branch sees a trainer
	# that is already recorded as beaten.
	if _vm != null and _vm.pause_reason == ScriptVM.Pause.WAIT_BATTLE:
		_vm.resume_after_battle(r.outcome == BattleOutcome.WON)
	battle_returned.emit(r)
	return false


## [M27O O3] What losing costs, in money.
##
## Source: `Cmd_getmoneyreward`'s defeat branch. At this project's config
## `B_WHITEOUT_MONEY` is GEN_LATEST, so it is the BADGE TABLE rather than the
## older "half your money" rule — `sWhiteOutBadgeMoney[badge_count] * level`,
## where level is the highest in the party.
##
## ⚠️ Clamped to what the player actually holds, which is source's own
## `if (!IsEnoughMoney(..)) money = GetMoney()`. `Wallet.spend` clamps to zero
## anyway, so this returns the REAL amount taken rather than the amount asked
## for — the difference matters the moment anything reports it to the player.
func whiteout_payout(highest_level: int) -> int:
	var badges := 0
	for f in BADGE_FLAGS:
		if flags.flag_get(f):
			badges += 1
	# Explicit `: int` — indexing an untyped Array yields Variant, which `:=`
	# cannot infer from. This project's own documented GDScript gotcha.
	var asked: int = int(WHITEOUT_BADGE_MONEY[mini(badges, WHITEOUT_BADGE_MONEY.size() - 1)]) \
			* maxi(1, highest_level)
	return mini(asked, OverworldSession.wallet.money)


## Drop a running script without running the rest of it.
##
## [M27O O2] Source's `ScriptContext_Init()` inside `CB2_WhiteOut`. Distinct
## from the normal finish path, which reports where a script stopped — a script
## abandoned by a blackout did not stop at a coverage gap, so saying so would be
## noise.
func _abandon_script() -> void:
	if _vm == null:
		return
	if _box != null:
		_box.close()
	_vm = null


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


## [M27F] Load the compiled corpora once and build the message box.
##
## Both JSONs are read at boot for the same reason the TileSets are: a first
## interaction should not pay an 8.8 MB parse mid-conversation. Measured at
## ~200 ms for the scripts, which is boot cost where a pause is expected.
func _setup_scripting() -> void:
	_script_source = ScriptVM.ScriptSource.new()
	_script_source.ops_by_label = _read_json("res://data/map_scripts.json")
	_script_source.texts = _read_json("res://data/map_texts.json")
	_box = MessageBox.new()
	add_child(_box)
	_yes_no = YesNoBox.new()
	add_child(_yes_no)


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("overworld: %s missing — scripts will not run" % path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}


## Press A: what does it hit?
##
## Ported dispatch order and the counter hop live in Interaction; this is the
## wiring. Returns true if something was started.
func try_interact() -> bool:
	if _vm != null or _in_battle or _warping or _moving or _in_approach:
		return false
	var hit := Interaction.resolve(_cell, _facing,
			func(c: Vector2i) -> int: return manager.behavior_at(c),
			func(c: Vector2i) -> Variant: return manager.entity_node_at(c))
	if hit.is_empty():
		return false
	var label := str(hit.get("script", ""))
	if label == "" or label == "0x0" or label == "0":
		# A placed entity with no script is real and common — the importer
		# records `0x0` for one. Nothing to run, and nothing wrong.
		return false
	# `faceplayer` is a VM no-op, so turning the NPC to face the player is done
	# here, where the scene actually lives.
	var e := hit.get("entity") as OverworldEntity
	if e is NPC:
		(e as NPC).set_facing(OPPOSITE_DIR.get(_facing, StepResolver.Dir.SOUTH))
	return run_script(label, e)


## Start a script. Public so a test — and later a trigger or a warp — can start
## one without simulating a button press.
func run_script(label: String, p_subject: OverworldEntity = null) -> bool:
	_vm = ScriptVM.new(_script_source, flags)
	# [M27I I3] The session's bag, not the VM's own default — the same reason
	# `flags` reads through OverworldSession. A per-script bag would forget
	# every item the moment the script ended.
	_vm.bag = OverworldSession.bag
	_vm.respawn = OverworldSession.respawn
	_vm.wallet = OverworldSession.wallet
	if not _vm.start(label, p_subject):
		# Degrade LOUDLY but without breaking play: the VM named what it could
		# not resolve, so say so and hand control back.
		push_warning("overworld: %s" % _vm.diagnostic)
		script_finished.emit(label, "UNRESOLVED", _vm.diagnostic)
		_vm = null
		return false
	script_started.emit(label)
	return true


## Advance the running script. Called once per frame while `_vm` is live.
##
## THIS is what the VM's external state is for. The driver reads `pause_reason`
## and decides what the scene should do about it — the VM never awaits, never
## touches the message box, and never knows what a button is.
func _drive_script() -> void:
	if _vm == null:
		return

	# Run until the VM needs something from us.
	var guard := 0
	while _vm.step() and guard < 500:
		guard += 1

	# [M27F Stage 3] `applymovement` is ASYNCHRONOUS: it queues rather than
	# pausing, so the script keeps running and a cutscene can start two
	# entities walking at once. Drained here, after stepping, so everything
	# queued this frame starts together.
	_start_pending_movements()

	match _vm.pause_reason:
		ScriptVM.Pause.WAIT_MESSAGE:
			# `message` only OPENS the box. The compiled msgbox chain is
			# message -> waitmessage -> waitbuttonpress, so the waiting belongs
			# to WAIT_BUTTON below; resuming here is what lets the VM reach it.
			if not _box.is_open:
				_box.open(_expanded_pages())
			_vm.resume()

		ScriptVM.Pause.WAIT_BUTTON:
			if _box.is_open:
				if Input.is_action_just_pressed("ui_accept"):
					if not _box.advance():
						_vm.resume()
			else:
				_vm.resume()

		ScriptVM.Pause.WAIT_YES_NO:
			# [M27F Stage 4] A REAL prompt. Stage 1 answered NO unconditionally
			# as a disclosed stopgap, which made every one of the corpus's 425
			# yes/no call sites unreachable past the question.
			#
			# ⚠️ YES = 1, NO = 0 (`Task_HandleYesNoInput` writes
			# `gSpecialVar_Result` 1 for row 0 and 0 for row 1 or B). The two are
			# not interchangeable: `goto_if_eq VAR_RESULT, YES` is what every
			# call site branches on.
			if not _yes_no.is_open:
				_yes_no.open()
			elif _yes_no.accepts_input:
				if Input.is_action_just_pressed("ui_up"):
					_yes_no.move(-1)
				elif Input.is_action_just_pressed("ui_down"):
					_yes_no.move(1)
				elif Input.is_action_just_pressed("ui_cancel"):
					_yes_no.cancel()
					_vm.cancel_yes_no()
				elif Input.is_action_just_pressed("ui_accept"):
					# ⚠️ The VM writes VAR_RESULT, not this — `yesnobox` and
					# `multichoice MULTI_YESNO` use OPPOSITE polarity and only
					# the VM knows which opcode paused.
					_vm.answer_yes_no(_yes_no.confirm())

		ScriptVM.Pause.WAIT_BATTLE:
			# The trainer's intro speech runs first, then the battle. Source does
			# the same (`EventScript_ShowTrainerIntroMsg` precedes `dotrainerbattle`).
			if _vm.pending_pages.size() > 0:
				if not _box.is_open:
					_box.open(_expanded_pages())
				elif Input.is_action_just_pressed("ui_accept") and not _box.advance():
					_box.close()
					_vm.pending_pages = PackedStringArray()
				return
			if not start_script_battle(_vm.pending_trainer_key):
				# Cannot start (no resolvable party, no scene). End the script
				# rather than retrying this branch every frame forever.
				push_warning("overworld: battle vs '%s' could not start"
					% _vm.pending_trainer_key)
				_vm.resume_after_battle(false)
				_finish_script()

		ScriptVM.Pause.WAIT_MOVEMENT:
			# The blocking half. A plain `resume()` is right here because there
			# is no RESULT to branch on — unlike WAIT_BATTLE, which must never
			# be resumed this way or the win/loss branch is silently skipped.
			if not _movement_pending():
				_vm.resume()

		ScriptVM.Pause.DONE, ScriptVM.Pause.UNRESOLVED, ScriptVM.Pause.UNKNOWN_OP:
			_finish_script()


## Start every movement the script has asked for since the last drain.
##
## Targets are LOCALIDs, not node paths — map data, resolved here rather than in
## the VM, which has no business knowing what a chunk is.
func _start_pending_movements() -> void:
	if _vm == null or _vm.pending_movements.is_empty():
		return
	var queued := _vm.pending_movements.duplicate()
	_vm.pending_movements.clear()
	for m in queued:
		var target := str(m.get("target", ""))
		# Movement scripts are ordinary labels — the compiler indexes every
		# label uniformly, so `Common_Movement_WalkDown` resolves through the
		# exact same table `goto` uses. No second pipeline.
		var ops: Array = _script_source.ops_for(str(m.get("script", "")))
		if ops.is_empty():
			push_warning("overworld: movement script '%s' is empty or unresolved"
					% str(m.get("script", "")))
			continue
		if _is_player_target(target):
			_start_player_movement(target, ops)
			continue
		var e := _resolve_movement_entity(target)
		if e == null or not manager.start_movement_for_entity(e, ops):
			push_warning("overworld: applymovement target '%s' did not resolve" % target)


static func _is_player_target(target: String) -> bool:
	return target == "LOCALID_PLAYER" or target == "255"


## The non-player half. `VAR_LAST_TALKED` is the entity you are talking to,
## which the VM already carries as `subject` — 15 corridor call sites use it,
## and resolving it any other way would be a second source of truth.
func _resolve_movement_entity(target: String) -> OverworldEntity:
	if target == "VAR_LAST_TALKED":
		return _vm.subject if _vm != null else null
	return manager.find_entity_by_local_id(target)


## Walk the PLAYER through the same runner every NPC uses.
##
## ⚠️ The commit must leave `_player.position` AT the destination — the runner
## reads it back to learn where it is interpolating TO, then rewinds. Assigning
## `_cell` is what keeps the manager's own occupancy copy true (its setter
## notifies), so this cannot be reordered.
##
## [M27F Stage 3b] The player now turns and walks like any NPC. The disclosed
## gap this comment used to carry — "the player sprite does not change facing
## frame" — is closed: `_face_player`/`_step_player` drive the same [WalkAnim]
## through the same frame tables, rather than a second implementation.
func _start_player_movement(key: String, ops: Array) -> void:
	if _player == null:
		return
	var commit := func(dir: int) -> void:
		_facing = dir
		_cell = _cell + StepResolver.STEP[dir]
		_elev = manager.elevation_at(_cell)
		# Both strata are siblings under one chunk root, so this leaves the
		# local position the runner is interpolating in untouched.
		_reparent_for_elevation()
		_player.position = manager.local_pixel_of(_cell)
	var face := func(dir: int) -> void:
		_face_player(dir)
	var anim := func(dir: int, ticks: int, delta: float) -> void:
		_step_player(dir, ticks, delta)
	manager.movement().start(key, _player, ops, commit, face, anim, face)


## Cycle-entry length for a player step of `dur` seconds.
##
## ⚠️ Derived from the step's own duration rather than copied from source's
## constant, and that is deliberate. Source pairs a 16-frame walk with 8-tick
## entries — TWO cycle entries per tile. This project's player step is 0.16s
## (~9.6 frames), its own tuning choice, so reusing the literal 8 would run the
## feet at source's rate under a faster body and read as skating. Preserving the
## INVARIANT (two entries per tile) rather than the CONSTANT keeps the cadence
## matched to whatever the step duration is tuned to later.
func _player_step_ticks(dur: float) -> int:
	return maxi(1, int(roundf(dur * 60.0 / 2.0)))


## The player's own sprite, or null before it is built / on the fallback path.
func _player_sprite() -> Sprite2D:
	if _player == null:
		return null
	return _player.get_node_or_null("Sprite") as Sprite2D


## Turn the player and stand still.
func _face_player(dir: int) -> void:
	_facing = dir
	var spr := _player_sprite()
	if spr == null:
		return
	_player_anim.setup(PLAYER_GRAPHICS_ID)
	_player_anim.rest(spr, WalkAnim.facing_name(dir))


## Advance the player's walk cycle one tick.
func _step_player(dir: int, ticks: int, delta: float) -> void:
	_facing = dir
	var spr := _player_sprite()
	if spr == null:
		return
	_player_anim.setup(PLAYER_GRAPHICS_ID)
	_player_anim.step(spr, WalkAnim.facing_name(dir), ticks, delta)


## True while anything `waitmovement` could be waiting on is still walking.
##
## `waitmovement 0` means "everything", not "object 0" — LOCALID_NONE is 0, so
## there is no object to name. A named target waits only on that one mover.
func _movement_pending() -> bool:
	if _vm == null:
		return false
	var who := _vm.pending_wait_target
	if who == "":
		return manager.movement().is_busy()
	if _is_player_target(who):
		return manager.movement().is_busy(who)
	var e := _resolve_movement_entity(who)
	return e != null and manager.is_entity_moving(e)


func _finish_script() -> void:
	if _vm == null:
		return
	var d := _vm.describe()
	if _vm.pause_reason == ScriptVM.Pause.UNKNOWN_OP:
		# Not an error — 53 opcodes arrive in later stages. Reported so a script
		# that stops early is visibly a coverage gap rather than a silent no-op.
		print("overworld: script '%s' stopped at pc=%d — %s"
				% [d["label"], d["pc"], _vm.diagnostic])
	_box.close()
	script_finished.emit(str(d["label"]), str(d["pause"]), str(_vm.diagnostic))
	_vm = null


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
	# ABOVE the battle overlay (layer 100), not level with it — same-layer
	# ordering falls back to tree order, which would make whether the fade
	# covers a battle transition depend on child insertion order.
	layer.layer = 200
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

	_teardown_and_load(dest)

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
	_place_player(dest, _cell)

	await _fade_to(0.0)
	await _exit_arrival(arrival.get("warp"))
	_warping = false


## Tear the region down and stand the player somewhere in a fresh map.
##
## [M27O O2] Extracted from `_do_warp` so a whiteout and a door do the same
## thing — the ordering here is load-bearing and had already been got wrong once
## (`[M27C C4]`). `_cell` is GLOBAL and must already be resolved by the caller;
## everything after it is placement.
func _teardown_and_load(dest: String) -> void:
	# The player is parented INTO a chunk for draw order, and unload_all frees
	# chunk roots. Moving it out first is not tidying — it is the difference
	# between a relocation and deleting the player.
	if _player != null and _player.get_parent() != null:
		_player.reparent(self)
	manager.unload_all()
	manager.load_chunk(dest, Vector2i.ZERO)


## Stand the player at a resolved global cell in an ALREADY-LOADED map.
##
## ⚠️ SPLIT FROM THE LOAD ON PURPOSE, and the regression suite is what forced
## it. A first cut did both in one call, which put `warp_arrival` BEFORE
## `load_chunk` — so every warp resolved its destination against a chunk that
## was not loaded yet, got {} and fell back to `_first_walkable`. Seventeen warp
## assertions failed at once. The destination has to be loaded before anything
## can ask it where its warps are.
func _place_player(dest: String, gcell: Vector2i) -> void:
	_cell = gcell
	_elev = manager.elevation_at(_cell)
	_reparent_for_elevation()
	_player.position = manager.local_pixel_of(_cell)
	if _camera != null:
		_camera.global_position = _player.global_position
		_camera.reset_smoothing()
	# An interior has none; an outdoor destination needs its own back.
	manager.load_neighbours(dest)
	manager.refresh_skirts()


## [M27O O2] The whiteout: wake up at the respawn point.
##
## Source's own sequence is `DoWhiteOut` (`overworld.c:392`):
##     RunScriptImmediately(EventScript_WhiteOut)   <- money loss (O3)
##     HealPlayerParty()
##     Overworld_ResetStateAfterWhiteOut()
##     SetWarpDestinationToLastHealLocation()
##     WarpIntoMap()
##
## ⚠️ The destination is the RESPAWN point, not the heal point. At this
## project's config `OW_WHITEOUT_CUTSCENE` is GEN_LATEST, so
## `SetWarpDestinationToLastHealLocation` takes its `IsWhiteoutCutscene()`
## branch and warps INSIDE — the Centre, or Pallet's own house. See
## RespawnPoint for why the two are different places.
func _do_whiteout() -> void:
	var warp := OverworldSession.respawn.respawn_warp()
	var dest := str(warp.get("map", ""))
	# ⚠️ Only 3 of 42 respawn maps are baked today. Refuse BEFORE tearing the
	# region down, exactly as a dead door does — being left standing is
	# recoverable, being stranded in an empty region is not.
	if dest == "" or not ResourceLoader.exists("res://scenes/maps/%s.tscn" % dest):
		push_warning("overworld: whiteout respawn '%s' is not baked — staying put" % dest)
		return

	_warping = true
	await _fade_to(1.0)
	# [M27O O4] The heal, at source's own position — `DoWhiteOut` runs it
	# between the money loss and the warp (`overworld.c:392`).
	#
	# ⚠️ THIS WAS DELIBERATELY OMITTED BY O2, WHICH CALLED IT "THEATRE", AND
	# THAT WAS CORRECT AT THE TIME — with a party rebuilt per battle there was
	# nothing to heal. O4's persistent party makes it LOAD-BEARING: without it
	# the player wakes at the Centre with the same wiped team and the next
	# battle starts on a fainted lead. The slot O2 left is exactly the right one.
	OverworldSession.heal_party()
	FieldPoison.clear_counter(flags)
	_teardown_and_load(dest)
	_place_player(dest, manager.origin_of(dest) + Vector2i(warp.get("cell", Vector2i.ZERO)))
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
