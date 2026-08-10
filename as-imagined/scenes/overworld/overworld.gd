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

## [M26A1 / 3:2 Phase 4] Camera zoom, and it is not a feel value.
##
## At the 1200x800 canvas (a uniform 5x GBA) a zoom of 5 makes the visible
## region exactly **15 x 10 tiles -- the GBA's own viewport**:
##
##     1200 / 5 / 16 = 15      800 / 5 / 16 = 10
##
## ⚠️ **THIS IS A GAMEPLAY CHANGE, NOT A RENDER CHANGE, AND THAT IS THE
## POINT.** The previous 1024x768 / zoom 3 showed 21.3 x 16.0 tiles -- 42%
## more width and 60% more height than the real game. How much of a map reads
## at once, how cutscenes frame, and how close an encounter feels all shift.
##
## ⚠️ **`_snap_camera_to_player` DEPENDS ON THIS BEING AN INTEGER**, so an
## integer world position can only ever land on an integer screen position.
## A fractional zoom reintroduces the sub-pixel drift that function exists to
## remove -- see its own doc comment.
##
## ⚠️ **`TiledWeatherOverlay.TILE_SCALE` MUST MATCH THIS.** It is a separate
## hand-kept copy (that class cannot reach this file -- `overworld.gd` has no
## `class_name`), and a mismatch renders weather tiles at the wrong size with
## visible gaps between them. `m27n_weather_test` pins the two equal.
const CAMERA_ZOOM := 5

## Which map the player starts in. An @export rather than a constant because
## this is exactly the thing that stopped being fixed at authoring time — C4
## changes it during play, and a warp (C5) changes it on arrival.
## [M27L L5] Where a NEW GAME begins — source's own `WarpToTruck` destination
## for FRLG (`new_game.c:138`): the player's bedroom in Pallet Town at (6, 6).
## Separate from `start_map`, which is the debug/corridor boot.
const NEW_GAME_MAP := "PalletTown_PlayersHouse_2F_Frlg"
const NEW_GAME_CELL := Vector2i(6, 6)

## The map actually booted into, which is NOT always `start_map` — a battle
## return and a new game both name their own. Held because `_resolve_start_cell`
## has to validate against the map the player is really standing in; resolving
## `start_cell` against `start_map` while booting elsewhere put the spawn check
## in a different town from the spawn.
var _boot_map := ""

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

## [M27E E1c] Flags to set on the DEBUG BOOT ONLY, so an F6 into this scene can
## reach content the corridor does not yet award.
##
## ⚠️ **SCAFFOLDING, AND IT MUST STAY UNABLE TO REACH THE REAL GAME.** Applied
## only when this is a fresh F6 boot — not a new game, not a battle return, not
## a loaded save (see `_ready`) — so a slot cannot inherit a badge it never
## earned, which would be a save-corrupting kind of convenience. The code
## default is EMPTY; the value lives on `overworld.tscn`, exactly as `start_map`
## and `start_cell` do, for the same reason: this scene IS the debug boot.
##
## Currently: the Soul Badge, because surfing is gated on it (E0) and the
## 32-map slice stops at Pewter, which awards badge 01. Retire this the moment
## the roster actually reaches Fuchsia.
@export var debug_flags: PackedStringArray = PackedStringArray()

## [M27E E1c] Seed the debug team on the DEBUG BOOT ONLY.
##
## ⚠️ **WITHOUT THIS, F6 STARTS WITH NO PARTY AND THE FIRST PATCH OF GRASS IS A
## BLACK SCREEN.** `[M27L L5]` correctly retired the lazily-built debug team as
## the DEFAULT — a new game must start empty, and Oak's script gives you the
## starter — but the debug boot never runs Oak, so it inherited the empty party
## and nothing put one back. Reported from play as a hang on encountering a wild
## Pokemon, and reproduced headlessly: an empty party reaches `BattleManager`
## and every `get_active()` dereference fails.
##
## Same gating as `debug_flags`, and the same reason: this must never be able to
## hand a real save a team it was not given. `build_debug_player_party()` was
## kept alive by L5 for exactly this.
##
## ⚠️ This is a WORKAROUND for the debug path, NOT a fix for the underlying
## defect: starting a battle with an unusable party is still unguarded, and any
## other route to an empty party still black-screens. See CLAUDE.md.
@export var debug_party: bool = false

## [M27D D1] Placeholder, matching the battle side's own `_PLAYER_BACK_PIC`.
## M27K owns a real player identity; until then the two halves at least agree.
##
## ⚠️ **[M27E E2] WAS `OBJ_EVENT_GFX_LEAF`, WHICH IS THE WRONG HALF OF A REAL
## SPLIT.** Rob's call, 2026-08-04, after seeing both sprites side by side.
## `pics/people/leaf.png` is a STANDALONE cameo sprite — 9 frames, no bike, no
## surf, no run, nothing else. `pics/people/leaf/` is the FRLG PLAYER SET
## (green_normal / green_bike / green_surf / green_surf_run / green_fish /
## green_item), and only that set has run art.
##
## ⚠️ This is load-bearing for RUNNING SPECIFICALLY, not just tidiness: the run
## frames live on `green_surf_run.png` and are swapped in mid-step, so if the
## walking sprite were a different character the player would visibly change
## design every time they held Shift.
##
## It also closes an inconsistency that predates running — the player already
## SURFED as `OBJ_EVENT_GFX_GREEN_SURF` (below) while WALKING as someone else.
const PLAYER_GRAPHICS_ID := "OBJ_EVENT_GFX_GREEN_NORMAL"

## [M27E E2] The sheet the player's RUN frames live on.
##
## ⚠️ **THIS IS THE SAME FILE THE SURF ID DRAWS FROM, AND THAT IS NOT A REUSE
## HACK — IT IS HOW KANTO SHIPS IT.** `leaf/green_surf_run.png` holds the three
## surf poses at raw frames 0-2 and the eleven run frames at 3-13. Source
## stitches those eleven onto the walking sheet via `sPicTable_GreenNormal` and
## numbers them 9-19; this project reads the file directly instead, so the run
## tables carry raw indices (6 lower) and nothing has to be regenerated.
##
## Named separately from `PLAYER_SURF_GRAPHICS_ID` even though both resolve to
## one file: they are different questions, and a future sheet split should not
## have to guess which of the two a call site meant.
const PLAYER_RUN_SHEET_ID := "OBJ_EVENT_GFX_GREEN_SURF"

## [M27E E1c] The player's sheet while riding the blob. Leaf's surf sheet, for
## the same placeholder reason as above; `OBJ_EVENT_GFX_RED_SURF` sits beside
## it already pulled if the male counterpart is ever wanted. The graphics table
## deliberately declares these ids as 3 frames (see gen_object_event_sprites'
## FRAME_OVERRIDES): source's own surf pic table maps every walking frame back
## onto the three facing poses, so WalkAnim's rest-only path IS the faithful
## behaviour — no walk cycle on water.
const PLAYER_SURF_GRAPHICS_ID := "OBJ_EVENT_GFX_GREEN_SURF"

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
## [M27E E1c] The blob under the player while surfing, or null on foot. Owned
## HERE, not on the session — it is presentation, and a battle's scene swap is
## supposed to destroy and rebuild it (which `_build_player_node` does).
var _surf_blob: SurfBlob = null
## Set when a dismount lands while the step tween is still in flight, so the
## blob is removed when the player ARRIVES ashore rather than mid-glide.
var _surf_exit_pending := false
## [M27E E1e] The mount jump's vertical arc — `sJumpY_High`, verbatim
## (`event_object_movement.c:10876`). Source's surf mount is
## `InitJumpSpecial` -> `InitJump(..., JUMP_DISTANCE_NORMAL, JUMP_TYPE_HIGH)`,
## so this is the HIGH table, not the normal one: 16 frames peaking at -12px.
##
## Ported rather than computed, matching this project's standing practice for
## source tables (`gSineTable`'s 320 entries, `EXP_SCALING_FACTORS`' 211) — a
## parabola fitted by eye would be close and would not be this.
const _JUMP_Y_HIGH: Array[int] = [
	-4, -6, -8, -10, -11, -12, -12, -12,
	-11, -10, -9, -8, -6, -4, 0, 0,
]
## 16 frames at 60fps, wall clock — the table's own length, not a feel value.
const _MOUNT_JUMP_SECONDS := 16.0 / 60.0
## True while the mount jump is in flight, so `_update_surf_visuals` holds the
## blob back until the player lands on it. The mirror of `_surf_exit_pending`.
var _mount_jump_active := false
## [M27E E1f] How much higher the rider sits than an ordinary walker. Derived
## from FRLG's own combined surf sprite — see `_swap_player_sheet`.
const _SURF_RIDER_LIFT := 8
## [M27E E1f] How long a field-move announcement stays up before dismissing
## itself. A feel value, not a ported one — source has no auto-close at all.
const _USED_MOVE_MESSAGE_SECONDS := 0.5

## [M27E E2] RUNNING.
##
## ⚠️ **THE SPEED IS EXACTLY DOUBLE, AND THAT RATIO IS PORTED WHILE THE ABSOLUTE
## VALUES ARE NOT.** Source runs at `MOVE_SPEED_FAST_1`, whose step table
## (`sStep2Funcs`) is 8 entries against the walk's 16 (`sStep1Funcs`) —
## `event_object_movement.c:10669-10731`, counted rather than assumed. This
## project's walk is its own tuned 0.16s rather than source's 16 frames, so the
## RATIO is what gets preserved, the same reasoning `_player_step_ticks` already
## records for the walk cycle.
const _WALK_STEP_SECONDS := 0.16
const _RUN_STEP_SECONDS := _WALK_STEP_SECONDS / 2.0

## Source gates running on the B button. B is already spoken for here — it is
## `ui_cancel`, which opens the START menu in the field — so running takes SHIFT
## instead, read as a raw held key rather than an InputMap action.
##
## ⚠️ That is the established shape in this project, not a shortcut: there is no
## `[input]` section in `project.godot` at all, and the battle screen's own F3
## toggle already reads a raw keycode for the same reason. **M26C8 owns real
## input mapping** and is where this should become a rebindable action.
const _RUN_KEY := KEY_SHIFT

## Source's Running Shoes flag (`FLAG_SYS_B_DASH`, `flags_frlg.h:1346`). No
## in-game event grants it yet — see `debug_flags`, which is how it is reachable.
const RUN_FLAG := "FLAG_SYS_B_DASH"

## Whether the step in flight is a RUN, latched when the step is committed.
##
## ⚠️ Latched rather than re-read per frame so the animation and the step
## duration cannot disagree partway through a tile: releasing Shift mid-step
## would otherwise leave a half-length step playing a walk cycle.
var _running := false
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

## [M27R 7a-1] The scene's one audio player. Built in `_setup_scripting`.
var _audio: GameAudio = null

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

## [M27F] The message box the field script interpreter drives.
## [M27G G4] `_vm` itself moved to `ScriptDriver`; it is still addressable here
## as a forwarding property (declared below, with the driver) because "is a
## script running" — `_vm == null` — remains the "is the player in control"
## test that this scene's own `_process` gates on.
var _box: MessageBox = null
## [M27F Stage 4] The yes/no prompt, built alongside the message box.
var _yes_no: YesNoBox = null
## [M27G] `multichoicegrid`'s widget, opened by the `Multichoice` native handler.
var _multichoice: MultichoiceGrid = null
## [M27I I6c] The Poke Mart. Public to the `Pokemart` native handler, the same
## way `_multichoice` is to its own.
var _shop_screen: FieldShopScreen = null
## [M27I I4] The START menu and the bag it opens.
var _start_menu: FieldStartMenu = null
var _bag_screen: FieldBagScreen = null
## [M27I I5-2] The party, and which item is waiting for a target.
var _party_screen: FieldPartyScreen = null
## [M27K K-b] The naming screen, for the player's name and the rival's.
var _naming: NamingScreen = null
## [M27K K-b visuals] Oak/player/rival portraits during `run_new_game()`.
var _oak_overlay: OakSpeechOverlay = null
## [M27N] Field weather — the palette-grade state machine + shared shader.
var _weather: WeatherManager = null
var _pending_use_item: int = -1
## [M27G G2] True while `_party_screen` is open FOR THE SCRIPT VM (`special
## ChoosePartyMon`), as opposed to the bag's item-use flow or a plain browse —
## a third disambiguation alongside `_pending_use_item`'s own two states.
## [M27G G4] Script execution lives here now. See `script_driver.gd` for the
## execution-vs-triggering boundary; this scene still owns every decision to
## START a script, and every scene resource the driver borrows.
## ⚠️ Created at DECLARATION, not in `_setup_scripting`, and RefCounted rather
## than a Node — see `script_driver.gd`'s own header for both reasons. The
## short version: `m27i_text_buffers_test` uses a bare `overworld.tscn`
## instance that never enters the tree, so `_vm` has to be addressable before
## `_ready()` ever runs.
var _driver: ScriptDriver = ScriptDriver.new()

## ⚠️ **A FORWARDING PROPERTY, NOT STORAGE — and it is load-bearing for tests.**
## `m27i_text_buffers_test` both READS and ASSIGNS `ow._vm` (it hands in a
## hand-built VM, calls `_expanded_pages()`, then clears it), and `_talk_drive`
## reads `_ow._vm.pending_pages`. Keeping the name addressable here is what let
## G4 move the implementation without touching a single assertion.
##
## Also read by `_process`'s own gates and by `try_interact` — "is a script
## running" is genuinely a scene-level question even though the VM is not a
## scene-level object.
var _vm: ScriptVM:
	get:
		return _driver.vm if _driver != null else null
	set(value):
		if _driver != null:
			_driver.vm = value

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
	# [Map-edge hitch] A SEPARATE cost from the resource preload just above —
	# that one warms the CPU-side Resource, this one warms whatever the renderer
	# pays the first time a tileset is actually DRAWN. Every pair, not just one:
	# see `warm_tilemap_draws`' own doc comment for why the earlier
	# "process-global, so one is enough" reading does not survive a real GPU,
	# and why the Route 1 crossing is exactly where that shows. Awaited, so
	# `boot_map`'s own `load_chunk` below is what benefits — without the await
	# this would still be in flight when that chunk's own TileMapLayers get
	# their first real draw, paying the cost live anyway. `self` is what it
	# hangs the throwaway layers and frame waits off.
	await MapManager.warm_tilemap_draws(self)
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
	# [M27L L5] ⚠️ **A NEW GAME STARTS IN THE PLAYER'S BEDROOM, NOT AT
	# `start_map`.** Source is exact: `WarpToTruck` (`new_game.c:136`) sends FRLG
	# to `MAP_PALLET_TOWN_PLAYERS_HOUSE_2F` at (6, 6) — the truck is Hoenn's
	# opening and Kanto's is the bedroom.
	#
	# ⚠️ PEEKED here, not consumed — `take_new_game()` below is what consumes it,
	# and the speech has to be fired after the field exists. Reading the flag in
	# two places is deliberate: this one decides WHERE, that one decides WHEN.
	#
	# `start_map` is deliberately untouched. It is the DEBUG boot (F6 into the
	# corridor) and the corridor is what M27C's seam work is built on; repointing
	# it would move that scaffolding to answer a question about the new game.
	if OverworldSession.pending_new_game:
		boot_map = NEW_GAME_MAP
		start_cell = NEW_GAME_CELL
		# [Bugfix, live-reported: Oak visible in the middle of Pallet Town
		# before the north trigger reveals him] Source's own
		# `EventScript_ResetAllMapFlagsFrlg` runs before the player is ever
		# placed on a map — matched here, before `load_chunk` below, for both
		# a normal new game AND Quick Start (which never runs `run_new_game`'s
		# own cutscene at all, so this cannot ride along with that instead).
		# See `FlagStore.seed_new_game_flags()`'s own doc comment for why this
		# was never called anywhere in this project until now.
		OverworldSession.flags.seed_new_game_flags()
	# [M27E E1c] Debug-boot flags, gated to the F6 case alone. A new game has
	# `pending_new_game` set; a battle return and a CONTINUE both arrive with a
	# non-empty `resume`. What is left is someone running this scene directly,
	# which is the only place this scaffolding is allowed to act.
	elif resume.is_empty():
		for f in debug_flags:
			OverworldSession.flags.flag_set(String(f))
		if not debug_flags.is_empty():
			print("overworld: DEBUG BOOT — set %d flag(s): %s"
					% [debug_flags.size(), ", ".join(debug_flags)])
		# Only when there is nothing to lose: a debug boot that somehow already
		# has a team keeps it rather than being overwritten.
		if debug_party and OverworldSession.player_party().members.is_empty():
			OverworldSession.party = OverworldParty.build_debug_player_party()
			print("overworld: DEBUG BOOT — seeded a %d-member debug party"
					% OverworldSession.party.members.size())
	_boot_map = boot_map
	if not manager.load_chunk(boot_map):
		push_error("overworld: %s is not baked — run map_baker.tscn" % boot_map)
		return
	# [M27N] The boot map's own real weather. Neither `_try_step`'s seamless-
	# crossing hook nor `_place_player`'s hard-cut-warp hook ever fires for the
	# map you simply START in, so without this the field boots weatherless
	# regardless of what the destination map actually carries.
	if _weather != null:
		_weather.request_weather(manager.weather_of(boot_map))
	_resolver = manager.global_resolver()
	# [M27E E1b] ⚠️ Pushed on EVERY boot, not just a mount. A battle return and a
	# loaded save both rebuild this scene, and a player who was surfing must
	# arrive still surfing — otherwise they land on water on foot, which the step
	# resolver refuses in every direction.
	_resolver.surfing = OverworldSession.surfing
	_resume = resume
	# Neighbours up front. Hysteresis-based loading as the player moves is the
	# remaining half of C4; loading the starting map's neighbours is what makes
	# a seam crossable at all, and is what the corridor is for.
	# [M27L L5] `boot_map`, not `start_map` — a new game boots somewhere
	# start_map does not name, and loading the wrong map's neighbours would
	# leave the real one's seams unloaded.
	var added := manager.load_neighbours(boot_map)
	_spawn_player()
	_add_camera()
	_add_fade()
	if _pending_whiteout:
		_pending_whiteout = false
		_do_whiteout()
	# [M27L L4] A new game runs its speech once the field exists — the naming
	# screen and message box are children of THIS scene, so it cannot run any
	# earlier. Consumed on read, so the rebuild after every battle does not
	# re-run Oak.
	#
	# [Quick Start] `take_new_game_skip_intro()` is only ever meaningful
	# alongside a real `take_new_game()`, so it's consumed inside this branch
	# rather than unconditionally — a Quick Start boot spawns in the bedroom
	# exactly like a normal new game (that's `pending_new_game` alone doing
	# its usual job above) and simply never plays Oak's speech in front of it.
	if OverworldSession.take_new_game():
		if not OverworldSession.take_new_game_skip_intro():
			run_new_game.call_deferred()
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
	var where := _boot_map if _boot_map != "" else start_map
	if start_cell.x < 0 or start_cell.y < 0:
		return _first_walkable(where)
	var origin := manager.origin_of(where)
	var g := origin + start_cell
	if manager.chunk_owning(g) == where and manager.collision_at(g) == 0:
		return g
	push_warning("start_cell %s is not standable in %s — falling back."
			% [str(start_cell), where])
	return _first_walkable(where)


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
	# [M27E E1c] A battle return and a loaded save rebuild this node with the
	# session's surf flag already set — the same reason `_ready` re-pushes the
	# resolver flag. Without this, a player who was surfing arrives standing on
	# the water in walking clothes with no blob.
	_update_surf_visuals()


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
	_camera.zoom = Vector2(CAMERA_ZOOM, CAMERA_ZOOM)
	# Smoothing OFF, deliberately. The player's own movement is already the
	# tween — layering Camera2D's built-in smoothing on top means the camera is
	# forever lerping toward a continuously-moving target, which never lands on
	# a whole pixel. Confirmed directly: with smoothing on and pixel snapping
	# project settings on, `get_viewport().canvas_transform.origin` still had a
	# real, continuously-varying fractional remainder every frame while walking
	# (e.g. 0.496, -0.441, 0.240 px) — snap_2d_transforms_to_pixel only snaps
	# each CanvasItem's own local transform, never the camera/view transform,
	# so nothing about that project setting was ever going to fix this. A hard
	# follow to a rounded position (`_snap_camera_to_player`) is what actually
	# keeps the whole scene pixel-aligned during ordinary movement.
	_camera.position_smoothing_enabled = false
	add_child(_camera)
	_snap_camera_to_player()
	_camera.reset_smoothing()
	_camera.make_current()


## The one place the camera's position is ever set, so a future call site
## cannot reintroduce the sub-pixel drift by copying `_player.global_position`
## raw. Rounds in WORLD space (not screen space) — correct as long as camera
## zoom is an integer, which it is (`CAMERA_ZOOM`), so an integer world
## position can only ever land on an integer screen position.
func _snap_camera_to_player() -> void:
	if _camera == null or _player == null:
		return
	_camera.global_position = _clamp_camera_position(_player.global_position).round()
	# [M27N W3] Pushed from the exact call that just moved the camera, not
	# polled later — a sibling node reading camera position from its own
	# `_process()` would reliably see LAST frame's value, since Tweens (the
	# mid-step camera mover, via `_apply_player_position`) advance after a
	# frame's own `_process()` calls have already run. Same reasoning this
	# function's own doc comment already applies to pixel-snapping.
	if _weather != null:
		_weather.push_camera_scroll(_camera.global_position * _camera.zoom.x)


## [Bugfix, live-reported: "a one tile deep strip of black on indoor maps on
## the side where there is an exit"] Interior maps carry a real, in-bounds
## "void" padding row baked at one edge (present in the imported reference
## data itself — measured region-wide, 192 of 421 maps, almost entirely
## interiors). The GBA's own small, fixed viewport keeps it permanently
## off-screen; this project's camera never clamped to a map's bounds at all,
## so standing near a door — the one place a player gets close enough to that
## edge — exposes it.
##
## Clamps to the UNION of every currently LOADED chunk's pixel bounds, not
## just the player's own map, so a seamless outdoor connection can still pan
## across a boundary into an already-streamed neighbour exactly as before —
## a no-op there, since the loaded region is far larger than one viewport.
## Only a small, unconnected interior (nothing else ever loaded beside it) is
## small enough for the clamp to actually take hold.
func _clamp_camera_position(target: Vector2) -> Vector2:
	if _camera == null:
		return target
	var bounds := Rect2i()
	for map_name in manager.loaded_chunks():
		var r := manager.chunk_rect(map_name)
		if r.size == Vector2i.ZERO:
			continue
		bounds = r if bounds.size == Vector2i.ZERO else bounds.merge(r)
	if bounds.size == Vector2i.ZERO:
		return target
	var px := Rect2(Vector2(bounds.position) * CELL, Vector2(bounds.size) * CELL)
	var half := get_viewport_rect().size / _camera.zoom / 2.0
	# A loaded region SMALLER than the viewport on a given axis has no valid
	# clamp range at all (min would exceed max) — center on that axis instead
	# of clamping into a backwards range.
	var min_x := px.position.x + half.x
	var max_x := px.position.x + px.size.x - half.x
	var min_y := px.position.y + half.y
	var max_y := px.position.y + px.size.y - half.y
	var x := (px.position.x + px.size.x / 2.0) if min_x > max_x else clampf(target.x, min_x, max_x)
	var y := (px.position.y + px.size.y / 2.0) if min_y > max_y else clampf(target.y, min_y, max_y)
	return Vector2(x, y)


## Tween `_player.position` toward `target_local` over `dur` seconds, snapping
## the camera on every single interpolation step rather than leaving it to a
## separate per-frame poll.
##
## ⚠️ **THIS IS NOT A STYLE PREFERENCE — A `_process()`-SIDE POLL CANNOT KEEP
## UP WITH A BUILT-IN `Tween`, AT ALL, EVEN DEFERRED.** Measured directly by
## sampling `_player.global_position` / `_camera.global_position` from
## `RenderingServer.frame_pre_draw` (the actual instant a frame's contents are
## final): with the camera snap called plainly from `_process()`, `round()` of
## the player's real position disagreed with the camera's for every sample
## taken while a step was in flight — the camera was always exactly one
## render-frame stale. Moving the same call to `call_deferred` did not help
## either, and re-measuring the same way proved it did not: Godot's built-in
## Tweens advance AFTER a frame's node `_process()` calls (deferred or not)
## have already run, so nothing scheduled from a node's own per-frame
## processing can ever observe a Tween's update for that same frame — the
## Tween itself is the last thing to move `_player.position` before the frame
## is drawn. The only way to land in the render's own timing is to be driven
## BY that Tween, not to chase it from outside.
##
## `tween_method` (not `tween_property`) is what makes that possible: it hands
## the interpolated value to a callback on every step the Tween itself takes,
## so the camera snap runs in the exact call that just moved the player,
## whatever frame-processing order the engine happens to use that build.
func _tween_player_position(t: Tween, target_local: Vector2, dur: float) -> void:
	t.tween_method(_apply_player_position, _player.position, target_local, dur)


func _apply_player_position(pos: Vector2) -> void:
	if _player == null:
		return
	_player.position = pos
	_snap_camera_to_player()


## Grid-locked movement polls a HELD direction every frame rather than
## reacting to discrete input events. `_unhandled_input` fires once per key
## event, so holding a direction produced a single step (plus erratic OS key
## repeat) — correct per-step logic, unplayable feel.
func _process(_delta: float) -> void:
	if _player == null:
		return
	# [M27D D5] A battle is a scripted takeover: the world underneath freezes.
	# This is the one case where NPCs must NOT keep wandering — unlike a warp
	# fade, where they deliberately do. The camera still snaps (there is
	# nothing else moving it), so that half runs even on this early return.
	if _in_battle:
		_snap_camera_to_player()
		return
	# [M27L L2] ⚠️ TICKS HERE, ABOVE every menu and script gate, because a menu
	# open or a cutscene running is still time the player has spent — source
	# counts the whole session, not just the walking. It sits BELOW the
	# `_in_battle` return only because a battle is a different scene that will
	# tick its own time when M27L reaches it; noted so the omission is a known
	# one rather than a hole.
	OverworldSession.tick_playtime(_delta)
	# [M27F Stage 3] Ordering is load-bearing. In-flight motion keeps advancing
	# while a script runs — that IS what a cutscene is — so this sits ABOVE the
	# `_vm` return, while `tick_entities` (which DECIDES on new wandering moves)
	# sits below it and stays frozen.
	#
	# [Bugfix, live-reported: scripted movement — following Oak into the lab —
	# looks jittery for both the player and Oak, while ordinary player-input
	# walking is smooth] ⚠️ **THIS MUST RUN *BEFORE* THE CAMERA SNAP BELOW, AND
	# IT USED TO RUN AFTER.** `_tween_player_position`'s own doc comment
	# already proved the exact shape of this bug for the player's ordinary
	# Tween-driven walk: a `_process()`-side poll of a moving position is
	# always one render-frame stale, measured directly via
	# `RenderingServer.frame_pre_draw`. That path was fixed by driving the
	# camera snap FROM INSIDE the Tween's own `tween_method` callback
	# (`_apply_player_position`), so the two updates land in the same call.
	# `MovementRunner.tick()` — the thing that actually advances a position
	# under script control (`applymovement`, on the player or any NPC) — has
	# no such per-step callback; it is a plain `_process()`-side position
	# write. The camera snap used to run BEFORE this call in the same frame,
	# so every single frame of a scripted walk rendered the camera at LAST
	# frame's player position while the sprite was already at THIS frame's —
	# a one-frame gap sustained continuously for the whole walk, which is
	# exactly what reads as "jittery" rather than a one-off glitch. Everything
	# on screen renders relative to that same (jittering) camera, which is why
	# Oak's own otherwise-smooth interpolation looked shaky too. Fixed by
	# ensuring the position write happens before the snap that follows it in
	# the SAME frame, closing the gap the same way the Tween path already did.
	manager.tick_movement(_delta)
	_snap_camera_to_player()
	# [M27E E1c] The blob bobs through message boxes and menus — source's field
	# effects keep running under windows — so this sits ABOVE the input gates.
	# Only a battle freezes it, and a battle is a different scene anyway.
	if _surf_blob != null and is_instance_valid(_surf_blob):
		_surf_blob.tick(_delta)
	# [M27F] A running script owns input and freezes the world, the same way a
	# battle does. `lock`/`lockall` are VM no-ops precisely because THIS is where
	# locking actually lives — the VM has no business knowing about input.
	# [M27I I4] The bag and the START menu own input while they are up, and the
	# world freezes behind them — source's own bag/start-menu callbacks are full
	# screen swaps, so nothing underneath keeps running. Ordered bag-first: the
	# bag is opened FROM the menu, so it sits on top of it.
	# ⚠️ [M27I I5-3a] THIS SITS ABOVE THE MENUS, AND THAT ORDERING IS LOAD-BEARING.
	# It used to sit below them, which was fine while the poison notice was the
	# only script-less box — that fires while walking, with no menu up. Item use
	# announces its result with the BAG still open underneath, so leaving this
	# below `_drive_bag_screen` would let the bag eat every press and the box
	# would never dismiss. Source has the same precedence: the party menu's own
	# message window takes input (`{PAUSE_UNTIL_PRESS}`) while the menu freezes.
	# [M27O O4] A message box with no script behind it. Freezing the world for
	# it is the faithful shape rather than a shortcut — source runs the poison
	# notice as a real script and
	# `EventScript_FieldPoison` opens with `lockall`. This project simply has no
	# VM to park it on, so the same lock is expressed by returning here.
	# [M27L L2] ⚠️ **A YES/NO OPENED OUTSIDE THE SCRIPT VM HAD NO INPUT DRIVER AT
	# ALL, AND THAT IS A REAL DEFECT OLDER THAN L2.** The only driver lived inside
	# `_drive_script`'s WAIT_YES_NO branch, so `[M27K K-b]`'s own gender question
	# ("Are you a boy? Or are you a girl?") — which does `_yes_no.open()` then
	# `await _yes_no.chosen` with no VM running — could never be answered from the
	# keyboard. K-b's live drive missed it for the same reason its keyboard bug
	# was missed: the driver called `confirm()` directly instead of pressing keys.
	# **A driver that reaches past the input layer cannot test the input layer.**
	#
	# Sits ABOVE the message-box block because a yes/no draws OVER the message it
	# is asking about (layer 85 vs 80) and must take the input first — which is
	# exactly what the condition below already assumed by excluding itself.
	# [M27G G7] ⚠️ **BOTH FREE-STANDING INPUT DRIVERS ARE GONE.** One drove a
	# yes/no opened outside the VM, one drove a message box opened outside it,
	# both gated on `_vm == null`. The yes/no one had to be ADDED after
	# `[M27K K-b]`'s gender question shipped unanswerable from the keyboard,
	# which is the whole reason this block treats a second input path as a
	# defect rather than a convenience.
	#
	# Every caller is a script now — Oak's speech, saving, and the field-poison
	# notice — so the VM's own WAIT_BUTTON / WAIT_YES_NO branches are the only
	# drivers again. **If a future beat needs a box, make it a script.** The
	# poison notice is the worked example for the hard case: pages built at
	# runtime, shown by a loop that buffers one name per pass
	# (`FieldPoisonEvents`).
	# [M27K K-b] The naming screen owns input outright while it is up, above
	# even the message box — it is a screen, not a prompt over one.
	# [M27R 7a-2] ⚠️ **ONE HOOK FOR ALL SIX WIDGETS, DELIBERATELY.** The obvious
	# implementation is a `play_se` inside each widget's own `move`/`confirm`,
	# which would couple every menu to the audio player and put the same three
	# lines in six files. Every one of these is driven from the chain directly
	# below, so reading the SAME input one step earlier covers all of them and
	# leaves the widgets knowing nothing about sound.
	#
	# Gated on a menu actually being open, or walking around pressing A would
	# blip at nothing.
	_ui_input_sfx()
	if _naming != null and _naming.is_open:
		_drive_naming()
		return
	if _party_screen != null and _party_screen.is_open:
		_drive_party_screen()
		return
	if _bag_screen != null and _bag_screen.is_open:
		_drive_bag_screen()
		return
	if _start_menu != null and _start_menu.is_open:
		_drive_start_menu()
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
	# [M27I I4] START. Source binds this to the START button; this project has no
	# gamepad mapping yet (M26C8 owns that), so Escape stands in — the same key
	# the Item/Switch overlays already use for "open/close a menu".
	if Input.is_action_just_pressed("ui_cancel"):
		_start_menu.open(flags)
		return

	# [Bugfix, live-reported: "I can select a pokemon before I finish my
	# walking animation so I face the wrong direction"] A held direction was
	# read and applied to `_facing`/`_try_step` AFTER the interact check
	# below, so `try_interact()` always read `_facing`/`_cell` as they stood
	# at the START of the frame — last frame's values, not this one's. A
	# player already correctly facing one target who, in the SAME input
	# frame, pressed a NEW direction (turning toward a different target) AND
	# `ui_accept` together got the OLD target: the interact fired on stale
	# facing before this frame's turn was ever applied, and — because
	# `try_interact()` succeeding `return`s immediately — the facing update
	# for the new key was silently dropped, never retried (the key's
	# `just_pressed` edge is gone next frame). Reproduced live: holding a new
	# direction + accept in one frame fired the OLD target's script and left
	# `_facing` unchanged.
	#
	# Turning/stepping now resolves FIRST, so `_facing` is always this
	# frame's true value by the time interact is checked. `_try_step` sets
	# `_moving` synchronously only when a step actually STARTS (a blocked
	# step — turning into a wall, or, in this exact bug, into a solid item
	# ball — leaves `_moving` false); a real, in-flight step still owns the
	# frame and interact is skipped for it, matching the "before movement"
	# comment's own original intent, just applied to a step that is actually
	# happening rather than to stale state from last frame.
	var dir := _held_direction()
	if dir >= 0:
		_facing = dir
		_try_step(dir)
		if _moving:
			return
	if Input.is_action_just_pressed("ui_accept") and try_interact():
		return


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
	# [M27E E1d] STOP_SURFING is a PERMITTED outcome, not a refusal: it is the
	# resolver saying "this step lands you ashore and ends the surf". The
	# dismount itself still falls out of `should_dismount` below, which reads the
	# landed tile — this only has to stop treating the step as blocked.
	if outcome != StepResolver.Outcome.NONE \
			and outcome != StepResolver.Outcome.LEDGE_JUMP \
			and outcome != StepResolver.Outcome.STOP_SURFING:
		# A blocked step is not necessarily a bump — it is how you open a door.
		# [M27R 7a-2] ⚠️ WHICH IS EXACTLY WHY THE BUMP IS GATED ON THE DOOR
		# CHECK FAILING. `SE_WALL_HIT` (`field_player_avatar.c:1425`) is the
		# "you walked into a wall" sound; playing it before `_try_door_warp`
		# would make every door in Kanto thud as it opened, since a door tile is
		# solid and reaches this branch on the way in.
		if not _try_door_warp(dir) and _audio != null:
			_audio.play_se("SE_WALL_HIT")
		return
	var was_in := manager.chunk_owning(_cell)
	# [M27H H2] Captured BEFORE the move: source's `AllowWildCheckOnNewMetatile`
	# compares the tile you were on against the one you land on, so reading it
	# after the step would always compare a tile with itself and make every step
	# a "same behaviour" one — silently removing the 40% gate entirely.
	var prev_behavior := manager.behavior_at(_cell)
	_cell = r["to"]
	_elev = manager.elevation_at(_cell)
	# [M27E E1d] ⚠️ SET BEFORE THE DISMOUNT CHECK, AND THAT ORDERING IS THE WHOLE
	# REASON THE DEFERRAL EXISTS. `_update_surf_visuals` holds the blob until the
	# step lands by testing `_moving`, and this used to be assigned *below* the
	# check — so the flag was still false, the blob came off at step START, and
	# the deferred path was unreachable in play. E1c's own F.07 guard set
	# `_moving` by hand and so proved only that the mechanism worked in
	# isolation. Found by driving the real map, not by the suite.
	_moving = true
	# [M27E E1b] ⚠️ RIDE ASHORE AND THE BLOB GOES AWAY — source has no "get off"
	# key. `[E1a]` only lets a surfing player reach a tile that was already
	# walkable, so "landed somewhere unsurfable" IS "landed ashore" and needs no
	# rule of its own. Checked on the INPUT step path only; scripted movement
	# (`applymovement`) is a cutscene the author controls, and source's own
	# forced walks off water do their own dismount.
	if FieldMoves.should_dismount(manager.behavior_at(_cell),
			OverworldSession.surfing):
		OverworldSession.surfing = false
		_begin_dismount()
		_sync_surfing()
	elif _surf_blob != null and is_instance_valid(_surf_blob):
		# [M27E E1c] Still on the water: retune the bob to the destination's own
		# shore adjacency, source's per-arrival `SynchronizeSurfPosition` check.
		_surf_blob.set_near_shore(_surf_shore_adjacent(_cell))
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
		if _weather != null:
			_weather.request_weather(manager.weather_of(now_in))
	_reparent_for_elevation()
	var t := create_tween()
	# [M27E E2] ⚠️ LATCHED HERE, AGAINST THE TILE THE PLAYER IS STANDING ON.
	# Source reads `currentMetatileBehavior` — the tile you are LEAVING, not the
	# one you are entering (`field_player_avatar.c:911`) — so this reuses
	# `prev_behavior`, captured above before `_cell` moved, rather than reading
	# the destination. Latching before the tween is built is what keeps the
	# duration and the cycle in agreement for the whole tile.
	_running = _can_run(prev_behavior, outcome)
	# [M27R 7a-2] The ledge hop. Source: `SE_LEDGE` (songs.h:16 `SE_DANSA`),
	# `field_player_avatar.c:1347`.
	if outcome == StepResolver.Outcome.LEDGE_JUMP and _audio != null:
		_audio.play_se("SE_LEDGE")
	# [M27E E1d] STOP_SURFING is an ordinary-speed step, not a ledge hop — the
	# 0.26 is the hop's own arc duration and would read as a stumble ashore.
	var dur := 0.26 if outcome == StepResolver.Outcome.LEDGE_JUMP \
			else (_RUN_STEP_SECONDS if _running else _WALK_STEP_SECONDS)
	# [M27F Stage 3b] The player's ordinary step is a tween, NOT a MovementRunner
	# script — the two paths are separate and the walk cycle has to be driven on
	# both. `_process` advances it while `_moving`; this records the cadence.
	_step_ticks = _player_step_ticks(dur)
	t.set_parallel(true)
	_tween_player_position(t, manager.local_pixel_of(_cell), dur)
	# [M27E E1f] Riding ashore is a JUMP, not a walk — `Task_StopSurfingInit`
	# issues the same `GetJumpSpecialMovementAction` the mount does. Reported
	# from play as "no jump animation when ending surf".
	if _surf_exit_pending:
		var jspr := _player_sprite()
		if jspr != null:
			_add_jump_arc(t, jspr, jspr.position.y, dur)
	# [M27C C5] THE WARP CHECK LIVES HERE, on the completion of a real step, and
	# nowhere else. Source fires warps from `TryStartStepBasedScript` under
	# `input->tookStep`, and that is the entire reason arriving on a warp tile
	# needs no guard against bouncing straight back: arriving is not a step. A
	# per-frame "am I standing on a warp" poll would look equivalent and would
	# ping-pong the player between two doors forever.
	t.finished.connect(func() -> void:
		_moving = false
		# [M27E E1c] The deferred half of a ride-ashore: the flag flipped at
		# step start, the blob comes off now that the player has ARRIVED. Runs
		# before the warp bail — the visual state must settle either way.
		if _surf_exit_pending:
			_surf_exit_pending = false
			_update_surf_visuals()
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
		# [Map scripts follow-up] A coord_event trigger on the cell just
		# arrived at — the SAME source function warps come from
		# (`TryStartStepBasedScript`), checked in the same neighbourhood for
		# that reason. `Trigger`/`trigger_armed` were fully built (M27B/M27D)
		# but never actually dispatched anywhere outside the editor overlay
		# and this file's own test suite — found while live-driving the
		# starter fix, since without this OakTrigger (and every other
		# coord_event in the corridor) can never fire at all, regardless of
		# any map-script work.
		check_step_trigger()
		if _vm != null:
			return
		check_trainer_sight()
		# [Map scripts] SECOND priority, matching source's own
		# `ProcessPlayerFieldInput` order (`CheckForTrainersWantingBattle`
		# then `TryRunOnFrameMapScript`, both before `input->tookStep`'s own
		# handling). Gated on `_in_approach` for the same reason the poison/
		# wild-encounter block below already is — a trainer sighting this
		# same step takes precedence.
		if not _in_approach and not _in_battle:
			check_on_frame_map_script()
		# [M27O O4] Poison ticks LAST, and the order is source's own:
		# `ProcessPlayerFieldInput` runs `CheckForTrainersWantingBattle` at its
		# very top, before it even tests `input->tookStep` — so a trainer who
		# just spotted you takes precedence over the step's own scripts, which
		# is where poison lives (`TryStartStepBasedScript` ->
		# `TryStartStepCountScript`). Gating on `_in_approach` rather than the
		# return value because `check_trainer_sight` is a coroutine; it sets the
		# flag synchronously before its first await, so this reads true already.
		# Also gated on `_vm == null` now — an OnFrame map script that just
		# started owns the frame the same way any other running script does.
		if not _in_approach and not _in_battle and _vm == null:
			_poison_step()
			# [M27H H2/H3] Wild encounters come LAST, and that is source's own
			# order: `ProcessPlayerFieldInput` runs the trainer check first, then
			# `TryStartStepBasedScript` (where poison lives), then
			# `CheckStandardWildEncounter`. Gated on the poison message too — a
			# tick that just opened a box owns the screen, and starting a battle
			# over it would strand the message unread.
			if not _in_battle and (_box == null or not _box.is_open):
				_wild_step(prev_behavior)
	)


## [M27R 7a-2] The menu blip layer. See its call site for why it lives there
## rather than inside each widget.
##
## ⚠️ Deliberately does NOT try to know whether the widget accepted the press —
## a cursor already at the end of a list still blips in source, so "input
## received" is the right trigger, not "state changed".
func _ui_input_sfx() -> void:
	if _audio == null or not _any_menu_open():
		return
	if Input.is_action_just_pressed("ui_up") \
			or Input.is_action_just_pressed("ui_down") \
			or Input.is_action_just_pressed("ui_left") \
			or Input.is_action_just_pressed("ui_right"):
		_audio.play_se("SE_SELECT")
	elif Input.is_action_just_pressed("ui_accept"):
		_audio.play_se("SE_CLICK")
	elif Input.is_action_just_pressed("ui_cancel"):
		# Source has no distinct back sound — B plays the same blip as a move.
		_audio.play_se("SE_SELECT")


func _any_menu_open() -> bool:
	return (_naming != null and _naming.is_open) \
			or (_party_screen != null and _party_screen.is_open) \
			or (_bag_screen != null and _bag_screen.is_open) \
			or (_start_menu != null and _start_menu.is_open)


## [M27I I4] START menu input.
func _drive_start_menu() -> void:
	if Input.is_action_just_pressed("ui_up"):
		_start_menu.move(-1)
	elif Input.is_action_just_pressed("ui_down"):
		_start_menu.move(1)
	elif Input.is_action_just_pressed("ui_accept"):
		_start_menu.confirm()
	elif Input.is_action_just_pressed("ui_cancel"):
		_start_menu.close()


## [M27I I4] Bag input. Left/right switch pockets, up/down move the cursor.
func _drive_bag_screen() -> void:
	# [M27I I5-3] The action menu owns input while it is up.
	if _bag_screen.actions_open:
		if Input.is_action_just_pressed("ui_up"):
			_bag_screen.move_action(-1)
		elif Input.is_action_just_pressed("ui_down"):
			_bag_screen.move_action(1)
		elif Input.is_action_just_pressed("ui_accept"):
			_bag_screen.confirm_action()
		elif Input.is_action_just_pressed("ui_cancel"):
			_bag_screen.close_actions()
		return
	if Input.is_action_just_pressed("ui_accept"):
		_bag_screen.open_actions()
		return
	if Input.is_action_just_pressed("ui_left"):
		_bag_screen.next_pocket(-1)
	elif Input.is_action_just_pressed("ui_right"):
		_bag_screen.next_pocket(1)
	elif Input.is_action_just_pressed("ui_up"):
		_bag_screen.move_row(-1)
	elif Input.is_action_just_pressed("ui_down"):
		_bag_screen.move_row(1)
	elif Input.is_action_just_pressed("ui_cancel"):
		_bag_screen.close()


func _on_start_menu_bag() -> void:
	_bag_screen.open(OverworldSession.bag)


## [M27I I5-2] Party input.
## [M27K K-b] Input for the naming screen.
##
## ⚠️ B DOES NOT CANCEL ON THE KEYBOARD — it backspaces, which is source's own
## binding. Cancelling out of naming mid-new-game would leave the player
## unnamed with nothing to re-enter through, so the only way off the keyboard
## is OK with something typed.
func _drive_naming() -> void:
	if Input.is_action_just_pressed("ui_up"):
		_naming.move(-1)
	elif Input.is_action_just_pressed("ui_down"):
		_naming.move(1)
	elif Input.is_action_just_pressed("ui_accept"):
		_naming.confirm()
	elif Input.is_action_just_pressed("ui_focus_next"):
		_naming.next_page()
	elif Input.is_action_just_pressed("ui_cancel"):
		if _naming.mode == NamingScreen.Mode.KEYBOARD:
			_naming.backspace()
	# [M27K K-c] There is deliberately NO `ui_text_submit` branch any more.
	# Godot binds it to Enter, and so is `ui_accept` — with `ui_accept` tested
	# first above, this one could never fire, so a typed name could never be
	# submitted. Accepting is the OK key on the grid now, reached by `confirm`.


func _drive_party_screen() -> void:
	if Input.is_action_just_pressed("ui_up"):
		_party_screen.move(-1)
	elif Input.is_action_just_pressed("ui_down"):
		_party_screen.move(1)
	elif Input.is_action_just_pressed("ui_accept"):
		_party_screen.confirm()
	elif Input.is_action_just_pressed("ui_cancel"):
		_party_screen.close()


## [M27L L2] SAVE, from the start menu. Source's own flow and its own text
## (`data/text/save.inc`), in source's own order: confirm, then the SAVING
## notice, then the report.
##
## ⚠️ **THE "SAVING… DON'T TURN OFF THE POWER" PAGE IS SHOWN EVEN THOUGH THIS
## WRITE IS INSTANT.** On the GBA it is a real warning about real flash memory;
## here `SaveManager.save` returns in under a millisecond. It is kept because it
## is the beat the player expects between the yes and the confirmation, and
## because dropping it would make a successful save read as if nothing happened.
## Recorded as a deliberate keep rather than left to look like a stray page.
##
## ⚠️ `gText_AlreadySavedFile` ("There is already a saved file. Is it okay to
## overwrite it?") is **deliberately not asked**. Source asks it because the GBA
## has ONE save; with three slots the overwrite question belongs to slot
## SELECTION (L3), and asking it here would be asking about a slot the player
## never chose.
const SAVE_CONFIRM := "Would you like to save the game?"
const SAVE_IN_PROGRESS := "SAVING…\nDON'T TURN OFF THE POWER."
const SAVE_DONE := "{PLAYER} saved the game."
## ⚠️ TWO PAGES, not one string with a `\p` in it. Source's `\p` is a
## PAGE-BREAK control code, not a character — GDScript reads it as an invalid
## escape and refuses to parse the file. Every other multi-page line in this
## scene is already an Array for the same reason.
const SAVE_FAILED := ["Save error.", "Please exchange the\nbackup memory."]


## [M27L L4] The slot the field writes to now lives on `OverworldSession`, where
## it survives the scene swap a battle performs — L2's stand-in here would have
## reverted to 0 after the first trainer fight.
var active_slot: int:
	get:
		return OverworldSession.active_slot


func _on_start_menu_save() -> void:
	# [M27G G7] Was an `await` coroutine opening a yes/no outside the VM — the
	# same shape as `run_new_game`, and the reason deleting the free-standing
	# yes/no driver would have broken saving. See `StartMenuEvents`.
	run_script(StartMenuEvents.LABEL)


func _on_start_menu_pokemon() -> void:
	_pending_use_item = -1
	_party_screen.open(OverworldSession.player_party())


## [M27K K-b] FRLG's Oak intro, verbatim from `data/text/new_game_intro_frlg.inc`
## (minus the `\p`/`$` page and terminator control codes, which are the message
## box's own paging here).
##
## ⚠️ **THE BEATS AND THEIR ORDER ARE SOURCE'S, NOT A RETELLING** — the task
## chain in `src/oak_speech.c` runs welcome -> this world -> inhabited far and
## wide -> I study Pokemon -> tell me about yourself -> gender -> your name ->
## rival's name -> let's go. Reordering reads fine and is a different scene.
const OAK_WELCOME := "Hello, there!\nGlad to meet you!"
const OAK_THIS_WORLD := "This world…"
const OAK_INHABITED := "…is inhabited far and wide by\ncreatures called POKéMON."
const OAK_I_STUDY := "For some people, POKéMON are pets.\nOthers use them for battling."
const OAK_ABOUT_YOURSELF := "But first, tell me a little about\nyourself."
const OAK_ASK_GENDER := "Now tell me. Are you a boy?\nOr are you a girl?"
const OAK_YOUR_NAME := "Let's begin with your name.\nWhat is it?"
## ⚠️ Repurposed from "said afterward" to "asked as a confirmation" — source's
## own `gOakSpeech_Text_SoYourNameIsPlayer` IS the confirmation prompt
## (`Task_OakSpeech_ConfirmName`), not a trailing statement. See the
## confirm/retry loop in `run_new_game()`.
const OAK_SO_YOUR_NAME := "Right…\nSo your name is {PLAYER}."
const OAK_RIVAL_INTRO := "This is my grandson.\nHe's been your rival since you both were babies."
const OAK_RIVAL_NAME := "…Erm, what was his name now?"
## Source's real `gOakSpeech_Text_ConfirmRivalName`
## (`data/text/new_game_intro_frlg.inc:231-232`), verbatim — the rival-name
## equivalent of `OAK_SO_YOUR_NAME`'s own confirmation-prompt role.
const OAK_CONFIRM_RIVAL_NAME := "…Er, was it {RIVAL}?"
const OAK_REMEMBER_RIVAL := "That's right! I remember now!\nHis name is {RIVAL}!"
const OAK_LETS_GO := "{PLAYER}!\nYour very own POKéMON legend is about to unfold!\nA world of dreams and adventures with POKéMON awaits! Let's go!"


## [M27I I5-3a] Source's own field item-use messages (`strings.c:246/280/289`),
## with the trailing `{PAUSE_UNTIL_PRESS}` dropped — that is the message box's
## own press-to-dismiss behaviour here, not part of the text.
const ITEM_MSG_NO_EFFECT := "It won't have any effect."
const ITEM_MSG_HP_RESTORED := "{STR_VAR_1}'s HP was restored\nby {STR_VAR_2} point(s)."
const ITEM_MSG_BECAME_HEALTHY := "{STR_VAR_1} became healthy."


## [M27K K-b] The new-game sequence: Oak's speech, gender, both names.
##
## ⚠️ **WHAT THIS DELIBERATELY DOES NOT PORT.** `src/oak_speech.c` is 2193 lines
## and most of them are theatre this project has no layer for. The BEATS,
## their ORDER and the TEXT are source's.
##
## **[M27K K-b visuals] Portraits + ball release + background + platform**
## — see `OakSpeechOverlay` and `docs/m27k_oak_speech_visuals_recon.md`.
## Still deliberately absent: source's own BG-affine shrink exit (a plain
## fade stands in — recon confirmed no exotic technique is actually
## load-bearing for that beat, only the mechanism differs), fade-in/
## cross-fade/slide transitions between portraits, and the real
## recall-into-ball motion (a plain fade stands in there too).
##
## ⚠️ **THE BALL RELEASES A RANDOM ROSTER SPECIES, NOT SOURCE'S FIXED
## NIDORAN♀ — Rob's own call, fully random across all 386, legendaries
## included.** No cry plays — this project has no audio playback anywhere.
## See `OakSpeechOverlay.release_random_pokemon()`'s own doc comment.
##
## ⚠️ **GENDER IS ASKED BEFORE THE NAME, AND THAT ORDERING IS LOAD-BEARING** —
## `PlayerIdentity.name_choices()` keys the preset list on it, exactly as
## source's `sMaleNameChoices`/`sFemaleNameChoices` do, so asking in the other
## order would offer a list it then has to throw away.
##
## ⚠️ **THE GENDER QUESTION DIVERGES FROM SOURCE ON PURPOSE, Rob's call
## 2026-08-05.** Source shows NO portrait during the choice itself (Oak's own
## portrait slides off first, then a bare 2-line text menu asks BOY/GIRL —
## see the recon's §A5). This project shows Red and Leaf side by side instead,
## clickable directly — picking a look IS the answer, rather than a separate
## text choice followed by the portrait appearing after the fact.
func run_new_game() -> void:
	# [M27G G7] Was a ~60-line `await` coroutine. It is now an authored script
	# (`NewGameEvents`) run through the ordinary driver, which is what let the
	# duplicate input drivers below be deleted — see that file's own header for
	# why the coroutine had to go, and `docs/m27g_scope.md` G7.
	#
	# ⚠️ The identity is reset HERE rather than in the script: it is scene setup,
	# not a beat of the cutscene, and the script's very first `native` already
	# reads `OverworldSession.identity` for the portrait.
	OverworldSession.identity = PlayerIdentity.new()
	TextBuffers.identity = OverworldSession.identity
	if _oak_overlay == null or _driver == null:
		return
	run_script(NewGameEvents.LABEL)


## Show pages and wait for them to be dismissed. Expanded at print time, like
## every other message — `{PLAYER}` must read the name just chosen.
func _say(pages: Array) -> void:
	var out := PackedStringArray()
	var buffers := TextBuffers.new()
	for p in pages:
		out.append(buffers.expand(str(p)))
	_box.open(out)
	await _box.closed


## Offer the presets, then the keyboard if NEW NAME is picked.
func _ask_name(prompt: String, choices: PackedStringArray) -> String:
	_naming.open(prompt, choices)
	return await _naming.name_chosen


## [M27I I5-3] USE was chosen in the bag: the party opens as a TARGET PICKER.
func _on_bag_item_use(item_id: int) -> void:
	_pending_use_item = item_id
	var identity: Dictionary = PokemonRegistry.get_item_identity(item_id)
	_party_screen.open(OverworldSession.player_party(), str(identity.get("name", "")))


## ⚠️ THE ITEM IS CONSUMED ONLY IF IT DID SOMETHING. Source refuses a Potion on a
## full-HP Pokémon rather than eating it — `RemoveBagItem` sits on the SUCCESS
## branch only (`party_menu.c:4922`) — so the bag removal is gated on the effect
## actually landing, not on the pick.
##
## [M27I I5-3a] Both outcomes are ANNOUNCED, matching `ItemUseCB_Medicine`, and
## the flow afterwards is source's own conditional — see `_announce_item_use`
## and `_reopen_party_after_item` for the two findings that shaped this.
func _on_party_mon_chosen(index: int) -> void:
	# [M27G G2] Checked FIRST: the VM's own `WAIT_PARTY_CHOICE` is a third,
	# mutually-exclusive reason this screen could be open, alongside item-use
	# (`_pending_use_item >= 0`) and a plain browse (neither flag set).
	if _driver.claim_party_choice(index):
		return
	if _pending_use_item < 0:
		return
	var item_id := _pending_use_item
	_pending_use_item = -1
	var party := OverworldSession.player_party()
	if index < 0 or index >= party.members.size():
		return
	var mon: BattlePokemon = party.members[index]
	var item := ItemRegistry.get_item(item_id)
	if item == null:
		return
	var healed := 0
	var cured := false
	match item.battle_usage:
		ItemManager.BATTLE_USE_RESTORE_HP:
			healed = ItemManager.bag_item_heal(mon, item)
		ItemManager.BATTLE_USE_CURE_STATUS:
			cured = ItemManager.bag_item_cure_status(mon, item)
	if healed > 0 or cured:
		OverworldSession.bag.remove(item_id, 1)

	var pages := item_use_pages(mon, item, healed, cured)
	if _box == null or pages.is_empty():
		_reopen_party_after_item(item_id)
		return
	_box.open(pages)
	await _box.closed
	_reopen_party_after_item(item_id)


## The text for one item use. Returns a single page, or nothing if the item was
## not one this screen knows how to announce.
##
## ⚠️ **KEYED ON THE ITEM, NOT ON WHICH STATUS WAS CURED.** The natural guess —
## look up the ailment that went away — is wrong: `GetMedicineItemEffectMessage`
## (`party_menu.c:4764`) switches on `GetItemEffectType(item)`, so a Full Heal
## (`ITEM_EFFECT_CURE_ALL_STATUS`) always prints "became healthy" even when the
## only thing it cured was poison. Its `statusCured` argument is consulted by
## exactly ONE case, freeze-vs-frostbite, to split two ailments that share a
## single item effect type — a distinction this project's roster cannot reach.
##
## Strings are source's own (`strings.c:246/280/289`), minus the trailing
## `{PAUSE_UNTIL_PRESS}` control code, which is the message box's own
## press-to-dismiss behaviour here rather than something baked into the text.
static func item_use_pages(mon: BattlePokemon, item: ItemData, healed: int,
		cured: bool) -> PackedStringArray:
	var pages := PackedStringArray()
	if item == null:
		return pages
	var buffers := TextBuffers.new()
	buffers.set_slot(0, mon.species.species_name if mon.species != null else "")
	match item.battle_usage:
		ItemManager.BATTLE_USE_RESTORE_HP:
			if healed > 0:
				buffers.set_slot(1, str(healed))
				pages.append(buffers.expand(ITEM_MSG_HP_RESTORED))
			else:
				pages.append(ITEM_MSG_NO_EFFECT)
		ItemManager.BATTLE_USE_CURE_STATUS:
			pages.append(buffers.expand(ITEM_MSG_BECAME_HEALTHY)
					if cured else ITEM_MSG_NO_EFFECT)
	return pages


## ⚠️ **YOU STAY IN THE PARTY MENU IF YOU STILL HOLD THE ITEM.** Source decides
## this per use, not once: `Task_DisplayHPRestoredMessage` (`:5249`) and the cure
## branch (`:4946`) both hand off to `Task_ReturnToChooseMonAfterText` when
## `menuType == PARTY_MENU_TYPE_FIELD && CheckBagHasItem(item, 1)`, and to
## `Task_ClosePartyMenuAfterText` otherwise; a REFUSAL returns unconditionally
## (`:4910`), which the same count check covers, since a refused item was never
## consumed. So "use two Potions in a row" needs no second trip through the bag.
##
## [This corrects an earlier claim of mine that source "returns you to the bag
## afterwards". That is only the last-one-used case, which is the one the first
## live drive happened to exercise.]
##
## ⚠️ Deliberately NOT reproduced: source ALSO resets the prompt to "Choose a
## POKéMON." on the way back (`Task_ReturnToChooseMonAfterText` -> `:2065`), so
## the second use of a Potion is prompted as if you were merely browsing. That
## reads as a bug rather than a feature, and this screen keeps naming the item.
func _reopen_party_after_item(item_id: int) -> void:
	# The DECISION is the count, and nothing else — kept ahead of the node check
	# so it stays testable on a bare instance, where no screen exists.
	if OverworldSession.bag.count_of(item_id) <= 0:
		return
	_pending_use_item = item_id
	if _party_screen == null:
		return
	var identity: Dictionary = PokemonRegistry.get_item_identity(item_id)
	_party_screen.open(OverworldSession.player_party(),
			str(identity.get("name", "")))


func _on_party_cancelled() -> void:
	if _driver.claim_party_choice(-1):
		return
	_pending_use_item = -1


## [M27H H2/H3] One step's worth of wild encounter.
func _wild_step(prev_behavior: int) -> void:
	var map_name := manager.chunk_owning(_cell)
	if map_name == "":
		return
	# [M27E follow-up] No usable party, no encounter — checked BEFORE the roll
	# rather than leaving it to the mount guard below. Two reasons: the roll
	# consumes RNG and reads the lead's ability, neither of which should happen
	# for a battle that cannot occur; and being dragged into an encounter that
	# then silently declines is worse to watch than simply walking through the
	# grass. The mount guard stays as the backstop for every OTHER battle path
	# (trainer, scripted), which this one cannot cover.
	if not _party_can_battle():
		return
	var behavior := manager.behavior_at(_cell)
	var lead := _lead_ability_id()
	if not WildEncounters.should_encounter(map_name, behavior, prev_behavior, _rng, lead):
		return
	var party := WildEncounters.build_wild_party(map_name, _rng)
	if party == null:
		# The table named a species that will not build. Decline the encounter
		# rather than mount an empty battle, matching how an unresolvable trainer
		# roster is handled.
		push_warning("overworld: %s wild table produced no party" % map_name)
		return
	begin_wild_battle(party)


## [M27E follow-up] Is there anything to fight WITH?
##
## Two states answer no and they are genuinely different in origin, even though
## both black-screen identically: an EMPTY party (a debug boot, or a new game
## before Oak's script has run) and an ALL-FAINTED one (unreachable in correct
## play, since a wipe whites you out — but a guard that trusted that would be
## trusting the very thing that broke).
##
## ⚠️ `is_fully_fainted()` already answers BOTH, because its loop is vacuously
## true on an empty party. Relying on that silently would be too clever by half,
## so the empty case is tested explicitly and the intent is written down.
func _party_can_battle() -> bool:
	var p := OverworldSession.player_party()
	if p == null or p.members.is_empty():
		return false
	return not p.is_fully_fainted()


## The LEAD's ability id, or -1. Source's `WildEncounterCheck` reads
## `gParties[B_TRAINER_PLAYER][0]` specifically — the first party slot, not the
## active battler, because out of battle there is no active one.
func _lead_ability_id() -> int:
	var party := OverworldSession.party
	if party == null or party.members.is_empty():
		return -1
	var lead: BattlePokemon = party.members[0]
	if lead == null or lead.ability == null:
		return -1
	return int(lead.ability.ability_id)


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
	# [M27G G7 follow-up] Hand the names to the SCRIPT rather than opening a box
	# here. `_poison_step` was the last caller that drove the message box
	# outside the VM, and the last reason a second input driver existed in
	# `_process`. The script loops one `message` per name; see
	# `FieldPoisonEvents`.
	var names := PackedStringArray()
	for mon: BattlePokemon in FieldPoison.cure_at_one_hp(party):
		names.append(mon.species.species_name if mon.species != null else "")
	if names.is_empty():
		return
	FieldPoison.pending_names = names
	run_script(FieldPoisonEvents.LABEL)


## [Map scripts follow-up] A `Trigger` on the cell just arrived at
## (`field_control_avatar.c`'s coord_event half of `TryStartStepBasedScript`)
## — gated on its own var/value via `trigger_armed`, the same gate the
## editor overlay and `m27a_step_resolver_test.gd` already exercise, just
## never wired to anything that actually runs at play time. Fires on STEP
## COMPLETION for the same reason `check_trainer_sight` does: the condition
## is a static "which cell am I on" fact, so per-step is equivalent to
## source's real per-frame poll and cannot re-trigger while the player
## stands still (the script it runs is what changes the var, exactly the
## same self-disarming shape `Trigger`'s own doc comment already describes).
##
## [Stacked-trigger fix] Several idioms (gated triggers chief among them)
## legitimately place more than one `Trigger` on the same cell, each gated
## on the same var at a different value. `manager.entity_node_at` answers
## with only the first scene-tree match regardless of its own gate, which
## permanently shadowed every later-declared trigger on a shared cell even
## once ITS condition became true. Scanning every `Trigger` at the cell and
## taking the first one whose OWN gate is armed reproduces source's real
## `GetCoordEventScriptAtPosition`, which walks every coord_event at a
## position and returns the first one whose condition actually passes.
func check_step_trigger() -> bool:
	if _vm != null or _in_battle or _warping or _in_approach:
		return false
	var t: Trigger = null
	for n in manager.entities_at(_cell):
		var candidate := n as Trigger
		if candidate == null:
			continue
		if candidate.script_label == "" or candidate.script_label == "0x0":
			continue
		if flags.trigger_armed(candidate):
			t = candidate
			break
	if t == null:
		return false
	return run_script(t.script_label, t)


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
	return _mount_battle(opp, trainer_key, t)


## [M27H H3] A wild battle: the same mount, no trainer.
##
## ⚠️ The empty trainer key is LOAD-BEARING, not a placeholder.
## `BattleOutcome.should_set_defeated_flag` already reads `trainer_key != ""`, so
## a wild win correctly records nothing — and `[M27O O3]`'s prize money is 0
## because `Cmd_getmoneyreward` only pays for a trainer. Both fall out of the
## empty key rather than needing a wild-specific branch.
func begin_wild_battle(party: BattleParty) -> bool:
	if party == null or party.members.is_empty():
		return false
	return _mount_battle(party, "", null)


## Everything a battle needs regardless of who it is against.
func _mount_battle(opp: BattleParty, trainer_key: String, t: TrainerNPC) -> bool:
	# [M27E follow-up] ⚠️ **REFUSE BEFORE MUTATING ANYTHING.** A battle mounted
	# with nothing to fight with is an UNRECOVERABLE BLACK SCREEN, not a lost
	# fight: `BattleManager` dereferences the active slot immediately
	# (`Out of bounds get index '0'`, then a cascade of `Invalid access ... on a
	# base object of type 'Nil'`), and the field is left behind an overlay that
	# never becomes usable. Reported from play; reproduced headlessly.
	#
	# ⚠️ **THIS GUARD IS ORIGINAL, NOT A PORT, AND THAT IS WORTH KNOWING.**
	# Source has no equivalent: `WildEncounterCheck` reads
	# `gParties[B_TRAINER_PLAYER][0]` unconditionally (`wild_encounter.c:349`)
	# because the state is unreachable there — Oak blocks Route 1 until you have
	# a starter, and a wipe always whites you out. Here it IS reachable: a debug
	# boot has no party, and a new game has none until Oak's script runs.
	#
	# Sits at the very top so a refusal cannot leave `pending_trainer_key` set,
	# `_in_battle` true or `battle_starting` emitted. `push_warning`, not
	# `push_error`: this is a handled degrade, and `run_overworld_tests.sh`
	# fails a run on ERROR lines, so a test exercising the guard would fail the
	# whole suite rather than pass.
	if not _party_can_battle():
		push_warning("overworld: refusing to start a battle with no usable "
				+ "party — this would black-screen. Nothing was mounted.")
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
	# [M27H H4] Catch inputs. Badges scale the catch malus; party room decides
	# whether a throw is allowed at all — Rob's decision that a full party
	# REFUSES, which is source's own behaviour with no PC and is what lets the
	# PC be deferred past the slice.
	BattleSetupContext.badge_count = badge_count()
	BattleSetupContext.party_has_room = player_party.members.size() < BattleParty.PARTY_SIZE
	# ⚠️ The trailing `true` is what marks this an OVERWORLD battle, and it is
	# load-bearing: it is the only signal the battle screen can trust at `_ready`
	# time to tell a wild encounter from a simulator battle. Without it Run
	# forfeits instead of fleeing, and a forfeit whites the player out.
	BattleSetupContext.set_pending(player_party, opp, false, "", trainer_key, true)

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
	var caught: BattlePokemon = null
	if _battle_screen != null and is_instance_valid(_battle_screen) \
			and _battle_screen.has_method("caught_pokemon"):
		caught = _battle_screen.caught_pokemon()
	OverworldSession.set_result(BattleOutcome.make(
			outcome, OverworldSession.pending_trainer_key, prize, _battle_party_level,
			caught))
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

	# [Bugfix, "don't whiteout and heal"] Decided before EITHER the money or
	# the whiteout branch below, since both need to skip their normal defeat
	# handling when it applies — source's own `HealPlayerParty()` branch in
	# `CB2_EndTrainerBattle` (`battle_setup.c:1449-1452`) charges no money and
	# never reaches `CB2_WhiteOut` at all. ⚠️ Rob's own call: this does NOT
	# also mark the trainer defeated — `should_set_defeated_flag()` above
	# already correctly stays false for any LOST outcome regardless, so this
	# path is a pure "heal and continue," not "treat a loss as a win."
	var heal_after_loss := r.player_defeated() and _vm != null \
			and _vm.pending_battle_heal_after

	# [M27O O3] Money. Source does BOTH halves in one place
	# (`Cmd_getmoneyreward`) — the win prize and the loss payout — so they are
	# applied together here rather than split across the win and whiteout paths.
	# [M27H H4] A caught Pokémon joins the party. The refusal happens BEFORE the
	# throw (see `party_has_room`), so reaching here with a full party would mean
	# that gate failed — refuse again rather than silently dropping the mon.
	if r.caught_pokemon != null:
		var party := OverworldSession.player_party()
		if party.members.size() < BattleParty.PARTY_SIZE:
			party.members.append(r.caught_pokemon)
		else:
			push_warning("overworld: caught a Pokémon with a full party — refused")
	if r.outcome == BattleOutcome.WON:
		OverworldSession.wallet.earn(r.prize_money)
	elif r.player_defeated() and not heal_after_loss:
		OverworldSession.wallet.spend(whiteout_payout(r.highest_party_level))

	# [M27O O2] A defeat whites out. The flag above is deliberately NOT set on
	# this path — source only calls `SetBattledTrainersFlags` on its non-defeat
	# branch, which is what makes losing cost something.
	#
	# ⚠️ THE PARKED SCRIPT MUST NOT RESUME. `CB2_WhiteOut` calls
	# `ScriptContext_Init()`, which wipes the script state outright — the
	# trainer's post-battle branch does not run after you black out. Resuming it
	# would hand out the reward for a fight you lost.
	if r.player_defeated() and not heal_after_loss:
		# ⚠️ Source's gate is `IsPlayerDefeated && NoAliveMonsForPlayer()`, not
		# defeat alone. That second half is currently UNREACHABLE-BUT-EQUIVALENT
		# here: with no persistent party, every battle starts at full health, so
		# a defeat means the party was wiped in that battle and "no alive mons"
		# is true by construction. It becomes a real distinction the moment a
		# party survives between battles — M27K/M27L — and belongs here.
		_abandon_script()
		battle_returned.emit(r)
		return true

	# [Bugfix] The heal-after loss's own healing step — source's
	# `HealPlayerParty()`, the exact heal a real whiteout would otherwise have
	# applied for free at the respawn point. Done here, BEFORE resuming the
	# script below, so the calling script's own post-battle dialogue plays out
	# against an already-healed party rather than a fainted one.
	if heal_after_loss:
		OverworldSession.heal_party()

	# [Bugfix, rolled in from the same source function] `DowngradeBadPoison()`
	# — source calls it on every branch that reaches this point (won,
	# already-beaten, heal-after loss), never on a real whiteout (which heals
	# everything anyway and returns above). Toxic poison resets to plain
	# poison the instant a battle you don't whiteout from ends with it still
	# active.
	OverworldSession.downgrade_bad_poison()

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
## [M27H H4] How many badges the player holds.
##
## Extracted from `whiteout_payout`, which counted them inline — two consumers
## now, and two hand-kept copies of one rule is the drift this project already
## paid for once with `check_bake_diff`.
func badge_count() -> int:
	# [M27L L1] Delegates — the list and the count both moved to `FlagStore`, so
	# the save-slot summary can count badges with no field scene loaded.
	return flags.badge_count()


func whiteout_payout(highest_level: int) -> int:
	var badges := badge_count()
	# Explicit `: int` — indexing an untyped Array yields Variant, which `:=`
	# cannot infer from. This project's own documented GDScript gotcha.
	var asked: int = int(WHITEOUT_BADGE_MONEY[mini(badges, WHITEOUT_BADGE_MONEY.size() - 1)]) \
			* maxi(1, highest_level)
	return mini(asked, OverworldSession.wallet.money)


## [Bugfix, live-reported: a trainer's ORIGINAL spawn cell stays permanently
## blocked after it approaches and battles, even though the trainer visibly
## ends up standing somewhere else entirely] This used to reimplement "which
## chunk owns this entity" as an ORIGIN-based geometry test — `e.cell` is
## LOCAL to the chunk the entity actually lives in, but the old body added
## EVERY *candidate* chunk's own origin to that local cell and checked whether
## the result fell inside THAT candidate's rect, never checking which chunk
## the entity is actually parented under. For any entity whose real home
## chunk sits at a non-zero origin, its raw local cell trivially collides with
## whichever OTHER loaded chunk happens to sit at origin (0,0) (Route1/
## Pallet Town in the corridor), so `_run_trainer_approach()`'s own
## `manager.start_entity_movement(map_name, ...)` call silently updated the
## WRONG chunk's occupancy dictionary on every step of the approach — the
## trainer's real spawn cell in its own chunk was never erased, and its new
## cell got written into a chunk nobody ever queries. `MapManager.map_name_of()`
## already answers this correctly, by real scene-tree ancestry rather than
## origin arithmetic, and is what `move_entity`/`start_movement_for_entity`
## already trust for this exact question — delegated to it instead of keeping
## a second, broken reimplementation.
func _owning_map_of(e: OverworldEntity) -> String:
	return manager.map_name_of(e)


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
## [M27R 7a-1] The scene's audio player, for the `ScriptDriver` and for the
## `WaitFanfare`/`WaitSe` native handlers.
##
## Public accessor rather than a public field, matching `scene()`'s own reason:
## a handler is ordinary Godot code living outside this file and legitimately
## needs it, so the surface is one named thing. May be null before
## `_setup_scripting` has run, and every caller treats null as "no audio".
func field_audio() -> GameAudio:
	return _audio


func _setup_scripting() -> void:
	# [M27R 7a-1] BEFORE `_driver.setup`, because `run_script` reads
	# `field_audio()` when it builds each VM — an audio player created after the
	# driver would leave the first script of the session silent.
	_audio = GameAudio.new()
	_audio.name = "GameAudio"
	add_child(_audio)
	# [M27G G4] The driver is created FIRST — `_vm` is a forwarding property
	# onto it, so anything touching `_vm` before this line would silently read
	# null rather than erroring.
	_driver.setup(self)
	_box = MessageBox.new()
	add_child(_box)
	_yes_no = YesNoBox.new()
	add_child(_yes_no)
	# [M27G] The general list-choice widget. Owns its own input — see
	# MultichoiceGrid's header for why that is the design and not a second
	# driver.
	_multichoice = MultichoiceGrid.new()
	add_child(_multichoice)
	_shop_screen = FieldShopScreen.new()
	add_child(_shop_screen)
	_start_menu = FieldStartMenu.new()
	add_child(_start_menu)
	_naming = NamingScreen.new()
	add_child(_naming)
	_oak_overlay = OakSpeechOverlay.new()
	add_child(_oak_overlay)
	_weather = WeatherManager.new()
	add_child(_weather)
	manager.set_weather_material(_weather.material())
	_bag_screen = FieldBagScreen.new()
	add_child(_bag_screen)
	_party_screen = FieldPartyScreen.new()
	add_child(_party_screen)
	_start_menu.bag_selected.connect(_on_start_menu_bag)
	_start_menu.save_selected.connect(_on_start_menu_save)
	_start_menu.pokemon_selected.connect(_on_start_menu_pokemon)
	_bag_screen.item_use_requested.connect(_on_bag_item_use)
	# [M27I I6d] SELL opens the bag in a shop context and reports back.
	_shop_screen.sell_requested.connect(_on_shop_sell_requested)
	_party_screen.mon_chosen.connect(_on_party_mon_chosen)
	_party_screen.cancelled.connect(_on_party_cancelled)


## Press A: what does it hit?
##
## Ported dispatch order and the counter hop live in Interaction; this is the
## wiring. Returns true if something was started.
func try_interact() -> bool:
	if _vm != null or _in_battle or _warping or _moving or _in_approach:
		return false
	# [M27E E1b] ⚠️ CHECKED BEFORE `Interaction.resolve`, because water carries no
	# script and no entity — it would return empty and the press would be eaten
	# with nothing to show for it. Source reaches surfing the same way, through
	# the ordinary interact path (`EventScript_UseSurf`), not a dedicated key.
	if _try_surf():
		return true
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


## [M27G G4] Start a script. Forwards to the driver, which owns execution.
##
## Kept on the scene because "run this script" is what every TRIGGER already
## calls — `try_interact`, `check_step_trigger`, `check_trainer_sight`,
## `check_on_frame_map_script` and the warp arrival hooks — and those are all
## scene concerns. The seam is execution, not entry.
func run_script(label: String, p_subject: OverworldEntity = null) -> bool:
	return _driver.run_script(label, p_subject)


## Advance the running script. Called once per frame while `_vm` is live.
func _drive_script() -> void:
	_driver.drive()


func _expanded_pages() -> PackedStringArray:
	return _driver.expanded_pages() if _driver != null else PackedStringArray()


func _finish_script() -> void:
	_driver.finish()


## Stop whatever is running WITHOUT reporting a coverage gap — the battle-return
## path uses it, because a script interrupted by a whiteout has not hit an
## unimplemented opcode. Kept on the scene alongside the other four forwarders:
## "abandon the running script" is a scene-level capability even now the
## implementation lives in the driver, and `m27o_whiteout_test` D.02 asserts the
## scene exposes it.
func _abandon_script() -> void:
	_driver.abandon()


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


## [M27E E2] May the player RUN out of `current_behavior` right now?
##
## Ported from the run branch of `PlayerAllowForcedMovementIfMovingSameDirection`'s
## caller (`field_player_avatar.c:906-919`), keeping source's own gate order and
## dropping only the parts with nothing here to check.
##
## Deliberately NOT modelled, each for a stated reason rather than by omission:
##   * `!(flags & PLAYER_AVATAR_FLAG_UNDERWATER)` — there is no underwater state;
##   * `ObjectMovingOnRockStairs` (which picks `PlayerRunSlow`) — no rock-stair
##     behaviour is imported, so the slow-run variant is unreachable;
##   * `FollowerNPCComingThroughDoor` / `I_ORAS_DOWSING_FLAG` — neither system
##     exists here.
##
## ⚠️ SURFING RETURNS FALSE BECAUSE SOURCE NEVER REACHES THE RUN BRANCH WHILE
## SURFING — it returns one block earlier, at `PLAYER_AVATAR_FLAG_SURFING`, having
## already moved at `PlayerWalkFast`. So a surfing player is not "a runner who is
## refused"; the question is never asked. Same for a ledge hop, which source
## resolves and returns from further up still.
func _can_run(current_behavior: int, outcome: int) -> bool:
	return _can_run_with(current_behavior, outcome, Input.is_key_pressed(_RUN_KEY))


## The gate itself, with the held-key state passed in.
##
## ⚠️ Split out so every condition is testable deterministically. `Input`'s own
## key state cannot be driven from a headless test — this project has already
## paid for that twice (K-b's naming screen was unreachable FROM THE KEYBOARD
## because its driver called the handler directly, and L2's yes/no repeated the
## mistake), so the seam is here rather than a driver reaching past it. **The one
## thing this shape does NOT cover is the key read in `_can_run` above**; that is
## a live-drive check, and is called out as such.
func _can_run_with(current_behavior: int, outcome: int, run_held: bool) -> bool:
	if OverworldSession.surfing:
		return false
	if outcome == StepResolver.Outcome.LEDGE_JUMP:
		return false
	if not run_held:
		return false
	if not flags.flag_get(RUN_FLAG):
		return false
	if MetatileBehavior.is_running_disallowed(current_behavior):
		return false
	# The sheet has the final say. Bound here rather than at build time because
	# `_player_anim` is re-`setup()` on every surf swap, and a walker with no run
	# sheet bound answers false — which is what keeps every NPC from running.
	_player_anim.setup(_player_graphics_id())
	_player_anim.setup_run(PLAYER_RUN_SHEET_ID)
	return _player_anim.can_run()


## Turn the player and stand still.
func _face_player(dir: int) -> void:
	_facing = dir
	# Resting ends the run — the cycle must settle on the STANDING frame, which
	# is not one of the run frames.
	_running = false
	var spr := _player_sprite()
	if spr == null:
		return
	_player_anim.setup(_player_graphics_id())
	_player_anim.rest(spr, WalkAnim.facing_name(dir))
	if _surf_blob != null and is_instance_valid(_surf_blob):
		_surf_blob.face(WalkAnim.facing_name(dir))


## Advance the player's walk cycle one tick.
func _step_player(dir: int, ticks: int, delta: float) -> void:
	_facing = dir
	var spr := _player_sprite()
	if spr == null:
		return
	_player_anim.setup(_player_graphics_id())
	# [M27E E2] `ticks` is the WALK cadence and is meaningless to the run cycle,
	# which is timed against the step's own duration instead — see
	# `WalkAnim.run_cycle_frame` for why the 5:3 split cannot survive ticks here.
	if _running:
		_player_anim.setup_run(PLAYER_RUN_SHEET_ID)
		_player_anim.run_step(spr, WalkAnim.facing_name(dir), _RUN_STEP_SECONDS, delta)
	else:
		_player_anim.step(spr, WalkAnim.facing_name(dir), ticks, delta)
	if _surf_blob != null and is_instance_valid(_surf_blob):
		_surf_blob.face(WalkAnim.facing_name(dir))


## True while anything `waitmovement` could be waiting on is still walking.
##
## `waitmovement 0` means "everything", not "object 0" — LOCALID_NONE is 0, so
## there is no object to name. A named target waits only on that one mover.
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
## [M27R 7a-2] Returns whether a door actually opened. Was `void`; the caller
## now needs to tell "blocked, and nothing happened" (a bump) from "blocked,
## because it is a door" — a door tile is SOLID, so both reach the same branch
## and only the return value separates them.
func _try_door_warp(dir: int) -> bool:
	if _warping or dir != StepResolver.Dir.NORTH:
		return false
	var target: Vector2i = _cell + StepResolver.STEP[dir]
	# Only a tile that CANNOT be entered — anything walkable is the step-on
	# path's business, and firing here as well would double-trigger it.
	if manager.collision_at(target) == 0:
		return false
	var w := manager.warp_at(target)
	if w == null:
		return false
	if _audio != null:
		_audio.play_se("SE_DOOR")
	_do_warp(w)
	return true


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

	await _run_arrival_map_scripts(dest)

	await _fade_to(0.0)
	await _exit_arrival(arrival.get("warp"))
	_warping = false
	# [Bugfix, live-reported: Oak's Lab OnFrame cutscene starts one tile late]
	# `check_on_frame_map_script()`'s ONLY other call site is the step-tween's
	# own `finished` callback (`_try_step`), so an arrival that happens under
	# ordinary player control (no script running — e.g. walking through the
	# lab door on your own, following Oak in) left the OnFrame table unchecked
	# until the player took one MORE voluntary step afterward. The condition
	# it gates on (`VAR_MAP_SCENE_...`) was already true the instant the warp
	# landed, so the cutscene started a tile late and the player looked like
	# they'd wandered off rather than followed Oak. Checked here too, right
	# after `_warping` clears (its own guard), so an already-true condition
	# fires on arrival instead of waiting for the next step.
	check_on_frame_map_script()


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
	# [Bugfix, live-reported: player stays invisible after a door-entry warp]
	# `set_invisible`/`set_visible` (MovementRunner's own instantaneous
	# actions) write straight to `_player.visible`, and a real door-entry
	# cutscene (`PalletTown_Movement_PlayerEnterLab`, ending in
	# `set_invisible` right before the warp — a real, correct match for
	# source's own "vanish into the doorway" beat) leaves it false. `_player`
	# is the SAME node across a warp (`_teardown_and_load`'s own doc comment:
	# reparented, never freed, "the difference between a relocation and
	# deleting the player"), so nothing else ever undoes it — there is no
	# fresh node defaulting back to visible the way an NPC on the new map
	# gets. Unconditional here rather than only after a scripted warp,
	# because a plain door `Warp` node reaches this exact function too and a
	# future authored door-entry movement on THAT path would hit the
	# identical bug. Arriving anywhere is always the right moment to be
	# shown again — there is no real scenario where the player should still
	# be invisible once standing on a freshly-loaded map.
	_player.visible = true
	_player.position = manager.local_pixel_of(_cell)
	_snap_camera_to_player()
	if _camera != null:
		_camera.reset_smoothing()
	if _weather != null:
		_weather.request_weather(manager.weather_of(dest))
	# An interior has none; an outdoor destination needs its own back.
	manager.load_neighbours(dest)


## [Map scripts] `RunOnTransitionMapScript` + `TryRunOnWarpIntoMapScript`
## (`script.c:383,414`) — real per-map auto-fire scripts, checked once on
## arriving in a NEW current map via a real warp. Entirely separate from the
## interact/trigger/warp-node scripts already built: the importer already
## extracted these into `map_scripts.json` (`<Map>_OnTransition`/`_OnWarp`)
## but nothing ever ran them, so `VAR_MAP_SCENE_*`-gated scenes (Oak's Lab's
## own starter table among them) could never advance past their own first
## gate. Both run to completion before the screen fades back in, matching
## source's real "before InitMap()" positioning as closely as this
## project's per-frame VM allows (see `_run_map_script_to_completion`'s own
## doc comment for what "to completion" means here).
##
## Deliberately NOT run on a connection crossing (the soft-boundary
## streaming path) — source treats every map change as a full reload and
## would run these there too, but this project's own C4/C5 decisions keep
## connection-crossing lightweight and streamed on purpose. Also not run at
## boot (a new game's own very first map). Both are disclosed
## simplifications, not oversights — neither is needed for any script this
## project currently ships, and extending coverage to them is straightforward
## once a real one is found to need it.
func _run_arrival_map_scripts(map_name: String) -> void:
	var prefix := _map_script_prefix(map_name)
	await _run_map_script_to_completion(prefix + "_OnTransition")
	await _run_map_script_to_completion(prefix + "_OnWarp")


## [Map scripts] `MapConstants.map_name_for`/`chunk_owning` both answer with
## the BAKED SCENE name (`PalletTown_ProfessorOaksLab_Frlg`, matching the
## `.tscn` on disk) — but `map_scripts.json`'s own keys never carry the
## `_Frlg` suffix (`PalletTown_ProfessorOaksLab_OnFrame`, matching the
## importer's own label convention, same as every other script label in the
## corpus). The exact "map constants are not derivable by naming convention
## alone" trap this project has already paid for once for tileset
## directories and node names — caught here only by live-driving the fix,
## since a silently-unresolved label degrades to "nothing happens" with no
## warning anywhere.
static func _map_script_prefix(map_name: String) -> String:
	return map_name.substr(0, map_name.length() - 5) if map_name.ends_with("_Frlg") else map_name


## Runs `label` to completion if it exists — a thin wrapper around the SAME
## run_script()/_drive_script() pipeline any other script uses (already
## driven automatically, once per frame, by `_process()`'s own `_vm != null`
## branch); the caller here just awaits instead of handing control back to
## the player. This project has no truly-synchronous execution mode the way
## source's `RunScriptImmediately` is, so "runs before anything else" is
## expressed by awaiting completion before the caller's own next step —
## safe for OnTransition/OnWarp specifically because neither ever reaches a
## `message` anywhere in its own call graph (checked directly against every
## corridor map's own table before relying on this), so this can never
## stall on player input mid-fade.
func _run_map_script_to_completion(label: String) -> void:
	if _driver == null or not _driver.has_script(label):
		return
	if not run_script(label):
		return
	while _vm != null:
		await get_tree().process_frame


## [Map scripts] `TryRunOnFrameMapScript` (`script.c:403`) — the per-map
## OnFrame table. Source polls this every raw frame via
## `ProcessPlayerFieldInput`; checked here at the SAME step-completion
## cadence as `check_trainer_sight` instead, because the condition it tests
## only ever changes as the RESULT of a script running, never from mere
## movement — step-completion is equivalent in practice and matches this
## project's own established cadence for exactly this class of check.
## Source's real priority is trainer sight FIRST, then this; call sites must
## preserve that order.
##
## Unlike OnTransition/OnWarp, this genuinely BECOMES the running script
## (`ScriptContext_SetupScript`, not `RunScriptImmediately`) — it can take
## input, show messages, queue movements, all across many frames, the same
## as an interact-triggered script. Returns true if a script was started, so
## the caller can freeze whatever it gates on that step.
func check_on_frame_map_script() -> bool:
	if _vm != null or _in_battle or _warping or _in_approach:
		return false
	var map_name := manager.chunk_owning(_cell)
	if map_name == "":
		return false
	var label := _map_script_prefix(map_name) + "_OnFrame"
	if _driver == null or not _driver.has_script(label):
		return false
	return run_script(label)


## [Map scripts] `_do_warp`'s own counterpart for a script-driven warp — the
## `warp` opcode names an explicit destination CELL rather than a warp id
## (source's `ScrCmd_warp` reads x/y literally), so this skips
## `warp_arrival` entirely and places the player at the named cell once the
## destination is loaded. Mirrors `_do_warp`'s own sequence otherwise,
## including running the destination's OnTransition/OnWarp. Resumes the VM
## with a plain resume() — like WAIT_MOVEMENT, there is no result to branch
## on.
func _do_scripted_warp(warp_data: Dictionary) -> void:
	var map_token := str(warp_data.get("map", ""))
	var dest := MapConstants.map_name_for(map_token)
	if dest == "" or not MapConstants.is_baked(map_token):
		print("overworld: scripted warp to %s is not baked — staying put" % map_token)
		if _vm != null:
			_vm.resume()
		return

	_warping = true
	await _fade_to(1.0)

	_teardown_and_load(dest)

	_cell = Vector2i(int(warp_data.get("x", 0)), int(warp_data.get("y", 0)))
	_place_player(dest, _cell)

	await _run_arrival_map_scripts(dest)

	await _fade_to(0.0)
	# No real Warp node on the destination side to read an exit_dir from —
	# _exit_arrival(null) degrades to its own collision-based fallback,
	# which is the correct behaviour for a scripted arrival.
	await _exit_arrival(null)
	_warping = false
	# See the identical fix/comment in `_do_warp` — same latent gap, same fix.
	# A no-op here whenever the calling script (about to `resume()`) is still
	# the active `_vm`, which is the common case for a scripted `warp` opcode.
	check_on_frame_map_script()
	if _vm != null:
		_vm.resume()


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
	_tween_player_position(t, manager.local_pixel_of(_cell), 0.16)
	await t.finished


## [M27E E1b] Face water, press A, ride out — if the badge says so.
##
## ⚠️ **SILENT ON EVERY REFUSAL EXCEPT THE BADGE ONE.** Facing ordinary land, or
## already surfing, must fall through to the normal interact path rather than
## printing anything — otherwise every press at a wall would answer about surfing.
## Only NO_BADGE speaks, because that is the one case where the player did aim at
## water and deserves to know why nothing happened.
func _try_surf() -> bool:
	if _box == null or _yes_no == null:
		return false
	var faced: Vector2i = _cell + Vector2i(StepResolver.STEP[_facing])
	var m := FieldMoves.can_mount(flags, manager.behavior_at(faced),
			OverworldSession.surfing)
	if m == FieldMoves.Mount.NOT_WATER or m == FieldMoves.Mount.ALREADY_SURFING:
		return false
	if m == FieldMoves.Mount.NO_BADGE:
		_box.open(PackedStringArray([
				FieldMoves.blocked_message(FieldMoves.Ability.SURF)]))
		return true
	_mount_surf.call_deferred()
	return true


## The prompt, then the ride. Deferred out of `try_interact` so the await does
## not run inside the input handler that started it.
func _mount_surf() -> void:
	# The SAVE flow's own shape: the box and the prompt open together and the box
	# closes on the answer. Awaiting `_box.closed` first would deadlock — nothing
	# can close it, because the yes/no that takes the keypress is not up yet.
	_box.open(PackedStringArray([FieldMoves.SURF_PROMPT]))
	_yes_no.open()
	var yes: bool = await _yes_no.chosen
	_box.close()
	if not yes:
		return
	_ride_out()


## [M27E E1c] Everything a confirmed mount actually DOES, split out of the
## awaiting shell above so the effect is reachable without driving a yes/no
## prompt — the await is the one part a test cannot step through.
##
## ⚠️ **THE STEP ONTO THE WATER IS PART OF MOUNTING, NOT A SEPARATE ACTION.**
## Source's `EventScript_UseSurf` jumps the player onto the water tile as the
## mount itself; without it the blob appears under a player still standing on
## the shore, which reads as a broken mount rather than a missing flourish. The
## ordinary step machinery does the move — with `surfing` now true the resolver
## allows it, and it is a real step in every sense (sight checks, step scripts),
## which source's jump also is. Disclosed divergence: a glide, not the jump arc,
## since this project has no jump animation. The open message box blocks INPUT,
## not a programmatic step.
func _ride_out() -> void:
	OverworldSession.surfing = true
	# [M27E E1e] Set BEFORE `_sync_surfing()`: that swaps the player onto the
	# surf sheet (which source also does before the jump,
	# `ObjectEventSetGraphicsId` in `SurfFieldEffect_JumpOnSurfBlob`) and would
	# otherwise attach the blob immediately, leaving it to arc along as a child.
	_mount_jump_active = true
	_sync_surfing()
	# ⚠️ `{PLAYER}`, expanded at print time — the badge-only gate leaves no
	# Pokemon to name, so the player is the subject.
	# ⚠️ Expanded through `TextBuffers`, not `_expanded_pages()` — that one reads
	# the VM's own pending pages and there is no VM behind this.
	if _box != null:
		# [M27E E1f] Auto-closes — Rob's call from live play. This is an
		# announcement, not a conversation, and requiring a press to dismiss
		# "{PLAYER} used SURF!" puts a keypress between the player and the thing
		# they just asked for. A disclosed divergence from source, which waits
		# for a press on essentially every message; see MessageBox.open.
		_box.open(PackedStringArray([
				TextBuffers.new().expand(FieldMoves.used_message(
						FieldMoves.Ability.SURF))]), _USED_MOVE_MESSAGE_SECONDS)
	_jump_onto_water(_facing)


## [M27E E1d] The mount's own move, and it is a JUMP — it does not consult the
## step resolver at all.
##
## ⚠️ **THIS CANNOT GO THROUGH `_try_step`, AND E1c's FIRST CUT DID.** Kanto's
## water is elevation 1 against land's 3, so the ordinary rules refuse the step
## onto it — correctly, and source refuses it too. Source's mount is
## `GetJumpSpecialMovementAction` (`SurfFieldEffect_JumpOnSurfBlob`,
## `src/field_effect.c`), a held movement that bypasses collision and elevation
## exactly as this project's own scripted `applymovement` already does
## (`[M27F Stage 3]`: "SCRIPTED MOVEMENT IGNORES COLLISION, DELIBERATELY").
## Going through the resolver looked right, passed a suite built on
## uniform-elevation fixtures, and could never move the player on a real map.
##
## Deliberately skips the step-completion scripts (warp, sight, poison,
## encounter): you are landing on water, where source has none of them, and
## water encounters are not wired yet regardless.
func _jump_onto_water(dir: int) -> void:
	if _player == null or _moving:
		return
	_cell = _cell + Vector2i(StepResolver.STEP[dir])
	_elev = manager.elevation_at(_cell)
	_reparent_for_elevation()
	_moving = true
	_step_ticks = _player_step_ticks(_MOUNT_JUMP_SECONDS)
	var t := create_tween()
	t.set_parallel(true)
	_tween_player_position(t, manager.local_pixel_of(_cell), _MOUNT_JUMP_SECONDS)
	# ⚠️ **THE ARC IS ON THE BODY SPRITE, NOT ON `_player`.** The blob is a CHILD
	# of `_player`, so arcing the node would hop the water with you — and source
	# does the opposite: `SurfFieldEffect_JumpOnSurfBlob` creates the blob at the
	# DESTINATION coords while the player arcs onto it. Driving the sprite alone
	# keeps the blob still, and `_mount_jump_active` holds it back until landing
	# so there is nothing to fight over `position.y` mid-flight.
	var spr := _player_sprite()
	var base_y := spr.position.y if spr != null else 0.0
	_add_jump_arc(t, spr, base_y, _MOUNT_JUMP_SECONDS)
	t.finished.connect(func() -> void: _finish_mount_jump(spr, base_y))


## Add source's jump arc to an existing tween, driving `spr`'s own y.
##
## Shared by the mount and the dismount because source uses the identical
## movement for both — `GetJumpSpecialMovementAction` in
## `SurfFieldEffect_JumpOnSurfBlob` and again in `Task_StopSurfingInit`.
func _add_jump_arc(t: Tween, spr: Sprite2D, base_y: float, secs: float) -> void:
	if spr == null:
		return
	t.tween_method(
			func(p: float) -> void:
				if not is_instance_valid(spr):
					return
				var i := clampi(int(p * float(_JUMP_Y_HIGH.size())), 0,
						_JUMP_Y_HIGH.size() - 1)
				spr.position.y = base_y + float(_JUMP_Y_HIGH[i]),
			0.0, 1.0, secs)


## [M27E E1f] Start riding ashore, ported from `Task_StopSurfingInit`
## (`field_player_avatar.c:1997`).
##
## ⚠️ **THE BLOB STOPS FOLLOWING THE MOMENT THE DISMOUNT BEGINS.** Reported from
## play as "the blob follows the player onto land for half a grid space", and
## source is explicit about why it should not: `UpdateBobbingEffect` only runs
## `sprite->x = playerSprite->x` inside `if (bobState != BOB_JUST_MON)`, and the
## dismount's first act is `SetSurfBlob_BobState(..., BOB_JUST_MON)`. So the blob
## keeps bobbing on the water while the player leaves it, and is destroyed only
## when the jump lands (`Task_WaitStopSurfing`'s `DestroySprite`).
##
## Here the blob is a CHILD of the player, so "stops following" means `top_level`
## — it keeps its current global position and ignores the parent's motion.
## BOB_JUST_MON's other half (stop driving the player's own y) falls out of
## releasing the body sprite at the same time.
func _begin_dismount() -> void:
	_surf_exit_pending = true
	if _surf_blob != null and is_instance_valid(_surf_blob):
		_surf_blob.stay_behind()


## The landing. Split out of the tween's own callback so it is reachable without
## a live SceneTree — `create_tween()` needs one, and this project's suites drive
## bare off-tree instances, so a test could otherwise never see the blob attach.
func _finish_mount_jump(spr: Sprite2D, base_y: float) -> void:
	_moving = false
	# Land on the CAPTURED base rather than trusting the sampled index to have
	# reached the table's final 0 — a dropped frame would otherwise leave the
	# player permanently floating.
	if spr != null and is_instance_valid(spr):
		spr.position.y = base_y
	_mount_jump_active = false
	# NOW the blob appears, under a player who has arrived on it.
	_update_surf_visuals()
	if _surf_blob != null and is_instance_valid(_surf_blob):
		_surf_blob.set_near_shore(_surf_shore_adjacent(_cell))


## Push the session's surf state onto the resolver, which is what actually
## decides whether water is passable.
##
## ⚠️ ONE WRITER. The resolver's flag is deliberately never set anywhere else —
## two places deciding whether the player is on water is exactly how a mount that
## half-took would happen.
func _sync_surfing() -> void:
	if _resolver != null:
		_resolver.surfing = OverworldSession.surfing
	# [M27E E1c] The visuals follow the same one flag from the same one writer,
	# so a mount that half-took cannot leave the sheet and the rules disagreeing.
	_update_surf_visuals()


## [M27E E1c] Make what the player LOOKS like agree with whether they are
## surfing: the surf sheet plus the blob on the water, the walking sheet and no
## blob on land. Idempotent — safe to call from every site that touches the
## flag, and from `_build_player_node` on a rebuild.
func _update_surf_visuals() -> void:
	if _player == null:
		return
	var spr := _player_sprite()
	if spr == null:
		return
	var has_blob := _surf_blob != null and is_instance_valid(_surf_blob)
	if OverworldSession.surfing and not has_blob:
		_surf_exit_pending = false
		_swap_player_sheet(spr, PLAYER_SURF_GRAPHICS_ID)
		# [M27E E1e] The sheet swaps now, the blob waits for the landing. Source
		# does the same split: the graphics id changes before the jump starts,
		# the blob is created at the destination. Attaching it here would make
		# it a child that arcs along with the player.
		if _mount_jump_active:
			return
		_surf_blob = SurfBlob.attach(_player, spr, WalkAnim.facing_name(_facing))
	elif not OverworldSession.surfing and has_blob:
		# Riding ashore flips the flag at step START (`_try_step` updates `_cell`
		# before the tween runs), and yanking the blob at that instant reads as
		# it sinking while the player is still visibly on the water. Held until
		# the step's own tween lands — which is also source's own timing:
		# `Task_WaitStopSurfing` destroys the blob when the JUMP finishes, not
		# when it starts. `_begin_dismount` has already stopped it following.
		if _moving:
			_surf_exit_pending = true
			return
		_surf_exit_pending = false
		_surf_blob.detach()
		_surf_blob = null
		_swap_player_sheet(spr, PLAYER_GRAPHICS_ID)


## Swap the player's sprite sheet and rebind the walk-cycle clock to it in one
## place — the texture and the anim's own frame table must never disagree,
## because the surf sheet's frames 3+ are FRLG's unrelated run cycle.
func _swap_player_sheet(spr: Sprite2D, gid: String) -> void:
	var path := ObjectEventGraphics.sheet_path(gid)
	if path != "" and ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		if tex != null:
			spr.texture = tex
	# [M27E E1f] ⚠️ **THE RIDER SITS 8px HIGHER, AND THE FIGURE IS DERIVED, NOT
	# TUNED BY EYE.** Reported from play as "the player sits too low on the
	# blob". FRLG ships a COMBINED 32x32 surfing sprite (`green_surf.png`,
	# unreferenced in source like the Kanto blob itself) where the character and
	# the blob are drawn as one piece — that art is the authored answer to how
	# the two sit together. Leaf's hat crown is at y4 there and at y12 on the
	# standalone 16x32 sheet this project draws, so the rider is exactly 8px low.
	#
	# The combined sprite is deliberately NOT used instead: it cannot be taken
	# apart, and the dismount needs the blob to STAY on the water while the
	# player jumps ashore (see `_begin_dismount`).
	var size := ObjectEventGraphics.frame_size(gid)
	spr.position.y = float(SurfBlob.CELL - size.y)
	if gid == PLAYER_SURF_GRAPHICS_ID:
		spr.position.y -= float(_SURF_RIDER_LIFT)
	_player_anim.setup(gid)
	_player_anim.rest(spr, WalkAnim.facing_name(_facing))


## Which sheet the player's anim should be driving RIGHT NOW. Keyed on the
## blob's presence, not the session flag — during the deferred dismount the
## flag is already false while the surf texture is still on the sprite, and
## keying on the flag there would run walk-cycle frame indices against the
## surf sheet's run frames.
func _player_graphics_id() -> String:
	if _surf_blob != null and is_instance_valid(_surf_blob):
		return PLAYER_SURF_GRAPHICS_ID
	return PLAYER_GRAPHICS_ID


## [M27E E1c] Is any cardinal neighbour dismountable land? Source's
## `SynchronizeSurfPosition` scans DIR_SOUTH..DIR_EAST for
## ELEVATION_DEFAULT (3, `global.fieldmap.h:18`) and slows the bob when one
## matches — the "bobs slower while dismounting" nuance.
func _surf_shore_adjacent(gcell: Vector2i) -> bool:
	for d in [StepResolver.Dir.SOUTH, StepResolver.Dir.NORTH,
			StepResolver.Dir.WEST, StepResolver.Dir.EAST]:
		if manager.elevation_at(gcell + Vector2i(StepResolver.STEP[d])) == 3:
			return true
	return false


## [M27I I6d] The clerk's SELL action: open the bag across ALL pockets, in a
## shop context, exactly as `CB2_GoToSellMenu` does.
##
## ⚠️ The shop stays OPEN underneath — leaving the bag returns to the clerk
## rather than ending the shop, matching `Task_GoToBuyOrSellMenu`'s own
## "Anything else I can help with?" So the script stays parked on WAIT_NATIVE
## throughout, and only QUIT releases it.
var _selling := false

func _on_shop_sell_requested() -> void:
	_selling = true
	_bag_screen.open(OverworldSession.bag)


func _on_shop_sell_chosen(item_id: int) -> void:
	if not _selling:
		return
	# A stack of one skips the picker; anything more sells one at a time here,
	# which is the honest shape until a real quantity prompt lands.
	var msg := _shop_screen.sell_from_bag(item_id, 1)
	_bag_screen.close()
	_selling = false
	_box.open([msg])
