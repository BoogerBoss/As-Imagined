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


# Re-frames an already-created sprite at a different OAM size.
#
# ⚠️ **THIS IS A REAL UPSTREAM IDIOM, NOT A CONVENIENCE.** A sprite's OAM shape
# and size are template defaults that a callback may OVERRIDE on its first
# frame — `AnimElectricBoltSegment` (`battle_anim_electric.c:912`) is the
# worked example, writing `oam.shape/size` to 8x16 or 16x16 depending on the
# bolt style while its template declares 8x8. Without this the port draws the
# template default forever, which for that behavior meant five 8px sparks
# spaced 16px apart: a dotted line where the reference draws a bolt.
#
# The tile offset is re-applied because `set_tile_offset` clamps against the
# frame size, so a resize can legitimately change which rect a given tile
# index resolves to. This class's own header already anticipated the case
# ("ANIM_TAG_SPARK is used as 8x8 AND 8x16"); this is the setter that was
# missing.
func set_frame_size(frame_w: int, frame_h: int, tile: int = -1) -> void:
	_frame_size = Vector2i(maxi(frame_w, 8), maxi(frame_h, 8))
	size = Vector2(_frame_size)
	pivot_offset = size * 0.5
	set_tile_offset(tile if tile >= 0 else _current_tile)
	_apply_position()


# The tile index currently framed, so a resize can re-resolve it.
var _current_tile: int = 0


# The whole point of tile-offset framing: resolve `ANIMCMD_FRAME(tile, dur)`.
func set_tile_offset(tile: int) -> void:
	_current_tile = tile
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


# ══ [M36F] The SPRITE-path affine player ══════════════════════════════════
#
# ⚠️ **THERE ARE TWO AFFINE RUNNERS IN SOURCE AND THEY READ THE SAME TABLE
# FORMAT WITH OPPOSITE SCALE CONVENTIONS. THIS IS THE SPRITE ONE.**
#
#   SPRITE path (here) — `AnimateSprite` -> `ApplyAffineAnimFrameRelativeAnd
#   UpdateMatrix` (`sprite.c:1327`) sends the accumulator through
#   `ConvertScaleParam` = `0x10000 / scale` BEFORE `ObjAffineSet`, so the
#   accumulator IS the visual scale (256 == 1.0) and a NEGATIVE delta SHRINKS.
#
#   TASK path — `RunAffineAnimFromTaskData` (`battle_anim_mons.c`) hands the
#   accumulator STRAIGHT to `SetSpriteRotScale`, so it is the texture STEP and
#   a negative delta GROWS. `AnimBehaviors._run_affine_cmds` serves that path
#   and is right to use `256 / accumulator`.
#
# **DO NOT UNIFY THEM.** M36R already got this wrong in both directions once
# each; 493 of 1148 templates name a table, so an inverted convention would be
# wrong everywhere at once.
#
# ⚠️ **THE PLAYER COMPOSES WITH A BASE RATHER THAN ASSIGNING.** `_make_sprite`
# writes `scale = ONE * pixel_scale` so a GBA particle occupies the same
# fraction of this stage as of a 240px screen, and some behaviors additionally
# set an OAM size preset before the first tick. On hardware the OAM shape/size
# and the affine matrix are separate and multiply; this port encodes both as
# `scale`, so the base is captured at BEGIN and multiplied through. Assigning
# instead would silently flatten every hit splat to its table's scale.
#
# ── Disclosed divergences, recorded so neither is "fixed" later ────────────
#
# **1. AffineNormal CLIPPING IS NOT REPRODUCED, AND THAT IS THE PORT'S ACCURACY
# CEILING HERE.** `ST_OAM_AFFINE_NORMAL` transforms a sprite inside its ORIGINAL
# OAM box, so anything the matrix pushes past the box edge is cut off on
# hardware; `ST_OAM_AFFINE_DOUBLE` is the mode that reserves a double-size box
# for exactly that reason. Godot's `scale` clips nothing, so an enlarging
# AffineNormal sprite draws whole here and cropped there.
#
# ⓘ **Measured at 21 of the 274 AffineNormal templates that carry a table** —
# i.e. the great majority only ever shrink or rotate, where the two agree.
# M36F's own scoping said "153 of 273"; that figure was wrong and is retracted.
# Not worth a viewport per sprite for 21 templates, so it is recorded rather
# than built.
#
# **2. A SEQUENCE OPENING ON A LOOP MARKER IS NOT UNION-PUNNED** — see
# `_begin_affine`.
#
# ⚠️ **AND IT RUNS AFTER THE BEHAVIOR, WHICH IS SOURCE'S OWN ORDER** —
# `AnimateSprites` is `callback(sprite)` then `AnimateSprite(sprite)`, and
# `AnimScriptVM.step()` is `_step_behaviors()` then `_tick_sprites()`. So where
# a ported behavior still drives the same channel by hand (10 of them do, per
# M36F's contention triage) the TABLE wins the frame, exactly as the OAM matrix
# does on hardware. Those hand-rolled workarounds are now inert and are the
# next thing to retire, not something to suppress the player for.

# `AFFINEANIMCMDTYPE_*` (`include/sprite.h`). Only END is ever compared against
# directly here; the extractor already resolved LOOP/JUMP into named fields.
const AFFINE_IDENTITY := 256
const AFFINE_ROT_SHIFT := 8
# One turn in the units `ObjAffineSet` takes. ⚠️ The same conversion lives at
# `AnimBehaviors._gba_rot_to_radians`, which serves the TASK path; the two are
# deliberately separate classes and must stay in step.
const AFFINE_ROT_UNITS_PER_TURN := 65536.0
# A degenerate accumulator (<= 0) is a real hardware state — the matrix mirrors
# or divides by zero — with no sane Godot equivalent, so it floors here rather
# than producing a NaN transform. Not a tuning value: nothing in the corpus is
# expected to reach it, and anything that does is a bug worth seeing as a dot.
const AFFINE_MIN_VISUAL_SCALE := 0.01
# Bounds the LOOP -> `ContinueAffineAnim` recursion source expresses through the
# call stack. A table cannot legitimately need 512 command dispatches to produce
# one frame's matrix; this stops a malformed one hanging the VM instead.
const AFFINE_DISPATCH_BUDGET := 512

# ⚠️ **[M36 sprite tick] THE AFFINE CLOCK, ADVANCED CENTRALLY.**
# `AnimScriptVM._tick_sprites()` calls `advance_affine()` for EVERY live sprite
# once per GBA frame — the `AnimateSprite(sprite)` half of source's own
# `AnimateSprites()` loop, which this port had distributed into 184 per-behavior
# `advance_frame()` calls and therefore never ran for a sprite whose behavior
# did not ask. The counter itself predates the player and is kept because tests
# and behaviors read it as a plain frame count.
#
# Deliberately NOT advancing cel frames: `advance_frame()` below is already
# called by those 184 behaviors, and doing it here too would double it.
var affine_frames: int = 0

var _affine_seqs: Array = []
var _affine_on := false
var _affine_num := 0
var _affine_index := 0
var _affine_delay := 0
var _affine_loop := 0
var _affine_beginning := true
var _affine_anim_ended := false
var _affine_x := AFFINE_IDENTITY
var _affine_y := AFFINE_IDENTITY
var _affine_rot := 0
var _affine_base_scale := Vector2.ONE
var _affine_base_rotation := 0.0
var _affine_base_captured := false


# Binds the template's affine table and OAM mode. Called from `_make_sprite`,
# which is the one seam all 291 spawn sites go through.
#
# ⚠️ **THE OAM MODE IS A REAL GATE, NOT A FORMALITY.** `BeginAffineAnim`
# (`sprite.c:1086`) tests `oam.affineMode & ST_OAM_AFFINE_ON_MASK` first, and
# **19 of the 493 templates that name an affine table declare `AffineOff`** —
# hardware never applies those matrices, so neither does this. The split is
# AffineNormal 274 / AffineDouble 200 / AffineOff 19.
#
# ⓘ A mid-session "correction" of that 19 to 27 was itself wrong and is
# retracted: the extra 8 were templates whose bespoke OAM struct the extractor
# had never decoded, so they carried no `affine` field and a `.get(default)`
# swept them into the off bucket. All 8 are affine-ON in source, and
# `gen_battle_anim_meta.parse_oam_structs` now reads them — which is the real
# fix, because the gate silencing 8 templates hardware animates would have been
# invisible. Measure, then measure the measurement.
func setup_affine(template_name: String, oam: Dictionary) -> void:
	_affine_seqs = AnimData.affine_sequences_for(template_name)
	var mode := str(oam.get("affine", "AffineOff"))
	_affine_on = mode != "AffineOff" and not _affine_seqs.is_empty()


# `StartSpriteAffineAnim` (`sprite.c:1391`) — selects a sequence AND resets the
# accumulators to identity, via `AffineAnimStateStartAnim`.
func start_affine_anim(anim_num: int) -> void:
	_affine_num = anim_num
	_affine_index = 0
	_affine_delay = 0
	_affine_loop = 0
	_affine_x = AFFINE_IDENTITY
	_affine_y = AFFINE_IDENTITY
	_affine_rot = 0
	_affine_beginning = true
	_affine_anim_ended = false


# `ChangeSpriteAffineAnim` (`sprite.c:1407`).
#
# ⚠️ **THIS IS NOT `start_affine_anim` WITH A DIFFERENT NAME — IT DELIBERATELY
# KEEPS THE ACCUMULATORS.** Source sets only `animNum` and the beginning/ended
# flags, so the new sequence continues from whatever scale and rotation the old
# one reached. `_mimic_orb`'s own `ChangeSpriteAffineAnim(sprite, 1)` depends on
# it: the orb hands its current size to the second sequence rather than snapping
# back to full size first.
func change_affine_anim(anim_num: int) -> void:
	_affine_num = anim_num
	_affine_beginning = true
	_affine_anim_ended = false


# The port of `sprite->affineAnimEnded`. A sequence that JUMPs never sets it,
# exactly as on hardware — which is why the behaviors that wait on it also carry
# a frame cap.
func affine_ended() -> bool:
	return _affine_anim_ended


func has_affine_anim() -> bool:
	return _affine_on


func advance_affine() -> void:
	affine_frames += 1
	if not _affine_on:
		return
	if _affine_beginning:
		_begin_affine()
	else:
		_continue_affine()


# `BeginAffineAnim` (`sprite.c:1086`). Note it uses `AffineAnimStateRestartAnim`,
# which resets the CURSOR (index/delay/loop) and deliberately not the
# accumulators — that is what makes `change_affine_anim` above carry over.
func _begin_affine() -> void:
	var first: Variant = _cmd_at(0, _affine_num)
	if first == null or first is String:
		# `affineAnims[0][0].type != AFFINE_ANIM_END` in source: a sequence that
		# is nothing but a terminator never starts, so the sprite is left alone.
		_affine_beginning = false
		return
	_affine_index = 0
	_affine_delay = 0
	_affine_loop = 0
	_affine_beginning = false
	_affine_anim_ended = false
	_capture_affine_base()
	# ⚠️ **DISCLOSED DIVERGENCE: A SEQUENCE OPENING ON A LOOP MARKER IS NOT
	# APPLIED AS A FRAME.** `GetAffineAnimFrame` reads the command union's frame
	# fields whatever the command actually is, so on hardware a leading LOOP is
	# reinterpreted as an absolute set with the opcode word (0x7FFD) standing in
	# for xScale — garbage, and only expressible if the port carried the raw type
	# words the extractor has already resolved away. Skipping instead leaves the
	# cursor on the marker, so the next tick dispatches it properly and the
	# following LOOP rewinds to exactly the right place.
	if (first as Dictionary).has("duration"):
		_apply_affine_frame(first as Dictionary)


# `ContinueAffineAnim` (`sprite.c:1103`) plus the four command handlers. Source
# expresses LOOP as a recursive call back into `ContinueAffineAnim`; this is the
# same control flow as a bounded loop, which also gives the runaway a floor.
func _continue_affine() -> void:
	if _affine_delay > 0:
		# `AffineAnimDelay`: the counter drops AND the same delta re-applies, so
		# a multi-frame FRAME command produces continuous motion rather than one
		# step followed by a hold. Applying it once and idling is the plausible
		# misreading and makes every affine anim stutter.
		_affine_delay -= 1
		var held: Variant = _cmd_at(_affine_index, _affine_num)
		if held is Dictionary and (held as Dictionary).has("duration"):
			_apply_affine_relative(held as Dictionary)
		return
	var budget := AFFINE_DISPATCH_BUDGET
	while budget > 0:
		budget -= 1
		_affine_index += 1
		var cmd: Variant = _cmd_at(_affine_index, _affine_num)
		if cmd == null:
			# ⚠️ **THE TRAILING-LOOP OVERRUN GUARD, AND IT IS A REPRODUCED
			# UPSTREAM BUG RATHER THAN A PORT DEFECT.** Two sequences
			# (`gSleepLetterZAffineAnimCmds*_2`) end on LOOP with no terminator,
			# and `JumpToTopOfAffineAnimLoop` only rewinds while the counter is
			# nonzero — so once exhausted, source genuinely walks off the end of
			# the array and reads whatever follows it in ROM. There is nothing
			# faithful to reproduce, so the port ends the sequence instead.
			_affine_cmd_end()
			return
		if cmd is String:
			_affine_cmd_end()
			return
		var d: Dictionary = cmd
		if d.has("jump"):
			_affine_index = int(d["jump"])
			var target: Variant = _cmd_at(_affine_index, _affine_num)
			if target is Dictionary and (target as Dictionary).has("duration"):
				_apply_affine_frame(target as Dictionary)
			else:
				_affine_cmd_end()
			return
		if d.has("loop"):
			# `AffineAnimCmd_loop`: the FIRST arrival seeds the counter, every
			# later one decrements it. A count of 0 therefore rewinds nothing and
			# the command acts purely as a loop-top MARKER for the next LOOP to
			# rewind to — which is how `sAffineAnim_TailGlowOrb` is built.
			if _affine_loop > 0:
				_affine_loop -= 1
			else:
				_affine_loop = int(d["loop"])
			_jump_to_top_of_affine_loop()
			continue
		_apply_affine_frame(d)
		return


# `JumpToTopOfAffineAnimLoop` (`sprite.c:1165`): walk back to the command just
# after the PREVIOUS loop marker (or the start), then one further so the
# caller's own `index++` lands on it.
func _jump_to_top_of_affine_loop() -> void:
	if _affine_loop <= 0:
		return
	_affine_index -= 1
	while _affine_index > 0:
		var prev: Variant = _cmd_at(_affine_index - 1, _affine_num)
		if prev is Dictionary and (prev as Dictionary).has("loop"):
			break
		_affine_index -= 1
	_affine_index -= 1


# `AffineAnimCmd_end` (`sprite.c:1191`). The index steps BACK so the next tick's
# `index++` lands on the terminator again — the sprite idles on END rather than
# running off the array.
func _affine_cmd_end() -> void:
	_affine_anim_ended = true
	_affine_index -= 1
	_apply_affine_relative({})


# `ApplyAffineAnimFrame` (`sprite.c:1345`).
#
# ⚠️ **`duration == 0` IS AN ABSOLUTE SET, NOT A ZERO-LENGTH FRAME.** Source
# branches on it: a nonzero duration decrements and applies the values as a
# RELATIVE delta, a zero duration assigns them outright and then pushes the
# matrix with a dummy zero delta. Reading it as "skip this frame" is the
# plausible misreading and drops every sequence's opening pose —
# `sAffineAnim_SpiderWeb` would expand from full size instead of from nothing.
#
# ⚠️ **AND THE DELAY IS THE DECREMENTED DURATION.** Source decrements its local
# copy before `delayCounter = frameCmd.duration`, so a duration of 3 holds for
# 2 further ticks, not 3. The command dict is shared extracted data and is never
# mutated here.
func _apply_affine_frame(d: Dictionary) -> void:
	var dur := int(d.get("duration", 0))
	if dur != 0:
		dur -= 1
		_apply_affine_relative(d)
	else:
		_apply_affine_absolute(d)
		_apply_affine_relative({})
	_affine_delay = dur


# `ApplyAffineAnimFrameAbsolute` (`sprite.c:1299`). ⚠️ The rotation is shifted
# left 8 here TOO — the shift is not exclusive to the relative path, and reading
# it as raw makes every absolute pose 256x under-rotated.
func _apply_affine_absolute(d: Dictionary) -> void:
	_affine_x = _affine_s16(int(d.get("xscale", 0)))
	_affine_y = _affine_s16(int(d.get("yscale", 0)))
	_affine_rot = (_affine_s16(int(d.get("rot", 0))) << AFFINE_ROT_SHIFT) & 0xFFFF


# `ApplyAffineAnimFrameRelativeAndUpdateMatrix` (`sprite.c:1327`). An empty dict
# is source's own `dummyFrameCmd = {0}` — accumulate nothing, push the matrix.
#
# ⚠️ **THE `& ~0xFF` IS A REAL QUANTISATION AND IS KEPT.** It costs the low 8
# bits of the accumulated rotation, i.e. rotation resolves to 256ths of a turn.
# It is inert against any single `rot << 8` on its own and only bites once a
# carry crosses into the low byte, which is exactly the case a "tidier" port
# would drop without noticing.
func _apply_affine_relative(d: Dictionary) -> void:
	_affine_x = _affine_wrap_s16(_affine_x + _affine_s16(int(d.get("xscale", 0))))
	_affine_y = _affine_wrap_s16(_affine_y + _affine_s16(int(d.get("yscale", 0))))
	var delta := _affine_s16(int(d.get("rot", 0))) << AFFINE_ROT_SHIFT
	_affine_rot = ((_affine_rot + delta) & 0xFFFF) & ~0xFF
	_push_affine_matrix()


func _capture_affine_base() -> void:
	if _affine_base_captured:
		return
	_affine_base_captured = true
	_affine_base_scale = scale
	_affine_base_rotation = rotation


func _push_affine_matrix() -> void:
	_capture_affine_base()
	var vx := maxf(AFFINE_MIN_VISUAL_SCALE,
			float(_affine_x) / float(AFFINE_IDENTITY))
	var vy := maxf(AFFINE_MIN_VISUAL_SCALE,
			float(_affine_y) / float(AFFINE_IDENTITY))
	scale = Vector2(_affine_base_scale.x * vx, _affine_base_scale.y * vy)
	rotation = _affine_base_rotation \
			+ float(_affine_rot) / AFFINE_ROT_UNITS_PER_TURN * TAU


# The extractor emits a `.4byte`-sourced field verbatim, so a negative literal
# arrives as its unsigned 16-bit spelling (-5 as 65531) or as -5, depending on
# how the C wrote it. Both mean the same s16.
static func _affine_s16(v: int) -> int:
	return v - 65536 if v > 32767 else v


# `sAffineAnimStates[].xScale` is an s16 and genuinely wraps on hardware.
static func _affine_wrap_s16(v: int) -> int:
	return _affine_s16(v & 0xFFFF)


# A command from the active sequence, or null when the index is off either end.
func _cmd_at(index: int, anim_num: int) -> Variant:
	if index < 0 or anim_num < 0 or anim_num >= _affine_seqs.size():
		return null
	var seq: Array = _affine_seqs[anim_num]
	if index >= seq.size():
		return null
	return seq[index]


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
