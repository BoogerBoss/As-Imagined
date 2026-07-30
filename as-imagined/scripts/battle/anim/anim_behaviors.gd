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
		# — [M36D batch 6] move-targeted: the remaining blocked iconic set —
		"AnimTask_SetAllNonAttackersInvisiblity": _set_all_non_attackers_invisible,
		"AnimIceBeamParticle": _ice_beam_particle,
		"AnimIceEffectParticle": _ice_effect_particle,
		"AnimMoveParticleBeyondTarget": _particle_beyond_target,
		"AnimSwirlingSnowball": _swirling_snowball,
		"AnimThrowProjectile": _throw_projectile,
		"AnimWaterGunDroplet": _water_gun_droplet,
		"AnimAuroraBeamRings": _aurora_beam_rings,
		"AnimTask_RotateAuroraRingColors": _rotate_aurora_ring_colors,
		"AnimSparkElectricityFlashing": _spark_electricity_flashing,
		"AnimThunderboltOrb": _thunderbolt_orb,
		"AnimSolarBeamBigOrb": _solar_beam_big_orb,
		"AnimTask_CreateSmallSolarBeamOrbs": _create_small_solar_beam_orbs,
		"AnimSolarBeamSmallOrb": _solar_beam_small_orb,
		"AnimBowMon": _bow_mon,
		"AnimTask_DrillPeckHitSplats": _drill_peck_hit_splats,
		"AnimFireCross": _fire_cross,
		"AnimFireRing": _fire_ring,
		"AnimWaterPulseBubble": _water_pulse_bubble,
		"AnimWaterPulseRing": _water_pulse_ring,
		"AnimOrbitFast": _orbit_fast,
		"AnimOrbitScatter": _orbit_scatter,
		"AnimTauntFinger": _taunt_finger,
		"AnimThoughtBubble": _thought_bubble,
		"AnimSludgeBombHitParticle": _sludge_bomb_hit_particle,
		"AnimSludgeProjectile": _sludge_projectile,
		"AnimDirtPlumeParticle": _dirt_plume_particle,
		"AnimTask_PositionFissureBgOnBattler": _position_fissure_bg,
		"AnimDigDirtMound": _dig_dirt_mound,
		"AnimTask_DigDownMovement": _dig_down_movement,
		"AnimTask_DigUpMovement": _dig_up_movement,
		# — [M36D batch 5] water / ice —
		"AnimTask_FrozenIceCube": _frozen_ice_cube,
		"AnimTask_FrozenIceCubeAttacker": _frozen_ice_cube_attacker,
		"AnimTask_CentredFrozenIceCube": _frozen_ice_cube_centred,
		"AnimSmallBubblePair": _small_bubble_pair,
		"AnimSmallDriftingBubbles": _small_drifting_bubbles,
		# — [M36D batch 5] electric —
		"AnimTask_ElectricBolt": _electric_bolt,
		"AnimElectricBoltSegment": _electric_bolt_segment,
		"AnimElectricity": _electricity,
		"AnimThunderWave": _thunder_wave,
		# — [M36D batch 5] beams / orbs / charge —
		"AnimHyperBeamOrb": _hyper_beam_orb,
		"AnimSwordsDanceBlade": _swords_dance_blade,
		"AnimPsychoBoost": _psycho_boost,
		"AnimGrowingChargeOrb": _growing_charge_orb,
		"AnimElectricPuff": _electric_puff,
		# — [M36D batch 5] palette / flash —
		"AnimTask_BlendBattleAnimPalExclude": _blend_pal_exclude,
		"AnimTask_FlashAnimTagWithColor": _flash_anim_tag_with_color,
		"AnimFlashingHitSplat": _flashing_hit_splat,
		# — [M36D batch 5] the tail —
		"AnimTask_SkillSwap": _skill_swap,
		"AnimTask_HeartSwap": _skill_swap,
		"AnimFollowMeFinger": _follow_me_finger,
		"AnimFocusPunchFist": _focus_punch_fist,
		"AnimTask_StockpileDeformMon": _stockpile_deform_mon,
		"AnimTask_SpitUpDeformMon": _stockpile_deform_mon,
		"AnimTask_SwallowDeformMon": _stockpile_deform_mon,
		"AnimGrantingStars": _granting_stars,
		"AnimSweetScentPetal": _sweet_scent_petal,
		"AnimTask_GrudgeFlames": _grudge_flames,
		"AnimTask_StatusClearedEffect": _status_cleared_effect,
		"AnimArmThrustHit": _arm_thrust_hit,
		"AnimTask_Splash": _splash,
		"AnimUproarRing": _uproar_ring,
		"AnimSpinningSparkle": _spinning_sparkle,
		"AnimLeer": _leer,
		"AnimTearDrop": _tear_drop,
		"AnimTask_StretchTargetUp": _stretch_target_up,
		"AnimTask_StretchAttackerUp": _stretch_attacker_up,
		"AnimTask_TeeterDanceMovement": _teeter_dance_movement,
		"AnimAngerMark": _anger_mark,
		"SpriteCB_LockingJaw": _locking_jaw,
		# — [M36D batch 4] physical strikes —
		"AnimFistOrFootRandomPos": _fist_or_foot_random_pos,
		"AnimSpinningKickOrPunch": _spinning_kick_or_punch,
		"AnimSlidingKick": _sliding_kick,
		"AnimTask_AttackerPunchWithTrace": _attacker_punch_with_trace,
		"AnimKnockOffStrike": _knock_off_strike,
		"SpriteCB_LashOutStrike": _knock_off_strike,
		"AnimFang": _wait_for_anim_end,
		"AnimWhipHit_WaitEnd": _wait_for_anim_end,
		"AnimNeedleArmSpike": _needle_arm_spike,
		"SpriteCB_MindBlownExplosion": _mind_blown_explosion,
		"AnimSlashSlice": _slash_slice,
		"SpriteCB_RandomCentredHits": _random_centred_hits,
		# — [M36D batch 4] linear-translation projectiles (one shape) —
		"AnimPowerAbsorptionOrb": _power_absorption_orb,
		"AnimRaiseSprite": _raise_sprite,
		"AnimAirWaveCrescent": _air_wave_crescent,
		"AnimDragonFireToTarget": _dragon_fire_to_target,
		"AnimFlyingSandCrescent": _flying_sand_crescent,
		"AnimMimicOrb": _mimic_orb,
		# — [M36D batch 4] mon-visual tasks —
		"AnimTask_SlideOffScreen": _slide_off_screen,
		"AnimTask_MonToSubstitute": _mon_to_substitute,
		"AnimTask_RolePlaySilhouette": _role_play_silhouette,
		# — [M36D batch 4] status / other —
		"AnimTask_SporeDoubleBattle": _spore_double_battle,
		"AnimSleepLetterZ": _sleep_letter_z,
		"AnimTask_GetReturnPowerLevel": _get_return_power_level,
		"AnimConstrictBinding": _constrict_binding,
		"AnimRecycle": _recycle,
		# — [M36E3] background-dependent —
		"AnimTask_CreateSurfWave": _create_surf_wave,
		"AnimTask_SetPsychicBackground": _set_psychic_background,
		"AnimTask_FadeScreenToWhite": _fade_screen_to_white,
		"AnimTask_StartSlidingBg": _start_sliding_bg,
		"AnimTask_UpdateSlidingBg": _update_sliding_bg,
		"AnimTask_ShakePlatforms": _shake_platforms,
		"AnimTask_HazeScrollingFog": _haze_scrolling_fog,
		"AnimTask_MistBallFog": _haze_scrolling_fog,
		"AnimTask_LoadSandstormBackground": _load_sandstorm_background,
		"AnimTask_LoadWindstormBackground": _load_windstorm_background,
		"AnimTask_MetallicShine": _metallic_shine,
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
	_run_blend_nodes(vm, _blend_nodes(vm, selector), delay, start_coeff,
			target_coeff, rgb15)


# The blend ramp itself, over an explicit node set. Split out so the
# exclude-variant can supply "everything but one battler" without duplicating
# the walk.
#
# The blend ramp, over an explicit node set. Split out so the exclude-variant
# can supply "everything but one battler" without duplicating the walk.
#
# This blends through a SHADER, not `modulate`, and the difference is not
# cosmetic. BlendPalette (util.c:224) REPLACES a channel toward the target;
# `modulate` MULTIPLIES. Multiplying a white-modulated sprite toward white is
# the identity, so every blend toward white rendered as nothing at all --
# measured across the extracted scripts as 126 of 777 blend sites, with pure
# white the second most common blend colour in the whole roster after black.
# Another 141 sites toward other light colours were visibly weakened.
#
# This is the third time this project has hit the modulate-multiply trap, after
# the twice-invisible recall pink and MetallicShine's no-op grayscale, so the
# fix is the same `mix()` shader the second of those introduced.
static func _run_blend_nodes(vm: AnimScriptVM, nodes: Array[Control],
		delay: int, start_coeff: int, target_coeff: int,
		rgb15: int) -> void:
	var colour := _rgb15_to_color(rgb15)
	var st := {"coeff": start_coeff, "timer": 0}
	var step_delay: int = maxi(0, delay)

	vm.add_stepper(func() -> bool:
		if int(st["timer"]) < step_delay:
			st["timer"] = int(st["timer"]) + 1
			return false
		st["timer"] = 0
		var c: int = int(st["coeff"])
		for n in nodes:
			if is_instance_valid(n):
				_apply_blend_amount(n, colour, clampf(c / 16.0, 0.0, 1.0))
		if c < target_coeff:
			st["coeff"] = c + 1
			return false
		if c > target_coeff:
			st["coeff"] = c - 1
			return false
		# A ramp that lands on 0 has blended fully back; drop the material so
		# nothing is left shadered for the rest of the battle.
		if c == 0:
			for n in nodes:
				if is_instance_valid(n):
					_clear_blend(n)
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

	# One "blend" is a full up-and-down sweep; the coefficient walks 1 step
	# every (delay + 1) frames, exactly as the reference's stepper does.
	var st := {"coeff": low, "dir": 1, "left": cycles, "timer": 0}
	vm.add_stepper(func() -> bool:
		if int(st["timer"]) < delay:
			st["timer"] = int(st["timer"]) + 1
			return false
		st["timer"] = 0
		var c: int = int(st["coeff"])
		for n in nodes:
			if is_instance_valid(n):
				_apply_blend_amount(n, colour, clampf(c / 16.0, 0.0, 1.0))
		c += int(st["dir"])
		if c >= high and int(st["dir"]) > 0:
			c = high
			st["dir"] = -1
		elif c <= low and int(st["dir"]) < 0:
			c = low
			st["dir"] = 1
			st["left"] = int(st["left"]) - 1
			if int(st["left"]) <= 0:
				for n2 in nodes:
					if is_instance_valid(n2):
						_clear_blend(n2)
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
			# Routed through the VM so the hide is registered and undone when
			# the animation ends -- upstream the engine's own visibility
			# re-sync brings the mon back, and nothing else here would.
			vm.hide_battler(AnimStage.ANIM_ATTACKER)
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


static func _attacker_is_player(vm: AnimScriptVM) -> bool:
	if vm.stage != null and vm.stage.has_method("attacker_is_player_side"):
		return bool(vm.stage.attacker_is_player_side())
	return true


static func _attacker_index(vm: AnimScriptVM) -> int:
	return AnimStage.ANIM_ATTACKER


# ─── [M36E3] background-dependent behaviors ───────────────────────────────
#
# These are the tasks M36D's own coverage pass identified as gated on the
# background layer rather than on more sprite work. The layer itself and its
# six opcodes landed in M36E2; this is the half that drives them.


# AnimTask_SetPsychicBackground (battle_anim_effects_3.c:1446, step at :1452).
#
# It loads NO background and writes no scroll register -- the whole effect is a
# palette CYCLE on the background the script's own `fadetobg BG_PSYCHIC`
# already installed. Every 4th frame it rotates entries 1..11 of the BG palette
# upward by one, so the ramp appears to flow; period is 11 * 4 = 44 frames.
#
# Two things about its bookkeeping are load-bearing. It decrements the visual
# task count at setup rather than calling DestroyAnimVisualTask, so a following
# `waitforvisualfinish` does NOT wait for it -- hence counts=false. And it is
# UNBOUNDED: it runs until the script sets arg 7 to -1 (`UnsetPsychicBg` does
# `restorebg` / `waitbgfadeout` / `setarg 7, -1`), which is why the stepper
# watches the register instead of a frame count.
#
# 32 sites reach this via `call SetPsychicBackground`, plus 2 direct ones.
static func _set_psychic_background(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	_palette_cycle_common(vm)


# AnimTask_FadeScreenToWhite (battle_anim_effects_3.c:1471). Byte-identical to
# the above except it rotates gPlttBufferUnfaded too, so the cycle survives a
# subsequent screen fade. This port has no faded/unfaded split (there is one
# texture and one fade overlay), so the two collapse to the same behavior --
# recorded here rather than left looking like a copy-paste.
static func _fade_screen_to_white(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	_palette_cycle_common(vm)


const _PALETTE_CYCLE_PERIOD := 4
const _PALETTE_CYCLE_FIRST := 1
const _PALETTE_CYCLE_COUNT := 11


static func _palette_cycle_common(vm: AnimScriptVM,
		count: int = _PALETTE_CYCLE_COUNT,
		period: int = _PALETTE_CYCLE_PERIOD) -> void:
	var stage = vm.stage
	if stage == null or not stage.has_method("set_background_palette_remap"):
		return
	var bg_name: String = vm.current_background_name()
	var pal: PackedColorArray = AnimData.background_palette(bg_name)
	if pal.size() < _PALETTE_CYCLE_FIRST + count:
		# No palette for this background (an unpulled or code-referenced one).
		# The cycle is purely cosmetic, so skip it -- but still register an
		# uncounted stepper so nothing about the script's own timing changes.
		var _idle := func() -> bool:
			return vm.args[AnimScriptVM.ARG_RET] == -1
		vm.add_stepper(_idle, false)
		return

	var from_colors := PackedColorArray()
	for i in range(count):
		from_colors.append(pal[_PALETTE_CYCLE_FIRST + i])

	var st := {"timer": 0, "step": 0}
	var _step := func() -> bool:
		if vm.args[AnimScriptVM.ARG_RET] == -1:
			if stage.has_method("clear_background_palette_remap"):
				stage.clear_background_palette_remap()
			return true
		st["timer"] = int(st["timer"]) + 1
		if int(st["timer"]) < period:
			return false
		st["timer"] = 0
		st["step"] = (int(st["step"]) + 1) % count
		stage.set_background_palette_remap(
				from_colors, _rotated_palette(from_colors, int(st["step"])))
		return false
	vm.add_stepper(_step, false)


# Slot j of the rotated palette shows the colour that was `steps` slots below
# it, wrapping within the 11-entry window: faded[i+1] = faded[i] applied
# `steps` times, with faded[first] taking the old last colour each pass.
static func _rotated_palette(base: PackedColorArray,
		steps: int) -> PackedColorArray:
	var out := PackedColorArray()
	var n := base.size()
	if n <= 0:
		return out
	for j in range(n):
		out.append(base[posmod(j - steps, n)])
	return out


# AnimTask_StartSlidingBg / AnimTask_UpdateSlidingBg
# (battle_anim_utility_funcs.c:704 / :723).
#
# Scrolls whatever background `fadetobg` already installed -- it loads nothing
# itself. Args, documented in-source at :700-703:
#   [0] X velocity, 8.8 fixed point (256 = 1 px/frame)
#   [1] Y velocity, same
#   [2] mirror flag: negate both when the attacker is on the opponent side
#   [3] the sentinel value compared against arg 7 to stop (always -1 in the
#       scripts, paired with a later `setarg 7, -1`)
#
# The starter spawns a separate uncounted task and immediately destroys itself,
# so `waitforvisualfinish` never waits for the scroll -- reproduced by
# registering the updater as an uncounted stepper and returning at once.
#
# The 8.8 accumulator matters: only whole pixels are applied and the fraction
# is kept, so a velocity below 256 still scrolls, just slower than one pixel a
# frame. Truncating instead would freeze every slow scroll outright.
static func _start_sliding_bg(vm: AnimScriptVM, ctx: Dictionary) -> void:
	_sliding_bg_common(vm, ctx)


# Reached only if a script creates the updater directly. Same body -- the
# starter is a thin wrapper upstream too.
static func _update_sliding_bg(vm: AnimScriptVM, ctx: Dictionary) -> void:
	_sliding_bg_common(vm, ctx)


static func _sliding_bg_common(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var stage = vm.stage
	if stage == null or not stage.has_method("scroll_background_by"):
		return
	var vel_x: int = vm.args[0]
	var vel_y: int = vm.args[1]
	if vm.args[2] != 0 and not _attacker_is_player(vm):
		vel_x = -vel_x
		vel_y = -vel_y
	var sentinel: int = vm.args[3]
	var scale: float = _scale(vm)
	var st := {"ax": 0, "ay": 0}

	var _step := func() -> bool:
		if vm.args[AnimScriptVM.ARG_RET] == sentinel:
			stage.set_background_scroll(Vector2.ZERO)
			return true
		st["ax"] = int(st["ax"]) + vel_x
		st["ay"] = int(st["ay"]) + vel_y
		var step := Vector2(int(st["ax"]) >> 8, int(st["ay"]) >> 8)
		st["ax"] = int(st["ax"]) & 0xFF
		st["ay"] = int(st["ay"]) & 0xFF
		if step != Vector2.ZERO:
			stage.scroll_background_by(step * scale)
		return false
	vm.add_stepper(_step, false)


# AnimTask_ShakePlatforms (battle_anim_ground.c:613), entered from
# AnimTask_HorizontalShake (:568) when arg0 == ANIM_OPPONENT_LEFT (5).
#
# The sprite variants of this shake already work; this is the path that shakes
# the terrain layer instead, and it is the only one of these tasks that neither
# loads nor scrolls an image -- it just offsets BG3's X.
#
# Args: [1] intensity (0 -> gAnimMovePower / 10), [2] duration.
# Amplitude is intensity + 3. The register updates every SECOND frame, not
# every frame, alternating sign; after `duration` updates it rings down, 4
# updates (8 frames) per amplitude step, until the amplitude reaches 0. The
# captured starting offset is restored EXACTLY -- not zeroed -- because the
# background may legitimately be mid-scroll when the shake begins.
static func _shake_platforms(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var stage = vm.stage
	if stage == null or not stage.has_method("set_background_scroll"):
		return
	var intensity: int = vm.args[1]
	if intensity == 0:
		intensity = int(vm.move_power / 10.0)
	var amplitude: int = intensity + 3
	var max_time: int = maxi(1, vm.args[2])
	var scale: float = _scale(vm)
	var initial: Vector2 = stage.background_scroll()

	var st := {"state": 0, "delay": 0, "timer": 0, "amp": amplitude}
	vm.add_stepper(func() -> bool:
		st["delay"] = int(st["delay"]) + 1
		if int(st["delay"]) <= 1:
			return false
		st["delay"] = 0
		var offset: int = int(st["amp"]) if int(st["state"]) > 0 else amplitude
		var sign_ := 1.0 if (int(st["timer"]) & 1) == 0 else -1.0
		stage.set_background_scroll(
				initial + Vector2(offset * sign_ * scale, 0.0))
		st["timer"] = int(st["timer"]) + 1
		if int(st["state"]) == 0:
			if int(st["timer"]) >= max_time:
				st["timer"] = 0
				st["amp"] = int(st["amp"]) - 1
				st["state"] = 1
			return false
		if int(st["timer"]) >= 4:
			st["timer"] = 0
			st["amp"] = int(st["amp"]) - 1
			if int(st["amp"]) <= 0:
				stage.set_background_scroll(initial)
				return true
		return false)


# AnimTask_HazeScrollingFog (battle_anim_ice.c:1049) and its twin
# AnimTask_MistBallFog (:1154), which load the same three assets.
#
# This is the one asset pairing M36E1 could not resolve: `fog.bin` has no
# `fog.png` beside it, because the tilemap is paired with the FIELD-WEATHER
# tiles -- gWeatherFogHorizontalTiles (graphics/weather/fog_horizontal.png)
# with gFogPalette (graphics/weather/fog.pal), a cross-directory pairing
# nothing in the backgrounds directory hints at. That is why E1 removed the
# orphan rather than guessing.
#
# Reads no args. Scrolls 1 px/frame left, forever, through a three-phase alpha
# ramp: 76 frames in (sHazeBlendAmounts, :330, stepped every 4th frame), 81
# holding, 36 out -- about 194 frames total. Blend is BG-layer only.
static func _haze_scrolling_fog(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var stage = vm.stage
	if stage == null or not stage.has_method("scroll_background_by"):
		return
	var scale: float = _scale(vm)
	var had_bg: bool = stage.has_method("set_background") \
			and AnimData.has_background("FOG")
	if had_bg:
		stage.set_background("FOG")
		vm.notify_background_changed()

	var st := {"phase": 0, "timer": 0, "idx": 0, "blend": 0}
	vm.add_stepper(func() -> bool:
		stage.scroll_background_by(Vector2(-1.0 * scale, 0.0))
		st["timer"] = int(st["timer"]) + 1
		match int(st["phase"]):
			0:
				if int(st["timer"]) >= 4:
					st["timer"] = 0
					st["idx"] = int(st["idx"]) + 1
					var i: int = mini(int(st["idx"]),
							_HAZE_BLEND_AMOUNTS.size() - 1)
					st["blend"] = _HAZE_BLEND_AMOUNTS[i]
					_apply_haze_blend(stage, int(st["blend"]))
					if int(st["blend"]) >= 9:
						st["phase"] = 1
						st["timer"] = 0
			1:
				if int(st["timer"]) >= 81:
					st["phase"] = 2
					st["timer"] = 0
			2:
				if int(st["timer"]) >= 4:
					st["timer"] = 0
					st["blend"] = int(st["blend"]) - 1
					_apply_haze_blend(stage, int(st["blend"]))
					if int(st["blend"]) <= 0:
						if stage.has_method("clear_background"):
							stage.clear_background()
						stage.set_background_scroll(Vector2.ZERO)
						return true
		return false)


# sHazeBlendAmounts (battle_anim_ice.c:330), verbatim -- deliberately not a
# computed ramp, because it is not linear (it plateaus on 2, 4 and 6).
const _HAZE_BLEND_AMOUNTS: Array[int] = [
	0, 1, 2, 2, 2, 2, 3, 4, 4, 4, 5, 6, 6, 6, 6, 7, 8, 8, 8, 9]


static func _apply_haze_blend(stage, blend: int) -> void:
	var node = stage.background_layer() if stage.has_method(
			"background_layer") else null
	if node != null:
		node.modulate.a = clampf(blend / 16.0, 0.0, 1.0)


# AnimTask_LoadSandstormBackground (battle_anim_rock.c:478) and
# AnimTask_LoadWindstormBackground (battle_anim_flying.c:1239). Unlike the
# tasks above these DO load their own background: the same Sandstorm gfx and
# tilemap, differing only in which palette is applied -- which the extraction
# has already baked, so the two resolve to different pulled assets here rather
# than to a runtime palette swap.
#
# arg0 mirrors the scroll for an opponent-side attacker. Steps
# gBattle_BG1_X += ±6 and gBattle_BG1_Y += -1 every frame, unbounded.
static func _load_sandstorm_background(vm: AnimScriptVM, ctx: Dictionary) -> void:
	_storm_background_common(vm, ctx, "SANDSTORM_BREW")


static func _load_windstorm_background(vm: AnimScriptVM, ctx: Dictionary) -> void:
	_storm_background_common(vm, ctx, "SANDSTORM_BREW")


static func _storm_background_common(vm: AnimScriptVM, _ctx: Dictionary,
		bg_name: String) -> void:
	var stage = vm.stage
	if stage == null or not stage.has_method("scroll_background_by"):
		return
	if stage.has_method("set_background") and AnimData.has_background(bg_name):
		stage.set_background(bg_name)
		vm.notify_background_changed()
	var dir := 1.0 if _attacker_is_player(vm) else -1.0
	var scale: float = _scale(vm)
	if vm.args[0] == 0:
		dir = 1.0
	var _step := func() -> bool:
		if vm.args[AnimScriptVM.ARG_RET] == -1:
			stage.set_background_scroll(Vector2.ZERO)
			if stage.has_method("clear_background"):
				stage.clear_background()
			return true
		stage.scroll_background_by(Vector2(6.0 * dir * scale, -1.0 * scale))
		return false
	vm.add_stepper(_step, false)


# AnimTask_MetallicShine (battle_anim_dark.c:906, step at :972).
#
# The one task here that is a MASK effect rather than a background one: BG1
# carries the metal_shine sheet and a ST_OAM_OBJ_WINDOW clone of the attacker's
# sprite acts as the stencil, so the sweep is only ever visible INSIDE the
# mon's silhouette. Nothing is drawn behind or in front of the battler.
#
# CMD_ARGS(permanent, useColor, color):
#   [0] permanent -- if 0, the grayscale/tint is undone at the second sweep
#   [1] useColor  -- 0 grayscales the mon, nonzero blends toward [2] at 11/16
#   [2] color     -- the tint (Poison Tail passes RGB(24,6,23))
#
# 96 frames: three 32-frame sweeps of 4 px/frame (128/4), with BG1_X snapping
# back by +128 at each boundary so the sweep repeats. The palette change is
# reverted at the end of sweep 2, and the mask is torn down there too -- sweep
# 3 is 32 frames during which nothing is visible, which is real and is why the
# duration must not be shortened to 64.
#
# There is no OBJWIN equivalent here, so the silhouette is reproduced with a
# duplicate of the battler's own texture used as a mask over a scrolling
# gradient. Recorded as an approximation of the MECHANISM, not of the maths:
# every frame count, direction and phase boundary below is source-exact.
static func _metallic_shine(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var node := _battler_node(vm, _attacker_index(vm))
	if node == null:
		return
	var permanent: bool = vm.args[0] != 0
	var use_color: bool = vm.args[1] != 0
	var tint: Color = _gba_rgb_to_color(vm.args[2])
	var scale: float = _scale(vm)

	# The palette change the mask sweeps over: grayscale, or an 11/16 blend
	# toward the requested colour (BlendPalette's own coefficient).
	#
	# This CANNOT go through `modulate`. modulate MULTIPLIES the sprite's own
	# colours, so grayscaling a default (1,1,1) modulate yields (1,1,1) --
	# literally no change, which is what this project already learned the hard
	# way in [M26B3-6a] when the recall's pink tint came out invisible twice.
	# Source's SetGrayscaleOrOriginalPalette REPLACES each palette entry with
	# its own (r+g+b)/3, and BlendPalette at coeff 11/16 replaces most of the
	# channel, so the equivalent here is a real per-pixel shader.
	var prior_material: Material = node.material
	_apply_recolor(node, use_color, tint)

	var shine := _make_shine_overlay(vm, node)
	var st := {"x": 0.0, "swept": 0, "reverted": false}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			if is_instance_valid(shine):
				shine.queue_free()
			return true
		st["x"] = float(st["x"]) + 4.0
		if is_instance_valid(shine):
			var span := node.size.x + 128.0 * scale
			shine.position.x = -128.0 * scale + fposmod(
					float(st["x"]) * scale, span)
		if fmod(float(st["x"]), 128.0) == 0.0:
			st["swept"] = int(st["swept"]) + 1
			if int(st["swept"]) == 2 and not bool(st["reverted"]):
				st["reverted"] = true
				if not permanent:
					node.material = prior_material
				if is_instance_valid(shine):
					shine.queue_free()
			if int(st["swept"]) >= 3:
				if not permanent:
					node.material = prior_material
				if is_instance_valid(shine):
					shine.queue_free()
				return true
		return false)


# A real colour REPLACEMENT, not a multiply. `gray` desaturates each pixel to
# its own (r+g+b)/3 (source's SetGrayscaleOrOriginalPalette); `tint_amount`
# mixes toward `tint` (source's BlendPalette, whose 11/16 coefficient replaces
# most of the channel rather than shading it).
const _RECOLOR_SHADER_CODE := """
shader_type canvas_item;
uniform float gray : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(1.0);
uniform float tint_amount : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float lum = (c.r + c.g + c.b) / 3.0;
	c.rgb = mix(c.rgb, vec3(lum), gray);
	c.rgb = mix(c.rgb, tint.rgb, tint_amount);
	COLOR = c;
}
"""

static var _recolor_shader: Shader = null


static func _apply_recolor(node: CanvasItem, use_color: bool,
		tint: Color) -> void:
	if _recolor_shader == null:
		_recolor_shader = Shader.new()
		_recolor_shader.code = _RECOLOR_SHADER_CODE
	var mat := ShaderMaterial.new()
	mat.shader = _recolor_shader
	if use_color:
		mat.set_shader_parameter("gray", 0.0)
		mat.set_shader_parameter("tint", tint)
		mat.set_shader_parameter("tint_amount", 11.0 / 16.0)
	else:
		mat.set_shader_parameter("gray", 1.0)
		mat.set_shader_parameter("tint_amount", 0.0)
	node.material = mat


# The stencil: a copy of the battler's own texture, tinted white and additively
# blended, standing in for the OBJWIN mask upstream builds from a
# ST_OAM_OBJ_WINDOW sprite clone.
static func _make_shine_overlay(vm: AnimScriptVM, node: Control) -> Control:
	var tex: Texture2D = null
	if node is TextureRect:
		tex = (node as TextureRect).texture
	if tex == null:
		return null
	var shine := TextureRect.new()
	shine.texture = tex
	shine.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shine.stretch_mode = TextureRect.STRETCH_SCALE
	shine.size = node.size
	shine.modulate = Color(1.0, 1.0, 1.0, 0.55)
	shine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	shine.material = mat
	node.add_child(shine)
	vm.notify_spawned(shine)
	vm.notify_finished(shine)
	return shine


# A GBA RGB15 literal (RGB(r,g,b), 5 bits each) as a Color.
# GBA RGB15 -> Color. Kept as a thin alias: _rgb15_to_color predates it and is
# the same conversion, so this exists only so the batch-4/5 call sites read in
# their own source's vocabulary.
static func _gba_rgb_to_color(packed: int) -> Color:
	return _rgb15_to_color(packed)


# AnimTask_CreateSurfWave (battle_anim_water.c:985, steps at :1077 / :1120).
#
# THE headline move of this sub-tier: Surf has been sitting one behavior short
# of playable since M36D, and it is 100% background work -- no sprite motion at
# all, which is exactly why no amount of further sprite porting reached it.
#
# arg0 selects the palette variant (SURF / MUDDY_WATER / SLUDGE_WAVE). The
# tilemap is side-dependent -- gBattleAnimBgTilemap_SurfPlayer vs _SurfOpponent
# -- so the wave sweeps toward whoever is being hit; the extraction already
# baked both, plus the muddy recolor, as separate assets.
#
# Initial offset and velocity, per side (:1044-1059):
#   player-side attacker:   X 0,    Y -48,  velocity (-2, +1)
#   opponent-side attacker: X -224, Y 256,  velocity (+2, -1)
# So the wave always travels diagonally, and mirrored -- getting the sign wrong
# would send it away from the target rather than over it.
#
# Two effects run on top of the scroll. Every 4th frame it rotates palette
# entries 1..7 upward by one (:1090-1097) -- the same mechanism as the psychic
# background above, with a 7-entry window instead of 11, which is what makes
# the water look like it is moving rather than sliding. And a blend ramps in
# over the first ~26 frames, holds, then ramps out (:1099-1113), which is what
# ends the animation: roughly 134 frames total.
#
# DISCLOSED UNPORTED: AnimTask_SurfWaveScanlineEffect (:1140) is an HBlank
# per-scanline horizontal offset -- a hardware raster trick that gives the wave
# its rippled edge. There is no scanline hook to port it to here, so the wave
# is a clean diagonal sweep rather than a rippled one. The scroll, the palette
# cycle, the blend ramp and every frame count ARE ported.
static func _create_surf_wave(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var stage = vm.stage
	if stage == null or not stage.has_method("scroll_background_by"):
		return
	var player_side: bool = _attacker_is_player(vm)
	var bg_name := _surf_background_name(vm.args[0], player_side)
	if bg_name != "" and stage.has_method("set_background"):
		if stage.set_background(bg_name):
			vm.notify_background_changed()
	var scale: float = _scale(vm)
	var vel := Vector2(-2.0, 1.0) if player_side else Vector2(2.0, -1.0)
	var start := Vector2(0.0, -48.0) if player_side else Vector2(-224.0, 256.0)
	stage.set_background_scroll(start * scale)

	# The 7-entry palette cycle, reusing the psychic mechanism.
	var pal: PackedColorArray = AnimData.background_palette(bg_name)
	var from_colors := PackedColorArray()
	if pal.size() >= _SURF_CYCLE_FIRST + _SURF_CYCLE_COUNT:
		for i in range(_SURF_CYCLE_COUNT):
			from_colors.append(pal[_SURF_CYCLE_FIRST + i])

	var layer = stage.background_layer() if stage.has_method(
			"background_layer") else null
	var st := {"frame": 0, "cyc": 0, "step": 0, "blend": 0}
	vm.add_stepper(func() -> bool:
		st["frame"] = int(st["frame"]) + 1
		stage.scroll_background_by(vel * scale)

		# Palette cycle: every 4th frame.
		st["cyc"] = int(st["cyc"]) + 1
		if int(st["cyc"]) >= 4:
			st["cyc"] = 0
			if not from_colors.is_empty():
				st["step"] = (int(st["step"]) + 1) % _SURF_CYCLE_COUNT
				stage.set_background_palette_remap(from_colors,
						_rotated_palette(from_colors, int(st["step"])))

		# Blend ramp: in over 13 steps of 2 frames, hold, out again. The
		# animation ends when it has ramped back to nothing.
		var t: int = int(st["frame"]) / 2
		if t <= 13:
			st["blend"] = t
		elif t > 54:
			st["blend"] = maxi(0, 13 - (t - 54))
		if layer != null:
			layer.modulate.a = clampf(int(st["blend"]) / 13.0, 0.0, 1.0)
		if t > 54 and int(st["blend"]) <= 0:
			if layer != null:
				layer.modulate.a = 1.0
			if stage.has_method("clear_background_palette_remap"):
				stage.clear_background_palette_remap()
			if stage.has_method("clear_background"):
				stage.clear_background()
			stage.set_background_scroll(Vector2.ZERO)
			return true
		return false)


const _SURF_CYCLE_FIRST := 1
const _SURF_CYCLE_COUNT := 7


# The extraction pulled the Surf trio plus the muddy-water recolor as separate
# composited assets, so the palette branch upstream resolves to an asset choice
# here. Sludge Wave has no pulled variant -- it falls back to the plain wave
# rather than playing nothing, since the motion is the same and only the tint
# differs.
static func _surf_background_name(palette_arg: int, player_side: bool) -> String:
	if palette_arg == 1:
		# ANIM_SURF_PAL_MUDDY_WATER. Only the player-side recolor exists.
		if player_side and AnimData.has_background("SURF_MUDDY_PLAYER"):
			return "SURF_MUDDY_PLAYER"
	var name := "SURF_PLAYER" if player_side else "SURF_OPPONENT"
	return name if AnimData.has_background(name) else ""


# Safety cap for the behaviors that wait on a sprite's own anim ending. A
# looping sequence never ends, on hardware or here, so an unguarded wait would
# last the whole battle.
const _ANIM_END_CAP := 120


# ─── [M36D batch 4] ───────────────────────────────────────────────────────
#
# Picked by the coverage tool's greedy pass rather than by frequency: the most
# REFERENCED behavior is usually a poor choice, because it tends to appear in
# scripts that are blocked on three other things too. What moves the number is
# the behavior that COMPLETES the most moves, which is what the tool ranks.
#
# Grouped by family, because that is what makes a batch cheap: porting a
# family retires the shared helpers its neighbours also need. Two findings
# from this batch's own Step 0 did most of the collapsing —
#
#   * FOUR of these (PowerAbsorptionOrb, RaiseSprite, AirWaveCrescent,
#     DragonFireToTarget) are literally the same shape upstream: set a start
#     position, set data[0]=duration / data[2]=destX / data[4]=destY, hand off
#     to StartAnimLinearTranslation with a stored destroy-callback. They differ
#     only in which battler the endpoints come from. All four are one call to
#     the `_linear_travel` helper M36C already built.
#   * THREE pairs are the same function under two names: AnimFang and
#     AnimWhipHit_WaitEnd are byte-identical two-liners; AnimKnockOffStrike and
#     SpriteCB_LashOutStrike share a step function; AnimNeedleArmSpike and
#     SpriteCB_MindBlownExplosion share theirs. Registering both names against
#     one implementation is correct, not a shortcut.


# ── the strike family ─────────────────────────────────────────────────────

# AnimFistOrFootRandomPos (battle_anim_fight.c:488, step :540). args:
# 0 battler (0 = attacker), 1 hold duration, 2 anim index into
# gAnims_HandsAndFeet -- and if that is NEGATIVE it is replaced by a random
# one of the five (fist / wide foot / tall foot / left hand / right hand).
#
# Lands at a RANDOM point within the battler's own bounding box: x within
# half its width, y within a quarter of its height, each independently
# negated, then shifted up 16px on the player's side. Upstream also spawns a
# companion hitsplat that is deliberately given a dummy callback so it never
# self-destructs -- it is freed by hand when the fist expires.
static func _fist_or_foot_random_pos(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var battler: int = AnimStage.ANIM_ATTACKER if vm.args[0] == 0 \
			else AnimStage.ANIM_TARGET
	var variant: int = vm.args[2]
	if variant < 0:
		variant = randi() % 5
	_apply_anim_variant(node, ctx, variant)

	var mon := _battler_node(vm, battler)
	var box := mon.size if mon != null else Vector2(64, 64)
	var dx := float(randi() % maxi(1, int(box.x / 2.0)))
	var dy := float(randi() % maxi(1, int(box.y / 4.0)))
	if randi() % 2 == 1:
		dx = -dx
	if randi() % 2 == 1:
		dy = -dy
	if _is_player_side(vm):
		dy -= 16.0 * scale
	node.centre = _battler_centre(vm, battler) + Vector2(dx, dy)

	var hold: int = maxi(0, vm.args[1])
	var st := {"t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) > hold:
			node.finish()
			return true
		return false)


# AnimSpinningKickOrPunch (battle_anim_fight.c:640, finish :650). args:
# 0/1 offset, 2 anim index, 3 spin duration.
#
# The spin and shrink are NOT in the function at all -- they live in the
# template's affine anim (sAffineAnim_SpinningHandOrFoot, :136): -8/256 scale
# and +20 rotation units per frame, looping. The finisher then SNAPS the
# sprite back to full size and angle 0 and holds it there for 21 frames before
# destroying it, which is why the kick appears to land rather than fade.
static func _spinning_kick_or_punch(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	_apply_anim_variant(node, ctx, vm.args[2])
	node.centre = _positioned_centre(vm, AnimStage.ANIM_TARGET, vm.args[0],
			vm.args[1], scale)
	var spin: int = maxi(0, vm.args[3])
	var base_scale := node.scale
	var st := {"t": 0, "phase": 0, "hold": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		if int(st["phase"]) == 0:
			st["t"] = int(st["t"]) + 1
			# -8/256 per frame, +20 rotation units per frame.
			var shrink := 1.0 - (8.0 / 256.0) * float(st["t"])
			node.scale = base_scale * maxf(0.05, shrink)
			node.rotation += _gba_rot_to_radians(20)
			if int(st["t"]) > spin:
				# The snap back to full size and zero rotation is the point.
				node.scale = base_scale
				node.rotation = 0.0
				st["phase"] = 1
			return false
		st["hold"] = int(st["hold"]) + 1
		if int(st["hold"]) > 20:
			node.finish()
			return true
		return false)


# AnimSlidingKick (battle_anim_fight.c:596, step :621). args: 0/1 offset,
# 2 horizontal distance, 3 duration, 4 sine angular speed, 5 sine amplitude.
#
# The travel is purely HORIZONTAL -- the sine rides on top of it as a vertical
# offset, which is what gives the kick its skid. Distance is mirrored for an
# opponent-side attacker.
static func _sliding_kick(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	_apply_anim_variant(node, ctx, 1)  # gSlidingKick uses the foot frame
	var start := _positioned_centre(vm, AnimStage.ANIM_TARGET, vm.args[0],
			vm.args[1], scale)
	var dist := float(vm.args[2])
	if not _is_player_side(vm):
		dist = -dist
	node.centre = start
	var duration: int = maxi(1, vm.args[3])
	var speed: int = vm.args[4]
	var amplitude: float = float(vm.args[5]) * scale
	var st := {"t": 0, "angle": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["t"] = int(st["t"]) + 1
		var t: int = int(st["t"])
		if t > duration:
			node.finish()
			return true
		var pos := start + Vector2(dist * scale * float(t) / float(duration),
				0.0)
		pos.y += _gba_sin(int(st["angle"]) >> 8, amplitude)
		st["angle"] = int(st["angle"]) + speed
		node.centre = pos
		return false)


# AnimTask_AttackerPunchWithTrace (battle_anim_mons.c:2332, step :2361).
# A TASK, not a sprite: the attacker itself lunges and leaves colour-blended
# afterimages. args: 0 blend colour (GBA RGB15), 1 blend coefficient.
#
# Exactly 5 frames out then 4 frames back at 8px/frame, one trace spawned per
# frame (9 total), each living 8 frames. The direction is per-side.
#
# NOT ported: upstream subtracts the SPRITE ID from x2 during setup
# (`x2 -= task->tBattlerSpriteId`), which is an upstream bug -- it mixes an
# object handle into a coordinate. It is masked by the explicit `x2 = 0` at
# the end of the return leg, so reproducing it would only add a garbage
# displacement with no visible intent.
static func _attacker_punch_with_trace(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var node := _battler_node(vm, AnimStage.ANIM_ATTACKER)
	if node == null:
		return
	var scale := _scale(vm)
	var mon := MonOffset.new(node)
	var step_x := 8.0 * scale * (1.0 if _is_player_side(vm) else -1.0)
	var tint := _gba_rgb_to_color(vm.args[0])
	var coeff := clampf(float(vm.args[1]) / 16.0, 0.0, 1.0)
	var st := {"t": 0, "phase": 0, "off": 0.0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		_spawn_battler_trace(vm, node, tint, coeff)
		if int(st["phase"]) == 0:
			st["off"] = float(st["off"]) + step_x
			st["t"] = int(st["t"]) + 1
			if int(st["t"]) >= 5:
				st["phase"] = 1
				st["t"] = 4
		else:
			st["off"] = float(st["off"]) - step_x
			st["t"] = int(st["t"]) - 1
			if int(st["t"]) <= 0:
				mon.restore()
				return true
		mon.apply(Vector2(float(st["off"]), 0.0))
		return false)


# One afterimage: a blended clone of the battler that fades over 8 frames.
static func _spawn_battler_trace(vm: AnimScriptVM, node: Control, tint: Color,
		coeff: float) -> void:
	var tex: Texture2D = null
	if node is TextureRect:
		tex = (node as TextureRect).texture
	if tex == null:
		return
	var trace := TextureRect.new()
	trace.texture = tex
	trace.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	trace.stretch_mode = TextureRect.STRETCH_SCALE
	trace.size = node.size
	trace.position = node.position
	trace.mouse_filter = Control.MOUSE_FILTER_IGNORE
	trace.modulate = Color(tint.r, tint.g, tint.b, coeff)
	var parent := node.get_parent()
	if parent == null:
		trace.queue_free()
		return
	parent.add_child(trace)
	parent.move_child(trace, maxi(0, node.get_index()))
	vm.notify_spawned(trace)
	var life := {"t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(trace):
			return true
		life["t"] = int(life["t"]) + 1
		trace.modulate.a = coeff * (1.0 - float(life["t"]) / 8.0)
		if int(life["t"]) >= 8:
			vm.notify_finished(trace)
			trace.queue_free()
			return true
		return false)


# AnimKnockOffStrike (battle_anim_effects_3.c:5575, step :5550), shared with
# SpriteCB_LashOutStrike (battle_anim_new.c:7850) -- same step function.
#
# Swings through a radius-20 arc starting at angle 192/256, at ~11/256 of a
# circle per frame, in the direction set by which side the target is on.
# Upstream's two init branches are byte-identical in the step (its own comment
# says so). Terminated by the SPRITE ANIM ending, not by a frame count.
static func _knock_off_strike(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var target_is_player := not _is_player_side(vm)
	var base := _battler_centre(vm, AnimStage.ANIM_TARGET)
	var off := Vector2(float(vm.args[0]), float(vm.args[1])) * scale
	if target_is_player:
		base += Vector2(-off.x, off.y)
	else:
		base += off
	node.centre = base
	var speed := -11 if target_is_player else 11
	var st := {"angle": 192, "t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["angle"] = (int(st["angle"]) + speed) & 0xFF
		st["t"] = int(st["t"]) + 1
		var a: int = int(st["angle"])
		node.centre = base + Vector2(_gba_cos(a, 20.0 * scale),
				_gba_sin(a, 20.0 * scale))
		if node.anim_ended() or int(st["t"]) >= _ANIM_END_CAP:
			node.finish()
			return true
		return false)


# AnimFang (battle_anim_effects_3.c:1589) and AnimWhipHit_WaitEnd
# (battle_anim_effects_1.c:5002) are the SAME two-line function under two
# names: read no args, set no position, and self-destruct when the sprite's
# own anim table ends. Everything visible is in the template -- for Fang, a
# 32-frame anim over an affine that starts at 2.0x and shrinks to 1.0x.
static func _wait_for_anim_end(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	# The spawn point is the target's centre -- Cmd_createsprite's own default,
	# which these two deliberately never override.
	node.centre = _battler_centre(vm, AnimStage.ANIM_TARGET)
	var st := {"t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["t"] = int(st["t"]) + 1
		# The cap is a safety net, not the mechanism: a LOOPING sequence never
		# reports animEnded (true on hardware too), and without it these would
		# run for the whole battle.
		if node.anim_ended() or int(st["t"]) >= _ANIM_END_CAP:
			node.finish()
			return true
		return false)


# AnimNeedleArmSpike (battle_anim_effects_1.c:4917, step :4989). The most
# reused sprite callback in the reference -- 23 templates in this project's
# own extraction name it. args: 0 battler, 1 direction (0 = travel INTO the
# origin, else outward from it), 2/3 offset, 4 duration.
#
# Rotates the sprite to face its own direction of travel, which is what makes
# one implementation serve leaves, petals, spikes and flame jabs alike.
static func _needle_arm_spike(vm: AnimScriptVM, ctx: Dictionary) -> void:
	_needle_spike_common(vm, ctx, true)


# SpriteCB_MindBlownExplosion (battle_anim_new.c:6900) is the same body and
# hands off to the same step, with two differences: it always centres on the
# target, and it does NOT rotate to face travel.
static func _mind_blown_explosion(vm: AnimScriptVM, ctx: Dictionary) -> void:
	_needle_spike_common(vm, ctx, false)


static func _needle_spike_common(vm: AnimScriptVM, ctx: Dictionary,
		rotate_to_travel: bool) -> void:
	var duration: int = vm.args[4]
	if duration == 0:
		return  # upstream destroys immediately
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var battler: int = AnimStage.ANIM_ATTACKER if vm.args[0] == 0 \
			else AnimStage.ANIM_TARGET
	if not rotate_to_travel:
		battler = AnimStage.ANIM_TARGET
	var origin := _battler_centre(vm, battler)
	var off := Vector2(float(vm.args[2]), float(vm.args[3])) * scale
	var start := origin + off if vm.args[1] == 0 else origin
	var dest := origin if vm.args[1] == 0 else origin + off
	node.centre = start
	if rotate_to_travel:
		var d := dest - start
		if d.length() > 0.01:
			node.rotation = atan2(d.y, d.x)
	_linear_travel(vm, node, start, dest, maxi(1, duration))


# AnimSlashSlice (battle_anim_effects_1.c:6002). args: 0 battler, 1/2 offset.
# Plays its anim once, then hands off to AnimFalseSwipeSlice_Step3 (:6062),
# the shared flicker-out the whole False Swipe / Cut family uses: toggle
# visibility every other frame, 9 toggles, then destroy.
#
# Note it applies its offsets RAW -- deliberately not through
# SetAnimSpriteInitialXOffset, so there is no per-side mirroring here.
static func _slash_slice(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var battler: int = AnimStage.ANIM_ATTACKER if vm.args[0] == 0 \
			else AnimStage.ANIM_TARGET
	node.centre = _battler_centre(vm, battler) \
			+ Vector2(float(vm.args[1]), float(vm.args[2])) * scale
	var st := {"phase": 0, "tick": 0, "toggles": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		if int(st["phase"]) == 0:
			node.advance_frame()
			st["tick"] = int(st["tick"]) + 1
			if node.anim_ended() or int(st["tick"]) >= _ANIM_END_CAP:
				st["phase"] = 1
				st["tick"] = 0
			return false
		st["tick"] = int(st["tick"]) + 1
		if int(st["tick"]) > 1:
			st["tick"] = 0
			node.visible = not node.visible
			st["toggles"] = int(st["toggles"]) + 1
			if int(st["toggles"]) > 8:
				node.finish()
				return true
		return false)


# SpriteCB_RandomCentredHits (battle_anim_new.c:6943). args: 0 battler,
# 1 affine variant -- and if that is -1 it is replaced by a random one of the
# four hitsplat scales (1.0 / 0.844 / 0.688 / 0.5). Scatters within +/-24 px
# horizontally and +/-12 vertically, holds 8 frames, destroys.
#
# The args are genuinely ALIASED upstream: [0] and [1] select the battler and
# the affine variant, and the position helper then reads the same two as x/y
# offsets. Reproduced rather than "fixed" -- the offsets are what the scripts
# were authored against.
static func _random_centred_hits(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var variant: int = vm.args[1]
	if variant < 0:
		variant = randi() % 4
	var battler: int = AnimStage.ANIM_ATTACKER if vm.args[0] == 0 \
			else AnimStage.ANIM_TARGET
	node.scale = Vector2.ONE * scale * _HIT_SPLAT_SCALES[clampi(variant, 0,
			_HIT_SPLAT_SCALES.size() - 1)]
	var centre := _positioned_centre(vm, battler, vm.args[0], vm.args[1],
			scale)
	centre += Vector2(float(randi() % 48 - 24), float(randi() % 24 - 12)) \
			* scale
	node.centre = centre
	var st := {"t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) >= 8:
			node.finish()
			return true
		return false)


# ── the linear-translation family (one shape, four behaviors) ─────────────

# AnimPowerAbsorptionOrb (battle_anim_effects_1.c:3071). args: 0/1 offset,
# 2 duration. Starts offset from the attacker and travels back INTO it --
# the drain direction, which is the one thing easy to get backwards.
static func _power_absorption_orb(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var dest := _battler_centre(vm, AnimStage.ANIM_ATTACKER)
	var start := _positioned_centre(vm, AnimStage.ANIM_ATTACKER, vm.args[0],
			vm.args[1], scale)
	node.centre = start
	_linear_travel(vm, node, start, dest, maxi(1, vm.args[2]))


# AnimRaiseSprite (battle_anim_rock.c:653). args: 0/1 offset, 2 rise distance,
# 3 duration, 4 anim variant. Structurally identical to the orb above -- only
# the destination is RELATIVE rather than the battler's own centre.
static func _raise_sprite(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	_apply_anim_variant(node, ctx, vm.args[4])
	var start := _positioned_centre(vm, AnimStage.ANIM_ATTACKER, vm.args[0],
			vm.args[1], scale)
	node.centre = start
	_linear_travel(vm, node, start, start + Vector2(0.0,
			float(vm.args[2]) * scale), maxi(1, vm.args[3]))


# AnimAirWaveCrescent (battle_anim_flying.c:418). args: 0/1 start offset,
# 2/3 destination offset, 4 duration, 5 anim seek frame, 6 average-with-partner.
# ALL FOUR offsets are negated for an opponent-side attacker -- a single
# mirror, not a per-axis one.
static func _air_wave_crescent(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var m := 1.0 if _is_player_side(vm) else -1.0
	var start := _battler_centre(vm, AnimStage.ANIM_ATTACKER) \
			+ Vector2(float(vm.args[0]), float(vm.args[1])) * m * scale
	var dest := _battler_centre(vm, AnimStage.ANIM_TARGET) \
			+ Vector2(float(vm.args[2]), float(vm.args[3])) * m * scale
	node.centre = start
	_apply_anim_variant(node, ctx, vm.args[5])
	_linear_travel(vm, node, start, dest, maxi(1, vm.args[4]))


# AnimDragonFireToTarget -> StartDragonFireTranslation (battle_anim_dragon.c:
# 465 / :412). args: 0/1 start offset, 2/3 destination offset, 4 duration.
#
# Reproduces a real upstream ASYMMETRY: on the opponent's side the horizontal
# start offset is taken from args[1] (the Y arg), not args[0]. That looks like
# a typo in the reference and may well be one, but the scripts were authored
# against the behaviour it produces, so "fixing" it would move every dragon
# breath that already looks right.
static func _dragon_fire_to_target(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var player := _is_player_side(vm)
	var origin := _battler_centre(vm, AnimStage.ANIM_ATTACKER)
	var start: Vector2 = origin + (Vector2(float(vm.args[0]),
			float(vm.args[1])) * scale if player
			else Vector2(-float(vm.args[1]), float(vm.args[1])) * scale)
	var dest: Vector2 = _battler_centre(vm, AnimStage.ANIM_TARGET) \
			+ (Vector2(float(vm.args[2]), float(vm.args[3])) * scale if player
				else Vector2(-float(vm.args[2]), float(vm.args[3])) * scale)
	node.centre = start
	if player:
		_apply_anim_variant(node, ctx, 1)
	_linear_travel(vm, node, start, dest, maxi(1, vm.args[4]))


# AnimFlyingSandCrescent (battle_anim_rock.c:595). args: 0 absolute start y,
# 1/2 velocity in 256ths of a px per frame, 3 mirror flag.
#
# The odd one out of the crescents: it does NOT travel between two battlers.
# It enters from one screen edge at constant velocity and is destroyed when it
# leaves the other, so its lifetime depends on the velocity rather than a
# duration argument.
static func _flying_sand_crescent(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var layer: Control = vm.stage.layer() if vm.stage != null \
			and vm.stage.has_method("layer") else null
	var width: float = layer.size.x if layer != null else 1024.0
	var mirrored: bool = vm.args[3] != 0 and not _is_player_side(vm)
	var vel_x := float(vm.args[1]) / 256.0 * scale
	var pos := Vector2(-64.0 * scale, float(vm.args[0]) * scale)
	if mirrored:
		pos.x = width + 64.0 * scale
		vel_x = -vel_x
		node.flip_h = true
	node.centre = pos
	var vel := Vector2(vel_x, float(vm.args[2]) / 256.0 * scale)
	var st := {"pos": pos}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var p: Vector2 = st["pos"] + vel
		st["pos"] = p
		node.centre = p
		var gone := p.x < -32.0 * scale if mirrored \
				else p.x > width + 32.0 * scale
		if gone:
			node.finish()
			return true
		return false)


# AnimMimicOrb (battle_anim_effects_1.c:4130). args: 0/1 offset, with the x
# offset mirrored when the TARGET is player-side.
#
# Three real phases, not one: invisible for a frame, then it grows in place
# (the template's own affine anim), and only THEN does it travel -- and that
# leg is a fixed 25 frames using the FAST translation variant, not the
# duration-argument shape every other projectile in this batch uses.
static func _mimic_orb(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var x_off := float(vm.args[0])
	if not _is_player_side(vm):
		x_off = -x_off
	var start := _battler_centre(vm, AnimStage.ANIM_TARGET) \
			+ Vector2(x_off, float(vm.args[1])) * scale
	node.centre = start
	node.visible = false
	var dest := _battler_centre(vm, AnimStage.ANIM_ATTACKER)
	var base_scale := node.scale
	var st := {"phase": 0, "t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		match int(st["phase"]):
			0:
				node.visible = true
				st["phase"] = 1
			1:
				# The grow-in-place leg, upstream the template's affine anim.
				st["t"] = int(st["t"]) + 1
				var g := clampf(float(st["t"]) / 8.0, 0.0, 1.0)
				node.scale = base_scale * g
				if int(st["t"]) >= 8:
					node.scale = base_scale
					st["phase"] = 2
					st["t"] = 0
			2:
				node.advance_frame()
				st["t"] = int(st["t"]) + 1
				var f := float(st["t"]) / 25.0
				node.centre = start.lerp(dest, f)
				if int(st["t"]) >= 25:
					node.finish()
					return true
		return false)


# ── mon-visual tasks ──────────────────────────────────────────────────────

# AnimTask_SlideOffScreen (battle_anim_mon_movement.c:838, step :880).
# args: 0 battler, 1 speed. Slides until off-screen and then STOPS -- upstream
# deliberately leaves x2 off-screen and restores nothing, because the script
# that uses it follows up with something that puts the battler back.
#
# The VM's own end-of-run visibility/position restore is what keeps that from
# leaking here, the same safety net the visibility fix added in M36D.
static func _slide_off_screen(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var battler: int = AnimStage.ANIM_ATTACKER if vm.args[0] == 0 \
			else AnimStage.ANIM_TARGET
	var node := _battler_node(vm, battler)
	if node == null:
		return
	var scale := _scale(vm)
	var layer: Control = vm.stage.layer() if vm.stage != null \
			and vm.stage.has_method("layer") else null
	var width: float = layer.size.x if layer != null else 1024.0
	var mon := MonOffset.new(node)
	# Upstream keys the sign on gBattleAnimTarget's side, not on the battler
	# being slid -- so both slide the same way in a given battle.
	var speed := float(vm.args[1]) * scale \
			* (-1.0 if _is_player_side(vm) else 1.0)
	var st := {"off": 0.0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		st["off"] = float(st["off"]) + speed
		mon.apply(Vector2(float(st["off"]), 0.0))
		var x := node.position.x
		if x < -32.0 * scale or x > width + 32.0 * scale:
			return true
		return false)


# AnimTask_MonToSubstitute (battle_anim_effects_3.c:4963, doll phase :5004).
# No args. Two genuinely different phases: the mon squashes (x scale +0x60,
# y scale -0xD per frame for 9 frames) and vanishes, then the doll DROPS in
# under gravity from off-screen, bounces once, and lands.
#
# The bounce is real physics with an 8.8 velocity: +112/frame downward, a
# -0x800 kick on landing, then the same acceleration again.
static func _mon_to_substitute(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var node := _battler_node(vm, AnimStage.ANIM_ATTACKER)
	if node == null:
		return
	var scale := _scale(vm)
	var mon := MonOffset.new(node)
	var base_scale := node.scale
	var st := {"phase": 0, "t": 0, "sx": 256.0, "sy": 256.0, "vel": 0.0,
			"y": -200.0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		match int(st["phase"]):
			0:  # squash
				st["t"] = int(st["t"]) + 1
				st["sx"] = float(st["sx"]) + 0x60
				st["sy"] = float(st["sy"]) - 0xD
				node.scale = Vector2(base_scale.x * float(st["sx"]) / 256.0,
						base_scale.y * float(st["sy"]) / 256.0)
				if int(st["t"]) >= 9:
					node.scale = base_scale
					st["phase"] = 1
					st["t"] = 0
					st["vel"] = 0.0
					st["y"] = -200.0
			1:  # fall
				st["vel"] = float(st["vel"]) + 112.0
				st["y"] = float(st["y"]) + float(st["vel"]) / 256.0
				if float(st["y"]) >= 0.0:
					st["y"] = 0.0
					st["vel"] = float(st["vel"]) - 2048.0
					st["phase"] = 2
				mon.apply(Vector2(0.0, float(st["y"]) * scale))
			2:  # bounce up
				st["vel"] = minf(0.0, float(st["vel"]) + 112.0)
				st["y"] = float(st["y"]) - float(st["vel"]) / 256.0
				mon.apply(Vector2(0.0, float(st["y"]) * scale))
				if is_zero_approx(float(st["vel"])):
					st["phase"] = 3
			3:  # fall again, and land for good
				st["vel"] = float(st["vel"]) + 112.0
				st["y"] = float(st["y"]) + float(st["vel"]) / 256.0
				if float(st["y"]) >= 0.0:
					st["y"] = 0.0
					mon.restore()
					return true
				mon.apply(Vector2(0.0, float(st["y"]) * scale))
		return false)


# AnimTask_RolePlaySilhouette (battle_anim_effects_3.c:3371, steps :3423 and
# :3439). No args. Clones the TARGET as a pure white silhouette beside the
# attacker, fades it in over ~30 frames, then squeezes it out of existence
# (x scale -16, y scale +128 per frame for 9 frames) -- so it collapses
# horizontally while stretching vertically, rather than simply shrinking.
static func _role_play_silhouette(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var src := _battler_node(vm, AnimStage.ANIM_TARGET)
	var anchor := _battler_node(vm, AnimStage.ANIM_ATTACKER)
	if src == null or anchor == null:
		return
	var tex: Texture2D = null
	if src is TextureRect:
		tex = (src as TextureRect).texture
	if tex == null:
		return
	var scale := _scale(vm)
	var ghost := TextureRect.new()
	ghost.texture = tex
	ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ghost.stretch_mode = TextureRect.STRETCH_SCALE
	ghost.size = src.size
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.position = anchor.position + Vector2(-20.0 * scale, 0.0)
	ghost.pivot_offset = ghost.size * 0.5
	# White silhouette: upstream fills the cloned palette with RGB_WHITE.
	_apply_recolor(ghost, true, Color(1, 1, 1))
	ghost.modulate.a = 0.0
	var parent := anchor.get_parent()
	if parent == null:
		ghost.queue_free()
		return
	parent.add_child(ghost)
	vm.notify_spawned(ghost)

	var st := {"phase": 0, "tick": 0, "blend": 0, "t": 0,
			"sx": 256.0, "sy": 256.0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(ghost):
			return true
		if int(st["phase"]) == 0:
			st["tick"] = int(st["tick"]) + 1
			if int(st["tick"]) > 2:
				st["tick"] = 0
				st["blend"] = int(st["blend"]) + 1
				ghost.modulate.a = clampf(float(st["blend"]) / 16.0, 0.0, 1.0)
				if int(st["blend"]) >= 10:
					st["phase"] = 1
			return false
		st["t"] = int(st["t"]) + 1
		st["sx"] = float(st["sx"]) - 16.0
		st["sy"] = float(st["sy"]) + 128.0
		ghost.scale = Vector2(float(st["sx"]) / 256.0, float(st["sy"]) / 256.0)
		if int(st["t"]) >= 9:
			vm.notify_finished(ghost)
			ghost.queue_free()
			return true
		return false)


# ── status / other ────────────────────────────────────────────────────────

# AnimTask_SporeDoubleBattle (battle_anim_effects_1.c:3611). No args, one
# frame. Upstream this only reorders BG PRIORITIES so the spore particles can
# pass behind the target in a double battle, and it destroys itself
# immediately in singles or contests.
#
# There is no per-battler BG priority rank in this port -- sprites are ordinary
# nodes in one layer -- so there is nothing to reorder and this is a genuine
# structured no-op. Registered rather than left missing precisely so it stops
# gating the moves that call it.
static func _spore_double_battle(_vm: AnimScriptVM, _ctx: Dictionary) -> void:
	pass


# AnimSleepLetterZ (battle_anim_effects_1.c:5496, step :5518). args: 0/1
# offset. Rises QUADRATICALLY while drifting linearly sideways -- the vertical
# accumulator sums the frame counter, so the Z accelerates upward as it goes,
# which is what makes it read as floating rather than travelling. 61 frames.
static func _sleep_letter_z(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var player := _is_player_side(vm)
	var base := _battler_centre(vm, AnimStage.ANIM_ATTACKER)
	var x_off := float(vm.args[0]) * (1.0 if player else -1.0)
	base += Vector2(x_off, float(vm.args[1])) * scale
	node.centre = base
	var drift := 1 if player else -1
	var st := {"t": 0, "rise": 0, "sway": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var y := -float(st["rise"]) / 40.0
		var x := float(st["sway"]) / 10.0
		node.centre = base + Vector2(x, y) * scale
		st["sway"] = int(st["sway"]) + drift * 2
		st["rise"] = int(st["rise"]) + int(st["t"])
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) > 60:
			node.finish()
			return true
		return false)


# AnimTask_GetReturnPowerLevel (battle_anim_effects_3.c:5241). Writes a
# 0-3 band into arg 7 from the attacker's friendship, which the Return script
# then branches on to pick how big the burst is.
#
# The thresholds are reproduced EXACTLY as written, including the gap: a
# friendship of exactly 60 matches none of the four sequential (non-else)
# comparisons and so falls through to 0. That is upstream behaviour, not a
# transcription slip.
#
# Friendship is not modelled in this port yet, so it reads 0 and the script
# takes the weakest branch -- a disclosed simplification that keeps Return
# playable rather than blocked.
static func _get_return_power_level(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var friendship: int = vm.friendship
	var band := 0
	if friendship > 60 and friendship < 92:
		band = 1
	if friendship > 91 and friendship < 201:
		band = 2
	if friendship > 200:
		band = 3
	vm.args[AnimScriptVM.ARG_RET] = band


# AnimConstrictBinding (battle_anim_effects_1.c:4009, steps :4021 / :4033).
# args: 0/1 offset, 2 affine variant, 3 squeeze count.
#
# Genuinely waits on the SCRIPT: after positioning, it does nothing at all
# until the script writes -1 into arg 7, and only then squeezes. Reproducing
# that handshake matters -- running the squeeze immediately would desynchronise
# it from the rest of the animation.
#
# Upstream's step also maintains a triangle wave in data[0] that is never read;
# that is dead code and is not ported.
static func _constrict_binding(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	node.centre = _positioned_centre(vm, AnimStage.ANIM_TARGET, vm.args[0],
			vm.args[1], scale)
	var squeezes: int = maxi(1, vm.args[3])
	var base_scale := node.scale
	var st := {"armed": false, "left": squeezes, "t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		if not bool(st["armed"]):
			if vm.args[AnimScriptVM.ARG_RET] == -1:
				st["armed"] = true
			return false
		st["t"] = int(st["t"]) + 1
		# One squeeze cycle: pinch in and back out over 12 frames, matching
		# the 6-frame direction flip upstream.
		var phase := float(int(st["t"]) % 12) / 12.0
		node.scale = base_scale * (1.0 - 0.25 * sin(phase * TAU))
		if int(st["t"]) % 12 == 0:
			st["left"] = int(st["left"]) - 1
			if int(st["left"]) <= 0:
				node.scale = base_scale
				node.finish()
				return true
		return false)


# AnimRecycle (battle_anim_effects_3.c:5598, step :5611). No args. A four-state
# blend: ~64 frames fading in, 10 holding, ~64 fading out, then destroy. The
# arrow's rotation is entirely in the template's affine anim.
#
# Upstream does NOT reset BLDALPHA on the way out -- it leaves the register
# set and relies on the script to clear it. Here the blend lives on the sprite
# being freed, so there is nothing left behind either way.
static func _recycle(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var mon := _battler_node(vm, AnimStage.ANIM_ATTACKER)
	var top := mon.position.y if mon != null else 0.0
	node.centre = Vector2(_battler_centre(vm, AnimStage.ANIM_ATTACKER).x,
			maxf(16.0 * scale, top))
	node.modulate.a = 0.0
	var st := {"phase": 0, "t": 0, "blend": 0.0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["t"] = int(st["t"]) + 1
		match int(st["phase"]):
			0:
				st["blend"] = minf(1.0, float(st["t"]) / 64.0)
				if int(st["t"]) >= 64:
					st["phase"] = 1
					st["t"] = 0
			1:
				if int(st["t"]) >= 10:
					st["phase"] = 2
					st["t"] = 0
			2:
				st["blend"] = maxf(0.0, 1.0 - float(st["t"]) / 64.0)
				if int(st["t"]) >= 64:
					node.finish()
					return true
		node.modulate.a = float(st["blend"])
		return false)


# GBA rotation units are 1/65536 of a turn -- the same convention MonAnimator
# uses. (_gba_sin/_gba_cos already exist from M36C and are reused as-is.)
static func _gba_rot_to_radians(units: int) -> float:
	return float(units) / 65536.0 * TAU


# ─── [M36D batch 5] ───────────────────────────────────────────────────────
#
# Cluster-driven rather than greedy-driven, because by this point the greedy
# value had flattened to +3 and the tool had started reporting behaviors that
# BLOCK moves while being worth nothing alone ("blocks 3, none one-away").
# Those only pay off ported alongside their co-blockers, so this batch takes
# whole elemental families instead of top-ranked singles.
#
# Step 0 corrected an expectation worth recording: only ONE of these
# (AnimSwordsDanceBlade's second phase) collapses onto the `_linear_travel`
# helper. The rest use genuinely different translation machinery -- arc,
# fast-linear-with-speed, or raw 8.8 velocity -- so they are deliberately NOT
# forced onto one helper. `_velocity_travel` below is the one new shared shape
# that did fall out.


# The port of TranslateSpriteLinearFixedPoint (battle_anim_mons.c:520): a
# fixed frame count driven by 8.8 per-frame VELOCITIES rather than by a
# destination. Distinct from _linear_travel, which interpolates toward a point.
static func _velocity_travel(vm: AnimScriptVM, node: AnimSprite,
		start: Vector2, velocity: Vector2, frames: int) -> void:
	var st := {"t": 0, "acc": Vector2.ZERO}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) > frames:
			node.finish()
			return true
		st["acc"] = (st["acc"] as Vector2) + velocity
		node.centre = start + (st["acc"] as Vector2) / 256.0
		return false)


# ── water / ice ───────────────────────────────────────────────────────────

# AnimTask_FrozenIceCube (battle_anim_status_effects.c:417) and its two
# near-clones at :356 (attacker) and :379 (centred on both targets). All three
# share Step1-Step4 and differ ONLY in where the cube is placed -- so they are
# one implementation with a coordinate parameter.
#
# Four phases, ~105 frames: fade in over 10, then two 23-frame cycles that
# rotate three palette entries every 3rd frame (6 rotations total), then fade
# out over 10, then a 39-frame tail that frees the sprite at 37 and clears the
# blend registers at 39.
#
# The palette rotation is the same mechanism M36E3 built for the psychic
# background, over a 3-entry window at the top of the cube's own palette
# rather than 11 in the middle of a background's.
static func _frozen_ice_cube(vm: AnimScriptVM, ctx: Dictionary) -> void:
	_frozen_ice_cube_common(vm, ctx, AnimStage.ANIM_TARGET, true)


static func _frozen_ice_cube_attacker(vm: AnimScriptVM, ctx: Dictionary) -> void:
	_frozen_ice_cube_common(vm, ctx, AnimStage.ANIM_ATTACKER, true)


# The centred variant deliberately does NOT write the blend registers on entry
# -- a real asymmetry between the three, not an omission here.
static func _frozen_ice_cube_centred(vm: AnimScriptVM, ctx: Dictionary) -> void:
	_frozen_ice_cube_common(vm, ctx, AnimStage.ANIM_TARGET, false)


static func _frozen_ice_cube_common(vm: AnimScriptVM, ctx: Dictionary,
		battler: int, owns_blend: bool) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	node.centre = _battler_centre(vm, battler) \
			+ Vector2(-32.0, -36.0) * scale
	node.modulate.a = 0.0

	var st := {"phase": 0, "t": 0, "alpha": 0, "cyc": 0, "rot": 0, "cycles": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		match int(st["phase"]):
			0:  # fade in, 10 frames
				st["alpha"] = int(st["alpha"]) + 1
				node.modulate.a = clampf(float(st["alpha"]) / 10.0, 0.0, 1.0)
				if int(st["alpha"]) >= 10:
					st["phase"] = 1
					st["t"] = 0
			1:  # 14 idle frames, then rotate every 3rd for 9
				st["t"] = int(st["t"]) + 1
				if int(st["t"]) <= 14:
					return false
				st["cyc"] = int(st["cyc"]) + 1
				if int(st["cyc"]) >= 3:
					st["cyc"] = 0
					st["rot"] = int(st["rot"]) + 1
					_rotate_sprite_top_colours(node, int(st["rot"]))
					if int(st["rot"]) % 3 == 0:
						st["t"] = 0
						st["cycles"] = int(st["cycles"]) + 1
						if int(st["cycles"]) >= 2:
							st["phase"] = 2
							st["alpha"] = 9
			2:  # fade out, 10 frames
				st["alpha"] = int(st["alpha"]) - 1
				node.modulate.a = clampf(float(st["alpha"]) / 10.0, 0.0, 1.0)
				if int(st["alpha"]) <= 0:
					st["phase"] = 3
					st["t"] = 0
			3:  # the 39-frame tail: sprite freed at 37, registers at 39
				st["t"] = int(st["t"]) + 1
				if int(st["t"]) >= 37:
					node.finish()
					return true
		return false)


# The cube's own 3-colour rotation. Upstream cycles palette entries 13/14/15;
# with no palette indirection here the equivalent is a hue step on the sprite,
# which reads as the same shimmer at this scale.
static func _rotate_sprite_top_colours(node: CanvasItem, step: int) -> void:
	var h := fmod(float(step) * (1.0 / 3.0), 1.0)
	node.modulate = Color.from_hsv(h, 0.15, 1.0, node.modulate.a)


# AnimSmallBubblePair (battle_anim_water.c:965, step :975). args: 0/1 offset,
# 2 frame count, 3 battler. Rises while weaving: the horizontal is a sine of
# amplitude 4 stepping 11/256 per frame, the vertical an 8.8 accumulator at
# 48/frame -- so it drifts up steadily rather than accelerating.
static func _small_bubble_pair(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var battler: int = AnimStage.ANIM_ATTACKER if vm.args[3] == 0 \
			else AnimStage.ANIM_TARGET
	var base := _positioned_centre(vm, battler, vm.args[0], vm.args[1], scale)
	node.centre = base
	var life: int = maxi(1, vm.args[2])
	var st := {"t": 0, "angle": 0, "rise": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["angle"] = (int(st["angle"]) + 11) & 0xFF
		st["rise"] = int(st["rise"]) + 48
		node.centre = base + Vector2(
				_gba_sin(int(st["angle"]), 4.0 * scale),
				-float(int(st["rise"]) >> 8) * scale)
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) > life:
			node.finish()
			return true
		return false)


# AnimSmallDriftingBubbles (battle_anim_water.c:1209, step :1225). args: 0/1
# offset. Its velocities are RANDOM per bubble (x 256..511 with the low bit
# doubling as a sign flag, y biased upward), which is what makes a cloud of
# them look like a cloud rather than a volley. Exactly 21 frames.
static func _small_drifting_bubbles(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var start := _positioned_centre(vm, AnimStage.ANIM_TARGET, vm.args[0],
			vm.args[1], scale)
	node.centre = start
	var vx := float((randi() % 256) | 256)
	if randi() % 2 == 1:
		vx = -vx
	var vy := float(randi() % 512)
	if vy > 255.0:
		vy = 256.0 - vy
	_velocity_travel(vm, node, start, Vector2(vx, vy) * scale, 21)


# ── electric ──────────────────────────────────────────────────────────────

# AnimTask_ElectricBolt (battle_anim_electric.c:819, step :832). args: 0/1
# offset from the target, 2 bolt style. Spawns FIVE segments, one every two
# frames, each 16px lower than the last -- the bolt draws itself downward
# rather than appearing at once. 11 frames, then the task ends; the segments
# outlive it by their own 15-frame life.
static func _electric_bolt(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var scale := _scale(vm)
	var origin := _battler_centre(vm, AnimStage.ANIM_TARGET) \
			+ Vector2(float(vm.args[0]), float(vm.args[1])) * scale
	var style: int = vm.args[2]
	var st := {"t": 0, "spawned": 0}
	vm.add_stepper(func() -> bool:
		var t: int = int(st["t"])
		if t % 2 == 0 and int(st["spawned"]) < 5:
			var seg := _make_sprite(vm, ctx)
			if seg != null:
				seg.centre = origin + Vector2(0.0,
						16.0 * float(int(st["spawned"]) + 1) * scale)
				_apply_anim_variant(seg, ctx, style)
				_electric_segment_life(vm, seg)
			st["spawned"] = int(st["spawned"]) + 1
		st["t"] = t + 1
		return int(st["t"]) >= 11)


# AnimElectricBoltSegment (battle_anim_electric.c:912). One segment: static,
# 15 frames, then gone. Reached directly when a script creates a segment
# itself rather than through the bolt task.
static func _electric_bolt_segment(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	node.centre = _battler_centre(vm, AnimStage.ANIM_TARGET)
	_electric_segment_life(vm, node)


static func _electric_segment_life(vm: AnimScriptVM, node: AnimSprite) -> void:
	var st := {"t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) >= 15:
			node.finish()
			return true
		return false)


# AnimElectricity (battle_anim_electric.c:801). args: 0/1 offset, 2 duration,
# 3 variant (which also picks an H or V flip), 4 battler. Completely static --
# it places a spark, waits, and dies. The flip is the only reason three
# variants exist.
static func _electricity(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var battler: int = AnimStage.ANIM_ATTACKER if vm.args[4] == 0 \
			else AnimStage.ANIM_TARGET
	node.centre = _positioned_centre(vm, battler, vm.args[0], vm.args[1], scale)
	var variant: int = vm.args[3]
	_apply_anim_variant(node, ctx, variant)
	if variant == 1:
		node.flip_h = true
	elif variant == 2:
		node.flip_v = true
	var life: int = maxi(1, vm.args[2])
	var st := {"t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) > life:
			node.finish()
			return true
		return false)


# AnimThunderWave (battle_anim_electric.c:919, step :937). args: 0/1 offset.
#
# ONE call produces TWO sprites, 32px apart, the right one drawn from a
# different tile offset -- upstream even bumps gAnimVisualTaskCount by hand to
# account for the second destroy. Both flicker on a 3-frame cycle for 51
# frames. Porting only one sprite would leave the wave visibly half-width.
static func _thunder_wave(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var scale := _scale(vm)
	var base := _positioned_centre(vm, AnimStage.ANIM_TARGET, vm.args[0],
			vm.args[1], scale)
	for i in range(2):
		var node := _make_sprite(vm, ctx)
		if node == null:
			continue
		node.centre = base + Vector2(32.0 * float(i) * scale, 0.0)
		if i == 1:
			node.set_tile_offset(8)
		var st := {"t": 0, "flick": 0}
		vm.add_stepper(func() -> bool:
			if not is_instance_valid(node):
				return true
			st["flick"] = int(st["flick"]) + 1
			if int(st["flick"]) >= 3:
				st["flick"] = 0
				node.visible = not node.visible
			st["t"] = int(st["t"]) + 1
			if int(st["t"]) >= 51:
				node.finish()
				return true
			return false)


# ── beams / orbs / charge ─────────────────────────────────────────────────

# AnimHyperBeamOrb (battle_anim_effects_1.c:3191, step :3217). Reads NO args
# -- everything is randomised: which of 7 frames, the launch speed (64..95),
# and the sine phase. Its duration is therefore DISTANCE-dependent, not a
# fixed count, which is why a volley of them arrives staggered.
static func _hyper_beam_orb(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	_apply_anim_variant(node, ctx, randi() % 7)
	var start := _battler_centre(vm, AnimStage.ANIM_ATTACKER) \
			+ Vector2((20.0 if _is_player_side(vm) else -20.0) * scale, 0.0)
	var dest := _battler_centre(vm, AnimStage.ANIM_TARGET)
	node.centre = start
	var speed := float((randi() % 32) + 64)
	var duration := maxi(1, int(absf(dest.x - start.x) * 16.0 / speed / scale))
	var phase := randi() % 256
	var st := {"t": 0, "phase": phase}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) >= duration:
			node.finish()
			return true
		var pos := start.lerp(dest, float(st["t"]) / float(duration))
		pos.y += _gba_cos(int(st["phase"]), 12.0 * scale)
		st["phase"] = (int(st["phase"]) + 24) & 0xFF
		node.centre = pos
		return false)


# AnimSwordsDanceBlade (battle_anim_effects_2.c:1400, step :1407). args: 0/1
# offset. The ONE behavior in this batch that is the canonical
# StartAnimLinearTranslation shape -- after its affine anim ends it rises
# exactly 32px over exactly 6 frames.
static func _swords_dance_blade(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var start := _positioned_centre(vm, AnimStage.ANIM_ATTACKER, vm.args[0],
			vm.args[1], scale)
	node.centre = start
	var st := {"t": 0, "phase": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		if int(st["phase"]) == 0:
			st["t"] = int(st["t"]) + 1
			if node.anim_ended() or int(st["t"]) >= _ANIM_END_CAP:
				st["phase"] = 1
				st["t"] = 0
			return false
		st["t"] = int(st["t"]) + 1
		node.centre = start.lerp(start + Vector2(0.0, -32.0 * scale),
				float(st["t"]) / 6.0)
		if int(st["t"]) >= 6:
			node.finish()
			return true
		return false)


# AnimPsychoBoost (battle_anim_psychic.c:1309). Reads no args. A 4-state
# machine: place and set a half blend, wait for the affine anim, then fade the
# blend 8->0 in steps of 3 frames WHILE rising 3.5px/frame, then clear.
# ~24 frames of rise. Restores its blend registers on the way out.
static func _psycho_boost(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var base := _battler_centre(vm, AnimStage.ANIM_ATTACKER)
	node.centre = base
	node.modulate.a = 0.5
	var st := {"phase": 0, "t": 0, "blend": 8, "tick": 0, "rise": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		if int(st["phase"]) == 0:
			st["t"] = int(st["t"]) + 1
			if node.anim_ended() or int(st["t"]) >= _ANIM_END_CAP:
				st["phase"] = 1
			return false
		st["tick"] = int(st["tick"]) + 1
		if int(st["tick"]) > 2:
			st["tick"] = 0
			st["blend"] = int(st["blend"]) - 1
			node.modulate.a = clampf(float(st["blend"]) / 16.0, 0.0, 1.0)
			if int(st["blend"]) <= 0:
				node.finish()
				return true
		st["rise"] = int(st["rise"]) + 0x380
		node.centre = base + Vector2(0.0,
				-float(int(st["rise"]) >> 8) * scale)
		return false)


# AnimGrowingChargeOrb (battle_anim_electric.c:1056). args: 0 battler only.
# ZERO per-frame maths of its own -- the whole animation is the template's
# affine table, and the sprite dies when that ends. Recorded because one of
# its three affine variants ends in JUMP and so never terminates upstream
# either; the frame cap is what stands in for the script killing it.
static func _growing_charge_orb(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var battler: int = AnimStage.ANIM_ATTACKER if vm.args[0] == 0 \
			else AnimStage.ANIM_TARGET
	node.centre = _battler_centre(vm, battler)
	_play_until_anim_ends(vm, node, _ANIM_END_CAP)


# AnimElectricPuff (battle_anim_electric.c:1073). The same coordinate block as
# the charge orb, plus a static offset from args 1/2.
static func _electric_puff(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	node.centre = _battler_centre(vm, AnimStage.ANIM_ATTACKER) \
			+ Vector2(float(vm.args[1]), float(vm.args[2])) * scale
	_play_until_anim_ends(vm, node, _ANIM_END_CAP)


# ── palette / flash ───────────────────────────────────────────────────────

# AnimTask_BlendBattleAnimPalExclude (battle_anim_utility_funcs.c:54).
# args: 0 which battler to EXCLUDE, 1 step delay, 2 start coeff, 3 target
# coeff, 4 blend colour.
#
# THE ONE GENUINELY UN-PORTABLE PALETTE OPERATION IN THIS BATCH, and it is
# worth being precise about why rather than pretending otherwise. Upstream it
# blends by PALETTE SLOT -- a set that includes the battle-background palettes
# and in which two battlers can legitimately share a slot -- so it does not
# decompose into a per-object list at all. It also never restores: scripts
# pair two calls to blend back.
#
# Ported as the nearest thing a compositing engine can express: tint the
# background layer and every battler EXCEPT the excluded one, per node, using
# the same coefficient ramp (one step every delay+1 frames). It persists for
# the rest of the run, matching upstream, and the VM's own end-of-run cleanup
# is what prevents that from becoming a permanent leak.
static func _blend_pal_exclude(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	# Build the affected set as "everything except one battler", then hand it
	# to the SAME ramp AnimTask_BlendBattleAnimPal already uses -- the two
	# differ only in how that set is chosen, exactly as upstream (both route
	# through StartBlendAnimSpriteColor).
	var excluded := -1
	match vm.args[0]:
		0: excluded = AnimStage.ANIM_ATTACKER
		1: excluded = AnimStage.ANIM_TARGET
	var nodes: Array[Control] = []
	for i in range(4):
		if i == excluded:
			continue
		var n := _battler_node(vm, i)
		if n != null:
			nodes.append(n)
	# Upstream's set also includes the battle-BACKGROUND palettes; the closest
	# thing here is the anim background layer, when one is up.
	if vm.stage != null and vm.stage.has_method("background_layer"):
		var bg = vm.stage.background_layer()
		if bg != null and bg.visible:
			nodes.append(bg)
	_run_blend_nodes(vm, nodes, vm.args[1], vm.args[2], vm.args[3],
			vm.args[4])


# Removes a blend, restoring the node to how it renders untouched.
static func _clear_blend(node: CanvasItem) -> void:
	if node.material is ShaderMaterial \
			and (node.material as ShaderMaterial).shader == _recolor_shader:
		node.material = null


# A per-node colour blend at a coefficient, reusing the recolor shader the
# MetallicShine fix introduced -- modulate would only multiply, which is the
# trap this project has now hit twice.
static func _apply_blend_amount(node: CanvasItem, tint: Color,
		amount: float) -> void:
	if _recolor_shader == null:
		_recolor_shader = Shader.new()
		_recolor_shader.code = _RECOLOR_SHADER_CODE
	var mat := node.material as ShaderMaterial
	if mat == null or mat.shader != _recolor_shader:
		mat = ShaderMaterial.new()
		mat.shader = _recolor_shader
		node.material = mat
	mat.set_shader_parameter("gray", 0.0)
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("tint_amount", clampf(amount, 0.0, 1.0))


# AnimTask_FlashAnimTagWithColor (battle_anim_normal.c:747). args: 0 anim tag,
# 1 delay (low byte) with bit 8 as the alternation flag, 2 blend count,
# 3/4 colour+strength A, 5/6 colour+strength B.
#
# Unlike the exclude-blend above this touches exactly ONE palette, which here
# is 1:1 with a sprite sheet -- so it maps cleanly onto tinting every live
# sprite of that tag. The one behaviour with no texture analogue is that it
# also catches sprites spawned LATER while the blend is applied; that is
# disclosed rather than emulated. It restores itself, so nothing leaks.
static func _flash_anim_tag_with_color(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var stage = vm.stage
	if stage == null or not stage.has_method("layer"):
		return
	var layer: Control = stage.layer()
	if layer == null:
		return
	var tag_name := str(AnimData.tag_row(str(vm.args[0])).get("name", ""))
	var delay: int = maxi(0, vm.args[1] & 0xFF)
	var blends: int = maxi(1, vm.args[2])
	var col_a := _gba_rgb_to_color(vm.args[3])
	var amt_a := clampf(float(vm.args[4]) / 16.0, 0.0, 1.0)
	var col_b := _gba_rgb_to_color(vm.args[5])
	var amt_b := clampf(float(vm.args[6]) / 16.0, 0.0, 1.0)

	var st := {"left": blends, "tick": 0, "alt": false}
	vm.add_stepper(func() -> bool:
		st["tick"] = int(st["tick"]) + 1
		if int(st["tick"]) <= delay:
			return false
		st["tick"] = 0
		var col: Color = col_b if bool(st["alt"]) else col_a
		var amt: float = amt_b if bool(st["alt"]) else amt_a
		for child in layer.get_children():
			if child is AnimSprite and (tag_name == ""
					or (child as AnimSprite).tag_name == tag_name):
				_apply_blend_amount(child, col, amt)
		st["alt"] = not bool(st["alt"])
		st["left"] = int(st["left"]) - 1
		if int(st["left"]) <= 0:
			# Upstream's final fade returns the palette to unblended.
			for child in layer.get_children():
				if child is AnimSprite:
					_apply_blend_amount(child, col, 0.0)
			return true
		return false)


# AnimFlashingHitSplat (battle_anim_normal.c:1186, step :1199). args: 0/1
# offset, 2 battler, 3 affine variant.
#
# Despite the name and the company it keeps, this does NO palette work at all:
# it toggles visibility every single frame for 14 frames. Grouped here only by
# association, and recorded so nobody looks for a palette effect that is not
# there.
static func _flashing_hit_splat(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var battler: int = AnimStage.ANIM_ATTACKER if vm.args[2] == 0 \
			else AnimStage.ANIM_TARGET
	node.scale = Vector2.ONE * scale * _HIT_SPLAT_SCALES[clampi(vm.args[3], 0,
			_HIT_SPLAT_SCALES.size() - 1)]
	node.centre = _positioned_centre(vm, battler, vm.args[0], vm.args[1], scale)
	var st := {"t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.visible = not node.visible
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) > 13:
			node.finish()
			return true
		return false)


# ── the tail ──────────────────────────────────────────────────────────────

# AnimTask_SkillSwap (battle_anim_psychic.c:954, step :1062), shared verbatim
# with AnimTask_HeartSwap (:1006) -- upstream's own comment says so. args:
# 0 direction. Spawns 12 orbs, one every 7 frames, each arcing for 16 frames
# between the two battlers' corners. ~102 frames.
static func _skill_swap(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var scale := _scale(vm)
	var to_attacker: bool = vm.args[0] != 0
	var from_b: int = AnimStage.ANIM_TARGET if to_attacker \
			else AnimStage.ANIM_ATTACKER
	var to_b: int = AnimStage.ANIM_ATTACKER if to_attacker \
			else AnimStage.ANIM_TARGET
	var start := _battler_centre(vm, from_b)
	var dest := _battler_centre(vm, to_b)
	var arc := (-10.0 if to_attacker else 10.0) * scale
	var st := {"t": 0, "made": 0}
	vm.add_stepper(func() -> bool:
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) % 7 == 0 and int(st["made"]) < 12:
			var orb := _make_sprite(vm, ctx)
			if orb != null:
				orb.centre = start
				_arc_travel(vm, orb, start, dest, 16, arc)
			st["made"] = int(st["made"]) + 1
		return int(st["made"]) >= 12 and int(st["t"]) > 12 * 7 + 17)


# AnimFollowMeFinger (battle_anim_effects_1.c:7157, steps :7181 / :7186).
# args: 0 battler. Pauses 13 frames, then wags: the horizontal is 1.5x a sine
# eighth, swept 4/256 per frame, so one full wag is 64 frames. Terminates
# through AnimMetronomeFinger_Step, which it shares with Metronome.
static func _follow_me_finger(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var battler: int = AnimStage.ANIM_ATTACKER if vm.args[0] == 0 \
			else AnimStage.ANIM_TARGET
	var mon := _battler_node(vm, battler)
	var top := mon.position.y if mon != null else 0.0
	var base := Vector2(_battler_centre(vm, battler).x,
			maxf(10.0 * scale, top))
	node.centre = base
	var st := {"phase": 0, "t": 0, "angle": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		match int(st["phase"]):
			0:
				st["t"] = int(st["t"]) + 1
				if int(st["t"]) > 12:
					st["phase"] = 1
					st["t"] = 0
			1:
				st["angle"] = int(st["angle"]) + 4
				var sx := _gba_sin(int(st["angle"]) & 0xFF, 1.0)
				node.centre = base + Vector2(sx * 1.5 * 32.0 * scale / 8.0,
						0.0)
				if int(st["angle"]) > 254:
					node.centre = base
					st["phase"] = 2
					st["t"] = 0
			2:
				st["t"] = int(st["t"]) + 1
				if int(st["t"]) > 16:
					node.finish()
					return true
		return false)


# AnimFocusPunchFist (battle_anim_fight.c:1013). Reads NO args. The shrink is
# the template's affine anim; the SHAKE only begins once that ends -- a sine
# of amplitude 2 stepping 40/256 per frame, for 41 frames.
static func _focus_punch_fist(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var base := node.centre
	var st := {"phase": 0, "t": 0, "angle": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		if int(st["phase"]) == 0:
			st["t"] = int(st["t"]) + 1
			if node.anim_ended() or int(st["t"]) >= 8:
				st["phase"] = 1
				st["t"] = 0
			return false
		st["angle"] = (int(st["angle"]) + 40) & 0xFF
		node.centre = base + Vector2(_gba_sin(int(st["angle"]), 2.0 * scale),
				0.0)
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) > 40:
			node.finish()
			return true
		return false)


# AnimTask_StockpileDeformMon (battle_anim_effects_3.c:2269), shared by
# SpitUp (:2281) and Swallow (:2314) -- identical bodies, only the affine
# table differs. A squash/stretch cycle of 36 frames run twice = 72.
static func _stockpile_deform_mon(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var node := _battler_node(vm, AnimStage.ANIM_ATTACKER)
	if node == null:
		return
	var base_scale := node.scale
	var st := {"t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		st["t"] = int(st["t"]) + 1
		var t: int = int(st["t"])
		# 36-frame cycle: squash for 12, overshoot back for 12, settle for 12.
		var phase := t % 36
		var f := 0.0
		if phase < 12:
			f = float(phase) / 12.0 * 8.0
		elif phase < 24:
			f = 8.0 - float(phase - 12) / 12.0 * 16.0
		else:
			f = -8.0 + float(phase - 24) / 12.0 * 8.0
		node.scale = Vector2(base_scale.x * (1.0 + f / 256.0),
				base_scale.y * (1.0 - f / 256.0))
		if t >= 72:
			node.scale = base_scale
			return true
		return false)


# AnimGrantingStars (battle_anim_effects_1.c:5407). args: 0/1 offset,
# 2 battler, 3/4 velocity (8.8), 5 duration.
#
# Reproduces a real upstream quirk: args 0 and 1 are applied TWICE -- once by
# the position helper and again immediately after. Left as-is because the
# scripts were authored against the doubled offset.
static func _granting_stars(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var battler: int = AnimStage.ANIM_ATTACKER if vm.args[2] == 0 \
			else AnimStage.ANIM_TARGET
	var start := _positioned_centre(vm, battler, vm.args[0], vm.args[1], scale)
	start += Vector2(float(vm.args[0]) * _facing(vm), float(vm.args[1])) * scale
	node.centre = start
	_velocity_travel(vm, node, start,
			Vector2(float(vm.args[3]), float(vm.args[4])) * scale,
			maxi(1, vm.args[5]))


# AnimSweetScentPetal (battle_anim_effects_3.c:2986, step :3004). args:
# 0 initial y, 1 anim variant, 2 unused. Enters from a SCREEN EDGE, not from a
# battler -- crosses at 5px/frame while weaving, and dies on leaving the far
# side, so its life depends on the stage width rather than a duration.
static func _sweet_scent_petal(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var layer: Control = vm.stage.layer() if vm.stage != null \
			and vm.stage.has_method("layer") else null
	var width: float = layer.size.x if layer != null else 1024.0
	var player := _is_player_side(vm)
	var pos := Vector2(0.0, float(vm.args[0]) * scale) if player \
			else Vector2(width, float(vm.args[0] - 30) * scale)
	_apply_anim_variant(node, ctx, vm.args[1])
	node.centre = pos
	var st := {"pos": pos, "angle": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["angle"] = int(st["angle"]) + 3
		var p: Vector2 = st["pos"]
		p.x += (5.0 if player else -5.0) * scale
		p.y += (-1.0 if player else 1.0) * scale
		st["pos"] = p
		var wave := _gba_sin(int(st["angle"]) & 0xFF, 16.0 * scale) if player \
				else _gba_cos(int(st["angle"]) & 0xFF, 16.0 * scale)
		node.centre = p + Vector2(0.0, wave)
		if (player and p.x > width) or (not player and p.x < 0.0):
			node.finish()
			return true
		return false)


# AnimTask_GrudgeFlames (battle_anim_ghost.c:1235, step :1261). No args.
# Spawns SIX flames in one frame, evenly spread around the attacker, each
# orbiting horizontally at 2 units/frame (a 128-frame lap) while bobbing at 8.
# The task fades them in, holds 30 frames, fades out, then waits for every
# flame to die before clearing its blend.
static func _grudge_flames(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var scale := _scale(vm)
	var centre := _battler_centre(vm, AnimStage.ANIM_ATTACKER)
	var mon := _battler_node(vm, AnimStage.ANIM_ATTACKER)
	var radius := ((mon.size.x * 0.5) if mon != null else 32.0) + 8.0 * scale
	var flames: Array = []
	for i in range(6):
		var f := _make_sprite(vm, ctx)
		if f == null:
			continue
		f.modulate.a = 0.0
		flames.append({"node": f, "angle": (i * 42) & 0xFF, "bob": i * 6})
	if flames.is_empty():
		return
	var player := _is_player_side(vm)
	var st := {"phase": 0, "t": 0, "alpha": 0.0}
	vm.add_stepper(func() -> bool:
		var alive := 0
		for e in flames:
			var n: AnimSprite = e["node"]
			if not is_instance_valid(n):
				continue
			alive += 1
			e["angle"] = (int(e["angle"]) + (2 if player else -2)) & 0xFF
			e["bob"] = int(e["bob"]) + 1
			n.centre = centre + Vector2(
					_gba_sin(int(e["angle"]), radius),
					_gba_sin((int(e["bob"]) * 8) & 0xFF, 7.0 * scale))
			n.modulate.a = float(st["alpha"])
		if alive == 0:
			return true
		st["t"] = int(st["t"]) + 1
		match int(st["phase"]):
			0:
				st["alpha"] = minf(0.875, float(st["alpha"]) + 1.0 / 32.0)
				if float(st["alpha"]) >= 0.875:
					st["phase"] = 1
					st["t"] = 0
			1:
				if int(st["t"]) >= 30:
					st["phase"] = 2
			2:
				st["alpha"] = maxf(0.0, float(st["alpha"]) - 1.0 / 32.0)
				if float(st["alpha"]) <= 0.0:
					for e in flames:
						if is_instance_valid(e["node"]):
							(e["node"] as AnimSprite).finish()
					return true
		return false)


# AnimTask_StatusClearedEffect (battle_anim_effects_3.c:4070). args: 0 include
# partner. Upstream this is StartMonScrollingBgMask -- an OBJ-window masked BG
# scroll: cure bubbles scroll UNDER a stencil shaped like the mon, so they
# appear only inside its silhouette. ~90 frames, fully self-restoring.
#
# There is no object-window here, so this is the same approximation
# MetallicShine uses: a masked overlay standing in for the stencil. The scroll
# rate, the 10-step fade, the 30-frame hold and the fade-out are source-exact.
static func _status_cleared_effect(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var node := _battler_node(vm, AnimStage.ANIM_ATTACKER)
	if node == null:
		return
	var overlay := _make_shine_overlay(vm, node)
	if overlay == null:
		return
	overlay.modulate = Color(0.7, 0.9, 1.0, 0.0)
	var st := {"phase": 0, "t": 0, "a": 0.0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(overlay):
			return true
		st["t"] = int(st["t"]) + 1
		match int(st["phase"]):
			0:
				if int(st["t"]) % 2 == 0:
					st["a"] = minf(1.0, float(st["a"]) + 0.1)
					if float(st["a"]) >= 1.0:
						st["phase"] = 1
						st["t"] = 0
			1:
				if int(st["t"]) >= 30:
					st["phase"] = 2
					st["t"] = 0
			2:
				if int(st["t"]) % 2 == 0:
					st["a"] = maxf(0.0, float(st["a"]) - 0.1)
					if float(st["a"]) <= 0.0:
						overlay.queue_free()
						return true
		overlay.modulate.a = float(st["a"])
		return false)


# AnimArmThrustHit (battle_anim_fight.c:965, step :957). args: 0/1 offset,
# 2 duration, 3 base anim index. Completely STATIC -- it appears, waits, and
# goes. Its one piece of logic is that alternating hits mirror: on odd turns
# the x offset flips and the anim index advances, so a flurry does not stack
# every hit in the same spot.
static func _arm_thrust_hit(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var variant: int = vm.args[3]
	var x_off := float(vm.args[0])
	var turn: int = vm.turn
	if not _is_player_side(vm):
		turn += 1
	if turn % 2 == 1:
		x_off = -x_off
		variant += 1
	_apply_anim_variant(node, ctx, variant)
	node.centre = _battler_centre(vm, AnimStage.ANIM_TARGET) \
			+ Vector2(x_off, float(vm.args[1])) * scale
	var life: int = maxi(1, vm.args[2])
	var st := {"t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) >= life:
			node.finish()
			return true
		return false)


# AnimTask_Splash (battle_anim_effects_2.c:2097, step :2118). args: 0 battler,
# 1 hop count -- and zero hops destroys immediately. Each hop is 24 frames of
# affine squash plus a real fall: +3px/frame acceleration for 8 frames, then 8
# at constant speed, then a decelerating settle. Restores y offset on exit.
static func _splash(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var hops: int = vm.args[1]
	if hops <= 0:
		return
	var battler: int = AnimStage.ANIM_ATTACKER if vm.args[0] == 0 \
			else AnimStage.ANIM_TARGET
	var node := _battler_node(vm, battler)
	if node == null:
		return
	var scale := _scale(vm)
	var mon := MonOffset.new(node)
	var st := {"hop": 0, "phase": 0, "t": 0, "v": 0.0, "y": 0.0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		match int(st["phase"]):
			0:
				st["v"] = float(st["v"]) + 3.0
				st["y"] = float(st["y"]) + float(st["v"])
				st["t"] = int(st["t"]) + 1
				if int(st["t"]) > 7:
					st["phase"] = 1
					st["t"] = 0
			1:
				st["y"] = float(st["y"]) + float(st["v"])
				st["t"] = int(st["t"]) + 1
				if int(st["t"]) > 7:
					st["phase"] = 2
			2:
				if float(st["v"]) > 0.0:
					st["y"] = float(st["y"]) - 2.0
					st["v"] = float(st["v"]) - 2.0
				else:
					st["hop"] = int(st["hop"]) + 1
					if int(st["hop"]) >= hops:
						mon.restore()
						return true
					st["phase"] = 0
					st["t"] = 0
					st["v"] = 0.0
					st["y"] = 0.0
		mon.apply(Vector2(0.0, float(st["y"]) * scale / 4.0))
		return false)


# AnimUproarRing (battle_anim_effects_2.c:2625). args: 0-3 placement,
# 4 blend colour, 5 blend coefficient.
#
# Worth noting because it is easy to miss: this DOES touch a palette, tinting
# the ring sheet once at setup and never restoring it. Here that is a per-node
# tint, so it goes with the sprite and cannot leak.
static func _uproar_ring(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var battler: int = AnimStage.ANIM_ATTACKER if vm.args[2] == 0 \
			else AnimStage.ANIM_TARGET
	node.centre = _positioned_centre(vm, battler, vm.args[0], vm.args[1], scale)
	if vm.args[5] != 0:
		_apply_blend_amount(node, _gba_rgb_to_color(vm.args[4]),
				clampf(float(vm.args[5]) / 16.0, 0.0, 1.0))
	_play_until_anim_ends(vm, node, _ANIM_END_CAP)


# AnimSpinningSparkle (battle_anim_mons.c:2304) and AnimLeer
# (battle_anim_effects_3.c:1542) are the same four-line shape: attacker
# coords, two offsets, live as long as the sprite anim. They differ in ONE
# detail -- Leer mirrors its x offset by relative battler POSITION, the
# sparkle by which side the attacker is on. Identical head-on, so they are
# kept separate only because that difference is real in doubles.
static func _spinning_sparkle(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var x := float(vm.args[0]) * (1.0 if _is_player_side(vm) else -1.0)
	node.centre = _battler_centre(vm, AnimStage.ANIM_ATTACKER) \
			+ Vector2(x, float(vm.args[1])) * scale
	_play_until_anim_ends(vm, node, _ANIM_END_CAP)


static func _leer(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	node.centre = _positioned_centre(vm, AnimStage.ANIM_ATTACKER, vm.args[0],
			vm.args[1], scale)
	_play_until_anim_ends(vm, node, _ANIM_END_CAP)


# AnimTearDrop (battle_anim_dark.c:438, step :486). args: 0 battler,
# 1 corner variant 0-3. Arcs 20px sideways and 12px down over exactly 32
# frames, with a -12 amplitude (upward) sine on top. The two right-hand
# variants mirror and flip.
static func _tear_drop(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var battler: int = AnimStage.ANIM_ATTACKER if vm.args[0] == 0 \
			else AnimStage.ANIM_TARGET
	var variant: int = clampi(vm.args[1], 0, 3)
	var mon := _battler_node(vm, battler)
	var box := mon.size if mon != null else Vector2(64, 64)
	var c := _battler_centre(vm, battler)
	var right := variant < 2
	var x_edge := (box.x * 0.5) * (1.0 if right else -1.0)
	var inset := (8.0 if variant % 2 == 0 else 14.0) * scale
	var start := c + Vector2(x_edge - inset * (1.0 if right else -1.0),
			-box.y * 0.5 + (8.0 if variant % 2 == 0 else 16.0) * scale)
	var x_off := (20.0 if right else -20.0) * scale
	node.centre = start
	if not right:
		node.flip_h = true
	_arc_travel(vm, node, start, start + Vector2(x_off, 12.0 * scale), 32,
			-12.0 * scale)


# AnimTask_StretchTargetUp (battle_anim_effects_2.c:3087), shared verbatim
# with AnimTask_StretchAttackerUp (:3107). No args. 10 frames of widen-and-
# shorten then 10 back, with the sprite jittering +/-4px every frame on top.
# Restores both offsets and scale.
static func _stretch_target_up(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	_stretch_common(vm, AnimStage.ANIM_TARGET)


static func _stretch_attacker_up(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	_stretch_common(vm, AnimStage.ANIM_ATTACKER)


static func _stretch_common(vm: AnimScriptVM, battler: int) -> void:
	var node := _battler_node(vm, battler)
	if node == null:
		return
	var scale := _scale(vm)
	var mon := MonOffset.new(node)
	var base_scale := node.scale
	var st := {"t": 0, "sx": 0.0, "sy": 0.0, "jit": 4.0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		st["t"] = int(st["t"]) + 1
		var t: int = int(st["t"])
		if t <= 10:
			st["sx"] = float(st["sx"]) + 10.0
			st["sy"] = float(st["sy"]) - 13.0
		else:
			st["sx"] = float(st["sx"]) - 10.0
			st["sy"] = float(st["sy"]) + 13.0
		node.scale = Vector2(base_scale.x * (1.0 + float(st["sx"]) / 256.0),
				base_scale.y * (1.0 + float(st["sy"]) / 256.0))
		st["jit"] = -float(st["jit"])
		mon.apply(Vector2(float(st["jit"]) * scale, 0.0))
		if t >= 21:
			node.scale = base_scale
			mon.restore()
			return true
		return false)


# AnimTask_TeeterDanceMovement (battle_anim_effects_3.c:5502, step :5516).
# No args. TWO superimposed sines: a fast +/-8px wobble on a 32-frame period
# and a slow +/-32px sway on a 128-frame one, which is what makes it read as
# unsteady rather than as a simple shake. Restores position; never touches y.
static func _teeter_dance_movement(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var node := _battler_node(vm, AnimStage.ANIM_ATTACKER)
	if node == null:
		return
	var scale := _scale(vm)
	var mon := MonOffset.new(node)
	var dir := 1.0 if _is_player_side(vm) else -1.0
	var st := {"fast": 0, "slow": 0, "phase": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		st["fast"] = (int(st["fast"]) + 8) & 0xFF
		var wobble := _gba_sin(int(st["fast"]), 8.0 * scale)
		if int(st["phase"]) == 0:
			st["slow"] = (int(st["slow"]) + 2) & 0xFF
			var sway := _gba_sin(int(st["slow"]), 32.0 * scale) * dir
			mon.apply(Vector2(wobble + sway, 0.0))
			if int(st["slow"]) == 0:
				st["phase"] = 1
			return false
		mon.apply(Vector2(wobble, 0.0))
		if int(st["fast"]) == 0:
			mon.restore()
			return true
		return false)


# AnimAngerMark (battle_anim_effects_2.c:2230). args: 0 battler, 1/2 offset.
# Trivial: place (mirrored for an opponent-side battler, clamped away from the
# top edge) and live as long as the affine anim.
static func _anger_mark(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var battler: int = AnimStage.ANIM_TARGET if vm.args[0] != 0 \
			else AnimStage.ANIM_ATTACKER
	var x := float(vm.args[1])
	if not _is_player_side(vm):
		x = -x
	var pos := _battler_centre(vm, battler) \
			+ Vector2(x, float(vm.args[2])) * scale
	pos.y = maxf(8.0 * scale, pos.y)
	node.centre = pos
	_play_until_anim_ends(vm, node, _ANIM_END_CAP)


# SpriteCB_LockingJaw (battle_anim_new.c:6975, steps :6986 / :6995). args:
# 0/1 offset, 2 affine variant, 3/4 velocity (8.8), 5 bite frames, 6 hold.
#
# The timing is asymmetric and easy to get wrong: it MOVES for `bite` frames,
# then FREEZES in place and counts back down from bite to -hold, so the total
# is 2*bite + hold, not bite + hold.
static func _locking_jaw(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var start := _battler_centre(vm, AnimStage.ANIM_TARGET) \
			+ Vector2(float(vm.args[0]), float(vm.args[1])) * scale
	node.centre = start
	_apply_anim_variant(node, ctx, vm.args[2])
	var vel := Vector2(float(vm.args[3]), float(vm.args[4])) * scale
	var bite: int = maxi(1, vm.args[5])
	var hold: int = maxi(0, vm.args[6])
	var st := {"t": 0, "acc": Vector2.ZERO, "phase": 0, "down": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		if int(st["phase"]) == 0:
			st["acc"] = (st["acc"] as Vector2) + vel
			node.centre = start + (st["acc"] as Vector2) / 256.0
			st["t"] = int(st["t"]) + 1
			if int(st["t"]) >= bite:
				st["phase"] = 1
				st["down"] = bite
			return false
		st["down"] = int(st["down"]) - 1
		if int(st["down"]) <= -hold:
			node.finish()
			return true
		return false)


# ─── [M36D batch 6] ───────────────────────────────────────────────────────
#
# MOVE-targeted rather than family-targeted, and that is a deliberate change
# from batch 5. Reading each blocked iconic move's ACTUAL missing set (rather
# than inferring it from a family name, which is how batch 5 picked an ice
# cluster that did not unblock Ice Beam) showed there is almost no sharing
# left: only AnimIceEffectParticle (Ice Beam + Blizzard) and
# AnimDirtPlumeParticle (Fissure + Dig) block two moves each. Everything else
# blocks exactly one. So this batch is a list of moves, not of families.
#
# Three existing helpers absorbed a good part of it, per Step 0:
#   * `_linear_travel`  -- IceBeamParticle, WaterGunDroplet, SolarBeamBigOrb
#   * `_arc_travel`     -- ThrowProjectile, SludgeProjectile, DirtPlumeParticle
#                          (all three share ONE step function upstream)
#   * `_velocity_travel`-- SludgeBombHitParticle, with a decay term on top


# AnimTask_SetAllNonAttackersInvisiblity (battle_anim_utility_funcs.c:760).
# arg0 is the boolean written into `.invisible`. One frame, and it RESTORES
# NOTHING -- it is a raw setter, and the script is responsible for the paired
# call with arg0 = 0. Routed through the VM's own visibility tracking so that
# a script which never makes that second call cannot leave a Pokemon hidden
# for the rest of the battle.
static func _set_all_non_attackers_invisible(vm: AnimScriptVM,
		_ctx: Dictionary) -> void:
	var hide: bool = vm.args[0] != 0
	for i in range(4):
		if i == AnimStage.ANIM_ATTACKER:
			continue
		var n := _battler_node(vm, i)
		if n != null and is_instance_valid(n):
			vm.set_battler_visible_tracked(i, not hide)


# AnimIceBeamParticle (battle_anim_ice.c:665). args: 0/1 start offset,
# 2/3 destination offset, 4 duration. The canonical linear-translation shape,
# with the destination's x offset mirrored for an opponent-side attacker.
static func _ice_beam_particle(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var start := _positioned_centre(vm, AnimStage.ANIM_ATTACKER, vm.args[0],
			vm.args[1], scale)
	var dx := float(vm.args[2]) * (1.0 if _is_player_side(vm) else -1.0)
	var dest := _battler_centre(vm, AnimStage.ANIM_TARGET) \
			+ Vector2(dx, float(vm.args[3])) * scale
	node.centre = start
	_linear_travel(vm, node, start, dest, maxi(1, vm.args[4]))


# AnimIceEffectParticle (battle_anim_ice.c:686, step :706). args: 0/1 offset,
# 2 average-both-targets flag. Plays its affine anim, then FLICKERS for
# exactly 20 frames before dying -- the flicker is the whole tell that the
# target is freezing rather than just being hit.
#
# Shared by Ice Beam and Blizzard, and by five more scripts besides.
static func _ice_effect_particle(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var x := float(vm.args[0])
	if vm.args[2] != 0 and not _is_player_side(vm):
		x = -x
	node.centre = _battler_centre(vm, AnimStage.ANIM_TARGET) \
			+ Vector2(x, float(vm.args[1])) * scale
	var st := {"phase": 0, "t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		if int(st["phase"]) == 0:
			st["t"] = int(st["t"]) + 1
			if node.anim_ended() or int(st["t"]) >= _ANIM_END_CAP:
				st["phase"] = 1
				st["t"] = 0
			return false
		node.visible = not node.visible
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) >= 20:
			node.finish()
			return true
		return false)


# AnimMoveParticleBeyondTarget (battle_anim_ice.c:843, step :902) and
# AnimSwirlingSnowball (:721). Step 0 found these share ~90% of their setup.
#
# Both do something genuinely odd that has to be reproduced or the effect is
# wrong: they run a BLOCKING pre-simulation that walks the sprite BACKWARDS
# until it is off-screen behind the attacker, bake that as the real start, and
# only then run forward. That is what lets the particle pass THROUGH the
# target and exit the far side rather than stopping on it.
#
# Ported as the equivalent closed form -- project backwards along the travel
# direction until outside the stage -- rather than as a literal while-loop,
# because a blocking loop inside a per-frame stepper would stall the frame.
static func _particle_beyond_target(vm: AnimScriptVM, ctx: Dictionary) -> void:
	_beyond_target_common(vm, ctx, false)


static func _swirling_snowball(vm: AnimScriptVM, ctx: Dictionary) -> void:
	_beyond_target_common(vm, ctx, true)


static func _beyond_target_common(vm: AnimScriptVM, ctx: Dictionary,
		swirl: bool) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var layer: Control = vm.stage.layer() if vm.stage != null \
			and vm.stage.has_method("layer") else null
	var bounds := layer.size if layer != null else Vector2(1024, 768)
	var origin := _positioned_centre(vm, AnimStage.ANIM_ATTACKER, vm.args[0],
			vm.args[1], scale)
	var dx := float(vm.args[2]) * (1.0 if _is_player_side(vm) else -1.0)
	var dest := _battler_centre(vm, AnimStage.ANIM_TARGET) \
			+ Vector2(dx, float(vm.args[3])) * scale
	var dir := (dest - origin).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2(1, 0)
	# The pre-simulation's closed form: far enough back to be off-stage.
	var back := bounds.length()
	var start := origin - dir * back
	node.centre = start
	var speed := maxf(1.0, float(vm.args[4])) / 16.0 * scale
	var amp := float(vm.args[5]) * scale
	var freq: int = vm.args[6]
	var st := {"pos": start, "wave": 0, "phase": 0, "t": 0, "orbit": 128}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		if swirl and int(st["phase"]) == 1:
			# AnimSwirlingSnowball_Step2: two full revolutions in exactly 32
			# frames (16 units of 256 per frame), then carry on outward.
			st["orbit"] = (int(st["orbit"]) + 16) & 0xFF
			st["t"] = int(st["t"]) + 1
			node.centre = (st["pos"] as Vector2) + Vector2(
					_gba_sin(int(st["orbit"]), 20.0 * scale),
					_gba_cos(int(st["orbit"]), 15.0 * scale))
			if int(st["t"]) >= 32:
				st["phase"] = 2
			return false
		var p: Vector2 = (st["pos"] as Vector2) + dir * speed
		st["pos"] = p
		var off := Vector2.ZERO
		if not swirl:
			off.y = _gba_sin(int(st["wave"]), amp)
			st["wave"] = (int(st["wave"]) + freq) & 0xFF
		node.centre = p + off
		if swirl and int(st["phase"]) == 0 \
				and p.distance_to(dest) < speed * 2.0:
			st["phase"] = 1
			st["t"] = 0
		# Terminated only by leaving the screen, never by a frame count.
		if p.x < -32.0 * scale or p.x > bounds.x + 32.0 * scale \
				or p.y < -32.0 * scale or p.y > bounds.y + 32.0 * scale:
			node.finish()
			return true
		return false)


# AnimThrowProjectile (battle_anim_mons.c:1530). args: 0/1 start offset,
# 2/3 end offset, 4 duration, 5 arc amplitude.
#
# Step 0 found its step function is byte-identical to SludgeProjectile's and
# DirtPlumeParticle's -- all three are `if (TranslateAnimHorizontalArc)
# DestroyAnimSprite`, so all three are one call to the existing `_arc_travel`.
static func _throw_projectile(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var start := _positioned_centre(vm, AnimStage.ANIM_ATTACKER, vm.args[0],
			vm.args[1], scale)
	var dx := float(vm.args[2]) * (1.0 if _is_player_side(vm) else -1.0)
	var dest := _battler_centre(vm, AnimStage.ANIM_TARGET) \
			+ Vector2(dx, float(vm.args[3])) * scale
	node.centre = start
	_arc_travel(vm, node, start, dest, maxi(1, vm.args[4]),
			float(vm.args[5]) * scale)


# AnimWaterGunDroplet (battle_anim_water.c:951). args: 0/1 offset, 2 x delta,
# and 4 as BOTH the duration and the y delta -- arg 3 is unused. Reproduced as
# written; it is the kind of arg aliasing that looks like a typo but is what
# the scripts were authored against.
static func _water_gun_droplet(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var start := _positioned_centre(vm, AnimStage.ANIM_TARGET, vm.args[0],
			vm.args[1], scale)
	node.centre = start
	_linear_travel(vm, node, start, start
			+ Vector2(float(vm.args[2]), float(vm.args[4])) * scale,
			maxi(1, vm.args[4]))


# AnimAuroraBeamRings (battle_anim_water.c:747, step :767). args: 0/1 start
# offset, 2/3 destination offset, 4 duration -- plus arg 7 read LIVE as a
# signal. The ring travels with its affine anim FROZEN, and the script
# unfreezes it by writing -1 into arg 7, which is how the beam's end is
# synchronised with the rings already in flight.
static func _aurora_beam_rings(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var start := _positioned_centre(vm, AnimStage.ANIM_ATTACKER, vm.args[0],
			vm.args[1], scale)
	var dx := float(vm.args[2]) * (1.0 if _is_player_side(vm) else -1.0)
	var dest := _battler_centre(vm, AnimStage.ANIM_TARGET) \
			+ Vector2(dx, float(vm.args[3])) * scale
	node.centre = start
	var duration: int = maxi(1, vm.args[4])
	var st := {"t": 0, "released": false}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		if not bool(st["released"]) \
				and vm.args[AnimScriptVM.ARG_RET] == -1:
			st["released"] = true
			node.advance_frame()
		elif bool(st["released"]):
			node.advance_frame()
		st["t"] = int(st["t"]) + 1
		node.centre = start.lerp(dest, float(st["t"]) / float(duration))
		if int(st["t"]) >= duration:
			node.finish()
			return true
		return false)


# AnimTask_RotateAuroraRingColors (battle_anim_water.c:779, step :786).
# arg0 = duration. Rotates 8 palette entries LEFT once every 3 frames, which
# is what makes the rings appear to flow. Same mechanism as the psychic
# background cycle from M36E3, over the ring sheet's own palette.
#
# Upstream never restores the rotation -- it is invisible because the sprite
# palette is freed with the animation. Here the tint goes with the sprites, so
# there is likewise nothing to leak.
static func _rotate_aurora_ring_colors(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var stage = vm.stage
	if stage == null or not stage.has_method("layer"):
		return
	var layer: Control = stage.layer()
	if layer == null:
		return
	var duration: int = maxi(1, vm.args[0])
	var st := {"t": 0, "tick": 0, "step": 0}
	vm.add_stepper(func() -> bool:
		st["t"] = int(st["t"]) + 1
		st["tick"] = int(st["tick"]) + 1
		if int(st["tick"]) >= 3:
			st["tick"] = 0
			st["step"] = int(st["step"]) + 1
			# The visible consequence of an 8-entry rotate on a ring sheet is
			# a hue sweep; applied per-sprite since there is no palette here.
			var h := fmod(float(st["step"]) / 8.0, 1.0)
			for child in layer.get_children():
				if child is AnimSprite:
					(child as AnimSprite).modulate = Color.from_hsv(h, 0.35,
							1.0, (child as AnimSprite).modulate.a)
		if int(st["t"]) >= duration:
			for child in layer.get_children():
				if child is AnimSprite:
					(child as AnimSprite).modulate = Color(1, 1, 1,
							(child as AnimSprite).modulate.a)
			return true
		return false)


# AnimSparkElectricityFlashing (battle_anim_electric.c:760, step :787). args:
# 0/1 offset, 2 radius, 3 lifetime, 4 initial angle, 5 angular step,
# 6 tile selector, 7 a BITFIELD -- bit 15 picks the target instead of the
# attacker, and the low 15 bits are the flicker modulus.
static func _spark_electricity_flashing(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var flags: int = vm.args[7]
	var battler: int = AnimStage.ANIM_TARGET if (flags & 0x8000) != 0 \
			else AnimStage.ANIM_ATTACKER
	var x := float(vm.args[0])
	if _is_player_side(vm):
		x = -x
	var base := _battler_centre(vm, battler) \
			+ Vector2(x, float(vm.args[1])) * scale
	node.set_tile_offset(vm.args[6] * 4)
	var radius := float(vm.args[2]) * scale
	var modulus: int = maxi(1, flags & 0x7FFF)
	var life: int = maxi(1, vm.args[3])
	var st := {"angle": vm.args[4], "t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		var a: int = int(st["angle"])
		node.centre = base + Vector2(_gba_sin(a, radius), _gba_cos(a, radius))
		st["angle"] = (a + vm.args[5]) & 0xFF
		if int(st["angle"]) % modulus == 0:
			node.visible = not node.visible
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) > life:
			node.finish()
			return true
		return false)


# AnimThunderboltOrb (battle_anim_electric.c:748, step :737). args: 0 lifetime,
# 1/2 offset, 3 flicker interval. Static and flickering. Note upstream does NOT
# invoke its step on the setup frame, so the first frame is a pure wait.
static func _thunderbolt_orb(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var x := float(vm.args[1])
	if _is_player_side(vm):
		x = -x
	node.centre = _battler_centre(vm, AnimStage.ANIM_TARGET) \
			+ Vector2(x, float(vm.args[2])) * scale
	var interval: int = maxi(1, vm.args[3])
	var life: int = maxi(1, vm.args[0])
	var st := {"t": 0, "flick": interval}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		st["flick"] = int(st["flick"]) - 1
		if int(st["flick"]) < 0:
			node.visible = not node.visible
			st["flick"] = interval
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) > life:
			node.finish()
			return true
		return false)


# AnimSolarBeamBigOrb (battle_anim_effects_1.c:3084). args: 0/1 offset,
# 2 duration, 3 anim index. Straight linear travel with no per-side fudge at
# all -- unusual in this batch, and deliberate upstream.
static func _solar_beam_big_orb(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	_apply_anim_variant(node, ctx, vm.args[3])
	var start := _positioned_centre(vm, AnimStage.ANIM_ATTACKER, vm.args[0],
			vm.args[1], scale)
	node.centre = start
	_linear_travel(vm, node, start,
			_battler_centre(vm, AnimStage.ANIM_TARGET),
			maxi(1, vm.args[2]))


# AnimTask_CreateSmallSolarBeamOrbs (battle_anim_effects_1.c:3146). No args in
# -- and it CLOBBERS gBattleAnimArgs[0..3] for each spawn, permanently. Spawns
# 15 orbs, one every 7 frames (~99 frames). The source comment says a 7-frame
# delay; the code uses 6, which with the -1 wrap is 7 frames between spawns.
static func _create_small_solar_beam_orbs(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var st := {"t": 0, "made": 0}
	vm.add_stepper(func() -> bool:
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) % 7 == 1 and int(st["made"]) < 15:
			vm.args[0] = 15
			vm.args[1] = 0
			vm.args[2] = 80
			vm.args[3] = 0
			_solar_beam_small_orb(vm, ctx)
			st["made"] = int(st["made"]) + 1
		return int(st["made"]) >= 15 and int(st["t"]) > 15 * 7)


# AnimSolarBeamSmallOrb (battle_anim_effects_1.c:3099, step :3124). Travels to
# the target over 80 frames while weaving, and passes behind or in front of it
# depending on which half of the weave it is in.
static func _solar_beam_small_orb(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var start := _positioned_centre(vm, AnimStage.ANIM_ATTACKER, vm.args[0],
			vm.args[1], scale)
	var dest := _battler_centre(vm, AnimStage.ANIM_TARGET)
	node.centre = start
	var st := {"t": 0, "wave": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) >= 80:
			node.finish()
			return true
		var pos := start.lerp(dest, float(st["t"]) / 80.0)
		pos += Vector2(_gba_sin(int(st["wave"]), 5.0 * scale),
				_gba_cos(int(st["wave"]), 14.0 * scale))
		st["wave"] = (int(st["wave"]) + 15) & 0xFF
		node.centre = pos
		return false)


# AnimBowMon (battle_anim_effects_1.c:5709). arg0 selects one of four modes.
#
# This is a CONTROLLER sprite: it is invisible and never draws. What it moves
# is the ATTACKER'S OWN battler sprite. Mode 0 pulls back and tilts, mode 1
# lunges forward, mode 2 waits then untilts -- and mode 0 deliberately leaves
# the tilt applied, so the scripts must pair 0 with 2. Neither mode zeroes the
# displacement, which is why the VM's own end-of-run restore matters here.
static func _bow_mon(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var node := _battler_node(vm, AnimStage.ANIM_ATTACKER)
	if node == null:
		return
	var scale := _scale(vm)
	var mon := MonOffset.new(node)
	var away := 1.0 if not _is_player_side(vm) else -1.0
	match vm.args[0]:
		0:
			var st := {"t": 0}
			vm.add_stepper(func() -> bool:
				if not is_instance_valid(node):
					return true
				st["t"] = int(st["t"]) + 1
				mon.apply(Vector2(2.0 * away * float(st["t"]) * scale, 0.0))
				if int(st["t"]) >= 6:
					# The tilt, deliberately left applied for mode 2 to undo.
					node.rotation = _gba_rot_to_radians(3072) * away
					return true
				return false)
		1:
			var st2 := {"t": 0}
			vm.add_stepper(func() -> bool:
				if not is_instance_valid(node):
					return true
				st2["t"] = int(st2["t"]) + 1
				mon.apply(Vector2(-3.0 * away * float(st2["t"]) * scale, 0.0))
				return int(st2["t"]) >= 4)
		2:
			var st3 := {"t": 0, "phase": 0}
			vm.add_stepper(func() -> bool:
				if not is_instance_valid(node):
					return true
				st3["t"] = int(st3["t"]) + 1
				if int(st3["phase"]) == 0:
					if int(st3["t"]) > 8:
						st3["phase"] = 1
						st3["t"] = 0
					return false
				node.rotation = lerpf(_gba_rot_to_radians(3072) * away, 0.0,
						clampf(float(st3["t"]) / 3.0, 0.0, 1.0))
				if int(st3["t"]) >= 3:
					node.rotation = 0.0
					mon.restore()
					return true
				return false)
		_:
			pass


# AnimTask_DrillPeckHitSplats (battle_anim_flying.c:936). No args in; it WRITES
# args 0..3 per spawn. Eight splats at 45 degrees apart on a radius-13 circle,
# one every 4th frame, over 32 frames. The radius is NEGATIVE upstream, which
# inverts the points -- reproduced rather than tidied.
static func _drill_peck_hit_splats(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var scale := _scale(vm)
	var centre := _battler_centre(vm, AnimStage.ANIM_TARGET)
	var st := {"angle": 0}
	vm.add_stepper(func() -> bool:
		var a: int = int(st["angle"])
		if a % 32 == 0:
			var splat := _make_sprite(vm, ctx)
			if splat != null:
				splat.centre = centre + Vector2(_gba_sin(a, -13.0 * scale),
						_gba_cos(a, -13.0 * scale))
				_flashing_splat_life(vm, splat)
		st["angle"] = a + 8
		return int(st["angle"]) > 255)


static func _flashing_splat_life(vm: AnimScriptVM, node: AnimSprite) -> void:
	var st := {"t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.visible = not node.visible
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) > 13:
			node.finish()
			return true
		return false)


# AnimFireCross (battle_anim_fire.c:774). args: 0/1 offset from the TARGET's
# centre (it never calls a position helper), 2 duration, 3/4 per-frame delta.
# Integer velocity, no side mirroring at all.
static func _fire_cross(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var start := _battler_centre(vm, AnimStage.ANIM_TARGET) \
			+ Vector2(float(vm.args[0]), float(vm.args[1])) * scale
	node.centre = start
	var vel := Vector2(float(vm.args[3]), float(vm.args[4])) * scale
	var life: int = maxi(1, vm.args[2])
	var st := {"t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["t"] = int(st["t"]) + 1
		node.centre = start + vel * float(st["t"])
		if int(st["t"]) >= life:
			node.finish()
			return true
		return false)


# AnimFireRing (battle_anim_fire.c:701). args: 0/1 offset, 2 initial phase.
# Three real phases totalling 74 frames: circle the attacker for 18, travel to
# the target for 25 with the circle still riding on top, then circle the
# target for 31. Radius 28, 20/256 per frame throughout.
static func _fire_ring(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var origin := _positioned_centre(vm, AnimStage.ANIM_ATTACKER, vm.args[0],
			vm.args[1], scale)
	var dest := _battler_centre(vm, AnimStage.ANIM_TARGET)
	node.centre = origin
	var st := {"phase": 0, "t": 0, "ang": vm.args[2]}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var a: int = int(st["ang"])
		var circle := Vector2(_gba_sin(a, 28.0 * scale),
				_gba_cos(a, 28.0 * scale))
		st["ang"] = (a + 20) & 0xFF
		st["t"] = int(st["t"]) + 1
		match int(st["phase"]):
			0:
				node.centre = origin + circle
				if int(st["t"]) >= 18:
					st["phase"] = 1
					st["t"] = 0
			1:
				node.centre = origin.lerp(dest,
						float(st["t"]) / 25.0) + circle
				if int(st["t"]) >= 25:
					st["phase"] = 2
					st["t"] = 0
			2:
				node.centre = dest + circle
				if int(st["t"]) >= 31:
					node.finish()
					return true
		return false)


# AnimWaterPulseBubble (battle_anim_water.c:1781, step :1792). args: 0/1 are
# ABSOLUTE coordinates, not offsets -- the one behavior in this batch that
# does not position relative to a battler. 2 rise speed, 3 sine step,
# 4 amplitude, 5 lifetime.
static func _water_pulse_bubble(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var base := Vector2(float(vm.args[0]), float(vm.args[1])) * scale
	node.centre = base
	var life: int = maxi(1, vm.args[5])
	var st := {"t": 0, "rise": 0, "wave": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["rise"] = int(st["rise"]) - vm.args[2]
		st["wave"] = (int(st["wave"]) + vm.args[3]) & 0xFF
		node.centre = base + Vector2(
				_gba_sin(int(st["wave"]), float(vm.args[4]) * scale),
				float(int(st["rise"])) / 10.0 * scale)
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) >= life:
			node.finish()
			return true
		return false)


# AnimWaterPulseRing (battle_anim_water.c:1815, step :1832). args: 0/1 offset,
# 2 duration, 3 bubble-spawn interval. Uses a direct fractional lerp rather
# than the translation helper, and sheds a PAIR of bubbles every interval.
static func _water_pulse_ring(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var start := _positioned_centre(vm, AnimStage.ANIM_ATTACKER, vm.args[0],
			vm.args[1], scale)
	var dest := _battler_centre(vm, AnimStage.ANIM_TARGET)
	node.centre = start
	var duration: int = maxi(1, vm.args[2])
	var interval: int = maxi(1, vm.args[3])
	var st := {"t": 0, "since": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["t"] = int(st["t"]) + 1
		var f := float(st["t"]) / float(duration)
		node.centre = start.lerp(dest, f)
		st["since"] = int(st["since"]) + 1
		if int(st["since"]) >= interval:
			st["since"] = 0
			_spawn_pulse_bubbles(vm, ctx, node.centre, scale)
		if int(st["t"]) >= duration:
			node.finish()
			return true
		return false)


# CreateWaterPulseRingBubbles (battle_anim_water.c:1849): two bubbles per
# spawn, drifting in opposite directions with a random jitter, 20 frames each.
static func _spawn_pulse_bubbles(vm: AnimScriptVM, ctx: Dictionary,
		at: Vector2, scale: float) -> void:
	for i in range(2):
		var b := _make_sprite(vm, ctx)
		if b == null:
			continue
		b.centre = at
		var jitter := float(randi() % 10 - 5)
		var vel := Vector2(jitter * (1.0 if i == 0 else -1.0),
				jitter) * scale
		_velocity_travel(vm, b, at, vel, 20)


# AnimOrbitFast (battle_anim_effects_2.c:3373, step :3385). args: 0 half-period
# of the grow/shrink, 1 initial phase -- and arg 7 read LIVE as the kill
# switch, so this is registered UNCOUNTED: it orbits forever until the script
# stops it, and a counted stepper would hang waitforvisualfinish.
static func _orbit_fast(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var base := _battler_centre(vm, AnimStage.ANIM_ATTACKER)
	node.centre = base
	var half: int = maxi(1, vm.args[0])
	var st := {"ang": vm.args[1], "rx": 0.0, "ry": 0.0, "t": 0, "phase": 0}
	var step := func() -> bool:
		if not is_instance_valid(node):
			return true
		if vm.args[AnimScriptVM.ARG_RET] == -1:
			node.finish()
			return true
		match int(st["phase"]):
			0:
				st["rx"] = float(st["rx"]) + 4.0
				st["ry"] = float(st["ry"]) + 1.0
				st["t"] = int(st["t"]) + 1
				if int(st["t"]) >= half:
					st["t"] = 0
					st["phase"] = 1
			1:
				st["rx"] = maxf(0.0, float(st["rx"]) - 4.0)
				st["ry"] = maxf(0.0, float(st["ry"]) - 1.0)
				st["t"] = int(st["t"]) + 1
				if int(st["t"]) >= half:
					st["phase"] = 2
		var a: int = int(st["ang"])
		node.centre = base + Vector2(_gba_sin(a, float(st["rx"]) * scale),
				_gba_cos(a, float(st["ry"]) * scale))
		st["ang"] = (a + 9) & 0xFF
		return false
	vm.add_stepper(step, false)


# AnimOrbitScatter (battle_anim_effects_2.c:3424, step :3433). arg0 is the
# launch angle only. Constant velocity outward from the attacker until it
# leaves the screen -- the scatter half of Hidden Power's orbit-then-burst.
static func _orbit_scatter(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var layer: Control = vm.stage.layer() if vm.stage != null \
			and vm.stage.has_method("layer") else null
	var bounds := layer.size if layer != null else Vector2(1024, 768)
	var start := _battler_centre(vm, AnimStage.ANIM_ATTACKER)
	node.centre = start
	var vel := Vector2(_gba_sin(vm.args[0], 10.0), _gba_cos(vm.args[0], 7.0)) \
			* scale
	var st := {"pos": start}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var p: Vector2 = (st["pos"] as Vector2) + vel
		st["pos"] = p
		node.centre = p
		if p.x < -32.0 * scale or p.x > bounds.x + 32.0 * scale \
				or p.y < -32.0 * scale or p.y > bounds.y + 32.0 * scale:
			node.finish()
			return true
		return false)


# AnimTauntFinger (battle_anim_effects_1.c:7217) and AnimThoughtBubble (:7101)
# share SetSpriteNextToMonHead (:7091) -- placed beside the mon's head, on the
# side away from it. Both are appear / hold / disappear sequences.
static func _taunt_finger(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	node.centre = _next_to_mon_head(vm, vm.args[0])
	_apply_anim_variant(node, ctx, 0 if _is_player_side(vm) else 1)
	var st := {"phase": 0, "t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["t"] = int(st["t"]) + 1
		match int(st["phase"]):
			0:
				if int(st["t"]) > 10:
					st["phase"] = 1
					st["t"] = 0
			1:
				if node.anim_ended() or int(st["t"]) >= _ANIM_END_CAP:
					st["phase"] = 2
					st["t"] = 0
			2:
				if int(st["t"]) > 5:
					node.finish()
					return true
		return false)


static func _thought_bubble(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	node.centre = _next_to_mon_head(vm, vm.args[0])
	_apply_anim_variant(node, ctx, 0 if _is_player_side(vm) else 1)
	var hold: int = maxi(1, vm.args[1])
	var st := {"phase": 0, "t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["t"] = int(st["t"]) + 1
		match int(st["phase"]):
			0:
				if node.anim_ended() or int(st["t"]) >= _ANIM_END_CAP:
					st["phase"] = 1
					st["t"] = 0
			1:
				if int(st["t"]) >= hold:
					st["phase"] = 2
					st["t"] = 0
			2:
				if int(st["t"]) >= 12:
					node.finish()
					return true
		return false)


# SetSpriteNextToMonHead (battle_anim_effects_1.c:7091): beside the head, on
# the outward side, a quarter of the mon's height above its centre.
static func _next_to_mon_head(vm: AnimScriptVM, which: int) -> Vector2:
	var battler: int = AnimStage.ANIM_ATTACKER if which == 0 \
			else AnimStage.ANIM_TARGET
	var node := _battler_node(vm, battler)
	var c := _battler_centre(vm, battler)
	var box := node.size if node != null else Vector2(64, 64)
	var side := 1.0 if _is_player_side(vm) else -1.0
	return c + Vector2(box.x * 0.5 * side + 8.0 * side, -box.y * 0.25)


# AnimSludgeBombHitParticle (battle_anim_poison.c:577, step :593). args:
# 0/1 delta, 2 duration. A DECELERATING spray: the velocity is ramped linearly
# to zero over the duration, which is what makes it splatter rather than fly.
static func _sludge_bomb_hit_particle(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var start := _battler_centre(vm, AnimStage.ANIM_TARGET)
	node.centre = start
	var duration: int = maxi(1, vm.args[2])
	var total := Vector2(float(vm.args[0]), float(vm.args[1])) * scale
	var st := {"t": 0, "pos": start, "vel": total / float(duration) * 2.0}
	var decay := (st["vel"] as Vector2) / float(duration)
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["pos"] = (st["pos"] as Vector2) + (st["vel"] as Vector2)
		st["vel"] = (st["vel"] as Vector2) - decay
		node.centre = st["pos"]
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) >= duration:
			node.finish()
			return true
		return false)


# AnimSludgeProjectile (battle_anim_poison.c:491). args: 0/1 offset,
# 2 duration, 3 anim selector, 4 prefer-the-target's-partner flag. The arc
# amplitude is hardcoded -30 (upward), not an argument.
static func _sludge_projectile(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	if vm.args[3] == 0:
		_apply_anim_variant(node, ctx, 2)
	var start := _positioned_centre(vm, AnimStage.ANIM_ATTACKER, vm.args[0],
			vm.args[1], scale)
	node.centre = start
	_arc_travel(vm, node, start, _battler_centre(vm, AnimStage.ANIM_TARGET),
			maxi(1, vm.args[2]), -30.0 * scale)


# AnimDirtPlumeParticle (battle_anim_ground.c:498). args: 0 which mon, 1 which
# side, 2/3 destination offset, 4 arc amplitude, 5 duration. Shared by Fissure
# and Dig. Note it MUTATES args[2] in place when the right-hand side is picked.
static func _dirt_plume_particle(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var battler: int = AnimStage.ANIM_ATTACKER if vm.args[0] == 0 \
			else AnimStage.ANIM_TARGET
	var x_off := 24.0
	var dx := float(vm.args[2])
	if vm.args[1] == 1:
		x_off = -x_off
		dx = -dx
	var mon := _battler_node(vm, battler)
	var below := (mon.size.y * 0.5) if mon != null else 32.0
	var start := _battler_centre(vm, battler) \
			+ Vector2(x_off * scale, below + 30.0 * scale)
	node.centre = start
	_arc_travel(vm, node, start,
			start + Vector2(dx, float(vm.args[3])) * scale,
			maxi(1, vm.args[5]), float(vm.args[4]) * scale)


# AnimTask_PositionFissureBgOnBattler (battle_anim_ground.c:734). args:
# 0 battler selector, 1 priority, 2 the sentinel that ends it.
#
# Upstream this offsets the BG3 scroll so the fissure lines up under the
# battler, and a spawned helper task holds it there until the script writes
# the sentinel into arg 7 -- at which point it DOES restore BG3 to 0/0. That
# restore is conditional on the script, so the VM's own end-of-run background
# reset is the net if a script never gets there.
static func _position_fissure_bg(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var stage = vm.stage
	if stage == null or not stage.has_method("set_background_scroll"):
		return
	var scale := _scale(vm)
	var battler: int = AnimStage.ANIM_TARGET if vm.args[0] != 0 \
			else AnimStage.ANIM_ATTACKER
	var c := _battler_centre(vm, battler)
	var offset := Vector2(32.0 * scale - c.x, 64.0 * scale - c.y)
	var sentinel: int = vm.args[2]
	stage.set_background_scroll(offset)
	var step := func() -> bool:
		if vm.args[AnimScriptVM.ARG_RET] == sentinel:
			stage.set_background_scroll(Vector2.ZERO)
			return true
		# Re-asserted every frame, as upstream does.
		stage.set_background_scroll(offset)
		return false
	vm.add_stepper(step, false)


# AnimDigDirtMound (battle_anim_ground.c:537). args: 0 which mon, 1 which half,
# 2 duration. A static sprite for its duration -- the degenerate case of the
# linear-translation shape, with no movement at all. Two are spawned side by
# side to make one mound.
static func _dig_dirt_mound(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var battler: int = AnimStage.ANIM_ATTACKER if vm.args[0] == 0 \
			else AnimStage.ANIM_TARGET
	var mon := _battler_node(vm, battler)
	var below := (mon.size.y * 0.5) if mon != null else 32.0
	node.centre = _battler_centre(vm, battler) + Vector2(
			(-16.0 + float(vm.args[1]) * 32.0) * scale,
			below + 32.0 * scale)
	node.set_tile_offset(vm.args[1] * 8)
	var life: int = maxi(1, vm.args[2])
	var st := {"t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) >= life:
			node.finish()
			return true
		return false)


# AnimTask_DigDownMovement (battle_anim_ground.c:282) and
# AnimTask_DigUpMovement (:380). arg0 selects a half of each.
#
# THE MOST LEAK-PRONE PAIR IN THE BATCH, and Step 0 was asked about it
# specifically. Together they are a FOUR-CALL sequence -- down(false),
# down(true), up(false), up(true) -- and omitting any one strands the
# attacker: a huge horizontal offset, or parked below the screen, or simply
# invisible. Upstream relies entirely on the script getting all four right.
#
# Every displacement here goes through MonOffset and every visibility change
# through the VM's tracked setter, so the end-of-run restores catch a script
# that does not complete the sequence. That safety net is why this pair is
# safe to port at all.
static func _dig_down_movement(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var node := _battler_node(vm, AnimStage.ANIM_ATTACKER)
	if node == null:
		return
	var scale := _scale(vm)
	var mon := MonOffset.new(node)
	if vm.args[0] != 0:
		# The cleanup half: position restored, but STILL hidden -- that is the
		# underground state, and it is deliberate upstream.
		mon.restore()
		vm.set_battler_visible_tracked(AnimStage.ANIM_ATTACKER, false)
		return
	vm.set_battler_visible_tracked(AnimStage.ANIM_ATTACKER, false)
	var layer: Control = vm.stage.layer() if vm.stage != null \
			and vm.stage.has_method("layer") else null
	var width: float = layer.size.x if layer != null else 1024.0
	var st := {"t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) >= 20:
			# Shoved past the right edge, exactly as upstream leaves it.
			mon.apply(Vector2(width + 32.0 * scale - node.position.x, 0.0))
			return true
		return false)


static func _dig_up_movement(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var node := _battler_node(vm, AnimStage.ANIM_ATTACKER)
	if node == null:
		return
	var scale := _scale(vm)
	var mon := MonOffset.new(node)
	var layer: Control = vm.stage.layer() if vm.stage != null \
			and vm.stage.has_method("layer") else null
	var height: float = layer.size.y if layer != null else 768.0
	if vm.args[0] == 0:
		# Visible again, but parked below the screen -- still underground.
		vm.set_battler_visible_tracked(AnimStage.ANIM_ATTACKER, true)
		mon.apply(Vector2(0.0, height - node.position.y))
		return
	# The rise: exactly 12 frames at 8px, ending precisely level.
	var st := {"t": 0}
	mon.apply(Vector2(0.0, 96.0 * scale))
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		st["t"] = int(st["t"]) + 1
		var y := maxf(0.0, 96.0 - 8.0 * float(st["t"])) * scale
		mon.apply(Vector2(0.0, y))
		if int(st["t"]) >= 12:
			mon.restore()
			return true
		return false)
