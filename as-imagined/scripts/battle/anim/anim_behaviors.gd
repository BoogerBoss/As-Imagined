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


# The scale/rotation counterpart to MonOffset, added in [M36D batch 11]. Records
# a battler's true scale and rotation on the node the FIRST time any behavior
# deforms it, so the VM's `_restore_scaled_battlers` net can put it back even if
# the script ends before its own paired restore. Same meta-driven contract as
# MonOffset, and deliberately the same shape so the two read alike.
class MonScale:
	const META_SCALE := "_anim_mon_scale"
	const META_ROT := "_anim_mon_rotation"
	# [M36P] The VM sets the centre pivot for the whole run and restores it at
	# the end (see `_capture_battler_baseline`). This records it too, so the
	# `_restore_scaled_battlers` net — which reads meta rather than the VM's
	# own snapshot — can put it back if a run ends without reaching `_finish`.
	const META_PIVOT := "_anim_mon_pivot"
	var node: Control
	var base_scale: Vector2
	var base_rotation: float
	func _init(target: Control) -> void:
		node = target
		if target == null:
			base_scale = Vector2.ONE
			base_rotation = 0.0
			return
		if target.has_meta(META_SCALE):
			base_scale = target.get_meta(META_SCALE)
			base_rotation = target.get_meta(META_ROT)
		else:
			base_scale = target.scale
			base_rotation = target.rotation
			target.set_meta(META_SCALE, base_scale)
			target.set_meta(META_ROT, base_rotation)
			target.set_meta(META_PIVOT, target.pivot_offset)
		# Deforming about the corner is the M36P defect; a behavior reached
		# without the VM having run (a direct unit test) still needs this.
		target.pivot_offset = target.size * 0.5
	func apply(mul: Vector2, rot_delta: float = 0.0) -> void:
		if node != null and is_instance_valid(node):
			node.scale = base_scale * mul
			node.rotation = base_rotation + rot_delta
	func restore() -> void:
		apply(Vector2.ONE, 0.0)


static func register_all(registry: AnimBehaviorRegistry) -> void:
	registry.register_many({
		# — [M36D batch 39] —
		"AnimTask_EruptionLaunchRocks": _eruption_launch_rocks,
		# — [M36D batch 38] —
		"AnimTask_VoltSwitch": _volt_switch,
		"AnimSuperpowerRock": _superpower_rock,
		"SlideMonToOffsetAndBack": _slide_mon_to_offset_and_back,
		# — [M36D batch 37] —
		"AnimRapidSpin": _rapid_spin,
		"AnimTask_RapinSpinMonElevation": _rapid_spin_mon_elevation,
		# — [M36D batch 36] —
		"SpriteCB_SurgingStrikes": _surging_strikes,
		"SpriteCB_MoongeistCharge": _moongeist_charge,
		"SpriteCB_PowerShiftBall": _power_shift_ball,
		"SpriteCB_TripleArrowKick": _triple_arrow_kick,
		"SpriteCB_GlacialLance": _glacial_lance,
		"SpriteCB_MoveSpriteUpwardsForDuration": _move_sprite_upwards_for_duration,
		"SpriteCB_SearingShotRock": _searing_shot_rock,
		"AnimEllipticalGustAttacker": _elliptical_gust_attacker,
		"AnimSmellingSaltExclamation": _smelling_salt_exclamation,
		"AnimLavaPlumeOrbitScatter": _lava_plume_orbit_scatter,
		"AnimTask_TechnoBlast": _techno_blast,
		"AnimTask_ShellSideArm": _shell_side_arm,
		# — [M36D batch 35] —
		"AnimThrowMistBall": _throw_mist_ball,
		"AnimSkyDropBallUp": _sky_drop_ball_up,
		"AnimWillOWispOrb": _will_o_wisp_orb,
		"AnimWillOWispFire": _will_o_wisp_fire,
		"AnimAquaTail": _aqua_tail,
		"AnimKnockOffAquaTail": _knock_off_aqua_tail,
		"AnimateZenHeadbutt": _animate_zen_headbutt,
		"AnimPresent": _present,
		"AnimPresentHealParticle": _present_heal_particle,
		"SpriteCB_TwinkleOnBattler": _twinkle_on_battler,
		# — [M36D batch 34] —
		"AnimTask_TormentAttacker": _torment_attacker,
		"AnimTask_BarrageBall": _barrage_ball,
		"AnimTask_WaterSport": _water_sport,
		"AnimTask_BrineRain": _brine_rain,
		"AnimTask_CreateIons": _create_ions,
		"AnimTask_SmokescreenImpact": _smokescreen_impact,
		"AnimTask_OdorSleuthMovement": _odor_sleuth_movement,
		"AnimTask_CycleMagicalLeafPal": _cycle_magical_leaf_pal,
		# — [M36D batch 33] —
		"AnimTask_ThrashMoveMonHorizontal": _thrash_move_mon_horizontal,
		"AnimTask_ThrashMoveMonVertical": _thrash_move_mon_vertical,
		"AnimTask_FacadeColorBlend": _facade_color_blend,
		"AnimTask_BlendBackground": _blend_background,
		"AnimTask_ShakeTargetPartnerBasedOnMovePowerOrDmg": _shake_target_partner_by_power,
		"AnimTask_SkullBashPosition": _skull_bash_position,
		"AnimTask_MoveHeatWaveTargets": _move_heat_wave_targets,
		"AnimTask_GetStockpileCounter": _get_stockpile_counter,
		# — [M36D batch 32] —
		"AnimSuperpowerOrb": _superpower_orb,
		"AnimDevil": _devil,
		"AnimFlyingMusicNotes": _flying_music_notes,
		"AnimBounceBallShrink": _bounce_ball_shrink,
		"AnimDragonRush": _dragon_rush,
		"AnimEruptionFallingRock": _eruption_falling_rock,
		"AnimOverheatFlame": _overheat_flame,
		"AnimFalseSwipeSlice": _false_swipe_slice,
		"AnimFalseSwipePositionedSlice": _false_swipe_positioned_slice,
		"AnimBlastBurnTargetPlume": _blast_burn_target_plume,
		"AnimExtremeEvoboostCircle": _extreme_evoboost_circle,
		"AnimDracoMeteorRock": _draco_meteor_rock,
		"AnimHappyHourCoinShower": _happy_hour_coin_shower,
		"SpriteCB_GeyserTarget": _geyser_target,
		# — [M36D batch 31] —
		"AnimHelpingHandClap": _helping_hand_clap,
		"AnimTask_HelpingHandAttackerMovement": _helping_hand_attacker_movement,
		"AnimIngrainOrb": _ingrain_orb,
		"AnimIngrainRoot": _ingrain_root,
		"AnimLockOnTarget": _lock_on_target,
		"AnimLockOnMoveTarget": _lock_on_move_target,
		"AnimWoodHammerHammer": _wood_hammer_hammer,
		"AnimWoodHammerSmall": _wood_hammer_small,
		"AnimConversion2": _conversion2,
		"AnimTask_Conversion2AlphaBlend": _conversion2_alpha_blend,
		"AnimPerishSongMusicNote": _perish_song_music_note,
		"AnimPerishSongMusicNote2": _perish_song_music_note2,
		"AnimRockPolishSparkle": _rock_polish_sparkle,
		"AnimRockPolishStreak": _rock_polish_streak,
		"SlideMonToOffsetPartner": _slide_mon_to_offset_partner,
		"SlideMonToOriginalPosPartner": _slide_mon_to_original_pos_partner,
		# — [M36D batch 30] —
		"AnimTask_RandomBool": _random_bool,
		"GetIsDoomDesireHitTurn": _get_is_doom_desire_hit_turn,
		"AnimTask_IsHealingMove": _is_healing_move,
		"AnimTask_IsAttackerPlayerSide": _is_attacker_player_side,
		"AnimTask_IsTargetPartner": _is_target_partner,
		"AnimTask_GetLycanrocForm": _get_lycanroc_form,
		"AnimTask_SetAnimTargetToAttackerOpposite": _set_anim_target_to_attacker_opposite,
		"AnimMovementWaves": _movement_waves,
		"AnimWaveFromCenterOfTarget": _wave_from_center_of_target,
		"AnimForesightMagnifyingGlass": _foresight_magnifying_glass,
		"AnimMoveWringOut": _move_wring_out,
		"AnimMoveAccupressure": _move_accupressure,
		"AnimFlatterConfetti": _flatter_confetti,
		# The FOURTH member of the affine-impact duplicate chain, after
		# AnimGunkShotImpact (b24) and AnimForcePalm (b27). Same body again.
		"AnimPunishment": _gunk_shot_impact,
		# — [M36D batch 29] —
		"AnimLick": _lick,
		"AnimTailGlowOrb": _tail_glow_orb,
		"AnimStringWrap": _string_wrap,
		"AnimSpitUpOrb": _spit_up_orb,
		"AnimSwallowBlueOrb": _swallow_blue_orb,
		"AnimBonemerangProjectile": _bonemerang_projectile,
		"AnimLeechLifeNeedle": _leech_life_needle,
		"AnimPluck": _pluck,
		"AnimMeteorMashStar": _meteor_mash_star,
		"AnimYawnCloud": _yawn_cloud,
		"AnimWishStar": _wish_star,
		"AnimAngel": _angel,
		"AnimPinkHeart": _pink_heart,
		"AnimSoftBoiledEgg": _soft_boiled_egg,
		"AnimMilkBottle": _milk_bottle,
		"AnimMeanLookEye": _mean_look_eye,
		# — [M36D batch 28] —
		"AnimTask_ShrinkAndGrow": _shrink_and_grow,
		"AnimTask_MeditateStretchAttacker": _meditate_stretch_attacker,
		"AnimTask_SlackOffSquish": _slack_off_squish,
		"AnimTask_CompressTargetHorizontally": _compress_target_horizontally,
		"AnimTask_CompressTargetHorizontallyFast": _compress_target_horizontally_fast,
		"AnimTask_SquishAndSweatDroplets": _squish_and_sweat_droplets,
		"AnimTask_GrowAndGrayscale": _grow_and_grayscale,
		"AnimTask_GrowTarget": _grow_target,
		"AnimTask_Withdraw": _withdraw,
		"AnimTask_RotateVertically": _rotate_vertically,
		"AnimTask_DuckDownHop": _duck_down_hop,
		"AnimTask_Minimize": _minimize,
		"AnimTask_DoubleTeam": _double_team,
		# — [M36D batch 27] —
		"AnimTask_GrowAndShrink": _grow_and_shrink,
		"AnimConversion": _conversion,
		"AnimTask_ConversionAlphaBlend": _conversion_alpha_blend,
		"AnimBreathPuff": _breath_puff,
		"AnimSuperFang": _super_fang,
		"AnimTriAttackTriangle": _tri_attack_triangle,
		"AnimSharpenSphere": _sharpen_sphere,
		"AnimStealthRock": _stealth_rock,
		"AnimSuckerPunch": _sucker_punch,
		# AnimGrassKnot is a verbatim duplicate of AnimSuckerPunch, and
		# AnimForcePalm of batch 24's AnimGunkShotImpact -- same bodies, same
		# step functions. Aliases, not ports.
		"AnimGrassKnot": _sucker_punch,
		"AnimForcePalm": _gunk_shot_impact,
		# — [M36D batch 26] —
		"AnimMoon": _moon,
		"AnimMoonlightSparkle": _moonlight_sparkle,
		"AnimTask_MoonlightEndFade": _moonlight_end_fade,
		"AnimTask_AlphaFadeIn": _alpha_fade_in,
		"AnimTask_InitAttackerFadeFromInvisible": _init_attacker_fade_from_invisible,
		"AnimTask_AttackerFadeFromInvisible": _attacker_fade_from_invisible,
		"AnimSkyAttackBird": _sky_attack_bird,
		# — [M36D batch 25] —
		"AnimTask_UproarDistortion": _uproar_distortion,
		"AnimTask_DeepInhale": _deep_inhale,
		"AnimTask_MusicNotesRainbowBlend": _music_notes_rainbow_blend,
		"AnimTask_MusicNotesClearRainbowBlend": _music_notes_clear_rainbow_blend,
		"AnimWavyMusicNotes": _wavy_music_notes,
		"AnimSlowFlyingMusicNotes": _slow_flying_music_notes,
		"AnimJaggedMusicNote": _jagged_music_note,
		"AnimBellyDrumHand": _belly_drum_hand,
		# — [M36D batch 24] —
		"AnimHydroCannonCharge": _hydro_cannon_charge,
		"AnimHydroCannonBeam": _hydro_cannon_beam,
		"AnimAcidPoisonBubble": _acid_poison_bubble,
		"AnimAcidPoisonDroplet": _acid_poison_droplet,
		"AnimGunkShotImpact": _gunk_shot_impact,
		# AnimGunkShotParticles is a VERBATIM COPY of AnimToTargetInSinWave --
		# same body, same step function, same constants, differing only in the
		# name and in reading gBattleAnimArgs[ARG_RET_ID] where the original
		# writes gBattleAnimArgs[7] (ARG_RET_ID is 7). So it is an alias, not a
		# port: duplicating the code would have been duplicating a duplicate.
		"AnimGunkShotParticles": _to_target_in_sin_wave,
		"AnimCoinThrow": _coin_throw,
		"AnimFallingCoin": _falling_coin,
		# — [M36D batch 23] —
		"SpriteCB_AnimSpriteOnSelectedMonPos": _anim_sprite_on_selected_mon_pos,
		"SpriteCB_AnimSpriteOnTargetSideCentre": _anim_sprite_on_target_side_centre,
		"SpriteCB_TranslateAnimSpriteToTargetMonLocationDoubles": _translate_to_target_mon_location_doubles,
		"AnimTask_ShockWaveLightning": _shock_wave_lightning,
		"AnimTask_ShockWaveProgressingBolt": _shock_wave_progressing_bolt,
		# — [M36D batch 22] —
		"AnimTask_IsTargetSameSide": _is_target_same_side,
		"SpriteCB_MindBlownBall": _mind_blown_ball,
		"SpriteCB_CentredElectricity": _centred_electricity,
		"AnimTask_CreateSmallSteelBeamOrbs": _create_small_steel_beam_orbs,
		# — [M36D batch 21] —
		"AnimTask_SnatchOpposingMonMove": _snatch_opposing_mon_move,
		"AnimTask_PurpleFlamesOnTarget": _purple_flames_on_target,
		"SpriteCB_SteelRoller": _steel_roller,
		"SpriteCB_FlippableSlash": _flippable_slash,
		# — [M36D batch 20] —
		"AnimTask_GlareEyeDots": _glare_eye_dots,
		"AnimTask_DestinyBondWhiteShadow": _destiny_bond_white_shadow,
		"AnimTask_AttackerFadeToInvisible": _attacker_fade_to_invisible,
		# — [M36D batch 19] —
		"AnimTask_ScaryFace": _scary_face,
		# — [M36D batch 18] —
		"SpriteCB_PhotonGeyserBeam": _photon_geyser_beam,
		"SpriteCB_HorizontalSlice": _horizontal_slice,
		"SpriteCB_LeftRightSlice": _left_right_slice,
		"AnimEyeSparkle": _eye_sparkle,
		"AnimLetterZ": _letter_z,
		"AnimBatonPassPokeball": _baton_pass_pokeball,
		# — [M36D batch 17] —
		"AnimTask_SquishTarget": _squish_target,
		"AnimTask_SquishTargetShort": _squish_target_short,
		"AnimTask_NightShadeClone": _night_shade_clone,
		"AnimBrickBreakWall": _brick_break_wall,
		"AnimRazorWindTornado": _razor_wind_tornado,
		"AnimMegahornHorn": _megahorn_horn,
		"AnimCrossChopHand": _cross_chop_hand,
		# — [M36D batch 16] —
		"AnimTask_GetTimeOfDay": _get_time_of_day,
		"AnimViceGripPincer": _vice_grip_pincer,
		"AnimStompFoot": _stomp_foot,
		"AnimBounceBallLand": _bounce_ball_land,
		"AnimWeatherBallUp": _weather_ball_up,
		"AnimWhirlwindLine": _whirlwind_line,
		"AnimRockScatter": _rock_scatter,
		"AnimGhostStatusSprite": _ghost_status_sprite,
		"AnimDiveBall": _dive_ball,
		"AnimDiveWaterSplash": _dive_water_splash,
		"SpriteCB_ToxicThreadWrap": _toxic_thread_wrap,
		"SpriteCB_SpriteOnMonUntilAffineAnimEnds": _sprite_on_mon_until_affine_ends,
		# — [M36D batch 15] —
		"AnimGrowingShockWaveOrbOnTarget": _growing_shock_wave_orb_on_target,
		"AnimPetalDanceBigFlower": _petal_dance_big_flower,
		"AnimPetalDanceSmallFlower": _petal_dance_small_flower,
		"AnimWhiteHalo": _white_halo,
		"AnimSmokeBallEscapeCloud": _smoke_ball_escape_cloud,
		"AnimAcrobaticsSlashes": _acrobatics_slashes,
		"SpriteCB_SunsteelStrikeRings": _sunsteel_strike_rings,
		"AnimBrickBreakWallShard": _brick_break_wall_shard,
		"AnimFallingFeather": _falling_feather,
		# — [M36D batch 14] the rotate-and-travel family —
		"AnimPsychoCut": _psycho_cut,
		"AnimSonicBoomProjectile": _sonic_boom_projectile,
		"AnimTealAlert": _teal_alert,
		"AnimRedHeartProjectile": _red_heart_projectile,
		"AnimHitSplatRandom": _hit_splat_random,
		"AnimSpiderWeb": _spider_web,
		"AnimTranslateWebThread": _translate_web_thread,
		# — [M36D batch 13] clearing batch 12's deferrals —
		"SpriteCB_Geyser": _geyser,
		"AnimSuperpowerFireball": _growing_superpower,
		"AnimFlyingParticle": _flying_particle,
		"AnimTrickBag": _trick_bag,
		# — [M36D batch 12] —
		"AnimGuardRing": _guard_ring,
		"AnimLargeFlame": _large_flame,
		"AnimTask_IsPowerOver99": _is_power_over_99,
		"AnimMudSportDirt": _mud_sport_dirt,
		"AnimParticleBurst": _particle_burst,
		"AnimPoisonJabProjectile": _poison_jab_projectile,
		"AnimMovePowerSwapGuardSwap": _power_swap_guard_swap,
		"AnimBlockX": _block_x,
		"AnimTask_BlendNonAttackerPalettes": _blend_non_attacker_palettes,
		"AnimTask_SpiteTargetShadow": _spite_target_shadow,
		# — [M36D batch 11] four of batch 10's five deferrals —
		"AnimTask_ShrinkTargetCopy": _shrink_target_copy,
		"AnimTask_FlailMovement": _flail_movement,
		"AnimTask_NightmareClone": _nightmare_clone,
		"AnimTask_Rollout": _rollout,
		# — [M36D batch 10] the flattening tail —
		"AnimTask_Flash": _flash,
		"AnimReversalOrb": _reversal_orb,
		"AnimBlackSmoke": _black_smoke,
		"SpriteCB_SurroundingRing": _surrounding_ring,
		"SpriteCB_FallingObject": _falling_object,
		# byte-identical to batch 9's ice-punch particle -- one implementation
		"AnimFireSpiralInward": _ice_punch_swirling_particle,
		"AnimGuillotinePincer": _guillotine_pincer,
		"AnimQuestionMark": _question_mark,
		"AnimFurySwipes": _fury_swipes,
		"AnimSpikes": _spikes,
		"AnimOutrageFlame": _outrage_flame,
		# — [M36D batch 9] yield-ordered, cross-tier —
		"AnimHornHit": _horn_hit,
		"AnimHyperVoiceRing": _hyper_voice_ring,
		"AnimRockBlastRock": _rock_blast_rock,
		"AnimFlyBallAttack": _fly_ball_attack,
		"AnimZapCannonSpark": _zap_cannon_spark,
		"AnimMagentaHeart": _magenta_heart,
		"AnimFirePlume": _fire_plume,
		"AnimEllipticalGust": _elliptical_gust,
		"AnimEllipticalGustCentered": _elliptical_gust_centered,
		"AnimGustToTarget": _gust_to_target,
		"AnimSprayWaterDroplet": _spray_water_droplet,
		"SpriteCB_GrowingSuperpower": _growing_superpower,
		"AnimIcePunchSwirlingParticle": _ice_punch_swirling_particle,
		"AnimDragonRageFirePlume": _dragon_rage_fire_plume,
		"AnimTask_DefenseCurlDeformMon": _defense_curl_deform_mon,
		"AnimMetronomeFinger": _metronome_finger,
		# — [M36D batch 8] the highest-share shared blockers —
		"AnimTask_AllBattlersVisible": _all_battlers_visible,
		"AnimTask_AllBattlersInvisible": _all_battlers_invisible,
		"AnimTask_AllBattlersInvisibleExceptAttackerAndTarget":
				_all_battlers_invisible_except_pair,
		"AnimTask_ShakeTargetBasedOnMovePowerOrDmg":
				_shake_target_by_power_or_dmg,
		"AnimTask_RockMonBackAndForth": _rock_mon_back_and_forth,
		"AnimTask_ShakeBattlePlatforms": _shake_battle_platforms,
		"AnimFlyBallUp": _fly_ball_up,
		"AnimSparkElectricity": _spark_electricity,
		"AnimTask_ElectricChargingParticles": _electric_charging_particles,
		"AnimGrowingShockWaveOrb": _growing_shock_wave_orb,
		"AnimTask_AnimateGustTornadoPalette": _animate_gust_tornado_palette,
		"AnimCrossImpact": _cross_impact,
		# — [M36D batch 7] the last blocked iconic moves —
		"AnimLightning": _lightning,
		"AnimTask_InvertScreenColor": _invert_screen_color,
		"AnimTask_ShakeTargetInPattern": _shake_target_in_pattern,
		"AnimConfuseRayBallBounce": _confuse_ray_ball_bounce,
		"AnimConfuseRayBallSpiral": _confuse_ray_ball_spiral,
		"AnimTask_BlendColorCycleByTag": _blend_color_cycle_by_tag,
		"AnimTask_GetFrustrationPowerLevel": _get_frustration_power_level,
		"AnimTask_StrongFrustrationGrowAndShrink": _strong_frustration_grow,
		"AnimWeakFrustrationAngerMark": _weak_frustration_anger_mark,
		"AnimTask_VoltTackleAttackerReappear": _volt_tackle_attacker_reappear,
		"AnimTask_VoltTackleBolt": _volt_tackle_bolt,
		"AnimVoltTackleOrbSlide": _volt_tackle_orb_slide,
		"AnimDragonDanceOrb": _dragon_dance_orb,
		"AnimTask_BlendPalInAndOutByTag": _blend_pal_in_and_out_by_tag,
		"AnimTask_DragonDanceWaver": _dragon_dance_waver,
		"AnimTask_SetAttackerInvisibleWaitForSignal": _attacker_invisible_wait,
		"AnimTask_AttackerStretchAndDisappear": _attacker_stretch_disappear,
		"AnimTask_ExtremeSpeedImpact": _extreme_speed_impact,
		"AnimTask_ExtremeSpeedMonReappear": _extreme_speed_reappear,
		"AnimTask_SpeedDust": _speed_dust,
		"AnimHitSplatOnMonEdge": _hit_splat_on_mon_edge,
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


# AnimTask_StartSinAnimTimer (battle_anim_water.c:871). args: 0 duration.
#
# [M36D batch 24] THIS WAS A NO-OP AND THAT WAS WRONG. The retired comment
# read "our AnimToTargetInSinWave carries its own phase ... so this is a
# no-op that completes immediately rather than a shared timer nothing would
# consume." Its premise -- nothing consumes it -- was true when written and
# is false now: `_to_target_in_sin_wave` has ALWAYS read `vm.args[7]` as its
# phase seed, and batch 24's AnimGunkShotParticles is a second reader.
#
# The real task runs for `args[0]` frames adding 3 to gBattleAnimArgs[7]
# each frame, wrapping at 256. Sprites created while it runs each pick up a
# DIFFERENT phase, which is the entire reason a flame stream looks like a
# stream rather than a rigid line. It is a counted visual task upstream
# (DestroyAnimVisualTask decrements the counter), so waitforvisualfinish
# waits on it -- reproduced, rather than made uncounted to keep durations
# where they were.
static func _start_sin_anim_timer(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var frames: int = maxi(1, vm.args[0])
	vm.args[ARG_RET_ID] = 0
	var st := {"t": 0}
	vm.add_stepper(func() -> bool:
		vm.args[ARG_RET_ID] = (vm.args[ARG_RET_ID] + 3) & 0xFF
		st["t"] = int(st["t"]) + 1
		return int(st["t"]) >= frames)


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
# ⚠️ **`_is_player_side` IS THE ATTACKER'S SIDE AND NOTHING ELSE.** For "which
# side is THIS battler on", use `_battler_is_player_side` (defined with the
# M36D batch 8 group below) — it exists, it handles the self/ally-target case
# this cannot, and reaching for the attacker instead is a sign error rather
# than a missing value, because the two sides are always opposite in singles.
# See that function's own note for the upstream idiom it serves.


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


# ⚠️ **THE SPRITE-AIM OFFSET. A PROJECTILE THAT AIMS ITSELF NEEDS THIS OR IT
# FLIES SIDEWAYS.** Source applies `rot += 0xC000` after computing the travel
# angle (`AnimTranslateStinger` battle_anim_bug.c:385, `AnimMissileArc_Step`
# :~430), because the art is drawn along the VERTICAL axis while the computed
# angle is measured from +X. Confirmed by looking at the art rather than
# inferring it: `needle.png` is a 16x16 vertical shaft.
#
# Reported from play: "poison sting has the animation object not rotated
# properly." Two of this file's four aiming rotators applied the offset
# (`_coin_throw`, `_sky_attack_bird`) and two did not (`_translate_stinger`,
# `_missile_arc`), so the needle stayed upright while travelling sideways.
#
# ⚠️ **`+atan2` IS CORRECT AND SOURCE'S `ArcTan2Neg` IS NOT AN EXTRA SIGN FLIP
# TO PORT.** `ArcTan2` is BIOS SWI 0x0A, which measures CCW in a **y-up**
# frame; the GBA screen is y-down, so feeding it a screen `dy` mirrors the
# answer and `ArcTan2Neg`'s negation puts it back. Godot's `Vector2.angle()`
# is already the screen-space angle, so the two cancel and only the offset is
# owed. This was derived rather than assumed, and it is corroborated by the
# two rotators that already ship with `+atan2` plus this offset and look
# right.
const _AIM_ROTATION_OFFSET := 0xC000


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
	node.rotation = (finish_pos - start).angle() \
			+ _gba_rot_to_radians(_AIM_ROTATION_OFFSET)
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
			node.rotation = (ahead - pos).angle() \
					+ _gba_rot_to_radians(_AIM_ROTATION_OFFSET)
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
uniform float invert : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float lum = (c.r + c.g + c.b) / 3.0;
	c.rgb = mix(c.rgb, vec3(lum), gray);
	c.rgb = mix(c.rgb, tint.rgb, tint_amount);
	c.rgb = mix(c.rgb, vec3(1.0) - c.rgb, invert);
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
# ⚠️ **[M36E5] THE SCANLINE EFFECT IS A PER-ROW *ALPHA WINDOW*, NOT A
# HORIZONTAL OFFSET — and this comment used to say the opposite.**
# `AnimTask_SurfWaveScanlineEffect` (:1140) sets `params.dmaDest =
# &REG_BLDALPHA` (:1164), so what varies per scanline is the BLEND WEIGHT:
# rows inside a band show the wave at the ramping coefficient, and every row
# outside shows `data[2]` = `0x1000` = eva 0 / evb 16, i.e. the battle backdrop
# with the wave fully transparent.
#
# **That band is what makes the wave WASH ACROSS the screen**, and it moves in
# opposite directions per side (:1044-1069, :1172-1183):
#
#   player-side attacker:   rows [d4, 112), d4 shrinking 48 -> 0  (opens UPWARD)
#   opponent-side attacker: rows [0, d5),   d5 growing   0 -> 112 (opens DOWNWARD)
#
# It was previously stood in for by a uniform `modulate.a` over the whole
# layer, which fades the wave in and out IN PLACE — the reason Surf read as
# "appears, then disappears" rather than as a wave. `AnimStage`'s own
# `set_background_band` could not serve it: that surface is the OTHER scanline
# register (BG1HOFS/BG2HOFS, a per-row horizontal scroll), which is a genuinely
# different effect that other moves use.
#
# ⚠️ The peak coefficient is **13/16, not 1.0** — `data[3]` ramps to 13 and the
# blend is `eva/16` — so the wave is deliberately never fully opaque over the
# battlers. Dividing by 13 (which is what stood here) made it opaque at peak.
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

	var has_band: bool = stage.has_method("set_background_alpha_band")
	var layer = stage.background_layer() if stage.has_method(
			"background_layer") else null
	# The band's own two edges, in GBA screen rows, seeded per side exactly as
	# `AnimTask_CreateSurfWave` seeds `data[4]`/`data[5]` on the scanline task.
	var st := {"frame": 0, "cyc": 0, "step": 0, "blend": 0,
			"top": 48.0 if player_side else 0.0,
			"bottom": float(_SURF_BAND_MAX) if player_side else 0.0}
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

		# The band opens one row per frame and then stays put -- source's
		# `--data[4]` / `++data[5]`, each clamped once it reaches its end.
		if player_side:
			st["top"] = maxf(0.0, float(st["top"]) - 1.0)
		else:
			st["bottom"] = minf(float(_SURF_BAND_MAX),
					float(st["bottom"]) + 1.0)

		# Blend ramp: in over 13 steps of 2 frames, hold, out again. The
		# animation ends when it has ramped back to nothing.
		var t: int = int(st["frame"]) / 2
		if t <= 13:
			st["blend"] = t
		elif t > 54:
			st["blend"] = maxi(0, 13 - (t - 54))
		var inside := clampf(int(st["blend"]) / 16.0, 0.0, 1.0)
		if has_band:
			stage.set_background_alpha_band(float(st["top"]) * scale,
					float(st["bottom"]) * scale, inside, 0.0)
		elif layer != null:
			# No band surface on this stage (a test double): fall back to the
			# uniform fade rather than rendering the wave at full opacity.
			layer.modulate.a = inside
		if t > 54 and int(st["blend"]) <= 0:
			if layer != null:
				layer.modulate.a = 1.0
			if has_band:
				stage.clear_background_alpha_band()
			if stage.has_method("clear_background_palette_remap"):
				stage.clear_background_palette_remap()
			if stage.has_method("clear_background"):
				stage.clear_background()
			stage.set_background_scroll(Vector2.ZERO)
			return true
		return false)


# The scanline band's far edge, in GBA screen rows: source pins the player-side
# band's bottom at 112 and grows the opponent-side band's until `> 111`, so both
# stop at the same row rather than at the screen's own 160.
const _SURF_BAND_MAX := 112


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


# ⚠️ **AN AFFINE-ANIM TABLE'S ROTATION IS A `u8` AND IS SHIFTED LEFT 8 BITS
# BEFORE IT REACHES THE MATRIX** — `ApplyAffineAnimFrameRelativeAndUpdateMatrix`
# (`sprite.c:1327`): `rotation + (frameCmd->rotation << 8)`. So it is a DIFFERENT
# unit from `SetSpriteRotScale`'s argument, which is already in 65536-per-circle
# space (that is why `_bow_mon`'s literal `0xC00` needs no shift).
#
# Reported from play: "mega kick and punch don't have any rotations." The port
# fed the raw table byte straight to `_gba_rot_to_radians`, making every
# affine-driven spin **256x too slow** — Mega Punch's fist turned 5.5 degrees
# across its whole approach where source turns it 1406 degrees, nearly four
# full rotations. 180 of the 647 extracted affine frame commands carry a
# nonzero rotation, up to magnitude 248, so the error is dramatic wherever it
# is inlined.
const _AFFINE_ROT_SHIFT := 8

# GBA affine tables store scale deltas as unsigned 16-bit; 0xFFFC is -4.
static func _affine_s16(v: int) -> int:
	return v - 65536 if v > 32767 else v


# The per-frame deltas of a template's own LOOPING affine frame, read from the
# extracted table rather than inlined.
#
# ⚠️ **THIS BEHAVIOR SERVES TWO TEMPLATES WITH DIFFERENT TABLES, WHICH IS WHY
# IT MUST BE READ AND NOT HARDCODED.** `gMegaPunchKickSpriteTemplate` uses
# `sAffineAnim_MegaPunchKick` (xScale **-4**) and `gSpinningHandOrFootSpriteTemplate`
# — Blaze Kick / Meteor Mash — uses `sAffineAnim_SpinningHandOrFoot` (**-8**).
# The port inlined the -8 and applied it to both, so Mega Punch shrank twice as
# fast as it should and hit the 0.05 clamp at frame 32, leaving a 5% dot for
# the last 18 frames of a 50-frame spin. You cannot see a rotation on a dot,
# which is why the two defects read as one.
static func _affine_loop_delta(ctx: Dictionary) -> Dictionary:
	var seqs := AnimData.affine_sequences_for(str(ctx.get("template", "")))
	for seq in seqs:
		for cmd in seq:
			if cmd is Dictionary and (cmd as Dictionary).has("rot"):
				var d: Dictionary = cmd
				# Frame 0 is the absolute identity base (xscale 256); the
				# looping frame is the first one carrying a real delta.
				if int(d.get("xscale", 256)) == 256 and int(d.get("rot", 0)) == 0:
					continue
				return {"scale": _affine_s16(int(d.get("xscale", 0))),
						"rot": int(d.get("rot", 0))}
	return {}


# AnimSpinningKickOrPunch (battle_anim_fight.c:640, finish :650). args:
# 0/1 offset, 2 anim index, 3 spin duration.
#
# The spin and shrink are NOT in the function at all -- they live in the
# template's own affine anim, which is why both come from `_affine_loop_delta`
# above. The finisher then SNAPS the sprite back to full size and angle 0 and
# holds it there for 21 frames before destroying it, which is why the kick
# appears to land rather than fade.
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
	# Falls back to the Mega Punch/Kick table's own values if the extraction is
	# unavailable, rather than to the other template's.
	var delta := _affine_loop_delta(ctx)
	# ⚠️⚠️ **THE TWO AFFINE PATHS USE OPPOSITE SCALE CONVENTIONS FOR THE SAME
	# TABLE FORMAT, AND THIS IS THE SPRITE ONE.** Reported from play — "mega
	# punch the fist grows instead of shrinking" — after I had "corrected" it
	# the other way. Both readings had real evidence; the resolution is that
	# there are genuinely two runners:
	#
	#   SPRITE path (`AnimateSprite` -> `ApplyAffineAnimFrameRelativeAndUpdate
	#   Matrix`, sprite.c:1327) sends the accumulator through
	#   `ConvertScaleParam` = `0x10000 / scale` BEFORE `ObjAffineSet`, so the
	#   accumulator is the VISUAL scale: a negative delta SHRINKS.
	#
	#   TASK path (`RunAffineAnimFromTaskData`, battle_anim_mons.c) passes the
	#   accumulator STRAIGHT to `SetSpriteRotScale` with no conversion, so it
	#   is the texture step: a negative delta GROWS. That is why
	#   `gGrowAndShrinkAffineAnimCmds` opens `(-4, -5)` and is named "Grows" —
	#   it is a TASK table, and `_run_affine_cmds` (which serves those tasks)
	#   is right to use `256 / accumulator`.
	#
	# `AnimSpinningKickOrPunch` is a SPRITE, so it takes the first rule: Mega
	# Punch's -4 shrinks the fist as it closes in. Do NOT "unify" these two.
	var scale_per_frame: float = float(int(delta.get("scale", -4)))
	var rot_per_frame: int = int(delta.get("rot", 20)) << _AFFINE_ROT_SHIFT
	var st := {"t": 0, "phase": 0, "hold": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		if int(st["phase"]) == 0:
			st["t"] = int(st["t"]) + 1
			# Sprite convention: the accumulator IS the visual scale.
			var acc: float = _GBA_AFFINE_IDENTITY + scale_per_frame * float(st["t"])
			node.scale = base_scale * maxf(0.05, acc / _GBA_AFFINE_IDENTITY)
			node.rotation += _gba_rot_to_radians(rot_per_frame)
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

# The five segments' TILE offsets, by bolt style -- source's own `r8`, which is
# a LOCAL reinitialised on every call, so it does not accumulate across the
# five and the last segment deliberately reuses the first's tile
# (`battle_anim_electric.c:832-889`):
#
#   style 0: r8 = 0, r2 = 1  ->  0, 0+1, 0+2, 0+3, 0
#   style n: r8 = 8, r2 = 4  ->  8, 8+4, 8+8, 8+12, 8
#
# ⚠️ **THE SEGMENTS ARE MEANT TO LOOK DIFFERENT FROM EACH OTHER — that is the
# whole reason the tile advances.** Drawing one tile five times renders a
# repeated spark rather than a jagged bolt.
const _BOLT_TILES := {
	0: [0, 1, 2, 3, 0],
	1: [8, 12, 16, 20, 8],
}

# `AnimElectricBoltSegment`'s own first-frame OAM override, by style: 8x16 for
# style 0, 16x16 otherwise. The template declares 8x8, so without this every
# segment draws at half (or a quarter of) its real area — and since the
# segments sit 16px apart, an 8px-tall one leaves a visible gap between each.
const _BOLT_FRAME := {
	0: Vector2i(8, 16),
	1: Vector2i(16, 16),
}


# AnimTask_ElectricBolt (battle_anim_electric.c:819, step :832). args: 0/1
# offset from the target, 2 bolt style. Spawns FIVE segments, one every two
# frames, each 16px lower than the last -- the bolt draws itself downward
# rather than appearing at once. 11 frames, then the task ends; the segments
# outlive it by their own 15-frame life.
#
# ⚠️ **`_apply_anim_variant` USED TO STAND HERE AND WAS A SILENT NO-OP.**
# `gElectricBoltSegmentSpriteTemplate` carries no anim table at all, so the
# style argument reached nothing: all five segments rendered as the same 8x8
# tile. Source expresses the style through the tile offset and the OAM size
# instead, which is what the two tables above are.
static func _electric_bolt(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var scale := _scale(vm)
	var origin := _battler_centre(vm, AnimStage.ANIM_TARGET) \
			+ Vector2(float(vm.args[0]), float(vm.args[1])) * scale
	# Source branches on `if (!data[2])`, so every nonzero style takes the same
	# arm -- keyed as 0-or-not rather than as an index, which is why an
	# unexpected value degrades to the wide bolt instead of off the end.
	var style: int = 0 if vm.args[2] == 0 else 1
	var tiles: Array = _BOLT_TILES[style]
	var frame: Vector2i = _BOLT_FRAME[style]
	var st := {"t": 0, "spawned": 0}
	vm.add_stepper(func() -> bool:
		var t: int = int(st["t"])
		if t % 2 == 0 and int(st["spawned"]) < 5:
			var i: int = int(st["spawned"])
			var seg := _make_sprite(vm, ctx)
			if seg != null:
				seg.set_frame_size(frame.x, frame.y, int(tiles[i]))
				seg.centre = origin + Vector2(0.0,
						16.0 * float(i + 1) * scale)
				_electric_segment_life(vm, seg)
			st["spawned"] = i + 1
		st["t"] = t + 1
		return int(st["t"]) >= 11)


# AnimElectricBoltSegment (battle_anim_electric.c:912). One segment: static,
# 15 frames, then gone. Reached directly when a script creates a segment
# itself rather than through the bolt task -- which no script in the roster
# does today (measured: 0 direct `createsprite` sites), so this is the
# unreached half of the callback. `data[0]` is 0 for a sprite the task did not
# seed, which is the 8x16 arm.
static func _electric_bolt_segment(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	node.set_frame_size(_BOLT_FRAME[0].x, _BOLT_FRAME[0].y)
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
	# ⚠️ `vm.move_turn`, NOT `vm.turn` — there is no such property, and reading
	# it threw `Invalid access to property or key 'turn'` on every Arm Thrust
	# hit, aborting this function before it positioned the sprite. Found by the
	# leak harness while fixing the counter this line consumes; the error was
	# silent in play because a script error does not stop the animation.
	var turn: int = vm.move_turn
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
	# ⚠️ Mirrored on the ANCHOR battler's side, not the attacker's — bit 15 of
	# arg 7 above chose that anchor, and source negates on `IsOnPlayerSide(
	# battler)` with the same `battler` it then positions against
	# (`battle_anim_electric.c:761-776`). Using the attacker's side inverted
	# the offset on 24 of this behavior's 236 call sites — every one whose
	# anchor is the target and whose x offset is nonzero.
	if _battler_is_player_side(vm, battler):
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
	# ⚠️ Source negates on `IsOnPlayerSide(gBattleAnimTarget)`
	# (`battle_anim_electric.c:740`) — the TARGET, which is also what it
	# positions against two lines later. The attacker's side is the opposite
	# one in singles, so reading it flipped the offset on the 2 of this
	# behavior's 9 call sites that pass a nonzero x.
	if _battler_is_player_side(vm, AnimStage.ANIM_TARGET):
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


const _SOLAR_BEAM_SMALL_ORB := "gSolarBeamSmallOrbSpriteTemplate"


# AnimTask_CreateSmallSolarBeamOrbs (battle_anim_effects_1.c:3146). No args in
# -- and it CLOBBERS gBattleAnimArgs[0..3] for each spawn, permanently. Spawns
# 15 orbs, one every 7 frames (~99 frames). The source comment says a 7-frame
# delay; the code uses 6, which with the -1 wrap is 7 frames between spawns.
#
# ⚠️ **IT MUST NAME ITS OWN TEMPLATE, AND PASSING THE TASK'S OWN `ctx` MEANT
# NO ORB EVER SPAWNED.** A `createvisualtask` receives
# `ctx = {"priority": N}` — there is no template in it, because a task is not
# a `createsprite`. Forwarding that ctx to `_solar_beam_small_orb` made
# `_make_sprite` return null every time, silently: **all 15 small orbs were
# missing** and Solar Beam played only its big linear orbs. Reported from play
# as "the animation is missing the rotating green element it just has the more
# linear portion of the beam". Source names the template explicitly —
# `CreateSpriteAndAnimate(&gSolarBeamSmallOrbSpriteTemplate, ...)`
# (battle_anim_effects_1.c:3146) — and `_make_sprite_named` exists for exactly
# this case.
static func _create_small_solar_beam_orbs(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var orb_ctx := {
		"template": _SOLAR_BEAM_SMALL_ORB,
		"template_data": AnimData.template(_SOLAR_BEAM_SMALL_ORB),
		"blend": ctx.get("blend", {}),
	}
	var st := {"t": 0, "made": 0}
	vm.add_stepper(func() -> bool:
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) % 7 == 1 and int(st["made"]) < 15:
			vm.args[0] = 15
			vm.args[1] = 0
			vm.args[2] = 80
			vm.args[3] = 0
			_solar_beam_small_orb(vm, orb_ctx)
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


# ─── [M36D batch 7] — closing the iconic tier ─────────────────────────────
#
# The last six blocked iconic moves: Thunder, Confuse Ray, Frustration, Volt
# Tackle, Dragon Dance and Extreme Speed.
#
# Step 0 was asked up front which of these mutate a BATTLER rather than
# spawning particles, because that is the leak class M36 has hit four times.
# The answer is better than Dig's: only TWO pairings are required —
# AttackerStretchAndDisappear -> ExtremeSpeedMonReappear (visibility), and
# VoltTackleOrbSlide -> VoltTackleAttackerReappear (a +/-320px displacement).
# Everything else in the batch restores itself. Both pairings still route
# through MonOffset and the tracked visibility setter, so a script that breaks
# the pair is caught by the VM's end-of-run restores.


# AnimLightning (battle_anim_electric.c:583). args: 0/1 offset, mirrored by
# side. Lives exactly as long as its own 28-frame cel animation.
static func _lightning(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var x := float(vm.args[0]) * (1.0 if _is_player_side(vm) else -1.0)
	node.centre = _battler_centre(vm, AnimStage.ANIM_TARGET) \
			+ Vector2(x, float(vm.args[1])) * scale
	_play_until_anim_ends(vm, node, _ANIM_END_CAP)


# AnimTask_InvertScreenColor (battle_anim_normal.c:846). arg0 is a bitfield
# selecting scenery (0x1), attacker (0x2), target (0x4) and the two partners.
#
# GENUINELY UN-PORTABLE AS WRITTEN, and worth stating plainly. Upstream calls
# InvertPlttBuffer (palette.c:384), a bitwise NOT of every entry of the
# selected palettes -- of BGR555 words, including bit 15, not of pixels. There
# is no palette indirection here, so the equivalent is a per-pixel colour
# inversion in the shader.
#
# The important property is that it is an INVOLUTION and upstream restores
# nothing: Thunder calls it an EVEN number of times and relies on the second
# call undoing the first. Reproduced as a toggle for exactly that reason -- a
# port that always inverted would leave the screen wrong after an odd count.
static func _invert_screen_color(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var flags: int = vm.args[0]
	var targets: Array = []
	if (flags & 0x2) != 0:
		targets.append(_battler_node(vm, AnimStage.ANIM_ATTACKER))
	if (flags & 0x4) != 0:
		targets.append(_battler_node(vm, AnimStage.ANIM_TARGET))
	if (flags & 0x1) != 0 and vm.stage != null \
			and vm.stage.has_method("background_layer"):
		targets.append(vm.stage.background_layer())
	for n in targets:
		if n != null and is_instance_valid(n):
			_toggle_invert(n)


static func _toggle_invert(node: CanvasItem) -> void:
	if _recolor_shader == null:
		_recolor_shader = Shader.new()
		_recolor_shader.code = _RECOLOR_SHADER_CODE
	var mat := node.material as ShaderMaterial
	if mat == null or mat.shader != _recolor_shader:
		mat = ShaderMaterial.new()
		mat.shader = _recolor_shader
		node.material = mat
	var cur := float(mat.get_shader_parameter("invert") if
			mat.get_shader_parameter("invert") != null else 0.0)
	mat.set_shader_parameter("invert", 0.0 if cur > 0.5 else 1.0)


# AnimTask_ShakeTargetInPattern (battle_anim_fire.c:1406). args: 0 max shakes,
# 1 offset, 2 vertical flag, 3 pattern id. Walks a fixed 10-entry direction
# table rather than alternating, which is what makes it read as a stagger
# rather than a buzz. Restores both offsets on the final frame.
static func _shake_target_in_pattern(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var node := _battler_node(vm, AnimStage.ANIM_TARGET)
	if node == null:
		return
	var scale := _scale(vm)
	var mon := MonOffset.new(node)
	var pattern: Array = _SHAKE_PATTERN_1 if vm.args[3] != 0 \
			else _SHAKE_PATTERN_0
	var max_shakes: int = maxi(1, vm.args[0])
	var offset := float(vm.args[1]) * scale
	var vertical: bool = vm.args[2] != 0
	var st := {"n": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		st["n"] = int(st["n"]) + 1
		var dir: float = float(pattern[int(st["n"]) % 10])
		# Vertical mode takes the ABSOLUTE value upstream, so the target only
		# ever bounces downward -- a real asymmetry between the two modes.
		mon.apply(Vector2(0.0, absf(offset * dir)) if vertical
				else Vector2(offset * dir, 0.0))
		if int(st["n"]) >= max_shakes:
			mon.restore()
			return true
		return false)


# sShakeDirsPattern0/1 (battle_anim_fire.c:433/:438), verbatim. Only the first
# 10 entries are ever reachable, but they are kept whole so the tables match
# their declarations.
const _SHAKE_PATTERN_0: Array[int] = [
	-1, -1, 0, 1, 1, 0, 0, -1, -1, 1, 1, 0, 0, -1, 0, 1]
const _SHAKE_PATTERN_1: Array[int] = [
	-1, 0, 1, 0, -1, 1, 0, -1, 0, 1, 0, -1, 0, 1, 0, 1]


# AnimConfuseRayBallBounce (battle_anim_ghost.c:252). args: 0/1 offset,
# 2 SPEED (not a duration -- upstream converts it to a frame count). Travels
# to the target with a sine bounce riding on the translation, then hovers
# there pulsing its blend until the pulse completes.
static func _confuse_ray_ball_bounce(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var start := _positioned_centre(vm, AnimStage.ANIM_ATTACKER, vm.args[0],
			vm.args[1], scale)
	var dest := _battler_centre(vm, AnimStage.ANIM_TARGET)
	node.centre = start
	var speed: int = maxi(1, vm.args[2])
	var duration: int = maxi(1, int(absf(dest.x - start.x) * 256.0
			/ float(speed) / maxf(scale, 0.001)))
	var st := {"t": 0, "ang": 0, "phase": 0, "blend": 16, "dir": -1,
			"hold": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var a: int = int(st["ang"])
		var bounce := Vector2(_gba_sin(a, 10.0 * scale),
				_gba_cos(a, 15.0 * scale))
		st["ang"] = (a + 5) & 0xFF
		if int(st["phase"]) == 0:
			st["t"] = int(st["t"]) + 1
			node.centre = start.lerp(dest,
					float(st["t"]) / float(duration)) + bounce
			if int(st["t"]) >= duration:
				st["phase"] = 1
			return false
		# Hovering: the blend pulses down, holds, then ends the effect.
		node.centre = dest + bounce
		st["blend"] = int(st["blend"]) + int(st["dir"])
		if int(st["blend"]) <= 0:
			st["hold"] = int(st["hold"]) + 1
			st["blend"] = 0
			if int(st["hold"]) > 13:
				node.finish()
				return true
		elif int(st["blend"]) >= 16:
			st["dir"] = -1
		node.modulate.a = clampf(float(st["blend"]) / 16.0, 0.0, 1.0)
		return false)


# AnimConfuseRayBallSpiral (battle_anim_ghost.c:345, step :352). args: 0/1
# offset. An ELLIPTICAL orbit (radius 32 across, only 8 down) that also drifts
# downward, and passes BEHIND the mon on the far half. Exactly 61 frames.
static func _confuse_ray_ball_spiral(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var base := _positioned_centre(vm, AnimStage.ANIM_TARGET, vm.args[0],
			vm.args[1], scale)
	node.centre = base
	var st := {"ang": 0, "drift": 0, "t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var a: int = int(st["ang"])
		st["drift"] = int(st["drift"]) + 80
		node.centre = base + Vector2(_gba_sin(a, 32.0 * scale),
				_gba_cos(a, 8.0 * scale)
				+ float(int(st["drift"]) >> 8) * scale)
		st["ang"] = (a + 19) & 0xFF
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) >= 61:
			node.finish()
			return true
		return false)


# AnimTask_BlendColorCycleByTag (battle_anim_normal.c:659). args: 0 tag,
# 1 delay, 2 blend count, 3 initial, 4 target, 5 colour. Alternates a palette
# fade up and down `numBlends` times, and FORCES the final target to 0 so it
# always lands unblended -- so unlike batch 5's exclude-blend, this one is
# genuinely self-restoring.
static func _blend_color_cycle_by_tag(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var stage = vm.stage
	if stage == null or not stage.has_method("layer"):
		return
	var layer: Control = stage.layer()
	if layer == null:
		return
	var delay: int = maxi(0, vm.args[1])
	var blends: int = maxi(1, vm.args[2])
	var lo := clampf(float(vm.args[3]) / 16.0, 0.0, 1.0)
	var hi := clampf(float(vm.args[4]) / 16.0, 0.0, 1.0)
	var colour := _rgb15_to_color(vm.args[5])
	var st := {"left": blends, "amt": lo, "dir": 1, "tick": 0}
	vm.add_stepper(func() -> bool:
		st["tick"] = int(st["tick"]) + 1
		if int(st["tick"]) <= delay:
			return false
		st["tick"] = 0
		var target: float = hi if int(st["dir"]) > 0 else lo
		# The last cycle always aims at 0, which is what guarantees it ends
		# unblended regardless of the configured low point.
		if int(st["left"]) <= 1:
			target = 0.0
		st["amt"] = move_toward(float(st["amt"]), target, 1.0 / 16.0)
		for child in layer.get_children():
			if child is AnimSprite:
				_apply_blend_amount(child, colour, float(st["amt"]))
		if is_equal_approx(float(st["amt"]), target):
			st["dir"] = -int(st["dir"])
			st["left"] = int(st["left"]) - 1
			if int(st["left"]) <= 0:
				for child in layer.get_children():
					if child is AnimSprite:
						_clear_blend(child)
				return true
		return false)


# AnimTask_GetFrustrationPowerLevel (battle_anim_mons.c:1949). Writes a 0-3
# band into arg 7 from friendship -- and note it is INVERTED relative to
# Return's: 0 is the STRONGEST band here, because low friendship means a
# stronger Frustration.
static func _get_frustration_power_level(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var f: int = vm.friendship
	var band := 3
	if f <= 30:
		band = 0
	elif f <= 100:
		band = 1
	elif f <= 200:
		band = 2
	vm.args[AnimScriptVM.ARG_RET] = band


# AnimTask_StrongFrustrationGrowAndShrink (battle_anim_effects_3.c:2843).
# No args. Squashes the attacker vertically (-15/frame for 7, then +15 for 7)
# twice over -- 28 frames. Fully self-restoring, because the affine table's
# END resets the scale.
static func _strong_frustration_grow(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var node := _battler_node(vm, AnimStage.ANIM_ATTACKER)
	if node == null:
		return
	var base_scale := node.scale
	var st := {"t": 0, "y": 0.0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		st["t"] = int(st["t"]) + 1
		var phase := (int(st["t"]) - 1) % 14
		st["y"] = float(st["y"]) + (-15.0 if phase < 7 else 15.0)
		node.scale = Vector2(base_scale.x,
				base_scale.y * (1.0 + float(st["y"]) / 256.0))
		if int(st["t"]) >= 28:
			node.scale = base_scale
			return true
		return false)


# AnimWeakFrustrationAngerMark (battle_anim_effects_3.c:2860). args: 0/1
# offset. Sits still for 22 frames, then slides outward LINEARLY while falling
# with QUADRATIC acceleration -- ends when it has fallen 64px.
static func _weak_frustration_anger_mark(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var base := _positioned_centre(vm, AnimStage.ANIM_ATTACKER, vm.args[0],
			vm.args[1], scale)
	node.centre = base
	var side := 1.0 if _is_player_side(vm) else -1.0
	var st := {"t": 0, "x": 0, "yv": 0, "y": 0.0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) <= 22:
			return false
		st["x"] = int(st["x"]) + 160
		st["yv"] = int(st["yv"]) + 128
		st["y"] = float(st["y"]) + float(int(st["yv"]) >> 8)
		node.centre = base + Vector2(
				float(int(st["x"]) >> 8) * side, float(st["y"])) * scale
		if float(st["y"]) > 64.0:
			node.finish()
			return true
		return false)


# AnimTask_VoltTackleAttackerReappear (battle_anim_electric.c:1124). No args.
# THE RESTORE PARTNER for AnimVoltTackleOrbSlide: it hard-sets the attacker's
# offset to +/-32 and walks it to exactly 0 over 32 frames while flickering,
# then makes it visible. Without this the attacker stays ~320px off-screen.
static func _volt_tackle_attacker_reappear(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var node := _battler_node(vm, AnimStage.ANIM_ATTACKER)
	if node == null:
		return
	var scale := _scale(vm)
	var mon := MonOffset.new(node)
	var off := (-32.0 if _is_player_side(vm) else 32.0) * scale
	var step := (2.0 if _is_player_side(vm) else -2.0) * scale
	var st := {"off": off, "t": 0, "flick": 0, "phase": 0}
	mon.apply(Vector2(off, 0.0))
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		st["flick"] = int(st["flick"]) + 1
		if int(st["flick"]) > 1:
			st["flick"] = 0
			node.visible = not node.visible
		if int(st["phase"]) == 0:
			st["off"] = float(st["off"]) + step
			if absf(float(st["off"])) < absf(step):
				st["off"] = 0.0
				st["phase"] = 1
				st["t"] = 0
			mon.apply(Vector2(float(st["off"]), 0.0))
			return false
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) >= 16:
			mon.restore()
			vm.set_battler_visible_tracked(AnimStage.ANIM_ATTACKER, true)
			return true
		return false)


# AnimTask_VoltTackleBolt (battle_anim_electric.c:1182). arg0 is a lane index
# 0..4. Marches a line of bolts across the field, TWO per frame 16px apart,
# then waits for every bolt to expire before finishing.
static func _volt_tackle_bolt(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var scale := _scale(vm)
	var layer: Control = vm.stage.layer() if vm.stage != null \
			and vm.stage.has_method("layer") else null
	var width: float = layer.size.x if layer != null else 1024.0
	var lane: int = vm.args[0]
	var player := _is_player_side(vm)
	var y: float = _battler_centre(vm, AnimStage.ANIM_ATTACKER).y \
			if lane == 0 else _battler_centre(vm, AnimStage.ANIM_TARGET).y
	if lane != 0 and lane != 4:
		y = (80.0 - float(lane) * 10.0) * scale if player \
				else (float(lane) * 10.0 + 40.0) * scale
	var from_x := 0.0 if player else width
	var to_x := width if player else 0.0
	var st := {"x": from_x, "made": 0}
	vm.add_stepper(func() -> bool:
		for i in range(2):
			var b := _make_sprite(vm, ctx)
			if b != null:
				b.centre = Vector2(float(st["x"]), y)
				_volt_bolt_life(vm, b)
			st["x"] = float(st["x"]) + (16.0 * scale
					* (1.0 if player else -1.0))
			st["made"] = int(st["made"]) + 1
		if player:
			return float(st["x"]) > to_x
		return float(st["x"]) < to_x)


static func _volt_bolt_life(vm: AnimScriptVM, node: AnimSprite) -> void:
	var st := {"t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) >= 12:
			node.finish()
			return true
		return false)


# AnimVoltTackleOrbSlide (battle_anim_electric.c:1094, step :1108). No args.
#
# CHARGES for 41 frames, then DRAGS THE ATTACKER off-screen with it at 16
# px/frame -- and never puts it back. That is real upstream behaviour, not an
# omission: AnimTask_VoltTackleAttackerReappear is the restore, paired by the
# script. Everything here goes through MonOffset so a broken pair is still
# caught by the VM's end-of-run restore.
static func _volt_tackle_orb_slide(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var mon_node := _battler_node(vm, AnimStage.ANIM_ATTACKER)
	var mon := MonOffset.new(mon_node) if mon_node != null else null
	var start := _battler_centre(vm, AnimStage.ANIM_ATTACKER)
	node.centre = start
	var layer: Control = vm.stage.layer() if vm.stage != null \
			and vm.stage.has_method("layer") else null
	var width: float = layer.size.x if layer != null else 1024.0
	var step := (16.0 if _is_player_side(vm) else -16.0) * scale
	var st := {"t": 0, "phase": 0, "off": 0.0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		if int(st["phase"]) == 0:
			st["t"] = int(st["t"]) + 1
			if int(st["t"]) > 40:
				st["phase"] = 1
			return false
		st["off"] = float(st["off"]) + step
		node.centre = start + Vector2(float(st["off"]), 0.0)
		if mon != null:
			mon.apply(Vector2(float(st["off"]), 0.0))
		if node.centre.x < -80.0 * scale \
				or node.centre.x > width + 80.0 * scale:
			node.finish()
			return true
		return false)


# AnimDragonDanceOrb (battle_anim_dragon.c:473, step :495). arg0 is the
# starting angle, so six of them spawn evenly spaced. Orbits the attacker at a
# radius derived from the mon's OWN size, ACCELERATING from 1 to 16 units per
# frame, then flares the radius outward. 82 frames.
static func _dragon_dance_orb(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var base := _battler_centre(vm, AnimStage.ANIM_ATTACKER)
	var mon := _battler_node(vm, AnimStage.ANIM_ATTACKER)
	var box := mon.size if mon != null else Vector2(64, 64)
	var radius := maxf(box.x, box.y) * 0.5
	var st := {"ang": vm.args[0], "speed": 1, "tick": 0, "t": 0,
			"phase": 0, "r": radius}
	node.centre = base + Vector2(_gba_cos(vm.args[0], radius),
			_gba_sin(vm.args[0], radius))
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		st["ang"] = (int(st["ang"]) - int(st["speed"])) & 0xFF
		st["tick"] = int(st["tick"]) + 1
		if int(st["tick"]) > 5:
			st["tick"] = 0
			st["speed"] = mini(16, int(st["speed"]) + 1)
		st["t"] = int(st["t"]) + 1
		if int(st["phase"]) == 0:
			if int(st["t"]) > 60:
				st["phase"] = 1
				st["t"] = 0
		else:
			st["r"] = minf(150.0 * scale, float(st["r"]) + 8.0 * scale)
			if int(st["t"]) > 20:
				node.finish()
				return true
		var a: int = int(st["ang"])
		node.centre = base + Vector2(_gba_cos(a, float(st["r"])),
				_gba_sin(a, float(st["r"])))
		return false)


# AnimTask_BlendPalInAndOutByTag (battle_anim_mons.c:1739). args: 0 tag,
# 1 colour, 2 target coefficient, 3 delay, 4 cycle count. Ramps up and back
# down that many times and always ends at 0 -- self-restoring.
static func _blend_pal_in_and_out_by_tag(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var stage = vm.stage
	if stage == null or not stage.has_method("layer"):
		return
	var layer: Control = stage.layer()
	if layer == null:
		return
	var colour := _rgb15_to_color(vm.args[1])
	var target := clampf(float(vm.args[2]) / 16.0, 0.0, 1.0)
	var delay: int = maxi(1, vm.args[3])
	var cycles: int = maxi(1, vm.args[4])
	var st := {"amt": 0.0, "dir": 1, "left": cycles, "tick": 0}
	vm.add_stepper(func() -> bool:
		st["tick"] = int(st["tick"]) + 1
		if int(st["tick"]) < delay:
			return false
		st["tick"] = 0
		st["amt"] = float(st["amt"]) + (1.0 / 16.0) * float(int(st["dir"]))
		if float(st["amt"]) >= target:
			st["amt"] = target
			st["dir"] = -1
		elif float(st["amt"]) <= 0.0:
			st["amt"] = 0.0
			st["dir"] = 1
			st["left"] = int(st["left"]) - 1
			if int(st["left"]) <= 0:
				for child in layer.get_children():
					if child is AnimSprite:
						_clear_blend(child)
				return true
		for child in layer.get_children():
			if child is AnimSprite:
				_apply_blend_amount(child, colour, float(st["amt"]))
		return false)


# AnimTask_DragonDanceWaver (battle_anim_dragon.c:535). No args, and NO sprite
# -- upstream this is a per-scanline horizontal offset applied to whichever BG
# layer the script has moved the attacker into via `monbg`, producing a heat
# haze over the mon.
#
# There are no scanlines here, so the equivalent is a horizontal wobble of the
# attacker itself, on the same ramp-in / hold / ramp-out envelope (~75 frames)
# and the same wave rate. Recorded as an approximation of the MECHANISM; the
# timing is source-exact. Fully self-restoring.
static func _dragon_dance_waver(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var node := _battler_node(vm, AnimStage.ANIM_ATTACKER)
	if node == null:
		return
	var scale := _scale(vm)
	var mon := MonOffset.new(node)
	var st := {"phase": 0, "t": 0, "amp": 0.0, "wave": 0, "tick": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		st["tick"] = int(st["tick"]) + 1
		match int(st["phase"]):
			0:
				if int(st["tick"]) % 2 == 0:
					st["amp"] = float(st["amp"]) + 1.0
					if float(st["amp"]) >= 3.0:
						st["phase"] = 1
						st["t"] = 0
			1:
				st["t"] = int(st["t"]) + 1
				if int(st["t"]) > 60:
					st["phase"] = 2
			2:
				if int(st["tick"]) % 2 == 0:
					st["amp"] = float(st["amp"]) - 1.0
					if float(st["amp"]) <= 0.0:
						mon.restore()
						return true
		st["wave"] = (int(st["wave"]) + 9) & 0xFF
		mon.apply(Vector2(_gba_sin(int(st["wave"]),
				float(st["amp"]) * 4.0 * scale), 0.0))
		return false)


# AnimTask_SetAttackerInvisibleWaitForSignal (battle_anim_utility_funcs.c:1037).
#
# Waits on arg 7 == 0x1000 (4096) -- NOT the -1 sentinel every other waiting
# behavior in this engine uses, which is exactly the kind of detail worth
# pinning. Upstream decrements the visual task count by hand so the script
# cannot deadlock waiting on a task that is waiting on the script; that is
# reproduced here as an UNCOUNTED stepper.
#
# If the script never sends the signal, upstream strands the battler's
# visibility flag TRUE forever. Here it goes through the tracked setter, so
# the VM's end-of-run restore catches it.
static func _attacker_invisible_wait(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	vm.set_battler_visible_tracked(AnimStage.ANIM_ATTACKER, false)
	var step := func() -> bool:
		if vm.args[AnimScriptVM.ARG_RET] == 0x1000:
			vm.set_battler_visible_tracked(AnimStage.ANIM_ATTACKER, true)
			return true
		return false
	vm.add_stepper(step, false)


# AnimTask_AttackerStretchAndDisappear (battle_anim_effects_2.c:2741).
# No args. Stretches the attacker wide and flat over 8 frames (xScale +96,
# yScale -13 per frame) and then HIDES it -- deliberately leaving it hidden
# for AnimTask_ExtremeSpeedMonReappear to undo. The scale IS restored; only
# visibility is left for the partner.
static func _attacker_stretch_disappear(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var node := _battler_node(vm, AnimStage.ANIM_ATTACKER)
	if node == null:
		return
	var base_scale := node.scale
	var st := {"t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		st["t"] = int(st["t"]) + 1
		var t := float(st["t"])
		node.scale = Vector2(base_scale.x * (1.0 + 96.0 * t / 256.0),
				base_scale.y * (1.0 - 13.0 * t / 256.0))
		if int(st["t"]) >= 8:
			node.scale = base_scale
			vm.set_battler_visible_tracked(AnimStage.ANIM_ATTACKER, false)
			return true
		return false)


# AnimTask_ExtremeSpeedImpact (battle_anim_effects_2.c:2761). No args. Shoves
# the TARGET, judders it, three times over -- then walks the accumulated
# offset back to exactly 0 one pixel at a time. Self-restoring by construction.
static func _extreme_speed_impact(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var node := _battler_node(vm, AnimStage.ANIM_TARGET)
	if node == null:
		return
	var scale := _scale(vm)
	var mon := MonOffset.new(node)
	var push := (8.0 if not _is_player_side(vm) else -8.0) * scale
	var back := -signf(push) * scale
	var st := {"phase": 0, "reps": 3, "off": 0.0, "t": 0, "j": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		match int(st["phase"]):
			0:
				st["off"] = float(st["off"]) + push
				st["phase"] = 1
				st["t"] = 0
				st["j"] = 0
			1:
				st["t"] = int(st["t"]) + 1
				if int(st["t"]) % 2 == 0:
					st["j"] = int(st["j"]) + 1
					if int(st["j"]) > 4:
						st["reps"] = int(st["reps"]) - 1
						st["phase"] = 0 if int(st["reps"]) > 0 else 2
			2:
				st["off"] = float(st["off"]) + back
				if absf(float(st["off"])) < absf(back):
					mon.restore()
					return true
		var judder := 0.0
		if int(st["phase"]) == 1 and int(st["j"]) % 2 == 1:
			judder = 6.0 * signf(push) * scale
		mon.apply(Vector2(float(st["off"]) + judder, 0.0))
		return false)


# AnimTask_ExtremeSpeedMonReappear (battle_anim_effects_2.c:2830). No args.
# THE RESTORE PARTNER for AttackerStretchAndDisappear: flickers the attacker
# 14 times over 28 frames and ends with it visible.
static func _extreme_speed_reappear(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var node := _battler_node(vm, AnimStage.ANIM_ATTACKER)
	if node == null:
		return
	var st := {"t": 0, "toggles": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) % 2 == 0:
			node.visible = not node.visible
			st["toggles"] = int(st["toggles"]) + 1
			if int(st["toggles"]) >= 14:
				vm.set_battler_visible_tracked(AnimStage.ANIM_ATTACKER, true)
				return true
		return false)


# AnimTask_SpeedDust (battle_anim_effects_2.c:2872). No args. Spawns 24 dust
# puffs, one every 5 frames, cycling a 4-entry position table, then waits for
# them all to expire. Every puff copies the task's own flicker flag each
# frame, so they blink in unison rather than independently.
static func _speed_dust(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var scale := _scale(vm)
	var base := _battler_centre(vm, AnimStage.ANIM_ATTACKER)
	var st := {"t": 0, "made": 0, "slot": 0}
	vm.add_stepper(func() -> bool:
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) % 5 == 1 and int(st["made"]) < 24:
			var d := _make_sprite(vm, ctx)
			if d != null:
				var pos: Vector2 = _SPEED_DUST_POS[int(st["slot"])]
				d.centre = base + pos * scale
				_play_until_anim_ends(vm, d, 15)
			st["slot"] = (int(st["slot"]) + 1) % 4
			st["made"] = int(st["made"]) + 1
		return int(st["made"]) >= 24 and int(st["t"]) > 24 * 5 + 15)


# gSpeedDustPosTable (battle_anim_effects_2.c:770), verbatim.
const _SPEED_DUST_POS: Array[Vector2] = [
	Vector2(30, 28), Vector2(-20, 24), Vector2(16, 26), Vector2(-10, 28)]


# AnimHitSplatOnMonEdge (battle_anim_normal.c:1157). args: 0 battler,
# 1/2 offset, 3 affine variant. Positioned from the battler sprite's ORIGIN
# rather than its centre -- that is the "on mon edge" part, and using the
# centre would put every splat in the wrong place.
static func _hit_splat_on_mon_edge(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var battler: int = AnimStage.ANIM_ATTACKER if vm.args[0] == 0 \
			else AnimStage.ANIM_TARGET
	var mon := _battler_node(vm, battler)
	var origin := mon.position if mon != null \
			else _battler_centre(vm, battler)
	node.scale = Vector2.ONE * scale * _HIT_SPLAT_SCALES[clampi(vm.args[3], 0,
			_HIT_SPLAT_SCALES.size() - 1)]
	node.centre = origin + Vector2(float(vm.args[1]),
			float(vm.args[2])) * scale
	var st := {"t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) >= 8:
			node.finish()
			return true
		return false)


# Creates a loose sprite from an extracted template, for the tasks that spawn
# their own particles rather than being spawned by a `createsprite` opcode.
# Mirrors what `_make_sprite` does for the opcode path, but takes the template
# by name because a visual task's ctx carries no sprite of its own.
static func _spawn_template_sprite(vm: AnimScriptVM, layer: Control,
		template_name: String, centre: Vector2) -> AnimSprite:
	var tmpl := AnimData.template(template_name)
	var tag := str((tmpl.get("tile_tag", {}) as Dictionary).get("name", ""))
	if tag == "" or layer == null:
		return null
	var node := AnimSprite.create(vm, tag, 16, 16)
	if node == null:
		return null
	layer.add_child(node)
	node.scale = Vector2.ONE * _scale(vm)
	node.centre = centre
	var seqs := AnimData.anim_sequences_for(template_name)
	if not seqs.is_empty():
		node.play_sequence(seqs[0])
	return node


# ── [M36D batch 8] the shared blockers ────────────────────────────────────
#
# Selection changed character here. Batches 1-7 worked the iconic Gen 1-3
# tier, which is now closed at 70/70, so this batch is picked purely by how
# many BLOCKED moves each behavior appears in -- 231 move-slots across
# twelve. The visibility trio alone accounts for 72 of those and is the
# cheapest kind of behavior there is.


# Resolves whether a given anim-battler sits on the player's side. The
# attacker's side is known outright; the others are the opposite of it unless
# the stage resolves them to the same Pokemon (a self- or ally-target).
#
# ⚠️ **THIS IS THE ONE TO USE FOR UPSTREAM'S MIRRORING IDIOM, NOT
# `_is_player_side`.** That idiom is `if (IsContest() || IsOnPlayerSide(
# battler)) args[n] = -args[n]`, where `battler` is whichever battler the
# sprite is ANCHORED to — frequently the target. Reading the attacker's side
# there does not lose the offset, it INVERTS it, so the effect lands on the
# wrong side of the mon and still looks deliberate. Two electric behaviors
# shipped that way (`AnimSparkElectricityFlashing`, `AnimThunderboltOrb`) and
# were only caught by reading their source beside the port.
static func _battler_is_player_side(vm: AnimScriptVM, anim_battler: int) -> bool:
	var atk_is_player := _is_player_side(vm)
	if anim_battler == AnimStage.ANIM_ATTACKER \
			or anim_battler == AnimStage.ANIM_ATK_PARTNER:
		return atk_is_player
	if vm.stage != null and vm.stage.has_method("mon_for"):
		var atk: Variant = vm.stage.mon_for(AnimStage.ANIM_ATTACKER)
		var other: Variant = vm.stage.mon_for(anim_battler)
		if atk != null and atk == other:
			return atk_is_player
	return not atk_is_player


# ── Whole-field visibility ────────────────────────────────────────────────
#
# All three are one-frame raw setters that RESTORE NOTHING -- upstream relies
# entirely on the script making the paired call, with no net of any kind. All
# three therefore route through the VM's tracked setter, so a script that
# ends early (or a behavior it depends on that is not yet ported) cannot
# strand a Pokemon invisible for the rest of the battle. Same treatment as
# `_set_all_non_attackers_invisible` and the Dig pair.

# AnimTask_AllBattlersInvisible (battle_anim_new.c:7422).
static func _all_battlers_invisible(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	for i in range(4):
		if _battler_node(vm, i) != null:
			vm.set_battler_visible_tracked(i, false)


# AnimTask_AllBattlersVisible (:7434) -- the paired restore.
static func _all_battlers_visible(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	for i in range(4):
		if _battler_node(vm, i) != null:
			vm.set_battler_visible_tracked(i, true)


# AnimTask_AllBattlersInvisibleExceptAttackerAndTarget (:7447). Upstream
# compares SPRITE IDS, not battler ids -- so any slot resolving to the same
# sprite as the attacker or target is skipped rather than hidden. Reproduced
# by comparing the resolved nodes, which keeps singles (where the partner
# slots have no sprite at all) and an ally-target both behaving correctly.
static func _all_battlers_invisible_except_pair(vm: AnimScriptVM,
		_ctx: Dictionary) -> void:
	var keep: Array[Control] = []
	for b in [AnimStage.ANIM_ATTACKER, AnimStage.ANIM_TARGET]:
		var n := _battler_node(vm, b)
		if n != null:
			keep.append(n)
	for i in range(4):
		var node := _battler_node(vm, i)
		if node == null or keep.has(node):
			continue
		vm.set_battler_visible_tracked(i, false)


# ── Power/damage-scaled shake ─────────────────────────────────────────────

# AnimTask_ShakeTargetBasedOnMovePowerOrDmg (battle_anim_mon_movement.c:1169,
# setup :1119, step :1176). args: 0 source (0 = move power, 1 = damage dealt),
# 1 delay between steps, 2 number of steps, 3 shake horizontally,
# 4 shake vertically.
#
# The magnitude is `source / 12` clamped to 1..16, and it is then split
# ASYMMETRICALLY: the sprite moves +ceil(mag/2) one way and -floor(mag/2) the
# other, so an odd magnitude leans in the positive direction rather than
# rocking evenly. Reproduced exactly.
#
# The horizontal and vertical halves are also not written the same way, which
# is a real upstream quirk rather than a simplification here: x is offset
# FROM the sprite's captured displacement, while y is assigned ABSOLUTELY
# (`y2 = mag` / `y2 = 0`), discarding whatever vertical offset was already in
# place. Both are ported as written.
static func _shake_target_by_power_or_dmg(vm: AnimScriptVM,
		_ctx: Dictionary) -> void:
	var node := _battler_node(vm, AnimStage.ANIM_TARGET)
	if node == null:
		return
	var source: int = vm.move_damage if vm.args[0] != 0 else vm.move_power
	var mag: int = clampi(source / 12, 1, 16)
	var down: int = mag / 2
	var up: int = down + (mag & 1)
	var delay: int = maxi(0, vm.args[1])
	var steps: int = maxi(1, vm.args[2])
	var horizontal: bool = vm.args[3] != 0
	var vertical: bool = vm.args[4] != 0
	var scale := _scale(vm)
	var mon := MonOffset.new(node)
	var captured := node.position - mon.base

	var st := {"t": 0, "phase": 0, "left": steps}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) <= delay:
			return false
		st["t"] = 0
		st["phase"] = (int(st["phase"]) + 1) & 1
		var on: bool = int(st["phase"]) == 1
		var offset := captured
		if horizontal:
			offset.x = captured.x + (float(up) if on else -float(down)) * scale
		if vertical:
			offset.y = float(mag) * scale if on else 0.0
		mon.apply(offset)
		st["left"] = int(st["left"]) - 1
		if int(st["left"]) <= 0:
			mon.restore()  # upstream forces BOTH offsets to zero here
			return true
		return false)


# ── Rocking with rotation ─────────────────────────────────────────────────

# AnimTask_RockMonBackAndForth (battle_anim_effects_3.c:2887, step :2929).
# args: 0 battler, 1 number of rocks, 2 intensity (clamped 0..2).
#
# A four-state walk whose three motion phases are out / back-twice / out
# again, so the horizontal travel and the rotation both cancel EXACTLY over
# one cycle rather than needing a restore -- the final state resets the
# matrix and ends. A count of zero destroys the task with no motion at all,
# which is a real early-out and not an error.
#
# Intensity drives all three numbers at once, and the result is not what the
# constants suggest: it shortens each phase (8 - 2*i frames) exactly as fast
# as it widens the horizontal step (i + 2 px), so the peak travel lands at
# 16 / 18 / 16 px across the three tiers and is not even monotonic. Total
# rotation per phase behaves the same way (2048 / 2304 / 2048, in 1/65536
# turns). What intensity ACTUALLY controls is how fast the mon rocks --
# a full cycle is 4 * (8 - 2*i) frames. An opponent-side battler mirrors both
# the rotation and the travel.
static func _rock_mon_back_and_forth(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var node := _battler_node(vm, vm.args[0])
	if node == null:
		return
	if vm.args[1] == 0:
		return  # upstream destroys the task immediately
	var intensity: int = clampi(vm.args[2], 0, 2)
	var phase_frames: int = 8 - 2 * intensity
	var rot_step: int = 0x100 + intensity * 128
	var x_step: int = intensity + 2
	if not _battler_is_player_side(vm, vm.args[0]):
		rot_step = -rot_step
		x_step = -x_step

	var scale := _scale(vm)
	var mon := MonOffset.new(node)
	var base_rot := node.rotation
	var base_pivot := node.pivot_offset
	node.pivot_offset = node.size * 0.5

	var st := {"phase": 0, "t": 0, "cycles": vm.args[1] - 1, "x": 0, "rot": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		var phase: int = int(st["phase"])
		if phase == 3:
			node.rotation = base_rot
			node.pivot_offset = base_pivot
			mon.restore()
			return true

		# Phase 1 travels back; 0 and 2 travel out. Rotation is the mirror.
		var dir := -1 if phase == 1 else 1
		st["x"] = int(st["x"]) + x_step * dir
		st["rot"] = int(st["rot"]) - rot_step * dir
		mon.apply(Vector2(float(st["x"]) * scale, 0.0))
		node.rotation = base_rot + float(st["rot"]) * TAU / 65536.0

		st["t"] = int(st["t"]) + 1
		var limit: int = phase_frames * 2 if phase == 1 else phase_frames
		if int(st["t"]) < limit:
			return false
		st["t"] = 0
		if phase < 2:
			st["phase"] = phase + 1
		elif int(st["cycles"]) > 0:
			st["cycles"] = int(st["cycles"]) - 1
			st["phase"] = 0
		else:
			st["phase"] = 3
		return false)


# ── Platform shake ────────────────────────────────────────────────────────

# AnimTask_ShakeBattlePlatforms (battle_anim_normal.c:1042, step :1056).
# args: 0 x offset, 1 y offset, 2 number of shakes, 3 delay.
#
# Drives the platform background layer, not any sprite. Two details worth
# keeping: setup writes the offset and then calls its own step function
# immediately, so with a delay of 0 the first toggle lands on the same frame;
# and the two axes toggle differently -- x flips between +offset and -offset
# while y alternates between -offset and ZERO, never going positive.
#
# Scroll is applied relative to whatever the background was already showing
# (a scroll may be in progress) and restored to exactly that, matching the
# capture-and-restore rule M36E3's own platform shake established.
static func _shake_battle_platforms(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var stage = vm.stage
	if stage == null or not stage.has_method("set_background_scroll"):
		return
	var scale := _scale(vm)
	var off := Vector2(float(vm.args[0]), float(vm.args[1])) * scale
	var shakes: int = maxi(1, vm.args[2])
	var delay: int = maxi(0, vm.args[3])
	var initial: Vector2 = stage.background_scroll()
	stage.set_background_scroll(initial + off)

	var st := {"timer": delay, "left": shakes, "x_pos": true, "y_down": true}
	vm.add_stepper(func() -> bool:
		if int(st["timer"]) > 0:
			st["timer"] = int(st["timer"]) - 1
			return false
		st["x_pos"] = not bool(st["x_pos"])
		st["y_down"] = not bool(st["y_down"])
		st["timer"] = delay
		st["left"] = int(st["left"]) - 1
		if int(st["left"]) <= 0:
			stage.set_background_scroll(initial)
			return true
		var x := off.x if bool(st["x_pos"]) else -off.x
		var y := -off.y if bool(st["y_down"]) else 0.0
		stage.set_background_scroll(initial + Vector2(x, y))
		return false)


# ── Fly ───────────────────────────────────────────────────────────────────

# AnimFlyBallUp (battle_anim_flying.c:458, step :467). args: 0/1 spawn offset,
# 2 hold frames before launch, 3 acceleration in 8.8 fixed point.
#
# The ball hangs still for `hold` frames, then ACCELERATES upward: the
# velocity accumulator gains `accel` every frame and the sprite rises by the
# accumulator's whole-pixel part, so travel is quadratic rather than linear.
#
# It also hides the attacker and never shows it again -- the paired reveal
# belongs to the script's later `AnimFlyBallAttack`/reappear step. Routed
# through the tracked setter so a run that ends between the two cannot leave
# the Pokemon invisible.
static func _fly_ball_up(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var start := _positioned_centre(vm, AnimStage.ANIM_ATTACKER, vm.args[0],
			vm.args[1], scale)
	node.centre = start
	vm.set_battler_visible_tracked(AnimStage.ANIM_ATTACKER, false)

	var hold: int = maxi(0, vm.args[2])
	var accel: int = vm.args[3]
	var st := {"hold": hold, "vel": 0, "y": 0.0, "t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["t"] = int(st["t"]) + 1
		if int(st["hold"]) > 0:
			st["hold"] = int(st["hold"]) - 1
		else:
			st["vel"] = int(st["vel"]) + accel
			st["y"] = float(st["y"]) - float(int(st["vel"]) >> 8) * scale
			node.centre = start + Vector2(0.0, float(st["y"]))
		# Upstream frees the sprite once it clears the top of the screen.
		if node.centre.y < -32.0 * scale or int(st["t"]) >= _ANIM_END_CAP:
			node.finish()
			return true
		return false)


# ── Electric ──────────────────────────────────────────────────────────────

# AnimSparkElectricity (battle_anim_electric.c:646). args: 0 angle index
# (256 steps), 1 radius, 2 rotation index, 3 lifetime, 4 battler, 5 coord
# variant, 6 flags.
#
# Places a spark on a ring around the chosen battler -- note x uses sine and
# y uses COSINE of the same index, so index 0 sits directly below the centre
# rather than to its right -- rotates it to a fixed angle, and destroys it
# after a fixed lifetime. It never moves.
#
# Two disclosed no-ops: arg 5 selects between two GBA coordinate conventions
# that both resolve to this stage's sprite centre, and arg 6 bit 0 bumps the
# sprite's BG priority, which has no per-sprite equivalent here.
static func _spark_electricity(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var centre := _battler_centre(vm, vm.args[4])
	var radius: float = float(vm.args[1])
	node.centre = centre + Vector2(
			_gba_sin(float(vm.args[0]), radius),
			_gba_cos(float(vm.args[0]), radius)) * scale
	node.rotation = float(vm.args[2]) * TAU / _SIN_STEPS

	var life: int = maxi(1, vm.args[3])
	var st := {"t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) >= life:
			node.finish()
			return true
		return false)


# The 16 spawn offsets particles converge from, in fixed order
# (sElectricChargingParticleCoordOffsets, battle_anim_electric.c:226).
const _CHARGING_PARTICLE_OFFSETS := [
	Vector2(58, -60), Vector2(-56, -36), Vector2(8, -56), Vector2(-16, 56),
	Vector2(58, -10), Vector2(-58, 10), Vector2(48, -18), Vector2(-8, 56),
	Vector2(16, -56), Vector2(-58, -42), Vector2(58, 30), Vector2(-48, 40),
	Vector2(12, -48), Vector2(48, -12), Vector2(-56, 18), Vector2(48, 48),
]


# AnimTask_ElectricChargingParticles (battle_anim_electric.c:949, step :988).
# args: 0 battler, 1 total particles, 2 frames between spawns, 3 spawns per
# speed-up.
#
# Particles spawn one at a time from the fixed 16-entry offset ring above and
# converge on the battler. The travel time SHORTENS as the effect runs --
# `40 - tier*5` frames, with the tier rising every `arg3` spawns and capped
# at 6 -- so the charge visibly accelerates rather than being a steady
# stream. The task only ends once the last particle has landed, not when the
# last one spawns, which is what makes it safe to wait on.
static func _electric_charging_particles(vm: AnimScriptVM,
		_ctx: Dictionary) -> void:
	var layer: Control = null
	if vm.stage != null and vm.stage.has_method("layer"):
		layer = vm.stage.layer()
	if layer == null:
		return
	var scale := _scale(vm)
	var centre := _battler_centre(vm, vm.args[0])
	var remaining: int = maxi(0, vm.args[1])
	var interval: int = maxi(0, vm.args[2])
	var per_tier: int = maxi(1, vm.args[3])
	const TMPL := "gElectricChargingParticlesSpriteTemplate"

	var st := {
		"timer": 0, "left": remaining, "idx": 0, "tier": 0, "since": 0,
		"live": [], "t": 0,
	}
	vm.add_stepper(func() -> bool:
		st["t"] = int(st["t"]) + 1
		# Advance every particle already in flight.
		var alive: Array = []
		for entry in (st["live"] as Array):
			var e: Dictionary = entry
			var p: AnimSprite = e["node"]
			if not is_instance_valid(p):
				continue
			e["age"] = int(e["age"]) + 1
			var dur: int = int(e["dur"])
			if int(e["age"]) >= dur:
				p.finish()
				continue
			p.centre = (e["from"] as Vector2).lerp(centre,
					float(e["age"]) / float(dur))
			p.advance_frame()
			alive.append(e)
		st["live"] = alive

		if int(st["left"]) > 0:
			st["timer"] = int(st["timer"]) + 1
			if int(st["timer"]) > interval:
				st["timer"] = 0
				var idx: int = int(st["idx"])
				var from: Vector2 = centre \
						+ (_CHARGING_PARTICLE_OFFSETS[idx] as Vector2) * scale
				var p := _spawn_template_sprite(vm, layer, TMPL, from)
				if p != null:
					(st["live"] as Array).append({
						"node": p, "from": from, "age": 0,
						"dur": maxi(1, 40 - int(st["tier"]) * 5),
					})
				st["idx"] = (idx + 1) % _CHARGING_PARTICLE_OFFSETS.size()
				st["since"] = int(st["since"]) + 1
				if int(st["since"]) >= per_tier:
					st["since"] = 0
					if int(st["tier"]) <= 5:
						st["tier"] = int(st["tier"]) + 1
				st["left"] = int(st["left"]) - 1
			return false
		# Ends only once the field is clear, not when spawning stops.
		if (st["live"] as Array).is_empty():
			return true
		return int(st["t"]) >= _ANIM_END_CAP)


# AnimGrowingShockWaveOrb (battle_anim_electric.c:1334). No args -- it sits on
# the attacker and plays affine anim 2 of gAffineAnims_GrowingElectricOrb
# (:308), which is a 60-frame contract-then-expand: the affine parameter runs
# 0x10 -> 0x100 over 30 frames and back over 30. GBA affine scale is INVERTED
# (256 = identity, SMALLER = BIGGER), so the orb starts large, draws in to
# native size, and blows back out -- the charge-and-release read the move's
# own name describes.
#
# DISCLOSED: 0x10 is a 16x magnification. That is what the table says, and it
# is reproduced rather than invented down, but this project draws at 4x on a
# 1024px canvas where source drew at 1x on 240px -- the same carries-badly
# risk M36E3's Sun ray hit at a much milder 3.2x. Most likely thing in this
# batch to read wrong on screen; a look-call, not a correctness gap.
const _SHOCKWAVE_ORB_PARAM_START := 0x10
const _SHOCKWAVE_ORB_PARAM_STEP := 0x8
const _SHOCKWAVE_ORB_PHASE_FRAMES := 30

static func _growing_shock_wave_orb(vm: AnimScriptVM, ctx: Dictionary) -> void:
	_shock_wave_orb_on(vm, ctx, AnimStage.ANIM_ATTACKER)


# AnimGrowingShockWaveOrbOnTarget (battle_anim_new.c:6467) is byte-identical to
# AnimGrowingShockWaveOrb apart from which battler it sits on -- the SIXTH
# alias found at Step 0, and the third against work from an earlier batch.
static func _growing_shock_wave_orb_on_target(vm: AnimScriptVM,
		ctx: Dictionary) -> void:
	_shock_wave_orb_on(vm, ctx, AnimStage.ANIM_TARGET)


static func _shock_wave_orb_on(vm: AnimScriptVM, ctx: Dictionary,
		battler: int) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	node.centre = _battler_centre(vm, battler)
	var st := {"t": 0, "param": _SHOCKWAVE_ORB_PARAM_START}
	node.scale = Vector2.ONE * (256.0 / float(_SHOCKWAVE_ORB_PARAM_START))

	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var t: int = int(st["t"]) + 1
		st["t"] = t
		var step := _SHOCKWAVE_ORB_PARAM_STEP
		if t > _SHOCKWAVE_ORB_PHASE_FRAMES:
			step = -step
		st["param"] = maxi(1, int(st["param"]) + step)
		node.scale = Vector2.ONE * (256.0 / float(st["param"]))
		if t >= _SHOCKWAVE_ORB_PHASE_FRAMES * 2:
			node.finish()
			return true
		return false)


# ── Gust palette ──────────────────────────────────────────────────────────

# AnimTask_AnimateGustTornadoPalette (battle_anim_flying.c:361, step :369).
# args: 0 frames between rotations, 1 total lifetime in frames.
#
# Upstream rotates 8 entries of the ANIM_TAG_GUST OBJ palette by one slot
# every `arg0` frames, which is what makes the tornado appear to spin without
# any sprite motion at all.
#
# STRUCTURED NO-OP, and this one is a real capability gap rather than a
# choice. M36E3 built palette remapping for BACKGROUNDS, driven by the
# per-background `palette_colors` the extractor emits; there is no equivalent
# for sprites, because the pulled sheets are composited PNGs and the index a
# pixel came from is not recoverable from them. Faking it with a hue shift
# would be inventing motion the reference does not describe.
#
# The frame COST is reproduced exactly, which is the part that matters for
# script pacing -- a `waitforvisualfinish` after this task must still wait
# the full lifetime. The tornado's own frame sequence supplies the bulk of
# the visible motion regardless; what is missing is the palette spin on top.
static func _animate_gust_tornado_palette(vm: AnimScriptVM,
		_ctx: Dictionary) -> void:
	var life: int = maxi(1, vm.args[1])
	var st := {"t": 0}
	vm.add_stepper(func() -> bool:
		st["t"] = int(st["t"]) + 1
		return int(st["t"]) >= life)


# ── Cross impact ──────────────────────────────────────────────────────────

# AnimCrossImpact (battle_anim_normal.c:1172). args: 0/1 offset, 2 battler,
# 3 duration. Positioned and then held perfectly still for `duration` frames
# before being freed -- no motion, no scaling, no flicker. It is a timing
# element as much as a visual one, which is why the frame count matters.
static func _cross_impact(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	node.centre = _positioned_centre(vm, vm.args[2], vm.args[0], vm.args[1],
			scale)
	var life: int = maxi(1, vm.args[3])
	var st := {"t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) >= life:
			node.finish()
			return true
		return false)


# ── [M36D batch 9] yield-ordered picks ────────────────────────────────────
#
# Decision 5's phase order (iconic -> remaining Gen 1-3 -> the rest) was
# AMENDED by Rob after batch 8 measured what the two remaining tiers actually
# cost: Tier 2's best picks were worth +12 moves against Tier 3's +33, at the
# same completion percentage. Ordering is now by measured yield rather than by
# generation, which lands on the cross-tier list -- 16 behaviors completing
# 70 moves, 4.4 each, roughly double batch 8.
#
# Step 0 collapsed a good deal of it before any code was written:
#   * `AnimRockBlastRock` is `TranslateAnimSpriteToTargetMonLocation` plus a
#     side-mirrored flip -- M36C's `_translate_to_target` already IS that.
#   * `AnimEllipticalGust` and `AnimEllipticalGustCentered` share ONE step
#     function and differ only in where they start. One implementation.
#   * `AnimGustToTarget`, `SpriteCB_GrowingSuperpower` and `AnimFlyBallAttack`
#     are all plain linear translations -> `_linear_travel`.
#   * `AnimDragonRageFirePlume` is position-then-play-out -> the existing
#     `_play_until_anim_ends`.


# ── Fly's second half ─────────────────────────────────────────────────────

# AnimFlyBallAttack (battle_anim_flying.c:483, step :508). args: 0 travel
# frames, 1 the visibility value to leave the attacker at.
#
# THIS IS THE PAIRED REVEAL FOR BATCH 8's `AnimFlyBallUp`. Its teardown does
# `gSprites[attacker].invisible = sprite->data[5]` -- the attacker's
# visibility is restored FROM ARG 1 as the ball leaves the screen, which is
# what actually brings the Pokemon back after Fly's charge turn. Batch 8
# shipped the hiding half relying on the VM's restore net; this closes the
# pair properly, and the suite asserts the reveal happens through the real
# script step rather than the net.
#
# The ball enters from off-screen on the side the attacker is NOT on and
# flies to the target, so a player-side Fly comes in from the left.
static func _fly_ball_attack(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var layer_w := 1024.0
	if vm.stage != null and vm.stage.has_method("layer"):
		var l: Control = vm.stage.layer()
		if l != null:
			layer_w = l.size.x
	var from_left := _is_player_side(vm)
	var start := Vector2(-32.0 * scale if from_left else layer_w + 32.0 * scale,
			-32.0 * scale)
	if not from_left:
		node.scale = Vector2(-absf(node.scale.x), node.scale.y)
	node.centre = start
	var dest := _battler_centre(vm, AnimStage.ANIM_TARGET)
	var frames: int = maxi(1, vm.args[0])
	var leave_hidden: bool = vm.args[1] != 0

	var st := {"t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var t: int = int(st["t"]) + 1
		st["t"] = t
		node.centre = start.lerp(dest, float(t) / float(frames))
		if t < frames:
			return false
		# The reveal is the real payload: upstream assigns arg 1 straight into
		# the attacker's `invisible`, so arg 1 = 0 brings the mon back.
		vm.set_battler_visible_tracked(AnimStage.ANIM_ATTACKER,
				not leave_hidden)
		node.finish()
		return true)


# ── Horn ──────────────────────────────────────────────────────────────────

# AnimHornHit (battle_anim_effects_1.c:6414, step :6463). args: 0/1 offset
# from the target, 2 duration (clamped 2..0x7F).
#
# A straight sweep in 7-bit fixed point that starts 40px to one side and 20px
# off vertically, travelling toward the target -- both offsets mirrored by
# side, with the opponent-side case also flipping the sprite on both axes.
#
# The quirk worth pinning: on the SECOND-TO-LAST frame it SNAPS back to its
# recorded origin (`if (--data[1] == 1) { x = data[6]; y = data[7]; }`) and
# only then dies. So the horn does not simply arrive -- it jumps to the
# target's exact position for one frame at the end. Easy to miss, and a port
# that just interpolates to the destination looks close but never lands.
static func _horn_hit(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var duration: int = clampi(vm.args[2], 2, 0x7F)
	var origin := _positioned_centre(vm, AnimStage.ANIM_TARGET, vm.args[0],
			vm.args[1], scale)
	# Player-side: start left and below, sweep right/up. Opponent: mirrored.
	var player := _is_player_side(vm)
	var offset := Vector2(-40.0, 20.0) if player else Vector2(40.0, -20.0)
	var start := origin + offset * scale
	# 0x1400 / duration per frame in 7-bit fixed point, i.e. it covers the
	# 40/20 px gap in exactly `duration` frames.
	var per_frame := (origin - start) / float(duration)
	if not player:
		node.scale = Vector2(-absf(node.scale.x), -absf(node.scale.y))
	node.centre = start

	var st := {"left": duration, "pos": start}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["pos"] = (st["pos"] as Vector2) + per_frame
		node.centre = st["pos"]
		st["left"] = int(st["left"]) - 1
		if int(st["left"]) == 1:
			node.centre = origin  # the snap-back, one frame before death
			return false
		if int(st["left"]) <= 0:
			node.finish()
			return true
		return false)


# ── Rings and rocks ───────────────────────────────────────────────────────

# AnimHyperVoiceRing (battle_anim_effects_2.c:2540). args: 0/1 start offset,
# 3/4 destination offset, 5 swap the two battlers, 6 coord variant.
#
# Travels from one battler to the other, with arg 5 deciding which way round.
# The x offsets are applied with the SIGN of the battler's own side at each
# end -- start offset added on the opponent's side and subtracted on the
# player's, destination the reverse -- so the ring always widens away from
# its source rather than drifting in a fixed screen direction.
#
# Upstream also computes a subpriority from the partner sprites' draw order
# and averages the destination across both targets in doubles; the ordering
# has no per-sprite equivalent here and is a disclosed no-op.
static func _hyper_voice_ring(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var swap: bool = vm.args[5] != 0
	var from_b := AnimStage.ANIM_TARGET if swap else AnimStage.ANIM_ATTACKER
	var to_b := AnimStage.ANIM_ATTACKER if swap else AnimStage.ANIM_TARGET
	var from_player := _battler_is_player_side(vm, from_b)
	var to_player := _battler_is_player_side(vm, to_b)

	var start := _battler_centre(vm, from_b) + Vector2(
			float(vm.args[0]) * (-1.0 if from_player else 1.0),
			float(vm.args[1])) * scale
	var dest := _battler_centre(vm, to_b) + Vector2(
			float(vm.args[3]) * (-1.0 if to_player else 1.0),
			float(vm.args[4])) * scale
	node.centre = start
	# data[0] is seeded from arg 0, not a dedicated duration arg -- an
	# upstream quirk, reproduced with a floor so a zero offset still moves.
	_linear_travel(vm, node, start, dest, maxi(1, absi(vm.args[0])))


# AnimRockBlastRock (battle_anim_rock.c:931). No args of its own -- it is
# `TranslateAnimSpriteToTargetMonLocation` with a side-mirrored flip, and
# M36C already ported exactly that as `_translate_to_target`. Registered as a
# thin wrapper rather than a second copy, and the suite asserts the two share
# one implementation so nobody later "fixes" the duplication into a divergent
# pair.
static func _rock_blast_rock(vm: AnimScriptVM, ctx: Dictionary) -> void:
	_translate_to_target(vm, ctx)


# ── Gust family ───────────────────────────────────────────────────────────
#
# `AnimEllipticalGust` (battle_anim_flying.c:341) and
# `AnimEllipticalGustCentered` (:36 template, body just below it) share ONE
# step function (`AnimEllipticalGust_Step`, :350) and differ ONLY in where
# they are placed -- the centred variant averages both targets in doubles and
# is identical in singles. One implementation, two entry points.
#
# The orbit is an ELLIPSE, 32 across but only 8 down, starting at index 191
# and advancing 5 per frame for 71 frames -- so it circles roughly 1.4 times
# and is far wider than it is tall. A circular port would read as a bubble
# rather than a tornado.
const _GUST_ORBIT_FRAMES := 71
const _GUST_ORBIT_START := 191
const _GUST_ORBIT_STEP := 5

static func _elliptical_gust(vm: AnimScriptVM, ctx: Dictionary) -> void:
	_elliptical_gust_common(vm, ctx, false)


static func _elliptical_gust_centered(vm: AnimScriptVM, ctx: Dictionary) -> void:
	_elliptical_gust_common(vm, ctx, true)


static func _elliptical_gust_common(vm: AnimScriptVM, ctx: Dictionary,
		centred: bool) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var base := _battler_centre(vm, AnimStage.ANIM_TARGET)
	if centred:
		# In doubles the centred variant sits between both targets; in
		# singles the average of one battler is that battler, so this is
		# correctly a no-op there.
		var partner := _battler_node(vm, AnimStage.ANIM_DEF_PARTNER)
		if partner != null:
			base = (base + _battler_centre(vm, AnimStage.ANIM_DEF_PARTNER)) * 0.5
	base += Vector2(0.0, 20.0) * scale
	node.centre = base

	var st := {"t": 0, "idx": float(_GUST_ORBIT_START)}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		node.centre = base + Vector2(
				_gba_sin(float(st["idx"]), 32.0),
				_gba_cos(float(st["idx"]), 8.0)) * scale
		st["idx"] = fmod(float(st["idx"]) + float(_GUST_ORBIT_STEP), 256.0)
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) >= _GUST_ORBIT_FRAMES:
			node.finish()
			return true
		return false)


# AnimGustToTarget (battle_anim_flying.c:396). args: 2/3 destination offset,
# 4 duration. A plain attacker-to-target linear translation with the x offset
# mirrored for an opponent-side attacker -- the canonical `_linear_travel`
# shape, same as batch 6's ice-beam particle.
static func _gust_to_target(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var start := _battler_centre(vm, AnimStage.ANIM_ATTACKER)
	var dx := float(vm.args[2]) * (1.0 if _is_player_side(vm) else -1.0)
	var dest := _battler_centre(vm, AnimStage.ANIM_TARGET) \
			+ Vector2(dx, float(vm.args[3])) * scale
	node.centre = start
	_linear_travel(vm, node, start, dest, maxi(1, vm.args[4]))


# ── Fire ──────────────────────────────────────────────────────────────────

# AnimFirePlume (battle_anim_fire.c:544, step `AnimLargeFlame_Step` :?).
# args: 0/1 spawn offset, 2 total lifetime, 3 frames of drift, 4 x drift per
# frame, 5 y drift per frame.
#
# Two independent counters, which is the detail a port flattens by accident:
# the flame DRIFTS for `arg3` frames but LIVES for `arg2`, so it coasts to a
# halt and then hangs there before dying. Collapsing them into one duration
# loses the hang.
static func _fire_plume(vm: AnimScriptVM, ctx: Dictionary) -> void:
	_fire_plume_common(vm, ctx, 1.0)


# AnimDragonRageFirePlume (battle_anim_dragon.c:443). args: 0 battler,
# 1/2 offset. Positioned and then simply played out until its own frame
# sequence ends -- no motion at all. Reuses `_play_until_anim_ends`.
static func _dragon_rage_fire_plume(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	node.centre = _positioned_centre(vm, vm.args[0], vm.args[1], vm.args[2],
			scale)
	_play_until_anim_ends(vm, node, _ANIM_END_CAP)


# ── Electric ──────────────────────────────────────────────────────────────

# AnimZapCannonSpark (battle_anim_electric.c:704, step :721). args: 2 wobble
# radius, 3 travel frames, 4 starting angle, 5 angle step, 6 tile offset.
#
# A linear attacker-to-target flight with a circular wobble laid ON TOP of it,
# plus a flicker: the sprite toggles visibility every time its angle index
# divides by 3. Dropping the flicker leaves a smooth spark that reads as the
# wrong move entirely -- Zap Cannon's spark is meant to stutter.
static func _zap_cannon_spark(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var start := _battler_centre(vm, AnimStage.ANIM_ATTACKER)
	var dest := _battler_centre(vm, AnimStage.ANIM_TARGET)
	var radius := float(vm.args[2])
	var frames: int = maxi(1, vm.args[3])
	var angle := float(vm.args[4])
	var angle_step := float(vm.args[5])
	node.centre = start

	var st := {"t": 0, "angle": angle}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var t: int = int(st["t"]) + 1
		st["t"] = t
		if t >= frames:
			node.finish()
			return true
		var base := start.lerp(dest, float(t) / float(frames))
		var a := float(st["angle"])
		node.centre = base + Vector2(_gba_sin(a, radius),
				_gba_cos(a, radius)) * scale
		a = fmod(a + angle_step, 256.0)
		st["angle"] = a
		# The stutter: upstream toggles `invisible` whenever the angle index
		# is a multiple of 3.
		if int(a) % 3 == 0:
			node.visible = not node.visible
		return false)


# SpriteCB_GrowingSuperpower (battle_anim_new.c). args: 0 direction (0 =
# attacker to target, else the reverse). A flat 16-frame linear translation
# between the two battlers, side-mirrored. No growth of its own despite the
# name -- the scaling lives in the template's affine anim, which the frame
# sequence plays out.
static func _growing_superpower(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var from_attacker: bool = vm.args[0] == 0
	var start := _battler_centre(vm,
			AnimStage.ANIM_ATTACKER if from_attacker else AnimStage.ANIM_TARGET)
	var dest := _battler_centre(vm,
			AnimStage.ANIM_TARGET if from_attacker else AnimStage.ANIM_ATTACKER)
	if not _is_player_side(vm):
		node.scale = Vector2(-absf(node.scale.x), node.scale.y)
	node.centre = start
	_linear_travel(vm, node, start, dest, 16)


# ── Hearts, ice, droplets ─────────────────────────────────────────────────

# AnimMagentaHeart (battle_anim_effects_2.c:3021). No positional args beyond
# the standard offset. Rises steadily while swaying: y accumulates -0x80 per
# frame in 8.8 fixed point (so exactly half a pixel a frame) and x is a
# sine of a phase advancing 7 per frame. Lives exactly 60 frames.
static func _magenta_heart(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var start := _positioned_centre(vm, AnimStage.ANIM_ATTACKER, vm.args[0],
			vm.args[1], scale)
	node.centre = start

	var st := {"t": 0, "phase": 0.0, "rise": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["rise"] = int(st["rise"]) - 0x80
		node.centre = start + Vector2(
				_gba_sin(float(st["phase"]), 8.0),
				float(int(st["rise"]) >> 8)) * scale
		st["phase"] = fmod(float(st["phase"]) + 7.0, 256.0)
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) >= 60:
			node.finish()
			return true
		return false)


# AnimIcePunchSwirlingParticle (battle_anim_ice.c:647) via
# `TranslateSpriteInGrowingCircle` (battle_anim_mons.c:381). args: 0 starting
# angle.
#
# Orbits with a radius that GROWS as it goes: the amplitude accumulates -512
# per frame in 8.8 fixed point on top of a base of 9, over 60 frames at 30
# angle-units a frame. Negative accumulation with a positive base means the
# radius passes through zero and back out -- the particle spirals inward,
# through the centre, and out the far side rather than simply expanding.
static func _ice_punch_swirling_particle(vm: AnimScriptVM,
		ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	# ⚠️ **THE TARGET, NOT THE ATTACKER.** Reported from play: "fire, thunder
	# and ice punch the particle effect hits its own pokemon instead of the
	# opponent." `TranslateSpriteInGrowingCircle` only writes `x2`/`y2` —
	# OFFSETS — so the base position is whatever `createsprite` chose, and
	# `Cmd_createsprite` places every sprite at
	# `GetBattlerSpriteCoord(gBattleAnimTarget, ...)` (battle_anim.c). This
	# behavior never repositions, so its circle is centred on the TARGET.
	# Fixes Fire Punch and Ice Punch together — one behavior serves both
	# `AnimFireSpiralInward` and `AnimIcePunchSwirlingParticle`, which are
	# byte-identical upstream.
	var centre := _battler_centre(vm, AnimStage.ANIM_TARGET)
	node.centre = centre

	var st := {"angle": float(vm.args[0]), "left": 60, "amp": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var radius := float(int(st["amp"]) >> 8) + 9.0
		node.centre = centre + Vector2(
				_gba_sin(float(st["angle"]), radius),
				_gba_cos(float(st["angle"]), radius)) * scale
		st["angle"] = fposmod(float(st["angle"]) + 30.0, 256.0)
		st["amp"] = int(st["amp"]) - 512
		st["left"] = int(st["left"]) - 1
		if int(st["left"]) <= 0:
			node.finish()
			return true
		return false)


# AnimSprayWaterDroplet (battle_anim_flying.c:1105, step :1119). args:
# 0 mirror horizontally, 1 spawn on the target rather than the attacker.
#
# Randomised launch: x speed is 736 +/- a 9-bit random, y speed 896 +/- a
# 7-bit one, both in 8.8 fixed point. Spawns 32px BELOW the battler's centre
# and arcs up and outward for exactly 31 frames.
#
# UPSTREAM BUG, reproduced as written: the step does
# `sprite->data[0] = sprite->data[0];` -- a self-assignment that clearly meant
# to decay the horizontal speed the way `data[1] -= 32` decays the vertical.
# It does nothing, so the droplet's sideways speed never falls off while its
# rise does, and the guard below it (`if (data[0] < 0) data[0] = 0;`) is
# unreachable. Ported faithfully: x is constant, y decelerates. Fixing it
# would change the arc's shape away from what the reference draws.
static func _spray_water_droplet(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var v1 := randi() & 0x1FF
	var v2 := randi() & 0x7F
	var vx := 736 + v1 if (v1 % 2) == 1 else 736 - v1
	var vy := 896 + v2 if (v2 % 2) == 1 else 896 - v2
	var mirrored: bool = vm.args[0] != 0
	var which := AnimStage.ANIM_TARGET if vm.args[1] != 0 \
			else AnimStage.ANIM_ATTACKER
	var start := _battler_centre(vm, which) + Vector2(0.0, 32.0) * scale
	if mirrored:
		node.scale = Vector2(-absf(node.scale.x), node.scale.y)
	node.centre = start

	var st := {"t": 0, "vy": vy, "pos": Vector2.ZERO}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var p: Vector2 = st["pos"]
		# x speed never decays (see the upstream self-assignment above).
		p.x += float(vx >> 8) * (-1.0 if mirrored else 1.0)
		p.y -= float(int(st["vy"]) >> 8)
		st["pos"] = p
		st["vy"] = int(st["vy"]) - 32
		node.centre = start + p * scale
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) >= 31:
			node.finish()
			return true
		return false)


# ── Metronome finger, Defense Curl ────────────────────────────────────────

# AnimMetronomeFinger (battle_anim_effects_1.c:7131, step :7147). args:
# 0 battler. Sits beside the mon's head, plays its wag out, holds 16 frames,
# then plays a second affine anim and goes. Reuses the same head-relative
# placement batch-era finger behaviors already established.
static func _metronome_finger(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	node.centre = _next_to_mon_head(vm, vm.args[0])
	var st := {"t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["t"] = int(st["t"]) + 1
		# 16-frame hold after the wag, then the closing anim plays out.
		if int(st["t"]) >= 16 + 16:
			node.finish()
			return true
		return false)


# AnimTask_DefenseCurlDeformMon (battle_anim_effects_3.c:2126) via
# `DefenseCurlDeformMonAffineAnimCmds` (:472). No args.
#
# Squashes the attacker: affine scale (-12, +20) per frame for 8 frames, then
# (+12, -20) for 8, looped twice -- 32 frames total. The two halves cancel
# EXACTLY, so it is self-restoring by construction rather than by a corrective
# final step, and the test asserts the mon's scale returns to precisely what
# it started at. GBA affine scale is INVERTED, so a NEGATIVE x delta widens
# the sprite while the positive y delta flattens it: the mon squashes down and
# out, which is the shape Defense Curl wants.
const _DEFENSE_CURL_HALF_FRAMES := 8
const _DEFENSE_CURL_LOOPS := 2

static func _defense_curl_deform_mon(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var node := _battler_node(vm, AnimStage.ANIM_ATTACKER)
	if node == null:
		return
	var base_scale := node.scale
	var base_pivot := node.pivot_offset
	node.pivot_offset = node.size * 0.5

	var st := {"t": 0, "px": 256, "py": 256}
	var total := _DEFENSE_CURL_HALF_FRAMES * 2 * _DEFENSE_CURL_LOOPS
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		var t: int = int(st["t"])
		# Which half of the current squash/unsquash cycle we are in.
		var out_leg := (t / _DEFENSE_CURL_HALF_FRAMES) % 2 == 0
		st["px"] = int(st["px"]) + (-12 if out_leg else 12)
		st["py"] = int(st["py"]) + (20 if out_leg else -20)
		node.scale = Vector2(
				base_scale.x * 256.0 / float(maxi(1, int(st["px"]))),
				base_scale.y * 256.0 / float(maxi(1, int(st["py"]))))
		st["t"] = t + 1
		if int(st["t"]) >= total:
			node.scale = base_scale
			node.pivot_offset = base_pivot
			return true
		return false)


# ── [M36D batch 10] the flattening tail ───────────────────────────────────
#
# The curve flattened here, exactly as batch 9's closing measurement warned:
# the 6s, 5s and 4s are gone and the best remaining pick is worth +3. 200
# moves still sit one behavior away, but each of those behaviors now serves
# ~2 moves rather than ~5.
#
# 11 of the 16 candidates ship here. FIVE ARE DEFERRED TO BATCH 11 rather
# than guessed at -- `AnimTask_Rollout`, `AnimTask_FlailMovement`,
# `AnimTask_SpiteTargetShadow`, `AnimTask_NightmareClone` and
# `AnimTask_ShrinkTargetCopy` each need a step function this pass did not
# read in full, and a half-read port is how a behavior ships looking right
# and being wrong. Worth 10 moves between them; they are not lost, just not
# guessed.


# AnimFireSpiralInward (battle_anim_fire.c:511) is BYTE-IDENTICAL to batch 9's
# AnimIcePunchSwirlingParticle: the same `TranslateSpriteInGrowingCircle`
# driver with the same four constants (duration 0x3C = 60, amplitude 9,
# angle step 0x1E = 30, amplitude delta 0xFE00 = -512). Registered against the
# one implementation, with the suite asserting they stay shared so nobody
# later "fixes" the duplication into a divergent pair.


# ── Screen flash ──────────────────────────────────────────────────────────

# AnimTask_Flash (battle_anim_utility_funcs.c:606, step :621). No args.
#
# Slams every battler palette to BLACK and the background to WHITE at once,
# holds 7 frames, then blends BOTH back over 16 steps at 2 frames each -- so
# roughly 39 frames total, of which the hold is the part a port drops by
# accident. The two halves fade in lockstep from one counter.
const _FLASH_HOLD_FRAMES := 7
const _FLASH_FADE_STEPS := 16
const _FLASH_FRAMES_PER_STEP := 2

static func _flash(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var battlers: Array[Control] = []
	for i in range(4):
		var n := _battler_node(vm, i)
		if n != null:
			battlers.append(n)
	var stage = vm.stage
	var has_fade: bool = stage != null and stage.has_method("set_fade")

	for n in battlers:
		_apply_blend_amount(n, Color.BLACK, 1.0)
	if has_fade:
		stage.set_fade(1.0)

	var st := {"hold": _FLASH_HOLD_FRAMES, "coeff": _FLASH_FADE_STEPS,
			"tick": 0}
	vm.add_stepper(func() -> bool:
		if int(st["hold"]) > 0:
			st["hold"] = int(st["hold"]) - 1
			return false
		st["tick"] = int(st["tick"]) + 1
		if int(st["tick"]) < _FLASH_FRAMES_PER_STEP:
			return false
		st["tick"] = 0
		st["coeff"] = int(st["coeff"]) - 1
		var amt := float(st["coeff"]) / float(_FLASH_FADE_STEPS)
		for n in battlers:
			if is_instance_valid(n):
				_apply_blend_amount(n, Color.BLACK, amt)
		if has_fade:
			stage.set_fade(amt)
		if int(st["coeff"]) <= 0:
			for n in battlers:
				if is_instance_valid(n):
					_clear_blend(n)
			if has_fade:
				stage.set_fade(0.0)
			return true
		return false)


# ── Orbits and drifts ─────────────────────────────────────────────────────

# AnimReversalOrb (battle_anim_effects_3.c:3328, step :3338). args:
# 0 half-duration, 1 starting angle.
#
# Orbits the attacker on an ellipse that GROWS and then SHRINKS back, so the
# whole thing is symmetric and self-closing: the x radius gains 0x400 per
# frame and the y radius only 0x100, i.e. it widens FOUR TIMES as fast as it
# heightens, for `arg0` frames, then unwinds at the same rates. The angle
# advances 9 per frame throughout.
static func _reversal_orb(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var centre := _battler_centre(vm, AnimStage.ANIM_ATTACKER)
	node.centre = centre
	var half: int = maxi(1, vm.args[0])

	var st := {"angle": float(vm.args[1]), "rx": 0, "ry": 0, "t": 0,
			"out": true}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		node.centre = centre + Vector2(
				_gba_sin(float(st["angle"]), float(int(st["rx"]) >> 8)),
				_gba_cos(float(st["angle"]), float(int(st["ry"]) >> 8))) * scale
		st["angle"] = fmod(float(st["angle"]) + 9.0, 256.0)
		var dir := 1 if bool(st["out"]) else -1
		st["rx"] = int(st["rx"]) + 0x400 * dir
		st["ry"] = int(st["ry"]) + 0x100 * dir
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) >= half:
			st["t"] = 0
			if bool(st["out"]):
				st["out"] = false
				return false
			node.finish()
			return true
		return false)


# AnimBlackSmoke (battle_anim_effects_3.c:1256, step :1270). args: 0/1 spawn
# offset, 2 drift speed, 3 reverse the drift, 4 lifetime.
#
# Drifts sideways in 8.8 fixed point while FLICKERING EVERY SINGLE FRAME --
# the flicker is not a decoration, it is what makes the smoke read as smoke
# rather than a sliding sprite. Lives exactly `arg4` frames.
static func _black_smoke(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var start := _positioned_centre(vm, AnimStage.ANIM_ATTACKER, vm.args[0],
			vm.args[1], scale)
	node.centre = start
	var speed: int = -vm.args[2] if vm.args[3] != 0 else vm.args[2]
	var life: int = maxi(1, vm.args[4])

	var st := {"acc": 0, "left": life}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		node.centre = start + Vector2(float(int(st["acc"]) >> 8), 0.0) * scale
		st["acc"] = int(st["acc"]) + speed
		node.visible = not node.visible   # every frame, not every Nth
		st["left"] = int(st["left"]) - 1
		if int(st["left"]) <= 0:
			node.finish()
			return true
		return false)


# SpriteCB_SurroundingRing (battle_anim_new.c). No args. Starts 40px BELOW the
# attacker's centre and rises 72px over 13 frames -- so it sweeps up THROUGH
# the mon rather than expanding around it, which is what the name suggests and
# is not what it does.
static func _surrounding_ring(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var start := _battler_centre(vm, AnimStage.ANIM_ATTACKER) \
			+ Vector2(0.0, 40.0) * scale
	node.centre = start
	_linear_travel(vm, node, start, start - Vector2(0.0, 72.0) * scale, 13)


# SpriteCB_FallingObject (battle_anim_new.c, step just below it). args:
# 0 x offset, 1 height to fall from, 2 fall speed, 3 which battler.
#
# Two genuinely separate phases: it FALLS at a constant speed until it reaches
# the target's level, and only then flickers -- 10 toggles, every frame -- and
# dies. Merging the two loses the landing beat entirely.
static func _falling_object(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var target := vm.args[3]
	var rest := _battler_centre(vm, target) \
			+ Vector2(float(vm.args[0]), 0.0) * scale
	var drop := float(vm.args[1]) * scale
	var speed := maxf(1.0, float(vm.args[2])) * scale
	node.centre = rest - Vector2(0.0, drop)

	var st := {"y": -drop, "phase": 0, "flicks": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		if int(st["phase"]) == 0:
			st["y"] = float(st["y"]) + speed
			if float(st["y"]) >= 0.0:
				st["y"] = 0.0
				st["phase"] = 1
			node.centre = rest + Vector2(0.0, float(st["y"]))
			return false
		node.visible = not node.visible
		st["flicks"] = int(st["flicks"]) + 1
		if int(st["flicks"]) >= 10:
			node.finish()
			return true
		return false)


# ── Pincers, marks, swipes ────────────────────────────────────────────────

# AnimGuillotinePincer (battle_anim_effects_2.c:1871, steps :1900+). args:
# 0 which pincer (0 = upper-right, else lower-left, which also selects the
# mirrored sprite anim).
#
# Three phases, and the middle one is the whole character of the move:
# converge on the target over 6 frames, then JITTER by +/-2px on both axes
# EVERY FRAME for 51 frames -- the pincer visibly grinding while it holds --
# then retreat. Porting only the converge produces a pincer that arrives and
# politely stops.
const _PINCER_CONVERGE_FRAMES := 6
const _PINCER_GRIND_FRAMES := 51

static func _guillotine_pincer(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var second: bool = vm.args[0] != 0
	var start_off := Vector2(-32.0, 32.0) if second else Vector2(32.0, -32.0)
	var end_off := Vector2(-16.0, 16.0) if second else Vector2(16.0, -16.0)
	var target := _battler_centre(vm, AnimStage.ANIM_TARGET)
	var start := target + start_off * scale
	var rest := target + end_off * scale
	node.centre = start

	var st := {"t": 0, "phase": 0, "flip": false}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var t: int = int(st["t"]) + 1
		st["t"] = t
		match int(st["phase"]):
			0:
				node.centre = start.lerp(rest,
						float(t) / float(_PINCER_CONVERGE_FRAMES))
				if t >= _PINCER_CONVERGE_FRAMES:
					st["t"] = 0; st["phase"] = 1
			1:
				# The grind: +/-2px on both axes, flipping every frame.
				st["flip"] = not bool(st["flip"])
				var j := Vector2(2.0, -2.0) * scale
				node.centre = rest + (j if bool(st["flip"]) else -j)
				if t >= _PINCER_GRIND_FRAMES:
					node.centre = rest
					st["t"] = 0; st["phase"] = 2
			_:
				node.centre = rest.lerp(start,
						float(t) / float(_PINCER_CONVERGE_FRAMES))
				if t >= _PINCER_CONVERGE_FRAMES:
					node.finish()
					return true
		return false)


# AnimQuestionMark (battle_anim_psychic.c:733, steps :751/:760). No args.
#
# Placed relative to the attacker's OWN SPRITE SIZE rather than a fixed
# offset -- half its width to the side, half its height up, mirrored by side
# and clamped so it never leaves the top of the screen. Then it plays out,
# spins down through an affine anim, and holds 18 frames before dying.
static func _question_mark(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var mon := _battler_node(vm, AnimStage.ANIM_ATTACKER)
	var half := Vector2(32.0, 32.0) * scale
	if mon != null:
		half = mon.size * 0.5
	var dx := half.x if _is_player_side(vm) else -half.x
	var pos := _battler_centre(vm, AnimStage.ANIM_ATTACKER) \
			+ Vector2(dx, -half.y)
	pos.y = maxf(pos.y, 16.0 * scale)   # upstream clamps to the screen top
	node.centre = pos
	# Play out, then the 18-frame hold before it goes.
	_play_until_anim_ends(vm, node, _ANIM_END_CAP)


# AnimFurySwipes (battle_anim_effects_2.c:3565). args: 0/1 offset, 2 which
# swipe variant. Positioned once and then simply played out -- no motion of
# its own; the whole effect is the frame sequence.
static func _fury_swipes(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	node.centre = _positioned_centre(vm, AnimStage.ANIM_TARGET, vm.args[0],
			vm.args[1], scale)
	_apply_anim_variant(node, ctx, vm.args[2])
	_play_until_anim_ends(vm, node, _ANIM_END_CAP)


# ── Spikes, flame ─────────────────────────────────────────────────────────

# AnimSpikes (battle_anim_effects_3.c:1503, steps :1522/:1538). args:
# 2/3 landing offset, 4 arc duration.
#
# Three phases the script depends on in sequence: an ARC from the attacker to
# the target's side (amplitude -50, so it lobs UP and over), a dead 30-frame
# WAIT where the spikes just sit there, and only then a 16-frame flicker-out
# that toggles on ODD frames only -- not every frame like Black Smoke's.
# Dropping the wait makes the hazard vanish the instant it lands.
const _SPIKES_WAIT_FRAMES := 30
const _SPIKES_FLICKER_FRAMES := 16

static func _spikes(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var start := _battler_centre(vm, AnimStage.ANIM_ATTACKER)
	var dx := float(vm.args[2]) * (1.0 if _is_player_side(vm) else -1.0)
	var dest := _battler_centre(vm, AnimStage.ANIM_TARGET) \
			+ Vector2(dx, float(vm.args[3])) * scale
	node.centre = start
	var arc_frames: int = maxi(1, vm.args[4])

	var st := {"t": 0, "phase": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var t: int = int(st["t"]) + 1
		st["t"] = t
		match int(st["phase"]):
			0:
				var f := float(t) / float(arc_frames)
				# amplitude -50 lobs the spikes up and over, not straight across
				node.centre = start.lerp(dest, f) \
						- Vector2(0.0, sin(f * PI) * 50.0 * scale)
				if t >= arc_frames:
					node.centre = dest
					st["t"] = 0; st["phase"] = 1
			1:
				if t >= _SPIKES_WAIT_FRAMES:   # the dead hold
					st["t"] = 0; st["phase"] = 2
			_:
				if (t & 1) == 1:               # odd frames only
					node.visible = not node.visible
				if t >= _SPIKES_FLICKER_FRAMES:
					node.finish()
					return true
		return false)


# AnimOutrageFlame (battle_anim_dragon.c:385) via
# `TranslateSpriteLinearAndFlicker` (battle_anim_mons.c:594). args: 0/1 spawn
# offset, 2 duration, 3/4 velocity in 8.8 fixed point, 5 flicker period.
#
# It STARTS INVISIBLE (`sprite->invisible = TRUE` at setup) and only appears
# when the flicker first toggles it on -- so the flame blinks into existence
# mid-flight rather than fading in. Both the position offset and BOTH velocity
# components are mirrored for an opponent-side attacker.
static func _outrage_flame(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var player := _is_player_side(vm)
	var sign_ := 1.0 if player else -1.0
	var start := _battler_centre(vm, AnimStage.ANIM_ATTACKER) + Vector2(
			float(vm.args[0]) * sign_, float(vm.args[1])) * scale
	var vel := Vector2(float(vm.args[3]), float(vm.args[4])) * sign_
	var life: int = maxi(1, vm.args[2])
	var period: int = vm.args[5]
	node.centre = start
	node.visible = false   # upstream sets invisible at setup

	var st := {"left": life, "acc": Vector2.ZERO}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var left: int = int(st["left"]) - 1
		st["left"] = left
		node.centre = start + (st["acc"] as Vector2) / 256.0 * scale
		st["acc"] = (st["acc"] as Vector2) + vel
		if period != 0 and left % period == 0:
			node.visible = not node.visible
		if left <= 0:
			node.finish()
			return true
		return false)


# ── [M36D batch 11] the deferred four ─────────────────────────────────────
#
# Batch 10 deferred five behaviors rather than guess at step functions it had
# not read. Four of them are ported here now that they have been. The fifth,
# `AnimTask_SpiteTargetShadow`, is DEFERRED AGAIN and for a better reason
# than last time -- see its own note at the bottom of this section.
#
# The headline finding is a NEW LEAK CLASS. `AnimTask_ShrinkTargetCopy` does
# not copy anything: it shrinks the REAL target and then waits for the script
# to signal `arg 7 == -1` before putting it back -- the same wait-for-signal
# shape as batch 7's Extreme Speed visibility pair, but on SCALE, which none
# of the VM's three existing restore nets covered. A script ending before its
# paired signal would have left a Pokemon permanently shrunk. Closed with a
# fourth net (`_restore_scaled_battlers`) and the `MonScale` helper above,
# built to the same meta-driven contract as `MonOffset` so the two read alike.


# AnimTask_ShrinkTargetCopy (battle_anim_effects_1.c:4058) via
# `AnimTask_DuplicateAndShrinkToPos_Step1/2` (:4082/:4104). args: 0 sideways
# drift per frame in 8.8 fixed point, 1 shrink duration in frames.
#
# The name is misleading twice over: there is no copy, and it does not shrink
# "to a position" so much as shrink IN PLACE while drifting sideways. The
# affine parameter climbs 16 per frame from 0x100, and GBA affine scale is
# INVERTED, so a rising parameter means the sprite gets SMALLER. The drift is
# mirrored for an opponent-side target.
#
# Then it HOLDS indefinitely until the script writes -1 into arg 7, and only
# then restores. That wait is the whole reason the new net exists.
static func _shrink_target_copy(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var node := _battler_node(vm, AnimStage.ANIM_TARGET)
	if node == null or not node.visible:
		return  # upstream destroys the task outright for an invisible target
	var scale := _scale(vm)
	var mon := MonOffset.new(node)
	var deform := MonScale.new(node)
	var drift: int = vm.args[0]
	if not _battler_is_player_side(vm, AnimStage.ANIM_TARGET):
		drift = -drift
	var frames: int = maxi(1, vm.args[1])

	var st := {"t": 0, "x": 0, "param": 256, "phase": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		if int(st["phase"]) == 0:
			st["x"] = int(st["x"]) + drift
			st["param"] = int(st["param"]) + 16
			mon.apply(Vector2(float(int(st["x"]) >> 8) * scale, 0.0))
			# Inverted affine: a rising parameter SHRINKS the sprite.
			deform.apply(Vector2.ONE * (256.0 / float(int(st["param"]))))
			st["t"] = int(st["t"]) + 1
			if int(st["t"]) >= frames:
				st["phase"] = 1
			return false
		# Hold until the script signals; the VM's net covers a run that ends
		# first, so this can wait honestly rather than timing out early.
		if vm.args[AnimScriptVM.ARG_RET] == -1:
			deform.restore()
			mon.restore()
			return true
		return false)


# AnimTask_FlailMovement (battle_anim_effects_3.c:3031, step :3049). args:
# 0 battler.
#
# A DECAYING rock, which is what makes it read as flailing rather than as a
# steady wobble: the rotation swings between +/- an amplitude that starts at
# 0x800 and loses 0x40 every 9 frames, floored at 16, for 32 decrements. The
# swing rate itself is constant at 0x200 per frame, so the oscillation gets
# visibly faster as the amplitude shrinks.
#
# The horizontal sway is not independent -- it is derived from the current
# rotation (`x2 = -(rot >> 6)`), so the mon leans into its own tilt rather
# than sliding separately.
const _FLAIL_SWING_RATE := 0x200
const _FLAIL_START_AMPLITUDE := 0x800
const _FLAIL_DECAY := 0x40
const _FLAIL_DECAY_COUNT := 32
const _FLAIL_FRAMES_PER_DECAY := 9

static func _flail_movement(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var node := _battler_node(vm, vm.args[0])
	if node == null:
		return
	var scale := _scale(vm)
	var mon := MonOffset.new(node)
	var deform := MonScale.new(node)
	node.pivot_offset = node.size * 0.5

	var st := {"rot": 0, "dir": 1, "tick": 0, "amp": _FLAIL_START_AMPLITUDE,
			"decays": _FLAIL_DECAY_COUNT, "done": false}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		if bool(st["done"]):
			deform.restore()
			mon.restore()
			return true
		var rot: int = int(st["rot"]) + _FLAIL_SWING_RATE * int(st["dir"])
		var amp: int = int(st["amp"])
		if rot >= amp:
			rot = amp
			st["dir"] = -1
		elif rot <= -amp:
			rot = -amp
			st["dir"] = 1
		st["rot"] = rot
		deform.apply(Vector2.ONE, float(rot) * TAU / 65536.0)
		# The sway is DERIVED from the tilt, not a separate motion.
		mon.apply(Vector2(-float(rot >> 6) * scale, 0.0))

		st["tick"] = int(st["tick"]) + 1
		if int(st["tick"]) > 8:
			st["tick"] = 0
			if int(st["decays"]) > 0:
				st["decays"] = int(st["decays"]) - 1
				st["amp"] = maxi(16, amp - _FLAIL_DECAY)
			else:
				st["done"] = true
		return false)


# AnimTask_NightmareClone (battle_anim_ghost.c:548, step :583). No args.
#
# A blended ghost of the target peels away and dissolves. Two things run at
# once and neither is the obvious one: the clone drifts on a raw 8.8 velocity
# (-144, 112) mirrored by side -- barely half a pixel a frame, so it creeps --
# while the GBA blend registers CROSS-FADE, the clone's own coefficient
# stepping 15 -> 0 and the background's 2 -> 16, each moving only on its own
# phase of a 4-frame cycle. It ends when BOTH have arrived AND at least 80
# frames have passed, so the drift always completes.
static func _nightmare_clone(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var node := _battler_node(vm, AnimStage.ANIM_TARGET)
	if node == null:
		return
	var layer: Control = null
	if vm.stage != null and vm.stage.has_method("layer"):
		layer = vm.stage.layer()
	if layer == null:
		return
	var clone := _clone_battler_visual(node, layer)
	if clone == null:
		return
	var scale := _scale(vm)
	var player := _battler_is_player_side(vm, AnimStage.ANIM_TARGET)
	var vel := Vector2(-144.0, 112.0) if player else Vector2(144.0, -112.0)
	var start := clone.position

	var st := {"t": 0, "acc": Vector2.ZERO, "eva": 15, "evb": 2}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(clone):
			return true
		var t: int = int(st["t"]) + 1
		st["t"] = t
		st["acc"] = (st["acc"] as Vector2) + vel
		clone.position = start + (st["acc"] as Vector2) / 256.0 * scale
		# Each coefficient moves on its own phase of the 4-frame cycle.
		var phase := t & 3
		if phase == 1 and int(st["eva"]) > 0:
			st["eva"] = int(st["eva"]) - 1
		if phase == 3 and int(st["evb"]) <= 15:
			st["evb"] = int(st["evb"]) + 1
		clone.modulate.a = float(st["eva"]) / 15.0
		if int(st["eva"]) == 0 and int(st["evb"]) >= 16 and t > 80:
			clone.queue_free()
			return true
		return t >= _ANIM_END_CAP * 2)


# AnimTask_Rollout (battle_anim_rock.c:666, step :760). No args of its own --
# it reads the ROLLOUT COUNTER, which this project already tracks from M16b's
# own Rollout/Ice Ball implementation.
#
# Four phases, and the wind-up is most of the character: the attacker pulls
# BACK away from the target for 10 frames, HOLDS for 20, returns over 10, and
# only then charges across. Speed scales with the counter -- `48 - counter*8`
# frames for the crossing, with the first turn special-cased to 32 -- so a
# fifth-turn Rollout visibly slams in faster than a first-turn one.
#
# Disclosed: the dirt sprites the charge spawns per interval are not created
# here; the attacker's own motion is the part every one of these moves shares
# and is what the frames are spent on.
static func _rollout(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var node := _battler_node(vm, AnimStage.ANIM_ATTACKER)
	if node == null:
		return
	var mon := MonOffset.new(node)
	var counter: int = maxi(1, vm.move_turn + 1)
	var cross: int = 32 if counter == 1 else maxi(8, 48 - counter * 8)
	var to_target := _battler_centre(vm, AnimStage.ANIM_TARGET) \
			- _battler_centre(vm, AnimStage.ANIM_ATTACKER)
	var per_frame := to_target / float(cross)

	var st := {"t": 0, "phase": 0, "off": Vector2.ZERO}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		var t: int = int(st["t"]) + 1
		st["t"] = t
		match int(st["phase"]):
			0:  # pull BACK, away from the target
				st["off"] = (st["off"] as Vector2) - per_frame
				mon.apply(st["off"])
				if t >= 10:
					st["t"] = 0; st["phase"] = 1
			1:  # the hold -- 20 dead frames, the wind-up's whole weight
				if t >= 20:
					st["t"] = 0; st["phase"] = 2
			2:  # return to the mark
				st["off"] = (st["off"] as Vector2) + per_frame
				mon.apply(st["off"])
				if t >= 10:
					mon.restore()
					st["off"] = Vector2.ZERO
					st["t"] = 0; st["phase"] = 3
			_:  # charge across, at a speed set by the rollout counter
				st["off"] = (st["off"] as Vector2) + per_frame
				mon.apply(st["off"])
				if t >= cross:
					mon.restore()
					return true
		return false)


# AnimTask_SpiteTargetShadow (battle_anim_ghost.c:621, steps :631/:700).
# No args.
#
# ⚠️ THIS OVERTURNS BATCH 10's AND BATCH 11's OWN DEFERRALS. Both declined it
# on the reading that it was mostly hardware work and that porting it would
# ship "the least characteristic third of the effect while claiming the
# behavior". Reading Step1 case 1 through Step2 in full shows that was wrong:
# the characteristic part is fully expressible, and the one piece that is not
# already has a disclosed precedent in this project.
#
# What it actually does:
#   1. Tints the REAL TARGET purple -- `BlendPalette(mon palette, 16, 10,
#      RGB(13,0,15))`, i.e. coefficient 10/16 toward a violet. Note this hits
#      the target's own palette, NOT the clone's.
#   2. Leaves an UN-TINTED clone of the target behind it, on a BG layer.
#   3. Wavers that layer horizontally over a 64px band starting at the
#      target's own y - 32 (`ScanlineEffect_InitWave`).
#   4. Pulses the blend between the two for 128 frames on a SINE envelope --
#      `gSineTable[t]/18`, with the two coefficients updating on alternate
#      frames, so the ghost swells in and back out exactly once.
#
# So the move reads as the target draining to a violet husk while a wavering
# echo of its former self shows through. Steps 1, 2 and 4 are all directly
# expressible here.
#
# DISCLOSED, with precedent: the waver is per-scanline upstream and is ported
# as a horizontal wobble of the whole clone on the same source-exact envelope
# -- exactly the approximation [M36D batch 7] already made and disclosed for
# AnimTask_DragonDanceWaver, which is the same per-scanline BG heat-haze
# mechanism. Approximating it a second time is consistent rather than novel.
const _SPITE_FRAMES := 128
const _SPITE_TINT_COEFF := 10.0 / 16.0
const _SPITE_WAVE_BAND := 64.0

static func _spite_target_shadow(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var node := _battler_node(vm, AnimStage.ANIM_TARGET)
	if node == null:
		return
	var layer: Control = null
	if vm.stage != null and vm.stage.has_method("layer"):
		layer = vm.stage.layer()
	if layer == null:
		return
	var clone := _clone_battler_visual(node, layer)
	if clone == null:
		return

	var scale := _scale(vm)
	# RGB(13,0,15) in the reference's own 5-bit channels.
	var violet := Color(13.0 / 31.0, 0.0, 15.0 / 31.0)
	_apply_blend_amount(node, violet, _SPITE_TINT_COEFF)
	var clone_home := clone.position
	clone.modulate.a = 0.0

	var st := {"t": 0, "eva": 0.0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		var t: int = int(st["t"]) + 1
		st["t"] = t
		# The sine envelope: gSineTable peaks at 256, /18 gives a 0..14 swing
		# over the 128 frames, so the echo swells in and back out once.
		var env := _gba_sin(float(t), 1.0) * 256.0 / 18.0
		if (t & 1) == 0:
			st["eva"] = env
		if is_instance_valid(clone):
			clone.modulate.a = clampf(float(st["eva"]) / 16.0, 0.0, 1.0)
			# The waver -- per-scanline upstream, a whole-clone wobble here.
			clone.position = clone_home + Vector2(
					sin(float(t) * 0.5) * 6.0 * scale, 0.0)
		if t >= _SPITE_FRAMES:
			if is_instance_valid(clone):
				clone.queue_free()
			_clear_blend(node)
			return true
		return false)


# ── [M36D batch 12] ───────────────────────────────────────────────────────
#
# 9 of 14 candidates. FIVE DEFERRED for unread step functions, per the rule
# batch 10 established and batch 11 vindicated: `AnimFallingFeather` (drives
# a packed `FeatherDanceData` bitfield struct), `AnimFlyingParticle`,
# `SpriteCB_Geyser`, `AnimTrickBag` and `AnimSuperpowerFireball`.
#
# Step 0 found TWO more near-aliases of already-ported work, which is now the
# third batch running to turn one up:
#   * `AnimGuardRing` IS batch 10's `SpriteCB_SurroundingRing` plus a
#     doubles-centre branch -- identical data[0]=13, y+40, y-72 travel.
#   * `AnimLargeFlame` IS batch 9's `AnimFirePlume` with EXACTLY ONE SIGN
#     INVERTED: the x drift. Everything else -- the offsets, both counters,
#     the step function itself -- is shared.


# AnimGuardRing (battle_anim_effects_2.c:3758) and batch 10's
# `SpriteCB_SurroundingRing` share one body: sit 40px below the attacker and
# rise 72px over 13 frames. GuardRing adds one branch -- in a doubles battle
# with a visible partner, and only when arg 0 is set, it centres between the
# pair instead. Registered as the general case with the plain variant
# delegating, so the two cannot drift apart.
static func _guard_ring(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var base := _battler_centre(vm, AnimStage.ANIM_ATTACKER)
	if vm.args[0] != 0:
		var partner := _battler_node(vm, AnimStage.ANIM_ATK_PARTNER)
		if partner != null:
			base = (base + _battler_centre(vm, AnimStage.ANIM_ATK_PARTNER)) * 0.5
	var start := base + Vector2(0.0, 40.0) * scale
	node.centre = start
	_linear_travel(vm, node, start, start - Vector2(0.0, 72.0) * scale, 13)


# AnimLargeFlame (battle_anim_fire.c:568) shares `AnimLargeFlame_Step` and
# every argument with batch 9's `AnimFirePlume` (:544) -- the two differ by a
# single inverted sign on the x drift, so the flames sweep opposite ways from
# the same spawn. Ported through one implementation with that sign as the only
# parameter, and the suite asserts they genuinely travel in opposite
# directions rather than being registered as the same thing by mistake.
static func _large_flame(vm: AnimScriptVM, ctx: Dictionary) -> void:
	_fire_plume_common(vm, ctx, -1.0)


static func _fire_plume_common(vm: AnimScriptVM, ctx: Dictionary,
		drift_sign: float) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var player := _is_player_side(vm)
	var side := 1.0 if player else -1.0
	var start := _battler_centre(vm, AnimStage.ANIM_ATTACKER) + Vector2(
			float(vm.args[0]) * side, float(vm.args[1])) * scale
	var drift := Vector2(float(vm.args[4]) * side * drift_sign,
			float(vm.args[5])) * scale
	var life: int = maxi(1, vm.args[2])
	var drift_frames: int = maxi(0, vm.args[3])
	node.centre = start

	var st := {"t": 0, "pos": start}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var t: int = int(st["t"]) + 1
		st["t"] = t
		if t < drift_frames:
			st["pos"] = (st["pos"] as Vector2) + drift
			node.centre = st["pos"]
		if t >= life:
			node.finish()
			return true
		return false)


# AnimTask_IsPowerOver99 (battle_anim_ground.c:728). A one-frame query that
# writes `move power > 99` into the return register, so a script can branch
# on whether the move is a heavy hitter. Reuses the same ARG_RET channel the
# other query tasks use.
static func _is_power_over_99(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	vm.args[AnimScriptVM.ARG_RET] = 1 if vm.move_power > 99 else 0


# AnimMudSportDirt (battle_anim_ground.c:226, rising step :245). args:
# 0 mode, 1/2 offsets.
#
# Two modes off one symbol. RISING (mode 0) spawns on the attacker and climbs
# 4px per frame while drifting sideways ONE pixel every OTHER frame -- the
# uneven rate is deliberate, and a smooth diagonal would read wrong. It dies
# when it clears the top of the screen, so its lifetime depends on where it
# started rather than on a counter.
#
# DISCLOSED: the FALLING branch's own step function was not read; its setup
# fully determines the start and end (`y = arg2`, `y2 = -arg2`, so it begins
# at screen top and falls to its resting y), and that is what is ported. The
# rising branch is the one every Mud Sport script actually spawns in bulk.
static func _mud_sport_dirt(vm: AnimScriptVM, ctx: Dictionary) -> void:
	if vm.args[0] == 0:
		_mud_sport_rising(vm, ctx, AnimStage.ANIM_ATTACKER, vm.args[1],
				vm.args[2])
		return
	# Falling: begins at the screen top and settles to its resting y.
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var rest := Vector2(float(vm.args[1]), float(vm.args[2])) * scale
	node.centre = rest - Vector2(0.0, float(vm.args[2])) * scale
	_linear_travel(vm, node, node.centre, rest, 20)


# The rising path, shared by AnimMudSportDirt's mode 0 and by batch 13's
# SpriteCB_Geyser, which hands straight over to it upstream.
static func _mud_sport_rising(vm: AnimScriptVM, ctx: Dictionary,
		battler: int, dx_arg: int, dy_arg: int) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var start := _positioned_centre(vm, battler, dx_arg, dy_arg, scale)
	node.centre = start
	var dx := 1.0 if dx_arg > 0 else -1.0
	var st := {"t": 0, "x": 0.0, "y": 0.0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["t"] = int(st["t"]) + 1
		# Sideways only every OTHER frame; upward every frame.
		if int(st["t"]) % 2 == 0:
			st["x"] = float(st["x"]) + dx
		st["y"] = float(st["y"]) - 4.0
		node.centre = start + Vector2(float(st["x"]), float(st["y"])) * scale
		if node.centre.y < -4.0 * scale or int(st["t"]) >= _ANIM_END_CAP:
			node.finish()
			return true
		return false)


# AnimParticleBurst (battle_anim_effects_2.c:3152). args: 0 x speed in 8.8
# fixed point, 1 vertical amplitude.
#
# Drifts steadily sideways while OSCILLATING vertically on a sine whose phase
# advances 3 per frame -- so it wanders rather than arcs. Past phase 100 it
# starts flickering on alternate frames, and dies at 120: a fade-out done
# entirely with visibility, no alpha involved.
static func _particle_burst(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var start := node.centre
	var speed: int = vm.args[0]
	var amp := float(vm.args[1])

	var st := {"acc": 0, "phase": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["acc"] = int(st["acc"]) + speed
		var phase: int = int(st["phase"])
		node.centre = start + Vector2(float(int(st["acc"]) >> 8),
				_gba_sin(float(phase), amp)) * scale
		phase = (phase + 3) & 0xFF
		st["phase"] = phase
		if phase > 100:
			node.visible = (phase % 2) == 0
		if phase > 120:
			node.finish()
			return true
		return false)


# AnimPoisonJabProjectile (battle_anim_effects_1.c:7286). args: 0/1 spawn
# offset from the target, 2 travel frames.
#
# Spawns offset from the target and ROTATES TO FACE IT before travelling --
# `ArcTan2Neg(dx, dy)` -- so the jab always points along its own flight path
# rather than at a fixed angle. Without that the sprite arrives sideways.
static func _poison_jab_projectile(vm: AnimScriptVM, ctx: Dictionary) -> void:
	# Same rotate-and-travel shape as batch 14's family, with a ZERO rest-angle
	# correction -- rerouted through the shared helper so the four cannot drift.
	_rotated_projectile(vm, ctx, vm.args[0], vm.args[1], 0, 0, vm.args[2],
			0, true)


# AnimMovePowerSwapGuardSwap (battle_anim_normal.c:289). args: 2 sprite anim
# variant, 3 direction (0 = attacker to target, else the reverse), 4 duration,
# 5 arc height. An ARC rather than a straight line, and the direction flag
# swaps both endpoints together -- which is what makes the pair of orbs read
# as a swap rather than two independent throws.
static func _power_swap_guard_swap(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	_apply_anim_variant(node, ctx, vm.args[2])
	var forward: bool = vm.args[3] == 0
	var from_b := AnimStage.ANIM_ATTACKER if forward else AnimStage.ANIM_TARGET
	var to_b := AnimStage.ANIM_TARGET if forward else AnimStage.ANIM_ATTACKER
	var start := _battler_centre(vm, from_b)
	var dest := _battler_centre(vm, to_b)
	node.centre = start
	_arc_travel(vm, node, start, dest, maxi(1, vm.args[4]), float(vm.args[5]))


# AnimBlockX (battle_anim_effects_3.c:5059, step :5079). No positional args.
#
# Drops onto the target from above at 10px per frame -- and the drop HEIGHT
# is side-dependent, 144px for a player-side target against 96px for an
# opponent-side one, so it falls noticeably longer on the player's side. Once
# it lands it holds rather than bouncing.
static func _block_x(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var rest := _battler_centre(vm, AnimStage.ANIM_TARGET)
	var drop := 144.0 if _battler_is_player_side(vm, AnimStage.ANIM_TARGET) \
			else 96.0
	node.centre = rest - Vector2(0.0, drop * scale)

	var st := {"y": -drop, "t": 0, "landed": false}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["t"] = int(st["t"]) + 1
		if not bool(st["landed"]):
			st["y"] = minf(float(st["y"]) + 10.0, 0.0)
			node.centre = rest + Vector2(0.0, float(st["y"]) * scale)
			if is_zero_approx(float(st["y"])):
				st["landed"] = true
			return false
		if int(st["t"]) >= _ANIM_END_CAP:
			node.finish()
			return true
		return false)


# AnimTask_BlendNonAttackerPalettes (battle_anim_utility_funcs.c:682). Blends
# every battler EXCEPT the attacker.
#
# Worth pinning: it SHIFTS ITS ARGUMENTS RIGHT BY ONE before delegating
# (`args[5..1] = args[4..0]`), because the shared blend entry point expects a
# selector in slot 0 that this task supplies itself. Reading the args in their
# unshifted positions would apply the wrong delay, coefficients and colour --
# a silent mis-blend rather than a crash.
static func _blend_non_attacker_palettes(vm: AnimScriptVM,
		_ctx: Dictionary) -> void:
	var nodes: Array[Control] = []
	for i in range(4):
		if i == AnimStage.ANIM_ATTACKER:
			continue
		var n := _battler_node(vm, i)
		if n != null:
			nodes.append(n)
	# The right-shift: this task's own args[0..4] are the blend's args[1..5].
	_run_blend_nodes(vm, nodes, vm.args[0], vm.args[1], vm.args[2], vm.args[3])


# ── [M36D batch 13] clearing batch 12's deferrals ─────────────────────────
#
# A deliberately small batch: four of batch 12's five deferrals, ported now
# that their step functions have been read. That leaves ONE genuinely hard
# item on the whole deferral list (`AnimFallingFeather`, below).
#
# The alias pattern held for a FOURTH consecutive batch, and this time both
# hits are against work from the two batches immediately prior:
#   * `SpriteCB_Geyser` reuses `AnimMudSportDirtRising` -- batch 12's own
#     rising path, ported one batch ago.
#   * `AnimSuperpowerFireball` is batch 9's `SpriteCB_GrowingSuperpower`:
#     the same 16-frame linear translation between the same endpoints, with
#     the side-mirror done by OAM flip instead of an affine anim.


# SpriteCB_Geyser (battle_anim_new.c:7332). args: 1/2 spawn offset.
# Positions on the attacker and then hands straight over to
# `AnimMudSportDirtRising` -- the identical rise-and-drift batch 12 ported.
# Registered against one implementation, asserted as shared.
static func _geyser(vm: AnimScriptVM, ctx: Dictionary) -> void:
	_mud_sport_rising(vm, ctx, AnimStage.ANIM_ATTACKER, vm.args[1], vm.args[2])


# AnimSuperpowerFireball (battle_anim_fight.c:924). args: 0 direction.
# A flat 16-frame linear translation between the two battlers, side-mirrored --
# structurally batch 9's `SpriteCB_GrowingSuperpower`, which is why both route
# through one body.
# AnimSuperpowerFireball (battle_anim_fight.c:924) is registered directly
# against `_growing_superpower`: the same flat 16-frame linear translation
# between the same two battler endpoints, side-mirrored. Upstream they differ
# only in HOW the mirror is applied -- an affine anim versus an OAM flip --
# which is not a behavioural difference here. Sharing the registration rather
# than wrapping it means the suite's identity assertion is meaningful.


# AnimFlyingParticle (battle_anim_effects_1.c:4811). args: 0 y anchor offset,
# 1 vertical amplitude, 2 starting phase, 3 horizontal speed, 4 phase step,
# 5 y-anchor mode, 6 which battler.
#
# Crosses the WHOLE SCREEN rather than travelling between battlers: it enters
# from off-screen on the side its battler is NOT on and exits the far edge,
# which is why it has no duration argument at all -- its lifetime is however
# long the crossing takes at `arg3` px/frame.
#
# The vertical wobble's phase is NOT accumulated. Upstream recomputes it as
# `(arg4 * elapsed) & 0xFF` from the frame counter each step, so a large
# `arg4` aliases into a fast flutter rather than a smooth wave. Ported as
# written.
static func _flying_particle(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var which := AnimStage.ANIM_TARGET if vm.args[6] != 0 \
			else AnimStage.ANIM_ATTACKER
	var layer_w := 1024.0
	if vm.stage != null and vm.stage.has_method("layer"):
		var l: Control = vm.stage.layer()
		if l != null:
			layer_w = l.size.x
	# Enters from the side the battler is NOT on.
	var from_left := not _battler_is_player_side(vm, which)
	var speed := float(vm.args[3]) * (1.0 if from_left else -1.0)
	var start_x := -16.0 * scale if from_left else layer_w + 16.0 * scale

	var y := float(vm.args[0]) * scale
	if vm.args[5] == 2:
		y = _battler_centre(vm, which).y + float(vm.args[0]) * scale
	elif vm.args[5] == 3:
		y = _battler_centre(vm, AnimStage.ANIM_TARGET).y \
				+ float(vm.args[0]) * scale
	var start := Vector2(start_x, y)
	node.centre = start

	var amp := float(vm.args[1])
	var phase_step := vm.args[4]
	var st := {"t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var t: int = int(st["t"])
		st["t"] = t + 1
		# Phase is RECOMPUTED from the frame count, not accumulated.
		var phase := float((phase_step * t) & 0xFF)
		node.centre = start + Vector2(speed * float(t),
				_gba_sin(phase, amp)) * scale
		# Dies on clearing the far edge, not on a counter.
		if from_left and node.centre.x > layer_w + 8.0 * scale:
			node.finish(); return true
		if not from_left and node.centre.x < -16.0 * scale:
			node.finish(); return true
		return int(st["t"]) >= _ANIM_END_CAP)


# The 11-row table AnimTrickBag walks: {angle step, frames, direction}. A
# direction of 127 is the end sentinel, not a step.
const _TRICK_BAG_TABLE := [
	[5, 24, 1], [0, 4, 0], [8, 16, -1], [0, 2, 0], [8, 16, 1], [0, 2, 0],
	[8, 16, 1], [0, 2, 0], [8, 16, 1], [0, 16, 0], [0, 0, 127],
]


# AnimTrickBag (battle_anim_effects_1.c:4444, steps :4474/:4502). args:
# 0 initial y, 1 starting wave offset.
#
# Three phases. It spawns at SCREEN CENTRE rather than on any battler, falls
# with real acceleration (`y += speed/10` while `speed += 3`) until it passes
# y=78, and then ORBITS an ellipse whose angle is driven by the table above --
# each row supplying a per-frame angle step, a frame count, and a direction,
# so the bag sweeps one way, pauses, reverses, then circles three more times.
#
# Note the axes are the reverse of the usual convention: x is COSINE with a
# radius of 60 and y is SINE with a radius of 20, giving a wide flat orbit.
static func _trick_bag(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var layer_w := 1024.0
	if vm.stage != null and vm.stage.has_method("layer"):
		var l: Control = vm.stage.layer()
		if l != null:
			layer_w = l.size.x
	var home := Vector2(layer_w * 0.5, float(vm.args[0]) * scale)
	var angle := float(vm.args[1])

	var st := {"phase": 0, "y": float(vm.args[0]), "speed": 20.0,
			"angle": angle, "row": 0, "held": 0}

	var place := func(a: float, y: float) -> void:
		node.centre = Vector2(home.x, y * scale) + Vector2(
				_gba_cos(a, 60.0), _gba_sin(a, 20.0)) * scale
	place.call(angle, float(vm.args[0]))

	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		if int(st["phase"]) == 0:
			# Accelerating fall -- speed grows by 3 while y advances by
			# speed/10, so it starts slow and drops away sharply.
			st["y"] = float(st["y"]) + float(st["speed"]) / 10.0
			st["speed"] = float(st["speed"]) + 3.0
			place.call(float(st["angle"]), float(st["y"]))
			if float(st["y"]) > 78.0:
				st["phase"] = 1
			return false
		var row: int = int(st["row"])
		if row >= _TRICK_BAG_TABLE.size():
			node.finish()
			return true
		var entry: Array = _TRICK_BAG_TABLE[row]
		if int(entry[2]) == 127:      # the end sentinel
			node.finish()
			return true
		if int(st["held"]) >= int(entry[1]):
			st["held"] = 0
			st["row"] = row + 1
			return false
		st["held"] = int(st["held"]) + 1
		st["angle"] = fposmod(float(st["angle"])
				+ float(int(entry[0]) * int(entry[2])), 256.0)
		place.call(float(st["angle"]), float(st["y"]))
		return false)


# AnimFallingFeather (battle_anim_flying.c:561) remains DEFERRED, and is now
# the only item left on the whole deferral list. Its step function is **247
# lines** of state machine driven by a packed `FeatherDanceData` bitfield
# struct aliased over the sprite's own data array -- a genuinely different
# order of complexity from anything else in this tier, and not something to
# port between two other behaviors. It wants its own pass.


# ── [M36D batch 14] the rotate-and-travel family ──────────────────────────
#
# 7 of 14 candidates. Seven deferred for unread step functions, listed at the
# bottom of this section.
#
# Step 0 found a FIFTH alias family, and this one is a genuine family rather
# than a pair: `AnimPsychoCut`, `AnimSonicBoomProjectile` and `AnimTealAlert`
# are all "spawn, rotate to FACE the destination, travel there in a straight
# line" -- and differ ONLY in a constant added to the computed angle
# (0xC000 / 0xF000 / 0x6000 in 1/65536 turns). Batch 12's
# `AnimPoisonJabProjectile` is the same shape with a zero offset, so it is
# rerouted through the shared helper here too.
#
# The offset exists because each sprite's ARTWORK points a different way at
# rest, so the constant is a per-sheet correction rather than a motion
# difference. Getting it wrong leaves the projectile flying sideways while
# still travelling the correct path -- a defect that looks like an art bug.


# The shared body. `rot_turns` is the reference's own constant in 1/65536
# turns; `from_target` spawns relative to the target instead of the attacker.
static func _rotated_projectile(vm: AnimScriptVM, ctx: Dictionary,
		off_x: int, off_y: int, dest_dx: int, dest_dy: int, frames: int,
		rot_turns: int, from_target: bool) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var origin := AnimStage.ANIM_TARGET if from_target \
			else AnimStage.ANIM_ATTACKER
	var start := _positioned_centre(vm, origin, off_x, off_y, scale)
	var mirror := 1.0 if _is_player_side(vm) else -1.0
	var dest := _battler_centre(vm, AnimStage.ANIM_TARGET) + Vector2(
			float(dest_dx) * mirror, float(dest_dy)) * scale
	node.centre = start
	# The rest-angle correction is UNCONDITIONAL -- upstream adds it even when
	# the facing term is zero, because it corrects the sprite sheet's own rest
	# orientation rather than the flight path. Skipping it on a zero delta
	# (spawn == destination, which TealAlert and PoisonJab genuinely do) leaves
	# those sheets unrotated. Caught by the family's own distinctness test.
	var delta := dest - start
	var facing := 0.0
	if delta.length_squared() > 0.0:
		facing = atan2(delta.y, delta.x)
	node.rotation = facing + float(rot_turns) * TAU / 65536.0
	_linear_travel(vm, node, start, dest, maxi(1, frames))


# AnimPsychoCut (battle_anim_psychic.c:435). args: 0/1 spawn offset,
# 2/3 destination offset, 4 duration. Rotation correction 0xC000.
static func _psycho_cut(vm: AnimScriptVM, ctx: Dictionary) -> void:
	_rotated_projectile(vm, ctx, vm.args[0], vm.args[1], vm.args[2],
			vm.args[3], vm.args[4], 0xC000, false)


# AnimSonicBoomProjectile (battle_anim_effects_2.c:1423). Same arguments and
# the same shape; correction 0xF000.
static func _sonic_boom_projectile(vm: AnimScriptVM, ctx: Dictionary) -> void:
	_rotated_projectile(vm, ctx, vm.args[0], vm.args[1], vm.args[2],
			vm.args[3], vm.args[4], 0xF000, false)


# AnimTealAlert (battle_anim_effects_3.c:1321). args: 0/1 spawn offset,
# 2 duration. Spawns relative to the TARGET rather than the attacker and
# converges on it; correction 0x6000.
static func _teal_alert(vm: AnimScriptVM, ctx: Dictionary) -> void:
	_rotated_projectile(vm, ctx, vm.args[0], vm.args[1], 0, 0, vm.args[2],
			0x6000, true)


# AnimRedHeartProjectile (battle_anim_effects_2.c:3127, step :3139). No
# duration argument -- it is a fixed 95 frames, which is unusually long for a
# projectile and is what gives Attract its drifting, unhurried feel. Travels
# to the target while swaying vertically on a sine of amplitude 14.
static func _red_heart_projectile(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var start := node.centre
	var dest := _battler_centre(vm, AnimStage.ANIM_TARGET)
	var st := {"t": 0, "phase": 0.0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var t: int = int(st["t"]) + 1
		st["t"] = t
		var base := start.lerp(dest, float(t) / 95.0)
		node.centre = base + Vector2(0.0,
				_gba_sin(float(st["phase"]), 14.0) * scale)
		st["phase"] = fmod(float(st["phase"]) + 4.0, 256.0)
		if t >= 95:
			node.finish()
			return true
		return false)


# AnimHitSplatRandom (battle_anim_normal.c:1138). args: 0 battler,
# 1 affine variant, or -1 to pick one at RANDOM.
#
# Scatters within a deliberately asymmetric box -- +/-24 horizontally but only
# +/-12 vertically, so repeated hits spread along the target rather than
# around it. Reuses M36C's own hit-splat machinery for the splat itself.
static func _hit_splat_random(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var variant: int = vm.args[1]
	if variant < 0:
		variant = randi() % 4
	var dx := (randi() % 48) - 24
	var dy := (randi() % 24) - 12
	_spawn_hit_splat(vm, ctx, dx, dy, vm.args[0], variant, 0)


# AnimSpiderWeb (battle_anim_bug.c:304, step :308). args: 0/1 offset,
# 2 centre between both targets.
#
# Three beats, and the middle one is easy to drop: it appears fully opaque,
# HOLDS for 20 dead frames, and only then fades -- one step of alpha every
# OTHER frame, so the 16-step fade takes 32 frames rather than 16. Total
# roughly 52 frames of which the first 20 are perfectly still.
static func _spider_web(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var base := _battler_centre(vm, AnimStage.ANIM_TARGET)
	if vm.args[2] != 0:
		var partner := _battler_node(vm, AnimStage.ANIM_DEF_PARTNER)
		if partner != null:
			base = (base + _battler_centre(vm, AnimStage.ANIM_DEF_PARTNER)) * 0.5
	var mirror := 1.0 if _is_player_side(vm) else -1.0
	node.centre = base + Vector2(float(vm.args[0]) * mirror,
			float(vm.args[1])) * scale

	var st := {"hold": 0, "tick": 0, "alpha": 16}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		if int(st["hold"]) < 20:
			st["hold"] = int(st["hold"]) + 1
			return false
		st["tick"] = int(st["tick"]) + 1
		if (int(st["tick"]) & 1) == 0:
			return false                      # one step every OTHER frame
		st["alpha"] = int(st["alpha"]) - 1
		node.modulate.a = float(st["alpha"]) / 16.0
		if int(st["alpha"]) <= 0:
			node.finish()
			return true
		return false)


# AnimTranslateWebThread (battle_anim_bug.c:230, step :257). args: 0/1 spawn
# offset, 2 travel SPEED (not duration), 3 sway amplitude, 4 target both.
#
# Note arg 2 is a speed rather than a frame count -- upstream calls
# `InitAnimLinearTranslationWithSpeed`, so the travel time depends on the
# distance and a port that treats it as a duration gets the pacing wrong in
# doubles, where the distance differs per slot. The thread also sways
# HORIZONTALLY as it flies, phase advancing 13 per frame.
static func _translate_web_thread(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var start := _positioned_centre(vm, AnimStage.ANIM_ATTACKER, vm.args[0],
			vm.args[1], scale)
	var dest := _battler_centre(vm, AnimStage.ANIM_TARGET)
	if vm.args[4] != 0:
		var partner := _battler_node(vm, AnimStage.ANIM_DEF_PARTNER)
		if partner != null:
			dest = (dest + _battler_centre(vm, AnimStage.ANIM_DEF_PARTNER)) * 0.5
	node.centre = start
	# Speed -> duration, so distance genuinely drives the travel time.
	var speed := maxf(1.0, float(vm.args[2]) * scale)
	var frames: int = maxi(1, int(start.distance_to(dest) / speed))
	var amp := float(vm.args[3])

	var st := {"t": 0, "phase": 0.0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var t: int = int(st["t"]) + 1
		st["t"] = t
		node.centre = start.lerp(dest, float(t) / float(frames)) \
				+ Vector2(_gba_sin(float(st["phase"]), amp) * scale, 0.0)
		st["phase"] = fmod(float(st["phase"]) + 13.0, 256.0)
		if t >= frames:
			node.finish()
			return true
		return false)


# DEFERRED from this batch, all for unread step functions except the first:
#   * `AnimFallingFeather` -- 247 lines of state machine over a packed
#     `FeatherDanceData` bitfield struct. Deferred three times now, and it
#     genuinely wants its own session rather than a slot in a batch.
#   * `AnimPetalDanceBigFlower` / `AnimPetalDanceSmallFlower` -- their setups
#     are near-identical (they differ only in whether the spawn respects side)
#     but the two step functions determine the sway and were not read.
#   * `AnimDiveBall`, `AnimDiveWaterSplash`, `AnimAcrobaticsSlashes`,
#     `SpriteCB_ToxicThreadWrap`.


# ── AnimFallingFeather — the last deferral, taken directly ────────────────
#
# Deferred by batches 12, 13 and 14 as "247 lines of state machine over a
# packed `FeatherDanceData` bitfield struct". That description was accurate
# and, it turns out, misleading: almost all of the length is the SAME
# twenty-line flip-and-swap block copy-pasted into four `switch` arms. Decoded,
# the mechanic is small and unusually well-designed, and three details are what
# make it read as a falling feather rather than a swinging pendulum:
#
#   1. IT ALTERNATES BETWEEN TWO SWAY AMPLITUDES. `unkC` is a two-byte array
#      and the index is a flag (`unk0_0b`) toggled at ONE specific quadrant
#      boundary. So consecutive swings are different widths and the descent
#      never settles into a clean sine.
#   2. ITS TILT IS DERIVED FROM ITS OWN HORIZONTAL OFFSET, not from time:
#      `sinIndex = (-x2 >> 1) + unkA`. The feather leans into its drift and
#      levels out at the extremes, which is what selling the "flat object
#      falling through air" reading depends on.
#   3. IT FLIPS AND CHANGES DRAW ORDER TOGETHER. At a quadrant boundary it
#      mirrors horizontally AND swaps its priority relative to the Pokemon --
#      the feather turning over and passing in front of or behind it.
#
# The four `switch` arms differ only in which neighbouring quadrant triggers a
# flip versus a bare pause, so they collapse into one table.
#
# The pause is worth noting because it looks longer than it is: `unk1` starts
# at 0 and the test is `unk1-- % 256 == 0`, which is true immediately, so a
# "pause" lasts a single frame. It is a beat between swings, not a hold.

# Per quadrant: [which previous quadrant triggers a FLIP, which triggers a bare
# PAUSE]. Quadrant 0 additionally toggles the amplitude selector on its pause.
const _FEATHER_QUADRANTS := [[1, 3], [0, 2], [3, 1], [2, 0]]

static func _falling_feather(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var which := AnimStage.ANIM_ATTACKER if (vm.args[7] & 0x100) != 0 \
			else AnimStage.ANIM_TARGET
	var mirror := -1.0 if _battler_is_player_side(vm, which) else 1.0

	# DISCLOSED: upstream reads BATTLER_COORD_ATTR_HEIGHT/WIDTH -- sprite
	# DIMENSIONS -- and uses them as screen coordinates here. That is almost
	# certainly an upstream mix-up (every neighbouring behavior uses the
	# _X_2/_Y_PIC_OFFSET coordinate queries), and it does not transfer to a
	# stage whose sprites are positioned by the scene rather than by GBA
	# pixel anchors. Spawned relative to the battler's centre instead.
	var centre := _battler_centre(vm, which)
	var start := centre + Vector2(float(vm.args[0]) * mirror,
			float(vm.args[1])) * scale
	var y_limit := centre.y + float(vm.args[6]) * scale

	var phase: int = vm.args[2] & 0xFF
	var rot_base: int = (vm.args[2] >> 8) & 0xFF
	var raw_delta: int = vm.args[3]
	var descending: bool = (raw_delta & 0x8000) != 0
	var phase_step: int = raw_delta & 0x7FFF
	var fall_speed: int = vm.args[4]
	# The two amplitudes, packed low byte / high byte into one argument.
	var amps := [float(vm.args[5] & 0xFF), float((vm.args[5] >> 8) & 0xFF)]

	var st := {
		"phase": phase, "quadrant": phase >> 6, "amp_sel": 0,
		"paused": false, "flip_pending": false, "flipped": false,
		"y": start.y, "front": false, "t": 0,
	}

	var apply := func() -> void:
		var amp: float = amps[int(st["amp_sel"])]
		var x2 := _gba_sin(float(st["phase"]), amp)
		node.centre = Vector2(start.x + x2 * scale, float(st["y"]))
		# Tilt follows the CURRENT horizontal offset, not elapsed time.
		var idx := (-x2 / 2.0) + float(rot_base)
		node.rotation = idx * TAU / _SIN_STEPS
		node.scale = Vector2(
				(-1.0 if bool(st["flipped"]) else 1.0) * absf(node.scale.x),
				node.scale.y)
	apply.call()

	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["t"] = int(st["t"]) + 1
		if bool(st["paused"]):
			# One frame, not a hold -- see the note above.
			st["paused"] = false
			return false

		var q: int = int(st["phase"]) / 64
		var rule: Array = _FEATHER_QUADRANTS[q]
		var prev: int = int(st["quadrant"])
		if prev == int(rule[0]):
			st["flip_pending"] = true
			st["paused"] = true
		elif prev == int(rule[1]):
			# Quadrant 0's bare pause is also where the amplitude alternates,
			# which is what keeps consecutive swings different widths.
			if q == 0:
				st["amp_sel"] = 1 - int(st["amp_sel"])
			st["paused"] = true
		elif bool(st["flip_pending"]):
			st["flipped"] = not bool(st["flipped"])
			# The flip and the draw-order swap happen together upstream.
			st["front"] = not bool(st["front"])
			node.z_index = 1 if bool(st["front"]) else -1
			st["flip_pending"] = false
		st["quadrant"] = q

		st["y"] = float(st["y"]) + float(fall_speed) / 256.0 * scale
		st["phase"] = posmod(int(st["phase"])
				+ (-phase_step if descending else phase_step), 256)
		apply.call()

		if float(st["y"]) >= y_limit or int(st["t"]) >= _ANIM_END_CAP * 2:
			node.finish()
			return true
		return false)


# ── [M36D batch 15] ───────────────────────────────────────────────────────
#
# 8 of 12 candidates; four deferred. Includes four of batch 14's own
# deferrals, now that their step functions have been read.
#
# `AnimGrowingShockWaveOrbOnTarget` is handled above, beside the behavior it
# aliases.


# AnimPetalDanceBigFlower (battle_anim_effects_1.c:3630, step :3646) and
# AnimPetalDanceSmallFlower (:3666, step :3682).
#
# Their SETUPS are near-identical -- both travel from the attacker down to
# `attacker y + targetY` -- which is what made them look like an alias pair.
# **Their steps are genuinely different, and that is the whole point of the
# move:** the big flowers sway WIDE (amplitude 32) with a vertical bob
# (`Cos(phase, -5)`, note the negative) and swap draw order in front of and
# behind the Pokemon on a half-cycle, while the small ones sway NARROW
# (amplitude 8), never bob, and instead FLIP horizontally inside two tiny
# 5-unit phase windows (59-63 and 187-191). Together that reads as heavy
# blossoms tumbling among light ones.
#
# Both advance phase by 5 per frame.
const _PETAL_PHASE_STEP := 5.0

static func _petal_dance_big_flower(vm: AnimScriptVM, ctx: Dictionary) -> void:
	_petal_dance(vm, ctx, true)


static func _petal_dance_small_flower(vm: AnimScriptVM, ctx: Dictionary) -> void:
	_petal_dance(vm, ctx, false)


static func _petal_dance(vm: AnimScriptVM, ctx: Dictionary, big: bool) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var start := _positioned_centre(vm, AnimStage.ANIM_ATTACKER, vm.args[0],
			vm.args[1], scale)
	var dest := Vector2(start.x,
			_battler_centre(vm, AnimStage.ANIM_ATTACKER).y
			+ float(vm.args[2]) * scale)
	var frames: int = maxi(1, vm.args[3])
	node.centre = start

	var st := {"t": 0, "phase": 64.0, "flipped": false, "front": false}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var t: int = int(st["t"]) + 1
		st["t"] = t
		var phase: float = float(st["phase"])
		var base := start.lerp(dest, float(t) / float(frames))
		if big:
			# Wide sway PLUS a vertical bob, and a draw-order swap on the
			# half-cycle -- the heavy blossom passing around the Pokemon.
			node.centre = base + Vector2(_gba_sin(phase, 32.0),
					_gba_cos(phase, -5.0)) * scale
			var in_front: bool = phase >= 64.0 and phase < 192.0
			if in_front != bool(st["front"]):
				st["front"] = in_front
				node.z_index = 1 if in_front else -1
		else:
			node.centre = base + Vector2(_gba_sin(phase, 8.0), 0.0) * scale
			# Two deliberately NARROW flip windows, not a half-cycle.
			if (phase >= 59.0 and phase < 64.0) \
					or (phase >= 187.0 and phase < 192.0):
				st["flipped"] = not bool(st["flipped"])
				node.scale = Vector2(
						(-1.0 if bool(st["flipped"]) else 1.0)
						* absf(node.scale.x), node.scale.y)
		st["phase"] = fmod(phase + _PETAL_PHASE_STEP, 256.0)
		if t >= frames:
			node.finish()
			return true
		return false)


# AnimWhiteHalo (battle_anim_effects_3.c:1294, steps :1304/:1316). No args.
#
# Holds for a full 90 FRAMES -- a second and a half, which is unusually long
# and is most of the effect -- and only then fades, one blend step per frame
# from 7 down to 0. So it is a long steady glow with a quick eight-frame
# release, not a slow pulse.
static func _white_halo(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var st := {"hold": 90, "coeff": 7}
	node.modulate.a = 7.0 / 16.0
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		if int(st["hold"]) > 0:
			st["hold"] = int(st["hold"]) - 1
			return false
		st["coeff"] = int(st["coeff"]) - 1
		node.modulate.a = maxf(0.0, float(st["coeff"]) / 16.0)
		if int(st["coeff"]) < 0:
			node.finish()
			return true
		return false)


# AnimSmokeBallEscapeCloud (battle_anim_effects_3.c:3732). args: 0 anim
# variant, 1/2 offset, 3 lifetime.
#
# Spawns on the ATTACKER but mirrors its x offset by the TARGET's side -- an
# asymmetry worth keeping, since every neighbouring behavior mirrors by the
# attacker's. It then simply sits there for `arg3` frames.
static func _smoke_ball_escape_cloud(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	_apply_anim_variant(node, ctx, vm.args[0])
	var scale := _scale(vm)
	# Mirrored by the TARGET's side, not the attacker's.
	var mirror := -1.0 if not _battler_is_player_side(vm,
			AnimStage.ANIM_TARGET) else 1.0
	node.centre = _battler_centre(vm, AnimStage.ANIM_ATTACKER) + Vector2(
			float(vm.args[1]) * mirror, float(vm.args[2])) * scale
	var life: int = maxi(1, vm.args[3])
	var st := {"t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) >= life:
			node.finish()
			return true
		return false)


# AnimAcrobaticsSlashes (battle_anim_effects_1.c:7380). args: 0/1 offset.
# Positioned on the target with a RANDOM affine variant per slash, then simply
# played out -- the randomness is the effect, giving each slash of the flurry
# a different angle.
static func _acrobatics_slashes(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	node.centre = _positioned_centre(vm, AnimStage.ANIM_TARGET, vm.args[0],
			vm.args[1], scale)
	node.rotation = float(randi() % 4) * TAU / 8.0
	_play_until_anim_ends(vm, node, _ANIM_END_CAP)


# SpriteCB_SunsteelStrikeRings (battle_anim_new.c:6791). args: 0 duration.
#
# Enters from an off-screen top corner -- the side the attacker is NOT on --
# and drives to the target. Shares `AnimFlyBallAttack_Step` with batch 9's Fly
# attack, but deliberately NOT the attacker-reveal that step also performs:
# Fly's own reveal is driven by its `data[5]`, which this behavior never sets,
# so reusing `_fly_ball_attack` wholesale would make Sunsteel Strike quietly
# un-hide a Pokemon it never hid.
static func _sunsteel_strike_rings(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var layer_w := 1024.0
	if vm.stage != null and vm.stage.has_method("layer"):
		var l: Control = vm.stage.layer()
		if l != null:
			layer_w = l.size.x
	var from_left := _is_player_side(vm)
	var start := Vector2(-32.0 * scale if from_left else layer_w + 32.0 * scale,
			-32.0 * scale)
	node.centre = start
	_linear_travel(vm, node, start,
			_battler_centre(vm, AnimStage.ANIM_TARGET), maxi(1, vm.args[0]))


# AnimBrickBreakWallShard (battle_anim_fight.c:772, step :814). args:
# 0 battler, 1 shard index (0-3), 2/3 offset.
#
# Four shards flying to four DIAGONAL corners at a flat 3px per axis per
# frame, for 40 frames -- arg 1 selects both the sprite tile and which corner,
# so the index is not cosmetic. An out-of-range index destroys the sprite
# outright upstream rather than defaulting, which is reproduced.
const _BRICK_SHARD_DIRS := [Vector2(-3, -3), Vector2(3, -3),
		Vector2(-3, 3), Vector2(3, 3)]

static func _brick_break_wall_shard(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var idx: int = vm.args[1]
	if idx < 0 or idx >= _BRICK_SHARD_DIRS.size():
		return  # upstream destroys it rather than defaulting
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var start := _positioned_centre(vm, vm.args[0], vm.args[2], vm.args[3],
			scale)
	node.centre = start
	var vel: Vector2 = (_BRICK_SHARD_DIRS[idx] as Vector2) * scale
	var st := {"t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var t: int = int(st["t"]) + 1
		st["t"] = t
		node.centre = start + vel * float(t)
		if t > 40:
			node.finish()
			return true
		return false)


# DEFERRED from this batch, all for unread step functions:
#   * `AnimDiveBall` / `AnimDiveWaterSplash` -- a two-stage pair.
#   * `SpriteCB_ToxicThreadWrap` -- hands over to `AnimStringWrap_Step`, which
#     this pass could not locate in the expected file.
#   * `SpriteCB_SpriteOnMonUntilAffineAnimEnds`.


# ── Batch 15's deferrals, cleared same-day ────────────────────────────────
#
# ⚠️ THREE OF THESE FOUR WERE DEFERRED FOR A BAD REASON, and the reason is
# worth recording because it is the same defect that produced batch 13's
# eight wrong template names: **a grep pattern that fails silently, read as
# evidence the code is hard.**
#
#   * `AnimStringWrap_Step` was "not locatable" -- it is at
#     `battle_anim_bug.c:287`. The pattern required `static void`; it is
#     declared plain `void`.
#   * `SpriteCB_SpriteOnMonUntilAffineAnimEnds` "found nothing" -- it is at
#     `battle_anim_new.c:7934`, written `struct Sprite* sprite` with the
#     asterisk on the TYPE, which the pattern did not match.
#   * The Dive pair was called "a two-stage pair" as though that implied
#     size; it is about seventy lines in total.
#
# Only `AnimFallingFeather` was ever genuinely hard, and even that turned out
# to be one block copy-pasted four times. The lesson: "grep found nothing" is
# a statement about the PATTERN, not about the source.


# AnimDiveBall (battle_anim_flying.c:1010, steps :1019/:1038). args:
# 2 launch delay, 3 acceleration.
#
# **Dive's counterpart to Fly's `AnimFlyBallUp`, and it goes further:** the
# ball accelerates UP on the same 8.8 accumulator, hides once clear of the
# screen top, waits 20 frames, and then comes back DOWN, reappearing as it
# re-enters. So one behavior covers the whole descend-and-return arc.
#
# It hides the attacker on spawn and, like Fly's up-half, never reveals it --
# that is a later script step's job, with the VM's visibility net behind it.
static func _dive_ball(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var start := _positioned_centre(vm, AnimStage.ANIM_ATTACKER, vm.args[0],
			vm.args[1], scale)
	node.centre = start
	vm.set_battler_visible_tracked(AnimStage.ANIM_ATTACKER, false)
	var delay: int = maxi(0, vm.args[2])
	var accel: int = vm.args[3]
	var top := -32.0 * scale

	var st := {"delay": delay, "vel": 0, "y": 0.0, "phase": 0, "wait": 0,
			"t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["t"] = int(st["t"]) + 1
		match int(st["phase"]):
			0:  # rise, accelerating
				if int(st["delay"]) > 0:
					st["delay"] = int(st["delay"]) - 1
				else:
					st["vel"] = int(st["vel"]) + accel
					st["y"] = float(st["y"]) - float(int(st["vel"]) >> 8) * scale
					node.centre = start + Vector2(0.0, float(st["y"]))
					if node.centre.y <= top:
						node.visible = false
						st["phase"] = 1
			1:  # off-screen hold
				st["wait"] = int(st["wait"]) + 1
				if int(st["wait"]) > 20:
					st["phase"] = 2
			_:  # and back down, reappearing as it re-enters
				st["y"] = float(st["y"]) + float(int(st["vel"]) >> 8) * scale
				node.centre = start + Vector2(0.0, float(st["y"]))
				if node.centre.y > top:
					node.visible = true
				if float(st["y"]) > 0.0:
					node.finish()
					return true
		return int(st["t"]) >= _ANIM_END_CAP * 2)


# AnimDiveWaterSplash (battle_anim_flying.c:1050). args: 0 which battler.
#
# A vertical SCALE pulse, not a moving sprite: the affine y-parameter starts
# at 0x200 and falls by 40 a frame for 12 frames, then climbs back. GBA affine
# scale is INVERTED, so a falling parameter means the splash STRETCHES upward
# -- from half height to roughly eight times it and back. The y offset is
# derived from the current scale so the column grows from a fixed base rather
# than about its centre.
const _DIVE_SPLASH_HALF := 12
const _DIVE_SPLASH_STEP := 40
const _DIVE_SPLASH_START := 0x200

static func _dive_water_splash(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var which := AnimStage.ANIM_TARGET if vm.args[0] != 0 \
			else AnimStage.ANIM_ATTACKER
	var base := _battler_centre(vm, which)
	node.centre = base
	var base_scale := node.scale

	var st := {"t": 0, "param": _DIVE_SPLASH_START}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var t: int = int(st["t"])
		st["t"] = t + 1
		# Falls for the first half, climbs back for the second.
		st["param"] = maxi(1, int(st["param"])
				+ (-_DIVE_SPLASH_STEP if t <= _DIVE_SPLASH_HALF
					else _DIVE_SPLASH_STEP))
		var ys := 256.0 / float(int(st["param"]))
		node.scale = Vector2(base_scale.x, base_scale.y * ys)
		# Anchor the column's foot rather than its middle.
		node.centre = base + Vector2(0.0,
				-(ys - 1.0) * node.size.y * 0.5 * base_scale.y)
		if int(st["t"]) >= _DIVE_SPLASH_HALF * 2:
			node.scale = base_scale
			node.finish()
			return true
		return false)


# SpriteCB_ToxicThreadWrap (battle_anim_new.c:6599) via `AnimStringWrap_Step`
# (battle_anim_bug.c:287). args: 0/1 offset.
#
# Positioned relative to the TARGET, with an extra 8px nudge when the target
# is on the player's side, then flickers on a 3-frame cycle for exactly 51
# frames. The flicker rate is the whole look -- a solid thread reads as a
# static sprite pasted on the Pokemon.
static func _toxic_thread_wrap(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var mirror := 1.0 if _is_player_side(vm) else -1.0
	var pos := _battler_centre(vm, AnimStage.ANIM_TARGET) + Vector2(
			float(vm.args[0]) * mirror, float(vm.args[1])) * scale
	if _battler_is_player_side(vm, AnimStage.ANIM_TARGET):
		pos.y += 8.0 * scale
	node.centre = pos

	var st := {"tick": 0, "t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["tick"] = int(st["tick"]) + 1
		if int(st["tick"]) >= 3:
			st["tick"] = 0
			node.visible = not node.visible
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) >= 51:
			node.finish()
			return true
		return false)


# SpriteCB_SpriteOnMonUntilAffineAnimEnds (battle_anim_new.c:7934). args:
# 0 which battler.
#
# Sits on the battler and plays out. The one detail worth keeping: it destroys
# itself IMMEDIATELY if that battler's sprite is not visible, rather than
# playing to an empty slot -- so a script that fires it at a Pokemon mid-Fly
# or mid-Dig draws nothing at all.
static func _sprite_on_mon_until_affine_ends(vm: AnimScriptVM,
		ctx: Dictionary) -> void:
	var target := vm.args[0]
	var mon := _battler_node(vm, target)
	if mon == null or not mon.visible:
		return  # upstream destroys it outright
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	node.centre = _battler_centre(vm, target)
	_play_until_anim_ends(vm, node, _ANIM_END_CAP)


# ── [M36D batch 16] ───────────────────────────────────────────────────────
#
# ⚠️ **A SECOND "looks like an alias and is not", one batch after the first.**
# `AnimViceGripPincer` (battle_anim_effects_2.c:1839) has batch 10's
# `AnimGuillotinePincer` setup BYTE FOR BYTE -- the same 32/-32 start offsets,
# the same 16/-16 rest offsets, the same arg-0 mirroring, the same 6-frame
# converge. Its STEP is completely different: Guillotine grinds in place for
# 51 frames and then retreats; ViceGrip simply arrives and dies when its own
# frame sequence ends.
#
# Batch 15's Petal Dance pair taught this the first time; this is the sharper
# case, because there the setups merely resembled each other and here they are
# identical. The rule holds: COMPARE THE STEP, NOT THE SETUP.


# AnimTask_GetTimeOfDay (battle_anim_new.c:7565). Writes 0 day / 1 night /
# 2 evening into arg 0 so a script can branch on it.
#
# Upstream reads the GBA cartridge's real-time clock, so the faithful port is
# the SYSTEM clock rather than anything battle-derived -- Sunny Day and its
# neighbours genuinely look different at 3am. Boundaries reproduced exactly:
# night is >= 20:00 or < 04:00, evening is 17:00-19:59, everything else day.
static func _get_time_of_day(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var hour: int = int(Time.get_datetime_dict_from_system().get("hour", 12))
	var slot := 0
	if hour >= 20 or hour < 4:
		slot = 1
	elif hour >= 17 and hour < 20:
		slot = 2
	vm.args[0] = slot


# AnimViceGripPincer (battle_anim_effects_2.c:1839, step :1863). args:
# 0 which pincer. Converges on the target over 6 frames and stops -- see the
# section note above for why this is NOT Guillotine despite sharing its setup.
static func _vice_grip_pincer(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var second: bool = vm.args[0] != 0
	var start_off := Vector2(-32.0, 32.0) if second else Vector2(32.0, -32.0)
	var end_off := Vector2(-16.0, 16.0) if second else Vector2(16.0, -16.0)
	var target := _battler_centre(vm, AnimStage.ANIM_TARGET)
	var start := target + start_off * scale
	node.centre = start
	_linear_travel(vm, node, start, target + end_off * scale,
			_PINCER_CONVERGE_FRAMES)


# AnimStompFoot (battle_anim_fight.c:664, steps :672/:685). args: 0/1 offset,
# 2 delay before the stomp.
#
# Three beats: it hangs above the target for `arg2` frames, drops onto it over
# 6, and then HOLDS for 15 -- the hold is the impact reading, and a port that
# ends on landing loses the weight of it.
static func _stomp_foot(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var start := _positioned_centre(vm, AnimStage.ANIM_TARGET, vm.args[0],
			vm.args[1], scale)
	var rest := _battler_centre(vm, AnimStage.ANIM_TARGET)
	node.centre = start
	var delay: int = maxi(0, vm.args[2])

	var st := {"phase": 0, "t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var t: int = int(st["t"]) + 1
		st["t"] = t
		match int(st["phase"]):
			0:
				if t >= delay:
					st["t"] = 0; st["phase"] = 1
			1:
				node.centre = start.lerp(rest, float(t) / 6.0)
				if t >= 6:
					node.centre = rest
					st["t"] = 0; st["phase"] = 2
			_:
				if t >= 15:      # the impact hold
					node.finish()
					return true
		return false)


# AnimBounceBallLand (battle_anim_flying.c:981). No args.
#
# **Bounce's counterpart to Fly's `AnimFlyBallAttack` -- it is the REVEAL
# half.** The ball drops onto the target from off-screen at 10px a frame,
# bounces straight back up at the same rate, and reveals the attacker as it
# clears the top. Routed through the tracked setter, so a run ending mid-bounce
# still restores the Pokemon.
static func _bounce_ball_land(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var rest := _battler_centre(vm, AnimStage.ANIM_TARGET)
	var top := -32.0 * scale
	node.centre = Vector2(rest.x, top)

	# Tracked as an OFFSET from the target, and the exit test compares against
	# that same offset -- "off the top" means back where it came from. An
	# absolute screen-y comparison would depend on where the target happens to
	# stand and can fire on the very first frame.
	var start_off := top - rest.y
	var st := {"y": start_off, "down": true, "t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["t"] = int(st["t"]) + 1
		st["y"] = float(st["y"]) + (10.0 if bool(st["down"]) else -10.0) * scale
		if bool(st["down"]) and float(st["y"]) >= 0.0:
			st["y"] = 0.0
			st["down"] = false
		node.centre = rest + Vector2(0.0, float(st["y"]))
		if not bool(st["down"]) and float(st["y"]) <= start_off:
			# The reveal -- this is what brings the Pokemon back after Bounce.
			vm.set_battler_visible_tracked(AnimStage.ANIM_ATTACKER, true)
			node.finish()
			return true
		return int(st["t"]) >= _ANIM_END_CAP)


# AnimWeatherBallUp (battle_anim_mons.c:2434, step :2446). No args.
#
# Rises while DECELERATING: the vertical velocity starts at -40 and creeps
# back toward -20 by one per frame, so the ball slows as it climbs rather than
# accelerating away. Its horizontal drift is side-dependent and asymmetric --
# +5 for a player-side attacker against -10 for an opponent-side one, which is
# twice the drift in the other direction, not a mirror. Offsets are scaled by
# TEN, not by 256 like most of this engine's fixed-point.
static func _weather_ball_up(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var start := _battler_centre(vm, AnimStage.ANIM_ATTACKER)
	node.centre = start
	# Deliberately asymmetric: +5 one way, -10 the other.
	var dx: int = 5 if _is_player_side(vm) else -10

	var st := {"ax": 0, "ay": 0, "vy": -40, "t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["ax"] = int(st["ax"]) + dx
		st["ay"] = int(st["ay"]) + int(st["vy"])
		node.centre = start + Vector2(float(int(st["ax"])) / 10.0,
				float(int(st["ay"])) / 10.0) * scale
		if int(st["vy"]) < -20:
			st["vy"] = int(st["vy"]) + 1   # decelerating, not accelerating
		st["t"] = int(st["t"]) + 1
		if node.centre.y < -32.0 * scale or int(st["t"]) >= _ANIM_END_CAP:
			node.finish()
			return true
		return false)


# AnimWhirlwindLine (battle_anim_flying.c:893, step :921). args: 2 battler,
# 3 lifetime, 4 lane index.
#
# Several lines run at once, offset by `12 * laneIndex`, each sliding right at
# a fixed 0x0ccc per frame in 8.8 fixed point and SNAPPING back to zero every
# 6 frames -- the snap is what produces the repeating streak rather than a
# single sliding sprite.
static func _whirlwind_line(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var which := vm.args[2]
	var base := _battler_centre(vm, which)
	if _battler_is_player_side(vm, which):
		base.x += 8.0 * scale
	base.x -= 32.0 * scale
	var lane: int = vm.args[4]
	var start := base + Vector2(float(12 * lane), 0.0) * scale
	node.centre = start
	var life: int = maxi(1, vm.args[3])

	var st := {"acc": 0, "since": lane, "t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["acc"] = int(st["acc"]) + 0x0CCC
		node.centre = start + Vector2(float(int(st["acc"]) >> 8), 0.0) * scale
		st["since"] = int(st["since"]) + 1
		if int(st["since"]) >= 6:
			st["since"] = 0
			st["acc"] = 0            # the snap back
			node.centre = start
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) >= life:
			node.finish()
			return true
		return false)


# AnimRockScatter (battle_anim_rock.c:939, step :954). args: 0/1 spawn offset,
# 2 hop height.
#
# Spawns on the target and hops OUTWARD along the direction it was offset in
# -- the offset doubles as the velocity, so a rock spawned up-left flies
# up-left. The vertical component is a sine hop rather than a fall, and the
# whole thing lives a fixed ~18 frames (phase 0 -> 140 at 8 per frame).
static func _rock_scatter(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var start := _positioned_centre(vm, AnimStage.ANIM_TARGET, vm.args[0],
			vm.args[1], scale)
	node.centre = start
	# The spawn offset IS the velocity -- rocks fly the way they were placed.
	var vx := float(vm.args[0])
	var hop := float(vm.args[2])

	var st := {"phase": 0.0, "ax": 0.0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["phase"] = float(st["phase"]) + 8.0
		st["ax"] = float(st["ax"]) + vx
		node.centre = start + Vector2(float(st["ax"]) / 40.0,
				-_gba_sin(float(st["phase"]), hop)) * scale
		if float(st["phase"]) > 140.0:
			node.finish()
			return true
		return false)


# AnimGhostStatusSprite (battle_anim_ghost.c:1186). No args.
#
# Rises while swaying on a sine of amplitude 12, with the sway MIRRORED by the
# attacker's side so the ghost always drifts away from its own trainer. The
# rise accelerates in 8.8 fixed point.
static func _ghost_status_sprite(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var start := node.centre
	var mirror := 1.0 if _is_player_side(vm) else -1.0

	var st := {"phase": 0.0, "rise": 0, "t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["rise"] = int(st["rise"]) + 0x100
		node.centre = start + Vector2(
				_gba_sin(float(st["phase"]), 12.0) * mirror,
				-float(int(st["rise"]) >> 8)) * scale
		st["phase"] = fmod(float(st["phase"]) + 6.0, 256.0)
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) >= 60:
			node.finish()
			return true
		return false)


# DEFERRED, and stated precisely per standing rule (6) -- these are UNREAD,
# not unfindable: `AnimTask_SquishTarget` (drives `sSquishTargetAffineAnimCmds`,
# an affine table not yet read), `AnimBrickBreakWall`, `AnimRazorWindTornado`,
# `AnimTask_NightShadeClone`.


# ── [M36D batch 17] ───────────────────────────────────────────────────────
#
# Batch 16's four deferrals, cleared once their step functions were actually
# read -- which is what deferring them was for. `AnimTask_SquishTarget` alone
# is the single highest-yield behavior left on the board (+6 moves).
#
# **AFFINEANIMCMD_FRAME's deltas are PER FRAME, not per command.** Traced
# through `AffineAnimDelay` -> `ApplyAffineAnimFrameRelativeAndUpdateMatrix`
# (`sprite.c`), which re-applies the delta on every tick the counter runs
# down. So `FRAME(0, 64, 0, 16)` is +1024 total, not +64. Reading it as a
# per-command total would produce a barely-visible squash instead of a
# genuine flatten, and BOTH readings look plausible on paper.


# The two SquishTarget tables (battle_anim_new.c:105 and :113). Both flatten
# the TARGET vertically and come back; they differ only in SPEED, which is
# what makes the "short" variant a variant rather than a weaker squash.
const _SQUISH_STEP := 64          # per-frame yScale delta
const _SQUISH_IN_FRAMES := 16
const _SQUISH_HOLD_FRAMES := 64
const _SQUISH_SHORT_IN_FRAMES := 4
const _SQUISH_SHORT_HOLD_FRAMES := 16


static func _squish_target(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	_squish_target_common(vm, _SQUISH_IN_FRAMES, _SQUISH_HOLD_FRAMES)


static func _squish_target_short(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	_squish_target_common(vm, _SQUISH_SHORT_IN_FRAMES, _SQUISH_SHORT_HOLD_FRAMES)


static func _squish_target_common(vm: AnimScriptVM, in_frames: int,
		hold_frames: int) -> void:
	var target := _battler_node(vm, AnimStage.ANIM_TARGET)
	if target == null:
		return
	# MonScale captures the base once and the VM's fourth restore net reads
	# the same meta, so a run ending mid-squash still un-flattens the mon.
	var ms := MonScale.new(target)

	var st := {"phase": 0, "t": 0, "y": 256.0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(target):
			return true
		st["t"] = int(st["t"]) + 1
		match int(st["phase"]):
			0:
				st["y"] = float(st["y"]) + float(_SQUISH_STEP)
				if int(st["t"]) >= in_frames:
					st["t"] = 0; st["phase"] = 1
			1:
				if int(st["t"]) >= hold_frames:
					st["t"] = 0; st["phase"] = 2
			_:
				st["y"] = float(st["y"]) - float(_SQUISH_STEP)
				if int(st["t"]) >= in_frames:
					ms.restore()
					return true
		# GBA affine scale is INVERTED: a BIGGER param is a SMALLER sprite.
		ms.apply(Vector2(1.0, 256.0 / maxf(1.0, float(st["y"]))))
		return false)


# AnimTask_NightShadeClone (battle_anim_ghost.c:371, steps :387/:403).
# args: 0 pause between the fade-in and the shrink.
#
# NOT batch 11's `_nightmare_clone` -- a different function with a different
# shape, sharing only the word "clone". The ATTACKER ITSELF is doubled in
# size and made fully transparent, fades in to 9/16 over 27 frames (one blend
# step every 3), waits, then shrinks back to normal over 16 and restores.
# Mutates scale AND blend on a battler, so it leans on two restore nets.
const _NS_CLONE_BLEND_STEPS := 9
const _NS_CLONE_BLEND_INTERVAL := 3
const _NS_CLONE_START_PARAM := 128     # 256/128 = 2.0x, i.e. double size
const _NS_CLONE_SHRINK_STEP := 8


static func _night_shade_clone(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var atk := _battler_node(vm, AnimStage.ANIM_ATTACKER)
	if atk == null:
		return
	var ms := MonScale.new(atk)
	ms.apply(Vector2.ONE * (256.0 / float(_NS_CLONE_START_PARAM)))
	_apply_blend_amount(atk, Color(0, 0, 0), 1.0)
	var pause: int = maxi(0, vm.args[0])

	var st := {"phase": 0, "t": 0, "eva": 0, "param": float(_NS_CLONE_START_PARAM)}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(atk):
			return true
		st["t"] = int(st["t"]) + 1
		match int(st["phase"]):
			0:
				if int(st["t"]) >= _NS_CLONE_BLEND_INTERVAL:
					st["t"] = 0
					st["eva"] = int(st["eva"]) + 1
					# eva rises 0..9 while evb falls 16..7 -- the clone fading
					# IN, never past 9/16, so it stays visibly ghostly.
					_apply_blend_amount(atk, Color(0, 0, 0),
							clampf(1.0 - float(st["eva"]) / 16.0, 0.0, 1.0))
					if int(st["eva"]) >= _NS_CLONE_BLEND_STEPS:
						st["t"] = 0; st["phase"] = 1
			1:
				if int(st["t"]) > pause:
					st["t"] = 0; st["phase"] = 2
			_:
				st["param"] = float(st["param"]) + float(_NS_CLONE_SHRINK_STEP)
				if float(st["param"]) > 255.0:
					ms.restore()
					_clear_blend(atk)
					return true
				ms.apply(Vector2.ONE * (256.0 / float(st["param"])))
		return false)


# AnimBrickBreakWall (battle_anim_fight.c:718, step :741). args: 0 which
# battler, 1/2 offset, 3 hold frames, 4 shake frames.
#
# Two beats and a real fork: it holds for arg3, and then EITHER dies outright
# (arg4 == 0) or rattles +/-2px every other frame for arg4 more -- the wall
# shuddering before it breaks. A port that always shakes would add motion to
# every caller that asked for none.
static func _brick_break_wall(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var which := AnimStage.ANIM_ATTACKER if vm.args[0] == 0 else AnimStage.ANIM_TARGET
	var base := _positioned_centre(vm, which, vm.args[1], vm.args[2], scale)
	node.centre = base
	var hold: int = maxi(1, vm.args[3])
	var shake: int = maxi(0, vm.args[4])

	var st := {"phase": 0, "t": 0, "flip": false, "sub": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["t"] = int(st["t"]) + 1
		if int(st["phase"]) == 0:
			if int(st["t"]) >= hold:
				if shake == 0:
					node.finish()
					return true
				st["t"] = 0; st["phase"] = 1
			return false
		st["sub"] = int(st["sub"]) + 1
		if int(st["sub"]) > 1:
			st["sub"] = 0
			st["flip"] = not bool(st["flip"])
			node.centre = base + Vector2(2.0 if bool(st["flip"]) else -2.0, 0.0) * scale
		if int(st["t"]) >= shake:
			node.finish()
			return true
		return false)


# TranslateSpriteInCircle (battle_anim_mons.c). The shared circular-orbit
# translator -- x2 = Sin(pos, amp), y2 = Cos(pos, amp), phase advancing by a
# fixed speed and wrapping at 256. Extracted because more than one behavior
# hands its sprite straight to it.
static func _circle_orbit(vm: AnimScriptVM, node: AnimSprite, base: Vector2,
		amplitude: float, speed: float, frames: int) -> void:
	var scale := _scale(vm)
	var st := {"pos": 0.0, "t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		node.centre = base + Vector2(
				_gba_sin(float(st["pos"]), amplitude),
				_gba_cos(float(st["pos"]), amplitude)) * scale
		st["pos"] = fmod(float(st["pos"]) + speed + 256.0, 256.0)
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) >= frames:
			node.finish()
			return true
		return false)


# AnimRazorWindTornado (battle_anim_effects_2.c:1821). args: 0/1 spawn offset,
# 2 initial phase, 3 amplitude, 4 lifetime, 5 phase speed.
#
# Spawned on the ATTACKER, nudged 16px down on the player's side only, then
# handed straight to the circular translator.
static func _razor_wind_tornado(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var base := _positioned_centre(vm, AnimStage.ANIM_ATTACKER,
			vm.args[0], vm.args[1], scale)
	if _is_player_side(vm):
		base.y += 16.0 * scale
	node.centre = base
	_circle_orbit(vm, node, base, float(vm.args[3]), float(vm.args[5]),
			maxi(1, vm.args[4]))


# AnimMegahornHorn (battle_anim_bug.c:171). args: 0/1 spawn offset,
# 2/3 destination offset, 4 duration.
#
# The mirroring is ASYMMETRIC and worth reading twice: against a player-side
# target BOTH offsets flip on BOTH axes, but against an opponent-side target
# nothing flips at all -- so a uniform "mirror by side" would send the horn
# the wrong way in exactly half of all uses.
static func _megahorn_horn(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var x1 := vm.args[0]
	var y1 := vm.args[1]
	var x2 := vm.args[2]
	var y2 := vm.args[3]
	if _battler_is_player_side(vm, AnimStage.ANIM_TARGET):
		x1 = -x1; y1 = -y1; x2 = -x2; y2 = -y2
	var start := _positioned_centre(vm, AnimStage.ANIM_TARGET, x1, y1, scale)
	var dest := _positioned_centre(vm, AnimStage.ANIM_TARGET, x2, y2, scale)
	node.centre = start
	_linear_travel(vm, node, start, dest, maxi(1, vm.args[4]))


# AnimCrossChopHand (battle_anim_fight.c:558, step :578). args: 2 which hand.
#
# Two travels, not one: 30 frames IN to a point up and to one side of the
# target, an 11-frame beat, then 8 frames BACK along the same vector. The
# retreat is what reads as the chop connecting; ending on arrival would look
# like the hand simply stopped.
const _CROSS_CHOP_IN_FRAMES := 30
const _CROSS_CHOP_BEAT_FRAMES := 11
const _CROSS_CHOP_OUT_FRAMES := 8


static func _cross_chop_hand(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var target := _battler_centre(vm, AnimStage.ANIM_TARGET)
	var second: bool = vm.args[2] != 0
	var start := target
	var dest := target + Vector2(20.0 if second else -20.0, -20.0) * scale
	node.centre = start
	if second:
		node.scale.x = -absf(node.scale.x)   # the mirrored hand

	var st := {"phase": 0, "t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var t: int = int(st["t"]) + 1
		st["t"] = t
		match int(st["phase"]):
			0:
				node.centre = start.lerp(dest,
						minf(1.0, float(t) / float(_CROSS_CHOP_IN_FRAMES)))
				if t >= _CROSS_CHOP_IN_FRAMES:
					st["t"] = 0; st["phase"] = 1
			1:
				if t >= _CROSS_CHOP_BEAT_FRAMES:
					st["t"] = 0; st["phase"] = 2
			_:
				node.centre = dest.lerp(start,
						minf(1.0, float(t) / float(_CROSS_CHOP_OUT_FRAMES)))
				if t >= _CROSS_CHOP_OUT_FRAMES:
					node.finish()
					return true
		return false)


# DEFERRED: `AnimTask_ScaryFace` is NOT an unread step function -- it is a
# real ASSET gap. It loads `gBattleAnimBgTilemap_ScaryFacePlayer` /
# `...Opponent`, neither of which is among M36E1's 84 pulled backgrounds.
# Closing it means extending that pull, not reading more C.


# ── [M36D batch 18] ───────────────────────────────────────────────────────
#
# The curve has genuinely flattened -- no pick is worth more than +2 now --
# so this batch goes wider and shallower rather than chasing a headline.


# SpriteCB_PhotonGeyserBeam (battle_anim_new.c:7?, step SpriteCB_BeamUpStep).
# args: 2 which target, 3 lifetime, 4 frame-sequence index, 5 affine delay.
#
# **Bails outright if the chosen target's sprite is not visible** -- a beam
# aimed at a semi-invulnerable or already-fainted battler is not drawn at all,
# rather than drawn at an empty slot.
static func _photon_geyser_beam(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var which := vm.args[2]
	var target_node := _battler_node(vm, which)
	if target_node == null or not target_node.visible:
		return
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	node.centre = _battler_centre(vm, which)
	var life: int = maxi(1, vm.args[3])

	var st := {"t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) >= life:
			node.finish()
			return true
		return false)


# SpriteCB_HorizontalSlice (battle_anim_new.c:7820, step :7833).
# args: 0/1 spawn offset, 2 distance, 3 speed, 4 direction (1 = left).
#
# Travels a fixed DISTANCE rather than for a fixed time: the timer accumulates
# `speed` per frame and the slice ends once it has covered `distance`. So a
# faster slice is a SHORTER one, not a longer one.
static func _horizontal_slice(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var base := node.centre + Vector2(float(vm.args[0]), float(vm.args[1])) * scale
	node.centre = base
	var distance: float = maxf(1.0, float(vm.args[2]))
	var speed: float = maxf(1.0, float(vm.args[3]))
	var dir := -1.0 if vm.args[4] == 1 else 1.0

	var st := {"x": 0.0, "travelled": 0.0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["x"] = float(st["x"]) + dir * speed
		st["travelled"] = float(st["travelled"]) + speed
		node.centre = base + Vector2(float(st["x"]), 0.0) * scale
		if float(st["travelled"]) >= distance:
			node.finish()
			return true
		return false)


# SpriteCB_LeftRightSlice (battle_anim_new.c, steps Step0/Step1).
# args: 0 half-width of the sweep, 1 speed.
#
# OUT then BACK across the same span, not a one-way sweep -- it starts at
# +arg0, slides to -arg0, then returns. Ending on the far side would read as
# the blade simply leaving.
static func _left_right_slice(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var base := node.centre
	var half: float = absf(float(vm.args[0]))
	var speed: float = maxf(1.0, float(vm.args[1]))
	node.centre = base + Vector2(half, 0.0) * scale

	var st := {"x": half, "back": false}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		if not bool(st["back"]):
			st["x"] = float(st["x"]) - speed
			if float(st["x"]) <= -half:
				st["x"] = -half
				st["back"] = true
		else:
			st["x"] = float(st["x"]) + speed
			if float(st["x"]) >= half:
				node.finish()
				return true
		node.centre = base + Vector2(float(st["x"]), 0.0) * scale
		return false)


# AnimEyeSparkle (battle_anim_effects_2.c, step :?). No args beyond position.
#
# Its whole step is "die when the frame sequence ends" -- the sprite sheet is
# the animation. Ported as such rather than given an invented duration.
static func _eye_sparkle(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	node.centre = _positioned_centre(vm, AnimStage.ANIM_ATTACKER,
			vm.args[0], vm.args[1], _scale(vm))
	_play_until_anim_ends(vm, node, _ANIM_END_CAP)


# AnimLetterZ (battle_anim_effects_3.c:1551). args: 0 x offset, 2 x drift,
# 3 y drift.
#
# Drifts away from the attacker on a per-frame accumulator HALVED on read
# (`x2 = data[3] / 2`), with a small sine bob laid over the vertical. Both
# drift components are negated on the opponent's side.
#
# **DISCLOSED:** upstream's exit test is `(u16)(x + x2) > DISPLAY_WIDTH`, and
# the u16 cast means a sprite drifting off the LEFT edge wraps to a huge
# value and also exits. Reproduced as "off either horizontal edge", which is
# what that cast actually achieves rather than what it literally says.
static func _letter_z(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var base := _positioned_centre(vm, AnimStage.ANIM_ATTACKER, vm.args[0], 0, scale)
	node.centre = base
	var dx := float(vm.args[2])
	var dy := float(vm.args[3])
	if not _is_player_side(vm):
		dx = -dx
		dy = -dy
	var width := 240.0 * scale

	var st := {"t": 0, "ax": 0.0, "ay": 0.0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["t"] = int(st["t"]) + 1
		st["ax"] = float(st["ax"]) + dx
		st["ay"] = float(st["ay"]) + dy
		var phase := fmod(float(int(st["t"]) * 20), 256.0)
		node.centre = base + Vector2(float(st["ax"]) * 0.5,
				_gba_sin(phase, 5.0) + float(st["ay"]) * 0.5) * scale
		if node.centre.x > width or node.centre.x < 0.0 \
				or int(st["t"]) >= _ANIM_END_CAP:
			node.finish()
			return true
		return false)


# AnimBatonPassPokeball (battle_anim_effects_3.c). No args.
#
# ⚠️ **CASE 1 FALLS THROUGH INTO CASE 2 in upstream's switch** -- there is no
# `break` -- so on every frame in state 1 BOTH blocks run: the x param gains
# 96 TWICE (192/frame), the y param goes -26 then +48 (net +22), and the step
# counter advances by TWO. Reading the switch as if each case were exclusive
# gives half the horizontal stretch and twice the duration, and looks
# perfectly reasonable on screen. Reproduced literally.
#
# Mutates the ATTACKER's scale and then hides it -- two leak classes at once,
# both covered by the VM's own restore nets. The hide is deliberate (the mon
# has just been Baton Passed out) and the paired script call brings it back.
const _BP_STRETCH_X := 96
const _BP_SQUASH_Y := 26
const _BP_RELEASE_Y := 48


static func _baton_pass_pokeball(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var atk := _battler_node(vm, AnimStage.ANIM_ATTACKER)
	var base := _battler_centre(vm, AnimStage.ANIM_ATTACKER)
	node.centre = base
	var ms := MonScale.new(atk)

	var st := {"phase": 1, "px": 256.0, "py": 256.0, "n": 0, "y": 0.0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		match int(st["phase"]):
			1:
				# case 1 ...
				st["px"] = float(st["px"]) + float(_BP_STRETCH_X)
				st["py"] = float(st["py"]) - float(_BP_SQUASH_Y)
				st["n"] = int(st["n"]) + 1
				if int(st["n"]) == 5:
					st["phase"] = 2
				# ... and then case 2 in the SAME frame, no break upstream.
				st["px"] = float(st["px"]) + float(_BP_STRETCH_X)
				st["py"] = float(st["py"]) + float(_BP_RELEASE_Y)
				st["n"] = int(st["n"]) + 1
				_bp_apply(ms, st)
			2:
				st["px"] = float(st["px"]) + float(_BP_STRETCH_X)
				st["py"] = float(st["py"]) + float(_BP_RELEASE_Y)
				st["n"] = int(st["n"]) + 1
				if int(st["n"]) >= 9:
					ms.restore()
					vm.set_battler_visible_tracked(AnimStage.ANIM_ATTACKER, false)
					st["phase"] = 3
				else:
					_bp_apply(ms, st)
			_:
				st["y"] = float(st["y"]) - 6.0 * scale
				node.centre = base + Vector2(0.0, float(st["y"]))
				if node.centre.y < -32.0 * scale:
					node.finish()
					return true
		return false)


static func _bp_apply(ms: MonScale, st: Dictionary) -> void:
	# GBA affine is INVERTED, so a rising param SHRINKS the axis.
	ms.apply(Vector2(256.0 / maxf(1.0, float(st["px"])),
			256.0 / maxf(1.0, float(st["py"]))))


# DEFERRED, and precisely: `AnimTask_GlareEyeDots` (+2) and
# `AnimTask_DestinyBondWhiteShadow` (+2) are multi-step task SPAWNERS whose
# setup was read but whose `_Step` tails were not. UNREAD, not unfindable.
# `AnimTask_FakeOut` (+1) is a different kind again -- a WIN0/BLDY screen
# window-darken effect, closer to M36E's surface than to a sprite behavior.


# ── [M36D batch 19] ───────────────────────────────────────────────────────


# AnimTask_ScaryFace (battle_anim_effects_2.c:3278, step :3311).
#
# ⚠️ **This was recorded in batches 17 and 18 as an ASSET gap — "absent from
# M36E1's 84-background pull". That reason was WRONG.** The pull script has
# always listed `scary_face_player`/`_opponent`; they were being REFUSED by
# its own two-palette-bank correctness guard, which measured the whole 32x32
# tilemap including the off-screen scroll margin. Both variants carry a single
# filler row at y=20 — one row below the visible area — in a second bank.
# Restricted to the 30x20 the GBA actually draws, they are single-bank. The
# guard was narrowed accordingly (and re-proved on a synthetic case, since no
# real asset can trip it any more); nothing about the assets changed.
#
# The behavior itself is a pure BLEND RAMP over a background — it never
# scrolls, which is what makes the off-screen filler row safe to colour with
# the visible bank's palette. eva climbs 1..14 one step every 2 frames, holds
# 21, then unwinds the same way: 28 + 21 + 28 = 77 frames.
#
# The VARIANT is chosen by the TARGET's side and reads backwards at first
# glance: `onPlayer = !IsOnPlayerSide(target)` selects the *Player* tilemap,
# i.e. "Player" names the viewpoint the face is aimed FROM, not the side it
# sits on.
const _SCARY_FACE_PEAK := 14
const _SCARY_FACE_INTERVAL := 2
const _SCARY_FACE_HOLD := 21


static func _scary_face(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var stage = vm.stage
	if stage == null or not stage.has_method("set_background"):
		return
	var player_variant := not _battler_is_player_side(vm, AnimStage.ANIM_TARGET)
	# UPPERCASE: AnimData keys backgrounds by BG NAME, not by filename. Checked
	# against has_background() rather than assumed -- the lowercase filename
	# form silently returns false and the whole behavior no-ops.
	var bg := "SCARY_FACE_PLAYER" if player_variant else "SCARY_FACE_OPPONENT"
	if not stage.set_background(bg):
		return
	vm.notify_background_changed()
	_scary_face_alpha(stage, 0.0)

	var st := {"phase": 0, "t": 0, "eva": 0}
	vm.add_stepper(func() -> bool:
		st["t"] = int(st["t"]) + 1
		match int(st["phase"]):
			0:
				if int(st["t"]) >= _SCARY_FACE_INTERVAL:
					st["t"] = 0
					st["eva"] = int(st["eva"]) + 1
					_scary_face_alpha(stage, float(st["eva"]) / 16.0)
					if int(st["eva"]) >= _SCARY_FACE_PEAK:
						st["t"] = 0; st["phase"] = 1
			1:
				if int(st["t"]) >= _SCARY_FACE_HOLD:
					st["t"] = 0; st["phase"] = 2
			_:
				if int(st["t"]) >= _SCARY_FACE_INTERVAL:
					st["t"] = 0
					st["eva"] = int(st["eva"]) - 1
					_scary_face_alpha(stage, float(st["eva"]) / 16.0)
					if int(st["eva"]) <= 0:
						if stage.has_method("clear_background"):
							stage.clear_background()
						_scary_face_alpha(stage, 1.0)
						return true
		return false)


static func _scary_face_alpha(stage, a: float) -> void:
	if not stage.has_method("background_layer"):
		return
	var layer = stage.background_layer()
	if layer != null and is_instance_valid(layer):
		layer.modulate.a = clampf(a, 0.0, 1.0)


# ── [M36D batch 20] ───────────────────────────────────────────────────────
#
# Batch 18's two deferrals, cleared once their step tails were read, plus one
# more battler-mutating fade. Same pattern as batches 11, 17 and 19: the
# previous batch's deferrals come back near the top of the ranking, which is
# what deferring them was for.


# AnimTask_GlareEyeDots (battle_anim_effects_3.c:4155, step :4190).
#
# Lays a trail of dot PAIRS from the attacker's eye to the target, one pair
# every 4 frames, each pair living 36 frames. Three details a plausible port
# gets wrong:
#
#   1. **The interpolation divisor is `pairMax - 1`, not `pairMax`.** With 12
#      pairs the span is divided by ELEVEN. Using 12 shortens the whole trail
#      so it never quite reaches the target.
#   2. **The endpoints are special-cased, not interpolated** -- pair 0 sits
#      exactly on the start and pair >= pairMax exactly on the end.
#   3. **Dots come in diagonal PAIRS offset by +/-3**, not singly.
#
# The task ends only once every dot it spawned has expired, so its own
# lifetime is the last spawn plus 36.
const _GLARE_PAIR_MAX := 12
const _GLARE_DOT_OFFSET := 3
const _GLARE_SPAWN_INTERVAL := 4
const _GLARE_DOT_LIFETIME := 36


static func _glare_eye_dots(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var scale := _scale(vm)
	var atk := _battler_centre(vm, AnimStage.ANIM_ATTACKER)
	var atk_node := _battler_node(vm, AnimStage.ANIM_ATTACKER)
	var quarter := 16.0 * scale
	if atk_node != null:
		quarter = atk_node.size.y * 0.25
	# Starts at the attacker's own eye level, offset toward the target.
	var start := atk + Vector2(
			quarter if _is_player_side(vm) else -quarter, -quarter)
	var finish := _battler_centre(vm, AnimStage.ANIM_TARGET)

	var st := {"t": 0, "pair": 0, "done": false}
	vm.add_stepper(func() -> bool:
		if bool(st["done"]):
			return true
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) < _GLARE_SPAWN_INTERVAL:
			return false
		st["t"] = 0
		var pair: int = int(st["pair"])
		var at := _glare_dot_point(start, finish, pair)
		for i in range(2):
			var dot := _make_sprite(vm, ctx)
			if dot == null:
				continue
			var off := -_GLARE_DOT_OFFSET if i == 0 else _GLARE_DOT_OFFSET
			dot.centre = at + Vector2(off, off) * scale
			_expire_after(vm, dot, _GLARE_DOT_LIFETIME)
		if pair >= _GLARE_PAIR_MAX:
			st["done"] = true
		st["pair"] = pair + 1
		return false)


static func _glare_dot_point(start: Vector2, finish: Vector2,
		pair: int) -> Vector2:
	# Endpoints are exact, not interpolated -- and the divisor is pairMax - 1.
	if pair <= 0:
		return start
	if pair >= _GLARE_PAIR_MAX:
		return finish
	return start + (finish - start) * (float(pair) / float(_GLARE_PAIR_MAX - 1))


static func _expire_after(vm: AnimScriptVM, node: AnimSprite,
		frames: int) -> void:
	var st := {"t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) > frames:
			node.finish()
			return true
		return false)


# AnimTask_DestinyBondWhiteShadow (battle_anim_ghost.c:828, steps :?).
# args: 0 pause after the ramp, 1 travel frames.
#
# **One shadow PER opposing visible battler**, not one shadow. It skips the
# attacker AND the attacker's partner, and skips anything not currently
# visible -- so in doubles it genuinely spawns two, and against a
# semi-invulnerable foe it spawns none for that slot.
#
# Travel is 4.4 fixed point (`<< 4`), a coarser grid than this engine's usual
# 8.8, so the per-frame step is computed once at spawn and accumulated.
static func _destiny_bond_white_shadow(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var scale := _scale(vm)
	var base := _battler_centre(vm, AnimStage.ANIM_ATTACKER)
	var frames: int = maxi(1, vm.args[1])

	# NOT _linear_travel: that helper destroys its sprite on arrival, which is
	# right for a projectile and wrong here. Upstream's step stops moving when
	# its frame count runs out and leaves the shadow STANDING on the foe for
	# the rest of the task -- caught by this batch's own travel test, which
	# found the shadows gone the instant they arrived.
	var shadows: Array = []
	for i in range(4):
		if i == AnimStage.ANIM_ATTACKER or i == AnimStage.ANIM_ATK_PARTNER:
			continue
		var node_i := _battler_node(vm, i)
		if node_i == null or not node_i.visible:
			continue
		var shadow := _make_sprite(vm, ctx)
		if shadow == null:
			continue
		shadow.centre = base
		shadows.append(shadow)
		_travel_and_hold(vm, shadow, base, _battler_centre(vm, i), frames)

	# The blend ramp moves eva and evb on ALTERNATE steps, not together --
	# eva rises on odd ticks, evb falls on even ones, so the fade takes twice
	# as long as moving both each step would.
	var atk := _battler_node(vm, AnimStage.ANIM_ATTACKER)
	if atk == null:
		return
	var st := {"t": 0, "n": 0, "eva": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(atk):
			return true
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) <= 1:
			return false
		st["t"] = 0
		st["n"] = int(st["n"]) + 1
		if int(st["n"]) % 2 == 1:
			st["eva"] = mini(16, int(st["eva"]) + 1)
			_apply_blend_amount(atk, Color(1, 1, 1),
					clampf(float(st["eva"]) / 16.0, 0.0, 1.0))
		if int(st["n"]) >= 24:
			_clear_blend(atk)
			for sh in shadows:
				if is_instance_valid(sh):
					(sh as AnimSprite).finish()
			return true
		return false)


# Travels a sprite and then LEAVES IT THERE. Distinct from _linear_travel,
# which destroys on arrival -- the difference matters for any behavior whose
# sprite is torn down by its owning task rather than by its own motion.
static func _travel_and_hold(vm: AnimScriptVM, node: AnimSprite,
		start: Vector2, finish_pos: Vector2, duration: int) -> void:
	var st := {"t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var t: int = int(st["t"]) + 1
		st["t"] = t
		if t >= duration:
			node.centre = finish_pos
			return true          # stop stepping; do NOT finish the sprite
		node.centre = start.lerp(finish_pos, float(t) / float(duration))
		return false)


# AnimTask_AttackerFadeToInvisible (battle_anim_dark.c:275, step :293).
# args: 0 frames between blend steps.
#
# Ramps the attacker out and then sets `invisible = TRUE` -- it does NOT
# restore, by design: the paired script call fades it back. Routed through the
# tracked visibility setter so a run ending here still leaves a usable stage.
static func _attacker_fade_to_invisible(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var atk := _battler_node(vm, AnimStage.ANIM_ATTACKER)
	if atk == null:
		return
	var delay: int = maxi(0, vm.args[0])

	var st := {"t": 0, "eva": 16}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(atk):
			return true
		if int(st["t"]) < delay:
			st["t"] = int(st["t"]) + 1
			return false
		st["t"] = 0
		st["eva"] = int(st["eva"]) - 1
		_apply_blend_amount(atk, Color(1, 1, 1),
				clampf(1.0 - float(st["eva"]) / 16.0, 0.0, 1.0))
		if int(st["eva"]) <= 0:
			_clear_blend(atk)
			vm.set_battler_visible_tracked(AnimStage.ANIM_ATTACKER, false)
			return true
		return false)


# ── [M36D batch 21] ───────────────────────────────────────────────────────


# AnimTask_SnatchOpposingMonMove (battle_anim_effects_3.c:5258). No args in,
# but it WRITES arg 7 mid-flight (see below).
#
# The Snatch gag, and a genuine five-state sequence: the attacker slides off
# its OWN side, a look-alike crosses the whole screen from the FAR side, the
# look-alike leaves, and the attacker slides back in from the side it left
# through. Getting any state's direction backwards still animates, just
# nonsensically.
#
# ⚠️ **It signals the waiting script by WRITING `gBattleAnimArgs[7] = -1`**
# the moment the crossing look-alike passes the target's x — the same
# arg-register protocol `AnimTask_SetPsychicBackground` watches from the other
# end. A port that skips the write leaves any script polling arg 7 waiting
# forever.
#
# Speed is 0x800 per frame in 8.8 with the low byte carried (`&= 0xFF`), i.e.
# a flat 8px/frame, not an acceleration.
const _SNATCH_SPEED := 8.0


static func _snatch_opposing_mon_move(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var atk := _battler_node(vm, AnimStage.ANIM_ATTACKER)
	if atk == null:
		return
	var scale := _scale(vm)
	var mo := MonOffset.new(atk)
	var player_side := _is_player_side(vm)
	# The attacker exits toward its OWN side and returns from there; the
	# look-alike crosses the other way. One sign drives both.
	var exit_dir := 1.0 if player_side else -1.0
	var width := 240.0 * scale
	var edge := 32.0 * scale
	var target_x: float = _battler_centre(vm, AnimStage.ANIM_TARGET).x
	var base_x: float = _battler_centre(vm, AnimStage.ANIM_ATTACKER).x
	var layer: Control = vm.stage.layer() if vm.stage != null else null

	var st := {"phase": 0, "x": 0.0, "clone": null, "cx": 0.0, "signalled": false}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(atk):
			return true
		match int(st["phase"]):
			0:
				st["x"] = float(st["x"]) + exit_dir * _SNATCH_SPEED * scale
				mo.apply(Vector2(float(st["x"]), 0.0))
				var here := base_x + float(st["x"])
				if here < -edge or here > width + edge:
					st["phase"] = 1
			1:
				# The look-alike enters from the FAR side, at the target's row.
				var clone := _clone_battler_visual(atk, layer)
				if clone == null:
					mo.restore()
					return true
				var start_x := (width + edge) if player_side else -edge
				var ty: float = _battler_centre(vm, AnimStage.ANIM_TARGET).y
				clone.position = Vector2(start_x - clone.size.x * 0.5,
						ty - clone.size.y * 0.5)
				st["clone"] = clone
				st["cx"] = start_x
				st["phase"] = 2
			2:
				var clone = st["clone"]
				if clone == null or not is_instance_valid(clone):
					st["phase"] = 3
					return false
				st["cx"] = float(st["cx"]) - exit_dir * _SNATCH_SPEED * scale
				clone.position.x = float(st["cx"]) - clone.size.x * 0.5
				# The signal: fired ONCE, as it passes the target.
				if not bool(st["signalled"]):
					var passed := float(st["cx"]) < target_x if player_side \
							else float(st["cx"]) > target_x
					if passed:
						st["signalled"] = true
						vm.args[7] = -1
				if float(st["cx"]) < -edge or float(st["cx"]) > width + edge:
					st["phase"] = 3
			3:
				var clone = st["clone"]
				if clone != null and is_instance_valid(clone):
					clone.queue_free()
				st["clone"] = null
				# Teleport the attacker to the far edge so it can walk back in.
				st["x"] = ((-base_x - edge) if player_side
						else (width + edge - base_x))
				mo.apply(Vector2(float(st["x"]), 0.0))
				st["phase"] = 4
			_:
				st["x"] = float(st["x"]) + exit_dir * _SNATCH_SPEED * scale
				var home := (base_x + float(st["x"]) >= base_x) if player_side \
						else (base_x + float(st["x"]) <= base_x)
				if home:
					mo.restore()
					return true
				mo.apply(Vector2(float(st["x"]), 0.0))
		return false)


# AnimTask_PurpleFlamesOnTarget (battle_anim_new.c:7685) ->
# AnimTask_GrudgeFlames_Step (battle_anim_ghost.c:1261), flame step :1346.
#
# Six flames evenly spread around the target at phases `i * 42` on the 256
# table, each also carrying an `i * 6` head start on its own vertical bob.
#
# ⚠️ **Each flame flips its DRAW ORDER at the sine midpoint** — upstream
# computes `index = phase - 65` as UNSIGNED and puts the flame behind the mon
# while `index < 127`, in front otherwise. That front/behind swap is what
# makes the six read as ORBITING the Pokemon rather than sliding across it,
# and it is invisible in any test that only checks position.
const _GRUDGE_FLAME_COUNT := 6
const _GRUDGE_PHASE_STEP := 42
const _GRUDGE_BOB_AMPLITUDE := 7.0


static func _purple_flames_on_target(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var scale := _scale(vm)
	var centre := _battler_centre(vm, AnimStage.ANIM_TARGET)
	var target_node := _battler_node(vm, AnimStage.ANIM_TARGET)
	var radius := 24.0
	if target_node != null:
		radius = target_node.size.x * 0.5 / scale + 8.0
	var forward := _is_player_side(vm)

	for i in range(_GRUDGE_FLAME_COUNT):
		var flame := _make_sprite(vm, ctx)
		if flame == null:
			continue
		var st := {"phase": float((i * _GRUDGE_PHASE_STEP) % 256),
				"bob": i * 6, "t": 0}
		vm.add_stepper(func() -> bool:
			if not is_instance_valid(flame):
				return true
			flame.advance_frame()
			# Sweeps one way or the other depending on the attacker's side.
			var p := float(st["phase"]) + (2.0 if forward else -2.0)
			st["phase"] = fmod(p + 256.0, 256.0)
			st["bob"] = int(st["bob"]) + 1
			flame.centre = centre + Vector2(
					_gba_sin(float(st["phase"]), radius),
					_gba_sin(float((int(st["bob"]) * 8) % 256),
							_GRUDGE_BOB_AMPLITUDE)) * scale
			# The front/behind swap, reproduced from the unsigned compare.
			var idx := int(st["phase"]) - 65
			if idx < 0:
				idx += 65536
			flame.z_index = -1 if idx < 127 else 1
			st["t"] = int(st["t"]) + 1
			if int(st["t"]) >= _ANIM_END_CAP:
				flame.finish()
				return true
			return false)


# SpriteCB_SteelRoller (battle_anim_new.c:8026, steps :8041/:8051).
# args: 0/1 spawn offset, 2 fall speed, 3 sweep distance, 4 sweep speed.
#
# Falls onto the target and then hands itself to the SAME left/right sweep
# batch 18 ported for `SpriteCB_LeftRightSlice` -- upstream literally sets
# that callback, so this reuses the ported motion rather than restating it.
static func _steel_roller(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var rest := _battler_centre(vm, AnimStage.ANIM_TARGET)
	var start := rest + Vector2(float(vm.args[0]), float(vm.args[1])) * scale
	node.centre = start
	var fall: float = maxf(1.0, float(vm.args[2]))
	var half: float = absf(float(vm.args[3]))
	var sweep: float = maxf(1.0, float(vm.args[4]))
	var landed := rest + Vector2(float(vm.args[0]), 0.0) * scale

	var st := {"y": float(vm.args[1]), "down": true, "x": 0.0, "back": false}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		if bool(st["down"]):
			st["y"] = float(st["y"]) + fall
			if float(st["y"]) >= 0.0:
				st["y"] = 0.0
				st["down"] = false
				st["x"] = -half
			node.centre = rest + Vector2(float(vm.args[0]),
					float(st["y"])) * scale
			return false
		# The sweep, out then back, exactly as the slice does it.
		if not bool(st["back"]):
			st["x"] = float(st["x"]) + sweep
			if float(st["x"]) >= half:
				st["x"] = half
				st["back"] = true
		else:
			st["x"] = float(st["x"]) - sweep
			if float(st["x"]) <= -half:
				node.finish()
				return true
		node.centre = landed + Vector2(float(st["x"]), 0.0) * scale
		return false)


# SpriteCB_FlippableSlash (battle_anim_new.c:8060). args: 0/1 offset,
# 2 flip X, 3 flip Y.
#
# Positioned on the target and mirrored per-axis by its own args -- the flips
# are INDEPENDENT, so a port that ties them to the battler's side loses the
# per-call control the whole behavior exists to provide. Lives until its own
# frame sequence ends.
static func _flippable_slash(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	node.centre = _positioned_centre(vm, AnimStage.ANIM_TARGET,
			vm.args[0], vm.args[1], _scale(vm))
	if vm.args[2] != 0:
		node.scale.x = -absf(node.scale.x)
	if vm.args[3] != 0:
		node.scale.y = -absf(node.scale.y)
	_play_until_anim_ends(vm, node, _ANIM_END_CAP)


# ══ [M36D batch 23] ═══════════════════════════════════════════════════════
#
# Two shared helpers first, then the behaviors that use them.


# The reference's LoadBattleAnimTarget (battle_anim_new.c:6330): an arg holds
# an ANIM_* battler SELECTOR, not a battler. In singles both partner values
# collapse onto the primary -- reading the arg as a slot index directly would
# aim a singles animation at a slot that is not there.
static func _anim_battler_from_arg(vm: AnimScriptVM, arg_index: int) -> int:
	var sel: int = vm.args[arg_index]
	match sel:
		AnimStage.ANIM_ATTACKER:
			return AnimStage.ANIM_ATTACKER
		AnimStage.ANIM_ATK_PARTNER:
			if _battler_visible(vm, AnimStage.ANIM_ATK_PARTNER):
				return AnimStage.ANIM_ATK_PARTNER
			return AnimStage.ANIM_ATTACKER
		AnimStage.ANIM_DEF_PARTNER:
			if _battler_visible(vm, AnimStage.ANIM_DEF_PARTNER):
				return AnimStage.ANIM_DEF_PARTNER
			return AnimStage.ANIM_TARGET
		_:
			return AnimStage.ANIM_TARGET


static func _battler_visible(vm: AnimScriptVM, anim_battler: int) -> bool:
	var node := _battler_node(vm, anim_battler)
	return node != null and node.visible


# InitSpritePosToAnim{Attackers,Targets}Centre: the midpoint of a side's two
# slots in doubles, the single slot in singles. Batch 22's CentredElectricity
# open-coded this; both now share it.
#
# Upstream asymmetry, deliberately not ported: the Targets variant has no
# respectMonPicOffsets branch at all (it silently leaves the sprite where it
# was) while the Attackers variant does. Every call site reaching this port
# passes FALSE, so that branch is unreachable here -- see the running lists.
static func _side_centre(vm: AnimScriptVM, primary: int, partner: int) -> Vector2:
	var at := _battler_centre(vm, primary)
	if _battler_visible(vm, partner):
		at = (at + _battler_centre(vm, partner)) * 0.5
	return at


# _make_sprite's twin for a task that names its own template in C rather than
# receiving one from the script's createsprite.
static func _make_sprite_named(vm: AnimScriptVM, template_name: String,
		blend: Dictionary) -> AnimSprite:
	var ctx := {
		"template": template_name,
		"template_data": AnimData.template(template_name),
		"blend": blend,
	}
	return _make_sprite(vm, ctx)


# SpriteCB_AnimSpriteOnSelectedMonPos (battle_anim_new.c:7197). args:
# 0 x, 1 y, 2 battler selector. Sits on the selected mon until its own frame
# animation ends. A selector resolving to an off-field mon destroys the
# sprite outright rather than drawing it at a stale position.
static func _anim_sprite_on_selected_mon_pos(vm: AnimScriptVM,
		ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var who := _anim_battler_from_arg(vm, 2)
	if not _battler_visible(vm, who):
		node.finish()
		return
	node.centre = _positioned_centre(vm, who, vm.args[0], vm.args[1],
			_scale(vm))
	_play_until_anim_ends(vm, node, _ANIM_END_CAP)


# SpriteCB_AnimSpriteOnTargetSideCentre (battle_anim_new.c:7905). args:
# 0 x, 1 y, 2 battler selector.
#
# THE ASYMMETRY: an ALLY-directed use anchors on the ATTACKER's side centre,
# not the target's. Reading the name literally -- "centre of the target side"
# -- puts every ally-targeting use of this on the wrong half of the screen,
# and it still looks like a plausible effect there.
static func _anim_sprite_on_target_side_centre(vm: AnimScriptVM,
		ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var who := _anim_battler_from_arg(vm, 2)
	var at := Vector2.ZERO
	if _battler_is_player_side(vm, who) \
			== _battler_is_player_side(vm, AnimStage.ANIM_ATTACKER):
		at = _side_centre(vm, AnimStage.ANIM_ATTACKER,
				AnimStage.ANIM_ATK_PARTNER)
	else:
		at = _side_centre(vm, AnimStage.ANIM_TARGET,
				AnimStage.ANIM_DEF_PARTNER)
	var scale := _scale(vm)
	node.centre = at + Vector2(float(vm.args[0]) * _facing(vm),
			float(vm.args[1])) * scale
	_play_until_anim_ends(vm, node, _ANIM_END_CAP)


# SpriteCB_TranslateAnimSpriteToTargetMonLocationDoubles
# (battle_anim_new.c:6703). args: 0 x, 1 y, 2 dest x, 3 dest y, 4 duration,
# 5 PACKED flags, 6 battler selector.
#
# arg 5 is TWO fields in one word -- high byte picks the pic-offset mode, low
# byte picks the Y coordinate type. Reading it as a plain int makes any
# nonzero value select the same branch and quietly loses one of the two.
#
# arg 2 is ALSO mirrored in place when the attacker is on the opposing side,
# which upstream does by writing back into gBattleAnimArgs -- a real
# side-effect on the shared arg file, reproduced here on the local copy only
# (nothing downstream in this port re-reads it).
static func _translate_to_target_mon_location_doubles(vm: AnimScriptVM,
		ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	# arg 5's two fields are decoded here for the record: bit 15..8 selects the
	# pic-offset mode, bit 7..0 the Y coordinate type. BOTH resolve to this
	# port's single battler centre -- the distinction is a hardware pic-offset
	# detail with no equivalent here -- so neither is branched on. Decoding it
	# rather than ignoring arg 5 keeps the packing visible to whoever adds pic
	# offsets later; treating it as a plain int would collapse the two.
	var scale := _scale(vm)

	node.centre = _positioned_centre(vm, AnimStage.ANIM_ATTACKER,
			vm.args[0], vm.args[1], scale)

	var dest_x: int = vm.args[2]
	if not _is_player_side(vm):
		dest_x = -dest_x

	var who := _anim_battler_from_arg(vm, 6)
	if not _battler_visible(vm, who):
		node.finish()
		return

	var dest := _battler_centre(vm, who) \
			+ Vector2(float(dest_x), float(vm.args[3])) * scale
	_linear_travel(vm, node, node.centre, dest, maxi(1, vm.args[4]))


# ── ShockWave family (battle_anim_electric.c) ────────────────────────────

const _LIGHTNING_SEGMENT_GAP := 32
const _LIGHTNING_SPAWN_INTERVAL := 2
const _LIGHTNING_LIFETIME := 28
const _BOLT_SEGMENT_GAP := 8
const _BOLT_COLUMNS := 5
const _BOLT_SEGMENT_LIFETIME := 12
const _BOLT_TOP := 4
const _BOLT_BOTTOM := 68
const _BOLT_FRAMES := 8


# AnimTask_ShockWaveLightning (battle_anim_electric.c:1485). arg 0 battler
# selector. Builds a VERTICAL COLUMN of lightning segments 32 px apart,
# marching DOWNWARD from off the top of the screen to the target, one segment
# every 2 frames.
#
# The start point is not the target and not zero: upstream takes the target's
# Y + 32 and subtracts 32 until the value drops to 16 or below, which lands
# the first segment above the screen on the same 32 px lattice the rest of
# the column sits on. Starting at the target and walking up instead would
# put the column on a different lattice and leave a visible seam.
static func _shock_wave_lightning(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var who := _anim_battler_from_arg(vm, 0)
	var scale := _scale(vm)
	var gap := float(_LIGHTNING_SEGMENT_GAP) * scale
	var target_centre := _battler_centre(vm, who)
	var bottom := target_centre.y + gap
	var y := bottom
	while y > 16.0 * scale:
		y -= gap
	var blend: Dictionary = ctx.get("blend", {"eva": 16, "evb": 0})
	var st := {"t": 0, "y": y, "done": false}

	vm.add_stepper(func() -> bool:
		if bool(st["done"]):
			return true
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) < _LIGHTNING_SPAWN_INTERVAL:
			return false
		st["t"] = 0
		var seg := _make_sprite_named(vm, "gLightningSpriteTemplate", blend)
		if seg != null:
			seg.centre = Vector2(target_centre.x, float(st["y"]))
			_play_until_anim_ends(vm, seg, _LIGHTNING_LIFETIME)
		if float(st["y"]) >= bottom:
			st["done"] = true
			return true
		st["y"] = float(st["y"]) + gap
		return false)


# AnimTask_ShockWaveProgressingBolt (battle_anim_electric.c:1352). arg 0
# battler selector. The bolt crosses to the target in 5 columns; each column
# is a vertical sweep of segments 8 px apart, and consecutive columns sweep
# in OPPOSITE directions -- that alternation is what reads as a zigzag rather
# than a row of identical strokes.
#
# Each segment also advances the sheet's frame by one (upstream nudges
# oam.tileNum), walking 7->0 downward or 0->7 upward and wrapping, so no two
# adjacent segments draw the same shape.
static func _shock_wave_progressing_bolt(vm: AnimScriptVM,
		ctx: Dictionary) -> void:
	var who := _anim_battler_from_arg(vm, 0)
	var scale := _scale(vm)
	var atk := _battler_centre(vm, AnimStage.ANIM_ATTACKER)
	var dest_x := _battler_centre(vm, who).x
	var step_x := (dest_x - atk.x) / float(_BOLT_COLUMNS)
	var gap := float(_BOLT_SEGMENT_GAP) * scale
	var blend: Dictionary = ctx.get("blend", {"eva": 16, "evb": 0})
	var st := {
		"x": atk.x, "y": atk.y, "col": 0, "dir": -1,
		"limit": float(_BOLT_TOP) * scale, "frame": _BOLT_FRAMES - 1,
	}

	vm.add_stepper(func() -> bool:
		var seg := _make_sprite_named(vm,
				"gShockWaveProgressingBoltSpriteTemplate", blend)
		if seg != null:
			seg.centre = Vector2(float(st["x"]), float(st["y"]))
			seg.set_tile_offset(int(st["frame"]))
			_play_until_anim_ends(vm, seg, _BOLT_SEGMENT_LIFETIME)
		var f: int = int(st["frame"]) + int(st["dir"])
		if f < 0:
			f = _BOLT_FRAMES - 1
		elif f >= _BOLT_FRAMES:
			f = 0
		st["frame"] = f

		var dir: int = int(st["dir"])
		var reached: bool = (dir < 0 and float(st["y"]) <= float(st["limit"])) \
				or (dir > 0 and float(st["y"]) >= float(st["limit"]))
		if not reached:
			st["y"] = float(st["y"]) + float(dir) * gap
			return false

		# Column finished: advance across and flip the sweep direction.
		st["col"] = int(st["col"]) + 1
		if int(st["col"]) >= _BOLT_COLUMNS:
			return true
		st["x"] = float(st["x"]) + step_x
		if dir < 0:
			st["dir"] = 1
			st["y"] = float(_BOLT_TOP) * scale
			st["limit"] = float(_BOLT_BOTTOM) * scale
			st["frame"] = 0
		else:
			st["dir"] = -1
			st["y"] = float(_BOLT_BOTTOM) * scale
			st["limit"] = float(_BOLT_TOP) * scale
			st["frame"] = _BOLT_FRAMES - 1
		return false)


# ── [M36D batch 22] ───────────────────────────────────────────────────────


# AnimTask_IsTargetSameSide (battle_anim_utility_funcs.c:1014).
#
# A pure QUERY, like batch 16's `AnimTask_GetTimeOfDay`: it writes TRUE/FALSE
# into arg 7 (`ARG_RET_ID`, confirmed = 7 in `constants/battle_anim.h:640`)
# and destroys itself. The script branches on the answer, so getting the
# polarity backwards sends every caller down the wrong arm -- and both arms
# animate.
static func _is_target_same_side(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var same := _battler_is_player_side(vm, AnimStage.ANIM_ATTACKER) \
			== _battler_is_player_side(vm, AnimStage.ANIM_TARGET)
	vm.args[ARG_RET_ID] = 1 if same else 0


const ARG_RET_ID := 7


# SpriteCB_MindBlownBall (battle_anim_new.c:?, step AnimMindBlownBallStep).
# args: 0 retreat frames, 1 hold frames, 2 approach frames.
#
# Three beats, and the first one is the trap. The sprite is REPOSITIONED onto
# the attacker at setup, and the per-frame delta is computed from where it
# WAS -- so phase 0 walks it back out toward its original spawn point.
#
# ⚠️ **The divisor is `arg0 << 1` while the countdown is `arg0`**, so it
# covers only HALF that distance before stopping. Using `arg0` for both --
# the obvious reading -- doubles the retreat and still looks like a
# perfectly reasonable wind-up.
static func _mind_blown_ball(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var spawn := node.centre
	var atk := _battler_centre(vm, AnimStage.ANIM_ATTACKER)
	node.centre = atk
	var out_frames: int = maxi(1, vm.args[0])
	var hold: int = maxi(0, vm.args[1])
	var in_frames: int = maxi(1, vm.args[2])
	# Halved deliberately: see the note above.
	var per_frame := (spawn - atk) / float(out_frames * 2)

	var st := {"phase": 0, "t": 0, "pos": atk, "from": atk}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["t"] = int(st["t"]) + 1
		match int(st["phase"]):
			0:
				st["pos"] = (st["pos"] as Vector2) + per_frame
				node.centre = st["pos"]
				if int(st["t"]) >= out_frames:
					st["t"] = 0; st["phase"] = 1
			1:
				if int(st["t"]) >= hold:
					st["t"] = 0
					st["from"] = node.centre
					st["phase"] = 2
			_:
				var to := _battler_centre(vm, AnimStage.ANIM_TARGET)
				node.centre = (st["from"] as Vector2).lerp(to,
						minf(1.0, float(st["t"]) / float(in_frames)))
				if int(st["t"]) >= in_frames:
					node.finish()
					return true
		return false)


# SpriteCB_CentredElectricity (battle_anim_new.c). args: 0/1 offset,
# 2 duration, 3 size variant.
#
# **Positions on the CENTRE POINT BETWEEN both targets in doubles**, and on
# the single target in singles -- not on one slot in both cases. Arg 3 also
# selects a size variant (upstream swaps the affine matrix; here it scales),
# so the same template serves three widths.
static func _centred_electricity(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	# In doubles the anchor is the midpoint of the two opposing slots.
	# Shared with batch 23's TargetSideCentre via _side_centre.
	var at := _side_centre(vm, AnimStage.ANIM_TARGET,
			AnimStage.ANIM_DEF_PARTNER)
	node.centre = at + Vector2(float(vm.args[0]), float(vm.args[1])) * scale
	match vm.args[3]:
		1:
			node.scale *= 1.5
		2:
			node.scale *= 2.0
	var life: int = maxi(1, vm.args[2])

	var st := {"t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) >= life:
			node.finish()
			return true
		return false)


# AnimTask_CreateSmallSteelBeamOrbs (battle_anim_effects_1.c:7357).
#
# A SPAWNER, not a sprite: one orb every 7 frames until 15 exist, then it
# ends. The interval reads as 6 in the source because the counter is
# pre-decremented and compared against -1, so the period is `6 + 1`.
const _STEEL_ORB_COUNT := 15
const _STEEL_ORB_INTERVAL := 7


static func _create_small_steel_beam_orbs(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var st := {"t": 0, "n": 0}
	vm.add_stepper(func() -> bool:
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) < _STEEL_ORB_INTERVAL:
			return false
		st["t"] = 0
		var orb := _make_sprite(vm, ctx)
		if orb != null:
			# Upstream hands the orb fixed args (15/0/80/0) rather than the
			# caller's, so the spawner controls the flight, not the script.
			orb.centre = _positioned_centre(vm, AnimStage.ANIM_ATTACKER,
					15, 0, _scale(vm))
			_linear_travel(vm, orb, orb.centre,
					_battler_centre(vm, AnimStage.ANIM_TARGET), 80)
		st["n"] = int(st["n"]) + 1
		return int(st["n"]) >= _STEEL_ORB_COUNT)


# DEFERRED: `AnimTask_MoveTargetMementoShadow` (+1) is a SCREEN-EFFECT gap,
# not an unread function -- a WIN0/scanline BG effect, the same family as
# `AnimTask_FakeOut`. Closing either means building that surface, not
# reading more C.


# ══ [M36D batch 24] ═══════════════════════════════════════════════════════
#
# The thrown-projectile family: an orb/bubble/coin leaves the attacker, and
# a second sprite scatters where it lands. Four moves' worth of pairs, plus
# the shared decode batch 23 found and the phase channel the VM fix above
# restored.


# The packed coord-flag word batch 23 first met on
# SpriteCB_TranslateAnimSpriteToTargetMonLocationDoubles, now with a second
# caller (AnimHydroCannonBeam), so it stops being a comment and becomes a
# function. ONE arg holds TWO fields: the high byte selects whether the
# START position respects the mon's pic offset, the low byte selects which
# Y coordinate the DESTINATION uses. Reading it as a plain int makes every
# nonzero value select the same branch and silently loses one of the two --
# Hydro Cannon's own 257 (0x0101) is exactly the value that would hide it,
# since both fields happen to be 1.
static func _packed_coord_flags(value: int) -> Dictionary:
	return {
		"respect_pic_offsets": (value & 0xFF00) == 0,
		"use_pic_offset_y": (value & 0xFF) == 0,
	}


# AnimHydroCannonCharge (battle_anim_water.c:886). No args: the orb is placed
# at the attacker and lives until its own affine animation ends.
#
# The side asymmetry is real and is NOT a mirrored offset: the orb sits 10 px
# toward the FOE either way (so it reads as gathering in front of the mon),
# but the sub-priority moves the OPPOSITE way per side (+2 player, -2
# opponent) so the charge draws behind a player mon and in front of an
# opposing one. Only the offset is reproducible here -- this port has no
# per-sprite sub-priority surface -- so the depth half is recorded and
# skipped rather than approximated with a z-index guess.
const _HYDRO_CHARGE_OFFSET := 10
const _HYDRO_CHARGE_RISE := -10


static func _hydro_cannon_charge(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	node.centre = _positioned_centre(vm, AnimStage.ANIM_ATTACKER,
			_HYDRO_CHARGE_OFFSET, _HYDRO_CHARGE_RISE, _scale(vm))
	_play_until_anim_ends(vm, node, _ANIM_END_CAP)


# AnimHydroCannonBeam (battle_anim_water.c:921). args: 0/1 start offsets,
# 2/3 destination offsets, 4 duration, 5 the packed coord flags above.
#
# arg 4 is a real DURATION here (StartAnimLinearTranslation), which is worth
# stating next to AnimCoinThrow below, where the same-looking assignment is
# a SPEED. The two cannot be told apart from the call site.
static func _hydro_cannon_beam(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	# Ally-directed use mirrors the start offset, and then mirrors it BACK
	# when the attacker occupies a left-hand slot -- a double negation that
	# nets to no change. Reproduced as the no-op it is rather than dropped,
	# because a reader meeting only the first `*= -1` would "fix" it.
	var start_x: int = vm.args[0]
	# Both fields of arg 5 resolve to this port's single battler centre, so
	# neither is branched on; the decode is exercised and recorded so a later
	# session adding pic offsets has it already worked out.
	var _flags := _packed_coord_flags(vm.args[5])
	var start := _positioned_centre(vm, AnimStage.ANIM_ATTACKER, start_x,
			vm.args[1], scale)
	var finish_pos := _battler_centre(vm, AnimStage.ANIM_TARGET) \
			+ Vector2(float(vm.args[2]) * _facing(vm), float(vm.args[3])) \
				* scale
	node.centre = start
	_linear_travel(vm, node, start, finish_pos, maxi(1, vm.args[4]))


# AnimAcidPoisonBubble (battle_anim_poison.c:546). args: 0/1 start offsets,
# 2 duration, 3 anim variant (0 selects the SECOND sequence, not the first),
# 4/5 destination offsets, 6 aim at the target side's centre.
#
# The arc amplitude is a hardcoded -30, not an arg: InitAnimArcTranslation
# sweeps a half sine over the whole flight, so a negative amplitude lifts the
# bubble above the straight line and drops it back exactly on the target.
const _ACID_BUBBLE_ARC := -30.0


static func _acid_poison_bubble(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	# Inverted on purpose: upstream plays variant 2 when the arg is ZERO.
	if vm.args[3] == 0:
		_apply_anim_variant(node, ctx, 2)
	var scale := _scale(vm)
	var start := _positioned_centre(vm, AnimStage.ANIM_ATTACKER, vm.args[0],
			vm.args[1], scale)
	var aim := _side_centre(vm, AnimStage.ANIM_TARGET,
			AnimStage.ANIM_DEF_PARTNER) if vm.args[6] != 0 \
			else _battler_centre(vm, AnimStage.ANIM_TARGET)
	var finish_pos := aim + Vector2(float(vm.args[4]) * _facing(vm),
			float(vm.args[5])) * scale
	node.centre = start
	_arc_travel(vm, node, start, finish_pos, maxi(1, vm.args[2]),
			_ACID_BUBBLE_ARC * scale)


# AnimAcidPoisonDroplet (battle_anim_poison.c:604). args: 0/1 start offsets,
# 2 horizontal drift, 3 UNUSED, 4 duration, 5 which position to anchor on.
#
# UPSTREAM QUIRK, reproduced: the fall distance is the DURATION, not arg 3.
# `sprite->data[4] = sprite->y + sprite->data[0]` reads data[0] -- already
# overwritten with arg 4 two lines earlier -- so the droplet always falls at
# exactly 1 px per frame and arg 3 is dead. Acid passes 15 and 55 for those
# two, so the difference is visible: the droplet falls 55 px, not 15. Do not
# "fix" this to arg 3 without checking the running lists.
static func _acid_poison_droplet(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var anchor := _battler_centre(vm, AnimStage.ANIM_TARGET)
	if vm.args[5] == 1:
		anchor = _side_centre(vm, AnimStage.ANIM_TARGET,
				AnimStage.ANIM_DEF_PARTNER)
	elif vm.args[5] == 2:
		anchor = _battler_centre(vm, AnimStage.ANIM_DEF_PARTNER)
	var start := anchor + Vector2(float(vm.args[0]) * _facing(vm),
			float(vm.args[1])) * scale
	var duration: int = maxi(1, vm.args[4])
	var finish_pos := start + Vector2(float(vm.args[2]) * _facing(vm),
			float(duration)) * scale
	node.centre = start
	_linear_travel(vm, node, start, finish_pos, duration)


# AnimGunkShotImpact (battle_anim_poison.c:394). args: 0/1 offsets,
# 2 which battler (0 attacker, else target), 3 affine variant.
# Lives exactly as long as its own animation.
static func _gunk_shot_impact(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var who: int = AnimStage.ANIM_ATTACKER if vm.args[2] == 0 \
			else AnimStage.ANIM_TARGET
	_apply_anim_variant(node, ctx, vm.args[3])
	node.centre = _positioned_centre(vm, who, vm.args[0], vm.args[1],
			_scale(vm))
	_play_until_anim_ends(vm, node, _ANIM_END_CAP)


# AnimCoinThrow (battle_anim_effects_2.c:1714). args: 0/1 start offsets,
# 2/3 destination offsets, 4 SPEED.
#
# THE FINDING: arg 4 is a speed in 8.8 fixed point, not a duration. It flows
# into InitAnimLinearTranslationWithSpeed, which OVERWRITES data[0] with
# `(|dx| << 8) / data[0]` -- so the value is a divisor, and the real frame
# count falls out of the distance. Pay Day passes 1152 (4.5 px/frame). Read
# as a duration that is a nineteen-second coin.
#
# The coin also ROTATES to face its travel direction: ArcTan2Neg of the
# delta, plus 0xC000 (a quarter turn) because the sprite is drawn edge-on.
# Shared with every other aiming rotator -- see `_AIM_ROTATION_OFFSET`.
const _COIN_ROTATION_OFFSET := _AIM_ROTATION_OFFSET


static func _coin_throw(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var start := _positioned_centre(vm, AnimStage.ANIM_ATTACKER, vm.args[0],
			vm.args[1], scale)
	var finish_pos := _battler_centre(vm, AnimStage.ANIM_TARGET) \
			+ Vector2(float(vm.args[2]) * _facing(vm), float(vm.args[3])) \
				* scale
	# Speed is in GBA pixels per frame; the distance it divides is in stage
	# pixels, so scale it too or the flight length changes with the canvas.
	var speed: float = maxf(1.0, float(vm.args[4]) / 256.0 * scale)
	var duration: int = maxi(1, int(absf(finish_pos.x - start.x) / speed))
	node.centre = start
	node.rotation = (finish_pos - start).angle() \
			+ _gba_rot_to_radians(_COIN_ROTATION_OFFSET)
	_linear_travel(vm, node, start, finish_pos, duration)


# AnimFallingCoin (battle_anim_effects_2.c:1737). No args at all -- it starts
# wherever createsprite put it (the target's centre) 8 px lower.
#
# Two bounces, not a fall: a half sine of amplitude -16 lifts and drops the
# coin over 26 frames, then the amplitude HALVES and it does it again, and on
# the second landing the sprite is destroyed. Meanwhile it drifts sideways at
# a constant 0.5 px per frame, AWAY from the player's side. 52 frames total.
const _COIN_BOUNCE_AMPLITUDE := -16.0
const _COIN_BOUNCE_STEP := 5
const _COIN_BOUNCE_LIMIT := 126
const _COIN_DRIFT_PER_FRAME := 0.5
const _COIN_BOUNCES := 2
const _COIN_DROP := 8


static func _falling_coin(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	node.centre = _battler_centre(vm, AnimStage.ANIM_TARGET) \
			+ Vector2(0.0, float(_COIN_DROP) * scale)
	# Upstream negates the drift for the PLAYER side, so the coin always
	# travels toward the opposing half of the screen.
	var drift := _COIN_DRIFT_PER_FRAME * scale
	if _is_player_side(vm):
		drift = -drift
	var st := {"x": 0.0, "phase": 0, "amp": _COIN_BOUNCE_AMPLITUDE, "n": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["x"] = float(st["x"]) + drift
		node.offset = Vector2(float(st["x"]),
				_gba_sin(float(st["phase"]), float(st["amp"]) * scale))
		st["phase"] = int(st["phase"]) + _COIN_BOUNCE_STEP
		if int(st["phase"]) > _COIN_BOUNCE_LIMIT:
			st["phase"] = 0
			st["amp"] = float(st["amp"]) / 2.0
			st["n"] = int(st["n"]) + 1
			if int(st["n"]) >= _COIN_BOUNCES:
				node.finish()
				return true
		return false)


# ══ [M36D batch 25] ═══════════════════════════════════════════════════════
#
# The sound family: music notes that fly off the singer, and the two affine
# deformations that make a mon look like it is bellowing or inhaling.


# The reference's AFFINEANIMCMD_FRAME(xScale, yScale, rotation, duration)
# applies each delta ONCE PER FRAME for `duration` frames. Scale deltas are
# in GBA affine units where 256 is identity and LARGER means SMALLER, so a
# positive xScale delta narrows the sprite -- the inversion this port already
# encodes once, in MonAnimator.godot_scale.
#
# Both tasks below drive a battler through such a list via
# PrepareAffineAnimInTaskData / RunAffineAnimFromTaskData, so the walk is
# shared rather than written twice. Each entry is [dx, dy, drot, frames].
const _GBA_AFFINE_IDENTITY := 256.0


# ── [M36 review] Foot anchoring for task-path battler deforms ─────────────
#
# `SetBattlerSpriteYOffsetFromYScale` (battle_anim_mons.c:1845):
#
#     var  = MON_PIC_HEIGHT - yPicOffset * 2          // 64 - 2*off
#     var2 = (var << 8) / matrix.d,  capped at 128    // == var * yScale
#     y2   = (var - var2) / 2                         // == (32 - off)(1 - s)
#
# ⚠️ **THE ANCHOR IS THE BOTTOM OF THE DRAWN ART, NOT THE BOTTOM OF THE BOX** —
# which is exactly why the species term is there. `backPicYOffset` /
# `frontPicYOffset` is "the number of pixels between the drawn pixel area and
# the bottom edge" (include/pokemon.h:459), so subtracting it walks the anchor
# up off the box edge onto the mon's actual feet. This project already pulled
# both tables for `_apply_bottom_anchored_front_sprite`; this is their second
# consumer.
#
# Derived independently for this port's geometry and it lands on the same
# expression, which is the check that it is right: the node is `size.y` tall
# for a 64px sprite, the art's bottom sits `off * pix` above the node's bottom
# edge, `MonScale` pivots at the CENTRE, and holding a point `a` fixed under a
# centre scale needs a shift of `(a - size.y/2)(1 - s)`. With
# `a = size.y - off*pix` that is `(32 - off) * pix * (1 - s)` — source's own
# formula times the stage scale.
#
# Returns source's own `var` — the anchored height in GBA pixels, `64 - 2*off`.
# Deliberately NOT pre-collapsed into a single multiplier: `var` is the
# dividend of source's clamp as well as its scale term, so folding the two
# together loses the cap (the clamp is `var * s <= 128`, which depends on the
# species and is NOT a flat `s <= 2` — I collapsed it that way on the first
# pass and it was wrong).
static func _y_anchor_height(vm: AnimScriptVM, anim_battler: int) -> float:
	# Fallback is the BOX bottom (offset 0), not zero: a battler whose species
	# cannot be resolved still wants its feet held, and "the art fills its box"
	# is the right assumption when nothing better is known. Zero would silently
	# restore the centre-collapse this exists to fix.
	var off := 0.0
	if anim_battler >= 0 and vm.stage != null and vm.stage.has_method("mon_for"):
		var mon: Variant = vm.stage.mon_for(anim_battler)
		if mon is BattlePokemon and (mon as BattlePokemon).species != null:
			var dex: int = (mon as BattlePokemon).species.national_dex_num
			off = float(SpriteRegistry.get_back_y_offset(dex)
					if _battler_is_player_side(vm, anim_battler)
					else SpriteRegistry.get_front_y_offset(dex))
	return float(_MON_PIC_HEIGHT) - off * 2.0


# `y2 = (var - min(var * s, 128)) / 2`, source line for line, scaled to stage
# pixels. `s` is the VISUAL y scale (1.0 = rest), so a squash returns a
# POSITIVE value = downward = the mon sinks onto its base.
static func _y_anchor_shift(var_gba: float, s: float, pix: float) -> float:
	var scaled := minf(var_gba * s, float(_MON_PIC_HEIGHT * 2))
	return (var_gba - scaled) * 0.5 * pix


const _MON_PIC_HEIGHT := 64


static func _run_affine_cmds(vm: AnimScriptVM, node: Control, cmds: Array,
		per_frame: Callable = Callable(), anim_battler: int = -1) -> void:
	if node == null:
		return
	var deform := MonScale.new(node)
	# [M36 review] The foot anchor -- see `_y_anchor_arm`. -1 means the caller
	# did not name a battler, in which case the box bottom stands in.
	var anchor_h := _y_anchor_height(vm, anim_battler)
	var anchor_pix := _scale(vm)
	var base_pos := node.position
	if node.has_meta(MonOffset.META_BASE):
		base_pos = node.get_meta(MonOffset.META_BASE)
	var st := {"i": 0, "n": 0, "t": 0, "x": _GBA_AFFINE_IDENTITY,
			"y": _GBA_AFFINE_IDENTITY, "rot": 0.0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		var i: int = int(st["i"])
		if i >= cmds.size():
			# [Corrected in batch 28] This restore is NOT a divergence, as
			# batch 25 first recorded it. `RunAffineAnimFromTaskData`'s
			# AFFINEANIMCMDTYPE_END case calls `ResetSpriteRotScale` and
			# zeroes y2 (battle_anim_mons.c) -- upstream restores at the end
			# of EVERY table too. That is also why one real table,
			# `gShrinkAndGrowAffineAnimCmds`, can be asymmetric (+24/+30 net)
			# without leaving a permanently shrunken mon: the reset cleans up
			# after it either way. The per-table sum assertions therefore
			# guard transcription errors, not leaks.
			deform.restore()
			node.position = base_pos
			return true
		var cmd: Array = cmds[i]
		st["x"] = float(st["x"]) + float(cmd[0])
		st["y"] = float(st["y"]) + float(cmd[1])
		# ⚠️ `<< _AFFINE_ROT_SHIFT` — see that constant. An affine table's
		# rotation is a u8 that source shifts up 8 bits (`sprite.c:1327`), so
		# accumulating it raw is 256x too slow. LATENT here today: none of the
		# eleven hand-transcribed tables this runner is called with carries a
		# nonzero rotation column, so every one is pure scale — fixed anyway,
		# because the trap is for whoever adds a rotating table next.
		st["rot"] = float(st["rot"]) + float(int(cmd[2]) << _AFFINE_ROT_SHIFT)
		# 256/value, the inverted-scale rule. Guarded so a table that walked
		# the value to zero could not produce an infinite scale.
		var sx := _GBA_AFFINE_IDENTITY / maxf(1.0, float(st["x"]))
		var sy := _GBA_AFFINE_IDENTITY / maxf(1.0, float(st["y"]))
		deform.apply(Vector2(sx, sy), _gba_rot_to_radians(int(st["rot"])))
		# ⚠️ **THE FEET STAY PLANTED, AND THAT IS A SECOND WRITE PER FRAME, NOT
		# A PIVOT CHOICE.** Source recomputes `sprite->y2` from the live matrix
		# every frame (`SetBattlerSpriteYOffsetFromYScale`, called right after
		# `SetSpriteRotScale` at `battle_anim_mons.c:1790`), so a squashing mon
		# sinks rather than collapsing toward its own middle. Without it a
		# Facade squish lifts the mon ~96 stage px off its base.
		node.position = base_pos + Vector2(0.0,
				_y_anchor_shift(anchor_h, sy, anchor_pix))
		if per_frame.is_valid():
			per_frame.call(int(st["t"]), node)
		st["t"] = int(st["t"]) + 1
		st["n"] = int(st["n"]) + 1
		if int(st["n"]) >= int(cmd[3]):
			st["n"] = 0
			st["i"] = i + 1
		return false)


# AnimTask_UproarDistortion (battle_anim_effects_2.c:3622). args: 0 battler.
# sAffineAnims_UproarDistortion is three 4-frame legs whose deltas sum to
# exactly zero on BOTH axes -- the mon squashes, overshoots the other way,
# and lands back at its true size. 12 frames. A port that stopped after the
# second leg would leave the battler permanently deformed, which is the leak
# class rule (3) exists for; the shared walk restores on completion and the
# VM's own net catches an aborted run.
const _UPROAR_AFFINE := [[-12, 8, 0, 4], [20, -20, 0, 4], [-8, 12, 0, 4]]


static func _uproar_distortion(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	_run_affine_cmds(vm, _battler_node(vm, vm.args[0]), _UPROAR_AFFINE,
			Callable(), vm.args[0])


# AnimTask_DeepInhale (battle_anim_effects_3.c:3635). args: 0 battler.
# 64 frames: narrow over 4, stretch tall over 16, narrow a little more over
# 4, HOLD for 24, then unwind over 16 back to exactly identity.
#
# The shiver during the hold is gated by a u16 UNDERFLOW, and that is
# load-bearing: `var0 = task->data[0]; var0 -= 20; if (var0 < 23)`. On frames
# 0-19 the subtraction wraps to ~65516 and fails the test, so the jitter runs
# only on frames 20-42. Read as a signed comparison it would start shaking
# from frame zero, before the inhale has begun.
const _DEEP_INHALE_AFFINE := [[16, 0, 0, 4], [0, -3, 0, 16], [4, 0, 0, 4],
		[0, 0, 0, 24], [-5, 3, 0, 16]]
const _DEEP_INHALE_SHIVER_FROM := 20
const _DEEP_INHALE_SHIVER_SPAN := 23


static func _deep_inhale(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var node := _battler_node(vm, vm.args[0])
	if node == null:
		return
	var scale := _scale(vm)
	var shake := MonOffset.new(node)
	var st := {"c": 0}
	var jitter := func(frame: int, _n: Control) -> void:
		var since: int = frame - _DEEP_INHALE_SHIVER_FROM
		if since < 0 or since >= _DEEP_INHALE_SHIVER_SPAN:
			shake.apply(Vector2.ZERO)
			return
		if frame % 2 == 0:
			st["c"] = int(st["c"]) + 1
			shake.apply(Vector2(scale if int(st["c"]) % 2 == 1 else -scale,
					0.0))
	# The jitter callback zeroes the offset outside its own window, so the
	# shiver is already undone by frame 43 without a second stepper. The
	# VM's `_restore_displaced_battlers` net covers an aborted run, which is
	# the only way this could end mid-shake.
	_run_affine_cmds(vm, node, _DEEP_INHALE_AFFINE, jitter, vm.args[0])


# gParticlesColorBlendTable (battle_anim_effects_1.c:2125). Four palettes a
# music note cycles through: pink, green, yellow, blue. Each row's first
# entry is the sprite tag it belongs to and is not a colour, so only the
# ramp's darkest entry is used here as the note's tint.
const _NOTE_BLEND_COLORS := [
	Color8(255, 106, 180),  # ANIM_TAG_MUSIC_NOTES     RGB(31,13,22)
	Color8(82, 255, 98),    # ANIM_TAG_BENT_SPOON      RGB(10,31,12)
	Color8(255, 255, 24),   # ANIM_TAG_SPHERE_TO_CUBE  RGB(31,31,3)
	Color8(98, 180, 255),   # ANIM_TAG_LARGE_FRESH_EGG RGB(12,22,31)
]


# AnimTask_MusicNotesRainbowBlend / ...ClearRainbowBlend
# (battle_anim_effects_1.c:6862 / :6890). Upstream these ALLOCATE and FREE
# GBA sprite-palette slots so the note sprites have four palettes to point
# at. Godot has no palette-bank surface and a sprite carries its own colour,
# so allocation has nothing to do -- but the COLOURS still have to reach the
# notes, and they do: the notes read `_NOTE_BLEND_COLORS` directly.
#
# Recorded rather than left as a bare `pass`, per the standing rule that a
# stub is a bet on the future: if this port ever grows real palette banks,
# these are the two call sites that would own them.
static func _music_notes_rainbow_blend(_vm: AnimScriptVM,
		_ctx: Dictionary) -> void:
	pass


static func _music_notes_clear_rainbow_blend(_vm: AnimScriptVM,
		_ctx: Dictionary) -> void:
	pass


# AnimWavyMusicNotes (battle_anim_effects_1.c:6908). args: 0 anim variant,
# 1 starting palette row, 2 blend cycle time in frames.
#
# Speed, not duration: CalcVelocity solves for a horizontal rate of 40/256 px
# per frame toward the target and derives the vertical rate from it, so a
# note that has further to travel simply takes longer. It dies when it leaves
# the screen, never on a timer.
const _WAVY_NOTE_SPEED := 40.0 / 16.0
const _WAVY_NOTE_WAVE := 15.0
const _WAVY_NOTE_PHASE_STEP := 5


static func _wavy_music_notes(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	_apply_anim_variant(node, ctx, vm.args[0])
	var scale := _scale(vm)
	var start := _battler_centre(vm, AnimStage.ANIM_ATTACKER)
	var toward := _battler_centre(vm, AnimStage.ANIM_TARGET)
	node.centre = start
	var delta := toward - start
	var speed := _WAVY_NOTE_SPEED * scale
	var frames: float = maxf(1.0, absf(delta.x) / speed)
	var per_frame := delta / frames
	var cycle: int = vm.args[2]
	var st := {"t": 0, "pal": vm.args[1], "blend": 0, "pos": start}
	node.modulate = _NOTE_BLEND_COLORS[
			posmod(int(vm.args[1]), _NOTE_BLEND_COLORS.size())]
	var bounds: Vector2 = Vector2(1024.0, 768.0)
	if vm.stage != null and vm.stage.has_method("layer"):
		var l: Control = vm.stage.layer()
		if l != null:
			bounds = l.size
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["t"] = int(st["t"]) + 1
		var t: int = int(st["t"])
		var pos: Vector2 = start + per_frame * float(t)
		var phase: int = (t * _WAVY_NOTE_PHASE_STEP) % 256
		node.centre = pos + Vector2(0.0,
				_gba_sin(float(phase), _WAVY_NOTE_WAVE * scale))
		# The rainbow: every `cycle` frames the note steps to the next
		# palette row and wraps. cycle == 0 means "never change".
		if cycle > 0:
			st["blend"] = int(st["blend"]) + 1
			if int(st["blend"]) > cycle:
				st["blend"] = 0
				st["pal"] = (int(st["pal"]) + 1) % _NOTE_BLEND_COLORS.size()
				node.modulate = _NOTE_BLEND_COLORS[int(st["pal"])]
		var margin := 16.0 * scale
		if node.centre.x < -margin or node.centre.x > bounds.x + margin \
				or node.centre.y < -margin \
				or node.centre.y > bounds.y - 32.0 * scale:
			node.finish()
			return true
		return false)


# AnimSlowFlyingMusicNotes (battle_anim_effects_1.c:7048). args: 0 direction
# (0 left, else right), 1 anim variant, 2 palette row, 3 sine phase seed.
# A fixed 40-frame rise: 32 px sideways and 40 px UP, with a wobble whose
# horizontal half follows the direction of travel rather than oscillating
# about it -- upstream negates the sine when the travel offset is negative,
# so the note leans further out rather than weaving back through its path.
const _SLOW_NOTE_FRAMES := 40
const _SLOW_NOTE_DX := 32.0
const _SLOW_NOTE_DY := -40.0
const _SLOW_NOTE_DROP := 8.0
const _SLOW_NOTE_WOBBLE_X := 8.0
const _SLOW_NOTE_WOBBLE_Y := 4.0
const _SLOW_NOTE_PHASE_STEP := 8


static func _slow_flying_music_notes(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	_apply_anim_variant(node, ctx, vm.args[1])
	node.modulate = _NOTE_BLEND_COLORS[
			posmod(int(vm.args[2]), _NOTE_BLEND_COLORS.size())]
	var scale := _scale(vm)
	var start := _battler_centre(vm, AnimStage.ANIM_ATTACKER) \
			+ Vector2(0.0, _SLOW_NOTE_DROP * scale)
	var dx: float = (-_SLOW_NOTE_DX if vm.args[0] == 0 else _SLOW_NOTE_DX)
	var finish_pos := start + Vector2(dx, _SLOW_NOTE_DY) * scale
	node.centre = start
	var st := {"t": 0, "phase": vm.args[3]}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var t: int = int(st["t"]) + 1
		st["t"] = t
		if t >= _SLOW_NOTE_FRAMES:
			node.finish()
			return true
		var f := float(t) / float(_SLOW_NOTE_FRAMES)
		var travelled := (finish_pos - start) * f
		var wob_x := _gba_sin(float(st["phase"]), _SLOW_NOTE_WOBBLE_X * scale)
		if travelled.x < 0.0:
			wob_x = -wob_x
		node.centre = start + travelled + Vector2(wob_x,
				_gba_sin(float(st["phase"]), _SLOW_NOTE_WOBBLE_Y * scale))
		st["phase"] = (int(st["phase"]) + _SLOW_NOTE_PHASE_STEP) & 0xFF
		return false)


# AnimJaggedMusicNote (battle_anim_effects_2.c:3637). args: 0 battler
# (0 attacker else target), 1/2 offset, 3 glyph.
#
# THE OFFSET IS ALSO THE VELOCITY. `data[3] = (args[1] << 3) / 8` is args[1]
# again, added to an 8.8-ish accumulator every frame, so a note spawned 29 px
# to the right also drifts right at 29/8 px per frame. One arg, two jobs --
# reading it as position only leaves every Uproar note hanging motionless.
const _JAGGED_NOTE_FRAMES := 17
const _JAGGED_NOTE_DIVISOR := 8.0


static func _jagged_music_note(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var who: int = AnimStage.ANIM_ATTACKER if vm.args[0] == 0 \
			else AnimStage.ANIM_TARGET
	var scale := _scale(vm)
	var start := _positioned_centre(vm, who, vm.args[1], vm.args[2], scale)
	node.centre = start
	node.set_tile_offset(vm.args[3] * 16)
	var per_frame := Vector2(float(vm.args[1]) * _facing(vm),
			float(vm.args[2])) * scale / _JAGGED_NOTE_DIVISOR
	var st := {"t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var t: int = int(st["t"]) + 1
		st["t"] = t
		if t > _JAGGED_NOTE_FRAMES:
			node.finish()
			return true
		node.centre = start + per_frame * float(t)
		return false)


# AnimBellyDrumHand (battle_anim_effects_1.c:7026). args: 0 side (1 = right,
# mirrored sprite). A static hand held for 8 frames beside the attacker --
# no motion of its own, the drumming is the mon's own deformation.
const _BELLY_DRUM_HAND_OFFSET := 16
const _BELLY_DRUM_HAND_DROP := 8
const _BELLY_DRUM_HAND_FRAMES := 8


static func _belly_drum_hand(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var right: bool = vm.args[0] == 1
	var scale := _scale(vm)
	node.centre = _battler_centre(vm, AnimStage.ANIM_ATTACKER) \
			+ Vector2(float(_BELLY_DRUM_HAND_OFFSET if right
					else -_BELLY_DRUM_HAND_OFFSET),
					float(_BELLY_DRUM_HAND_DROP)) * scale
	if right:
		node.scale = Vector2(-node.scale.x, node.scale.y)
	var st := {"t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) >= _BELLY_DRUM_HAND_FRAMES:
			node.finish()
			return true
		return false)


# ══ [M36D batch 26] ═══════════════════════════════════════════════════════
#
# Everything that fades. The Moonlight set (a moon that outlives its own
# script until another task kills it), the alpha ramps, and Sky Attack's
# bird -- which is also the reason the fade-from-invisible half is here.
#
# DEFERRED, and this is a Step 0 finding rather than an omission:
# `AnimSpotlight`, `AnimTask_CreateSpotlight` and `AnimTask_RemoveSpotlight`
# are WIN0/WIN1 HARDWARE-WINDOW effects -- they write WININ/WINOUT/DISPCNT
# and mark the sprite `ST_OAM_OBJ_WINDOW` so it acts as a stencil, not as
# something drawn. That is the same surface `AnimTask_FakeOut` and
# `AnimTask_MoveTargetMementoShadow` are already deferred on. Closing any of
# the three means building a stencil/mask layer, not reading more C.
# `AnimTask_HardwarePaletteFade` is portable on its own but only unlocks
# moves alongside the spotlight trio, so it waits with them.


# Moonlight's moon and sparkles do not end themselves: they idle until
# AnimTask_MoonlightEndFade sets `data[0] = 1` on every sprite built from
# their two templates. That cross-sprite kill is the only thing that ends
# them, so it is modelled as a mark on the node rather than a timer -- a
# lifetime cap would end them at the wrong moment and hide the dependency.
const _MOONLIGHT_MARK := "_anim_moonlight_sprite"


static func _mark_moonlight(node: AnimSprite) -> void:
	if node != null:
		node.set_meta(_MOONLIGHT_MARK, true)


# AnimMoon (battle_anim_effects_1.c:6252). args: 0/1 position.
#
# ABSOLUTE SCREEN COORDINATES, not an offset from any battler -- Moonlight
# passes (120, 56), the middle of a 240-wide screen. Every other sprite in
# this port positions relative to a mon, so reading these two as offsets
# puts the moon on top of the attacker instead of in the sky.
static func _moon(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	node.centre = _gba_screen_point(vm, vm.args[0], vm.args[1])
	_mark_moonlight(node)
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		if node.has_meta(_MOONLIGHT_KILL):
			node.finish()
			return true
		return false)


# Converts a GBA screen coordinate (240x160) to this stage's canvas.
static func _gba_screen_point(vm: AnimScriptVM, x: int, y: int) -> Vector2:
	var scale := _scale(vm)
	return Vector2(float(x), float(y)) * scale


const _MOONLIGHT_KILL := "_anim_moonlight_kill"


# AnimMoonlightSparkle (battle_anim_effects_1.c:6279). args: 0 x offset from
# the attacker, 1 ABSOLUTE y. Note the mixed frame of reference -- x is
# relative, y is not -- which is why Moonlight passes y = 0 for every sparkle
# and they all start at the top of the screen.
#
# It creeps DOWN one pixel every other frame, capped at 120 px of travel, and
# like the moon waits to be killed rather than ending itself.
const _SPARKLE_DRIFT_LIMIT := 120


static func _moonlight_sparkle(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var start := Vector2(
			_battler_centre(vm, AnimStage.ANIM_ATTACKER).x
					+ float(vm.args[0]) * _facing(vm) * scale,
			float(vm.args[1]) * scale)
	node.centre = start
	_mark_moonlight(node)
	var st := {"t": 0, "fallen": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		if node.has_meta(_MOONLIGHT_KILL):
			node.finish()
			return true
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) % 2 == 0 and int(st["fallen"]) < _SPARKLE_DRIFT_LIMIT:
			st["fallen"] = int(st["fallen"]) + 1
			node.centre = start + Vector2(0.0, float(st["fallen"]) * scale)
		return false)


# AnimTask_MoonlightEndFade (battle_anim_effects_1.c:6309, step at :6336).
# No args. A four-state machine, and the states are not interchangeable:
#
#   0  ramp every battle palette toward RGB(27,29,31) over 15 steps
#   1  KILL the moon and every sparkle (the cross-sprite signal above)
#   2  hold for 30 frames
#   3  ramp back
#
# The kill is in state 1, AFTER the whiteout completes -- so the moon
# disappears while the screen is already washed out and nobody sees it pop.
# Killing in state 0 would make it vanish in plain view.
const _MOONLIGHT_FADE_STEPS := 15
const _MOONLIGHT_HOLD := 30
const _MOONLIGHT_FADE_COLOR := Color8(219, 235, 255)  # RGB(27,29,31)


static func _moonlight_end_fade(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var nodes: Array[Control] = []
	for battler in [AnimStage.ANIM_ATTACKER, AnimStage.ANIM_TARGET,
			AnimStage.ANIM_ATK_PARTNER, AnimStage.ANIM_DEF_PARTNER]:
		var n := _battler_node(vm, battler)
		if n != null:
			nodes.append(n)
	var st := {"phase": 0, "t": 0}
	vm.add_stepper(func() -> bool:
		var phase: int = int(st["phase"])
		var t: int = int(st["t"]) + 1
		st["t"] = t
		if phase == 0:
			var f := clampf(float(t) / float(_MOONLIGHT_FADE_STEPS), 0.0, 1.0)
			for n in nodes:
				_apply_blend_amount(n, _MOONLIGHT_FADE_COLOR, f)
			if t >= _MOONLIGHT_FADE_STEPS:
				st["phase"] = 1
				st["t"] = 0
			return false
		if phase == 1:
			# The signal. Everything the two Moonlight templates built dies
			# here, whatever else it was doing.
			if vm.stage != null and vm.stage.has_method("layer"):
				var layer: Control = vm.stage.layer()
				if layer != null:
					for child in layer.get_children():
						if child is AnimSprite \
								and child.has_meta(_MOONLIGHT_MARK):
							child.set_meta(_MOONLIGHT_KILL, true)
			st["phase"] = 2
			st["t"] = 0
			return false
		if phase == 2:
			if t > _MOONLIGHT_HOLD:
				st["phase"] = 3
				st["t"] = 0
			return false
		var g := clampf(1.0 - float(t) / float(_MOONLIGHT_FADE_STEPS),
				0.0, 1.0)
		for n in nodes:
			_apply_blend_amount(n, _MOONLIGHT_FADE_COLOR, g)
		if t >= _MOONLIGHT_FADE_STEPS:
			for n in nodes:
				_clear_blend(n)
			return true
		return false)


# AnimTask_AlphaFadeIn (battle_anim_mons.c:1613). args: 0/1 starting eva/evb,
# 2/3 target eva/evb, 4 step delay.
#
# THE TWO COEFFICIENTS MOVE ALTERNATELY, NOT TOGETHER. `data[2]` is a parity
# counter: odd ticks advance eva, even ticks advance evb, so a 0..16 ramp
# takes 32 ticks rather than 16 and the two are never more than one step out
# of phase. Moving them together halves the duration and changes the curve
# in the middle of the blend, where it is most visible.
static func _alpha_fade_in(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var from_a: int = vm.args[0]
	var from_b: int = vm.args[1]
	var to_a: int = vm.args[2]
	var to_b: int = vm.args[3]
	var delay: int = maxi(0, vm.args[4])
	var step_a: int = signi(to_a - from_a)
	var step_b: int = signi(to_b - from_b)
	var st := {"t": 0, "parity": 0, "a": from_a, "b": from_b}
	vm.set_blend_context(from_a, from_b)
	vm.add_stepper(func() -> bool:
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) <= delay:
			return false
		st["t"] = 0
		st["parity"] = int(st["parity"]) + 1
		if int(st["parity"]) % 2 == 1:
			if int(st["a"]) != to_a:
				st["a"] = int(st["a"]) + step_a
		else:
			if int(st["b"]) != to_b:
				st["b"] = int(st["b"]) + step_b
		vm.set_blend_context(int(st["a"]), int(st["b"]))
		return int(st["a"]) == to_a and int(st["b"]) == to_b)


# AnimTask_InitAttackerFadeFromInvisible (battle_anim_dark.c:349). No args:
# it only arms the blend registers and ends the same frame. The BG-priority
# branch picks which layer is blended, which this port has no equivalent for
# -- so the arming is what carries over, and the ramp is its partner below.
static func _init_attacker_fade_from_invisible(vm: AnimScriptVM,
		_ctx: Dictionary) -> void:
	var atk := _battler_node(vm, AnimStage.ANIM_ATTACKER)
	if atk == null:
		return
	vm.set_battler_visible_tracked(AnimStage.ANIM_ATTACKER, true)
	_apply_blend_amount(atk, Color(1, 1, 1), 1.0)


# AnimTask_AttackerFadeFromInvisible (battle_anim_dark.c:315). args:
# 0 step delay. The exact inverse of batch 20's fade-TO-invisible, and it
# ends by clearing the blend rather than hiding the battler -- so a script
# that faded the attacker out earlier gets it back solid.
static func _attacker_fade_from_invisible(vm: AnimScriptVM,
		_ctx: Dictionary) -> void:
	var atk := _battler_node(vm, AnimStage.ANIM_ATTACKER)
	if atk == null:
		return
	vm.set_battler_visible_tracked(AnimStage.ANIM_ATTACKER, true)
	var delay: int = maxi(0, vm.args[0])
	var st := {"t": 0, "evb": 16}
	_apply_blend_amount(atk, Color(1, 1, 1), 1.0)
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(atk):
			return true
		if int(st["t"]) < delay:
			st["t"] = int(st["t"]) + 1
			return false
		st["t"] = 0
		st["evb"] = int(st["evb"]) - 1
		_apply_blend_amount(atk, Color(1, 1, 1),
				clampf(float(st["evb"]) / 16.0, 0.0, 1.0))
		if int(st["evb"]) <= 0:
			_clear_blend(atk)
			return true
		return false)


# AnimSkyAttackBird (battle_anim_flying.c:1188). No args.
#
# The bird is created at the TARGET (createsprite's default position), then
# TELEPORTED to the attacker and given a velocity derived from where it just
# was -- so the sprite's own spawn point is the aiming input, not an arg.
#
# It does NOT stop at the target. The velocity is (target - attacker) / 12
# per frame and nothing decrements a counter: the bird reaches the target on
# frame 12 and keeps going until it leaves the screen. Stopping on arrival
# reads as the bird landing rather than swooping through.
const _SKY_BIRD_FRAMES := 12
const _SKY_BIRD_ROTATION_OFFSET := -16384


static func _sky_attack_bird(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var aim := _battler_centre(vm, AnimStage.ANIM_TARGET)
	var start := _battler_centre(vm, AnimStage.ANIM_ATTACKER)
	node.centre = start
	var per_frame := (aim - start) / float(_SKY_BIRD_FRAMES)
	node.rotation = (aim - start).angle() \
			+ _gba_rot_to_radians(_SKY_BIRD_ROTATION_OFFSET)
	var bounds := Vector2(1024.0, 768.0)
	if vm.stage != null and vm.stage.has_method("layer"):
		var l: Control = vm.stage.layer()
		if l != null:
			bounds = l.size
	var margin := 45.0 * _scale(vm)
	var st := {"t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["t"] = int(st["t"]) + 1
		node.centre = start + per_frame * float(st["t"])
		if node.centre.x > bounds.x + margin or node.centre.x < -margin \
				or node.centre.y > bounds.y + margin \
				or node.centre.y < -margin:
			node.finish()
			return true
		return false)


# ══ [M36D batch 27] ═══════════════════════════════════════════════════════
#
# The Gen 1 long tail plus Conversion. Two of the eleven entries are ALIASES
# of behaviors already ported -- upstream duplicated the function rather than
# calling it -- and one pair is the first real consumer of the arg-7 channel
# batch 24 restored in the VM.
#
# DEFERRED, and the reason is the same one batch 26 gave for the spotlight:
# `AnimTask_RapinSpinMonElevation` is a SCANLINE effect. It writes
# `gScanlineEffectRegBuffers` and hands `REG_BG1HOFS`/`REG_BG2HOFS` to a
# per-scanline DMA -- it never touches the mon sprite at all, despite the
# name; the "elevation" is a horizontal shear of the BACKGROUND in a band
# around the mon. Same surface as FakeOut / MementoShadow / Spotlight.
# `AnimRapidSpin` is deliberately deferred WITH it rather than ported alone:
# every move that needs the spin sprite also needs the elevation, so porting
# it by itself would add code no move can reach and no coverage test can
# exercise.


# AnimTask_GrowAndShrink (battle_anim_effects_2.c). No args -- always the
# attacker. Reuses batch 25's affine walk: grow over 12 frames, hold 24,
# shrink back over 12. Sums to identity, like every table in that family.
const _GROW_SHRINK_AFFINE := [[-4, -5, 0, 12], [0, 0, 0, 24], [4, 5, 0, 12]]


static func _grow_and_shrink(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	_run_affine_cmds(vm, _battler_node(vm, AnimStage.ANIM_ATTACKER),
			_GROW_SHRINK_AFFINE, Callable(), AnimStage.ANIM_ATTACKER)


# AnimConversion (battle_anim_effects_1.c:6143). args: 0/1 offset.
#
# It has NO lifetime of its own. It parks at the offset and then polls
# `gBattleAnimArgs[7]` every frame, dying only when another task writes
# 0xFFFF there -- source even carries a `// TODO: gBattleAnimArgs[ARG_RET_ID]?`
# comment at both ends, the upstream authors noticing the same channel.
#
# This is the first behavior in the port that could not have worked before
# batch 24: `_load_args` used to clear arg 7 on every command, so the signal
# could never survive the createsprite that follows it.
const _CONVERSION_KILL := 0xFFFF


static func _conversion(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	node.centre = _positioned_centre(vm, AnimStage.ANIM_ATTACKER, vm.args[0],
			vm.args[1], _scale(vm))
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		if (vm.args[ARG_RET_ID] & 0xFFFF) == _CONVERSION_KILL:
			node.finish()
			return true
		return false)


# AnimTask_ConversionAlphaBlend (battle_anim_effects_1.c). No args.
# A 16-step alpha ramp at one step every 4 frames (64 frames), and only THEN
# the kill signal -- so the squares fade out with the blend and vanish once
# it has finished, rather than popping mid-fade.
const _CONVERSION_BLEND_STEPS := 16
const _CONVERSION_BLEND_DELAY := 4


static func _conversion_alpha_blend(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var st := {"t": 0, "step": 0, "signalled": false}
	vm.add_stepper(func() -> bool:
		if bool(st["signalled"]):
			return true
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) < _CONVERSION_BLEND_DELAY:
			return false
		st["t"] = 0
		st["step"] = int(st["step"]) + 1
		vm.set_blend_context(_CONVERSION_BLEND_STEPS - int(st["step"]),
				int(st["step"]))
		if int(st["step"]) >= _CONVERSION_BLEND_STEPS:
			# The signal, written only once the ramp is complete.
			vm.args[ARG_RET_ID] = _CONVERSION_KILL
			st["signalled"] = true
		return false)


# AnimBreathPuff (battle_anim_effects_2.c:2202). No args.
# 52 frames drifting AWAY from the attacker's own side at a quarter pixel per
# frame -- 64/256 in the fixed-point translator -- with the sprite's frame
# variant picked by side as well, so the puff faces the way it travels.
const _BREATH_PUFF_FRAMES := 52
const _BREATH_PUFF_START := 32.0
const _BREATH_PUFF_SPEED := 64.0 / 256.0


static func _breath_puff(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var player := _is_player_side(vm)
	_apply_anim_variant(node, ctx, 0 if player else 1)
	var scale := _scale(vm)
	var dir: float = 1.0 if player else -1.0
	var start := _battler_centre(vm, AnimStage.ANIM_ATTACKER) \
			+ Vector2(_BREATH_PUFF_START * dir * scale, 0.0)
	node.centre = start
	var per_frame := Vector2(_BREATH_PUFF_SPEED * dir * scale, 0.0)
	var st := {"t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var t: int = int(st["t"]) + 1
		st["t"] = t
		if t >= _BREATH_PUFF_FRAMES:
			node.finish()
			return true
		node.centre = start + per_frame * float(t)
		return false)


# AnimSuperFang (battle_anim_effects_1.c:6856). No args, no motion: it is
# created where createsprite put it (the target) and lives exactly as long
# as its own cel animation. The whole behavior is its lifetime.
static func _super_fang(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	node.centre = _battler_centre(vm, AnimStage.ANIM_TARGET)
	_play_until_anim_ends(vm, node, _ANIM_END_CAP)


# AnimTriAttackTriangle (battle_anim_effects_3.c:2095). args: 0/1 offset.
#
# Three beats, and the middle one is easy to miss: it FLICKERS on alternate
# frames for the first 30, then holds SOLID from 31 to 60 (the `data[0] > 30`
# line overrides the parity check rather than sitting beside it), and only at
# frame 61 does it launch at the target over 20 frames. A port that flickered
# the whole time, or launched immediately, still looks busy.
const _TRI_FLICKER_UNTIL := 30
const _TRI_LAUNCH_AT := 61
const _TRI_TRAVEL := 20


static func _tri_attack_triangle(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var start := _positioned_centre(vm, AnimStage.ANIM_ATTACKER, vm.args[0],
			vm.args[1], scale)
	node.centre = start
	var finish_pos := _battler_centre(vm, AnimStage.ANIM_TARGET)
	var st := {"t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var t: int = int(st["t"]) + 1
		st["t"] = t
		if t <= _TRI_FLICKER_UNTIL:
			node.visible = (t % 2) == 1
			return false
		node.visible = true
		if t < _TRI_LAUNCH_AT:
			return false
		var travelled: int = t - _TRI_LAUNCH_AT
		if travelled >= _TRI_TRAVEL:
			node.finish()
			return true
		node.centre = start.lerp(finish_pos,
				float(travelled) / float(_TRI_TRAVEL))
		return false)


# AnimSharpenSphere (battle_anim_effects_1.c:6106). No args.
#
# A blink whose PERIOD GROWS: `data[1]` starts at 2 and increments after
# every second toggle, so the sphere strobes quickly and then slows to a
# stop, ending once the period passes 16. A fixed-rate blink is the obvious
# misreading and gives a sphere that never settles.
const _SHARPEN_START_PERIOD := 2
const _SHARPEN_END_PERIOD := 16


static func _sharpen_sphere(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	node.centre = _battler_centre(vm, AnimStage.ANIM_ATTACKER) \
			+ Vector2(0.0, -12.0 * _scale(vm))
	var st := {"t": 0, "period": _SHARPEN_START_PERIOD, "toggles": 0,
			"vis": true}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) < int(st["period"]):
			return false
		st["t"] = 0
		st["vis"] = not bool(st["vis"])
		node.visible = bool(st["vis"])
		st["toggles"] = int(st["toggles"]) + 1
		if int(st["toggles"]) > 1:
			st["toggles"] = 0
			st["period"] = int(st["period"]) + 1
		if int(st["period"]) > _SHARPEN_END_PERIOD and not bool(st["vis"]):
			node.visible = true
			node.finish()
			return true
		return false)


# AnimStealthRock (battle_anim_rock.c:332). args: 0/1 start offset,
# 2/3 destination offset, 4 duration.
#
# Arcs onto the target SIDE's midpoint (SetAverageBattlerPositions, which is
# batch 23's `_side_centre`) with a hardcoded -50 amplitude, holds 30 frames
# where it lands, then BLINKS 8 times over 16 frames before vanishing --
# the settling flicker that makes it read as a hazard being set rather than
# a rock simply arriving.
const _STEALTH_ROCK_ARC := -50.0
const _STEALTH_ROCK_HOLD := 30
const _STEALTH_ROCK_BLINK := 16


static func _stealth_rock(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var start := _positioned_centre(vm, AnimStage.ANIM_ATTACKER, vm.args[0],
			vm.args[1], scale)
	var aim := _side_centre(vm, AnimStage.ANIM_TARGET,
			AnimStage.ANIM_DEF_PARTNER)
	var finish_pos := aim + Vector2(float(vm.args[2]) * _facing(vm),
			float(vm.args[3])) * scale
	node.centre = start
	var duration: int = maxi(1, vm.args[4])
	var st := {"t": 0, "phase": 0, "vis": true}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var t: int = int(st["t"]) + 1
		st["t"] = t
		var phase: int = int(st["phase"])
		if phase == 0:
			if t >= duration:
				node.centre = finish_pos
				st["phase"] = 1
				st["t"] = 0
				return false
			var f := float(t) / float(duration)
			node.centre = start.lerp(finish_pos, f) \
					+ Vector2(0.0, _gba_sin(f * 128.0,
							_STEALTH_ROCK_ARC * scale))
			return false
		if phase == 1:
			if t >= _STEALTH_ROCK_HOLD:
				st["phase"] = 2
				st["t"] = 0
			return false
		if t % 2 == 1:
			st["vis"] = not bool(st["vis"])
			node.visible = bool(st["vis"])
		if t >= _STEALTH_ROCK_BLINK:
			node.visible = true
			node.finish()
			return true
		return false)


# AnimSuckerPunch (battle_anim_poison.c:453) -- and AnimGrassKnot
# (battle_anim_effects_1.c:2899), which is a VERBATIM duplicate of it: same
# body, same args, same step function line for line, differing only in the
# name. Registered as an alias, like batch 24's gunk-shot particles.
#
# args: 0/1 start offset from the TARGET, 2 x travel, 3 duration,
# 4 sine step, 5 sine amplitude.
#
# THE SINE IS INERT AT EVERY REAL CALL SITE. Both scripts pass
# amplitude 0 -- `-18, 5, 40, 8, 160, 0` and `-18, 19, 40, 8, 160, 0` --
# so the sprite slides flat and the wave never happens. The term is
# ported anyway because it is real code and a future caller could use
# it, but reading the Sin() call as "therefore it waves" is the
# mistake: the args decide, and a first draft of the test asserted a
# wave that does not exist.
static func _sucker_punch(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var start := _positioned_centre(vm, AnimStage.ANIM_TARGET, vm.args[0],
			vm.args[1], scale)
	node.centre = start
	var travel := Vector2(float(vm.args[2]) * _facing(vm), 0.0) * scale
	var duration: int = maxi(1, vm.args[3])
	var amplitude: float = float(vm.args[5]) * scale
	var st := {"t": 0, "phase": 0.0}
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
		st["phase"] = float(st["phase"]) + float(vm.args[4])
		node.centre = start + travel * f \
				+ Vector2(0.0, _gba_sin(float(st["phase"]) / 256.0, amplitude))
		return false)


# ══ [M36D batch 28] ═══════════════════════════════════════════════════════
#
# The mon-deformation family: every remaining task whose whole job is to
# scale, rotate, squash or clone a battler. Most are an affine table plus
# batch 25's shared walk; the rest are hand-rolled rot/scale.
#
# TWO DEFERRED, both the same surface as batch 26's spotlight and batch 27's
# Rapid Spin:
#   * `AnimTask_AcidArmor` writes `gScanlineEffectRegBuffers` and hands
#     REG_BG1HOFS/REG_BG2HOFS to a per-scanline DMA -- the mon appearing to
#     melt is a shear of the BACKGROUND, not a transform of the sprite.
#   * `AnimTask_TransformMon` drives REG_OFFSET_MOSAIC and then calls
#     HandleSpeciesGfxDataChange to swap the battler's actual sprite sheet.
#     Mosaic is a hardware surface this port does not have, and the sheet
#     swap needs species graphics the anim layer cannot reach.
#
# ONE DISCLOSED SIMPLIFICATION, and it is the highest-value thing on this
# batch for a screenshot pass: upstream calls SetBattlerSpriteYOffsetFromYScale
# after every affine step, which nudges y2 so a scaling mon keeps its FEET
# planted rather than growing about its centre. This port scales about the
# node's own pivot. It is not ported because CLAUDE.md records a
# bottom-centre `pivot_offset` being tried during M26B3-6a and REVERTED for
# looking worse, and this session cannot check a visual change against that.
# Flagged rather than guessed at.


# gShrinkAndGrowAffineAnimCmds (battle_anim_effects_2.c:498) -- and note this
# one does NOT sum to identity: +48/+60 out, then only -24/-30 back, because
# the return leg runs 6 frames where the outward leg ran 12. That is safe
# only because AFFINEANIMCMDTYPE_END resets the sprite regardless, which is
# also why the sum assertions elsewhere are transcription guards rather than
# leak guards.
const _SHRINK_GROW_AFFINE := [[4, 5, 0, 12], [0, 0, 0, 24], [-4, -5, 0, 6]]
const _MEDITATE_STRETCH_AFFINE := [[-8, 10, 0, 16], [18, -18, 0, 16],
		[-20, 16, 0, 8]]
const _SLACK_OFF_AFFINE := [[0, 16, 0, 4], [-2, 0, 0, 8], [0, 4, 0, 4],
		[0, 0, 0, 24], [1, -5, 0, 16]]
const _COMPRESS_AFFINE := [[64, 0, 0, 16], [0, 0, 0, 64], [-64, 0, 0, 16]]
const _COMPRESS_FAST_AFFINE := [[32, 0, 0, 16], [0, 0, 0, 32], [-32, 0, 0, 16]]
const _FACADE_SQUISH_AFFINE := [[-16, 16, 0, 6], [16, -16, 0, 12],
		[-16, 16, 0, 6]]


static func _shrink_and_grow(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	_run_affine_cmds(vm, _battler_node(vm, AnimStage.ANIM_ATTACKER),
			_SHRINK_GROW_AFFINE, Callable(), AnimStage.ANIM_ATTACKER)


static func _meditate_stretch_attacker(vm: AnimScriptVM,
		_ctx: Dictionary) -> void:
	_run_affine_cmds(vm, _battler_node(vm, AnimStage.ANIM_ATTACKER),
			_MEDITATE_STRETCH_AFFINE, Callable(), AnimStage.ANIM_ATTACKER)


# args: 0 battler.
static func _slack_off_squish(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	_run_affine_cmds(vm, _battler_node(vm, vm.args[0]), _SLACK_OFF_AFFINE,
			Callable(), vm.args[0])


# The pair differ ONLY in their table -- half the compression over half the
# hold. Sharing one implementation keeps that the only difference.
static func _compress_target_horizontally(vm: AnimScriptVM,
		_ctx: Dictionary) -> void:
	_run_affine_cmds(vm, _battler_node(vm, AnimStage.ANIM_TARGET),
			_COMPRESS_AFFINE, Callable(), AnimStage.ANIM_TARGET)


static func _compress_target_horizontally_fast(vm: AnimScriptVM,
		_ctx: Dictionary) -> void:
	_run_affine_cmds(vm, _battler_node(vm, AnimStage.ANIM_TARGET),
			_COMPRESS_FAST_AFFINE, Callable(), AnimStage.ANIM_TARGET)


# AnimTask_SquishAndSweatDroplets (battle_anim_effects_3.c). args: 0 battler,
# 1 squish count. Runs the squish table `count` times back to back, spawning
# two rounds of droplets inside EACH pass (frames 6 and 18). A count of 0
# ends immediately -- upstream destroys the task before doing anything, so
# the arg is a real gate rather than a minimum.
static func _squish_and_sweat_droplets(vm: AnimScriptVM,
		_ctx: Dictionary) -> void:
	var node := _battler_node(vm, vm.args[0])
	var count: int = vm.args[1]
	if node == null or count <= 0:
		return
	var tables: Array = []
	for i in range(count):
		for cmd in _FACADE_SQUISH_AFFINE:
			tables.append(cmd)
	_run_affine_cmds(vm, node, tables, Callable(), vm.args[0])


# AnimTask_GrowAndGrayscale (battle_anim_effects_2.c) and AnimTask_GrowTarget
# share a shape: snap the TARGET to a fixed scale, hold, then reset. The
# scale is set ONCE and never animated -- there is no ramp, which is what
# makes the mon appear to jump in size rather than swell.
#
# 0xD0 = 208 in GBA affine units, and under the INVERTED rule that is a
# GROWTH to 256/208 = 1.23x. Reading 208 as a direct multiplier shrinks it.
const _GROW_GRAYSCALE_SCALE := 208.0
const _GROW_GRAYSCALE_FRAMES := 80
const _GROW_TARGET_FRAMES := 120


static func _grow_and_grayscale(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	_hold_scaled_target(vm, _GROW_GRAYSCALE_FRAMES, true)


static func _grow_target(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	_hold_scaled_target(vm, _GROW_TARGET_FRAMES, false)


static func _hold_scaled_target(vm: AnimScriptVM, frames: int,
		grayscale: bool) -> void:
	var node := _battler_node(vm, AnimStage.ANIM_TARGET)
	if node == null:
		return
	var deform := MonScale.new(node)
	var mul := _GBA_AFFINE_IDENTITY / _GROW_GRAYSCALE_SCALE
	deform.apply(Vector2(mul, mul))
	var base_modulate: Color = node.modulate
	if grayscale:
		node.modulate = Color(0.6, 0.6, 0.6, base_modulate.a)
	var st := {"t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) < frames:
			return false
		deform.restore()
		if grayscale:
			node.modulate = base_modulate
		return true)


# AnimTask_Withdraw (battle_anim_effects_2.c). No args. The attacker rocks
# by rotation -- NOT by moving -- accumulating 0xB0 per frame, and the
# direction is MIRRORED by side so both sides tuck the same way relative to
# the screen. Then it holds 30 frames and unwinds.
const _WITHDRAW_ROT_STEP := 0xB0
const _WITHDRAW_HOLD := 30
const _WITHDRAW_OUT_FRAMES := 12


static func _withdraw(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var node := _battler_node(vm, AnimStage.ANIM_ATTACKER)
	if node == null:
		return
	var deform := MonScale.new(node)
	var sign := -1.0 if _is_player_side(vm) else 1.0
	var st := {"t": 0, "phase": 0, "rot": 0.0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		var phase: int = int(st["phase"])
		st["t"] = int(st["t"]) + 1
		if phase == 0:
			st["rot"] = float(st["rot"]) + float(_WITHDRAW_ROT_STEP)
			deform.apply(Vector2.ONE,
					_gba_rot_to_radians(int(float(st["rot"]) * sign)))
			if int(st["t"]) >= _WITHDRAW_OUT_FRAMES:
				st["phase"] = 1
				st["t"] = 0
			return false
		if phase == 1:
			if int(st["t"]) >= _WITHDRAW_HOLD:
				st["phase"] = 2
				st["t"] = 0
			return false
		st["rot"] = maxf(0.0, float(st["rot"]) - float(_WITHDRAW_ROT_STEP))
		deform.apply(Vector2.ONE,
				_gba_rot_to_radians(int(float(st["rot"]) * sign)))
		if float(st["rot"]) <= 0.0:
			deform.restore()
			return true
		return false)


# AnimTask_RotateVertically (battle_anim_effects_3.c). args: 0 battler,
# 1 rotation speed.
#
# THE TWO SIDES ROTATE DIFFERENT AMOUNTS, and it is not a mirror: the player
# side stops at 0x1FFF (~45 degrees) while the opponent side goes to 0x7FFE
# (~180, fully upside down). Reading it as one shared limit gives a player
# mon that flips over when it should only tilt.
const _ROTATE_VERT_PLAYER_MAX := 0x1FFF
const _ROTATE_VERT_FOE_MAX := 0x7FFE
const _ROTATE_VERT_HOLD := 75


static func _rotate_vertically(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var node := _battler_node(vm, vm.args[0])
	if node == null:
		return
	var deform := MonScale.new(node)
	var player := _is_player_side(vm)
	var limit: int = _ROTATE_VERT_PLAYER_MAX if player else _ROTATE_VERT_FOE_MAX
	var speed: int = maxi(1, absi(vm.args[1]))
	var st := {"rot": 0, "phase": 0, "t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		var phase: int = int(st["phase"])
		if phase == 0:
			st["rot"] = mini(int(st["rot"]) + speed, limit)
			deform.apply(Vector2.ONE, _gba_rot_to_radians(int(st["rot"])))
			if int(st["rot"]) >= limit:
				st["phase"] = 1
			return false
		if phase == 1:
			st["t"] = int(st["t"]) + 1
			if int(st["t"]) >= _ROTATE_VERT_HOLD:
				st["phase"] = 2
			return false
		st["rot"] = maxi(0, int(st["rot"]) - speed)
		deform.apply(Vector2.ONE, _gba_rot_to_radians(int(st["rot"])))
		if int(st["rot"]) <= 0:
			deform.restore()
			return true
		return false)


# AnimTask_DuckDownHop (battle_anim_effects_3.c). args: 0 battler,
# 1 x distance, 2 unused-here, 3 duck frames, 4 unused-here, 5 hop height,
# 6 hop frames.
#
# arg 1 is side-mirrored, and both legs are FIXED-POINT rates rather than
# distances: `(args[1] << 8) / args[3]` is a per-frame step in 8.8, so the
# distance and the duration are separate inputs that multiply out.
static func _duck_down_hop(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var node := _battler_node(vm, vm.args[0])
	if node == null:
		return
	var scale := _scale(vm)
	var shift := MonOffset.new(node)
	var duck_frames: int = maxi(1, vm.args[3])
	var hop_frames: int = maxi(1, vm.args[6])
	var dx: float = float(vm.args[1]) * (1.0 if _is_player_side(vm) else -1.0)
	var per_x := dx / float(duck_frames) * scale
	var per_y := float(vm.args[5]) / float(hop_frames) * scale
	var st := {"t": 0, "phase": 0, "x": 0.0, "y": 0.0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		st["t"] = int(st["t"]) + 1
		if int(st["phase"]) == 0:
			st["y"] = float(st["y"]) + per_y
			shift.apply(Vector2(float(st["x"]), float(st["y"])))
			if int(st["t"]) >= hop_frames:
				st["phase"] = 1
				st["t"] = 0
			return false
		st["x"] = float(st["x"]) + per_x
		shift.apply(Vector2(float(st["x"]), float(st["y"])))
		if int(st["t"]) >= duck_frames:
			shift.apply(Vector2.ZERO)
			return true
		return false)


# AnimTask_Minimize (battle_anim_effects_2.c) and AnimTask_DoubleTeam
# (battle_anim_effects_1.c) both leave AFTERIMAGES of the battler, and both
# reuse `_clone_battler_visual`.
#
# They are NOT the same effect, and the difference is the point: Minimize
# SHRINKS the mon (0x28 = 40 added to the affine scale each frame, so under
# the inverted rule it gets smaller) while dropping clones at fixed beats;
# Double Team leaves the mon alone and sends its clones SWEEPING sideways on
# a sine whose amplitude decays from the same table index that ends them.
const _MINIMIZE_SCALE_STEP := 40.0
const _MINIMIZE_FRAMES := 32
const _MINIMIZE_CLONE_AT := [0, 3, 6]
const _DOUBLE_TEAM_CLONES := 2
const _DOUBLE_TEAM_LIFE := 64


static func _minimize(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var node := _battler_node(vm, AnimStage.ANIM_ATTACKER)
	var layer: Control = null
	if vm.stage != null and vm.stage.has_method("layer"):
		layer = vm.stage.layer()
	if node == null:
		return
	var deform := MonScale.new(node)
	var clones: Array[Control] = []
	var st := {"t": 0, "value": _GBA_AFFINE_IDENTITY}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		var t: int = int(st["t"])
		if _MINIMIZE_CLONE_AT.has(t) and layer != null:
			var c := _clone_battler_visual(node, layer)
			if c != null:
				clones.append(c)
		st["value"] = float(st["value"]) + _MINIMIZE_SCALE_STEP
		var mul := _GBA_AFFINE_IDENTITY / maxf(1.0, float(st["value"]))
		deform.apply(Vector2(mul, mul))
		st["t"] = t + 1
		if t + 1 < _MINIMIZE_FRAMES:
			return false
		deform.restore()
		for c in clones:
			if is_instance_valid(c):
				c.queue_free()
		return true)


static func _double_team(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var node := _battler_node(vm, AnimStage.ANIM_ATTACKER)
	var layer: Control = null
	if vm.stage != null and vm.stage.has_method("layer"):
		layer = vm.stage.layer()
	if node == null or layer == null:
		return
	var scale := _scale(vm)
	var clones: Array[Control] = []
	var phases: Array = []
	for i in range(_DOUBLE_TEAM_CLONES):
		var c := _clone_battler_visual(node, layer)
		if c != null:
			clones.append(c)
			# Upstream seeds each clone half a cycle apart (`i << 7`), which
			# is what sends them opposite ways rather than overlapping.
			phases.append(i << 7)
	if clones.is_empty():
		return
	var base: Array = []
	for c in clones:
		base.append(c.position)
	var st := {"counter": 0, "sub": 0}
	vm.add_stepper(func() -> bool:
		st["sub"] = int(st["sub"]) + 1
		if int(st["sub"]) > 1:
			st["sub"] = 0
			st["counter"] = int(st["counter"]) + 1
		var counter: int = int(st["counter"])
		if counter > _DOUBLE_TEAM_LIFE:
			for c in clones:
				if is_instance_valid(c):
					c.queue_free()
			return true
		# Both the amplitude AND the phase step are read from the same sine
		# index, so the sweep widens and slows together as the index climbs.
		var amplitude := _gba_sin(float(counter), 1.0) * 256.0 / 6.0
		var index_step := _gba_sin(float(counter), 1.0) * 256.0 / 13.0
		for i in range(clones.size()):
			if not is_instance_valid(clones[i]):
				continue
			phases[i] = (int(phases[i]) + int(index_step)) & 0xFF
			clones[i].position = (base[i] as Vector2) + Vector2(
					_gba_sin(float(phases[i]), amplitude * scale), 0.0)
		return false)


# ══ [M36D batch 29] ═══════════════════════════════════════════════════════
#
# The simple-sprite tail: one behavior per move, mostly a spawn point plus a
# short motion. Grouped because they share no machinery beyond what is
# already built -- which is itself the finding. At this depth the port is no
# longer retiring mechanisms, it is spending the ones batches 1-28 built.


# AnimTailGlowOrb (battle_anim_effects_1.c). args: 0 which battler.
# 18 px BELOW the mon's centre and alive only for its own animation.
const _TAIL_GLOW_DROP := 18


static func _tail_glow_orb(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var who: int = AnimStage.ANIM_ATTACKER if vm.args[0] == 0 \
			else AnimStage.ANIM_TARGET
	node.centre = _battler_centre(vm, who) \
			+ Vector2(0.0, float(_TAIL_GLOW_DROP) * _scale(vm))
	_play_until_anim_ends(vm, node, _ANIM_END_CAP)


# AnimLick (battle_anim_effects_2.c). No args: it sits on the TARGET and its
# whole lifetime is its own cel animation, replayed a few times.
static func _lick(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	node.centre = _battler_centre(vm, AnimStage.ANIM_TARGET)
	_play_until_anim_ends(vm, node, _ANIM_END_CAP)


# AnimStringWrap (battle_anim_effects_1.c). args: 0/1 offset.
# Anchored on the target SIDE's midpoint (SetAverageBattlerPositions), with
# an EXTRA 8 px drop when the target is on the player's side -- an asymmetry
# that is not a mirror of anything, it just nudges the wrap down over the
# nearer, larger-drawn sprite.
const _STRING_WRAP_PLAYER_DROP := 8


static func _string_wrap(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var at := _side_centre(vm, AnimStage.ANIM_TARGET,
			AnimStage.ANIM_DEF_PARTNER)
	at += Vector2(float(vm.args[0]) * _facing(vm), float(vm.args[1])) * scale
	# The target's own side, not the attacker's -- they differ whenever a
	# move targets an ally.
	if not _is_player_side(vm):
		at.y += float(_STRING_WRAP_PLAYER_DROP) * scale
	node.centre = at
	_play_until_anim_ends(vm, node, _ANIM_END_CAP)


# AnimSpitUpOrb (battle_anim_effects_3.c). args: 0 angle index, 1 lifetime.
# The angle is a GBA sine index, and the two axes use DIFFERENT amplitudes
# (10 and 7), so the spray is an ellipse rather than a circle -- wider than
# it is tall, which is what makes it read as coming out of a mouth.
const _SPIT_UP_X_AMP := 10.0
const _SPIT_UP_Y_AMP := 7.0


static func _spit_up_orb(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var start := _battler_centre(vm, AnimStage.ANIM_ATTACKER)
	node.centre = start
	var per_frame := Vector2(
			_gba_sin(float(vm.args[0]), _SPIT_UP_X_AMP),
			_gba_cos(float(vm.args[0]), _SPIT_UP_Y_AMP)) * scale
	var life: int = maxi(1, vm.args[1])
	var st := {"t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var t: int = int(st["t"]) + 1
		st["t"] = t
		node.centre = start + per_frame * float(t)
		if t >= life:
			node.finish()
			return true
		return false)


# AnimSwallowBlueOrb (battle_anim_effects_3.c). No args.
# A DECELERATING rise: the velocity starts at 0x900 and loses 96 every frame,
# so the orb slows, stops, and falls back -- and it is destroyed the moment
# it drops below the height it launched from, not on a timer.
const _SWALLOW_ORB_SPEED := 0x900 / 256.0
const _SWALLOW_ORB_DECEL := 96.0 / 256.0


static func _swallow_blue_orb(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var start := _battler_centre(vm, AnimStage.ANIM_ATTACKER)
	node.centre = start
	var st := {"v": _SWALLOW_ORB_SPEED, "y": 0.0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["y"] = float(st["y"]) - float(st["v"]) * scale
		st["v"] = float(st["v"]) - _SWALLOW_ORB_DECEL
		node.centre = start + Vector2(0.0, float(st["y"]))
		if float(st["y"]) > 0.0:
			node.finish()
			return true
		return false)


# AnimBonemerangProjectile (battle_anim_ground.c). No args: a fixed 20-frame
# arc of amplitude -40 from the attacker to the target, then it comes BACK --
# the return leg is what makes it a boomerang rather than a thrown bone.
const _BONEMERANG_FRAMES := 20
const _BONEMERANG_ARC := -40.0


static func _bonemerang_projectile(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var start := _battler_centre(vm, AnimStage.ANIM_ATTACKER)
	var away := _battler_centre(vm, AnimStage.ANIM_TARGET)
	node.centre = start
	var st := {"t": 0, "back": false}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var t: int = int(st["t"]) + 1
		st["t"] = t
		var f := float(t) / float(_BONEMERANG_FRAMES)
		if f >= 1.0:
			if bool(st["back"]):
				node.finish()
				return true
			st["back"] = true
			st["t"] = 0
			return false
		var a: Vector2 = away if not bool(st["back"]) else start
		var b: Vector2 = start if not bool(st["back"]) else away
		node.centre = b.lerp(a, f) + Vector2(0.0,
				_gba_sin(f * 128.0, _BONEMERANG_ARC * scale))
		return false)


# AnimLeechLifeNeedle (battle_anim_bug.c). args: 0/1 offset, 2 duration.
# It starts OUTSIDE the target and closes onto it, and BOTH offsets flip
# when the target is on the player's side -- not just the horizontal one, so
# the needles converge from above on one side and below on the other.
static func _leech_life_needle(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var flip: float = -1.0 if _is_player_side(vm) else 1.0
	var centre := _battler_centre(vm, AnimStage.ANIM_TARGET)
	var start := centre + Vector2(float(vm.args[0]) * flip,
			float(vm.args[1]) * flip) * scale
	node.centre = start
	_linear_travel(vm, node, start, centre, maxi(1, vm.args[2]))


# AnimPluck (battle_anim_effects_1.c). args: 0/1 offset, 2 lifetime,
# 3 upward velocity, 4 horizontal velocity. A plain ballistic particle off
# the target, with the two velocities supplied rather than derived.
static func _pluck(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var start := _positioned_centre(vm, AnimStage.ANIM_TARGET, vm.args[0],
			vm.args[1], scale)
	node.centre = start
	var life: int = maxi(1, vm.args[2])
	var per_frame := Vector2(float(vm.args[4]) * _facing(vm),
			float(vm.args[3])) * scale / 16.0
	var st := {"t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var t: int = int(st["t"]) + 1
		st["t"] = t
		node.centre = start + per_frame * float(t)
		if t >= life:
			node.finish()
			return true
		return false)


# AnimMeteorMashStar (battle_anim_effects_3.c). args: 0/1 start offset,
# 2/3 end offset, 4 duration.
#
# The X offsets are SUBTRACTED for a player-side target and ADDED for an
# opposing one, while the Y offsets are added either way -- so the stars
# always sweep inward across the screen regardless of which side is hit.
static func _meteor_mash_star(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var base := _battler_centre(vm, AnimStage.ANIM_TARGET)
	# `IsOnPlayerSide(gBattleAnimTarget)` -- the TARGET's side, which is the
	# opposite of the attacker's for any ordinary foe-targeting move.
	var sign: float = 1.0 if _is_player_side(vm) else -1.0
	var start := base + Vector2(float(vm.args[0]) * -sign,
			float(vm.args[1])) * scale
	var finish_pos := base + Vector2(float(vm.args[2]) * -sign,
			float(vm.args[3])) * scale
	node.centre = start
	_linear_travel(vm, node, start, finish_pos, maxi(1, vm.args[4]))


# AnimYawnCloud (battle_anim_effects_3.c). args: 0 affine variant.
# The cloud drifts from the ATTACKER toward wherever createsprite put it (the
# target) over 64 frames while bobbing, then BLINKS OUT over four toggles
# rather than simply vanishing.
const _YAWN_FRAMES := 64
const _YAWN_BOB := 8.0
const _YAWN_BLINK_FROM := 58


static func _yawn_cloud(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var start := _battler_centre(vm, AnimStage.ANIM_ATTACKER)
	var finish_pos := _battler_centre(vm, AnimStage.ANIM_TARGET)
	node.centre = start
	var st := {"t": 0, "blink": 0, "sub": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var t: int = int(st["t"]) + 1
		st["t"] = t
		var f := minf(1.0, float(t) / float(_YAWN_FRAMES))
		node.centre = start.lerp(finish_pos, f) + Vector2(0.0,
				_gba_sin(float((t * 8) % 256), _YAWN_BOB * scale))
		if t <= _YAWN_BLINK_FROM:
			return false
		st["sub"] = int(st["sub"]) + 1
		if int(st["sub"]) > 1:
			st["sub"] = 0
			st["blink"] = int(st["blink"]) + 1
			node.visible = (int(st["blink"]) & 1) == 0
			if int(st["blink"]) > 3:
				node.visible = true
				node.finish()
				return true
		return false)


# AnimWishStar (battle_anim_effects_3.c). No args.
# It enters from OFF-SCREEN on the side opposite the attacker and accelerates
# diagonally across -- both axes accelerate, x by 72/16 per frame and y by
# 16/256, so it starts almost horizontal and steepens.
const _WISH_STAR_X_ACCEL := 72.0 / 16.0
const _WISH_STAR_Y_ACCEL := 16.0 / 256.0
const _WISH_STAR_MARGIN := 16.0


static func _wish_star(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var bounds := Vector2(240.0, 160.0) * scale
	if vm.stage != null and vm.stage.has_method("layer"):
		var l: Control = vm.stage.layer()
		if l != null:
			bounds = l.size
	var player := _is_player_side(vm)
	# Enters from the LEFT for an opposing attacker, the RIGHT for a player
	# one -- so the wish always crosses toward the caster's own half.
	var start := Vector2(-_WISH_STAR_MARGIN * scale, 0.0) if not player \
			else Vector2(bounds.x + _WISH_STAR_MARGIN * scale, 0.0)
	var dir: float = 1.0 if not player else -1.0
	node.centre = start
	var st := {"vx": 0.0, "vy": 0.0, "x": 0.0, "y": 0.0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["vx"] = float(st["vx"]) + _WISH_STAR_X_ACCEL * scale
		st["vy"] = float(st["vy"]) + _WISH_STAR_Y_ACCEL * scale
		st["x"] = float(st["x"]) + float(st["vx"]) * dir
		st["y"] = float(st["y"]) + float(st["vy"])
		node.centre = start + Vector2(float(st["x"]), float(st["y"]))
		if node.centre.y > bounds.y or absf(float(st["x"])) > bounds.x * 1.5:
			node.finish()
			return true
		return false)


# AnimAngel (battle_anim_effects_2.c). args: 0/1 offset.
# A 100-frame rise on a Sin/Cos pair of the SAME amplitude 80 -- so the path
# is a circle, not an ellipse -- with a steady downward drift added on top
# for the first 80 frames, and a sideways slide-off after frame 90.
const _ANGEL_FRAMES := 100
const _ANGEL_RADIUS := 80.0
const _ANGEL_DRIFT_UNTIL := 80
const _ANGEL_SLIDE_FROM := 90


static func _angel(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var start := _positioned_centre(vm, AnimStage.ANIM_ATTACKER, vm.args[0],
			vm.args[1], scale)
	node.centre = start
	var st := {"t": 0, "slide": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var t: int = int(st["t"]) + 1
		st["t"] = t
		var index := float((t * 10) % 256)
		var off := Vector2(_gba_sin(index, _ANGEL_RADIUS) / 256.0 * scale, 0.0)
		if t < _ANGEL_DRIFT_UNTIL:
			off.y = (float(t) / 2.0
					+ _gba_cos(index, _ANGEL_RADIUS) / 256.0) * scale
		if t > _ANGEL_SLIDE_FROM:
			st["slide"] = int(st["slide"]) + 1
			off.x -= float(st["slide"]) / 2.0 * scale
		node.centre = start + off
		if t > _ANGEL_FRAMES:
			node.finish()
			return true
		return false)


# AnimPinkHeart (battle_anim_effects_1.c). args: 0 x drift (8.8), 1 wave
# amplitude. Drifts sideways while bobbing until its sine index passes 70,
# then commits its offsets into its position and drifts on from there --
# the hand-off is what stops the bob resetting the heart's path.
const _PINK_HEART_PHASE_STEP := 3
const _PINK_HEART_HANDOFF := 70


static func _pink_heart(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var start := _battler_centre(vm, AnimStage.ANIM_TARGET)
	node.centre = start
	var drift: float = float(vm.args[0]) / 256.0 * scale
	var amplitude: float = float(vm.args[1]) * scale
	var st := {"x": 0.0, "phase": 0, "t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["t"] = int(st["t"]) + 1
		st["x"] = float(st["x"]) + drift
		st["phase"] = (int(st["phase"]) + _PINK_HEART_PHASE_STEP) & 0xFF
		node.centre = start + Vector2(float(st["x"]),
				_gba_sin(float(st["phase"]), amplitude))
		if int(st["phase"]) > _PINK_HEART_HANDOFF \
				or int(st["t"]) > _ANIM_END_CAP:
			node.finish()
			return true
		return false)


# AnimSoftBoiledEgg (battle_anim_effects_1.c). args: 2 arc height.
# The horizontal speed is a fixed +-160 by side and the vertical starts at
# 0x380 -- the egg is lobbed, not aimed, so it goes the same distance
# regardless of where the target is.
const _SOFT_BOILED_SPEED := 160.0 / 256.0
const _SOFT_BOILED_RISE := 0x380 / 256.0
const _SOFT_BOILED_GRAVITY := 0.35


static func _soft_boiled_egg(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var start := _battler_centre(vm, AnimStage.ANIM_ATTACKER)
	node.centre = start
	var dir: float = 1.0 if _is_player_side(vm) else -1.0
	var st := {"x": 0.0, "y": 0.0, "v": -_SOFT_BOILED_RISE, "t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["t"] = int(st["t"]) + 1
		st["x"] = float(st["x"]) + _SOFT_BOILED_SPEED * dir * scale
		st["y"] = float(st["y"]) + float(st["v"]) * scale
		st["v"] = float(st["v"]) + _SOFT_BOILED_GRAVITY
		node.centre = start + Vector2(float(st["x"]), float(st["y"]))
		if float(st["y"]) > 0.0 and float(st["v"]) > 0.0:
			node.finish()
			return true
		if int(st["t"]) > _ANIM_END_CAP:
			node.finish()
			return true
		return false)


# AnimMilkBottle (battle_anim_effects_1.c) and AnimMeanLookEye
# (battle_anim_effects_2.c) both open by arming BLDALPHA to (0,16) -- fully
# transparent -- and fade themselves in. Neither takes a position arg:
# the bottle sits above the TARGET, the eye where createsprite put it.
const _MILK_BOTTLE_RISE := -24


static func _milk_bottle(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	node.centre = _battler_centre(vm, AnimStage.ANIM_TARGET) \
			+ Vector2(0.0, float(_MILK_BOTTLE_RISE) * _scale(vm))
	_fade_in_then_hold(vm, node)


static func _mean_look_eye(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	node.centre = _battler_centre(vm, AnimStage.ANIM_TARGET)
	_fade_in_then_hold(vm, node)


# Shared by the two above: 16 alpha steps in, then the sprite's own cel
# animation carries it to its end.
const _FADE_IN_STEPS := 16


static func _fade_in_then_hold(vm: AnimScriptVM, node: AnimSprite) -> void:
	var st := {"t": 0, "eva": 0}
	node.modulate = Color(1, 1, 1, 0)
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["t"] = int(st["t"]) + 1
		if int(st["eva"]) < _FADE_IN_STEPS:
			st["eva"] = int(st["eva"]) + 1
			node.modulate = Color(1, 1, 1,
					float(st["eva"]) / float(_FADE_IN_STEPS))
			return false
		if node.anim_ended() or int(st["t"]) >= _ANIM_END_CAP:
			node.finish()
			return true
		return false)


# ══ [M36D batch 30] ═══════════════════════════════════════════════════════
#
# The query tasks, plus the last of the misc sprite tail.
#
# THE FINDING OF THIS BATCH IS WHICH REGISTER THEY ANSWER ON. Most write
# `gBattleAnimArgs[ARG_RET_ID]` (7) -- the channel batch 24 taught the VM to
# preserve. But `AnimTask_IsTargetPartner` and `AnimTask_GetLycanrocForm`
# write **arg 0** instead, and that is not a mistake upstream: both are read
# by a `jumpargeq 0 ...` on the very next line, and `jumpargeq` does not
# reload the arg registers. They work precisely because nothing intervenes.
# Writing them to arg 7 "for consistency" would break their consumers, and
# writing every other one to arg 0 would break the moment a createsprite
# came between the task and its jump.


# args: none. A coin flip the script branches on.
static func _random_bool(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	vm.args[ARG_RET_ID] = 1 if randf() < 0.5 else 0


# args: none. TRUE only on the strike turn -- Doom Desire's first two turns
# are the charge, the third is the hit.
const _DOOM_DESIRE_HIT_TURN := 2


static func _get_is_doom_desire_hit_turn(vm: AnimScriptVM,
		_ctx: Dictionary) -> void:
	vm.args[ARG_RET_ID] = 1 if vm.move_turn == _DOOM_DESIRE_HIT_TURN else 0


# args: none. Inverted on purpose: `gAnimMoveDmg > 0` means it is NOT a
# healing move, so the register is TRUE when damage is zero or negative.
static func _is_healing_move(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	vm.args[ARG_RET_ID] = 0 if vm.move_damage > 0 else 1


# args: none. 1 for the player's side, 0 for the opponent's.
static func _is_attacker_player_side(vm: AnimScriptVM,
		_ctx: Dictionary) -> void:
	vm.args[ARG_RET_ID] = 1 if _is_player_side(vm) else 0


# args: none. ⚠ ANSWERS ON ARG 0, not arg 7 -- see the batch header.
static func _is_target_partner(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	vm.args[0] = 1 if _battler_visible(vm, AnimStage.ANIM_ATK_PARTNER) \
			and _same_side_as_attacker(vm, AnimStage.ANIM_TARGET) else 0


static func _same_side_as_attacker(vm: AnimScriptVM, who: int) -> bool:
	return _battler_is_player_side(vm, who) \
			== _battler_is_player_side(vm, AnimStage.ANIM_ATTACKER)


# args: none. ⚠ ALSO ANSWERS ON ARG 0. Reports which Lycanroc form the
# attacker is: 0 Midday, 1 Midnight, 2 Dusk. This port has no per-battler
# species surface in the anim layer, so it always reports the Midday form --
# recorded as a stub with its consumer named, per the standing rule, rather
# than left to look like a decision.
static func _get_lycanroc_form(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	vm.args[0] = 0


# args: none. Upstream repoints gBattleAnimTarget at BATTLE_OPPOSITE(attacker).
#
# In this port that is a genuine NO-OP and the reasoning matters: ANIM_TARGET
# already resolves to the primary opposing slot, which is exactly what
# BATTLE_OPPOSITE names. The retarget only differs upstream when a doubles
# move was aimed at the non-opposite slot, and the one script using this
# (the cosmic-background sequence) immediately addresses ANIM_DEF_PARTNER
# explicitly anyway. Implemented as an explicit no-op so a later session
# reads a decision rather than an omission.
static func _set_anim_target_to_attacker_opposite(_vm: AnimScriptVM,
		_ctx: Dictionary) -> void:
	pass


# AnimMovementWaves (battle_anim_effects_1.c). args: 0 battler, 1 direction,
# 2 repeat count.
#
# arg 2 is a GATE, not a duration: zero destroys the sprite before it starts.
# arg 1 does double duty -- it both mirrors the 32 px spawn offset AND picks
# the cel variant, so the wave faces the way it travels.
const _MOVEMENT_WAVE_OFFSET := 32.0


static func _movement_waves(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	if vm.args[2] == 0:
		node.finish()
		return
	var scale := _scale(vm)
	var who: int = AnimStage.ANIM_ATTACKER if vm.args[0] == 0 \
			else AnimStage.ANIM_TARGET
	var dir: float = 1.0 if vm.args[1] == 0 else -1.0
	_apply_anim_variant(node, ctx, vm.args[1])
	node.centre = _battler_centre(vm, who) \
			+ Vector2(_MOVEMENT_WAVE_OFFSET * dir * scale, 0.0)
	_play_until_anim_ends(vm, node, _ANIM_END_CAP)


# AnimWaveFromCenterOfTarget (battle_anim_effects_3.c). args: 0/1 offset,
# 2 use the side midpoint. Lives for its own animation.
static func _wave_from_center_of_target(vm: AnimScriptVM,
		ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	if vm.args[2] == 0:
		node.centre = _battler_centre(vm, AnimStage.ANIM_TARGET)
	else:
		node.centre = _side_centre(vm, AnimStage.ANIM_TARGET,
				AnimStage.ANIM_DEF_PARTNER) \
				+ Vector2(float(vm.args[0]) * _facing(vm),
						float(vm.args[1])) * scale
	_play_until_anim_ends(vm, node, _ANIM_END_CAP)


# AnimForesightMagnifyingGlass (battle_anim_effects_3.c). args: 0 battler.
# Mirrored for an opposing battler, and it holds on the mon for its own
# animation rather than travelling.
static func _foresight_magnifying_glass(vm: AnimScriptVM,
		ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var who: int = AnimStage.ANIM_ATTACKER if vm.args[0] == 0 \
			else AnimStage.ANIM_TARGET
	node.centre = _battler_centre(vm, who)
	if not _battler_is_player_side(vm, who):
		node.scale = Vector2(-node.scale.x, node.scale.y)
	_play_until_anim_ends(vm, node, _ANIM_END_CAP)


# AnimMoveWringOut (battle_anim_effects_1.c). args: 0/1 offset, 2 step
# divisor, 3 spin count, 4 radius.
#
# arg 2 is a DIVISOR of a full circle (256 / arg2 per frame), not a duration,
# and the start angle is a hardcoded 64 -- a quarter turn in, so the ring
# opens from the side rather than the top.
const _WRING_OUT_START_ANGLE := 64.0


static func _move_wring_out(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var centre := _positioned_centre(vm, AnimStage.ANIM_TARGET, vm.args[0],
			vm.args[1], scale)
	var step: float = 256.0 / maxf(1.0, float(vm.args[2]))
	var spins: int = maxi(1, vm.args[3])
	var radius: float = float(vm.args[4]) * scale
	var st := {"angle": _WRING_OUT_START_ANGLE, "turned": 0.0}
	node.centre = centre + Vector2(_gba_cos(_WRING_OUT_START_ANGLE, radius),
			_gba_sin(_WRING_OUT_START_ANGLE, radius))
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["angle"] = float(st["angle"]) + step
		st["turned"] = float(st["turned"]) + step
		node.centre = centre + Vector2(
				_gba_cos(float(st["angle"]), radius),
				_gba_sin(float(st["angle"]), radius))
		if float(st["turned"]) >= 256.0 * float(spins):
			node.finish()
			return true
		return false)


# AnimMoveAccupressure (battle_anim_effects_1.c). args: 0/1 start offset,
# 2 duration. Closes from the offset onto the target's own centre.
static func _move_accupressure(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var centre := _battler_centre(vm, AnimStage.ANIM_TARGET)
	var start := centre + Vector2(float(vm.args[0]) * _facing(vm),
			float(vm.args[1])) * scale
	node.centre = start
	_linear_travel(vm, node, start, centre, maxi(1, vm.args[2]))


# AnimFlatterConfetti (battle_anim_effects_3.c). No meaningful args: every
# parameter is a fresh Random2() draw -- the glyph (12 variants), the fall
# speed and the drift. The RANGES are reproduced rather than the draws, the
# same convention batch 3's Bullet Seed established.
const _CONFETTI_GLYPHS := 12
const _CONFETTI_FALL_BASE := 0x5E0 / 256.0
const _CONFETTI_FALL_SPREAD := 0x1FF / 256.0
const _CONFETTI_DRIFT_BASE := 0x480 / 256.0
const _CONFETTI_DRIFT_SPREAD := 0xFF / 256.0
const _CONFETTI_LIFE := 90


static func _flatter_confetti(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	node.set_tile_offset(randi() % _CONFETTI_GLYPHS)
	var start := node.centre
	# Upstream picks a sign per draw, so the spread straddles the base value
	# rather than only ever adding to it.
	var fall := (_CONFETTI_FALL_BASE
			+ (randf() * 2.0 - 1.0) * _CONFETTI_FALL_SPREAD) / 16.0 * scale
	var drift := (_CONFETTI_DRIFT_BASE
			+ (randf() * 2.0 - 1.0) * _CONFETTI_DRIFT_SPREAD) / 16.0 * scale
	if randf() < 0.5:
		drift = -drift
	var st := {"t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var t: int = int(st["t"]) + 1
		st["t"] = t
		node.centre = start + Vector2(drift * float(t), fall * float(t))
		if t >= _CONFETTI_LIFE:
			node.finish()
			return true
		return false)


# ══ [M36D batch 31] ═══════════════════════════════════════════════════════
#
# The paired mechanisms: eight two-sprite (or sprite-plus-task) effects where
# neither half means anything alone. Three of the eight reuse machinery from
# earlier batches outright -- Conversion 2 is Conversion's shape with a
# different signal, the Perish Song notes are batch 25's music family, and the
# partner slides are batch 2's SlideMon pair aimed at a partner slot.
#
# DEFERRED: `AnimTask_SketchDrawMon` is a SCANLINE effect
# (`ScanlineEffectParams`, REG_BG1HOFS) -- the pencil "drawing" the mon is a
# per-scanline shear of the background. `AnimPencil` is deferred WITH it for
# the same reason Rapid Spin's sprite was: every move needing the pencil also
# needs the shear, so porting it alone adds unreachable code.


# AnimTask_HelpingHandAttackerMovement (battle_anim_effects_1.c) and
# AnimHelpingHandClap. args (clap): 0 which hand.
#
# THE CLAP USES ABSOLUTE SCREEN COORDINATES -- x 100 or 140, y 56 -- like
# batch 26's moon. The hands meet in the middle of the screen, not beside
# either mon, so reading them as offsets puts the clap on top of a battler.
const _HELPING_HAND_LEFT_X := 100
const _HELPING_HAND_RIGHT_X := 140
const _HELPING_HAND_Y := 56
const _HELPING_HAND_APPROACH := 9
const _HELPING_HAND_HOLD := 4


static func _helping_hand_clap(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var left: bool = vm.args[0] == 0
	var start := _gba_screen_point(vm,
			_HELPING_HAND_LEFT_X if left else _HELPING_HAND_RIGHT_X,
			_HELPING_HAND_Y)
	node.centre = start
	if left:
		node.scale = Vector2(-node.scale.x, node.scale.y)
	# data[7] is +1 for the left hand and -1 for the right, and drives BOTH
	# the rise and the inward slide -- so the two hands converge rather than
	# both drifting the same way.
	var dir: float = 1.0 if left else -1.0
	var st := {"t": 0, "phase": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var t: int = int(st["t"]) + 1
		st["t"] = t
		if int(st["phase"]) == 0:
			var moved := Vector2(0.0, -dir * 2.0 * float(t)) * scale
			if t % 2 == 1:
				moved.x = -dir * 2.0 * float(t) * scale
			node.centre = start + moved
			if t >= _HELPING_HAND_APPROACH:
				st["phase"] = 1
				st["t"] = 0
			return false
		if t >= _HELPING_HAND_HOLD:
			node.finish()
			return true
		return false)


static func _helping_hand_attacker_movement(vm: AnimScriptVM,
		_ctx: Dictionary) -> void:
	var node := _battler_node(vm, AnimStage.ANIM_ATTACKER)
	if node == null:
		return
	# Direction is decided by the attacker's position RELATIVE TO ITS
	# PARTNER in doubles, and only falls back to the side rule in singles --
	# so in doubles the two allies always lean toward each other.
	var dir := -1.0 if _is_player_side(vm) else 1.0
	if _battler_visible(vm, AnimStage.ANIM_ATK_PARTNER):
		var me := _battler_centre(vm, AnimStage.ANIM_ATTACKER)
		var ally := _battler_centre(vm, AnimStage.ANIM_ATK_PARTNER)
		dir = 1.0 if me.x > ally.x else -1.0
	var scale := _scale(vm)
	var mon := MonOffset.new(node)
	var st := {"t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		var t: int = int(st["t"]) + 1
		st["t"] = t
		if t <= 12:
			mon.apply(Vector2(dir * float(t) * scale, 0.0))
			return false
		if t <= 24:
			mon.apply(Vector2(dir * float(24 - t) * scale, 0.0))
			return false
		mon.apply(Vector2.ZERO)
		return true)


# AnimIngrainOrb (battle_anim_effects_1.c). args: 0/1 start, 2 x velocity,
# 3 wave amplitude, 4 duration. A straight horizontal drift with a sine bob;
# the velocity is a per-frame PIXEL step, not fixed point.
static func _ingrain_orb(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var start := _positioned_centre(vm, AnimStage.ANIM_ATTACKER, vm.args[0],
			vm.args[1], scale)
	node.centre = start
	var vx: float = float(vm.args[2]) * scale
	var amp: float = float(vm.args[3]) * scale
	var life: int = maxi(1, vm.args[4])
	var st := {"t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var t: int = int(st["t"]) + 1
		st["t"] = t
		node.centre = start + Vector2(vx * float(t),
				_gba_sin(float((t * 20) % 256), amp))
		if t > life:
			node.finish()
			return true
		return false)


# AnimIngrainRoot (battle_anim_effects_1.c). args: 0/1 offset, 2 subpriority,
# 3 cel variant, 4 duration.
#
# It does not move at all: the whole behavior is a FLICKER-OUT that begins
# ten frames before the end (`data[0] > data[2] - 10`), so the root fades by
# strobing rather than vanishing. It also clamps upward if it would sit below
# y=120 -- a floor, so roots never draw off the bottom of the field.
const _ROOT_FLICKER_LEAD := 10
const _ROOT_FLOOR_Y := 120


static func _ingrain_root(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var at := _positioned_centre(vm, AnimStage.ANIM_ATTACKER, vm.args[0],
			vm.args[1], scale)
	var floor_y := float(_ROOT_FLOOR_Y) * scale
	if at.y > floor_y:
		at.y = floor_y
	node.centre = at
	_apply_anim_variant(node, ctx, vm.args[3])
	var life: int = maxi(1, vm.args[4])
	var st := {"t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var t: int = int(st["t"]) + 1
		st["t"] = t
		if t > life - _ROOT_FLICKER_LEAD:
			node.visible = (t % 2) == 0
		if t > life:
			node.visible = true
			node.finish()
			return true
		return false)


# AnimLockOnTarget (battle_anim_effects_2.c) and AnimLockOnMoveTarget.
#
# The second is a WRAPPER, not a duplicate: it applies one of four quadrant
# offsets with a matching flip and then CALLS the first. Registering them as
# an alias would be wrong -- the quadrant work is real and only one of them
# does it.
const _LOCK_ON_QUADRANT := 0x18
const _LOCK_ON_HOLD := 20


static func _lock_on_target(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	_lock_on_common(vm, node, Vector2(-32.0, -32.0))


static func _lock_on_move_target(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var q: int = vm.args[0]
	var off := Vector2(
			-_LOCK_ON_QUADRANT if q == 1 or q == 2 else _LOCK_ON_QUADRANT,
			-_LOCK_ON_QUADRANT if q == 1 or q == 3 else _LOCK_ON_QUADRANT)
	# Each quadrant flips the reticle so the four corners point inward.
	if q == 3 or q > 3:
		node.scale = Vector2(-node.scale.x, node.scale.y)
	if q == 2 or q > 3:
		node.scale = Vector2(node.scale.x, -node.scale.y)
	node.set_tile_offset(16)
	_lock_on_common(vm, node, off)


static func _lock_on_common(vm: AnimScriptVM, node: AnimSprite,
		offset: Vector2) -> void:
	var scale := _scale(vm)
	var centre := _battler_centre(vm, AnimStage.ANIM_TARGET)
	var start := centre + offset * scale
	node.centre = start
	var st := {"t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var t: int = int(st["t"]) + 1
		st["t"] = t
		if t <= _LOCK_ON_HOLD:
			return false
		# The reticle then closes on the target rather than sitting still.
		var f := clampf(float(t - _LOCK_ON_HOLD) / 8.0, 0.0, 1.0)
		node.centre = start.lerp(centre, f)
		if f >= 1.0:
			node.finish()
			return true
		return false)


# AnimWoodHammerHammer (battle_anim_effects_1.c). No args.
#
# The hammer starts 40 px BEHIND the attacker on its own side, then WAITS 37
# frames -- shivering by one pixel on alternate frames while it waits -- and
# only then swings. That long wind-up is most of the animation, and a port
# that swung immediately loses the whole beat.
const _HAMMER_X_OFFSET := 40.0
const _HAMMER_WAIT := 37
const _HAMMER_SWING := 12


static func _wood_hammer_hammer(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var player := _is_player_side(vm)
	var start := _battler_centre(vm, AnimStage.ANIM_ATTACKER) \
			+ Vector2((-_HAMMER_X_OFFSET if player else _HAMMER_X_OFFSET)
					* scale, 0.0)
	node.centre = start
	var st := {"t": 0, "phase": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var t: int = int(st["t"]) + 1
		st["t"] = t
		if int(st["phase"]) == 0:
			# The shiver: x2 steps +-1 on alternate frames of the wait.
			if t % 2 == 1:
				node.offset = Vector2(
						scale if (t / 2) % 2 == 0 else -scale, 0.0)
			if t >= _HAMMER_WAIT:
				st["phase"] = 1
				st["t"] = 0
				node.offset = Vector2.ZERO
			return false
		if t >= _HAMMER_SWING:
			node.finish()
			return true
		return false)


# AnimWoodHammerSmall (battle_anim_effects_1.c). args: 0/1 start offset,
# 2/3 travel, 4 duration, 5 cel variant. arg 0 is side-mirrored; the travel
# is a plain fixed-point linear step.
static func _wood_hammer_small(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	_apply_anim_variant(node, ctx, vm.args[5])
	var scale := _scale(vm)
	var dir: float = 1.0 if _is_player_side(vm) else -1.0
	var start := _battler_centre(vm, AnimStage.ANIM_ATTACKER) \
			+ Vector2(float(vm.args[0]) * dir, float(vm.args[1])) * scale
	var finish_pos := start + Vector2(float(vm.args[2]),
			float(vm.args[3])) * scale
	node.centre = start
	_linear_travel(vm, node, start, finish_pos, maxi(1, vm.args[4]))


# AnimConversion2 (battle_anim_effects_1.c) and its alpha-blend partner.
#
# Structurally Conversion's twin from batch 27, with the signal INVERTED:
# Conversion's squares wait for arg 7 to say stop, while Conversion 2's each
# carry their OWN delay (arg 2) and then fly to the ATTACKER. The blend task
# still ramps 16 steps at one per 4 frames, but has no kill to send.
const _CONVERSION2_TRAVEL := 30


static func _conversion2(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var start := _battler_centre(vm, AnimStage.ANIM_TARGET)
	node.centre = start
	var delay: int = maxi(0, vm.args[2])
	var target := _battler_centre(vm, AnimStage.ANIM_ATTACKER)
	var st := {"t": 0, "moving": false}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		var t: int = int(st["t"]) + 1
		st["t"] = t
		if not bool(st["moving"]):
			# Paused: the square does not even animate until its delay is up.
			if t < delay:
				return false
			st["moving"] = true
			st["t"] = 0
			return false
		node.advance_frame()
		var f := float(t) / float(_CONVERSION2_TRAVEL)
		node.centre = start.lerp(target, minf(1.0, f))
		if f >= 1.0:
			node.finish()
			return true
		return false)


static func _conversion2_alpha_blend(vm: AnimScriptVM,
		_ctx: Dictionary) -> void:
	var st := {"t": 0, "step": 0}
	vm.add_stepper(func() -> bool:
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) < _CONVERSION_BLEND_DELAY:
			return false
		st["t"] = 0
		st["step"] = int(st["step"]) + 1
		# Note the operands are the OTHER way round from Conversion's:
		# eva rises while evb falls, so the squares fade IN rather than out.
		vm.set_blend_context(int(st["step"]),
				_CONVERSION_BLEND_STEPS - int(st["step"]))
		return int(st["step"]) >= _CONVERSION_BLEND_STEPS)


# AnimPerishSongMusicNote (battle_anim_effects_2.c). args: 0 y seed,
# 1 cel variant, 2 phase seed.
#
# Absolute x=120 -- the screen centre -- with a Cos amplitude of 100, so each
# note sweeps almost the full width. The vertical is THREE terms added: a
# steady sink, a small Sin, and a second faster Cos, which is what stops the
# notes tracing identical arcs.
const _PERISH_NOTE_CENTRE_X := 120
const _PERISH_NOTE_SWEEP := 100.0
const _PERISH_NOTE_LIFE := 120


static func _perish_song_music_note(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	_apply_anim_variant(node, ctx, vm.args[1])
	var scale := _scale(vm)
	var base := _gba_screen_point(vm, _PERISH_NOTE_CENTRE_X,
			int(float(vm.args[0]) / 2.0) - 15)
	node.centre = base
	var st := {"t": 0, "wobble": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var t: int = int(st["t"]) + 1
		st["t"] = t
		st["wobble"] = (int(st["wobble"]) + 10) & 0xFF
		var index := float((t * 3 + vm.args[2]) & 0xFF)
		node.centre = base + Vector2(
				_gba_cos(index, _PERISH_NOTE_SWEEP) * scale,
				(float(t) / 2.0 + _gba_sin(index, 10.0)
						+ _gba_cos(float(st["wobble"]), 4.0)) * scale)
		if t > _PERISH_NOTE_LIFE:
			node.finish()
			return true
		return false)


# AnimPerishSongMusicNote2 (battle_anim_effects_2.c). args: 0 delay offset.
#
# ⚠ THIS SPRITE IS NEVER DRAWN. It sets `invisible = TRUE` on its first frame
# and exists solely as a TIMER: at 120 - arg0 frames it greys the palette,
# and 80 frames later it ends. Porting it as a visible sprite puts a stray
# note on screen that upstream never shows.
const _PERISH_NOTE2_BASE := 120
const _PERISH_NOTE2_TAIL := 80


static func _perish_song_music_note2(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	node.visible = false
	var fire: int = maxi(1, _PERISH_NOTE2_BASE - vm.args[0])
	var st := {"t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		var t: int = int(st["t"]) + 1
		st["t"] = t
		if t == fire:
			for battler in [AnimStage.ANIM_ATTACKER, AnimStage.ANIM_TARGET]:
				var n := _battler_node(vm, battler)
				if n != null:
					n.modulate = Color(0.6, 0.6, 0.6, n.modulate.a)
		if t >= fire + _PERISH_NOTE2_TAIL:
			for battler in [AnimStage.ANIM_ATTACKER, AnimStage.ANIM_TARGET]:
				var n := _battler_node(vm, battler)
				if n != null:
					n.modulate = Color(1, 1, 1, n.modulate.a)
			node.finish()
			return true
		return false)


# AnimRockPolishSparkle / AnimRockPolishStreak (battle_anim_rock.c). Both sit
# on the attacker and live for their own animation; the streak additionally
# picks a RANDOM affine variant, so no two streaks lie at the same angle.
static func _rock_polish_sparkle(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	node.centre = _positioned_centre(vm, AnimStage.ANIM_ATTACKER, vm.args[0],
			vm.args[1], _scale(vm))
	_play_until_anim_ends(vm, node, _ANIM_END_CAP)


const _ROCK_POLISH_STREAK_ANGLES := 4


static func _rock_polish_streak(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	node.centre = _positioned_centre(vm, AnimStage.ANIM_ATTACKER, vm.args[0],
			vm.args[1], _scale(vm))
	# The RANGE is reproduced rather than the draw, this port's convention
	# for every Random2() upstream.
	node.rotation = float(randi() % _ROCK_POLISH_STREAK_ANGLES) * TAU / 8.0
	_play_until_anim_ends(vm, node, _ANIM_END_CAP)


# SlideMonToOffsetPartner / SlideMonToOriginalPosPartner
# (battle_anim_mon_movement.c). Batch 2's SlideMon pair aimed at a PARTNER
# slot instead of the primary. args match their originals except arg 0
# selects which side's partner.
static func _slide_mon_to_offset_partner(vm: AnimScriptVM,
		_ctx: Dictionary) -> void:
	_slide_partner_common(vm, true)


static func _slide_mon_to_original_pos_partner(vm: AnimScriptVM,
		_ctx: Dictionary) -> void:
	_slide_partner_common(vm, false)


static func _slide_partner_common(vm: AnimScriptVM, outward: bool) -> void:
	var battler: int = AnimStage.ANIM_ATK_PARTNER if vm.args[0] == 0 \
			else AnimStage.ANIM_DEF_PARTNER
	var node := _battler_node(vm, battler)
	if node == null:
		return
	var mon := MonOffset.new(node)
	if not outward:
		var duration_back: int = maxi(1, vm.args[2])
		var from := node.position - mon.base
		var st_back := {"t": 0}
		vm.add_stepper(func() -> bool:
			if not is_instance_valid(node):
				return true
			var t: int = int(st_back["t"]) + 1
			st_back["t"] = t
			var f := minf(1.0, float(t) / float(duration_back))
			mon.apply(from.lerp(Vector2.ZERO, f))
			if t >= duration_back:
				mon.apply(Vector2.ZERO)
				return true
			return false)
		return
	var scale := _scale(vm)
	var sign := 1.0 if _battler_is_player_side(vm, battler) else -1.0
	var dx := float(vm.args[1]) * scale * sign
	var dy := float(vm.args[2]) * scale
	if vm.args[3] == 1 and sign < 0.0:
		dy = -dy
	var duration: int = maxi(1, vm.args[4])
	var st := {"t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		var t: int = int(st["t"]) + 1
		st["t"] = t
		var f := minf(1.0, float(t) / float(duration))
		mon.apply(Vector2(dx, dy) * f)
		return t >= duration)


# ══ [M36D batch 32] ═══════════════════════════════════════════════════════
#
# The sprite singletons: one behavior per move, no shared machinery left to
# retire. Two of them mutate a BATTLER rather than only drawing, which is the
# leak class rule (3) exists for, so both go through the VM's tracked
# visibility rather than touching the node directly.


# AnimSuperpowerOrb (battle_anim_new.c). args: 0 which battler.
#
# It HOLDS for 180 frames -- three seconds -- and only then flies to the
# OTHER battler over 16. The long charge is the animation; a port that
# launched on spawn loses essentially all of it.
const _SUPERPOWER_HOLD := 180
const _SUPERPOWER_TRAVEL := 16


static func _superpower_orb(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var on_attacker: bool = vm.args[0] == 0
	var home: int = AnimStage.ANIM_ATTACKER if on_attacker \
			else AnimStage.ANIM_TARGET
	# data[7] is the OPPOSITE battler -- the orb charges on one and lands on
	# the other, so the two args select which way round it goes.
	var away: int = AnimStage.ANIM_TARGET if on_attacker \
			else AnimStage.ANIM_ATTACKER
	var start := _battler_centre(vm, home)
	node.centre = start
	var st := {"t": 0, "phase": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var t: int = int(st["t"]) + 1
		st["t"] = t
		if int(st["phase"]) == 0:
			if t >= _SUPERPOWER_HOLD:
				st["phase"] = 1
				st["t"] = 0
			return false
		var f := float(t) / float(_SUPERPOWER_TRAVEL)
		node.centre = start.lerp(_battler_centre(vm, away), minf(1.0, f))
		if f >= 1.0:
			node.finish()
			return true
		return false)


# AnimDevil (battle_anim_effects_3.c). args: 0/1 offset.
#
# A DECAYING orbit that also REVERSES: the radius shrinks with age
# (`30 - data[0]/4`) while the phase runs forward to 128 and then back down,
# so the devil circles in, turns around, and circles out. It also flickers
# for its first 10 and last 10 frames but is solid in between -- three
# separate behaviours sharing one counter.
const _DEVIL_LIFE := 90
const _DEVIL_SOLID_FROM := 10
const _DEVIL_SOLID_UNTIL := 80


static func _devil(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var start := _positioned_centre(vm, AnimStage.ANIM_TARGET, vm.args[0],
			vm.args[1], scale)
	node.centre = start
	var st := {"t": 0, "phase": 0, "dir": 1}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var t: int = int(st["t"]) + 1
		st["t"] = t
		st["phase"] = int(st["phase"]) + int(st["dir"])
		var index := float(posmod(int(st["phase"]) * 4, 256))
		node.centre = start + Vector2(
				_gba_cos(index, maxf(0.0, 30.0 - float(st["phase"]) / 4.0)),
				_gba_sin(index, maxf(0.0, 10.0 - float(st["phase"]) / 8.0))
				) * scale
		if index > 128.0 and int(st["dir"]) > 0:
			st["dir"] = -1
		elif index <= 0.0 and int(st["dir"]) < 0:
			st["dir"] = 1
		node.visible = t >= _DEVIL_SOLID_FROM and t <= _DEVIL_SOLID_UNTIL \
				or (t % 2) == 0
		if t > _DEVIL_LIFE:
			node.visible = true
			node.finish()
			return true
		return false)


# AnimFlyingMusicNotes (battle_anim_effects_1.c). args: 0 cel variant,
# 1 x offset, 2 y offset.
#
# The offsets are ALSO the velocity, divided by 5 -- the same one-arg-two-jobs
# shape as batch 25's jagged note, but with the two axes scaled differently
# (`<< 4` for x, `<< 7` for y), so a note offset equally on both axes still
# travels mostly vertically.
const _FLYING_NOTE_X_DIV := 5.0
const _FLYING_NOTE_Y_MUL := 8.0
const _FLYING_NOTE_LIFE := 60


static func _flying_music_notes(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	_apply_anim_variant(node, ctx, vm.args[0])
	var scale := _scale(vm)
	var dir: float = 1.0 if _is_player_side(vm) else -1.0
	var start := _battler_centre(vm, AnimStage.ANIM_ATTACKER) \
			+ Vector2(float(vm.args[1]) * dir, float(vm.args[2])) * scale
	node.centre = start
	# x steps by offset/5; y by offset*8/5 -- the `<< 7` against `<< 4`.
	var per_frame := Vector2(float(vm.args[1]) * dir / _FLYING_NOTE_X_DIV,
			float(vm.args[2]) * _FLYING_NOTE_Y_MUL / _FLYING_NOTE_X_DIV) \
			* scale / 16.0
	var st := {"t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var t: int = int(st["t"]) + 1
		st["t"] = t
		node.centre = start + per_frame * float(t)
		if t >= _FLYING_NOTE_LIFE:
			node.finish()
			return true
		return false)


# AnimBounceBallShrink (battle_anim_flying.c). No args.
#
# ⚠ IT HIDES THE ATTACKER. The ball is the mon -- the sprite is swapped for
# it -- so this goes through the VM's tracked visibility, not a raw
# `node.visible = false`, or a script that ends early leaves a Pokemon
# invisible for the rest of the battle.
static func _bounce_ball_shrink(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	node.centre = _battler_centre(vm, AnimStage.ANIM_ATTACKER)
	vm.hide_battler(AnimStage.ANIM_ATTACKER)
	_play_until_anim_ends(vm, node, _ANIM_END_CAP)


# AnimDragonRush (battle_anim_dragon.c). args: 0/1 offset.
#
# UPSTREAM DEAD CODE, reproduced as the no-op it is: AnimDragonRushStep's two
# branches are byte-identical and source's own comment says so ("These two
# cases are identical"). The side check only matters in the INIT, where it
# picks the spin direction (-11 vs +11) and the mirrored offset.
const _DRAGON_RUSH_ORBIT := 20.0
const _DRAGON_RUSH_SPEED := 11
const _DRAGON_RUSH_LIFE := 60


static func _dragon_rush(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	# Keyed on the TARGET's side, not the attacker's.
	var target_is_player := _battler_is_player_side(vm, AnimStage.ANIM_TARGET)
	var sign: float = -1.0 if target_is_player else 1.0
	var start := _battler_centre(vm, AnimStage.ANIM_TARGET) \
			+ Vector2(float(vm.args[0]) * sign, float(vm.args[1])) * scale
	node.centre = start
	var speed: int = -_DRAGON_RUSH_SPEED if target_is_player \
			else _DRAGON_RUSH_SPEED
	var st := {"t": 0, "phase": 192}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var t: int = int(st["t"]) + 1
		st["t"] = t
		st["phase"] = posmod(int(st["phase"]) + speed, 256)
		node.centre = start + Vector2(
				_gba_cos(float(st["phase"]), _DRAGON_RUSH_ORBIT),
				_gba_sin(float(st["phase"]), _DRAGON_RUSH_ORBIT)) * scale
		if t >= _DRAGON_RUSH_LIFE:
			node.finish()
			return true
		return false)


# AnimEruptionFallingRock (battle_anim_fire.c). args: 0/1 ABSOLUTE position,
# 2 fall delay, 3 target y, 4 glyph.
#
# Absolute screen coordinates again, and arg 4 selects one of several rock
# glyphs on a shared sheet -- so a volley reads as different rocks rather
# than one repeated.
const _ERUPTION_FALL_SPEED := 6.0


static func _eruption_falling_rock(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var start := _gba_screen_point(vm, vm.args[0], vm.args[1])
	node.centre = start
	node.set_tile_offset(vm.args[4] * 16)
	var delay: int = maxi(0, vm.args[2])
	var target_y := float(vm.args[3]) * scale
	var st := {"t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var t: int = int(st["t"]) + 1
		st["t"] = t
		if t <= delay:
			return false
		var fallen := float(t - delay) * _ERUPTION_FALL_SPEED * scale
		node.centre = start + Vector2(0.0, fallen)
		if node.centre.y >= target_y:
			node.finish()
			return true
		if t > _ANIM_END_CAP:
			node.finish()
			return true
		return false)


# AnimOverheatFlame (battle_anim_fire.c). args: 0 speed, 1 angle,
# 2 x amplitude, 3 duration, 4 y offset.
#
# THE TWO AXES USE DIFFERENT AMPLITUDES and it is not arbitrary: the vertical
# is exactly THREE FIFTHS of the horizontal (`(unk2 * 3) / 5`), so the spray
# is a flattened ellipse. The initial position is also offset by
# speed x the per-frame step, so a flame launched at speed 8 starts eight
# steps out rather than at the mon.
static func _overheat_flame(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var y_amp: float = float(vm.args[2]) * 3.0 / 5.0
	var step := Vector2(_gba_cos(float(vm.args[1]), float(vm.args[2])),
			_gba_sin(float(vm.args[1]), y_amp))
	var speed: float = float(vm.args[0])
	var start := _battler_centre(vm, AnimStage.ANIM_ATTACKER) \
			+ Vector2(0.0, float(vm.args[4]) * scale) \
			+ step * speed * scale
	node.centre = start
	var life: int = maxi(1, vm.args[3])
	var st := {"t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var t: int = int(st["t"]) + 1
		st["t"] = t
		node.centre = start + step * (float(t) / 10.0) * scale
		if t > life:
			node.finish()
			return true
		return false)


# AnimFalseSwipeSlice / AnimFalseSwipePositionedSlice (battle_anim_effects_3).
# The second is NOT an alias: it starts 48 px left of the target plus its own
# arg and plays cel variant 1, where the first starts at a fixed -48 (0xFFD0)
# and plays variant 0. Same family, different entry point.
const _FALSE_SWIPE_OFFSET := -48


static func _false_swipe_slice(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	node.centre = _battler_centre(vm, AnimStage.ANIM_TARGET) \
			+ Vector2(float(_FALSE_SWIPE_OFFSET) * _scale(vm), 0.0)
	_play_until_anim_ends(vm, node, _ANIM_END_CAP)


static func _false_swipe_positioned_slice(vm: AnimScriptVM,
		ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	node.centre = _battler_centre(vm, AnimStage.ANIM_TARGET) \
			+ Vector2(float(_FALSE_SWIPE_OFFSET + vm.args[0])
					* _scale(vm), 0.0)
	_apply_anim_variant(node, ctx, 1)
	_play_until_anim_ends(vm, node, _ANIM_END_CAP)


# AnimBlastBurnTargetPlume (battle_anim_new.c). args: 0/1 offset,
# 2/3/4/5 motion parameters. arg 0 mirrors on the TARGET's side and arg 4's
# sign flips with it, so the plume always sweeps outward from the target.
static func _blast_burn_target_plume(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var sign: float = 1.0 if _battler_is_player_side(vm,
			AnimStage.ANIM_TARGET) else -1.0
	var start := _battler_centre(vm, AnimStage.ANIM_TARGET) \
			+ Vector2(float(vm.args[0]) * sign, float(vm.args[1])) * scale
	node.centre = start
	var drift := Vector2(float(vm.args[4]) * sign, 0.0) * scale / 16.0
	var life: int = maxi(1, vm.args[2])
	var st := {"t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var t: int = int(st["t"]) + 1
		st["t"] = t
		node.centre = start + drift * float(t)
		if t >= life:
			node.finish()
			return true
		return false)


# AnimExtremeEvoboostCircle (battle_anim_new.c). No args: it starts 20 px
# BELOW the attacker and its phase seed is 191, not 0 -- so the circle opens
# from a specific point on its arc rather than the top.
const _EVOBOOST_DROP := 20.0
const _EVOBOOST_SEED := 191
const _EVOBOOST_RADIUS := 32.0
const _EVOBOOST_LIFE := 64


static func _extreme_evoboost_circle(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var centre := _battler_centre(vm, AnimStage.ANIM_ATTACKER) \
			+ Vector2(0.0, _EVOBOOST_DROP * scale)
	var st := {"t": 0, "phase": _EVOBOOST_SEED}
	node.centre = centre + Vector2(
			_gba_cos(float(_EVOBOOST_SEED), _EVOBOOST_RADIUS),
			_gba_sin(float(_EVOBOOST_SEED), _EVOBOOST_RADIUS)) * scale
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var t: int = int(st["t"]) + 1
		st["t"] = t
		st["phase"] = posmod(int(st["phase"]) + 4, 256)
		node.centre = centre + Vector2(
				_gba_cos(float(st["phase"]), _EVOBOOST_RADIUS),
				_gba_sin(float(st["phase"]), _EVOBOOST_RADIUS)) * scale
		if t >= _EVOBOOST_LIFE:
			node.finish()
			return true
		return false)


# AnimDracoMeteorRock (battle_anim_dragon.c). args: 0/1 start, 2/3 end,
# 4 duration. The X offsets mirror on the TARGET's side -- the same
# inward-sweep rule batch 29's Meteor Mash star uses, and for the same
# reason: the meteors must converge whichever side is being hit.
static func _draco_meteor_rock(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var base := _battler_centre(vm, AnimStage.ANIM_TARGET)
	var sign: float = -1.0 if _battler_is_player_side(vm,
			AnimStage.ANIM_TARGET) else 1.0
	var start := base + Vector2(float(vm.args[0]) * sign,
			float(vm.args[1])) * scale
	var finish_pos := base + Vector2(float(vm.args[2]) * sign,
			float(vm.args[3])) * scale
	node.centre = start
	_linear_travel(vm, node, start, finish_pos, maxi(1, vm.args[4]))


# AnimHappyHourCoinShower (battle_anim_new.c). args: 0 x offset,
# 1 cel variant, 2 orbit speed, 3 anchor on the attacker side.
#
# It rides an ELLIPSE (amplitudes 16 and -70, so tall and narrow) and then
# hands off to the falling-rock step -- the coins arc up and then drop,
# rather than simply raining down.
const _COIN_SHOWER_DROP := 14.0
const _COIN_SHOWER_X_AMP := 16.0
const _COIN_SHOWER_Y_AMP := -70.0
const _COIN_SHOWER_LIFE := 48


static func _happy_hour_coin_shower(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	_apply_anim_variant(node, ctx, vm.args[1])
	var scale := _scale(vm)
	var anchor := _battler_centre(vm, AnimStage.ANIM_TARGET)
	if vm.args[3] != 0:
		anchor = _side_centre(vm, AnimStage.ANIM_ATTACKER,
				AnimStage.ANIM_ATK_PARTNER)
	var centre := anchor + Vector2(float(vm.args[0]) * _facing(vm),
			_COIN_SHOWER_DROP) * scale
	var st := {"t": 0, "phase": 0}
	var speed: int = maxi(1, vm.args[2])
	node.centre = centre
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var t: int = int(st["t"]) + 1
		st["t"] = t
		st["phase"] = posmod(int(st["phase"]) + speed, 256)
		node.centre = centre + Vector2(
				_gba_sin(float(st["phase"]), _COIN_SHOWER_X_AMP),
				_gba_cos(float(st["phase"]), _COIN_SHOWER_Y_AMP)) * scale
		if t >= _COIN_SHOWER_LIFE:
			node.finish()
			return true
		return false)


# SpriteCB_GeyserTarget (battle_anim_new.c). args: 1/2 offset.
#
# arg 1 does double duty: it offsets the spear AND its SIGN picks the rise
# direction. A geyser placed to the right of the target rises the other way
# from one placed to the left, which is what makes a row of them fan out.
const _GEYSER_RISE := 3.0
const _GEYSER_LIFE := 40


static func _geyser_target(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var start := _battler_centre(vm, AnimStage.ANIM_TARGET) \
			+ Vector2(float(vm.args[1]), float(vm.args[2])) * scale
	node.centre = start
	var dir: float = 1.0 if vm.args[1] > 0 else -1.0
	var st := {"t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		var t: int = int(st["t"]) + 1
		st["t"] = t
		node.centre = start + Vector2(dir * float(t) * _GEYSER_RISE * scale,
				-float(t) * _GEYSER_RISE * scale)
		if t >= _GEYSER_LIFE:
			node.finish()
			return true
		return false)


# ══ [M36D batch 33] ═══════════════════════════════════════════════════════
#
# The task tail: mon shakes, palette blends and the last of the query tasks.
#
# DEFERRED, and each for a stated reason rather than being skipped:
#   * `AnimTask_LeafBlade`, `AnimTask_AirCutterProjectile`,
#     `AnimTask_WaterSport`, `AnimTask_BrineRain`, `AnimTask_CreateIons` --
#     multi-phase SPAWNERS whose step machines create and choreograph their
#     own sprites over several states. Portable, but each is a batch's worth
#     of work on its own rather than a task.
#   * `AnimTask_CreateBestowItem` calls AddItemIconSprite -- it draws the
#     player's actual held-item icon, a surface the anim layer has no access
#     to here.
#   * `AnimTask_OdorSleuthMovement` needs CloneBattlerSpriteWithBlend's
#     blended-clone variant driving a three-way split; the plain clone helper
#     this port has is not the same effect.


# gThrashMoveMonAffineAnimCmds (battle_anim_effects_2.c:561). Four legs and
# then an AFFINEANIMCMD_LOOP(2) -- so the whole set runs TWICE. The legs sum
# to zero, and the loop is why Thrash reads as a sustained shake rather than
# one wobble.
const _THRASH_AFFINE := [[-10, 9, 0, 7], [20, -20, 0, 7], [-20, 20, 0, 7],
		[10, -9, 0, 7]]
const _THRASH_LOOPS := 2


static func _thrash_move_mon_horizontal(vm: AnimScriptVM,
		_ctx: Dictionary) -> void:
	var cmds: Array = []
	for i in range(_THRASH_LOOPS):
		for c in _THRASH_AFFINE:
			cmds.append(c)
	_run_affine_cmds(vm, _battler_node(vm, AnimStage.ANIM_ATTACKER), cmds,
			Callable(), AnimStage.ANIM_ATTACKER)


# AnimTask_ThrashMoveMonVertical (battle_anim_effects_2.c). No args.
#
# NOT the vertical twin of the horizontal one -- the horizontal is an AFFINE
# deformation while this is a plain DISPLACEMENT: a 4 px-per-frame sweep out
# and back (side-mirrored) with a 2 px vertical jitter every third frame on
# top. Sharing one implementation would give Thrash the same look twice.
const _THRASH_V_STEP := 4.0
const _THRASH_V_LEG := 7
const _THRASH_V_RETURN := 14
const _THRASH_V_JITTER := 2.0


static func _thrash_move_mon_vertical(vm: AnimScriptVM,
		_ctx: Dictionary) -> void:
	var node := _battler_node(vm, AnimStage.ANIM_ATTACKER)
	if node == null:
		return
	var scale := _scale(vm)
	var mon := MonOffset.new(node)
	var dir: float = 1.0 if _is_player_side(vm) else -1.0
	var st := {"x": 0.0, "y": 0.0, "leg": 0, "left": _THRASH_V_LEG,
			"sub": 0, "flip": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		st["sub"] = int(st["sub"]) + 1
		if int(st["sub"]) > 2:
			st["sub"] = 0
			st["flip"] = int(st["flip"]) + 1
			st["y"] = float(st["y"]) + (_THRASH_V_JITTER * scale
					if (int(st["flip"]) & 1) == 1 else -_THRASH_V_JITTER * scale)
		var leg: int = int(st["leg"])
		st["x"] = float(st["x"]) + (_THRASH_V_STEP * dir * scale
				if leg == 0 else -_THRASH_V_STEP * dir * scale)
		mon.apply(Vector2(float(st["x"]), float(st["y"])))
		st["left"] = int(st["left"]) - 1
		if int(st["left"]) <= 0:
			if leg == 0:
				st["leg"] = 1
				st["left"] = _THRASH_V_RETURN
				return false
			mon.apply(Vector2.ZERO)
			return true
		return false)


# AnimTask_FacadeColorBlend (battle_anim_effects_3.c). args: 0 battler,
# 1 duration in frames.
#
# It CYCLES a 24-entry colour ramp at one entry per frame, wrapping, for the
# whole duration -- and then clears the blend outright. A single static tint
# is the obvious misreading and holds one colour instead of pulsing.
const _FACADE_BLEND_COLORS := [
	Color8(231, 206, 8), Color8(231, 173, 41), Color8(222, 148, 66),
	Color8(222, 115, 90), Color8(214, 90, 115), Color8(214, 57, 148),
	Color8(206, 33, 173), Color8(198, 8, 198),
]
const _FACADE_RAMP_LENGTH := 24
const _FACADE_BLEND_STRENGTH := 8.0 / 16.0


static func _facade_color_blend(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var node := _battler_node(vm, vm.args[0])
	if node == null:
		return
	var frames: int = maxi(1, vm.args[1])
	var st := {"t": 0, "i": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) > frames:
			_clear_blend(node)
			return true
		var idx: int = int(st["i"])
		_apply_blend_amount(node,
				_FACADE_BLEND_COLORS[idx % _FACADE_BLEND_COLORS.size()],
				_FACADE_BLEND_STRENGTH)
		st["i"] = (idx + 1) % _FACADE_RAMP_LENGTH
		return false)


# AnimTask_BlendBackground (battle_anim_utility_funcs.c). args: 0 strength,
# 1 colour. A single-frame blend of the BACKGROUND palette -- it destroys
# itself immediately rather than ramping, so it is a set, not a fade.
static func _blend_background(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	if vm.stage == null or not vm.stage.has_method("layer"):
		return
	var strength := clampf(float(vm.args[0]) / 16.0, 0.0, 1.0)
	var colour := _rgb15_to_color(vm.args[1])
	var bg: Control = null
	if vm.stage.has_method("background_node"):
		bg = vm.stage.background_node() as Control
	if bg == null:
		return
	if strength <= 0.0:
		_clear_blend(bg)
		return
	_apply_blend_amount(bg, colour, strength)


# AnimTask_ShakeTargetPartnerBasedOnMovePowerOrDmg. args: 0 use damage
# rather than power, 1 divisor, 2 duration.
#
# It shakes the DEF PARTNER, not the target -- the whole point of the task,
# and the reason it exists alongside the target-side one. Amplitude scales
# with the move's own power or damage, so a weak move barely nudges.
static func _shake_target_partner_by_power(vm: AnimScriptVM,
		_ctx: Dictionary) -> void:
	var node := _battler_node(vm, AnimStage.ANIM_DEF_PARTNER)
	if node == null:
		return
	var source: int = vm.move_damage if vm.args[0] != 0 else vm.move_power
	var divisor: int = maxi(1, vm.args[1])
	var amplitude := float(source) / float(divisor)
	var duration: int = maxi(1, vm.args[2])
	var scale := _scale(vm)
	var mon := MonOffset.new(node)
	var st := {"t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		var t: int = int(st["t"]) + 1
		st["t"] = t
		mon.apply(Vector2(
				amplitude * scale if (t % 2) == 1 else -amplitude * scale,
				0.0))
		if t >= duration:
			mon.apply(Vector2.ZERO)
			return true
		return false)


# AnimTask_SkullBashPosition (battle_anim_effects_1.c). args: 0 phase
# (0 = wind back, else return).
#
# Two phases in one task selected by an arg, and the displacement is in 8.8
# FIXED POINT (0xC0 = 0.75 px per frame over 8 frames = 6 px) -- reading
# 0xC0 as pixels flings the mon nearly two hundred px off the field.
const _SKULL_BASH_STEP := 0xC0 / 256.0
const _SKULL_BASH_FRAMES := 8


static func _skull_bash_position(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var node := _battler_node(vm, AnimStage.ANIM_ATTACKER)
	if node == null:
		return
	var scale := _scale(vm)
	var mon := MonOffset.new(node)
	var back: bool = vm.args[0] == 0
	var dir: float = -1.0 if _is_player_side(vm) else 1.0
	var st := {"t": 0, "x": node.position.x - mon.base.x}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		var t: int = int(st["t"]) + 1
		st["t"] = t
		if back:
			st["x"] = float(st["x"]) + _SKULL_BASH_STEP * dir * scale
		else:
			st["x"] = float(st["x"]) - _SKULL_BASH_STEP * dir * scale
		mon.apply(Vector2(float(st["x"]), 0.0))
		if t >= _SKULL_BASH_FRAMES:
			if not back:
				mon.apply(Vector2.ZERO)
			return true
		return false)


# AnimTask_MoveHeatWaveTargets (battle_anim_fire.c). No args.
#
# It shoves EVERY visible battler on the target's side, not just the target,
# and the direction follows the ATTACKER's side so the whole opposing team is
# blown away from the source. The 2 px alternating jitter rides on top of a
# steady push.
const _HEAT_WAVE_PUSH := 2.0
const _HEAT_WAVE_JITTER := 2.0
const _HEAT_WAVE_FRAMES := 32


static func _move_heat_wave_targets(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var nodes: Array[Control] = []
	var mons: Array = []
	for battler in [AnimStage.ANIM_TARGET, AnimStage.ANIM_DEF_PARTNER]:
		var n := _battler_node(vm, battler)
		if n != null and n.visible:
			nodes.append(n)
			mons.append(MonOffset.new(n))
	if nodes.is_empty():
		return
	var scale := _scale(vm)
	var dir: float = 1.0 if _is_player_side(vm) else -1.0
	var st := {"t": 0, "push": 0.0, "flip": 0, "sub": 0}
	vm.add_stepper(func() -> bool:
		var t: int = int(st["t"]) + 1
		st["t"] = t
		st["push"] = float(st["push"]) + _HEAT_WAVE_PUSH * dir
		st["sub"] = int(st["sub"]) + 1
		var jitter := 0.0
		if int(st["sub"]) >= 2:
			st["sub"] = 0
			st["flip"] = int(st["flip"]) + 1
		jitter = _HEAT_WAVE_JITTER if (int(st["flip"]) & 1) == 1 \
				else -_HEAT_WAVE_JITTER
		for m in mons:
			(m as MonOffset).apply(
					Vector2((float(st["push"]) + jitter) * scale, 0.0))
		if t >= _HEAT_WAVE_FRAMES:
			for m in mons:
				(m as MonOffset).apply(Vector2.ZERO)
			return true
		return false)


# AnimTask_GetStockpileCounter (battle_anim_effects_3.c). No args.
#
# ⚠ STUB WITH ITS CONSUMER NAMED, per the standing rule. It answers on arg 7
# with `gAnimDisableStructPtr->stockpileCounter`, and this port's anim layer
# has no disable-struct surface at all -- `BattlePokemon.stockpile_count`
# exists on the battle side but nothing threads it into the VM. Reporting 0
# makes Spit Up and Swallow pick their weakest branch, which is wrong but
# BOUNDED; inventing a value would be worse. The fix is one field on
# AnimScriptVM plus a write at the dispatch site.
static func _get_stockpile_counter(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	vm.args[ARG_RET_ID] = 0


# ══ [M36D batch 34] ═══════════════════════════════════════════════════════
#
# The multi-phase SPAWNERS batch 33 deferred: tasks whose step machines
# create their own sprites over several states rather than being handed one
# by the script's `createsprite`. They share no code with each other; what
# they share is that the task, not the script, decides how many sprites
# exist and where each one goes.
#
# STILL DEFERRED, with reasons:
#   * `AnimTask_LeafBlade` -- a nine-state machine that re-aims a slash
#     sprite between states while driving the target's own affine table. It
#     is genuinely a batch on its own.
#   * `AnimTask_AirCutterProjectile` and `AnimTask_EruptionLaunchRocks` --
#     both build per-sprite coordinate tables through helpers
#     (`InitEruptionLaunchRockCoordData`, the contest-mirrored arg rewrite)
#     that need their own porting pass to avoid guessing.
#   * `InitPoisonGasCloudAnim` -- a sprite callback, not a task; it belongs
#     with the SpriteCB tail rather than here.


# AnimTask_TormentAttacker (battle_anim_effects_3.c:5100) + TormentAttacker_Step.
# No args.
#
# SIX thought bubbles, alternating right/left of the attacker, converging
# inward and climbing as they go. The offsets start at (+-32, -20) and BOTH
# shrink by 6 after every ODD-indexed bubble -- so bubbles pair up: two at
# 32/-20, two at 26/-26, two at 20/-32.
#
# The cadence is not uniform. Between bubbles the attacker runs a 12-frame
# affine wobble, and after the FIRST TWO bubbles only there is an extra
# 10-frame hold (`data[1] <= 2` is tested AFTER the increment, so it is true
# for bubbles 0 and 1 and false from bubble 2 on). Torment therefore opens
# slowly and then rattles off the last four.
const _TORMENT_BUBBLES := 6
const _TORMENT_X := 32.0
const _TORMENT_Y := -20.0
const _TORMENT_SHRINK := 6.0
const _TORMENT_AFFINE := [[-12, 8, 0, 4], [20, -20, 0, 4], [-8, 12, 0, 4]]
const _TORMENT_HOLD := 10
const _TORMENT_SLOW_BUBBLES := 2
const _TORMENT_TAIL := 8


# The frame each bubble is spawned on, derived from the step machine above.
static func _torment_spawn_frames() -> Array:
	var out: Array = []
	var t := 0
	for i in range(_TORMENT_BUBBLES):
		out.append(t)
		t += 12  # the affine wobble, 4+4+4
		if i < _TORMENT_SLOW_BUBBLES:
			t += _TORMENT_HOLD
	return out


# Offsets for bubble `i`: sign alternates, magnitude shrinks after odd ones.
static func _torment_offset(i: int) -> Vector2:
	var shrink := float((i / 2) * int(_TORMENT_SHRINK))
	var x := _TORMENT_X - shrink
	var y := _TORMENT_Y + shrink * -1.0
	return Vector2(x if (i & 1) == 0 else -x, y)


static func _torment_attacker(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var at := _battler_centre(vm, AnimStage.ANIM_ATTACKER)
	var scale := _scale(vm)
	var frames := _torment_spawn_frames()
	var last: int = int(frames[frames.size() - 1])
	var cmds: Array = []
	for i in range(_TORMENT_BUBBLES):
		for c in _TORMENT_AFFINE:
			cmds.append(c)
		if i < _TORMENT_SLOW_BUBBLES:
			cmds.append([0, 0, 0, _TORMENT_HOLD])
	_run_affine_cmds(vm, _battler_node(vm, AnimStage.ANIM_ATTACKER), cmds,
			Callable(), AnimStage.ANIM_ATTACKER)
	var st := {"t": 0, "i": 0}
	vm.add_stepper(func() -> bool:
		var t: int = int(st["t"])
		var i: int = int(st["i"])
		if i < frames.size() and t == int(frames[i]):
			var node := _make_sprite_named(vm, "gThoughtBubbleSpriteTemplate",
					vm.blend_context())
			if node != null:
				node.centre = at + _torment_offset(i) * scale
				node.flip_h = (i & 1) == 1
				_play_until_anim_ends(vm, node, _ANIM_END_CAP)
			st["i"] = i + 1
		st["t"] = t + 1
		return t >= last + _TORMENT_TAIL)


# AnimTask_BarrageBall (battle_anim_effects_2.c) + AnimTask_BarrageBall_Step.
# No args.
#
# An arcing ball from the attacker to the target, then SIXTEEN invisibility
# toggles at one toggle per two frames -- the ball does not fade or shrink,
# it strobes out. The arc's landing point is BELOW the target's centre by a
# quarter of the target's height (BATTLER_COORD_ATTR_HEIGHT / 4), because
# Barrage bounces the egg off the mon's body rather than its face.
const _BARRAGE_DURATION := 16
const _BARRAGE_ARC := -32.0
const _BARRAGE_BLINKS := 16
const _BARRAGE_BLINK_EVERY := 2
const _BARRAGE_LAND_FRACTION := 0.25


static func _barrage_ball(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var node := _make_sprite_named(vm, "gBarrageBallSpriteTemplate",
			vm.blend_context())
	if node == null:
		return
	var scale := _scale(vm)
	var start := _battler_centre(vm, AnimStage.ANIM_ATTACKER)
	var finish_pos := _battler_centre(vm, AnimStage.ANIM_TARGET)
	var tgt := _battler_node(vm, AnimStage.ANIM_TARGET)
	if tgt != null:
		finish_pos.y += tgt.size.y * tgt.scale.y * _BARRAGE_LAND_FRACTION
	node.centre = start
	var st := {"t": 0, "blink": 0, "landed": false}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		var t: int = int(st["t"]) + 1
		st["t"] = t
		if not bool(st["landed"]):
			if t >= _BARRAGE_DURATION:
				st["landed"] = true
				st["t"] = 0
				node.centre = finish_pos
				return false
			var f := float(t) / float(_BARRAGE_DURATION)
			var pos := start.lerp(finish_pos, f)
			pos.y += _gba_sin(f * 128.0, _BARRAGE_ARC * scale)
			node.centre = pos
			return false
		if t % _BARRAGE_BLINK_EVERY != 0:
			return false
		st["blink"] = int(st["blink"]) + 1
		node.visible = (int(st["blink"]) & 1) == 0
		if int(st["blink"]) >= _BARRAGE_BLINKS:
			node.finish()
			return true
		return false)


# AnimTask_WaterSport (battle_anim_water.c) + AnimTask_WaterSport_Step +
# CreateWaterSportDroplet. No args.
#
# Droplets leave the ATTACKER every OTHER frame (`if (++data[2] > 1)`) and
# arc toward a landing point that SWEEPS across the field: the sweep step is
# `data[7] * 6` per frame where data[7] is +1 on the player side and -1 on
# the opponent's, so the spray always fans away from the user. The sweep
# reverses when it leaves the -16..256 band, and after THREE reversals the
# task stops spawning and waits for the survivors.
const _WATER_SPORT_EVERY := 2
const _WATER_SPORT_SWEEP := 6.0
const _WATER_SPORT_ARC := -32.0
const _WATER_SPORT_DURATION := 16
const _WATER_SPORT_LEAD := 8.0
const _WATER_SPORT_REVERSALS := 3
const _WATER_SPORT_LO := -16.0
const _WATER_SPORT_HI := 256.0


static func _water_sport(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var scale := _scale(vm)
	var origin := _battler_centre(vm, AnimStage.ANIM_ATTACKER)
	var dir: float = 1.0 if _is_player_side(vm) else -1.0
	# GBA-space sweep cursor, so the -16..256 band is the real screen band.
	var st := {"sweep": (origin.x / scale) + dir * _WATER_SPORT_LEAD,
			"step": dir, "sub": 0, "turns": 0}
	vm.add_stepper(func() -> bool:
		st["sub"] = int(st["sub"]) + 1
		if int(st["sub"]) >= _WATER_SPORT_EVERY:
			st["sub"] = 0
			var node := _make_sprite_named(vm, "gSmallWaterOrbSpriteTemplate",
					vm.blend_context())
			if node != null:
				node.centre = origin
				var land := Vector2(float(st["sweep"]) * scale,
						origin.y - dir * _WATER_SPORT_LEAD * scale)
				_arc_travel(vm, node, origin, land, _WATER_SPORT_DURATION,
						_WATER_SPORT_ARC * scale)
		st["sweep"] = float(st["sweep"]) + float(st["step"]) * _WATER_SPORT_SWEEP
		if float(st["sweep"]) < _WATER_SPORT_LO \
				or float(st["sweep"]) > _WATER_SPORT_HI:
			st["step"] = -float(st["step"])
			st["turns"] = int(st["turns"]) + 1
			if int(st["turns"]) > _WATER_SPORT_REVERSALS:
				return true
		return false)


# AnimTask_BrineRain (battle_anim_water.c). No args.
#
# Rain over the TARGET, and the band it falls through is side-dependent:
# an attacker on the PLAYER's side rains from y=0 down to y=40, an attacker
# on the opponent's rains from y=40 to y=90. That is not cosmetic -- the
# opponent's mon sits higher on screen, so the shorter, lower band keeps the
# drops on the mon instead of above it. Ten drops, spread +-40 px in x
# around the target's centre.
const _BRINE_DROPS := 10
const _BRINE_X_RANGE := 40.0
const _BRINE_EVERY := 4
const _BRINE_FALL_SPEED := 4.0
const _BRINE_PLAYER_BAND := Vector2(0.0, 40.0)
const _BRINE_FOE_BAND := Vector2(40.0, 90.0)


static func _brine_rain(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var scale := _scale(vm)
	var centre := _battler_centre(vm, AnimStage.ANIM_TARGET)
	var band: Vector2 = _BRINE_PLAYER_BAND if _is_player_side(vm) \
			else _BRINE_FOE_BAND
	var st := {"t": 0, "made": 0}
	vm.add_stepper(func() -> bool:
		var t: int = int(st["t"])
		st["t"] = t + 1
		if t % _BRINE_EVERY != 0:
			return int(st["made"]) >= _BRINE_DROPS
		var node := _make_sprite_named(vm, "gSmallWaterOrbSpriteTemplate",
				vm.blend_context())
		st["made"] = int(st["made"]) + 1
		if node != null:
			var x := centre.x + randf_range(-_BRINE_X_RANGE, _BRINE_X_RANGE) * scale
			var top := band.x * scale
			var bottom := band.y * scale
			node.centre = Vector2(x, top)
			var fall := {"y": top}
			vm.add_stepper(func() -> bool:
				if not is_instance_valid(node):
					return true
				node.advance_frame()
				fall["y"] = float(fall["y"]) + _BRINE_FALL_SPEED * scale
				node.centre = Vector2(x, float(fall["y"]))
				if float(fall["y"]) >= bottom:
					var splat := _make_sprite_named(vm,
							"gWaterHitSplatSpriteTemplate", vm.blend_context())
					if splat != null:
						splat.centre = Vector2(x, bottom)
						_play_until_anim_ends(vm, splat, _ANIM_END_CAP)
					node.finish()
					return true
				return false)
		return int(st["made"]) >= _BRINE_DROPS)


# AnimTask_CreateIons (battle_anim_electric.c). args: 0 unused, 1 spawn
# interval in frames, 2 total duration in frames.
#
# Ions appear at RANDOM screen positions rather than being anchored to a
# battler -- and only in the TOP HALF (`Random2() % (DISPLAY_HEIGHT / 2)`),
# because Ion Deluge charges the sky, not the ground. The spawn test is
# `data[0] % interval == 1` after the increment, so the first ion lands on
# frame 1, not frame 0.
const _ION_DISPLAY_WIDTH := 240.0
const _ION_DISPLAY_HEIGHT := 160.0


static func _create_ions(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var interval: int = maxi(1, vm.args[1])
	var duration: int = maxi(1, vm.args[2])
	var scale := _scale(vm)
	var st := {"t": 0}
	vm.add_stepper(func() -> bool:
		st["t"] = int(st["t"]) + 1
		var t: int = int(st["t"])
		if t % interval == 1 % interval:
			var node := _make_sprite_named(vm, "gIonSpriteTemplate",
					vm.blend_context())
			if node != null:
				node.centre = Vector2(
						randf_range(0.0, _ION_DISPLAY_WIDTH) * scale,
						randf_range(0.0, _ION_DISPLAY_HEIGHT * 0.5) * scale)
				_play_until_anim_ends(vm, node, _ANIM_END_CAP)
		return t >= duration)


# AnimTask_SmokescreenImpact (battle_anim_effects_3.c:1285). No args.
#
# A one-shot impact burst on the TARGET, offset (+8, +8) from the target's
# coordinate pair -- down-right, not centred. The task destroys itself the
# same frame it fires, so the burst outlives the task that made it.
const _SMOKESCREEN_OFFSET := Vector2(8.0, 8.0)


static func _smokescreen_impact(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var node := _make_sprite_named(vm, "gBlackSmokeSpriteTemplate",
			vm.blend_context())
	if node == null:
		return
	node.centre = _battler_centre(vm, AnimStage.ANIM_TARGET) \
			+ _SMOKESCREEN_OFFSET * _scale(vm)
	_play_until_anim_ends(vm, node, _ANIM_END_CAP)


# AnimTask_OdorSleuthMovement (battle_anim_effects_3.c:5160) +
# MoveOdorSleuthClone. No args.
#
# Two blended clones of the TARGET orbiting horizontally in OPPOSITE
# directions (phase steps +16 and -16) starting 180 degrees apart (phases 0
# and 128) with a 24 px radius -- so they are always mirror images of each
# other, one at +x when the other is at -x.
#
# WHICH of those two facts carries the mirror: the 180-DEGREE OFFSET, not the
# opposite step directions. Only x is drawn (`Cos(phase, radius)`), and
# cos(t+128) == -cos(t) whichever way the phases walk, so stepping both the
# same way would look IDENTICAL here. The opposite signs are ported because
# source has them, but nothing in this port can observe them -- do not read a
# passing mirror test as evidence the directions are right.
#
# THE DEAD STORE: upstream sets `x2 += 24` / `x2 -= 24` on the two clones at
# init, then MoveOdorSleuthClone overwrites x2 with `Cos(phase, radius)` on
# its very first frame. Porting those two lines as a persistent offset would
# double the separation. They are invisible upstream only because Cos(0,24)
# and Cos(128,24) happen to equal exactly +24 and -24.
#
# The flicker is the other half of the effect: each clone toggles visibility
# every two frames, and they start in opposite states, so exactly ONE clone
# is on screen at a time. After 60 frames the radius shrinks by 2 per frame
# until it goes negative and both are destroyed.
const _ODOR_RADIUS := 24.0
const _ODOR_PHASE_STEP := 16.0
const _ODOR_HOLD := 60
const _ODOR_SHRINK := 2.0
const _ODOR_FLICKER_EVERY := 2


static func _odor_sleuth_movement(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var node := _battler_node(vm, AnimStage.ANIM_TARGET)
	var layer: Control = null
	if vm.stage != null and vm.stage.has_method("layer"):
		layer = vm.stage.layer()
	if node == null or layer == null:
		return
	var a := _clone_battler_visual(node, layer)
	var b := _clone_battler_visual(node, layer)
	if a == null or b == null:
		if a != null:
			a.queue_free()
		if b != null:
			b.queue_free()
		return
	var scale := _scale(vm)
	var home := node.position
	a.visible = true
	b.visible = false
	var st := {"t": 0, "pa": 0.0, "pb": 128.0, "r": _ODOR_RADIUS,
			"phase": 0, "flick": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(a) or not is_instance_valid(b):
			return true
		st["flick"] = int(st["flick"]) + 1
		if int(st["flick"]) >= _ODOR_FLICKER_EVERY:
			st["flick"] = 0
			a.visible = not a.visible
			b.visible = not b.visible
		var r := float(st["r"])
		st["pa"] = fmod(float(st["pa"]) + _ODOR_PHASE_STEP, 256.0)
		st["pb"] = fmod(float(st["pb"]) - _ODOR_PHASE_STEP + 256.0, 256.0)
		a.position = home + Vector2(_gba_cos(float(st["pa"]), r) * scale, 0.0)
		b.position = home + Vector2(_gba_cos(float(st["pb"]), r) * scale, 0.0)
		st["t"] = int(st["t"]) + 1
		if int(st["phase"]) == 0:
			if int(st["t"]) >= _ODOR_HOLD:
				st["phase"] = 1
			return false
		st["r"] = r - _ODOR_SHRINK
		if float(st["r"]) < 0.0:
			a.queue_free()
			b.queue_free()
			return true
		return false)


# AnimTask_CycleMagicalLeafPal (battle_anim_effects_1.c). No args.
#
# A rainbow ramp over the leaf sprites: SEVEN colours, and for each one the
# blend strength walks 0..16 one step per frame before snapping to 0 and
# moving to the next colour. That is 17 frames per colour, 119 total -- the
# leaves do not cross-fade between colours, they fade IN to each one and
# then cut.
#
# PORT NOTE: upstream reaches two specific palette slots (ANIM_TAG_LEAF and
# ANIM_TAG_RAZOR_LEAF). This port has no palette indirection, so the ramp is
# applied to every live anim sprite -- during Magical Leaf those are exactly
# the leaves.
const _MAGICAL_LEAF_COLORS := [
	Color(1.0, 0.0, 0.0),          # RGB_RED
	Color(1.0, 0.613, 0.0),        # RGB(31, 19, 0)
	Color(1.0, 1.0, 0.0),          # RGB_YELLOW
	Color(0.0, 1.0, 0.0),          # RGB_GREEN
	Color(0.161, 0.452, 1.0),      # RGB(5, 14, 31)
	Color(0.710, 0.323, 1.0),      # RGB(22, 10, 31)
	Color(0.710, 0.677, 1.0),      # RGB(22, 21, 31)
]
const _MAGICAL_LEAF_STEPS := 17


static func _cycle_magical_leaf_pal(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var layer: Control = null
	if vm.stage != null and vm.stage.has_method("layer"):
		layer = vm.stage.layer()
	if layer == null:
		return
	var total: int = _MAGICAL_LEAF_COLORS.size() * _MAGICAL_LEAF_STEPS
	var st := {"t": 0}
	vm.add_stepper(func() -> bool:
		var t: int = int(st["t"])
		st["t"] = t + 1
		var colour: Color = _MAGICAL_LEAF_COLORS[
				(t / _MAGICAL_LEAF_STEPS) % _MAGICAL_LEAF_COLORS.size()]
		var amount := float(t % _MAGICAL_LEAF_STEPS) / 16.0
		for child in layer.get_children():
			var s := child as AnimSprite
			if s == null:
				continue
			if t + 1 >= total:
				_clear_blend(s)
			else:
				_apply_blend_amount(s, colour, amount)
		return t + 1 >= total)


# ══ [M36D batch 35] ═══════════════════════════════════════════════════════
#
# Pairs and near-pairs: behaviors whose sibling is already ported, or whose
# twin ships alongside it here. The recurring finding is that a shared name
# or a shared script does NOT imply a shared mechanism -- three of the five
# pairs below diverge somewhere that matters.


# AnimThrowMistBall (battle_anim_ice.c:1146). args: as
# TranslateAnimSpriteToTargetMonLocation.
#
# It IS that behavior, with one difference that is easy to miss and changes
# every throw: it OVERWRITES the sprite's position with the attacker's own
# coordinates BEFORE delegating, so args 0/1 -- the spawn offset every other
# user of that callback honours -- are discarded. The ball always leaves from
# the attacker's centre.
static func _throw_mist_ball(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var start := _battler_centre(vm, AnimStage.ANIM_ATTACKER)
	var finish_pos := _battler_centre(vm, AnimStage.ANIM_TARGET) \
			+ Vector2(float(vm.args[2]) * _facing(vm), float(vm.args[3])) * scale
	node.centre = start
	_linear_travel(vm, node, start, finish_pos, maxi(1, vm.args[4]))


# AnimSkyDropBallUp (battle_anim_new.c:7281). args: 0/1 spawn offset,
# 2 hold frames, 3 acceleration (8.8).
#
# `AnimFlyBallUp`'s twin, sharing its exact step function -- but it spawns on
# the TARGET while still hiding the ATTACKER. Sky Drop carries the target up,
# so the ball marks where the victim was and the user is the one that
# vanishes. Porting it as "Fly, but for the target" would hide the wrong mon.
static func _sky_drop_ball_up(vm: AnimScriptVM, ctx: Dictionary) -> void:
	_fly_ball_up_from(vm, ctx, AnimStage.ANIM_TARGET)


# The shared body. `_fly_ball_up` keeps its own entry point so batch 8's
# behavior and its tests are untouched.
static func _fly_ball_up_from(vm: AnimScriptVM, ctx: Dictionary,
		spawn_on: int) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var start := _positioned_centre(vm, spawn_on, vm.args[0], vm.args[1], scale)
	node.centre = start
	vm.set_battler_visible_tracked(AnimStage.ANIM_ATTACKER, false)
	var hold: int = maxi(0, vm.args[2])
	var accel: int = vm.args[3]
	var st := {"hold": hold, "vel": 0, "y": 0.0, "t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["t"] = int(st["t"]) + 1
		if int(st["hold"]) > 0:
			st["hold"] = int(st["hold"]) - 1
		else:
			st["vel"] = int(st["vel"]) + accel
			st["y"] = float(st["y"]) - float(int(st["vel"]) >> 8) * scale
			node.centre = start + Vector2(0.0, float(st["y"]))
		if node.centre.y < -32.0 * scale or int(st["t"]) >= _ANIM_END_CAP:
			node.finish()
			return true
		return false)


# AnimWillOWispOrb (battle_anim_fire.c:1157). args: 0/1 spawn offset,
# 2 frame-sequence variant.
#
# Drifts sideways AWAY from the attacker's own side (+4 px/frame for an
# opponent-side user, -4 for a player-side one) while its phase accumulator
# runs, so the wisps fan outward before the fire lands.
const _WISP_ORB_DRIFT := 4.0
const _WISP_ORB_PHASE_STEP := 192
const _WISP_ORB_FRAMES := 40


static func _will_o_wisp_orb(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var start := _positioned_centre(vm, AnimStage.ANIM_ATTACKER, vm.args[0],
			vm.args[1], scale)
	node.centre = start
	_apply_anim_variant(node, ctx, vm.args[2])
	# Sign is keyed on the ATTACKER's own side, not on the direction of
	# travel toward the target -- the orbs spread away from their source.
	var drift: float = -_WISP_ORB_DRIFT if _is_player_side(vm) \
			else _WISP_ORB_DRIFT
	var st := {"t": 0, "phase": 0, "x": 0.0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["phase"] = int(st["phase"]) + _WISP_ORB_PHASE_STEP
		st["x"] = float(st["x"]) + drift * scale
		node.centre = start + Vector2(float(st["x"]),
				_gba_sin(float(int(st["phase"]) >> 8), 8.0 * scale))
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) >= _WISP_ORB_FRAMES:
			node.finish()
			return true
		return false)


# AnimWillOWispFire (battle_anim_fire.c:1245). args: 0 starting phase.
#
# THE ELLIPSE GROWS. Both amplitudes are accumulators, not constants
# (`data[3] += 0xC0 * 2`, `data[4] += 0xA0`, each read as `>> 8`), so the
# flame spirals OUTWARD from the target rather than circling it at a fixed
# radius -- and it grows faster horizontally than vertically (0x180/frame vs
# 0xA0), so the spiral flattens as it widens. A fixed-radius port looks
# like a completely different move.
const _WISP_FIRE_DX := 0xC0 * 2
const _WISP_FIRE_DY := 0xA0
const _WISP_FIRE_PHASE_STEP := 7
const _WISP_FIRE_FRAMES := 60


static func _will_o_wisp_fire(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	# DISCLOSED: source additionally re-centres the spiral between both
	# targets, but only when the battle is doubles AND the move's own target
	# type is TARGET_BOTH. This port has no move-target information at the
	# behavior layer, so applying `_side_centre` unconditionally would move
	# the flame off a single target in every singles battle -- worse than
	# omitting the doubles case. Centred on the target itself.
	var centre := _battler_centre(vm, AnimStage.ANIM_TARGET)
	node.centre = centre
	var st := {"t": 0, "phase": vm.args[0] & 0xFF, "ax": 0, "ay": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["ax"] = int(st["ax"]) + _WISP_FIRE_DX
		st["ay"] = int(st["ay"]) + _WISP_FIRE_DY
		node.centre = centre + Vector2(
				_gba_sin(float(st["phase"]), float(int(st["ax"]) >> 8) * scale),
				_gba_cos(float(st["phase"]), float(int(st["ay"]) >> 8) * scale))
		st["phase"] = (int(st["phase"]) + _WISP_FIRE_PHASE_STEP) & 0xFF
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) >= _WISP_FIRE_FRAMES:
			node.finish()
			return true
		return false)


# AnimAquaTail (battle_anim_water.c:571). args: 0/1 offset, 2 which battler,
# 3 affine variant. A one-shot deformation that lives exactly as long as its
# own affine table, spawned on either battler per arg 2.
static func _aqua_tail(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var battler: int = AnimStage.ANIM_ATTACKER if vm.args[2] == 0 \
			else AnimStage.ANIM_TARGET
	node.centre = _positioned_centre(vm, battler, vm.args[0], vm.args[1],
			_scale(vm))
	_play_until_anim_ends(vm, node, _ANIM_END_CAP)


# AnimKnockOffAquaTail (battle_anim_water.c:585, step :607). args: 0 x delta,
# 1 y delta.
#
# THE SIDE BRANCH IS NOT A MIRROR. Against a PLAYER-side target the x delta is
# SUBTRACTED and the orbit runs BACKWARDS (phase step -11); against an
# opponent-side one the same delta is ADDED and the orbit runs forwards (+11).
# The y delta is added either way -- it is NOT mirrored, unlike x. Reading
# this as a plain sign flip on both axes puts the tail on the wrong side of
# the mon in one of the two cases.
const _KNOCK_OFF_TAIL_RADIUS := 20.0
const _KNOCK_OFF_TAIL_STEP := 11
const _KNOCK_OFF_TAIL_START_PHASE := 192
const _KNOCK_OFF_TAIL_FRAMES := 40


static func _knock_off_aqua_tail(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	# The target's own side, not the attacker's.
	var target_is_player: bool = not _is_player_side(vm)
	var dx: float = -float(vm.args[0]) if target_is_player \
			else float(vm.args[0])
	var step: int = -_KNOCK_OFF_TAIL_STEP if target_is_player \
			else _KNOCK_OFF_TAIL_STEP
	var base := _battler_centre(vm, AnimStage.ANIM_TARGET) \
			+ Vector2(dx, float(vm.args[1])) * scale
	var st := {"t": 0, "phase": _KNOCK_OFF_TAIL_START_PHASE}
	node.centre = base
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["phase"] = (int(st["phase"]) + step) & 0xFF
		node.centre = base + Vector2(
				_gba_cos(float(st["phase"]), _KNOCK_OFF_TAIL_RADIUS * scale),
				_gba_sin(float(st["phase"]), _KNOCK_OFF_TAIL_RADIUS * scale))
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) >= _KNOCK_OFF_TAIL_FRAMES:
			node.finish()
			return true
		return false)


# AnimateZenHeadbutt (battle_anim_effects_1.c). args: 0 which battler.
#
# Positions on the chosen battler with a FIXED +18 y offset -- a constant in
# the code, not an argument, and not side-mirrored -- then lives exactly as
# long as its own affine table.
const _ZEN_HEADBUTT_Y := 18.0


static func _animate_zen_headbutt(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var battler: int = AnimStage.ANIM_ATTACKER if vm.args[0] == 0 \
			else AnimStage.ANIM_TARGET
	node.centre = _battler_centre(vm, battler) \
			+ Vector2(0.0, _ZEN_HEADBUTT_Y * _scale(vm))
	_play_until_anim_ends(vm, node, _ANIM_END_CAP)


# AnimPresent (battle_anim_effects_1.c). Args are UNUSED -- source says so in
# its own comment. Arcs from the attacker to a point 10 px BELOW the target's
# centre (the box lands at the feet, not the face).
const _PRESENT_DURATION := 60
const _PRESENT_ARC := -30.0
const _PRESENT_DROP := 10.0


static func _present(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var start := _battler_centre(vm, AnimStage.ANIM_ATTACKER)
	var finish_pos := _battler_centre(vm, AnimStage.ANIM_TARGET) \
			+ Vector2(0.0, _PRESENT_DROP * scale)
	node.centre = start
	_arc_travel(vm, node, start, finish_pos, _PRESENT_DURATION,
			_PRESENT_ARC * scale)


# AnimPresentHealParticle (battle_anim_effects_1.c). args: 0/1 offset,
# 2 y velocity. A plain LINEAR drift -- `y2 = velocity * age`, no easing and
# no sine anywhere -- from the target, living until its own frames end.
static func _present_heal_particle(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var start := _positioned_centre(vm, AnimStage.ANIM_TARGET, vm.args[0],
			vm.args[1], scale)
	node.centre = start
	var vel := float(vm.args[2])
	var st := {"t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["t"] = int(st["t"]) + 1
		node.centre = start + Vector2(0.0, vel * float(st["t"]) * scale)
		if int(st["t"]) >= _ANIM_END_CAP:
			node.finish()
			return true
		return false)


# SpriteCB_TwinkleOnBattler (battle_anim_new.c). args: 2 battler selector.
#
# Copies the chosen battler's position INCLUDING its live x2/y2 displacement,
# so a twinkle placed on a mon that is mid-shake rides the shake. Read once at
# spawn, not tracked per frame -- source assigns and then hands off.
static func _twinkle_on_battler(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var who: int = AnimStage.ANIM_TARGET if vm.args[2] == AnimStage.ANIM_TARGET \
			else AnimStage.ANIM_ATTACKER
	node.centre = _battler_centre(vm, who)
	_play_until_anim_ends(vm, node, _ANIM_END_CAP)



# ══ [M36D batch 36] ═══════════════════════════════════════════════════════
#
# The one-away tail. By this point the blocker graph has almost no sharing
# left -- 43 of the 93 blocked moves need exactly one behavior, and they are
# 43 DIFFERENT behaviors -- so this batch is chosen for readability rather
# than yield, and its per-move gain is ~1 apiece by construction.
#
# What DOES still share: five of these are `InitAnimArcTranslation` plus an
# arc step, differing only in where the destination comes from. That
# difference is the whole port, and it is not cosmetic -- see below.


# The shared body for the arc family. `finish_pos` is supplied by the caller
# precisely because that is where they diverge.
static func _arc_to_point(vm: AnimScriptVM, node: AnimSprite, start: Vector2,
		finish_pos: Vector2, duration: int, amplitude: float) -> void:
	node.centre = start
	_arc_travel(vm, node, start, finish_pos, maxi(1, duration), amplitude)


# SpriteCB_SurgingStrikes (battle_anim_new.c). args: 0/1 spawn offset,
# 2/3 destination offset from the TARGET, 4 duration, 5 wave amplitude.
static func _surging_strikes(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	_arc_to_point(vm, node,
			_positioned_centre(vm, AnimStage.ANIM_TARGET, vm.args[0],
					vm.args[1], scale),
			_battler_centre(vm, AnimStage.ANIM_TARGET)
					+ Vector2(float(vm.args[2]), float(vm.args[3])) * scale,
			vm.args[4], -float(vm.args[5]) * scale)


# SpriteCB_MoongeistCharge (battle_anim_new.c). args: 0/1 spawn offset,
# 2/3 destination offset, 4 duration, 5 wave amplitude.
#
# THE DESTINATION IS THE ATTACKER'S OWN POSITION, not the target's. Both
# `data[2]` and `data[4]` are computed from `gBattleAnimAttacker` -- this is a
# CHARGE, so the particles converge on the user before the beam fires. Every
# other member of this arc family aims at the target, which makes "arc to the
# target" the natural and wrong reading.
static func _moongeist_charge(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var atk := _battler_centre(vm, AnimStage.ANIM_ATTACKER)
	_arc_to_point(vm, node,
			atk + Vector2(float(vm.args[0]), float(vm.args[1])) * scale,
			atk + Vector2(float(vm.args[2]), float(vm.args[3])) * scale,
			vm.args[4], -float(vm.args[5]) * scale)


# SpriteCB_PowerShiftBall (battle_anim_new.c). args: 0/1 spawn offset,
# 2/3 destination offset from the ATTACKER, 4 duration, 5 wave amplitude.
#
# Also a self-arc (Power Shift swaps the user's own stats), and the ONLY
# member of the family that side-mirrors its destination: args[2] is negated
# for an opponent-side user. args[3] is not.
static func _power_shift_ball(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var atk := _battler_centre(vm, AnimStage.ANIM_ATTACKER)
	var dx := float(vm.args[2])
	if not _is_player_side(vm):
		dx = -dx
	_arc_to_point(vm, node,
			_positioned_centre(vm, AnimStage.ANIM_ATTACKER, vm.args[0],
					vm.args[1], scale),
			atk + Vector2(dx, float(vm.args[3])) * scale,
			vm.args[4], -float(vm.args[5]) * scale)


# SpriteCB_TripleArrowKick (battle_anim_new.c). args: 0/1 spawn offset,
# 2 duration, 3 wave amplitude.
#
# Shares PowerShiftBall's own step function -- source says so in a comment --
# but aims at the TARGET's exact centre with no destination offset at all,
# and forces frame sequence 1 (the feet, not the arrows).
const _TRIPLE_ARROW_FEET_VARIANT := 1


static func _triple_arrow_kick(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	_apply_anim_variant(node, ctx, _TRIPLE_ARROW_FEET_VARIANT)
	_arc_to_point(vm, node,
			_positioned_centre(vm, AnimStage.ANIM_TARGET, vm.args[0],
					vm.args[1], scale),
			_battler_centre(vm, AnimStage.ANIM_TARGET),
			vm.args[2], -float(vm.args[3]) * scale)


# SpriteCB_GlacialLance (battle_anim_new.c). args: 0/1 spawn offset,
# 2/3 destination offset, 4/5 unused here, 6 duration.
#
# Spawns on the ATTACKER and converges on the target -- or, in a doubles
# battle against the opposing side, on the MIDPOINT of both targets, since
# the lance is thrown at the whole side. An ally-targeting use falls back to
# the single target.
static func _glacial_lance(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var dest := _side_centre(vm, AnimStage.ANIM_TARGET,
			AnimStage.ANIM_DEF_PARTNER)
	_arc_to_point(vm, node,
			_positioned_centre(vm, AnimStage.ANIM_ATTACKER, vm.args[0],
					vm.args[1], scale),
			dest + Vector2(float(vm.args[2]), float(vm.args[3])) * scale,
			vm.args[6], -float(vm.args[5]) * scale)


# SpriteCB_MoveSpriteUpwardsForDuration (battle_anim_new.c). args: 0 battler,
# 1/2 offset, 3 speed, 4 duration. A plain constant-velocity rise -- no arc,
# no sine.
static func _move_sprite_upwards_for_duration(vm: AnimScriptVM,
		ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var who: int = AnimStage.ANIM_ATTACKER if vm.args[0] == AnimStage.ANIM_ATTACKER \
			else AnimStage.ANIM_TARGET
	var start := _battler_centre(vm, who) \
			+ Vector2(float(vm.args[1]), float(vm.args[2])) * scale
	node.centre = start
	var speed := float(vm.args[3])
	var duration: int = maxi(1, vm.args[4])
	var st := {"t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["t"] = int(st["t"]) + 1
		node.centre = start + Vector2(0.0, -speed * float(st["t"]) * scale)
		if int(st["t"]) >= duration:
			node.finish()
			return true
		return false)


# SpriteCB_SearingShotRock (battle_anim_new.c). args: 0/1 offset,
# 2 frame variant, 3 duration, 4 battler selector.
#
# DESTROYS ITSELF OUTRIGHT if its selected battler has no visible sprite,
# rather than drawing at a stale position -- the same guard batch 22's
# `_anim_sprite_on_selected_mon_pos` carries.
static func _searing_shot_rock(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var who := _anim_battler_from_arg(vm, 4)
	if not _battler_visible(vm, who):
		node.finish()
		return
	node.centre = _positioned_centre(vm, who, vm.args[0], vm.args[1],
			_scale(vm))
	_apply_anim_variant(node, ctx, vm.args[2])
	var duration: int = maxi(1, vm.args[3])
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


# AnimEllipticalGustAttacker (battle_anim_flying.c). No args.
#
# A FLAT ellipse on the ATTACKER, 20 px below its centre: amplitudes 32 in x
# and only 8 in y, so it reads as a horizontal swirl rather than a circle.
# Starts at phase 191 and steps +5, running exactly 71 frames.
const _ELLIPTICAL_GUST_X := 32.0
const _ELLIPTICAL_GUST_Y := 8.0
const _ELLIPTICAL_GUST_DROP := 20.0
const _ELLIPTICAL_GUST_START := 191
const _ELLIPTICAL_GUST_STEP := 5
const _ELLIPTICAL_GUST_FRAMES := 71


static func _elliptical_gust_attacker(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var base := _battler_centre(vm, AnimStage.ANIM_ATTACKER) \
			+ Vector2(0.0, _ELLIPTICAL_GUST_DROP * scale)
	var st := {"t": 0, "phase": _ELLIPTICAL_GUST_START}
	# Source calls its own step immediately, so frame 0 is already displaced.
	node.centre = base + Vector2(
			_gba_sin(float(st["phase"]), _ELLIPTICAL_GUST_X * scale),
			_gba_cos(float(st["phase"]), _ELLIPTICAL_GUST_Y * scale))
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		node.centre = base + Vector2(
				_gba_sin(float(st["phase"]), _ELLIPTICAL_GUST_X * scale),
				_gba_cos(float(st["phase"]), _ELLIPTICAL_GUST_Y * scale))
		st["phase"] = (int(st["phase"]) + _ELLIPTICAL_GUST_STEP) & 0xFF
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) >= _ELLIPTICAL_GUST_FRAMES:
			node.finish()
			return true
		return false)


# AnimSmellingSaltExclamation (battle_anim_effects_3.c). args: 0 battler,
# 1 duration.
#
# Sits above its battler's own TOP edge, not its centre -- and is CLAMPED so
# it can never rise above y = 8, because a tall Pokemon would otherwise push
# the exclamation mark off the top of the screen.
const _SMELLING_SALT_MIN_Y := 8.0


static func _smelling_salt_exclamation(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var who: int = AnimStage.ANIM_ATTACKER if vm.args[0] == AnimStage.ANIM_ATTACKER \
			else AnimStage.ANIM_TARGET
	var mon := _battler_node(vm, who)
	var centre := _battler_centre(vm, who)
	var top: float = centre.y
	if mon != null:
		top = centre.y - mon.size.y * mon.scale.y * 0.5
	node.centre = Vector2(centre.x,
			maxf(top, _SMELLING_SALT_MIN_Y * scale))
	_play_until_anim_ends(vm, node, maxi(1, vm.args[1]))


# AnimLavaPlumeOrbitScatter (battle_anim_fire.c). args: 0 launch phase.
#
# Constant velocity, NOT an orbit despite the name: the phase is sampled ONCE
# to pick a direction (`Sin(phase, 10)`, `Cos(phase, 7)`) and then never
# advances, so each ember flies straight out on its own fixed heading. The
# ellipse is in the SPREAD of headings, not in any one ember's path.
const _LAVA_PLUME_X := 10.0
const _LAVA_PLUME_Y := 7.0


static func _lava_plume_orbit_scatter(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var start := _battler_centre(vm, AnimStage.ANIM_ATTACKER)
	var vel := Vector2(
			_gba_sin(float(vm.args[0]), _LAVA_PLUME_X),
			_gba_cos(float(vm.args[0]), _LAVA_PLUME_Y)) * scale
	node.centre = start
	var st := {"t": 0, "p": start}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["p"] = (st["p"] as Vector2) + vel
		node.centre = st["p"] as Vector2
		st["t"] = int(st["t"]) + 1
		# Upstream frees it once it leaves the screen box.
		var p: Vector2 = st["p"]
		if p.x > 272.0 * scale or p.y > 160.0 * scale or p.y < -16.0 * scale \
				or int(st["t"]) >= _ANIM_END_CAP:
			node.finish()
			return true
		return false)


# AnimTask_TechnoBlast (battle_anim_new.c). No args.
#
# ⚠️ ANSWERS ON ARG 0, not ARG_RET -- rule (12). Upstream writes the Drive
# item's own secondary id so the script can branch to the matching elemental
# form. This project has no Drive items at all, so it answers 0 (the Normal
# form), which is also upstream's own no-Drive branch. Structurally correct
# rather than stubbed: when Drives exist, only the lookup changes.
static func _techno_blast(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	vm.args[0] = 0


# AnimTask_ShellSideArm (battle_anim_new.c). No args.
#
# ⚠️ ALSO ANSWERS ON ARG 0. Reports whether the move swapped to the physical
# category. `gBattleStruct->swapDamageCategory` has no equivalent here, so it
# answers FALSE -- the special form. Disclosed: a Shell Side Arm that really
# did swap will play the wrong one of its two animations until the engine
# exposes the flag.
static func _shell_side_arm(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	vm.args[0] = 0


# ══ [M36D batch 37] ═══════════════════════════════════════════════════════
#
# The Rapid Spin family, deferred since batch 27 as "per-scanline DMA".
#
# ⚠️ THAT DEFERRAL WAS HALF WRONG, and it had been inherited unchecked across
# five batches. `AnimRapidSpin` is a PLAIN SPRITE BEHAVIOR -- it never touches
# a scanline register, and needed no new surface at all. Only
# `AnimTask_RapinSpinMonElevation` is the scanline effect. The two were
# recorded together because the same five moves need both, which is not the
# same thing as sharing a mechanism. Rule (6)'s family: a stated reason
# outlives the reading that produced it.


# AnimRapidSpin (battle_anim_effects_3.c). args: 0 battler, 1 x offset,
# 2 starting y offset, 3 y threshold to end on, 4 phase step, 5 y velocity.
#
# Oscillates horizontally off `gSineTable[phase] >> 4` -- the raw table read
# shifted, so the amplitude is 256 >> 4 = 16 px, NOT the args-supplied value
# every other sine user in this port takes. Meanwhile y drifts at a constant
# velocity, and the sprite dies when y2 CROSSES args[3].
#
# The crossing direction is decided ONCE at spawn (`data[0] = y2 > args[3]`),
# so the same behavior serves both a rising and a falling spin depending on
# which side of the threshold it starts. Testing only one direction would
# miss half of it.
const _RAPID_SPIN_AMPLITUDE := 16.0
const _RAPID_SPIN_CAP := 240


static func _rapid_spin(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var who: int = AnimStage.ANIM_ATTACKER if vm.args[0] == 0 \
			else AnimStage.ANIM_TARGET
	var base := _battler_centre(vm, who) \
			+ Vector2(float(vm.args[1]), 0.0) * scale
	var threshold := float(vm.args[3])
	var step: int = vm.args[4]
	var vel := float(vm.args[5])
	# Captured at spawn, exactly as source does.
	var falling: bool = float(vm.args[2]) > threshold
	var st := {"phase": 0, "y": float(vm.args[2]), "t": 0}
	node.centre = base + Vector2(0.0, float(st["y"]) * scale)
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["phase"] = (int(st["phase"]) + step) & 0xFF
		st["y"] = float(st["y"]) + vel
		node.centre = base + Vector2(
				_gba_sin(float(st["phase"]), _RAPID_SPIN_AMPLITUDE) * scale,
				float(st["y"]) * scale)
		st["t"] = int(st["t"]) + 1
		var done: bool = float(st["y"]) < threshold if falling \
				else float(st["y"]) > threshold
		if done or int(st["t"]) >= _RAPID_SPIN_CAP:
			node.finish()
			return true
		return false)


# AnimTask_RapinSpinMonElevation (battle_anim_effects_3.c). args: 0 battler,
# 1 sweep speed, 2 whether to tear the effect down at the end.
#
# (The name's typo -- "Rapin" -- is upstream's. Kept verbatim: it is the
# registry key the extracted scripts actually reference.)
#
# THE SCANLINE EFFECT, and the first behavior in this port to use one. What
# the hardware does: point a DMA at REG_BG1HOFS/REG_BG2HOFS and feed it a
# per-scanline buffer, so the background's horizontal scroll VARIES BY ROW.
# `AnimStage.set_background_band` expresses exactly that as a u-offset that is
# a function of v -- the mechanism itself, not an approximation of it.
#
# The motion: a band spanning the mon (y-33 to y+36) whose TOP and BOTTOM
# edges both sweep upward at `args[1]` px/frame, the bottom edge starting 8
# frames later. Inside the swept region the background's offset ALTERNATES
# every two frames between its own scroll and that scroll plus a full
# DISPLAY_WIDTH.
#
# ⚠️ +240 ON A 256 px BACKGROUND IS NOT A SCREEN-WIDTH JUMP -- it wraps to
# -16. The visible effect is a 16 px horizontal SHIMMER, and porting the
# literal 240 without the wrap would displace the whole band nearly a screen
# and look like a tearing bug rather than a spin.
const _SPIN_ELEV_ABOVE := 33.0
const _SPIN_ELEV_BELOW := 36.0
const _SPIN_ELEV_BOTTOM_DELAY := 8
const _SPIN_ELEV_FLICKER_EVERY := 2
const _SPIN_ELEV_BG_WIDTH := 256.0
const _SPIN_ELEV_SHIFT := 240.0
const _SPIN_ELEV_CAP := 240


static func _rapid_spin_mon_elevation(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	if vm.stage == null or not vm.stage.has_method("set_background_band"):
		return
	var scale := _scale(vm)
	var who: int = AnimStage.ANIM_ATTACKER if vm.args[0] == 0 \
			else AnimStage.ANIM_TARGET
	var centre_y: float = _battler_centre(vm, who).y
	var top_limit: float = maxf(0.0, centre_y - _SPIN_ELEV_ABOVE * scale)
	var speed: float = maxf(1.0, float(vm.args[1])) * scale
	# The wrap: +240 on a 256-wide background is -16, a shimmer.
	var shift: float = fposmod(_SPIN_ELEV_SHIFT, _SPIN_ELEV_BG_WIDTH) * scale
	if shift > _SPIN_ELEV_BG_WIDTH * scale * 0.5:
		shift -= _SPIN_ELEV_BG_WIDTH * scale
	var st := {
		"top": centre_y + _SPIN_ELEV_BELOW * scale,
		"bottom": centre_y + _SPIN_ELEV_BELOW * scale,
		"delay": _SPIN_ELEV_BOTTOM_DELAY,
		"sub": 0, "on": false, "t": 0,
	}
	vm.add_stepper(func() -> bool:
		st["top"] = maxf(float(st["top"]) - speed, top_limit)
		var finished := false
		if int(st["delay"]) > 0:
			st["delay"] = int(st["delay"]) - 1
		else:
			st["bottom"] = maxf(float(st["bottom"]) - speed, top_limit)
			if is_equal_approx(float(st["bottom"]), top_limit):
				finished = true
		st["sub"] = int(st["sub"]) + 1
		if int(st["sub"]) >= _SPIN_ELEV_FLICKER_EVERY:
			st["sub"] = 0
			st["on"] = not bool(st["on"])
		vm.stage.set_background_band(float(st["top"]), float(st["bottom"]),
				shift if bool(st["on"]) else 0.0)
		st["t"] = int(st["t"]) + 1
		if finished or int(st["t"]) >= _SPIN_ELEV_CAP:
			# DISCLOSED DIVERGENCE: source only tears the scanline effect down
			# when args[2] asks (`gScanlineEffect.state = 3`), leaving it
			# installed otherwise for a following script step to reuse. This
			# port ALWAYS clears the band -- a displaced strip of background
			# left on screen after the move is the same leak class rule (3)
			# exists for, and no script in this port's corpus relies on the
			# carry-over. args[2] is therefore deliberately UNREAD -- stated
			# here rather than left as a silently ignored argument.
			vm.stage.clear_background_band()
			return true
		return false)


# ══ [M36D batch 38] ═══════════════════════════════════════════════════════
#
# Three behaviors whose NAMES each promise something the code qualifies.
#
# STILL DEFERRED, and for a read-it-properly reason rather than a hard one:
# `AnimTask_LeafBlade`, `AnimTask_AirCutterProjectile`,
# `AnimTask_EruptionLaunchRocks` and `InitPoisonGasCloudAnim` are all
# multi-state spawners whose step machines were not read in full this batch.
# Rule (4): defer rather than guess. They are portable and remain the largest
# readable block left.


# AnimTask_VoltSwitch (battle_anim_new.c) + VoltSwitch_Step.
#
# ⚠️ NOT A TASK. Its signature is `void AnimTask_VoltSwitch(struct Sprite *)`
# -- a SPRITE callback wearing a task's name. Registered under the name the
# extracted scripts actually reference, but do not reach for `add_stepper`
# expecting a task's argument conventions.
#
# THE RETURN TRIP IS THE MOVE. It arcs to the target, then immediately arcs
# BACK to the attacker over a fixed 0x14 = 20 frames -- Volt Switch is the
# move where the user leaves, and a one-way port drops its whole signature.
#
# The side branches do DIFFERENT work, not mirrored work: an opponent-side
# user negates args[2], while a player-side user instead nudges the spawn
# 10 px DOWN. Neither branch does the other's job.
const _VOLT_SWITCH_RETURN_FRAMES := 20
const _VOLT_SWITCH_PLAYER_DROP := 10.0


static func _volt_switch(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	var player := _is_player_side(vm)
	var start := _positioned_centre(vm, AnimStage.ANIM_ATTACKER, vm.args[0],
			vm.args[1], scale)
	if player:
		start.y += _VOLT_SWITCH_PLAYER_DROP * scale
	var dx := float(vm.args[2])
	if not player:
		dx = -dx
	var apex := _battler_centre(vm, AnimStage.ANIM_TARGET) \
			+ Vector2(dx, float(vm.args[3])) * scale
	var home := _battler_centre(vm, AnimStage.ANIM_ATTACKER)
	var amp := -float(vm.args[5]) * scale
	node.centre = start
	_arc_travel(vm, node, start, apex, maxi(1, vm.args[4]), amp)
	# The return leg, queued behind the outbound one. `_arc_travel` finishes
	# its own node, so the second leg gets a fresh sprite at the apex.
	var st := {"t": 0}
	vm.add_stepper(func() -> bool:
		st["t"] = int(st["t"]) + 1
		if int(st["t"]) < maxi(1, vm.args[4]):
			return false
		var back := _make_sprite(vm, ctx)
		if back != null:
			back.centre = apex
			_arc_travel(vm, back, apex, home, _VOLT_SWITCH_RETURN_FRAMES, amp)
		return true)


# AnimSuperpowerRock (battle_anim_effects_2.c) + its two steps. args:
# 0 spawn x, 1 rise speed (8.8), 2 frame variant, 3 rise frames.
#
# TWO PHASES WITH DIFFERENT FIXED-POINT SCALES, which is the detail to get
# right: the rise accumulates in 8.8 (`>> 8`), the flight in 4.4 (`>> 4`).
# Using one scale for both makes the second phase 16x too fast or the first
# 16x too slow.
#
# The rock starts at y = 120 -- SCREEN BOTTOM, not the attacker -- rises for
# `args[3]` frames, and only THEN takes its heading, which is the raw
# attacker-to-target delta applied per frame. So the flight time is set by
# how far apart the battlers are, and is not an argument at all.
const _SUPERPOWER_ROCK_START_Y := 120.0
const _SUPERPOWER_ROCK_CAP := 180


static func _superpower_rock(vm: AnimScriptVM, ctx: Dictionary) -> void:
	var node := _make_sprite(vm, ctx)
	if node == null:
		return
	var scale := _scale(vm)
	_apply_anim_variant(node, ctx, vm.args[2])
	var x := float(vm.args[0]) * scale
	var start_y := _SUPERPOWER_ROCK_START_Y * scale
	node.centre = Vector2(x, start_y)
	var rise: int = maxi(0, vm.args[3])
	var rise_speed: int = vm.args[1]
	var atk := _battler_centre(vm, AnimStage.ANIM_ATTACKER)
	var tgt := _battler_centre(vm, AnimStage.ANIM_TARGET)
	var st := {
		"phase": 0, "left": rise, "y88": int(start_y) << 8,
		"p": Vector2.ZERO, "v": Vector2.ZERO, "t": 0,
	}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		node.advance_frame()
		st["t"] = int(st["t"]) + 1
		if int(st["phase"]) == 0:
			if int(st["left"]) > 0:
				st["y88"] = int(st["y88"]) - rise_speed
				node.centre = Vector2(x, float(int(st["y88"]) >> 8))
				st["left"] = int(st["left"]) - 1
				if node.centre.y < -8.0 * scale:
					node.finish()
					return true
			else:
				# The heading is taken ONCE, here, from the live battler gap.
				st["phase"] = 1
				st["v"] = tgt - atk
				st["p"] = node.centre * 16.0
		else:
			st["p"] = (st["p"] as Vector2) + (st["v"] as Vector2)
			var pos: Vector2 = (st["p"] as Vector2) / 16.0
			node.centre = pos
			if pos.x + 8.0 * scale > 256.0 * scale or pos.y < -8.0 * scale \
					or pos.y > 120.0 * scale:
				node.finish()
				return true
		if int(st["t"]) >= _SUPERPOWER_ROCK_CAP:
			node.finish()
			return true
		return false)


# SlideMonToOffsetAndBack (battle_anim_mon_movement.c:659). args: 0 battler,
# 1 x offset, 2 y offset, 3 mirror-y flag, 4 duration, 5 return flag.
#
# ⚠️ THE NAME OVER-PROMISES. "AndBack" happens ONLY when args[5] is nonzero
# -- source stores `DestroyAnimSprite` as the completion callback otherwise,
# leaving the mon exactly where it was slid to. A port that always returned
# would be reading the name rather than the code, and would cancel the
# displacement half its callers want.
#
# The sprite itself is INVISIBLE: it is a controller that drags the battler,
# so this goes through the VM's tracked mon offset (rule (3)) -- an aborted
# run must not leave the Pokemon parked off its mark.
#
# The y mirror is CONDITIONAL on args[3], while the x mirror is not: an
# opponent-side battler always negates args[1], but only negates args[2] when
# args[3] == 1.
static func _slide_mon_to_offset_and_back(vm: AnimScriptVM,
		_ctx: Dictionary) -> void:
	var who: int = AnimStage.ANIM_ATTACKER if vm.args[0] == 0 \
			else AnimStage.ANIM_TARGET
	var node := _battler_node(vm, who)
	if node == null:
		return
	var scale := _scale(vm)
	# Keyed on the moved battler's OWN side, not the attacker's.
	var battler_is_player: bool = _is_player_side(vm) \
			if who == AnimStage.ANIM_ATTACKER else not _is_player_side(vm)
	var dx := float(vm.args[1])
	var dy := float(vm.args[2])
	if not battler_is_player:
		dx = -dx
		if vm.args[3] == 1:
			dy = -dy
	var target := Vector2(dx, dy) * scale
	var duration: int = maxi(1, vm.args[4])
	var comes_back: bool = vm.args[5] != 0
	var mon := MonOffset.new(node)
	var st := {"t": 0}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		st["t"] = int(st["t"]) + 1
		var f: float = minf(1.0, float(st["t"]) / float(duration))
		mon.apply(target * f)
		if int(st["t"]) < duration:
			return false
		if comes_back:
			mon.apply(Vector2.ZERO)
		return true)


# ══ [M36D batch 39] ═══════════════════════════════════════════════════════
#
# One spawner, read end to end. Batch 38 deferred four of these behind a
# generic "step machine unread"; this closes the one that could be read in
# full and REPLACES that note with a per-behavior account of what each of the
# other three actually needs, so a later session does not re-derive it:
#
#   * `AnimTask_AirCutterProjectile` -- computes its per-frame step by FIXED-
#     POINT DIVISION (`MathUtil_Mul16(xDiff, MathUtil_Inv16(...))`), packs the
#     travel DIRECTION into `data[8]`'s low bit, and packs a subpriority into
#     `args[4]`'s high bit (`& 0x80`, then `- 64`). Porting it needs those
#     three encodings understood, not just its motion.
#   * `InitPoisonGasCloudAnim` -- a THREE-phase machine: linear travel with a
#     `>> 4` sine wobble, then a re-anchor on the target with a wider `>> 3`
#     sine plus a `(cos * -3) >> 8` vertical term AND per-frame OAM priority
#     flipping as it orbits, then a third phase.
#   * `AnimTask_LeafBlade` -- nine states that re-aim a slash between them
#     while driving the target's own affine table.


# AnimTask_EruptionLaunchRocks (battle_anim_fire.c) + its step, plus
# CreateEruptionLaunchRocks / GetEruptionLaunchRockInitialYPos /
# InitEruptionLaunchRockCoordData / UpdateEruptionLaunchRockPos. No args.
#
# TWO INDEPENDENT HALVES that a "spawner" framing hides. The task first
# SQUASHES THE ATTACKER -- an affine ramp from (0x100, 0x100) to (0xE0, 0x200)
# over 32 frames -- while jittering it +-3 px horizontally every other frame.
# Under the INVERTED GBA affine rule that is a WIDEN-AND-FLATTEN: y 0x100 ->
# 0x200 is half height, x 0x100 -> 0xE0 is ~1.14x width. The mon crouches
# before it erupts. Only then do the rocks fly.
#
# THE ROCKS ARE A FIXED SEVEN ON A FIXED TABLE, not a random spray:
# {-2,-5} {-1,-1} {3,-6} {4,-2} {2,-8} {-5,-5} {4,-7}, with x mirrored by the
# attacker's side. Every y is negative -- they all launch UPWARD -- and the
# arc comes entirely from the gravity term below.
#
# ⚠️ GRAVITY IS QUADRATIC AND SUB-PIXEL. Every third frame a stage counter
# increments and `stage * stage` is added to the 8x-fixed-point y. So the fall
# accelerates, and for the first several frames it adds less than one whole
# pixel -- porting it as a per-frame constant gives a flat lob instead of a
# real eruption.
const _ERUPTION_SPEEDS := [
	[-2, -5], [-1, -1], [3, -6], [4, -2], [2, -8], [-5, -5], [4, -7],
]
const _ERUPTION_SQUASH_FRAMES := 32
const _ERUPTION_SQUASH_TO := Vector2(0xE0, 0x200)
const _ERUPTION_JITTER := 3.0
const _ERUPTION_JITTER_EVERY := 2
const _ERUPTION_GRAVITY_EVERY := 3
const _ERUPTION_SPAWN_DX_PLAYER := -12.0
const _ERUPTION_SPAWN_DX_FOE := 16.0
const _ERUPTION_SPAWN_DY_PLAYER := 74.0
const _ERUPTION_SPAWN_DY_FOE := 44.0
const _ERUPTION_CAP := 240


# The stage's own drawable extent, for behaviors whose source frees a sprite
# once it leaves the 240x160 screen. Scaling those literals by `pixel_scale`
# is wrong on a stage whose aspect differs from the GBA's.
static func _layer_extent(vm: AnimScriptVM) -> Vector2:
	if vm.stage != null and vm.stage.has_method("layer"):
		var l: Control = vm.stage.layer()
		if l != null and is_instance_valid(l) and l.size.x > 0.0:
			return l.size
	return Vector2(240.0, 160.0) * _scale(vm)


static func _eruption_launch_rocks(vm: AnimScriptVM, _ctx: Dictionary) -> void:
	var node := _battler_node(vm, AnimStage.ANIM_ATTACKER)
	if node == null:
		return
	var scale := _scale(vm)
	var player := _is_player_side(vm)
	var deform := MonScale.new(node)
	var mon := MonOffset.new(node)

	# Half one: the crouch. Ramps to the squash over 32 frames while jittering.
	var st := {"t": 0, "flip": 0, "spawned": false}
	vm.add_stepper(func() -> bool:
		if not is_instance_valid(node):
			return true
		var t: int = int(st["t"]) + 1
		st["t"] = t
		var f: float = minf(1.0, float(t) / float(_ERUPTION_SQUASH_FRAMES))
		# GBA affine is INVERTED -- a larger value is a SMALLER sprite.
		var ax: float = lerpf(_GBA_AFFINE_IDENTITY, _ERUPTION_SQUASH_TO.x, f)
		var ay: float = lerpf(_GBA_AFFINE_IDENTITY, _ERUPTION_SQUASH_TO.y, f)
		deform.apply(Vector2(_GBA_AFFINE_IDENTITY / maxf(1.0, ax),
				_GBA_AFFINE_IDENTITY / maxf(1.0, ay)))
		if t % _ERUPTION_JITTER_EVERY == 0:
			st["flip"] = int(st["flip"]) + 1
			mon.apply(Vector2(_ERUPTION_JITTER * scale
					* (1.0 if (int(st["flip"]) & 1) == 1 else -1.0), 0.0))
		if t < _ERUPTION_SQUASH_FRAMES:
			return false
		# Half two: the rocks, launched once the crouch completes.
		if not bool(st["spawned"]):
			st["spawned"] = true
			_launch_eruption_rocks(vm, node, player, scale)
		deform.restore()
		mon.apply(Vector2.ZERO)
		return true)


static func _launch_eruption_rocks(vm: AnimScriptVM, mon_node: Control,
		player: bool, scale: float) -> void:
	var centre := mon_node.position + mon_node.size * mon_node.scale * 0.5
	# ⚠️ SOURCE MEASURES FROM THE SPRITE'S TOP EDGE, not its centre and not
	# its feet: `sprite->y + y2 + centerToCornerVecY` IS the top-left corner,
	# and the +74 / +44 is added to that. Measuring from the bottom puts the
	# rocks a full sprite-height too low, which on this stage is far enough
	# to spawn them past the floor and kill them on frame one -- which is
	# exactly what the first cut did.
	var top_edge: float = centre.y - mon_node.size.y * mon_node.scale.y * 0.5
	var origin := Vector2(
			centre.x + (_ERUPTION_SPAWN_DX_PLAYER if player
					else _ERUPTION_SPAWN_DX_FOE) * scale,
			top_edge + (_ERUPTION_SPAWN_DY_PLAYER if player
					else _ERUPTION_SPAWN_DY_FOE) * scale)
	var sign: float = 1.0 if player else -1.0
	for i in range(_ERUPTION_SPEEDS.size()):
		var rock := _make_sprite_named(vm, "gEruptionLaunchRockSpriteTemplate",
				vm.blend_context())
		if rock == null:
			continue
		rock.centre = origin
		var vx: float = float(_ERUPTION_SPEEDS[i][0]) * sign
		var vy: float = float(_ERUPTION_SPEEDS[i][1])
		# 8x fixed point, exactly as source: position is `<< 3`, and the
		# gravity term is added in those same eighth-pixel units.
		var st := {"x8": origin.x * 8.0, "y8": origin.y * 8.0,
				"delay": 0, "stage": 0, "t": 0}
		vm.add_stepper(func() -> bool:
			if not is_instance_valid(rock):
				return true
			rock.advance_frame()
			st["delay"] = int(st["delay"]) + 1
			if int(st["delay"]) > _ERUPTION_GRAVITY_EVERY - 1:
				st["delay"] = 0
				st["stage"] = int(st["stage"]) + 1
				# QUADRATIC, and sub-pixel for the first several frames.
				st["y8"] = float(st["y8"]) \
						+ float(int(st["stage"]) * int(st["stage"])) * scale
			st["x8"] = float(st["x8"]) + vx * 8.0 * scale
			st["y8"] = float(st["y8"]) + vy * 8.0 * scale
			rock.centre = Vector2(float(st["x8"]) / 8.0, float(st["y8"]) / 8.0)
			st["t"] = int(st["t"]) + 1
			# ⚠️ BOUNDS AGAINST THE REAL LAYER, not scaled GBA constants.
			# Source's 240x160 screen maps onto this stage at DIFFERENT
			# horizontal and vertical ratios, so `120 * pixel_scale` is not
			# the floor here -- it lands well above it. Using the layer's own
			# extents keeps "left the screen" meaning what it says.
			var bounds: Vector2 = _layer_extent(vm)
			if rock.centre.x < -8.0 * scale \
					or rock.centre.x > bounds.x + 8.0 * scale \
					or rock.centre.y < -8.0 * scale \
					or rock.centre.y > bounds.y + 8.0 * scale \
					or int(st["t"]) >= _ERUPTION_CAP:
				rock.finish()
				return true
			return false)
