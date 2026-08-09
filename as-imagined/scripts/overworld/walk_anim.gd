class_name WalkAnim
extends RefCounted

## [M27F Stage 3b] One walker's sprite-frame animation.
##
## Held by whatever owns a sprite that walks — every NPC, and the player. The
## motion itself belongs to [MovementRunner]; this only decides WHICH FRAME is
## showing, so the two can be reasoned about (and broken) independently.
##
## ⚠️ **THE CLOCK MUST FREE-RUN ACROSS STEPS, AND THAT IS THE WHOLE MECHANISM.**
## Source starts a walk with `StartSpriteAnimIfDifferent` — the animation is
## only restarted when the requested anim CHANGES, so walking three tiles south
## in a row runs one continuous four-entry cycle and the feet genuinely
## alternate. Restarting per step is the obvious implementation and is wrong in
## a specific, recognisable way: the same foot leads every tile and the walk
## reads as a hop. `_key` is what makes the difference — same key, keep
## accumulating; different key, reset to the start of the cycle.
##
## The cycle is four entries, not two: `FRAME(stepA) FRAME(idle) FRAME(stepB)
## FRAME(idle)`. The resting frame is PART of the walk. Alternating stepA/stepB
## alone drops half the animation and reads as a shuffle.
##
## Timing is WALL CLOCK, matching the runner it plays against — [M26G4] measured
## frame-tied stepping running ~10% slow at 144 Hz and half speed at 30 Hz.

const FRAME := 1.0 / 60.0

var _graphics_id := ""
var _frames := 0
var _key := ""
var _elapsed := 0.0

## [M27E E2] The RUN sheet, bound separately — see `setup_run`.
var _run_graphics_id := ""
var _run_texture: Texture2D = null
var _run_frames := 0
var _walk_texture: Texture2D = null
## Which sheet is currently on the sprite, so the swap only costs an assignment
## when the cycle actually crosses between them.
var _sheet_applied := ""


## Bind this to a graphics id. Safe to call again; it resets if the id changed.
func setup(graphics_id: String) -> void:
	if graphics_id == _graphics_id:
		return
	_graphics_id = graphics_id
	_frames = ObjectEventGraphics.frame_count(graphics_id)
	_key = ""
	_elapsed = 0.0
	# [M27E E2] Cached so a run can swap back without a load, and cleared so the
	# next draw re-applies it — the surf path assigns `sprite.texture` directly
	# (`_swap_player_sheet`), so this class must never assume the sheet it last
	# applied is still the one on the sprite.
	_sheet_applied = ""
	_walk_texture = null
	var path := ObjectEventGraphics.sheet_path(graphics_id)
	if path != "" and ResourceLoader.exists(path):
		_walk_texture = load(path) as Texture2D


## Can this sheet hold a walk cycle at all?
##
## 70 of the 385 ids carry only the three facing frames and 96 carry a single
## frame — a sign or a static prop has nothing to animate, and indexing a step
## frame on one would read past the end of its sheet.
func animates() -> bool:
	return _frames >= ObjectEventGraphics.MIN_FRAMES_TO_ANIMATE


## Show the resting frame for a facing, and stop the cycle.
##
## Called when a walker stops, so the next step starts its cycle cleanly rather
## than resuming mid-stride from wherever it happened to stop.
## Idempotent: the overworld calls this every idle frame, so re-resting an
## already-resting walker must cost nothing and must not re-write the region.
func rest(sprite: Sprite2D, facing: String) -> void:
	var key := "rest:" + facing
	if key == _key:
		return
	_key = key
	_elapsed = 0.0
	_draw(sprite, facing, int(ObjectEventGraphics.FACE_FRAME.get(facing, 0)))


## Advance the cycle by `delta` and show the frame it lands on.
##
## `ticks` is how long ONE cycle entry is held, in 60ths — 8 for a normal or
## slow walk, 4 for fast, 2 for faster. See ObjectEventGraphics' own note on
## why slow reuses the normal value rather than doubling it.
func step(sprite: Sprite2D, facing: String, ticks: int, delta: float) -> void:
	if not animates():
		# A single- or three-frame sheet still has to FACE the right way while
		# it slides; it just cannot animate. Silently drawing frame 0 here would
		# make every sign face south the moment a script moved it. Routed
		# through `rest` so it is idempotent rather than redrawing every frame.
		rest(sprite, facing)
		return
	var key := "%s:%d" % [facing, ticks]
	if key != _key:
		_key = key
		_elapsed = 0.0
	else:
		_elapsed += delta
	_draw(sprite, facing, cycle_frame(facing, ticks, _elapsed))


## [M27E E2] Bind the sheet the RUN cycle draws from.
##
## ⚠️ **RUNNING USES A DIFFERENT SHEET FROM WALKING, AND THAT IS THE WHOLE SHAPE
## OF IT.** Kanto packs the player's run frames into `leaf/green_surf_run.png`
## alongside the surf poses; source stitches them onto the walking sheet through
## `sPicTable_GreenNormal` and calls them frames 9-19. This project does NOT
## materialise that stitched sheet (Rob's call — the file is already on disk), so
## the run frames are read from the second sheet directly and this class swaps
## the sprite's texture for the duration of a run.
##
## ⚠️ THE FRAME COUNT IS MEASURED FROM THE TEXTURE, not taken from the id's own
## declared `frames`. `FRAME_OVERRIDES` deliberately reports 3 for the surf ids
## (their pic table only uses the three facing poses), so asking the table would
## refuse the very sheet the run frames live on.
func setup_run(run_graphics_id: String) -> void:
	if run_graphics_id == _run_graphics_id:
		return
	_run_graphics_id = run_graphics_id
	_run_texture = null
	_run_frames = 0
	var path := ObjectEventGraphics.sheet_path(run_graphics_id)
	if path == "" or not ResourceLoader.exists(path):
		return
	var tex := load(path) as Texture2D
	if tex == null:
		return
	var size := ObjectEventGraphics.frame_size(run_graphics_id)
	if size.x <= 0:
		return
	_run_texture = tex
	_run_frames = int(tex.get_width() / size.x)


## Can the bound run sheet hold a run cycle?
##
## False until `setup_run` has bound a real sheet, so a walker that was never
## given one — every NPC — can never be asked for a frame it does not have.
func can_run() -> bool:
	return _run_frames >= ObjectEventGraphics.MIN_RAW_FRAMES_TO_RUN


## Advance the RUN cycle and show the frame it lands on.
##
## `step_seconds` is how long ONE TILE takes, not one cycle entry — see
## `run_cycle_frame` for why running is timed differently from walking.
func run_step(sprite: Sprite2D, facing: String, step_seconds: float, delta: float) -> void:
	if not can_run():
		# Should be unreachable (the caller gates on `can_run`), but a walker
		# with no run sheet bound must degrade to a walk rather than index off
		# the end of the strip it does have.
		step(sprite, facing, ObjectEventGraphics.ANIM_TICKS_FAST, delta)
		return
	var key := "run:%s:%.4f" % [facing, step_seconds]
	if key != _key:
		_key = key
		_elapsed = 0.0
	else:
		_elapsed += delta
	_draw(sprite, facing, run_cycle_frame(facing, step_seconds, _elapsed), true)


## Which sheet frame the RUN cycle is on after `elapsed` seconds.
##
## ⚠️ **TIMED IN SECONDS AGAINST THE STEP, NOT IN FIXED TICKS LIKE THE WALK, AND
## THAT IS FORCED BY THE 5:3 SPLIT.** Source runs a tile in 8 frames and holds
## its four anim entries for 5,3,5,3 — so the same "two cycle entries per tile"
## invariant the walk keeps also holds for the run, but the two entries are
## UNEVEN. This project's step is its own tuned duration rather than source's 8
## frames, and at ~4.8 frames a tile an integer-tick split of 5:3 would round to
## 3:2 or 2:1 and visibly distort the gait. Scaling the ratio instead keeps the
## asymmetry exact at any step duration.
##
## Free-running across steps for the same reason the walk does — see the header.
static func run_cycle_frame(facing: String, step_seconds: float, elapsed: float) -> int:
	var idle: int = int(ObjectEventGraphics.RUN_IDLE_FRAME.get(facing, 9))
	var pair: Array = ObjectEventGraphics.RUN_STEP_FRAME.get(facing, [idle, idle])
	var ticks: Array = ObjectEventGraphics.RUN_TICKS
	# One source frame of the run anim, scaled to this project's own step: the
	# four entries span 16 source frames and exactly two tiles.
	var unit := maxf(step_seconds, FRAME) / float(ticks[0] + ticks[1])
	var total: float = float(ticks[0] + ticks[1] + ticks[2] + ticks[3])
	var t := fposmod(elapsed / unit, total)
	# [neutral, legA, neutral, legB] — the neutral is a RUN frame, never the
	# standing pose the walk rests on.
	if t < float(ticks[0]):
		return idle
	if t < float(ticks[0] + ticks[1]):
		return int(pair[0])
	if t < float(ticks[0] + ticks[1] + ticks[2]):
		return idle
	return int(pair[1])


## Which sheet frame this facing/speed is on after `elapsed` seconds.
##
## Pure and static so the cycle maths is testable without a Sprite2D, a
## SceneTree or a live walker.
static func cycle_frame(facing: String, ticks: int, elapsed: float) -> int:
	var idle: int = int(ObjectEventGraphics.FACE_FRAME.get(facing, 0))
	var pair: Array = ObjectEventGraphics.STEP_FRAME.get(facing, [idle, idle])
	var entry_seconds := maxf(FRAME, float(ticks) * FRAME)
	var i := int(floorf(elapsed / entry_seconds)) % ObjectEventGraphics.WALK_CYCLE_LEN
	# [stepA, idle, stepB, idle] — see the header on why idle is in here twice.
	match i:
		0: return int(pair[0])
		2: return int(pair[1])
		_: return idle


func _draw(sprite: Sprite2D, facing: String, frame: int, run := false) -> void:
	if sprite == null or not is_instance_valid(sprite):
		return
	# [M27E E2] A run frame lives on a different sheet, so the texture has to
	# follow the cycle. Guarded on the id actually changing: this runs every
	# frame of every walk in the game.
	var gid := _run_graphics_id if run else _graphics_id
	if gid != _sheet_applied:
		var tex: Texture2D = _run_texture if run else _walk_texture
		if tex != null:
			sprite.texture = tex
			_sheet_applied = gid
	var size := ObjectEventGraphics.frame_size(gid)
	sprite.region_rect = Rect2(frame * size.x, 0, size.x, size.y)
	sprite.flip_h = facing == "EAST" and ObjectEventGraphics.EAST_IS_MIRRORED_WEST


## [M27R Step 1] Draw one RAW sheet frame directly, bypassing the facing/cycle
## vocabulary entirely.
##
## ⚠️ Clamped to the sheet's real frame count rather than trusted. The bow's own
## source anim quotes pic-table index 9 against a four-frame sheet, so an
## un-translated index is exactly the mistake this guards — it would read past
## the strip and draw empty space, which looks like a sprite that vanished
## mid-animation rather than like a bad index.
func show_raw(sprite: Sprite2D, raw_index: int) -> void:
	if sprite == null or not is_instance_valid(sprite):
		return
	var count := ObjectEventGraphics.frame_count(_graphics_id)
	if count <= 0:
		return
	_draw(sprite, "SOUTH", clampi(raw_index, 0, count - 1))


## Direction constant -> the facing name the frame tables are keyed by.
static func facing_name(dir: int) -> String:
	match dir:
		StepResolver.Dir.NORTH: return "NORTH"
		StepResolver.Dir.WEST: return "WEST"
		StepResolver.Dir.EAST: return "EAST"
		_: return "SOUTH"
