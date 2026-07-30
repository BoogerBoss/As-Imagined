class_name AnimBehaviors
extends RefCounted

# [M36C] The core behavior batch — the first real port of the reference's
# animation C into Godot. Scope of record: docs/m26_f1_recon.md.
#
# Chosen by measurement, not guesswork: M36B's coverage report ranked every
# unported behavior by how many moves it blocks, and this file implements the
# head of that distribution — AnimTask_ShakeMon (436 moves), AnimHitSplatBasic
# (386), AnimTask_ShakeMon2 (368) and the helpers those three reach.
#
# Fidelity notes that apply throughout:
#
# - TIMING IS FRAME-EXACT. Every duration here is the reference's own frame
#   count at 60fps (the M36 acceptance bar). Where upstream runs its callback
#   once on the creation frame and then once per frame after, so does the port:
#   the behavior does its frame-0 work inline and registers a stepper for the
#   rest.
# - OFFSETS ARE GBA PIXELS, SCALED. Script arguments are pixels on a 240x160
#   canvas; `stage.pixel_scale()` converts to this project's much larger
#   stage. Without it every effect would huddle invisibly at a sprite's centre.
# - X OFFSETS ARE DIRECTION-MIRRORED. Upstream `SetAnimSpriteInitialXOffset`
#   makes a positive x mean "toward the target" regardless of which side is
#   attacking; `stage.facing_sign()` is that rule.
# - MON OFFSETS ARE ADDITIVE AND RESTORED. Shakes write an offset on top of a
#   battler's real position and put it back at the end, exactly as upstream
#   writes and clears `sprite->x2/y2`. They never touch the base position, so
#   a shake interrupted by the VM's frame ceiling cannot leave a mon adrift.

# Tracks the temporary offset a shake applies to a battler sprite, so it can
# be restored precisely rather than by assuming the sprite started at zero.
#
# Convention matches the rest of the project: the battle screen's own
# species-entry animation also drives `sprite.position = base + offset` from
# its per-frame loop (battle_screen_shared.gd's back-anim runner). If a move
# animation ever overlapped a still-running entry animation the two would
# each rewrite position every frame and the mon would jitter -- but only
# while they overlap, because both restore from their own recorded base, so
# neither can corrupt the sprite's real position. In practice entry
# animations finish before a turn's moves execute; this is recorded as a
# known interaction rather than guarded against, since guarding would mean
# one system reaching into the other.
class MonOffset:
	const META_BASE := "_anim_mon_base"
	var node: Control
	var base: Vector2
	func _init(target: Control) -> void:
		node = target
		if target == null:
			base = Vector2.ZERO
			return
		# The FIRST behavior to displace a battler records its true position
		# on the node. Later behaviors reuse it, so a shake layered on a
		# lunge still restores to the real spot rather than to wherever the
		# previous effect happened to leave the sprite.
		if target.has_meta(META_BASE):
			base = target.get_meta(META_BASE)
		else:
			base = target.position
			target.set_meta(META_BASE, base)
	func apply(offset: Vector2) -> void:
		if node != null and is_instance_valid(node):
			node.position = base + offset
	func restore() -> void:
		apply(Vector2.ZERO)


static func register_all(registry: AnimBehaviorRegistry) -> void:
	registry.register_many({
		# — the three top blockers —
		"AnimTask_ShakeMon": _shake_mon,
		"AnimTask_ShakeMon2": _shake_mon2,
		"AnimTask_ShakeMonInPlace": _shake_mon_in_place,
		# — the hitsplat family —
		"AnimHitSplatBasic": _hit_splat_basic,
		"AnimHitSplatHandleInvert": _hit_splat_handle_invert,
		"AnimHitSplatPersistent": _hit_splat_persistent,
		# — travel —
		"AnimToTargetInSinWave": _to_target_in_sin_wave,
		"TranslateAnimSpriteToTargetMonLocation": _translate_to_target,
		"AnimSpriteOnMonPos": _sprite_on_mon_pos,
		# — invisible controller sprites —
		"DoHorizontalLunge": _horizontal_lunge,
		"DoVerticalDip": _vertical_dip,
		"SlideMonToOffset": _slide_mon_to_offset,
		"SlideMonToOriginalPos": _slide_mon_to_original_pos,
		# — palette blends —
		"AnimSimplePaletteBlend": _simple_palette_blend,
		"AnimTask_BlendBattleAnimPal": _blend_battle_anim_pal,
		"AnimTask_BlendColorCycle": _blend_color_cycle,
		"AnimTask_BlendColorCycleExclude": _blend_color_cycle,
		"AnimTask_BlendParticle": _blend_particle,
		"AnimTask_StartSinAnimTimer": _start_sin_anim_timer,
		# — [M36D] particle families —
		"AnimMovePowderParticle": _move_powder_particle,
		"AnimSporeParticle": _spore_particle,
		"AnimParticleInVortex": _particle_in_vortex,
		"AnimCuttingSlice": _cutting_slice,
		"AnimAirCutterSlice": _air_cutter_slice,
		"AnimBite": _bite,
		"AnimWhipHit": _whip_hit,
		"AnimEmberFlare": _ember_flare,
		"AnimBurnFlame": _burn_flame,
		"AnimTravelDiagonally": _travel_diagonally,
		"AnimFireSpread": _fire_spread,
		"AnimBasicFistOrFoot": _basic_fist_or_foot,
		"AnimEndureEnergy": _endure_energy,
		"AnimAbsorptionOrb": _absorption_orb,
		"AnimBubbleEffect": _bubble_effect,
		"AnimTranslateLinearSingleSineWave": _linear_single_sine_wave,
		# — [M36D] mon tasks —
		"AnimTask_ScaleMonAndRestore": _scale_mon_and_restore,
		"AnimTask_SwayMon": _sway_mon,
		"AnimTask_TranslateMonElliptical": _translate_mon_elliptical,
		"AnimTask_TranslateMonEllipticalRespectSide":
				_translate_mon_elliptical_respect_side,
		"AnimTask_ShakeAndSinkMon": _shake_and_sink_mon,
		# — [M36D batch 2] projectiles —
		"AnimShadowBall": _shadow_ball,
		"AnimWaterBubbleProjectile": _water_bubble_projectile,
		"AnimBoneHitProjectile": _bone_hit_projectile,
		"AnimTranslateStinger": _translate_stinger,
		"AnimMissileArc": _missile_arc,
		# — [M36D batch 2] seeds, leaves, rocks —
		"AnimLeechSeed": _leech_seed,
		"AnimRazorLeafParticle": _razor_leaf_particle,
		"AnimFallingRock": _falling_rock,
		"AnimFrenzyPlantRoot": _frenzy_plant_root,
		# — [M36D batch 2] mon visuals —
		"AnimTask_TraceMonBlended": _trace_mon_blended,
		"AnimFlyUpTarget": _fly_up_target,
		"AnimJumpKick": _jump_kick,
		"AnimSlideHandOrFootToTarget": _slide_hand_or_foot_to_target,
		"AnimDizzyPunchDuck": _dizzy_punch_duck,
		"AnimClawSlash": _claw_slash,
		"SpriteCB_SpriteOnMonForDuration": _sprite_on_mon_for_duration,
		# — [M36D batch 2] palette / screen —
		"AnimComplexPaletteBlend": _complex_palette_blend,
		"AnimTask_SetGrayscaleOrOriginalPal": _set_grayscale_or_original,
		"AnimDefensiveWall": _defensive_wall,
		# — [M36D batch 2] sound tasks (audio deferred to M36-S) —
		"SoundTask_PlaySE1WithPanning": _sound_immediate,
		"SoundTask_PlaySE2WithPanning": _sound_immediate,
		"SoundTask_PlayCryHighPitch": _sound_immediate,
		"SoundTask_PlayDoubleCry": _sound_cry_wait,
		"SoundTask_PlayNormalCry": _sound_cry_wait,
		"SoundTask_PlayCryWithEcho": _sound_cry_wait,
		"SoundTask_PlayDynamaxCry": _sound_cry_wait,
		"SoundTask_WaitForCry": _sound_cry_wait,
		"SoundTask_AdjustPanningVar": _sound_immediate,
		# — [M36D batch 3] mon tasks —
		"AnimTask_IsTargetPlayerSide": _is_target_player_side,
		"AnimTask_HorizontalShake": _horizontal_shake,
		"AnimTask_WindUpLunge": _wind_up_lunge,
		"AnimTask_RotateMonSpriteToSide": _rotate_mon_to_side,
		"AnimTask_RotateMonToSideAndRestore": _rotate_mon_to_side_restore,
		"AnimTask_Teleport": _teleport,
		"AnimTask_DynamaxGrowth": _dynamax_growth,
		"AnimTask_BlendMonInAndOut": _blend_mon_in_and_out,
		"AnimShakeMonOrBattlePlatforms": _shake_mon_or_platforms,
		# — [M36D batch 3] particles —
		"AnimWallSparkle": _wall_sparkle,
		"AnimBulletSeed": _bullet_seed,
		"AnimSunlight": _sunlight,
		"AnimTask_CreateRaindrops": _create_raindrops,
		"AnimDirtScatter": _dirt_scatter,
		"AnimRoarNoiseLine": _roar_noise_line,
		"AnimRockFragment": _rock_fragment,
		"AnimMoveTwisterParticle": _move_twister_particle,
		"AnimFireSpiralOutward": _fire_spiral_outward,
		"AnimProtect": _protect,
		"AnimRevengeScratch": _revenge_scratch,
		"AnimAssistPawprint": _assist_pawprint,
		"InitSwirlingFogAnim": _swirling_fog,
		# — single-frame query tasks —
		"AnimTask_IsDoubleBattle": _is_double_battle,
		"AnimTask_IsContest": _is_contest,
		"AnimTask_GetAttackerSide": _get_attacker_side,
		"AnimTask_GetTargetSide": _get_target_side,
		"AnimTask_GetTargetIsAttackerPartner": _get_target_is_attacker_partner,
	})


# ── Shakes ────────────────────────────────────────────────────────────────
# args: 0 battler, 1 x offset, 2 y offset, 3 shake count, 4 frame delay

# AnimTask_ShakeMon (battle_anim_mon_movement.c:98). Toggles between the
# offset and ZERO -- not +/- -- so the mon rests at its true position on
# alternate steps. Total ~= shakes * (delay + 1) frames.
static func _shake_mon(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	_shake_common(vm, false)


# AnimTask_ShakeMon2 (:161). Identical bookkeeping, but oscillates +offset /
# -offset, so the amplitude is double ShakeMon's and the mon never rests at
# its true position mid-shake.
static func _shake_mon2(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	_shake_common(vm, true)


static func _shake_common(vm: AnimScriptVM, bidirectional: bool) -> void:
	var node := _battler_node(vm, vm.args[0])
	if node == null:
		return
	var scale := _scale(vm)
	var delta := Vector2(vm.args[1], vm.args[2]) * scale
	var shakes: int = maxi(1, vm.args[3])
	var delay: int = maxi(0, vm.args[4])
	var mon := MonOffset.new(node)

	var st := {"left": shakes, "timer": delay, "on": false}
	mon.apply(delta)  # the reference applies the offset during setup
	st["on"] = true

	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		if int(st["timer"]) > 0:
			st["timer"] = int(st["timer"]) - 1
			return false
		st["timer"] = delay
		st["on"] = not bool(st["on"])
		if bool(st["on"]):
			mon.apply(delta)
		else:
			mon.apply(-delta if bidirectional else Vector2.ZERO)
		st["left"] = int(st["left"]) - 1
		if int(st["left"]) <= 0:
			mon.restore()  # upstream forces x2/y2 back to 0 on the last step
			return true
		return false)


# AnimTask_ShakeMonInPlace (:258). Hops by +/-(2 * offset) about the shifted
# position and undoes its own displacement with a final half-step, rather
# than forcing the offset to zero. Ported as the same arithmetic so a shake
# layered on an existing offset behaves identically.
static func _shake_mon_in_place(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var node := _battler_node(vm, vm.args[0])
	if node == null:
		return
	var scale := _scale(vm)
	var half := Vector2(vm.args[1], vm.args[2]) * scale
	var delta := half * 2.0
	var shakes: int = maxi(1, vm.args[3])
	var delay: int = maxi(0, vm.args[4])
	var mon := MonOffset.new(node)

	var st := {"i": 0, "timer": 0, "offset": half}
	mon.apply(half)

	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		if int(st["timer"]) > 0:
			st["timer"] = int(st["timer"]) - 1
			return false
		st["timer"] = delay
		var cur: Vector2 = st["offset"]
		cur += delta if (int(st["i"]) & 1) == 1 else -delta
		st["i"] = int(st["i"]) + 1
		if int(st["i"]) >= shakes:
			cur += half if (int(st["i"]) & 1) == 1 else -half
			mon.apply(cur)
			return true
		st["offset"] = cur
		mon.apply(cur)
		return false)


# ── Hit splats ────────────────────────────────────────────────────────────
# args: 0 x, 1 y, 2 relative_to (0 = attacker), 3 affine variant

# AnimHitSplatBasic (battle_anim_normal.c:1095). Positioned relative to the
# chosen battler, scaled by one of four presets, and destroyed when that
# affine animation ends -- roughly 9-10 frames. It does NOT move.
static func _hit_splat_basic(vm: AnimScriptVM, ctx: Dictionary) -> void:
	_spawn_hit_splat(vm, ctx, vm.args[0], vm.args[1], vm.args[2], vm.args[3], 0)


# AnimHitSplatHandleInvert (:1127): identical, but flips the Y offset when
# the attacker is on the opponent's side.
static func _hit_splat_handle_invert(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var y: int = vm.args[1]
	if vm.stage != null and vm.stage.has_method("attacker_is_player_side") \
			and not vm.stage.attacker_is_player_side():
		y = -y
	_spawn_hit_splat(vm, ctx, vm.args[0], y, vm.args[2], vm.args[3], 0)


# AnimHitSplatPersistent (:1110): same, plus an explicit duration in args[4]
# that outlives the affine animation.
static func _hit_splat_persistent(vm: AnimScriptVM, ctx: Dictionary) -> void:
	_spawn_hit_splat(vm, ctx, vm.args[0], vm.args[1], vm.args[2], vm.args[3],
			maxi(0, vm.args[4]))


# The four gAffineAnims_HitSplat variants are static size presets held for 8
# frames. The affine scale parameter is an INVERSE scale (0x100 = 1.0, and
# smaller means bigger), which is why these are reciprocals.
const _HIT_SPLAT_SCALES := [1.0, 256.0 / 216.0, 256.0 / 176.0, 2.0]
const _HIT_SPLAT_FRAMES := 9


static func _spawn_hit_splat(vm: AnimScriptVM, ctx: Dictionary, x: int, y: int,
		relative_to: int, variant: int, persist_frames: int) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	# relative_to is compared against ANIM_ATTACKER (0); anything else means
	# the target -- the same test upstream makes.
	var battler: int = AnimStage.ANIM_ATTACKER if relative_to == 0 \
			else AnimStage.ANIM_TARGET
	node.centre = _positioned_centre(vm, battler, x, y, scale)
	node.scale = Vector2.ONE * scale * _HIT_SPLAT_SCALES[clampi(variant, 0,
			_HIT_SPLAT_SCALES.size() - 1)]
	node.pivot_offset = node.size * 0.5

	var lifetime: int = persist_frames if persist_frames > 0 \
			else _HIT_SPLAT_FRAMES
	var st := {"t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) >= lifetime:
			node.finish()
			return true
		return false)


# ── Travel ────────────────────────────────────────────────────────────────

# AnimToTargetInSinWave (battle_anim_water.c:827) -- Flamethrower's flames.
# Linear attacker->target over a hard-coded 30 frames, with a sine offset
# added on top of the interpolated Y. The phase sweeps 0..127 then resets and
# flips the amplitude's sign, which is what makes a beam's particles arc
# alternately above and below the line.
const _SIN_WAVE_FRAMES := 30

static func _to_target_in_sin_wave(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var start := _positioned_centre(vm, AnimStage.ANIM_ATTACKER, vm.args[0],
			vm.args[1], scale)
	var finish_pos := _battler_centre(vm, AnimStage.ANIM_TARGET)
	node.centre = start

	var amplitude: float = float(vm.args[3]) * scale
	var phase_seed: int = vm.args[7]
	# Upstream packs a >127 seed as "start half a cycle in, inverted".
	var phase: float = float(phase_seed - 127) if phase_seed > 127 \
			else float(phase_seed)
	if phase_seed > 127:
		amplitude = -amplitude
	var phase_step := 53760.0 / 256.0 / float(_SIN_WAVE_FRAMES)

	var st := {"t": 0, "phase": phase, "amp": amplitude}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var t: int = int(st["t"])
		if t >= _SIN_WAVE_FRAMES:
			node.finish()
			return true
		var f := float(t + 1) / float(_SIN_WAVE_FRAMES)
		var pos := start.lerp(finish_pos, f)
		var ph: float = st["phase"]
		# Sin(index, amplitude) over a 256-step table = sin(2*PI*index/256).
		pos.y += sin(TAU * ph / 256.0) * float(st["amp"])
		node.centre = pos
		ph += phase_step
		if ph > 127.0:
			ph = 0.0
			st["amp"] = -float(st["amp"])
		st["phase"] = ph
		st["t"] = t + 1
		return false)


# TranslateAnimSpriteToTargetMonLocation (battle_anim_mons.c:1498).
# args: 0/1 start offsets, 2/3 target offsets, 4 duration, 5 coord flags.
static func _translate_to_target(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var start := _positioned_centre(vm, AnimStage.ANIM_ATTACKER, vm.args[0],
			vm.args[1], scale)
	# args[2] is side-mirrored (so positive means "past the target in the
	# attack direction"); args[3] is not.
	var sign := _facing(vm)
	var finish_pos := _battler_centre(vm, AnimStage.ANIM_TARGET) \
			+ Vector2(float(vm.args[2]) * sign, float(vm.args[3])) * scale
	var duration: int = maxi(1, vm.args[4])
	node.centre = start
	_linear_travel(vm, node, start, finish_pos, duration)


# AnimSpriteOnMonPos (battle_anim_mons.c:1451): positions on frame 0 and
# lives until its own frame animation ends.
static func _sprite_on_mon_pos(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var battler: int = AnimStage.ANIM_ATTACKER if vm.args[2] == 0 \
			else AnimStage.ANIM_TARGET
	node.centre = _positioned_centre(vm, battler, vm.args[0], vm.args[1], scale)
	var st := {"t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) >= 16:
			node.finish()
			return true
		return false)


static func _linear_travel(vm: AnimScriptVM, node: AnimSprite, start: Vector2,
		finish_pos: Vector2, duration: int) -> void:
	var st := {"t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var t: int = int(st["t"]) + 1
		st["t"] = t
		if t >= duration:
			node.finish()
			return true
		node.centre = start.lerp(finish_pos, float(t) / float(duration))
		return false)


# ── Invisible controller sprites ──────────────────────────────────────────

# DoHorizontalLunge (battle_anim_mon_movement.c:439). args: 0 frames per leg,
# 1 px per frame. Always drives the ATTACKER, always out-and-back, and the
# per-frame delta is side-mirrored so a positive value lunges forward for
# either side. Net displacement is exactly zero by symmetry.
static func _horizontal_lunge(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var node := _battler_node(vm, AnimStage.ANIM_ATTACKER)
	if node == null:
		return
	var scale := _scale(vm)
	var per_frame := float(vm.args[1]) * scale * _facing(vm)
	var leg: int = maxi(1, vm.args[0])
	var mon := MonOffset.new(node)
	var st := {"t": 0, "x": 0.0, "back": false}

	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		var t: int = int(st["t"])
		if t < leg:
			st["x"] = float(st["x"]) + (per_frame if not bool(st["back"])
					else -per_frame)
			mon.apply(Vector2(float(st["x"]), 0.0))
			st["t"] = t + 1
			return false
		if not bool(st["back"]):
			st["back"] = true
			st["t"] = 0
			return false
		mon.restore()
		return true)


# DoVerticalDip (:468). args: 0 frames per leg, 1 px per frame, 2 battler.
# Unlike the lunge it takes an explicit battler and is NOT side-mirrored.
static func _vertical_dip(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var node := _battler_node(vm, vm.args[2])
	if node == null:
		return
	var scale := _scale(vm)
	var per_frame := float(vm.args[1]) * scale
	var leg: int = maxi(1, vm.args[0])
	var mon := MonOffset.new(node)
	var st := {"t": 0, "y": 0.0, "back": false}

	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		var t: int = int(st["t"])
		if t < leg:
			st["y"] = float(st["y"]) + (per_frame if not bool(st["back"])
					else -per_frame)
			mon.apply(Vector2(0.0, float(st["y"])))
			st["t"] = t + 1
			return false
		if not bool(st["back"]):
			st["back"] = true
			st["t"] = 0
			return false
		mon.restore()
		return true)


# SlideMonToOffset (:593). args: 0 battler(0=atk,1=tgt), 1 x, 2 y,
# 3 mirror-y flag, 4 duration. Slides to the offset and LEAVES IT THERE --
# the script is expected to slide back explicitly.
static func _slide_mon_to_offset(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var battler: int = AnimStage.ANIM_ATTACKER if vm.args[0] == 0 \
			else AnimStage.ANIM_TARGET
	var node := _battler_node(vm, battler)
	if node == null:
		return
	var scale := _scale(vm)
	var sign := _facing(vm)
	var dx := float(vm.args[1]) * scale * sign
	var dy := float(vm.args[2]) * scale
	if vm.args[3] == 1 and sign < 0.0:
		dy = -dy
	var duration: int = maxi(1, vm.args[4])
	var mon := MonOffset.new(node)
	var st := {"t": 0}

	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		var t: int = int(st["t"]) + 1
		st["t"] = t
		var f := minf(1.0, float(t) / float(duration))
		mon.apply(Vector2(dx, dy) * f)
		return t >= duration)


# SlideMonToOriginalPos (:496). args: 0 battler, 1 axes (0 both, 1 x, 2 y),
# 2 duration. Returns a displaced mon to its true position and snaps the
# affected axes to exactly 0 on the final frame.
static func _slide_mon_to_original_pos(vm: AnimScriptVM,
		_ctx: Dictionary) -> void:
	var battler: int = AnimStage.ANIM_TARGET if vm.args[0] == 1 \
			else AnimStage.ANIM_ATTACKER
	var node := _battler_node(vm, battler)
	if node == null:
		return
	var duration: int = maxi(1, vm.args[2])
	var axes: int = vm.args[1]
	var start := node.position
	# Restores to the battler's TRUE position, which MonOffset recorded on the
	# node when the first behavior displaced it. Without that record this
	# would interpolate from the current position to itself -- a silent no-op,
	# which is exactly the bug a mon left mid-lunge would show.
	var origin: Vector2 = node.get_meta(MonOffset.META_BASE, start)
	var st := {"t": 0}

	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		var t: int = int(st["t"]) + 1
		st["t"] = t
		var f := minf(1.0, float(t) / float(duration))
		var pos := start.lerp(origin, f)
		if axes == 1:
			pos.y = start.y
		elif axes == 2:
			pos.x = start.x
		node.position = pos
		return t >= duration)


# ── Palette blends ────────────────────────────────────────────────────────

# The GBA blends whole 16-colour palettes toward a colour by a coefficient
# 0..16. Godot has no palette indirection at runtime, so the equivalent is
# modulating the affected NODES toward that colour by coeff/16 -- visually
# the same for the selectors these scripts actually use (battlers and
# particles), and a no-op for the BG selector, which M36E owns.
const _F_PAL_BG := 1
const _F_PAL_ATTACKER := 2
const _F_PAL_TARGET := 4
const _F_PAL_ATK_PARTNER := 8
const _F_PAL_DEF_PARTNER := 16


# AnimSimplePaletteBlend (battle_anim_normal.c:351).
# args: 0 selector, 1 delay, 2 start coeff, 3 target coeff, 4 RGB colour.
static func _simple_palette_blend(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	_run_blend(vm, vm.args[0], vm.args[1], vm.args[2], vm.args[3], vm.args[4])


# AnimTask_BlendBattleAnimPal (battle_anim_utility_funcs.c:44) -- same
# arguments, same stepping; the difference upstream is which palette mask it
# builds, which collapses to the same node set here.
static func _blend_battle_anim_pal(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	_run_blend(vm, vm.args[0], vm.args[1], vm.args[2], vm.args[3], vm.args[4])


static func _run_blend(vm: AnimScriptVM, selector: int, delay: int,
		start_coeff: int, target_coeff: int, rgb15: int) -> void:
	# BG-only blends (F_PAL_BG) have no node equivalent until M36E builds the
	# background layer; the stepper still runs so the script's timing holds.
	var nodes := _blend_nodes(vm, selector)

	var colour := _rgb15_to_color(rgb15)
	var bases: Array[Color] = []
	for n in nodes:
		bases.append(n.modulate)

	var st := {"coeff": start_coeff, "timer": 0}
	var step_delay: int = maxi(0, delay)

	vm.add_stepper(func() -> bool:
		if int(st["timer"]) < step_delay:
			st["timer"] = int(st["timer"]) + 1
			return false
		st["timer"] = 0
		var c: int = int(st["coeff"])
		for i in range(nodes.size()):
			var n: Control = nodes[i]
			if is_instance_valid(n):
				n.modulate = (bases[i] as Color).lerp(colour,
						clampf(c / 16.0, 0.0, 1.0))
		if c < target_coeff:
			st["coeff"] = c + 1
			return false
		if c > target_coeff:
			st["coeff"] = c - 1
			return false
		return true)


# AnimTask_BlendColorCycle -- args: 0 selector, 1 delay, 2 num_blends,
# 3 initial_blend_y, 4 target_blend_y, 5 colour. Ramps the blend up to the
# target and back down, num_blends times, so a mon pulses a colour rather
# than staying tinted. Ported as repeated runs of the same ramp the simple
# blend uses; the reference likewise reuses its blend stepper.
static func _blend_color_cycle(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var selector: int = vm.args[0]
	var delay: int = maxi(0, vm.args[1])
	var cycles: int = maxi(1, vm.args[2])
	var low: int = vm.args[3]
	var high: int = vm.args[4]
	var colour := _rgb15_to_color(vm.args[5])
	var nodes := _blend_nodes(vm, selector)
	var bases: Array[Color] = []
	for n in nodes:
		bases.append(n.modulate)

	# One "blend" is a full up-and-down sweep; the coefficient walks 1 step
	# every (delay + 1) frames, exactly as the reference's stepper does.
	var st := {"coeff": low, "dir": 1, "left": cycles, "timer": 0}
	vm.add_stepper(func() -> bool:
		if int(st["timer"]) < delay:
			st["timer"] = int(st["timer"]) + 1
			return false
		st["timer"] = 0
		var c: int = int(st["coeff"])
		for i in range(nodes.size()):
			var n: Control = nodes[i]
			if is_instance_valid(n):
				n.modulate = (bases[i] as Color).lerp(colour,
						clampf(c / 16.0, 0.0, 1.0))
		c += int(st["dir"])
		if c >= high and int(st["dir"]) > 0:
			c = high
			st["dir"] = -1
		elif c <= low and int(st["dir"]) < 0:
			c = low
			st["dir"] = 1
			st["left"] = int(st["left"]) - 1
			if int(st["left"]) <= 0:
				for i in range(nodes.size()):
					var n2: Control = nodes[i]
					if is_instance_valid(n2):
						n2.modulate = bases[i]
				return true
		st["coeff"] = c
		return false)


# AnimTask_BlendParticle -- args: 0 ANIM_TAG, 1 delay, 2 initial, 3 target,
# 4 colour. Upstream this tints one PARTICLE palette rather than a battler.
# Here it tints the live anim sprites drawn from that tag, which is the same
# visible result without a palette indirection Godot does not have.
static func _blend_particle(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var colour := _rgb15_to_color(vm.args[4])
	var coeff: int = clampi(vm.args[3], 0, 16)
	var layer: Control = null
	if vm.stage != null and vm.stage.has_method("layer"):
		layer = vm.stage.layer()
	if layer != null:
		for child in layer.get_children():
			if child is AnimSprite:
				var sp := child as AnimSprite
				sp.modulate = sp.modulate.lerp(colour, coeff / 16.0)
	# Single-frame: the tint applies and the task is done, like the
	# reference's own immediate-blend variant.


# AnimTask_StartSinAnimTimer -- starts a global sine-phase counter the beam
# particles read. Our AnimToTargetInSinWave carries its own phase (each
# sprite advances independently, which is what the per-sprite data slots do
# upstream too), so this is a no-op that completes immediately rather than a
# shared timer nothing would consume.
static func _start_sin_anim_timer(_vm: AnimScriptVM, _ctx: Dictionary) -> void:
	pass


static func _blend_nodes(vm: AnimScriptVM, selector: int) -> Array[Control]:
	var nodes: Array[Control] = []
	for pair in [[_F_PAL_ATTACKER, AnimStage.ANIM_ATTACKER],
			[_F_PAL_TARGET, AnimStage.ANIM_TARGET],
			[_F_PAL_ATK_PARTNER, AnimStage.ANIM_ATK_PARTNER],
			[_F_PAL_DEF_PARTNER, AnimStage.ANIM_DEF_PARTNER]]:
		if (selector & int(pair[0])) != 0:
			var n := _battler_node(vm, int(pair[1]))
			if n != null:
				nodes.append(n)
	return nodes


# GBA 15-bit BGR -> Color.
static func _rgb15_to_color(rgb15: int) -> Color:
	var r := float(rgb15 & 31) / 31.0
	var g := float((rgb15 >> 5) & 31) / 31.0
	var b := float((rgb15 >> 10) & 31) / 31.0
	return Color(r, g, b, 1.0)


# ── Query tasks (single frame, write args[7]) ─────────────────────────────

static func _is_double_battle(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var doubles: bool = vm.stage != null and vm.stage.has_method("mon_for") \
			and vm.stage.mon_for(AnimStage.ANIM_DEF_PARTNER) != null
	vm.args[AnimScriptVM.ARG_RET] = 1 if doubles else 0


static func _is_contest(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	vm.args[AnimScriptVM.ARG_RET] = 0  # contests are out of scope


static func _get_attacker_side(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	# B_SIDE_PLAYER = 0, B_SIDE_OPPONENT = 1.
	vm.args[AnimScriptVM.ARG_RET] = 0 if _is_player_side(vm) else 1


static func _get_target_side(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	vm.args[AnimScriptVM.ARG_RET] = 1 if _is_player_side(vm) else 0


static func _get_target_is_attacker_partner(vm: AnimScriptVM,
		_ctx: Dictionary) -> void:
	var same: bool = vm.stage != null and vm.stage.has_method("mon_for") \
			and vm.stage.mon_for(AnimStage.ANIM_TARGET) != null \
			and vm.stage.mon_for(AnimStage.ANIM_TARGET) \
				== vm.stage.mon_for(AnimStage.ANIM_ATK_PARTNER)
	vm.args[AnimScriptVM.ARG_RET] = 1 if same else 0


# ── Shared helpers ────────────────────────────────────────────────────────

static func _scale(vm: AnimScriptVM) -> float:
	if vm.stage != null and vm.stage.has_method("pixel_scale"):
		return vm.stage.pixel_scale()
	return 1.0


static func _facing(vm: AnimScriptVM) -> float:
	if vm.stage != null and vm.stage.has_method("facing_sign"):
		return vm.stage.facing_sign()
	return 1.0


static func _is_player_side(vm: AnimScriptVM) -> bool:
	if vm.stage != null and vm.stage.has_method("attacker_is_player_side"):
		return vm.stage.attacker_is_player_side()
	return true


static func _battler_node(vm: AnimScriptVM, anim_battler: int) -> Control:
	if vm.stage == null or not vm.stage.has_method("sprite_for"):
		return null
	return vm.stage.sprite_for(anim_battler) as Control


static func _battler_centre(vm: AnimScriptVM, anim_battler: int) -> Vector2:
	if vm.stage == null or not vm.stage.has_method("center_of"):
		return Vector2.ZERO
	return vm.stage.center_of(anim_battler)


# The reference's InitSpritePosTo* pair: start from a battler's centre, add a
# direction-mirrored X offset and a raw Y offset.
static func _positioned_centre(vm: AnimScriptVM, anim_battler: int, x: int,
		y: int, scale: float) -> Vector2:
	return _battler_centre(vm, anim_battler) \
			+ Vector2(float(x) * _facing(vm), float(y)) * scale


# Builds the sprite a template describes: its tag's sheet, its OAM frame
# size, its frame sequence and the script's current blend context.
static func _make_sprite(vm: AnimScriptVM, ctx: Dictionary) -> AnimSprite:
	var tmpl_name := str(ctx.get("template", ""))
	var tmpl: Dictionary = ctx.get("template_data", {})
	if tmpl.is_empty():
		tmpl = AnimData.template(tmpl_name)
	var tag := str((tmpl.get("tile_tag", {}) as Dictionary).get("name", ""))
	if tag == "":
		return null
	var oam: Dictionary = tmpl.get("oam", {})
	var node := AnimSprite.create(vm, tag, int(oam.get("width", 32)),
			int(oam.get("height", 32)))
	var layer: Control = null
	if vm.stage != null and vm.stage.has_method("layer"):
		layer = vm.stage.layer()
	if layer == null:
		node.queue_free()
		return null
	layer.add_child(node)
	# Sprites render at the same scale their OFFSETS are scaled by. Without
	# this the two disagree: a 32x32 GBA particle would draw 32 px wide on a
	# 1024-wide stage (a speck) while being flung 4x further than it should,
	# so a "beam" became a scatter of dots. Scaling both keeps the effect the
	# same fraction of the screen it occupies on hardware.
	node.scale = Vector2.ONE * _scale(vm)
	node.pivot_offset = node.size * 0.5
	var seqs := AnimData.anim_sequences_for(tmpl_name)
	if not seqs.is_empty():
		node.play_sequence(seqs[0])
	node.apply_blend(ctx.get("blend", {"eva": 16, "evb": 0}))
	return node


# ══ [M36D] Particle families ══════════════════════════════════════════════
#
# The GBA's Sin/Cos take a 0-255 index over a full circle, so every phase
# accumulator below is in the same units the C uses and converts once here.

const _SIN_STEPS := 256.0


static func _gba_sin(index: float, amplitude: float) -> float:
	return sin(TAU * index / _SIN_STEPS) * amplitude


static func _gba_cos(index: float, amplitude: float) -> float:
	return cos(TAU * index / _SIN_STEPS) * amplitude


# AnimMovePowderParticle (battle_anim_effects_1.c:3032) -- Sleep Powder,
# Stun Spore, Poison Powder. args: 0 x, 1 y, 2 duration, 3 y velocity (8.8),
# 4 wave amplitude, 5 wave speed.
#
# Note this one does NOT reposition to a battler: it drifts from wherever the
# script spawned it (the target's centre) using RAW offsets -- no direction
# mirroring -- which is why the powder clouds hang over the target rather
# than flying at it. The amplitude, however, IS side-flipped.
static func _move_powder_particle(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	node.centre = _battler_centre(vm, AnimStage.ANIM_TARGET) \
			+ Vector2(vm.args[0], vm.args[1]) * scale
	var duration: int = maxi(1, vm.args[2])
	var y_vel: float = float(vm.args[3]) / 256.0 * scale
	var amplitude: float = float(vm.args[4]) * scale
	if not _is_player_side(vm):
		amplitude = -amplitude
	var wave_speed: float = float(vm.args[5])

	var st := {"t": 0, "fall": 0.0, "phase": 0.0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		# y2 is written from the accumulator BEFORE it advances (a one-frame
		# lag that is in the original and visible as a beat of hang time).
		node.offset = Vector2(_gba_sin(float(st["phase"]), amplitude),
				float(st["fall"]))
		st["fall"] = float(st["fall"]) + y_vel
		st["phase"] = fmod(float(st["phase"]) + wave_speed, _SIN_STEPS)
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) >= duration:
			node.finish()
			return true
		return false)


# AnimSporeParticle (battle_anim_effects_1.c:3570). args: 0 x, 1 y,
# 2 initial sine index, 3 duration, 4 blend flag. Orbits the target on a
# flattened ellipse (radius 32, vertical squash -3) while drifting down,
# and passes BEHIND the mon on the far half of the orbit.
static func _spore_particle(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	node.centre = _positioned_centre(vm, AnimStage.ANIM_TARGET, vm.args[0],
			vm.args[1], scale)
	var duration: int = maxi(1, vm.args[3])
	var st := {"t": 0, "phase": float(vm.args[2]), "drift": 0.0}

	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var ph: float = st["phase"]
		st["drift"] = float(st["drift"]) + 24.0 / 256.0
		node.offset = Vector2(_gba_sin(ph, 32.0 * scale),
				_gba_cos(ph, -3.0 * scale) + float(st["drift"]) * scale)
		# The far half of the orbit draws behind the mon. Z-order is the
		# Godot equivalent of the priority swap upstream performs.
		node.z_index = 1 if ((int(ph) - 64) & 0xFF) < 0x80 else -1
		st["phase"] = fmod(ph + 2.0, _SIN_STEPS)
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) > duration:
			node.finish()
			return true
		return false)


# AnimParticleInVortex (battle_anim_rock.c:444). args: 0 x, 1 y,
# 2 y increment (8.8, upward), 3 duration, 4 sine increment, 5 radius,
# 6 anchor battler. Rises while circling -- the sand/rock vortex particle.
static func _particle_in_vortex(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var battler: int = vm.args[6] if vm.args[6] in [0, 1, 2, 3] \
			else AnimStage.ANIM_ATTACKER
	node.centre = _positioned_centre(vm, battler, vm.args[0], vm.args[1],
			scale)
	var duration: int = maxi(1, vm.args[3])
	var rise: float = float(vm.args[2]) / 256.0 * scale
	var sine_step: float = float(vm.args[4])
	var radius: float = float(vm.args[5]) * scale
	var st := {"t": 0, "y": 0.0, "phase": 0.0}

	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["y"] = float(st["y"]) + rise
		node.offset = Vector2(_gba_sin(float(st["phase"]), radius),
				-float(st["y"]))
		st["phase"] = fmod(float(st["phase"]) + sine_step, _SIN_STEPS)
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) > duration:
			node.finish()
			return true
		return false)


# AnimCuttingSlice (battle_anim_effects_1.c:5062). args: 0 x, 1 y,
# 2 direction (0 = right-to-left). A decelerating arc: constant acceleration
# applied to both axes for 20 frames, then a 4-frame hold. 24 frames total.
static func _cutting_slice(vm: AnimScriptVM, ctx: Dictionary) -> void:
	_spawn_slice(vm, ctx, AnimStage.ANIM_TARGET)


# AnimAirCutterSlice (:5090) shares the same step; its extra arg picks the
# anchor (target / partner / their midpoint), which in singles is the target.
static func _air_cutter_slice(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var anchor: int = AnimStage.ANIM_TARGET
	if vm.args[3] == 1:
		anchor = AnimStage.ANIM_DEF_PARTNER
	_spawn_slice(vm, ctx, anchor)


static func _spawn_slice(vm: AnimScriptVM, ctx: Dictionary,
		anchor: int) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var direction: int = vm.args[2]
	var base := _battler_centre(vm, anchor)
	if _is_player_side(vm):
		base.y += 8.0 * scale
	var x_off := float(vm.args[0]) * scale
	node.centre = base + Vector2(x_off if direction == 0 else -x_off,
			float(vm.args[1]) * scale)
	node.flip_h = direction != 0

	var vx: float = (-0x400 if direction == 0 else 0x400) / 256.0 * scale
	var vy: float = 0x400 / 256.0 * scale
	var accel: float = 0x18 / 256.0 * scale
	var st := {"t": 0, "x": 0.0, "y": 0.0, "vx": vx, "vy": vy}

	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var t: int = int(st["t"])
		if t < 20:
			st["x"] = float(st["x"]) + float(st["vx"])
			st["y"] = float(st["y"]) + float(st["vy"])
			st["vx"] = float(st["vx"]) + (accel if direction == 0 else -accel)
			st["vy"] = float(st["vy"]) - accel
			node.offset = Vector2(float(st["x"]), float(st["y"]))
		st["t"] = t + 1
		if t + 1 >= 24:
			node.finish()
			return true
		return false)


# AnimBite (battle_anim_dark.c:404) -- Bite, Crunch, Clamp. args: 0 x, 1 y,
# 2 affine anim, 3 x velocity (8.8), 4 y velocity, 5 half-duration. The fangs
# converge for half the duration then retreat, so total = 2 * arg5.
static func _bite(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	node.centre = _battler_centre(vm, AnimStage.ANIM_TARGET) \
			+ Vector2(vm.args[0], vm.args[1]) * scale
	var vx: float = float(vm.args[3]) / 256.0 * scale
	var vy: float = float(vm.args[4]) / 256.0 * scale
	var half: int = maxi(1, vm.args[5])
	var st := {"t": 0, "x": 0.0, "y": 0.0, "out": false}

	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var dir := -1.0 if bool(st["out"]) else 1.0
		st["x"] = float(st["x"]) + vx * dir
		st["y"] = float(st["y"]) + vy * dir
		node.offset = Vector2(float(st["x"]), float(st["y"]))
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) >= half:
			if bool(st["out"]):
				node.finish()
				return true
			st["out"] = true
			st["t"] = 0
		return false)


# AnimWhipHit (battle_anim_effects_1.c:5030) -- Vine Whip. No motion at all:
# a pure cel animation that dies when its frames run out.
static func _whip_hit(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	node.centre = _positioned_centre(vm, AnimStage.ANIM_TARGET, vm.args[0],
			vm.args[1], scale)
	_play_until_anim_ends(vm, node, 24)


# AnimTravelDiagonally (battle_anim_mons.c:1549) and its two wrappers.
# args: 0/1 start offsets, 2/3 target offsets, 4 duration, 5 anchor battler.
# A straight-line lerp from one battler toward another -- Ember's flame.
static func _travel_diagonally(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var anchor: int = AnimStage.ANIM_ATTACKER if vm.args[5] == 0 \
			else AnimStage.ANIM_TARGET
	var start := _positioned_centre(vm, anchor, vm.args[0], vm.args[1], scale)
	var target_x := float(vm.args[2]) * _facing(vm)
	var finish_pos := _battler_centre(vm, AnimStage.ANIM_TARGET) \
			+ Vector2(target_x, float(vm.args[3])) * scale
	node.centre = start
	_linear_travel(vm, node, start, finish_pos, maxi(1, vm.args[4]))


# AnimEmberFlare (battle_anim_fire.c:674) is AnimTravelDiagonally with one
# doubles-only mirroring tweak; AnimBurnFlame (:685) negates args 0 and 2.
static func _ember_flare(vm: AnimScriptVM, ctx: Dictionary) -> void:
	_travel_diagonally(vm, ctx)


static func _burn_flame(vm: AnimScriptVM, ctx: Dictionary) -> void:
	vm.args[0] = -vm.args[0]
	vm.args[2] = -vm.args[2]
	_travel_diagonally(vm, ctx)


# AnimFireSpread (battle_anim_fire.c:531). Unlike the above it has NO
# destination: constant 8.8-fixed velocity for a fixed duration.
static func _fire_spread(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	node.centre = _battler_centre(vm, AnimStage.ANIM_TARGET) \
			+ Vector2(vm.args[0], vm.args[1]) * scale
	var vx: float = float(vm.args[2]) / 256.0 * scale
	var vy: float = float(vm.args[3]) / 256.0 * scale
	var duration: int = maxi(1, vm.args[4])
	var st := {"t": 0, "x": 0.0, "y": 0.0}

	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["x"] = float(st["x"]) + vx
		st["y"] = float(st["y"]) + vy
		node.offset = Vector2(float(st["x"]), float(st["y"]))
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) >= duration:
			node.finish()
			return true
		return false)


# AnimBasicFistOrFoot (battle_anim_fight.c:474). args: 0 x, 1 y, 2 duration,
# 3 anchor, 4 anim frame (0 fist, 1/2 feet, 3/4 hands). Static: it appears,
# holds for the duration, and vanishes.
static func _basic_fist_or_foot(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var anchor: int = AnimStage.ANIM_ATTACKER if vm.args[3] == 0 \
			else AnimStage.ANIM_TARGET
	node.centre = _positioned_centre(vm, anchor, vm.args[0], vm.args[1], scale)
	_apply_anim_variant(node, ctx, vm.args[4])
	var duration: int = maxi(1, vm.args[2]) + 1
	var st := {"t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) >= duration:
			node.finish()
			return true
		return false)


# AnimEndureEnergy (battle_anim_effects_1.c:6073). args: 0 anchor, 1 x,
# 2 y, 3 frames per step. Rises with an ACCELERATING sawtooth -- expansion
# adds `y -= data[0]` every frame on top of the periodic 1px step, which
# vanilla does not have, so the ascent speeds up as it goes.
static func _endure_energy(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var anchor: int = AnimStage.ANIM_ATTACKER if vm.args[0] == 0 \
			else AnimStage.ANIM_TARGET
	node.centre = _battler_centre(vm, anchor) \
			+ Vector2(vm.args[1], vm.args[2]) * scale
	var threshold: int = maxi(1, vm.args[3])
	var st := {"t": 0, "counter": 0, "y": 0.0}

	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["counter"] = int(st["counter"]) + 1
		if int(st["counter"]) > threshold:
			st["counter"] = 0
			st["y"] = float(st["y"]) - scale
		st["y"] = float(st["y"]) - float(st["counter"]) * scale
		node.offset = Vector2(0.0, float(st["y"]))
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) >= 32:
			node.finish()
			return true
		return false)


# AnimAbsorptionOrb (battle_anim_effects_1.c:3170). args: 0 x, 1 y,
# 2 arc amplitude, 3 duration. Travels target -> attacker along an arc: the
# drain orb. This is the arc-translation helper's canonical use.
static func _absorption_orb(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var start := _positioned_centre(vm, AnimStage.ANIM_TARGET, vm.args[0],
			vm.args[1], scale)
	var finish_pos := _battler_centre(vm, AnimStage.ANIM_ATTACKER)
	node.centre = start
	_arc_travel(vm, node, start, finish_pos, maxi(1, vm.args[3]),
			float(vm.args[2]) * scale)


# AnimBubbleEffect (battle_anim_poison.c:634). args: 0 x, 1 y, 2 multi-target.
# Wobbles horizontally while rising; ends with its 21-frame affine anim.
static func _bubble_effect(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	node.centre = _positioned_centre(vm, AnimStage.ANIM_TARGET, vm.args[0],
			vm.args[1], scale)
	var st := {"t": 0, "phase": 0.0, "rise": 0.0}

	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["phase"] = fmod(float(st["phase"]) + 11.0, _SIN_STEPS)
		st["rise"] = float(st["rise"]) + 0x30 / 256.0
		node.offset = Vector2(_gba_sin(float(st["phase"]), 4.0 * scale),
				-float(st["rise"]) * scale)
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) >= 21:
			node.finish()
			return true
		return false)


# AnimTranslateLinearSingleSineWave (battle_anim_effects_1.c:3900).
# args: 0/1 start, 2/3 target offsets, 4 duration, 5 arc amplitude.
static func _linear_single_sine_wave(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var start := _positioned_centre(vm, AnimStage.ANIM_ATTACKER, vm.args[0],
			vm.args[1], scale)
	var finish_pos := _battler_centre(vm, AnimStage.ANIM_TARGET) \
			+ Vector2(float(vm.args[2]) * _facing(vm), float(vm.args[3])) \
				* scale
	node.centre = start
	_arc_travel(vm, node, start, finish_pos, maxi(1, vm.args[4]),
			float(vm.args[5]) * scale)


# ══ [M36D] Mon tasks ══════════════════════════════════════════════════════

# AnimTask_ScaleMonAndRestore (battle_anim_mon_movement.c:977). args: 0 x
# scale delta, 1 y scale delta, 2 half-duration, 3 battler, 4 obj mode.
# Ramps the scale then runs the exact reverse ramp, so it always lands back
# at 1.0. Note the deltas are MATRIX scale, where positive means smaller on
# screen -- hence the negation here.
static func _scale_mon_and_restore(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var node := _battler_node(vm, vm.args[3])
	if node == null:
		return
	var half: int = maxi(1, vm.args[2])
	var dx: float = -float(vm.args[0]) / 256.0
	var dy: float = -float(vm.args[1]) / 256.0
	var base_scale := node.scale
	var base_pivot := node.pivot_offset
	node.pivot_offset = node.size * 0.5
	var st := {"t": 0, "out": false, "sx": 1.0, "sy": 1.0}

	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		var dir := -1.0 if bool(st["out"]) else 1.0
		st["sx"] = float(st["sx"]) + dx * dir
		st["sy"] = float(st["sy"]) + dy * dir
		node.scale = Vector2(base_scale.x * maxf(0.05, float(st["sx"])),
				base_scale.y * maxf(0.05, float(st["sy"])))
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) >= half:
			if bool(st["out"]):
				node.scale = base_scale
				node.pivot_offset = base_pivot
				return true
			st["out"] = true
			st["t"] = 0
		return false)


# AnimTask_SwayMon (battle_anim_mon_movement.c:899). args: 0 axis
# (0 horizontal, 1 vertical), 1 amplitude, 2 phase step (8.8), 3 sway count,
# 4 battler. A "sway" is one HALF sine cycle, counted by 0x80 crossings.
static func _sway_mon(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var node := _battler_node(vm, vm.args[4])
	if node == null:
		return
	var scale := _scale(vm)
	var amplitude: float = float(vm.args[1]) * scale
	if not _is_player_side(vm):
		amplitude = -amplitude
	var vertical: bool = vm.args[0] != 0
	var phase_step: float = float(vm.args[2]) / 256.0
	var sways: int = maxi(1, vm.args[3])
	var mon := MonOffset.new(node)
	var st := {"phase": 0.0, "left": sways, "half": 0}

	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		st["phase"] = float(st["phase"]) + phase_step
		var idx := fmod(float(st["phase"]), _SIN_STEPS)
		var value := _gba_sin(idx, amplitude)
		if vertical:
			mon.apply(Vector2(0.0, -absf(value)))
		else:
			mon.apply(Vector2(value, 0.0))
		# Count each crossing of the half-cycle boundary.
		var half := 1 if idx >= 128.0 else 0
		if half != int(st["half"]):
			st["half"] = half
			st["left"] = int(st["left"]) - 1
			if int(st["left"]) <= 0:
				mon.restore()
				return true
		return false)


# AnimTask_TranslateMonElliptical (battle_anim_mon_movement.c:375).
# args: 0 battler, 1 width, 2 height, 3 loops, 4 speed (0-5 -> step 1..32).
# The -Cos(...) + height offset is what makes the path start and end at the
# mon's real position instead of jumping.
static func _translate_mon_elliptical(vm: AnimScriptVM,
		_ctx: Dictionary) -> void:
	var node := _battler_node(vm, vm.args[0])
	if node == null:
		return
	var scale := _scale(vm)
	var width: float = float(vm.args[1]) * scale
	var height: float = float(vm.args[2]) * scale
	var loops: int = maxi(1, vm.args[3])
	var step := float(1 << clampi(vm.args[4], 0, 5))
	var mon := MonOffset.new(node)
	var st := {"phase": 0.0, "left": loops}

	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		var ph: float = st["phase"]
		mon.apply(Vector2(_gba_sin(ph, width),
				-_gba_cos(ph, height) + height))
		ph = ph + step
		if ph >= _SIN_STEPS:
			ph = fmod(ph, _SIN_STEPS)
			st["left"] = int(st["left"]) - 1
			if int(st["left"]) <= 0:
				mon.restore()
				return true
		st["phase"] = ph
		return false)


# AnimTask_TranslateMonEllipticalRespectSide (:427) negates the width for an
# opponent-side attacker, then delegates.
static func _translate_mon_elliptical_respect_side(vm: AnimScriptVM,
		ctx: Dictionary) -> void:
	if not _is_player_side(vm):
		vm.args[1] = -vm.args[1]
	_translate_mon_elliptical(vm, ctx)


# ══ [M36D] Shared motion helpers ══════════════════════════════════════════

# Linear travel plus a half-sine arc, the port of InitAnimArcTranslation +
# TranslateAnimHorizontalArc: the phase advances 0x8000/duration per frame,
# i.e. exactly half a sine cycle over the whole flight.
static func _arc_travel(vm: AnimScriptVM, node: AnimSprite, start: Vector2,
		finish_pos: Vector2, duration: int, amplitude: float) -> void:
	var st := {"t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var t: int = int(st["t"]) + 1
		st["t"] = t
		if t >= duration:
			node.finish()
			return true
		var f := float(t) / float(duration)
		var pos := start.lerp(finish_pos, f)
		pos.y += _gba_sin(f * 128.0, amplitude)
		node.centre = pos
		return false)


# A sprite whose lifetime is its own cel animation. `cap` bounds it so a
# sheet with a looping sequence cannot keep a script waiting forever.
static func _play_until_anim_ends(vm: AnimScriptVM, node: AnimSprite,
		cap: int) -> void:
	var st := {"t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) >= cap:
			node.finish()
			return true
		return false)


# Selects one of a template's alternate frame sequences (the fist/foot set).
static func _apply_anim_variant(node: AnimSprite, ctx: Dictionary,
		variant: int) -> void:
	var seqs := AnimData.anim_sequences_for(str(ctx.get("template", "")))
	if seqs.is_empty():
		return
	node.play_sequence(seqs[clampi(variant, 0, seqs.size() - 1)])


# ══ [M36D batch 2] ════════════════════════════════════════════════════════

# AnimTask_ShakeAndSinkMon (battle_anim_mon_movement.c:324). args: 0 battler,
# 1 x offset, 2 flip delay, 3 sink speed (1/256 px per frame), 4 duration.
# Unlike the shakes this does NOT restore -- the mon is left sunk, and the
# script is expected to follow up. Reproduced faithfully, but the base is
# recorded so a later SlideMonToOriginalPos can undo it.
static func _shake_and_sink_mon(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var node := _battler_node(vm, vm.args[0])
	if node == null:
		return
	var scale := _scale(vm)
	var x_off := float(vm.args[1]) * scale
	var flip_delay: int = maxi(1, vm.args[2])
	var sink: float = float(vm.args[3]) / 256.0 * scale
	var duration: int = maxi(1, vm.args[4])
	var mon := MonOffset.new(node)
	var st := {"t": 0, "flip": 0, "x": 0.0, "y": 0.0}

	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		if int(st["flip"]) >= flip_delay:
			st["flip"] = 0
			st["x"] = x_off if is_zero_approx(float(st["x"])) else 0.0
		st["flip"] = int(st["flip"]) + 1
		st["y"] = float(st["y"]) + sink
		mon.apply(Vector2(float(st["x"]), float(st["y"])))
		st["t"] = int(st["t"]) + 1
		return int(st["t"]) >= duration)


# AnimShadowBall (battle_anim_ghost.c:432). args: 0 gather duration,
# 1 pause, 2 strike duration. Three phases: the ball forms by travelling
# HALF-way from the attacker toward the target, hangs, then strikes home.
static func _shadow_ball(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var gather: int = maxi(1, vm.args[0])
	var pause: int = maxi(0, vm.args[1])
	var strike: int = maxi(1, vm.args[2])
	var from := _battler_centre(vm, AnimStage.ANIM_ATTACKER)
	var to := _battler_centre(vm, AnimStage.ANIM_TARGET)
	var midpoint := from + (to - from) * 0.5
	node.centre = from

	var st := {"phase": 0, "t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var phase: int = int(st["phase"])
		var t: int = int(st["t"]) + 1
		st["t"] = t
		match phase:
			0:
				node.centre = from.lerp(midpoint, minf(1.0,
						float(t) / float(gather)))
				if t >= gather:
					st["phase"] = 1
					st["t"] = 0
			1:
				if t >= pause:
					st["phase"] = 2
					st["t"] = 0
			_:
				node.centre = midpoint.lerp(to, minf(1.0,
						float(t) / float(strike)))
				if t >= strike:
					node.finish()
					return true
		return false)


# AnimWaterBubbleProjectile (battle_anim_water.c:674). args: 0/1 start
# offsets, 2 x wave amplitude, 3 y wave amplitude, 4 initial trig index,
# 5 trig delta, 6 duration. Linear travel with an elliptical wobble
# superimposed, then a cel-animation flourish before it dies.
static func _water_bubble_projectile(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var start := _positioned_centre(vm, AnimStage.ANIM_ATTACKER, vm.args[0],
			vm.args[1], scale)
	var finish_pos := _battler_centre(vm, AnimStage.ANIM_TARGET)
	var amp_x: float = float(vm.args[2]) * scale
	if not _is_player_side(vm):
		amp_x = -amp_x
	var amp_y: float = float(vm.args[3]) * scale
	var duration: int = maxi(1, vm.args[6])
	node.centre = start

	var st := {"t": 0, "phase": float(vm.args[4]), "tail": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var t: int = int(st["t"])
		if t < duration:
			var f := float(t + 1) / float(duration)
			node.centre = start.lerp(finish_pos, f)
			node.offset = Vector2(_gba_sin(float(st["phase"]), amp_x),
					_gba_cos(float(st["phase"]), amp_y))
			st["phase"] = fmod(float(st["phase"]) + float(vm.args[5]),
					_SIN_STEPS)
			st["t"] = t + 1
			return false
		# The tail: upstream plays out the cel animation then holds 10 frames.
		st["tail"] = int(st["tail"]) + 1
		if int(st["tail"]) >= 18:
			node.finish()
			return true
		return false)


# AnimBoneHitProjectile (battle_anim_ground.c:178). args: 0/1 start offsets,
# 2/3 target offsets, 4 duration. Plain linear travel to the target.
static func _bone_hit_projectile(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var start := _positioned_centre(vm, AnimStage.ANIM_TARGET, vm.args[0],
			vm.args[1], scale)
	var finish_pos := _battler_centre(vm, AnimStage.ANIM_TARGET) \
			+ Vector2(float(vm.args[2]) * _facing(vm), float(vm.args[3])) \
				* scale
	node.centre = start
	_linear_travel(vm, node, start, finish_pos, maxi(1, vm.args[4]))


# AnimTranslateStinger (battle_anim_bug.c:350). args: 0/1 start, 2/3 target
# offsets, 4 duration. Like the missile, but ROTATED to face its direction of
# travel -- a stinger that flew sideways would read as a bug.
static func _translate_stinger(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var start := _positioned_centre(vm, AnimStage.ANIM_ATTACKER, vm.args[0],
			vm.args[1], scale)
	var finish_pos := _battler_centre(vm, AnimStage.ANIM_TARGET) \
			+ Vector2(float(vm.args[2]) * _facing(vm), float(vm.args[3])) \
				* scale
	node.centre = start
	node.rotation = (finish_pos - start).angle()
	_linear_travel(vm, node, start, finish_pos, maxi(1, vm.args[4]))


# AnimMissileArc (battle_anim_bug.c:398). args: 0/1 start, 2/3 target,
# 4 duration, 5 arc amplitude. An arcing projectile that rotates to follow
# its own tangent -- upstream computes that by stepping the arc one frame
# ahead and taking the angle between, which is what this reproduces.
static func _missile_arc(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var start := _positioned_centre(vm, AnimStage.ANIM_ATTACKER, vm.args[0],
			vm.args[1], scale)
	var finish_pos := _battler_centre(vm, AnimStage.ANIM_TARGET) \
			+ Vector2(float(vm.args[2]) * _facing(vm), float(vm.args[3])) \
				* scale
	var duration: int = maxi(1, vm.args[4])
	var amplitude: float = float(vm.args[5]) * scale
	node.centre = start

	var arc_at := func(f: float) -> Vector2:
		var p := start.lerp(finish_pos, f)
		p.y += _gba_sin(f * 128.0, amplitude)
		return p

	var st := {"t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var t: int = int(st["t"]) + 1
		st["t"] = t
		if t >= duration:
			node.finish()
			return true
		var f := float(t) / float(duration)
		var pos: Vector2 = arc_at.call(f)
		# One-frame lookahead for the tangent, exactly as upstream does.
		var ahead: Vector2 = arc_at.call(minf(1.0, f + 1.0 / float(duration)))
		node.centre = pos
		if not ahead.is_equal_approx(pos):
			node.rotation = (ahead - pos).angle()
		return false)


# AnimLeechSeed (battle_anim_effects_1.c:3531). args: 0/1 start, 2/3 target,
# 4 duration, 5 arc amplitude. Arcs onto the target, hides for 10 frames,
# then SPROUTS (a second cel animation) for 60 more.
static func _leech_seed(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var start := _positioned_centre(vm, AnimStage.ANIM_ATTACKER, vm.args[0],
			vm.args[1], scale)
	var finish_pos := _battler_centre(vm, AnimStage.ANIM_TARGET) \
			+ Vector2(float(vm.args[2]) * _facing(vm), float(vm.args[3])) \
				* scale
	var duration: int = maxi(1, vm.args[4])
	var amplitude: float = float(vm.args[5]) * scale
	node.centre = start

	var seqs := AnimData.anim_sequences_for(str(ctx.get("template", "")))
	var st := {"t": 0, "phase": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var t: int = int(st["t"]) + 1
		st["t"] = t
		match int(st["phase"]):
			0:
				var f := float(t) / float(duration)
				var pos := start.lerp(finish_pos, f)
				pos.y += _gba_sin(f * 128.0, amplitude)
				node.centre = pos
				if t >= duration:
					node.visible = false
					st["phase"] = 1
					st["t"] = 0
			1:
				if t >= 10:
					node.visible = true
					if seqs.size() > 1:
						node.play_sequence(seqs[1])
					st["phase"] = 2
					st["t"] = 0
			_:
				if t >= 60:
					node.finish()
					return true
		return false)


# AnimRazorLeafParticle (battle_anim_effects_1.c:3700). args: 0/1 per-frame
# drift, 2 drift duration. Blows outward, then flutters: a 25px sine sway
# while falling 1 px every other frame, for 81 frames.
static func _razor_leaf_particle(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	node.centre = _battler_centre(vm, AnimStage.ANIM_ATTACKER)
	var dx := float(vm.args[0]) * scale
	var dy := float(vm.args[1]) * scale
	var drift: int = maxi(1, vm.args[2])
	# The parity of the y delta picks the starting sine phase upstream.
	var phase0: float = 128.0 if (vm.args[1] & 1) == 1 else 0.0
	var sway: float = 25.0 * scale * _facing(vm)

	var st := {"t": 0, "phase": phase0, "flutter": 0, "pos": Vector2.ZERO}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var t: int = int(st["t"])
		if t < drift:
			st["pos"] = (st["pos"] as Vector2) + Vector2(dx, dy)
			node.offset = st["pos"]
			st["t"] = t + 1
			return false
		var f: int = int(st["flutter"]) + 1
		st["flutter"] = f
		var base: Vector2 = st["pos"]
		node.offset = base + Vector2(_gba_sin(float(st["phase"]), sway),
				float(f / 2) * scale)
		st["phase"] = fmod(float(st["phase"]) + 2.0, _SIN_STEPS)
		if f > 80:
			node.finish()
			return true
		return false)


# AnimFallingRock (battle_anim_rock.c:371). args: 0 x offset, 1 cel anim,
# 2 horizontal drift per phase, 3 recenter flag. Two 4-frame elliptical
# sweeps with a drift between them -- the tumbling debris.
static func _falling_rock(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	node.centre = _battler_centre(vm, AnimStage.ANIM_TARGET) \
			+ Vector2(float(vm.args[0]) * scale, 14.0 * scale)
	_apply_anim_variant(node, ctx, vm.args[1])
	var drift := float(vm.args[2]) * scale

	# Phase 1: circlePos 0, amplitudes (16, -70), 4 frames.
	# Phase 2: circlePos 192, amplitudes (32, -24), 4 frames, after drifting.
	var st := {"phase": 0, "t": 0, "pos": 0.0, "speed": 0.0,
			"ax": 16.0 * scale, "ay": -70.0 * scale, "shift": 0.0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var pos: float = st["pos"]
		node.offset = Vector2(
				_gba_sin(pos, float(st["ax"])) + float(st["shift"]),
				_gba_cos(pos, float(st["ay"])))
		st["pos"] = fposmod(pos + float(st["speed"]), _SIN_STEPS)
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) >= 4:
			st["t"] = 0
			if int(st["phase"]) == 0:
				st["phase"] = 1
				st["shift"] = drift
				st["pos"] = 192.0
				st["speed"] = drift
				st["ax"] = 32.0 * scale
				st["ay"] = -24.0 * scale
				return false
			node.finish()
			return true
		return false)


# AnimFrenzyPlantRoot (battle_anim_effects_1.c:4182). args: 0 interpolate
# percent along attacker->target, 1/2 offsets, 3 subpriority, 4 cel anim,
# 5 duration. Static, flickering out over its last 10 frames.
static func _frenzy_plant_root(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var from := _battler_centre(vm, AnimStage.ANIM_ATTACKER)
	var to := _battler_centre(vm, AnimStage.ANIM_TARGET)
	node.centre = from + (to - from) * (float(vm.args[0]) / 100.0) \
			+ Vector2(vm.args[1], vm.args[2]) * scale
	_apply_anim_variant(node, ctx, vm.args[4])
	var duration: int = maxi(1, vm.args[5])
	var st := {"t": 0}

	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var t: int = int(st["t"]) + 1
		st["t"] = t
		if t > duration - 10:
			node.visible = (t % 2) == 0
		if t > duration:
			node.finish()
			return true
		return false)


# AnimTask_TraceMonBlended (battle_anim_utility_funcs.c:188). args:
# 0 battler, 1 delay, 2 trace lifetime, 3 trace count. Real afterimages:
# each trace is a blended copy of the mon's own sprite that fades out.
static func _trace_mon_blended(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var node := _battler_node(vm, vm.args[0])
	var layer: Control = null
	if vm.stage != null and vm.stage.has_method("layer"):
		layer = vm.stage.layer()
	if node == null or layer == null:
		return
	var delay: int = maxi(0, vm.args[1])
	var lifetime: int = maxi(1, vm.args[2])
	var count: int = maxi(1, vm.args[3])
	var st := {"t": 0, "left": count, "traces": []}

	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		# Age existing traces.
		var alive: Array = []
		for entry in (st["traces"] as Array):
			var e: Dictionary = entry
			e["age"] = int(e["age"]) + 1
			var tex: Control = e["node"]
			if not is_instance_valid(tex):
				continue
			if int(e["age"]) >= lifetime:
				tex.queue_free()
				continue
			tex.modulate.a = 0.6 * (1.0 - float(e["age"]) / float(lifetime))
			alive.append(e)
		st["traces"] = alive

		if int(st["left"]) > 0 and int(st["t"]) % (delay + 1) == 0:
			var trace := _clone_battler_visual(node, layer)
			if trace != null:
				(st["traces"] as Array).append({"node": trace, "age": 0})
			st["left"] = int(st["left"]) - 1
		st["t"] = int(st["t"]) + 1
		# Upstream ends only when every trace has expired too.
		if int(st["left"]) <= 0 and (st["traces"] as Array).is_empty():
			return true
		return false)


# A blended copy of a battler's current appearance, used for afterimages.
# Copies the texture rather than the node so the clone cannot inherit the
# original's own per-frame updates.
static func _clone_battler_visual(node: Control, layer: Control) -> Control:
	var src := node as TextureRect
	if src == null or src.texture == null:
		return null
	var copy := TextureRect.new()
	copy.texture = src.texture
	copy.size = src.size
	copy.scale = src.scale
	copy.position = src.position
	copy.flip_h = src.flip_h
	copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	copy.modulate = Color(1, 1, 1, 0.6)
	copy.z_index = -1
	# Tagged so anim-owned clones are distinguishable from the real battler
	# sprites they were copied from -- both are TextureRects on the same
	# layer, and only these should ever be cleaned up.
	copy.set_meta("_anim_trace", true)
	layer.add_child(copy)
	return copy


# AnimFlyUpTarget (battle_anim_water.c:805). args: 0 x offset, 1 y offset,
# 2 stop threshold, 3 speed. Rises from the target's mid-height until it
# passes the threshold. The guard is checked BEFORE moving, so a sprite that
# starts already past the threshold dies on its first frame.
static func _fly_up_target(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	node.centre = _positioned_centre(vm, AnimStage.ANIM_TARGET, vm.args[0],
			vm.args[1], scale)
	var rect := Rect2()
	if vm.stage != null and vm.stage.has_method("rect_of"):
		rect = vm.stage.rect_of(AnimStage.ANIM_TARGET)
	var y := rect.size.y * 0.5 + float(vm.args[1]) * scale
	var threshold := float(vm.args[2]) * scale
	var speed := maxf(0.5, float(vm.args[3]) * scale)
	var st := {"y": y}

	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		if float(st["y"]) <= threshold:
			node.finish()
			return true
		st["y"] = float(st["y"]) - speed
		node.offset = Vector2(0.0, float(st["y"]))
		return false)


# AnimJumpKick / AnimSlideHandOrFootToTarget (battle_anim_fight.c:456/:443)
# both resolve to a diagonal travel with a cel-anim selection.
static func _jump_kick(vm: AnimScriptVM, ctx: Dictionary) -> void:
	_slide_hand_or_foot_to_target(vm, ctx)


static func _slide_hand_or_foot_to_target(vm: AnimScriptVM,
		ctx: Dictionary) -> void:
	if vm.args[7] == 1 and not _is_player_side(vm):
		vm.args[1] = -vm.args[1]
		vm.args[3] = -vm.args[3]
	var variant: int = vm.args[6]
	# Upstream zeroes arg 6 before delegating, which forces the
	# respect-mon-pic-offsets branch downstream.
	vm.args[6] = 0
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	_apply_anim_variant(node, ctx, variant)
	var scale := _scale(vm)
	var anchor: int = AnimStage.ANIM_ATTACKER if vm.args[5] == 0 \
			else AnimStage.ANIM_TARGET
	var start := _positioned_centre(vm, anchor, vm.args[0], vm.args[1], scale)
	var finish_pos := _battler_centre(vm, anchor) \
			+ Vector2(float(vm.args[2]) * _facing(vm), float(vm.args[3])) \
				* scale
	node.centre = start
	_linear_travel(vm, node, start, finish_pos, maxi(1, vm.args[4]))


# AnimDizzyPunchDuck (battle_anim_fight.c:693). args: 0/1 offsets,
# 2 horizontal velocity (8.8), 3 sine amplitude. Drifts sideways on a sine
# bob, flickers from frame ~34, gone by ~41.
static func _dizzy_punch_duck(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	node.centre = _positioned_centre(vm, AnimStage.ANIM_TARGET, vm.args[0],
			vm.args[1], scale)
	var vx := float(vm.args[2]) / 256.0 * scale
	var amp := float(vm.args[3]) * scale
	var st := {"x": 0.0, "phase": 0.0}

	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["x"] = float(st["x"]) + vx
		var ph: float = st["phase"]
		node.offset = Vector2(float(st["x"]), _gba_sin(ph, amp))
		ph += 3.0
		st["phase"] = ph
		if ph > 100.0:
			node.visible = int(ph) % 2 == 0
		if ph > 120.0:
			node.finish()
			return true
		return false)


# AnimClawSlash (battle_anim_dark.c:892). args: 0/1 offsets, 2 cel anim.
# Pure cel animation at the target, no motion.
static func _claw_slash(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	node.centre = _battler_centre(vm, AnimStage.ANIM_TARGET) \
			+ Vector2(vm.args[0], vm.args[1]) * scale
	_apply_anim_variant(node, ctx, vm.args[2])
	_play_until_anim_ends(vm, node, 20)


# SpriteCB_SpriteOnMonForDuration (battle_anim_new.c:6577) + its shared step
# (battle_anim_fight.c:741). args: 0 battler, 1/2 offsets, 3 hold duration,
# 4 shake duration. Sits still, then rattles +/-2 px every other frame.
static func _sprite_on_mon_for_duration(vm: AnimScriptVM,
		ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var battler: int = vm.args[0] if vm.args[0] in [0, 1, 2, 3] \
			else AnimStage.ANIM_TARGET
	node.centre = _battler_centre(vm, battler) \
			+ Vector2(vm.args[1], vm.args[2]) * scale
	var hold: int = maxi(1, vm.args[3])
	var shake: int = maxi(0, vm.args[4])
	var st := {"t": 0, "shake_t": 0, "n": 0}

	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var t: int = int(st["t"]) + 1
		st["t"] = t
		if t < hold:
			return false
		if shake == 0:
			node.finish()
			return true
		var s: int = int(st["shake_t"]) + 1
		st["shake_t"] = s
		if s % 2 == 0:
			st["n"] = int(st["n"]) + 1
			node.offset = Vector2(
					2.0 * scale if (int(st["n"]) & 1) == 1 else -2.0 * scale,
					0.0)
		if s >= shake:
			node.finish()
			return true
		return false)


# AnimComplexPaletteBlend (battle_anim_normal.c:418). args: 0 selector,
# 1 delay (low byte) packed with a toggle bit, 2 blend count, 3 colour 1,
# 4 blend y 1, 5 colour 2, 6 blend y 2. Alternates between two tints.
static func _complex_palette_blend(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var nodes := _blend_nodes(vm, vm.args[0])
	var delay: int = vm.args[1] & 0xFF
	var blends: int = maxi(1, vm.args[2])
	var colour1 := _rgb15_to_color(vm.args[3])
	var blend1: int = vm.args[4]
	var colour2 := _rgb15_to_color(vm.args[5])
	var blend2: int = vm.args[6]
	var bases: Array[Color] = []
	for n in nodes:
		bases.append(n.modulate)

	var st := {"left": blends, "timer": 0, "alt": false}
	vm.add_stepper(func() -> bool:
		if int(st["timer"]) < delay:
			st["timer"] = int(st["timer"]) + 1
			return false
		st["timer"] = 0
		var use_second: bool = st["alt"]
		var colour: Color = colour2 if use_second else colour1
		var amount: float = clampf(
				float(blend2 if use_second else blend1) / 16.0, 0.0, 1.0)
		for i in range(nodes.size()):
			var n: Control = nodes[i]
			if is_instance_valid(n):
				n.modulate = (bases[i] as Color).lerp(colour, amount)
		st["alt"] = not use_second
		st["left"] = int(st["left"]) - 1
		if int(st["left"]) <= 0:
			for i in range(nodes.size()):
				var n2: Control = nodes[i]
				if is_instance_valid(n2):
					n2.modulate = bases[i]
			return true
		return false)


# AnimTask_SetGrayscaleOrOriginalPal (battle_anim_dark.c:1016). args:
# 0 battler, 1 mode (0 = restore, else grayscale). Single frame upstream.
static func _set_grayscale_or_original(vm: AnimScriptVM,
		_ctx: Dictionary) -> void:
	var node := _battler_node(vm, vm.args[0])
	if node == null:
		return
	if vm.args[1] != 0:
		# Desaturating a modulate cannot truly grayscale a texture, but it is
		# the closest single-property equivalent without a shader; the visible
		# effect (the mon drains of colour) reads correctly.
		node.modulate = Color(0.6, 0.6, 0.6, node.modulate.a)
	else:
		node.modulate = Color(1, 1, 1, node.modulate.a)


# AnimDefensiveWall (battle_anim_psychic.c:503) -- Reflect / Light Screen.
# A wall that fades in over 13 frames, shimmers for 32, fades out over 14.
# Upstream moves the opponent sprites to a BG layer so the wall sits in
# front; z-ordering is the Godot equivalent.
static func _defensive_wall(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	node.centre = _battler_centre(vm, AnimStage.ANIM_ATTACKER) \
			+ Vector2(float(vm.args[0]) * _facing(vm), float(vm.args[1])) \
				* scale
	node.z_index = 2
	node.modulate.a = 0.0
	var st := {"phase": 0, "t": 0}

	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var t: int = int(st["t"]) + 1
		st["t"] = t
		match int(st["phase"]):
			0:
				node.modulate.a = clampf(float(t) / 13.0, 0.0, 1.0)
				if t >= 13:
					st["phase"] = 1
					st["t"] = 0
			1:
				# The shimmer: upstream rotates 8 palette entries every other
				# frame. A subtle brightness pulse is the closest equivalent
				# without palette indirection.
				node.modulate.v = 1.0 + 0.15 * sin(TAU * float(t) / 8.0)
				if t >= 32:
					st["phase"] = 2
					st["t"] = 0
			_:
				node.modulate.a = clampf(1.0 - float(t) / 14.0, 0.0, 1.0)
				if t >= 14:
					node.finish()
					return true
		return false)


# ── Sound tasks: structured no-ops (audio is M36-S) ───────────────────────
#
# These still matter to TIMING even with no audio. Upstream most are
# single-frame, but the cry tasks block a script until the cry finishes --
# and with no cry playing, "finished" is immediate after their two warm-up
# frames. Reproducing that distinction keeps script pacing right rather than
# collapsing every sound cue to zero cost.

static func _sound_immediate(_vm: AnimScriptVM, _ctx: Dictionary) -> void:
	pass


static func _sound_cry_wait(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var st := {"t": 0}
	vm.add_stepper(func() -> bool:
		st["t"] = int(st["t"]) + 1
		return int(st["t"]) >= 2)


# ══ [M36D batch 3] ════════════════════════════════════════════════════════

# AnimTask_IsTargetPlayerSide (battle_anim_effects_3.c:1595). Writes 1 when
# the TARGET is on the player's side.
static func _is_target_player_side(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	# The attacker's side is known; the target is on the other one unless it
	# is a self- or ally-target, which the stage resolves by identity.
	var target_is_player: bool = not _is_player_side(vm)
	if vm.stage != null and vm.stage.has_method("mon_for"):
		var atk: Variant = vm.stage.mon_for(AnimStage.ANIM_ATTACKER)
		var tgt: Variant = vm.stage.mon_for(AnimStage.ANIM_TARGET)
		if atk != null and atk == tgt:
			target_is_player = _is_player_side(vm)
	vm.args[AnimScriptVM.ARG_RET] = 1 if target_is_player else 0


# AnimTask_HorizontalShake (battle_anim_ground.c:568). args: 0 what to shake
# (0-3 a battler, 4 all battlers, 5 the PLATFORMS), 1 intensity (0 = derive
# from move power), 2 shake length. Flips every other frame, then rings down
# by decrementing the amplitude every 4 frames until it reaches zero.
static func _horizontal_shake(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var scale := _scale(vm)
	var intensity: int = vm.args[1]
	if intensity == 0:
		intensity = int(vm.move_power / 10.0)
	var amplitude: float = float(intensity + 3) * scale
	var max_time: int = maxi(1, vm.args[2])

	var targets: Array[MonOffset] = []
	if vm.args[0] == 5:
		# Platform shake writes gBattle_BG3_X -- background-layer work that
		# M36E owns. The frames are still consumed so script pacing holds;
		# nothing is drawn.
		pass
	elif vm.args[0] == 4:
		for b in [AnimStage.ANIM_ATTACKER, AnimStage.ANIM_TARGET,
				AnimStage.ANIM_ATK_PARTNER, AnimStage.ANIM_DEF_PARTNER]:
			var n := _battler_node(vm, b)
			if n != null:
				targets.append(MonOffset.new(n))
	else:
		var n2 := _battler_node(vm, vm.args[0])
		if n2 != null:
			targets.append(MonOffset.new(n2))

	var st := {"t": 0, "phase": 0, "amp": amplitude, "delay": 0}
	vm.add_stepper(func() -> bool:
		# Acts every second frame, as the tDelay > 1 guard does upstream.
		if int(st["delay"]) < 1:
			st["delay"] = int(st["delay"]) + 1
			return false
		st["delay"] = 0
		var t: int = int(st["t"])
		var amp: float = st["amp"]
		var off := (amp * 0.5) if (t & 1) == 0 else -(amp * 0.5)
		for mon in targets:
			mon.apply(Vector2(off, 0.0))
		st["t"] = t + 1
		if int(st["phase"]) == 0:
			if int(st["t"]) >= max_time:
				st["t"] = 0
				st["amp"] = amp - scale
				st["phase"] = 1
			return false
		if int(st["t"]) >= 4:
			st["t"] = 0
			st["amp"] = amp - scale
			if float(st["amp"]) <= 0.0:
				for mon in targets:
					mon.restore()
				return true
		return false)


# AnimTask_WindUpLunge (battle_anim_mon_movement.c:718). args: 0 battler,
# 1 wind-up travel, 2 wave amplitude, 3 wind-up duration, 4 delay,
# 5 lunge distance, 6 lunge duration. Pulls back on a sine bob, pauses,
# then drives forward -- the classic charge-and-strike.
static func _wind_up_lunge(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var node := _battler_node(vm, vm.args[0])
	if node == null:
		return
	var scale := _scale(vm)
	var sign := _facing(vm)
	var back_total := float(vm.args[1]) * scale * sign
	var amplitude := float(vm.args[2]) * scale
	var back_frames: int = maxi(1, vm.args[3])
	var delay: int = maxi(0, vm.args[4])
	var lunge_total := float(vm.args[5]) * scale * sign
	var lunge_frames: int = maxi(1, vm.args[6])
	var mon := MonOffset.new(node)
	var st := {"phase": 0, "t": 0, "x": 0.0, "y": 0.0}

	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		var t: int = int(st["t"]) + 1
		st["t"] = t
		match int(st["phase"]):
			0:
				# Half a sine cycle across the wind-up, as upstream's
				# wavePeriod = 0x8000 / duration gives.
				st["x"] = back_total * (float(t) / float(back_frames))
				st["y"] = _gba_sin(128.0 * float(t) / float(back_frames),
						amplitude)
				mon.apply(Vector2(float(st["x"]), float(st["y"])))
				if t >= back_frames:
					st["phase"] = 1
					st["t"] = 0
			1:
				if t >= delay:
					st["phase"] = 2
					st["t"] = 0
			_:
				var f := float(t) / float(lunge_frames)
				mon.apply(Vector2(float(st["x"]) + lunge_total * f,
						float(st["y"])))
				if t >= lunge_frames:
					mon.restore()
					return true
		return false)


# AnimTask_RotateMonSpriteToSide (battle_anim_mon_movement.c:1017). args:
# 0 frames, 1 rotation delta per frame, 2 battler, 3 mode (0 hold, 1 reset,
# 2 out-and-back -- mode 2 costs twice the frames).
static func _rotate_mon_to_side(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	_rotate_mon(vm, vm.args[3], false)


# AnimTask_RotateMonToSideAndRestore (:1058) always rotates back.
static func _rotate_mon_to_side_restore(vm: AnimScriptVM,
		_ctx: Dictionary) -> void:
	_rotate_mon(vm, 2, true)


static func _rotate_mon(vm: AnimScriptVM, mode: int, force_back: bool) -> void:
	var node := _battler_node(vm, vm.args[2])
	if node == null:
		return
	var frames: int = maxi(1, vm.args[0])
	# GBA rotation units are 1/65536 of a turn.
	var delta := float(vm.args[1]) * TAU / 65536.0
	if not _is_player_side(vm) or force_back:
		delta = -delta
	var base_rot := node.rotation
	var base_pivot := node.pivot_offset
	node.pivot_offset = node.size * 0.5
	var st := {"t": 0, "rot": 0.0, "back": false}

	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		var dir := -1.0 if bool(st["back"]) else 1.0
		st["rot"] = float(st["rot"]) + delta * dir
		node.rotation = base_rot + float(st["rot"])
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) >= frames:
			if mode == 2 and not bool(st["back"]):
				st["back"] = true
				st["t"] = 0
				return false
			if mode != 0:
				node.rotation = base_rot
				node.pivot_offset = base_pivot
			return true
		return false)


# AnimTask_Teleport (battle_anim_psychic.c:795). No args. The attacker
# squashes horizontally over 20 frames, then rises in 8px steps and vanishes.
static func _teleport(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var node := _battler_node(vm, AnimStage.ANIM_ATTACKER)
	if node == null:
		return
	var scale := _scale(vm)
	var base_scale := node.scale
	var base_pivot := node.pivot_offset
	node.pivot_offset = node.size * 0.5
	var mon := MonOffset.new(node)
	var rises: int = 8 if _is_player_side(vm) else 4
	var st := {"t": 0, "phase": 0, "y": 0.0}

	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		var t: int = int(st["t"]) + 1
		st["t"] = t
		if int(st["phase"]) == 0:
			# xScale rises and yScale falls in matrix units, which narrows
			# and stretches the sprite before it lifts away.
			var f := float(t) / 20.0
			node.scale = Vector2(base_scale.x * maxf(0.05, 1.0 - 0.75 * f),
					base_scale.y * (1.0 + 0.1 * f))
			if t >= 20:
				st["phase"] = 1
				st["t"] = 0
			return false
		st["y"] = float(st["y"]) - 8.0 * scale
		mon.apply(Vector2(0.0, float(st["y"])))
		if t >= rises:
			node.visible = false
			node.scale = base_scale
			node.pivot_offset = base_pivot
			mon.restore()
			return true
		return false)


# AnimTask_DynamaxGrowth (battle_anim_new.c:8281). args: 0 non-zero for the
# shorter attack variant. Grows over 64 frames, holds 64, snaps back over 8.
static func _dynamax_growth(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var node := _battler_node(vm, AnimStage.ANIM_ATTACKER)
	if node == null:
		return
	var attack_variant: bool = vm.args[0] != 0
	var grow: int = 32 if attack_variant else 64
	var hold: int = 32 if attack_variant else 64
	var base_scale := node.scale
	var base_pivot := node.pivot_offset
	node.pivot_offset = node.size * 0.5
	# The affine deltas are -2 (or -4) per frame against a 0x100 base, and a
	# SMALLER matrix value means a BIGGER sprite.
	var peak := 256.0 / (256.0 - float(4 if attack_variant else 2) * grow)
	var st := {"t": 0, "phase": 0}

	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		var t: int = int(st["t"]) + 1
		st["t"] = t
		match int(st["phase"]):
			0:
				node.scale = base_scale.lerp(base_scale * peak,
						float(t) / float(grow))
				if t >= grow:
					st["phase"] = 1
					st["t"] = 0
			1:
				if t >= hold:
					st["phase"] = 2
					st["t"] = 0
			_:
				node.scale = (base_scale * peak).lerp(base_scale,
						float(t) / 8.0)
				if t >= 8:
					node.scale = base_scale
					node.pivot_offset = base_pivot
					return true
		return false)


# AnimTask_BlendMonInAndOut (battle_anim_mons.c:1673). args: 0 battler,
# 1 colour, 2 peak coefficient, 3 frames per step, 4 cycles. Pulses a mon
# toward a colour and back, N times.
static func _blend_mon_in_and_out(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var node := _battler_node(vm, vm.args[0])
	if node == null:
		return
	var colour := _rgb15_to_color(vm.args[1])
	var peak: int = maxi(1, vm.args[2])
	var delay: int = maxi(1, vm.args[3])
	var cycles: int = maxi(1, vm.args[4])
	var base := node.modulate
	var st := {"coeff": 0, "timer": 0, "out": false, "left": cycles}

	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		st["timer"] = int(st["timer"]) + 1
		if int(st["timer"]) < delay:
			return false
		st["timer"] = 0
		var c: int = int(st["coeff"])
		c += -1 if bool(st["out"]) else 1
		st["coeff"] = c
		node.modulate = base.lerp(colour, clampf(c / 16.0, 0.0, 1.0))
		if c >= peak:
			st["out"] = true
		elif c <= 0 and bool(st["out"]):
			st["out"] = false
			st["left"] = int(st["left"]) - 1
			if int(st["left"]) <= 0:
				node.modulate = base
				return true
		return false)


# AnimShakeMonOrBattlePlatforms (battle_anim_normal.c:940). An invisible
# controller sprite. args: 0 velocity, 1 flip period, 2 total frames,
# 3 type (0/1 = BG axes, 2/3 = mon axes), 4 which battlers.
static func _shake_mon_or_platforms(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var scale := _scale(vm)
	var velocity := float(vm.args[0]) * scale
	var period: int = maxi(0, vm.args[1])
	var total: int = maxi(1, vm.args[2])
	var kind: int = vm.args[3]
	var vertical: bool = kind == 1 or kind == 3

	var targets: Array[MonOffset] = []
	if kind >= 2:
		# SHAKE_MON_*: upstream writes a global sprite-coordinate offset that
		# only battlers with coordOffsetEnabled pick up -- selected by arg 4.
		var sel: int = vm.args[4]
		var battlers: Array[int] = []
		if sel == 2:
			battlers = [AnimStage.ANIM_ATTACKER, AnimStage.ANIM_TARGET]
		elif sel == 0:
			battlers = [AnimStage.ANIM_ATTACKER]
		else:
			battlers = [AnimStage.ANIM_TARGET]
		for b in battlers:
			var n := _battler_node(vm, b)
			if n != null:
				targets.append(MonOffset.new(n))
	# SHAKE_BG_*: writes gBattle_BG3_X/Y, background-layer work owned by
	# M36E. The frames are consumed so timing holds; nothing is drawn.

	var st := {"t": 0, "timer": period, "on": false}
	vm.add_stepper(func() -> bool:
		if int(st["timer"]) > 0:
			st["timer"] = int(st["timer"]) - 1
		else:
			st["timer"] = period
			st["on"] = not bool(st["on"])
			var v := velocity if bool(st["on"]) else 0.0
			for mon in targets:
				mon.apply(Vector2(0.0, v) if vertical else Vector2(v, 0.0))
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) > total:
			for mon in targets:
				mon.restore()
			return true
		return false)


# ── Batch 3 particles ─────────────────────────────────────────────────────

# AnimWallSparkle (battle_anim_psychic.c:670). args: 0/1 offsets, 2 battler,
# 3 ignore-offsets. Static; lives for its cel animation.
static func _wall_sparkle(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var battler: int = AnimStage.ANIM_ATTACKER if vm.args[2] == 0 \
			else AnimStage.ANIM_TARGET
	node.centre = _positioned_centre(vm, battler, vm.args[0], vm.args[1], scale)
	_play_until_anim_ends(vm, node, 24)


# AnimBulletSeed (battle_anim_effects_2.c:1762). Flies to the target over 20
# frames, then SCATTERS on a widening sine for ~16 more.
static func _bullet_seed(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var start := _positioned_centre(vm, AnimStage.ANIM_ATTACKER, vm.args[0],
			vm.args[1], scale)
	var finish_pos := _battler_centre(vm, AnimStage.ANIM_TARGET)
	node.centre = start
	# The scatter parameters are randomised upstream (Random2()); the RANGES
	# are reproduced rather than the exact draws.
	var amp := -(12.0 + randf() * 7.0) * scale
	var speed := (160.0 + randf() * 160.0) / 256.0 * scale
	var st := {"t": 0, "phase": 0, "x": 0.0, "ph": 0.0}

	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var t: int = int(st["t"]) + 1
		st["t"] = t
		if int(st["phase"]) == 0:
			node.centre = start.lerp(finish_pos, minf(1.0, float(t) / 20.0))
			if t >= 20:
				st["phase"] = 1
				st["t"] = 0
			return false
		st["x"] = float(st["x"]) + speed
		st["ph"] = float(st["ph"]) + 8.0
		node.offset = Vector2(float(st["x"]), _gba_sin(float(st["ph"]), amp))
		if float(st["ph"]) > 126.0:
			node.finish()
			return true
		return false)


# AnimSunlight (battle_anim_fire.c:654). No args: a fixed 60-frame sweep
# from the screen's top-left corner toward its centre.
static func _sunlight(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var start := Vector2.ZERO
	var finish_pos := Vector2(140.0, 80.0) * scale
	node.centre = start
	_linear_travel(vm, node, start, finish_pos, 60)


# AnimTask_CreateRaindrops (battle_anim_water.c:623). args: 0 unused,
# 1 spawn interval, 2 total duration. Spawns drops at random screen
# positions; each falls 4px/frame for 13 frames then splashes.
static func _create_raindrops(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var layer: Control = null
	if vm.stage != null and vm.stage.has_method("layer"):
		layer = vm.stage.layer()
	if layer == null:
		return
	var scale := _scale(vm)
	var interval: int = maxi(1, vm.args[1])
	var duration: int = maxi(1, vm.args[2])
	var tmpl := AnimData.template("gRainDropSpriteTemplate")
	var tag := str((tmpl.get("tile_tag", {}) as Dictionary).get("name", ""))
	var st := {"t": 0, "drops": []}

	vm.add_stepper(func() -> bool:
		var t: int = int(st["t"]) + 1
		st["t"] = t
		var alive: Array = []
		for entry in (st["drops"] as Array):
			var e: Dictionary = entry
			var d: AnimSprite = e["node"]
			if not is_instance_valid(d):
				continue
			e["age"] = int(e["age"]) + 1
			if int(e["age"]) <= 13:
				d.offset = Vector2(float(e["age"]) * scale,
						float(e["age"]) * 4.0 * scale)
			d.advance_frame()
			if int(e["age"]) >= 20:
				d.finish()
				continue
			alive.append(e)
		st["drops"] = alive

		if t % interval == 1 and t <= duration and tag != "":
			var drop := AnimSprite.create(vm, tag, 16, 16)
			layer.add_child(drop)
			drop.scale = Vector2.ONE * scale
			drop.centre = Vector2(randf() * layer.size.x,
					randf() * layer.size.y * 0.5)
			var seqs := AnimData.anim_sequences_for("gRainDropSpriteTemplate")
			if not seqs.is_empty():
				drop.play_sequence(seqs[0])
			(st["drops"] as Array).append({"node": drop, "age": 0})

		if t >= duration and (st["drops"] as Array).is_empty():
			return true
		return false)


# AnimDirtScatter (battle_anim_ground.c:197). args: 0/1 offsets, 2 duration.
# Flies to a RANDOM point near the target -- the scatter is randomised
# upstream too, not a fixed spread.
static func _dirt_scatter(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var start := _positioned_centre(vm, AnimStage.ANIM_ATTACKER, vm.args[0],
			vm.args[1], scale)
	var jitter := Vector2(randf_range(-15.0, 16.0), randf_range(-15.0, 16.0))
	var finish_pos := _battler_centre(vm, AnimStage.ANIM_TARGET) \
			+ jitter * scale
	node.centre = start
	_linear_travel(vm, node, start, finish_pos, maxi(1, vm.args[2]))


# AnimRoarNoiseLine (battle_anim_effects_3.c:4090). args: 0/1 offsets,
# 2 direction (0 up, 1 down, else horizontal). Exactly 14 frames at
# 2.5 px/frame.
static func _roar_noise_line(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var sign := _facing(vm)
	node.centre = _battler_centre(vm, AnimStage.ANIM_ATTACKER) \
			+ Vector2(float(vm.args[0]) * sign, float(vm.args[1])) * scale
	var speed := 640.0 / 256.0 * scale
	var vx := speed * sign
	var vy := 0.0
	match vm.args[2]:
		0:
			vy = -speed
		1:
			vy = speed
			node.flip_v = true
		_:
			pass
	var st := {"t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var t: int = int(st["t"]) + 1
		st["t"] = t
		node.offset = Vector2(vx * float(t), vy * float(t))
		if t >= 14:
			node.finish()
			return true
		return false)


# AnimRockFragment (battle_anim_rock.c:410). args: 0/1 offsets, 2/3 travel
# distance, 4 duration, 5 cel anim.
static func _rock_fragment(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	_apply_anim_variant(node, ctx, vm.args[5])
	var start := _battler_centre(vm, AnimStage.ANIM_TARGET) \
			+ Vector2(float(vm.args[0]) * _facing(vm), float(vm.args[1])) \
				* scale
	var finish_pos := start + Vector2(vm.args[2], vm.args[3]) * scale
	node.centre = start
	_linear_travel(vm, node, start, finish_pos, maxi(1, vm.args[4]))


# AnimMoveTwisterParticle (battle_anim_effects_1.c:3964). args: 0 duration,
# 1 rise distance (0xFF = rise forever), 2 wave period, 3 wave amplitude,
# 4 speed-up threshold. Circles the target while rising, passing behind it
# on the far half of the orbit.
static func _move_twister_particle(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	node.centre = _battler_centre(vm, AnimStage.ANIM_TARGET) \
			+ Vector2(0.0, 32.0 * scale)
	var duration: int = maxi(1, vm.args[0])
	var period: float = float(vm.args[2])
	var amplitude: float = float(vm.args[3]) * scale
	var speed_up: int = vm.args[4]
	var st := {"t": 0, "phase": 0.0, "y": 0.0, "left": vm.args[1]}

	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var t: int = int(st["t"])
		if int(st["left"]) == 0xFF:
			st["y"] = float(st["y"]) - 2.0 * scale
		elif int(st["left"]) > 0:
			st["y"] = float(st["y"]) - 2.0 * scale
			st["left"] = int(st["left"]) - 2
		var ph: float = float(st["phase"]) + period
		if (duration - t) < speed_up:
			ph += period
		ph = fmod(ph, _SIN_STEPS)
		st["phase"] = ph
		node.offset = Vector2(_gba_cos(ph, amplitude),
				float(st["y"]) + _gba_sin(ph, 5.0 * scale))
		node.z_index = 1 if ph < 128.0 else -1
		st["t"] = t + 1
		if int(st["t"]) >= duration:
			node.finish()
			return true
		return false)


# AnimFireSpiralOutward (battle_anim_fire.c:788). args: 0/1 offsets,
# 2 spiral duration, 3 initial invisible wait. Spirals outward at a growing
# radius, ~14 degrees per frame.
static func _fire_spiral_outward(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	node.centre = _positioned_centre(vm, AnimStage.ANIM_ATTACKER, vm.args[0],
			vm.args[1], scale)
	node.visible = false
	var wait: int = maxi(0, vm.args[3])
	var spiral: int = maxi(1, vm.args[2])
	var st := {"t": 0, "phase": 0.0, "radius": 0.0, "started": false}

	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		var t: int = int(st["t"]) + 1
		st["t"] = t
		if not bool(st["started"]):
			if t >= wait:
				st["started"] = true
				st["t"] = 0
				node.visible = true
			return false
		st["radius"] = float(st["radius"]) + 0xD0 / 256.0 * scale
		var ph: float = st["phase"]
		node.offset = Vector2(_gba_sin(ph, float(st["radius"])),
				_gba_cos(ph, float(st["radius"])))
		st["phase"] = fmod(ph + 10.0, _SIN_STEPS)
		if t > spiral:
			node.finish()
			return true
		return false)


# AnimProtect (battle_anim_effects_1.c:5230). args: 0/1 offsets, 2 hold.
# The shield fades in, drifts slowly left, then fades out. Upstream drives
# this through the global blend registers plus a rotating palette; alpha and
# a slow drift are the closest equivalent without palette indirection.
static func _protect(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	node.centre = _battler_centre(vm, AnimStage.ANIM_ATTACKER) \
			+ Vector2(vm.args[0], vm.args[1]) * scale
	var hold: int = maxi(1, vm.args[2])
	var st := {"t": 0, "x": 0.0, "phase": 0}
	node.modulate.a = 0.0

	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["x"] = float(st["x"]) - 96.0 / 256.0 * scale
		node.offset = Vector2(float(st["x"]), 0.0)
		var t: int = int(st["t"]) + 1
		st["t"] = t
		if int(st["phase"]) == 0:
			node.modulate.a = clampf(float(t) / 20.0, 0.0, 0.6)
			if t >= hold:
				st["phase"] = 1
				st["t"] = 0
			return false
		node.modulate.a = clampf(0.6 - float(t) / 20.0, 0.0, 0.6)
		if t >= 20:
			node.finish()
			return true
		return false)


# AnimRevengeScratch (battle_anim_fight.c:992). args: 0/1 offsets,
# 2 battler. Pure cel animation.
static func _revenge_scratch(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var battler: int = AnimStage.ANIM_ATTACKER if vm.args[2] == 0 \
			else AnimStage.ANIM_TARGET
	node.centre = _positioned_centre(vm, battler, vm.args[0], vm.args[1],
			scale)
	_play_until_anim_ends(vm, node, 20)


# AnimAssistPawprint (battle_anim_effects_3.c:4317). args: 0/1 ABSOLUTE
# screen start, 2/3 absolute destination, 4 duration. The one callback here
# that works in screen space rather than battler-relative space.
static func _assist_pawprint(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var start := Vector2(vm.args[0], vm.args[1]) * scale
	var finish_pos := Vector2(vm.args[2], vm.args[3]) * scale
	node.centre = start
	_linear_travel(vm, node, start, finish_pos, maxi(1, vm.args[4]))


# InitSwirlingFogAnim (battle_anim_ice.c:959). args: 0/1 offsets, 2 y drift,
# 3 duration, 4 battler, 5 average-positions flag. Travels while swirling;
# the swirl is ADDED on top of the linear motion, and the sprite passes
# behind the mon on half the orbit. Note this is a pure sprite -- the
# BG-layer fog is a different function (AnimTask_HazeScrollingFog, M36E).
static func _swirling_fog(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var battler: int = AnimStage.ANIM_TARGET if vm.args[4] == 1 \
			else AnimStage.ANIM_ATTACKER
	var start := _positioned_centre(vm, battler, vm.args[0], vm.args[1], scale)
	var finish_pos := start + Vector2(0.0, float(vm.args[2]) * scale)
	var duration: int = maxi(1, vm.args[3])
	var radius := (64.0 if vm.args[5] != 0 else 32.0) * scale
	node.centre = start
	var st := {"t": 0, "phase": 64.0}

	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var t: int = int(st["t"]) + 1
		st["t"] = t
		if t >= duration:
			node.finish()
			return true
		node.centre = start.lerp(finish_pos, float(t) / float(duration))
		var ph: float = st["phase"]
		node.offset = Vector2(_gba_sin(ph, radius), _gba_cos(ph, -6.0 * scale))
		node.z_index = 1 if ((int(ph) - 64) & 0xFF) <= 0x7F else -1
		st["phase"] = fmod(ph + 3.0, _SIN_STEPS)
		return false)
