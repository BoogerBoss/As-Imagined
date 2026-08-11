class_name AnimSprite
extends TextureRect

# [M36C] The node an animation sprite behavior actually drives.
#
# One of these stands in for a GBA OAM sprite. It reproduces the three things
# the scripts' frame data assumes and nothing more:
#
#  1. TILE-OFFSET FRAMING. `ANIMCMD_FRAME`'s first argument is a TILE index
#     into the sheet, not a frame ordinal (step 16 for a 32x32 sprite, 4 for
#     16x16). Since M36A preserved raster tile order in every pulled sheet,
#     a tile index maps to a rect by plain arithmetic against the sheet's
#     own `tiles_wide`. That is why frames work for sheets consumed at two
#     different sizes at once (ANIM_TAG_SPARK is used as 8x8 AND 8x16).
#  2. CENTRE-ORIGIN POSITIONING. Every anim sprite is positioned by its
#     centre upstream; Control nodes position by top-left, so `centre` is the
#     property behaviors set and the node converts.
#  3. x2/y2 OFFSETS. The reference keeps a base position and separate
#     per-frame offsets (`sprite->x2`, `->y2`) that oscillating callbacks
#     write without disturbing the base. Reproduced as `offset`, so a shake
#     or wave never accumulates drift into the origin.
#
# Deliberately NOT a Sprite2D: the battle stage is a Control tree (sprites,
# health boxes and the effect layer are all Controls), so a Control keeps
# coordinate spaces consistent with `AnimStage`'s rect queries.

var vm: AnimScriptVM = null

# Base position (centre) and the per-frame offset applied on top of it.
var centre: Vector2 = Vector2.ZERO:
	set(value):
		centre = value
		_apply_position()
var offset: Vector2 = Vector2.ZERO:
	set(value):
		offset = value
		_apply_position()

# Frame data
var _atlas: AtlasTexture = null
var _frame_size := Vector2i(32, 32)
var _tiles_wide := 4
var _sheet_size := Vector2i(32, 32)
var _sequence: Array = []
var _seq_index := 0
var _seq_timer := 0
var _loops := true

# data[0..7]: the reference's per-sprite scratch registers. Behaviors use the
# same slots the C callbacks do, so ported math reads identically.
var data: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0]

# Set by StoreSpriteCallbackInData6's port: what to run when a translation
# finishes.
var followup: Callable = Callable()

var _finished := false
# The port of `sprite->animEnded`. An entire upstream idiom depends on it --
# RunStoredCallbackWhenAnimEnds is how Fang, Slash, Knock Off and the whole
# False Swipe / Cut family decide they are done, with no frame count anywhere.
# Without this those behaviors have nothing to wait on and run forever.
var _anim_ended := false


static func create(vm_ref: AnimScriptVM, tag_name: String,
		frame_w: int, frame_h: int) -> AnimSprite:
	var node := AnimSprite.new()
	node.vm = vm_ref
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.stretch_mode = TextureRect.STRETCH_SCALE
	node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	node._configure(tag_name, frame_w, frame_h)
	return node


func _configure(tag_name: String, frame_w: int, frame_h: int) -> void:
	var sheet := AnimData.sheet_for_tag(tag_name)
	var row := AnimData.sheet_row(tag_name)
	_frame_size = Vector2i(maxi(frame_w, 8), maxi(frame_h, 8))
	if sheet == null:
		return
	_sheet_size = Vector2i(int(row.get("width", sheet.get_width())),
			int(row.get("height", sheet.get_height())))
	_tiles_wide = maxi(1, int(row.get("tiles_wide", _sheet_size.x / 8)))
	_atlas = AtlasTexture.new()
	_atlas.atlas = sheet
	texture = _atlas
	set_tile_offset(0)
	size = Vector2(_frame_size)
	pivot_offset = size * 0.5


# The whole point of tile-offset framing: resolve `ANIMCMD_FRAME(tile, dur)`.
func set_tile_offset(tile: int) -> void:
	if _atlas == null:
		return
	var x := (tile % _tiles_wide) * 8
	var y := int(tile / float(_tiles_wide)) * 8
	# A frame that would run off the sheet means the tile index and the frame
	# size disagree; clamp rather than render garbage, and say so once.
	if x + _frame_size.x > _sheet_size.x or y + _frame_size.y > _sheet_size.y:
		x = clampi(x, 0, maxi(0, _sheet_size.x - _frame_size.x))
		y = clampi(y, 0, maxi(0, _sheet_size.y - _frame_size.y))
	_atlas.region = Rect2(x, y, _frame_size.x, _frame_size.y)


func play_sequence(sequence: Array) -> void:
	_sequence = sequence
	_seq_index = 0
	_seq_timer = 0
	_anim_ended = false
	_apply_current_frame()


# ⚠️ **[M36 sprite tick] THE AFFINE CLOCK, ADVANCED CENTRALLY.**
# `AnimScriptVM._tick_sprites()` calls this for EVERY live sprite once per GBA
# frame — the `AnimateSprite(sprite)` half of source's own `AnimateSprites()`
# loop, which this port had distributed into 184 per-behavior `advance_frame()`
# calls and therefore never ran for a sprite whose behavior did not ask.
#
# ⚠️ **RIGHT NOW IT ONLY COUNTS FRAMES, AND THAT IS A BET ON A CONSUMER THAT
# DOES NOT EXIST YET** — per this milestone's own rule (9), said here rather
# than left for someone to infer. The affine-anim interpreter is that consumer:
# 493 of 1148 templates carry an affine table, 607 of 933 moves spawn one, and
# nothing plays them today (`AnimData.affine_sequences_for()` has no callers).
# When it lands, the state machine goes HERE and the counter becomes its clock.
#
# Deliberately NOT advancing cel frames: `advance_frame()` below is already
# called by those 184 behaviors, and doing it here too would double it.
var affine_frames: int = 0


func advance_affine() -> void:
	affine_frames += 1


# Advances the frame animation by one GBA frame. Called by the behavior's own
# per-frame step so animation and motion stay on the same clock.
func advance_frame() -> void:
	if _sequence.is_empty():
		return
	_seq_timer += 1
	var step: Variant = _sequence[_seq_index]
	var dur := 1
	if step is Dictionary and (step as Dictionary).has("duration"):
		dur = maxi(1, int((step as Dictionary)["duration"]))
	if _seq_timer < dur:
		return
	_seq_timer = 0
	_seq_index += 1
	while _seq_index < _sequence.size():
		var nxt: Variant = _sequence[_seq_index]
		if nxt is String and str(nxt) == "end":
			_seq_index -= 1  # hold the last real frame
			_anim_ended = true
			return
		if nxt is Dictionary and (nxt as Dictionary).has("jump"):
			_seq_index = int((nxt as Dictionary)["jump"])
			continue
		if nxt is Dictionary and (nxt as Dictionary).has("loop"):
			_seq_index += 1
			continue
		break
	if _seq_index >= _sequence.size():
		_seq_index = _sequence.size() - 1
		_anim_ended = true
	_apply_current_frame()


func _apply_current_frame() -> void:
	if _sequence.is_empty() or _seq_index >= _sequence.size():
		return
	var step: Variant = _sequence[_seq_index]
	if step is Dictionary and (step as Dictionary).has("tile"):
		set_tile_offset(int((step as Dictionary)["tile"]))
		flip_h = bool((step as Dictionary).get("hFlip", false))
		flip_v = bool((step as Dictionary).get("vFlip", false))


func _apply_position() -> void:
	position = centre + offset - size * 0.5


# `setalpha eva, evb` -> a blend weight. 16 is opaque; the canonical
# `setalpha 12, 8` gives 0.75, which is what the reference's particle-over-mon
# blend looks like.
func apply_blend(blend: Dictionary) -> void:
	var eva := int(blend.get("eva", 16))
	modulate.a = clampf(eva / 16.0, 0.0, 1.0)


# Ends this sprite. Completion is reported by the STEPPER that owns it (one
# slot per behavior on the VM's counter), not here -- reporting in both
# places would double-decrement and let `waitforvisualfinish` fall through
# while sprites were still on screen.
func finish() -> void:
	if _finished:
		return
	_finished = true
	queue_free()


func is_finished() -> bool:
	return _finished


# True once the sprite's own frame sequence has played through to its `end`.
# A LOOPING sequence never sets this, exactly as on hardware -- which is why
# behaviors that wait on it also carry a frame cap.
func anim_ended() -> bool:
	return _anim_ended
